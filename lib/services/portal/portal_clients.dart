part of 'portal_database.dart';

/// The lawyer's clients and what is kept for them (lib/services/clients/
/// client.dart), in the portal's database: one person's devices keep them
/// alike through Senkron's agenda part.
extension PortalClients on PortalDatabase {
  static const _tables = '''
    CREATE TABLE IF NOT EXISTS client (
      id TEXT PRIMARY KEY, json TEXT NOT NULL, updated TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS client_record (
      id TEXT PRIMARY KEY, client_id TEXT NOT NULL, kind TEXT NOT NULL,
      json TEXT NOT NULL, updated TEXT NOT NULL,
      locked INTEGER NOT NULL DEFAULT 0);
    CREATE INDEX IF NOT EXISTS client_record_client
      ON client_record(client_id);
    CREATE TABLE IF NOT EXISTS client_record_pending (
      id TEXT PRIMARY KEY, author TEXT NOT NULL, json TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS ledger_projection (
      id TEXT PRIMARY KEY, entry_id TEXT NOT NULL, client_id TEXT NOT NULL,
      json TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS ledger_projection_entry
      ON ledger_projection(entry_id);
    CREATE INDEX IF NOT EXISTS ledger_projection_client
      ON ledger_projection(client_id);
    CREATE TABLE IF NOT EXISTS ledger_legacy (
      id TEXT PRIMARY KEY, entry_id TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS ledger_repair (
      entry_id TEXT PRIMARY KEY, json TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS ledger_history (
      id TEXT PRIMARY KEY, entry_id TEXT NOT NULL, json TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS clients_revision (n INTEGER NOT NULL);
    INSERT INTO clients_revision SELECT 0
      WHERE NOT EXISTS (SELECT 1 FROM clients_revision);
    CREATE TRIGGER IF NOT EXISTS client_written AFTER INSERT ON client
      BEGIN UPDATE clients_revision SET n = n + 1; END;
    CREATE TRIGGER IF NOT EXISTS client_removed AFTER DELETE ON client
      BEGIN UPDATE clients_revision SET n = n + 1; END;
    CREATE TRIGGER IF NOT EXISTS representation_written
      AFTER INSERT ON case_representation
      BEGIN UPDATE clients_revision SET n = n + 1; END;
    CREATE TRIGGER IF NOT EXISTS party_written AFTER INSERT ON case_party
      BEGIN UPDATE clients_revision SET n = n + 1; END;
    CREATE TRIGGER IF NOT EXISTS party_removed AFTER DELETE ON case_party
      BEGIN UPDATE clients_revision SET n = n + 1; END;
  ''';

  /// Counted up at every client card written or removed, and every word
  /// of whom the lawyer acts for: what was made of the clients stands
  /// while it stays the same (the search's index).
  int get clientsRevision =>
      _db.select('SELECT n FROM clients_revision').first.columnAt(0) as int;

  void saveClient(Client c) {
    _putClient(c);
    PortalDatabase.changed?.call();
  }

  void _putClient(Client c) => _db.execute(
    'INSERT OR REPLACE INTO client(id, json, updated) VALUES(?,?,?)',
    [c.id, c.encode(), c.updated.toIso8601String()],
  );

  /// Every client card, the removed among them.
  List<Client> clientCards() => [
    for (final r in _db.select('SELECT json FROM client'))
      ?Client.fromJson(jsonDecode(r['json'] as String)),
  ];

  Client? clientCard(String id) {
    final rows = _db.select('SELECT json FROM client WHERE id=?', [id]);
    return rows.isEmpty
        ? null
        : Client.fromJson(jsonDecode(rows.first['json'] as String));
  }

  /// Keeps [r]; false when the one kept is locked: signed minutes are not
  /// written over.
  bool saveClientRecord(ClientRecord r) {
    // A ledger's movements are made of it, never written (R3).
    if (LedgerBook.isProjected(r) || _isProjectionId(r.id)) return false;
    // Nor taken back or set off by hand, nor booked as an older Folio did.
    if (_actsOnLedger(r)) return false;
    final kept = clientRecord(r.id);
    if (kept != null && kept.locked) return false;
    // Money in or out is evidence: never changed once written.
    if ((r.kind == ClientRecordKind.movement ||
            r.kind == ClientRecordKind.cash) &&
        !r.locked) {
      r = r.copyWith(locked: true);
    }
    _putRecord(r);
    if (r.kind == ClientRecordKind.enforcement) rebuildLedger(r.id);
    _notifyChanged();
    return true;
  }

  /// Whether [r] is a movement acting on a ledger's own money: one that
  /// takes back or sets off a movement made of a ledger, or books a
  /// ledger's payment as an older Folio did (`kaynak: icra:…`).
  bool _actsOnLedger(ClientRecord r) {
    if (r.kind != ClientRecordKind.movement) return false;
    final source = r.text('kaynak');
    if (source.startsWith('icra:') || source.startsWith('mahsup:icra:')) {
      return true;
    }
    final link = _linkOf(r);
    if (link == null) return false;
    if (link.startsWith('icra:') || _isProjectionId(link)) return true;
    final target = clientRecord(link);
    return target != null && isOldLedgerMovement(target);
  }

  /// Whether [m] is a movement an older Folio wrote of a ledger, or a
  /// set-off of one: its ledger waits for its repair, or was mended and it
  /// moved aside; nothing new acts on it (R3).
  bool isOldLedgerMovement(ClientRecord m) {
    if (m.kind != ClientRecordKind.movement || LedgerBook.isProjected(m)) {
      return false;
    }
    final source = m.text('kaynak');
    if (source.startsWith('icra:')) return true;
    if (!source.startsWith('mahsup:')) return false;
    final held = clientRecord(source.substring('mahsup:'.length));
    return held != null &&
        !LedgerBook.isProjected(held) &&
        held.text('kaynak').startsWith('icra:');
  }

  bool _isProjectionId(String id) =>
      _db.select('SELECT 1 FROM ledger_projection WHERE id=?', [id]).isNotEmpty;

  /// [entryId]'s movements made anew of its record (docs/senkron-plan.md
  /// R3): what is held for the client and each set-off in effect; none
  /// while it waits for its repair.
  void rebuildLedger(String entryId) {
    _db.execute('DELETE FROM ledger_projection WHERE entry_id=?', [entryId]);
    if (ledgerRepairOf(entryId) != null) return;
    final rows = _db.select('SELECT json FROM client_record WHERE id=?', [
      entryId,
    ]);
    if (rows.isEmpty) return;
    final r = ClientRecord.fromJson(jsonDecode(rows.first['json'] as String));
    if (r == null || r.kind != ClientRecordKind.enforcement) return;
    // A record in its old form still has its old movements: they count
    // till the migration moves them aside, never beside a projection.
    if (!LedgerBook.isNewForm(r)) return;
    for (final m in LedgerBook.projectionOf(r)) {
      _db.execute(
        'INSERT OR REPLACE INTO ledger_projection(id, entry_id, client_id, '
        'json) VALUES(?,?,?,?)',
        [m.id, entryId, m.clientId, jsonEncode(m.toJson())],
      );
    }
  }

  /// A line of [entryId]'s history: who changed what of it, when, and
  /// from which device (R3, R5); seen only where the ledger is.
  void addLedgerHistory(String entryId, Map<String, Object?> line) {
    final id =
        'g${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '${Random.secure().nextInt(1 << 32).toRadixString(36)}';
    _db.execute(
      'INSERT INTO ledger_history(id, entry_id, json) VALUES(?,?,?)',
      [id, entryId, jsonEncode(line)],
    );
  }

  /// [entryId]'s history, the oldest first.
  List<Map<String, Object?>> ledgerHistory(String entryId) => [
    for (final r in _db.select(
      'SELECT json FROM ledger_history WHERE entry_id=? ORDER BY rowid',
      [entryId],
    ))
      if (jsonDecode(r['json'] as String) case final Map j)
        Map<String, Object?>.from(j),
  ];

  /// The movements of a ledger whose record is no longer here, gone.
  void _dropOrphanProjection() => _db.execute(
    'DELETE FROM ledger_projection WHERE entry_id NOT IN '
    '(SELECT id FROM client_record)',
  );

  /// What was kept of the ledgers no longer here: their movements, their
  /// history and their repair reports.
  void _dropLedgerLeftovers() {
    _dropOrphanProjection();
    for (final table in const ['ledger_history', 'ledger_repair']) {
      _db.execute(
        'DELETE FROM $table WHERE entry_id NOT IN (SELECT id FROM client_record)',
      );
    }
  }

  List<ClientRecord> _projection({
    String? where,
    List<Object?> args = const [],
  }) => [
    for (final r in _db.select(
      'SELECT json FROM ledger_projection${where == null ? '' : ' WHERE $where'}',
      args,
    ))
      ?ClientRecord.fromJson(jsonDecode(r['json'] as String)),
  ];

  /// What waits for the lawyer's word before a ledger's old movements
  /// become its projection (R3, migration), by the record.
  Map<String, Object?>? ledgerRepairOf(String entryId) {
    final rows = _db.select('SELECT json FROM ledger_repair WHERE entry_id=?', [
      entryId,
    ]);
    if (rows.isEmpty) return null;
    final j = jsonDecode(rows.first['json'] as String);
    return j is Map ? Map<String, Object?>.from(j) : null;
  }

  List<String> get ledgerRepairs => [
    for (final r in _db.select('SELECT entry_id FROM ledger_repair'))
      r['entry_id'] as String,
  ];

  /// Whether [r] is a movement not to be taken from another device: made
  /// of a ledger, or acting on a movement made of one, or one of the old
  /// movements a ledger's migration moved aside, or acting on one of them;
  /// or an older Folio's booking of a ledger that is in its new form here.
  /// An older Folio's booking of a ledger in its old form here is taken: the
  /// ledger is weighed with it ([_weighLedger]).
  bool _ledgerMade(ClientRecord r) {
    if (r.kind != ClientRecordKind.movement) return false;
    if (LedgerBook.isProjected(r)) return true;
    final source = r.text('kaynak');
    if (source.startsWith('mahsup:icra:')) return true;
    final link = _linkOf(r);
    if (link != null && (link.startsWith('icra:') || _isProjectionId(link))) {
      return true;
    }
    if (source.startsWith('icra:')) {
      final entry = clientRecord(source.substring('icra:'.length));
      if (entry != null && LedgerBook.isNewForm(entry)) return true;
    }
    final named = {
      r.id,
      if (r.text('ters').isNotEmpty) r.text('ters'),
      if (source.startsWith('mahsup:')) source.substring('mahsup:'.length),
    };
    return _db
        .select(
          'SELECT 1 FROM ledger_legacy WHERE id IN '
          '(${List.filled(named.length, '?').join(',')})',
          named.toList(),
        )
        .isNotEmpty;
  }

  /// The old movements moved aside, by their ledger: for another device to
  /// know them (R3), [entries] alone when given.
  List<Map<String, Object?>> _legacyMap({Set<String>? entries}) => [
    for (final r in _db.select('SELECT id, entry_id FROM ledger_legacy'))
      if (entries == null || entries.contains(r['entry_id']))
        {'id': r['id'], 'kayit': r['entry_id']},
  ];

  void _takeLegacyMap(Object? list) {
    for (final j in list is List ? list : const []) {
      if (j is! Map || j['id'] is! String || j['kayit'] is! String) continue;
      _db.execute(
        'INSERT OR IGNORE INTO ledger_legacy(id, entry_id) VALUES(?,?)',
        [j['id'], j['kayit']],
      );
    }
  }

  /// The old movements kept here that another device moved aside, moved
  /// aside here alike once their ledger is here in its new form: its
  /// projection counts in their place (R3). True when one was.
  bool _retireMapped() {
    var moved = false;
    for (final row in _db.select(
      'SELECT l.id, l.entry_id, c.json FROM ledger_legacy l '
      'JOIN client_record c ON c.id = l.id',
    )) {
      final e = clientRecord(row['entry_id'] as String);
      if (e == null ||
          e.kind != ClientRecordKind.enforcement ||
          !LedgerBook.isNewForm(e)) {
        continue;
      }
      _db.execute(
        'INSERT OR REPLACE INTO ledger_history(id, entry_id, json) '
        'VALUES(?,?,?)',
        [row['id'], row['entry_id'], row['json']],
      );
      _db.execute('DELETE FROM client_record WHERE id=?', [row['id']]);
      moved = true;
    }
    return moved;
  }

  /// For tests: [r] kept as an older Folio kept it, with no check.
  @visibleForTesting
  void putRecordForTesting(ClientRecord r) => _putRecord(r);

  void _putRecord(ClientRecord r) => _db.execute(
    'INSERT OR REPLACE INTO client_record(id, client_id, kind, json, '
    'updated, locked) VALUES(?,?,?,?,?,?)',
    [
      r.id,
      r.clientId,
      r.kind.code,
      jsonEncode(r.toJson()),
      r.updated.toIso8601String(),
      r.locked ? 1 : 0,
    ],
  );

  /// Every record kept, the removed among them, and the ledgers'
  /// movements made of them.
  List<ClientRecord> allClientRecords() => [
    for (final r in _db.select('SELECT json FROM client_record'))
      ?ClientRecord.fromJson(jsonDecode(r['json'] as String)),
    ..._projection(),
  ];

  ClientRecord? clientRecord(String id) {
    final rows = _db.select('SELECT json FROM client_record WHERE id=?', [id]);
    if (rows.isNotEmpty) {
      return ClientRecord.fromJson(jsonDecode(rows.first['json'] as String));
    }
    return _projection(where: 'id=?', args: [id]).firstOrNull;
  }

  /// [clientId]'s records, the newest first; none taken off. [also], the
  /// other cards of the same client's.
  List<ClientRecord> clientRecords(
    String clientId, {
    ClientRecordKind? kind,
    Iterable<String> also = const [],
  }) {
    final ids = {clientId, ...also}.toList();
    final out = [
      for (final r in _db.select(
        'SELECT json FROM client_record WHERE client_id IN '
        '(${List.filled(ids.length, '?').join(',')})'
        '${kind == null ? '' : ' AND kind=?'}',
        [...ids, ?kind?.code],
      ))
        ?ClientRecord.fromJson(jsonDecode(r['json'] as String)),
      if (kind == null || kind == ClientRecordKind.movement)
        ..._projection(
          where: 'client_id IN (${List.filled(ids.length, '?').join(',')})',
          args: ids,
        ),
    ]..removeWhere((r) => r.removed);
    return out..sort((a, b) => b.created.compareTo(a.created));
  }

  /// The money records others wrote, forgotten here: this person may no
  /// longer see them. Their own stay. Every [ClientRecordKind.financial]
  /// kind: the office's cash and bank and papers, and the enforcement
  /// files' accounts, as much as the fees and movements (R11).
  void forgetClientMoney({required String keepPerson}) {
    final kinds = ClientRecordKind.financialCodes.map((_) => '?').join(',');
    for (final r in _db.select(
      'SELECT id, json FROM client_record WHERE kind IN ($kinds)',
      ClientRecordKind.financialCodes,
    )) {
      final rec = ClientRecord.fromJson(jsonDecode(r['json'] as String));
      if (rec == null || rec.person == keepPerson) continue;
      _db.execute('DELETE FROM client_record WHERE id=?', [r['id']]);
      removedClientRecords.add(rec);
    }
    // What was kept of the ledgers gone, their history and repair reports
    // too, and the money others sent that waited (R11).
    _dropLedgerLeftovers();
    for (final r in _db.select('SELECT id, json FROM client_record_pending')) {
      final rec = ClientRecord.fromJson(jsonDecode(r['json'] as String));
      if (rec == null || (rec.kind.financial && rec.person != keepPerson)) {
        _db.execute('DELETE FROM client_record_pending WHERE id=?', [r['id']]);
      }
    }
  }

  /// The clients as the list shows them: each card, with the cases its
  /// names are the lawyer's in; then each party the lawyer acts for whom
  /// no card names yet. The lawyer's own word of whom they act for comes
  /// first, else UYAP's lawyer field (see [clientsOf]).
  List<ClientEntry> clientEntries({String? lawyer}) {
    final byName =
        <
          String,
          ({String name, List<({String caseKey, String role})> cases})
        >{};
    final parties = caseParties();
    final keys = {
      ...parties.keys,
      for (final r in _db.select('SELECT key FROM cases')) r['key'] as String,
      for (final r in _db.select('SELECT case_key FROM case_representation'))
        r['case_key'] as String,
    };
    for (final key in keys) {
      final said = representation(key);
      final ours = said.isNotEmpty
          ? said
          : [
              for (final t in parties[key] ?? const <UyapParty>[])
                if (vekilOlarakGeciyor(t.lawyer, lawyer))
                  (ad: t.name, rol: t.role),
            ];
      for (final t in ours) {
        final folded = UyapWebService.fold(t.ad);
        // A name UYAP shortened names no client: its whole one comes later.
        if (folded.isEmpty || isShortenedName(t.ad)) continue;
        final seen = byName.putIfAbsent(folded, () => (name: t.ad, cases: []));
        if (!seen.cases.any((c) => c.caseKey == key)) {
          seen.cases.add((caseKey: key, role: t.rol));
        }
      }
    }
    final out = <ClientEntry>[];
    final named = <String>{};
    // The cards of one client, a colleague's among them: the same TCKN or
    // VKN, else the same name. The oldest card is the one shown.
    final groups = <String, List<Client>>{};
    for (final c in clientCards()..sort((a, b) => a.id.compareTo(b.id))) {
      if (c.removed) {
        named.addAll(c.folded);
        continue;
      }
      final same = c.idNo.isNotEmpty
          ? 'kimlik:${c.idNo}'
          : 'ad:${UyapWebService.fold(c.name)}';
      (groups[same] ??= []).add(c);
    }
    for (final cards in groups.values) {
      final c = cards.first;
      final cases = <({String caseKey, String role})>[];
      for (final f in {for (final x in cards) ...x.folded}) {
        named.add(f);
        for (final x in byName[f]?.cases ?? const []) {
          if (!cases.any((y) => y.caseKey == x.caseKey)) cases.add(x);
        }
      }
      // The lawyer's own word on a case outweighs the names in it: the
      // latest said on any of the client's cards.
      final links = <String, CaseLink>{};
      for (final x in cards) {
        x.caseLinks.forEach((k, l) {
          if (links[k] == null || l.at.isAfter(links[k]!.at)) links[k] = l;
        });
      }
      final removedCases = <({String caseKey, String role})>[];
      final added = <String>{};
      for (final MapEntry(:key, value: l) in links.entries) {
        final found = cases.where((y) => y.caseKey == key).firstOrNull;
        if (l.state == CaseLink.removed) {
          cases.removeWhere((y) => y.caseKey == key);
          removedCases.add((caseKey: key, role: found?.role ?? l.role));
        } else if (l.state == CaseLink.added && found == null) {
          cases.add((caseKey: key, role: l.role));
          added.add(key);
        }
      }
      out.add(
        ClientEntry(
          key: c.id,
          name: c.name,
          client: c,
          cases: cases,
          ids: [
            for (final x in cards) ...[x.id, ...x.absorbed],
          ],
          removedCases: removedCases,
          addedCases: added,
        ),
      );
    }
    for (final e in byName.entries) {
      if (named.contains(e.key)) continue;
      out.add(
        ClientEntry(key: e.key, name: e.value.name, cases: e.value.cases),
      );
    }
    out.sort(
      (a, b) =>
          UyapWebService.fold(a.name).compareTo(UyapWebService.fold(b.name)),
    );
    return out;
  }

  /// The cards and records, for one of the person's own devices: all of
  /// them.
  /// The clients that may be [e] written another way: the same surname,
  /// and each other word of the shorter name the start of the longer's
  /// ("A. KARACA", "AYŞE KARACA"). A body's name is not guessed at.
  List<ClientEntry> clientLookalikes(ClientEntry e, List<ClientEntry> all) {
    List<String> words(String n) => [
      for (final w in UyapWebService.fold(n).split(RegExp(r'[\s.]+')))
        if (w.isNotEmpty) w,
    ];
    bool body(List<String> w) => w.any(
      (x) => const {'ltd', 'sti', 'as', 'a.s', 'sirketi', 'koop'}.contains(x),
    );
    final mine = words(e.name);
    if (mine.length < 2 || body(mine) || (e.client?.body ?? false)) {
      return const [];
    }
    return [
      for (final o in all)
        if (o.key != e.key && !(o.client?.body ?? false))
          if (words(o.name) case final theirs
              when theirs.length >= 2 &&
                  !body(theirs) &&
                  theirs.last == mine.last &&
                  UyapWebService.fold(o.name) != UyapWebService.fold(e.name) &&
                  () {
                    final a = mine.sublist(0, mine.length - 1);
                    final b = theirs.sublist(0, theirs.length - 1);
                    final (short, long) = a.length <= b.length
                        ? (a, b)
                        : (b, a);
                    for (var i = 0; i < short.length; i++) {
                      if (!long[i].startsWith(short[i]) &&
                          !short[i].startsWith(long[i])) {
                        return false;
                      }
                    }
                    return true;
                  }())
            o,
    ];
  }

  /// [other] told to be [card]'s client too: its names, and its card's
  /// records, are [card]'s; its card kept, taken off the list.
  Client mergeClients(Client card, ClientEntry other) {
    final merged = card.copyWith(
      names: {
        ...card.names,
        ...other.client?.folded ?? {UyapWebService.fold(other.name)},
      }.toList(),
      absorbed: {...card.absorbed, ...other.ids, ?other.client?.id}.toList(),
    );
    saveClient(merged);
    final gone = other.client;
    if (gone != null) saveClient(gone.copyWith(removed: true));
    return merged;
  }

  /// The cards and records, for one of the person's own devices: all of
  /// them; but the money others wrote while this person may not see it.
  /// What others than [me] wrote of client [id], taken off here.
  void _forgetOthersOf(String id, String me) {
    for (final r in _db.select(
      'SELECT id, json FROM client_record WHERE client_id=?',
      [id],
    )) {
      final rec = ClientRecord.fromJson(jsonDecode(r['json'] as String));
      if (rec != null && rec.person == me && me.isNotEmpty) continue;
      _db.execute('DELETE FROM client_record WHERE id=?', [r['id']]);
      if (rec != null) removedClientRecords.add(rec);
    }
    _forgetWaitingOf(id, me);
    _dropLedgerLeftovers();
  }

  /// What others than [me] sent of client [id] that waited, dropped.
  void _forgetWaitingOf(String id, String me) {
    for (final r in _db.select('SELECT id, json FROM client_record_pending')) {
      final rec = ClientRecord.fromJson(jsonDecode(r['json'] as String));
      if (rec != null &&
          rec.clientId == id &&
          !(rec.person == me && me.isNotEmpty)) {
        _db.execute('DELETE FROM client_record_pending WHERE id=?', [r['id']]);
      }
    }
  }

  Map<String, Object?> clientsExport() {
    final allowed = PortalDatabase.clientMoneyAllowed?.call() ?? true;
    final me = PortalDatabase.clientPerson?.call() ?? '';
    return {
      'muvekkiller': [
        for (final r in _db.select('SELECT json FROM client'))
          jsonDecode(r['json'] as String),
      ],
      'muvekkilKayitlari': [
        for (final r in _db.select('SELECT json FROM client_record'))
          if (ClientRecord.fromJson(jsonDecode(r['json'] as String))
              case final rec?
              when allowed || !rec.kind.financial || rec.person == me)
            rec.toJson(),
      ],
      if (allowed) 'defterEski': _legacyMap(),
    };
  }

  /// For the office's members: only the clients [me] shares, a client at
  /// a time (KVKK), and the records [me] wrote of the clients shared; the
  /// money among them only when it goes to one who may see it ([money]).
  /// A client no longer shared goes as its id alone, nothing of the person
  /// with it, for the others to forget it.
  Map<String, Object?> clientsOfficeExport({
    required bool money,
    required String me,
  }) {
    bool mine(String person) => person == me || person.isEmpty;
    final cards = clientCards();
    final shared = {
      for (final c in cards)
        if (c.office && !c.removed) c.id,
    };
    return {
      'muvekkiller': [
        for (final c in cards)
          if (c.sharedOnce && mine(c.person))
            c.office && !c.removed
                ? {...c.toJson(), 'kisi': me}
                : {
                    'id': c.id,
                    'ad': '',
                    'kisi': me,
                    'buro': false,
                    'paylasildi': true,
                    'guncelleme': c.updated.toIso8601String(),
                  },
      ],
      'muvekkilKayitlari': [
        for (final r in _db.select('SELECT json FROM client_record'))
          if (ClientRecord.fromJson(jsonDecode(r['json'] as String))
              case final rec?
              when (shared.contains(rec.clientId) ||
                      (rec.clientId == officeCashId && money)) &&
                  mine(rec.person) &&
                  (money || !rec.kind.financial))
            {...rec.toJson(), 'kisi': me},
      ],
      if (money)
        'defterEski': _legacyMap(
          entries: {
            for (final r in _db.select(
              "SELECT id, client_id, json FROM client_record WHERE kind='icra'",
            ))
              if (shared.contains(r['client_id']))
                if (ClientRecord.fromJson(jsonDecode(r['json'] as String))
                    case final rec? when mine(rec.person))
                  rec.id,
          },
        ),
    };
  }

  /// What the office member [from] sent ([clientsOfficeExport]): the cards
  /// they own and share, their records of the clients shared; a card they
  /// shared no longer forgotten here, but for what [me] wrote of it. No
  /// one's card is changed by another, nor a record by one who did not
  /// write it. Money only when [money].
  bool clientsOfficeMerge(
    Map<String, Object?> theirs, {
    required bool money,
    required String me,
    required String from,
  }) {
    // Nothing from no one; nothing from this person's own devices either:
    // those keep alike through their own channel, the card whole.
    if (from.isEmpty || from == me) return false;
    var changed = false;
    _transaction(() {
      for (final j in theirs['muvekkiller'] as List? ?? const []) {
        final c = Client.fromJson(j);
        if (c == null || c.person != from) continue;
        final kept = clientCard(c.id);
        // Only its owner's word changes a card here; one with no owner
        // named is this device's own, no one else's to take.
        if (kept != null && kept.person != from) continue;
        if (!c.office) {
          if (kept != null && !c.updated.isAfter(kept.updated)) continue;
          // Unshared by its owner: nothing of the person kept, but its id,
          // owner and day, so that an older word of it shared is refused;
          // what this person wrote of the client stays.
          _putClient(
            Client(
              id: c.id,
              name: '',
              updated: c.updated,
              removed: true,
              sharedOnce: true,
              person: from,
            ),
          );
          for (final r in _db.select(
            'SELECT id, json FROM client_record WHERE client_id=?',
            [c.id],
          )) {
            final rec = ClientRecord.fromJson(jsonDecode(r['json'] as String));
            if (rec != null && rec.person == me && me.isNotEmpty) continue;
            _db.execute('DELETE FROM client_record WHERE id=?', [r['id']]);
            if (rec != null) removedClientRecords.add(rec);
          }
          _forgetWaitingOf(c.id, me);
          _dropLedgerLeftovers();
          changed = true;
          continue;
        }
        // The owner's devices each say what they changed: field by field.
        final merged = kept == null ? c : Client.merge(kept, c);
        if (kept != null && merged.encode() == kept.encode()) continue;
        _putClient(merged);
        changed = true;
      }
    });
    final shared = {
      for (final c in clientCards())
        if (c.office && !c.removed) c.id,
    };
    final records = [
      for (final j in theirs['muvekkilKayitlari'] as List? ?? const [])
        if (j is Map &&
            (shared.contains(j['muvekkil']) ||
                (j['muvekkil'] == officeCashId && money)) &&
            j['kisi'] == from)
          j,
    ];
    // The old movements its writer's devices moved aside: only of their
    // own ledgers, sent with them or kept here (R3, R6).
    final ledgersOf = {
      for (final j in records)
        if (j['tur'] == ClientRecordKind.enforcement.code) j['id'],
    };
    if (clientsMerge(
      {
        'muvekkilKayitlari': records,
        if (money)
          'defterEski': [
            for (final j in theirs['defterEski'] as List? ?? const [])
              if (j is Map &&
                  (ledgersOf.contains(j['kayit']) ||
                      (j['kayit'] is String &&
                          clientRecord(j['kayit'] as String)?.person == from)))
                j,
          ],
      },
      money: money,
      author: from,
      person: me,
    )) {
      changed = true;
    }
    return changed;
  }

  /// What another device keeps, merged in: of each card, each field the
  /// one set later ([Client.merge]); of each record, the newer; a record locked here stays as it is. True when anything
  /// changed here.
  bool clientsMerge(
    Map<String, Object?> theirs, {
    bool money = true,
    String? author,
    String? person,
  }) {
    final me = person ?? PortalDatabase.clientPerson?.call() ?? '';
    var changed = false;
    _transaction(() {
      for (final j in theirs['muvekkiller'] as List? ?? const []) {
        final c = Client.fromJson(j);
        if (c == null) continue;
        final kept = clientCard(c.id);
        final merged = kept == null ? c : Client.merge(kept, c);
        if (kept != null && merged.encode() == kept.encode()) continue;
        _putClient(merged);
        changed = true;
      }
      final ledgers = <String>{};
      // Ledgers in their old form, with what came of them: weighed after.
      final weigh = <String>{};
      // The old movements another device moved aside, known first: what
      // acts on them is not taken (R3).
      if (money) {
        _takeLegacyMap(theirs['defterEski']);
        if (_retireMapped()) changed = true;
      }
      // Ledgers kept here in their old form that came in their new one.
      final mended = <String>{};
      for (final j in theirs['muvekkilKayitlari'] as List? ?? const []) {
        final r = ClientRecord.fromJson(j);
        // Money from, or for, one who may not see it is not taken.
        if (r == null || (!money && r.kind.financial)) continue;
        // A ledger's movements are made here of its record, never taken.
        if (_ledgerMade(r)) continue;
        // Of a colleague's client unshared, only this person's own.
        final card = clientCard(r.clientId);
        if (card != null && _unshared(card, me) && r.person != me) continue;
        // From the office, only its writer's own: a record kept here is
        // changed by no one else, nor moved to another client or kind.
        if (author != null) {
          final there = clientRecord(r.id);
          if (r.person != author) continue;
          if (there != null &&
              (there.person != author ||
                  there.clientId != r.clientId ||
                  there.kind != r.kind)) {
            continue;
          }
        }
        // A movement that takes back, sets off or books another's: only
        // its owner's, of the same client; one whose other has not come
        // yet waits apart, in no total, till it does (R6). A movement made
        // of a ledger is no one's to act on (R3), from any device.
        if (_linkCheck(r) == _Link.refused && _linkOf(r) != null) {
          final target = clientRecord(_linkOf(r)!);
          if (target != null && LedgerBook.isProjected(target)) continue;
        }
        if (author != null) {
          switch (_linkCheck(r)) {
            case _Link.refused:
              continue;
            case _Link.waiting:
              _db.execute(
                'INSERT OR REPLACE INTO client_record_pending(id, author, json) '
                'VALUES(?,?,?)',
                [r.id, author, jsonEncode(r.toJson())],
              );
              continue;
            case _Link.ok:
          }
        }
        final kept = clientRecord(r.id);
        // A ledger's record, group by group: what each device changed of it
        // stands (R1).
        if (r.kind == ClientRecordKind.enforcement &&
            kept != null &&
            kept.kind == ClientRecordKind.enforcement &&
            !kept.locked) {
          // Both in an older Folio's form: the later of the two whole, and
          // weighed; only the weighing makes it new (R3), never a merge.
          if (!LedgerBook.isNewForm(kept) && !LedgerBook.isNewForm(r)) {
            if (!r.updated.isAfter(kept.updated)) continue;
            _putRecord(r);
            weigh.add(r.id);
            changed = true;
            continue;
          }
          if (!LedgerBook.isNewForm(kept)) mended.add(r.id);
          final merged = LedgerBook.merge(kept, r);
          if (jsonEncode(merged.toJson()) == jsonEncode(kept.toJson())) {
            continue;
          }
          _putRecord(merged);
          ledgers.add(r.id);
          changed = true;
          continue;
        }
        if (kept != null && (kept.locked || !r.updated.isAfter(kept.updated))) {
          continue;
        }
        _putRecord(r);
        if (r.kind == ClientRecordKind.enforcement) {
          if (LedgerBook.isNewForm(r)) {
            ledgers.add(r.id);
          } else {
            weigh.add(r.id);
          }
        }
        final source = r.text('kaynak');
        if (source.startsWith('icra:')) {
          weigh.add(source.substring('icra:'.length));
        }
        changed = true;
      }
      for (final id in ledgers) {
        // Mended on another device: mended here alike.
        if (ledgerRepairOf(id) != null || mended.contains(id)) {
          _adoptRepaired(id);
        } else {
          rebuildLedger(id);
        }
        // Each version seen: what is written here after it comes after it.
        if (clientRecord(id) case final r?) _observe(r);
      }
      for (final id in weigh.difference(ledgers)) {
        _weighLedger(id);
      }
      if (money && _retireMapped()) changed = true;
      if (_takeWaiting(money: money, me: me)) changed = true;
      // Every colleague's client unshared, come now or before: what
      // others wrote of it goes here, this person's stays.
      // Not knowing who this is, nothing is taken for another's.
      if (me.isNotEmpty) {
        for (final c in clientCards()) {
          if (_unshared(c, me)) _forgetOthersOf(c.id, me);
        }
      }
      _dropOrphanProjection();
    });
    return changed;
  }

  /// The record [r] names as the one it takes back (`ters`), sets off
  /// (`kaynak: mahsup:…`) or books (`kaynak: icra:…`); null for none.
  static String? _linkOf(ClientRecord r) {
    if (r.kind != ClientRecordKind.movement) return null;
    final back = r.text('ters');
    if (back.isNotEmpty) return back;
    final source = r.text('kaynak');
    for (final p in const ['mahsup:', 'icra:']) {
      if (source.startsWith(p) && source.length > p.length) {
        return source.substring(p.length);
      }
    }
    return null;
  }

  /// Whether a member's [r] may act on the record it names: refused when
  /// that is another person's or another client's, waiting when it has not
  /// come yet.
  _Link _linkCheck(ClientRecord r) {
    final link = _linkOf(r);
    if (link == null) return _Link.ok;
    final target = clientRecord(link);
    if (target == null) return _Link.waiting;
    if (LedgerBook.isProjected(target) ||
        target.person != r.person ||
        target.clientId != r.clientId) {
      return _Link.refused;
    }
    // A reversal takes back a movement of its own case.
    if (r.text('ters').isNotEmpty &&
        r.text('dosya').isNotEmpty &&
        target.text('dosya') != r.text('dosya')) {
      return _Link.refused;
    }
    return _Link.ok;
  }

  /// The movements waiting for the record they name, taken in now that it
  /// came, or dropped when it is another's; true when one was taken in.
  bool _takeWaiting({required bool money, required String me}) {
    var took = false;
    for (final row in _db.select(
      'SELECT id, author, json FROM client_record_pending',
    )) {
      final r = ClientRecord.fromJson(jsonDecode(row['json'] as String));
      // What may be taken is asked again now: the money let, the client
      // still shared, its writer the one who sent it, nothing of a ledger.
      final card = r == null ? null : clientCard(r.clientId);
      final allowed =
          r != null &&
          (money || !r.kind.financial) &&
          r.person == row['author'] &&
          !(card != null && _unshared(card, me) && r.person != me) &&
          !_ledgerMade(r);
      final check = !allowed ? _Link.refused : _linkCheck(r);
      if (check == _Link.waiting) continue;
      _db.execute('DELETE FROM client_record_pending WHERE id=?', [row['id']]);
      if (check == _Link.refused || r == null) continue;
      final kept = clientRecord(r.id);
      if (kept != null && (kept.locked || !r.updated.isAfter(kept.updated))) {
        continue;
      }
      _putRecord(r);
      took = true;
    }
    return took;
  }

  /// The movements from members waiting for the record they name.
  int get waitingRecords =>
      _db.select('SELECT count(*) AS n FROM client_record_pending').first['n']
          as int;

  /// The enforcement ledgers made into their new form (docs/senkron-plan.md
  /// R3, migration; schema 2), in the migration's transaction: each in its
  /// old form weighed ([_weighLedger]); one in its new form is left as it
  /// is, so that the migration run again changes nothing.
  void migrateLedgers() {
    final index = _LegacyIndex(_db);
    for (final e in index.entries) {
      if (LedgerBook.isNewForm(e)) continue;
      _weighLedgerWith(e, index);
    }
  }

  /// [entryId], a ledger in its old form, weighed against the movements an
  /// older Folio wrote of it ([_weigh]): alike, made into its new form; not
  /// alike, put in a repair report for the lawyer's word.
  void _weighLedger(String entryId) {
    final e = clientRecord(entryId);
    if (e == null ||
        e.kind != ClientRecordKind.enforcement ||
        LedgerBook.isNewForm(e)) {
      return;
    }
    _weighLedgerWith(e, _LegacyIndex(_db));
  }

  void _weighLedgerWith(ClientRecord e, _LegacyIndex index) {
    final weighed = _weigh(e, index);
    if (weighed.why == null) {
      _ledgerAside(e, weighed.legacy, weighed.setOffs);
      return;
    }
    _db.execute(
      'INSERT OR REPLACE INTO ledger_repair(entry_id, json) VALUES(?,?)',
      [e.id, jsonEncode(_reportOf(e, weighed))],
    );
  }

  /// [e]'s old movements weighed against it, component by component: its
  /// client, its case, TL, what each is, and its sum (R3).
  _Weighed _weigh(ClientRecord e, _LegacyIndex index) {
    final held = [
      for (final m in index.bySource['icra:${e.id}'] ?? const <ClientRecord>[])
        if (m.text('ters').isEmpty) m,
    ];
    final applied = [
      for (final h in held)
        for (final m
            in index.bySource['mahsup:${h.id}'] ?? const <ClientRecord>[])
          if (m.text('ters').isEmpty) m,
    ];
    // The reversals of them, and of those, all the way down.
    final reversals = <ClientRecord>[];
    final seen = {
      for (final m in [...held, ...applied]) m.id,
    };
    for (var round = [...held, ...applied]; round.isNotEmpty;) {
      round = [
        for (final m in round)
          for (final r in index.reversalsOf[m.id] ?? const <ClientRecord>[])
            if (seen.add(r.id)) r,
      ];
      reversals.addAll(round);
    }
    final legacy = [...held, ...applied, ...reversals];
    bool standing(ClientRecord m) =>
        !m.removed && !index.reversalsOf.containsKey(m.id);
    bool ours(ClientRecord m) =>
        m.clientId == e.clientId &&
        m.text('dosya') == e.text('dosya') &&
        (m.text('para').isEmpty || m.text('para') == 'TL');
    final standingHeld = [
      for (final m in held)
        if (standing(m)) m,
    ];
    final standingApplied = [
      for (final m in applied)
        if (standing(m)) m,
    ];
    final setOffs = [
      for (final m in standingApplied)
        if (m.movement case final kind? when kind.isApplied)
          LedgerSetOff(
            id: m.id,
            target: kind,
            amount: m.amount,
            at: m.at,
            version: Hlc.fromLegacy(m.created.toIso8601String()),
          ),
    ];
    String? why;
    final byId = {for (final m in legacy) m.id: m};
    if (reversals.any((r) => index.reversalsOf.containsKey(r.id))) {
      why = 'Bir ters kayıt yeniden terslenmiş.';
    } else if (legacy.any((m) => !ours(m))) {
      why =
          'Eski kayıtlardan biri başka bir müvekkilin, dosyanın ya da '
          'para biriminin.';
    } else if (reversals.any((r) => byId[r.text('ters')]?.amount != r.amount)) {
      why = 'Bir ters kayıt düzelttiği tutardan farklı.';
    } else if (reversals.any(
      (r) => byId[r.text('ters')]?.movement != r.movement,
    )) {
      why = 'Bir ters kayıt düzelttiği kaydın türünden farklı.';
    } else if (held.any((m) => m.movement != MovementKind.collected) ||
        applied.any((m) => !(m.movement?.isApplied ?? false))) {
      why = 'Eski kayıtlardan birinin türü beklenmedik.';
    } else if (LedgerBook.books(e) && e.amount > 0) {
      final takenOut = standingApplied.fold<int>(0, (n, m) => n + m.amount);
      if (standingHeld.length != 1) {
        why = standingHeld.isEmpty
            ? 'Ödeme müvekkil hesabına işlenmemiş.'
            : 'Ödeme müvekkil hesabına ${standingHeld.length} kez işlenmiş.';
      } else if (standingHeld.single.amount != e.amount) {
        why = 'Müvekkil hesabındaki tutar ödemeninkinden farklı.';
      } else if (takenOut > e.amount) {
        why = 'Mahsuplar ödenen tutarı aşıyor.';
      } else if (standingApplied.any(
        (m) => m.text('kaynak') != 'mahsup:${standingHeld.single.id}',
      )) {
        why = 'Bir mahsup terslenmiş bir tahsilata bağlı.';
      }
    } else if (standingHeld.isNotEmpty || standingApplied.isNotEmpty) {
      why = 'Kaldırılmış ödeme müvekkil hesabında hâlâ duruyor.';
    }
    int sum(Iterable<ClientRecord> ms) =>
        ms.fold<int>(0, (n, m) => n + m.amount);
    final proposed = LedgerBook.stateOf(
      LedgerBook.write(e, versions: LedgerBook.versionsOf(e), setOffs: setOffs),
    );
    // What is held and taken, by what it is taken as: in TL, of this
    // client and case alone; what is not is only named (`karsilastirilir`).
    Map<String, Object?> sums(
      int held,
      Iterable<({MovementKind kind, int amount})> taken,
    ) {
      final out = <String, Object?>{'emanet': held};
      for (final t in taken) {
        out['emanet'] = (out['emanet'] as int) - t.amount;
        out[t.kind.code] = ((out[t.kind.code] as int?) ?? 0) + t.amount;
      }
      return out;
    }

    return _Weighed(
      legacy: legacy,
      why: why,
      setOffs: setOffs,
      comparable: legacy.every(ours),
      now: sums(sum(standingHeld), [
        for (final m in standingApplied)
          if (m.movement case final k?) (kind: k, amount: m.amount),
      ]),
      after: sums(proposed.held, [
        for (final s in proposed.active) (kind: s.target, amount: s.amount),
      ]),
    );
  }

  /// The report of [e]'s weighing: why, the old movements, what is held
  /// and taken as a fee now and once mended, and a digest of the record,
  /// the movements and what is proposed, which the lawyer's word is given
  /// for.
  Map<String, Object?> _reportOf(ClientRecord e, _Weighed w) => {
    'neden': w.why,
    'kimlikler': [for (final m in w.legacy) m.id],
    'simdi': w.now,
    'onarinca': w.after,
    'karsilastirilir': w.comparable,
    'ozet': _digestOf(e, w),
  };

  static String _digestOf(ClientRecord e, _Weighed w) => Hlc.digest({
    'kayit': {'veri': e.data, 'muvekkil': e.clientId, 'silindi': e.removed},
    'eski': [
      for (final m in [...w.legacy]..sort((a, b) => a.id.compareTo(b.id)))
        m.toJson(),
    ],
    'oneri': [for (final s in w.setOffs) s.toJson()],
  });

  /// [e] in its new form with [setOffs], its [legacy] movements moved to
  /// the ledger's history, and its projection made.
  void _ledgerAside(
    ClientRecord e,
    List<ClientRecord> legacy,
    List<LedgerSetOff> setOffs,
  ) {
    final made = LedgerBook.isNewForm(e)
        ? e
        : LedgerBook.write(
            e,
            versions: LedgerBook.versionsOf(e),
            setOffs: setOffs,
            // The lawyer's word that UYAP has it, given by an older Folio,
            // for the sum and day it has now (R4).
            data: LedgerBook.bindOldWord(e),
          );
    _putRecord(made);
    for (final m in legacy) {
      _db.execute(
        'INSERT OR REPLACE INTO ledger_history(id, entry_id, json) '
        'VALUES(?,?,?)',
        [m.id, e.id, jsonEncode(m.toJson())],
      );
      _db.execute(
        'INSERT OR REPLACE INTO ledger_legacy(id, entry_id) VALUES(?,?)',
        [m.id, e.id],
      );
      _db.execute('DELETE FROM client_record WHERE id=?', [m.id]);
    }
    _db.execute('DELETE FROM ledger_repair WHERE entry_id=?', [e.id]);
    rebuildLedger(e.id);
    _observe(made);
  }

  /// [entryId] waited for its repair here and came in its new form from a
  /// device where it was mended: its old movements here moved aside alike.
  void _adoptRepaired(String entryId) {
    final e = clientRecord(entryId);
    if (e == null || !LedgerBook.isNewForm(e)) return;
    _ledgerAside(e, _weigh(e, _LegacyIndex(_db)).legacy, const []);
  }

  /// Every version of [r] taken into the clock (R2).
  void _observe(ClientRecord r) {
    for (final v in LedgerBook.versionsOf(r).values) {
      SyncClock.observe(this, v);
    }
    for (final s in LedgerBook.setOffsOf(r)) {
      SyncClock.observe(this, s.version);
    }
  }

  /// The lawyer's word on [entryId]'s repair report: its old movements
  /// give way to what its record says, as the report showed it. When the
  /// record, its movements or what is proposed changed since ([digest] no
  /// longer theirs), nothing is mended, the report is made anew, and false
  /// is given: it is to be looked at again.
  bool resolveLedgerRepair(String entryId, String digest) {
    var ok = false;
    _transaction(() {
      final e = clientRecord(entryId);
      if (e == null || ledgerRepairOf(entryId) == null) return;
      // Only by its writer, as every change of it (R6).
      if (!isMineToMend(e)) return;
      final weighed = _weigh(e, _LegacyIndex(_db));
      if (_digestOf(e, weighed) != digest) {
        _db.execute(
          'INSERT OR REPLACE INTO ledger_repair(entry_id, json) VALUES(?,?)',
          [
            e.id,
            jsonEncode(
              _reportOf(
                e,
                _Weighed(
                  legacy: weighed.legacy,
                  why: weighed.why ?? 'Kayıt bu arada değişti.',
                  setOffs: weighed.setOffs,
                  comparable: weighed.comparable,
                  now: weighed.now,
                  after: weighed.after,
                ),
              ),
            ),
          ],
        );
        return;
      }
      _ledgerAside(e, weighed.legacy, weighed.setOffs);
      addLedgerHistory(e.id, {
        'islem': 'onar',
        'kisi': PortalDatabase.clientPerson?.call() ?? '',
        'kaynak': SyncClock.of(this).source,
        'zaman': DateTime.now().toIso8601String(),
        'eski': [for (final m in weighed.legacy) m.id],
      });
      ok = true;
    });
    if (ok) _notifyChanged();
    return ok;
  }

  /// Whether [e] is this person's to mend: their own, or no one's named.
  bool isMineToMend(ClientRecord e) {
    final me = PortalDatabase.clientPerson?.call() ?? '';
    return e.person.isEmpty || me.isEmpty || e.person == me;
  }

  /// A colleague's client unshared: the mark of it, nothing of the person
  /// in it (a card merged into another keeps its name and its records).
  static bool _unshared(Client c, String me) =>
      c.removed &&
      c.name.isEmpty &&
      !c.office &&
      c.person.isNotEmpty &&
      c.person != me;
}

/// What a member's movement may do to the record it names.
enum _Link { ok, refused, waiting }

/// What an older Folio wrote of the ledgers, read once: the movements by
/// what they came of, and the reversals by what they take back.
class _LegacyIndex {
  _LegacyIndex(Database db) {
    for (final r in db.select('SELECT json FROM client_record')) {
      final rec = ClientRecord.fromJson(jsonDecode(r['json'] as String));
      if (rec == null) continue;
      if (rec.kind == ClientRecordKind.enforcement) entries.add(rec);
      if (rec.kind != ClientRecordKind.movement) continue;
      final source = rec.text('kaynak');
      if (source.isNotEmpty) (bySource[source] ??= []).add(rec);
      final back = rec.text('ters');
      if (back.isNotEmpty) (reversalsOf[back] ??= []).add(rec);
    }
  }

  final entries = <ClientRecord>[];
  final bySource = <String, List<ClientRecord>>{};
  final reversalsOf = <String, List<ClientRecord>>{};
}

/// A ledger weighed against its old movements.
class _Weighed {
  const _Weighed({
    required this.legacy,
    required this.why,
    required this.setOffs,
    required this.comparable,
    required this.now,
    required this.after,
  });

  final List<ClientRecord> legacy;
  final String? why;
  final List<LedgerSetOff> setOffs;

  /// Whether every old movement is in TL, of this client and case: what
  /// [now] and [after] say is the whole of it only then.
  final bool comparable;

  /// Kuruş held (`emanet`) and taken, by what it is taken as.
  final Map<String, Object?> now, after;
}

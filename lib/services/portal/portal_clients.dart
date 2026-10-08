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
    final kept = clientRecord(r.id);
    if (kept != null && kept.locked) return false;
    // Money in or out is evidence: never changed once written.
    if (r.kind == ClientRecordKind.movement && !r.locked) {
      r = r.copyWith(locked: true);
    }
    _putRecord(r);
    PortalDatabase.changed?.call();
    return true;
  }

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

  /// Every record kept, the removed among them.
  List<ClientRecord> allClientRecords() => [
    for (final r in _db.select('SELECT json FROM client_record'))
      ?ClientRecord.fromJson(jsonDecode(r['json'] as String)),
  ];

  ClientRecord? clientRecord(String id) {
    final rows = _db.select('SELECT json FROM client_record WHERE id=?', [id]);
    return rows.isEmpty
        ? null
        : ClientRecord.fromJson(jsonDecode(rows.first['json'] as String));
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
    ]..removeWhere((r) => r.removed);
    return out..sort((a, b) => b.created.compareTo(a.created));
  }

  /// The money records others wrote, forgotten here: this person may no
  /// longer see them. Their own stay.
  void forgetClientMoney({required String keepPerson}) {
    for (final r in _db.select(
      "SELECT id, json FROM client_record WHERE kind IN ('ucret','hareket')",
    )) {
      final rec = ClientRecord.fromJson(jsonDecode(r['json'] as String));
      if (rec == null || rec.person == keepPerson) continue;
      _db.execute('DELETE FROM client_record WHERE id=?', [r['id']]);
      removedClientRecords.add(rec);
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
        if (folded.isEmpty) continue;
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
      out.add(
        ClientEntry(
          key: c.id,
          name: c.name,
          client: c,
          cases: cases,
          ids: [
            for (final x in cards) ...[x.id, ...x.absorbed],
          ],
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
              when allowed || !rec.kind.money || rec.person == me)
            rec.toJson(),
      ],
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
              when shared.contains(rec.clientId) &&
                  mine(rec.person) &&
                  (money || !rec.kind.money))
            {...rec.toJson(), 'kisi': me},
      ],
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
    if (from.isEmpty) return false;
    var changed = false;
    _transaction(() {
      for (final j in theirs['muvekkiller'] as List? ?? const []) {
        final c = Client.fromJson(j);
        if (c == null || c.person != from) continue;
        final kept = clientCard(c.id);
        if (kept != null && kept.person.isNotEmpty && kept.person != from) {
          continue;
        }
        if (kept != null && !c.updated.isAfter(kept.updated)) continue;
        if (!c.office) {
          if (kept == null) continue;
          // Unshared by its owner: gone from here, but what this person
          // wrote of the client.
          _db.execute('DELETE FROM client WHERE id=?', [c.id]);
          for (final r in _db.select(
            'SELECT id, json FROM client_record WHERE client_id=?',
            [c.id],
          )) {
            final rec = ClientRecord.fromJson(jsonDecode(r['json'] as String));
            if (rec != null && rec.person == me && me.isNotEmpty) continue;
            _db.execute('DELETE FROM client_record WHERE id=?', [r['id']]);
            if (rec != null) removedClientRecords.add(rec);
          }
          changed = true;
          continue;
        }
        _putClient(c);
        changed = true;
      }
    });
    final shared = {
      for (final c in clientCards())
        if (c.office && !c.removed) c.id,
    };
    if (clientsMerge({
      'muvekkilKayitlari': [
        for (final j in theirs['muvekkilKayitlari'] as List? ?? const [])
          if (j is Map && shared.contains(j['muvekkil']) && j['kisi'] == from)
            j,
      ],
    }, money: money)) {
      changed = true;
    }
    return changed;
  }

  /// What another device keeps, merged in: the newer of each card and
  /// record wins; a record locked here stays as it is. True when anything
  /// changed here.
  bool clientsMerge(Map<String, Object?> theirs, {bool money = true}) {
    var changed = false;
    _transaction(() {
      for (final j in theirs['muvekkiller'] as List? ?? const []) {
        final c = Client.fromJson(j);
        if (c == null) continue;
        final kept = clientCard(c.id);
        if (kept != null && !c.updated.isAfter(kept.updated)) continue;
        _putClient(c);
        changed = true;
      }
      for (final j in theirs['muvekkilKayitlari'] as List? ?? const []) {
        final r = ClientRecord.fromJson(j);
        // Money from, or for, one who may not see it is not taken.
        if (r == null || (!money && r.kind.money)) continue;
        final kept = clientRecord(r.id);
        if (kept != null && (kept.locked || !r.updated.isAfter(kept.updated))) {
          continue;
        }
        _putRecord(r);
        changed = true;
      }
    });
    return changed;
  }
}

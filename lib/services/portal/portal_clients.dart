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
  ''';

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
          ids: [for (final x in cards) x.id],
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
  Map<String, Object?> clientsExport() => {
    'muvekkiller': [
      for (final r in _db.select('SELECT json FROM client'))
        jsonDecode(r['json'] as String),
    ],
    'muvekkilKayitlari': [
      for (final r in _db.select('SELECT json FROM client_record'))
        jsonDecode(r['json'] as String),
    ],
  };

  /// For the office's members: only the clients shared with the office,
  /// a client at a time (KVKK); the money among their records only when
  /// it goes to one who may see it ([money]). A client no longer shared
  /// goes as a card alone, for them to forget it.
  Map<String, Object?> clientsOfficeExport({required bool money}) {
    final cards = [
      for (final c in clientCards())
        if (c.sharedOnce) c,
    ];
    final shared = {
      for (final c in cards)
        if (c.office && !c.removed) c.id,
    };
    return {
      'muvekkiller': [for (final c in cards) c.toJson()],
      'muvekkilKayitlari': [
        for (final r in _db.select('SELECT json FROM client_record'))
          if (ClientRecord.fromJson(jsonDecode(r['json'] as String))
              case final rec?
              when shared.contains(rec.clientId) && (money || !rec.kind.money))
            rec.toJson(),
      ],
    };
  }

  /// What an office member sent ([clientsOfficeExport]): the clients they
  /// share, and those they shared no longer, forgotten here but for what
  /// [me] wrote of them. Money only when [money].
  bool clientsOfficeMerge(
    Map<String, Object?> theirs, {
    required bool money,
    required String me,
  }) {
    var changed = false;
    final shared = <String>{};
    _transaction(() {
      for (final j in theirs['muvekkiller'] as List? ?? const []) {
        final c = Client.fromJson(j);
        if (c == null) continue;
        final kept = clientCard(c.id);
        if (kept != null && !c.updated.isAfter(kept.updated)) {
          if (kept.office) shared.add(kept.id);
          continue;
        }
        if (!c.office && c.person != me) {
          // Unshared by its owner: gone from here, but what this person
          // wrote of the client.
          final hadAny = kept != null;
          _db.execute('DELETE FROM client WHERE id=?', [c.id]);
          for (final r in _db.select(
            'SELECT id, json FROM client_record WHERE client_id=?',
            [c.id],
          )) {
            final rec = ClientRecord.fromJson(jsonDecode(r['json'] as String));
            if (rec != null && rec.person == me && me.isNotEmpty) continue;
            _db.execute('DELETE FROM client_record WHERE id=?', [r['id']]);
            changed = true;
          }
          if (hadAny) changed = true;
          continue;
        }
        _putClient(c);
        changed = true;
        if (c.office) shared.add(c.id);
      }
    });
    if (clientsMerge({
      'muvekkilKayitlari': [
        for (final j in theirs['muvekkilKayitlari'] as List? ?? const [])
          if (j is Map && shared.contains(j['muvekkil'])) j,
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

part of 'portal_database.dart';

/// What is kept of the lawyer's notes beyond the notes themselves
/// (docs/senkron-plan.md R7): of their own, each made secret and who in
/// the office holds a copy; of a colleague's, the notes of the tasks they
/// gave, and what they took back.
extension PortalNotes on PortalDatabase {
  static const _tables = '''
    CREATE TABLE IF NOT EXISTS note_hide (
      not_key TEXT NOT NULL, kapsam TEXT NOT NULL, surum TEXT NOT NULL,
      PRIMARY KEY(not_key, surum));
    CREATE TABLE IF NOT EXISTS note_hold (
      not_key TEXT NOT NULL, cihaz TEXT NOT NULL, kisi TEXT NOT NULL,
      kapsam TEXT NOT NULL, tuttu INTEGER NOT NULL DEFAULT 0,
      surum TEXT NOT NULL DEFAULT '', uygulanan TEXT NOT NULL DEFAULT '',
      PRIMARY KEY(not_key, cihaz, kapsam));
    CREATE TABLE IF NOT EXISTS task_note (
      sahip TEXT NOT NULL, gorev TEXT NOT NULL, dosya TEXT NOT NULL,
      id TEXT NOT NULL, satir TEXT, surumler TEXT NOT NULL,
      gizlenen TEXT NOT NULL DEFAULT '',
      PRIMARY KEY(sahip, gorev, dosya, id));
    CREATE TABLE IF NOT EXISTS taken_note_hide (
      sahip TEXT NOT NULL, not_key TEXT NOT NULL, surum TEXT NOT NULL,
      PRIMARY KEY(sahip, not_key, surum));
    CREATE TABLE IF NOT EXISTS task_note_clean (
      gorev TEXT NOT NULL, dosya TEXT NOT NULL, durum TEXT NOT NULL,
      PRIMARY KEY(gorev, dosya));
  ''';

  // The lawyer's own notes.

  /// [noteKey] made secret at [version], of [scope] (a case's key, a
  /// card's id): kept for good, its text never in it. Made open again, it
  /// stays: what was taken back stays taken back.
  void recordHide(String noteKey, String scope, Hlc version) => _db.execute(
    'INSERT OR IGNORE INTO note_hide(not_key, kapsam, surum) VALUES(?,?,?)',
    [noteKey, scope, '$version'],
  );

  /// Every note made secret, by its key: the latest version it was.
  Map<String, ({String scope, Hlc version})> get noteHides {
    final out = <String, ({String scope, Hlc version})>{};
    for (final r in _db.select(
      'SELECT not_key, kapsam, surum FROM note_hide',
    )) {
      final v = Hlc.tryParse(r['surum']);
      if (v == null) continue;
      final key = r['not_key'] as String;
      final kept = out[key];
      if (kept == null || v > kept.version) {
        out[key] = (scope: r['kapsam'] as String, version: v);
      }
    }
    return out;
  }

  /// The latest version [noteKey] was made secret at; null for never.
  Hlc? hideOf(String noteKey) {
    Hlc? out;
    for (final r in _db.select('SELECT surum FROM note_hide WHERE not_key=?', [
      noteKey,
    ])) {
      final v = Hlc.tryParse(r['surum']);
      if (v != null && (out == null || v > out)) out = v;
    }
    return out;
  }

  /// That [device] of [person] may hold [noteKey] in [scope] (`gorev:`
  /// task and case, `kart:` a card's id): sent to it, or said by it. [held] the
  /// version it said it holds, [applied] the latest taking back it did.
  void recordHold(
    String noteKey,
    String device,
    String person,
    String scope, {
    Hlc? held,
    Hlc? applied,
    bool gone = false,
  }) {
    _db.execute(
      'INSERT OR IGNORE INTO note_hold(not_key, cihaz, kisi, kapsam, tuttu) '
      'VALUES(?,?,?,?,1)',
      [noteKey, device, person, scope],
    );
    final now = _db.select(
      'SELECT surum, uygulanan FROM note_hold WHERE not_key=? AND cihaz=? '
      'AND kapsam=?',
      [noteKey, device, scope],
    ).first;
    final was = Hlc.tryParse(now['uygulanan']);
    _db.execute(
      'UPDATE note_hold SET surum=?, uygulanan=? WHERE not_key=? AND cihaz=? '
      'AND kapsam=?',
      [
        gone ? '' : (held == null ? now['surum'] : '$held'),
        applied != null && (was == null || applied > was)
            ? '$applied'
            : now['uygulanan'],
        noteKey,
        device,
        scope,
      ],
    );
  }

  /// Who holds, or may hold, [noteKey], device by device.
  List<({String device, String person, String scope, Hlc? held, Hlc? applied})>
  holdsOf(String noteKey) => [
    for (final r in _db.select(
      'SELECT cihaz, kisi, kapsam, surum, uygulanan FROM note_hold '
      'WHERE not_key=? AND tuttu=1',
      [noteKey],
    ))
      (
        device: r['cihaz'] as String,
        person: r['kisi'] as String,
        scope: r['kapsam'] as String,
        held: Hlc.tryParse(r['surum']),
        applied: Hlc.tryParse(r['uygulanan']),
      ),
  ];

  /// What the lawyer's other devices take of it.
  Map<String, Object?> noteTrackingExport() => {
    'gizlemeler': [
      for (final r in _db.select('SELECT * FROM note_hide'))
        {for (final c in r.keys) c: r[c]},
    ],
    'tutanlar': [
      for (final r in _db.select('SELECT * FROM note_hold'))
        {for (final c in r.keys) c: r[c]},
    ],
    'alinanGizlemeler': [
      for (final r in _db.select('SELECT * FROM taken_note_hide'))
        {for (final c in r.keys) c: r[c]},
    ],
  };

  /// Another own device's [noteTrackingExport]: each kept for good, the
  /// later of what was said of each copy. True when anything changed.
  bool noteTrackingMerge(Object? theirs) {
    if (theirs is! Map) return false;
    final before = Hlc.canonical(noteTrackingExport());
    _transaction(() {
      for (final r in theirs['gizlemeler'] as List? ?? const []) {
        if (r is! Map) continue;
        final v = Hlc.tryParse(r['surum']);
        if (r['not_key'] is! String || r['kapsam'] is! String || v == null) {
          continue;
        }
        SyncClock.observe(this, v);
        recordHide(r['not_key'] as String, r['kapsam'] as String, v);
      }
      for (final r in theirs['tutanlar'] as List? ?? const []) {
        if (r is! Map ||
            r['not_key'] is! String ||
            r['cihaz'] is! String ||
            r['kapsam'] is! String) {
          continue;
        }
        recordHold(
          r['not_key'] as String,
          r['cihaz'] as String,
          '${r['kisi'] ?? ''}',
          r['kapsam'] as String,
          held: Hlc.tryParse(r['surum']),
          applied: Hlc.tryParse(r['uygulanan']),
        );
      }
      for (final r in theirs['alinanGizlemeler'] as List? ?? const []) {
        if (r is! Map || r['sahip'] is! String || r['not_key'] is! String) {
          continue;
        }
        final v = Hlc.tryParse(r['surum']);
        if (v != null) {
          takeNoteHide(r['sahip'] as String, r['not_key'] as String, v);
        }
      }
    });
    final changed = Hlc.canonical(noteTrackingExport()) != before;
    if (changed) applyTakenNoteHides();
    return changed;
  }

  // A colleague's notes.

  /// That [owner] took back [noteKey] at [version]: kept for good, so that
  /// no copy of it of before comes back here.
  void takeNoteHide(String owner, String noteKey, Hlc version) => _db.execute(
    'INSERT OR IGNORE INTO taken_note_hide(sahip, not_key, surum) '
    'VALUES(?,?,?)',
    [owner, noteKey, '$version'],
  );

  /// What [owner] took back of their cards' notes, as kept here: each
  /// applied to the copies here as it came ([applyTakenNoteHides]).
  List<({String key, Hlc version})> takenNoteHidesOf(String owner) => [
    for (final r in _db.select(
      'SELECT not_key, surum FROM taken_note_hide WHERE sahip=?',
      [owner],
    ))
      if (Hlc.tryParse(r['surum']) case final v?)
        (key: r['not_key'] as String, version: v),
  ];

  /// Whether [device] is known to have held [noteKey].
  bool knowsHold(String noteKey, String device) => _db.select(
    'SELECT 1 FROM note_hold WHERE not_key=? AND cihaz=? AND tuttu=1',
    [noteKey, device],
  ).isNotEmpty;

  /// Every note held in [scope]'s older packages ("eski:" task and case):
  /// those of [caseKey].
  List<({String device, String person, Hlc? applied})> oldHoldsOf(
    String caseKey,
  ) => [
    for (final r in _db.select(
      "SELECT not_key, cihaz, kisi, uygulanan FROM note_hold "
      "WHERE not_key LIKE 'eski:%' AND tuttu=1",
    ))
      if ((r['not_key'] as String).endsWith('|$caseKey'))
        (
          device: r['cihaz'] as String,
          person: r['kisi'] as String,
          applied: Hlc.tryParse(r['uygulanan']),
        ),
  ];

  /// The latest of what [owner] took back of [noteKey]; null for none.
  Hlc? takenNoteHide(String owner, String noteKey) {
    Hlc? out;
    for (final r in _db.select(
      'SELECT surum FROM taken_note_hide WHERE sahip=? AND not_key=?',
      [owner, noteKey],
    )) {
      final v = Hlc.tryParse(r['surum']);
      if (v != null && (out == null || v > out)) out = v;
    }
    return out;
  }

  /// What the colleagues took back of their cards' notes, applied to the
  /// copies kept here: the text of one of before left empty, whatever came
  /// since. True when one was.
  bool applyTakenNoteHides() {
    var changed = false;
    final hides = [
      for (final r in _db.select(
        'SELECT sahip, not_key, surum FROM taken_note_hide',
      ))
        if (Hlc.tryParse(r['surum']) case final v?)
          (
            owner: r['sahip'] as String,
            key: r['not_key'] as String,
            version: v,
          ),
    ];
    for (final h in hides) {
      final parts = h.key.split(':');
      if (parts.length < 2) continue;
      switch (parts.first) {
        case 'kartNotu' || 'dosyaNotu':
          final card = clientCard(parts[1]);
          if (card == null || card.person != h.owner) continue;
          var next = card;
          if (parts.first == 'kartNotu') {
            if (card.note.isNotEmpty && card.versionOf('not') <= h.version) {
              next = card.copyWith(note: '', noteSecret: true);
            }
          } else if (parts.length >= 3) {
            final n = card.caseNotes[parts.sublist(2).join(':')];
            if (n != null && n.text.isNotEmpty && n.versionOf <= h.version) {
              next = card.copyWith(
                caseNotes: {
                  ...card.caseNotes,
                  parts.sublist(2).join(':'): CaseNote(
                    '',
                    n.at,
                    by: n.by,
                    version: n.version,
                    secret: true,
                  ),
                },
              );
            }
          }
          if (identical(next, card)) continue;
          // As it was kept, its versions as they were: only the text gone.
          _putClient(
            Client.fromJson({
              ...card.toJson(),
              'not': next.note,
              if (next.noteSecret) 'notGizli': true,
              'dosyaNotlari': {
                for (final e in next.caseNotes.entries) e.key: e.value.toJson(),
              },
            })!,
          );
          changed = true;
        case 'aciklama':
          final r = clientRecord(parts[1]);
          if (r == null ||
              r.person != h.owner ||
              LedgerBook.isProjected(r) ||
              r.text('aciklama').isEmpty ||
              LedgerBook.versionOf(r, 'bilgi') > h.version) {
            continue;
          }
          _putRecord(
            ClientRecord.fromJson({
              ...r.toJson(),
              'veri': {...r.data, 'aciklama': '', 'aciklamaGizli': true},
            })!,
          );
          changed = true;
      }
    }
    return changed;
  }

  /// [owner]'s notes of [task]'s case [caseKey] kept here, as they came:
  /// standing, not taken back.
  List<Map<String, Object?>> taskNotes(
    String owner,
    String task,
    String caseKey,
  ) => [
    for (final r in _db.select(
      'SELECT satir FROM task_note WHERE sahip=? AND gorev=? AND dosya=? '
      'AND satir IS NOT NULL ORDER BY id',
      [owner, task, caseKey],
    ))
      ?PortalAgendaVersions._map(r['satir']),
  ];

  /// Every note kept of [owner]'s tasks: (task, case) → id → its versions,
  /// and what was taken back of it.
  List<({String task, String caseKey, String id, Hlc? body, Hlc? hidden})>
  taskNotesHeld(String owner) => [
    for (final r in _db.select(
      'SELECT gorev, dosya, id, surumler, gizlenen FROM task_note WHERE sahip=?',
      [owner],
    ))
      (
        task: r['gorev'] as String,
        caseKey: r['dosya'] as String,
        id: r['id'] as String,
        body: PortalAgendaVersions._agendaGroups.versionsOf(
          r['surumler'],
          legacy: null,
        )['govde'],
        hidden: Hlc.tryParse(r['gizlenen']),
      ),
  ];

  /// [rows] of [owner]'s [task]'s case [caseKey] taken note by note, group
  /// by group (R1): each the later version's; one taken off by the later
  /// lifecycle; one taken back ([hidden]: id → version) gone, kept so that
  /// no copy of before brings it back. True when anything changed.
  bool mergeTaskNotes(
    String owner,
    String task,
    String caseKey,
    List<Map> rows,
    Map<String, Hlc> hidden, {
    Map<String, Hlc> removed = const {},
  }) {
    var changed = false;
    final g = PortalAgendaVersions._agendaGroups;
    _transaction(() {
      Map<String, Object?>? keptRow(String id) {
        final r = _db.select(
          'SELECT satir, surumler, gizlenen FROM task_note WHERE sahip=? '
          'AND gorev=? AND dosya=? AND id=?',
          [owner, task, caseKey, id],
        );
        return r.isEmpty ? null : {for (final c in r.first.keys) c: r.first[c]};
      }

      void write(
        String id,
        Map<String, Object?>? row,
        String versions,
        String hid,
      ) {
        _db.execute(
          'INSERT OR REPLACE INTO task_note(sahip, gorev, dosya, id, satir, '
          'surumler, gizlenen) VALUES(?,?,?,?,?,?,?)',
          [
            owner,
            task,
            caseKey,
            id,
            row == null ? null : jsonEncode(row),
            versions,
            hid,
          ],
        );
      }

      for (final raw in rows) {
        if (raw['id'] is! String) continue;
        final id = raw['id'] as String;
        final row = PortalAgendaVersions._agendaRow(raw);
        final versions = g.versionsOf(raw['surumler'], legacy: null);
        final life = PortalAgendaVersions._lifeOf(raw['surumler'], null);
        final kept = keptRow(id);
        final hid = Hlc.tryParse(kept?['gizlenen']);
        // Taken back: no copy of before comes back.
        if (hid != null && versions['govde']! <= hid) continue;
        // Taken off there after this copy: it stays off.
        if (kept != null &&
            kept['satir'] == null &&
            PortalAgendaVersions._lifeOf(kept['surumler'], null) >= life &&
            hid == null) {
          continue;
        }
        if (kept == null || kept['satir'] == null) {
          write(
            id,
            row,
            FieldGroups.encode({...versions, 'yasam': life}),
            '${hid ?? ''}',
          );
          changed = true;
          continue;
        }
        final mineRow = PortalAgendaVersions._map(kept['satir'])!;
        final mv = g.versionsOf(kept['surumler'], legacy: null);
        final ml = PortalAgendaVersions._lifeOf(kept['surumler'], null);
        final m = g.merge(mineRow, mv, row, versions);
        final next = FieldGroups.encode({
          ...m.versions,
          'yasam': life > ml ? life : ml,
        });
        if (next == kept['surumler'] &&
            Hlc.canonical(m.row) == Hlc.canonical(mineRow)) {
          continue;
        }
        write(id, m.row, next, '${hid ?? ''}');
        changed = true;
      }
      for (final MapEntry(key: id, value: v) in removed.entries) {
        final kept = keptRow(id);
        if (kept == null || kept['satir'] == null) {
          if (kept == null) {
            write(id, null, FieldGroups.encode({'yasam': v}), '');
            changed = true;
          }
          continue;
        }
        final life = PortalAgendaVersions._lifeOf(kept['surumler'], null);
        if (life >= v) continue;
        final versions = g.versionsOf(kept['surumler'], legacy: null);
        write(
          id,
          null,
          FieldGroups.encode({...versions, 'yasam': v}),
          '${kept['gizlenen'] ?? ''}',
        );
        changed = true;
      }
      for (final MapEntry(key: id, value: v) in hidden.entries) {
        final kept = keptRow(id);
        final hid = Hlc.tryParse(kept?['gizlenen']);
        if (hid != null && hid >= v) continue;
        final body = kept == null
            ? null
            : g.versionsOf(kept['surumler'], legacy: null)['govde'];
        // Made open again after it, there: the copy that came stays.
        final open = body != null && body > v && kept!['satir'] != null;
        write(
          id,
          open ? PortalAgendaVersions._map(kept['satir']) : null,
          '${kept?['surumler'] ?? FieldGroups.encode({})}',
          '$v',
        );
        changed = true;
      }
    });
    return changed;
  }

  /// [owner]'s notes of the tasks no longer given to this person, or done:
  /// forgotten here. [still] the (task, case) pairs that stand.
  bool forgetTaskNotes(String owner, Set<String> still) {
    var changed = false;
    for (final r in _db.select(
      'SELECT DISTINCT gorev, dosya FROM task_note WHERE sahip=?',
      [owner],
    )) {
      final pair = '${r['gorev']}|${r['dosya']}';
      if (still.contains(pair)) continue;
      // What was taken back is kept; the rest goes.
      _db.execute(
        "UPDATE task_note SET satir=NULL WHERE sahip=? AND gorev=? AND dosya=?",
        [owner, r['gorev'], r['dosya']],
      );
      changed = true;
    }
    return changed;
  }

  /// Whether the notes an older Folio put in [task]'s case [caseKey]'s
  /// package here are still to be taken out ('bekliyor'), or were ('tamam').
  String? taskNotesCleaning(String task, String caseKey) {
    final r = _db.select(
      'SELECT durum FROM task_note_clean WHERE gorev=? AND dosya=?',
      [task, caseKey],
    );
    return r.isEmpty ? null : r.first['durum'] as String;
  }

  void setTaskNotesCleaning(String task, String caseKey, String state) =>
      _db.execute(
        'INSERT OR REPLACE INTO task_note_clean(gorev, dosya, durum) '
        'VALUES(?,?,?)',
        [task, caseKey, state],
      );

  List<({String task, String caseKey})> get taskNotesToClean => [
    for (final r in _db.select(
      "SELECT gorev, dosya FROM task_note_clean WHERE durum='bekliyor'",
    ))
      (task: r['gorev'] as String, caseKey: r['dosya'] as String),
  ];
}

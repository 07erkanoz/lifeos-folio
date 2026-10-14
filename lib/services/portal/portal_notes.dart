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
  void recordHide(String noteKey, String scope, Hlc version) {
    _db.execute(
      'INSERT OR IGNORE INTO note_hide(not_key, kapsam, surum) VALUES(?,?,?)',
      [noteKey, scope, '$version'],
    );
    _scrubProposalsOf(noteKey, version);
  }

  /// The text of the proposals of [noteKey]'s note made seeing it as it was
  /// till [version] gone: it is secret now.
  void _scrubProposalsOf(String noteKey, Hlc version) {
    final of = PortalProposals.proposalOfNote(noteKey);
    if (of != null) {
      scrubProposals(of.kind, of.target, caseKey: of.caseKey, upTo: version);
    }
  }

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
  bool recordHold(
    String noteKey,
    String device,
    String person,
    String scope, {
    Hlc? held,
    Hlc? applied,
    bool gone = false,
    bool latest = false,
  }) {
    final before = _db.select(
      'SELECT tuttu, surum, uygulanan FROM note_hold WHERE not_key=? '
      'AND cihaz=? AND kapsam=?',
      [noteKey, device, scope],
    );
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
    // A report that says how it is now, by its version: the latest one
    // stands, clean or not ([held] its version, [applied] when clean).
    if (latest) {
      final was = Hlc.tryParse(now['surum']);
      if (held != null && (was == null || held > was)) {
        _db.execute(
          'UPDATE note_hold SET surum=?, uygulanan=? WHERE not_key=? '
          'AND cihaz=? AND kapsam=?',
          ['$held', applied == null ? '' : '$applied', noteKey, device, scope],
        );
      }
      final after = _db.select(
        'SELECT tuttu, surum, uygulanan FROM note_hold WHERE not_key=? '
        'AND cihaz=? AND kapsam=?',
        [noteKey, device, scope],
      );
      return before.isEmpty ||
          Hlc.canonical({
                for (final c in before.first.keys) c: before.first[c],
              }) !=
              Hlc.canonical({
                for (final c in after.first.keys) c: after.first[c],
              });
    }
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
    final after = _db.select(
      'SELECT tuttu, surum, uygulanan FROM note_hold WHERE not_key=? '
      'AND cihaz=? AND kapsam=?',
      [noteKey, device, scope],
    );
    return before.isEmpty ||
        Hlc.canonical({
              for (final c in before.first.keys) c: before.first[c],
            }) !=
            Hlc.canonical({
              for (final c in after.first.keys) c: after.first[c],
            });
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
    // The cases' accounts shared with this person, for their other devices
    // (R8): only while they may see the money.
    if (PortalDatabase.clientMoneyAllowed?.call() ?? true)
      'paylasilanDefterler': sharedLedgersExport(),
    // The colleagues' tasks' notes that came here, for this person's other
    // devices: note by note, with what was taken back and off.
    'gorevNotlari': [
      for (final r in _db.select('SELECT * FROM task_note'))
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
          // An older package's cleaning: the latest report stands.
          latest: (r['not_key'] as String).startsWith('eski:'),
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
      if (PortalDatabase.clientMoneyAllowed?.call() ?? true) {
        sharedLedgersMerge(theirs['paylasilanDefterler']);
      }
      final scopes =
          <
            String,
            ({List<Map> rows, Map<String, Hlc> hidden, Map<String, Hlc> off})
          >{};
      for (final r in theirs['gorevNotlari'] as List? ?? const []) {
        if (r is! Map ||
            r['sahip'] is! String ||
            r['gorev'] is! String ||
            r['dosya'] is! String ||
            r['id'] is! String) {
          continue;
        }
        final s = scopes.putIfAbsent(
          '${r['sahip']}|${r['gorev']}|${r['dosya']}',
          () => (rows: [], hidden: {}, off: {}),
        );
        final versions = PortalAgendaVersions._map(r['surumler']) ?? const {};
        final row = PortalAgendaVersions._map(r['satir']);
        if (row != null) {
          s.rows.add({...row, 'id': r['id'], 'surumler': r['surumler']});
        }
        if (Hlc.tryParse(r['gizlenen']) case final h?) s.hidden[r['id']] = h;
        if (Hlc.tryParse(versions['silindi']) case final o?) {
          s.off[r['id'] as String] = o;
        }
      }
      for (final MapEntry(:key, :value) in scopes.entries) {
        final parts = key.split('|');
        mergeTaskNotes(
          parts[0],
          parts[1],
          parts.sublist(2).join('|'),
          value.rows,
          value.hidden,
          removed: value.off,
        );
      }
    });
    final changed = Hlc.canonical(noteTrackingExport()) != before;
    if (changed) applyTakenNoteHides();
    return changed;
  }

  // A colleague's notes.

  /// That [owner] took back [noteKey] at [version]: kept for good, so that
  /// no copy of it of before comes back here.
  void takeNoteHide(String owner, String noteKey, Hlc version) {
    _db.execute(
      'INSERT OR IGNORE INTO taken_note_hide(sahip, not_key, surum) '
      'VALUES(?,?,?)',
      [owner, noteKey, '$version'],
    );
    _scrubProposalsOf(noteKey, version);
  }

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

  /// The task and case of every note [person] held, or may have, of this
  /// person's tasks: "task|case".
  Set<String> holdScopesOf(String person) => {
    for (final r in _db.select(
      "SELECT DISTINCT kapsam FROM note_hold WHERE kisi=? AND kapsam LIKE 'gorev:%'",
      [person],
    ))
      (r['kapsam'] as String).substring('gorev:'.length),
  };

  /// The task and case of every note kept here of [owner]'s: "task|case".
  Set<String> receivedScopesOf(String owner) => {
    for (final r in _db.select(
      'SELECT DISTINCT gorev, dosya FROM task_note WHERE sahip=?',
      [owner],
    ))
      '${r['gorev']}|${r['dosya']}',
    for (final r in _db.select('SELECT gorev, dosya FROM task_note_clean'))
      '${r['gorev']}|${r['dosya']}',
  };

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
    // Those of the accounts shared with this person too (R8).
    var changed = applyTakenHidesToShared();
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
      // What is kept of one note: its row (null while taken back or off),
      // its groups' versions and lifecycle, when it was taken off
      // (`silindi`) and taken back (`gizlenen`), each apart.
      ({
        Map<String, Object?>? row,
        Map<String, Hlc> versions,
        Hlc life,
        Hlc? off,
        Hlc? hid,
      })?
      kept(String id) {
        final r = _db.select(
          'SELECT satir, surumler, gizlenen FROM task_note WHERE sahip=? '
          'AND gorev=? AND dosya=? AND id=?',
          [owner, task, caseKey, id],
        );
        if (r.isEmpty) return null;
        final v = PortalAgendaVersions._map(r.first['surumler']) ?? const {};
        return (
          row: PortalAgendaVersions._map(r.first['satir']),
          versions: g.versionsOf(v, legacy: null),
          life: PortalAgendaVersions._lifeOf(v, null),
          off: Hlc.tryParse(v['silindi']),
          hid: Hlc.tryParse(r.first['gizlenen']),
        );
      }

      void write(
        String id,
        Map<String, Object?>? row,
        Map<String, Hlc> versions,
        Hlc life,
        Hlc? off,
        Hlc? hid,
      ) {
        final now = (
          row: row,
          versions: versions,
          life: life,
          off: off,
          hid: hid,
        );
        final was = kept(id);
        if (was != null &&
            Hlc.canonical(was.row) == Hlc.canonical(now.row) &&
            FieldGroups.encode(was.versions) == FieldGroups.encode(versions) &&
            was.life == life &&
            was.off == off &&
            was.hid == hid) {
          return;
        }
        _db.execute(
          'INSERT OR REPLACE INTO task_note(sahip, gorev, dosya, id, satir, '
          'surumler, gizlenen) VALUES(?,?,?,?,?,?,?)',
          [
            owner,
            task,
            caseKey,
            id,
            row == null ? null : jsonEncode(row),
            jsonEncode({
              for (final e in versions.entries) e.key: '${e.value}',
              'yasam': '$life',
              'silindi': ?off?.toString(),
            }),
            hid == null ? '' : '$hid',
          ],
        );
        changed = true;
      }

      Hlc? later(Hlc? a, Hlc? b) =>
          a == null ? b : (b == null || a >= b ? a : b);

      for (final raw in rows) {
        if (raw['id'] is! String) continue;
        final id = raw['id'] as String;
        final row = PortalAgendaVersions._agendaRow(raw);
        final versions = g.versionsOf(raw['surumler'], legacy: null);
        final life = PortalAgendaVersions._lifeOf(raw['surumler'], null);
        final k = kept(id);
        // Each mark stands on its own: taken back unless its text and
        // secrecy are newer than that; taken off unless it was brought
        // back after.
        if (k?.hid != null && versions['govde']! <= k!.hid!) continue;
        if (k?.off != null && life <= k!.off!) continue;
        if (k == null || k.row == null) {
          write(id, row, versions, later(life, k?.life)!, k?.off, k?.hid);
          continue;
        }
        final m = g.merge(k.row!, k.versions, row, versions);
        write(id, m.row, m.versions, later(life, k.life)!, k.off, k.hid);
      }
      for (final MapEntry(key: id, value: v) in removed.entries) {
        final k = kept(id);
        final off = later(k?.off, v)!;
        final life = later(k?.life, v)!;
        // Brought back after it was taken off, there: it stands.
        final stands = k?.row != null && k!.life > off;
        write(
          id,
          stands ? k.row : null,
          k?.versions ?? g.versionsOf(null, legacy: null),
          life,
          off,
          k?.hid,
        );
      }
      for (final MapEntry(key: id, value: v) in hidden.entries) {
        final k = kept(id);
        final hid = later(k?.hid, v)!;
        // Made open again after it, there: the copy that came stays.
        final stands = k?.row != null && k!.versions['govde']! > hid;
        write(
          id,
          stands ? k.row : null,
          k?.versions ?? g.versionsOf(null, legacy: null),
          k?.life ?? const Hlc(0, 0, Hlc.migrated),
          k?.off,
          hid,
        );
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

  /// [owner]'s [task]'s case [caseKey]'s notes, its task done there: gone
  /// here, what was taken back of them kept. True when one was.
  bool forgetTaskScope(String owner, String task, String caseKey) {
    final had = _db.select(
      'SELECT 1 FROM task_note WHERE sahip=? AND gorev=? AND dosya=? '
      'AND satir IS NOT NULL',
      [owner, task, caseKey],
    );
    if (had.isEmpty) return false;
    _db.execute(
      'UPDATE task_note SET satir=NULL WHERE sahip=? AND gorev=? AND dosya=?',
      [owner, task, caseKey],
    );
    return true;
  }

  /// Every task and case of which notes of a giver's are kept here.
  List<({String task, String caseKey})> get taskNoteScopes => [
    for (final r in _db.select('SELECT DISTINCT gorev, dosya FROM task_note'))
      (task: r['gorev'] as String, caseKey: r['dosya'] as String),
  ];

  /// Whether the notes an older Folio put in [task]'s case [caseKey]'s
  /// package here are still to be taken out ('bekliyor'), or were ('tamam').
  String? taskNotesCleaning(String task, String caseKey) {
    final r = _db.select(
      'SELECT durum FROM task_note_clean WHERE gorev=? AND dosya=?',
      [task, caseKey],
    );
    return r.isEmpty ? null : r.first['durum'] as String;
  }

  /// Each change of it a version of its own, for the giver to take the
  /// latest of what is said of it.
  void setTaskNotesCleaning(String task, String caseKey, String state) {
    if (taskNotesCleaning(task, caseKey) == state) return;
    _db.execute(
      'INSERT OR REPLACE INTO task_note_clean(gorev, dosya, durum, surum) '
      'VALUES(?,?,?,?)',
      [task, caseKey, state, '${SyncClock.of(this).tick()}'],
    );
  }

  /// The version of what was last said of [task]'s case's cleaning.
  Hlc? taskNotesCleaningVersion(String task, String caseKey) {
    final r = _db.select(
      'SELECT surum FROM task_note_clean WHERE gorev=? AND dosya=?',
      [task, caseKey],
    );
    return r.isEmpty ? null : Hlc.tryParse(r.first['surum']);
  }

  List<({String task, String caseKey})> get taskNotesToClean => [
    for (final r in _db.select(
      "SELECT gorev, dosya FROM task_note_clean WHERE durum='temizlenecek'",
    ))
      (task: r['gorev'] as String, caseKey: r['dosya'] as String),
  ];
}

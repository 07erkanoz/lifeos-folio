part of 'portal_database.dart';

/// The agenda kept alike field group by field group (docs/senkron-plan.md
/// R1, R5): its own rows, the lawyer's decisions on the notices' deadlines
/// and whom they act for in a case. Each group has a version of its own;
/// a row taken off has a lifecycle version, so that a change made
/// elsewhere without seeing it does not bring it back, only "Geri al".
extension PortalAgendaVersions on PortalDatabase {
  static const _agendaGroups = FieldGroups({
    'tur': ['kind'],
    'baslik': ['title'],
    'govde': ['body'],
    'zaman': ['at', 'all_day'],
    'tamam': ['done'],
    'bag': ['case_key', 'hearing_key'],
  });

  /// A deadline's confirmation is one group: the inputs it was given for
  /// and when, its day going with them.
  static const _decisionGroups = FieldGroups({
    'tamam': ['done'],
    'gun': ['manual_day'],
    'baslik': ['title_override'],
    'govde': ['body_override'],
    'onay': ['confirmed_inputs', 'confirmed_at'],
    'kaldir': ['dismissed'],
  });

  static const _life = 'yasam';

  static String? _text(Object? v) => v is String ? v : null;
  static int _flag(Object? v) => v == 1 || v == true ? 1 : 0;

  static Map<String, Object?> _agendaRow(Map r) => {
    'id': '${r['id']}',
    'kind': '${r['kind']}',
    'title': '${r['title'] ?? ''}',
    'body': '${r['body'] ?? ''}',
    'at': _text(r['at']),
    'all_day': _flag(r['all_day']),
    'done': _flag(r['done']),
    'case_key': _text(r['case_key']),
    'hearing_key': _text(r['hearing_key']),
  };

  static Map<String, Object?>? _map(Object? text) {
    if (text is! String) return null;
    try {
      final j = jsonDecode(text);
      return j is Map ? Map<String, Object?>.from(j) : null;
    } on FormatException {
      return null;
    }
  }

  static Hlc _lifeOf(Object? versions, Object? legacy) {
    final map = versions is String ? _map(versions) : versions;
    return (map is Map ? Hlc.tryParse(map[_life]) : null) ??
        Hlc.fromLegacy(legacy);
  }

  _AgendaCopy _live(Map r) => _AgendaCopy(
    live: true,
    life: _lifeOf(r['surumler'], r['updated']),
    row: _agendaRow(r),
    versions: _agendaGroups.versionsOf(r['surumler'], legacy: r['updated']),
    updated: '${r['updated'] ?? ''}',
  );

  _AgendaCopy _removed(Object? id, Object? at, Object? version, Object? row) {
    final kept = row is Map ? row : _map(row);
    return _AgendaCopy(
      live: false,
      life: Hlc.tryParse(version) ?? Hlc.fromLegacy(at),
      row: kept == null ? null : _agendaRow({...kept, 'id': id}),
      versions: kept == null
          ? null
          : _agendaGroups.versionsOf(kept['surumler'], legacy: kept['updated']),
      updated: '${kept?['updated'] ?? at ?? ''}',
      at: _text(at),
    );
  }

  /// [id] as it is kept here: standing, taken off, or not at all.
  _AgendaCopy? _agendaHere(String id) {
    final rows = _db.select('SELECT * FROM agenda WHERE id=?', [id]);
    if (rows.isNotEmpty) return _live(rows.first);
    final gone = _db.select(
      'SELECT at, surum, satir FROM agenda_removed WHERE id=?',
      [id],
    );
    if (gone.isEmpty) return null;
    final g = gone.first;
    return _removed(id, g['at'], g['surum'], g['satir']);
  }

  void _agendaWrite(String id, _AgendaCopy c) {
    final versions = FieldGroups.encode({...?c.versions, _life: c.life});
    if (c.live) {
      final r = c.row!;
      _db.execute(
        '''INSERT OR REPLACE INTO agenda
           (id, kind, title, body, at, all_day, done, case_key, hearing_key,
            updated, surumler) VALUES(?,?,?,?,?,?,?,?,?,?,?)''',
        [
          id,
          r['kind'],
          r['title'],
          r['body'],
          r['at'],
          r['all_day'],
          r['done'],
          r['case_key'],
          r['hearing_key'],
          c.updated,
          versions,
        ],
      );
      _db.execute('DELETE FROM agenda_removed WHERE id=?', [id]);
      return;
    }
    _db.execute('DELETE FROM agenda WHERE id=?', [id]);
    _db.execute(
      'INSERT OR REPLACE INTO agenda_removed(id, at, surum, satir) '
      'VALUES(?,?,?,?)',
      [
        id,
        c.at ?? c.updated,
        '${c.life}',
        c.row == null
            ? null
            : jsonEncode({
                ...c.row!,
                'updated': c.updated,
                'surumler': versions,
              }),
      ],
    );
  }

  /// [item] kept as the lawyer wrote it here: each group changed given a
  /// new version, the others keeping theirs; a new row all of them. One
  /// taken off is not written: only [restoreAgenda] brings it back.
  bool _agendaSave(AgendaItem item) {
    final here = _agendaHere(item.id);
    if (here != null && !here.live) return false;
    final row = _agendaRow({
      'id': item.id,
      'kind': item.kind,
      'title': item.title,
      'body': item.body,
      'at': item.at?.toIso8601String(),
      'all_day': item.allDay,
      'done': item.done,
      'case_key': item.caseKey,
      'hearing_key': item.hearingKey,
    });
    final clock = SyncClock.of(this);
    final Map<String, Hlc> versions;
    final Hlc life;
    if (here == null) {
      life = clock.tick();
      versions = {for (final g in _agendaGroups.groups.keys) g: life};
    } else {
      versions = _agendaGroups.stamp(here.row, here.versions!, row, clock.tick);
      life = here.life;
    }
    _agendaWrite(
      item.id,
      _AgendaCopy(
        live: true,
        life: life,
        row: row,
        versions: versions,
        updated: item.updated.toIso8601String(),
      ),
    );
    return true;
  }

  /// [id] taken off: kept with what it said and a new lifecycle version,
  /// for "Geri al" and for the lawyer's other devices.
  void _agendaRemove(String id) {
    final here = _agendaHere(id);
    if (here != null && !here.live) return;
    final now = DateTime.now().toIso8601String();
    _agendaWrite(
      id,
      _AgendaCopy(
        live: false,
        life: SyncClock.of(this).tick(),
        row: here?.row,
        versions: here?.versions,
        updated: here?.updated ?? now,
        at: now,
      ),
    );
  }

  /// [id], taken off, brought back as it was, with whatever was changed of
  /// it since on another device (R5). False when there is nothing to.
  bool restoreAgenda(String id) {
    final here = _agendaHere(id);
    if (here == null || here.live || here.row == null) return false;
    _agendaWrite(
      id,
      _AgendaCopy(
        live: true,
        life: SyncClock.of(this).tick(),
        row: here.row,
        versions: here.versions,
        updated: DateTime.now().toIso8601String(),
      ),
    );
    PortalDatabase.changed?.call();
    return true;
  }

  /// The rows taken off, as another device takes them.
  List<Map<String, Object?>> _agendaRemovedExport() => [
    for (final r in _db.select(
      'SELECT id, at, surum, satir FROM agenda_removed',
    ))
      {for (final c in r.keys) c: r[c]},
  ];

  /// Another device's rows and those it took off, taken group by group:
  /// true when anything here changed.
  bool _agendaMergeRows(Map theirs) {
    final came = <String, _AgendaCopy>{};
    final gone = theirs['silinenler'];
    if (gone is List) {
      for (final t in gone) {
        if (t is! Map || t['id'] is! String) continue;
        came[t['id'] as String] = _removed(
          t['id'],
          t['at'],
          t['surum'],
          t['satir'],
        );
      }
    } else if (theirs['silinen'] case final Map old) {
      // An older Folio's: when each was taken off, nothing more.
      for (final e in old.entries) {
        came['${e.key}'] = _removed(e.key, e.value, null, null);
      }
    }
    for (final r in theirs['satirlar'] as List? ?? const []) {
      if (r is! Map || r['id'] is! String || r['kind'] is! String) continue;
      final id = r['id'] as String;
      final copy = _live(r);
      came[id] = came[id] == null ? copy : _AgendaCopy.join(came[id]!, copy);
    }
    var changed = false;
    for (final MapEntry(key: id, value: copy) in came.entries) {
      for (final v in [copy.life, ...?copy.versions?.values]) {
        SyncClock.observe(this, v);
      }
      final here = _agendaHere(id);
      final next = here == null ? copy : _AgendaCopy.join(here, copy);
      if (here != null && next.sameAs(here)) continue;
      // A row never seen here, taken off there, with nothing of it: only
      // its mark is kept.
      _agendaWrite(id, next);
      changed = true;
    }
    return changed;
  }

  static Map<String, Object?> _decisionRow(Map r) => {
    'deadline_id': '${r['deadline_id']}',
    'done': _flag(r['done']),
    'manual_day': _text(r['manual_day']),
    'title_override': _text(r['title_override']),
    'body_override': _text(r['body_override']),
    'confirmed_inputs': _text(r['confirmed_inputs']),
    'confirmed_at': _text(r['confirmed_at']),
    'confirmed_day': _text(r['confirmed_day']),
    'dismissed': _flag(r['dismissed']),
  };

  void _decisionWrite(
    Map<String, Object?> r,
    Map<String, Hlc> versions,
    String updated,
  ) => _db.execute(
    '''INSERT OR REPLACE INTO deadline_user(deadline_id, done, manual_day,
       title_override, body_override, confirmed_inputs, confirmed_at,
       dismissed, updated, confirmed_day, surumler)
       VALUES(?,?,?,?,?,?,?,?,?,?,?)''',
    [
      r['deadline_id'],
      r['done'],
      r['manual_day'],
      r['title_override'],
      r['body_override'],
      r['confirmed_inputs'],
      r['confirmed_at'],
      r['dismissed'],
      updated,
      r['confirmed_day'],
      FieldGroups.encode(versions),
    ],
  );

  /// [u] kept as decided here: only what it changed gets a new version. A
  /// decision not kept before is weighed against none, so that what it
  /// leaves as it was never outweighs another device's word on it.
  void _decisionSave(DeadlineUser u) {
    final row = _decisionRow({
      'deadline_id': u.deadlineId,
      'done': u.done,
      'manual_day': u.manualDay,
      'title_override': u.titleOverride,
      'body_override': u.bodyOverride,
      'confirmed_inputs': u.confirmedInputs,
      'confirmed_at': u.confirmedAt?.toIso8601String(),
      'confirmed_day': u.confirmedDay,
      'dismissed': u.dismissed,
    });
    final here = _db.select('SELECT * FROM deadline_user WHERE deadline_id=?', [
      u.deadlineId,
    ]);
    final before = here.isEmpty
        ? _decisionRow({'deadline_id': u.deadlineId})
        : _decisionRow(here.first);
    final kept = here.isEmpty
        ? _decisionGroups.versionsOf(null, legacy: null)
        : _decisionGroups.versionsOf(
            here.first['surumler'],
            legacy: here.first['updated'],
          );
    _decisionWrite(
      row,
      _decisionGroups.stamp(before, kept, row, SyncClock.of(this).tick),
      DateTime.now().toIso8601String(),
    );
  }

  /// Another device's decisions, taken group by group; a confirmation's
  /// day goes with it, and one only this side knows is kept.
  bool _decisionMerge(Map theirs) {
    var changed = false;
    for (final r in theirs['kararlar'] as List? ?? const []) {
      if (r is! Map || r['deadline_id'] is! String) continue;
      final t = _decisionRow(r);
      final tv = _decisionGroups.versionsOf(
        r['surumler'],
        legacy: r['updated'],
      );
      for (final v in tv.values) {
        SyncClock.observe(this, v);
      }
      final here = _db.select(
        'SELECT * FROM deadline_user WHERE deadline_id=?',
        [t['deadline_id']],
      );
      if (here.isEmpty) {
        _decisionWrite(t, tv, '${r['updated'] ?? ''}');
        changed = true;
        continue;
      }
      final m = _decisionRow(here.first);
      final mv = _decisionGroups.versionsOf(
        here.first['surumler'],
        legacy: here.first['updated'],
      );
      final merged = _decisionGroups.merge(m, mv, t, tv);
      final row = merged.row;
      String onay(Map x) => Hlc.canonical(_decisionGroups.valueOf(x, 'onay'));
      if (onay(row) == onay(t)) {
        row['confirmed_day'] = onay(t) != onay(m)
            ? t['confirmed_day']
            : m['confirmed_day'] ?? t['confirmed_day'];
      }
      if (Hlc.canonical([row, FieldGroups.encode(merged.versions)]) ==
          Hlc.canonical([m, FieldGroups.encode(mv)])) {
        continue;
      }
      final later =
          (DateTime.tryParse('${r['updated']}') ?? DateTime(2000)).isAfter(
            DateTime.tryParse('${here.first['updated']}') ?? DateTime(2000),
          )
          ? '${r['updated']}'
          : '${here.first['updated'] ?? ''}';
      _decisionWrite(row, merged.versions, later);
      changed = true;
    }
    return changed;
  }

  /// Another device's word of whom the lawyer acts for in each case: the
  /// later version's; for the same, the same on every device. The notices
  /// of each case changed, to be reckoned again.
  Set<String> _representationMerge(Map theirs) {
    final touched = <String>{};
    for (final r in theirs['temsil'] as List? ?? const []) {
      if (r is! Map || r['case_key'] is! String || r['json'] is! String) {
        continue;
      }
      final key = r['case_key'] as String;
      final tv = Hlc.tryParse(r['surum']) ?? Hlc.fromLegacy(r['updated']);
      SyncClock.observe(this, tv);
      final here = _db.select(
        'SELECT json, updated, surum FROM case_representation WHERE case_key=?',
        [key],
      );
      if (here.isNotEmpty) {
        final mv =
            Hlc.tryParse(here.first['surum']) ??
            Hlc.fromLegacy(here.first['updated']);
        if (Hlc.decide(tv, r['json'], mv, here.first['json']) <= 0) continue;
      }
      _db.execute(
        'INSERT OR REPLACE INTO case_representation(case_key, json, updated, '
        'surum) VALUES(?,?,?,?)',
        [key, r['json'], '${r['updated'] ?? ''}', '$tv'],
      );
      for (final n in _db.select('SELECT id FROM uets WHERE case_key=?', [
        key,
      ])) {
        touched.add(n['id'] as String);
      }
    }
    return touched;
  }
}

/// One copy of an agenda row: standing or taken off, with what it says
/// and its versions (none for an older Folio's mark of one taken off).
class _AgendaCopy {
  const _AgendaCopy({
    required this.live,
    required this.life,
    required this.updated,
    this.row,
    this.versions,
    this.at,
  });

  final bool live;
  final Hlc life;
  final Map<String, Object?>? row;
  final Map<String, Hlc>? versions;

  /// When it was last written, as the device's clock said.
  final String updated;

  /// When it was taken off.
  final String? at;

  /// [mine] and [theirs] made one: what it says group by group, whether it
  /// stands by the later lifecycle version. For the same one, taken off
  /// wins, as it did before versions.
  static _AgendaCopy join(_AgendaCopy mine, _AgendaCopy theirs) {
    Map<String, Object?>? row;
    Map<String, Hlc>? versions;
    if (mine.row != null && theirs.row != null) {
      final m = PortalAgendaVersions._agendaGroups.merge(
        mine.row!,
        mine.versions!,
        theirs.row!,
        theirs.versions!,
      );
      (row, versions) = (m.row, m.versions);
    } else if (mine.row != null) {
      (row, versions) = (mine.row, mine.versions);
    } else {
      (row, versions) = (theirs.row, theirs.versions);
    }
    final byLife = theirs.life.compareTo(mine.life);
    final theirsLive = byLife > 0 || (byLife == 0 && !theirs.live && mine.live);
    final life = theirsLive ? theirs : mine;
    DateTime when(String s) => DateTime.tryParse(s) ?? DateTime(2000);
    final updated = when(theirs.updated).isAfter(when(mine.updated))
        ? theirs.updated
        : mine.updated;
    return _AgendaCopy(
      live: life.live && row != null,
      life: life.life,
      row: row,
      versions: versions,
      updated: updated,
      at: life.live ? null : (life.at ?? updated),
    );
  }

  /// Whether [other] says the same: when it was written aside.
  bool sameAs(_AgendaCopy other) =>
      Hlc.canonical(_said) == Hlc.canonical(other._said);

  Object? get _said => {
    'live': live,
    'life': '$life',
    'row': row,
    'versions': versions == null ? null : FieldGroups.encode(versions!),
  };
}

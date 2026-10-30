part of 'portal_database.dart';

/// What the lawyer's AI program left of a case (lib/services/ai/
/// ai_memory.dart): its conversations, the findings the lawyer kept and
/// the drafts it wrote, each a row of its own with its version. A row taken
/// off keeps its id and version and loses its text, for the lawyer's other
/// devices not to bring it back (Senkron's `yapay-zeka` part, between the
/// lawyer's own devices alone).
extension PortalAi on PortalDatabase {
  static const _tables = '''
    CREATE TABLE IF NOT EXISTS ai_record (
      id TEXT PRIMARY KEY, tur TEXT NOT NULL, case_key TEXT NOT NULL,
      json TEXT, surum TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS ai_record_case ON ai_record(case_key, tur);
  ''';

  /// The records of [kind] (`sohbet`, `bulgu`, `taslak`), of [caseKey] or
  /// of every case; what was taken off is not among them.
  List<Map<String, Object?>> aiRecords(String kind, {String? caseKey}) => [
    for (final r in _db.select(
      'SELECT id, case_key, json FROM ai_record WHERE tur=? AND json IS NOT '
      'NULL${caseKey == null ? '' : ' AND case_key=?'}',
      [kind, ?caseKey],
    ))
      if (_aiJson(r['json']) case final json?)
        {...json, 'id': r['id'], 'dosya': r['case_key']},
  ];

  static Map<String, Object?>? _aiJson(Object? text) {
    if (text is! String) return null;
    try {
      final json = jsonDecode(text);
      return json is Map ? json.cast<String, Object?>() : null;
    } catch (_) {
      return null;
    }
  }

  /// How many records of each kind [caseKey] has.
  Map<String, int> aiCounts(String caseKey) => {
    for (final r in _db.select(
      'SELECT tur, COUNT(*) AS n FROM ai_record WHERE case_key=? AND json IS '
      'NOT NULL GROUP BY tur',
      [caseKey],
    ))
      r['tur'] as String: r['n'] as int,
  };

  void _aiObserve(String id) {
    final kept = _db.select('SELECT surum FROM ai_record WHERE id=?', [id]);
    if (kept.isNotEmpty) {
      if (Hlc.tryParse(kept.first['surum']) case final v?) {
        SyncClock.observe(this, v);
      }
    }
  }

  /// [json] kept as the record [id] of [kind] in [caseKey], its version the
  /// next one.
  void putAiRecord(
    String id,
    String kind,
    String caseKey,
    Map<String, Object?> json,
  ) {
    _aiObserve(id);
    final body = {...json}
      ..remove('id')
      ..remove('dosya');
    _db.execute(
      'INSERT OR REPLACE INTO ai_record(id, tur, case_key, json, surum) '
      'VALUES(?,?,?,?,?)',
      [id, kind, caseKey, jsonEncode(body), '${SyncClock.of(this).tick()}'],
    );
    PortalDatabase.changed?.call();
  }

  /// The record [id] taken off, on every own device.
  void removeAiRecord(String id) {
    _aiObserve(id);
    _db.execute(
      'UPDATE ai_record SET json=NULL, surum=? WHERE id=?',
      ['${SyncClock.of(this).tick()}', id],
    );
    PortalDatabase.changed?.call();
  }

  /// Every record, those taken off with them, for the lawyer's other
  /// devices.
  Map<String, Object?> aiExport() => {
    'kayitlar': [
      for (final r in _db.select(
        'SELECT id, tur, case_key, json, surum FROM ai_record',
      ))
        {for (final c in r.keys) c: r[c]},
    ],
  };

  /// Another own device's [aiExport]: of each record, the later version's,
  /// taken off or not. True when anything here changed.
  bool aiMerge(Object? theirs) {
    if (theirs is! Map) return false;
    var changed = false;
    _db.execute('BEGIN');
    try {
      for (final r in jsonList(theirs['kayitlar'])) {
        if (r is! Map ||
            r['id'] is! String ||
            r['tur'] is! String ||
            r['case_key'] is! String) {
          continue;
        }
        final tv = Hlc.tryParse(r['surum']);
        if (tv == null) continue;
        final json = r['json'];
        if (json != null && (json is! String || _aiJson(json) == null)) {
          continue;
        }
        SyncClock.observe(this, tv);
        final here = _db.select(
          'SELECT json, surum FROM ai_record WHERE id=?',
          [r['id']],
        );
        if (here.isNotEmpty) {
          final mv = Hlc.tryParse(here.first['surum']);
          if (mv != null && Hlc.decide(tv, json, mv, here.first['json']) <= 0) {
            continue;
          }
        }
        _db.execute(
          'INSERT OR REPLACE INTO ai_record(id, tur, case_key, json, surum) '
          'VALUES(?,?,?,?,?)',
          [r['id'], r['tur'], r['case_key'], json, '$tv'],
        );
        changed = true;
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    return changed;
  }
}

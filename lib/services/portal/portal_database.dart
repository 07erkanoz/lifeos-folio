import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../platform/app_directories.dart';
import 'portal_case.dart';
import 'portal_channel.dart';
import 'portal_hearing.dart';

/// A note, a task or a deadline in the agenda: the lawyer's own, kept apart
/// from what the portals report so that no sync ever touches it.
class AgendaItem {
  final String id;

  /// "note", "task" or "deadline".
  final String kind;
  final String title;
  final String body;

  /// Local time; null for a note without a date.
  final DateTime? at;
  final bool allDay;
  final bool done;

  /// The case and hearing it belongs to, by key, if any.
  final String? caseKey;
  final String? hearingKey;
  final DateTime updated;

  const AgendaItem({
    required this.id,
    required this.kind,
    required this.title,
    this.body = '',
    this.at,
    this.allDay = false,
    this.done = false,
    this.caseKey,
    this.hearingKey,
    required this.updated,
  });

  static String newId() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  AgendaItem copyWith({
    String? title,
    String? body,
    DateTime? at,
    bool? done,
    DateTime? updated,
  }) => AgendaItem(
    id: id,
    kind: kind,
    title: title ?? this.title,
    body: body ?? this.body,
    at: at ?? this.at,
    allDay: allDay,
    done: done ?? this.done,
    caseKey: caseKey,
    hearingKey: hearingKey,
    updated: updated ?? DateTime.now(),
  );
}

/// What Folio keeps of the portals on this computer: the merged cases and
/// hearings, and the agenda's own notes and tasks (UYGULAMAPLANI §4, §9).
/// One SQLite file in Folio's data folder; every write is one transaction.
class PortalDatabase {
  PortalDatabase._(this._db) {
    _db.execute('''
      PRAGMA journal_mode=WAL;
      PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS cases (
        key TEXT PRIMARY KEY, json TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS hearings (
        key TEXT PRIMARY KEY, case_key TEXT NOT NULL, at TEXT NOT NULL,
        json TEXT NOT NULL);
      CREATE INDEX IF NOT EXISTS hearings_at ON hearings(at);
      CREATE INDEX IF NOT EXISTS hearings_case ON hearings(case_key);
      CREATE TABLE IF NOT EXISTS agenda (
        id TEXT PRIMARY KEY, kind TEXT NOT NULL, title TEXT NOT NULL,
        body TEXT NOT NULL DEFAULT '', at TEXT, all_day INTEGER NOT NULL DEFAULT 0,
        done INTEGER NOT NULL DEFAULT 0, case_key TEXT, hearing_key TEXT,
        updated TEXT NOT NULL);
      CREATE INDEX IF NOT EXISTS agenda_at ON agenda(at);
    ''');
  }

  final Database _db;

  static PortalDatabase memory() => PortalDatabase._(sqlite3.openInMemory());
  static PortalDatabase open(String path) =>
      PortalDatabase._(sqlite3.open(path));

  static PortalDatabase? _shared;

  /// The one in Folio's data folder.
  static Future<PortalDatabase> shared() async {
    if (_shared != null) return _shared!;
    final dir = Directory(
      p.join((await folioSupportDirectory()).path, 'portal'),
    );
    await dir.create(recursive: true);
    return _shared = open(p.join(dir.path, 'portal.sqlite'));
  }

  void dispose() => _db.dispose();

  void _transaction(void Function() action) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      action();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  // Cases

  Map<String, PortalCase> cases() => {
    for (final row in _db.select('SELECT key, json FROM cases'))
      row['key'] as String: _case(row['json'] as String),
  };

  PortalCase _case(String json) => PortalCaseJson.fromJson(
    Map<String, Object?>.from(jsonDecode(json) as Map),
  );

  /// Merges [incoming] into what is kept, in one transaction: neither
  /// portal's fields overwrite the other's, and a case the answer leaves out
  /// stays.
  void mergeCases(Iterable<PortalCase> incoming) => _transaction(() {
    final read = _db.prepare('SELECT json FROM cases WHERE key=?');
    final write = _db.prepare(
      'INSERT OR REPLACE INTO cases(key, json) VALUES(?, ?)',
    );
    try {
      for (final one in incoming) {
        final rows = read.select([one.key]);
        final merged = rows.isEmpty
            ? one
            : _case(rows.first['json'] as String).merge(one);
        write.execute([merged.key, jsonEncode(merged.toJson())]);
      }
    } finally {
      read.dispose();
      write.dispose();
    }
  });

  // Hearings

  List<PortalHearing> hearings({
    DateTime? from,
    DateTime? to,
    String? caseKey,
  }) {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('at >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('at < ?');
      args.add(to.toIso8601String());
    }
    if (caseKey != null) {
      where.add('case_key = ?');
      args.add(caseKey);
    }
    final sql =
        'SELECT json FROM hearings'
        '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'} ORDER BY at';
    return [
      for (final row in _db.select(sql, args))
        PortalHearing.fromJson(
          Map<String, Object?>.from(jsonDecode(row['json'] as String) as Map),
        ),
    ];
  }

  /// Merges one channel's answer for the window [from]–[to] (UYGULAMAPLANI
  /// §9.7). Only the web's [complete] answer, without errors and not empty,
  /// removes a hearing in the window it no longer lists: a moved hearing is
  /// a new one, and the old one would otherwise stay forever. The mobile
  /// API's answer never removes anything; a gap in a window is not a
  /// cancellation.
  void mergeHearings(
    PortalChannel channel,
    DateTime from,
    DateTime to,
    List<PortalHearing> incoming, {
    required bool complete,
  }) => _transaction(() {
    final read = _db.prepare('SELECT json FROM hearings WHERE key=?');
    final write = _db.prepare(
      'INSERT OR REPLACE INTO hearings(key, case_key, at, json) VALUES(?,?,?,?)',
    );
    try {
      for (final one in incoming) {
        final rows = read.select([one.key]);
        final merged = rows.isEmpty
            ? one
            : PortalHearing.fromJson(
                Map<String, Object?>.from(
                  jsonDecode(rows.first['json'] as String) as Map,
                ),
              ).merge(one);
        write.execute([
          merged.key,
          merged.caseKey,
          merged.at.toIso8601String(),
          jsonEncode(merged.toJson()),
        ]);
      }
    } finally {
      read.dispose();
      write.dispose();
    }
    if (channel == PortalChannel.uyapWeb && complete && incoming.isNotEmpty) {
      final keep = {for (final h in incoming) h.key};
      for (final old in hearings(from: from, to: to)) {
        if (!keep.contains(old.key)) {
          _db.execute('DELETE FROM hearings WHERE key=?', [old.key]);
        }
      }
    }
  });

  // Agenda

  List<AgendaItem> agenda({DateTime? from, DateTime? to}) {
    final rows = from == null || to == null
        ? _db.select('SELECT * FROM agenda ORDER BY at')
        : _db.select(
            'SELECT * FROM agenda WHERE at >= ? AND at < ? ORDER BY at',
            [from.toIso8601String(), to.toIso8601String()],
          );
    return [
      for (final r in rows)
        AgendaItem(
          id: r['id'] as String,
          kind: r['kind'] as String,
          title: r['title'] as String,
          body: r['body'] as String,
          at: r['at'] == null ? null : DateTime.parse(r['at'] as String),
          allDay: r['all_day'] == 1,
          done: r['done'] == 1,
          caseKey: r['case_key'] as String?,
          hearingKey: r['hearing_key'] as String?,
          updated: DateTime.parse(r['updated'] as String),
        ),
    ];
  }

  void saveAgenda(AgendaItem item) => _db.execute(
    '''INSERT OR REPLACE INTO agenda
       (id, kind, title, body, at, all_day, done, case_key, hearing_key, updated)
       VALUES(?,?,?,?,?,?,?,?,?,?)''',
    [
      item.id,
      item.kind,
      item.title,
      item.body,
      item.at?.toIso8601String(),
      item.allDay ? 1 : 0,
      item.done ? 1 : 0,
      item.caseKey,
      item.hearingKey,
      item.updated.toIso8601String(),
    ],
  );

  void removeAgenda(String id) =>
      _db.execute('DELETE FROM agenda WHERE id=?', [id]);
}

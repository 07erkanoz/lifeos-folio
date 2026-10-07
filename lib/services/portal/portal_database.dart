import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../platform/app_directories.dart';
import 'portal_case.dart';
import 'portal_channel.dart';
import 'portal_deadline.dart';
import '../uets/uets_api.dart';
import 'portal_hearing.dart';

/// A UETS notification as kept, with the case it is tied to.
class KeptNotice {
  final UetsMessage message;
  final String? caseKey;

  /// "auto" or "manual"; null while untied.
  final String? link;
  const KeptNotice(this.message, {this.caseKey, this.link});
}

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

/// What Folio knows of a case beyond the portals' answers (see
/// [PortalDatabase.caseStates]).
class CaseState {
  const CaseState({
    this.firstSeen,
    this.seenAt,
    this.fresh = 0,
    this.change,
    this.changeAt,
  });

  /// When the portfolio first brought it; null for one there from the start.
  final DateTime? firstSeen;

  /// When the lawyer last opened it.
  final DateTime? seenAt;

  /// Its documents not yet looked at.
  final int fresh;

  /// "3 yeni evrak", "Taraflar değişti" and the like, and when.
  final String? change;
  final DateTime? changeAt;

  /// New to the portfolio and not yet opened.
  bool get isNew =>
      firstSeen != null && (seenAt == null || seenAt!.isBefore(firstSeen!));
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
      CREATE TABLE IF NOT EXISTS uets (
        id TEXT PRIMARY KEY, sent TEXT, json TEXT NOT NULL,
        case_key TEXT, link TEXT);
      CREATE INDEX IF NOT EXISTS uets_sent ON uets(sent);
      CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS case_state (
        key TEXT PRIMARY KEY, first_seen TEXT NOT NULL DEFAULT '',
        seen_at TEXT, fresh INTEGER NOT NULL DEFAULT 0, change TEXT,
        change_at TEXT);
      CREATE TABLE IF NOT EXISTS uets_part (
        notice_id TEXT NOT NULL, part_id TEXT NOT NULL, name TEXT NOT NULL,
        mime TEXT NOT NULL DEFAULT '', seq INTEGER NOT NULL,
        PRIMARY KEY(notice_id, part_id));
      CREATE TABLE IF NOT EXISTS uets_manifest (
        notice_id TEXT PRIMARY KEY, state TEXT NOT NULL, fetched_at TEXT,
        error TEXT);
      CREATE TABLE IF NOT EXISTS deadline (
        id TEXT PRIMARY KEY, notice_id TEXT NOT NULL, case_key TEXT,
        rule_id TEXT NOT NULL, title TEXT NOT NULL, law TEXT NOT NULL,
        start_event TEXT NOT NULL, start_day TEXT, raw_day TEXT, due_day TEXT,
        state TEXT NOT NULL, ownership TEXT NOT NULL, reasons TEXT NOT NULL,
        evidence TEXT NOT NULL, engine INTEGER NOT NULL,
        calendar INTEGER NOT NULL, inputs TEXT NOT NULL,
        updated TEXT NOT NULL);
      CREATE INDEX IF NOT EXISTS deadline_notice ON deadline(notice_id);
      CREATE TABLE IF NOT EXISTS deadline_user (
        deadline_id TEXT PRIMARY KEY, done INTEGER NOT NULL DEFAULT 0,
        manual_day TEXT, title_override TEXT, body_override TEXT,
        confirmed_inputs TEXT, confirmed_at TEXT,
        dismissed INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE IF NOT EXISTS deadline_history (
        seq INTEGER PRIMARY KEY AUTOINCREMENT, deadline_id TEXT NOT NULL,
        at TEXT NOT NULL, inputs TEXT NOT NULL, engine INTEGER NOT NULL,
        calendar INTEGER NOT NULL, state TEXT NOT NULL, due_day TEXT,
        change TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS deadline_legacy (
        legacy_id TEXT PRIMARY KEY, kind TEXT NOT NULL, title TEXT NOT NULL,
        body TEXT NOT NULL, at TEXT, all_day INTEGER NOT NULL,
        done INTEGER NOT NULL, case_key TEXT, hearing_key TEXT,
        updated TEXT NOT NULL, migrated_at TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS deadline_map (
        legacy_id TEXT NOT NULL, deadline_id TEXT NOT NULL,
        PRIMARY KEY(legacy_id, deadline_id));
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
  /// stays. A case is written only when something in it changed; the same
  /// answer again writes nothing. Answers the keys of cases not kept
  /// before; those the portfolio brings are marked new unless [baseline]
  /// (the first reading of the portfolio, where nothing is news).
  Set<String> mergeCases(
    Iterable<PortalCase> incoming, {
    bool portfolio = false,
    bool baseline = false,
  }) {
    final added = <String>{};
    _transaction(() {
      final read = _db.prepare('SELECT json FROM cases WHERE key=?');
      final write = _db.prepare(
        'INSERT OR REPLACE INTO cases(key, json) VALUES(?, ?)',
      );
      final state = _db.prepare(
        'INSERT OR IGNORE INTO case_state(key, first_seen) VALUES(?, ?)',
      );
      final now = DateTime.now().toUtc().toIso8601String();
      try {
        for (final one in incoming) {
          final rows = read.select([one.key]);
          final before = rows.isEmpty ? null : rows.first['json'] as String;
          final merged = before == null ? one : _case(before).merge(one);
          final json = jsonEncode(merged.toJson());
          if (json == before) continue;
          write.execute([merged.key, json]);
          if (before == null) {
            added.add(merged.key);
            state.execute([merged.key, portfolio && !baseline ? now : '']);
          }
        }
      } finally {
        read.dispose();
        write.dispose();
        state.dispose();
      }
    });
    return added;
  }

  // What Folio remembers beside the portals' answers.

  String? meta(String key) {
    final rows = _db.select('SELECT value FROM meta WHERE key=?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void setMeta(String key, String value) => _db.execute(
    'INSERT OR REPLACE INTO meta(key, value) VALUES(?, ?)',
    [key, value],
  );

  /// Each case's news: whether it came new to the portfolio, how many of
  /// its documents are new, and the last change seen in it.
  Map<String, CaseState> caseStates() => {
    for (final row in _db.select(
      'SELECT key, first_seen, seen_at, fresh, change, change_at '
      'FROM case_state',
    ))
      row['key'] as String: CaseState(
        firstSeen: DateTime.tryParse('${row['first_seen'] ?? ''}'),
        seenAt: DateTime.tryParse('${row['seen_at'] ?? ''}'),
        fresh: row['fresh'] as int? ?? 0,
        change: row['change'] as String?,
        changeAt: DateTime.tryParse('${row['change_at'] ?? ''}'),
      ),
  };

  /// A change found in [key]: [fresh] new documents, and what changed.
  void noteChange(String key, {required int fresh, String? change}) {
    _db.execute(
      'INSERT OR IGNORE INTO case_state(key, first_seen) VALUES(?, ?)',
      [key, ''],
    );
    _db.execute(
      'UPDATE case_state SET fresh=?, '
      'change=COALESCE(?, change), '
      'change_at=CASE WHEN ? IS NULL THEN change_at ELSE ? END WHERE key=?',
      [fresh, change, change, DateTime.now().toUtc().toIso8601String(), key],
    );
  }

  /// The lawyer opened [key]: it is no longer new, nor are its documents.
  void markSeen(String key) {
    _db.execute(
      'INSERT OR IGNORE INTO case_state(key, first_seen) VALUES(?, ?)',
      [key, ''],
    );
    _db.execute('UPDATE case_state SET seen_at=?, fresh=0 WHERE key=?', [
      DateTime.now().toUtc().toIso8601String(),
      key,
    ]);
  }

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

  // UETS

  /// The notifications kept, newest first, each with the case it was tied
  /// to (UYGULAMAPLANI §9.8) and how.
  List<KeptNotice> notices() => [
    for (final r in _db.select(
      'SELECT json, case_key, link FROM uets ORDER BY sent DESC',
    ))
      KeptNotice(
        UetsMessage.fromJson(
          Map<String, Object?>.from(jsonDecode(r['json'] as String) as Map),
        ),
        caseKey: r['case_key'] as String?,
        link: r['link'] as String?,
      ),
  ];

  /// Keeps [messages] as UETS gave them; the tie to a case stays.
  void mergeNotices(Iterable<UetsMessage> messages) => _transaction(() {
    final write = _db.prepare('''
      INSERT INTO uets(id, sent, json) VALUES(?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET sent=excluded.sent, json=excluded.json''');
    try {
      for (final m in messages) {
        if (m.id.isEmpty) continue;
        write.execute([
          m.id,
          m.sent?.toIso8601String(),
          jsonEncode(m.toJson()),
        ]);
      }
    } finally {
      write.dispose();
    }
  });

  /// Ties notification [id] to [caseKey]; [link] says how: "auto" for the
  /// matcher's single candidate, "manual" for the lawyer's choice, which
  /// the matcher never undoes.
  void linkNotice(String id, String? caseKey, String? link) => _db.execute(
    'UPDATE uets SET case_key=?, link=? WHERE id=?',
    [caseKey, link, id],
  );

  // Agenda

  /// The agenda: the lawyer's own notes, tasks and deadlines, and the
  /// notices' deadlines the lawyer confirmed or gave a day (see
  /// [KeptDeadline.onAgenda]). The old rows the notices' deadlines were
  /// kept in before are not shown: they live on as [deadlines] records.
  List<AgendaItem> agenda({DateTime? from, DateTime? to}) {
    final rows = from == null || to == null
        ? _db.select('SELECT * FROM agenda ORDER BY at')
        : _db.select(
            'SELECT * FROM agenda WHERE at >= ? AND at < ? ORDER BY at',
            [from.toIso8601String(), to.toIso8601String()],
          );
    final all = deadlines();
    final byId = {for (final d in all) d.record.id: d};
    // An old row stays until the lawyer has decided on every deadline it
    // was carried over to, or had marked it done; marked as the old
    // reckoning it is.
    final carried = <String, List<String>>{};
    for (final r in _db.select(
      'SELECT legacy_id, deadline_id FROM deadline_map',
    )) {
      (carried[r['legacy_id'] as String] ??= []).add(
        r['deadline_id'] as String,
      );
    }
    final legacy = {
      for (final r in _db.select('SELECT legacy_id FROM deadline_legacy'))
        r['legacy_id'] as String,
    };
    final own = [
      for (final i in _agendaRows(rows))
        if (!legacy.contains(i.id))
          i
        else if (!i.done &&
            (carried[i.id] ?? const []).any(
              (id) => !(byId[id]?.decided ?? true),
            ))
          i.copyWith(
            body: [
              if (i.body.isNotEmpty) i.body,
              'önceki hesap · İncelenecek sürelerden kontrol edin',
            ].join(' · '),
            updated: i.updated,
          ),
    ];
    final kept =
        [
          for (final d in all)
            if (d.onAgenda) _agendaOf(d),
        ].where(
          (i) =>
              from == null ||
              to == null ||
              (i.at != null && !i.at!.isBefore(from) && i.at!.isBefore(to)),
        );
    if (kept.isEmpty) return own;
    final shown = [...own, ...kept];
    shown.sort((a, b) {
      final x = a.at, y = b.at;
      if (x == null || y == null) return x == null ? (y == null ? 0 : -1) : 1;
      return x.compareTo(y);
    });
    return shown;
  }

  /// Every notice's list of documents at once (see [manifest]).
  Map<
    String,
    ({String state, String? fetchedAt, List<({String id, String name})> parts})
  >
  manifests() {
    final parts = <String, List<({String id, String name})>>{};
    for (final r in _db.select(
      'SELECT notice_id, part_id, name FROM uets_part ORDER BY notice_id, seq',
    )) {
      (parts[r['notice_id'] as String] ??= []).add((
        id: r['part_id'] as String,
        name: r['name'] as String,
      ));
    }
    return {
      for (final r in _db.select(
        'SELECT notice_id, state, fetched_at FROM uets_manifest',
      ))
        r['notice_id'] as String: (
          state: r['state'] as String,
          fetchedAt: r['fetched_at'] as String?,
          parts: parts[r['notice_id'] as String] ?? const [],
        ),
    };
  }

  AgendaItem _agendaOf(KeptDeadline d) {
    final day = DateTime.parse(d.day!);
    final r = d.record;
    return AgendaItem(
      id: r.id,
      kind: 'deadline',
      title: d.user?.titleOverride ?? r.title,
      body: d.user?.bodyOverride ?? [r.law, 'UETS'].join(' · '),
      at: DateTime(day.year, day.month, day.day),
      allDay: true,
      done: d.user?.done ?? false,
      caseKey: r.caseKey,
      updated: r.updated,
    );
  }

  List<AgendaItem> _agendaRows(ResultSet rows) => [
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

  /// Keeps [item]. A notice's deadline shown on the agenda is not an
  /// agenda row: what the lawyer changed on it (done, the day, the title)
  /// goes to the lawyer's decisions on that deadline.
  void saveAgenda(AgendaItem item) {
    final kept = deadline(item.id);
    if (kept != null) {
      final shown = kept.onAgenda ? _agendaOf(kept) : null;
      final user = kept.user ?? DeadlineUser(deadlineId: item.id);
      String? day(DateTime? d) => d == null ? null : _dayKey(d);
      saveDeadlineUser(
        user.copyWith(
          done: item.done,
          manualDay: shown != null && day(item.at) != day(shown.at)
              ? day(item.at)
              : null,
          titleOverride: shown != null && item.title != shown.title
              ? item.title
              : null,
          bodyOverride: shown != null && item.body != shown.body
              ? item.body
              : null,
        ),
      );
      return;
    }
    // An old row still shown: what the lawyer changed goes on it, not the
    // note the agenda shows it with.
    final legacy = _db.select(
      'SELECT body FROM agenda WHERE id=? AND id IN '
      '(SELECT legacy_id FROM deadline_legacy)',
      [item.id],
    );
    if (legacy.isNotEmpty) {
      final body = legacy.first['body'] as String;
      // Done or not done on the old row is the lawyer's word on the one
      // deadline it was carried over to; with several, it stays the row's.
      final to = [
        for (final r in _db.select(
          'SELECT deadline_id FROM deadline_map WHERE legacy_id=?',
          [item.id],
        ))
          r['deadline_id'] as String,
      ];
      if (to.length == 1) {
        final d = deadline(to.single);
        if (d != null) {
          saveDeadlineUser(
            (d.user ?? DeadlineUser(deadlineId: to.single)).copyWith(
              done: item.done,
            ),
          );
        }
      }
      _saveAgendaRow(
        AgendaItem(
          id: item.id,
          kind: item.kind,
          title: item.title,
          body: item.body.contains('önceki hesap') ? body : item.body,
          at: item.at,
          allDay: item.allDay,
          done: item.done,
          caseKey: item.caseKey,
          hearingKey: item.hearingKey,
          updated: item.updated,
        ),
      );
      return;
    }
    _saveAgendaRow(item);
  }

  void _saveAgendaRow(AgendaItem item) => _db.execute(
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

  /// Takes [id] off the agenda: a notice's deadline is only set aside by
  /// the lawyer, and still shown on its notice.
  void removeAgenda(String id) {
    final kept = deadline(id);
    if (kept != null) {
      saveDeadlineUser(
        (kept.user ?? DeadlineUser(deadlineId: id)).copyWith(dismissed: true),
      );
      return;
    }
    _db.execute('DELETE FROM agenda WHERE id=?', [id]);
  }

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // Notices' documents

  /// Keeps the list of [noticeId]'s documents as UETS gave it; [error]
  /// when it could not be had, so that "not asked yet", "asked, none" and
  /// "could not be had" stay apart.
  void saveManifest(
    String noticeId,
    List<({String id, String name, String mime})>? parts, {
    String? error,
    DateTime? now,
  }) => _transaction(() {
    final at = (now ?? DateTime.now()).toIso8601String();
    if (parts == null) {
      _db.execute(
        'INSERT OR REPLACE INTO uets_manifest(notice_id, state, fetched_at, '
        "error) VALUES(?, 'hata', ?, ?)",
        [noticeId, at, error ?? ''],
      );
      return;
    }
    _db.execute('DELETE FROM uets_part WHERE notice_id=?', [noticeId]);
    for (var i = 0; i < parts.length; i++) {
      _db.execute(
        'INSERT OR REPLACE INTO uets_part(notice_id, part_id, name, mime, seq) '
        'VALUES(?, ?, ?, ?, ?)',
        [noticeId, parts[i].id, parts[i].name, parts[i].mime, i],
      );
    }
    _db.execute(
      'INSERT OR REPLACE INTO uets_manifest(notice_id, state, fetched_at, '
      'error) VALUES(?, ?, ?, NULL)',
      [noticeId, parts.isEmpty ? 'bos' : 'alindi', at],
    );
  });

  /// [noticeId]'s documents as last kept: the state ('alinmadi' when never
  /// asked, 'alindi', 'bos' or 'hata'), when, and the documents in order.
  ({String state, String? fetchedAt, List<({String id, String name})> parts})
  manifest(String noticeId) {
    final m = _db.select(
      'SELECT state, fetched_at FROM uets_manifest WHERE notice_id=?',
      [noticeId],
    );
    if (m.isEmpty) return (state: 'alinmadi', fetchedAt: null, parts: const []);
    return (
      state: m.first['state'] as String,
      fetchedAt: m.first['fetched_at'] as String?,
      parts: [
        for (final r in _db.select(
          'SELECT part_id, name FROM uets_part WHERE notice_id=? ORDER BY seq',
          [noticeId],
        ))
          (id: r['part_id'] as String, name: r['name'] as String),
      ],
    );
  }

  // Notices' deadlines

  List<KeptDeadline> deadlines({String? noticeId}) => [
    for (final r
        in noticeId == null
            ? _db.select(
                'SELECT d.*, u.deadline_id AS u_id, u.done, u.manual_day, '
                'u.title_override, u.body_override, u.confirmed_inputs, '
                'u.confirmed_at, u.dismissed FROM deadline d LEFT JOIN '
                'deadline_user u ON u.deadline_id = d.id ORDER BY d.due_day',
              )
            : _db.select(
                'SELECT d.*, u.deadline_id AS u_id, u.done, u.manual_day, '
                'u.title_override, u.body_override, u.confirmed_inputs, '
                'u.confirmed_at, u.dismissed FROM deadline d LEFT JOIN '
                'deadline_user u ON u.deadline_id = d.id WHERE d.notice_id=? '
                'ORDER BY d.due_day',
                [noticeId],
              ))
      _keptDeadline(r),
  ];

  KeptDeadline? deadline(String id) {
    final rows = _db.select(
      'SELECT d.*, u.deadline_id AS u_id, u.done, u.manual_day, '
      'u.title_override, u.body_override, u.confirmed_inputs, '
      'u.confirmed_at, u.dismissed FROM deadline d LEFT JOIN deadline_user u '
      'ON u.deadline_id = d.id WHERE d.id=?',
      [id],
    );
    return rows.isEmpty ? null : _keptDeadline(rows.first);
  }

  KeptDeadline _keptDeadline(Row r) {
    final record = DeadlineRecord(
      id: r['id'] as String,
      noticeId: r['notice_id'] as String,
      caseKey: r['case_key'] as String?,
      ruleId: r['rule_id'] as String,
      title: r['title'] as String,
      law: r['law'] as String,
      startEvent: r['start_event'] as String,
      startDay: r['start_day'] as String?,
      rawDay: r['raw_day'] as String?,
      dueDay: r['due_day'] as String?,
      state: r['state'] as String,
      ownership: r['ownership'] as String,
      reasons: [
        for (final x in jsonDecode(r['reasons'] as String) as List)
          DeadlineReason.fromJson(x),
      ],
      evidence: Map<String, Object?>.from(
        jsonDecode(r['evidence'] as String) as Map,
      ),
      engine: r['engine'] as int,
      calendar: r['calendar'] as int,
      inputs: r['inputs'] as String,
      updated: DateTime.parse(r['updated'] as String),
    );
    final user = r['u_id'] == null
        ? null
        : DeadlineUser(
            deadlineId: record.id,
            done: r['done'] == 1,
            manualDay: r['manual_day'] as String?,
            titleOverride: r['title_override'] as String?,
            bodyOverride: r['body_override'] as String?,
            confirmedInputs: r['confirmed_inputs'] as String?,
            confirmedAt: r['confirmed_at'] == null
                ? null
                : DateTime.parse(r['confirmed_at'] as String),
            dismissed: r['dismissed'] == 1,
          );
    return KeptDeadline(record, user);
  }

  /// [noticeId]'s deadlines as the engine now makes them, in one
  /// transaction: a record whose inputs and state are unchanged is not
  /// written; a changed one is, with a line in its history; one no longer
  /// made is kept as 'eski', never deleted. The lawyer's decisions are
  /// not touched here.
  void replaceNoticeDeadlines(
    String noticeId,
    List<DeadlineRecord> fresh, {
    DateTime? now,
  }) => _transaction(() {
    final at = (now ?? DateTime.now()).toIso8601String();
    final before = {
      for (final d in deadlines(noticeId: noticeId)) d.record.id: d.record,
    };
    for (final r in fresh) {
      final old = before.remove(r.id);
      if (old != null &&
          old.inputs == r.inputs &&
          old.state == r.state &&
          old.caseKey == r.caseKey &&
          old.reasonsJson == r.reasonsJson) {
        continue;
      }
      _writeDeadline(r);
      _history(r, at, old == null ? 'yeni' : 'yeniden hesaplandı');
    }
    for (final old in before.values) {
      if (old.state == 'eski') continue;
      final gone = old.withState(
        'eski',
        reasons: [
          const DeadlineReason(
            'artikUretilmiyor',
            'Bu süre artık hesaplanmıyor (tebligatın bilgisi ya da kural '
                'değişti).',
          ),
          ...old.reasons,
        ],
        updated: now,
      );
      _writeDeadline(gone);
      _history(gone, at, 'artık üretilmiyor');
    }
  });

  void _writeDeadline(DeadlineRecord r) => _db.execute(
    '''INSERT OR REPLACE INTO deadline(id, notice_id, case_key, rule_id, title,
       law, start_event, start_day, raw_day, due_day, state, ownership,
       reasons, evidence, engine, calendar, inputs, updated)
       VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
    [
      r.id,
      r.noticeId,
      r.caseKey,
      r.ruleId,
      r.title,
      r.law,
      r.startEvent,
      r.startDay,
      r.rawDay,
      r.dueDay,
      r.state,
      r.ownership,
      r.reasonsJson,
      r.evidenceJson,
      r.engine,
      r.calendar,
      r.inputs,
      r.updated.toIso8601String(),
    ],
  );

  void _history(DeadlineRecord r, String at, String change) => _db.execute(
    'INSERT INTO deadline_history(deadline_id, at, inputs, engine, calendar, '
    'state, due_day, change) VALUES(?,?,?,?,?,?,?,?)',
    [r.id, at, r.inputs, r.engine, r.calendar, r.state, r.dueDay, change],
  );

  /// [id]'s history, oldest first.
  List<({DateTime at, String state, String? dueDay, String change})>
  deadlineHistory(String id) => [
    for (final r in _db.select(
      'SELECT at, state, due_day, change FROM deadline_history '
      'WHERE deadline_id=? ORDER BY seq',
      [id],
    ))
      (
        at: DateTime.parse(r['at'] as String),
        state: r['state'] as String,
        dueDay: r['due_day'] as String?,
        change: r['change'] as String,
      ),
  ];

  void saveDeadlineUser(DeadlineUser u) => _db.execute(
    '''INSERT OR REPLACE INTO deadline_user(deadline_id, done, manual_day,
       title_override, body_override, confirmed_inputs, confirmed_at,
       dismissed) VALUES(?,?,?,?,?,?,?,?)''',
    [
      u.deadlineId,
      u.done ? 1 : 0,
      u.manualDay,
      u.titleOverride,
      u.bodyOverride,
      u.confirmedInputs,
      u.confirmedAt?.toIso8601String(),
      u.dismissed ? 1 : 0,
    ],
  );

  /// Confirms [id] on the inputs it has now; refused for one without a day.
  bool confirmDeadline(String id, {DateTime? now}) {
    final kept = deadline(id);
    if (kept == null ||
        kept.record.state != 'aday' ||
        kept.record.dueDay == null ||
        kept.record.startDay == null) {
      return false;
    }
    saveDeadlineUser(
      (kept.user ?? DeadlineUser(deadlineId: id)).copyWith(
        confirmedInputs: kept.record.inputs,
        confirmedAt: now ?? DateTime.now(),
      ),
    );
    return true;
  }

  // The agenda rows the notices' deadlines were kept in before

  /// The notices' deadline rows of the agenda not yet carried over.
  List<AgendaItem> legacyNoticeDeadlines() => _agendaRows(
    _db.select(
      "SELECT * FROM agenda WHERE kind='deadline' AND id LIKE 'uets:%' "
      'AND id NOT IN (SELECT legacy_id FROM deadline_legacy)',
    ),
  );

  /// Keeps [old] as it was, tied to [to] (none, one or more records), and
  /// takes it off the agenda's own rows. Nothing of it is deleted.
  void archiveLegacy(AgendaItem old, List<String> to, {DateTime? now}) =>
      _transaction(() {
        _db.execute(
          '''INSERT OR IGNORE INTO deadline_legacy(legacy_id, kind, title, body,
             at, all_day, done, case_key, hearing_key, updated, migrated_at)
             VALUES(?,?,?,?,?,?,?,?,?,?,?)''',
          [
            old.id,
            old.kind,
            old.title,
            old.body,
            old.at?.toIso8601String(),
            old.allDay ? 1 : 0,
            old.done ? 1 : 0,
            old.caseKey,
            old.hearingKey,
            old.updated.toIso8601String(),
            (now ?? DateTime.now()).toIso8601String(),
          ],
        );
        for (final id in to) {
          _db.execute(
            'INSERT OR IGNORE INTO deadline_map(legacy_id, deadline_id) '
            'VALUES(?, ?)',
            [old.id, id],
          );
        }
      });

  /// The old row [deadlineId] was carried over from, if any.
  AgendaItem? legacyOf(String deadlineId) {
    final rows = _agendaRows(
      _db.select(
        'SELECT l.legacy_id AS id, l.kind, l.title, l.body, l.at, l.all_day, '
        'l.done, l.case_key, l.hearing_key, l.updated FROM deadline_legacy l '
        'JOIN deadline_map m ON m.legacy_id = l.legacy_id '
        'WHERE m.deadline_id=?',
        [deadlineId],
      ),
    );
    return rows.isEmpty ? null : rows.first;
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../platform/app_directories.dart';
import 'portal_case.dart';
import 'portal_channel.dart';
import 'portal_deadline.dart';
import '../uets/deadline_choice.dart';
import '../uets/notice_documents.dart';
import '../uets/notice_matcher.dart';
import '../uets/uets_api.dart';
import 'portal_hearing.dart';
import 'uyap_notice.dart';
import '../legal/deadlines/aidiyet.dart' show vekilOlarakGeciyor;
import '../uyap/uyap_web_service.dart' show UyapParty, UyapWebService;
import '../clients/client.dart';

part 'portal_clients.dart';

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
      CREATE TABLE IF NOT EXISTS cases_revision (n INTEGER NOT NULL);
      INSERT INTO cases_revision SELECT 0
        WHERE NOT EXISTS (SELECT 1 FROM cases_revision);
      CREATE TRIGGER IF NOT EXISTS cases_written AFTER INSERT ON cases
        BEGIN UPDATE cases_revision SET n = n + 1; END;
      CREATE TRIGGER IF NOT EXISTS cases_removed AFTER DELETE ON cases
        BEGIN UPDATE cases_revision SET n = n + 1; END;
      CREATE TABLE IF NOT EXISTS uets_part (
        notice_id TEXT NOT NULL, part_id TEXT NOT NULL, name TEXT NOT NULL,
        mime TEXT NOT NULL DEFAULT '', seq INTEGER NOT NULL,
        PRIMARY KEY(notice_id, part_id));
      CREATE TABLE IF NOT EXISTS uets_manifest (
        notice_id TEXT PRIMARY KEY, state TEXT NOT NULL, fetched_at TEXT,
        error TEXT);
      CREATE TABLE IF NOT EXISTS uets_envelope (
        notice_id TEXT PRIMARY KEY, state TEXT NOT NULL, folder TEXT,
        package_path TEXT, envelope_path TEXT, envelope_text TEXT,
        attachments TEXT NOT NULL DEFAULT '[]', fetched_at TEXT, error TEXT);
      CREATE TABLE IF NOT EXISTS uets_document (
        notice_id TEXT NOT NULL, seq INTEGER NOT NULL, name TEXT NOT NULL,
        path TEXT NOT NULL, part_id TEXT, digest TEXT NOT NULL,
        state TEXT NOT NULL, text TEXT NOT NULL DEFAULT '', note TEXT,
        reader INTEGER NOT NULL, read_at TEXT NOT NULL,
        PRIMARY KEY(notice_id, seq));
      CREATE TABLE IF NOT EXISTS case_party (
        case_key TEXT NOT NULL, seq INTEGER NOT NULL, ad TEXT NOT NULL,
        rol TEXT NOT NULL, vekil TEXT NOT NULL DEFAULT '',
        tur TEXT NOT NULL DEFAULT '', kaynak TEXT NOT NULL,
        alindi TEXT NOT NULL, PRIMARY KEY(case_key, seq));
      CREATE INDEX IF NOT EXISTS case_party_ad ON case_party(ad);
      CREATE TABLE IF NOT EXISTS case_representation (
        case_key TEXT PRIMARY KEY, json TEXT NOT NULL, updated TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS deadline_choice (
        id TEXT PRIMARY KEY, notice_id TEXT NOT NULL, json TEXT NOT NULL);
      CREATE INDEX IF NOT EXISTS deadline_choice_notice
        ON deadline_choice(notice_id);
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
      CREATE INDEX IF NOT EXISTS deadline_history_id
        ON deadline_history(deadline_id);
      CREATE TABLE IF NOT EXISTS deadline_legacy (
        legacy_id TEXT PRIMARY KEY, kind TEXT NOT NULL, title TEXT NOT NULL,
        body TEXT NOT NULL, at TEXT, all_day INTEGER NOT NULL,
        done INTEGER NOT NULL, case_key TEXT, hearing_key TEXT,
        updated TEXT NOT NULL, migrated_at TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS deadline_map (
        legacy_id TEXT NOT NULL, deadline_id TEXT NOT NULL,
        PRIMARY KEY(legacy_id, deadline_id));
      CREATE TABLE IF NOT EXISTS uyap_notice (
        source TEXT NOT NULL, id TEXT NOT NULL,
        message_id TEXT NOT NULL DEFAULT '', title TEXT NOT NULL DEFAULT '',
        body TEXT NOT NULL DEFAULT '', sent TEXT, remote_read INTEGER,
        local_read INTEGER, first_seen TEXT NOT NULL, updated TEXT NOT NULL,
        PRIMARY KEY(source, id));
      CREATE INDEX IF NOT EXISTS uyap_notice_sent ON uyap_notice(sent);
      CREATE TABLE IF NOT EXISTS agenda_removed (
        id TEXT PRIMARY KEY, at TEXT NOT NULL);
    ''');
    _db.execute(PortalClients._tables);
    // When the lawyer last decided on a deadline: for the newer to win
    // between their own devices.
    final columns = {
      for (final r in _db.select('PRAGMA table_info(deadline_user)'))
        r['name'] as String,
    };
    if (!columns.contains('updated')) {
      _db.execute('ALTER TABLE deadline_user ADD COLUMN updated TEXT');
    }
    // The day a deadline had when confirmed, for every device (B22).
    if (!columns.contains('confirmed_day')) {
      _db.execute('ALTER TABLE deadline_user ADD COLUMN confirmed_day TEXT');
    }
  }

  /// Told after the lawyer changed the agenda here, for their other
  /// devices to hear of it; not after what came from those.
  static void Function()? changed;

  /// Whether this device's person sees the clients' money, and who they
  /// are in the office (OwnSync tells): their own devices bring the money
  /// others wrote only while they may.
  static bool Function()? clientMoneyAllowed;
  static String Function()? clientPerson;

  /// The clients' records taken off here since last asked (unshared, the
  /// money no longer let), for their files to go too.
  final removedClientRecords = <ClientRecord>[];

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

  /// Counted up at every case written or removed, by any connection: what
  /// was made of the cases stands while it stays the same.
  int get casesRevision =>
      _db.select('SELECT n FROM cases_revision').first.columnAt(0) as int;

  /// One case as kept; null when it is not. Not all of them read for one.
  PortalCase? caseOf(String key) {
    final rows = _db.select('SELECT json FROM cases WHERE key=?', [key]);
    return rows.isEmpty ? null : _case(rows.first['json'] as String);
  }

  PortalCase _case(String json) => PortalCaseJson.fromJson(
    Map<String, Object?>.from(jsonDecode(json) as Map),
  );

  /// Merges [incoming] into what is kept, in one transaction: neither
  /// portal's fields overwrite the other's, and a case the answer leaves out
  /// stays. A case is written only when something in it changed; the same
  /// answer again writes nothing. Answers the keys of cases not kept
  /// before; those the portfolio brings are marked new unless [baseline]
  /// (the first reading of the portfolio, where nothing is news).
  ///
  /// [changed], when given, is told the key of every case written: new or
  /// changed, so that only those are asked about afterwards.
  Set<String> mergeCases(
    Iterable<PortalCase> incoming, {
    bool portfolio = false,
    bool baseline = false,
    Set<String>? changed,
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
          changed?.add(merged.key);
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

  // UYAP's notifications

  /// [rows] of one channel kept, in one transaction: each channel writes
  /// only its own rows, so UYAP Mobil's reading and the portal's never
  /// write over each other. What a row had is not lost to an answer
  /// without it (UYAP Mobil's list has no body); the lawyer's own read or
  /// unread is never touched. The rows new to Folio, for the desktop's
  /// word of them.
  List<UyapNoticeRow> saveUyapNotices(
    Iterable<UyapNoticeRow> rows, {
    DateTime? now,
  }) {
    final at = (now ?? DateTime.now()).toIso8601String();
    final added = <UyapNoticeRow>[];
    _transaction(() {
      for (final r in rows) {
        final kept = _db.select(
          'SELECT 1 FROM uyap_notice WHERE source=? AND id=?',
          [r.source.name, r.id],
        );
        if (kept.isEmpty) {
          _db.execute(
            'INSERT INTO uyap_notice(source, id, message_id, title, body, '
            'sent, remote_read, first_seen, updated) '
            'VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              r.source.name,
              r.id,
              r.messageId,
              r.title,
              r.body,
              r.sentAt?.toIso8601String(),
              r.remoteRead == null ? null : (r.remoteRead! ? 1 : 0),
              at,
              at,
            ],
          );
          added.add(r);
          continue;
        }
        _db.execute(
          'UPDATE uyap_notice SET '
          "message_id=CASE WHEN ?1<>'' THEN ?1 ELSE message_id END, "
          "title=CASE WHEN ?2<>'' THEN ?2 ELSE title END, "
          "body=CASE WHEN ?3<>'' THEN ?3 ELSE body END, "
          'sent=COALESCE(?4, sent), '
          'remote_read=COALESCE(?5, remote_read), updated=?6 '
          'WHERE source=?7 AND id=?8',
          [
            r.messageId,
            r.title,
            r.body,
            r.sentAt?.toIso8601String(),
            r.remoteRead == null ? null : (r.remoteRead! ? 1 : 0),
            at,
            r.source.name,
            r.id,
          ],
        );
      }
    });
    return added;
  }

  /// The body UYAP Mobil gave for one of its notifications.
  void setUyapNoticeBody(String id, String body) => _db.execute(
    "UPDATE uyap_notice SET body=? WHERE source='mobile' AND id=? "
    "AND body=''",
    [body, id],
  );

  /// UYAP Mobil's notifications with no body yet, newest first.
  List<UyapNoticeRow> uyapNoticesWithoutBody({int limit = 25}) => [
    for (final row in _db.select(
      "SELECT * FROM uyap_notice WHERE source='mobile' AND body='' "
      "AND message_id<>'' ORDER BY sent DESC LIMIT ?",
      [limit],
    ))
      _noticeRow(row),
  ];

  /// Every channel's rows since [since] (all when null), newest first.
  List<UyapNoticeRow> uyapNoticeRows({DateTime? since}) => [
    for (final row
        in since == null
            ? _db.select('SELECT * FROM uyap_notice ORDER BY sent DESC')
            : _db.select(
                'SELECT * FROM uyap_notice WHERE sent IS NULL OR sent>=? '
                'ORDER BY sent DESC',
                [since.toIso8601String()],
              ))
      _noticeRow(row),
  ];

  /// The lawyer's read or unread, on every row of a notification: both
  /// channels' rows of one say the same.
  void setUyapNoticeRead(Iterable<UyapNoticeRow> rows, bool read) =>
      _transaction(() {
        for (final r in rows) {
          _db.execute(
            'UPDATE uyap_notice SET local_read=? WHERE source=? AND id=?',
            [read ? 1 : 0, r.source.name, r.id],
          );
        }
      });

  UyapNoticeRow _noticeRow(Row row) {
    bool? flag(Object? v) => v == null ? null : v == 1;
    return UyapNoticeRow(
      source: UyapNoticeSource.values.byName(row['source'] as String),
      id: row['id'] as String,
      messageId: row['message_id'] as String,
      title: row['title'] as String,
      body: row['body'] as String,
      sentAt: row['sent'] == null
          ? null
          : DateTime.tryParse(row['sent'] as String),
      remoteRead: flag(row['remote_read']),
      localRead: flag(row['local_read']),
    );
  }

  /// The notifications as the lawyer sees them, both channels' as one,
  /// each tied to its case in the portfolio where its body names it.
  List<UyapNotice> uyapNotices({DateTime? since, String? caseKey}) {
    final keys = {
      for (final row in _db.select('SELECT key FROM cases'))
        row['key'] as String,
    };
    final all = mergeUyapNotices(uyapNoticeRows(since: since), caseKeys: keys);
    return caseKey == null
        ? all
        : [
            for (final n in all)
              if (n.caseKey == caseKey) n,
          ];
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

  /// The hearings and inspections the notices' papers set, for [cases]:
  /// those the papers set before and no longer are taken off, but a day
  /// a portal listed too; [found] kept where no portal lists that minute.
  void replacePaperHearings(Set<String> cases, List<PortalHearing> found) =>
      _transaction(() {
        final keep = {for (final h in found) h.key};
        for (final key in cases) {
          for (final r in _db.select(
            'SELECT key, json FROM hearings WHERE case_key=?',
            [key],
          )) {
            final h = PortalHearing.fromJson(
              Map<String, Object?>.from(jsonDecode(r['json'] as String) as Map),
            );
            final paperOnly =
                h.ids.keys.every((c) => c == PortalChannel.uets) &&
                h.ids.isNotEmpty;
            if (paperOnly && !keep.contains(h.key)) {
              _db.execute('DELETE FROM hearings WHERE key=?', [h.key]);
            }
          }
        }
        for (final h in found) {
          final there = _db.select('SELECT 1 FROM hearings WHERE key=?', [
            h.key,
          ]);
          if (there.isNotEmpty) continue;
          _db.execute(
            'INSERT INTO hearings(key, case_key, at, json) VALUES(?,?,?,?)',
            [h.key, h.caseKey, h.at.toIso8601String(), jsonEncode(h.toJson())],
          );
        }
      });

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
        // A day only a notice's papers set (an inspection) is not UYAP's
        // to take off (refreshNoticeEvents keeps those).
        final paperOnly =
            old.ids.isNotEmpty &&
            old.ids.keys.every((c) => c == PortalChannel.uets);
        if (!keep.contains(old.key) && !paperOnly) {
          _db.execute('DELETE FROM hearings WHERE key=?', [old.key]);
        }
      }
    }
  });

  // UETS

  /// The notifications kept, newest first, each with the case it was tied
  /// to (UYGULAMAPLANI §9.8) and how.
  List<KeptNotice> notices({String? caseKey}) => [
    for (final r
        in caseKey == null
            ? _db.select(
                'SELECT json, case_key, link FROM uets ORDER BY sent DESC',
              )
            : _db.select(
                'SELECT json, case_key, link FROM uets WHERE case_key=? '
                'ORDER BY sent DESC',
                [caseKey],
              ))
      KeptNotice(
        UetsMessage.fromJson(
          Map<String, Object?>.from(jsonDecode(r['json'] as String) as Map),
        ),
        caseKey: r['case_key'] as String?,
        link: r['link'] as String?,
      ),
  ];

  /// The notifications' ids, newest first; nothing else read.
  List<String> noticeIds() => [
    for (final r in _db.select('SELECT id FROM uets ORDER BY sent DESC'))
      r['id'] as String,
  ];

  /// The subjects of the notifications [ids], by id.
  Map<String, String> noticeSubjects(Set<String> ids) {
    if (ids.isEmpty) return const {};
    final out = <String, String>{};
    final read = _db.prepare('SELECT json FROM uets WHERE id=?');
    try {
      for (final id in ids) {
        final rows = read.select([id]);
        if (rows.isEmpty) continue;
        final json = jsonDecode(rows.first['json'] as String);
        if (json is Map) out[id] = '${json['subject'] ?? ''}';
      }
    } finally {
      read.dispose();
    }
    return out;
  }

  /// One notification as kept; null when it is not.
  KeptNotice? notice(String id) {
    final rows = _db.select(
      'SELECT json, case_key, link FROM uets WHERE id=?',
      [id],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return KeptNotice(
      UetsMessage.fromJson(
        Map<String, Object?>.from(jsonDecode(r['json'] as String) as Map),
      ),
      caseKey: r['case_key'] as String?,
      link: r['link'] as String?,
    );
  }

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

  /// Changes since it was opened, made here or by another connection (a
  /// worker's): what was read of it stands while this stays the same.
  (int, int) get revision => (
    _db.select('PRAGMA data_version').first.columnAt(0) as int,
    _db.select('SELECT total_changes()').first.columnAt(0) as int,
  );

  /// The agenda: the lawyer's own notes, tasks and deadlines, and the
  /// notices' deadlines the lawyer confirmed or gave a day (see
  /// [KeptDeadline.onAgenda]). The old rows the notices' deadlines were
  /// kept in before are not shown: they live on as [deadlines] records.
  List<AgendaItem> agenda({DateTime? from, DateTime? to, String? caseKey}) {
    final where = <String>[
      if (from != null && to != null) 'at >= ? AND at < ?',
      if (caseKey != null) 'case_key = ?',
    ];
    final rows = _db.select(
      'SELECT * FROM agenda'
      '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'} ORDER BY at',
      [
        if (from != null && to != null) ...[
          from.toIso8601String(),
          to.toIso8601String(),
        ],
        ?caseKey,
      ],
    );
    final all = [
      for (final d in deadlines(decidedOnly: true))
        if (caseKey == null || d.record.caseKey == caseKey) d,
    ];
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
            // One never touched by the lawyer is not among those read.
            (carried[i.id] ?? const []).any(
              (id) => !(byId[id]?.decided ?? false),
            ))
          i.copyWith(
            body: [
              if (i.body.isNotEmpty) i.body,
              'önceki hesap · İncelenecek sürelerden kontrol edin',
            ].join(' · '),
            updated: i.updated,
          ),
    ];
    final subjects = noticeSubjects({
      for (final d in all)
        if (d.onAgenda) d.record.noticeId,
    });
    final kept =
        [
          for (final d in all)
            if (d.onAgenda) _agendaOf(d, subjects[d.record.noticeId]),
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

  /// [subject] is its notice's subject, for the court and number the
  /// deadline belongs to.
  AgendaItem _agendaOf(KeptDeadline d, [String? subject]) {
    final day = DateTime.parse(d.day!);
    final r = d.record;
    final parsed = subject == null ? null : NoticeSubject.parse(subject);
    return AgendaItem(
      id: r.id,
      kind: 'deadline',
      title: d.user?.titleOverride ?? r.title,
      body:
          d.user?.bodyOverride ??
          [
            if (r.law.isNotEmpty) r.law,
            parsed == null ? 'UETS' : '${parsed.unit} · ${parsed.number}',
          ].join(' · '),
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
    changed?.call();
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
    // Kept, so that it is not brought back from another device.
    _db.execute('INSERT OR REPLACE INTO agenda_removed(id, at) VALUES(?,?)', [
      id,
      DateTime.now().toIso8601String(),
    ]);
    changed?.call();
  }

  /// The agenda as the lawyer's other devices take it (docs/buro.md,
  /// Senkron): their own rows, those taken off, and their word on the
  /// notices' deadlines. Notices' old rows stay on each device.
  Map<String, Object?> agendaExport() => {
    'satirlar': [
      for (final r in _db.select(
        'SELECT * FROM agenda WHERE id NOT IN '
        '(SELECT legacy_id FROM deadline_legacy)',
      ))
        {for (final c in r.keys) c: r[c]},
    ],
    'silinen': {
      for (final r in _db.select('SELECT id, at FROM agenda_removed'))
        r['id'] as String: r['at'] as String,
    },
    'kararlar': [
      for (final r in _db.select('SELECT * FROM deadline_user'))
        {for (final c in r.keys) c: r[c]},
    ],
    // The deadlines the lawyer chose, and whom they act for in a case.
    'secimler': [
      for (final r in _db.select(
        'SELECT id, notice_id, json FROM deadline_choice',
      ))
        {for (final c in r.keys) c: r[c]},
    ],
    'temsil': [
      for (final r in _db.select('SELECT * FROM case_representation'))
        {for (final c in r.keys) c: r[c]},
    ],
    // The clients' cards, minutes and powers of attorney.
    ...clientsExport(),
  };

  /// The notices whose deadlines the last [agendaMerge] gave other grounds
  /// to (a deadline chosen, whom the lawyer acts for), to be made again.
  Set<String> mergedNotices = const {};

  /// Takes another device's [agendaExport]: the newer of each row, and
  /// what was taken off after it was last changed. True when anything here
  /// changed.
  bool agendaMerge(Object? theirs) {
    if (theirs is! Map) return false;
    var changedHere = false;
    DateTime when(Object? v) =>
        DateTime.tryParse('${v ?? ''}') ?? DateTime(2000);
    final removed = <String, DateTime>{
      for (final r in _db.select('SELECT id, at FROM agenda_removed'))
        r['id'] as String: when(r['at']),
    };
    final mine = <String, DateTime>{
      for (final r in _db.select('SELECT id, updated FROM agenda'))
        r['id'] as String: when(r['updated']),
    };
    // Two rows changed at the same moment, or decisions kept before their
    // time was: the same one is taken on both devices, the larger by its
    // words, so that they end alike.
    String words(Map r, List<String> columns) =>
        jsonEncode([for (final c in columns) r[c]]);
    const agendaColumns = [
      'kind',
      'title',
      'body',
      'at',
      'all_day',
      'done',
      'case_key',
      'hearing_key',
    ];
    const decisionColumns = [
      'done',
      'manual_day',
      'title_override',
      'body_override',
      'confirmed_inputs',
      'confirmed_at',
      'confirmed_day',
      'dismissed',
    ];
    bool newer(
      DateTime theirs,
      DateTime? kept,
      Map r,
      String table,
      String key,
      String id,
      List<String> columns,
    ) {
      if (kept == null || theirs.isAfter(kept)) return true;
      if (theirs.isBefore(kept)) return false;
      final here = _db.select('SELECT * FROM $table WHERE $key=?', [id]);
      return here.isNotEmpty &&
          words(r, columns).compareTo(words(here.first, columns)) > 0;
    }

    _db.execute('BEGIN');
    try {
      final gone = theirs['silinen'];
      if (gone is Map) {
        for (final e in gone.entries) {
          final id = '${e.key}', at = when(e.value);
          final had = mine[id];
          if (had != null && !had.isAfter(at)) {
            _db.execute('DELETE FROM agenda WHERE id=?', [id]);
            mine.remove(id);
            changedHere = true;
          }
          if (removed[id] == null || removed[id]!.isBefore(at)) {
            _db.execute(
              'INSERT OR REPLACE INTO agenda_removed(id, at) VALUES(?,?)',
              [id, at.toIso8601String()],
            );
            removed[id] = at;
          }
        }
      }
      for (final r in (theirs['satirlar'] as List? ?? const [])) {
        if (r is! Map || r['id'] is! String || r['kind'] is! String) continue;
        final id = r['id'] as String, updated = when(r['updated']);
        if (removed[id] != null && !updated.isAfter(removed[id]!)) continue;
        if (!newer(updated, mine[id], r, 'agenda', 'id', id, agendaColumns)) {
          continue;
        }
        _db.execute(
          '''INSERT OR REPLACE INTO agenda
             (id, kind, title, body, at, all_day, done, case_key, hearing_key,
              updated) VALUES(?,?,?,?,?,?,?,?,?,?)''',
          [
            id,
            r['kind'],
            '${r['title'] ?? ''}',
            '${r['body'] ?? ''}',
            r['at'] is String ? r['at'] : null,
            r['all_day'] == 1 ? 1 : 0,
            r['done'] == 1 ? 1 : 0,
            r['case_key'] is String ? r['case_key'] : null,
            r['hearing_key'] is String ? r['hearing_key'] : null,
            updated.toIso8601String(),
          ],
        );
        changedHere = true;
      }
      final decided = <String, DateTime>{
        for (final r in _db.select(
          'SELECT deadline_id, updated FROM deadline_user',
        ))
          r['deadline_id'] as String: when(r['updated']),
      };
      for (final r in (theirs['kararlar'] as List? ?? const [])) {
        if (r is! Map || r['deadline_id'] is! String) continue;
        final id = r['deadline_id'] as String, updated = when(r['updated']);
        if (!newer(
          updated,
          decided[id],
          r,
          'deadline_user',
          'deadline_id',
          id,
          decisionColumns,
        )) {
          continue;
        }
        String? text(String k) => r[k] is String ? r[k] as String : null;
        _db.execute(
          '''INSERT OR REPLACE INTO deadline_user(deadline_id, done,
             manual_day, title_override, body_override, confirmed_inputs,
             confirmed_at, dismissed, updated, confirmed_day)
             VALUES(?,?,?,?,?,?,?,?,?,?)''',
          [
            id,
            r['done'] == 1 ? 1 : 0,
            text('manual_day'),
            text('title_override'),
            text('body_override'),
            text('confirmed_inputs'),
            text('confirmed_at'),
            r['dismissed'] == 1 ? 1 : 0,
            updated.toIso8601String(),
            text('confirmed_day'),
          ],
        );
        changedHere = true;
      }
      final touched = <String>{};
      for (final r in (theirs['secimler'] as List? ?? const [])) {
        if (r is! Map || r['id'] is! String || r['notice_id'] is! String) {
          continue;
        }
        if (r['json'] is! String) continue;
        final had = _db.select('SELECT 1 FROM deadline_choice WHERE id=?', [
          r['id'],
        ]);
        if (had.isNotEmpty) continue;
        _db.execute(
          'INSERT INTO deadline_choice(id, notice_id, json) VALUES(?,?,?)',
          [r['id'], r['notice_id'], r['json']],
        );
        touched.add(r['notice_id'] as String);
        changedHere = true;
      }
      for (final r in (theirs['temsil'] as List? ?? const [])) {
        if (r is! Map || r['case_key'] is! String || r['json'] is! String) {
          continue;
        }
        final key = r['case_key'] as String, updated = when(r['updated']);
        final here = _db.select(
          'SELECT updated FROM case_representation WHERE case_key=?',
          [key],
        );
        if (here.isNotEmpty && !updated.isAfter(when(here.first['updated']))) {
          continue;
        }
        _db.execute(
          'INSERT OR REPLACE INTO case_representation(case_key, json, updated) '
          'VALUES(?,?,?)',
          [key, r['json'], updated.toIso8601String()],
        );
        for (final n in _db.select('SELECT id FROM uets WHERE case_key=?', [
          key,
        ])) {
          touched.add(n['id'] as String);
        }
        changedHere = true;
      }
      mergedNotices = touched;
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      return false;
    }
    // In a transaction of its own: what the agenda took stands if a client
    // does not.
    try {
      final allowed = clientMoneyAllowed?.call() ?? true;
      if (clientsMerge(theirs.cast<String, Object?>(), money: allowed)) {
        changedHere = true;
      }
      if (!allowed) {
        forgetClientMoney(keepPerson: clientPerson?.call() ?? '');
      }
    } catch (_) {}
    return changedHere;
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

  // Notices' packages

  /// What a notice's package gave, as kept: 'indirildi' (the envelope read),
  /// 'zarfYok' (a package without an envelope), 'metinYok' (an envelope
  /// with no text layer) or 'hata'; and where its files are.
  void saveEnvelope(NoticeEnvelope e) => _db.execute(
    '''INSERT OR REPLACE INTO uets_envelope(notice_id, state, folder,
       package_path, envelope_path, envelope_text, attachments, fetched_at,
       error) VALUES(?,?,?,?,?,?,?,?,?)''',
    [
      e.noticeId,
      e.state,
      e.folder,
      e.packagePath,
      e.envelopePath,
      e.envelopeText,
      jsonEncode([
        for (final a in e.attachments) {'ad': a.name, 'yol': a.path},
      ]),
      e.fetchedAt?.toIso8601String(),
      e.error,
    ],
  );

  NoticeEnvelope? envelope(String noticeId) {
    final rows = _db.select('SELECT * FROM uets_envelope WHERE notice_id=?', [
      noticeId,
    ]);
    return rows.isEmpty ? null : _envelope(rows.first);
  }

  Map<String, NoticeEnvelope> envelopes() => {
    for (final r in _db.select('SELECT * FROM uets_envelope'))
      r['notice_id'] as String: _envelope(r),
  };

  NoticeEnvelope _envelope(Row r) => NoticeEnvelope(
    noticeId: r['notice_id'] as String,
    state: r['state'] as String,
    folder: r['folder'] as String?,
    packagePath: r['package_path'] as String?,
    envelopePath: r['envelope_path'] as String?,
    envelopeText: r['envelope_text'] as String?,
    attachments: [
      for (final a in jsonDecode(r['attachments'] as String) as List)
        if (a is Map) (name: '${a['ad']}', path: '${a['yol']}'),
    ],
    fetchedAt: r['fetched_at'] == null
        ? null
        : DateTime.parse(r['fetched_at'] as String),
    error: r['error'] as String?,
  );

  /// A notice's documents as read (see [readNoticeDocuments]), all of
  /// them at once in place of those read before.
  void saveNoticeDocuments(String noticeId, List<NoticeDocument> docs) {
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM uets_document WHERE notice_id=?', [noticeId]);
      for (final d in docs) {
        _db.execute(
          '''INSERT INTO uets_document(notice_id, seq, name, path, part_id,
             digest, state, text, note, reader, read_at)
             VALUES(?,?,?,?,?,?,?,?,?,?,?)''',
          [
            d.noticeId,
            d.seq,
            d.name,
            d.path,
            d.partId,
            d.digest,
            d.state,
            d.text,
            d.note,
            d.reader,
            d.readAt.toIso8601String(),
          ],
        );
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// A case's parties as UYAP gave them, one row each: name, role, its
  /// lawyers, person or institution, and where they came from ('uyap', a
  /// case fetched; 'taraflar', the parties read on their own; 'paket', a
  /// notice's package). All of a case's at once, in place of those kept
  /// before; a source no better than the one kept does not replace it.
  /// Kept for whose a deadline is, and for the clients' own accounts to
  /// come.
  void saveCaseParties(
    String caseKey,
    List<UyapParty> parties, {
    required String source,
  }) {
    if (parties.isEmpty) return;
    const rank = {'paket': 0, 'taraflar': 1, 'uyap': 2};
    final kept = _db.select(
      'SELECT kaynak FROM case_party WHERE case_key=? LIMIT 1',
      [caseKey],
    );
    if (kept.isNotEmpty &&
        (rank[kept.first['kaynak']] ?? 0) > (rank[source] ?? 0)) {
      return;
    }
    // The same parties from the same source: kept as they are, with the
    // day they came.
    final same = caseParties(caseKey: caseKey)[caseKey];
    if (kept.isNotEmpty &&
        kept.first['kaynak'] == source &&
        same != null &&
        same.length == parties.length &&
        [
          for (var i = 0; i < same.length; i++)
            same[i].name == parties[i].name &&
                same[i].role == parties[i].role &&
                same[i].lawyer == parties[i].lawyer &&
                same[i].kind == parties[i].kind,
        ].every((x) => x)) {
      return;
    }
    final at = DateTime.now().toIso8601String();
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM case_party WHERE case_key=?', [caseKey]);
      for (var i = 0; i < parties.length; i++) {
        final t = parties[i];
        _db.execute(
          'INSERT INTO case_party(case_key, seq, ad, rol, vekil, tur, kaynak, '
          'alindi) VALUES(?,?,?,?,?,?,?,?)',
          [caseKey, i, t.name, t.role, t.lawyer, t.kind, source, at],
        );
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Every case's parties kept, by case key; of [caseKey] alone when given.
  Map<String, List<UyapParty>> caseParties({String? caseKey}) {
    final out = <String, List<UyapParty>>{};
    for (final r in _db.select(
      'SELECT * FROM case_party'
      '${caseKey == null ? '' : ' WHERE case_key=?'} ORDER BY case_key, seq',
      [?caseKey],
    )) {
      (out[r['case_key'] as String] ??= []).add(
        UyapParty(
          r['ad'] as String,
          r['rol'] as String,
          r['vekil'] as String,
          r['tur'] as String,
        ),
      );
    }
    return out;
  }

  /// The lawyer's clients in [caseKey]: the parties they said they act for,
  /// else those whose lawyers name [lawyer] in UYAP.
  List<({String ad, String rol})> clientsOf(String caseKey, {String? lawyer}) {
    final said = representation(caseKey);
    if (said.isNotEmpty) return said;
    return [
      for (final t in caseParties(caseKey: caseKey)[caseKey] ?? const [])
        if (vekilOlarakGeciyor(t.lawyer, lawyer)) (ad: t.name, rol: t.role),
    ];
  }

  /// Whom the lawyer said they act for in the case [caseKey]: each party's
  /// name and role; empty while not said.
  List<({String ad, String rol})> representation(String caseKey) {
    final rows = _db.select(
      'SELECT json FROM case_representation WHERE case_key=?',
      [caseKey],
    );
    if (rows.isEmpty) return const [];
    return [
      for (final t in jsonDecode(rows.first['json'] as String) as List)
        if (t is Map) (ad: '${t['ad']}', rol: '${t['rol']}'),
    ];
  }

  /// [parties] the lawyer acts for in [caseKey]; none forgets it.
  void setRepresentation(
    String caseKey,
    List<({String ad, String rol})> parties,
  ) {
    // None said is kept too, as an empty word: the lawyer's other devices
    // would bring the old one back otherwise.
    _db.execute(
      'INSERT OR REPLACE INTO case_representation(case_key, json, updated) '
      'VALUES(?,?,?)',
      [
        caseKey,
        jsonEncode([
          for (final t in parties) {'ad': t.ad, 'rol': t.rol},
        ]),
        DateTime.now().toIso8601String(),
      ],
    );
  }

  /// A deadline the lawyer chose for a notice (see [DeadlineChoice]).
  void saveDeadlineChoice(DeadlineChoice c) => _db.execute(
    'INSERT OR REPLACE INTO deadline_choice(id, notice_id, json) '
    'VALUES(?,?,?)',
    [c.id, c.noticeId, jsonEncode(c.toJson())],
  );

  List<DeadlineChoice> deadlineChoices(String noticeId) => [
    for (final r in _db.select(
      'SELECT json FROM deadline_choice WHERE notice_id=? ORDER BY rowid',
      [noticeId],
    ))
      DeadlineChoice.fromJson(jsonDecode(r['json'] as String) as Map),
  ];

  List<NoticeDocument> noticeDocuments(String noticeId) => [
    for (final r in _db.select(
      'SELECT * FROM uets_document WHERE notice_id=? ORDER BY seq',
      [noticeId],
    ))
      _document(r),
  ];

  NoticeDocument _document(Row r) => NoticeDocument(
    noticeId: r['notice_id'] as String,
    seq: r['seq'] as int,
    name: r['name'] as String,
    path: r['path'] as String,
    partId: r['part_id'] as String?,
    digest: r['digest'] as String,
    state: r['state'] as String,
    text: r['text'] as String,
    note: r['note'] as String?,
    reader: r['reader'] as int,
    readAt: DateTime.parse(r['read_at'] as String),
  );

  // Notices' deadlines

  /// The notices' deadlines; of [noticeId] alone when given; with
  /// [decidedOnly], only those the lawyer did something with (confirmed,
  /// gave a day, marked, set aside), the only ones the agenda can show:
  /// the rest are not read at all.
  List<KeptDeadline> deadlines({
    String? noticeId,
    bool decidedOnly = false,
  }) => [
    for (final r
        in noticeId == null
            ? _db.select(
                'SELECT d.*, u.deadline_id AS u_id, u.done, u.manual_day, '
                'u.title_override, u.body_override, u.confirmed_inputs, '
                'u.confirmed_at, u.dismissed, u.confirmed_day AS u_day, '
                '$_confirmedDay FROM deadline d '
                '${decidedOnly ? 'JOIN' : 'LEFT JOIN'} '
                'deadline_user u ON u.deadline_id = d.id ORDER BY d.due_day',
              )
            : _db.select(
                'SELECT d.*, u.deadline_id AS u_id, u.done, u.manual_day, '
                'u.title_override, u.body_override, u.confirmed_inputs, '
                'u.confirmed_at, u.dismissed, u.confirmed_day AS u_day, '
                '$_confirmedDay FROM deadline d LEFT JOIN '
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
      'u.confirmed_at, u.dismissed, u.confirmed_day AS u_day, '
      '$_confirmedDay FROM deadline d LEFT JOIN deadline_user u '
      'ON u.deadline_id = d.id WHERE d.id=?',
      [id],
    );
    return rows.isEmpty ? null : _keptDeadline(rows.first);
  }

  /// The day a deadline had when the lawyer confirmed it: its history's
  /// line of the inputs confirmed.
  static const _confirmedDay =
      '(SELECT h.due_day FROM deadline_history h WHERE h.deadline_id = d.id '
      'AND h.inputs = u.confirmed_inputs ORDER BY h.seq DESC LIMIT 1) '
      'AS confirmed_day';

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
            confirmedDay: r['u_day'] as String?,
          );
    return KeptDeadline(
      record,
      user,
      // Kept with the confirmation, else read from the history.
      confirmedDay: r['u_day'] as String? ?? r['confirmed_day'] as String?,
    );
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

  void saveDeadlineUser(DeadlineUser u) {
    _db.execute(
      '''INSERT OR REPLACE INTO deadline_user(deadline_id, done, manual_day,
         title_override, body_override, confirmed_inputs, confirmed_at,
         dismissed, updated, confirmed_day) VALUES(?,?,?,?,?,?,?,?,?,?)''',
      [
        u.deadlineId,
        u.done ? 1 : 0,
        u.manualDay,
        u.titleOverride,
        u.bodyOverride,
        u.confirmedInputs,
        u.confirmedAt?.toIso8601String(),
        u.dismissed ? 1 : 0,
        DateTime.now().toIso8601String(),
        u.confirmedDay,
      ],
    );
    changed?.call();
  }

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
        confirmedDay: kept.record.dueDay,
      ),
    );
    return true;
  }

  // The agenda rows the notices' deadlines were kept in before

  /// The notices' deadline rows of the agenda not yet carried over; of
  /// [noticeId] alone when given.
  List<AgendaItem> legacyNoticeDeadlines({String? noticeId}) => _agendaRows(
    _db.select(
      "SELECT * FROM agenda WHERE kind='deadline' AND id LIKE ? "
      'AND id NOT IN (SELECT legacy_id FROM deadline_legacy)',
      [noticeId == null ? 'uets:%' : 'uets:$noticeId:%'],
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

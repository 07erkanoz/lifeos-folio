import 'dart:convert';

import '../portal/portal_channel.dart';
import '../portal/portal_database.dart';
import '../portal/portal_hearing.dart';
import '../portal/portal_sync.dart';
import '../portal/uyap_notice.dart';
import '../uyap/uyap_case_store.dart';

/// Senkron's "UYAP verileri": what one of the person's own devices read of
/// UYAP, given to the others, so that UYAP is asked once for all of them.
///
/// Each sync sends only a summary: a digest of each case kept, when each
/// case's list was fetched, which notifications are kept, a digest of the
/// coming hearings, and when UYAP was last read. The other device asks for
/// what it lacks or has older, a part at a time, and takes it in by the
/// rules a portal's answer goes by: the newer of each field wins, nothing
/// is marked new. The times come last, with what they cover, so that the
/// other device's own reading waits as if it had read itself.
///
/// Only between one person's own devices, on their key's proof
/// (OfficeNetwork's vouched channel); never to the office.
class UyapOwnSync {
  UyapOwnSync({required this.database, this._store, required this.ask});

  final Future<PortalDatabase> Function() database;
  final UyapCaseStore? _store;
  UyapCaseStore get store => _store ?? UyapCaseStore.instance;

  /// Asks the own device [deviceId] for [body]; null when it did not answer.
  final Future<Map<String, Object?>?> Function(
    String deviceId,
    Map<String, Object?> body,
  )
  ask;

  /// What one own device asks another for, by this name.
  static const kind = 'uyap-al';

  /// The times taken over from another own device: when the whole portfolio
  /// was read, each channel's hearings, and the notifications.
  static const stamps = [
    'portfolio_at',
    'hearings_at:uyapMobile',
    'hearings_at:uyapWeb',
    PortalSync.noticesAtKey,
    'uyap_notice_mobile',
    'uyap_notice_web',
  ];

  /// The hearings given: a month back to three ahead, as UYAP is read.
  static ({DateTime from, DateTime to}) window(DateTime now) => (
    from: now.subtract(const Duration(days: 30)),
    to: now.add(const Duration(days: 90)),
  );

  // Small enough parts for a message of a megabyte, a case's long list of
  // documents and a notification's long body included.
  static const _casesAtOnce = 50, _recordsAtOnce = 3, _noticesAtOnce = 50;

  /// This device's summary, for another own device to compare.
  Future<Map<String, Object?>> summary(String deviceId) async {
    final db = await database();
    final hearings = _hearings(db);
    return {
      'cihaz': deviceId,
      'damga': {for (final k in stamps) k: ?db.meta(k)},
      'davalar': db.caseDigests(),
      'kayitlar': {
        for (final e in (await _fetched()).entries)
          e.key: e.value.toIso8601String(),
      },
      'bildirimler': {
        for (final e in db.uyapNoticeKeys().entries) e.key: e.value,
      },
      'durusmalar': PortalDatabase.digestOf(jsonEncode(hearings)),
    };
  }

  List<Map<String, Object?>> _hearings(PortalDatabase db) {
    final w = window(DateTime.now());
    final list = [
      for (final h in db.hearings(from: w.from, to: w.to)) h.toJson(),
    ]..sort((a, b) => '${a['key']}'.compareTo('${b['key']}'));
    return list;
  }

  /// Takes in what another own device's [theirs] summary says it has newer
  /// or more. True when anything here changed.
  Future<bool> merge(Object? theirs) async {
    if (theirs is! Map || theirs['cihaz'] is! String) return false;
    final from = theirs['cihaz'] as String;
    final db = await database();
    var changed = false;
    var whole = true;

    Future<Map<String, Object?>?> asked(Map<String, Object?> body) async {
      final answer = await ask(from, body);
      if (answer == null) whole = false;
      return answer;
    }

    // Cases whose kept form differs: theirs taken in field by field.
    final mine = db.caseDigests();
    final cases = [
      for (final MapEntry(:key, :value)
          in ((theirs['davalar'] as Map?) ?? const {}).entries)
        if (mine['$key'] != '$value') '$key',
    ];
    for (var i = 0; i < cases.length; i += _casesAtOnce) {
      final answer = await asked({
        'parca': 'davalar',
        'anahtarlar': cases.sublist(i, _end(i, _casesAtOnce, cases.length)),
      });
      final got = answer?['davalar'];
      if (got is! List) continue;
      if (got.length < _end(i, _casesAtOnce, cases.length) - i) whole = false;
      if (db.adoptCases([
            for (final c in got)
              if (c is Map) c.cast<String, Object?>(),
          ]) >
          0) {
        changed = true;
      }
    }

    // Each case's list, where theirs was fetched later.
    final fetched = await _fetched();
    final records = [
      for (final MapEntry(:key, :value)
          in ((theirs['kayitlar'] as Map?) ?? const {}).entries)
        if (DateTime.tryParse('$value') case final at?)
          if (fetched['$key'] == null || at.isAfter(fetched['$key']!)) '$key',
    ];
    for (var i = 0; i < records.length; i += _recordsAtOnce) {
      final answer = await asked({
        'parca': 'kayitlar',
        'anahtarlar': records.sublist(
          i,
          _end(i, _recordsAtOnce, records.length),
        ),
      });
      final got = answer?['kayitlar'];
      if (got is! List) continue;
      if (got.length < _end(i, _recordsAtOnce, records.length) - i) {
        whole = false;
      }
      for (final r in got) {
        if (r is Map && await store.adopt(r.cast<String, Object?>())) {
          changed = true;
        }
      }
    }

    // Notifications not kept here, or read or unread there and not here.
    final kept = db.uyapNoticeKeys();
    final notices = [
      for (final MapEntry(:key, :value)
          in ((theirs['bildirimler'] as Map?) ?? const {}).entries)
        if (!kept.containsKey('$key') ||
            (value is bool && kept['$key'] != value))
          '$key',
    ];
    for (var i = 0; i < notices.length; i += _noticesAtOnce) {
      final answer = await asked({
        'parca': 'bildirimler',
        'anahtarlar': notices.sublist(
          i,
          _end(i, _noticesAtOnce, notices.length),
        ),
      });
      final got = answer?['bildirimler'];
      if (got is! List) continue;
      if (got.length < _end(i, _noticesAtOnce, notices.length) - i) {
        whole = false;
      }
      final rows = [
        for (final r in got)
          if (r is Map) ?noticeFromJson(r.cast<String, Object?>()),
      ];
      if (db.adoptUyapNotices(rows) > 0 || rows.isNotEmpty) changed = true;
    }

    final stamped = (theirs['damga'] as Map?) ?? const {};
    DateTime? latest(DateTime? Function(String key) at) {
      DateTime? last;
      for (final k in ['hearings_at:uyapMobile', 'hearings_at:uyapWeb']) {
        final t = at(k);
        if (t != null && (last == null || t.isAfter(last))) last = t;
      }
      return last;
    }

    final theirRead = latest((k) => DateTime.tryParse('${stamped[k] ?? ''}'));
    final myRead = latest((k) => DateTime.tryParse(db.meta(k) ?? ''));
    // The coming hearings, when theirs differ and were read later than
    // these: an older list would bring back a hearing taken off here since.
    // A hearing taken off goes only by a whole reading of the web portal's
    // today there, newer than this one's: as here, nothing else takes one
    // off.
    if (theirRead != null &&
        (myRead == null || theirRead.isAfter(myRead)) &&
        '${theirs['durusmalar']}' !=
            PortalDatabase.digestOf(jsonEncode(_hearings(db)))) {
      final answer = await asked({'parca': 'durusmalar'});
      final got = answer?['durusmalar'];
      if (got is List) {
        final list = [
          for (final h in got)
            if (h is Map) PortalHearing.fromJson(h.cast<String, Object?>()),
        ];
        final theirWeb = DateTime.tryParse(
          '${stamped['hearings_at:uyapWeb'] ?? ''}',
        );
        final myWeb = DateTime.tryParse(db.meta('hearings_at:uyapWeb') ?? '');
        final now = DateTime.now();
        final removes =
            theirWeb != null &&
            _sameDay(theirWeb, now) &&
            (myWeb == null || theirWeb.isAfter(myWeb));
        final w = window(now);
        db.mergeHearings(
          removes ? PortalChannel.uyapWeb : PortalChannel.uyapMobile,
          w.from,
          w.to,
          list,
          complete: removes,
        );
        changed = true;
      }
    }

    // The times, last and only with all of it here: a reading another own
    // device made counts here as made, and is not made again yet.
    if (whole) {
      for (final k in stamps) {
        final at = DateTime.tryParse('${stamped[k] ?? ''}');
        if (at == null) continue;
        final mineAt = DateTime.tryParse(db.meta(k) ?? '');
        if (mineAt == null || at.isAfter(mineAt)) {
          db.setMeta(k, at.toIso8601String());
        }
      }
    }
    if (changed) {
      PortalSync.started?.portfolioVersion.value++;
      PortalSync.started?.noticesVersion.value++;
      PortalSync.started?.notifyListeners();
    }
    return changed;
  }

  /// What another own device asked for: a part of what is kept here.
  Future<Map<String, Object?>> answer(Map<String, Object?> asked) async {
    final db = await database();
    final keys = [
      for (final k in (asked['anahtarlar'] as List?) ?? const []) '$k',
    ];
    switch (asked['parca']) {
      case 'davalar':
        return {'davalar': db.casesOf(keys.take(_casesAtOnce))};
      case 'kayitlar':
        return {
          'kayitlar': [
            for (final k in keys.take(_recordsAtOnce))
              ?await store.recordToShare(k),
          ],
        };
      case 'bildirimler':
        return {
          'bildirimler': [
            for (final r in db.uyapNoticesOf(keys.take(_noticesAtOnce)))
              noticeToJson(r),
          ],
        };
      case 'durusmalar':
        return {'durusmalar': _hearings(db)};
    }
    return const {};
  }

  /// When each kept case's list was fetched; none when the store cannot
  /// be read here.
  Future<Map<String, DateTime>> _fetched() async {
    try {
      return await store.fetchedTimes();
    } catch (_) {
      return const {};
    }
  }

  static int _end(int i, int step, int length) =>
      i + step > length ? length : i + step;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static Map<String, Object?> noticeToJson(UyapNoticeRow r) => {
    'kaynak': r.source.name,
    'id': r.id,
    'mesaj': r.messageId,
    'baslik': r.title,
    'metin': r.body,
    'gonderildi': r.sentAt?.toIso8601String(),
    'uyapOkundu': r.remoteRead,
    'okundu': r.localRead,
  };

  static UyapNoticeRow? noticeFromJson(Map<String, Object?> j) {
    final source = UyapNoticeSource.values
        .where((s) => s.name == j['kaynak'])
        .firstOrNull;
    final id = j['id'];
    if (source == null || id is! String || id.isEmpty) return null;
    return UyapNoticeRow(
      source: source,
      id: id,
      messageId: '${j['mesaj'] ?? ''}',
      title: '${j['baslik'] ?? ''}',
      body: '${j['metin'] ?? ''}',
      sentAt: DateTime.tryParse('${j['gonderildi'] ?? ''}'),
      remoteRead: j['uyapOkundu'] is bool ? j['uyapOkundu'] as bool : null,
      localRead: j['okundu'] is bool ? j['okundu'] as bool : null,
    );
  }
}

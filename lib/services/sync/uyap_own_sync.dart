import 'dart:convert';

import '../portal/case_sections.dart';
import '../portal/observed.dart' show caseKey;
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
    'portfolio_web_only_at',
    'web_prosecutor_full_at',
    'web_enriched_at',
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

  /// What the records of one answer come to at most, under the megabyte a
  /// message carries once sealed and in base64.
  static const _recordBytes = 600 * 1024;

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
          e.key: e.value.at.toIso8601String(),
      },
      // Which sections were read when, apart: a section read on one device
      // is asked by the other though the latest time is the same.
      'bolumOzeti': {
        for (final e in (await _fetched()).entries) e.key: e.value.sections,
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
      if (got is! List) {
        whole = false;
        continue;
      }
      final valid = [
        for (final c in got)
          if (c is Map && c.isNotEmpty) c.cast<String, Object?>(),
      ];
      if (valid.length < _end(i, _casesAtOnce, cases.length) - i) {
        whole = false;
      }
      if (db.adoptCases(valid) > 0) {
        changed = true;
      }
    }

    // Each case's list, where theirs was read later (its record or one of
    // its sections), or as late with other sections read.
    final fetched = await _fetched();
    final theirSections = (theirs['bolumOzeti'] as Map?) ?? const {};
    bool later(String key, DateTime at) {
      final mine = fetched[key];
      if (mine == null || at.isAfter(mine.at)) return true;
      return at.isAtSameMomentAs(mine.at) &&
          theirSections[key] != null &&
          '${theirSections[key]}' != mine.sections;
    }

    final records = [
      for (final MapEntry(:key, :value)
          in ((theirs['kayitlar'] as Map?) ?? const {}).entries)
        if (DateTime.tryParse('$value') case final at?)
          if (later('$key', at)) '$key',
    ];
    // As many at a time as fit in a message (answer); asked again for the
    // rest until all came, or one comes that nothing fits.
    var left = records;
    while (left.isNotEmpty) {
      final batch = left.take(_recordsAtOnce).toList();
      final answer = await asked({'parca': 'kayitlar', 'anahtarlar': batch});
      final got = answer?['kayitlar'];
      if (got is! List || got.isEmpty) {
        whole = false;
        break;
      }
      final came = <String>{};
      for (final r in got) {
        if (r is! Map) continue;
        final json = r.cast<String, Object?>();
        final record = UyapCaseStore.keyOf(
          '${json['mahkeme'] ?? ''}',
          '${json['esas'] ?? ''}',
        );
        came.add(record);
        final key = caseKey(
          '${json['esas'] ?? ''}',
          '${json['mahkeme'] ?? ''}',
        );
        // Read later there, by its record or by its sections: its record is
        // taken whole with its sections. Not later: its sections only where
        // its record says what this one says, so that no section is said
        // read for data that is not here.
        final theirAt = _readAt(
          DateTime.tryParse('${json['cekildi'] ?? ''}'),
          json['bolumler'],
        );
        final mine = fetched[record];
        final newer =
            theirAt != null &&
            (mine == null ||
                theirAt.isAfter(mine.at) ||
                theirAt.isAtSameMomentAs(mine.at));
        final adopted = await store.adoptChecked(json, force: newer);
        final sameData =
            adopted == AdoptResult.kept ||
            (adopted == AdoptResult.older && await store.sameData(json));
        if (sameData) db.adoptSections(key, json['bolumler']);
        if (sameData) {
          // Read whole by the web there, as it says, as if here: not read
          // again here for it; also when only its sections came newer, the
          // record being the same. A device that does not say is not taken
          // at its data's word (money kept from before is no new reading).
          final at = _webReadWhole(db.sections(key));
          final mineAt = DateTime.tryParse(
            db.meta(PortalSync.webCheckedKey(key)) ?? '',
          );
          if (at != null && (mineAt == null || at.isAfter(mineAt))) {
            db.setMeta('case_checked:$key', at.toIso8601String());
            db.setMeta(PortalSync.webCheckedKey(key), at.toIso8601String());
            changed = true;
          }
        }
        switch (adopted) {
          case AdoptResult.kept:
            changed = true;
            // Its parties for the clients here too.
            if (await store.load(
                  '${json['mahkeme'] ?? ''}',
                  '${json['esas'] ?? ''}',
                )
                case final kept? when kept.parties.isNotEmpty) {
              db.saveCaseParties(key, kept.parties, source: 'uyap');
            }
          case AdoptResult.older:
            break;
          case AdoptResult.failed:
            whole = false;
        }
      }
      final rest = [
        for (final k in left)
          if (!came.contains(k)) k,
      ];
      // Nothing of the batch came: it is not asked for again without end.
      if (rest.length == left.length) {
        whole = false;
        break;
      }
      left = rest;
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
      if (got is! List) {
        whole = false;
        continue;
      }
      final rows = [
        for (final r in got)
          if (r is Map) ?noticeFromJson(r.cast<String, Object?>()),
      ];
      if (rows.length < _end(i, _noticesAtOnce, notices.length) - i) {
        whole = false;
      }
      if (db.adoptUyapNotices(rows) > 0 || rows.isNotEmpty) changed = true;
    }

    final stamped = (theirs['damga'] as Map?) ?? const {};
    // The coming hearings, when theirs differ and one of the channels was
    // read later there than here, each channel's time against its own: an
    // older list would bring back a hearing taken off here since. A
    // hearing taken off goes only by a whole reading of the web portal's
    // today there, newer than this one's: as here, nothing else takes one
    // off.
    bool newerThere(String k) {
      final there = DateTime.tryParse('${stamped[k] ?? ''}');
      final here = DateTime.tryParse(db.meta(k) ?? '');
      return there != null && (here == null || there.isAfter(here));
    }

    if ((newerThere('hearings_at:uyapMobile') ||
            newerThere('hearings_at:uyapWeb')) &&
        '${theirs['durusmalar']}' !=
            PortalDatabase.digestOf(jsonEncode(_hearings(db)))) {
      final answer = await asked({'parca': 'durusmalar'});
      final got = answer?['durusmalar'];
      if (got is! List) whole = false;
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

  /// When the web last read every section of a case done, by [sections]:
  /// the earliest of them; null while one is missing or failed last.
  static DateTime? _webReadWhole(List<SectionState> sections) {
    final web = {
      for (final s in sections)
        if (s.channel == PortalChannel.uyapWeb) s.section: s,
    };
    DateTime? at;
    for (final section in CaseSection.values) {
      final s = web[section];
      final done = s?.succeeded;
      if (s == null || done == null || !s.result.done) return null;
      if (at == null || done.isBefore(at)) at = done;
    }
    return at;
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
        // As many as fit in a message of a megabyte, sealed and in base64
        // (OfficeLink): the first always, the asker asks again for the rest.
        final out = <Map<String, Object?>>[];
        var size = 0;
        for (final k in keys.take(_recordsAtOnce)) {
          final shared = await store.recordToShare(k);
          if (shared == null) continue;
          // What each channel read of it there, said: not told from its data.
          final r = {
            ...shared,
            'bolumler': db.sectionsToShare(
              caseKey('${shared['esas'] ?? ''}', '${shared['mahkeme'] ?? ''}'),
            ),
          };
          final bytes = utf8.encode(jsonEncode(r)).length;
          if (out.isNotEmpty && size + bytes > _recordBytes) break;
          out.add(r);
          size += bytes;
        }
        return {'kayitlar': out};
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
  /// When each kept case was last read here: its record's reading, or
  /// a section read since (the record unchanged by it), whichever is later.
  /// So a section read on one device goes to the other though the case's
  /// record did not change.
  Future<Map<String, ({DateTime at, String sections})>> _fetched() async {
    try {
      final db = await database();
      return {
        for (final (record, _) in await store.cases(counted: false))
          if (db.sectionsToShare(caseKey(record.number, record.court))
              case final shared)
            record.key: (
              at: _readAt(record.fetchedAt, shared)!,
              sections: _sectionsDigest(shared),
            ),
      };
    } catch (_) {
      return const {};
    }
  }

  /// The latest of [fetched] and the successes of the sections [shared]
  /// (as [PortalDatabase.sectionsToShare] gives them).
  static DateTime? _readAt(DateTime? fetched, Object? shared) {
    var at = fetched;
    for (final s in shared is List ? shared : const []) {
      if (s is! Map) continue;
      final done = DateTime.tryParse('${s['basari'] ?? ''}');
      if (done != null && (at == null || done.isAfter(at))) at = done;
    }
    return at;
  }

  /// The sections read done, as a short digest: alike on two devices
  /// when they have read the same sections at the same times.
  static String _sectionsDigest(List<Map<String, Object?>> shared) {
    final lines = [
      for (final s in shared)
        '${s['bolum']}|${s['kanal']}|${s['basari']}|${s['kismi']}',
    ]..sort();
    return PortalDatabase.digestOf(lines.join(';'));
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

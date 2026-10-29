import 'dart:async';
import 'dart:convert';

import '../platform/system_notices.dart';
import 'lifeos_agenda.dart';
import 'portal_database.dart';
import 'uyap_notice_alerts.dart';

/// What the agenda has to tell now: a deadline's last day coming or gone,
/// a hearing tomorrow or today.
typedef AgendaReminder = ({
  String key,
  String title,
  String body,
  String payload,
});

/// The agenda's alarms (the audit's B23): a deadline followed is told 7, 3
/// and 1 days before its last day, on it, and once the day after if not
/// marked done; a hearing a day before and an hour before. Each once, kept
/// in the database, so that the window and the phone's background check
/// do not both tell it. Clicked, each opens the agenda at its record as
/// `--ajanda <uid>` does (payload `ajanda:<uid>`, LifeosAgenda.uidOf).
abstract final class AgendaReminders {
  static const _sentKey = 'ajanda_hatirlatma';
  static const _deadlineStages = {7, 3, 1, 0, -1};

  /// How long before a hearing it is told: a day, and an hour.
  static const _day1 = Duration(days: 1), _hour1 = Duration(hours: 1);

  static Set<String> _sent(PortalDatabase db) {
    try {
      return {
        for (final s in jsonDecode(db.meta(_sentKey) ?? '[]') as List) '$s',
      };
    } catch (_) {
      return {};
    }
  }

  static String _day(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}.'
      '${t.month.toString().padLeft(2, '0')}.${t.year}';

  /// What is due to be told at [now], each once; marked told only when
  /// [mark] (a test's check), else by [tell] once shown.
  static List<AgendaReminder> due(
    PortalDatabase db,
    DateTime now, {
    bool mark = true,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final sent = _sent(db);
    final out = <AgendaReminder>[];
    for (final d in db.deadlines(decidedOnly: false)) {
      if (!d.onAgenda || (d.user?.done ?? false)) continue;
      final day = DateTime.tryParse(d.day ?? '');
      if (day == null) continue;
      final left = DateTime(
        day.year,
        day.month,
        day.day,
      ).difference(today).inDays;
      if (!_deadlineStages.contains(left)) continue;
      final key = 's|${d.record.id}|${d.day}|$left';
      if (!sent.add(key)) continue;
      out.add((
        key: key,
        title: left < 0
            ? 'Süre doldu'
            : left == 0
            ? 'Bugün son gün'
            : '$left gün sonra son gün',
        body: '${d.record.title} · ${_day(day)}',
        payload:
            'ajanda:${LifeosAgenda.uidOf('sure', 'folio-sure-${d.record.id}')}',
      ));
    }
    // A hearing begun is not told of any more; one within the day is told
    // once, within the hour once more.
    for (final h in db.hearings(from: now, to: now.add(_day1 * 2))) {
      final left = h.at.difference(now);
      if (left > _day1) continue;
      final hour = left <= _hour1;
      final key = 'd|${h.key}|${hour ? '1s' : '1g'}';
      // An earlier Folio told the day before as `|1`.
      if (!hour && sent.contains('d|${h.key}|1')) continue;
      if (!sent.add(key)) continue;
      final time =
          '${h.at.hour.toString().padLeft(2, '0')}:'
          '${h.at.minute.toString().padLeft(2, '0')}';
      final minutes = left.inMinutes < 1 ? 1 : left.inMinutes;
      final day = DateTime(h.at.year, h.at.month, h.at.day);
      out.add((
        key: key,
        title: hour
            ? minutes >= 55
                  ? '1 saat sonra duruşma $time'
                  : '$minutes dakika sonra duruşma $time'
            : day == today
            ? 'Bugün duruşma $time'
            : 'Yarın duruşma $time',
        body: '${h.number} · ${h.court}',
        payload:
            'ajanda:${LifeosAgenda.uidOf('durusma', 'folio-durusma-${h.key}')}',
      ));
    }
    if (mark && out.isNotEmpty) _mark(db, [for (final r in out) r.key]);
    return out;
  }

  /// When after [now] a hearing is next due to be told: a day or an hour
  /// before it, whichever comes first; null with none in the next day.
  static DateTime? nextHearing(PortalDatabase db, DateTime now) {
    DateTime? next;
    for (final h in db.hearings(from: now, to: now.add(_day1 * 2))) {
      for (final at in [h.at.subtract(_day1), h.at.subtract(_hour1)]) {
        if (at.isAfter(now) && (next == null || at.isBefore(next))) next = at;
      }
    }
    return next;
  }

  /// [keys] told, kept so; the newest hundreds: the old are past telling.
  static void _mark(PortalDatabase db, List<String> keys) {
    final kept = [..._sent(db), ...keys];
    db.setMeta(
      _sentKey,
      jsonEncode(kept.length > 800 ? kept.sublist(kept.length - 800) : kept),
    );
  }

  /// Tells what is due through [notices]; [private], what may show of it
  /// (locked, or in the phone's background: only that something is due).
  static Future<int> tell(
    PortalDatabase db, {
    SystemNotices? notices,
    bool Function()? private,
    DateTime? now,
    bool ask = false,
  }) async {
    final system = notices ?? SystemNotices.instance;
    final todo = due(db, now ?? DateTime.now(), mark: false);
    final told = <String>[];
    final quiet = !UyapNoticeAlerts.of(db).details;
    for (final r in todo) {
      final hide = quiet || (private?.call() ?? false);
      final ok = await system
          .shown(
            id: r.key.hashCode & 0x7fffffff,
            title: hide ? 'LifeOS Folio' : r.title,
            body: hide ? 'Ajandada yaklaşan bir iş var' : r.body,
            payload: r.payload,
            // Asked for in sight; in the background there is no one to ask.
            ask: ask,
          )
          .catchError((Object _) => false);
      // Not shown (no leave yet): told again at the next check.
      if (ok) told.add(r.key);
    }
    if (told.isNotEmpty) _mark(db, told);
    return told.length;
  }

  static Timer? _timer, _hearing;

  /// Checks now and every half hour while Folio runs, and at the minute a
  /// hearing is next due to be told: an hour before is not half an hour
  /// late.
  static void start({bool Function()? private}) {
    _timer?.cancel();
    Future<void> check() async {
      try {
        final db = await PortalDatabase.shared();
        await tell(db, private: private, ask: true);
        _hearing?.cancel();
        final next = nextHearing(db, DateTime.now());
        if (next != null) {
          _hearing = Timer(
            next.difference(DateTime.now()) + const Duration(seconds: 1),
            () => unawaited(check()),
          );
        }
      } catch (_) {}
    }

    unawaited(check());
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => check());
  }
}

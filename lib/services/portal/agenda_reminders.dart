import 'dart:async';
import 'dart:convert';

import '../platform/system_notices.dart';
import 'portal_database.dart';

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
/// marked done; a hearing the day before and on its day. Each once, kept
/// in the database, so that the window and the phone's background check
/// do not both tell it.
abstract final class AgendaReminders {
  static const _sentKey = 'ajanda_hatirlatma';
  static const _deadlineStages = {7, 3, 1, 0, -1};

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

  /// What is due to be told at [now], each once; marked told.
  static List<AgendaReminder> due(PortalDatabase db, DateTime now) {
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
        payload: 'ajanda:${d.record.id}',
      ));
    }
    for (final h in db.hearings(
      from: today,
      to: today.add(const Duration(days: 2)),
    )) {
      final left = DateTime(
        h.at.year,
        h.at.month,
        h.at.day,
      ).difference(today).inDays;
      if (left > 1) continue;
      final key = 'd|${h.key}|$left';
      if (!sent.add(key)) continue;
      final time =
          '${h.at.hour.toString().padLeft(2, '0')}:'
          '${h.at.minute.toString().padLeft(2, '0')}';
      out.add((
        key: key,
        title: left == 0 ? 'Bugün duruşma $time' : 'Yarın duruşma $time',
        body: '${h.number} · ${h.court}',
        payload: 'ajanda:${h.key}',
      ));
    }
    if (out.isNotEmpty) {
      // The newest hundreds kept: the old ones are past telling.
      final kept = sent.toList();
      db.setMeta(
        _sentKey,
        jsonEncode(kept.length > 800 ? kept.sublist(kept.length - 800) : kept),
      );
    }
    return out;
  }

  /// Tells what is due through [notices]; [private], what may show of it
  /// (locked, or in the phone's background: only that something is due).
  static Future<int> tell(
    PortalDatabase db, {
    SystemNotices? notices,
    bool Function()? private,
    DateTime? now,
  }) async {
    final system = notices ?? SystemNotices.instance;
    final todo = due(db, now ?? DateTime.now());
    for (final r in todo) {
      final hide = private?.call() ?? false;
      await system
          .show(
            id: r.key.hashCode & 0x7fffffff,
            title: hide ? 'LifeOS Folio' : r.title,
            body: hide ? 'Ajandada yaklaşan bir iş var' : r.body,
            payload: r.payload,
            ask: false,
          )
          .catchError((Object _) {});
    }
    return todo.length;
  }

  static Timer? _timer;

  /// Checks now and every half hour while Folio runs.
  static void start({bool Function()? private}) {
    _timer?.cancel();
    Future<void> check() async {
      try {
        await tell(await PortalDatabase.shared(), private: private);
      } catch (_) {}
    }

    unawaited(check());
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => check());
  }
}

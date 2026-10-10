import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../security/secret_store.dart';
import '../uyap/uyap_mobile_api.dart';
import 'agenda_reminders.dart';
import 'portal_database.dart';
import 'portal_sync.dart';
import 'uyap_notice.dart';
import 'uyap_notice_alerts.dart';

/// The phone's check for new UYAP notifications with Folio closed:
/// Android's WorkManager, at most every fifteen minutes; iOS's background
/// refresh, as often as iOS allows. UYAP Mobil's kept session is used;
/// nothing is asked of the lawyer. The computer does not need it: there
/// Folio stays in the tray when its window is closed.
abstract final class BackgroundNotices {
  /// The task's name, and on iOS its identifier in Info.plist's
  /// BGTaskSchedulerPermittedIdentifiers.
  static const task = 'com.erkanoz.evrak_convert.uyapNotices';

  /// When Folio was last in sight: within these minutes the check leaves
  /// it to the open app, not to renew one session twice at once.
  static const _seenKey = 'foreground_at';
  static const _quiet = Duration(minutes: 6);

  static bool get supported =>
      (Platform.isAndroid || Platform.isIOS) &&
      !Platform.environment.containsKey('FLUTTER_TEST');

  /// Schedules the check, or cancels it, as the lawyer chose.
  static Future<void> schedule(UyapNoticeAlerts alerts) async {
    if (!supported) return;
    try {
      await Workmanager().initialize(folioBackgroundDispatcher);
      // Always: the agenda's alarms need no UYAP and no network; the
      // UYAP check inside it goes by the lawyer's choice (see _check).
      await Workmanager().registerPeriodicTask(
        task,
        task,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      );
    } catch (_) {
      // No background work on this phone: notifications come while Folio
      // is open, as before.
    }
  }

  /// Folio in sight now; told by the open app.
  static void seen(PortalDatabase db) =>
      db.setMeta(_seenKey, DateTime.now().toIso8601String());

  static const _lastKey = 'background_check';

  /// When the check last asked UYAP.
  static const _askedKey = 'background_uyap_at';

  /// When the background check last ran, and what came of it; null when
  /// it never has. Shown in the settings, so that one can see it runs.
  static ({DateTime at, String result})? last(PortalDatabase db) {
    final kept = db.meta(_lastKey);
    if (kept == null) return null;
    final at = DateTime.tryParse(kept.split('|').first);
    if (at == null) return null;
    return (at: at, result: kept.substring(kept.indexOf('|') + 1));
  }

  static void _note(PortalDatabase db, String result) =>
      db.setMeta(_lastKey, '${DateTime.now().toIso8601String()}|$result');

  /// One check: UYAP Mobil's newest notifications kept, the new ones told.
  static Future<void> check() async {
    final db = await PortalDatabase.shared();
    // The agenda's alarms first, with or without a UYAP session: in the
    // background, only that something is due shows.
    try {
      await AgendaReminders.tell(db, private: () => true);
    } catch (_) {}
    try {
      _note(db, await _check(db));
    } catch (e) {
      _note(db, 'hata: $e');
      rethrow;
    }
  }

  static Future<String> _check(PortalDatabase db) async {
    final alerts = UyapNoticeAlerts.of(db);
    if (!alerts.on || !alerts.background) return 'kapalı';
    // Only when the lawyer has Folio read UYAP of itself.
    if (db.meta(PortalSync.autoKey) != '1') {
      return 'UYAP’tan kendiliğinden alma kapalı';
    }
    final seen = DateTime.tryParse(db.meta(_seenKey) ?? '');
    if (seen != null && DateTime.now().difference(seen) < _quiet) {
      return 'Folio açıktı, ona bırakıldı';
    }
    // The task wakes every quarter of an hour for the agenda's alarms;
    // UYAP is asked only as often as the open app asks it, and not at
    // night (PortalSync.noticeEvery).
    final now = DateTime.now();
    if (PortalSync.night(now)) return 'gece sorulmaz';
    // The last asking, here in the background or in the open app (or on
    // another own device, which Senkron brings): the same hour for both.
    DateTime? latest;
    for (final kept in [db.meta(_askedKey), db.meta(PortalSync.noticesAtKey)]) {
      final at = DateTime.tryParse(kept ?? '');
      if (at != null && (latest == null || at.isAfter(latest))) latest = at;
    }
    if (latest != null &&
        now.difference(latest) <
            PortalSync.noticeEvery - const Duration(minutes: 5)) {
      return 'son sorgudan bu yana bir saat geçmedi';
    }
    db.setMeta(_askedKey, now.toIso8601String());
    final secrets = SecretStore();
    const secret = 'uyap-mobile';
    final kept = MobileTokens.fromJson(await secrets.read(secret));
    if (kept == null) return 'UYAP Mobil oturumu yok';
    final api = UyapMobileApi.instance;
    api.keptTokens = () async =>
        MobileTokens.fromJson(await secrets.read(secret));
    final writes = <Future<void>>[];
    api.onTokens = (tokens) => writes.add(
      tokens == null
          ? secrets.remove(secret)
          : secrets.write(secret, tokens.toJson()),
    );
    try {
      if (await api.restore(kept) == null) {
        return 'UYAP Mobil oturumu sona ermiş';
      }
    } on UyapMobileUnreachable {
      return 'UYAP’a ulaşılamadı';
    }
    final sync = PortalSync(mobile: api, database: () async => db)
      ..paused = true;
    final fresh = <UyapNotice>[];
    sync.onNewNotices = fresh.addAll;
    try {
      await sync.syncNotices(force: true);
      if (fresh.isNotEmpty) await tellUyapNotices(db, fresh, ask: false);
      final problem = sync.noticeProblem;
      if (problem != null) return problem;
      return fresh.isEmpty
          ? 'yeni bildirim yok'
          : '${fresh.length} yeni bildirim bildirildi';
    } finally {
      await Future.wait(writes);
      sync.dispose();
    }
  }
}

/// Where Android and iOS start Folio's Dart for the background check.
@pragma('vm:entry-point')
void folioBackgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    try {
      await BackgroundNotices.check().timeout(const Duration(minutes: 8));
    } catch (_) {
      // Tried again at the next turn.
    }
    return true;
  });
}

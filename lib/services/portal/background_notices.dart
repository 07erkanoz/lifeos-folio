import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../security/secret_store.dart';
import '../uyap/uyap_mobile_api.dart';
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
      if (alerts.on && alerts.background) {
        await Workmanager().registerPeriodicTask(
          task,
          task,
          frequency: const Duration(minutes: 15),
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        );
      } else {
        await Workmanager().cancelByUniqueName(task);
      }
    } catch (_) {
      // No background work on this phone: notifications come while Folio
      // is open, as before.
    }
  }

  /// Folio in sight now; told by the open app.
  static void seen(PortalDatabase db) =>
      db.setMeta(_seenKey, DateTime.now().toIso8601String());

  /// One check: UYAP Mobil's newest notifications kept, the new ones told.
  static Future<void> check() async {
    final db = await PortalDatabase.shared();
    final alerts = UyapNoticeAlerts.of(db);
    if (!alerts.on || !alerts.background) return;
    final seen = DateTime.tryParse(db.meta(_seenKey) ?? '');
    if (seen != null && DateTime.now().difference(seen) < _quiet) return;
    final secrets = SecretStore();
    const secret = 'uyap-mobile';
    final kept = MobileTokens.fromJson(await secrets.read(secret));
    if (kept == null) return;
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
      if (await api.restore(kept) == null) return;
    } on UyapMobileUnreachable {
      return;
    }
    final sync = PortalSync(mobile: api, database: () async => db)
      ..paused = true;
    final fresh = <UyapNotice>[];
    sync.onNewNotices = fresh.addAll;
    try {
      await sync.syncNotices(force: true);
      if (fresh.isNotEmpty) await tellUyapNotices(db, fresh, ask: false);
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

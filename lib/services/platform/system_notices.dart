import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Word on the computer's or the phone's own notifications: a new UYAP
/// notification while Folio runs. Clicked, [onOpen] is told what it was
/// about.
class SystemNotices {
  SystemNotices._();

  static final instance = SystemNotices._();

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;

  /// Told the payload of the notification clicked.
  void Function(String payload)? onOpen;

  /// The one Windows knows Folio's notifications by; never to change, or
  /// Windows takes them for another app's.
  static const _windowsGuid = '5050b8bd-2412-4507-b2a9-d08dd96d1a0c';

  Future<bool> _start() => _ready ??= () async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    try {
      final ok = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Leave is asked for when the first word comes, not at start.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          linux: LinuxInitializationSettings(defaultActionName: 'Aç'),
          windows: WindowsInitializationSettings(
            appName: 'LifeOS Folio',
            // As windows/runner/main.cpp sets it.
            appUserModelId: 'com.erkanoz.lifeos.editor',
            guid: _windowsGuid,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) onOpen?.call(payload);
        },
      );
      // Folio opened by a word clicked while it was closed.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true &&
          payload != null &&
          payload.isNotEmpty) {
        _launched = payload;
      }
      return ok ?? false;
    } catch (_) {
      // No notifications on this system (no notification daemon on a
      // Linux desktop, say): Folio works on without them.
      return false;
    }
  }();

  String? _launched;
  bool _asked = false;

  /// Readies them at start, and tells [onOpen] of the word Folio was
  /// opened by, if it was.
  Future<void> prepare() async {
    await _start();
    final launched = _launched;
    _launched = null;
    if (launched != null) onOpen?.call(launched);
  }

  /// Leave to show them, asked once a run, where the system asks for it.
  Future<void> askLeave() async {
    if (!await _start()) return;
    if (_asked) return;
    _asked = true;
    try {
      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true);
      } else if (Platform.isMacOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true);
      }
    } catch (_) {}
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
    bool ask = true,
  }) async {
    if (!await _start()) return;
    if (ask) await askLeave();
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'uyap_bildirim',
            'UYAP bildirimleri',
            channelDescription: 'UYAP Mobil ve UYAP Web’den gelen yeni bildirimler',
            importance: Importance.high,
            priority: Priority.high,
          ),
          macOS: DarwinNotificationDetails(),
          iOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
        ),
      );
    } catch (_) {
      // Not shown; the page and the badge still tell of it.
    }
  }
}

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
          iOS: DarwinInitializationSettings(),
          macOS: DarwinInitializationSettings(),
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
      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      } else if (Platform.isMacOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true);
      }
      return ok ?? false;
    } catch (_) {
      // No notifications on this system (no notification daemon on a
      // Linux desktop, say): Folio works on without them.
      return false;
    }
  }();

  /// Readies them early, so that the first word is not the one lost to
  /// asking for leave.
  Future<void> prepare() async => _start();

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!await _start()) return;
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

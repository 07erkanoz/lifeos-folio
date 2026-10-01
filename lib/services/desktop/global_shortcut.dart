import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/services.dart';

class FolioShortcut {
  final String key;
  final int modifiers;
  const FolioShortcut({this.key = 'space', this.modifiers = 3});
  String get label => [
    if (modifiers & 1 != 0) 'Ctrl',
    if (modifiers & 2 != 0) 'Alt',
    if (modifiers & 4 != 0) 'Shift',
    if (modifiers & 8 != 0) 'Super',
    key == 'space' ? 'Space' : key.toUpperCase(),
  ].join(' + ');
  String get trigger => [
    if (modifiers & 1 != 0) 'CTRL',
    if (modifiers & 2 != 0) 'ALT',
    if (modifiers & 4 != 0) 'SHIFT',
    if (modifiers & 8 != 0) 'LOGO',
    key,
  ].join('+');
  Map<String, Object> toMap() => {'key': key, 'modifiers': modifiers};
  static FolioShortcut? fromEvent(KeyEvent event) {
    final keys = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final label = key == LogicalKeyboardKey.space ? 'space' : key.keyLabel;
    if (!RegExp(r'^(space|[a-zA-Z0-9]|F([1-9]|1[0-2]))$').hasMatch(label)) {
      return null;
    }
    final bits =
        (keys.isControlPressed ? 1 : 0) |
        (keys.isAltPressed ? 2 : 0) |
        (keys.isShiftPressed ? 4 : 0) |
        (keys.isMetaPressed ? 8 : 0);
    if (bits & 11 == 0) return null;
    return FolioShortcut(
      key: label.startsWith('F') && label.length > 1
          ? label
          : label.toLowerCase(),
      modifiers: bits,
    );
  }
}

/// Uses the compositor's portal on Wayland; X11/Windows use native registration.
class GlobalShortcut {
  static const channel = MethodChannel('com.erkanoz.folio/quick_search');
  static const _interface = 'org.freedesktop.portal.GlobalShortcuts';
  final void Function(String? token) onActivate;
  final bool? usePortal;
  final DBusClient Function()? busFactory;
  DBusClient? _bus;
  DBusObjectPath? _session;
  int _version = 0;
  StreamSubscription? _activated;
  StreamSubscription? _changed;
  void Function(String label)? onDescription;
  bool get canConfigure => wayland && _session != null && _version >= 2;

  Future<String> _parentWindow() async {
    try {
      return await channel.invokeMethod<String>('parentWindow') ?? '';
    } on MissingPluginException {
      return '';
    }
  }

  Future<void> configure() async {
    if (!canConfigure) return;
    await _portal.callMethod(_interface, 'ConfigureShortcuts', [
      _session!,
      DBusString(await _parentWindow()),
      DBusDict.stringVariant({}),
    ]);
  }

  GlobalShortcut(this.onActivate, {this.usePortal, this.busFactory}) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'activated') onActivate(null);
    });
  }
  bool get wayland =>
      usePortal ??
      (Platform.isLinux &&
          (Platform.environment['XDG_SESSION_TYPE'] == 'wayland' ||
              (Platform.environment['WAYLAND_DISPLAY']?.isNotEmpty ?? false)));
  DBusRemoteObject get _portal => DBusRemoteObject(
    _bus!,
    name: 'org.freedesktop.portal.Desktop',
    path: DBusObjectPath('/org/freedesktop/portal/desktop'),
  );
  Future<Map<String, DBusValue>> _request(
    String method,
    List<DBusValue> args, {
    Map<String, DBusValue> options = const {},
  }) async {
    final token = 'folio${DateTime.now().microsecondsSinceEpoch}';
    // Subscribe before sending the request so even an immediate response is kept.
    final path = DBusObjectPath(
      '/org/freedesktop/portal/desktop/request/${_bus!.uniqueName.substring(1).replaceAll('.', '_')}/$token',
    );
    final done = Completer<Map<String, DBusValue>>();
    final sub =
        DBusSignalStream(
          _bus!,
          sender: 'org.freedesktop.portal.Desktop',
          path: path,
          interface: 'org.freedesktop.portal.Request',
          name: 'Response',
        ).listen((event) {
          if (done.isCompleted) return;
          if (event.values[0].asUint32() == 0) {
            done.complete(event.values[1].asStringVariantDict());
          } else {
            done.completeError(StateError('Masaüstü kısayol izni verilmedi.'));
          }
        });
    try {
      await _portal.callMethod(_interface, method, [
        ...args,
        DBusDict.stringVariant({'handle_token': DBusString(token), ...options}),
      ]);
      return await done.future.timeout(const Duration(seconds: 60));
    } finally {
      await sub.cancel();
      if (!done.isCompleted) {
        try {
          await DBusRemoteObject(
            _bus!,
            name: _portal.name,
            path: path,
          ).callMethod('org.freedesktop.portal.Request', 'Close', []);
        } catch (_) {}
      }
    }
  }

  void _description(DBusValue? shortcuts) {
    if (shortcuts == null) return;
    for (final shortcut in shortcuts.asArray()) {
      final fields = shortcut.asStruct();
      if (fields[0].asString() == 'search') {
        final label = fields[1]
            .asStringVariantDict()['trigger_description']
            ?.asString();
        if (label != null) onDescription?.call(label);
      }
    }
  }

  Future<String> register(FolioShortcut shortcut) async {
    await unregister();
    if (!wayland) {
      await channel.invokeMethod('register', shortcut.toMap());
      return shortcut.label;
    }
    _bus = busFactory?.call() ?? DBusClient.session();
    try {
      // A standalone executable launched from a terminal has no desktop cgroup
      // identity. Register this very connection before its first portal call.
      // Keep the installed desktop ID stable across the Folio rename.
      if (!File('/.flatpak-info').existsSync() &&
          Platform.environment['SNAP'] == null) {
        try {
          await _portal.callMethod(
            'org.freedesktop.host.portal.Registry',
            'Register',
            [
              const DBusString('com.erkanoz.evrak_convert'),
              DBusDict.stringVariant({}),
            ],
          );
        } on DBusUnknownMethodException {
          // Older portals rely on launcher-provided application identification.
        } on DBusUnknownInterfaceException {
          // Registry was introduced after the original GlobalShortcuts portal.
        }
      }
      // Establish bus connection and check support before creating the request path.
      _version = (await _portal.getProperty(_interface, 'version')).asUint32();
      final created = await _request(
        'CreateSession',
        [],
        options: {
          'session_handle_token': DBusString(
            'folio${DateTime.now().microsecondsSinceEpoch}',
          ),
        },
      );
      _session = DBusObjectPath(created['session_handle']!.asString());
      _activated =
          DBusRemoteObjectSignalStream(
            object: _portal,
            interface: _interface,
            name: 'Activated',
          ).listen((event) {
            if (event.values[0].asObjectPath() != _session ||
                event.values[1].asString() != 'search') {
              return;
            }
            onActivate(
              event.values[3]
                  .asStringVariantDict()['activation_token']
                  ?.asString(),
            );
          });
      _changed =
          DBusRemoteObjectSignalStream(
            object: _portal,
            interface: _interface,
            name: 'ShortcutsChanged',
          ).listen((event) {
            if (event.values[0].asObjectPath() == _session) {
              _description(event.values[1]);
            }
          });
      final result = await _request('BindShortcuts', [
        _session!,
        DBusArray(DBusSignature('(sa{sv})'), [
          DBusStruct([
            const DBusString('search'),
            DBusDict.stringVariant({
              'description': const DBusString('LifeOS Folio hızlı arama'),
              'preferred_trigger': DBusString(shortcut.trigger),
            }),
          ]),
        ]),
        DBusString(await _parentWindow()),
      ]);
      final bound = result['shortcuts'];
      if (bound == null || bound.asArray().isEmpty) {
        throw StateError('Kısayol atanmadı.');
      }
      String? label;
      for (final value in bound.asArray()) {
        final fields = value.asStruct();
        if (fields[0].asString() == 'search') {
          label = fields[1]
              .asStringVariantDict()['trigger_description']
              ?.asString();
        }
      }
      if (label == null || label.trim().isEmpty) {
        throw StateError(
          'Masaüstü bir tuş birleşimi atamadı. Kısayol izninde tuşları seçin.',
        );
      }
      return label;
    } catch (_) {
      await unregister();
      rethrow;
    }
  }

  Future<void> unregister() async {
    await _activated?.cancel();
    _activated = null;
    await _changed?.cancel();
    _changed = null;
    if (_session != null && _bus != null) {
      try {
        await DBusRemoteObject(
          _bus!,
          name: _portal.name,
          path: _session!,
        ).callMethod('org.freedesktop.portal.Session', 'Close', []);
      } catch (_) {}
    }
    _session = null;
    await _bus?.close();
    _bus = null;
    if (!wayland) {
      try {
        await channel.invokeMethod('unregister');
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await unregister();
    channel.setMethodCallHandler(null);
  }
}

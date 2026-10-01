import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../platform/app_directories.dart';
import '../platform/atomic_file.dart';

class WindowSessionData {
  final Size size;
  final bool maximized, fullscreen;
  const WindowSessionData({
    this.size = const Size(1200, 800),
    this.maximized = false,
    this.fullscreen = false,
  });

  factory WindowSessionData.fromJson(Map data) {
    double dimension(String key, double fallback, double minimum) {
      final value = data[key];
      if (value is! num || !value.isFinite) return fallback;
      return value.toDouble().clamp(minimum, 7680);
    }

    return WindowSessionData(
      size: Size(dimension('width', 1200, 900), dimension('height', 800, 600)),
      maximized: data['maximized'] == true,
      fullscreen: data['fullscreen'] == true,
    );
  }

  Map<String, Object> toJson() => {
    'width': size.width,
    'height': size.height,
    'maximized': maximized,
    'fullscreen': fullscreen,
  };
}

/// Normal window geometry survives maximize/fullscreen and palette transitions.
class WindowSession with WindowListener {
  final File file;
  WindowSessionData data;
  final _restored = Completer<void>();
  Future<void> get restored => _restored.future;
  bool suspended = false;
  bool _listening = false;
  Timer? _timer;
  Future<void> _tail = Future.value();
  WindowSession(this.file, this.data);

  static Future<WindowSession> load({File? file}) async {
    final target =
        file ??
        File('${(await folioSupportDirectory()).path}/window-session.json');
    var data = const WindowSessionData();
    try {
      data = WindowSessionData.fromJson(
        jsonDecode(await target.readAsString()) as Map,
      );
    } catch (_) {
      // First launch or damaged optional settings use a visible normal window.
    }
    return WindowSession(target, data);
  }

  /// Puts the window back as it was left. [showMaximized], when given, shows
  /// a hidden window that was left maximized in one step instead of
  /// maximizing it after it is shown.
  Future<void> restore({Future<void> Function()? showMaximized}) async {
    suspended = true;
    try {
      await windowManager.setSize(data.size);
      await windowManager.center();
      if (data.maximized) {
        await (showMaximized ?? windowManager.maximize)();
      }
      if (data.fullscreen) await windowManager.setFullScreen(true);
    } finally {
      suspended = false;
      if (!_restored.isCompleted) _restored.complete();
      if (!_listening) {
        _listening = true;
        windowManager.addListener(this);
      }
    }
  }

  Future<void> save() {
    _timer?.cancel();
    _tail = _tail
        .then((_) async {
          if (suspended || !_listening) return;
          final fullscreen = await windowManager.isFullScreen();
          final maximized = await windowManager.isMaximized();
          if (await windowManager.isMinimized() || suspended) return;
          final size = fullscreen || maximized
              ? data.size
              : await windowManager.getSize();
          if (suspended) return;
          data = WindowSessionData(
            size: size,
            maximized: fullscreen ? data.maximized : maximized,
            fullscreen: fullscreen,
          );
          await replaceFileIfChanged(
            file,
            utf8.encode(jsonEncode(data.toJson())),
          );
        })
        .catchError((Object _) {
          // A settings write failure must never block closing a document window.
        });
    return _tail;
  }

  void _changed() {
    if (suspended) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 300), save);
  }

  @override
  void onWindowResize() => _changed();
  @override
  void onWindowMaximize() => _changed();
  @override
  void onWindowUnmaximize() => _changed();
  @override
  void onWindowEnterFullScreen() => _changed();
  @override
  void onWindowLeaveFullScreen() => _changed();

  void dispose() {
    _timer?.cancel();
    if (_listening) windowManager.removeListener(this);
    _listening = false;
  }
}

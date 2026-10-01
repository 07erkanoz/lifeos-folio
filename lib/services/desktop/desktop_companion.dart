import 'window_session.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../platform/app_directories.dart';
import '../platform/atomic_file.dart';
import 'global_shortcut.dart';

class DesktopCompanion extends ChangeNotifier
    with WindowListener, TrayListener {
  bool enabled = false;
  bool busy = false;
  bool quick = false;
  bool shortcutReady = false;
  bool trayReady = false;
  bool _disposed = false;
  bool _switching = false;
  bool _returnToMain = false;
  bool _wasMaximized = false, _wasFullscreen = false;
  bool _quitting = false;
  Rect mainBounds = const Rect.fromLTWH(100, 100, 1200, 800);
  String? error;
  String shortcutLabel = const FolioShortcut().label;
  FolioShortcut shortcut = const FolioShortcut();
  late final GlobalShortcut _global;
  final launches = StreamController<List<String>>();
  final VoidCallback? onQuit;
  final VoidCallback? onShowHome;
  final Future<bool> Function()? beforeClose;
  bool _closing = false;
  final WindowSession? windowSession;
  DesktopCompanion({
    this.onQuit,
    this.beforeClose,
    this.windowSession,
    this.onShowHome,
  }) {
    _global = GlobalShortcut((token) => toggleQuick(activationToken: token));
    _global.onDescription = (label) {
      shortcutLabel = label;
      _notify();
    };
    windowManager.addListener(this);
    trayManager.addListener(this);
  }
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool get usesDesktopShortcutSettings => _global.wayland;
  Future<void> configureDesktopShortcut() async {
    if (!enabled || !shortcutReady) {
      await configure(true);
      return;
    }
    try {
      if (_global.canConfigure) {
        await _global.configure();
      } else if (Platform.environment['XDG_CURRENT_DESKTOP']
              ?.toLowerCase()
              .contains('gnome') ==
          true) {
        final result = await Process.run('gnome-control-center', ['keyboard']);
        if (result.exitCode != 0) {
          throw StateError('GNOME klavye ayarları açılamadı.');
        }
      } else {
        error = 'Bu masaüstünde kısayolu sistem klavye ayarlarından değiştirebilirsiniz.';
      }
    } catch (e) {
      error = 'Kısayol ayarları açılamadı: $e';
    }
    _notify();
  }

  Future<File> get _settings async =>
      File('${(await folioSupportDirectory()).path}/quick-search.json');
  Future<void> load() async {
    await windowManager.setPreventClose(true);
    try {
      final data = jsonDecode(await (await _settings).readAsString()) as Map;
      final key = data['key'] as String? ?? 'space';
      final mods = data['modifiers'] as int? ?? 3;
      if (RegExp(r'^(space|[a-z0-9]|F([1-9]|1[0-2]))$').hasMatch(key) &&
          mods & 11 != 0) {
        shortcut = FolioShortcut(key: key, modifiers: mods & 15);
        shortcutLabel = shortcut.label;
      }
      if (data['enabled'] == true) await configure(true, persist: false);
    } on FileSystemException {
      /* Optional until explicitly enabled. */
    } catch (e) {
      error = 'Hızlı arama ayarı yüklenemedi: $e';
    }
    _notify();
  }

  Future<bool> _trayHostAvailable() async {
    if (!Platform.isLinux) return true;
    final bus = DBusClient.session();
    try {
      final watcher = DBusRemoteObject(
        bus,
        name: 'org.kde.StatusNotifierWatcher',
        path: DBusObjectPath('/StatusNotifierWatcher'),
      );
      return (await watcher
              .getProperty(
                'org.kde.StatusNotifierWatcher',
                'IsStatusNotifierHostRegistered',
              )
              .timeout(const Duration(seconds: 2)))
          .asBoolean();
    } catch (_) {
      return false;
    } finally {
      await bus.close();
    }
  }

  Future<void> configure(
    bool value, {
    FolioShortcut? binding,
    bool persist = true,
  }) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    _notify();
    try {
      enabled = value;
      if (binding != null) shortcut = binding;
      shortcutLabel = shortcut.label;
      await _global.unregister();
      shortcutReady = false;
      if (value) {
        await trayManager.setIcon(
          Platform.isWindows
              ? 'assets/branding/folio_tray.ico'
              : 'assets/branding/lifeos_folio.png',
        );
        if (!Platform.isLinux) {
          await trayManager.setToolTip('LifeOS Folio · Hızlı arama');
        }
        await trayManager.setContextMenu(
          Menu(
            items: [
              MenuItem(key: 'search', label: 'Hızlı arama'),
              MenuItem(key: 'open', label: 'LifeOS Folio’yu aç'),
              MenuItem.separator(),
              MenuItem(key: 'quit', label: 'Tamamen çık'),
            ],
          ),
        );
        trayReady = await _trayHostAvailable();
        try {
          shortcutLabel = await _global.register(shortcut);
          shortcutReady = true;
        } catch (e) {
          error = _global.wayland
              ? 'Masaüstü kısayolu etkinleştirilemedi. Sistem klavye ayarlarında “${Platform.resolvedExecutable} --quick-search” komutuna kısayol atayabilirsiniz. ($e)'
              : 'Kısayol atanamadı. Başka bir tuş birleşimi deneyin. ($e)';
        }
        if (!trayReady) {
          error =
              '${error == null ? '' : '$error\n'}Bu oturumda sistem tepsisi görünmüyor. GNOME’da AppIndicator desteği gerekir.';
        }
      } else {
        await trayManager.destroy();
        trayReady = false;
      }
      // Native close always passes through the unsaved-document guard. Only
      // hide after approval when there is an OS entry point to return through.
      await windowManager.setPreventClose(true);
      if (persist) {
        await replaceFileIfChanged(
          await _settings,
          utf8.encode(jsonEncode({'enabled': enabled, ...shortcut.toMap()})),
        );
      }
    } catch (e) {
      error = 'Arka plan modu etkinleştirilemedi: $e';
      enabled = false;
      await _global.unregister();
      try {
        await trayManager.destroy();
        await windowManager.setPreventClose(true);
      } catch (_) {}
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _present(String? token) async {
    await windowManager.show();
    await windowManager.focus();
    try {
      await GlobalShortcut.channel.invokeMethod('activate', token ?? '');
    } catch (_) {}
  }

  Future<void> toggleQuick({String? activationToken}) async {
    if (_switching || _disposed || _quitting) return;
    if (quick && await windowManager.isVisible()) {
      await dismiss();
      return;
    }
    _switching = true;
    try {
      _returnToMain = !quick && await windowManager.isVisible();
      if (!quick) {
        await windowSession?.save();
        if (windowSession != null) windowSession!.suspended = true;
        _wasMaximized = await windowManager.isMaximized();
        _wasFullscreen = await windowManager.isFullScreen();
        if (!_wasMaximized && !_wasFullscreen) {
          mainBounds = await windowManager.getBounds();
        }
      }
      await windowManager.hide();
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
      }
      if (await windowManager.isMaximized()) await windowManager.unmaximize();
      await windowManager.setMinimumSize(const Size(560, 420));
      await windowManager.setSize(const Size(740, 580));
      await windowManager.setSkipTaskbar(true);
      await windowManager.center();
      quick = true;
      _notify();
      // A hidden GTK window does not produce frames. Present before waiting
      // for any paint; awaiting endOfFrame here would leave the app hidden.
      await _present(activationToken);
      await windowManager.setSize(const Size(740, 580));
      await windowManager.center();
    } catch (e) {
      error = 'Hızlı arama açılamadı: $e';
      quick = false;
      if (windowSession != null) windowSession!.suspended = false;
      _notify();
      await windowManager.setSkipTaskbar(false);
      await _present(null);
    } finally {
      _switching = false;
    }
  }

  Future<void> showMain({
    List<String> paths = const [],
    bool showHome = true,
  }) async {
    if (_switching || _disposed || _quitting) return;
    _switching = true;
    try {
      if (quick) {
        await windowManager.hide();
        quick = false;
        _notify();
        await windowManager.setResizable(true);
        await windowManager.setMinimumSize(const Size(900, 600));
        await windowManager.setBounds(mainBounds);
        if (_wasMaximized) await windowManager.maximize();
        if (_wasFullscreen) await windowManager.setFullScreen(true);
        if (windowSession != null) windowSession!.suspended = false;
      }
      await windowManager.setSkipTaskbar(false);
      if (await windowManager.isMinimized()) await windowManager.restore();
      if (paths.isEmpty && showHome) onShowHome?.call();
      await _present(null);
      if (paths.isNotEmpty) launches.add(paths);
    } finally {
      _switching = false;
      _notify();
    }
  }

  Future<void> dismiss() async {
    if (_switching) return;
    if (_returnToMain) {
      await showMain(showHome: false);
      return;
    }
    await windowManager.hide();
  }

  Future<void> _close({required bool completely}) async {
    if (_quitting || _closing) return;
    _closing = true;
    try {
      if (beforeClose != null && !await beforeClose!()) return;
      await windowSession?.save();
      if (!completely && enabled && (trayReady || shortcutReady)) {
        await windowManager.hide();
        return;
      }
      _quitting = true;
      await _global.unregister();
      await trayManager.destroy();
      onQuit?.call();
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } finally {
      _closing = false;
    }
  }

  Future<void> quit() => _close(completely: true);

  @override
  void onWindowClose() => _close(completely: false);

  @override
  void onWindowBlur() {
    // Keep the palette available while switching applications or OS dialogs.
    // Escape, the close button, or the global shortcut dismiss it explicitly.
  }

  @override
  void onTrayIconMouseDown() => toggleQuick();
  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();
  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'search':
        toggleQuick();
      case 'open':
        showMain();
      case 'quit':
        quit();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    _global.dispose();
    launches.close();
    super.dispose();
  }
}

class CompanionScope extends InheritedNotifier<DesktopCompanion> {
  const CompanionScope({
    super.key,
    required DesktopCompanion super.notifier,
    required super.child,
  });
  static DesktopCompanion? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CompanionScope>()?.notifier;
}

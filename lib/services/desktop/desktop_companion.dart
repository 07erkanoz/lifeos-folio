import 'window_session.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:dbus/dbus.dart';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../platform/app_directories.dart';
import '../platform/atomic_file.dart';
import 'global_shortcut.dart';
import 'kwin_palette_rule.dart';
import 'linux_tray.dart';

class DesktopCompanion extends ChangeNotifier
    with WindowListener, TrayListener {
  bool enabled = false;
  bool busy = false;
  bool quick = false;

  /// The palette full screen as Folio Ajan's Jarvis mode.
  bool jarvis = false;
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

  /// Folio Ajan's full screen at a key of its own (KDE / Wayland, by the
  /// desktop's shortcut portal): Ctrl + Alt + J unless changed there.
  FolioShortcut ajanShortcut = const FolioShortcut(key: 'j');
  String ajanShortcutLabel = '';
  late final GlobalShortcut _global;
  final launches = StreamController<List<String>>();
  final VoidCallback? onQuit;
  final VoidCallback? onShowHome;
  final Future<bool> Function()? beforeClose;
  bool _closing = false;
  final WindowSession? windowSession;

  /// Linux's tray, Folio's own: a left click opens the quick search.
  late final LinuxTray _linuxTray = LinuxTray(
    onActivate: () {
      if (jarvis) {
        leaveJarvis(toPalette: true);
      } else {
        toggleQuick();
      }
    },
    onMenu: _menu,
  );
  bool _ownTray = false;

  static const _menuItems = [
    LinuxTrayItem('search', 'Hızlı arama ve ajan'),
    LinuxTrayItem('jarvis', 'Folio Ajan'),
    LinuxTrayItem('open', 'LifeOS Folio’yu aç'),
    LinuxTrayItem.separator(),
    LinuxTrayItem('quit', 'Tamamen çık'),
  ];

  Future<void> _destroyTray() async {
    if (_ownTray) {
      _ownTray = false;
      await _linuxTray.hide();
    } else {
      await trayManager.destroy();
    }
  }

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
    _global.onAjan = (token) => showJarvis(activationToken: token);
    _global.onAjanDescription = (label) {
      ajanShortcutLabel = label;
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
      final ajanKey = data['ajan_key'] as String? ?? 'j';
      final ajanMods = data['ajan_modifiers'] as int? ?? 3;
      if (RegExp(r'^(space|[a-z0-9]|F([1-9]|1[0-2]))$').hasMatch(ajanKey) &&
          ajanMods & 11 != 0) {
        ajanShortcut = FolioShortcut(key: ajanKey, modifiers: ajanMods & 15);
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
      var own = false;
      if (value && Platform.isLinux && !_ownTray) {
        try {
          await _linuxTray.show(
            asset: 'assets/branding/lifeos_folio.png',
            tooltip: 'Hızlı arama · sağ tık: menü',
            items: _menuItems,
          );
          own = _ownTray = true;
        } catch (_) {
          // No StatusNotifierWatcher: appindicator's tray below.
        }
      } else if (value && _ownTray) {
        own = true;
      }
      if (value && !own) {
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
              MenuItem(key: 'search', label: 'Hızlı arama ve ajan'),
              MenuItem(key: 'jarvis', label: 'Folio Ajan'),
              MenuItem(key: 'open', label: 'LifeOS Folio’yu aç'),
              MenuItem.separator(),
              MenuItem(key: 'quit', label: 'Tamamen çık'),
            ],
          ),
        );
      }
      if (value) {
        trayReady = await _trayHostAvailable();
        try {
          shortcutLabel = await _global.register(shortcut, ajan: ajanShortcut);
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
        await _destroyTray();
        trayReady = false;
      }
      // Native close always passes through the unsaved-document guard. Only
      // hide after approval when there is an OS entry point to return through.
      await windowManager.setPreventClose(true);
      if (persist) {
        await replaceFileIfChanged(
          await _settings,
          utf8.encode(
            jsonEncode({
              'enabled': enabled,
              ...shortcut.toMap(),
              'ajan_key': ajanShortcut.key,
              'ajan_modifiers': ajanShortcut.modifiers,
            }),
          ),
        );
      }
    } catch (e) {
      error = 'Arka plan modu etkinleştirilemedi: $e';
      enabled = false;
      await _global.unregister();
      try {
        await _destroyTray();
        await windowManager.setPreventClose(true);
      } catch (_) {}
    } finally {
      busy = false;
      _notify();
    }
  }

  /// Waits, a second at most, for the compositor to have done what was
  /// asked of the window.
  static Future<void> _settled(Future<bool> Function() done) async {
    for (var i = 0; i < 20 && !await done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _present(String? token) async {
    await windowManager.show();
    await windowManager.focus();
    try {
      await GlobalShortcut.channel.invokeMethod('activate', token ?? '');
    } catch (_) {}
  }

  /// The palette's window: the card (740 × 580) and room for its shadow.
  static const paletteWindow = Size(800, 650);

  /// Its title while it is the palette: KWin centres it by this.
  static const paletteTitle = 'Folio hızlı arama';

  Future<void> toggleQuick({String? activationToken}) async {
    if (_switching || _disposed || _quitting) return;
    if (quick && await windowManager.isVisible()) {
      if (jarvis) {
        await leaveJarvis(toPalette: true);
        return;
      }
      await dismiss();
      return;
    }
    await _openQuick(activationToken);
  }

  /// The quick window from the main window or from hidden: the palette, or
  /// with [full] Folio Ajan full screen straight away (the palette is not
  /// shown on the way: it came a moment before Folio Ajan, 21 Kasım 2026).
  Future<void> _openQuick(String? activationToken, {bool full = false}) async {
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
        // Out of full screen and maximized while still shown: a hidden
        // window's are not changed on Wayland (KWin), and the palette came
        // at the main window's size, a small search inside a large window
        // (measured under a virtual KWin, 21 Ekim 2026).
        if (_wasFullscreen) {
          await windowManager.setFullScreen(false);
          await _settled(() async => !await windowManager.isFullScreen());
        }
        if (_wasMaximized) {
          await windowManager.unmaximize();
          await _settled(() async => !await windowManager.isMaximized());
        }
      }
      await windowManager.hide();
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
      }
      if (await windowManager.isMaximized()) await windowManager.unmaximize();
      await windowManager.setMinimumSize(const Size(560, 420));
      await windowManager.setSkipTaskbar(true);
      if (full) {
        // The screen's size before it is shown; full screen once it is (a
        // hidden window's is not changed on Wayland).
        final display = PlatformDispatcher.instance.displays.first;
        await windowManager.setBounds(
          Offset.zero & (display.size / display.devicePixelRatio),
        );
        await windowManager.setTitle('Folio Ajan');
        jarvis = true;
        _jarvisFromPalette = false;
      } else {
        await windowManager.setSize(paletteWindow);
        await KwinPaletteRule.ensure(paletteTitle);
        await windowManager.setTitle(paletteTitle);
        await windowManager.center();
      }
      quick = true;
      _notify();
      // A hidden GTK window does not produce frames. Present before waiting
      // for any paint; awaiting endOfFrame here would leave the app hidden.
      await _present(activationToken);
      if (full) {
        await windowManager.setFullScreen(true);
        return;
      }
      // Started cold, the runner's maximize (or a full screen left by the
      // last session) lands only once shown: undone here, or the palette
      // fills the screen (21 Kasım 2026).
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
        await _settled(() async => !await windowManager.isFullScreen());
      }
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
        await _settled(() async => !await windowManager.isMaximized());
      }
      await windowManager.setSize(paletteWindow);
      await windowManager.center();
    } catch (e) {
      error = full ? 'Folio Ajan açılamadı: $e' : 'Hızlı arama açılamadı: $e';
      quick = false;
      jarvis = false;
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
        jarvis = false;
        await windowManager.setTitle('LifeOS Folio');
        // Out of the palette's full screen while still shown: a hidden
        // window's is not changed on Wayland (KWin).
        if (await windowManager.isFullScreen()) {
          await windowManager.setFullScreen(false);
          await _settled(() async => !await windowManager.isFullScreen());
        }
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

  /// Whether Folio Ajan was opened from the palette: going back from it
  /// returns there; opened from elsewhere, it returns where it came from.
  bool _jarvisFromPalette = false;

  /// Folio Ajan full screen: from the tray, its shortcut, the voice window,
  /// "Ajan açıl" or the palette's button. Only from the palette does the
  /// palette grow into it; from anywhere else it opens by itself.
  Future<void> showJarvis({String? activationToken}) async {
    if (_switching || _disposed || _quitting || jarvis) return;
    if (!quick || !await windowManager.isVisible()) {
      await _openQuick(activationToken, full: true);
      return;
    }
    _switching = true;
    try {
      jarvis = true;
      _jarvisFromPalette = true;
      _notify();
      await windowManager.setFullScreen(true);
      await _present(null);
    } catch (e) {
      jarvis = false;
      error = 'Folio Ajan açılamadı: $e';
      _notify();
    } finally {
      _switching = false;
    }
  }

  /// Folio Ajan's minimize (and Esc): back to the palette if it came from
  /// there, otherwise back where it was (the main window, or hidden). With
  /// [toPalette] (the tray's click) to the palette in any case.
  Future<void> leaveJarvis({bool toPalette = false}) async {
    if (_switching || !jarvis) return;
    if (!toPalette && !_jarvisFromPalette) return dismiss();
    _switching = true;
    try {
      jarvis = false;
      _notify();
      await windowManager.setFullScreen(false);
      await _settled(() async => !await windowManager.isFullScreen());
      await windowManager.setSize(paletteWindow);
      await KwinPaletteRule.ensure(paletteTitle);
      await windowManager.setTitle(paletteTitle);
      await windowManager.center();
    } finally {
      _switching = false;
    }
  }

  Future<void> dismiss() async {
    if (_switching) return;
    if (jarvis) {
      jarvis = false;
      _notify();
      await windowManager.setFullScreen(false);
      await _settled(() async => !await windowManager.isFullScreen());
      await windowManager.setSize(paletteWindow);
    }
    if (_returnToMain) {
      await showMain(showHome: false);
      return;
    }
    await windowManager.hide();
  }

  Future<void> _close({required bool completely, bool ask = true}) async {
    if (_quitting || _closing) return;
    _closing = true;
    try {
      if (ask && beforeClose != null && !await beforeClose!()) return;
      await windowSession?.save();
      if (!completely && enabled && (trayReady || shortcutReady)) {
        await windowManager.hide();
        return;
      }
      _quitting = true;
      await _global.unregister();
      await _destroyTray();
      onQuit?.call();
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } finally {
      _closing = false;
    }
  }

  /// [ask] false: what is not saved was asked about already (an update,
  /// before it put the new Folio in place).
  Future<void> quit({bool ask = true}) => _close(completely: true, ask: ask);

  /// A Mac's ⌘Q, which ends the app without closing its window first:
  /// whether it may, unsaved work asked about as the close button asks, and
  /// what Folio lets go of on quitting let go of. The app then ends itself
  /// (macos/Runner/AppDelegate.swift). Already quitting by its own close
  /// button, it is not asked twice.
  Future<bool> approveQuit() async {
    if (_quitting) return true;
    if (_closing) return false;
    _closing = true;
    try {
      if (beforeClose != null && !await beforeClose!()) return false;
      await windowSession?.save();
      _quitting = true;
      await _global.unregister();
      await _destroyTray();
      onQuit?.call();
      return true;
    } finally {
      _closing = false;
    }
  }

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
  void onTrayMenuItemClick(MenuItem menuItem) => _menu(menuItem.key ?? '');

  void _menu(String key) {
    switch (key) {
      case 'search':
        if (jarvis) {
          leaveJarvis(toPalette: true);
        } else {
          toggleQuick();
        }
      case 'jarvis':
        showJarvis();
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

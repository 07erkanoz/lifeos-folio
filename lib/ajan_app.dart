import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'services/ai/ai_assistant.dart';
import 'services/ai/ai_external.dart';
import 'services/desktop/desktop_instance.dart';
import 'services/desktop/global_shortcut.dart';
import 'services/voice/ajan_bridge.dart';
import 'services/voice/ajan_link.dart';
import 'services/voice/folio_ajan.dart';
import 'services/voice/wake_word.dart';
import 'ui/desktop/ajan_float.dart';
import 'ui/desktop/jarvis_view.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/theme_controller.dart';

/// Folio Ajan, a program of its own (`lifeos_ajan`, 22 Kasım 2026): in
/// Folio's window its animation stuttered whenever Folio worked, and
/// Folio waited whenever its tools ran. It has its own window (the full
/// screen, or the small voice window while a conversation goes on beside
/// other work), its own microphone ("Ajan açıl") and its own lock; what
/// only the open Folio does (UYAP, UETS, Senkron) it asks of Folio
/// ([AjanBridge]). Started with `--arka` it shows nothing and listens.
Future<void> runAjanApp(List<String> arguments) async {
  DesktopInstance? instance;
  try {
    instance = await DesktopInstance.acquire(
      arguments,
      directory: await AjanBridge.folder(),
    );
  } on StateError {
    DesktopInstance.tellStuck('Folio Ajan açık görünüyor ama yanıt vermiyor.');
    exit(1);
  }
  if (instance == null) exit(0);
  await windowManager.ensureInitialized();
  await windowManager.setTitleBarStyle(
    TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.setTitle('Folio Ajan');
  await windowManager.setMinimumSize(AjanApp.compactSize);
  await AiSettings.load();
  AjanPinRelay.instance.startInAjan();
  await AjanBridge.setShown(false);
  runApp(
    AjanApp(
      instance: instance,
      hidden: arguments.contains(AjanBridge.background),
      token: AjanApp.tokenOf(arguments),
    ),
  );
}

enum _Mode { hidden, full, compact }

class AjanApp extends StatefulWidget {
  const AjanApp({
    super.key,
    required this.instance,
    this.hidden = false,
    this.token,
  });

  final DesktopInstance instance;

  /// Started with no window ([AjanBridge.background]).
  final bool hidden;
  final String? token;

  /// The small voice window's size before it fits its card.
  static const compactSize = Size(320, 180);

  static String? tokenOf(List<String> args) {
    for (final a in args) {
      if (a.startsWith(AjanBridge.tokenPrefix)) {
        return a.substring(AjanBridge.tokenPrefix.length);
      }
    }
    return null;
  }

  @override
  State<AjanApp> createState() => _AjanAppState();
}

class _AjanAppState extends State<AjanApp> with WindowListener {
  final appearance = ThemeController();
  final _card = GlobalKey();
  late final StreamSubscription<List<String>> _requests;
  Timer? _status;
  var _mode = _Mode.hidden;
  bool _switching = false;
  bool _money = false;
  String _person = '';

  FolioAjan get ajan => FolioAjan.instance;

  @override
  void initState() {
    super.initState();
    appearance.load();
    // Who the person is and whether they see the clients' money: the open
    // Folio's word ([ExternalHost]), read from Folio Ajan's folder.
    ExternalHost.seesMoney = () => _money;
    ExternalHost.person = () => _person;
    unawaited(_readStatus());
    _status = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_readStatus()),
    );
    ajan.loadVoiceSettings();
    FolioAjan.beforeVoice = WakeWord.instance.pause;
    WakeWord.instance.onWake = _woken;
    ajan.addListener(_followWake);
    AiSettings.on.addListener(_followWake);
    ajanFloatOpen.addListener(_floatChanged);
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    _requests = widget.instance.requests.listen(_heard);
    if (!widget.hidden) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_full(widget.token)),
      );
    }
  }

  Future<void> _readStatus() async {
    try {
      final s = await FolioExternal.status(await AjanBridge.sessionFolder());
      _money = s.money;
      _person = s.person ?? '';
    } catch (_) {}
    // Listening with no window while Folio is gone (it crashed, or was
    // ended some way that did not tell): nowhere to be seen or stopped.
    if (_mode == _Mode.hidden && !ajan.voiceStarting && !ajan.voice.active) {
      _alone = await AjanBridge.folioRunning() ? 0 : _alone + 1;
      if (_alone >= 2 && _mode == _Mode.hidden) await _quit();
    }
  }

  /// How many times running Folio was not found, one after another.
  int _alone = 0;

  bool get _wantWake =>
      ajan.available && ajan.settings.on && ajan.settings.wake;

  void _followWake() {
    final wake = WakeWord.instance;
    if (!_wantWake) {
      if (wake.on) unawaited(wake.stop());
      return;
    }
    if (ajan.voiceStarting || ajan.voice.active) return;
    if (!wake.on || wake.state.value == WakeState.paused) {
      unawaited(wake.start());
    }
  }

  /// "Ajan açıl": the full screen from nothing; in a window already, the
  /// conversation.
  Future<void> _woken() async {
    if (_mode == _Mode.hidden) return _full(null);
    if (!ajan.voice.active) await ajan.startVoice(handsFree: true);
  }

  void _heard(List<String> args) {
    if (AjanPinRelay.instance.heardInAjan(args)) return;
    if (args.contains(AjanBridge.settings)) {
      unawaited(_settingsChanged());
      return;
    }
    // Folio ended: Folio Ajan, seen and stopped only in Folio's tray,
    // ends with it.
    if (args.contains(AjanBridge.quit)) {
      unawaited(_quit());
      return;
    }
    if (args.contains(AjanBridge.background)) return;
    unawaited(_full(AjanApp.tokenOf(args)));
  }

  /// Folio's settings changed the voice: read again; with no window and
  /// nothing to listen for, Folio Ajan has nothing to do.
  Future<void> _settingsChanged() async {
    await AiSettings.reload();
    await ajan.loadSettings(quick: true);
    _followWake();
    if (_mode == _Mode.hidden && !_wantWake) await _quit();
  }

  Future<void> _full(String? token) async {
    if (_switching) return;
    _switching = true;
    try {
      final from = _mode;
      setState(() => _mode = _Mode.full);
      ajanFloatOpen.value = false;
      await windowManager.setAlwaysOnTop(false);
      if (from == _Mode.hidden) {
        // The screen's size before it is shown, full screen once it is (a
        // hidden window's is not changed on Wayland): never small first.
        final display = PlatformDispatcher.instance.displays.first;
        await windowManager.setBounds(
          Offset.zero & (display.size / display.devicePixelRatio),
        );
      }
      await windowManager.show();
      await windowManager.setFullScreen(true);
      try {
        await GlobalShortcut.channel.invokeMethod('activate', token ?? '');
      } catch (_) {}
      await windowManager.focus();
      if (from == _Mode.hidden) await AjanBridge.setShown(true);
    } finally {
      _switching = false;
    }
  }

  /// The small voice window, while the conversation goes on; hidden when
  /// none does.
  Future<void> _compact() async {
    if (!ajan.voice.active) return _hide();
    if (_switching) return;
    _switching = true;
    try {
      setState(() => _mode = _Mode.compact);
      ajanFloatOpen.value = true;
      await windowManager.setFullScreen(false);
      for (var i = 0; i < 20 && await windowManager.isFullScreen(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await windowManager.setSize(AjanApp.compactSize);
      await windowManager.setAlwaysOnTop(true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
    } finally {
      _switching = false;
    }
  }

  /// The small window the size of its card, no margin around it.
  Future<void> _fit() async {
    final box = _card.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || _mode != _Mode.compact) return;
    final size = box.size;
    final now = await windowManager.getSize();
    if ((now.width - size.width).abs() > 1 ||
        (now.height - size.height).abs() > 1) {
      await windowManager.setSize(size);
    }
  }

  void _floatChanged() {
    if (!ajanFloatOpen.value && _mode == _Mode.compact) unawaited(_hide());
  }

  /// No window; the conversation ends with it. Listening for "Ajan açıl"
  /// goes on, or the program ends when it is not wanted.
  Future<void> _hide() async {
    if (_mode == _Mode.hidden) return;
    setState(() => _mode = _Mode.hidden);
    ajanFloatOpen.value = false;
    AjanLinks.instance.cancel();
    await AjanBridge.setShown(false);
    if (ajan.voice.active) await ajan.voice.stop();
    await windowManager.setAlwaysOnTop(false);
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
    }
    await windowManager.hide();
    _followWake();
    if (!_wantWake || !await AjanBridge.folioRunning()) await _quit();
  }

  Future<void> _quit() async {
    await AjanBridge.setShown(false);
    try {
      await WakeWord.instance.stop();
    } catch (_) {}
    await widget.instance.close();
    exit(0);
  }

  @override
  void onWindowClose() => unawaited(_hide());

  @override
  void dispose() {
    _status?.cancel();
    _requests.cancel();
    ajan.removeListener(_followWake);
    AiSettings.on.removeListener(_followWake);
    ajanFloatOpen.removeListener(_floatChanged);
    windowManager.removeListener(this);
    appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: appearance,
    builder: (context, _) => MaterialApp(
      title: 'Folio Ajan',
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: appearance.mode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('tr', 'TR'), Locale('en', 'US')],
      locale: const Locale('tr', 'TR'),
      home: switch (_mode) {
        _Mode.hidden => const SizedBox.shrink(),
        _Mode.full => JarvisView(
          ajan: ajan,
          onMinimize: () => unawaited(_compact()),
          // Folio's window, the conversation going on in the small one.
          onMain: () {
            unawaited(AjanBridge.openFolio());
            unawaited(_compact());
          },
          onClose: () => unawaited(_hide()),
        ),
        _Mode.compact => Align(
          alignment: Alignment.topLeft,
          child: NotificationListener<SizeChangedLayoutNotification>(
            onNotification: (_) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
              return false;
            },
            child: SizeChangedLayoutNotifier(
              child: ClipRRect(
                key: _card,
                borderRadius: BorderRadius.circular(16),
                child: AjanFloat(
                  ajan: ajan,
                  inWindow: true,
                  onFull: () => unawaited(_full(null)),
                ),
              ),
            ),
          ),
        ),
      },
    ),
  );
}

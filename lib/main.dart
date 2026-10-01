import 'services/desktop/window_session.dart';
import 'services/editor/editor_drafts.dart';

import 'dart:io';
import 'dart:async';

import 'services/desktop/desktop_instance.dart';
import 'services/platform/document_launch.dart';
import 'services/platform/onboarding_store.dart';
import 'services/desktop/desktop_companion.dart';
import 'services/desktop/native_window.dart';
import 'ui/desktop/quick_search_palette.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:window_manager/window_manager.dart';

import 'editor_app.dart';
import 'preview_app.dart';
import 'services/platform/editor_window.dart' show previewFlag;
import 'ui/home_page.dart';
import 'ui/widgets/desktop_frame.dart';
import 'ui/widgets/onboarding_gate.dart';
import 'ui/widgets/folio_about_dialog.dart';
import 'services/editor/editor_settings.dart';
import 'services/editor/suggestions/phrase_memory.dart';
import 'services/legal/legal_settings.dart';
import 'ui/widgets/overlay_card.dart';
import 'ui/widgets/hover_document_preview.dart';
import 'ui/theme/theme_controller.dart';
import 'services/search/library_controller.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/suggestion_list.dart';

void main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  // LifeOS Editör: the editor alone, in a window of its own, without the
  // archive, the tray or the single-instance lock.
  if (arguments.contains(previewFlag)) {
    await runPreviewApp([
      for (final argument in arguments)
        if (argument != previewFlag) argument,
    ]);
    return;
  }
  if (arguments.contains(editorFlag)) {
    unawaited(LegalSettings.instance.load());
    unawaited(EditorSettings.instance.load());
    unawaited(PhraseMemory.shared().then((_) {}, onError: (_) {}));
    await runEditorApp([
      for (final argument in arguments)
        if (argument != editorFlag) argument,
    ]);
    return;
  }
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Liberation Fonts',
    ], await rootBundle.loadString('fonts/pdf/LICENSE-Liberation.txt'));
  });

  // Read before the first document opens, so a reader who turned these off
  // never sees them flash on.
  unawaited(LegalSettings.instance.load());
  unawaited(EditorSettings.instance.load());

  final startup = Stopwatch()..start();
  final sessionFuture = Platform.isLinux || Platform.isWindows
      ? WindowSession.load()
      : Future<WindowSession?>.value();
  DesktopInstance? instance;
  if (Platform.isLinux || Platform.isWindows) {
    instance = await DesktopInstance.acquire(
      arguments.contains('--quick-search')
          ? ['--quick-search']
          : DocumentLaunch.parse(arguments).arguments,
    );
    if (instance == null) exit(0);
  }
  final windowSession = await sessionFuture;
  bool desktopChrome = false;
  WindowOptions? pendingWindowOptions;
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    try {
      await windowManager.ensureInitialized();
      desktopChrome = Platform.isLinux || Platform.isWindows;
      final windowOptions = WindowOptions(
        titleBarStyle: desktopChrome
            ? TitleBarStyle.hidden
            : TitleBarStyle.normal,
        windowButtonVisibility: !desktopChrome,
        size: windowSession?.data.size ?? const Size(1200, 800),
        minimumSize: const Size(900, 600),
        center: true,
        title: 'LifeOS Folio',
      );
      pendingWindowOptions = windowOptions;
    } catch (_) {
      desktopChrome = false;
      try {
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      } catch (_) {}
    }
  }

  runApp(
    EvrakConvertApp(
      windowSession: windowSession,
      desktopChrome: desktopChrome,
      instance: instance,
      startQuick: arguments.contains('--quick-search'),
      onboarding: true,
      initialPaths: DocumentLaunch.parse(arguments).paths,
      initialEdit: DocumentLaunch.parse(arguments).edit,
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (Platform.environment['FOLIO_STARTUP_TRACE'] == '1') {
      stderr.writeln(
        'Folio first Flutter frame: ${startup.elapsedMilliseconds} ms',
      );
    }
  });
  if (pendingWindowOptions != null) {
    await windowManager.waitUntilReadyToShow(pendingWindowOptions, () async {
      // A window left maximized opens maximized on Windows, rather than
      // appearing at its normal size and growing.
      if (Platform.isWindows && windowSession?.data.maximized == true) {
        await windowSession!.restore(showMaximized: showMaximized);
      } else {
        await windowManager.show();
        await windowSession?.restore();
      }
      await windowManager.focus();
    });
  }
}

class EvrakConvertApp extends StatefulWidget {
  final WindowSession? windowSession;
  final DesktopInstance? instance;
  final bool startQuick;
  final bool onboarding;
  final bool desktopChrome;
  final List<String> initialPaths;
  final bool initialEdit;
  final LibraryController? library;
  final ThemeController? appearance;
  const EvrakConvertApp({
    super.key,
    this.desktopChrome = false,
    this.windowSession,
    this.instance,
    this.startQuick = false,
    this.onboarding = false,
    this.initialPaths = const [],
    this.initialEdit = false,
    this.library,
    this.appearance,
  });
  @override
  State<EvrakConvertApp> createState() => _EvrakConvertAppState();
}

class _EvrakConvertAppState extends State<EvrakConvertApp> {
  DesktopCompanion? companion;
  StreamSubscription<List<String>>? _launchRequests;
  final _navigator = GlobalKey<NavigatorState>();
  final _quickNavigator = GlobalKey<NavigatorState>();
  final _homeKey = GlobalKey<HomePageState>();
  bool _backPending = false;
  bool _popPending = false;

  // Run before focused text fields consume Escape. Each key press dismisses
  // exactly one layer, with route PopScopes and draft decisions still honored.
  KeyEventResult _escape(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // The suggestion list under the caret goes first: it sits over the
    // document, and closing it must not also close the page.
    if (SuggestionPopup.dismissActive()) return KeyEventResult.handled;
    final quick = companion?.quick == true;
    final navigator = (quick ? _quickNavigator : _navigator).currentState;
    if (navigator?.canPop() == true) {
      if (!_popPending) {
        _popPending = true;
        navigator!.maybePop().whenComplete(() => _popPending = false);
      }
      return KeyEventResult.handled;
    }
    if (OverlayCard.dismissActive()) return KeyEventResult.handled;
    if (HoverDocumentPreview.dismissActive()) return KeyEventResult.handled;
    if (quick) {
      companion!.dismiss();
      return KeyEventResult.handled;
    }
    if (_homeKey.currentState == null) return KeyEventResult.ignored;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext?.findAncestorStateOfType<EditableTextState>() != null) {
      // EditableText dismisses its selection toolbar first, then delegates to
      // our ancestor DismissIntent action when there is no toolbar to close.
      Actions.maybeInvoke(focusContext!, const DismissIntent());
    } else {
      _requestPageBack();
    }
    return KeyEventResult.handled;
  }

  void _requestPageBack() {
    if (_backPending) return;
    _backPending = true;
    _escapePage().whenComplete(() => _backPending = false);
  }

  Future<void> _escapePage() async {
    if (widget.desktopChrome) {
      try {
        if (await windowManager.isFullScreen()) {
          await windowManager.setFullScreen(false);
          return;
        }
      } catch (_) {
        /* Navigation also works without native window controls. */
      }
    }
    if (mounted) await _homeKey.currentState?.escapeBack();
  }

  final _drafts = EditorDrafts();
  late final ThemeController appearance;
  late final LibraryController library;
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_escape);
    library = widget.library ?? LibraryController();
    appearance = widget.appearance ?? ThemeController();
    appearance.load();
    _startSuggestions();
    if (widget.instance != null) {
      companion = DesktopCompanion(
        windowSession: widget.windowSession,
        onShowHome: () => _homeKey.currentState?.showHomeFromTray(),
        beforeClose: () async {
          if (companion?.quick == true) {
            await companion!.showMain(showHome: false);
          }
          final context = _navigator.currentState?.overlay?.context;
          return context != null &&
              context.mounted &&
              await _drafts.confirm(context);
        },
        onQuit: () {
          widget.instance?.close();
        },
      );
      _launchRequests = widget.instance!.requests.listen((args) {
        if (args.contains('--quick-search')) {
          _openQuick();
        } else {
          companion!.showMain(paths: DocumentLaunch.parse(args).arguments);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await companion!.load();
        if (widget.startQuick && mounted) await _openQuick();
      });
    }
  }

  Future<void> _openQuick() async {
    await widget.windowSession?.restored;
    if (widget.onboarding &&
        !(await const OnboardingStore().load()).licenseAccepted) {
      await companion?.showMain();
      return;
    }
    await library.initialize();
    await companion?.toggleQuick();
  }

  Timer? _learnArchive;

  /// Opens what the editor's suggestions have learned, and a while after
  /// start, once the index has settled, lets them learn from the archive.
  void _startSuggestions() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    unawaited(PhraseMemory.shared().then((_) {}, onError: (_) {}));
    _learnArchive = Timer(const Duration(minutes: 2), () async {
      try {
        final memory = await PhraseMemory.shared();
        await memory.learnArchiveIfDue(
          widget.library?.databasePath ??
              await LibraryController.defaultDatabasePath(),
          allowed: EditorSettings.instance.learnArchive,
        );
      } on Object catch (e) {
        debugPrint('Öneriler: $e');
      }
    });
  }

  @override
  void dispose() {
    _learnArchive?.cancel();
    FocusManager.instance.removeEarlyKeyEventHandler(_escape);
    _launchRequests?.cancel();
    companion?.dispose();
    widget.windowSession?.dispose();
    if (widget.appearance == null) appearance.dispose();
    if (widget.library == null) library.dispose();
    super.dispose();
  }

  Widget _home() => Actions(
    actions: {
      DismissIntent: CallbackAction<DismissIntent>(
        onInvoke: (_) {
          _requestPageBack();
          return null;
        },
      ),
    },
    child: HomePage(
      key: _homeKey,
      onEscape: _requestPageBack,
      drafts: _drafts,
      initialPaths: widget.initialPaths,
      initialEdit: widget.initialEdit,
      desktopLaunches: companion?.launches.stream,
      library: library,
      appearance: appearance,
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([appearance, ?companion]),
    builder: (context, _) => companion == null
        ? _app()
        : CompanionScope(notifier: companion!, child: _app()),
  );

  Widget _app() => MaterialApp(
    navigatorKey: _navigator,
    builder: (context, child) => LayoutBuilder(
      builder: (context, constraints) {
        final quick = companion?.quick ?? false;
        final main = widget.desktopChrome
            ? DesktopFrame(
                closeToTray:
                    companion != null &&
                    companion!.enabled &&
                    (companion!.trayReady || companion!.shortcutReady),
                onAbout: () {
                  final context = _navigator.currentState?.overlay?.context;
                  if (context != null) showFolioAbout(context);
                },
                child: child ?? const SizedBox.shrink(),
              )
            : child ?? const SizedBox.shrink();
        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: quick
                  ? companion!.mainBounds.width.clamp(900, 10000)
                  : constraints.maxWidth,
              height: quick
                  ? companion!.mainBounds.height.clamp(600, 10000)
                  : constraints.maxHeight,
              child: Offstage(
                offstage: quick,
                child: TickerMode(enabled: !quick, child: main),
              ),
            ),
            if (quick)
              Positioned.fill(
                child: Navigator(
                  key: _quickNavigator,
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => QuickSearchPalette(
                      library: library,
                      onDismiss: companion!.dismiss,
                      onMain: () => companion!.showMain(),
                      onOpen: (file) => companion!.showMain(paths: [file.path]),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
    title: 'LifeOS Folio',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: appearance.mode,
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      FlutterQuillLocalizations.delegate,
    ],
    supportedLocales: const [Locale('tr', 'TR'), Locale('en', 'US')],
    locale: const Locale('tr', 'TR'),
    home: widget.onboarding
        ? OnboardingGate(
            appearance: appearance,
            library: library,
            externalDocument: widget.initialPaths.any(
              FileSystemEntity.isFileSync,
            ),
            child: _home(),
          )
        : _home(),
  );
}

import 'services/ai/ai_assistant.dart';
import 'services/desktop/window_session.dart';
import 'services/editor/editor_drafts.dart';

import 'dart:io';
import 'dart:async';

import 'services/desktop/desktop_instance.dart';
import 'services/desktop/mac_quit.dart';
import 'services/desktop/screen_fit.dart';
import 'services/platform/agenda_launch.dart';
import 'services/portal/lifeos_agenda.dart';
import 'services/ai/folio_mcp.dart';
import 'services/ai/ai_external.dart';
import 'services/ai/ai_refresh.dart';
import 'services/portal/portal_channel.dart';
import 'services/voice/ajan_link.dart';
import 'ui/agenda/uets_connect.dart';
import 'ui/widgets/uyap_connect_view.dart';
import 'services/platform/data_reset.dart';
import 'services/platform/document_launch.dart';
import 'services/live/live_links.dart';
import 'services/platform/onboarding_store.dart';
import 'services/library/file_library.dart';
import 'services/security/app_lock.dart';
import 'services/desktop/desktop_companion.dart';
import 'services/desktop/native_window.dart';
import 'services/voice/folio_ajan.dart';
import 'services/voice/wake_word.dart';
import 'ui/desktop/ajan_float.dart';
import 'ui/desktop/jarvis_view.dart';
import 'ui/desktop/quick_search_palette.dart';

import 'package:flutter/material.dart';

import 'services/platform/app_language.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:window_manager/window_manager.dart';

import 'editor_app.dart';
import 'preview_app.dart';
import 'ofis_app.dart';
import 'services/platform/app_edition.dart';
import 'services/platform/editor_window.dart' show ofisFlag, previewFlag;
import 'ui/home_page.dart';
import 'ui/widgets/desktop_frame.dart';
import 'ui/security/identity_check.dart';
import 'ui/security/app_lock_gate.dart';
import 'ui/widgets/onboarding_gate.dart';
import 'ui/widgets/folio_about_dialog.dart';
import 'services/editor/editor_settings.dart';
import 'services/fonts/system_font_catalog.dart';
import 'services/preview/pdf_fonts.dart';
import 'services/editor/suggestions/phrase_memory.dart';
import 'services/legal/legal_settings.dart';
import 'ui/widgets/overlay_card.dart';
import 'ui/widgets/hover_document_preview.dart';
import 'ui/theme/theme_controller.dart';
import 'services/search/library_controller.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/suggestion_list.dart';
import 'ui/theme/folio_palette.dart';

void main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  // LifeOS Ofis, said before anything asks where its records are kept:
  // they are its own, never Folio's.
  final asOfis = arguments.contains(ofisFlag) || AppEdition.packagedAsOfis;
  if (asOfis) AppEdition.current = AppEdition.ofis;
  // `--ajanda-yaz` (LifeOS's timer): the agenda file written and LifeOS's
  // requests kept, with no window (none is shown before a first frame),
  // beside an open Folio or without one; and nothing else of a start.
  if (Platform.isLinux && arguments.contains(agendaWriteFlag)) {
    exit(await LifeosAgendaWriter.runOnce());
  }
  // `--mcp` (the lawyer's AI program, started by Folio): Folio's legal
  // tools on standard input and output, with no window, until it closes.
  if (Platform.isLinux && arguments.contains(FolioMcp.flag)) {
    exit(
      await FolioMcp.serve(external: arguments.contains(FolioExternal.flag)),
    );
  }
  // Tüm verileri temizle left what was open then: cleared before anything
  // is read.
  await DataReset.finishPending();
  // LifeOS Editör: the editor alone, in a window of its own, without the
  // archive, the tray or the single-instance lock.
  // LifeOS Ofis: the documents and the editor for anyone (lib/ofis_app.dart).
  if (asOfis) {
    unawaited(SystemFontCatalog.load().then((_) {}, onError: (_) {}));
    unawaited(LegalSettings.instance.load());
    unawaited(EditorSettings.instance.load());
    await runOfisApp([
      for (final argument in arguments)
        if (argument != ofisFlag) argument,
    ]);
    return;
  }
  if (arguments.contains(previewFlag)) {
    await runPreviewApp([
      for (final argument in arguments)
        if (argument != previewFlag) argument,
    ]);
    return;
  }
  if (arguments.contains(editorFlag)) {
    // The document waits for the computer's fonts: looked up while the
    // window is made, not after.
    unawaited(SystemFontCatalog.load().then((_) {}, onError: (_) {}));
    unawaited(LegalSettings.instance.load());
    unawaited(EditorSettings.instance.load());
    // What the suggestions learned opens once the document is on screen
    // (runEditorApp): reading and ranking it held the first frame.
    await runEditorApp([
      for (final argument in arguments)
        if (argument != editorFlag) argument,
    ]);
    return;
  }
  // A document opened from outside (the file manager's double click) is
  // shown in a window of its own, as Windows's "Folio ile önizle" always
  // did: a second one no longer takes the first one's place in Folio's
  // window, and two can be read side by side. Folio's own window is for
  // its library, and for a document asked to be edited (`--edit`).
  if (Platform.isLinux || Platform.isWindows) {
    final own = previewLaunch(arguments);
    if (own.isNotEmpty &&
        (await const OnboardingStore().load()).licenseAccepted) {
      for (final other in own.skip(1)) {
        unawaited(openPreviewWindow(other));
      }
      await runPreviewApp([own.first]);
      return;
    }
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
  // `--ajanda [uid]` (LifeOS's notification centre): the agenda, at that
  // record; what is left of the arguments are documents, as ever.
  final agenda = AgendaLaunch.parse(arguments);
  final documents = DocumentLaunch.parse(AgendaLaunch.without(arguments));
  final sessionFuture =
      Platform.isLinux || Platform.isWindows || Platform.isMacOS
      ? WindowSession.load()
      : Future<WindowSession?>.value();
  DesktopInstance? instance;
  // A Mac too: an editor's "Folio'da aç" and a preview's "Düzenle" start
  // Folio again, and that second one hands its document to the first.
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    try {
      instance = await DesktopInstance.acquire(
        arguments.contains('--quick-search')
            ? ['--quick-search']
            : arguments.contains('--folio-ajan')
            ? ['--folio-ajan']
            : agenda != null
            ? agenda.arguments
            : documents.arguments,
      );
    } on StateError catch (e) {
      // The open Folio does not answer: said, and this one ends, not left
      // running with no window.
      DesktopInstance.tellStuck(e.message);
      exit(1);
    }
    if (instance == null) exit(0);
  }
  final windowSession = await sessionFuture;
  // An invitation's link Folio was started with: the home page asks to
  // join once it is up; and this Folio named as what opens them.
  if (documents.link case final link?) {
    LiveLinks.take(link);
  }
  if (Platform.isLinux || Platform.isWindows) {
    unawaited(LiveLinkRegistration.ensure());
  }
  bool desktopChrome = false;
  WindowOptions? pendingWindowOptions;
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    try {
      await windowManager.ensureInitialized();
      // Folio's own caption on a Mac too, over a hidden title bar: the
      // ribbon's tabs are in it. The system's traffic lights are kept.
      desktopChrome = true;
      final windowOptions = WindowOptions(
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: Platform.isMacOS,
        size: await fitToPrimaryScreen(
          windowSession?.data.size ?? const Size(1200, 800),
        ),
        minimumSize: const Size(900, 600),
        center: true,
        title: 'LifeOS Folio',
      );
      if (Platform.isLinux) {
        // GTK shows the window on Flutter's first frame. Put as it was left
        // before that, while it is not yet on screen: it appears at its
        // size or maximized at once, not at GTK's size first, then the
        // saved one, then maximized.
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );
        await windowManager.setTitle(windowOptions.title!);
        await windowManager.setMinimumSize(windowOptions.minimumSize!);
        // GTK has it maximized already (linux/runner): the size kept is
        // what un-maximizing returns to, the window not moved meanwhile.
        if (windowSession != null) {
          await windowSession.restore(maximizedByRunner: true);
        } else {
          await windowManager.setSize(windowOptions.size!);
        }
      } else {
        pendingWindowOptions = windowOptions;
      }
    } catch (_) {
      desktopChrome = false;
      try {
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      } catch (_) {}
    }
  }

  // Read before the first frame, so that nothing shows before the lock.
  await AppLock.instance.load();
  runApp(
    EvrakConvertApp(
      windowSession: windowSession,
      desktopChrome: desktopChrome,
      instance: instance,
      startQuick: arguments.contains('--quick-search'),
      startAjan: arguments.contains('--folio-ajan'),
      onboarding: true,
      initialPaths: documents.paths,
      initialEdit: documents.edit,
      initialAgenda: agenda,
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // The fonts unembedded papers name, ready before the first is opened.
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      unawaited(preloadPdfFonts());
    }
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

  /// Started with `--folio-ajan`: Folio Ajan full screen.
  final bool startAjan;
  final bool onboarding;
  final bool desktopChrome;
  final List<String> initialPaths;
  final bool initialEdit;

  /// Started with `--ajanda`: the agenda opens at its record.
  final AgendaLaunch? initialAgenda;
  final LibraryController? library;
  final ThemeController? appearance;
  const EvrakConvertApp({
    super.key,
    this.desktopChrome = false,
    this.windowSession,
    this.instance,
    this.startQuick = false,
    this.startAjan = false,
    this.onboarding = false,
    this.initialPaths = const [],
    this.initialEdit = false,
    this.initialAgenda,
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

  /// A program asked for UYAP or UETS: on Folio Ajan's screen only the
  /// e-signature PIN, there; elsewhere the connection dialog.
  Future<bool> _askConnect(UyapNeed need, String why) async {
    final c = companion;
    if (c != null && c.quick && c.jarvis && AjanLinks.instance.shown > 0) {
      return AjanLinks.instance.request(need, why);
    }
    final quick = c?.quick == true;
    final context = (quick ? _quickNavigator : _navigator).currentContext;
    if (context == null || !context.mounted) return false;
    return switch (need) {
      UyapNeed.web => connectUyap(
        context,
        channels: const {PortalChannel.uyapWeb},
        why: why,
      ),
      UyapNeed.uets => connectUets(context),
    };
  }

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_escape);
    library = widget.library ?? LibraryController();
    appearance = widget.appearance ?? ThemeController();
    appearance.load();
    _startSuggestions();
    AiRefresh.askConnect = _askConnect;
    // Whether the voice is on: the bar's Folio Ajan button shows by it.
    if (widget.desktopChrome) {
      FolioAjan.instance.loadVoiceSettings();
      // "Ajan açıl": listened for while the voice and it are on in
      // Settings, set aside while a conversation has the microphone.
      FolioAjan.beforeVoice = WakeWord.instance.pause;
      WakeWord.instance.onWake = _woken;
      FolioAjan.instance.addListener(_followWake);
      // The AI setting may come after the voice's: the wake follows it too,
      // or it never began when Folio opened.
      AiSettings.on.addListener(_followWake);
    }
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
      // Folio Ajan's conversation outlives its full screen: back in the main
      // window it goes on in the voice window, in the palette there; ended
      // only when Folio hides (22 Kasım 2026).
      companion!.onJarvisLeft = (exit) {
        final ajan = FolioAjan.instance;
        if (!ajan.voice.active) return;
        switch (exit) {
          case JarvisExit.main:
            ajanFloatOpen.value = true;
          case JarvisExit.palette:
            break;
          case JarvisExit.hidden:
            unawaited(ajan.voice.stop());
        }
      };
      MacQuit.handle(
        companion!.approveQuit,
        onSettings: () async {
          await companion!.showMain(showHome: false);
          _homeKey.currentState?.showSettings();
        },
      );
      _launchRequests = widget.instance!.requests.listen((args) {
        if (args.contains('--quick-search')) {
          _openQuick();
        } else if (args.contains('--folio-ajan')) {
          // A shortcut of the desktop's own (KDE's Özel Kısayollar):
          // Folio Ajan full screen.
          unawaited(companion!.showJarvis());
        } else if (AgendaLaunch.parse(args) case final agenda?) {
          // LifeOS's agenda clicked: the window, at that record.
          unawaited(
            companion!
                .showMain(showHome: false)
                .then((_) => _homeKey.currentState?.openAgenda(agenda.uid)),
          );
        } else {
          // Started again with no document: the home page, not what was
          // open when it went to the tray (23 Ekim 2026).
          final launch = DocumentLaunch.parse(args);
          companion!.showMain(
            paths: launch.paths.isEmpty ? const [] : launch.forwarded,
          );
          if (launch.link case final link?) LiveLinks.take(link);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await companion!.load();
        if (widget.startQuick && mounted) await _openQuick();
        if (widget.startAjan && mounted) await companion!.showJarvis();
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
    FolioAjan.instance.removeListener(_followWake);
    AiSettings.on.removeListener(_followWake);
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
      initialAgenda: widget.initialAgenda,
      desktopLaunches: companion?.launches.stream,
      library: library,
      appearance: appearance,
    ),
  );

  void _followWake() {
    final ajan = FolioAjan.instance;
    final wake = WakeWord.instance;
    final want = ajan.available && ajan.settings.on && ajan.settings.wake;
    if (!want) {
      if (wake.on) unawaited(wake.stop());
      return;
    }
    if (ajan.voiceStarting || ajan.voice.active) return;
    if (!wake.on || wake.state.value == WakeState.paused) {
      unawaited(wake.start());
    }
  }

  /// "Ajan açıl" heard: the small voice window over Folio when its window
  /// is in front; Folio Ajan full screen when it is in the tray.
  Future<void> _woken() async {
    final ajan = FolioAjan.instance;
    final c = companion;
    final front =
        c == null ||
        (!c.quick &&
            await windowManager.isVisible() &&
            !await windowManager.isMinimized());
    if (!front) {
      await c.showJarvis();
      return;
    }
    if (!ajanFloatOpen.value) {
      await toggleAjanFloat(ajan);
    } else if (!ajan.voice.active) {
      await ajan.startVoice(handsFree: true);
    }
  }

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
        // The pages' own colours follow the theme (FolioPalette); read
        // here, above them, each time the theme changes.
        FolioPalette.dark = Theme.of(context).brightness == Brightness.dark;
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
                // Folio Ajan's voice, when it is on in Settings: a button in
                // the bar, a small window above the pages.
                trailing: [AjanVoicePill(ajan: FolioAjan.instance)],
                floating: ValueListenableBuilder<bool>(
                  valueListenable: ajanFloatOpen,
                  builder: (context, open, _) => open
                      ? AjanFloat(
                          ajan: FolioAjan.instance,
                          onFull: companion == null
                              ? null
                              : () {
                                  ajanFloatOpen.value = false;
                                  companion!.showJarvis();
                                },
                        )
                      : const SizedBox.shrink(),
                ),
                child: AppLockGate(
                  identify: lockIdentity,
                  child: child ?? const SizedBox.shrink(),
                ),
              )
            : AppLockGate(
                identify: lockIdentity,
                child: child ?? const SizedBox.shrink(),
              );
        // On a phone a dialog opens from below, the screen's width, its top
        // corners rounded, as a phone's own sheets do.
        final phone = constraints.maxWidth < 700;
        // The size the lawyer chose for Folio's words (Görünüm).
        final scaled = appearance.textScale == 1
            ? main
            : Builder(
                builder: (context) {
                  final media = MediaQuery.of(context);
                  return MediaQuery(
                    data: media.copyWith(
                      textScaler: TextScaler.linear(
                        media.textScaler.scale(1) * appearance.textScale,
                      ),
                    ),
                    child: main,
                  );
                },
              );
        final themed = !phone
            ? scaled
            : Builder(
                builder: (context) {
                  final theme = Theme.of(context);
                  return Theme(
                    data: theme.copyWith(
                      dialogTheme: theme.dialogTheme.copyWith(
                        alignment: Alignment.bottomCenter,
                        insetPadding: EdgeInsets.zero,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                      ),
                    ),
                    child: scaled,
                  );
                },
              );
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
                child: TickerMode(enabled: !quick, child: themed),
              ),
            ),
            if (quick)
              Positioned.fill(
                child: Navigator(
                  key: _quickNavigator,
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => ListenableBuilder(
                      listenable: companion!,
                      builder: (context, _) => companion!.blank
                          ? const SizedBox.shrink()
                          : companion!.jarvis
                          ? JarvisView(
                              ajan: FolioAjan.instance,
                              onMinimize: companion!.leaveJarvis,
                              onMain: () => companion!.showMain(),
                              onClose: companion!.dismiss,
                            )
                          : FloatingPalette(
                              onOutside: companion!.dismiss,
                              child: QuickSearchPalette(
                                library: library,
                                ajan: FolioAjan.instance,
                                onJarvis: companion!.showJarvis,
                                onDismiss: companion!.dismiss,
                                onMain: () => companion!.showMain(),
                                onOpen: (file) =>
                                    companion!.showMain(paths: [file.path]),
                              ),
                            ),
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
      AppLocalizations.delegate,
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

/// The documents [arguments] name to be shown, each in a preview window of
/// its own: files alone, with nothing else asked of Folio (no `--edit`, no
/// invitation, no agenda, no quick search, no folder). Empty otherwise, and
/// Folio's own window takes the launch.
@visibleForTesting
List<String> previewLaunch(List<String> arguments) {
  if (AgendaLaunch.parse(arguments) != null) return const [];
  final launch = DocumentLaunch.parse(AgendaLaunch.without(arguments));
  if (launch.edit || launch.link != null || launch.paths.isEmpty) {
    return const [];
  }
  // Any flag of Folio's own (the tray's start, the quick search) is its
  // window's to answer.
  final separator = arguments.indexOf('--');
  final flags = separator < 0 ? arguments : arguments.take(separator);
  if (flags.any((a) => a.startsWith('-'))) return const [];
  for (final path in launch.paths) {
    if (!FileSystemEntity.isFileSync(path) || !FileLibrary.supports(path)) {
      return const [];
    }
  }
  return launch.paths;
}

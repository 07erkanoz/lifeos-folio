import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'editor_app.dart' show EditedDot, FrameButton, opensInEditor;
import 'models/evrak_file.dart';
import 'services/editor/document_history.dart';
import 'services/editor/editor_drafts.dart';
import 'services/editor/suggestions/phrase_memory.dart';
import 'services/editor/text_anchor.dart';
import 'services/library/recent_documents.dart';
import 'services/live/live_links.dart';
import 'services/live/live_owner.dart';
import 'ui/live/live_hub.dart';
import 'ui/live/ofis_live.dart';
import 'services/platform/app_edition.dart';
import 'services/platform/app_language.dart';
import 'services/platform/document_launch.dart';
import 'services/preview/pdf_fonts.dart';
import 'services/signing/imz_file.dart';
import 'services/desktop/mac_quit.dart';
import 'services/desktop/screen_fit.dart';
import 'ui/agenda/agenda_page.dart' show AgendaColors;
import 'ui/theme/app_theme.dart';
import 'ui/theme/theme_controller.dart';
import 'preview_app.dart' show PreviewFileMenu;
import 'ui/widgets/pdf_tools_dialogs.dart';
import 'ui/widgets/viewer_bar.dart';
import 'ui/widgets/desktop_frame.dart';
import 'ui/widgets/document_history_dialog.dart';
import 'ui/widgets/editor_file_menu.dart';
import 'ui/widgets/editor_ribbon.dart';
import 'ui/widgets/editor_widget.dart';
import 'ui/widgets/file_preview.dart';
import 'ui/widgets/imz_view.dart';
import 'ui/widgets/language_button.dart';
import 'ui/widgets/folio_about_dialog.dart';
import 'ui/widgets/notice.dart';

/// LifeOS Ofis (approved mockup, 27 Ekim 2026): Folio's documents and editor
/// for anyone, without UYAP, the office, clients, cash or the agenda. Its
/// own launcher (`lifeos_ofis`) starts this app with `--ofis`; a document
/// it is given opens to be read, Düzenle writes in it, and with none the
/// recent documents show. Like LifeOS Editör it takes no lock and keeps no
/// archive: each launch is a window of its own.
Future<void> runOfisApp(List<String> arguments) async {
  AppEdition.current = AppEdition.ofis;
  final launch = DocumentLaunch.parse(arguments);
  // An invitation's link Ofis was opened with: joined once it shows.
  if (launch.link case final link?) LiveLinks.take(link);
  final path = launch.paths
      .where(FileSystemEntity.isFileSync)
      .where(_previewable)
      .firstOrNull;
  var chrome = false;
  WindowOptions? options;
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    try {
      await windowManager.ensureInitialized();
      chrome = true;
      options = WindowOptions(
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: Platform.isMacOS,
        size: await fitToPrimaryScreen(const Size(1280, 840)),
        minimumSize: const Size(760, 540),
        center: true,
        title: ofisTitle(path),
      );
      await windowManager.setPreventClose(true);
    } catch (_) {
      chrome = false;
      options = null;
    }
  }
  runApp(
    OfisApp(
      path: path,
      edit: launch.edit && path != null && _editable(path),
      desktopChrome: chrome,
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(PhraseMemory.shared().then((_) {}, onError: (_) {}));
    unawaited(preloadPdfFonts());
  });
  if (options != null) {
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
}

bool _previewable(String path) {
  final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
  return extension == ImzFile.extension ||
      EvrakFormat.supportedExtensions.contains(extension);
}

bool _editable(String path) =>
    opensInEditor(EvrakFormat.fromExtension(p.extension(path)));

/// "dilekce.udf — LifeOS Ofis", or the program alone.
String ofisTitle(String? path) =>
    path == null ? 'LifeOS Ofis' : '${p.basename(path)} — LifeOS Ofis';

class OfisApp extends StatefulWidget {
  const OfisApp({
    super.key,
    this.path,
    this.edit = false,
    this.desktopChrome = false,
  });

  /// The document to show, if Ofis was opened on one.
  final String? path;

  /// Opened to be written in, not only read.
  final bool edit;
  final bool desktopChrome;

  @override
  State<OfisApp> createState() => _OfisAppState();
}

class _OfisAppState extends State<OfisApp> with WindowListener {
  final _navigator = GlobalKey<NavigatorState>();
  final _drafts = EditorDrafts();

  /// The list Folio and LifeOS Editör keep too.
  final _recent = RecentDocuments();
  final _appearance = ThemeController();

  /// The document shown; null on the home page, or for a new one.
  late String? _path = widget.path;

  /// Being written in; a new document has no [_path] yet.
  late bool _editing = widget.edit;

  /// What a new document is made as.
  // Ofis writes Word first: its users' documents; UDF is UYAP's.
  EvrakFormat _newFormat = EvrakFormat.docx;
  DocumentRevision? _recovery;
  late EditorDraft _draft = _draftFor(widget.path);
  int _generation = 0;
  bool _closing = false, _quitApproved = false;

  bool get _home => _path == null && !_editing;

  /// Live documents: shared from the editor, joined with a code.
  late final _live = OfisLive(() => _context);

  /// How many times the document shown was asked to be shared live as it
  /// opens (EditorWidget.liveAsk).
  int _liveAsk = 0;

  /// Canlı belge: a code to join with, or a document to share.
  Future<void> _liveHub() async {
    final context = _context;
    if (context == null) return;
    await LiveHub.show(
      context,
      recent: _recent.files,
      onJoin: (code) => unawaited(_live.join(code: code, start: true)),
      onShare: (file) => unawaited(_shareLive(file.path)),
      onPick: () => unawaited(_pickToShareLive()),
    );
  }

  Future<void> _shareLive(String path) async {
    if (!LiveHub.shareable(EvrakFormat.fromExtension(p.extension(path)))) {
      return;
    }
    await _show(path, edit: true);
    if (mounted && _path == path && _editing) setState(() => _liveAsk++);
  }

  Future<void> _pickToShareLive() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: AppLanguage.t.ofisLive,
      type: FileType.custom,
      allowedExtensions: [
        for (final f in EvrakFormat.values)
          if (LiveHub.shareable(f)) f.defaultExtension,
      ],
    );
    final path = picked?.files.single.path;
    if (path != null && mounted) await _shareLive(path);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_appearance.load());
    unawaited(AppLanguage.instance.load());
    if (widget.desktopChrome) windowManager.addListener(this);
    MacQuit.handle(_approveQuit);
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      // On the network for live documents, if no other window of Ofis is:
      // invited by a device nearby, and sharing from the editor.
      startLiveHere = _live.start;
      unawaited(_live.start());
    }
    unawaited(
      _recent.load().then((_) async {
        final path = widget.path;
        if (path != null) await _recent.remember([EvrakFile.fromPath(path)]);
        if (mounted) setState(() {});
      }),
    );
  }

  @override
  void dispose() {
    if (widget.desktopChrome) windowManager.removeListener(this);
    _live.dispose();
    _appearance.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() => unawaited(_close());

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      final context = _navigator.currentState?.overlay?.context;
      if (context == null || !context.mounted) return;
      if (!await _drafts.confirm(context)) return;
      _quitApproved = true;
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } finally {
      _closing = false;
    }
  }

  Future<bool> _approveQuit() async {
    if (_quitApproved) return true;
    if (_closing) return false;
    final context = _navigator.currentState?.overlay?.context;
    if (context == null || !context.mounted) return true;
    final ok = await _drafts.confirm(context);
    if (ok) _quitApproved = true;
    return ok;
  }

  EditorDraft _draftFor(String? path) => _drafts.draft(
    'ofis-$_generation',
    path == null
        ? AppLanguage.t.ofisNewDocumentTitle(_newFormat.defaultExtension)
        : p.basename(path),
  );

  BuildContext? get _context => _navigator.currentState?.overlay?.context;

  /// Moves to [path] (null: home, or with [edit] a new document), after
  /// asking about unsaved work in the one being written.
  Future<void> _show(
    String? path, {
    bool edit = false,
    DocumentRevision? recovery,
    TextAnchor? at,
  }) async {
    final context = _context;
    if (context == null) return;
    if (_editing && !await _drafts.confirm(context, only: _draft)) return;
    if (!mounted) return;
    setState(() {
      _generation++;
      _liveAsk = 0;
      _reveal = at;
      _path = path;
      _editing = edit;
      _recovery = recovery;
      _draft = _draftFor(path ?? recovery?.name);
    });
    if (widget.desktopChrome) {
      unawaited(windowManager.setTitle(ofisTitle(path)));
    }
    if (path != null) {
      await _recent.remember([EvrakFile.fromPath(path)]);
      if (mounted) setState(() {});
    }
  }

  Future<void> _open() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: AppLanguage.t.ofisOpenDialog,
      type: FileType.custom,
      allowedExtensions: [
        ...EvrakFormat.supportedExtensions,
        ImzFile.extension,
      ],
    );
    final path = picked?.files.single.path;
    if (path != null) await _openPath(path);
  }

  Future<void> _openPath(String path) async {
    final context = _context;
    if (!await File(path).exists()) {
      await _recent.remove(path);
      if (mounted) setState(() {});
      if (context != null && context.mounted) {
        showNotice(context, context.l.ofisFileMoved, detail: path);
      }
      return;
    }
    if (!_previewable(path)) {
      if (context != null && context.mounted) {
        showNotice(
          context,
          context.l.ofisCannotOpenType,
          detail: p.basename(path),
          kind: NoticeKind.error,
        );
      }
      return;
    }
    await _show(path);
  }

  Future<void> _new([EvrakFormat format = EvrakFormat.docx]) async {
    _newFormat = format;
    await _show(null, edit: true);
  }

  /// Where the preview was double-clicked, for the editor to open at.
  TextAnchor? _reveal;

  Future<void> _edit({TextAnchor? at}) async {
    final path = _path;
    if (path == null || !_editable(path)) return;
    await _show(path, edit: true, at: at);
  }

  /// A double-click on a text document's page writes in it there, as in
  /// Folio; not a PDF, whose text is another document's.
  bool _editsOnDoubleClick(String path) =>
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
      _editable(path) &&
      EvrakFormat.fromExtension(p.extension(path)) != EvrakFormat.pdf;

  Future<void> _openRecovery() async {
    final context = _context;
    if (context == null) return;
    final entry = await showRecoverableDrafts(context);
    if (entry == null || !context.mounted) return;
    if (entry.format != 'rich-draft') {
      showNotice(context, context.l.ofisDraftCannotOpen, detail: entry.name);
      return;
    }
    final source = entry.sourcePath;
    final exists = source != null && await File(source).exists();
    await _show(exists ? source : null, edit: true, recovery: entry);
  }

  void _saved(String path) {
    unawaited(
      _recent.remember([EvrakFile.fromPath(path)]).then((_) {
        if (mounted) setState(() {});
      }),
    );
    if (p.extension(path).toLowerCase() == '.pdf') return;
    if (widget.desktopChrome) {
      unawaited(windowManager.setTitle(ofisTitle(path)));
    }
  }

  Widget _body() {
    if (_home) {
      return OfisHome(
        recent: _recent.files,
        onOpen: () => unawaited(_open()),
        onNew: (format) => unawaited(_new(format)),
        onOpenFile: (path) => unawaited(_openPath(path)),
        onLive: () => unawaited(_liveHub()),
      );
    }
    final path = _path;
    if (!_editing && path != null) {
      if (ImzFile.isImz(path)) {
        return Scaffold(
          key: ValueKey('ofis-imz-$_generation'),
          body: ImzView(path: path),
        );
      }
      return Scaffold(
        key: ValueKey('ofis-preview-$_generation'),
        body: Stack(
          children: [
            Positioned.fill(
              child: FilePreview(
                path: path,
                onEditAt: _editsOnDoubleClick(path)
                    ? (anchor) => unawaited(_edit(at: anchor))
                    : null,
                onCropped: (saved) {
                  final context = _context;
                  if (context == null) return;
                  showNotice(
                    context,
                    p.basename(saved),
                    kind: NoticeKind.success,
                    actionLabel: context.l.ofisOpen,
                    onAction: () => unawaited(_openPath(saved)),
                    duration: const Duration(seconds: 6),
                  );
                },
              ),
            ),
            // At the right end of the viewer's row of tools: print, keep
            // a copy, keep as a PDF, show in its folder.
            Positioned(
              top: (ViewerToolbar.height - 36) / 2,
              right: 8,
              child: PreviewFileMenu(path: path),
            ),
          ],
        ),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // E-signing with a card is a Turkish lawyer's work, not Ofis's
            // users': an .imz is opened and shown, none is made here.
            if (_editable(path))
              // Above the viewer's status line, not over it.
              Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: FloatingActionButton.extended(
                  key: const ValueKey('ofis-edit'),
                  heroTag: 'ofis-edit',
                  onPressed: () => unawaited(_edit()),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: Text(context.l.ofisEdit),
                ),
              ),
          ],
        ),
      );
    }
    return Scaffold(
      body: EditorWidget(
        hostTabs: widget.desktopChrome,
        key: ValueKey('ofis-editor-$_generation'),
        draft: _draft,
        initialFilePath: path,
        initialFormat: path == null
            ? (_recovery == null ? _newFormat : null)
            : EvrakFormat.fromExtension(p.extension(path)),
        recovery: _recovery,
        reveal: _reveal,
        liveAsk: _liveAsk,
        fileHost: EditorFileHost(
          onNew: () => unawaited(_new()),
          onOpen: () => unawaited(_open()),
          recent: () => _recent.files,
          onOpenRecent: (file) => unawaited(_openPath(file.path)),
          onRecovery: () => unawaited(_openRecovery()),
        ),
        onSaved: _saved,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_appearance, AppLanguage.instance]),
    builder: (context, _) => MaterialApp(
      navigatorKey: _navigator,
      title: ofisTitle(_path),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _appearance.mode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
        AppLocalizations.delegate,
      ],
      // The system's language, or the one chosen in the language menu.
      supportedLocales: AppLanguage.supported,
      locale: AppLanguage.instance.locale,
      localeResolutionCallback: AppLanguage.resolve,
      builder: (context, child) => widget.desktopChrome
          ? DesktopFrame(
              title: _path == null
                  ? (_editing
                        ? context.l.ofisNewDocumentTitle(
                            _newFormat.defaultExtension,
                          )
                        : 'LifeOS Ofis')
                  : p.basename(_path!),
              titleIcon: _home ? null : Icons.description_outlined,
              titleTrailing: _editing
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        EditedDot(_draft.edited),
                        const SizedBox(width: 16),
                        const EditorRibbonTabs(height: 38),
                      ],
                    )
                  : null,
              icon: AppEdition.ofis.icon,
              iconTooltip: context.l.ofisAbout,
              leading: [
                if (!_home)
                  FrameButton(
                    key: const ValueKey('ofis-home'),
                    icon: Icons.grid_view_rounded,
                    label: context.l.ofisDocuments,
                    tooltip: context.l.ofisDocuments,
                    onPressed: () => unawaited(_show(null)),
                  ),
                FrameButton(
                  key: const ValueKey('ofis-new'),
                  icon: Icons.note_add_rounded,
                  label: context.l.ofisNew,
                  tooltip: context.l.ofisNewTooltip,
                  onPressed: () => unawaited(_new()),
                ),
                FrameButton(
                  key: const ValueKey('ofis-open'),
                  icon: Icons.folder_open_rounded,
                  label: context.l.ofisOpen,
                  tooltip: context.l.ofisOpenTooltip,
                  onPressed: () => unawaited(_open()),
                ),
                FrameButton(
                  key: const ValueKey('ofis-live'),
                  icon: Icons.cast_outlined,
                  label: context.l.ofisLive,
                  tooltip: context.l.ofisLiveDetail,
                  onPressed: () => unawaited(_liveHub()),
                ),
              ],
              onAbout: () {
                final context = _context;
                if (context != null) showFolioAbout(context);
              },
              child: child ?? const SizedBox.shrink(),
            )
          : child ?? const SizedBox.shrink(),
      home: CallbackShortcuts(
        bindings: {
          SingleActivator(
            LogicalKeyboardKey.keyO,
            control: !Platform.isMacOS,
            meta: Platform.isMacOS,
          ): () =>
              unawaited(_open()),
          SingleActivator(
            LogicalKeyboardKey.keyN,
            control: !Platform.isMacOS,
            meta: Platform.isMacOS,
          ): () =>
              unawaited(_new()),
        },
        child: _body(),
      ),
    ),
  );
}

/// LifeOS Ofis's first page (approved mockup, 27 Ekim 2026): open a
/// document, make a new one, drop one in, or take up a recent one.
class OfisHome extends StatefulWidget {
  const OfisHome({
    super.key,
    required this.recent,
    required this.onOpen,
    required this.onNew,
    required this.onOpenFile,
    this.onLive,
  });

  /// Canlı belge: shares a document or joins one with a code.
  final VoidCallback? onLive;

  final List<EvrakFile> recent;
  final VoidCallback onOpen;
  final ValueChanged<EvrakFormat> onNew;
  final ValueChanged<String> onOpenFile;

  @override
  State<OfisHome> createState() => _OfisHomeState();
}

class _OfisHomeState extends State<OfisHome> {
  bool _dragging = false;

  static String _when(BuildContext context, DateTime t) {
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(t.year, t.month, t.day)).inDays;
    final clock =
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    if (days <= 0) return context.l.whenToday(clock);
    if (days == 1) return context.l.whenYesterday(clock);
    if (days < 7) return context.l.whenDaysAgo(days);
    return '${t.day}.${t.month.toString().padLeft(2, '0')}.${t.year}';
  }

  static DateTime? _modified(String path) {
    try {
      return File(path).lastModifiedSync();
    } catch (_) {
      return null;
    }
  }

  Widget _action({
    required Key key,
    required IconData icon,
    required String title,
    required String detail,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 260,
      child: Material(
        color: primary ? scheme.primary : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: primary
              ? BorderSide.none
              : BorderSide(color: scheme.outlineVariant),
        ),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: primary
                        ? Colors.white.withValues(alpha: .18)
                        : scheme.primary.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: primary ? scheme.onPrimary : scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: primary ? scheme.onPrimary : null,
                        ),
                      ),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: primary
                              ? scheme.onPrimary.withValues(alpha: .85)
                              : AgendaColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recent = widget.recent.take(18).toList();
    return Scaffold(
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (details) {
          setState(() => _dragging = false);
          final path = details.files.map((f) => f.path).firstOrNull;
          if (path != null) widget.onOpenFile(path);
        },
        child: ListView(
          key: const ValueKey('ofis-home-page'),
          padding: const EdgeInsets.fromLTRB(36, 28, 36, 28),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l.ofisHomeTitle,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const LanguageButton(),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _action(
                  key: const ValueKey('ofis-home-open'),
                  icon: Icons.folder_open_rounded,
                  title: context.l.ofisOpenAction,
                  detail: context.l.ofisOpenActionDetail,
                  onTap: widget.onOpen,
                  primary: true,
                ),
                _action(
                  key: const ValueKey('ofis-home-new-docx'),
                  icon: Icons.description_outlined,
                  title: context.l.ofisNewDocx,
                  detail: context.l.ofisNewDocxDetail,
                  onTap: () => widget.onNew(EvrakFormat.docx),
                ),
                _action(
                  key: const ValueKey('ofis-home-make-pdf'),
                  icon: Icons.picture_as_pdf_outlined,
                  title: context.l.ofisMakePdf,
                  detail: context.l.ofisMakePdfDetail,
                  onTap: () async {
                    final saved = await PdfBuilderDialog.show(context);
                    if (saved != null) widget.onOpenFile(saved);
                  },
                ),
                if (widget.onLive case final live?)
                  _action(
                    key: const ValueKey('ofis-home-live'),
                    icon: Icons.cast_outlined,
                    title: context.l.ofisLive,
                    detail: context.l.ofisLiveDetail,
                    onTap: live,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _dragging
                    ? scheme.primary.withValues(alpha: .08)
                    : Colors.transparent,
                border: Border.all(
                  color: _dragging ? scheme.primary : scheme.outlineVariant,
                  width: _dragging ? 2 : 1.4,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.upload_file_rounded, color: AgendaColors.muted),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      context.l.ofisDropHere,
                      style: TextStyle(color: AgendaColors.muted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              context.l.ofisRecent,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .9,
                color: AgendaColors.muted,
              ),
            ),
            const SizedBox(height: 10),
            if (recent.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  context.l.ofisRecentEmpty,
                  style: TextStyle(color: AgendaColors.muted),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, box) {
                  final columns = (box.maxWidth / 220).floor().clamp(1, 6);
                  final width = (box.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final f in recent)
                        SizedBox(width: width, child: _recentCard(f)),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _recentCard(EvrakFile f) {
    final scheme = Theme.of(context).colorScheme;
    final modified = _modified(f.path);
    final imz = ImzFile.isImz(f.path);
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        key: ValueKey('ofis-recent-${f.path}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.onOpenFile(f.path),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  imz
                      ? context.l.ofisImzBadge
                      : f.format.defaultExtension.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // An .imz by the document it holds: "sozlesme.pdf".
                      p.basenameWithoutExtension(f.path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      modified == null
                          ? (imz
                                ? context.l.ofisSignedDocument
                                : f.format.label)
                          : _when(context, modified),
                      style: TextStyle(fontSize: 12, color: AgendaColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// For tests: Ofis's home page on its own.
@visibleForTesting
Widget ofisHomeForTesting({
  List<EvrakFile> recent = const [],
  VoidCallback? onOpen,
  ValueChanged<EvrakFormat>? onNew,
  ValueChanged<String>? onOpenFile,
}) => OfisHome(
  recent: recent,
  onOpen: onOpen ?? () {},
  onNew: onNew ?? (_) {},
  onOpenFile: onOpenFile ?? (_) {},
);

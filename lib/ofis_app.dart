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
import 'services/library/recent_documents.dart';
import 'services/platform/app_edition.dart';
import 'services/platform/document_launch.dart';
import 'services/preview/pdf_fonts.dart';
import 'services/desktop/mac_quit.dart';
import 'ui/agenda/agenda_page.dart' show AgendaColors;
import 'ui/theme/app_theme.dart';
import 'ui/theme/theme_controller.dart';
import 'ui/widgets/desktop_frame.dart';
import 'ui/widgets/document_history_dialog.dart';
import 'ui/widgets/editor_file_menu.dart';
import 'ui/widgets/editor_ribbon.dart';
import 'ui/widgets/editor_widget.dart';
import 'ui/widgets/file_preview.dart';
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
        size: const Size(1280, 840),
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
  return EvrakFormat.supportedExtensions.contains(extension);
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
  EvrakFormat _newFormat = EvrakFormat.udf;
  DocumentRevision? _recovery;
  late EditorDraft _draft = _draftFor(widget.path);
  int _generation = 0;
  bool _closing = false, _quitApproved = false;

  bool get _home => _path == null && !_editing;

  @override
  void initState() {
    super.initState();
    unawaited(_appearance.load());
    if (widget.desktopChrome) windowManager.addListener(this);
    MacQuit.handle(_approveQuit);
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
        ? 'Yeni belge.${_newFormat.defaultExtension}'
        : p.basename(path),
  );

  BuildContext? get _context => _navigator.currentState?.overlay?.context;

  /// Moves to [path] (null: home, or with [edit] a new document), after
  /// asking about unsaved work in the one being written.
  Future<void> _show(
    String? path, {
    bool edit = false,
    DocumentRevision? recovery,
  }) async {
    final context = _context;
    if (context == null) return;
    if (_editing && !await _drafts.confirm(context, only: _draft)) return;
    if (!mounted) return;
    setState(() {
      _generation++;
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
      dialogTitle: 'Belge aç',
      type: FileType.custom,
      allowedExtensions: EvrakFormat.supportedExtensions,
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
        showNotice(context, 'Belge taşınmış veya kaldırılmış', detail: path);
      }
      return;
    }
    if (!_previewable(path)) {
      if (context != null && context.mounted) {
        showNotice(
          context,
          'Bu belge türü açılamıyor',
          detail: p.basename(path),
          kind: NoticeKind.error,
        );
      }
      return;
    }
    await _show(path);
  }

  Future<void> _new([EvrakFormat format = EvrakFormat.udf]) async {
    _newFormat = format;
    await _show(null, edit: true);
  }

  Future<void> _edit() async {
    final path = _path;
    if (path == null || !_editable(path)) return;
    await _show(path, edit: true);
  }

  Future<void> _openRecovery() async {
    final context = _context;
    if (context == null) return;
    final entry = await showRecoverableDrafts(context);
    if (entry == null || !context.mounted) return;
    if (entry.format != 'rich-draft') {
      showNotice(context, 'Bu taslak burada açılamıyor', detail: entry.name);
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

  void _signed(String path) {
    final context = _context;
    if (context == null || !context.mounted) return;
    showNotice(
      context,
      'Belge imzalandı.',
      detail: path,
      kind: NoticeKind.success,
    );
  }

  Widget _body() {
    if (_home) {
      return OfisHome(
        recent: _recent.files,
        onOpen: () => unawaited(_open()),
        onNew: (format) => unawaited(_new(format)),
        onOpenFile: (path) => unawaited(_openPath(path)),
      );
    }
    final path = _path;
    if (!_editing && path != null) {
      return Scaffold(
        key: ValueKey('ofis-preview-$_generation'),
        body: FilePreview(path: path),
        floatingActionButton: _editable(path)
            ? FloatingActionButton.extended(
                key: const ValueKey('ofis-edit'),
                onPressed: () => unawaited(_edit()),
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Düzenle'),
              )
            : null,
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
        fileHost: EditorFileHost(
          onNew: () => unawaited(_new()),
          onOpen: () => unawaited(_open()),
          recent: () => _recent.files,
          onOpenRecent: (file) => unawaited(_openPath(file.path)),
          onRecovery: () => unawaited(_openRecovery()),
        ),
        onSaved: _saved,
        onSigned: _signed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _appearance,
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
      ],
      supportedLocales: const [Locale('tr', 'TR'), Locale('en', 'US')],
      locale: const Locale('tr', 'TR'),
      builder: (context, child) => widget.desktopChrome
          ? DesktopFrame(
              title: _path == null
                  ? (_editing
                        ? 'Yeni belge.${_newFormat.defaultExtension}'
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
              iconTooltip: 'LifeOS Ofis hakkında',
              leading: [
                if (!_home)
                  FrameButton(
                    key: const ValueKey('ofis-home'),
                    icon: Icons.grid_view_rounded,
                    label: 'Belgeler',
                    tooltip: 'Belgeler',
                    onPressed: () => unawaited(_show(null)),
                  ),
                FrameButton(
                  key: const ValueKey('ofis-new'),
                  icon: Icons.note_add_rounded,
                  label: 'Yeni',
                  tooltip: 'Yeni UDF belge · Ctrl+N',
                  onPressed: () => unawaited(_new()),
                ),
                FrameButton(
                  key: const ValueKey('ofis-open'),
                  icon: Icons.folder_open_rounded,
                  label: 'Aç',
                  tooltip: 'Belge aç · Ctrl+O',
                  onPressed: () => unawaited(_open()),
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
  });

  final List<EvrakFile> recent;
  final VoidCallback onOpen;
  final ValueChanged<EvrakFormat> onNew;
  final ValueChanged<String> onOpenFile;

  @override
  State<OfisHome> createState() => _OfisHomeState();
}

class _OfisHomeState extends State<OfisHome> {
  bool _dragging = false;

  static String _when(DateTime t) {
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(t.year, t.month, t.day)).inDays;
    final clock =
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    if (days <= 0) return 'Bugün $clock';
    if (days == 1) return 'Dün $clock';
    if (days < 7) return '$days gün önce';
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
            const Text(
              'Belgeleriniz',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _action(
                  key: const ValueKey('ofis-home-open'),
                  icon: Icons.folder_open_rounded,
                  title: 'Belge aç',
                  detail: 'UDF, Word, ODT, PDF, RTF, Excel',
                  onTap: widget.onOpen,
                  primary: true,
                ),
                _action(
                  key: const ValueKey('ofis-home-new-udf'),
                  icon: Icons.note_add_outlined,
                  title: 'Yeni UDF belge',
                  detail: 'UYAP’ın biçiminde',
                  onTap: () => widget.onNew(EvrakFormat.udf),
                ),
                _action(
                  key: const ValueKey('ofis-home-new-docx'),
                  icon: Icons.description_outlined,
                  title: 'Yeni Word belgesi',
                  detail: 'DOCX olarak',
                  onTap: () => widget.onNew(EvrakFormat.docx),
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
                      'Belgeyi buraya sürükleyin',
                      style: TextStyle(color: AgendaColors.muted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'SON BELGELER',
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
                  'Açtığınız belgeler burada görünür.',
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
                  f.format.defaultExtension.toUpperCase(),
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
                      p.basenameWithoutExtension(f.path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      modified == null ? f.format.label : _when(modified),
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

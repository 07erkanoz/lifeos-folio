import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'models/evrak_file.dart';
import 'services/portal/portal_sync.dart';
import 'services/desktop/native_window.dart';
import 'services/editor/document_history.dart';
import 'services/editor/editor_drafts.dart';
import 'services/library/recent_documents.dart';
import 'services/platform/document_launch.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/theme_controller.dart';
import 'ui/widgets/desktop_frame.dart';
import 'ui/widgets/document_history_dialog.dart';
import 'ui/widgets/editor_file_menu.dart';
import 'ui/widgets/editor_widget.dart';
import 'ui/widgets/folio_about_dialog.dart';
import 'ui/widgets/notice.dart';

export 'services/platform/editor_window.dart' show editorFlag;

/// LifeOS Editör: the editor on its own, in a window of its own.
///
/// It opens a blank UDF, or the document it was given, and nothing else:
/// no archive, no index, no tray, no single-instance lock. Each launch is a
/// window of its own, beside Folio or without it. Inside Folio the editor
/// stays where it has always been.
Future<void> runEditorApp(List<String> arguments) async {
  final launch = DocumentLaunch.parse(arguments);
  // Only what the text editor opens: a workbook or a picture is Folio's.
  final path = launch.paths
      .where(FileSystemEntity.isFileSync)
      .where(
        (path) => opensInEditor(EvrakFormat.fromExtension(p.extension(path))),
      )
      .firstOrNull;
  var chrome = false;
  WindowOptions? options;
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    try {
      await windowManager.ensureInitialized();
      chrome = Platform.isLinux || Platform.isWindows;
      options = WindowOptions(
        titleBarStyle: chrome ? TitleBarStyle.hidden : TitleBarStyle.normal,
        windowButtonVisibility: !chrome,
        size: const Size(1150, 820),
        minimumSize: const Size(720, 520),
        center: true,
        title: editorTitle(path),
      );
      await windowManager.setPreventClose(true);
    } catch (_) {
      chrome = false;
      options = null;
    }
  }
  // The portals' sessions kept from before: UYAP Mobil ties a petition to
  // its case here too.
  PortalSync.begin();
  runApp(EditorApp(path: path, desktopChrome: chrome));
  if (options != null) {
    await windowManager.waitUntilReadyToShow(options, () async {
      // A document is written across the whole screen: the editor always
      // opens maximized, its size above only what un-maximizing returns to.
      if (Platform.isWindows) {
        await showMaximized();
      } else {
        await windowManager.maximize();
        await windowManager.show();
      }
      await windowManager.focus();
    });
  }
}

/// Whether the standalone editor opens [format]: the formats Folio edits in
/// its text editor.
bool opensInEditor(EvrakFormat format) =>
    format.canEdit &&
    !format.usesPlainTextEditor &&
    format != EvrakFormat.spreadsheet;

/// "dilekce.udf — LifeOS Editör", or the program alone for a new document:
/// the window's title, which the task bar and Alt+Tab show.
String editorTitle(String? path) =>
    path == null ? 'LifeOS Editör' : '${p.basename(path)} — LifeOS Editör';

/// The document alone, for the title bar, where the icon names the program.
String editorDocumentName(String? path) =>
    path == null ? 'Yeni belge.udf' : p.basename(path);

class EditorApp extends StatefulWidget {
  const EditorApp({
    super.key,
    this.path,
    this.desktopChrome = false,
    this.appearance,
  });

  /// The document to open; null for a blank UDF.
  final String? path;
  final bool desktopChrome;
  final ThemeController? appearance;

  @override
  State<EditorApp> createState() => _EditorAppState();
}

class _EditorAppState extends State<EditorApp> with WindowListener {
  final _navigator = GlobalKey<NavigatorState>();
  final _drafts = EditorDrafts();

  /// The same list Folio keeps, so a document opened in either program is
  /// one click away in the other.
  final _recent = RecentDocuments();
  late final ThemeController _appearance;
  late EditorDraft _draft;
  late String _title = editorTitle(widget.path);
  late String _documentName = editorDocumentName(widget.path);

  /// The document the editor was opened on; changed only by Yeni and Aç,
  /// never by saving, which would reload the editor.
  late String? _opened = widget.path;

  /// A draft being recovered into this window, with [_opened] as its source
  /// when that file is still there.
  DocumentRevision? _recovery;

  /// Counts the documents this window has held, so each gets an editor and
  /// a draft of its own.
  int _generation = 0;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _appearance = widget.appearance ?? ThemeController();
    unawaited(_appearance.load());
    _draft = _draftFor(widget.path);
    if (widget.desktopChrome) windowManager.addListener(this);
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
    if (widget.appearance == null) _appearance.dispose();
    super.dispose();
  }

  /// Closing asks about unsaved work first, as Folio does.
  @override
  void onWindowClose() => unawaited(_close());

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      final context = _navigator.currentState?.overlay?.context;
      if (context == null || !context.mounted) return;
      if (!await _drafts.confirm(context)) return;
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } finally {
      _closing = false;
    }
  }

  EditorDraft _draftFor(String? path) => _drafts.draft(
    'editor-$_generation',
    path == null ? 'Yeni belge.udf' : p.basename(path),
  );

  /// The formats [opensInEditor] takes, for the file picker.
  static const _openable = ['udf', 'docx', 'doc', 'rtf', 'odt', 'txt', 'pdf'];

  /// Ctrl+O: another document in this window, after asking about unsaved
  /// work in the one open now.
  Future<void> _open() async {
    final context = _navigator.currentState?.overlay?.context;
    if (context == null) return;
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Belge aç',
      type: FileType.custom,
      allowedExtensions: _openable,
    );
    final path = picked?.files.single.path;
    if (path == null || !context.mounted) return;
    await _switchTo(context, path);
  }

  /// Ctrl+N: a blank UDF in this window.
  Future<void> _new() async {
    final context = _navigator.currentState?.overlay?.context;
    if (context == null) return;
    await _switchTo(context, null);
  }

  Future<void> _switchTo(
    BuildContext context,
    String? path, {
    DocumentRevision? recovery,
  }) async {
    if (!await _drafts.confirm(context, only: _draft)) return;
    if (!mounted) return;
    final title = recovery != null && path == null
        ? editorTitle(recovery.name)
        : editorTitle(path);
    setState(() {
      _generation++;
      _opened = path;
      _recovery = recovery;
      _draft = _draftFor(path ?? recovery?.name);
      _title = title;
      _documentName = editorDocumentName(path ?? recovery?.name);
    });
    if (widget.desktopChrome) unawaited(windowManager.setTitle(title));
    if (path != null) {
      await _recent.remember([EvrakFile.fromPath(path)]);
      if (mounted) setState(() {});
    }
  }

  /// A document from Son açılanlar. One moved or deleted since leaves the
  /// list, rather than failing to open every time it is picked.
  Future<void> _openRecent(EvrakFile file) async {
    final context = _navigator.currentState?.overlay?.context;
    if (context == null) return;
    if (!await File(file.path).exists()) {
      await _recent.remove(file.path);
      if (!context.mounted) return;
      setState(() {});
      showNotice(context, 'Belge taşınmış veya kaldırılmış', detail: file.path);
      return;
    }
    if (!context.mounted) return;
    if (!opensInEditor(file.format)) {
      showNotice(context, 'Bu belge Folio’da açılır', detail: file.name);
      return;
    }
    await _switchTo(context, file.path);
  }

  /// Unsaved work left by an editor that closed without a decision. Only a
  /// rich-text draft opens here; a text or table draft is Folio's.
  Future<void> _openRecovery() async {
    final context = _navigator.currentState?.overlay?.context;
    if (context == null) return;
    final entry = await showRecoverableDrafts(context);
    if (entry == null || !context.mounted) return;
    if (entry.format != 'rich-draft') {
      showNotice(context, 'Bu taslak Folio’da açılır', detail: entry.name);
      return;
    }
    final source = entry.sourcePath;
    final exists = source != null && await File(source).exists();
    if (!context.mounted) return;
    await _switchTo(context, exists ? source : null, recovery: entry);
  }

  void _saved(String path) {
    unawaited(
      _recent.remember([EvrakFile.fromPath(path)]).then((_) {
        if (mounted) setState(() {});
      }),
    );
    // A PDF is an export beside the document, not the document itself: the
    // window keeps the name of what is being edited.
    if (p.extension(path).toLowerCase() == '.pdf') return;
    final title = editorTitle(path);
    setState(() {
      _title = title;
      _documentName = editorDocumentName(path);
    });
    if (widget.desktopChrome) unawaited(windowManager.setTitle(title));
  }

  void _signed(String path) {
    final context = _navigator.currentState?.overlay?.context;
    if (context == null || !context.mounted) return;
    showNotice(
      context,
      'Belge imzalandı.',
      detail: path,
      kind: NoticeKind.success,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _appearance,
    builder: (context, _) => MaterialApp(
      navigatorKey: _navigator,
      title: _title,
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
              title: _documentName,
              titleIcon: Icons.description_outlined,
              titleTrailing: _EditedDot(_draft.edited),
              icon: 'assets/branding/lifeos_editor.png',
              iconTooltip: 'LifeOS Editör hakkında',
              leading: [
                _FrameButton(
                  key: const ValueKey('editor-new'),
                  icon: Icons.note_add_rounded,
                  label: 'Yeni',
                  tooltip: 'Yeni boş UDF · Ctrl+N',
                  onPressed: _new,
                ),
                _FrameButton(
                  key: const ValueKey('editor-open'),
                  icon: Icons.folder_open_rounded,
                  label: 'Aç',
                  tooltip: 'Belge aç · Ctrl+O',
                  onPressed: _open,
                ),
              ],
              onAbout: () {
                final context = _navigator.currentState?.overlay?.context;
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
          ): _open,
          SingleActivator(
            LogicalKeyboardKey.keyN,
            control: !Platform.isMacOS,
            meta: Platform.isMacOS,
          ): _new,
        },
        child: Scaffold(
          body: EditorWidget(
            // A fresh editor for each document: its own draft, history and
            // unsaved-changes state.
            key: ValueKey('standalone-editor-$_generation'),
            draft: _draft,
            initialFilePath: _opened,
            initialFormat: _opened == null
                ? (_recovery == null ? EvrakFormat.udf : null)
                : EvrakFormat.fromExtension(p.extension(_opened!)),
            recovery: _recovery,
            fileHost: EditorFileHost(
              onNew: _new,
              onOpen: _open,
              recent: () => _recent.files,
              onOpenRecent: (file) => unawaited(_openRecent(file)),
              onRecovery: () => unawaited(_openRecovery()),
            ),
            onSaved: _saved,
            onSigned: _signed,
          ),
        ),
      ),
    ),
  );
}

/// An icon in the title bar, beside the editor's own: tinted with the
/// theme's colour, filled softly under the pointer, named by its tooltip.
class _FrameButton extends StatelessWidget {
  const _FrameButton({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String label, tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 19, semanticLabel: label),
        style: IconButton.styleFrom(
          fixedSize: const Size(32, 30),
          minimumSize: const Size(32, 30),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: colors.primary,
          hoverColor: colors.primary.withValues(alpha: .12),
          highlightColor: colors.primary.withValues(alpha: .2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

/// The dot after the document's name while it has unsaved edits.
class _EditedDot extends StatelessWidget {
  const _EditedDot(this.edited);

  final ValueListenable<bool> edited;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: edited,
    builder: (context, edited, _) => edited
        ? const Tooltip(
            key: ValueKey('editor-unsaved'),
            message: 'Kaydedilmemiş değişiklikler var',
            child: Padding(
              padding: EdgeInsets.only(left: 7),
              child: SizedBox.square(
                dimension: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFE8912D),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          )
        : const SizedBox.shrink(),
  );
}

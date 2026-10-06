import 'agenda/agenda_page.dart';
import 'agenda/channel_bar.dart';
import 'agenda/mobile_connect.dart';
import 'agenda/uets_connect.dart';
import 'agenda/uets_page.dart';
import '../services/portal/case_import.dart';
import '../services/portal/observed.dart' show caseKey;
import '../services/portal/portal_case.dart';
import '../services/portal/portal_database.dart';
import '../services/portal/portal_sync.dart';

import 'dart:io';
import 'dart:async';

import '../services/platform/editor_window.dart';
import '../services/uyap/uyap_case_links.dart';
import '../services/uyap/uyap_case_store.dart';
import '../services/uyap/uyap_library.dart';
import '../services/speech/speech_session.dart';
import '../services/platform/document_intents.dart';
import '../services/platform/document_launch.dart';
import '../services/platform/platform_capabilities.dart';
import '../services/editor/editor_drafts.dart';
import '../services/editor/text_anchor.dart';
import '../services/editor/document_history.dart';
import 'widgets/document_history_dialog.dart';
import 'widgets/document_versions_window.dart';
import 'widgets/draft_prompts.dart' show draftDate;
import 'widgets/notice.dart';
import 'widgets/print_screen.dart';
import 'widgets/new_document_dialog.dart';
import 'widgets/speech_actions.dart';
import 'widgets/speech_bar.dart';
import 'widgets/document_actions_dialog.dart';
import 'widgets/spreadsheet_editor.dart';
import 'widgets/spreadsheet_viewer.dart';
import 'widgets/hover_document_preview.dart';
import 'desktop/desktop_home.dart';
import 'widgets/editor_ribbon.dart';
import 'widgets/desktop_frame.dart' show windowFullScreen;
import 'library/search_controls.dart';
import 'library/collapsing_overview.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../services/platform/file_actions.dart';
import 'widgets/share_document_dialog.dart';
import 'widgets/shortcuts_dialog.dart';

import '../models/evrak_file.dart';
import '../services/library/file_library.dart';
import '../services/library/recent_documents.dart';
import '../services/update/update_check.dart';
import '../services/platform/document_scan.dart';
import 'mobile/document_home.dart';
import 'mobile/mobile_drawer.dart';
import 'mobile/mobile_gallery.dart';
import 'mobile/photo_editor.dart';
import 'mobile/photo_viewer.dart';
import 'mobile/mobile_settings_page.dart';
import 'mobile/scroll_chrome.dart';
import 'widgets/uyap_connect_view.dart';
import 'mobile/profile_from_uyap.dart';
import '../services/editor/lawyer_profile.dart';
import '../services/uyap/uyap_mobile_api.dart';
import '../services/search/library_controller.dart';
import '../services/convert/converter_service.dart';
import '../services/pdf/pdf_service.dart';
import '../services/tiff/tiff_service.dart';
import 'library/index_status_dialog.dart';
import 'library/library_sidebar.dart';
import 'library/library_settings_dialog.dart';
import 'library/gallery_view.dart';
import 'library/search_results.dart';
import 'theme/theme_controller.dart';
import 'widgets/convert_dialog.dart';
import 'widgets/transition_pane.dart';
import 'widgets/plain_text_editor.dart';
import 'widgets/signing_dialog.dart';
import 'widgets/data_preview_widget.dart';
import 'widgets/document_preview_widget.dart';
import 'widgets/drop_zone.dart';
import 'widgets/editor_file_menu.dart';
import 'widgets/editor_widget.dart';
import 'widgets/uyap_cases_page.dart';
import 'widgets/uyap_operations_dialog.dart';
import 'widgets/image_viewer_widget.dart';
import 'widgets/optimize_dialog.dart';
import 'widgets/pdf_viewer_widget.dart';
import 'widgets/tiff_viewer_widget.dart';
import 'widgets/folio_select.dart';

class HomePage extends StatefulWidget {
  final List<String> initialPaths;
  final bool initialEdit;
  final Stream<List<String>>? desktopLaunches;
  final LibraryController? library;
  final ThemeController appearance;
  final EditorDrafts? drafts;
  final VoidCallback? onEscape;
  const HomePage({
    super.key,
    this.initialPaths = const [],
    this.initialEdit = false,
    this.desktopLaunches,
    this.library,
    required this.appearance,
    this.drafts,
    this.onEscape,
  });
  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final List<EvrakFile> _files = [];
  final _recentDocuments = RecentDocuments();
  bool _mobileArchive = false;
  Future<void> _rememberFiles(List<String> paths) async {
    final files = _files.where((file) => paths.contains(file.path)).toList();
    await _recentDocuments.remember(files);
    if (mounted) setState(() {});
  }

  /// The editor's Dosya menu. A document picked there opens in the editor
  /// too, except a PDF, which is read first: editing one converts it.
  EditorFileHost get _editorFileHost => EditorFileHost(
    onNew: () => unawaited(_newDocument()),
    onOpen: () => unawaited(_openFromEditor()),
    recent: () => _recentDocuments.files,
    onOpenRecent: (file) => unawaited(_openRecent(file, edit: _editsAt(file))),
    onRecovery: () => unawaited(_openRecovery()),
  );

  static bool _editsAt(EvrakFile file) =>
      file.format.canEdit && file.format != EvrakFormat.pdf;

  Future<void> _openFromEditor() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Belge aç',
      type: FileType.custom,
      allowedExtensions: EvrakFormat.supportedExtensions,
    );
    final path = result?.files.single.path;
    if (!mounted || path == null) return;
    await _addFiles([path], edit: _editsAt(EvrakFile.fromPath(path)));
  }

  Future<void> _openRecent(EvrakFile file, {bool edit = false}) async {
    if (!await File(file.path).exists()) {
      await _recentDocuments.remove(file.path);
      if (mounted) {
        setState(() {});
        showNotice(
          context,
          'Belge taşınmış veya kaldırılmış',
          detail: 'Dosyadan yeniden açabilirsiniz.',
        );
      }
      return;
    }
    await _addFiles([file.path], index: false, external: true, edit: edit);
  }

  /// Camera to PDF: the saved scan opens at once, and joins Son açılanlar.
  Future<void> _scanToPdf() async {
    try {
      final path = await DocumentScan.toPdf();
      if (path == null || !mounted) return;
      await _addFiles([path], index: false, external: true);
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Tarama yapılamadı',
          detail: e.toString().replaceFirst('Bad state: ', ''),
          kind: NoticeKind.error,
        );
      }
    }
  }

  /// A newer Folio has been published: say so across the top, where it
  /// stays until the reader chooses. Nothing is downloaded until asked.
  void _updateAvailable() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentMaterialBanner();
    final update = UpdateCheck.instance.available.value;
    if (update == null) return;
    final notes = update.notes['tr'] ?? update.notes['en'] ?? '';
    messenger.showMaterialBanner(
      MaterialBanner(
        key: const ValueKey('update-banner'),
        leading: const Icon(Icons.system_update_alt_rounded),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'LifeOS Folio ${update.version} hazır',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (notes.isNotEmpty)
              Text(notes, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => unawaited(UpdateCheck.instance.skip(update)),
            child: const Text('Bu sürümü atla'),
          ),
          TextButton(
            onPressed: UpdateCheck.instance.later,
            child: const Text('Sonra'),
          ),
          FilledButton.icon(
            onPressed: () {
              unawaited(
                launchUrl(update.url, mode: LaunchMode.externalApplication),
              );
              UpdateCheck.instance.later();
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('İndir'),
          ),
        ],
      ),
    );
  }

  void _openMobileArchive() => setState(() {
    _showLibrary = true;
    _mobileArchive = true;
  });
  Widget _mobileHome() => MobileDocumentHome(
    recent: _recentDocuments.files,
    onOpen: _pickFiles,
    onNew: _newDocument,
    onArchive: _openMobileArchive,
    onGallery: () => _selectGroup('images'),
    onScan: DocumentScan.available ? () => unawaited(_scanToPdf()) : null,
    onRecovery: _openRecovery,
    recoveryCount: _recoveryCount,
    onRecent: _openRecent,
    onShare: (file) => _previewAction('share', file),
    agendaToday: _agendaToday,
    deadlinesToday: _deadlinesToday,
    next: _nextHearing,
    uetsUnread: _uetsUnread,
    uyapCases: _uyapCases.length,
    uyapFresh: _uyapCases.fold(0, (sum, c) => sum + c.$1.fresh.length),
    name: _lawyerName,
    channels: PortalSync.started == null
        ? null
        : const PortalChannelBar(phone: true),
    onAgenda: () => unawaited(_selectGroup('agenda')),
    onUets: () => unawaited(_selectGroup('uets')),
    onUyap: () => unawaited(_selectGroup('uyap')),
  );
  final _intents = DocumentIntents();
  StreamSubscription<List<String>>? _incoming;
  StreamSubscription<List<String>>? _desktopIncoming;
  StreamSubscription<void>? _folderChanges;
  Timer? _mobileRefresh;
  Timer? _folderDebounce;
  final _openedEditors = <String>{};
  late final EditorDrafts _drafts = widget.drafts ?? EditorDrafts();
  int _newDocumentVersion = 0;
  EvrakFormat _newFormat = EvrakFormat.udf;

  /// The UYAP case the new document is written for, when begun from its page.
  UyapCaseLink? _newCase;
  bool _choosingNewDocument = false;
  String get _newTitle =>
      _newRecovery?.name ?? 'Yeni belge.${_newFormat.defaultExtension}';
  DocumentRevision? _newRecovery;
  String? _recoverySource;
  int _recoveryCount = 0;

  /// Counts the drafts waiting to be recovered, for the badge on the restore
  /// button. Only the badge: a notice for them at every start sat along the
  /// bottom of the window and, carrying a button, never went away.
  Future<void> _checkRecovery() async {
    try {
      final entries = await DocumentHistory.instance.recoveries();
      if (mounted) setState(() => _recoveryCount = entries.length);
    } catch (_) {
      /* Opening documents must work even if local history is unavailable. */
    }
  }

  Future<void> _openRecovery() async {
    final entry = await showRecoverableDrafts(context);
    if (!mounted) return;
    if (entry == null) {
      await _checkRecovery();
      return;
    }
    if (!await _leaveEditor()) return;
    final path = entry.sourcePath;
    final exists = path != null && await File(path).exists();
    if (!mounted) return;
    setState(() {
      // An editor still holding the file's saved text would write it back
      // over the recovered draft on its next save.
      if (exists) {
        final open = _files.where((f) => f.path == path).firstOrNull;
        if (open == null || !_fileDraft(open).hasChanges) {
          _openedEditors.remove(path);
          if (_selectedFile?.path == path) _isEditorMode = false;
        }
      }
      _newDocumentVersion++;
      _newRecovery = entry;
      _recoverySource = exists ? path : null;
      _editorPanelsVisible = false;
      _newEditorOpened = true;
      _isNewDocument = true;
      _showLibrary = false;
    });
  }

  final _viewerRevision = <String, int>{};

  /// The page each document was left on, for as long as the app is open.
  ///
  /// Going into the editor and back keeps the place by itself, since the
  /// preview stays in the tree. Reading another document does not: its
  /// viewer is the one being shown, and the first came back at page one.
  final _readingPage = <String, int>{};
  EditorDraft _fileDraft(EvrakFile file) => _drafts.draft(file.path, file.name);

  /// Where [file] is now: the name it was saved under from the editor, which
  /// "Farklı kaydet" moves the editor on to, or where it was opened from.
  String _shownPath(EvrakFile file) {
    if (!_isEditorMode) return file.path;
    final saved = _fileDraft(file).savedPath?.call();
    return saved == null || saved.isEmpty ? file.path : saved;
  }

  EditorDraft get _newDraft =>
      _drafts.draft('new-$_newDocumentVersion', _newTitle);
  EditorDraft? get _activeDraft => _showLibrary
      ? null
      : _isNewDocument
      ? _newDraft
      : _isEditorMode && _selectedFile != null
      ? _fileDraft(_selectedFile!)
      : null;
  Future<bool> _leaveEditor() async {
    final draft = _activeDraft;
    return (draft == null || await _drafts.confirm(context, only: draft)) &&
        mounted;
  }

  Future<void> _goLibrary() async {
    if (!await _leaveEditor()) return;
    _stopPreviewSpeech();
    _setFullScreen(false);
    setState(() {
      _showLibrary = true;
      _mobileArchive = false;
    });
    unawaited(_checkRecovery());
  }

  /// A normal tray activation changes the visible screen only. Editors stay
  /// mounted with their drafts; native close still uses the shared save guard.
  void showHomeFromTray() {
    if (!mounted) return;
    HoverDocumentPreview.dismissActive();
    _searchController.clear();
    // Coming back to the homepage has to clear the workspace as well.
    // `_showLibrary` only governs the side panel: the document area keeps
    // drawing whatever is selected, so the file that was being read reappeared
    // beside the archive every time the window came back from the tray.
    //
    // Unsaved work is the exception. Dropping the selection unmounts the
    // editor, and an unmounted editor detaches its draft callbacks, so the
    // pending changes would go without anything being asked.
    // Not `_activeDraft`: that reports nothing while the side panel is open,
    // and an editor can be on screen beside it.
    final open = _isNewDocument
        ? _newDraft
        : _isEditorMode && _selectedFile != null
        ? _fileDraft(_selectedFile!)
        : null;
    final unsaved = open?.hasChanges ?? false;
    setState(() {
      _showLibrary = true;
      _mobileArchive = false;
      _group = 'all';
      if (!unsaved) {
        _selectedIndex = -1;
        _isEditorMode = false;
        _isNewDocument = false;
        _previewExpanded = false;
      }
    });
    _library.setQuery('');
    _library.filter(clearFolder: true, types: const [], ordering: 'relevance');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showLibrary) _searchFocus.requestFocus();
    });
  }

  void _saved(String path) {
    if (!mounted) return;
    if (File(path).existsSync()) {
      unawaited(_recentDocuments.remember([EvrakFile.fromPath(path)]));
    }
    setState(() {
      _viewerRevision[path] = (_viewerRevision[path] ?? 0) + 1;
      if (_isNewDocument) _openedEditors.remove(path);
      final index = _files.indexWhere((file) => file.path == path);
      if (index >= 0 && File(path).existsSync()) {
        _files[index] = EvrakFile.fromPath(path);
      }
    });
  }

  Future<void> _signed(String path) async {
    if (!mounted) return;
    _saved(path);
    setState(() {
      _openedEditors.remove(path);
      _isEditorMode = false;
    });
    await _addFiles([path], index: false);
    await _library.updatePaths([path]);
  }

  /// Where each document's preview was double-clicked, for its editor to
  /// open at. Set only on the way into the editor, cleared on any other.
  final _revealAt = <String, TextAnchor>{};

  /// A double-click on the page of a text document opens it for editing
  /// there. Not for a PDF, whose editing is a conversion of its own that is
  /// asked about first, and not on a phone, where two taps zoom.
  bool _editsOnDoubleClick(EvrakFile file) =>
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
      file.format.canEdit &&
      file.format != EvrakFormat.pdf;

  Future<void> _editAt(EvrakFile file, TextAnchor anchor) async {
    if (_isEditorMode || !mounted) return;
    if (_fullScreen) _setFullScreen(false);
    await _toggleEditor(file, at: anchor);
  }

  Future<void> _toggleEditor(EvrakFile file, {TextAnchor? at}) async {
    _stopPreviewSpeech();
    if (!_isEditorMode &&
        file.format == EvrakFormat.pdf &&
        !_openedEditors.contains(file.path)) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('PDF metnini düzenle'),
          content: const Text(
            'PDF\'nin mevcut metin katmanı doğrudan düzenleyiciye aktarılacak; '
            'normal metin PDF\'lerinde OCR çalıştırılmaz. Sayfa '
            'yerleşimi, imzalar, formlar ve ek açıklamalar birebir '
            'taşınmayabilir; kaynak PDF değiştirilmez. Sonucu yeni bir '
            'UDF, DOCX, RTF veya PDF dosyası olarak kaydedebilirsiniz.\n\n'
            'Metin katmanı olmayan PDF\'lerde (taranmış ya da yazıları '
            'yazdırılırken şekle dönüştürülmüş) sayfalar OCR ile okunur; bu '
            'sayfa başına birkaç saniye sürer ve sonucu kontrol etmek gerekir.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Metni düzenlemeye aktar'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    if (_isEditorMode) {
      final draft = _fileDraft(file);
      if (!await _leaveEditor()) return;
      final path = draft.savedPath?.call();
      if (path != null && path != file.path && File(path).existsSync()) {
        await _addFiles([path]);
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _isEditorMode = !_isEditorMode;
      if (_isEditorMode) {
        _editorPanelsVisible = false;
        _openedEditors.add(file.path);
        if (at == null) {
          _revealAt.remove(file.path);
        } else {
          _revealAt[file.path] = at;
        }
      }
    });
  }

  void _showShortcuts() {
    if (mounted) unawaited(ShortcutsDialog.show(context));
  }

  Future<void> escapeBack() => _back(allowExit: false);

  Future<void> _back({bool allowExit = true}) async {
    if (_fullScreen) {
      _setFullScreen(false);
      return;
    }
    if (!_showLibrary &&
        _isEditorMode &&
        !_isNewDocument &&
        _selectedFile != null) {
      await _toggleEditor(_selectedFile!);
    } else if (!_showLibrary && _isNewDocument) {
      if (!await _leaveEditor()) return;
      final saved = _newDraft.savedPath?.call();
      if (saved != null && await File(saved).exists()) {
        if (mounted) await _addFiles([saved]);
      } else {
        await _goLibrary();
      }
    } else if (!_showLibrary) {
      await _goLibrary();
    } else if (_library.query.isNotEmpty) {
      _searchController.clear();
      _library.setQuery('');
    } else if (_library.sourceId != null ||
        _library.extensions.isNotEmpty ||
        _group != 'all') {
      await _selectGroup('all');
    } else if (_mobileArchive) {
      setState(() => _mobileArchive = false);
    } else if (allowExit &&
        Platform.isAndroid &&
        await _drafts.confirm(context) &&
        mounted) {
      await SystemNavigator.pop();
    }
  }

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _resultsFocus = FocusNode(debugLabel: 'Belge listesi');
  final _libraryResultsFocus = FocusNode(debugLabel: 'Arşiv listesi');
  late final LibraryController _library;
  int _selectedIndex = -1;
  bool _isEditorMode = false;
  bool _editorPanelsVisible = false;
  bool _showLibrary = true;
  bool _previewExpanded = false;

  /// Text providers owned by the open PDFium viewers. This is the same text
  /// selection/copy exposes, not the flattened archive index or OCR output.
  final _pdfTextLoaders = <String, PdfTextLoader>{};

  Future<String?> _loadViewerPdfText(String path) async {
    // The viewer and editor are switched in the same frame. Give PDFium a
    // short chance to publish its loader before falling back to the worker
    // extractor; no parsing or polling runs on the UI isolate.
    for (var attempt = 0; attempt < 30; attempt++) {
      final loader = _pdfTextLoaders[path];
      if (loader != null) return loader();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }

  void _windowFullScreen() {
    if (mounted) setState(() {});
  }

  /// Reading a document with nothing else on screen. On a phone the header and
  /// the action row take a sixth of the display before the document starts,
  /// and a viewer that cannot get out of the way is not a viewer.
  bool _fullScreen = false;

  void _setFullScreen(bool value) {
    if (_fullScreen == value) return;
    setState(() => _fullScreen = value);
    SystemChrome.setEnabledSystemUIMode(
      value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  final bool _includeSubfolders = true;
  bool _newEditorOpened = false;
  bool _isNewDocument = false;

  /// The desktop opens on its first page; a phone has a first page of its
  /// own, and tests start in the archive.
  String _group =
      Platform.isAndroid ||
          Platform.isIOS ||
          Platform.environment.containsKey('FLUTTER_TEST')
      ? 'all'
      : 'home';

  /// The UYAP cases kept on this computer, listed under UYAP in the sidebar.
  List<(UyapCaseRecord, int)> _uyapCases = const [];
  int _uyapTotal = -1;

  /// Looks again when a case changed in this window, or the archive grew:
  /// documents saved from an editor window of its own come in that way.
  void _reloadUyapCases() {
    // Tests do not list the lawyer's real cases; one with a store of its
    // own does.
    if (Platform.environment.containsKey('FLUTTER_TEST') &&
        UyapCaseStore.isReal) {
      return;
    }
    unawaited(
      UyapCaseStore.instance.cases().then((cases) {
        if (mounted) setState(() => _uyapCases = cases);
      }, onError: (Object _) {}),
    );
  }

  void _archiveChanged() {
    if (_library.total == _uyapTotal) return;
    _uyapTotal = _library.total;
    _reloadUyapCases();
  }

  EvrakFile? get _selectedFile =>
      _selectedIndex >= 0 && _selectedIndex < _files.length
      ? _files[_selectedIndex]
      : null;

  @override
  void initState() {
    super.initState();
    UpdateCheck.instance.available.addListener(_updateAvailable);
    UpdateCheck.instance.start();
    _recentDocuments.load().then((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkRecovery();
    });
    DocumentHistory.recoveryChanges.addListener(_checkRecovery);
    _library = widget.library ?? LibraryController();
    _library.addListener(_changed);
    _library.addListener(_archiveChanged);
    UyapCaseStore.changes.addListener(_reloadUyapCases);
    _library.initialize();
    // UYAP documents saved from an editor window of its own, which keeps no
    // archive, are searched from the next start.
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      unawaited(searchUyapFolder(_library).catchError((Object _) => false));
      unawaited(_countAgenda());
      unawaited(_loadLawyerName());
      // Each UYAP channel syncs when it connects, the agenda open or not.
      PortalSync.instance.addListener(_portalSynced);
    }
    _incoming = _intents.paths.listen(
      (paths) {
        if (mounted) _addFiles(paths, index: false, external: true);
      },
      onError: (Object error) {
        if (mounted) {
          showNotice(context, error.toString(), kind: NoticeKind.error);
        }
      },
    );
    _intents.start();
    _desktopIncoming = widget.desktopLaunches?.listen((paths) {
      if (mounted) {
        final launch = DocumentLaunch.parse(paths);
        _addFiles(
          launch.paths,
          index: false,
          external: true,
          edit: launch.edit,
        );
      }
    });
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addObserver(this);
      windowFullScreen.addListener(_windowFullScreen);
      _startMobileWatch();
      _folderChanges = _intents.changes.listen((_) {
        _folderDebounce?.cancel();
        _folderDebounce = Timer(
          const Duration(milliseconds: 750),
          () => _library.refresh(),
        );
      });
    }
    if (widget.initialPaths.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _addFiles(
            widget.initialPaths,
            index: false,
            external: true,
            edit: widget.initialEdit,
          );
        }
      });
    }
  }

  void _startMobileWatch() {
    _mobileRefresh?.cancel();
    _mobileRefresh = Timer.periodic(
      // ContentObserver normally reports changes immediately and resuming the
      // app also reconciles once. This is only a fallback for providers that
      // do not emit notifications; walking and comparing a large SAF tree
      // every 30 seconds kept storage and CPU busy on an otherwise idle phone.
      const Duration(minutes: 5),
      (_) {
        if (_library.sources.any((source) => source.folder)) {
          _library.refresh();
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isAndroid) return;
    if (state == AppLifecycleState.resumed) {
      _library.refresh();
      _startMobileWatch();
    } else {
      _mobileRefresh?.cancel();
    }
  }

  void _changed() {
    if (_searchController.text != _library.query) {
      _searchController.text = _library.query;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _stopPreviewSpeech();
    UpdateCheck.instance.available.removeListener(_updateAvailable);
    DocumentHistory.recoveryChanges.removeListener(_checkRecovery);
    WidgetsBinding.instance.removeObserver(this);
    windowFullScreen.removeListener(_windowFullScreen);
    _mobileRefresh?.cancel();
    _folderDebounce?.cancel();
    _folderChanges?.cancel();
    _incoming?.cancel();
    _desktopIncoming?.cancel();
    _intents.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _resultsFocus.dispose();
    _libraryResultsFocus.dispose();
    _library.removeListener(_changed);
    PortalSync.instance.removeListener(_portalSynced);
    _library.removeListener(_archiveChanged);
    UyapCaseStore.changes.removeListener(_reloadUyapCases);
    if (widget.library == null) _library.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: EvrakFormat.supportedExtensions,
    );
    if (mounted && result != null) {
      _addFiles(result.paths.whereType<String>().toList());
    }
  }

  /// The settings: a page of their own on a phone (docs/design/mobil-
  /// ayarlar-taslak.png), the dialog on a computer.
  void _pickFolder() {
    if (MediaQuery.sizeOf(context).width < 700) {
      unawaited(
        MobileSettingsPage.open(
          context,
          library: _library,
          appearance: widget.appearance,
        ).then((_) => _loadLawyerName()),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => LibrarySettingsDialog(
        library: _library,
        appearance: widget.appearance,
      ),
    );
  }

  Future<void> _addFiles(
    List<String> paths, {
    bool index = true,
    bool external = false,
    bool edit = false,
  }) async {
    if (paths.isEmpty || !await _leaveEditor()) return;
    final folders = paths
        .where((path) => Directory(path).existsSync())
        .toList();
    final files = paths
        .where((path) => !folders.contains(path) && FileLibrary.supports(path))
        .toList();
    EvrakFile? pdfToEdit;
    if (files.isNotEmpty) {
      _searchFocus.unfocus();
      setState(() {
        for (final path in files) {
          if (!_files.any((f) => f.path == path)) {
            _files.add(EvrakFile.fromPath(path));
          }
        }
        _selectedIndex = _files.indexWhere((f) => f.path == files.first);
        if (external) _previewExpanded = true;
        final requestedEdit = edit && _selectedFile!.format.canEdit;
        // PDF import needs the same explicit fidelity warning whether it was
        // requested inside Folio or through the OS "Folio ile düzenle" verb.
        // Other formats can still open directly into their native editor.
        pdfToEdit = requestedEdit && _selectedFile!.format == EvrakFormat.pdf
            ? _selectedFile
            : null;
        _isEditorMode = requestedEdit && pdfToEdit == null;
        if (_isEditorMode) {
          _openedEditors.add(_selectedFile!.path);
          _editorPanelsVisible = false;
        }
        _isNewDocument = false;
        _showLibrary = false;
      });
    } else if (folders.isNotEmpty) {
      setState(() => _showLibrary = true);
    }
    if (files.isNotEmpty) unawaited(_rememberFiles(files));
    if (pdfToEdit != null && mounted) await _toggleEditor(pdfToEdit!);
    if (index && !(Platform.isAndroid && folders.isEmpty)) {
      _library.addPaths([...folders, ...files], recursive: _includeSubfolders);
    }
  }

  /// Moves to the document beside this one, for a swipe that ran off the end
  /// of the one on screen. The order is the order on the shelf, so a folder of
  /// photographs reads like one.
  Future<void> _stepFile(bool forward) async {
    if (_isEditorMode) return;
    _stopPreviewSpeech();
    final current = _selectedFile?.path;
    if (current == null) return;

    // The list on screen is what a swipe walks. Opening one photograph out of
    // a folder of six hundred and then being able to reach only the ones
    // already opened is not a gallery.
    final hits = _library.hits;
    final at = hits.indexWhere((hit) => hit.file.path == current);
    if (at >= 0) {
      final next = at + (forward ? 1 : -1);
      if (next < 0) return;
      if (next >= hits.length) {
        // The end of what has been loaded is not the end of the folder.
        if (_library.hits.length >= _library.matches) return;
        await _library.searchNow(more: true);
        if (!mounted || _library.hits.length <= next) return;
        await _selectFile(_library.hits[next].file);
        return;
      }
      await _selectFile(hits[next].file);
      return;
    }

    // Opened from somewhere else — the desktop, a share — so walk those.
    if (_files.length < 2 || _selectedIndex < 0) return;
    final next = _selectedIndex + (forward ? 1 : -1);
    if (next < 0 || next >= _files.length) return;
    await _selectFile(_files[next]);
  }

  Future<void> _selectFile(EvrakFile file) async {
    if (!await _leaveEditor()) return;
    if (file.path != _selectedFile?.path) _stopPreviewSpeech();
    _searchFocus.unfocus();
    _library.rememberQuery();
    setState(() {
      var index = _files.indexWhere((f) => f.path == file.path);
      if (index < 0) {
        _files.add(file);
        index = _files.length - 1;
      }
      _selectedIndex = index;
      _showLibrary = false;
      _isEditorMode = false;
      _isNewDocument = false;
    });
    // Unconditionally: asking whether the list held the keyboard first does
    // not work, because requestFocus does not take effect while the frame
    // that called it is still running, so the answer was always no. It is
    // safe to always offer, since the offer is declined if anything else
    // has the keyboard — a photograph opened from the gallery takes it for
    // itself, and that request comes after this one.
    _returnFocusToList();
  }

  /// Hands the keyboard back to the list beside the preview.
  ///
  /// It is a different list from the one that was just clicked — the wide
  /// archive gives way to a narrow column — and on the frame after the
  /// choice that column is not in the tree yet. The single attempt this
  /// replaces found no context, gave up quietly, and left the keyboard with
  /// nobody: arrow keys did nothing at all until the reader clicked the
  /// page. Tried again over the next few frames instead, and abandoned if
  /// something else has taken the keyboard in the meantime, which is not
  /// ours to take back.
  void _returnFocusToList([int left = 5]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _showLibrary) return;
      final holder = FocusManager.instance.primaryFocus;
      // The wide archive list counts as nobody here: it is our own node and
      // it is on its way out of the tree, which is precisely how the
      // keyboard ended up with nobody. Anything else that has taken it is
      // left alone.
      final ours = holder == _libraryResultsFocus || holder == _resultsFocus;
      if (holder != null && holder is! FocusScopeNode && !ours) return;
      if (_resultsFocus.context != null) {
        _resultsFocus.requestFocus();
        return;
      }
      if (left > 0) _returnFocusToList(left - 1);
    });
  }

  Future<void> _selectGroup(String value) async {
    if (!await _leaveEditor()) return;
    ScrollChrome.show();
    setState(() {
      _group = value;
      _mobileArchive = true;
      _showLibrary = true;
    });
    // Case law and the UYAP cases are not ways of looking at the archive
    // but places of their own, so the archive's filters are left as they
    // were: coming back finds the documents where they were left.
    if (value == 'caselaw' ||
        value == 'home' ||
        value == 'agenda' ||
        value == 'uets' ||
        _isUyapGroup(value)) {
      return;
    }
    final types = value == 'all'
        ? <String>[]
        : EvrakFormat.supportedExtensions
              .where(
                (ext) =>
                    EvrakFormat.fromExtension(ext).isVisual ==
                    (value == 'images'),
              )
              .toList();
    _library.filter(types: types, clearFolder: true);
  }

  /// The office's own pages, which bring their headings and fill the page.
  static bool _isFullPage(String group) =>
      group == 'home' || group == 'agenda' || group == 'uets';

  static bool _isUyapGroup(String group) =>
      group == 'uyap' || group.startsWith('uyap:');

  /// The hearings today, for the badge beside Ajanda in the sidebar.
  /// Where the headings were last folded; see [ScrollChrome].
  String? _chromePlace;

  int _agendaToday = 0;

  /// The UETS notices not yet read, for the badge beside UETS Tebligatlarım.
  int _uetsUnread = 0;

  /// The deadlines that end today, and the next hearing, for the phone's
  /// first page.
  int _deadlinesToday = 0;
  NextHearingLine? _nextHearing;

  /// The office as the desktop's first page shows it.
  DesktopHomeOffice _office = const DesktopHomeOffice();

  /// "Av. Erkan Öz": the profile's lawyer, else the UYAP Mobil user.
  String _lawyerName = '';

  void _portalSynced() {
    unawaited(_countAgenda());
    if (_lawyerName.isEmpty) unawaited(_loadLawyerName());
  }

  Future<void> _loadLawyerName() async {
    var name = '';
    try {
      name = (await LawyerProfile.load()).lawyer?.titled ?? '';
    } catch (_) {}
    if (name.isEmpty) {
      final user = UyapMobileApi.instance.session.value?.user ?? '';
      if (user.isNotEmpty && user != 'UYAP Mobil') {
        name = 'Av. ${titleCaseTr(user)}';
      }
    }
    if (mounted && name != _lawyerName) setState(() => _lawyerName = name);
  }

  static const _shortMonths = [
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', //
    'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
  ];

  Future<void> _countAgenda() async {
    try {
      final db = await PortalDatabase.shared();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final count = db.hearings(from: today, to: tomorrow).length;
      final unread = db.notices().where((n) => n.message.read == null).length;
      final deadlines = db
          .agenda(from: today, to: tomorrow)
          .where((i) => i.kind == 'deadline' && !i.done)
          .length;
      final next = db
          .hearings(from: now, to: today.add(const Duration(days: 31)))
          .firstOrNull;
      final notices = db.notices().where((n) => n.message.read == null).toList()
        ..sort(
          (a, b) => (b.message.sent ?? DateTime(0)).compareTo(
            a.message.sent ?? DateTime(0),
          ),
        );
      final office = DesktopHomeOffice(
        today: db.hearings(from: today, to: tomorrow),
        next: db
            .hearings(from: tomorrow, to: today.add(const Duration(days: 90)))
            .firstOrNull,
        deadlines: db
            .agenda(from: today, to: today.add(const Duration(days: 60)))
            .where((i) => i.kind == 'deadline' && !i.done && i.at != null)
            .toList(),
        unread: unread,
        newest: notices.firstOrNull?.message,
      );
      NextHearingLine? line;
      if (next != null) {
        String two(int v) => v.toString().padLeft(2, '0');
        final t = next.at;
        final day = DateTime(t.year, t.month, t.day);
        final clock = '${two(t.hour)}:${two(t.minute)}';
        final when = day == today
            ? clock
            : day == tomorrow
            ? 'Yarın $clock'
            : '${t.day} ${_shortMonths[t.month - 1]} $clock';
        final court = next.court.replaceFirst(
          RegExp(r'\s+Mahkemesi$', caseSensitive: false),
          '',
        );
        final left = t.difference(now);
        final relative = left.inHours < 24
            ? '${left.inHours == 0 ? left.inMinutes : left.inHours} '
                  '${left.inHours == 0 ? 'dk' : 'sa'} sonra'
            : '${left.inDays} gün sonra';
        line = NextHearingLine(
          '$when · $court · ${next.number}',
          [
            (next.kind?.value ?? '').trim().isEmpty
                ? (next.isEHearing ? 'E-duruşma' : 'Duruşma')
                : next.kind!.value.trim(),
            relative,
          ].join(' · '),
        );
      }
      if (mounted) {
        setState(() {
          _agendaToday = count;
          _uetsUnread = unread;
          _deadlinesToday = deadlines;
          _nextHearing = line;
          _office = office;
        });
      }
    } catch (_) {
      // The badge is a convenience; the agenda shows the same when opened.
    }
  }

  /// The UYAP Dosyalarım key of the case the agenda names by [caseKey], if
  /// the case is kept there.
  String? _uyapKeyFor(String key) {
    for (final (record, _) in _uyapCases) {
      if (caseKey(record.number, record.court) == key) return record.key;
    }
    return null;
  }

  /// A petition for the agenda's [kase]: UYAP Dosyalarım's own link when
  /// the case is kept there, else one made of its court and number.
  void _agendaPetition(PortalCase kase) {
    UyapCaseLink? link;
    for (final (record, _) in _uyapCases) {
      if (caseKey(record.number, record.court) == kase.key) link = record.link;
    }
    final court = kase.court;
    final kind = court.contains('Ceza')
        ? '0'
        : court.contains('İcra')
        ? '2'
        : court.contains('İdare') || court.contains('Vergi')
        ? '6'
        : '1';
    link ??= UyapCaseLink(
      jurisdiction: kind,
      courtType: '',
      courtId: '${kase.details?.value['birimId'] ?? ''}',
      court: court,
      number: kase.number,
    );
    unawaited(_newDocument(forCase: link));
  }

  /// The case of the agenda or of UETS, by [key], on its UYAP Dosyalarım
  /// page: added there first, through whichever portal is connected, when
  /// it is not there yet.
  bool _openPortalCase(String key) {
    final found = _uyapKeyFor(key);
    if (found != null) {
      setState(() => _group = 'uyap:$found');
    } else {
      unawaited(_importPortalCase(key));
    }
    return true;
  }

  Future<void> _importPortalCase(String key) async {
    final sync = PortalSync.instance;
    final kase = await sync.portalCase(key);
    if (!mounted) return;
    if (kase == null) {
      showNotice(context, 'Dosya portföyde bulunamadı');
      return;
    }
    if (!sync.web.connected && !sync.mobile.connected) {
      showNotice(
        context,
        'Dosya henüz UYAP Dosyalarım’da yok',
        detail: 'Eklemek için UYAP Web’e ya da UYAP Mobil’e bağlanın.',
      );
      return;
    }
    showNotice(
      context,
      'Dosya UYAP Dosyalarım’a ekleniyor',
      detail: '${kase.court} ${kase.number}',
    );
    try {
      final record = await PortalCaseImport().add(kase);
      if (!mounted) return;
      setState(() => _group = 'uyap:${record.key}');
      showNotice(
        context,
        'Dosya UYAP Dosyalarım’a eklendi',
        detail:
            '${record.court} ${record.number} · ${record.documents.length} evrak',
      );
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Dosya eklenemedi',
          detail: '$e'.replaceFirst('Bad state: ', ''),
          kind: NoticeKind.error,
        );
      }
    }
  }

  /// The desktop's first page (docs/design/masaustu-anasayfa-taslak.png).
  Widget _desktopHome() => DesktopHome(
    name: _lawyerName,
    recent: _recentDocuments.files,
    office: _office,
    uyapFolder: UyapSettings.instance.folder,
    onSearch: (text) async {
      await _selectGroup('all');
      if (!mounted) return;
      _searchController.text = text;
      _library.setQuery(text);
    },
    onOpen: (file) => unawaited(_openRecent(file)),
    onEdit: (file) => unawaited(_openRecent(file, edit: _editsAt(file))),
    onSendUyap: (file) async {
      await _openRecent(file, edit: true);
      if (!mounted) return;
      showNotice(
        context,
        'UYAP’a göndermek için belgeyi imzalayın',
        detail:
            'Editörde “UYAP’a gönder” belgeyi imzalatır ve dosyasına gönderir.',
      );
    },
    onArchive: () => unawaited(_selectGroup('all')),
    onDrafts: () => unawaited(_openRecovery()),
    onAgenda: () => unawaited(_selectGroup('agenda')),
    onUets: () => unawaited(_selectGroup('uets')),
  );

  Widget _agendaPage() => AgendaPage(
    onChanged: () => unawaited(_countAgenda()),
    onPetition: _agendaPetition,
    onOpenCase: _openPortalCase,
  );

  Widget _uetsPage() => UetsPage(
    onChanged: () => unawaited(_countAgenda()),
    onOpenCase: _openPortalCase,
    onOpenFile: (path) =>
        unawaited(_addFiles([path], index: false, external: true)),
  );

  Widget _uyapPage() => UyapCasesPage(
    caseKey: _group.startsWith('uyap:') ? _group.substring(5) : null,
    onShowCase: (key) =>
        setState(() => _group = key == null ? 'uyap' : 'uyap:$key'),
    onOpen: (file) =>
        unawaited(_addFiles([file.path], index: false, external: true)),
    onSaved: (_) =>
        unawaited(searchUyapFolder(_library).catchError((Object _) => false)),
    onNewPetition: (link) => unawaited(_newDocument(forCase: link)),
  );

  void _openConvertDialog({List<EvrakFile>? specificFiles}) {
    final files =
        specificFiles ?? (_selectedFile == null ? [] : [_selectedFile!]);
    if (files.isEmpty) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConvertDialog(files: List.of(files)),
    );
  }

  void _showStatus() => showDialog<void>(
    context: context,
    builder: (_) => IndexStatusDialog(library: _library),
  );

  /// [forCase]: a petition begun from a UYAP case's page, a UDF written for
  /// that case; no choice of format is asked for.
  Future<void> _newDocument({UyapCaseLink? forCase}) async {
    if (_choosingNewDocument) return;
    _choosingNewDocument = true;
    try {
      final format = forCase != null
          ? EvrakFormat.udf
          : await showDialog<EvrakFormat>(
              context: context,
              builder: (_) => const NewDocumentDialog(),
            );
      if (format == null || !mounted || !await _leaveEditor()) return;
      setState(() {
        _newCase = forCase;
        _newFormat = format;
        _newDocumentVersion++;
        _newRecovery = null;
        _recoverySource = null;
        _editorPanelsVisible = false;
        _newEditorOpened = true;
        _isNewDocument = true;
        _showLibrary = false;
      });
    } finally {
      _choosingNewDocument = false;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 1050;
      // A new page, a document opened or the editor entered: the headings
      // a scrolled list folded away are shown again.
      final place =
          '$_showLibrary|$_group|$_mobileArchive|${_selectedFile?.path}|$_isEditorMode';
      if (place != _chromePlace) {
        _chromePlace = place;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => ScrollChrome.show(),
        );
      }
      final mobile =
          constraints.maxWidth < 700 ||
          (constraints.maxHeight < 500 && constraints.maxWidth < 1000);
      final editing = !_showLibrary && (_isNewDocument || _isEditorMode);
      final scheme = Theme.of(context).colorScheme;
      final mobileHome = mobile && !_mobileArchive;
      return PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _back();
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(
              LogicalKeyboardKey.keyK,
              control: true,
            ): () async {
              if (!await _leaveEditor() || !context.mounted) return;
              if (mobile) {
                setState(() {
                  _mobileArchive = true;
                  _showLibrary = true;
                });
              }
              if (!_showLibrary &&
                  (editing ||
                      _previewExpanded ||
                      MediaQuery.sizeOf(context).width < 900)) {
                setState(() {
                  _showLibrary = true;
                  _previewExpanded = false;
                });
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _searchFocus.requestFocus();
              });
            },
            const SingleActivator(LogicalKeyboardKey.keyO, control: true):
                _pickFiles,
            const SingleActivator(LogicalKeyboardKey.keyN, control: true):
                _newDocument,
            // Escape only comes out of the editor. This goes both ways, which
            // is what reading and correcting a document in turn asks for.
            const SingleActivator(
              LogicalKeyboardKey.keyE,
              control: true,
              // Shift, because Ctrl+E centres a paragraph in every
              // word processor there is, and this one is no exception.
              shift: true,
            ): () async {
              final file = _selectedFile;
              if (file == null || !file.format.canEdit) return;
              await _toggleEditor(file);
            },
            // The next and previous document without going back to the list.
            const SingleActivator(
              LogicalKeyboardKey.arrowRight,
              alt: true,
            ): () =>
                _stepFile(true),
            const SingleActivator(
              LogicalKeyboardKey.arrowLeft,
              alt: true,
            ): () =>
                _stepFile(false),
            // The editor prints what is being written; this, what is shown.
            const SingleActivator(LogicalKeyboardKey.keyP, control: true): () {
              final file = _selectedFile;
              if (_isEditorMode || file == null || !canPrint(file)) return;
              _printCurrent();
            },
            const SingleActivator(LogicalKeyboardKey.f1): _showShortcuts,
            const SingleActivator(LogicalKeyboardKey.slash, control: true):
                _showShortcuts,
          },
          child: Focus(
            autofocus: true,
            child: DropZoneOverlay(
              onFilesDropped: _addFiles,
              child: Scaffold(
                drawer: mobile ? _mobileDrawer(mobileHome) : null,
                body: Actions(
                  actions: {
                    DismissIntent: CallbackAction<DismissIntent>(
                      onInvoke: (_) {
                        if (widget.onEscape != null) {
                          widget.onEscape!();
                        } else {
                          escapeBack();
                        }
                        return null;
                      },
                    ),
                  },
                  child: SafeArea(
                    child: Row(
                      children: [
                        if (!mobile)
                          Offstage(
                            // Full screen means the page and nothing else,
                            // on a desktop as much as on a phone. It used to
                            // hide only the preview's own header, because it
                            // was written for a phone where there is nothing
                            // else on screen anyway; here the sidebar and
                            // the result list stayed and it was full screen
                            // in name only.
                            offstage: editing
                                ? !_editorPanelsVisible
                                : (_fullScreen ||
                                      (!_showLibrary && _previewExpanded)),
                            child: _sidebar(compact || !_showLibrary),
                          ),
                        Expanded(
                          child: Column(
                            children: [
                              if (_showLibrary && mobileHome)
                                FoldingChrome(
                                  child: Container(
                                    height: 56,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: scheme.surface,
                                      border: Border(
                                        bottom: BorderSide(
                                          color: scheme.outlineVariant,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Builder(
                                          builder: (context) => IconButton(
                                            key: const ValueKey('mobile-menu'),
                                            tooltip: 'Menü',
                                            onPressed: () =>
                                                Scaffold.of(context)
                                                    .openDrawer(),
                                            icon: const Icon(
                                              Icons.menu_rounded,
                                            ),
                                          ),
                                        ),
                                        const Expanded(
                                          child: Text(
                                            'LifeOS Folio',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 17,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Kurtarılabilir taslaklar',
                                          onPressed: _openRecovery,
                                          icon: const Icon(
                                            Icons.restore_rounded,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Ayarlar',
                                          onPressed: _pickFolder,
                                          icon: const Icon(
                                            Icons.settings_outlined,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              // The agenda and UETS fill the page with their
                              // own heading; on a phone the menu button stays.
                              if (_showLibrary &&
                                  !mobileHome &&
                                  (mobile
                                      ? _group != 'images'
                                      : !_isFullPage(_group)))
                                FoldingChrome(
                                  // On a phone the heading folds away while
                                  // a page's list is scrolled.
                                  enabled: mobile,
                                  child: Container(
                                    height: 72,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: mobile ? 8 : 24,
                                    ),
                                    decoration: BoxDecoration(
                                      color: scheme.surface,
                                      border: Border(
                                        bottom: BorderSide(
                                          color: scheme.outlineVariant,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        if (mobile)
                                          Builder(
                                            builder: (context) => IconButton(
                                              tooltip: 'Menü',
                                              onPressed: () =>
                                                  Scaffold.of(context)
                                                      .openDrawer(),
                                              icon: const Icon(
                                                Icons.menu_rounded,
                                              ),
                                            ),
                                          ),
                                        Text(
                                          compact
                                              ? 'LifeOS Folio'
                                              : 'Kütüphane',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        SizedBox(width: mobile ? 4 : 12),
                                        if (!compact)
                                          Text(
                                            '/  ${_showLibrary
                                                ? _isUyapGroup(_group)
                                                      ? 'UYAP Dosyalarım'
                                                      : 'Evrak arşivi'
                                                : _isNewDocument
                                                ? _newTitle
                                                : 'Önizleme'}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        const Spacer(),
                                        if (_files.isNotEmpty)
                                          PopupMenuButton<int>(
                                            tooltip: 'Açık evraklar',
                                            icon: const Icon(
                                              Icons.tab_outlined,
                                              size: 20,
                                            ),
                                            onSelected: (i) =>
                                                _selectFile(_files[i]),
                                            itemBuilder: (_) => [
                                              for (
                                                var i = 0;
                                                i < _files.length;
                                                i++
                                              )
                                                PopupMenuItem(
                                                  value: i,
                                                  child: Text(_files[i].name),
                                                ),
                                            ],
                                          ),
                                        if (mobile)
                                          IconButton(
                                            tooltip: 'Dosya aç',
                                            onPressed: _pickFiles,
                                            icon: const Icon(
                                              Icons.upload_file_outlined,
                                            ),
                                          ),
                                        if (!mobile &&
                                            (Platform.isLinux ||
                                                Platform.isWindows))
                                          IconButton(
                                            tooltip: 'UYAP Devam Eden İşlemler',
                                            onPressed: () => showDialog<void>(
                                              context: context,
                                              builder: (_) =>
                                                  const UyapOperationsDialog(),
                                            ),
                                            icon: const Icon(
                                              Icons.pending_actions_outlined,
                                            ),
                                          ),
                                        IconButton(
                                          tooltip: 'Kurtarılabilir taslaklar',
                                          onPressed: _openRecovery,
                                          icon: Badge(
                                            isLabelVisible: _recoveryCount > 0,
                                            label: Text('$_recoveryCount'),
                                            child: const Icon(
                                              Icons.restore_rounded,
                                            ),
                                          ),
                                        ),
                                        if (!mobile)
                                          IconButton(
                                            tooltip: 'İndeksi güncelle',
                                            onPressed: _library.ready
                                                ? () => _library.refresh()
                                                : null,
                                            icon: const Icon(
                                              Icons.refresh_rounded,
                                              size: 20,
                                            ),
                                          ),
                                        SizedBox(width: mobile ? 0 : 12),
                                        if (!mobile)
                                          FilledButton.icon(
                                            onPressed: _newDocument,
                                            icon: const Icon(
                                              Icons.note_add_outlined,
                                              size: 16,
                                            ),
                                            label: const Text(
                                              'Yeni belge oluştur',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              // The gallery and the UYAP cases bring their own
                              // headings; the archive's search field and type
                              // filters have nothing to offer either.
                              if (_showLibrary &&
                                  !mobileHome &&
                                  _group != 'images' &&
                                  !_isUyapGroup(_group) &&
                                  !_isFullPage(_group))
                                FoldingChrome(
                                  enabled: mobile,
                                  child: _searchArea(compact),
                                ),
                              if (_showLibrary &&
                                  !mobileHome &&
                                  _library.error != null)
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: scheme.error.withValues(alpha: .08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        color: scheme.error,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _library.error!,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: scheme.error,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: _showStatus,
                                        child: const Text('Ayrıntılar'),
                                      ),
                                    ],
                                  ),
                                ),
                              Expanded(
                                key: const ValueKey('workspace-area'),
                                child: ChromeScrollWatcher(
                                  enabled: mobile,
                                  child: LayoutBuilder(
                                    builder: (context, box) => Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        TransitionPane(
                                          visible: _showLibrary,
                                          child: mobileHome
                                              ? _mobileHome()
                                              : _group == 'images'
                                              ? _gallery(mobile)
                                              : _isUyapGroup(_group)
                                              ? _uyapPage()
                                              : _group == 'home'
                                              ? _desktopHome()
                                              : _group == 'agenda'
                                              ? _agendaPage()
                                              : _group == 'uets'
                                              ? _uetsPage()
                                              : _overview(),
                                        ),
                                        TransitionPane(
                                          visible: !_showLibrary,
                                          child: Row(
                                            children: [
                                              if (box.maxWidth >= 800 &&
                                                  !_fullScreen &&
                                                  (editing
                                                      ? _editorPanelsVisible
                                                      : !_previewExpanded))
                                                SizedBox(
                                                  width: 300,
                                                  child: Column(
                                                    children: [
                                                      _previewSearch(),
                                                      _resultHeading(true),
                                                      Expanded(
                                                        child: _results(true),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              if (box.maxWidth >= 800 &&
                                                  !_fullScreen &&
                                                  (editing
                                                      ? _editorPanelsVisible
                                                      : !_previewExpanded))
                                                VerticalDivider(
                                                  width: 1,
                                                  color: scheme.outlineVariant,
                                                ),
                                              Expanded(
                                                child: Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    Offstage(
                                                      offstage: _isNewDocument,
                                                      child:
                                                          _selectedFile == null
                                                          ? const SizedBox.shrink()
                                                          : _buildWorkspace(
                                                              context,
                                                              _selectedFile!,
                                                            ),
                                                    ),
                                                    if (_newEditorOpened)
                                                      Offstage(
                                                        offstage:
                                                            !_isNewDocument,
                                                        child: Column(
                                                          children: [
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        18,
                                                                    vertical:
                                                                        10,
                                                                  ),
                                                              child: Row(
                                                                children: [
                                                                  Text(
                                                                    _newTitle,
                                                                    style: const TextStyle(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700,
                                                                    ),
                                                                  ),
                                                                  const Spacer(),
                                                                  if (!mobile)
                                                                    _editorPanelButton(),
                                                                  IconButton(
                                                                    tooltip: 'Arşive dön',
                                                                    onPressed:
                                                                        _goLibrary,
                                                                    icon: const Icon(
                                                                      Icons
                                                                          .close,
                                                                      size: 18,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                            Expanded(
                                                              child:
                                                                  _newRecovery?.format ==
                                                                          'spreadsheet-draft' ||
                                                                      _newRecovery
                                                                              ?.format ==
                                                                          'xlsx'
                                                                  ? SpreadsheetEditor(
                                                                      path:
                                                                          _recoverySource,
                                                                      recovery:
                                                                          _newRecovery,
                                                                      draft:
                                                                          _newDraft,
                                                                      onSaved:
                                                                          _saved,
                                                                      key: ValueKey(
                                                                        'new-sheet_$_newDocumentVersion',
                                                                      ),
                                                                    )
                                                                  : _newRecovery
                                                                            ?.format ==
                                                                        'text-draft'
                                                                  ? PlainTextEditor(
                                                                      key: ValueKey(
                                                                        'new-text_$_newDocumentVersion',
                                                                      ),
                                                                      path:
                                                                          _recoverySource ??
                                                                          _newRecovery!
                                                                              .sourcePath ??
                                                                          'Kurtarılan belge.txt',
                                                                      recovery:
                                                                          _newRecovery,
                                                                      draft:
                                                                          _newDraft,
                                                                      onSaved:
                                                                          _saved,
                                                                    )
                                                                  : EditorWidget(
                                                                      hostTabs:
                                                                          MediaQuery.sizeOf(
                                                                            context,
                                                                          ).width >=
                                                                          700,
                                                                      fileHost:
                                                                          _editorFileHost,
                                                                      library:
                                                                          _library,
                                                                      onSigned:
                                                                          _signed,
                                                                      recovery:
                                                                          _newRecovery,
                                                                      initialFilePath:
                                                                          _recoverySource,
                                                                      initialFormat:
                                                                          _recoverySource ==
                                                                              null
                                                                          ? (_newRecovery == null
                                                                                ? _newFormat
                                                                                : null)
                                                                          : EvrakFormat.fromExtension(
                                                                              _recoverySource!.split('.').last,
                                                                            ),
                                                                      draft:
                                                                          _newDraft,
                                                                      onSaved:
                                                                          _saved,
                                                                      uyapCase:
                                                                          _newCase,
                                                                      isActive:
                                                                          !_showLibrary &&
                                                                          _isNewDocument,
                                                                      key: ValueKey(
                                                                        'new-document_$_newDocumentVersion',
                                                                      ),
                                                                    ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                  ],
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
                              if (_showLibrary && !mobileHome) _statusBar(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _editorPanelButton() => IconButton(
    tooltip: _editorPanelsVisible ? 'Sol paneli gizle' : 'Sol paneli göster',
    icon: Icon(
      _editorPanelsVisible
          ? Icons.space_dashboard
          : Icons.space_dashboard_outlined,
      size: 20,
    ),
    onPressed: () =>
        setState(() => _editorPanelsVisible = !_editorPanelsVisible),
  );

  Widget _sidebar(bool compact) => LibrarySidebar(
    library: _library,
    appearance: widget.appearance,
    compact: compact,
    group: _group,
    pickFiles: () {
      _closeDrawer();
      _pickFiles();
    },
    pickFolder: () {
      _closeDrawer();
      _pickFolder();
    },
    showStatus: () {
      _closeDrawer();
      _showStatus();
    },
    selectGroup: (value) {
      _closeDrawer();
      _selectGroup(value);
    },
    uyapCases: [
      for (final (record, _) in _uyapCases)
        (record.key, record.number, record.court, record.fresh.length),
    ],
    uyapFolder: UyapSettings.instance.folder,
    agendaToday: _agendaToday,
    uetsUnread: _uetsUnread,
    uyapAvailable: true,
    showHome: !(Platform.isAndroid || Platform.isIOS),
    selectFolder: (id) async {
      _closeDrawer();
      if (!await _leaveEditor()) return;
      setState(() {
        _showLibrary = true;
        _mobileArchive = true;
      });
      _library.filter(folder: id);
    },
  );

  /// The phone's menu (docs/design/mobil-anasayfa-taslak.png).
  Widget _mobileDrawer(bool home) => MobileDrawer(
    group: _group,
    home: home,
    agendaToday: _agendaToday,
    uetsUnread: _uetsUnread,
    uyapCases: _uyapCases.length,
    onHome: () {
      _closeDrawer();
      setState(() {
        _mobileArchive = false;
        _showLibrary = true;
      });
    },
    onGroup: (value) {
      _closeDrawer();
      unawaited(_selectGroup(value));
    },
    onFolders: () {
      _closeDrawer();
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ArchiveFoldersPage(library: _library),
          ),
        ),
      );
    },
    onSettings: () {
      _closeDrawer();
      _pickFolder();
    },
    onConnectMobile: () async {
      _closeDrawer();
      final sync = PortalSync.instance;
      if (sync.mobile.connected) {
        unawaited(sync.syncMobile());
      } else if (await connectUyapMobile(context, api: sync.mobile)) {
        unawaited(sync.syncMobile());
      }
    },
    onConnectWeb: () {
      _closeDrawer();
      final sync = PortalSync.instance;
      if (sync.web.connected) {
        unawaited(sync.syncWeb());
      } else {
        unawaited(
          connectUyapWeb(context, onConnected: () => unawaited(sync.syncWeb())),
        );
      }
    },
    onConnectUets: () {
      _closeDrawer();
      final sync = PortalSync.instance;
      if (sync.uets.connected) {
        unawaited(sync.syncUets());
      } else {
        unawaited(connectUets(context, api: sync.uets, secrets: sync.secrets));
      }
    },
    onSyncComputer: () {
      _closeDrawer();
      showNotice(
        context,
        'Bilgisayarla senkron hazırlanıyor',
        detail:
            'Masaüstünde “Telefonla senkronla” deyip QR’ı okutarak '
            'eşitleyeceksiniz; bu özellik bir sonraki sürümde.',
      );
    },
  );

  void _closeDrawer() {
    if (MediaQuery.sizeOf(context).width < 700) Navigator.of(context).pop();
  }

  Widget _searchArea(bool compact) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            focusNode: _searchFocus,
            onChanged: (text) {
              setState(() => _showLibrary = true);
              _library.setQuery(text);
            },
            onSubmitted: (_) {
              _library.searchNow();
              _library.rememberQuery();
            },
            decoration: InputDecoration(
              hintText: 'Evrak adı veya içeriğinde ara…',
              prefixIcon: Icon(
                Icons.search_rounded,
                color: scheme.onSurfaceVariant,
                size: 22,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_library.query.isNotEmpty)
                    IconButton(
                      tooltip: 'Aramayı temizle',
                      onPressed: () {
                        _searchController.clear();
                        _library.setQuery('');
                      },
                      icon: const Icon(Icons.close, size: 18),
                    )
                  else if (MediaQuery.sizeOf(context).width >= 700)
                    Padding(
                      padding: const EdgeInsets.only(right: 18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: scheme.outlineVariant),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          'Ctrl K',
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SearchControls(library: _library),
          if (_library.sourceId != null)
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.folder_outlined, size: 14),
                label: Text(
                  _library.sources
                          .where((s) => s.id == _library.sourceId)
                          .firstOrNull
                          ?.name ??
                      'Klasör',
                ),
                onDeleted: () => _library.filter(clearFolder: true),
              ),
            ),
        ],
      ),
    );
  }

  /// The gallery on its own, without the archive around it.
  ///
  /// A photograph has no text to search, no file type to filter by and no
  /// relevance to sort on. Leaving the archive's search field, its type chips
  /// and its sort chips above a wall of thumbnails takes a third of a phone
  /// screen to offer three things that mean nothing here.
  /// The phone's gallery (docs/design/mobil-galeri-taslak.png): its own
  /// heading, the photographs full screen, edited, made a PDF, shared or
  /// put in a UYAP case's folder.
  Widget _phoneGallery() => MobileGallery(
    hits: _library.hits,
    library: _library,
    hasMore: _library.hits.length < _library.matches,
    loadMore: () => _library.searchNow(more: true),
    pickFolder: () => Platform.isAndroid
        ? DocumentIntents.pickPictureFolder()
        : FilePicker.getDirectoryPath(
            dialogTitle: 'Galeriye eklenecek klasörü seçin',
          ),
    onScan: DocumentScan.available ? () => unawaited(_scanToPdf()) : null,
    onOpen: (index) => unawaited(
      PhotoViewerPage.open(
        context,
        files: [for (final h in _library.hits) h.file],
        initial: index,
        onShare: (file) => unawaited(_previewAction('share', file)),
        onPdf: (file) => _openConvertDialog(specificFiles: [file]),
        onEdit: _editPhoto,
        onToCase: (file) => unawaited(_photosToCase([file])),
      ),
    ),
    onMakePdf: (files) => _openConvertDialog(specificFiles: files),
    onShare: (files) => unawaited(_sharePhotos(files)),
    onToCase: (files) => unawaited(_photosToCase(files)),
  );

  /// The photograph edited, its copy written beside it and announced.
  Future<String?> _editPhoto(EvrakFile file) async {
    final path = await PhotoEditorPage.open(context, file.path);
    if (path != null) {
      _cropSaved(path);
      unawaited(_library.searchNow());
    }
    return path;
  }

  Future<void> _sharePhotos(List<EvrakFile> files) async {
    try {
      await FileActions.shareMany([for (final f in files) f.path]);
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Paylaşılamadı',
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
    }
  }

  /// Photographs copied into a UYAP case's folder, where the case's
  /// documents are kept and searched.
  Future<void> _photosToCase(List<EvrakFile> files) async {
    if (_uyapCases.isEmpty) {
      showNotice(
        context,
        'UYAP Dosyalarım boş',
        detail: 'Önce UYAP Dosyalarım’a bir dosya ekleyin.',
      );
      return;
    }
    final record = await showModalBottomSheet<UyapCaseRecord>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheet).height * .7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Hangi dosyaya?',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              for (final (r, _) in _uyapCases)
                ListTile(
                  leading: const Icon(Icons.gavel_rounded),
                  title: Text(r.number),
                  subtitle: Text(r.court),
                  onTap: () => Navigator.pop(sheet, r),
                ),
            ],
          ),
        ),
      ),
    );
    if (record == null || !mounted) return;
    try {
      await UyapSettings.instance.load();
      final folder = Directory(
        p.join(
          UyapSettings.instance.folder,
          UyapCaseStore.caseFolderName(record),
        ),
      );
      await folder.create(recursive: true);
      for (final f in files) {
        await FileActions.copyToDirectory(f.path, folder.path);
      }
      if (!mounted) return;
      showNotice(
        context,
        '${files.length} resim ${record.number} dosyasına kopyalandı.',
        kind: NoticeKind.success,
      );
      unawaited(searchUyapFolder(_library).catchError((Object _) => false));
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Kopyalanamadı',
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
    }
  }

  Widget _gallery(bool mobile) {
    if (mobile) return _phoneGallery();
    final scheme = Theme.of(context).colorScheme;
    final indexing = _library.active;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(mobile ? 6 : 24, 10, 12, 2),
          child: Row(
            children: [
              if (mobile)
                IconButton(
                  tooltip: 'Geri',
                  icon: const Icon(Icons.arrow_back_rounded, size: 22),
                  onPressed: () => setState(() => _mobileArchive = false),
                ),
              const Text(
                'Galeri',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.6,
                ),
              ),
              const Spacer(),
              Text(
                '${_library.matches} fotoğraf',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        // Scanning a camera roll takes a moment the first time; saying so is
        // better than a wall that fills in silently.
        if (indexing)
          Padding(
            padding: EdgeInsets.fromLTRB(mobile ? 14 : 24, 4, 24, 0),
            child: Row(
              children: [
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 9),
                Text(
                  'Fotoğraflar taranıyor…',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        Expanded(child: _results(mobile)),
      ],
    );
  }

  Widget _overview() {
    final scheme = Theme.of(context).colorScheme;
    return CollapsingOverview(
      header:
          (_library.query.isEmpty &&
              _library.sourceId == null &&
              MediaQuery.viewInsetsOf(context).bottom == 0 &&
              MediaQuery.sizeOf(context).height >= 650)
          ? Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Evraklarınız. Tek bir yerde.',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.9,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'Dosyalarınızı bulun, önizleyin ve uygun biçime dönüştürün.',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (MediaQuery.sizeOf(context).width >= 700 &&
                      MediaQuery.sizeOf(context).height >= 650)
                    Row(
                      children: [
                        Expanded(
                          child: _stat(
                            Icons.folder_copy_outlined,
                            'Arşivdeki evrak',
                            '${_library.total}',
                            const Color(0xFF6B8DED),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _stat(
                            Icons.manage_search_rounded,
                            'İçeriği aranabilir',
                            '${_library.searchable}',
                            const Color(0xFF36B895),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _stat(
                            Icons.folder_outlined,
                            'Bağlı klasör',
                            '${_library.sources.where((s) => s.folder).length}',
                            const Color(0xFFB395E3),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            )
          : const SizedBox.shrink(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_library.query.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_library.recentQueries.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.history_rounded, size: 15),
                        const SizedBox(width: 7),
                        const Expanded(
                          child: Text(
                            'Son aramalar',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _library.clearHistory,
                          child: const Text(
                            'Temizle',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final query in _library.recentQueries)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                label: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 240,
                                  ),
                                  child: Text(
                                    query,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                onPressed: () {
                                  _searchController.text = query;
                                  _library.setQuery(query);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Tüm evraklar'),
                        showCheckmark: false,
                        selected: _library.sort != 'added',
                        onSelected: (_) =>
                            _library.filter(ordering: 'relevance'),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Yeni eklenenler'),
                        showCheckmark: false,
                        selected: _library.sort == 'added',
                        onSelected: (_) => _library.filter(ordering: 'added'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          _resultHeading(false),
          Expanded(child: _results(false)),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String label, String value, Color accent) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: accent, size: 21),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultHeading(bool compact) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 24, 8, compact ? 12 : 24, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _library.query.isEmpty
                  ? 'EVRAKLAR  ·  ${_library.matches}'
                  : '${_library.matches} sonuç',
              style: TextStyle(
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w600,
                letterSpacing: _library.query.isEmpty ? .7 : 0,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (!compact)
            DropdownButtonHideUnderline(
              child: FolioSelect<String>(
                value: _library.sort,
                isDense: true,
                style: TextStyle(
                  fontFamily: 'LiberationSans',
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'relevance',
                    child: Text('Alaka sırasına göre'),
                  ),
                  DropdownMenuItem(
                    value: 'newest',
                    child: Text('En yeni önce'),
                  ),
                  DropdownMenuItem(
                    value: 'added',
                    child: Text('Son eklenenler'),
                  ),
                  DropdownMenuItem(
                    value: 'oldest',
                    child: Text('En eski önce'),
                  ),
                  DropdownMenuItem(
                    value: 'name',
                    child: Text('Dosya adına göre'),
                  ),
                ],
                onChanged: (value) => _library.filter(ordering: value),
              ),
            ),
          if (!compact && _files.isNotEmpty)
            PopupMenuButton<bool>(
              tooltip: 'Toplu dönüştür',
              icon: const Icon(Icons.transform_rounded, size: 18),
              onSelected: (visual) => _openConvertDialog(
                specificFiles: _files
                    .where(
                      (f) =>
                          f.format.isVisual == visual &&
                          f.conversionTargets.isNotEmpty,
                    )
                    .toList(),
              ),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: false,
                  enabled: _files.any(
                    (f) => !f.format.isVisual && f.conversionTargets.isNotEmpty,
                  ),
                  child: const Text('Açık belgeleri dönüştür'),
                ),
                PopupMenuItem(
                  value: true,
                  enabled: _files.any(
                    (f) => f.format.isVisual && f.conversionTargets.isNotEmpty,
                  ),
                  child: const Text('Açık görselleri dönüştür'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// The archive looks different when it is showing photographs: a wall of
  /// thumbnails rather than a list of names, and its own folders to add and
  /// take away.
  Widget _results(bool compact) => _group == 'images' && _library.query.isEmpty
      ? GalleryView(
          library: _library,
          hits: _library.hits,
          compact: compact,
          selectedPath: _showLibrary ? null : _selectedFile?.path,
          hasMore: _library.hits.length < _library.matches,
          loadMore: () => _library.searchNow(more: true),
          onOpen: _selectFile,
          pickFolder: () => Platform.isAndroid
              ? DocumentIntents.pickPictureFolder()
              : FilePicker.getDirectoryPath(
                  dialogTitle: 'Galeriye eklenecek klasörü seçin',
                ),
        )
      : _list(compact);

  Widget _list(bool compact) => SearchResults(
    focusNode: compact ? _resultsFocus : _libraryResultsFocus,
    empty: _library.searchError == null
        ? null
        : Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_library.searchError!),
            ),
          ),
    hoverPreview: widget.appearance.hoverPreview,
    hits: _library.hits,
    query: _library.query,
    selectedPath: _showLibrary ? null : _selectedFile?.path,
    compact: compact,
    searching: _library.searching,
    hasMore: _library.hits.length < _library.matches,
    loadMore: () => _library.searchNow(more: true),
    onOpen: _selectFile,
    passages: _library.passages,
  );

  /// Listens to the indexing counters on its own, so they move without the
  /// whole page being built again.
  Widget _statusBar() => ListenableBuilder(
    listenable: _library.progress,
    builder: (context, _) => _statusBarContent(),
  );

  Widget _statusBarContent() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          if (_library.active)
            // How far it has come rather than a spinner: a spinner redraws
            // the window on every display refresh, 200 times a second on a
            // fast screen, for as long as the archive is scanned.
            SizedBox(
              width: 12,
              height: 12,
              child: _library.toProcess > 0
                  ? CircularProgressIndicator(
                      value: _library.processed / _library.toProcess,
                      strokeWidth: 1.5,
                      color: scheme.primary,
                      backgroundColor: scheme.outlineVariant,
                    )
                  : Icon(Icons.sync_rounded, size: 12, color: scheme.primary),
            )
          else
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFF2CBA8C),
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _library.active
                  ? '${_library.phase} · ${_library.processed} / ${_library.toProcess}'
                  : _library.cancelled
                  ? 'İndeksleme durduruldu'
                  : 'Yerel arşiv · ${_library.total} evrak',
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_library.query.isNotEmpty)
            Text(
              '${(_library.elapsedMicros / 1000).toStringAsFixed(1)} ms',
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: _showStatus,
            child: Text(
              _library.active ? 'İlerlemeyi gör' : 'İndeks durumu',
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewSearch() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: TextField(
      key: const ValueKey('preview-search'),
      controller: _searchController,
      focusNode: _showLibrary ? null : _searchFocus,
      style: const TextStyle(fontSize: 13),
      onChanged: _library.setQuery,
      onSubmitted: (_) {
        _library.searchNow();
        _library.rememberQuery();
      },
      decoration: InputDecoration(
        hintText: 'Belge veya içerik ara…',
        isDense: true,
        prefixIcon: const Icon(Icons.search_rounded, size: 19),
        suffixIcon: IconButton(
          tooltip: 'Arama ve filtreler',
          icon: const Icon(Icons.tune_rounded, size: 18),
          onPressed: _goLibrary,
        ),
      ),
    ),
  );

  /// PDFs are exported, never saved over, so Folio keeps no versions of them.
  bool _hasHistory(EvrakFile file) =>
      file.format.canEdit && file.format != EvrakFormat.pdf;

  /// The document's history: through the open editor, which knows the edits
  /// not saved yet, or else straight from the file.
  Future<void> _showHistory(EvrakFile file) async {
    final fromEditor = _activeDraft?.history;
    if (fromEditor != null) return fromEditor();
    await _previewHistory(file);
  }

  Future<void> _previewHistory(EvrakFile file) async {
    final path = file.path;
    final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
    final entry = await showDocumentVersions(
      context,
      document: DocumentHistory.documentKey(path),
      title: file.name,
      currentText: () => documentFileText(path),
      restoreLabel: 'Bu sürüme dön',
      restoreHint:
          'Dosya seçtiğiniz sürümle değiştirilir; şu anki hali belge '
          'geçmişinde saklanır.',
      canRestore: (entry) => entry.format.toLowerCase() == extension,
    );
    if (entry == null || !mounted) return;
    if (_fileDraft(file).hasChanges) {
      showNotice(
        context,
        'Açık editörde kaydedilmemiş değişiklikler var',
        detail: 'Önce onları kaydedin ya da bırakın.',
        kind: NoticeKind.error,
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Belge bu sürüme döndürülsün mü?'),
        content: Text(
          '“${file.name}” dosyası ${draftDate(entry.created)} tarihli sürümle '
          'değiştirilecek. Dosyanın şu anki hali belge geçmişinde saklanır; '
          'istediğiniz an ona geri dönebilirsiniz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Bu sürüme dön'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await DocumentHistory.instance.restoreToFile(entry, path);
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Sürüme dönülemedi',
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      // An editor left open on the old text would write it back on its next
      // save; the next "Düzenle" reads the file again instead.
      _openedEditors.remove(path);
      _viewerRevision[path] = (_viewerRevision[path] ?? 0) + 1;
      final index = _files.indexWhere((f) => f.path == path);
      if (index >= 0) _files[index] = EvrakFile.fromPath(path);
    });
    unawaited(_library.updatePaths([path]));
    showNotice(
      context,
      'Belge seçilen sürüme döndürüldü',
      detail: 'Önceki hali belge geçmişinde saklandı.',
      kind: NoticeKind.success,
    );
  }

  bool _documentActionsOpen = false;
  Future<void> _showDocumentActions(EvrakFile file) async {
    if (_documentActionsOpen) return;
    _documentActionsOpen = true;
    HoverDocumentPreview.dismissActive();
    try {
      final saved = _isEditorMode ? _fileDraft(file).savedPath?.call() : null;
      if (saved != null && await File(saved).exists()) {
        file = EvrakFile.fromPath(saved);
      }
      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        useRootNavigator: true,
        builder: (_) => DocumentActionsDialog(file: file),
      );
      if (mounted && action != null) await _previewAction(action, file);
    } finally {
      _documentActionsOpen = false;
    }
  }

  Future<void> _previewAction(String action, EvrakFile file) async {
    if (['share', 'external', 'openWith', 'sign'].contains(action) &&
        _activeDraft != null) {
      final draft = _activeDraft!;
      if (!await _leaveEditor()) return;
      final path = draft.savedPath?.call();
      if (path != null && await File(path).exists()) {
        file = EvrakFile.fromPath(path);
      }
      if (!mounted) return;
    }
    switch (action) {
      case 'history':
        await _showHistory(file);
      case 'convert':
        _openConvertDialog(specificFiles: [file]);
      case 'sign':
        if (!signingAvailable || file.format != EvrakFormat.udf) return;
        final path = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (_) => SigningDialog(filePath: file.path),
        );
        if (mounted && path != null) await _signed(path);
      case 'optimize':
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => OptimizeDialog(file: file),
        );
      case 'print':
        await _printCurrent();
      case 'newWindow':
        await _openInNewWindow(file);
      case 'external':
        await _fileAction('openDefault', file);
      case 'openWith':
        await _fileAction('openWith', file);
      case 'folder':
        await _fileAction('showFolder', file);
      case 'share':
        if (Platform.isAndroid) {
          await _fileAction('share', file);
        } else {
          final message = await showDialog<String>(
            context: context,
            builder: (_) => ShareDocumentDialog(path: file.path),
          );
          if (mounted && message != null && message.isNotEmpty) {
            showNotice(context, message, kind: NoticeKind.success);
          }
        }
    }
  }

  Widget _buildWorkspace(BuildContext context, EvrakFile file) {
    final phone = MediaQuery.sizeOf(context).width < 700;
    final scheme = Theme.of(context).colorScheme;
    final pane = _workspace(context, file, phone, scheme);
    if (!phone) return pane;
    // A drag from the left edge goes back, the way a phone expects. Only the
    // edge: a drag anywhere else on the page turns it, or pans a picture
    // that has been zoomed into.
    return Stack(
      children: [
        pane,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 22,
          child: GestureDetector(
            key: const ValueKey('edge-back'),
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null &&
                  details.primaryVelocity! > 180) {
                unawaited(_back(allowExit: false));
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _workspace(
    BuildContext context,
    EvrakFile file,
    bool phone,
    ColorScheme scheme,
  ) {
    return Column(
      children: [
        // The window's full screen (F11) puts the heading away too.
        if (!_fullScreen && !windowFullScreen.value)
          FoldingChrome(
            // On a phone the heading folds away while the
            // document is scrolled, and returns when it is
            // pulled back.
            enabled: phone,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  key: const ValueKey('preview-header'),
                  height: 56,
                  color: scheme.surface,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Arşive dön',
                        onPressed: _goLibrary,
                        icon: const Icon(Icons.arrow_back_rounded, size: 20),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Tooltip(
                                message: _shownPath(file),
                                // As wide as the name, so that the ribbon's
                                // tabs follow it.
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    FileBadge(file: file, size: 28),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        p.basename(_shownPath(file)),
                                        key: const ValueKey('workspace-title'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // The editor's ribbon tabs, after the name.
                            if (_isEditorMode &&
                                !phone &&
                                file.format != EvrakFormat.spreadsheet &&
                                !file.format.usesPlainTextEditor) ...[
                              const SizedBox(width: 18),
                              const EditorRibbonTabs(height: 56),
                            ],
                          ],
                        ),
                      ),
                      if (phone && !_isEditorMode)
                        IconButton(
                          tooltip: 'Tam ekran',
                          icon: const Icon(Icons.fullscreen_rounded, size: 22),
                          onPressed: () => _setFullScreen(true),
                        ),
                      if (!phone && file.format.canEdit)
                        OutlinedButton.icon(
                          icon: Icon(
                            _isEditorMode
                                ? Icons.visibility_outlined
                                : Icons.edit_note_rounded,
                            size: 17,
                          ),
                          label: Text(
                            _isEditorMode ? 'Önizlemeye Dön' : 'Düzenle',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: () => _toggleEditor(file),
                        ),
                      if (!phone &&
                          !_isEditorMode &&
                          EditorWindow.available &&
                          opensInEditorWindow(file))
                        IconButton(
                          key: const ValueKey('preview-new-window'),
                          tooltip: 'Yeni pencerede düzenle',
                          icon: const Icon(Icons.open_in_new_rounded, size: 19),
                          onPressed: () => unawaited(_openInNewWindow(file)),
                        ),
                      // A phone's heading keeps to the essentials;
                      // printing is in the document's actions.
                      if (!phone &&
                          !_isEditorMode &&
                          speechAvailable &&
                          _readableFormats.contains(file.format))
                        ListenableBuilder(
                          listenable: ReadAloud.instance,
                          builder: (context, _) {
                            final reading =
                                ReadAloud.instance.owner == previewSpeech;
                            return IconButton(
                              key: const ValueKey('preview-read-aloud'),
                              tooltip: reading ? 'Okumayı durdur' : 'Sesli oku',
                              isSelected: reading,
                              icon: const Icon(
                                Icons.record_voice_over_outlined,
                                size: 20,
                              ),
                              onPressed: () => unawaited(_readPreview(file)),
                            );
                          },
                        ),
                      if (!phone && !_isEditorMode && canPrint(file))
                        IconButton(
                          key: const ValueKey('preview-print'),
                          tooltip: 'Yazdır (Ctrl+P)',
                          icon: const Icon(Icons.print_outlined, size: 20),
                          onPressed: _printCurrent,
                        ),
                      // In the editor its own toolbar has the same button.
                      if (!phone && !_isEditorMode && _hasHistory(file))
                        IconButton(
                          tooltip: 'Belge geçmişi',
                          icon: const Icon(Icons.history_rounded, size: 20),
                          onPressed: () => _showHistory(file),
                        ),
                      if (!phone && _isEditorMode)
                        _editorPanelButton()
                      else if (!phone)
                        IconButton(
                          tooltip: _previewExpanded
                              ? 'Sonuçları göster'
                              : 'Önizlemeyi genişlet',
                          icon: Icon(
                            _previewExpanded
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                            size: 21,
                          ),
                          onPressed: () => setState(
                            () => _previewExpanded = !_previewExpanded,
                          ),
                        ),
                      // A phone's two actions, small, where the heading has room.
                      if (phone && file.format.canEdit)
                        TextButton.icon(
                          key: const ValueKey('phone-edit-toggle'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: () => _toggleEditor(file),
                          icon: Icon(
                            _isEditorMode
                                ? Icons.visibility_outlined
                                : Icons.edit_note_rounded,
                            size: 18,
                          ),
                          label: Text(_isEditorMode ? 'Önizleme' : 'Düzenle'),
                        ),
                      if (phone)
                        IconButton(
                          key: const ValueKey('phone-share'),
                          tooltip: 'Paylaş',
                          icon: const Icon(Icons.ios_share_rounded, size: 20),
                          onPressed: () async {
                            if (_isEditorMode && !await _leaveEditor()) return;
                            final path = _fileDraft(file).savedPath?.call();
                            final target =
                                path != null && await File(path).exists()
                                ? EvrakFile.fromPath(path)
                                : file;
                            if (mounted) await _previewAction('share', target);
                          },
                        ),
                      IconButton(
                        tooltip: 'Belge işlemleri',
                        icon: const Icon(Icons.more_horiz_rounded, size: 23),
                        onPressed: () => _showDocumentActions(file),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
              ],
            ),
          ),
        Expanded(
          child: ChromeScrollWatcher(
            enabled: phone,
            child: Stack(
              fit: StackFit.expand,
              children: [
                TransitionPane(
                  visible: !_isEditorMode,
                  child: _previewBody(file),
                ),
                if (speechAvailable && !_isEditorMode)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 18,
                    child: Center(child: SpeechBar(owner: previewSpeech)),
                  ),
                // The way back out, floating over the document rather than
                // taking a strip of it. A tap on the page itself belongs to the
                // document — that is how text is selected and highlighted.
                if (_fullScreen)
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 6,
                    right: 8,
                    child: Material(
                      color: Colors.black.withValues(alpha: .55),
                      shape: const CircleBorder(),
                      child: IconButton(
                        key: const ValueKey('preview-exit-fullscreen'),
                        tooltip: 'Tam ekrandan çık',
                        icon: const Icon(
                          Icons.fullscreen_exit_rounded,
                          size: 22,
                          color: Colors.white,
                        ),
                        onPressed: () => _setFullScreen(false),
                      ),
                    ),
                  ),
                for (final opened in _files.where(
                  (f) => _openedEditors.contains(f.path),
                ))
                  TransitionPane(
                    key: ValueKey('draft_${opened.path}'),
                    visible: _isEditorMode && opened.path == file.path,
                    child: TickerMode(
                      enabled:
                          !_showLibrary &&
                          !_isNewDocument &&
                          _isEditorMode &&
                          opened.path == file.path,
                      child: opened.format == EvrakFormat.spreadsheet
                          ? SpreadsheetEditor(
                              path: opened.path,
                              draft: _fileDraft(opened),
                              onSaved: _saved,
                            )
                          : opened.format.usesPlainTextEditor
                          ? PlainTextEditor(
                              path: opened.path,
                              draft: _fileDraft(opened),
                              onSaved: _saved,
                            )
                          : EditorWidget(
                              hostTabs: MediaQuery.sizeOf(context).width >= 700,
                              fileHost: _editorFileHost,
                              draft: _fileDraft(opened),
                              library: _library,
                              onSaved: _saved,
                              onSigned: _signed,
                              initialFilePath: opened.path,
                              initialFormat: opened.format,
                              initialPdfTextLoader:
                                  opened.format == EvrakFormat.pdf
                                  ? () => _loadViewerPdfText(opened.path)
                                  : null,
                              reveal: _revealAt[opened.path],
                              isActive:
                                  !_showLibrary &&
                                  !_isNewDocument &&
                                  _isEditorMode &&
                                  opened.path == file.path,
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static const _readableFormats = {
    EvrakFormat.pdf,
    EvrakFormat.udf,
    EvrakFormat.docx,
    EvrakFormat.odt,
    EvrakFormat.rtf,
    EvrakFormat.doc,
    EvrakFormat.html,
    EvrakFormat.markdown,
    EvrakFormat.text,
  };

  void _stopPreviewSpeech() {
    if (ReadAloud.instance.owner == previewSpeech) {
      unawaited(ReadAloud.instance.stop());
    }
  }

  /// Reads the document being previewed aloud from the top; pressed again,
  /// stops.
  Future<void> _readPreview(EvrakFile file) async {
    final reading = ReadAloud.instance;
    if (reading.state != ReadState.idle && reading.owner == previewSpeech) {
      await reading.stop();
      return;
    }
    await readAloud(
      context,
      owner: previewSpeech,
      text: () async {
        final model = await ConverterService.extractDocModel(
          await File(file.path).readAsBytes(),
          file.format,
        );
        return [for (final block in model?.blocks ?? const []) block.plainText]
            .join('\n');
      },
      emptyDetail: file.format == EvrakFormat.pdf
          ? 'Taranmış bir PDF olabilir; önce metin tanıma gerekir.'
          : null,
    );
  }

  /// [file] in an editor window of its own, beside this one. What is open
  /// in this window's editor stays here: the new window then only reads it,
  /// and says why.
  Future<void> _openInNewWindow(EvrakFile file) async {
    try {
      await EditorWindow.open(file.path);
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Yeni pencere açılamadı',
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
    }
  }

  Future<void> _printCurrent() async {
    final file = _selectedFile;
    if (file == null) return;

    try {
      Uint8List? pdf;
      if (file.format == EvrakFormat.pdf) {
        pdf = await File(file.path).readAsBytes();
      } else if (file.format == EvrakFormat.tif) {
        pdf = await TiffService.tiffToPdf(await File(file.path).readAsBytes());
      } else {
        final model = await ConverterService.extractDocModel(
          await File(file.path).readAsBytes(),
          file.format,
        );
        if (model != null) {
          pdf = await PdfService.modelToPdfBytes(model, title: file.baseName);
        }
      }
      if (pdf != null && mounted) {
        await PrintScreen.show(context, pdf: pdf, name: file.name);
      }
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Yazdırılamadı',
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
    }
  }

  Future<void> _fileAction(String action, EvrakFile file) async {
    try {
      await FileActions.invoke(action, file.path);
    } catch (e) {
      if (mounted) {
        final message = e is PlatformException
            ? e.message ?? 'İşlem tamamlanamadı.'
            : '$e';
        showNotice(context, message, kind: NoticeKind.error);
      }
    }
  }

  /// A crop has been written beside the original.
  ///
  /// The folder is watched, so the new photograph arrives in the gallery
  /// on its own. What the reader needs is to be told it happened, and a
  /// way straight to it, since a crop is usually made to be used.
  void _cropSaved(String path) {
    if (!mounted) return;
    final name = path.split(Platform.pathSeparator).last;
    showNotice(
      context,
      '$name kaydedildi.',
      kind: NoticeKind.success,
      actionLabel: 'Aç',
      onAction: () => _selectFile(EvrakFile.fromPath(path)),
      duration: const Duration(seconds: 6),
    );
  }

  /// The viewer, with the crossing from one picture to the next.
  ///
  /// A photograph is faded across: stepping through a folder with a hard
  /// cut on every press reads as flicker rather than as movement, and two
  /// pictures are cheap to hold for a sixth of a second. A document is
  /// swapped outright, because two PDF viewers alive at once are not.
  Widget _previewBody(EvrakFile file) {
    final keyed = KeyedSubtree(
      key: ValueKey('preview_${file.path}_${_viewerRevision[file.path] ?? 0}'),
      child: _buildFileViewer(file),
    );
    if (file.format != EvrakFormat.image && file.format != EvrakFormat.svg) {
      return keyed;
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      // Stacked rather than laid side by side, so the one arriving is
      // already where it belongs while the one leaving fades off it.
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [...previous, ?current],
      ),
      child: keyed,
    );
  }

  Widget _buildFileViewer(EvrakFile file) {
    switch (file.format) {
      case EvrakFormat.spreadsheet:
        return SpreadsheetViewer(path: file.path);
      case EvrakFormat.pdf:
        return PdfViewerWidget(
          key: ValueKey('pdf_${file.path}'),
          filePath: file.path,
          library: _library,
          onPastEnd: _stepFile,
          chrome: !_fullScreen,
          initialPage: _readingPage[file.path],
          onPageChanged: (page) => _readingPage[file.path] = page,
          onTextLoaderChanged: (loader) {
            if (loader == null) {
              _pdfTextLoaders.remove(file.path);
            } else {
              _pdfTextLoaders[file.path] = loader;
            }
          },
        );

      case EvrakFormat.tif:
        return TiffViewerWidget(
          key: ValueKey('tif_${file.path}'),
          filePath: file.path,
          library: _library,
          onConvertToPdfRequested: () =>
              _openConvertDialog(specificFiles: [file]),
          initialPage: _readingPage[file.path],
          onPageChanged: (page) => _readingPage[file.path] = page,
        );

      case EvrakFormat.svg:
      case EvrakFormat.image:
        {
          final at = _library.hits.indexWhere(
            (hit) => hit.file.path == file.path,
          );
          return ImageViewerWidget(
            key: ValueKey(file.path),
            filePath: file.path,
            library: _library,
            onPastEnd: _stepFile,
            chrome: !_fullScreen,
            // Counted against the whole folder, not against what has been
            // loaded so far: a reader wants to know they are third of six
            // hundred, not third of the fifty fetched.
            position: at >= 0 ? at + 1 : null,
            total: at >= 0 ? _library.matches : null,
            onFullScreen: () => _setFullScreen(!_fullScreen),
            onCropped: _cropSaved,
            // From the gallery the picture is the whole of what was asked
            // for, so it takes the keyboard without waiting to be clicked.
            grabFocus: _group == 'images',
          );
        }

      case EvrakFormat.odt:
      case EvrakFormat.rtf:
      case EvrakFormat.doc:
      case EvrakFormat.html:
      case EvrakFormat.markdown:
      case EvrakFormat.udf:
      case EvrakFormat.docx:
      case EvrakFormat.text:
        return DocumentPreviewWidget(
          key: ValueKey('view_${file.path}'),
          file: file,
          onPastEnd: _stepFile,
          chrome: !_fullScreen,
          onEditAt: _editsOnDoubleClick(file)
              ? (anchor) => _editAt(file, anchor)
              : null,
        );

      case EvrakFormat.data:
        return DataPreviewWidget(key: ValueKey(file.path), filePath: file.path);
      default:
        return const Center(
          child: Text('Bu format için önizleme desteklenmiyor.'),
        );
    }
  }
}

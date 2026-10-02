import 'dart:convert';
import 'dart:math' as math;

import '../../services/speech/speech_models.dart';
import '../../services/speech/speech_session.dart';
import '../../services/platform/android_document_save.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

import '../../services/editor/document_history.dart';
import '../../services/editor/document_lock.dart';
import '../../services/uyap/uyap_case_links.dart';
import '../../services/uyap/uyap_case_panel_controller.dart';
import '../../services/uyap/uyap_library.dart';
import '../../preview_app.dart' show openPreviewWindow;
import '../../services/platform/editor_window.dart';
import 'document_versions_window.dart';
import 'draft_prompts.dart';
import 'notice.dart';
import 'print_screen.dart';

import 'package:path/path.dart' as p;

import '../../services/fonts/document_fonts.dart';
import '../legal/case_law_search_screen.dart';
import 'citation_list_panel.dart';
import 'file_preview.dart';
import 'resize_handle.dart';
import 'speech_actions.dart';
import 'uyap_case_panel.dart';
import 'speech_bar.dart';
import 'speech_download_dialog.dart';
import 'editor_citations.dart';
import 'editor_spelling.dart';
import 'editor_tab_spans.dart';
import 'article_panel.dart';
import '../../services/legal/case_law.dart';
import '../../services/legal/citation.dart';
import '../../services/legal/decision.dart';
import '../../services/legal/legal_settings.dart';
import '../../services/legal/legal_terms.dart';
import '../../services/legal/legislation.dart';
import 'signature_banner.dart';
import 'signing_dialog.dart';
import 'uyap_send_dialog.dart';
import 'editor_file_menu.dart';
import 'uyap_operations_dialog.dart';
import '../../services/uyap/uyap_web_service.dart';
import '../../services/signing/udf_signing_service.dart';
import '../../services/platform/platform_capabilities.dart';

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor_toolbar.dart';
import 'editor_find_replace.dart';
import 'editor_image_embed.dart';
import 'editor_clipboard.dart';
import 'editor_region_band.dart';
import 'letterhead_dialog.dart';
import 'page_number_dialog.dart';
import 'editor_pages.dart';
import 'editor_sheets.dart';
import 'editor_table_embed.dart';
import 'editor_shortcut.dart';
import 'snippet_fill.dart';
import 'snippet_harvest.dart';
import 'snippet_palette.dart';
import 'suggestion_list.dart';
import 'document_ruler.dart';
import 'editor_page_viewport.dart';

import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../models/document_model.dart';
import '../../models/evrak_file.dart';
import '../../services/convert/converter_service.dart';
import '../../services/docx/docx_bridge.dart';
import '../../services/editor/doc_delta_map.dart';
import '../../services/editor/editor_settings.dart';
import '../../services/editor/lawyer_profile.dart';
import '../../services/editor/suggestions/phrase_memory.dart';
import '../../services/editor/suggestions/suggestion_engine.dart';
import 'lawyer_profile_dialog.dart';
import 'snippet_manager.dart';
import '../../services/editor/text_anchor.dart';
import '../../services/editor/snippets.dart';
import '../../services/search/library_controller.dart';
import '../../services/editor/editor_drafts.dart';
import '../../services/editor/spell_check.dart';
import '../../services/editor/editor_images.dart';
import '../../services/ocr/ocr_service.dart';
import '../../services/ocr/ocr_text.dart';
import '../../services/ocr/preview_ocr.dart';
import '../../services/pdf/pdf_native_reader.dart';
import '../../services/editor/letterheads.dart';
import '../../services/layout/page_numbers.dart';
import '../../services/pdf/pdf_service.dart';
import '../../services/rtf/rtf_writer.dart';
import '../../services/udf/udf_reader.dart';
import '../../services/udf/udf_writer.dart';
import '../theme/app_theme.dart';
import 'editor_line_layout.dart';
import 'editor_units.dart';

List<dynamic> _pdfDeltaJson(DocModel model) =>
    DocDeltaMap.modeldenDelta(model).delta.toJson();

class EditorWidget extends StatefulWidget {
  final String? initialFilePath;
  final EvrakFormat? initialFormat;
  final Future<String?> Function()? initialPdfTextLoader;
  final bool isActive;
  final EditorDraft? draft;
  final DocumentRevision? recovery;
  final ValueChanged<String>? onSaved;
  final ValueChanged<String>? onSigned;

  /// A new petition begun from a UYAP case's page: written for that case,
  /// with the case open beside the page, and tied to it when first saved.
  final UyapCaseLink? uyapCase;

  /// Signs the UDF at a path and answers the signed file's path, or null
  /// when the lawyer gave up: the signing dialog, replaced under test.
  @visibleForTesting
  static Future<String?> Function(BuildContext context, String path) sign =
      (context, path) => showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => SigningDialog(filePath: path),
      );

  /// The archive, when the editor is standing in front of one.
  ///
  /// Only the snippet library uses it, and only to offer the passages the
  /// archive already repeats. Null in a bare editor, where that offer is
  /// simply not made.
  final LibraryController? library;

  /// A place double-clicked in the preview, to put the caret at once the
  /// document is in. Each one is taken to once.
  final TextAnchor? reveal;

  /// The program's part of the Dosya menu: new, open, recents, drafts.
  final EditorFileHost? fileHost;

  /// For screenshots and tests: the decision bank to ask.
  @visibleForTesting
  final CaseLaw? caseLaw;

  const EditorWidget({
    super.key,
    this.initialFilePath,
    this.initialFormat,
    this.initialPdfTextLoader,
    this.isActive = true,
    this.draft,
    this.recovery,
    this.onSaved,
    this.onSigned,
    this.uyapCase,
    this.library,
    this.reveal,
    this.fileHost,
    this.caseLaw,
  });

  @override
  State<EditorWidget> createState() => _EditorWidgetState();
}

class _EditorCommandIntent extends Intent {
  final String command;
  const _EditorCommandIntent(this.command);
}

enum _SignedSave { copy, overwrite }

class _EditorWidgetState extends State<EditorWidget>
    with WidgetsBindingObserver {
  /// This editor's own recovery slot; see [DocumentHistory.draftKey].
  final String _draftKey = DocumentHistory.draftKey();

  /// The file this editor's history belongs to: the one it was opened from,
  /// until it is saved somewhere else.
  String? get _documentPath => _savedPath ?? widget.initialFilePath;
  late final DraftRecovery _recovery;
  StreamSubscription<dynamic>? _documentChanges;
  DocModel? _baselineModel;
  List<DocBlock> _baselineProtected = [];
  bool _historyErrorShown = false;
  bool _restoredRevision = false;

  /// Settles [EditorDraft.edited] once typing pauses: comparing the whole
  /// document on every key would be too much.
  Timer? _editedCheck;
  bool _recoveredWithoutSource = false;

  /// Unsaved work an earlier session left in this same file, offered above
  /// the page until it is opened, deleted or waved away.
  DocumentRevision? _leftDraft;
  int _leftDrafts = 0;

  void _historyError(Object e) {
    if (!mounted || _historyErrorShown) return;
    _historyErrorShown = true;
    showNotice(
      context,
      'Belge geçmişine yazılamadı',
      detail: 'Belgeniz yine de kaydedilebilir; yalnız bu sürüm saklanmadı.',
      kind: NoticeKind.error,
    );
  }

  void _watchDocument() {
    _documentChanges?.cancel();
    _documentChanges = _quillController.document.changes.listen((event) {
      _fillTypedBlank(event);
      _typed(event);
      _recovery.changed();
      _checkEditedSoon();
      if (widget.initialFormat == EvrakFormat.pdf) return;
      final text = _quillController.document.toPlainText();
      _spelling.changed(text);
      _citations.changed(text);
    });
    if (widget.initialFormat == EvrakFormat.pdf) return;
    final text = _quillController.document.toPlainText();
    _spelling.changed(text);
    _citations.changed(text);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _recovery.flush();
    }
  }

  static List<int> _encodeRecovery(
    (DocModel, String, List<DocBlock>, String) value,
  ) => utf8.encode(
    jsonEncode({
      "udf": base64Encode(UdfWriter.writeBytes(value.$1)),
      "delta": value.$2,
      "saveFormat": value.$4,
      "protected": base64Encode(
        UdfWriter.writeBytes(DocModel(blocks: value.$3)),
      ),
    }),
  );
  Future<void> _writeRecovery() async {
    if (!_hasChanges) {
      await DocumentHistory.instance.clearRecovery(_draftKey);
      return;
    }
    final bytes = await compute(_encodeRecovery, (
      _currentModel(),
      _deltaSnapshot(),
      _korunanBloklar,
      (_savedFormat ?? widget.initialFormat ?? EvrakFormat.udf)
          .defaultExtension,
    ));
    final path = _documentPath;
    await DocumentHistory.instance.capture(
      document: _draftKey,
      name: path != null
          ? p.basename(path)
          : widget.recovery?.name ??
                "Yeni belge.${(_savedFormat ?? widget.initialFormat ?? EvrakFormat.udf).defaultExtension}",
      sourcePath: path,
      format: "rich-draft",
      bytes: bytes,
      kind: "recovery",
    );
  }

  /// Opens a draft left by another session, then moves it into this editor's
  /// own slot. The old slot goes only once the new one is written, so a crash
  /// in between leaves one draft or the other, never neither.
  Future<void> _recover(DocumentRevision draft) async {
    if (!await _restoreRevision(draft) || draft.document == _draftKey) return;
    if (!await _recovery.flush()) return;
    try {
      await DocumentHistory.instance.clearRecovery(draft.document);
    } catch (e) {
      _historyError(e);
    }
  }

  /// Looks for drafts an earlier session left in the file just opened.
  Future<void> _findLeftDrafts() async {
    final path = widget.initialFilePath;
    if (path == null || widget.recovery != null) return;
    try {
      final drafts = await DocumentHistory.instance.recoveriesFor(path);
      if (!mounted) return;
      setState(() {
        _leftDraft = drafts.firstOrNull;
        _leftDrafts = drafts.length;
      });
    } catch (_) {
      // The file opens either way; the homepage still lists the drafts.
    }
  }

  Future<void> _leftDraftMenu() async {
    final draft = _leftDraft;
    if (draft == null) return;
    final action = await askLeftDraft(context, draft, _leftDrafts);
    if (action == null || !mounted) return;
    if (action == LeftDraftAction.delete) {
      try {
        await DocumentHistory.instance.clearRecovery(draft.document);
      } catch (e) {
        _historyError(e);
      }
    } else {
      if (_hasChanges) {
        final choice = await confirmReplaceEdits(context, 'Taslak');
        if (choice == null || !mounted) return;
        if (choice == ReplaceChoice.saveFirst && !await _save()) return;
      }
      await _recover(draft);
    }
    await _findLeftDrafts();
  }

  Future<bool> _restoreRevision(DocumentRevision entry) async {
    final sourceFailed = _loadError != null;
    setState(() => _isLoading = true);
    try {
      final bytes = await DocumentHistory.instance.read(entry);
      String? delta;
      List<DocBlock>? protected;
      List<int> content = bytes;
      var format = EvrakFormat.fromExtension(entry.format);
      if (entry.format == "rich-draft") {
        final snapshot = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        delta = snapshot["delta"] as String;
        final preferred = EvrakFormat.fromExtension(
          snapshot["saveFormat"] as String? ?? 'udf',
        );
        if (widget.initialFilePath == null &&
            [
              EvrakFormat.udf,
              EvrakFormat.docx,
              EvrakFormat.text,
            ].contains(preferred)) {
          _savedFormat = preferred;
        }
        content = base64Decode(snapshot["udf"] as String);
        format = EvrakFormat.udf;
        protected = (await ConverterService.extractDocModel(
          base64Decode(snapshot["protected"] as String),
          EvrakFormat.udf,
        ))?.blocks;
      }
      final model = await ConverterService.extractDocModel(
        Uint8List.fromList(content),
        format,
      );
      if (model == null) throw const FormatException("Sürüm okunamadı.");
      await DocumentFonts.loadEditorFamilies(
        DocumentFonts.modelFamilies(model),
      );
      if (!mounted) return false;
      final mapped = DocDeltaMap.modeldenDelta(model);
      final metadata = _sourceModel?.metadata ?? const <String, dynamic>{};
      _sourceModel = DocModel(
        blocks: model.blocks,
        styles: model.styles,
        pageProperties: model.pageProperties,
        pageRegions: model.pageRegions,
        metadata: metadata,
      );
      _korunanBloklar = protected ?? mapped.korunanlar;
      _pageProperties = model.pageProperties;
      _quillController.document = delta == null
          ? Document.fromDelta(mapped.delta)
          : Document.fromJson(jsonDecode(delta) as List);
      _loadRegions(model);
      _loadedDelta = null;
      _loadedTableRevision = _tableRevision;
      _focusedCell = null;
      _restoredRevision = true;
      _loadError = null;
      if (sourceFailed) _recoveredWithoutSource = true;
      _watchDocument();
      _recovery.changed();
      _checkEditedSoon();
      setState(() {});
      return true;
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Sürüm açılamadı',
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _history() async {
    final path = _documentPath;
    if (path == null) {
      showNotice(
        context,
        'Bu belge henüz kaydedilmedi',
        detail: 'Geçmiş, ilk kayıttan itibaren tutulur.',
      );
      return;
    }
    final entry = await showDocumentVersions(
      context,
      document: DocumentHistory.documentKey(path),
      title: p.basename(path),
      // What the editor holds, unsaved edits included: that is what the
      // reader is looking at while choosing.
      currentText: _loadError == null
          ? () async => _currentModel().toPlainText()
          : null,
      restoreLabel: 'Editöre yükle',
      restoreHint:
          'Seçilen sürüm editöre kaydedilmemiş değişiklik olarak gelir; siz '
          'kaydedene kadar dosya değişmez.',
    );
    if (entry == null || !mounted) return;
    if (_hasChanges) {
      final choice = await confirmReplaceEdits(context, 'Seçilen sürüm');
      if (choice == null || !mounted) return;
      if (choice == ReplaceChoice.saveFirst && !await _save()) return;
      if (!mounted) return;
    }
    if (await _restoreRevision(entry) && mounted) {
      showNotice(
        context,
        '${draftDate(entry.created)} sürümü editöre yüklendi',
        detail: 'Dosyada kalıcı olması için kaydedin.',
        kind: NoticeKind.success,
      );
    }
  }

  /// Keeps [bytes] in the history of the file at [path]. False when that
  /// could not be done; the reader has been told once.
  Future<bool> _captureVersion(
    String path,
    List<int> bytes,
    String format,
    String kind,
  ) async {
    try {
      await DocumentHistory.instance.capture(
        document: DocumentHistory.documentKey(path),
        name: p.basename(path),
        sourcePath: path,
        format: format,
        bytes: bytes,
        kind: kind,
      );
      return true;
    } catch (e) {
      _historyError(e);
      return false;
    }
  }

  late _DocumentController _quillController;

  /// Header and footer, each its own little document. Keyed the way UDF names
  /// them, so a file that already carries one is edited in place rather than
  /// replaced by a second.
  final _regions = <String, QuillController>{};
  final _regionFocus = <String, FocusNode>{};
  final _regionChanges = <String, StreamSubscription<DocChange>>{};
  final _regionKorunan = <String, List<DocBlock>>{};
  String? _focusedRegion;

  /// How tall the header and footer are, in points, as the printed page
  /// measures them (see [_measureRegions]); the text area follows.
  ({double? header, double? footer}) _regionHeights = (
    header: null,
    footer: null,
  );
  Timer? _regionMeasure;
  int _regionGeneration = 0;

  /// What the header and footer carry besides their text, as UDF keeps it:
  /// page numbering and the page a header starts on (see [PageNumbering]).
  Map<String, Map<String, String>> _regionAttrs = {};
  String _baselineRegionAttrs = '{}';

  static Map<String, Map<String, String>> _attrsOf(Object? raw) => {
    if (raw is Map)
      for (final e in raw.entries)
        if (e.value is Map)
          '${e.key}': {
            for (final a in (e.value as Map).entries) '${a.key}': '${a.value}',
          },
  };

  /// The page whose header or footer is the one being edited; every other
  /// page shows a copy of it, read from the same document.
  final _livePage = <String, int>{};
  final _regionCopies = <String, QuillController>{};

  /// The cell of a table that holds the cursor, if any.
  QuillController? _focusedCell;

  /// Tables live beside the delta, so a cell edit does not show up in it.
  /// Counting the edits is what tells the editor there is something to save.
  int _tableRevision = 0;
  int _baselineTableRevision = 0;
  String _baselineRegions = '';
  String? _loadedRegions;

  /// What the toolbar and the formatting shortcuts act on. Typing in the
  /// header and pressing Ctrl+B has to embolden the header, not whatever was
  /// last selected in the body.
  QuillController get _active =>
      _focusedCell ?? _regions[_focusedRegion] ?? _quillController;

  /// Remembers the cell the cursor was last in, even once the cursor has left
  /// it for the toolbar.
  ///
  /// Picking a font or a size opens a dialog, and a dialog takes the focus,
  /// so by the time the choice is made the cell has none. Dropping the cell
  /// the moment it is no longer focused sent every one of those choices to
  /// the document instead — nothing in a table could be restyled. The cell is
  /// let go of when another editor is typed in, or when the cells themselves
  /// are rebuilt.
  void _cellFocused(QuillController? controller) {
    if (!mounted) return;
    // This one follows the cursor exactly: it decides who holds the keyboard.
    _quillController.cellHasCursor = controller != null;
    if (controller == null) return;
    setState(() => _focusedCell = controller);
  }

  /// Set for the instant a click is travelling out from inside a table.
  ///
  /// Flutter hands a pointer to the innermost thing it lands on first, so a
  /// table says so before the body hears about the same click.
  bool _clickedInTable = false;

  /// Puts the cursor in the body when the body is clicked.
  ///
  /// Quill moves the focus to an editor from inside `requestKeyboard`, and
  /// only when its own focus node reports none. A cell is a small editor
  /// drawn inside this one, so while a cell held the cursor that node
  /// reported focus and the body's own click never moved it: the caret
  /// stayed in the cell and everything typed went on landing there.
  void _bodyClicked(PointerDownEvent _) {
    if (_clickedInTable) {
      _clickedInTable = false;
      return;
    }
    if (_focusedCell != null) _editorFocus.requestFocus();
  }

  void _cellsGone() {
    if (!mounted || _focusedCell == null) return;
    _quillController.cellHasCursor = false;
    setState(() => _focusedCell = null);
  }

  /// Takes a table out of the document. The block itself stays in the list
  /// the mapper keeps aside, unreferenced; nothing reads it again, and the
  /// document the writer is handed no longer has the table in it.
  void _deleteTable(int documentOffset) {
    if (documentOffset < 0 ||
        documentOffset >= _quillController.document.length) {
      return;
    }
    _quillController.cellHasCursor = false;
    _quillController.replaceText(
      documentOffset,
      1,
      '',
      TextSelection.collapsed(offset: documentOffset),
    );
    if (mounted) setState(() => _focusedCell = null);
  }

  void _tableChanged(int index, DocBlock updated) {
    if (index < 0 || index >= _korunanBloklar.length) return;
    _korunanBloklar[index] = updated;
    _recovery.changed();
    _checkEditedSoon();
    // Enough to light up the save button once; rebuilding on every keystroke
    // inside a cell would cost a frame for nothing.
    final first = _tableRevision == _baselineTableRevision;
    _tableRevision++;
    if (first && mounted) setState(() {});
  }

  List<DocBlock> _korunanBloklar = [];
  DocPageProperties _pageProperties = const DocPageProperties();
  bool _isLoading = false;
  int _loadGeneration = 0;
  DocModel? _sourceModel;
  String? _loadedDelta;

  /// The table count at the moment the document was read. Cell edits never
  /// show up in the delta, so without this a document whose only change was
  /// inside a table would be saved from the untouched source.
  int _loadedTableRevision = 0;
  String? _loadError;
  String? _currentTitle;
  bool _signatureNoticeShown = false;

  /// Whether the file this editor was opened from carries a signature. Kept
  /// apart from the document in memory, which stops being signed as soon as it
  /// is saved somewhere else — the original on disk must stay protected either
  /// way.
  bool _sourceSigned = false;
  bool _isSaving = false;
  bool _isPrinting = false;
  final _editorFocus = FocusNode(debugLabel: 'document-editor');
  final _editorKey = GlobalKey<EditorState>();

  /// The last [EditorWidget.reveal] taken to.
  TextAnchor? _revealed;

  /// Puts the caret where the preview was double-clicked and brings that
  /// line well inside the view, not just to its edge.
  void _reveal() {
    final anchor = widget.reveal;
    if (anchor == null ||
        identical(anchor, _revealed) ||
        _isLoading ||
        _loadError != null) {
      return;
    }
    _revealed = anchor;
    final document = _quillController.document;
    final offset = math.min(
      anchor.locate(document.toPlainText()),
      math.max(0, document.length - 1),
    );
    _quillController.updateSelection(
      TextSelection.collapsed(offset: offset),
      ChangeSource.local,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final editor = _editorKey.currentState?.renderEditor;
      if (editor != null && editor.attached) {
        final caret = editor.getLocalRectForCaret(TextPosition(offset: offset));
        final margin = math.min(MediaQuery.sizeOf(context).height / 4, 220.0);
        // A jump, and before the focus: an editor gaining focus brings its
        // caret just inside the edge of the view, which would cut short an
        // animation of ours still under way. Found already in view, the
        // caret is left where this puts it.
        editor.showOnScreen(
          rect: Rect.fromLTRB(
            caret.left,
            caret.top - margin,
            caret.right,
            caret.bottom + margin,
          ),
        );
      }
      if (widget.isActive) _editorFocus.requestFocus();
    });
  }

  /// What the spelling checker last found, redrawn when it finds something
  /// else. Asked again a moment after the typing stops.
  late final _spelling = SpellingMarks()..addListener(_spellingChanged);

  void _spellingChanged() {
    if (mounted) setState(() {});
  }

  /// The laws the document cites, drawn as something to press.
  late final _citations = CitationMarks(
    onTap: _showArticle,
    // Left out when the reader turned decisions off, which is what
    // stops them being marked at all.
    onTapDecision: _legal.decisions ? _showDecision : null,
  )..addListener(_spellingChanged);

  /// Fetched once per decision and then kept, the answer either way.
  late final _caseLaw = widget.caseLaw ?? CaseLaw();

  /// Whether the list of what this filing rests on is open at the foot.
  bool _citationListOpen = false;

  /// What the filing rests on, at the foot of the page: where a reader looks
  /// for the state of a document. In the toolbar it was hard to find. Only
  /// there when the filing cites something.
  Widget? _citationStatus(BuildContext context) {
    final count = CitationList.counts(_citations.marks, _citations.decisions);
    final total = count.laws + count.decisions;
    if (total == 0) return null;
    final scheme = Theme.of(context).colorScheme;
    final detail = [
      if (count.laws > 0) '${count.laws} kanun maddesi',
      if (count.decisions > 0) '${count.decisions} karar',
    ].join(', ');
    return Tooltip(
      message:
          '$detail · ${_citationListOpen ? 'dayanakları gizle' : 'dayanakları göster'}',
      child: TextButton.icon(
        key: const ValueKey('citation-status'),
        onPressed: () => setState(() => _citationListOpen = !_citationListOpen),
        icon: const Icon(Icons.balance_outlined, size: 15),
        label: Text('$total dayanak'),
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          backgroundColor: _citationListOpen
              ? scheme.primary.withValues(alpha: .12)
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 24),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: Theme.of(context).textTheme.labelMedium
              ?.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  /// The list itself, between the page and the bar, so the page gives way
  /// and the bar stays where it was. Gone with the last citation.
  Widget? _citationDrawer() {
    if (!_citationListOpen ||
        (_citations.marks.isEmpty && _citations.decisions.isEmpty)) {
      return null;
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: CitationList(
        laws: _citations.marks,
        decisions: _citations.decisions,
        onLaw: _showArticle,
        onDecision: _showDecision,
        onClose: () => setState(() => _citationListOpen = false),
      ),
    );
  }

  /// Whether the case-law search is open beside the page.
  ///
  /// Beside rather than elsewhere: a precedent is looked for while the
  /// paragraph that needs it is being written, and leaving the document to
  /// go and find one means coming back having lost the thread.
  bool _caseLawOpen = false;

  /// The UYAP case the document is written for, beside the page.
  bool _uyapOpen = false;
  double _uyapWidth = 380;
  late final _uyap = UyapCasePanelController()..onSaved = _uyapSaved;

  /// A document of that case, open beside the page to write from.
  String? _evrakPath;
  String _evrakTitle = '';
  double _evrakWidth = 520;

  void _toggleUyap() {
    setState(() => _uyapOpen = !_uyapOpen);
    if (_uyapOpen) unawaited(_uyap.bind(_documentPath));
  }

  /// A UYAP document saved where Folio searches: the folder becomes one of
  /// the searched ones the first time, so the reports and petitions are
  /// found by what they say.
  void _uyapSaved(File file) {
    final library = widget.library;
    if (library == null) return;
    unawaited(searchUyapFolder(library).catchError((Object _) => false));
  }

  Widget _evrakPane(BuildContext context) {
    final path = _evrakPath!;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _evrakTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Ayrı pencerede aç',
                  onPressed: () {
                    unawaited(openPreviewWindow(path));
                    setState(() => _evrakPath = null);
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 19),
                ),
                IconButton(
                  tooltip: 'Kapat',
                  onPressed: () => setState(() => _evrakPath = null),
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FilePreview(key: ValueKey(path), path: path),
          ),
        ],
      ),
    );
  }

  /// Shows the decision a citation points at, over the document.
  void _showDecision(DecisionCitation citation, Offset at) {
    if (!mounted) return;
    DecisionPanel.show(
      context,
      citation: citation,
      lookup: () => _caseLaw.lookup(citation),
      at: at,
    );
  }

  /// Nothing is marked and nothing is fetched when the reader has turned the
  /// articles off.
  CitationMarks? get _citationMarks =>
      widget.initialFormat != EvrakFormat.pdf && _legal.articles
      ? _citations
      : null;

  /// Fetched once per law and then kept, so the second citation of the same
  /// law opens without the network.
  final _legislation = Legislation();

  /// The terms of art, read from the app's own copy. Null until it is read,
  /// and left null when the reader has turned the dictionary off.
  LegalTerms? _terms;

  final _legal = LegalSettings.instance;

  Future<void> _loadTerms() async {
    if (!_legal.dictionary || _terms != null) return;
    try {
      final loaded = await LegalTerms.load();
      if (mounted) setState(() => _terms = loaded);
    } on Object {
      // No dictionary, no entry in the menu.
    }
  }

  /// The word the caret sits in, with the two after it, so a term of more
  /// than one word — "aciz vesikası" — can be recognised.
  List<String> _wordsAt(int offset) {
    final text = _quillController.document.toPlainText();
    if (offset < 0 || offset > text.length) return const [];
    final letter = RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]');
    var start = offset;
    while (start > 0 && letter.hasMatch(text[start - 1])) {
      start--;
    }
    var end = start;
    var words = 0;
    while (end < text.length && words < 3) {
      while (end < text.length && letter.hasMatch(text[end])) {
        end++;
      }
      words++;
      if (end >= text.length || text[end] != ' ') break;
      end++;
    }
    return text
        .substring(start, end)
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  void _showTerm(TermMatch term, Offset at) {
    if (mounted) TermPanel.show(context, term: term, at: at);
  }

  /// Shows the article a citation points at, over the document.
  ///
  /// The card is put up before the text has arrived and fills itself in, so
  /// the press answers at once even when the law has to be fetched.
  void _showArticle(Citation citation, Offset at) {
    if (!mounted) return;
    ArticlePanel.show(
      context,
      citation: citation,
      lookup: () => _legislation.lookup(citation),
      at: at,
    );
  }

  /// The usual right-click menu, with what to write instead at the top of it
  /// when the click landed on a word the checker did not know.
  ///
  /// The suggestions are fetched as the menu opens rather than kept for every
  /// underlined word in the document: only one of them is ever asked about,
  /// and asking then costs nothing a reader would notice.
  Widget _contextMenu(BuildContext context, QuillRawEditorState state) {
    Widget toolbar(List<ContextMenuButtonItem> items) => TextFieldTapRegion(
      child: AdaptiveTextSelectionToolbar.buttonItems(
        buttonItems: items,
        anchors: state.contextMenuAnchors,
      ),
    );

    final selection = state.controller.selection;
    // What the reader pressed on may be a term of art. Offered before the
    // spelling suggestions, because a term the checker does not know is
    // exactly the word most likely to be both.
    final term = selection.isCollapsed && _legal.dictionary
        ? _terms?.matchPhrase(_wordsAt(selection.baseOffset))
        : null;
    final termItems = <ContextMenuButtonItem>[
      // The selection, read aloud.
      if (speechAvailable &&
          !selection.isCollapsed &&
          identical(state.controller, _quillController))
        ContextMenuButtonItem(
          label: 'Sesli oku',
          onPressed: () {
            ContextMenuController.removeAny();
            unawaited(_readAloud(restart: true));
          },
        ),
      if (term != null)
        ContextMenuButtonItem(
          label: '“${term.term}” ne demek?',
          onPressed: () {
            final at = state.contextMenuAnchors.primaryAnchor;
            ContextMenuController.removeAny();
            _showTerm(term, at);
          },
        ),
    ];

    final mark = selection.isCollapsed
        ? _spelling.at(selection.baseOffset)
        : null;
    if (mark == null) {
      return toolbar([...termItems, ...state.contextMenuButtonItems]);
    }

    final word = state.controller.document.getPlainText(
      mark.start,
      mark.length,
    );
    return FutureBuilder<List<String>>(
      future: SpellCheck.instance.suggest(word),
      builder: (context, snapshot) {
        final suggestions = snapshot.data ?? const <String>[];
        return toolbar([
          ...termItems,
          for (final suggestion in suggestions.take(5))
            ContextMenuButtonItem(
              label: suggestion,
              onPressed: () {
                ContextMenuController.removeAny();
                _quillController.replaceText(
                  mark.start,
                  mark.length,
                  suggestion,
                  TextSelection.collapsed(
                    offset: mark.start + suggestion.length,
                  ),
                );
              },
            ),
          ContextMenuButtonItem(
            label: 'Sözlüğe ekle',
            onPressed: () {
              ContextMenuController.removeAny();
              unawaited(
                SpellCheck.instance
                    .learn(word)
                    .then(
                      (_) => _spelling.now(
                        _quillController.document.toPlainText(),
                      ),
                    ),
              );
            },
          ),
          ...state.contextMenuButtonItems,
        ]);
      },
    );
  }

  /// The Dosya menu, opened from the keyboard by Ctrl+Shift+S.
  final _fileMenu = MenuController();
  String? _savedPath;
  EvrakFormat? _savedFormat;
  String _baselineDelta = '';
  DocPageProperties _baselinePage = const DocPageProperties();
  String _deltaSnapshot() =>
      jsonEncode(_quillController.document.toDelta().toJson());
  String _regionSnapshot() => jsonEncode({
    for (final e in _regions.entries)
      e.key: e.value.document.toDelta().toJson(),
  });

  /// Opens a header or footer for editing, replacing whatever was there.
  void _openRegion(String key, List<DocBlock> blocks) {
    final mapped = DocDeltaMap.modeldenDelta(
      DocModel(
        blocks: blocks,
        metadata: _sourceModel?.metadata['tabRules'] == 'word'
            ? const {'tabRules': 'word'}
            : const {},
      ),
    );
    _regionKorunan[key] = mapped.korunanlar;
    final controller = _regions.putIfAbsent(
      key,
      () => ClipboardController(target: PasteTarget.band)
        ..tables = (() => _regionKorunan[key] ?? const [])
        ..documentMetadata = (() => _sourceModel?.metadata ?? const {})
        ..onPasted = _pasted,
    );
    _regionFocus.putIfAbsent(key, () {
      final node = FocusNode(debugLabel: 'document-$key');
      // The toolbar follows the cursor, so it has to know where the cursor is.
      node.addListener(() {
        if (!mounted) return;
        if (node.hasFocus) {
          _cellsGone();
          setState(() => _focusedRegion = key);
        } else if (_focusedRegion == key) {
          setState(() => _focusedRegion = null);
        }
      });
      return node;
    });
    controller.document = Document.fromDelta(mapped.delta);
    _regionChanges[key]?.cancel();
    _regionChanges[key] = controller.document.changes.listen((_) {
      _recovery.changed();
      _checkEditedSoon();
      _measureRegionsSoon();
    });
  }

  void _closeRegion(String key) {
    _regionChanges.remove(key)?.cancel();
    _regions.remove(key)?.dispose();
    _regionCopies.remove(key);
    _livePage.remove(key);
    _regionFocus.remove(key)?.dispose();
    _regionKorunan.remove(key);
    if (_focusedRegion == key) _focusedRegion = null;
  }

  /// Rebuilds every band from a document that has just been opened.
  void _loadRegions(DocModel model) {
    for (final key in _regions.keys.toList()) {
      if (!model.pageRegions.containsKey(key)) _closeRegion(key);
    }
    for (final entry in model.pageRegions.entries) {
      _openRegion(entry.key, entry.value);
    }
    _loadedRegions = _regionSnapshot();
    _regionAttrs = _attrsOf(model.metadata['pageRegionAttrs']);
    _measureRegions();
  }

  /// Measures the header and footer as the printed page lays them out, and
  /// sets the text area by them, as UYAP does: text starts below a header
  /// only where the header runs past the top margin.
  Future<void> _measureRegions() async {
    _regionMeasure?.cancel();
    final generation = ++_regionGeneration;
    final regions = _currentRegions();
    final heights = await PdfService.regionHeights(
      DocModel(
        pageProperties: _pageProperties,
        pageRegions: regions,
        metadata: _sourceModel?.metadata ?? const {},
        blocks: const [],
      ),
    );
    if (!mounted || generation != _regionGeneration) return;
    if (heights != _regionHeights) setState(() => _regionHeights = heights);
  }

  /// After a pause in typing: every keystroke in a header would otherwise
  /// lay out a PDF page.
  void _measureRegionsSoon() {
    _regionMeasure?.cancel();
    _regionMeasure = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _measureRegions();
    });
  }

  /// A header or footer's height before it has been measured: a row a line.
  double? _regionHeight(String kind) {
    if (!_regions.keys.any((k) => k.endsWith(kind))) return null;
    final measured = kind == 'header'
        ? _regionHeights.header
        : _regionHeights.footer;
    if (measured != null) return measured;
    var rows = 0;
    for (final e in _regions.entries) {
      if (!e.key.endsWith(kind)) continue;
      final n = e.value.document.root.children.length;
      if (n > rows) rows = n;
    }
    return rows * 14.0;
  }

  /// Which of the document's headers or footers page [page] (from 0)
  /// shows, as the printed page picks: the first page's own, then the odd
  /// or even pages', then the one for every page.
  String? _regionKey(String kind, int page) {
    final number = page + 1;
    for (final key in [
      if (number == 1) 'first_page_$kind',
      '${number.isOdd ? 'odd' : 'even'}_page_$kind',
      kind,
    ]) {
      if (_regions.containsKey(key)) return key;
    }
    return null;
  }

  /// Header and footer as the document model wants them. Untouched bands are
  /// handed back exactly as they were read, since a trip through the editor
  /// keeps only what the editor understands.
  Map<String, List<DocBlock>> _currentRegions() {
    final source =
        _sourceModel?.pageRegions ?? const <String, List<DocBlock>>{};
    if (_loadedRegions != null && _regionSnapshot() == _loadedRegions) {
      return source;
    }
    return {
      for (final e in _regions.entries)
        e.key: DocDeltaMap.deltadanModel(
          e.value.document.toDelta(),
          korunanlar: _regionKorunan[e.key] ?? const [],
        ).blocks,
    };
  }

  List<Object> _pageValues(DocPageProperties page) => [
    page.marginLeft,
    page.marginRight,
    page.marginTop,
    page.marginBottom,
    page.landscape,
    page.headerOffset,
    page.footerOffset,
  ];
  bool get _hasChanges =>
      !_isLoading &&
      _loadError == null &&
      (_restoredRevision ||
          _deltaSnapshot() != _baselineDelta ||
          _regionSnapshot() != _baselineRegions ||
          jsonEncode(_regionAttrs) != _baselineRegionAttrs ||
          _tableRevision != _baselineTableRevision ||
          jsonEncode(_pageValues(_pageProperties)) !=
              jsonEncode(_pageValues(_baselinePage)));
  void _checkEditedSoon() {
    if (widget.draft == null) return;
    _editedCheck?.cancel();
    _editedCheck = Timer(const Duration(milliseconds: 300), () {
      if (mounted) widget.draft?.edited.value = _hasChanges;
    });
  }

  void _markSaved() {
    _checkEditedSoon();
    _restoredRevision = false;
    _baselineDelta = _deltaSnapshot();
    _baselineRegions = _regionSnapshot();
    _baselineRegionAttrs = jsonEncode(_regionAttrs);
    _baselineTableRevision = _tableRevision;
    _baselinePage = _pageProperties;
    _baselineModel = _currentModel();
    _baselineProtected = List.of(_korunanBloklar);
  }

  Future<void> _discard() async {
    _checkEditedSoon();
    _restoredRevision = false;
    final model = _baselineModel;
    if (model != null) {
      _sourceModel = model;
      _korunanBloklar = List.of(_baselineProtected);
      _tableRevision = _baselineTableRevision;
      _loadedDelta = _baselineDelta;
      _loadedTableRevision = _tableRevision;
      _focusedCell = null;
    }
    _quillController.document = Document.fromJson(
      jsonDecode(_baselineDelta) as List,
    );
    final regions = jsonDecode(_baselineRegions) as Map<String, dynamic>;
    for (final key in _regions.keys.toList()) {
      if (!regions.containsKey(key)) _closeRegion(key);
    }
    regions.forEach((key, delta) {
      _openRegion(
        key,
        DocDeltaMap.deltadanModel(Delta.fromJson(delta as List)).blocks,
      );
    });
    _regionAttrs = _attrsOf(jsonDecode(_baselineRegionAttrs));
    setState(() => _pageProperties = _baselinePage);
    _measureRegions();
    _watchDocument();
    await _recovery.clear();
  }

  bool _showHorizontalRuler = true;

  /// One beside every page, measuring it and setting its top and bottom
  /// margins; off on a phone, where there is no room for it.
  bool _showVerticalRuler = true;

  Map<ShortcutActivator, Intent> get _shortcuts => {
    for (final entry in <(LogicalKeyboardKey, bool), String>{
      (LogicalKeyboardKey.keyS, false): 'save',
      (LogicalKeyboardKey.keyS, true): 'saveAs',
      (LogicalKeyboardKey.keyF, false): 'find',
      (LogicalKeyboardKey.keyH, false): 'replace',
      (LogicalKeyboardKey.keyB, false): 'bold',
      (LogicalKeyboardKey.keyI, false): 'italic',
      (LogicalKeyboardKey.keyU, false): 'underline',
      (LogicalKeyboardKey.keyV, false): 'paste',
      (LogicalKeyboardKey.keyZ, false): 'undo',
      (LogicalKeyboardKey.keyY, false): 'redo',
      (LogicalKeyboardKey.keyM, false): 'indent',
      (LogicalKeyboardKey.keyM, true): 'outdent',
      (LogicalKeyboardKey.keyL, true): 'bullet',
      (LogicalKeyboardKey.keyP, false): 'print',
      (LogicalKeyboardKey.keyL, false): 'left',
      (LogicalKeyboardKey.keyE, false): 'center',
      (LogicalKeyboardKey.keyR, false): 'right',
      (LogicalKeyboardKey.keyJ, false): 'justify',
      (LogicalKeyboardKey.keyZ, true): 'redo',
      (LogicalKeyboardKey.digit7, true): 'number',
      (LogicalKeyboardKey.digit8, true): 'bullet',
      // Ctrl+J iki yana yaslamada, Tab tabloda. Boşluk hem boş hem de her
      // editörde "buraya bir şey ekle" tuşu.
      (LogicalKeyboardKey.space, false): 'snippets',
    }.entries)
      EditorShortcut(
        entry.key.$1,
        control: !Platform.isMacOS,
        meta: Platform.isMacOS,
        shift: entry.key.$2,
      ): _EditorCommandIntent(
        entry.value,
      ),
    // Alt+F1…F12 writes the passage put on that key. Not Alt+F4: Windows
    // closes the window with it before anything else can.
    for (final key in Snippet.hotkeys)
      SingleActivator(_functionKeys[key - 1], alt: true): _EditorCommandIntent(
        'hotkey:$key',
      ),
  };

  static const _functionKeys = [
    LogicalKeyboardKey.f1,
    LogicalKeyboardKey.f2,
    LogicalKeyboardKey.f3,
    LogicalKeyboardKey.f4,
    LogicalKeyboardKey.f5,
    LogicalKeyboardKey.f6,
    LogicalKeyboardKey.f7,
    LogicalKeyboardKey.f8,
    LogicalKeyboardKey.f9,
    LogicalKeyboardKey.f10,
    LogicalKeyboardKey.f11,
    LogicalKeyboardKey.f12,
  ];

  void _command(String command) {
    if (command == 'paste') {
      debugPrint(
        'Folio paste shortcut: active=${widget.isActive}, '
        'loading=$_isLoading, loadError=${_loadError != null}',
      );
    }
    if (!widget.isActive || _isLoading || _loadError != null) return;
    switch (command) {
      case 'save':
        _save();
      case 'saveAs':
        if (!_isSaving) _fileMenu.open();
      case 'find':
        _find();
      case 'replace':
        _find(replace: true);
      case 'bold':
        _toggle(Attribute.bold);
      case 'italic':
        _toggle(Attribute.italic);
      case 'underline':
        _toggle(Attribute.underline);
      case 'paste':
        // The outer shortcut owns Ctrl+V explicitly. Depending on focus,
        // Quill's overridable PasteTextAction could otherwise resolve to the
        // plain-text action above the editor before reaching our controller.
        // ignore: experimental_member_use
        unawaited(_active.clipboardPaste());
      case 'undo':
        _active.undo();
      case 'indent':
        _active.indentSelection(true);
      case 'outdent':
        _active.indentSelection(false);
      case 'print':
        _print();
      case 'redo':
        _active.redo();
      case 'left':
        _active.formatSelection(Attribute.leftAlignment);
      case 'center':
        _active.formatSelection(Attribute.centerAlignment);
      case 'right':
        _active.formatSelection(Attribute.rightAlignment);
      case 'justify':
        _active.formatSelection(Attribute.justifyAlignment);
      case 'number':
        _toggle(Attribute.ol);
      case 'bullet':
        _toggle(Attribute.ul);
      case 'snippets':
        unawaited(_snippets());
      case final hotkey when hotkey.startsWith('hotkey:'):
        unawaited(_hotkey(int.parse(hotkey.substring('hotkey:'.length))));
    }
  }

  /// The kept passages, loaded once so that Tab can decide at once whether
  /// the word before it is a keyword.
  SnippetStore? _snippetStore;

  /// Tab after a passage's keyword writes the passage in its place — its
  /// body, with its formatting, never its name. Any other Tab is left to
  /// Quill: a tab in the text, a step in a list.
  KeyEventResult? _onKey(KeyEvent event, Node? node) {
    if (_suggestions.isOpen) {
      final handled = _suggestionKey(event);
      if (handled != null) return handled;
    }
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.tab) {
      return null;
    }
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed ||
        keys.isControlPressed ||
        keys.isAltPressed ||
        keys.isMetaPressed) {
      return null;
    }
    final store = _snippetStore;
    final controller = _quillController;
    final selection = controller.selection;
    if (store == null || !selection.isValid || !selection.isCollapsed) {
      return null;
    }
    final text = controller.document.toPlainText();
    final at = selection.baseOffset;
    final letter = RegExp(r'[\p{L}\p{N}_]', unicode: true);
    // Only at the end of a word: Tab inside one is a tab.
    if (at < text.length && letter.hasMatch(text[at])) return null;
    final word = RegExp(
      r'[\p{L}\p{N}_]+$',
      unicode: true,
    ).firstMatch(text.substring(0, at))?.group(0);
    if (word == null) return null;
    final snippet = store.byKeyword(word);
    if (snippet == null) return null;
    unawaited(_expand(snippet, at - word.length, word.length));
    return KeyEventResult.handled;
  }

  /// Completions under the caret, from the snippets, the lawyer's profile,
  /// the built-in phrases and what was learned; see [SuggestionEngine].
  late final _suggestions = SuggestionPopup(onTake: _take)
    ..onDismissed = _suppressHere;
  Timer? _suggestTimer;

  /// Where the word Esc closed the list in begins; the list stays closed
  /// until the next word.
  int? _suppressedWord;

  /// The change a taken suggestion makes is not typing, and must not open
  /// the list again.
  bool _skipNextChange = false;

  static final _wordEnd = RegExp(r'[\p{L}\p{N}]+$', unicode: true);

  /// Only typing opens the list, and only once typing pauses.
  void _typed(DocChange event) {
    if (_skipNextChange) {
      _skipNextChange = false;
      return;
    }
    final typing =
        event.source == ChangeSource.local &&
        event.change.operations.any(
          (op) =>
              op.isInsert &&
              op.data is String &&
              !(op.data as String).contains('\n'),
        );
    if (!typing) return _hideSuggestions();
    _suggestTimer?.cancel();
    _suggestTimer = Timer(const Duration(milliseconds: 200), _suggestNow);
  }

  void _hideSuggestions() {
    _suggestTimer?.cancel();
    _suggestions.hide();
  }

  void _suggestNow() {
    if (!mounted ||
        !EditorSettings.instance.suggestions ||
        !_editorFocus.hasFocus) {
      return _hideSuggestions();
    }
    final controller = _quillController;
    final selection = controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return _hideSuggestions();
    }
    final text = controller.document.toPlainText();
    final at = selection.baseOffset;
    if (at > text.length ||
        (at < text.length &&
            RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(text[at]))) {
      return _hideSuggestions();
    }
    final before = text.substring(math.max(0, at - 400), at);
    final word = _wordEnd.firstMatch(before)?.group(0);
    if (word != null && _suppressedWord == at - word.length) {
      return _hideSuggestions();
    }
    _suppressedWord = null;
    final found = SuggestionEngine(
      snippets: _snippetStore,
      profile: LawyerProfile.cached,
      memory: PhraseMemory.cached,
    ).suggest(before);
    final editor = _editorKey.currentState?.renderEditor;
    if (found.isEmpty || editor == null || !editor.attached) {
      return _hideSuggestions();
    }
    final caret = editor.getLocalRectForCaret(TextPosition(offset: at));
    final top = editor.localToGlobal(caret.topLeft);
    final bottom = editor.localToGlobal(caret.bottomLeft);
    _suggestions.show(
      context,
      found,
      caret: bottom,
      lineHeight: bottom.dy - top.dy,
    );
  }

  /// Esc: not again within this word.
  void _suppressHere() {
    _suggestTimer?.cancel();
    final selection = _quillController.selection;
    if (!selection.isValid) return;
    final at = selection.baseOffset;
    final text = _quillController.document.toPlainText();
    final word = _wordEnd.firstMatch(text.substring(0, at))?.group(0);
    _suppressedWord = word == null ? null : at - word.length;
  }

  /// Tab or Enter takes the marked line, the arrows choose, Esc closes; with
  /// the list closed, Enter opens a line as it always does.
  KeyEventResult? _suggestionKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _suggestions.move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _suggestions.move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      SuggestionPopup.dismissActive();
      return KeyEventResult.handled;
    }
    final keys = HardwareKeyboard.instance;
    if ((key == LogicalKeyboardKey.tab ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        event is KeyDownEvent &&
        !keys.isShiftPressed &&
        !keys.isControlPressed &&
        !keys.isAltPressed &&
        !keys.isMetaPressed) {
      final chosen = _suggestions.current;
      if (chosen != null) {
        _take(chosen);
        return KeyEventResult.handled;
      }
    }
    if (_closingKeys.contains(key)) {
      _hideSuggestions();
    }
    return null;
  }

  static final _closingKeys = {
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
    LogicalKeyboardKey.pageUp,
    LogicalKeyboardKey.pageDown,
  };

  /// Writes [suggestion] over the words it completes, in the style around
  /// it and as one step to undo; a snippet is expanded as its keyword would be.
  void _take(Suggestion suggestion) {
    _hideSuggestions();
    final controller = _quillController;
    final selection = controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return;
    final at = selection.baseOffset;
    final start = at - suggestion.typed;
    if (start < 0) return;
    final snippet = suggestion.snippet;
    if (snippet != null) {
      unawaited(_expand(snippet, start, suggestion.typed));
      return;
    }
    _skipNextChange = true;
    controller.updateSelection(
      TextSelection(baseOffset: start, extentOffset: at),
      ChangeSource.local,
    );
    _putText(controller, suggestion.text);
    final learned = suggestion.learned;
    if (learned != null) PhraseMemory.cached?.accepted(learned.key);
    _editorFocus.requestFocus();
  }

  /// What the document just saved at [path] teaches the suggestions.
  void _learnFrom(String path, DocModel model) {
    if (!EditorSettings.instance.learnSaved) return;
    final memory = PhraseMemory.cached;
    if (memory == null) return;
    try {
      memory.learnSaved(path, model.toPlainText());
    } on Object catch (e) {
      debugPrint('Öneriler öğrenilemedi: $e');
    }
  }

  /// Puts [snippet] where its keyword was, in one step to undo.
  Future<void> _expand(Snippet snippet, int start, int length) async {
    final controller = _quillController;
    final body = await _filled(snippet);
    if (body == null || !mounted) return;
    // A blank may have been asked for meanwhile; write only if the keyword
    // is still where it was.
    final text = controller.document.toPlainText();
    if (start + length > text.length ||
        SnippetStore.fold(text.substring(start, start + length)) !=
            SnippetStore.fold(snippet.keyword)) {
      return;
    }
    controller.updateSelection(
      TextSelection(baseOffset: start, extentOffset: start + length),
      ChangeSource.local,
    );
    _putSnippet(controller, body);
    await _snippetStore?.reached(snippet.id);
  }

  /// Alt+F[key]: the passage on that key, where the cursor is — the body,
  /// the header or footer, or a table cell.
  Future<void> _hotkey(int key) async {
    final store = _snippetStore ?? await SnippetStore.shared();
    if (!mounted) return;
    final snippet = store.byHotkey(key);
    if (snippet == null) {
      showNotice(
        context,
        'Alt+F$key bir kalıba atanmamış.',
        detail: 'Ctrl+Space → Kalıplarımı yönet ile atayabilirsiniz.',
      );
      return;
    }
    final into = _active;
    final body = await _filled(snippet);
    if (body == null || !mounted) return;
    _putSnippet(into, body);
    await store.reached(snippet.id);
  }

  /// The passages the reader keeps, over the document.
  ///
  /// Whatever holds the cursor is what is written into — the body, a table
  /// cell, the header — because [_active] already answers that question for
  /// every other command.
  /// The snippet's body with its blanks filled: from the lawyer's profile
  /// where it knows them, from the reader for the rest. Asked only when the
  /// profile leaves something open. Null if the reader backed out.
  Future<Delta?> _filled(Snippet snippet) async {
    if (snippet.blanks.isEmpty) return snippet.body;
    final profile = (await LawyerProfile.load()).blanks();
    if (!mounted) return null;
    final known = {for (final blank in snippet.blanks) blank: ?profile[blank]};
    if (known.length == snippet.blanks.length) {
      return snippet.withBlanks(known);
    }
    final given = await SnippetFill.ask(context, snippet, known: known);
    if (given == null || !mounted) return null;
    return snippet.withBlanks(given);
  }

  Future<void> _snippets() async {
    final into = _active;
    final selection = into.selection;
    if (!selection.isValid) return;
    final store = await SnippetStore.shared();
    final profile = await LawyerProfile.load();
    if (!mounted) return;

    final chosen = await SnippetPalette.show(
      context,
      store: store,
      profile: profile.entries(),
      profileSet: profile.lawyer != null,
      canHarvest: widget.library != null,
      selection: selection.isCollapsed
          ? ''
          : into.document.getPlainText(
              selection.start,
              selection.end - selection.start,
            ),
    );
    if (chosen == null || !mounted) return;

    switch (chosen) {
      case InsertSnippet(:final snippet):
        final body = await _filled(snippet);
        if (body == null || !mounted) return;
        _putSnippet(into, body);
        await store.reached(snippet.id);
      case KeepSelection(:final name):
        if (selection.isCollapsed) return;
        await store.add(
          name,
          into.document.toDelta().slice(selection.start, selection.end),
        );
      case HarvestArchive():
        await _harvest(store);
      case ManageSnippets():
        await SnippetManager.show(context, store);
      case InsertText(:final text):
        _putText(into, text);
      case EditProfile():
        await LawyerProfileDialog.show(context);
    }
  }

  /// Looks through the archive for passages it already repeats.
  ///
  /// The counting happens in the index isolate, where the text is; what
  /// comes back is a list to choose from. Nothing is kept unchosen — an
  /// address repeats as faithfully as a recital does.
  Future<void> _harvest(SnippetStore store) async {
    final library = widget.library;
    if (library == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final found = await library.repeatedPassages();
    if (!mounted) return;
    final kept = await SnippetHarvest.show(context, found: found, store: store);
    if (kept != null && kept > 0) {
      messenger
        ?..clearSnackBars()
        ..showSnackBar(
          noticeBar('$kept kalıp eklendi.', kind: NoticeKind.success),
        );
    }
  }

  /// Puts a passage in at the cursor, formatting and all.
  ///
  /// The same road a rich paste takes: a delta of inserts handed to
  /// replaceText, which is what carries the bold of a heading and the
  /// indent of a list across.
  /// A value from the lawyer's profile, where the cursor is. Written as
  /// typing is, so it takes the style around it — bold in a bold heading —
  /// and as a step of its own to undo.
  void _putText(QuillController into, String text) {
    final selection = into.selection;
    if (!selection.isValid || text.isEmpty) return;
    final history = into.document.history;
    history.lastRecorded = 0;
    into.replaceText(
      selection.start,
      selection.end - selection.start,
      text,
      TextSelection.collapsed(offset: selection.start + text.length),
    );
    history.lastRecorded = 0;
    setState(() {});
  }

  /// A profile blank typed straight into the text — "[AVUKAT]" — is filled
  /// the moment its bracket closes. Undo brings the blank back, so a filing
  /// that means the brackets can keep them. Only for typing: a document
  /// opened or pasted with blanks in it keeps them until they are filled on
  /// purpose.
  void _fillTypedBlank(DocChange event) {
    if (event.source != ChangeSource.local) return;
    final typed = StringBuffer();
    for (final operation in event.change.toList()) {
      if (operation.isDelete) return;
      final data = operation.data;
      if (operation.isInsert && data is String) typed.write(data);
    }
    if (typed.toString() != ']') return;
    final profile = LawyerProfile.cached;
    if (profile == null) {
      unawaited(LawyerProfile.load());
      return;
    }
    // After the change has settled: this is called from inside it.
    scheduleMicrotask(() {
      if (!mounted) return;
      final controller = _quillController;
      final selection = controller.selection;
      if (!selection.isValid || !selection.isCollapsed) return;
      final before = controller.document.toPlainText().substring(
        0,
        selection.baseOffset,
      );
      final blank = RegExp('${Snippet.marker.pattern}\$').firstMatch(before);
      if (blank == null) return;
      final name = blank.group(1)!;
      final value = profile.blanks()[name];
      if (value == null) {
        if (LawyerProfile.known.contains(name)) {
          showNotice(
            context,
            'Avukat profilinde “${LawyerProfile.labels[name]}” yok.',
            detail: 'Ayarlar → Avukat profili’nden ekleyebilirsiniz.',
          );
        }
        return;
      }
      final history = controller.document.history;
      history.lastRecorded = 0;
      controller.replaceText(
        blank.start,
        blank.end - blank.start,
        value,
        TextSelection.collapsed(offset: blank.start + value.length),
      );
      history.lastRecorded = 0;
    });
  }

  void _putSnippet(QuillController into, Delta passage) {
    final selection = into.selection;
    if (!selection.isValid) return;
    final body = Delta();
    var length = 0;
    for (final operation in passage.toList()) {
      if (!operation.isInsert) continue;
      body.insert(operation.data, operation.attributes);
      final data = operation.data;
      length += data is String ? data.length : 1;
    }
    if (body.isEmpty) return;
    // A step of its own to undo: Quill folds changes less than 0.4 s apart
    // into one, and a keyword typed and then expanded at once would come
    // back out with the passage, keyword and all.
    final history = into.document.history;
    history.lastRecorded = 0;
    into.replaceText(
      selection.start,
      selection.end - selection.start,
      body,
      TextSelection.collapsed(offset: selection.start + length),
    );
    history.lastRecorded = 0;
    setState(() {});
  }

  void _toggle(Attribute attribute) {
    final current = _active.getSelectionStyle().attributes[attribute.key];
    _active.formatSelection(
      Attribute.clone(
        attribute,
        current?.value == attribute.value ? null : attribute.value,
      ),
    );
  }

  Future<void> _find({bool replace = false}) => showDialog<void>(
    context: context,
    builder: (_) =>
        EditorFindReplace(controller: _quillController, replace: replace),
  );

  /// The claim on the document this window edits, so that no other window
  /// edits it at the same time and one save does not undo the other's.
  DocumentLock? _pathLock;
  String? _lockedPath;

  /// The document is being edited in another window: this one only reads.
  bool _heldElsewhere = false;

  /// [carry]: the same document under a new name, keeping its UYAP case;
  /// not another document opened in its place.
  Future<void> _holdDocument({bool carry = true}) async {
    final path = _documentPath;
    unawaited(_uyap.bind(path, carry: carry));
    if (path == _lockedPath && _pathLock != null) return;
    final previous = _pathLock;
    _pathLock = null;
    _lockedPath = path;
    await previous?.release();
    DocumentLock? lock;
    var held = false;
    if (path != null && !Platform.isAndroid) {
      try {
        lock = await DocumentLock.document(path);
        held = lock == null;
      } catch (_) {
        // A lock that cannot be looked at does not stand in the way.
      }
    }
    if (!mounted || _lockedPath != path) {
      await lock?.release();
      return;
    }
    _pathLock = lock;
    if (held != _heldElsewhere) {
      setState(() => _heldElsewhere = held);
      _quillController.readOnly = held;
    }
  }

  /// Whether another window edits the document at [path]. A lock that
  /// cannot be looked at does not stand in the way of saving.
  Future<bool> _heldByAnotherWindow(String path) async {
    try {
      return await DocumentLock.documentHeld(path);
    } catch (_) {
      return false;
    }
  }

  void _showHeldElsewhere() => showNotice(
    context,
    'Bu belge başka bir pencerede açık',
    detail:
        'Aynı belge iki pencerede düzenlenirse biri ötekinin kaydını ezer. '
        'Belgeyi açık olduğu pencerede düzenleyin.',
    kind: NoticeKind.error,
  );

  Widget _heldElsewhereBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('held-elsewhere'),
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(
              Icons.lock_outline,
              size: 18,
              color: scheme.onTertiaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Bu belge başka bir Folio penceresinde düzenleniyor. Burada '
                'yalnız okunabilir; değişiklikleri o pencerede yapın.',
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ),
            TextButton(
              onPressed: () {
                _lockedPath = null;
                unawaited(_holdDocument());
              },
              child: const Text('Yeniden dene'),
            ),
          ],
        ),
      ),
    );
  }

  /// Reads the selection aloud, or everything from the paragraph the caret
  /// is in; pressed again, stops. Each sentence is selected as it is read,
  /// so the eye can follow the voice.
  Future<void> _readAloud({bool restart = false}) async {
    final reading = ReadAloud.instance;
    if (!restart && reading.state != ReadState.idle && reading.owner == this) {
      await reading.stop();
      return;
    }
    final controller = _quillController;
    final text = controller.document.toPlainText();
    final selection = controller.selection;
    var from = selection.isValid ? selection.start : 0;
    var to = selection.isValid && !selection.isCollapsed
        ? selection.end
        : text.length;
    if (!selection.isValid || selection.isCollapsed) {
      // From the start of the paragraph, or from the top when the caret is
      // past the last of the text.
      from =
          text.substring(0, from.clamp(0, text.length)).lastIndexOf('\n') + 1;
      if (text.substring(from).trim().isEmpty) from = 0;
      to = text.length;
    }
    await readAloud(
      context,
      owner: this,
      text: () async => text.substring(from, to),
      offset: from,
      onSentence: (s) {
        if (!mounted || s.end >= controller.document.length) return;
        controller.updateSelection(
          TextSelection(baseOffset: s.start, extentOffset: s.end),
          ChangeSource.local,
        );
      },
    );
  }

  /// Writes down what is said where the caret is, until pressed again.
  Future<void> _dictate() async {
    final dictation = Dictation.instance;
    if (dictation.state != ListenState.idle && dictation.owner == this) {
      await dictation.stop();
      return;
    }
    await ReadAloud.instance.stop();
    if (!mounted) return;
    final dir = await SpeechDownloadDialog.ensure(
      context,
      SpeechModel.dictation,
    );
    if (dir == null || !mounted) return;
    await dictation.start(modelDir: dir, owner: this, onText: _writeHeard);
    if (dictation.error != null && mounted) {
      showNotice(
        context,
        'Sesli yazma başlamadı',
        detail: dictation.error,
        kind: NoticeKind.error,
      );
    }
  }

  /// [text] in place of the selection, apart from the word before it.
  void _writeHeard(String text) {
    if (!mounted) return;
    final controller = _active;
    final selection = controller.selection;
    final plain = controller.document.toPlainText();
    final at = selection.isValid
        ? selection.start.clamp(0, controller.document.length - 1)
        : controller.document.length - 1;
    final length = selection.isValid ? selection.end - selection.start : 0;
    final before = at > 0 ? plain[at - 1] : '\n';
    final insert = '${RegExp(r'\s').hasMatch(before) ? '' : ' '}$text';
    controller.replaceText(
      at,
      length,
      insert,
      TextSelection.collapsed(offset: at + insert.length),
    );
  }

  Future<void> _print() async {
    if (_isPrinting) return;
    _isPrinting = true;
    try {
      final bytes = await PdfService.modelToPdfBytes(
        _currentModel(),
        title: _currentTitle,
      );
      if (!mounted) return;
      await PrintScreen.show(
        context,
        pdf: bytes,
        name: _currentTitle ?? 'Belge',
      );
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Yazdırılamadı',
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
    } finally {
      _isPrinting = false;
    }
  }

  /// Picks a picture and places it at the cursor. The bytes go into the
  /// document itself, so what is saved, mailed or signed carries the picture
  /// with it.
  Future<void> _insertImage() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Görsel ekle',
      type: FileType.custom,
      allowedExtensions: EditorImages.extensions,
    );
    final path = picked?.paths.whereType<String>().firstOrNull;
    if (path == null || !mounted) return;

    void uyar(String mesaj) {
      if (mounted) showNotice(context, mesaj, kind: NoticeKind.error);
    }

    try {
      final file = File(path);
      if (await file.length() > EditorImages.maxBytes) {
        uyar('Görsel çok büyük — en çok 12 MB eklenebilir.');
        return;
      }
      final bytes = await file.readAsBytes();
      final size = EditorImages.measure(bytes);
      if (size == null) {
        uyar('Görsel okunamadı: ${p.basename(path)}');
        return;
      }
      if (!mounted) return;
      EditorImages.insert(
        _active,
        base64Data: base64Encode(bytes),
        mime: EditorImages.mimeFor(path),
        size: size,
      );
    } catch (e) {
      uyar('Görsel eklenemedi: $e');
    }
  }

  /// Adds an empty header or footer, or takes one away. Removing is what
  /// deletes it from the saved document, so it asks first when there is
  /// something written there.
  /// A new document starts under the letterhead the lawyer picked for new
  /// documents, and counts as untouched until written in.
  Future<void> _defaultLetterhead() async {
    final LetterheadStore store;
    try {
      store = await LetterheadStore.shared();
    } on Object {
      // Without its folder there is no letterhead to start with; the new
      // document opens as it always did.
      return;
    }
    final letterhead = store.defaultOne;
    if (letterhead == null || !mounted || _hasChanges) return;
    if (_regions.containsKey('header')) return;
    _applyLetterhead(letterhead.blocks);
    _markSaved();
  }

  /// The letterheads: puts one on the document, or keeps the document's
  /// header as one (see [LetterheadDialog]).
  Future<void> _letterheads() async {
    final store = await LetterheadStore.shared();
    if (!mounted) return;
    final header = _regions['header'];
    final choice = await LetterheadDialog.show(
      context,
      store: store,
      header: header == null
          ? null
          : DocDeltaMap.deltadanModel(
              header.document.toDelta(),
              korunanlar: _regionKorunan['header'] ?? const [],
            ).blocks,
      pageWidth:
          EditorPages.sheet(_pageProperties).width -
          _pageProperties.marginLeft -
          _pageProperties.marginRight,
    );
    if (choice == null || !mounted) return;
    _applyLetterhead(
      choice.letterhead.blocks,
      firstPageOnly: choice.firstPageOnly,
    );
  }

  /// Puts [blocks] in the header, in place of what was there, keeping its
  /// page numbers: on every page, or with [firstPageOnly] on the first
  /// alone (UYAP's stopPage).
  void _applyLetterhead(List<DocBlock> blocks, {bool firstPageOnly = false}) {
    unawaited(
      DocumentFonts.loadEditorFamilies(
        DocumentFonts.modelFamilies(DocModel(blocks: blocks)),
      ).then((_) {
        if (mounted) setState(() {});
      }),
    );
    setState(() {
      _openRegion('header', blocks);
      final attrs = {...?_regionAttrs['header']}
        ..remove('startPage')
        ..remove('stopPage');
      if (firstPageOnly) attrs['stopPage'] = '1';
      _regionAttrs['header'] = attrs;
      _livePage.remove('header');
    });
    _recovery.changed();
    _checkEditedSoon();
    _measureRegions();
  }

  /// Sets where the page numbers go and how they read, as UYAP keeps them:
  /// on the header or the footer, which is opened for them if the document
  /// has none.
  Future<void> _pageNumbers() async {
    final current = [
      'footer',
      'header',
    ].where((k) => PageNumbering.parse(_regionAttrs[k]) != null).firstOrNull;
    final choice = await PageNumberDialog.show(
      context,
      region: current,
      numbering: current == null
          ? null
          : PageNumbering.parse(_regionAttrs[current]),
    );
    if (choice == null || !mounted) return;
    final region = choice.region;
    if (region != null) {
      // Drawn at once, in its own font as soon as that is in.
      unawaited(
        DocumentFonts.loadEditorFamilies([choice.numbering.fontFace]).then((_) {
          if (mounted) setState(() {});
        }),
      );
    }
    setState(() {
      for (final key in ['header', 'footer']) {
        if (_regionAttrs.containsKey(key)) {
          _regionAttrs[key] = PageNumbering.apply(_regionAttrs[key], null);
        }
      }
      if (region != null) {
        if (!_regions.containsKey(region)) {
          _openRegion(region, [DocBlock(plainText: '')]);
        }
        _regionAttrs[region] = PageNumbering.apply(
          _regionAttrs[region],
          choice.numbering,
        );
      }
    });
    _recovery.changed();
    _checkEditedSoon();
    _measureRegions();
  }

  Future<void> _toggleRegion(String key) async {
    if (_regions.containsKey(key)) {
      final written = _regions[key]!.document.toPlainText().trim().isNotEmpty;
      if (written) {
        final onay = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              key == 'header'
                  ? 'Üst bilgi silinsin mi?'
                  : 'Alt bilgi silinsin mi?',
            ),
            content: const Text(
              'Yazdıklarınız belgeden kaldırılacak. Kaydetmeden çıkarsanız '
              'değişiklik uygulanmaz.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Vazgeç'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Sil'),
              ),
            ],
          ),
        );
        if (onay != true) return;
      }
      setState(() {
        _closeRegion(key);
        // Its page numbering and start page go with it.
        _regionAttrs.remove(key);
      });
      _measureRegions();
    } else {
      setState(() => _openRegion(key, [DocBlock(plainText: '')]));
      _measureRegions();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _regionFocus[key]?.requestFocus();
      });
    }
    _recovery.changed();
    _checkEditedSoon();
  }

  /// Puts an empty table at the cursor. It goes into the list the mapper keeps
  /// aside and the document carries only its index, the same as a table read
  /// from a file, so everything downstream treats the two alike.
  void _insertTable(int rows, int columns) {
    final block = DocBlock(
      type: DocBlockType.table,
      plainText: '',
      table: DocTable(
        columnWidths: List.filled(columns, 100.0),
        rows: [
          for (var r = 0; r < rows; r++)
            DocTableRow(
              cells: [
                for (var c = 0; c < columns; c++)
                  DocTableCell(blocks: [DocBlock(plainText: '')]),
              ],
            ),
        ],
      ),
    );
    final index = _korunanBloklar.length;
    _korunanBloklar.add(block);
    EditorEmbeds.insertOnOwnLine(
      _quillController,
      Embeddable(DocDeltaMap.kTableEmbed, index),
    );
    setState(() {});
  }

  /// Takes the tables a paste brings into the list kept beside the delta,
  /// and says where the first one went, so the pasted embeds point at them.
  int _keepPastedTables(List<DocBlock> tables) {
    final base = _korunanBloklar.length;
    _korunanBloklar.addAll(tables);
    return base;
  }

  /// After a rich paste. Finding a pasted font can mean scanning a large
  /// system font tree, and the family name is already in the delta, so the
  /// paste does not wait for it: the text redraws in its face when it comes.
  void _pasted(DocModel model) {
    unawaited(
      (() async {
        try {
          await DocumentFonts.loadEditorFamilies(
            DocumentFonts.modelFamilies(model),
          );
          if (mounted) setState(() {});
        } catch (_) {
          // The stored family still survives and renders with its fallback.
        }
      })(),
    );
    if (mounted) setState(() {});
  }

  /// The page's own light theme, whatever the app's: black text on white
  /// paper.
  Widget _paperTheme(BuildContext context, Widget child) => Theme(
    data: Theme.of(context).copyWith(
      brightness: Brightness.light,
      textTheme: Theme.of(context).textTheme
          .apply(bodyColor: Colors.black, displayColor: Colors.black),
      colorScheme: ColorScheme.fromSeed(
        seedColor: Theme.of(context).colorScheme.primary,
      ),
    ),
    child: child,
  );

  /// The sheets and the text on them, with the header and footer in the
  /// first page's margins, where UYAP and the printed page put them, rather
  /// than in the text.
  Widget _paged({
    required double scale,
    required double paperHeight,
    required double heightPoints,
    required void Function(double start, double end) onMargins,
    required double textTop,
    required double textBottom,
    required Widget child,
  }) {
    // The vertical ruler, one beside every page, in a strip of its own left
    // of the sheets.
    final ruler = _showVerticalRuler ? 24.0 : 0.0;
    final left = ruler + _pageProperties.marginLeft * scale;
    final right = _pageProperties.marginRight * scale;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: EdgeInsets.only(left: ruler),
          child: child,
        ),
        if (ruler > 0)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: ruler,
            child: LayoutBuilder(
              builder: (context, box) {
                final pages = EditorSheetsPainter.pageCount(
                  box.maxHeight,
                  paperHeight,
                  EditorSheetsPainter.room,
                );
                return Column(
                  children: [
                    for (var page = 0; page < pages; page++) ...[
                      if (page > 0)
                        const SizedBox(height: EditorSheetsPainter.room),
                      DocumentRuler(
                        key: ValueKey('vertical-ruler-$page'),
                        axis: Axis.vertical,
                        pagePoints: heightPoints,
                        pixels: paperHeight,
                        leading: _pageProperties.marginTop,
                        trailing: _pageProperties.marginBottom,
                        onChanged: onMargins,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        // The header and footer on every page, where the printed page draws
        // them: a header at its offset from the top edge, a footer ending at
        // its offset from the bottom one.
        if (_regions.isNotEmpty)
          Positioned(
            left: left,
            right: right,
            top: 0,
            bottom: 0,
            child: LayoutBuilder(
              builder: (context, box) {
                final pages = EditorSheetsPainter.pageCount(
                  box.maxHeight,
                  paperHeight,
                  EditorSheetsPainter.room,
                );
                final stride = paperHeight + EditorSheetsPainter.room;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var page = 0; page < pages; page++) ...[
                      if (_regionKey('header', page) case final key?)
                        Positioned(
                          left: 0,
                          right: 0,
                          top:
                              page * stride +
                              _pageProperties.headerOffset * scale,
                          child: _paperTheme(context, _band(key, page, pages)),
                        ),
                      if (_regionKey('footer', page) case final key?)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom:
                              box.maxHeight -
                              page * stride -
                              paperHeight +
                              _pageProperties.footerOffset * scale,
                          child: _paperTheme(context, _band(key, page, pages)),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
      ],
    );
  }

  /// A header or footer on page [page]: the one being edited on the page it
  /// was last clicked on, and a copy of it on every other, which a click
  /// makes the one being edited.
  Widget _band(String key, int page, int pages) {
    final live = _regions[key]!;
    // A header UYAP starts on page 2 does not print on page 1: it is shown
    // there faded, so that it can still be written in.
    final printed = PageNumbering.regionShows(_regionAttrs[key], page + 1);
    final start = _regionAttrs[key]?['startPage'];
    final note = printed ? null : '$start. sayfadan itibaren basılır';
    // The page's own number, drawn over the band as UYAP draws it.
    final numbering = PageNumbering.parse(_regionAttrs[key]);
    final label =
        printed && numbering != null && numbering.shows(page + 1, pages)
        ? numbering.label(page + 1, pages)
        : null;
    final width =
        EditorPages.sheet(_pageProperties).width -
        _pageProperties.marginLeft -
        _pageProperties.marginRight;
    final kind = key.endsWith('header') ? 'header' : 'footer';
    if ((_livePage[key] ?? 0) == page) {
      return EditorRegionBand(
        key: ValueKey('region-$key'),
        controller: live,
        focusNode: _regionFocus[key]!,
        isHeader: kind == 'header',
        focused: _focusedRegion == key,
        pageWidth: width,
        numbering: numbering,
        numberLabel: label,
        note: note,
        onRemove: () => _toggleRegion(key),
      );
    }
    var copy = _regionCopies[key];
    // Never disposed: disposing a controller closes its document, and this
    // one's document is the band's own.
    if (copy == null || !identical(copy.document, live.document)) {
      copy = _regionCopies[key] = QuillController(
        document: live.document,
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );
    }
    return GestureDetector(
      key: ValueKey('region-$key-$page'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _livePage[key] = page);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _regionFocus[key]?.requestFocus();
        });
      },
      child: IgnorePointer(
        child: ListenableBuilder(
          // The copy follows the one being edited as it is typed in.
          listenable: live,
          builder: (context, _) => EditorRegionBand(
            controller: copy!,
            isHeader: kind == 'header',
            focused: false,
            pageWidth: width,
            numbering: numbering,
            numberLabel: label,
            note: note,
            onRemove: () {},
          ),
        ),
      ),
    );
  }

  void _showShortcuts() => showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Editör kısayolları'),
      content: const SingleChildScrollView(
        child: Text(
          'Ctrl+S  Kaydet\nCtrl+Shift+S  Farklı kaydet\nCtrl+Z  Geri al\nCtrl+Y / Ctrl+Shift+Z  Yinele\nCtrl+B / I / U  Kalın / İtalik / Altı çizili\nCtrl+A / C / X / V  Seç / Kopyala / Kes / Yapıştır\nCtrl+F  Belgede bul\nCtrl+H  Bul ve değiştir\nCtrl+P  Yazdır\nCtrl+L / E / R / J  Sola / Ortaya / Sağa / İki yana\nCtrl+Shift+L / 8  Madde işaretleri\nCtrl+Shift+7  Numaralı liste\nCtrl+M / Ctrl+Shift+M  Girintiyi artır / azalt\n\nmacOS’ta Ctrl yerine ⌘ kullanılır.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tamam'),
        ),
      ],
    ),
  );

  /// Whether this document can be signed from here. A document opened from a
  /// file counts: saving it writes an unsigned copy, and signing that copy is
  /// the whole reason someone re-saves a signed document.
  bool get _canSignNew =>
      signingAvailable &&
      widget.onSigned != null &&
      (_savedFormat ?? widget.initialFormat) == EvrakFormat.udf;
  bool _signingNew = false;
  bool _sendingUyap = false;

  /// The format Farklı kaydet keeps: the document's own when the editor can
  /// write it, UDF otherwise (a PDF or ODT opened here is saved as UDF).
  EvrakFormat get _ownFormat {
    final format = _savedFormat ?? widget.initialFormat ?? EvrakFormat.udf;
    return const [
          EvrakFormat.udf,
          EvrakFormat.docx,
          EvrakFormat.rtf,
        ].contains(format)
        ? format
        : EvrakFormat.udf;
  }

  Future<void> _openUyapOperations({UyapSendReceipt? receipt}) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => UyapOperationsDialog(focusReceipt: receipt),
    );
  }

  Future<void> _sendToUyap() async {
    if (_sendingUyap ||
        _isSaving ||
        _isLoading ||
        _loadError != null ||
        !(Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      return;
    }
    setState(() => _sendingUyap = true);
    try {
      // A draft, a non-UDF source, or an edited signed UDF must become a new
      // unsigned UDF before signing. Never send the previously signed bytes.
      var path = _savedPath ?? widget.initialFilePath;
      final format = _savedFormat ?? widget.initialFormat;
      if (path == null || format != EvrakFormat.udf || _hasChanges) {
        if (!await _saveAs(EvrakFormat.udf)) return;
        path = _savedPath;
      }
      if (!mounted || path == null) return;
      var bytes = await File(path).readAsBytes();
      if (!mounted) return;
      if (UdfSigningService.isSigned(bytes)) {
        // A present sign.sgn is only a hint. Refuse a signature detached from
        // this document; asking the signer to overwrite it would hide damage.
        UyapWebService.validateSignedUdf(bytes);
      } else {
        final signed = await EditorWidget.sign(context, path);
        if (!mounted || signed == null) return;
        path = signed;
        await _takeSignature(signed);
        if (!mounted) return;
        bytes = await File(signed).readAsBytes();
        UyapWebService.validateSignedUdf(bytes);
      }
      if (!mounted || _hasChanges) return;
      final capturedPath = path;
      final capturedHash = sha256.convert(bytes);
      final capturedDelta = _deltaSnapshot();
      final capturedRegions = _regionSnapshot();
      final capturedTable = _tableRevision;
      final capturedPage = jsonEncode(_pageValues(_pageProperties));
      Future<bool> stillCurrent() async {
        if (!mounted ||
            _hasChanges ||
            _deltaSnapshot() != capturedDelta ||
            _regionSnapshot() != capturedRegions ||
            _tableRevision != capturedTable ||
            jsonEncode(_pageValues(_pageProperties)) != capturedPage) {
          return false;
        }
        try {
          return sha256.convert(await File(capturedPath).readAsBytes()) ==
              capturedHash;
        } catch (_) {
          return false;
        }
      }

      // The case the document is tied to, if it is.
      await _uyap.bind(_documentPath);
      final target = _uyap.link;
      if (!mounted) return;
      final result = await showDialog<UyapSendReceipt>(
        context: context,
        barrierDismissible: false,
        builder: (_) => UyapSendDialog(
          documentName: p.basename(capturedPath),
          documentBytes: Uint8List.fromList(bytes),
          stillCurrent: stillCurrent,
          target: target,
        ),
      );
      if (mounted && result != null) {
        showNotice(
          context,
          'UYAP gönderim yanıtı alındı. İşlem tamamlanana kadar takip ediliyor.',
          kind: NoticeKind.success,
        );
        await _openUyapOperations(receipt: result);
      }
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'UYAP gönderimi başlatılamadı',
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _sendingUyap = false);
    }
  }

  Future<void> _signNew() async {
    if (!_canSignNew || _signingNew || _isSaving) return;
    setState(() => _signingNew = true);
    try {
      if ((_savedPath == null || _hasChanges) && !await _save()) return;
      final path = _savedPath;
      if (!mounted || path == null || _savedFormat != EvrakFormat.udf) return;
      final signed = await EditorWidget.sign(context, path);
      if (!mounted || signed == null) return;
      await _takeSignature(signed);
      widget.onSigned?.call(signed);
    } finally {
      if (mounted) {
        setState(() => _signingNew = false);
        if (widget.isActive) _editorFocus.requestFocus();
      }
    }
  }

  /// The document as it is now, signed at [path]. The editor read the
  /// signature only when it opened the file, so without this the banner
  /// stayed away until the document was opened again.
  Future<void> _takeSignature(String path) async {
    final signed = UdfReader.readBytes(await File(path).readAsBytes());
    if (!mounted) return;
    setState(() {
      _savedPath = path;
      _savedFormat = EvrakFormat.udf;
      if (signed != null) {
        _sourceModel = DocModel(
          blocks: _sourceModel?.blocks ?? signed.blocks,
          styles: _sourceModel?.styles ?? signed.styles,
          pageProperties: _sourceModel?.pageProperties ?? signed.pageProperties,
          pageRegions: _sourceModel?.pageRegions ?? signed.pageRegions,
          metadata: signed.metadata,
        );
        _sourceSigned = signed.metadata['hasSignature'] == true;
        // Editing it now drops the signature again: say so, as on opening.
        _signatureNoticeShown = false;
      }
    });
    unawaited(_holdDocument());
  }

  Future<bool> _save() async {
    if (_heldElsewhere) {
      _showHeldElsewhere();
      return false;
    }
    final originalFormat = widget.initialFormat;
    final writable =
        originalFormat == EvrakFormat.udf ||
        originalFormat == EvrakFormat.docx ||
        originalFormat == EvrakFormat.text;
    final target =
        _savedFormat ?? (writable ? originalFormat! : EvrakFormat.udf);
    final source = !_recoveredWithoutSource && writable
        ? widget.initialFilePath
        : null;
    // Most UDFs out of UYAP are signed. Refusing outright to save one in
    // place sent every edit of such a file to a new name, so the reader is
    // asked instead — and the signed file is kept in the history either way.
    // Only on a desktop: a phone saves through the system's own save screen,
    // which never writes over the file a document came from.
    if (_savedPath == null &&
        source != null &&
        _sourceSigned &&
        !Platform.isAndroid &&
        desktopSigningAvailable) {
      if (_isSaving || _isLoading || _loadError != null) return false;
      final choice = await _askSignedSave();
      if (choice == null || !mounted) return false;
      // Answered once; the unsigned-copy notice would ask about the same loss.
      _signatureNoticeShown = true;
      return choice == _SignedSave.overwrite
          ? _saveAs(target, destination: source, overwriteSigned: true)
          : _saveAs(target);
    }
    final path = _savedPath ?? (_sourceSigned ? null : source);
    return _saveAs(target, destination: Platform.isAndroid ? null : path);
  }

  Future<_SignedSave?> _askSignedSave() => showDialog<_SignedSave>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        Icons.draw_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: const Text('Bu belge e-imzalı'),
      content: const SizedBox(
        width: 460,
        child: Text(
          'İmza, belgenin imzalandığı andaki içeriğini kapsar; değiştirilmiş '
          'belgeye taşınamaz.\n\n'
          '• Üzerine kaydet: dosya değişikliklerinizle, imzasız olarak '
          'güncellenir. İmzalı hali belge geçmişinde saklanır; istediğinizde '
          'ona dönebilir ya da kopyasını alabilirsiniz.\n\n'
          '• İmzasız kopya: imzalı dosya olduğu gibi kalır, değişiklikler '
          'yeni bir dosyaya yazılır.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        TextButton(
          key: const ValueKey('save-unsigned-copy'),
          onPressed: () => Navigator.pop(context, _SignedSave.copy),
          child: const Text('İmzasız kopya kaydet…'),
        ),
        FilledButton(
          key: const ValueKey('overwrite-signed'),
          onPressed: () => Navigator.pop(context, _SignedSave.overwrite),
          child: const Text('Üzerine kaydet'),
        ),
      ],
    ),
  );

  /// The same question, for a signed file picked in the save dialog.
  Future<bool> _confirmSignedOverwrite() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('İmzalı dosyanın üzerine yazılsın mı?'),
          content: const Text(
            'Dosya değişikliklerinizle, imzasız olarak güncellenir. İmzalı '
            'hali belge geçmişinde saklanır.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Üzerine yaz'),
            ),
          ],
        ),
      ) ==
      true;

  @override
  void initState() {
    super.initState();
    unawaited(
      SnippetStore.shared().then((store) {
        if (mounted) _snippetStore = store;
      }, onError: (_) {}),
    );
    // Read once, so a blank typed into the text can be filled at once.
    unawaited(LawyerProfile.load());
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      _showHorizontalRuler = false;
      _showVerticalRuler = false;
    }
    _quillController = _DocumentController()
      ..tables = (() => _korunanBloklar)
      ..keepTables = _keepPastedTables
      ..documentMetadata = (() => _sourceModel?.metadata ?? const {})
      ..onPasted = _pasted;
    unawaited(_loadTerms());
    // Typing in the document again lets go of the cell the toolbar was
    // pointing at, so Ctrl+B there emboldens the document and not a table.
    _editorFocus.addListener(() {
      if (!_editorFocus.hasFocus) _hideSuggestions();
      if (_editorFocus.hasPrimaryFocus) _cellsGone();
    });
    DocumentHistory.holdDraft(_draftKey);
    _recovery = DraftRecovery(
      write: _writeRecovery,
      remove: () => DocumentHistory.instance.clearRecovery(_draftKey),
      onError: _historyError,
    );
    WidgetsBinding.instance.addObserver(this);
    _watchDocument();
    if (widget.initialFilePath == null) {
      _quillController.formatSelection(
        Attribute.clone(Attribute.font, 'Times New Roman'),
      );
      _quillController.formatSelection(Attribute.clone(Attribute.size, '16'));
      if (widget.recovery == null) unawaited(_defaultLetterhead());
      final uyapCase = widget.uyapCase;
      if (uyapCase != null) {
        _uyapOpen = true;
        unawaited(_uyap.attach(uyapCase));
      }
    }
    _markSaved();
    widget.draft?.changed = () => _hasChanges;
    widget.draft?.save = _save;
    widget.draft?.saving = () => _isSaving || _isLoading;
    widget.draft?.discard = _discard;
    widget.draft?.savedPath = () => _savedPath;
    widget.draft?.history = _history;
    DocumentFonts.loadEditorFamilies(['Times New Roman']).then((_) {
      if (mounted) setState(() {});
    });
    if (widget.initialFilePath != null) {
      _loadDocument(
        widget.initialFilePath!,
        widget.initialFormat ?? EvrakFormat.udf,
      );
    } else if (widget.recovery != null) {
      _recover(widget.recovery!);
    }
  }

  @override
  void didUpdateWidget(covariant EditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isActive) _editorFocus.requestFocus();
      });
    }

    if (oldWidget.initialFilePath != widget.initialFilePath &&
        widget.initialFilePath != null) {
      _loadDocument(
        widget.initialFilePath!,
        widget.initialFormat ?? EvrakFormat.udf,
      );
    }
    if (!identical(widget.reveal, oldWidget.reveal)) _reveal();
  }

  @override
  void dispose() {
    // A draft written while there were edits, and outlived by an undo, would
    // otherwise be offered after the next start as work that was never saved.
    final clean = !_isLoading && _loadError == null && !_hasChanges;
    (clean ? _recovery.clear() : Future<void>.value()).whenComplete(
      () => DocumentHistory.releaseDraft(_draftKey),
    );
    _loadGeneration++;
    _editedCheck?.cancel();
    _regionMeasure?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _documentChanges?.cancel();
    _hideSuggestions();
    unawaited(_pathLock?.release());
    _uyap.dispose();
    if (ReadAloud.instance.owner == this) unawaited(ReadAloud.instance.stop());
    if (Dictation.instance.owner == this) unawaited(Dictation.instance.stop());
    _recovery.dispose();
    widget.draft?.detach();
    _editorFocus.dispose();
    _spelling
      ..removeListener(_spellingChanged)
      ..dispose();
    _citations
      ..removeListener(_spellingChanged)
      ..dispose();
    for (final key in _regions.keys.toList()) {
      _closeRegion(key);
    }
    _quillController.dispose();
    super.dispose();
  }

  /// Set while a PDF with no text layer is read page by page.
  bool _readingPages = false;

  /// Pages read of a PDF with no text layer. The archive stops at twenty; a
  /// reader who asked to edit one document needs all of it, and a filing cut
  /// short is worse than a wait.
  static const _pagesToRead = 300;

  /// A PDF with no text layer, read as pictures. Its letters need not be a
  /// scan: "Microsoft Print to PDF" saves what UYAP's editor prints as shapes,
  /// which PDFium draws faithfully and nothing can select. Crisp shapes read
  /// almost without fault; either way this is the only text there is.
  Future<DocModel> _readPages(String path) async {
    if (!await OcrService.available) {
      throw const FormatException(
        'Bu PDF’te metin katmanı yok: yazıları taranmış ya da yazdırılırken '
        'şekle dönüştürülmüş. Okumak için gereken OCR aracı bu kurulumda '
        'bulunamadı.',
      );
    }
    if (mounted) setState(() => _readingPages = true);
    try {
      final text = await recognizeNow(
        path,
        EvrakFormat.pdf,
        pdfPages: _pagesToRead,
      );
      if (text == null || text.trim().isEmpty) {
        throw const FormatException(
          'Bu PDF’te metin katmanı yok ve sayfalarında okunabilir yazı '
          'bulunamadı.',
        );
      }
      return ocrDocModel(text);
    } finally {
      if (mounted) setState(() => _readingPages = false);
    }
  }

  Future<void> _loadDocument(String path, EvrakFormat format) async {
    final generation = ++_loadGeneration;
    var readByOcr = false;
    setState(() {
      _isLoading = true;
      _loadError = null;
      _sourceModel = null;
      _signatureNoticeShown = false;
      _savedPath = null;
      _savedFormat = null;
    });
    unawaited(_holdDocument(carry: false));
    try {
      final pdfText = format == EvrakFormat.pdf
          ? await widget.initialPdfTextLoader?.call()
          : null;
      if (!mounted || generation != _loadGeneration) return;
      DocModel? model;
      try {
        model = await ConverterService.extractFileDocModel(
          path,
          format,
          extractedPdfText: pdfText,
        );
      } on PdfWithoutText {
        if (!mounted || generation != _loadGeneration) return;
        model = await _readPages(path);
        readByOcr = true;
      }
      if (!mounted || generation != _loadGeneration) return;
      if (model == null) {
        throw const FormatException('Belge okunamadı veya bozuk.');
      }
      await DocumentFonts.loadEditorFamilies(
        DocumentFonts.modelFamilies(model),
      );
      if (!mounted || generation != _loadGeneration) return;
      // A PDF can contain hundreds of pages. Building thousands of Quill
      // operations is CPU work too, so keep it off the UI isolate along with
      // PDF parsing. Imported PDFs contain text blocks only; there are no
      // protected table/image blocks to bring back from this mapping.
      final pdfDelta = format == EvrakFormat.pdf
          ? await compute(_pdfDeltaJson, model)
          : null;
      final mapped = pdfDelta == null ? DocDeltaMap.modeldenDelta(model) : null;
      if (!mounted || generation != _loadGeneration) return;
      _sourceModel = model;
      _sourceSigned = model.metadata['hasSignature'] == true;
      _korunanBloklar = mapped?.korunanlar ?? <DocBlock>[];
      _pageProperties = model.pageProperties;
      _currentTitle = p.basenameWithoutExtension(path);
      _quillController.document = pdfDelta == null
          ? Document.fromDelta(mapped!.delta)
          : Document.fromJson(pdfDelta);
      _loadedDelta = jsonEncode(_quillController.document.toDelta().toJson());
      _loadedTableRevision = _tableRevision;
      _focusedCell = null;
      _loadRegions(model);
      _markSaved();
      _watchDocument();
      unawaited(_findLeftDrafts());
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        if (widget.recovery != null) {
          _recoveredWithoutSource = true;
          _markSaved();
        } else {
          _loadError = e is FormatException ? e.message : '$e';
        }
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _isLoading = false);
        if (readByOcr && _loadError == null) {
          showNotice(
            context,
            'Bu PDF’te metin katmanı yoktu; metin sayfalardan okundu (OCR).',
            detail:
                'Kaydetmeden önce özellikle rakamları ve adları kontrol '
                'edin.',
            duration: const Duration(seconds: 8),
          );
        }
        _reveal();
        if (_loadError == null && widget.recovery != null) {
          await _recover(widget.recovery!);
        }
      }
    }
  }

  /// Stops a filing going out with a blank still in it.
  ///
  /// A passage put in with [MÜVEKKİL] left showing is the one real danger
  /// this feature carries: it reads as finished text and it is not. The
  /// save is not refused — the reader may know what they are doing — but it
  /// is not allowed to happen quietly either.
  Future<bool> _confirmBlanks() async {
    final left = <String>[];
    for (final text in [
      _quillController.document.toPlainText(),
      for (final region in _regions.values) region.document.toPlainText(),
    ]) {
      for (final found in Snippet.marker.allMatches(text)) {
        final name = found.group(1)!;
        if (!left.contains(name)) left.add(name);
      }
    }
    if (left.isEmpty) return true;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Doldurulmamış yer var'),
        content: Text(
          'Belgede kalıptan gelen ${left.length} yer hâlâ boş: '
          '${left.map((one) => '[$one]').join(', ')}.\n\n'
          'Yine de kaydedilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Geri dön'),
          ),
          FilledButton(
            key: const ValueKey('save-with-blanks'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yine de kaydet'),
          ),
        ],
      ),
    );
    return go ?? false;
  }

  Future<bool> _confirmUnsignedSave() async {
    if (_signatureNoticeShown) return true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('İmzasız kopya kaydedilecek'),
        content: const Text(SignatureBanner.saveNotice),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Anladım, kaydet'),
          ),
        ],
      ),
    );
    if (!mounted) return false;
    _signatureNoticeShown = accepted == true;
    return _signatureNoticeShown;
  }

  /// The document's own metadata, with the header's and footer's numbering
  /// and start page as they are now.
  Map<String, dynamic> _metadata() => {
    ...?_sourceModel?.metadata,
    'pageRegionAttrs': {
      for (final e in _regionAttrs.entries)
        if (_regions.containsKey(e.key)) e.key: e.value,
    },
  };

  DocModel _currentModel() {
    if (_sourceModel != null &&
        _tableRevision == _loadedTableRevision &&
        jsonEncode(_quillController.document.toDelta().toJson()) ==
            _loadedDelta) {
      return DocModel(
        pageProperties: _pageProperties,
        styles: _sourceModel!.styles,
        blocks: _sourceModel!.blocks,
        metadata: _metadata(),
        pageRegions: _currentRegions(),
      );
    }
    return DocDeltaMap.deltadanModel(
      _quillController.document.toDelta(),
      korunanlar: _korunanBloklar,
      sayfa: _pageProperties,
      metadata: _metadata(),
      styles: _sourceModel?.styles ?? const [],
      pageRegions: _currentRegions(),
    );
  }

  Future<bool> _saveAs(
    EvrakFormat targetFormat, {
    String? destination,
    bool overwriteSigned = false,
  }) async {
    if (_isSaving || _isLoading || _loadError != null) return false;
    setState(() => _isSaving = true);
    final model = _currentModel();
    final savedDelta = _deltaSnapshot();
    // The header, footer and tables as they are written, which is what is
    // saved from here on: left out, a document whose header or a table had
    // been touched asked to be saved again every time it was closed.
    final savedRegions = _regionSnapshot();
    final savedRegionAttrs = jsonEncode(_regionAttrs);
    final savedTables = _tableRevision;
    final savedPage = _pageProperties;
    final savedProtected = List<DocBlock>.of(_korunanBloklar);
    final ext = targetFormat.defaultExtension;
    final defaultName =
        '${_currentTitle ?? "yeni_evrak"}${model.metadata['hasSignature'] == true ? '_imzasiz' : ''}.$ext';

    try {
      if (!await _confirmBlanks()) return false;
      if (!mounted) return false;
      if (model.metadata['hasSignature'] == true &&
          !await _confirmUnsignedSave()) {
        return false;
      }
      if (!mounted) return false;
      List<int> outBytes;
      if (targetFormat == EvrakFormat.udf) {
        outBytes = UdfWriter.writeBytes(model);
      } else if (targetFormat == EvrakFormat.docx) {
        outBytes = await DocxBridge.writeBytes(model);
      } else if (targetFormat == EvrakFormat.rtf) {
        outBytes = RtfWriter.writeBytes(model);
      } else if (targetFormat == EvrakFormat.pdf) {
        outBytes = await PdfService.modelToPdfBytes(
          model,
          title: _currentTitle,
        );
      } else {
        outBytes = utf8.encode(model.toPlainText());
      }

      final savePath = Platform.isAndroid
          ? await AndroidDocumentSave.save(
              fileName: defaultName,
              bytes: outBytes,
            )
          : destination ??
                await FilePicker.saveFile(
                  dialogTitle: 'Evrakı Kaydet ($ext)',
                  fileName: defaultName,
                  type: FileType.custom,
                  allowedExtensions: [ext],
                );

      if (savePath == null || !mounted) return false;
      // Another window's document is not written over from this one.
      if (!Platform.isAndroid &&
          savePath != _lockedPath &&
          await _heldByAnotherWindow(savePath)) {
        if (mounted) {
          showNotice(
            context,
            'Bu belge başka bir pencerede açık',
            detail:
                'Üzerine yazmak, o penceredeki çalışmayı kaybettirebilir. '
                'Başka bir adla kaydedin ya da önce o pencereyi kapatın.',
            kind: NoticeKind.error,
          );
        }
        return false;
      }
      final source = widget.initialFilePath;
      final overSource =
          !Platform.isAndroid &&
          source != null &&
          (p.equals(p.absolute(savePath), p.absolute(source)) ||
              (await File(savePath).exists() &&
                  await File(source).exists() &&
                  await FileSystemEntity.identical(savePath, source)));
      // A file signed after opening the editor is signed on disk even if the
      // original model's _sourceSigned flag is still false. Inspect the actual
      // destination before any overwrite, including a saved-as UDF path.
      var signedOnDisk = false;
      if (!Platform.isAndroid &&
          p.extension(savePath).toLowerCase() == '.udf' &&
          await File(savePath).exists()) {
        signedOnDisk = UdfSigningService.isSigned(
          await File(savePath).readAsBytes(),
        );
      }
      final overSigned = (overSource && _sourceSigned) || signedOnDisk;
      if (overSigned && !overwriteSigned && !await _confirmSignedOverwrite()) {
        return false;
      }
      if (!mounted) return false;

      if (!Platform.isAndroid) {
        final file = File(savePath);
        if (targetFormat != EvrakFormat.pdf && await file.exists()) {
          final kept = await _captureVersion(
            savePath,
            await file.readAsBytes(),
            ext,
            "original",
          );
          // Overwriting a signed file was agreed to on the promise that the
          // signed one stays in the history. Without it, nothing is written.
          if (!kept && overSigned) {
            if (mounted) {
              showNotice(
                context,
                'İmzalı dosyanın üzerine yazılmadı',
                detail:
                    'İmzalı hali belge geçmişine saklanamadı. Değişiklikleri '
                    'imzasız kopya olarak kaydedebilirsiniz.',
                kind: NoticeKind.error,
              );
            }
            return false;
          }
        }
        // Keep the destination semantics (including existing symlinks).
        await file.writeAsBytes(outBytes, flush: true);
        // The file on disk carries no signature any more.
        if (overSource) _sourceSigned = false;
      }
      if (targetFormat != EvrakFormat.pdf) {
        await _captureVersion(savePath, outBytes, ext, "saved");
        _learnFrom(savePath, model);
      }
      if (targetFormat != EvrakFormat.pdf) {
        // What was just written carries no signature — the writer never copies
        // one. Saying otherwise leaves a banner claiming a signature that is
        // not in the file, and makes every later save ask for a new name.
        final unsigned = model.metadata['hasSignature'] == true
            ? (Map<String, dynamic>.of(model.metadata)
                ..['hasSignature'] = false
                ..remove('signatureBytes')
                ..remove('signatureInfos'))
            : null;
        if (unsigned != null) {
          _sourceModel = DocModel(
            blocks: _sourceModel?.blocks ?? model.blocks,
            styles: _sourceModel?.styles ?? model.styles,
            pageProperties:
                _sourceModel?.pageProperties ?? model.pageProperties,
            pageRegions: _sourceModel?.pageRegions ?? model.pageRegions,
            metadata: unsigned,
          );
          _signatureNoticeShown = false;
        }
        _savedPath = savePath;
        _savedFormat = targetFormat;
        unawaited(_holdDocument());
        _baselineDelta = savedDelta;
        _baselineRegions = savedRegions;
        _baselineRegionAttrs = savedRegionAttrs;
        _baselineTableRevision = savedTables;
        _baselinePage = savedPage;
        _restoredRevision = false;
        _checkEditedSoon();
        _baselineModel = unsigned == null
            ? model
            : DocModel(
                blocks: model.blocks,
                styles: model.styles,
                pageProperties: model.pageProperties,
                pageRegions: model.pageRegions,
                metadata: unsigned,
              );
        _baselineProtected = savedProtected;
        if (!_hasChanges) {
          await _recovery.clear();
        } else {
          _recovery.changed();
          _checkEditedSoon();
        }
      }
      if (mounted) {
        widget.onSaved?.call(savePath);
        showNotice(
          context,
          Platform.isAndroid
              ? 'Belge seçtiğiniz konuma kaydedildi.'
              : 'Başarıyla kaydedildi: ${p.basename(savePath)}',
          detail: Platform.isAndroid ? null : p.dirname(savePath),
          kind: NoticeKind.success,
        );
      }
      return targetFormat != EvrakFormat.pdf && !_hasChanges;
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Kaydetme hatası: belge kaydedilemedi',
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (_readingPages) ...[
              const SizedBox(height: 16),
              const Text(
                'Bu PDF’te metin katmanı yok; sayfalar okunuyor (OCR)…',
                key: ValueKey('reading-pages'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Sayfa başına birkaç saniye sürebilir.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText('Belge açılamadı: $_loadError'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _history,
                icon: const Icon(Icons.history_rounded),
                label: const Text('Belge geçmişinden kurtar'),
              ),
            ],
          ),
        ),
      );
    }
    // Everything in the editor's frame — toolbar, rulers, the page around the
    // text, the zoom bar — counts as inside the editor. Quill drops the focus
    // on a click outside itself, so pressing the bold button left the
    // keyboard with nobody, and the next Delete or Ctrl+B did nothing.
    return TextFieldTapRegion(
      child: CallbackShortcuts(
        bindings: {
          for (final entry in _shortcuts.entries)
            entry.key: () =>
                _command((entry.value as _EditorCommandIntent).command),
        },
        child: Column(
          children: [
            Container(
              key: const ValueKey('editor-toolbar'),
              height:
                  MediaQuery.sizeOf(context).width >= 1000 &&
                      MediaQuery.sizeOf(context).height >= 550
                  ? 88
                  : 44,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                ),
              ),
              child: Row(
                children: [
                  EditorFileMenu(
                    controller: _fileMenu,
                    host: widget.fileHost,
                    currentPath: _documentPath,
                    busy: _isSaving || _signingNew || _sendingUyap,
                    // The short toolbar has no room for a label under an icon.
                    compact:
                        MediaQuery.sizeOf(context).width < 1000 ||
                        MediaQuery.sizeOf(context).height < 550,
                    onSave: () => unawaited(_save()),
                    onSaveAs: () => unawaited(_saveAs(_ownFormat)),
                    onSaveIn: (format) => unawaited(_saveAs(format)),
                    onPrint: () => unawaited(_print()),
                    onHistory: () => unawaited(_history()),
                    onSign: _canSignNew ? () => unawaited(_signNew()) : null,
                    onSendUyap:
                        Platform.isLinux ||
                            Platform.isWindows ||
                            Platform.isMacOS
                        ? () => unawaited(_sendToUyap())
                        : null,
                    onUyapOperations:
                        Platform.isLinux ||
                            Platform.isWindows ||
                            Platform.isMacOS
                        ? () => unawaited(_openUyapOperations())
                        : null,
                    onNewWindow: EditorWindow.available
                        ? () => unawaited(EditorWindow.open())
                        : null,
                  ),
                  Expanded(
                    child: EditorToolbar(
                      controller: _active,
                      onFind: _find,
                      onHistory: _history,
                      onSnippets: () => unawaited(_snippets()),
                      onReadAloud: speechAvailable
                          ? () => unawaited(_readAloud())
                          : null,
                      onDictate: speechAvailable
                          ? () => unawaited(_dictate())
                          : null,
                      onCaseLaw: () =>
                          setState(() => _caseLawOpen = !_caseLawOpen),
                      caseLawOpen: _caseLawOpen,
                      onUyapCase:
                          Platform.isLinux ||
                              Platform.isWindows ||
                              Platform.isMacOS
                          ? _toggleUyap
                          : null,
                      uyapCaseOpen: _uyapOpen,
                      onReplace: () => _find(replace: true),
                      onPrint: _print,
                      onInsertImage: _insertImage,
                      onInsertTable: _insertTable,
                      hasHeader: _regions.containsKey('header'),
                      hasFooter: _regions.containsKey('footer'),
                      onToggleRegion: (key) => switch (key) {
                        'page-numbers' => _pageNumbers(),
                        'letterheads' => _letterheads(),
                        _ => _toggleRegion(key),
                      },
                      onHelp: _showShortcuts,
                      onHorizontalRuler: () => setState(
                        () => _showHorizontalRuler = !_showHorizontalRuler,
                      ),
                      onVerticalRuler: () => setState(
                        () => _showVerticalRuler = !_showVerticalRuler,
                      ),
                      showHorizontalRuler: _showHorizontalRuler,
                      showVerticalRuler: _showVerticalRuler,
                      onFontSelected: (name) async {
                        try {
                          await DocumentFonts.loadEditorFamilies([name]);
                          if (mounted) setState(() {});
                        } catch (e) {
                          if (context.mounted) {
                            showNotice(
                              context,
                              'Yazı tipi yüklenemedi',
                              detail: '$e',
                              kind: NoticeKind.error,
                            );
                          }
                        }
                      },
                    ),
                  ),
                  if (_leftDraft != null)
                    LeftDraftButton(
                      draft: _leftDraft!,
                      onPressed: _leftDraftMenu,
                    ),
                  if (_canSignNew)
                    IconButton(
                      tooltip: 'UDF e-imzala',
                      onPressed: _isSaving || _signingNew ? null : _signNew,
                      icon: const Icon(Icons.draw_outlined, size: 20),
                    ),
                  if (_sourceModel?.metadata['hasSignature'] == true)
                    SizedBox(
                      width: MediaQuery.sizeOf(context).width < 700 ? 120 : 180,
                      child: SignatureBanner(
                        model: _sourceModel!,
                        compact: true,
                      ),
                    ),
                  IconButton(
                    tooltip: 'Kaydet · Ctrl+S',
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined, size: 19),
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary
                          .withValues(alpha: .10),
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Row(
                children: [
                  // The page keeps the room it had; the search takes its
                  // own beside it rather than pushing the document over.
                  Expanded(
                    child: Column(
                      children: [
                        if (_heldElsewhere) _heldElsewhereBanner(context),
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    // A4 exactly, as the preview lays it out: the
                                    // 595.28 this used to round to made the page a
                                    // hair wider, enough for a word the preview
                                    // put on the next row to stay on this one.
                                    final widthPoints =
                                        _pageProperties.landscape
                                        ? PdfPageFormat.a4.height
                                        : PdfPageFormat.a4.width;
                                    final heightPoints =
                                        _pageProperties.landscape
                                        ? PdfPageFormat.a4.width
                                        : PdfPageFormat.a4.height;
                                    // The page is laid out in points and drawn
                                    // larger (see EditorUnits).
                                    const scale = EditorUnits.pixelsPerPoint;
                                    final paperWidth = widthPoints * scale;
                                    final paperHeight = heightPoints * scale;
                                    // The text area of every page, by UYAP's rule.
                                    final area = EditorPages.textArea(
                                      _pageProperties,
                                      header: _regionHeight('header'),
                                      footer: _regionHeight('footer'),
                                    );
                                    final textTop = area.top;
                                    final textBottom = area.bottom;
                                    final pages = EditorPages.geometry(
                                      _pageProperties,
                                      header: _regionHeight('header'),
                                      footer: _regionHeight('footer'),
                                    );
                                    void margins(
                                      bool horizontal,
                                      double start,
                                      double end,
                                    ) => setState(() {
                                      _recovery.changed();
                                      _checkEditedSoon();
                                      _pageProperties = DocPageProperties(
                                        marginLeft: horizontal
                                            ? start
                                            : _pageProperties.marginLeft,
                                        marginRight: horizontal
                                            ? end
                                            : _pageProperties.marginRight,
                                        marginTop: horizontal
                                            ? _pageProperties.marginTop
                                            : start,
                                        marginBottom: horizontal
                                            ? _pageProperties.marginBottom
                                            : end,
                                        landscape: _pageProperties.landscape,
                                        headerOffset:
                                            _pageProperties.headerOffset,
                                        footerOffset:
                                            _pageProperties.footerOffset,
                                      );
                                      // A header breaks its lines at the page's
                                      // width.
                                      _measureRegionsSoon();
                                    });
                                    // A page is a facsimile of paper: twelve point is twelve
                                    // point whether or not Windows has been told to enlarge
                                    // text. Left scaled, the type grew while the page stayed the
                                    // width it prints at, and a table that fits on paper spilled
                                    // over three lines a cell. The setting still reaches the
                                    // toolbar and the menus, which is where it belongs.
                                    return MediaQuery.withNoTextScaling(
                                      child: EditorPageViewport(
                                        status: _citationStatus(context),
                                        drawer: _citationDrawer(),
                                        background: isDark
                                            ? const Color(0xFF17191D)
                                            : const Color(0xFFE9ECF1),
                                        pageWidth:
                                            (paperWidth +
                                                (_showVerticalRuler ? 24 : 0)) *
                                            EditorUnits.screenScale,
                                        child: Column(
                                          children: [
                                            if (_showHorizontalRuler)
                                              Padding(
                                                padding: EdgeInsets.only(
                                                  left: _showVerticalRuler
                                                      ? 24
                                                      : 0,
                                                  bottom: 6,
                                                ),
                                                child: DocumentRuler(
                                                  axis: Axis.horizontal,
                                                  pagePoints: widthPoints,
                                                  pixels: paperWidth,
                                                  leading: _pageProperties
                                                      .marginLeft,
                                                  trailing: _pageProperties
                                                      .marginRight,
                                                  onChanged: (start, end) =>
                                                      margins(true, start, end),
                                                ),
                                              ),
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                _paged(
                                                  scale: scale,
                                                  paperHeight: paperHeight,
                                                  heightPoints: heightPoints,
                                                  onMargins: (start, end) =>
                                                      margins(
                                                        false,
                                                        start,
                                                        end,
                                                      ),
                                                  textTop: textTop,
                                                  textBottom: textBottom,
                                                  child: CustomPaint(
                                                    painter: EditorSheetsPainter(
                                                      pageHeight: paperHeight,
                                                      gutter:
                                                          EditorSheetsPainter
                                                              .room,
                                                    ),
                                                    child: Container(
                                                      key: const ValueKey(
                                                        'editor-paper',
                                                      ),
                                                      width: paperWidth,
                                                      padding: EdgeInsets.fromLTRB(
                                                        _pageProperties
                                                                .marginLeft *
                                                            scale,
                                                        textTop * scale,
                                                        _pageProperties
                                                                .marginRight *
                                                            scale,
                                                        textBottom * scale,
                                                      ),
                                                      child: _paperTheme(
                                                        context,
                                                        DefaultTextStyle(
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .black,
                                                              ),
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .stretch,
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              ConstrainedBox(
                                                                constraints:
                                                                    const BoxConstraints(),
                                                                child: Listener(
                                                                  onPointerDown:
                                                                      _bodyClicked,
                                                                  child: QuillEditor.basic(
                                                                    controller:
                                                                        _quillController,
                                                                    focusNode:
                                                                        _editorFocus,
                                                                    config: QuillEditorConfig(
                                                                      editorKey:
                                                                          _editorKey,
                                                                      // Without this a tab is drawn as one
                                                                      // space and the columns a filing is
                                                                      // laid out in collapse.
                                                                      textSpanBuilder: EditorTabSpans.builder(
                                                                        spelling:
                                                                            _spelling,
                                                                        citations:
                                                                            _citationMarks,
                                                                        pageWidth:
                                                                            widthPoints -
                                                                            _pageProperties.marginLeft -
                                                                            _pageProperties.marginRight,
                                                                      ),
                                                                      lineLayoutBuilder: EditorLineLayout.builder(
                                                                        pageWidth:
                                                                            widthPoints -
                                                                            _pageProperties.marginLeft -
                                                                            _pageProperties.marginRight,
                                                                      ),
                                                                      contextMenuBuilder:
                                                                          _contextMenu,
                                                                      embedBuilders: [
                                                                        EditorImageEmbed(),
                                                                        EditorTableEmbed(
                                                                          word: () =>
                                                                              _sourceModel?.metadata['tabRules'] == 'word',
                                                                          blocks: () =>
                                                                              _korunanBloklar,
                                                                          onChanged:
                                                                              _tableChanged,
                                                                          onFocus:
                                                                              _cellFocused,
                                                                          onDelete:
                                                                              _deleteTable,
                                                                          onCellsGone:
                                                                              _cellsGone,
                                                                          onPointerInside: () =>
                                                                              _clickedInTable = true,
                                                                        ),
                                                                      ],
                                                                      customStyles: DefaultStyles(
                                                                        paragraph: DefaultTextBlockStyle(
                                                                          TextStyle(
                                                                            color:
                                                                                Colors.black,
                                                                            fontFamily: DocumentFonts.family(
                                                                              'Times New Roman',
                                                                            ),
                                                                            fontSize:
                                                                                12,
                                                                            height:
                                                                                1.15,
                                                                          ),
                                                                          const HorizontalSpacing(
                                                                            0,
                                                                            0,
                                                                          ),
                                                                          const VerticalSpacing(
                                                                            0,
                                                                            0,
                                                                          ),
                                                                          const VerticalSpacing(
                                                                            0,
                                                                            0,
                                                                          ),
                                                                          null,
                                                                        ),
                                                                        // A list item is set as a paragraph,
                                                                        // with no room between items that
                                                                        // UYAP and the page do not have.
                                                                        lists: DefaultListBlockStyle(
                                                                          TextStyle(
                                                                            color:
                                                                                Colors.black,
                                                                            fontFamily: DocumentFonts.family(
                                                                              'Times New Roman',
                                                                            ),
                                                                            fontSize:
                                                                                12,
                                                                            height:
                                                                                1.15,
                                                                          ),
                                                                          const HorizontalSpacing(
                                                                            0,
                                                                            0,
                                                                          ),
                                                                          const VerticalSpacing(
                                                                            0,
                                                                            0,
                                                                          ),
                                                                          const VerticalSpacing(
                                                                            0,
                                                                            0,
                                                                          ),
                                                                          null,
                                                                          null,
                                                                        ),
                                                                        // Nor between the lines of an indented block, which Quill spaces
                                                                        // 6 apart by default: the page does not.
                                                                        indent: DefaultTextBlockStyle(
                                                                          TextStyle(
                                                                            color:
                                                                                Colors.black,
                                                                            fontFamily: DocumentFonts.family(
                                                                              'Times New Roman',
                                                                            ),
                                                                            fontSize:
                                                                                12,
                                                                            height:
                                                                                1.15,
                                                                          ),
                                                                          const HorizontalSpacing(
                                                                            0,
                                                                            0,
                                                                          ),
                                                                          const VerticalSpacing(
                                                                            0,
                                                                            0,
                                                                          ),
                                                                          const VerticalSpacing(
                                                                            0,
                                                                            0,
                                                                          ),
                                                                          null,
                                                                        ),
                                                                      ),
                                                                      // ignore: experimental_member_use
                                                                      onKeyPressed:
                                                                          _onKey,
                                                                      customShortcuts:
                                                                          _shortcuts,
                                                                      customActions: {
                                                                        _EditorCommandIntent: CallbackAction<_EditorCommandIntent>(
                                                                          onInvoke: (intent) {
                                                                            _command(
                                                                              intent.command,
                                                                            );
                                                                            return null;
                                                                          },
                                                                        ),
                                                                      },
                                                                      customStyleBuilder:
                                                                          (
                                                                            attribute,
                                                                          ) => attribute.key == 'font'
                                                                          ? TextStyle(
                                                                              fontFamily: DocumentFonts.family(
                                                                                attribute.value as String?,
                                                                              ),
                                                                            )
                                                                          : const TextStyle(),
                                                                      autoFocus:
                                                                          widget
                                                                              .isActive,
                                                                      pages:
                                                                          pages,
                                                                      scrollable:
                                                                          false,
                                                                      expands:
                                                                          false,
                                                                      padding:
                                                                          EdgeInsets
                                                                              .zero,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              // Reading aloud and dictation, over the page
                              // they are working on.
                              if (speechAvailable)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 18,
                                  child: Center(child: SpeechBar(owner: this)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_evrakPath != null) ...[
                    ResizeHandle(
                      onDrag: (dx) => setState(
                        () => _evrakWidth = (_evrakWidth - dx).clamp(
                          320.0,
                          1100.0,
                        ),
                      ),
                    ),
                    SizedBox(width: _evrakWidth, child: _evrakPane(context)),
                  ],
                  if (_uyapOpen) ...[
                    ResizeHandle(
                      onDrag: (dx) => setState(
                        () =>
                            _uyapWidth = (_uyapWidth - dx).clamp(300.0, 700.0),
                      ),
                    ),
                    SizedBox(
                      width: _uyapWidth,
                      child: UyapCasePanel(
                        controller: _uyap,
                        onOpen: (file, document) => setState(() {
                          _evrakPath = file.path;
                          _evrakTitle = document.title;
                        }),
                        onInsert: _writeHeard,
                        onClose: _toggleUyap,
                      ),
                    ),
                  ],
                  if (_caseLawOpen) ...[
                    VerticalDivider(
                      width: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    SizedBox(
                      width: 420,
                      child: CaseLawSearchScreen(bank: _caseLaw, compact: true),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The document's controller, which stands down while a table cell is being
/// typed in.
///
/// A cell is a small editor of its own drawn inside the document, so the
/// document editor's focus node counts a cell's cursor as its own focus. On a
/// desktop Quill asks for the keyboard again on every change and every
/// selection it notices, grants the request whenever that node reports focus,
/// and so took the platform's text input back from the cell: the cursor
/// stayed in the cell and the letters landed in the document. Worse, the
/// editor that then held the keyboard still measured its edits against the
/// cell's text, so a backspace at the head of a cell poured the whole
/// document into it.
///
/// [QuillController.skipRequestKeyboard] is the editor's own way of declining
/// that request. Quill means it as a one-shot and clears it as it reads it,
/// so a cell's cursor is held here instead and answers for as long as it is
/// there.
///
/// The two levers that look simpler both fail. Reporting no focus makes Quill
/// claim the focus back rather than the keyboard, and the two editors fight
/// over it without end. Marking the document read-only takes the table apart
/// and rebuilds it, which throws away the cell being typed in.
class _DocumentController extends QuillController with EditorClipboard {
  _DocumentController()
    : super(
        document: Document(),
        selection: const TextSelection.collapsed(offset: 0),
      );

  /// Whether a table cell currently holds the cursor.
  bool cellHasCursor = false;

  bool _once = false;

  @override
  bool get skipRequestKeyboard => cellHasCursor || _once;

  @override
  set skipRequestKeyboard(bool value) => _once = value;
}

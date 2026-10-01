import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../services/annotations/pdf_annotation.dart';
import '../../services/editor/text_anchor.dart';
import '../../services/legal/case_law.dart';
import '../../services/legal/citation.dart';
import '../../services/legal/decision.dart';
import '../../services/legal/legal_settings.dart';
import '../../services/legal/legislation.dart';
import '../../services/legal/pdf_citations.dart';
import '../../services/preview/pdf_fonts.dart';
import '../../services/search/library_controller.dart';
import '../../models/evrak_file.dart';
import '../../services/ocr/preview_ocr.dart';
import 'ocr_text_panel.dart';
import 'swipe_pages.dart';
import 'page_jump.dart';
import 'page_zoom.dart';
import 'viewer_shortcuts.dart';
import 'pdf_context_menu.dart';
import 'article_panel.dart';
import 'citation_list_panel.dart';
import 'editor_citations.dart';
import 'notice.dart';

enum _PageFit { reading, page, width, manual }

/// The exact text the PDF viewer exposes to selection/copy, page by page.
typedef PdfTextLoader = Future<String?> Function();

class PdfViewerWidget extends StatefulWidget {
  final String? filePath;
  final Uint8List? bytes;

  /// Highlights are stored per file. A preview rendered from bytes (a UDF or
  /// DOCX drawn to PDF) has no file of its own, so it is never marked up.
  final LibraryController? library;

  /// Called when a finger swipe runs past the first or last page, so the
  /// reader carries on to the document beside this one.
  final void Function(bool forward)? onPastEnd;

  /// Whether to show the viewer's own row of buttons. In full screen the page
  /// is the point, and every strip of chrome is screen it does not get.
  final bool chrome;

  /// The page this document was last left on, so coming back to it opens
  /// where the reading stopped. One based, like the page numbers shown.
  final int? initialPage;

  /// Reports the page being read, so it can be come back to.
  final void Function(int page)? onPageChanged;

  /// Supplies the same PDFium text used by selection and copy. The editor can
  /// reuse the already-open document instead of parsing it through a second,
  /// differently ordered text extractor.
  final ValueChanged<PdfTextLoader?>? onTextLoaderChanged;

  /// Asks for the document to be edited at the place double-clicked. Given
  /// only where the pages are drawn from a document that can be edited — a
  /// UDF or DOCX, not a PDF — and where a double-click is a mouse's.
  final ValueChanged<TextAnchor>? onEditAt;

  const PdfViewerWidget({
    super.key,
    this.filePath,
    this.bytes,
    this.library,
    this.onPastEnd,
    this.chrome = true,
    this.initialPage,
    this.onPageChanged,
    this.onTextLoaderChanged,
    this.onEditAt,
  }) : assert(filePath != null || bytes != null);

  @override
  State<PdfViewerWidget> createState() => _PdfViewerWidgetState();
}

class _PdfViewerWidgetState extends State<PdfViewerWidget> {
  final PdfViewerController _controller = PdfViewerController();

  /// Finding a word in a document you are only reading.
  ///
  /// The editor has had Ctrl+F all along and the preview had nothing, so a
  /// name in a forty page scan meant either scrolling for it or opening the
  /// document for editing first. A rendered UDF or DOCX is shown through
  /// this same viewer, so they all gain it at once.
  /// Made once the document is open: the searcher reads the document in its
  /// own constructor, and there is none to read before then.
  PdfTextSearcher? _search;
  final _searchField = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'pdf-search');
  bool _searching = false;

  void _searched() {
    if (mounted) setState(() {});
  }

  void _openSearch() {
    if (_search == null) return;
    setState(() => _searching = true);
    _searchFocus.requestFocus();
    _searchField.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchField.text.length,
    );
  }

  void _closeSearch() {
    _search?.resetTextSearch();
    _searchField.clear();
    setState(() => _searching = false);
  }

  int _pageCount = 0;
  int _currentPage = 1;
  _PageFit _fit = _PageFit.reading;
  late PdfDocumentRef _documentRef;

  late final _ocr = PreviewOcr(library: widget.library);
  bool _showOcrText = false;
  List<PdfHighlight> _highlights = const [];
  PdfTextSelection? _selection;
  bool _hasSelection = false;
  int _color = PdfHighlight.palette.first;

  /// Quarter turns the reader has applied, relative to the document as loaded.
  /// `PdfPageRotated` swaps width/height but forwards `loadText()` untouched, so
  /// character rectangles always stay in the unrotated page space. Highlights
  /// are stored there too and turned only when drawn.
  int _quarterTurns = 0;

  /// The laws each page cites, read from the page's own text layer as it
  /// comes into view. Null until the table of laws has loaded.
  PdfCitations? _citations;

  /// Whether the list of what this document rests on is open at the foot.
  bool _citationListOpen = false;

  /// Everything found so far, across the pages that have been read. The
  /// list fills as the reader moves through the document rather than
  /// waiting for all of it, which on a long filing would be a long wait.
  List<PdfCitation> get _allCited {
    final out = <PdfCitation>[];
    final seen = <String>{};
    for (var page = 1; page <= _pageCount; page++) {
      for (final one in _citations?.found(page) ?? const <PdfCitation>[]) {
        final key = one.isDecision
            ? 'k:${one.decision!.esas}|${one.decision!.karar}'
            : 'm:${one.citation!.law.number}|${one.citation!.article}';
        if (seen.add(key)) out.add(one);
      }
    }
    return out;
  }

  final _legislation = Legislation();
  final _caseLaw = CaseLaw();

  bool get _canHighlight => widget.library != null && widget.filePath != null;

  Future<String?> _loadCopyableText() async {
    if (!_controller.isReady) return null;
    final pages = <String>[];
    for (final page in _controller.document.pages) {
      final text = await page.loadText();
      pages.add(
        (text?.fullText ?? '').replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
      );
    }
    final joined = pages.join('\n\n');
    return joined.trim().isEmpty ? null : joined;
  }

  @override
  void initState() {
    super.initState();
    _setDocumentRef();
    _loadHighlights();
    unawaited(_loadCitationScanner());
    _ocr.attach(widget.filePath, EvrakFormat.pdf);
  }

  Future<void> _loadCitationScanner() async {
    if (!LegalSettings.instance.articles) return;
    try {
      final scanner = await CitationScanner.load();
      final decisions = LegalSettings.instance.decisions
          ? await DecisionScanner.load()
          : null;
      if (!mounted) return;
      setState(() => _citations = PdfCitations(scanner, decisions));
    } on Object {
      // No table, no citations. The viewer is not otherwise affected.
    }
  }

  /// Reads a page as it comes into view, and redraws when it has something.
  void _readCitations(PdfPage page) {
    final citations = _citations;
    if (citations == null ||
        !LegalSettings.instance.articles ||
        citations.found(page.pageNumber) != null) {
      return;
    }
    unawaited(
      citations.read(page, quarterTurns: _quarterTurns).then((found) {
        if (!mounted) return;
        if (found) {
          setState(() {});
          return;
        }
        // The page was not ready to give up its text. Nothing else would
        // ask again on its own, so one nudge is scheduled; the read itself
        // gives up after a few of these.
        Future<void>.delayed(const Duration(milliseconds: 400), () {
          if (mounted) setState(() {});
        });
      }),
    );
  }

  bool _onGeneralTap(
    BuildContext context,
    PdfViewerController controller,
    PdfViewerGeneralTapHandlerDetails details,
  ) {
    final edit = widget.onEditAt;
    if (edit == null || details.type != PdfViewerGeneralTapType.doubleTap) {
      return false;
    }
    final hit = controller.getPdfPageHitTestResult(
      details.documentPosition,
      useDocumentLayoutCoordinates: true,
    );
    unawaited(
      _anchorAt(hit).then((anchor) {
        if (mounted) edit(anchor);
      }),
    );
    return true;
  }

  /// Where a double-click fell, in a form the editor can find again: the
  /// line under the pointer, read from the page's own text layer.
  Future<TextAnchor> _anchorAt(PdfPageHitTestResult? hit) async {
    final pages = math.max(_pageCount, 1);
    if (hit == null) return TextAnchor(page: _currentPage, pages: pages);
    final page = hit.page;
    // The text layer stays in the unturned page; a turned one is only
    // placed by its page.
    if (_quarterTurns % 4 != 0) {
      return TextAnchor(page: page.pageNumber, pages: pages);
    }
    PdfPageRawText? text;
    try {
      text = await page.loadText();
    } catch (_) {
      // Without its text the page still tells how far in the place is.
    }
    return TextAnchor.onPage(
      page: page.pageNumber,
      pages: pages,
      height: page.height,
      x: hit.offset.x,
      y: hit.offset.y,
      text: text?.fullText ?? '',
      boxes: [
        for (final box in text?.charRects ?? const <PdfRect>[])
          (left: box.left, top: box.top, right: box.right, bottom: box.bottom),
      ],
    );
  }

  /// Shows the article or the decision a citation points at, over the page.
  void _onCitationTap(PdfCitation mark, Offset at) {
    if (!mounted) return;
    final decision = mark.decision;
    if (decision != null) {
      DecisionPanel.show(
        context,
        citation: decision,
        lookup: () => _caseLaw.lookup(decision),
        at: at,
      );
      return;
    }
    final citation = mark.citation;
    if (citation == null) return;
    ArticlePanel.show(
      context,
      citation: citation,
      lookup: () => _legislation.lookup(citation),
      at: at,
    );
  }

  @override
  void dispose() {
    widget.onTextLoaderChanged?.call(null);
    _search
      ?..removeListener(_searched)
      ..dispose();
    _searchField.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadHighlights() async {
    if (!_canHighlight) return;
    final path = widget.filePath!;
    final marks = await widget.library!.highlights(path);
    // The viewer can be handed another document while this is in flight.
    if (!mounted || widget.filePath != path) return;
    setState(() => _highlights = marks);
  }

  Future<void> _addHighlight() async {
    final selection = _selection;
    if (!_canHighlight || selection == null || !selection.hasSelectedText) {
      return;
    }
    final path = widget.filePath!;
    final document = _controller.isReady ? _controller.document : null;
    if (document == null) return;

    final ranges = await selection.getSelectedTextRanges();
    final created = DateTime.now().millisecondsSinceEpoch;
    final saved = <PdfHighlight>[];
    for (final range in ranges) {
      if (range.end <= range.start) continue;
      final page = document.pages[range.pageNumber - 1];
      // A turned page reports swapped dimensions while its text rectangles stay
      // in the original space, so normalize against the unrotated box.
      final swapped = _quarterTurns.isOdd;
      final baseWidth = swapped ? page.height : page.width;
      final baseHeight = swapped ? page.width : page.height;
      final charRects = range.pageText.charRects;
      final boxes = <NormRect>[];
      for (var i = range.start; i < range.end && i < charRects.length; i++) {
        final r = charRects[i];
        if (r.isEmpty) continue;
        boxes.add(
          NormRect.fromPdf(
            r.left,
            r.top,
            r.right,
            r.bottom,
            baseWidth,
            baseHeight,
          ),
        );
      }
      final rects = PdfHighlight.mergeLines(boxes);
      if (rects.isEmpty) continue;
      try {
        saved.add(
          await widget.library!.saveHighlight(
            PdfHighlight(
              docKey: PdfHighlight.keyFor(path),
              path: path,
              page: range.pageNumber,
              rects: rects,
              text: range.text,
              color: _color,
              created: created,
            ),
          ),
        );
      } catch (error) {
        if (!mounted) return;
        showNotice(
          context,
          'Vurgu kaydedilemedi',
          detail: '$error',
          kind: NoticeKind.error,
        );
        return;
      }
    }
    if (!mounted || widget.filePath != path) return;
    setState(() => _highlights = [..._highlights, ...saved]);
    await _controller.textSelectionDelegate.clearTextSelection();
  }

  /// Tapping a highlight opens a menu rather than deleting outright: a stray
  /// tap while reading must not silently remove a mark.
  Future<void> _onHighlightTap(PdfHighlight mark, Offset globalPosition) async {
    if (!_canHighlight) return;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        for (final color in PdfHighlight.palette)
          PopupMenuItem(
            value: 'color:$color',
            height: 36,
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Color(color),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(mark.color == color ? 'Bu renk' : 'Rengi değiştir'),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: Text('Vurguyu sil')),
      ],
    );
    if (choice == null || !mounted) return;
    if (choice == 'delete') {
      await widget.library!.deleteHighlight(mark.id);
      if (!mounted) return;
      setState(
        () => _highlights = _highlights.where((h) => h.id != mark.id).toList(),
      );
      return;
    }
    final color = int.parse(choice.substring('color:'.length));
    final updated = mark.copyWith(color: color);
    await widget.library!.saveHighlight(updated);
    if (!mounted) return;
    setState(
      () => _highlights = [
        for (final h in _highlights) h.id == mark.id ? updated : h,
      ],
    );
  }

  void _setDocumentRef() {
    _documentRef = widget.bytes != null
        ? PdfDocumentRefData(
            widget.bytes!,
            sourceName: widget.filePath ?? 'preview.pdf',
          )
        : PdfDocumentRefFile(widget.filePath!);
  }

  @override
  void didUpdateWidget(covariant PdfViewerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath ||
        !identical(oldWidget.bytes, widget.bytes)) {
      _setDocumentRef();
      _pageCount = 0;
      _currentPage = 1;
      _fit = _PageFit.reading;
      _highlights = const [];
      _selection = null;
      _hasSelection = false;
      _quarterTurns = 0;
      _showOcrText = false;
      // What was read belongs to the document that has gone.
      _citations?.clear();
      _loadHighlights();
      _ocr.attach(widget.filePath, EvrakFormat.pdf);
    }
  }

  void _applyFit({bool animate = true}) {
    if (!mounted || !_controller.isReady || _fit == _PageFit.manual) return;
    final page = _controller.layout.pageLayouts[_currentPage - 1];
    final widthZoom =
        (_controller.viewSize.width - _controller.params.margin * 2) /
        page.width;
    // The size the editor opens the same page at (see PageZoom), narrowed
    // only where the window cannot hold it.
    final readingZoom = math.min(
      widthZoom,
      PageZoom.forPdfViewer(PageZoom.initial),
    );
    final matrix = switch (_fit) {
      _PageFit.page => _controller.calcMatrixForFit(pageNumber: _currentPage),
      _PageFit.width => _controller.calcMatrixFitWidthForPage(
        pageNumber: _currentPage,
      ),
      _ => _controller.calcMatrixFor(
        page.topCenter.translate(
          0,
          (_controller.viewSize.height / 2 - _controller.params.margin) /
              readingZoom,
        ),
        zoom: readingZoom,
      ),
    };
    _controller.goTo(
      matrix,
      duration: animate && !MediaQuery.disableAnimationsOf(context)
          ? const Duration(milliseconds: 160)
          : Duration.zero,
    );
  }

  void _rotate(bool clockwise) {
    if (!_controller.isReady) return;
    final document = _controller.document;
    final page = _currentPage;
    // Rotate page views in memory, keeping navigation vertical and source bytes intact.
    document.pages = [
      for (final page in document.pages)
        page.rotatedBy(
          clockwise
              ? PdfPageRotation.clockwise90
              : PdfPageRotation.clockwise270,
        ),
    ];
    _quarterTurns = (_quarterTurns + (clockwise ? 1 : 3)) % 4;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.isReady) return;
      _currentPage = page;
      if (_fit == _PageFit.manual) {
        _controller.goToPage(pageNumber: page, duration: Duration.zero);
      } else {
        _applyFit(animate: false);
      }
    });
  }

  /// Whether a sideways drag has any panning to do. Once the page is wider
  /// than the window, dragging moves it; until then the gesture is free.
  bool get _canSwipe {
    if (!_controller.isReady) return false;
    try {
      final page = _controller.layout.pageLayouts[_currentPage - 1];
      return page.width * _controller.currentZoom <=
          _controller.viewSize.width + 1;
    } catch (_) {
      return false;
    }
  }

  void _swipe(bool forward) {
    final next = _currentPage + (forward ? 1 : -1);
    if (next >= 1 && next <= _pageCount) {
      _goToPage(next);
      return;
    }
    // Nothing left in this document; the next one is what the reader wants.
    widget.onPastEnd?.call(forward);
  }

  void _goToPage(int page) {
    if (!_controller.isReady) return;
    setState(() => _currentPage = page.clamp(1, _pageCount));
    widget.onPageChanged?.call(_currentPage);
    if (_fit == _PageFit.manual) {
      _controller.goToPage(pageNumber: _currentPage);
    } else {
      _applyFit();
    }
  }

  Widget _searchBar() {
    final scheme = Theme.of(context).colorScheme;
    final search = _search;
    if (search == null) return const SizedBox.shrink();
    final found = search.matches.length;
    final at = search.currentIndex;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: scheme.surfaceContainerHighest,
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): _closeSearch,
                const SingleActivator(LogicalKeyboardKey.enter): () =>
                    search.goToNextMatch(),
                const SingleActivator(
                  LogicalKeyboardKey.enter,
                  shift: true,
                ): () =>
                    search.goToPrevMatch(),
              },
              child: TextField(
                controller: _searchField,
                focusNode: _searchFocus,
                autofocus: true,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Belgede bul',
                ),
                onChanged: (value) => value.isEmpty
                    ? search.resetTextSearch()
                    : search.startTextSearch(value, caseInsensitive: true),
              ),
            ),
          ),
          Text(
            _searchField.text.isEmpty
                ? ''
                : found == 0
                ? (search.isSearching ? 'aranıyor…' : 'bulunamadı')
                : '${(at ?? 0) + 1} / $found',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          _button(
            'Önceki · Shift+Enter',
            Icons.keyboard_arrow_up_rounded,
            found == 0 ? null : () => search.goToPrevMatch(),
          ),
          _button(
            'Sonraki · Enter',
            Icons.keyboard_arrow_down_rounded,
            found == 0 ? null : () => search.goToNextMatch(),
          ),
          _button('Kapat · Esc', Icons.close_rounded, _closeSearch),
        ],
      ),
    );
  }

  Widget _button(String tooltip, IconData icon, VoidCallback? action) =>
      IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 19),
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: EdgeInsets.zero,
        onPressed: action,
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = _controller.isReady;
    return Column(
      children: [
        if (widget.chrome)
          Container(
            key: const ValueKey('pdf-toolbar'),
            width: double.infinity,
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _button(
                    'İlk Sayfa',
                    Icons.first_page_rounded,
                    _currentPage > 1 ? () => _goToPage(1) : null,
                  ),
                  _button(
                    'Önceki Sayfa',
                    Icons.chevron_left_rounded,
                    _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
                  ),
                  PageJump(
                    label:
                        '$_currentPage / ${_pageCount > 0 ? _pageCount : "—"}',
                    current: _currentPage,
                    count: _pageCount,
                    onGo: _goToPage,
                  ),
                  _button(
                    'Sonraki Sayfa',
                    Icons.chevron_right_rounded,
                    _currentPage < _pageCount
                        ? () => _goToPage(_currentPage + 1)
                        : null,
                  ),
                  _button(
                    'Son Sayfa',
                    Icons.last_page_rounded,
                    _currentPage < _pageCount
                        ? () => _goToPage(_pageCount)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  _button(
                    'Uzaklaştır',
                    Icons.remove_rounded,
                    ready
                        ? () {
                            setState(() => _fit = _PageFit.manual);
                            _controller.zoomDown();
                          }
                        : null,
                  ),
                  _button(
                    'Yakınlaştır',
                    Icons.add_rounded,
                    ready
                        ? () {
                            setState(() => _fit = _PageFit.manual);
                            _controller.zoomUp();
                          }
                        : null,
                  ),
                  const SizedBox(width: 8),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<_PageFit>(
                      value: _fit,
                      isDense: true,
                      style: TextStyle(
                        fontFamily: 'LiberationSans',
                        fontSize: 12,
                        color: scheme.onSurface,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: _PageFit.reading,
                          child: Text('%120'),
                        ),
                        DropdownMenuItem(
                          value: _PageFit.page,
                          child: Text('Sayfaya sığdır'),
                        ),
                        DropdownMenuItem(
                          value: _PageFit.width,
                          child: Text('Genişliğe sığdır'),
                        ),
                        DropdownMenuItem(
                          value: _PageFit.manual,
                          child: Text('Serbest yakınlaştırma'),
                        ),
                      ],
                      onChanged: ready
                          ? (fit) {
                              setState(() => _fit = fit!);
                              _applyFit();
                            }
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _button(
                    'Sola 90° döndür',
                    Icons.rotate_left_rounded,
                    ready ? () => _rotate(false) : null,
                  ),
                  _button(
                    'Sağa 90° döndür',
                    Icons.rotate_right_rounded,
                    ready ? () => _rotate(true) : null,
                  ),
                  const SizedBox(width: 8),
                  OcrTextButton(
                    ocr: _ocr,
                    format: EvrakFormat.pdf,
                    showing: _showOcrText,
                    onToggle: (v) => setState(() => _showOcrText = v),
                  ),
                  if (_allCited.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _button(
                      'Dayanaklar · madde ve kararlar',
                      Icons.format_list_bulleted_rounded,
                      () => setState(
                        () => _citationListOpen = !_citationListOpen,
                      ),
                    ),
                  ],
                  if (_canHighlight) ...[
                    const SizedBox(width: 8),
                    _button(
                      _hasSelection
                          ? 'Seçimi vurgula'
                          : 'Vurgulamak için metin seçin',
                      Icons.border_color_rounded,
                      _hasSelection ? _addHighlight : null,
                    ),
                    for (final color in PdfHighlight.palette)
                      _ColorDot(
                        color: Color(color),
                        selected: _color == color,
                        onTap: () => setState(() => _color = color),
                      ),
                  ],
                ],
              ),
            ),
          ),
        if (_searching) _searchBar(),
        if (_showOcrText && _ocr.text != null)
          Expanded(child: OcrTextPanel(text: _ocr.text!))
        else
          Expanded(
            child: ClipRect(
              child: ViewerShortcuts(
                onFind: _openSearch,
                onPrevious: () => _swipe(false),
                onNext: () => _swipe(true),
                onFirst: () => _goToPage(1),
                onLast: () => _goToPage(_pageCount),
                onZoomIn: () {
                  if (!_controller.isReady) return;
                  setState(() => _fit = _PageFit.manual);
                  _controller.zoomUp();
                },
                onZoomOut: () {
                  if (!_controller.isReady) return;
                  setState(() => _fit = _PageFit.manual);
                  _controller.zoomDown();
                },
                onFit: () {
                  setState(() => _fit = _PageFit.width);
                  _applyFit();
                },
                onRotate: () => _rotate(true),
                child: SwipePages(
                  enabled: () => _canSwipe,
                  onSwipe: _swipe,
                  child: PdfViewer(
                    _documentRef,
                    controller: _controller,
                    fontManager: previewFontManager,
                    params: PdfViewerParams(
                      errorBannerBuilder:
                          (context, error, stackTrace, documentRef) => Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: SelectableText(
                                'Önizleme açılamadı: $error',
                              ),
                            ),
                          ),
                      buildContextMenu: buildPreviewContextMenu,
                      onGeneralTap: widget.onEditAt == null
                          ? null
                          : _onGeneralTap,
                      textSelectionParams: PdfTextSelectionParams(
                        onTextSelectionChange: (selection) {
                          _selection = selection;
                          final has = selection.hasSelectedText;
                          if (has != _hasSelection && mounted) {
                            setState(() => _hasSelection = has);
                          }
                        },
                      ),
                      pageOverlaysBuilder: (context, pageRect, page) {
                        // Reading a page is put off until it is looked at: a
                        // filing of two hundred pages should show its first
                        // one without being read through.
                        _readCitations(page);
                        final marks = _canHighlight
                            ? _highlights
                                  .where((h) => h.page == page.pageNumber)
                                  .toList()
                            : const <PdfHighlight>[];
                        final cited = LegalSettings.instance.articles
                            ? _citations?.found(page.pageNumber) ??
                                  const <PdfCitation>[]
                            : const <PdfCitation>[];
                        return [
                          // Under the citations, so a law inside a highlight
                          // is still the thing a press reaches.
                          if (marks.isNotEmpty)
                            Positioned.fill(
                              child: _HighlightLayer(
                                marks: marks,
                                quarterTurns: _quarterTurns,
                                onTap: _onHighlightTap,
                                onWheel: _controller.handlePointerSignalEvent,
                              ),
                            ),
                          if (cited.isNotEmpty)
                            Positioned.fill(
                              child: PdfCitationLayer(
                                marks: cited,
                                quarterTurns: _quarterTurns,
                                colour: citationInk,
                                onTap: _onCitationTap,
                                onWheel: _controller.handlePointerSignalEvent,
                              ),
                            ),
                        ];
                      },
                      // The package default (0.2) discards 80% of desktop wheel movement.
                      // Keep OS wheel/trackpad distance and direction, without queued easing.
                      scrollByMouseWheel: 1.0,
                      interactionDelegateProvider:
                          const PdfViewerScrollInteractionDelegateProviderInstant(),
                      margin: 16,
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF151719)
                          : const Color(0xFFE9ECEF),
                      pageDropShadow: const BoxShadow(
                        color: Color(0x26000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                      sizeDelegateProvider:
                          const PdfViewerSizeDelegateProviderSmart(),
                      onViewSizeChanged: (size, oldSize, controller) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _applyFit(animate: false),
                        );
                      },
                      pagePaintCallbacks: [
                        (canvas, pageRect, page) =>
                            _search?.pageTextMatchPaintCallback(
                              canvas,
                              pageRect,
                              page,
                            ),
                      ],
                      onViewerReady: (document, controller) {
                        if (!mounted) return;
                        setState(() => _pageCount = document.pages.length);
                        widget.onTextLoaderChanged?.call(_loadCopyableText);
                        // The searcher reads the document as it is built, so
                        // it cannot exist before there is one.
                        _search ??= PdfTextSearcher(_controller)
                          ..addListener(_searched);
                        _applyFit(animate: false);
                        // Where the reading stopped last time, once there is
                        // a document to count the pages of.
                        final page = widget.initialPage;
                        if (page != null && page > 1 && page <= _pageCount) {
                          _goToPage(page);
                        }
                      },
                      onPageChanged: (page) {
                        if (mounted && page != null && _currentPage != page) {
                          setState(() => _currentPage = page);
                          widget.onPageChanged?.call(page);
                        }
                      },
                      viewerOverlayBuilder: (context, size, handleLinkTap) => [
                        PdfViewerScrollThumb(
                          controller: _controller,
                          thumbSize: const Size(24, 52),
                          margin: 4,
                          thumbBuilder: (context, size, page, controller) =>
                              Container(
                                decoration: BoxDecoration(
                                  color: scheme.onSurfaceVariant.withValues(
                                    alpha: .8,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    '$page',
                                    style: TextStyle(
                                      color: scheme.surface,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                        ),
                        PdfViewerScrollThumb(
                          controller: _controller,
                          orientation: ScrollbarOrientation.bottom,
                          thumbSize: const Size(52, 10),
                          margin: 4,
                          thumbBuilder: (context, size, page, controller) =>
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: scheme.onSurfaceVariant.withValues(
                                    alpha: .6,
                                  ),
                                  borderRadius: BorderRadius.circular(5),
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
        if (_citationListOpen && _allCited.isNotEmpty)
          // At the foot, under the page, so the document keeps its place
          // while the reader looks over what it rests on.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: CitationList(
              laws: [
                for (final one in _allCited)
                  if (one.citation != null) one.citation!,
              ],
              decisions: [
                for (final one in _allCited)
                  if (one.decision != null) one.decision!,
              ],
              onLaw: (citation, at) => _onCitationTap(
                PdfCitation(citation: citation, rects: const []),
                at,
              ),
              onDecision: (decision, at) => _onCitationTap(
                PdfCitation(decision: decision, rects: const []),
                at,
              ),
              onClose: () => setState(() => _citationListOpen = false),
            ),
          ),
      ],
    );
  }
}

/// Draws stored highlights over a page. The layer must never swallow drag
/// gestures, or text selection would stop working wherever a mark sits, so the
/// painter reports a hit only inside a highlight rectangle and the detector
/// defers to it.
class _HighlightLayer extends StatelessWidget {
  final List<PdfHighlight> marks;
  final int quarterTurns;
  final void Function(PdfHighlight mark, Offset globalPosition) onTap;

  /// Where a highlight is hit it is what the pointer is over, and pdfrx's
  /// scrolling beside it hears no wheel; see [PdfCitationLayer].
  final void Function(PointerSignalEvent event) onWheel;
  const _HighlightLayer({
    required this.marks,
    required this.quarterTurns,
    required this.onTap,
    required this.onWheel,
  });

  @override
  Widget build(BuildContext context) {
    final painter = _HighlightPainter(marks, quarterTurns);
    return Listener(
      onPointerSignal: onWheel,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTapUp: (details) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final mark = painter.markAt(details.localPosition, box.size);
          if (mark != null) onTap(mark, details.globalPosition);
        },
        child: CustomPaint(painter: painter, size: Size.infinite),
      ),
    );
  }
}

class _HighlightPainter extends CustomPainter {
  final List<PdfHighlight> marks;
  final int quarterTurns;
  Size _lastSize = Size.zero;
  _HighlightPainter(this.marks, this.quarterTurns);

  Rect _toRect(NormRect r, Size size) => Rect.fromLTRB(
    r.left * size.width,
    r.top * size.height,
    r.right * size.width,
    r.bottom * size.height,
  );

  PdfHighlight? markAt(Offset point, Size size) {
    // Last drawn wins, matching what the reader sees on top.
    for (final mark in marks.reversed) {
      for (final rect in mark.rectsFor(quarterTurns)) {
        if (_toRect(rect, size).contains(point)) return mark;
      }
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _lastSize = size;
    for (final mark in marks) {
      final paint = Paint()
        ..color = Color(mark.color).withValues(alpha: .38)
        // Multiply keeps the glyphs readable under the wash instead of
        // flattening them the way a plain opaque fill would.
        ..blendMode = BlendMode.multiply;
      for (final rect in mark.rectsFor(quarterTurns)) {
        canvas.drawRRect(
          RRect.fromRectXY(_toRect(rect, size).inflate(1), 2, 2),
          paint,
        );
      }
    }
  }

  @override
  bool hitTest(Offset position) => markAt(position, _lastSize) != null;

  @override
  bool shouldRepaint(_HighlightPainter old) =>
      old.quarterTurns != quarterTurns ||
      old.marks.length != marks.length ||
      !identical(old.marks, marks);
}

/// Draws a line under each law the page cites, and answers a press on one.
///
/// Only the citations take the pointer: [_CitationPainter.hitTest] answers
/// for the rectangles alone, so a press anywhere else still reaches the text
/// underneath and selection goes on working.
/// Law and decision citations over a page, each one a place to press.
@visibleForTesting
class PdfCitationLayer extends StatelessWidget {
  final List<PdfCitation> marks;
  final int quarterTurns;
  final Color colour;
  final void Function(PdfCitation mark, Offset globalPosition) onTap;
  final void Function(PointerSignalEvent event) onWheel;
  const PdfCitationLayer({
    required this.marks,
    required this.quarterTurns,
    required this.colour,
    required this.onTap,
    required this.onWheel,
  });

  @override
  Widget build(BuildContext context) {
    final painter = _CitationPainter(marks, quarterTurns, colour);
    // pdfrx stacks page overlays beside its scrolling, not inside it, so a
    // layer the pointer hits takes the wheel away from the page. An opaque
    // mouse region the size of the page did that everywhere on it: over a
    // page that cited a law the wheel did nothing, and moving off the page
    // brought it back. Now only a citation itself is hit, and a turn of the
    // wheel over one is handed on.
    return Listener(
      onPointerSignal: onWheel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        hitTestBehavior: HitTestBehavior.deferToChild,
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onTapUp: (details) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            final mark = painter.markAt(details.localPosition, box.size);
            if (mark != null) onTap(mark, details.globalPosition);
          },
          child: CustomPaint(painter: painter, size: Size.infinite),
        ),
      ),
    );
  }
}

class _CitationPainter extends CustomPainter {
  final List<PdfCitation> marks;
  final int quarterTurns;
  final Color colour;
  Size _lastSize = Size.zero;
  _CitationPainter(this.marks, this.quarterTurns, this.colour);

  Rect _toRect(NormRect r, Size size) => Rect.fromLTRB(
    r.left * size.width,
    r.top * size.height,
    r.right * size.width,
    r.bottom * size.height,
  );

  List<NormRect> _rectsOf(PdfCitation mark) => quarterTurns % 4 == 0
      ? mark.rects
      : [for (final r in mark.rects) r.rotated(quarterTurns)];

  PdfCitation? markAt(Offset point, Size size) {
    for (final mark in marks.reversed) {
      for (final rect in _rectsOf(mark)) {
        // A line of text is a thin target, so the box a press has to land in
        // is grown a little rather than being exactly the glyphs.
        if (_toRect(rect, size).inflate(2).contains(point)) return mark;
      }
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _lastSize = size;
    final line = Paint()
      ..color = colour
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    // A rendered page cannot have its glyphs recoloured, so the citation is
    // marked by a rule under it rather than by the link colour the editor
    // gives the same text. A decision is dotted, as it is in the editor: it
    // may or may not be in the bank, and the line should not promise more
    // than the app can keep.
    for (final mark in marks) {
      for (final rect in _rectsOf(mark)) {
        final box = _toRect(rect, size);
        final y = box.bottom + 0.5;
        if (!mark.isDecision) {
          canvas.drawLine(Offset(box.left, y), Offset(box.right, y), line);
          continue;
        }
        for (var x = box.left; x < box.right; x += 3) {
          final to = x + 1.6 < box.right ? x + 1.6 : box.right;
          canvas.drawLine(Offset(x, y), Offset(to, y), line);
        }
      }
    }
  }

  @override
  bool hitTest(Offset position) => markAt(position, _lastSize) != null;

  @override
  bool shouldRepaint(_CitationPainter old) =>
      old.quarterTurns != quarterTurns ||
      old.colour != colour ||
      !identical(old.marks, marks);
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Vurgu rengi',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.onSurface : scheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

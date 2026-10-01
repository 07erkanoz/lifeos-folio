import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/hover_document_preview.dart';
import '../../services/preview/hover_thumbnail.dart';

import '../../models/evrak_file.dart';
import '../../services/search/search_models.dart';

Color formatColor(EvrakFormat format) => switch (format) {
  EvrakFormat.pdf => const Color(0xFFF06464),
  EvrakFormat.udf => const Color(0xFFF59E42),
  EvrakFormat.spreadsheet => const Color(0xFF399875),
  EvrakFormat.docx => const Color(0xFF5991F3),
  EvrakFormat.odt => const Color(0xFF8584EE),
  EvrakFormat.rtf => const Color(0xFF6D8BC9),
  EvrakFormat.doc => const Color(0xFF4C7BD4),
  EvrakFormat.tif ||
  EvrakFormat.image ||
  EvrakFormat.svg => const Color(0xFF39BA97),
  _ => const Color(0xFF8B91A1),
};

class FileBadge extends StatelessWidget {
  final EvrakFile file;
  final double size;
  const FileBadge({super.key, required this.file, this.size = 44});
  @override
  Widget build(BuildContext context) {
    final color = formatColor(file.format);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            file.format == EvrakFormat.spreadsheet
                ? Icons.table_chart_outlined
                : file.format.isVisual
                ? Icons.image_outlined
                : Icons.description_outlined,
            color: color,
            size: size * .43,
          ),
          if (size >= 44)
            Text(
              file.name.split('.').last.toUpperCase(),
              style: TextStyle(
                color: color,
                fontSize: 8,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

class SearchHighlight extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle? style;
  final int maxLines;
  const SearchHighlight({
    super.key,
    required this.text,
    required this.query,
    this.style,
    this.maxLines = 2,
  });
  @override
  Widget build(BuildContext context) {
    final terms =
        SearchQuery.terms(query).where((t) => t.isNotEmpty).toSet().toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    final base = style ?? Theme.of(context).textTheme.bodyMedium!;
    final spans = <TextSpan>[];
    var cursor = 0;
    if (terms.isNotEmpty) {
      final matches = RegExp(terms.map(RegExp.escape).join('|'))
          .allMatches(foldSearchText(text));
      for (final match in matches) {
        if (match.end > text.length) continue;
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
        spans.add(
          TextSpan(
            text: text.substring(match.start, match.end),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              backgroundColor: Theme.of(context).colorScheme.primary
                  .withValues(alpha: 0.18),
            ),
          ),
        );
        cursor = match.end;
      }
    }
    spans.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(
      TextSpan(children: spans, style: base),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class SearchResults extends StatefulWidget {
  final List<SearchHit> hits;
  final String query;
  final String? selectedPath;
  final bool compact;
  final bool hoverPreview;
  final bool searching;
  final bool hasMore;
  final VoidCallback loadMore;
  final ValueChanged<EvrakFile> onOpen;
  final Widget? empty;
  final FocusNode? focusNode;

  /// Reads the passages around the query for one document, for the quick look.
  final Future<DocumentPassages> Function(int documentId)? passages;
  const SearchResults({
    super.key,
    required this.hits,
    required this.query,
    required this.onOpen,
    required this.loadMore,
    this.passages,
    this.selectedPath,
    this.compact = false,
    this.hoverPreview = true,
    this.searching = false,
    this.hasMore = false,
    this.empty,
    this.focusNode,
  });
  @override
  State<SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends State<SearchResults> {
  final _scroll = ScrollController();
  final _localFocus = FocusNode();
  final _keys = <String, GlobalKey>{};
  String? _activePath;
  Timer? _previewTimer;
  FocusNode get _focus => widget.focusNode ?? _localFocus;

  @override
  void dispose() {
    _previewTimer?.cancel();
    _localFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    final paths = widget.hits.map((e) => e.file.path).toSet();
    _keys.removeWhere((path, _) => !paths.contains(path));
    if (!paths.contains(_activePath)) {
      _activePath = null;
      _previewTimer?.cancel();
    }
  }

  void _select(int index) {
    final file = widget.hits[index].file;
    setState(() => _activePath = file.path);
    HoverDocumentPreview.dismissActive();
    _previewTimer?.cancel();
    // Holding an arrow key should not decode every intermediate PDF/TIFF.
    if (widget.compact) {
      _previewTimer = Timer(const Duration(milliseconds: 110), () {
        if (mounted &&
            _focus.hasFocus &&
            _activePath == file.path &&
            widget.selectedPath != file.path) {
          widget.onOpen(file);
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_scroll.hasClients) return;
      var target = _keys[file.path]?.currentContext;
      if (target == null) {
        final estimate =
            _scroll.position.maxScrollExtent *
            index /
            (widget.hits.length - 1).clamp(1, widget.hits.length);
        _scroll.jumpTo(estimate.clamp(0, _scroll.position.maxScrollExtent));
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        target = _keys[file.path]?.currentContext;
      }
      if (target != null && target.mounted) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 100),
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (widget.hits.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;
    var index = widget.hits.indexWhere(
      (hit) => hit.file.path == (_activePath ?? widget.selectedPath),
    );
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      _previewTimer?.cancel();
      widget.onOpen(widget.hits[index < 0 ? 0 : index].file);
      return KeyEventResult.handled;
    }
    // Left and right walk the list too, not only up and down.
    //
    // Choosing a picture from the list leaves the cursor in the list, so
    // that the next arrow picks the next document. That is right for a
    // document, and it left a photograph unreachable: the list ignored left
    // and right, the viewer did not have the keyboard, and pressing them
    // did nothing at all until the picture was clicked. Nobody reaches for
    // "down" to see the next photograph.
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowRight) {
      if (index == widget.hits.length - 1 &&
          widget.hasMore &&
          !widget.searching) {
        widget.loadMore();
      }
      index = (index + 1).clamp(0, widget.hits.length - 1);
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft) {
      index = (index - 1).clamp(0, widget.hits.length - 1);
    } else if (key == LogicalKeyboardKey.home) {
      index = 0;
    } else if (key == LogicalKeyboardKey.end) {
      index = widget.hits.length - 1;
    } else {
      return KeyEventResult.ignored;
    }
    _focus.requestFocus();
    _select(index);
    return KeyEventResult.handled;
  }

  /// A document is previewed with its matching text; a picture has none, so it
  /// is previewed with a thumbnail.
  Future<HoverPreviewContent?> Function(bool Function())? _loader(
    SearchHit hit,
  ) {
    if (hit.file.format == EvrakFormat.image) {
      return (wanted) async {
        final bytes = await HoverThumbnail.load(
          hit.file,
          wanted,
          const HoverThumbnailRequest(width: 640, height: 640),
        );
        return bytes == null ? null : HoverPreviewContent(picture: bytes);
      };
    }
    final read = widget.passages;
    if (read == null) return null;
    return (wanted) async {
      final found = await read(hit.id);
      if (!wanted()) return null;
      return HoverPreviewContent(
        passages: found.passages,
        matches: found.matches,
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (widget.hits.isEmpty) {
      return widget.empty ??
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.query.isEmpty
                          ? Icons.folder_open_outlined
                          : Icons.search_off_rounded,
                      size: 48,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.searching
                          ? 'Aranıyor…'
                          : widget.query.isEmpty
                          ? 'Evraklarınız burada görünecek'
                          : 'Eşleşen evrak bulunamadı',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.query.isEmpty
                          ? 'Bir klasör ekleyin veya dosyalarınızı buraya bırakın.'
                          : 'Daha kısa bir sözcük deneyin ya da filtreleri kaldırın.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
    }
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: ListView.separated(
        controller: _scroll,
        key: const PageStorageKey('library-results'),
        padding: EdgeInsets.fromLTRB(
          widget.compact ? 12 : 24,
          8,
          widget.compact ? 12 : 24,
          24,
        ),
        itemCount: widget.hits.length + (widget.hasMore ? 1 : 0),
        separatorBuilder: (_, i) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == widget.hits.length) {
            return TextButton.icon(
              onPressed: widget.searching ? null : widget.loadMore,
              icon: const Icon(Icons.expand_more),
              label: const Text('Daha fazla göster'),
            );
          }
          final hit = widget.hits[index];
          final file = hit.file;
          final selected =
              file.path == widget.selectedPath ||
              (_focus.hasFocus && file.path == _activePath);
          return HoverDocumentPreview(
            key: _keys.putIfAbsent(file.path, GlobalKey.new),
            file: file,
            excerpt: hit.excerpt,
            note: hit.note ?? '',
            query: widget.query,
            loader: _loader(hit),
            enabled: widget.hoverPreview,
            child: Material(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.07)
                  : scheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: selected
                      ? scheme.primary.withValues(alpha: 0.45)
                      : scheme.outlineVariant,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onFocusChange: (focused) {
                  if (focused &&
                      widget.compact &&
                      FocusManager.instance.highlightMode ==
                          FocusHighlightMode.traditional) {
                    _select(index);
                  }
                },
                onTap: () {
                  _previewTimer?.cancel();
                  _activePath = file.path;
                  _focus.requestFocus();
                  widget.onOpen(file);
                },
                child: Padding(
                  padding: EdgeInsets.all(widget.compact ? 13 : 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FileBadge(file: file, size: widget.compact ? 36 : 44),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SearchHighlight(
                                  text: file.name,
                                  query: widget.query,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: widget.compact ? 13 : 15,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  file.path,
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
                          if (!widget.compact) ...[
                            const SizedBox(width: 12),
                            Text(
                              file.readableSize,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Icon(
                              Icons.north_east_rounded,
                              size: 16,
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ],
                      ),
                      if (hit.excerpt.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SearchHighlight(
                          text: hit.excerpt,
                          query: widget.query,
                          maxLines: widget.compact ? 2 : 3,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: hit.state == 'ready'
                                  ? const Color(0xFF22B58A)
                                  : hit.state == 'error'
                                  ? scheme.error
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Tooltip(
                              message: hit.note ?? hit.stateLabel,
                              child: Text(
                                hit.stateLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          if (hit.modified > 0)
                            Text(
                              DateFormat('dd.MM.yyyy').format(
                                DateTime.fromMicrosecondsSinceEpoch(
                                  hit.modified,
                                ),
                              ),
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

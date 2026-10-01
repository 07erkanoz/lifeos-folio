import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/evrak_file.dart';
import '../../services/search/search_models.dart';

/// What a quick look shows. A document answers with the passages around the
/// query, so the reader can tell whether this is the text they are after; a
/// picture answers with a thumbnail, where there is no text to read.
class HoverPreviewContent {
  final List<String> passages;
  final int matches;
  final Uint8List? picture;
  const HoverPreviewContent({
    this.passages = const [],
    this.matches = 0,
    this.picture,
  });
  bool get isEmpty => passages.isEmpty && picture == null;
}

const _headerHeight = 48.0;
const _footerHeight = 35.0;
const _pictureHeight = 300.0;

class HoverDocumentPreview extends StatefulWidget {
  static final _visible = <VoidCallback>[];
  static bool dismissActive() {
    if (_visible.isEmpty) return false;
    _visible.last();
    return true;
  }

  final EvrakFile file;

  /// Shown when the archive holds no passages for this document.
  final String excerpt;

  /// Why the archive could not read the document, if it could not.
  final String note;

  /// Current search text; its words are highlighted inside the passages.
  final String query;
  final bool enabled;
  final Widget child;
  final Future<HoverPreviewContent?> Function(bool Function() wanted)? loader;
  const HoverDocumentPreview({
    super.key,
    required this.file,
    required this.child,
    this.excerpt = '',
    this.note = '',
    this.query = '',
    this.enabled = true,
    this.loader,
  });
  @override
  State<HoverDocumentPreview> createState() => _HoverDocumentPreviewState();
}

class _HoverDocumentPreviewState extends State<HoverDocumentPreview> {
  Timer? _timer;
  OverlayEntry? _entry;
  ScrollPosition? _scroll;
  Offset _pointer = Offset.zero;
  int _generation = 0;
  bool _listening = false;
  bool get _desktop => switch (defaultTargetPlatform) {
    TargetPlatform.linux ||
    TargetPlatform.windows ||
    TargetPlatform.macOS => true,
    _ => false,
  };
  void _hide() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    HoverDocumentPreview._visible.remove(_hide);
    if (_listening) FocusManager.instance.removeEarlyKeyEventHandler(_key);
    _listening = false;
  }

  KeyEventResult _key(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.escape ||
        event is! KeyDownEvent ||
        ModalRoute.of(context)?.isCurrent == false) {
      return KeyEventResult.ignored;
    }
    final visible = _entry != null;
    _hide();
    return visible ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scroll?.removeListener(_hide);
    _scroll = Scrollable.maybeOf(context)?.position;
    _scroll?.addListener(_hide);
  }

  @override
  void didUpdateWidget(covariant HoverDocumentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || oldWidget.file != widget.file) _hide();
  }

  void _enter(PointerEnterEvent event) {
    if (!widget.enabled || !_desktop || event.kind != PointerDeviceKind.mouse) {
      return;
    }
    _hide();
    _pointer = event.position;
    FocusManager.instance.addEarlyKeyEventHandler(_key);
    _listening = true;
    _timer = Timer(const Duration(milliseconds: 550), _show);
  }

  /// Highlights the query words inside a passage. [foldSearchText] replaces one
  /// character with one character, so offsets found in the folded copy address
  /// the original text — Turkish İ/ı and accents match without shifting.
  List<TextSpan> _spans(String passage, TextStyle highlight) {
    final terms = SearchQuery.terms(widget.query);
    if (terms.isEmpty) return [TextSpan(text: passage)];
    final folded = foldSearchText(passage);
    final marks = <List<int>>[];
    for (final term in terms) {
      for (
        var at = folded.indexOf(term);
        at >= 0;
        at = folded.indexOf(term, at + term.length)
      ) {
        marks.add([at, at + term.length]);
      }
    }
    if (marks.isEmpty) return [TextSpan(text: passage)];
    marks.sort((a, b) => a[0].compareTo(b[0]));
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final mark in marks) {
      if (mark[0] < cursor) continue;
      if (mark[0] > cursor) {
        spans.add(TextSpan(text: passage.substring(cursor, mark[0])));
      }
      spans.add(
        TextSpan(text: passage.substring(mark[0], mark[1]), style: highlight),
      );
      cursor = mark[1];
    }
    if (cursor < passage.length) {
      spans.add(TextSpan(text: passage.substring(cursor)));
    }
    return spans;
  }

  Widget _body(
    AsyncSnapshot<HoverPreviewContent?> snapshot,
    ThemeData theme,
    double maxHeight,
  ) {
    final content = snapshot.data;
    if (content?.picture != null) {
      return SizedBox(
        height: math.min(_pictureHeight, maxHeight),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Image.memory(content!.picture!, fit: BoxFit.contain),
        ),
      );
    }
    final highlight = TextStyle(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.primary,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
    );
    final waiting = snapshot.connectionState != ConnectionState.done;
    final passages = content?.passages ?? const <String>[];
    if (passages.isEmpty) {
      // No indexed text: say why instead of leaving an empty panel.
      final message = widget.excerpt.isNotEmpty
          ? widget.excerpt
          : waiting
          ? 'Metin hazırlanıyor…'
          : widget.note.trim().isNotEmpty
          ? widget.note.trim()
          : 'Bu belgenin aranabilir metni yok. Açmak için tıklayın.';
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (waiting) ...[
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 14),
            ],
            Text.rich(
              TextSpan(children: _spans(message, highlight)),
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                height: 1.55,
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final passage in passages) ...[
              Flexible(
                child: Text.rich(
                  TextSpan(children: _spans(passage, highlight)),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    height: 1.55,
                    fontSize: 13,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (passage != passages.last) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  String _footer(HoverPreviewContent? content) {
    final matches = content?.matches ?? 0;
    return matches > 0
        ? '$matches eşleşme · Tam önizleme için tıklayın'
        : 'Hızlı bakış · Tam önizleme için tıklayın';
  }

  void _show() {
    if (!mounted ||
        !widget.enabled ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final overlay = Overlay.of(context);
    final box = overlay.context.findRenderObject() as RenderBox;
    final size = box.size;
    if (size.width < 500 || size.height < 300) return;
    final point = box.globalToLocal(_pointer);
    final width = math.min(520.0, size.width - 24);
    final height = math.min(430.0, size.height - 24);
    final left =
        (point.dx + width + 24 < size.width
                ? point.dx + 20
                : point.dx - width - 20)
            .clamp(12.0, size.width - width - 12);
    final top = (point.dy - 40).clamp(12.0, size.height - height - 12);
    final generation = _generation;
    final preview = widget.loader?.call(
      () => mounted && generation == _generation && _entry != null,
    );
    final theme = Theme.of(context);
    _entry = OverlayEntry(
      builder: (_) => Positioned(
        left: left,
        top: top,
        width: width,
        child: IgnorePointer(
          child: Theme(
            data: theme,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 140),
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 5 * (1 - value)),
                  child: child,
                ),
              ),
              child: Material(
                key: const ValueKey('hover-document-preview'),
                elevation: 12,
                shadowColor: Colors.black26,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: FutureBuilder<HoverPreviewContent?>(
                  future: preview,
                  builder: (context, snapshot) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: _headerHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 20,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  widget.file.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('Esc', style: TextStyle(fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                      ColoredBox(
                        color: theme.colorScheme.surfaceContainerLow,
                        child: SizedBox(
                          width: double.infinity,
                          child: _body(
                            snapshot,
                            theme,
                            height - _headerHeight - _footerHeight,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: _footerHeight,
                        child: Center(
                          child: Text(
                            _footer(snapshot.data),
                            style: const TextStyle(fontSize: 11),
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
      ),
    );
    HoverDocumentPreview._visible.add(_hide);
    overlay.insert(_entry!);
  }

  @override
  void dispose() {
    _hide();
    _scroll?.removeListener(_hide);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: _enter,
    onExit: (_) => _hide(),
    child: Listener(
      onPointerDown: (_) => _hide(),
      onPointerSignal: (_) => _hide(),
      child: widget.child,
    ),
  );
}

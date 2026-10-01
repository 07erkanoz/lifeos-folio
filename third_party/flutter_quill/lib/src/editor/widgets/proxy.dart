import 'dart:ui';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'box.dart';
import 'text/hanging_indent.dart';

class BaselineProxy extends SingleChildRenderObjectWidget {
  const BaselineProxy({
    super.key,
    super.child,
    this.textStyle,
    this.padding,
  });

  final TextStyle? textStyle;
  final EdgeInsets? padding;

  @override
  RenderBaselineProxy createRenderObject(BuildContext context) {
    return RenderBaselineProxy(
      null,
      textStyle!,
      padding,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant RenderBaselineProxy renderObject) {
    renderObject
      ..textStyle = textStyle!
      ..padding = padding!;
  }
}

class RenderBaselineProxy extends RenderProxyBox {
  RenderBaselineProxy(
    RenderParagraph? super.child,
    TextStyle textStyle,
    EdgeInsets? padding,
  ) : _prototypePainter = TextPainter(
            text: TextSpan(text: ' ', style: textStyle),
            textDirection: TextDirection.ltr,
            strutStyle:
                StrutStyle.fromTextStyle(textStyle, forceStrutHeight: true));

  final TextPainter _prototypePainter;

  set textStyle(TextStyle value) {
    if (_prototypePainter.text!.style == value) {
      return;
    }
    _prototypePainter.text = TextSpan(text: ' ', style: value);
    markNeedsLayout();
  }

  EdgeInsets? _padding;

  set padding(EdgeInsets value) {
    if (_padding == value) {
      return;
    }
    _padding = value;
    markNeedsLayout();
  }

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) =>
      _prototypePainter.computeDistanceToActualBaseline(baseline);
  // SEE What happens + _padding?.top;

  @override
  void performLayout() {
    super.performLayout();
    _prototypePainter.layout();
  }

  @override
  void dispose() {
    super.dispose();
    _prototypePainter.dispose();
  }
}

class EmbedProxy extends SingleChildRenderObjectWidget {
  const EmbedProxy(Widget child, {super.key}) : super(child: child);

  @override
  RenderEmbedProxy createRenderObject(BuildContext context) =>
      RenderEmbedProxy(null);
}

class RenderEmbedProxy extends RenderProxyBox implements RenderContentProxyBox {
  RenderEmbedProxy(super.child);

  @override
  List<TextBox> getBoxesForSelection(TextSelection selection) {
    if (!selection.isCollapsed) {
      return <TextBox>[
        TextBox.fromLTRBD(0, 0, size.width, size.height, TextDirection.ltr)
      ];
    }

    final left = selection.extentOffset == 0 ? 0.0 : size.width;
    final right = selection.extentOffset == 0 ? 0.0 : size.width;
    return <TextBox>[
      TextBox.fromLTRBD(left, 0, right, size.height, TextDirection.ltr)
    ];
  }

  @override
  double getFullHeightForCaret(TextPosition position) => size.height;

  @override
  Offset getOffsetForCaret(TextPosition position, Rect caretPrototype) {
    assert(
        position.offset == 1 || position.offset == 0 || position.offset == -1);
    return position.offset <= 0
        ? Offset.zero
        : Offset(size.width - caretPrototype.width, 0);
  }

  @override
  TextPosition getPositionForOffset(Offset offset) =>
      TextPosition(offset: offset.dx > size.width / 2 ? 1 : 0);

  @override
  TextRange getWordBoundary(TextPosition position) =>
      const TextRange(start: 0, end: 1);

  @override
  double get preferredLineHeight => size.height;
}

class RichTextProxy extends SingleChildRenderObjectWidget {
  /// Child argument should be an instance of RichText widget.
  const RichTextProxy({
    required RichText super.child,
    required this.textStyle,
    required this.textAlign,
    required this.textDirection,
    required this.locale,
    required this.strutStyle,
    required this.textScaler,
    this.textWidthBasis = TextWidthBasis.parent,
    this.textHeightBehavior,
    this.leadingPlaceholders = 0,
    this.insertions = const [],
    super.key,
  });

  /// FOLIO PATCH: placeholders the line drew ahead of its own text (a first
  /// line indent), which the document's offsets do not count.
  final int leadingPlaceholders;

  /// FOLIO PATCH: characters the line put into its text — joins, and the room
  /// of a hanging indent; see [HangingIndent].
  final List<LineInsertion> insertions;

  final TextStyle textStyle;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Locale locale;
  final StrutStyle? strutStyle;
  final TextWidthBasis textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;

  @override
  RenderParagraphProxy createRenderObject(BuildContext context) {
    return RenderParagraphProxy(null, textStyle, textAlign, textDirection,
        textScaler, strutStyle, locale, textWidthBasis, textHeightBehavior)
      ..leadingPlaceholders = leadingPlaceholders
      ..insertions = insertions;
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant RenderParagraphProxy renderObject) {
    renderObject
      ..textStyle = textStyle
      ..textAlign = textAlign
      ..textDirection = textDirection
      ..textScaler = textScaler
      ..locale = locale
      ..strutStyle = strutStyle
      ..textWidthBasis = textWidthBasis
      ..textHeightBehavior = textHeightBehavior
      ..leadingPlaceholders = leadingPlaceholders
      ..insertions = insertions;
  }
}

class RenderParagraphProxy extends RenderProxyBox
    implements RenderContentProxyBox {
  RenderParagraphProxy(
    RenderParagraph? super.child,
    TextStyle textStyle,
    TextAlign textAlign,
    TextDirection textDirection,
    TextScaler textScaler,
    StrutStyle? strutStyle,
    Locale locale,
    TextWidthBasis textWidthBasis,
    TextHeightBehavior? textHeightBehavior,
  ) : _prototypePainter = TextPainter(
          text: TextSpan(text: ' ', style: textStyle),
          textAlign: textAlign,
          textDirection: textDirection,
          textScaler: textScaler,
          strutStyle: strutStyle,
          locale: locale,
          textWidthBasis: textWidthBasis,
          textHeightBehavior: textHeightBehavior,
        );

  final TextPainter _prototypePainter;

  set textStyle(TextStyle value) {
    if (_prototypePainter.text!.style == value) {
      return;
    }
    _prototypePainter.text = TextSpan(text: ' ', style: value);
    markNeedsLayout();
  }

  set textAlign(TextAlign value) {
    if (_prototypePainter.textAlign == value) {
      return;
    }
    _prototypePainter.textAlign = value;
    markNeedsLayout();
  }

  set textDirection(TextDirection value) {
    if (_prototypePainter.textDirection == value) {
      return;
    }
    _prototypePainter.textDirection = value;
    markNeedsLayout();
  }

  set textScaler(TextScaler value) {
    if (_prototypePainter.textScaler == value) {
      return;
    }
    _prototypePainter.textScaler = value;
    markNeedsLayout();
  }

  set strutStyle(StrutStyle? value) {
    if (_prototypePainter.strutStyle == value) {
      return;
    }
    _prototypePainter.strutStyle = value;
    markNeedsLayout();
  }

  set locale(Locale value) {
    if (_prototypePainter.locale == value) {
      return;
    }
    _prototypePainter.locale = value;
    markNeedsLayout();
  }

  set textWidthBasis(TextWidthBasis value) {
    if (_prototypePainter.textWidthBasis == value) {
      return;
    }
    _prototypePainter.textWidthBasis = value;
    markNeedsLayout();
  }

  set textHeightBehavior(TextHeightBehavior? value) {
    if (_prototypePainter.textHeightBehavior == value) {
      return;
    }
    _prototypePainter.textHeightBehavior = value;
    markNeedsLayout();
  }

  /// FOLIO PATCH: placeholders ahead of the line's own text. Every position
  /// crossing into the paragraph is moved past them, and every position
  /// coming out is moved back, so the rest of Quill never sees them.
  int _leading = 0;
  set leadingPlaceholders(int value) {
    if (_leading == value) return;
    _leading = value;
    markNeedsLayout();
  }

  /// FOLIO PATCH: characters the line put into its text, which the document
  /// does not have.
  List<LineInsertion> _insertions = const [];
  set insertions(List<LineInsertion> value) {
    if (listEquals(_insertions, value)) return;
    _insertions = value;
    markNeedsLayout();
  }

  bool get _shifted => _leading != 0 || _insertions.isNotEmpty;

  TextPosition _in(TextPosition position) => !_shifted
      ? position
      : TextPosition(
          offset: HangingIndent.toRender(position.offset, _leading, _insertions),
          affinity: position.affinity);

  int _out(int offset) => !_shifted
      ? offset
      : HangingIndent.toDocument(offset, _leading, _insertions);

  @override
  RenderParagraph? get child => super.child as RenderParagraph?;

  /// FOLIO PATCH: pages. Where rows were moved down to start the next page:
  /// from each `from` (a y in the paragraph as laid out) on, everything is
  /// drawn `shift` lower, the shifts adding up. Set by the line once it
  /// knows where on the page it is; it moves painting and every position,
  /// not the paragraph's own layout, and the room it opens is the line's.
  List<({double from, double shift, double cut})> _pageGaps = const [];
  List<({double from, double shift, double cut})> get pageGaps => _pageGaps;
  set pageGaps(List<({double from, double shift, double cut})> value) {
    if (listEquals(_pageGaps, value)) return;
    _pageGaps = value;
    markNeedsPaint();
  }

  /// Where a point of the paragraph laid out at [y] is drawn, and back.
  double drawnY(double y) => y + _shiftAt(y);
  double laidY(double y) => _unshift(y);

  /// All the room the gaps open, which the line adds to its height.
  double get pageGapHeight => _pageGaps.isEmpty ? 0 : _pageGaps.last.shift;

  /// How much lower a point of the paragraph at [y] is drawn.
  double _shiftAt(double y) {
    var shift = 0.0;
    for (final gap in _pageGaps) {
      if (y < gap.from - .01) break;
      shift = gap.shift;
    }
    return shift;
  }

  /// The paragraph's own y for a [y] as drawn; one in a gap goes to the
  /// nearer of the row above and the row below it.
  double _unshift(double y) {
    var before = 0.0;
    for (final gap in _pageGaps) {
      final start = gap.from + before; // where the room opens, drawn
      if (y < start) break;
      final end = gap.from + gap.shift; // where the next row is drawn
      if (y < end) return y - start < end - y ? gap.from - .5 : gap.from;
      before = gap.shift;
    }
    return y - before;
  }

  /// The rows of the paragraph as laid out: the top and bottom of each,
  /// and where its letters are drawn — a descender can reach past the
  /// bottom of its row, so a page is cut between two rows' letters, not
  /// between the rows.
  List<({double top, double bottom, double inkTop, double inkBottom})>
      get rows {
    final paragraph = child;
    if (paragraph == null) return const [];
    final length =
        paragraph.text.toPlainText(includeSemanticsLabels: false).length;
    final all = TextSelection(baseOffset: 0, extentOffset: length);
    final boxes = length == 0
        ? const <TextBox>[]
        : paragraph.getBoxesForSelection(all,
            boxHeightStyle: BoxHeightStyle.max);
    final rows =
        <({double top, double bottom, double inkTop, double inkBottom})>[];
    for (final box in boxes) {
      if (rows.isNotEmpty && box.top < rows.last.bottom - .5) continue;
      rows.add((
        top: box.top,
        bottom: box.bottom,
        inkTop: box.bottom,
        inkBottom: box.top
      ));
    }
    if (rows.isEmpty) {
      return [(top: 0, bottom: size.height, inkTop: 0, inkBottom: size.height)];
    }
    final ink = paragraph.getBoxesForSelection(all,
        boxHeightStyle: BoxHeightStyle.tight);
    for (final box in ink) {
      final middle = (box.top + box.bottom) / 2;
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        if (middle < row.top || middle > row.bottom) continue;
        rows[i] = (
          top: row.top,
          bottom: row.bottom,
          inkTop: box.top < row.inkTop ? box.top : row.inkTop,
          inkBottom: box.bottom > row.inkBottom ? box.bottom : row.inkBottom,
        );
        break;
      }
    }
    return rows;
  }

  @override
  double get preferredLineHeight => _prototypePainter.preferredLineHeight;

  @override
  Offset getOffsetForCaret(TextPosition position, Rect caretPrototype) {
    final at = child!.getOffsetForCaret(_in(position), caretPrototype);
    return _pageGaps.isEmpty ? at : at.translate(0, _shiftAt(at.dy));
  }

  @override
  TextPosition getPositionForOffset(Offset offset) {
    if (_pageGaps.isNotEmpty) offset = Offset(offset.dx, _unshift(offset.dy));
    final position = child!.getPositionForOffset(offset);
    if (!_shifted) return position;
    return TextPosition(
        offset: _out(position.offset), affinity: position.affinity);
  }

  @override
  double? getFullHeightForCaret(TextPosition position) =>
      child!.getFullHeightForCaret(_in(position));

  @override
  TextRange getWordBoundary(TextPosition position) {
    final range = child!.getWordBoundary(_in(position));
    if (!_shifted) return range;
    return TextRange(start: _out(range.start), end: _out(range.end));
  }

  @override
  List<TextBox> getBoxesForSelection(TextSelection selection) {
    final boxes = _boxesForSelection(selection);
    if (_pageGaps.isEmpty) return boxes;
    return [
      for (final box in boxes)
        TextBox.fromLTRBD(box.left, box.top + _shiftAt(box.top), box.right,
            box.bottom + _shiftAt(box.top), box.direction),
    ];
  }

  List<TextBox> _boxesForSelection(TextSelection selection) =>
      child!.getBoxesForSelection(
          !_shifted
              ? selection
              : selection.copyWith(
                  baseOffset: HangingIndent.toRender(
                      selection.baseOffset, _leading, _insertions),
                  extentOffset: HangingIndent.toRender(
                      selection.extentOffset, _leading, _insertions)),
          boxHeightStyle: BoxHeightStyle.max);

  @override
  void performLayout() {
    super.performLayout();
    _prototypePainter.layout(
        minWidth: constraints.minWidth, maxWidth: constraints.maxWidth);
  }

  /// FOLIO PATCH: pages. With gaps, the paragraph is painted in slices, one
  /// per page, each clipped to its rows and moved down by its gap.
  @override
  void paint(PaintingContext context, Offset offset) {
    final paragraph = child;
    if (_pageGaps.isEmpty || paragraph == null) {
      super.paint(context, offset);
      return;
    }
    var from = double.negativeInfinity;
    var shift = 0.0;
    for (final gap in [
      ..._pageGaps,
      (from: double.infinity, shift: 0.0, cut: double.infinity)
    ]) {
      final top = from, bottom = gap.cut;
      final at = offset.translate(0, shift);
      context.pushClipRect(
        needsCompositing,
        at,
        Rect.fromLTRB(-1e5, top.isFinite ? top : -1e5, 1e5,
            bottom.isFinite ? bottom : size.height + 1e5),
        (context, offset) => context.paintChild(paragraph, offset),
      );
      from = gap.cut;
      shift = gap.shift;
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_pageGaps.isEmpty) return super.hitTest(result, position: position);
    final bounds = Size(size.width, size.height + pageGapHeight);
    if (!bounds.contains(position)) return false;
    final y = _unshift(position.dy);
    final hit = result.addWithPaintOffset(
      offset: Offset(0, _shiftAt(y)),
      position: position,
      hitTest: (result, transformed) =>
          child?.hitTest(result, position: transformed) ?? false,
    );
    if (hit) result.add(BoxHitTestEntry(this, position));
    return hit;
  }

  @override
  void dispose() {
    super.dispose();
    _prototypePainter.dispose();
  }
}

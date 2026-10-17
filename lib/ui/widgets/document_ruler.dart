import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/editor/tab_stops.dart';

/// The paragraph the caret is in, as the horizontal ruler shows it: its
/// indents and its own tab stops, in points (GELISTIRME.md §6).
@immutable
class RulerParagraph {
  const RulerParagraph({
    this.firstRow = 0,
    this.otherRows = 0,
    this.right = 0,
    this.stops = const [],
    this.origin = 0,
  });

  /// Where the first row starts, and the rows after it, from the left
  /// margin; the right indent from the right margin.
  final double firstRow, otherRows, right;

  /// The paragraph's own stops, counted from [origin]: the left indent for
  /// UYAP's rules, the margin for Word's.
  final List<TabStop> stops;
  final double origin;

  RulerParagraph copyWith({
    double? firstRow,
    double? otherRows,
    double? right,
    List<TabStop>? stops,
  }) => RulerParagraph(
    firstRow: firstRow ?? this.firstRow,
    otherRows: otherRows ?? this.otherRows,
    right: right ?? this.right,
    stops: stops ?? this.stops,
    origin: origin,
  );

  /// The model's own words for it: the left indent, the first row's step in
  /// from it, the hanging rows' (UYAP holds the two apart).
  ({double left, double first, double hanging}) get indents =>
      firstRow >= otherRows
      ? (left: otherRows, first: firstRow - otherRows, hanging: 0)
      : (left: firstRow, first: 0, hanging: otherRows - firstRow);

  @override
  bool operator ==(Object other) =>
      other is RulerParagraph &&
      other.firstRow == firstRow &&
      other.otherRows == otherRows &&
      other.right == right &&
      other.origin == origin &&
      listEquals(other.stops, stops);

  @override
  int get hashCode =>
      Object.hash(firstRow, otherRows, right, origin, Object.hashAll(stops));

  /// The stops as a UDF's TabSet writes them: "points:kind,…".
  String get tabSet => [
    for (final s in stops)
      '${s.position.toStringAsFixed(1)}:${switch (s.align) {
        TabAlign.right => 1,
        TabAlign.centre => 2,
        TabAlign.decimal => 4,
        TabAlign.bar => 5,
        TabAlign.left => 0,
      }}',
  ].join(',');
}

/// Centimetre ruler backed by document points (72 pt = 1 inch). The
/// horizontal one, given a [paragraph], shows its indents and tab stops
/// and changes them: a click puts a stop, a drag moves one, dragged off or
/// double clicked it goes; the triangles move the indents.
class DocumentRuler extends StatefulWidget {
  static const pointsPerCm = 72 / 2.54;

  /// Where a stop or an indent settles: a quarter of a centimetre; Alt
  /// held, anywhere.
  static const snap = pointsPerCm / 4;

  final Axis axis;
  final double pagePoints;
  final double pixels;
  final double leading;
  final double trailing;
  final void Function(double leading, double trailing) onChanged;

  final RulerParagraph? paragraph;

  /// The paragraph changed: told once, when a drag or a click is done.
  final ValueChanged<RulerParagraph>? onParagraph;

  const DocumentRuler({
    super.key,
    required this.axis,
    required this.pagePoints,
    required this.pixels,
    required this.leading,
    required this.trailing,
    required this.onChanged,
    this.paragraph,
    this.onParagraph,
  });

  @override
  State<DocumentRuler> createState() => _DocumentRulerState();
}

class _DocumentRulerState extends State<DocumentRuler> {
  /// The paragraph as a drag has it, before it is told.
  RulerParagraph? _moving;

  /// Where the line down the page stands while something is dragged.
  double? _guide;

  /// The kind of stop a click puts.
  TabAlign _kind = TabAlign.left;

  double get _scale => widget.pixels / widget.pagePoints;

  static double _snapped(double points) =>
      HardwareKeyboard.instance.isAltPressed
      ? points
      : (points / DocumentRuler.snap).roundToDouble() * DocumentRuler.snap;

  void _tell(RulerParagraph next) {
    setState(() {
      _moving = null;
      _guide = null;
    });
    widget.onParagraph?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    final scale = _scale;
    final scheme = Theme.of(context).colorScheme;
    final leading = widget.leading, trailing = widget.trailing;
    final paragraph = horizontal && widget.onParagraph != null
        ? _moving ?? widget.paragraph
        : null;
    Widget handle(bool start) {
      final margin = start ? leading : trailing;
      final position = (start ? leading : widget.pagePoints - trailing) * scale;
      final label = horizontal
          ? (start ? 'Sol kenar boşluğu' : 'Sağ kenar boşluğu')
          : (start ? 'Üst kenar boşluğu' : 'Alt kenar boşluğu');
      void change(double delta) {
        final next = (margin + delta)
            .clamp(
              0.0,
              math.max(
                0.0,
                widget.pagePoints - (start ? trailing : leading) - 72,
              ),
            )
            .toDouble();
        widget.onChanged(start ? next : leading, start ? trailing : next);
      }

      // With a paragraph's triangles on the ruler, the margin is the edge
      // between the grey and the white, held by a narrow grip.
      final grip = paragraph != null;
      final child = Semantics(
        label: label,
        value: '${(margin / DocumentRuler.pointsPerCm).toStringAsFixed(1)} cm',
        increasedValue:
            '${((margin + 2.8346) / DocumentRuler.pointsPerCm).toStringAsFixed(1)} cm',
        decreasedValue:
            '${((margin - 2.8346) / DocumentRuler.pointsPerCm).toStringAsFixed(1)} cm',
        onIncrease: () => change(2.8346),
        onDecrease: () => change(-2.8346),
        child: Tooltip(
          message:
              '$label: ${(margin / DocumentRuler.pointsPerCm).toStringAsFixed(2)} cm · Sürükleyin',
          child: MouseRegion(
            cursor: horizontal
                ? SystemMouseCursors.resizeLeftRight
                : SystemMouseCursors.resizeUpDown,
            child: GestureDetector(
              key: ValueKey(
                '${horizontal ? 'horizontal' : 'vertical'}-ruler-${start ? 'start' : 'end'}',
              ),
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) => change(
                (horizontal ? details.delta.dx : details.delta.dy) /
                    scale *
                    (start ? 1 : -1),
              ),
              child: SizedBox(
                width: horizontal ? (grip ? 6 : 18) : 24,
                height: horizontal ? 24 : 18,
                child: grip
                    ? null
                    : Icon(
                        horizontal
                            ? Icons.arrow_drop_down_rounded
                            : Icons.arrow_right_rounded,
                        size: 24,
                        color: scheme.primary,
                      ),
              ),
            ),
          ),
        ),
      );
      final half = grip ? 3.0 : 9.0;
      return Positioned(
        left: horizontal
            ? (position - half).clamp(0.0, widget.pixels - 2 * half)
            : 0,
        top: horizontal ? 0 : (position - 9).clamp(0.0, widget.pixels - 18),
        child: child,
      );
    }

    return SizedBox(
      width: horizontal ? widget.pixels : 24,
      height: horizontal ? 24 : widget.pixels,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: horizontal ? const ValueKey('ruler-track') : null,
              behavior: HitTestBehavior.opaque,
              onTapUp: paragraph == null
                  ? null
                  : (d) => _addStop(paragraph, d.localPosition.dx),
              child: CustomPaint(
                painter: _RulerPainter(
                  widget.axis,
                  widget.pagePoints,
                  leading,
                  trailing,
                  scheme,
                ),
              ),
            ),
          ),
          handle(true),
          handle(false),
          if (paragraph != null) ..._paragraphMarks(paragraph, scheme),
          if (_guide != null)
            Positioned(
              key: const ValueKey('ruler-guide'),
              left: _guide! * scale - .5,
              top: 24,
              child: IgnorePointer(
                child: Container(
                  width: 1,
                  height: 2000,
                  color: scheme.primary.withValues(alpha: .6),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// A click on the ruler, inside the margins: a stop of the kind chosen.
  void _addStop(RulerParagraph p, double x) {
    final page = x / _scale;
    if (page <= widget.leading || page >= widget.pagePoints - widget.trailing) {
      return;
    }
    final at = _snapped(page - widget.leading - p.origin);
    if (at <= 0) return;
    final stops = [
      for (final s in p.stops)
        if ((s.position - at).abs() > .5) s,
      TabStop(at, _kind),
    ]..sort((a, b) => a.position.compareTo(b.position));
    _tell(p.copyWith(stops: stops));
  }

  List<Widget> _paragraphMarks(RulerParagraph p, ColorScheme scheme) {
    final scale = _scale;
    final left = widget.leading;
    final ink = scheme.primary;
    final textEnd = widget.pagePoints - widget.trailing;

    /// A triangle the size of a fingertip's aim, dragged along the ruler.
    Widget mark({
      required Key key,
      required String tip,
      required double at,
      required bool down,
      required RulerParagraph Function(double points) moved,
    }) {
      return Positioned(
        left: at * scale - 7,
        top: down ? 0 : 14,
        child: Tooltip(
          message: tip,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              key: key,
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => setState(() => _guide = at),
              onHorizontalDragUpdate: (d) {
                final now = (_guide ?? at) + d.delta.dx / scale;
                setState(() {
                  _guide = now.clamp(0, widget.pagePoints).toDouble();
                  _moving = moved(_snapped(_guide! - left));
                });
              },
              onHorizontalDragEnd: (_) {
                final next = _moving;
                if (next != null) {
                  _tell(next);
                } else {
                  setState(() => _guide = null);
                }
              },
              child: SizedBox(
                width: 14,
                height: 10,
                child: CustomPaint(
                  painter: _Triangle(down: down, color: ink),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return [
      // The kind of stop a click puts, at the ruler's start.
      Positioned(
        left: 1,
        top: 3,
        child: Tooltip(
          message:
              'Sekme türü: ${_kindName(_kind)} · Değiştirmek için tıklayın',
          child: InkWell(
            key: const ValueKey('ruler-tab-kind'),
            onTap: () => setState(
              () => _kind = switch (_kind) {
                TabAlign.left => TabAlign.centre,
                TabAlign.centre => TabAlign.right,
                TabAlign.right => TabAlign.decimal,
                _ => TabAlign.left,
              },
            ),
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(3),
              ),
              child: CustomPaint(painter: _StopGlyph(_kind, scheme.onSurface)),
            ),
          ),
        ),
      ),
      for (final (i, stop) in p.stops.indexed)
        Positioned(
          left: (left + p.origin + stop.position) * scale - 6,
          top: 11,
          child: Tooltip(
            message:
                '${_kindName(stop.align)} sekme · '
                '${((p.origin + stop.position) / DocumentRuler.pointsPerCm).toStringAsFixed(2)} cm · '
                'Silmek için aşağı sürükleyin ya da çift tıklayın',
            child: GestureDetector(
              key: ValueKey('ruler-tab-$i'),
              behavior: HitTestBehavior.opaque,
              onDoubleTap: () =>
                  _tell(p.copyWith(stops: [...p.stops]..removeAt(i))),
              onPanStart: (_) =>
                  setState(() => _guide = left + p.origin + stop.position),
              onPanUpdate: (d) {
                final base = _moving ?? p;
                final now = (_guide ?? 0) + d.delta.dx / scale;
                final stops = [...base.stops];
                if (i >= stops.length) return;
                // Dragged off the ruler: shown gone, gone when let go.
                final off = d.localPosition.dy > 26;
                setState(() {
                  _guide = now;
                  stops[i] = TabStop(
                    _snapped(now - left - p.origin),
                    stop.align,
                  );
                  _moving = base.copyWith(stops: stops);
                  _offRuler = off;
                });
              },
              onPanEnd: (_) {
                final base = _moving ?? p;
                final stops = [...base.stops];
                if (_offRuler || i < stops.length && stops[i].position <= 0) {
                  if (i < stops.length) stops.removeAt(i);
                }
                _offRuler = false;
                stops.sort((a, b) => a.position.compareTo(b.position));
                _tell(base.copyWith(stops: stops));
              },
              child: SizedBox(
                width: 12,
                height: 13,
                child: CustomPaint(
                  painter: _StopGlyph(stop.align, scheme.onSurface),
                ),
              ),
            ),
          ),
        ),
      mark(
        key: const ValueKey('ruler-first'),
        tip: 'İlk satır girintisi',
        at: left + p.firstRow,
        down: true,
        moved: (points) =>
            p.copyWith(firstRow: points.clamp(0, textEnd - left - 36)),
      ),
      mark(
        key: const ValueKey('ruler-left'),
        tip: 'Sol ve asılı girinti',
        at: left + p.otherRows,
        down: false,
        moved: (points) =>
            p.copyWith(otherRows: points.clamp(0, textEnd - left - 36)),
      ),
      mark(
        key: const ValueKey('ruler-right'),
        tip: 'Sağ girinti',
        at: textEnd - p.right,
        down: false,
        moved: (points) => p.copyWith(
          right: (textEnd - left - points).clamp(0, textEnd - left - 36),
        ),
      ),
    ];
  }

  bool _offRuler = false;

  static String _kindName(TabAlign a) => switch (a) {
    TabAlign.left => 'Sol',
    TabAlign.centre => 'Orta',
    TabAlign.right => 'Sağ',
    TabAlign.decimal => 'Ondalık',
    TabAlign.bar => 'Çubuk',
  };
}

/// An indent's triangle: pointing down for the first row, up for the rest.
class _Triangle extends CustomPainter {
  const _Triangle({required this.down, required this.color});
  final bool down;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = down
        ? (Path()
            ..moveTo(2, 1)
            ..lineTo(w - 2, 1)
            ..lineTo(w / 2, h - 1)
            ..close())
        : (Path()
            ..moveTo(w / 2, 1)
            ..lineTo(w - 2, h - 1)
            ..lineTo(2, h - 1)
            ..close());
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _Triangle old) =>
      old.down != down || old.color != color;
}

/// A tab stop's mark, as word processors draw them: └ left, ┴ centre,
/// ┘ right, ┴ with a dot for a decimal one.
class _StopGlyph extends CustomPainter {
  const _StopGlyph(this.align, this.color);
  final TabAlign align;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.square;
    final mid = size.width / 2, top = size.height * .25;
    final base = size.height * .8, half = size.width * .32;
    canvas.drawLine(Offset(mid, top), Offset(mid, base), paint);
    switch (align) {
      case TabAlign.left:
        canvas.drawLine(Offset(mid, base), Offset(mid + half, base), paint);
      case TabAlign.right:
        canvas.drawLine(Offset(mid - half, base), Offset(mid, base), paint);
      case TabAlign.centre || TabAlign.bar:
        canvas.drawLine(
          Offset(mid - half, base),
          Offset(mid + half, base),
          paint,
        );
      case TabAlign.decimal:
        canvas.drawLine(
          Offset(mid - half, base),
          Offset(mid + half, base),
          paint,
        );
        canvas.drawCircle(Offset(mid + half * .9, top + 1), 1.2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StopGlyph old) =>
      old.align != align || old.color != color;
}

class _RulerPainter extends CustomPainter {
  final Axis axis;
  final double points, leading, trailing;
  final ColorScheme scheme;
  _RulerPainter(
    this.axis,
    this.points,
    this.leading,
    this.trailing,
    this.scheme,
  );
  @override
  void paint(Canvas canvas, Size size) {
    final horizontal = axis == Axis.horizontal;
    final extent = horizontal ? size.width : size.height;
    final scale = extent / points;
    final paint = Paint()..color = scheme.surfaceContainerHighest;
    canvas.drawRect(Offset.zero & size, paint);
    paint.color = scheme.surface;
    canvas.drawRect(
      horizontal
          ? Rect.fromLTWH(
              leading * scale,
              0,
              (points - leading - trailing) * scale,
              size.height,
            )
          : Rect.fromLTWH(
              0,
              leading * scale,
              size.width,
              (points - leading - trailing) * scale,
            ),
      paint,
    );
    paint.color = scheme.onSurfaceVariant.withValues(alpha: .45);
    paint.strokeWidth = .7;
    const step = DocumentRuler.pointsPerCm / 2;
    for (
      var tick = (-leading / step).ceil();
      tick <= ((points - leading) / step).floor();
      tick++
    ) {
      final at = (leading + tick * step) * scale;
      final major = tick.isEven;
      if (horizontal) {
        canvas.drawLine(
          Offset(at, size.height - (major ? 7 : 4)),
          Offset(at, size.height),
          paint,
        );
      } else {
        canvas.drawLine(
          Offset(size.width - (major ? 7 : 4), at),
          Offset(size.width, at),
          paint,
        );
      }
      if (!major || tick == 0) continue;
      final text = TextPainter(
        text: TextSpan(
          text: '${tick ~/ 2}',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 9,
            color: scheme.onSurfaceVariant,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(
        canvas,
        horizontal
            ? Offset(at - text.width / 2, 1)
            : Offset(1, at - text.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.leading != leading ||
      old.trailing != trailing ||
      old.points != points ||
      old.scheme != scheme ||
      old.axis != axis;
}

/// [builder] with [value] as it is read whenever [listenable] changes, built
/// again only when it reads otherwise: the caret's paragraph is read at
/// every key, and the ruler, the same for the whole paragraph, was drawn
/// again with each.
class DistinctBuilder<T> extends StatefulWidget {
  const DistinctBuilder({
    super.key,
    required this.listenable,
    required this.value,
    required this.builder,
  });

  final Listenable listenable;
  final T Function() value;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<DistinctBuilder<T>> createState() => _DistinctBuilderState<T>();
}

class _DistinctBuilderState<T> extends State<DistinctBuilder<T>> {
  late T _value = widget.value();

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(DistinctBuilder<T> old) {
    super.didUpdateWidget(old);
    if (!identical(old.listenable, widget.listenable)) {
      old.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
    // Built again from above: read anew, as everything else is.
    _value = widget.value();
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final next = widget.value();
    if (next != _value) setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}

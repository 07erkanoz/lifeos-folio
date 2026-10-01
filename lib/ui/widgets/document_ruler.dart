import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Centimetre ruler backed by document points (72 pt = 1 inch).
class DocumentRuler extends StatelessWidget {
  static const pointsPerCm = 72 / 2.54;
  final Axis axis;
  final double pagePoints;
  final double pixels;
  final double leading;
  final double trailing;
  final void Function(double leading, double trailing) onChanged;
  const DocumentRuler({
    super.key,
    required this.axis,
    required this.pagePoints,
    required this.pixels,
    required this.leading,
    required this.trailing,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final horizontal = axis == Axis.horizontal;
    final scale = pixels / pagePoints;
    final scheme = Theme.of(context).colorScheme;
    Widget handle(bool start) {
      final margin = start ? leading : trailing;
      final position = (start ? leading : pagePoints - trailing) * scale;
      final label = horizontal
          ? (start ? 'Sol kenar boşluğu' : 'Sağ kenar boşluğu')
          : (start ? 'Üst kenar boşluğu' : 'Alt kenar boşluğu');
      void change(double delta) {
        final next = (margin + delta)
            .clamp(
              0.0,
              math.max(0.0, pagePoints - (start ? trailing : leading) - 72),
            )
            .toDouble();
        onChanged(start ? next : leading, start ? trailing : next);
      }

      final child = Semantics(
        label: label,
        value: '${(margin / pointsPerCm).toStringAsFixed(1)} cm',
        increasedValue:
            '${((margin + 2.8346) / pointsPerCm).toStringAsFixed(1)} cm',
        decreasedValue:
            '${((margin - 2.8346) / pointsPerCm).toStringAsFixed(1)} cm',
        onIncrease: () => change(2.8346),
        onDecrease: () => change(-2.8346),
        child: Tooltip(
          message:
              '$label: ${(margin / pointsPerCm).toStringAsFixed(2)} cm · Sürükleyin',
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
                width: horizontal ? 18 : 24,
                height: horizontal ? 24 : 18,
                child: Icon(
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
      return Positioned(
        left: horizontal ? (position - 9).clamp(0.0, pixels - 18) : 0,
        top: horizontal ? 0 : (position - 9).clamp(0.0, pixels - 18),
        child: child,
      );
    }

    return SizedBox(
      width: horizontal ? pixels : 24,
      height: horizontal ? 24 : pixels,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _RulerPainter(
                axis,
                pagePoints,
                leading,
                trailing,
                scheme,
              ),
            ),
          ),
          handle(true),
          handle(false),
        ],
      ),
    );
  }
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
    final step = DocumentRuler.pointsPerCm / 2;
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
          style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
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

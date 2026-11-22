import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Folio Ajan's mark, drawn from Folio's own icon: the ivory paper F with
/// its folded corner, the sage ribbon around it, on the slate square. The
/// same mark in the palette, Folio Ajan and the floating voice window.
/// [live]: the ribbon's front runs, as long as Folio Ajan is talking.
class FolioMark extends StatefulWidget {
  const FolioMark({
    super.key,
    this.size = 28,
    this.live = false,
    this.square = true,
  });
  final double size;
  final bool live, square;

  @override
  State<FolioMark> createState() => _FolioMarkState();
}

class _FolioMarkState extends State<FolioMark>
    with SingleTickerProviderStateMixin {
  late final _run = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.live) _run.repeat();
  }

  @override
  void didUpdateWidget(FolioMark old) {
    super.didUpdateWidget(old);
    if (widget.live && !_run.isAnimating) _run.repeat();
    if (!widget.live && _run.isAnimating) _run.stop();
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.square(widget.size),
      painter: FolioMarkPainter(
        run: widget.live ? _run : null,
        square: widget.square,
      ),
    ),
  );
}

class FolioMarkPainter extends CustomPainter {
  FolioMarkPainter({this.run, this.square = true}) : super(repaint: run);
  final Animation<double>? run;
  final bool square;

  static const slateTop = Color(0xFF456A9C);
  static const slateBottom = Color(0xFF2B4669);
  static const ivory = Color(0xFFF6F1E7);
  static const fold = Color(0xFFD8CFBE);
  static const sage = Color(0xFF8FD6BF);
  static const sageBack = Color(0x8C7FC8B2);

  /// The F of the icon, in a 32 × 32 box.
  static Path letter() => Path()
    ..moveTo(9, 8.2)
    ..arcToPoint(const Offset(11.2, 6), radius: const Radius.circular(2.2))
    ..lineTo(19, 6)
    ..lineTo(23, 10)
    ..lineTo(23, 10.8)
    ..arcToPoint(const Offset(21.8, 12), radius: const Radius.circular(1.2))
    ..lineTo(14.2, 12)
    ..lineTo(14.2, 14.6)
    ..lineTo(19.8, 14.6)
    ..arcToPoint(const Offset(19.8, 17.8), radius: const Radius.circular(1.6))
    ..lineTo(14.2, 17.8)
    ..lineTo(14.2, 23.8)
    ..arcToPoint(const Offset(12, 26), radius: const Radius.circular(2.2))
    ..lineTo(11.2, 26)
    ..arcToPoint(const Offset(9, 23.8), radius: const Radius.circular(2.2))
    ..close();

  static Path corner() => Path()
    ..moveTo(19, 6)
    ..lineTo(19, 9)
    ..arcToPoint(
      const Offset(20, 10),
      radius: const Radius.circular(1),
      clockwise: false,
    )
    ..lineTo(23, 10)
    ..close();

  /// Half of the ribbon: the back runs over the top, the front under.
  static Path ribbon({required bool front}) {
    const r = Radius.elliptical(13.2, 4.4);
    final p = Path()..moveTo(front ? 29.2 : 2.8, 17);
    p.arcToPoint(Offset(front ? 2.8 : 29.2, 17), radius: r);
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    if (square) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 32, 32),
          const Radius.circular(8),
        ),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [slateTop, slateBottom],
          ).createShader(const Rect.fromLTWH(0, 0, 32, 32)),
      );
    }
    void tilted(void Function() draw) {
      canvas.save();
      canvas.translate(16, 17);
      canvas.rotate(-20 * math.pi / 180);
      canvas.translate(-16, -17);
      draw();
      canvas.restore();
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    tilted(
      () => canvas.drawPath(
        ribbon(front: false),
        stroke
          ..color = sageBack
          ..strokeWidth = 1.8,
      ),
    );
    canvas.drawPath(letter(), Paint()..color = ivory);
    canvas.drawPath(corner(), Paint()..color = fold);
    tilted(() {
      final front = ribbon(front: true);
      final paint = stroke
        ..color = sage
        ..strokeWidth = 2;
      final t = run?.value;
      if (t == null) {
        canvas.drawPath(front, paint);
        return;
      }
      // Running dashes, 14 on, 6 off, as the mock-up's animation.
      for (final m in front.computeMetrics()) {
        var at = -(t * 40) % 20 - 20;
        while (at < m.length) {
          final a = math.max(0.0, at), b = math.min(m.length, at + 14);
          if (b > a) canvas.drawPath(m.extractPath(a, b), paint);
          at += 20;
        }
      }
    });
    canvas.restore();
  }

  @override
  bool shouldRepaint(FolioMarkPainter old) =>
      old.square != square || old.run != run;
}

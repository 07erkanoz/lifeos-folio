import 'package:flutter/material.dart';

/// Which part of the frame a drag took hold of.
enum _Grip { draw, move, topLeft, topRight, bottomLeft, bottomRight }

/// The frame a reader drags over a photograph to say what to keep.
///
/// It works in shares of the picture rather than in pixels of the screen,
/// so turning the window, or the picture, does not throw the frame away.
class CropOverlay extends StatefulWidget {
  const CropOverlay({
    super.key,
    required this.picture,
    required this.selection,
    required this.onChanged,
  });

  /// Where the photograph actually sits inside this box. A picture is
  /// letterboxed to fit, and a frame dragged over the letterbox would cut
  /// out nothing at all.
  final Rect picture;

  /// What is kept, as a share of [picture], or null before anything has
  /// been drawn.
  final Rect? selection;

  final ValueChanged<Rect?> onChanged;

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay> {
  /// How near a corner a finger has to land to take hold of it, and the
  /// smallest frame worth keeping. A frame below that is a stray tap.
  static const _grab = 26.0, _least = 16.0;

  _Grip? _grip;
  Offset _from = Offset.zero;
  Rect _started = Rect.zero;

  Rect? get _onScreen {
    final share = widget.selection;
    if (share == null) return null;
    final box = widget.picture;
    return Rect.fromLTWH(
      box.left + share.left * box.width,
      box.top + share.top * box.height,
      share.width * box.width,
      share.height * box.height,
    );
  }

  void _emit(Rect? screen) {
    final box = widget.picture;
    if (screen == null || box.width <= 0 || box.height <= 0) {
      widget.onChanged(null);
      return;
    }
    final held = _within(screen, box);
    widget.onChanged(
      Rect.fromLTWH(
        (held.left - box.left) / box.width,
        (held.top - box.top) / box.height,
        held.width / box.width,
        held.height / box.height,
      ),
    );
  }

  /// A frame kept inside the picture, corner by corner.
  static Rect _within(Rect rect, Rect box) => Rect.fromLTRB(
    rect.left.clamp(box.left, box.right),
    rect.top.clamp(box.top, box.bottom),
    rect.right.clamp(box.left, box.right),
    rect.bottom.clamp(box.top, box.bottom),
  );

  /// A frame moved back inside the picture without being made smaller,
  /// which is what dragging one to the edge should do.
  static Rect _slidInside(Rect rect, Rect box) {
    var moved = rect;
    if (moved.left < box.left) {
      moved = moved.shift(Offset(box.left - moved.left, 0));
    }
    if (moved.top < box.top) {
      moved = moved.shift(Offset(0, box.top - moved.top));
    }
    if (moved.right > box.right) {
      moved = moved.shift(Offset(box.right - moved.right, 0));
    }
    if (moved.bottom > box.bottom) {
      moved = moved.shift(Offset(0, box.bottom - moved.bottom));
    }
    return _within(moved, box);
  }

  _Grip _gripAt(Offset at) {
    final frame = _onScreen;
    if (frame == null) return _Grip.draw;
    bool near(Offset corner) => (at - corner).distance <= _grab;
    if (near(frame.topLeft)) return _Grip.topLeft;
    if (near(frame.topRight)) return _Grip.topRight;
    if (near(frame.bottomLeft)) return _Grip.bottomLeft;
    if (near(frame.bottomRight)) return _Grip.bottomRight;
    if (frame.contains(at)) return _Grip.move;
    return _Grip.draw;
  }

  void _start(DragStartDetails details) {
    _from = details.localPosition;
    _grip = _gripAt(_from);
    _started = _onScreen ?? Rect.fromPoints(_from, _from);
    if (_grip == _Grip.draw) _emit(null);
  }

  void _update(DragUpdateDetails details) {
    final at = details.localPosition;
    final moved = at - _from;
    switch (_grip) {
      case null:
        return;
      case _Grip.draw:
        _emit(Rect.fromPoints(_from, at));
      case _Grip.move:
        _emit(_slidInside(_started.shift(moved), widget.picture));
      case _Grip.topLeft:
        _emit(Rect.fromPoints(_started.bottomRight, _started.topLeft + moved));
      case _Grip.topRight:
        _emit(Rect.fromPoints(_started.bottomLeft, _started.topRight + moved));
      case _Grip.bottomLeft:
        _emit(Rect.fromPoints(_started.topRight, _started.bottomLeft + moved));
      case _Grip.bottomRight:
        _emit(Rect.fromPoints(_started.topLeft, _started.bottomRight + moved));
    }
  }

  void _end(DragEndDetails _) {
    _grip = null;
    // A frame too small to see is a stray press, not a crop.
    final frame = _onScreen;
    if (frame != null && (frame.width < _least || frame.height < _least)) {
      _emit(null);
    }
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.precise,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _start,
      onPanUpdate: _update,
      onPanEnd: _end,
      child: CustomPaint(
        painter: _CropPainter(picture: widget.picture, frame: _onScreen),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

class _CropPainter extends CustomPainter {
  const _CropPainter({required this.picture, required this.frame});

  final Rect picture;
  final Rect? frame;

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Paint()..color = Colors.black.withValues(alpha: .52);
    final kept = frame;
    if (kept == null) {
      // Nothing framed yet: the whole picture is dimmed, so it is plain
      // that this is a mode and not the picture having gone dark.
      canvas.drawRect(picture, shade);
      return;
    }
    // Everything but the frame, in four pieces, so the kept part is the
    // only part at full strength.
    canvas
      ..drawRect(
        Rect.fromLTRB(picture.left, picture.top, picture.right, kept.top),
        shade,
      )
      ..drawRect(
        Rect.fromLTRB(picture.left, kept.bottom, picture.right, picture.bottom),
        shade,
      )
      ..drawRect(
        Rect.fromLTRB(picture.left, kept.top, kept.left, kept.bottom),
        shade,
      )
      ..drawRect(
        Rect.fromLTRB(kept.right, kept.top, picture.right, kept.bottom),
        shade,
      );

    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: .55);
    for (var i = 1; i < 3; i++) {
      final x = kept.left + kept.width * i / 3;
      final y = kept.top + kept.height * i / 3;
      canvas
        ..drawLine(Offset(x, kept.top), Offset(x, kept.bottom), thin)
        ..drawLine(Offset(kept.left, y), Offset(kept.right, y), thin);
    }

    canvas.drawRect(
      kept,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white,
    );

    // Corners drawn as brackets rather than dots: a bracket says which way
    // the corner goes, and stays visible on a white photograph.
    final grip = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.square
      ..color = Colors.white;
    const arm = 18.0;
    final reach = arm.clamp(0.0, kept.shortestSide / 2);
    void bracket(Offset corner, double dx, double dy) {
      canvas
        ..drawLine(corner, corner + Offset(dx * reach, 0), grip)
        ..drawLine(corner, corner + Offset(0, dy * reach), grip);
    }

    bracket(kept.topLeft, 1, 1);
    bracket(kept.topRight, -1, 1);
    bracket(kept.bottomLeft, 1, -1);
    bracket(kept.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.picture != picture || old.frame != frame;
}

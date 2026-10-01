import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Turning a page with a finger.
///
/// Only touch counts. A mouse drag across a document is how text gets
/// selected, and a viewer that turned the page instead would be unusable on a
/// desktop; a finger drag across a page that has nowhere to pan means one
/// thing only.
///
/// The pointers are watched rather than claimed, so nothing is taken away from
/// the viewer underneath: it keeps its panning, its pinch and its selection,
/// and [onSwipe] is offered the gesture only when the viewer had no use for
/// it — which is what [enabled] answers.
class SwipePages extends StatefulWidget {
  final Widget child;

  /// Whether a sideways drag means anything right now. False while the
  /// content is zoomed in, where a drag is panning.
  final bool Function() enabled;

  /// Forward is the next page, the way a right-to-left drag reads.
  final void Function(bool forward) onSwipe;

  const SwipePages({
    super.key,
    required this.child,
    required this.enabled,
    required this.onSwipe,
  });

  @override
  State<SwipePages> createState() => _SwipePagesState();
}

class _SwipePagesState extends State<SwipePages> {
  /// How far a finger has to travel, and how much straighter than it is tall,
  /// before it counts. A page turn is a deliberate movement; scrolling down a
  /// long document must never turn one by accident.
  static const _distance = 64.0;
  static const _straightness = 1.8;
  static const _within = Duration(milliseconds: 700);

  int? _pointer;
  Offset _from = Offset.zero;
  DateTime _at = DateTime.now();
  bool _multiTouch = false;

  void _down(PointerDownEvent event) {
    if (_pointer != null) {
      // A second finger is a pinch, not a page turn.
      _multiTouch = true;
      return;
    }
    if (event.kind != PointerDeviceKind.touch) return;
    _pointer = event.pointer;
    _from = event.position;
    _at = DateTime.now();
    _multiTouch = false;
  }

  void _up(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    if (_multiTouch || event is PointerCancelEvent) return;
    if (DateTime.now().difference(_at) > _within) return;
    final moved = event.position - _from;
    if (moved.dx.abs() < _distance) return;
    if (moved.dx.abs() < moved.dy.abs() * _straightness) return;
    if (!widget.enabled()) return;
    widget.onSwipe(moved.dx < 0);
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _down,
    onPointerUp: _up,
    onPointerCancel: _up,
    child: widget.child,
  );
}

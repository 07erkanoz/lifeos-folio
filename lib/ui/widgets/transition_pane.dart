import 'package:flutter/material.dart';

/// Keeps document/editor state alive. Only opacity and a small translation
/// animate; expensive document layout is never driven by the animation.
class TransitionPane extends StatefulWidget {
  final bool visible;
  final Widget child;
  const TransitionPane({super.key, required this.visible, required this.child});
  @override
  State<TransitionPane> createState() => _TransitionPaneState();
}

class _TransitionPaneState extends State<TransitionPane>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 170),
    value: widget.visible ? 1 : 0,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  @override
  void didUpdateWidget(TransitionPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = widget.visible ? 1 : 0;
      } else if (widget.visible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The child as it was when the pane was put away: given back unchanged
  /// while it stays away, so that each rebuild of the page above (a badge,
  /// a count) does not make the hidden editor or viewer again too. Shown
  /// again, it is the page's latest.
  Widget? _frozen;

  @override
  Widget build(BuildContext context) {
    final away = !widget.visible && _controller.isDismissed;
    final shown = away ? (_frozen ??= widget.child) : widget.child;
    if (!away) _frozen = null;
    return _build(shown);
  }

  Widget _build(Widget shown) => AnimatedBuilder(
    animation: _controller,
    child: RepaintBoundary(child: shown),
    builder: (context, child) => Offstage(
      offstage: _controller.isDismissed,
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: ExcludeFocus(
          excluding: !widget.visible,
          child: TickerMode(
            enabled: widget.visible,
            child: FadeTransition(
              opacity: _curve,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, .012),
                  end: Offset.zero,
                ).animate(_curve),
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

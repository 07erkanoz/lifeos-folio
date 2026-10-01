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

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: RepaintBoundary(child: widget.child),
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

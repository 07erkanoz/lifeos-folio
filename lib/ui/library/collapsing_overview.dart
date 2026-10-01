import 'package:flutter/material.dart';

/// Makes room for documents without rebuilding their rows on every scroll tick.
class CollapsingOverview extends StatefulWidget {
  final Widget header;
  final Widget child;
  const CollapsingOverview({
    super.key,
    required this.header,
    required this.child,
  });

  @override
  State<CollapsingOverview> createState() => _CollapsingOverviewState();
}

class _CollapsingOverviewState extends State<CollapsingOverview> {
  bool _collapsed = false;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    // Only movement notifications count: changing the viewport height during
    // the animation must not toggle the header back and forth on short lists.
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (!_collapsed && delta > 0 && notification.metrics.pixels > 48) {
        setState(() => _collapsed = true);
      } else if (_collapsed && delta < 0 && notification.metrics.pixels <= 0) {
        setState(() => _collapsed = false);
      }
    } else if (notification is OverscrollNotification &&
        _collapsed &&
        notification.overscroll < 0 &&
        notification.metrics.pixels <= 0) {
      setState(() => _collapsed = false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ClipRect(
        child: AnimatedAlign(
          alignment: Alignment.topCenter,
          heightFactor: _collapsed ? 0 : 1,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeInOutCubic,
          child: IgnorePointer(
            ignoring: _collapsed,
            child: ExcludeSemantics(
              excluding: _collapsed,
              child: widget.header,
            ),
          ),
        ),
      ),
      Expanded(
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        ),
      ),
    ],
  );
}

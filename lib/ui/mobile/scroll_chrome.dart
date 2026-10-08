import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The headings above a long list on a phone, folded away while the list
/// is scrolled on and back as soon as it is pulled back (UYAP Dosyalarım's
/// documents): the list takes the screen when it is being read.
abstract final class ScrollChrome {
  static final hidden = ValueNotifier<bool>(false);

  /// Back, for a new page.
  static void show() => hidden.value = false;

  /// How tall each heading that folds is, while shown.
  static final _heights = <Object, double>{};

  /// What folding gives the list: a list that would then fit, and so not
  /// scroll, is never folded for, or nothing could bring the headings
  /// back (the agenda's day).
  static double get foldedHeight =>
      _heights.values.fold(0.0, (sum, h) => sum + h);
}

/// Folds [ScrollChrome] as the vertical lists under it are scrolled:
/// hidden while scrolled on, shown when scrolled back or at the top.
class ChromeScrollWatcher extends StatelessWidget {
  const ChromeScrollWatcher({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) {
        // Folded, it fits and cannot be pulled back: shown again.
        if (ScrollChrome.hidden.value &&
            n.metrics.axis == Axis.vertical &&
            n.metrics.maxScrollExtent <= 0) {
          ScrollChrome.hidden.value = false;
        }
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.axis != Axis.vertical) return false;
          if (n is UserScrollNotification) {
            if (n.direction == ScrollDirection.reverse &&
                n.metrics.maxScrollExtent > ScrollChrome.foldedHeight) {
              ScrollChrome.hidden.value = true;
            } else if (n.direction == ScrollDirection.forward) {
              ScrollChrome.hidden.value = false;
            }
          } else if (n is OverscrollNotification && n.overscroll < 0) {
            // Pulled down at the top.
            ScrollChrome.hidden.value = false;
          } else if (n is ScrollUpdateNotification && n.metrics.pixels <= 0) {
            ScrollChrome.hidden.value = false;
          }
          return false;
        },
        child: child,
      ),
    );
  }
}

/// [child], folded away while [ScrollChrome] is hidden and [enabled].
class FoldingChrome extends StatefulWidget {
  const FoldingChrome({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<FoldingChrome> createState() => _FoldingChromeState();
}

class _FoldingChromeState extends State<FoldingChrome> {
  final _id = Object();

  @override
  void dispose() {
    ScrollChrome._heights.remove(_id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      ScrollChrome._heights.remove(_id);
      return widget.child;
    }
    return ValueListenableBuilder<bool>(
      valueListenable: ScrollChrome.hidden,
      builder: (context, hidden, child) => ClipRect(
        child: AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: hidden
              ? const SizedBox(width: double.infinity, height: 0)
              : child,
        ),
      ),
      child: _Measured(
        onHeight: (h) => ScrollChrome._heights[_id] = h,
        child: widget.child,
      ),
    );
  }
}

/// Tells its child's height after each layout.
class _Measured extends SingleChildRenderObjectWidget {
  const _Measured({required this.onHeight, super.child});
  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasured(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured r) =>
      r.onHeight = onHeight;
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.onHeight);
  ValueChanged<double> onHeight;

  @override
  void performLayout() {
    super.performLayout();
    onHeight(size.height);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The headings above a long list on a phone, folded away while the list
/// is scrolled on and back as soon as it is pulled back (UYAP Dosyalarım's
/// documents): the list takes the screen when it is being read.
abstract final class ScrollChrome {
  static final hidden = ValueNotifier<bool>(false);

  /// Back, for a new page.
  static void show() => hidden.value = false;
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
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis != Axis.vertical) return false;
        if (n is UserScrollNotification) {
          if (n.direction == ScrollDirection.reverse &&
              n.metrics.maxScrollExtent > 0) {
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
    );
  }
}

/// [child], folded away while [ScrollChrome] is hidden and [enabled].
class FoldingChrome extends StatelessWidget {
  const FoldingChrome({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
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
      child: child,
    );
  }
}

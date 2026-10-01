import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'page_zoom.dart';

// The editor and both enclosing scroll views must leave Ctrl+wheel to zoom.
class _PageScrollPhysics extends ClampingScrollPhysics {
  const _PageScrollPhysics({super.parent});
  @override
  _PageScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _PageScrollPhysics(parent: buildParent(ancestor));
  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      !HardwareKeyboard.instance.isControlPressed &&
      super.shouldAcceptUserOffset(position);
}

class _PageScrollBehavior extends MaterialScrollBehavior {
  const _PageScrollBehavior();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const _PageScrollPhysics();
}

/// Scales the complete page, including text and rulers, without changing layout
/// or saved document formatting. Scroll offsets remain attached to the page.
class EditorPageViewport extends StatefulWidget {
  final Widget child;
  final double pageWidth;
  final Color background;

  /// Said at the left of the bar under the page: the state of the document,
  /// where a reader looks for it, rather than among the tools.
  final Widget? status;

  /// A panel between the page and the bar, opened from [status].
  final Widget? drawer;
  const EditorPageViewport({
    super.key,
    required this.child,
    required this.pageWidth,
    required this.background,
    this.status,
    this.drawer,
  });
  @override
  State<EditorPageViewport> createState() => _EditorPageViewportState();
}

class _EditorPageViewportState extends State<EditorPageViewport> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  double _zoom = PageZoom.initial;

  /// The page opens at [PageZoom.initial], the size the preview opens at,
  /// narrowed only where the window cannot hold it.
  bool _opened = false;

  void _setZoom(double value, {double anchorY = 0}) {
    final next = value.clamp(.5, 3.0);
    if (next == _zoom) return;
    final offset = _vertical.hasClients ? _vertical.offset : 0.0;
    final target = (offset + anchorY) * next / _zoom - anchorY;
    setState(() => _zoom = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _vertical.hasClients) {
        _vertical.jumpTo(target.clamp(0, _vertical.position.maxScrollExtent));
      }
    });
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // Read here, around both the page and the bar under it, so the size the
    // page opens at and the percentage shown for it are one number.
    builder: (context, outer) {
      if (!_opened) {
        _opened = true;
        // The page sits inside 16 px of padding either side.
        _zoom = PageZoom.opening(widget.pageWidth, outer.maxWidth - 32);
      }
      return _viewport(context);
    },
  );

  Widget _viewport(BuildContext context) => Column(
    children: [
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Listener(
              key: const ValueKey('editor-page-viewport'),
              onPointerSignal: (event) {
                if (event is PointerScrollEvent &&
                    HardwareKeyboard.instance.isControlPressed) {
                  GestureBinding.instance.pointerSignalResolver.register(
                    event,
                    (_) {
                      _setZoom(
                        _zoom * math.exp(-event.scrollDelta.dy / 500),
                        anchorY: event.localPosition.dy,
                      );
                    },
                  );
                }
              },
              child: ColoredBox(
                color: widget.background,
                child: ScrollConfiguration(
                  behavior: const _PageScrollBehavior(),
                  child: SingleChildScrollView(
                    controller: _vertical,
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    child: SingleChildScrollView(
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Center(
                            child: SizedBox(
                              key: const ValueKey('editor-scaled-page'),
                              width: widget.pageWidth * _zoom,
                              child: FittedBox(
                                alignment: Alignment.topCenter,
                                fit: BoxFit.fitWidth,
                                child: widget.child,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      // Above the bar, so the bar stays where it was and the page gives way.
      ?widget.drawer,
      Container(
        height: 30,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            ?widget.status,
            const Spacer(),
            IconButton(
              tooltip: 'Uzaklaştır',
              onPressed: () => _setZoom(_zoom - .1),
              icon: const Icon(Icons.remove, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            ),
            PopupMenuButton<double>(
              tooltip: 'Yakınlaştırma · Ctrl + fare tekerleği',
              onSelected: _setZoom,
              itemBuilder: (_) => [
                for (final zoom in [.5, .75, 1.0, 1.2, 1.5, 2.0, 3.0])
                  PopupMenuItem(
                    value: zoom,
                    child: Text('%${(zoom * 100).round()}'),
                  ),
              ],
              child: SizedBox(
                width: 55,
                child: Center(
                  child: Text(
                    '%${(_zoom * 100).round()}',
                    key: const ValueKey('editor-zoom-label'),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Yakınlaştır',
              onPressed: () => _setZoom(_zoom + .1),
              icon: const Icon(Icons.add, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            ),
            TextButton(
              onPressed: () => _setZoom(PageZoom.initial),
              child: const Text('Sıfırla', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ),
    ],
  );
}

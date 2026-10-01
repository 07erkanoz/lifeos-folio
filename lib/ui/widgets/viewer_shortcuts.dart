import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The keys a page answers to while it is being read.
///
/// The viewers had none at all: turning a page, zooming, rotating and fitting
/// were each a trip to a button with the mouse, which is slow going through a
/// forty page scan.
///
/// A viewer takes the keyboard when it is clicked rather than when it appears.
/// Choosing a document from the list leaves the cursor in the list so the next
/// arrow key picks the next document, and stealing that would cost more than
/// the click saves.
class ViewerShortcuts extends StatefulWidget {
  const ViewerShortcuts({
    super.key,
    required this.child,
    this.onPrevious,
    this.onNext,
    this.onFirst,
    this.onLast,
    this.onZoomIn,
    this.onZoomOut,
    this.onFit,
    this.onRotate,
    this.onFind,
    this.onFullScreen,
    this.grabFocus = false,
  });

  final Widget child;

  /// Page back and forward. Left, right, page up, page down and space.
  final VoidCallback? onPrevious, onNext;

  /// The first and last page. Home and end.
  final VoidCallback? onFirst, onLast;

  /// Plus, minus, and zero for the size it started at.
  final VoidCallback? onZoomIn, onZoomOut, onFit;

  /// A quarter turn clockwise. R.
  final VoidCallback? onRotate;

  /// Find a word on the page. Ctrl+F, the way it is everywhere else.
  final VoidCallback? onFind;

  /// Full screen and back again. F.
  final VoidCallback? onFullScreen;

  /// Whether to take the keyboard the moment this appears, rather than
  /// waiting to be clicked.
  ///
  /// Off for a document: choosing one from the list leaves the cursor in
  /// the list, so the next arrow key picks the next document, and stealing
  /// that would cost more than the click saves. On for a photograph opened
  /// from the gallery, where the picture is the whole of what the reader
  /// asked for and the next arrow key can only mean the next picture. That
  /// difference was the whole of why arrow keys did nothing in the gallery.
  final bool grabFocus;

  @override
  State<ViewerShortcuts> createState() => _ViewerShortcutsState();
}

class _ViewerShortcutsState extends State<ViewerShortcuts> {
  final _focus = FocusNode(debugLabel: 'viewer');

  @override
  void initState() {
    super.initState();
    // After the frame: a focus asked for while the tree is still being
    // built is asked for against a node that is not in it yet.
    if (widget.grabFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.grabFocus) _focus.requestFocus();
      });
      // And again whenever the keyboard ends up held by nobody. Stepping
      // between pictures tears down one viewer and builds the next, and
      // anything that drops the focus in between leaves the reader pressing
      // an arrow key at nothing until they click the picture. Reclaiming
      // only when nothing real holds it means a dialog, a text field or a
      // list that has genuinely taken the keyboard is never interrupted.
      FocusManager.instance.addListener(_reclaim);
    }
  }

  void _reclaim() {
    if (!mounted || !widget.grabFocus || _focus.hasFocus) return;
    final holder = FocusManager.instance.primaryFocus;
    if (holder != null && holder is! FocusScopeNode) return;
    if (_focus.context == null || !_focus.canRequestFocus) return;
    _focus.requestFocus();
  }

  @override
  void didUpdateWidget(covariant ViewerShortcuts old) {
    super.didUpdateWidget(old);
    if (widget.grabFocus && !old.grabFocus) _focus.requestFocus();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_reclaim);
    _focus.dispose();
    super.dispose();
  }

  Map<ShortcutActivator, VoidCallback> get _bindings {
    final out = <ShortcutActivator, VoidCallback>{};
    void bind(List<LogicalKeyboardKey> keys, VoidCallback? action) {
      if (action == null) return;
      for (final key in keys) {
        out[SingleActivator(key)] = action;
        // A keypad is a keyboard too, and control is how a browser and a
        // reader both spell zooming, so both reach the same place.
        if (key == LogicalKeyboardKey.equal ||
            key == LogicalKeyboardKey.minus ||
            key == LogicalKeyboardKey.digit0) {
          out[SingleActivator(key, control: true)] = action;
        }
      }
    }

    bind([
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.pageUp,
    ], widget.onPrevious);
    bind([
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.space,
    ], widget.onNext);
    bind([LogicalKeyboardKey.home], widget.onFirst);
    bind([LogicalKeyboardKey.end], widget.onLast);
    bind([
      LogicalKeyboardKey.equal,
      LogicalKeyboardKey.add,
      LogicalKeyboardKey.numpadAdd,
    ], widget.onZoomIn);
    bind([
      LogicalKeyboardKey.minus,
      LogicalKeyboardKey.numpadSubtract,
    ], widget.onZoomOut);
    bind([LogicalKeyboardKey.digit0, LogicalKeyboardKey.numpad0], widget.onFit);
    bind([LogicalKeyboardKey.keyR], widget.onRotate);
    // F alone. F11 belongs to the window, and a viewer that swallowed it
    // while it happened to hold the keyboard would be a puzzle.
    bind([LogicalKeyboardKey.keyF], widget.onFullScreen);
    if (widget.onFind != null) {
      out[const SingleActivator(LogicalKeyboardKey.keyF, control: true)] =
          widget.onFind!;
      out[const SingleActivator(LogicalKeyboardKey.keyF, meta: true)] =
          widget.onFind!;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) => Listener(
    // Translucent, so the click counts wherever it lands on the page: a
    // rendered page does not answer a hit test everywhere, and deferring to
    // the child meant the keyboard was never handed over at all.
    behavior: HitTestBehavior.translucent,
    // Down rather than a tap: a drag across the page is how text is
    // selected and how a picture is panned, and neither ends in a tap.
    onPointerDown: (_) {
      if (!_focus.hasFocus) _focus.requestFocus();
    },
    child: CallbackShortcuts(
      bindings: _bindings,
      child: Focus(focusNode: _focus, child: widget.child),
    ),
  );
}

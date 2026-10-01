import 'package:flutter/material.dart';

/// A card shown over the document, near what the reader pressed.
///
/// Built like the quick look on the archive: an overlay rather than a
/// dialogue, so the document stays where it was and the reader is not taken
/// anywhere. It closes on Esc, on a press outside it, and when another card
/// takes its place.
///
/// Unlike the quick look it accepts the pointer, because what it shows — an
/// article, a decision, the meaning of a word — may be long enough to scroll
/// and is worth copying.
class OverlayCard {
  const OverlayCard._();

  static final _open = <VoidCallback>[];

  /// Closes the topmost card, if one is open. Answers whether it did, so
  /// Esc can go on to the next thing when it did not. Called from the app's
  /// own Esc handler in main.dart.
  static bool dismissActive() {
    if (_open.isEmpty) return false;
    _open.last();
    return true;
  }

  /// Puts a card on screen near [at], which is where the reader pressed.
  ///
  /// Only one is ever open: a second press replaces the first rather than
  /// stacking cards over a document.
  ///
  /// With [shrinkToFit], a card with room neither below nor above the press
  /// takes the larger of the two and is made short enough to fit it, rather
  /// than being pushed over the line that was pressed. Only for a card whose
  /// text scrolls in whatever height it is given.
  static void show(
    BuildContext context, {
    required Offset at,
    required double width,
    required double height,
    required Widget Function(VoidCallback close) builder,
    bool shrinkToFit = false,
  }) {
    dismissActive();
    final overlay = Overlay.of(context);
    final box = overlay.context.findRenderObject() as RenderBox;
    final size = box.size;
    final point = box.globalToLocal(at);

    final cardWidth = width < size.width - 24 ? width : size.width - 24;
    var cardHeight = height < size.height - 24 ? height : size.height - 24;
    // Below the press when there is room, above it when there is not, so the
    // card never covers the line that was pressed.
    final below = point.dy + 18;
    final roomBelow = size.height - below - 12;
    final roomAbove = point.dy - 18 - 12;
    if (shrinkToFit && cardHeight > roomBelow && cardHeight > roomAbove) {
      final room = roomBelow > roomAbove ? roomBelow : roomAbove;
      cardHeight = room < 260 ? 260 : room;
    }
    final top =
        (below + cardHeight + 12 <= size.height
                ? below
                : point.dy - cardHeight - 18)
            .clamp(12.0, size.height - cardHeight - 12);
    final left = (point.dx - cardWidth / 3).clamp(
      12.0,
      size.width - cardWidth - 12,
    );

    final theme = Theme.of(context);
    late final OverlayEntry entry;
    var closed = false;
    void close() {
      if (closed) return;
      closed = true;
      _open.remove(close);
      entry.remove();
      entry.dispose();
    }

    entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: close,
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: cardWidth,
            child: Theme(
              data: theme,
              child: shrinkToFit
                  ? ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: cardHeight),
                      child: builder(close),
                    )
                  : builder(close),
            ),
          ),
        ],
      ),
    );
    _open.add(close);
    overlay.insert(entry);
  }
}

/// The frame every one of these cards shares: a titled header with a way to
/// close it, a body, and a line naming where the words came from.
class OverlayCardFrame extends StatelessWidget {
  const OverlayCardFrame({
    super.key,
    required this.icon,
    required this.title,
    required this.source,
    required this.body,
    required this.maxHeight,
    required this.onClose,
    this.cardKey,
    this.actions = const [],
  });

  final IconData icon;
  final String title;

  /// Who said this, named so the reader can weigh it.
  final String source;
  final Widget body;
  final double maxHeight;
  final VoidCallback onClose;
  final Key? cardKey;

  /// What the reader can do with what is shown, beside the close button.
  final List<Widget> actions;

  static const headerHeight = 48.0;
  static const footerHeight = 34.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 140),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 5 * (1 - value)),
          child: child,
        ),
      ),
      child: Material(
        key: cardKey,
        elevation: 12,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: headerHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    ...actions,
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Kapat (Esc)',
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
            ),
            ColoredBox(
              color: theme.colorScheme.surfaceContainerLow,
              child: SizedBox(width: double.infinity, child: body),
            ),
            SizedBox(
              height: footerHeight,
              child: Center(
                child: Text(source, style: const TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A body that scrolls, for text long enough to need it.
class OverlayCardBody extends StatelessWidget {
  const OverlayCardBody({
    super.key,
    required this.child,
    required this.maxHeight,
  });

  final Widget child;
  final double maxHeight;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: maxHeight < 96 ? 96 : maxHeight),
    child: Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: child,
      ),
    ),
  );
}

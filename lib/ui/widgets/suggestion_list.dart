import 'package:flutter/material.dart';

import '../../services/editor/suggestions/suggestion_engine.dart';

/// The list of completions under the caret.
///
/// Unlike an [OverlayCard] it lays nothing over the page and never takes
/// the keyboard: the reader keeps typing into the document, Tab takes the
/// marked line, the arrows move the mark, Esc closes it. The editor owns it
/// and decides when it shows.
class SuggestionPopup {
  SuggestionPopup({required this.onTake});

  /// A line was clicked.
  final void Function(Suggestion suggestion) onTake;

  OverlayEntry? _entry;
  List<Suggestion> _items = const [];
  int _selected = 0;
  Offset _at = Offset.zero;
  double _lineHeight = 20;
  void Function()? onDismissed;

  static SuggestionPopup? _open;

  bool get isOpen => _entry != null;
  List<Suggestion> get items => _items;
  int get selected => _selected;
  Suggestion? get current => _items.isEmpty ? null : _items[_selected];

  /// Closes the list that is showing, if any: Esc's first job.
  static bool dismissActive() {
    final open = _open;
    if (open == null) return false;
    open.hide();
    open.onDismissed?.call();
    return true;
  }

  /// Shows [items] under the caret whose bottom-left corner is [caret], in
  /// global coordinates, on a line [lineHeight] tall.
  void show(
    BuildContext context,
    List<Suggestion> items, {
    required Offset caret,
    required double lineHeight,
  }) {
    if (items.isEmpty) return hide();
    _items = items;
    _selected = 0;
    _at = caret;
    _lineHeight = lineHeight;
    if (_entry == null) {
      _entry = OverlayEntry(builder: _build);
      Overlay.of(context).insert(_entry!);
    } else {
      _entry!.markNeedsBuild();
    }
    _open = this;
  }

  void move(int by) {
    if (_items.isEmpty) return;
    _selected = (_selected + by) % _items.length;
    if (_selected < 0) _selected += _items.length;
    _entry?.markNeedsBuild();
  }

  void hide() {
    _entry?.remove();
    _entry = null;
    _items = const [];
    if (identical(_open, this)) _open = null;
  }

  static const _width = 440.0;
  static const _row = 34.0;

  Widget _build(BuildContext context) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final at = overlay.globalToLocal(_at);
    final size = overlay.size;
    final height = _items.length * _row + 8;
    final below = at.dy + 4;
    final top = below + height <= size.height
        ? below
        : (at.dy - _lineHeight - height - 4).clamp(0.0, size.height - height);
    final left = at.dx.clamp(
      8.0,
      (size.width - _width - 8).clamp(8.0, double.infinity),
    );
    final colors = Theme.of(context).colorScheme;
    return Positioned(
      left: left,
      top: top,
      width: _width,
      child: Material(
        key: const ValueKey('suggestion-list'),
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        color: colors.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _items.length; i++)
                _line(context, _items[i], i == _selected),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(BuildContext context, Suggestion s, bool marked) {
    final colors = Theme.of(context).colorScheme;
    final typed = s.typed.clamp(0, s.text.length);
    final style = TextStyle(
      fontFamily: 'LiberationSans',
      fontSize: 13.5,
      color: colors.onSurface,
    );
    return InkWell(
      key: ValueKey('suggestion-${s.text}'),
      onTap: () => onTake(s),
      child: Container(
        height: _row,
        color: marked ? colors.primary.withValues(alpha: .12) : null,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Icon(_icon(s.source), size: 16, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: s.snippet == null ? s.text.substring(0, typed) : '',
                      style: style.copyWith(color: colors.onSurfaceVariant),
                    ),
                    TextSpan(
                      text: s.snippet == null
                          ? s.text.substring(typed)
                          : s.text,
                      style: style.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (s.label != null) ...[
              const SizedBox(width: 8),
              Text(
                s.label!,
                style: style.copyWith(
                  fontSize: 11.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            if (marked) ...[
              const SizedBox(width: 8),
              Text(
                'Tab',
                style: style.copyWith(
                  fontSize: 11,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _icon(SuggestionSource source) => switch (source) {
    SuggestionSource.snippet => Icons.short_text,
    SuggestionSource.profile => Icons.badge_outlined,
    SuggestionSource.builtIn => Icons.gavel_outlined,
    SuggestionSource.learned => Icons.auto_awesome_outlined,
  };
}

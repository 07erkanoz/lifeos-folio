import 'package:flutter/material.dart';

/// The app's combobox, in place of Flutter's DropdownButton(FormField):
/// the field is a text field's size, its text the field's text, and the list
/// opens under it, as wide as it, a card with rounded corners, a shadow and
/// a tick at the chosen row, instead of a slab laid over the field.
///
/// It takes the dropdowns' own [DropdownMenuItem]s and their parameter
/// names, so a dropdown becomes one by its name alone. With a [decoration]
/// it is a form field; without one a bare word and a chevron, for a
/// toolbar or a line of text.
class FolioSelect<T> extends StatefulWidget {
  const FolioSelect({
    super.key,
    required this.items,
    required this.onChanged,
    this.value,
    this.initialValue,
    this.decoration,
    this.style,
    this.hint,
    this.disabledHint,
    this.selectedItemBuilder,
    this.menuMaxHeight,
    this.iconSize = 20,
    this.icon,
    this.isExpanded = true,
    this.isDense = true,
    this.underline,
    this.padding,
    this.borderRadius,
    this.dropdownColor,
    this.focusNode,
    this.autofocus = false,
    this.elevation,
    this.alignment,
    this.itemHeight,
    this.focusColor,
    this.validator,
  });

  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;

  /// The value chosen, kept by the caller ([DropdownButton]'s way).
  final T? value;

  /// The value at first, kept by the field after that
  /// ([DropdownButtonFormField]'s way).
  final T? initialValue;
  final InputDecoration? decoration;
  final TextStyle? style;
  final Widget? hint, disabledHint, icon;
  final DropdownButtonBuilder? selectedItemBuilder;
  final double? menuMaxHeight;
  final double iconSize;

  // Taken so that a dropdown's arguments carry over; the look is the app's.
  final bool isExpanded, isDense, autofocus;
  final Widget? underline;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Color? dropdownColor, focusColor;
  final FocusNode? focusNode;
  final int? elevation;
  final AlignmentGeometry? alignment;
  final double? itemHeight;
  final FormFieldValidator<T>? validator;

  @override
  State<FolioSelect<T>> createState() => _FolioSelectState<T>();
}

class _FolioSelectState<T> extends State<FolioSelect<T>> {
  final _menu = MenuController();
  final _field = GlobalKey();
  late T? _value = widget.value ?? widget.initialValue;
  double _width = 220;
  bool _open = false;
  bool _focused = false;

  @override
  void didUpdateWidget(FolioSelect<T> old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value) _value = widget.value;
  }

  List<DropdownMenuItem<T>> get _items => widget.items ?? const [];
  bool get _enabled => widget.onChanged != null && _items.isNotEmpty;

  int get _index => _items.indexWhere((i) => i.value == _value);

  void _toggle() {
    if (!_enabled) return;
    if (_menu.isOpen) {
      _menu.close();
      return;
    }
    final size = _field.currentContext?.size;
    setState(() => _width = size == null ? 220 : size.width);
    _menu.open();
  }

  void _choose(DropdownMenuItem<T> item) {
    item.onTap?.call();
    setState(() => _value = item.value);
    widget.onChanged?.call(item.value);
  }

  TextStyle _textStyle(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium!.copyWith(
      fontSize: 13.5,
      color: theme.colorScheme.onSurface,
    );
    return base.merge(widget.style);
  }

  Widget _shown(BuildContext context) {
    final i = _index;
    if (i < 0) {
      final hint = _enabled ? widget.hint : widget.disabledHint ?? widget.hint;
      return hint == null
          ? const SizedBox.shrink()
          : DefaultTextStyle.merge(
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              child: hint,
            );
    }
    final builder = widget.selectedItemBuilder;
    return builder == null ? _items[i].child : builder(context)[i];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = _textStyle(context);
    final maxHeight = widget.menuMaxHeight ?? 360;
    final width = widget.decoration == null ? null : _width;
    final chosen = _index;
    return MenuAnchor(
      controller: _menu,
      onOpen: () => setState(() => _open = true),
      onClose: () {
        if (mounted) setState(() => _open = false);
      },
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(width ?? 160, 0)),
        maximumSize: WidgetStatePropertyAll(Size(width ?? 420, maxHeight)),
      ),
      menuChildren: [
        for (final (i, item) in _items.indexed)
          MenuItemButton(
            key: item.key,
            autofocus: i == chosen,
            onPressed: item.enabled ? () => _choose(item) : null,
            style: MenuItemButton.styleFrom(
              minimumSize: const Size(0, 38),
              backgroundColor: i == chosen
                  ? scheme.primary.withValues(alpha: .07)
                  : null,
            ),
            trailingIcon: i == chosen
                ? Icon(Icons.check_rounded, size: 18, color: scheme.primary)
                : const SizedBox(width: 18),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (width ?? 420) - 64,
                minWidth: width == null ? 0 : (width - 64).clamp(0, 2000),
              ),
              child: DefaultTextStyle(
                style: text.copyWith(
                  color: !item.enabled
                      ? scheme.onSurfaceVariant
                      : i == chosen
                      ? scheme.primary
                      : null,
                  fontWeight: i == chosen ? FontWeight.w600 : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                child: item.child,
              ),
            ),
          ),
      ],
      builder: (context, _, _) {
        final chevron = AnimatedRotation(
          turns: _open ? .5 : 0,
          duration: const Duration(milliseconds: 150),
          child:
              widget.icon ??
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: widget.iconSize + 2,
                color: _enabled ? scheme.onSurfaceVariant : scheme.outline,
              ),
        );
        final shown = DefaultTextStyle(
          style: _enabled
              ? text
              : text.copyWith(color: scheme.onSurfaceVariant),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          child: _shown(context),
        );
        final decoration = widget.decoration;
        if (decoration == null) {
          // A word and a chevron, for a toolbar or a line of text.
          return InkWell(
            key: _field,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            borderRadius: BorderRadius.circular(8),
            onTap: _enabled ? _toggle : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: shown),
                  const SizedBox(width: 2),
                  chevron,
                ],
              ),
            ),
          );
        }
        final field = decoration
            .applyDefaults(theme.inputDecorationTheme)
            .copyWith(
              enabled: _enabled,
              isDense: true,
              contentPadding:
                  decoration.contentPadding ??
                  const EdgeInsets.fromLTRB(14, 13, 8, 13),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: chevron,
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 30,
                minHeight: 24,
              ),
            );
        return MouseRegion(
          cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
          child: InkWell(
            key: _field,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            canRequestFocus: _enabled,
            onFocusChange: (v) => setState(() => _focused = v),
            onTap: _enabled ? _toggle : null,
            borderRadius: BorderRadius.circular(12),
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            focusColor: Colors.transparent,
            child: InputDecorator(
              decoration: field,
              isEmpty: chosen < 0 && widget.hint == null,
              isFocused: _open || _focused,
              child: shown,
            ),
          ),
        );
      },
    );
  }
}

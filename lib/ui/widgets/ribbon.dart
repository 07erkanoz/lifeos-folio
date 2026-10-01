import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// The colours of the ribbon, after Office's: a grey band for the tabs, a
/// white strip for the tools, neutral icons and the app's own accent.
class RibbonColors {
  final Color band, strip, border, text, secondary, hover, pressed, accent;
  final Color selected;
  const RibbonColors({
    required this.band,
    required this.strip,
    required this.border,
    required this.text,
    required this.secondary,
    required this.hover,
    required this.pressed,
    required this.accent,
    required this.selected,
  });

  factory RibbonColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? RibbonColors(
            band: const Color(0xFF1F1F1F),
            strip: const Color(0xFF292929),
            border: const Color(0xFF3D3D3D),
            text: const Color(0xFFF5F5F5),
            secondary: const Color(0xFFADADAD),
            hover: const Color(0xFF383838),
            pressed: const Color(0xFF424242),
            accent: scheme.primary,
            selected: scheme.primary.withValues(alpha: .22),
          )
        : RibbonColors(
            band: const Color(0xFFF3F3F3),
            strip: Colors.white,
            border: const Color(0xFFE0E0E0),
            text: const Color(0xFF242424),
            secondary: const Color(0xFF616161),
            hover: const Color(0xFFF0F0F0),
            pressed: const Color(0xFFE0E0E0),
            accent: scheme.primary,
            selected: scheme.primary.withValues(alpha: .12),
          );
  }
}

/// Segoe UI on Windows, as Office's own chrome; elsewhere the theme's.
TextStyle ribbonText(BuildContext context, {double size = 12, Color? color}) =>
    TextStyle(
      fontFamily: Theme.of(context).platform == TargetPlatform.windows
          ? 'Segoe UI'
          : null,
      fontSize: size,
      height: 1.2,
      color: color ?? RibbonColors.of(context).text,
    );

class RibbonGroup {
  final String label;
  final List<Widget> children;

  /// The small arrow beside the group's name, as Word's: the group's
  /// dialog with every setting it has.
  final VoidCallback? onMore;
  const RibbonGroup(this.label, this.children, {this.onMore});
}

class RibbonTab {
  final String label;
  final List<RibbonGroup> groups;
  const RibbonTab(this.label, this.groups);
}

/// Office's ribbon: a row of tabs and, under it, the chosen tab's groups.
/// [leading] opens before the tabs (Dosya); [trailing] stays at the right
/// whatever the tab (Kaydet, İmzala).
class Ribbon extends StatefulWidget {
  final Widget? leading;
  final List<RibbonTab> tabs;
  final List<Widget> trailing;
  final int initialTab;
  final ValueChanged<int>? onTabChanged;
  const Ribbon({
    super.key,
    this.leading,
    required this.tabs,
    this.trailing = const [],
    this.initialTab = 0,
    this.onTabChanged,
  });

  @override
  State<Ribbon> createState() => _RibbonState();
}

class _RibbonState extends State<Ribbon> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final colors = RibbonColors.of(context);
    final tab = widget.tabs[_tab];
    return Container(
      color: colors.band,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 38,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  ?widget.leading,
                  for (var i = 0; i < widget.tabs.length; i++)
                    _TabLabel(
                      label: widget.tabs[i].label,
                      selected: i == _tab,
                      onTap: () {
                        setState(() => _tab = i);
                        widget.onTabChanged?.call(i);
                      },
                    ),
                  const Spacer(),
                  for (final action in widget.trailing)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: action,
                    ),
                ],
              ),
            ),
          ),
          Container(
            height: 106,
            margin: const EdgeInsets.fromLTRB(6, 0, 6, 6),
            decoration: BoxDecoration(
              color: colors.strip,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < tab.groups.length; i++) ...[
                    _Group(tab.groups[i]),
                    if (i < tab.groups.length - 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: VerticalDivider(
                          width: 9,
                          thickness: 1,
                          color: colors.border,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabLabel extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool accent;
  const _TabLabel({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = false,
  });

  @override
  State<_TabLabel> createState() => _TabLabelState();
}

class _TabLabelState extends State<_TabLabel> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = RibbonColors.of(context);
    final style = ribbonText(
      context,
      size: 13,
      color: widget.accent ? colors.accent : colors.text,
    ).copyWith(fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: _hover && !widget.selected
                ? colors.pressed.withValues(alpha: .5)
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Bold text is wider: the label keeps the bold width either
              // way so the row does not shift when a tab is chosen.
              Text(
                widget.label,
                style: style.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.transparent,
                ),
              ),
              Text(widget.label, style: style),
              if (widget.selected)
                Positioned(
                  bottom: 2,
                  child: Container(
                    width: 18,
                    height: 3,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Dosya" before the tabs: a tab that opens a menu rather than a strip.
class RibbonFileTab extends StatelessWidget {
  final VoidCallback onTap;
  const RibbonFileTab({super.key, required this.onTap});
  @override
  Widget build(BuildContext context) =>
      _TabLabel(label: 'Dosya', selected: false, onTap: onTap, accent: true);
}

class _Group extends StatelessWidget {
  final RibbonGroup group;
  const _Group(this.group);

  @override
  Widget build(BuildContext context) {
    final colors = RibbonColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(3, 4, 3, 0),
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: group.children,
            ),
          ),
          SizedBox(
            height: 20,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  group.label,
                  style: ribbonText(
                    context,
                    size: 11.5,
                    color: colors.secondary,
                  ),
                ),
                if (group.onMore != null) ...[
                  const SizedBox(width: 6),
                  _Hover(
                    onTap: group.onMore,
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      FluentIcons.open_12_regular,
                      size: 12,
                      color: colors.secondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The hover and press fill every ribbon control shares.
class _Hover extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final bool selected;
  final String? tooltip;
  const _Hover({
    required this.child,
    this.onTap,
    this.padding = EdgeInsets.zero,
    this.selected = false,
    this.tooltip,
  });

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _hover = false, _down = false;

  @override
  Widget build(BuildContext context) {
    final colors = RibbonColors.of(context);
    final fill = _down
        ? colors.pressed
        : widget.selected
        ? colors.selected
        : _hover
        ? colors.hover
        : null;
    Widget result = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = _down = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(4),
            border: widget.selected
                ? Border.all(color: colors.accent.withValues(alpha: .35))
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
    if (widget.tooltip != null) {
      result = Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 500),
        child: result,
      );
    }
    return result;
  }
}

/// A tool that matters on its own: a large icon over its name, which may
/// take two lines, and a chevron when it opens a list.
class RibbonLargeButton extends StatelessWidget {
  final IconData icon;

  /// The filled shape of [icon], laid under its outline in a light tint:
  /// the two tones of Office's own icons.
  final IconData? fill;
  final Color? tint;
  final String label;
  final VoidCallback? onPressed;
  final bool dropdown, selected;
  final String? tooltip;
  const RibbonLargeButton({
    super.key,
    required this.icon,
    this.fill,
    this.tint,
    required this.label,
    this.onPressed,
    this.dropdown = false,
    this.selected = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final colors = RibbonColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: _Hover(
        onTap: onPressed,
        selected: selected,
        tooltip: tooltip,
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, maxWidth: 84),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RibbonIcon(icon, fill: fill, tint: tint, size: 32),
              const SizedBox(height: 3),
              // Two lines' room whatever the name, so every button of a
              // strip stands the same height; the chevron follows the name.
              SizedBox(
                height: 35,
                child: Text.rich(
                  TextSpan(
                    text: label,
                    children: [
                      if (dropdown)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 3),
                            child: Icon(
                              FluentIcons.chevron_down_12_regular,
                              size: 10,
                              color: colors.secondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: ribbonText(context, size: 12).copyWith(height: 1.25),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An icon in Office's two tones: the outline in the text's colour over its
/// filled shape in a light tint of the accent. Without [fill], the outline
/// alone.
class RibbonIcon extends StatelessWidget {
  final IconData icon;
  final IconData? fill;

  /// The colour of the fill: what the tool is about, as Office colours its
  /// own (PDF red, Word blue). The accent when not given.
  final Color? tint;
  final double size;
  const RibbonIcon(
    this.icon, {
    super.key,
    this.fill,
    this.tint,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    final colors = RibbonColors.of(context);
    final outline = Icon(icon, size: size, color: colors.text);
    if (fill == null) return outline;
    return Stack(
      children: [
        Icon(
          fill,
          size: size,
          color: (tint ?? colors.accent).withValues(alpha: .55),
        ),
        outline,
      ],
    );
  }
}

/// The colours tools are filled with, after Office's icon palette.
abstract final class RibbonTint {
  static const blue = Color(0xFF2B7CD3);
  static const navy = Color(0xFF3D526A);
  static const green = Color(0xFF2E9E5B);
  static const red = Color(0xFFE0393E);
  static const orange = Color(0xFFF7811E);
  static const purple = Color(0xFF8764B8);
  static const teal = Color(0xFF0FA3A3);
  static const gold = Color(0xFFE8A317);
}

/// A tool named beside a small icon; three stack in a column.
class RibbonSmallButton extends StatelessWidget {
  final IconData icon;
  final IconData? fill;
  final Color? tint;
  final String label;
  final VoidCallback? onPressed;
  final bool dropdown;
  const RibbonSmallButton({
    super.key,
    required this.icon,
    this.fill,
    this.tint,
    required this.label,
    this.onPressed,
    this.dropdown = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = RibbonColors.of(context);
    return _Hover(
      onTap: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: SizedBox(
        height: 24,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RibbonIcon(icon, fill: fill, tint: tint),
            const SizedBox(width: 6),
            Text(label, style: ribbonText(context)),
            if (dropdown) ...[
              const SizedBox(width: 3),
              Icon(
                FluentIcons.chevron_down_12_regular,
                size: 10,
                color: colors.secondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// An icon alone, for formatting, whose meaning the icon carries. [bar]
/// draws the coloured line under the icon that Word's font colour and
/// highlight buttons have.
class RibbonIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected, dropdown;
  final Color? bar;
  const RibbonIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.selected = false,
    this.dropdown = false,
    this.bar,
  });

  @override
  Widget build(BuildContext context) {
    final colors = RibbonColors.of(context);
    return _Hover(
      onTap: onPressed,
      selected: selected,
      tooltip: tooltip,
      padding: EdgeInsets.fromLTRB(4, 0, dropdown ? 1 : 4, 0),
      child: SizedBox(
        height: 26,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: colors.text),
                if (bar != null)
                  Container(
                    width: 16,
                    height: 3,
                    margin: const EdgeInsets.only(top: 1),
                    color: bar,
                  ),
              ],
            ),
            if (dropdown)
              Icon(
                FluentIcons.chevron_down_12_regular,
                size: 9,
                color: colors.secondary,
              ),
          ],
        ),
      ),
    );
  }
}

/// A box that opens a list: the font, the size, the zoom.
class RibbonField extends StatelessWidget {
  final String text;
  final double width;
  final VoidCallback? onPressed;
  const RibbonField(
    this.text, {
    super.key,
    required this.width,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = RibbonColors.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: width,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.only(left: 7, right: 4),
          decoration: BoxDecoration(
            color: colors.strip,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFC7C7C7)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ribbonText(context),
                ),
              ),
              Icon(
                FluentIcons.chevron_down_12_regular,
                size: 10,
                color: colors.secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rows of controls stacked in a group: two for formatting, three for
/// small named buttons.
class RibbonStack extends StatelessWidget {
  final List<Widget> children;
  const RibbonStack(this.children, {super.key});
  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: children,
  );
}

class RibbonRow extends StatelessWidget {
  final List<Widget> children;
  const RibbonRow(this.children, {super.key});
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: children);
}

/// Word's style gallery: each paragraph style drawn as it looks.
class RibbonStyleGallery extends StatelessWidget {
  final List<(String name, TextStyle sample)> styles;
  final int selected;
  final ValueChanged<int>? onSelected;
  const RibbonStyleGallery({
    super.key,
    required this.styles,
    this.selected = 0,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = RibbonColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < styles.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: _Hover(
                onTap: () => onSelected?.call(i),
                selected: i == selected,
                child: Container(
                  width: 76,
                  height: 62,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    border: i == selected
                        ? null
                        : Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'AaBbÇç',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: styles[i].$2.copyWith(color: colors.text),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        styles[i].$1,
                        style: ribbonText(
                          context,
                          size: 11,
                          color: colors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Column(
            children: [
              for (final icon in [
                FluentIcons.chevron_up_12_regular,
                FluentIcons.chevron_down_12_regular,
                FluentIcons.more_horizontal_16_regular,
              ])
                _Hover(
                  padding: const EdgeInsets.all(3),
                  child: Icon(icon, size: 12, color: colors.secondary),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A checkbox named beside it, as Word's Görünüm › Göster.
class RibbonCheck extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const RibbonCheck(
    this.label, {
    super.key,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = RibbonColors.of(context);
    return _Hover(
      onTap: () => onChanged?.call(!value),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: SizedBox(
        height: 24,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: value ? colors.accent : null,
                borderRadius: BorderRadius.circular(3),
                border: value ? null : Border.all(color: colors.secondary),
              ),
              child: value
                  ? const Icon(
                      FluentIcons.checkmark_12_regular,
                      size: 12,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 7),
            Text(label, style: ribbonText(context)),
          ],
        ),
      ),
    );
  }
}

/// A button beside the tabs, as Word's Paylaş: [filled] for the one
/// action that matters most.
class RibbonActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  const RibbonActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = RibbonColors.of(context);
    final foreground = filled ? Colors.white : colors.text;
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      side: filled
          ? null
          : WidgetStatePropertyAll(BorderSide(color: const Color(0xFFC7C7C7))),
      backgroundColor: WidgetStatePropertyAll(
        filled ? colors.accent : colors.strip,
      ),
      foregroundColor: WidgetStatePropertyAll(foreground),
      textStyle: WidgetStatePropertyAll(
        ribbonText(
          context,
          color: foreground,
        ).copyWith(fontWeight: FontWeight.w600),
      ),
      elevation: const WidgetStatePropertyAll(0),
    );
    return TextButton.icon(
      style: style,
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

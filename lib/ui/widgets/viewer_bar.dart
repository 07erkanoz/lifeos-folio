import 'package:flutter/material.dart';

/// The row of tools every viewer has above what it shows: a PDF, a
/// picture and a scan look like parts of one program. The tools sit in the
/// middle, each kind on a pill of its own, and scroll sideways on a narrow
/// window.
class ViewerToolbar extends StatelessWidget {
  const ViewerToolbar({super.key, required this.children});

  final List<Widget> children;

  static const height = 48.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0) const SizedBox(width: 10),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

/// Buttons that belong together, on a grey pill of their own.
class ViewerPill extends StatelessWidget {
  const ViewerPill({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
  );
}

/// One tool of a viewer's toolbar; [selected] while what it turns on is on.
class ViewerButton extends StatelessWidget {
  const ViewerButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      isSelected: selected,
      icon: Icon(icon, size: 19),
      color: selected ? scheme.primary : null,
      style: selected
          ? IconButton.styleFrom(
              backgroundColor: scheme.primary.withValues(alpha: .12),
            )
          : null,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
    );
  }
}

/// What is being looked at, in a line under it: the page, its size, the
/// file's, how large it is shown. Read, not pressed.
class ViewerStatusBar extends StatelessWidget {
  const ViewerStatusBar({super.key, required this.items, this.trailing});

  /// Left to right; empty ones are left out.
  final List<String?> items;

  /// How large it is shown, at the right end.
  final String? trailing;

  static const height = 26.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 11.5,
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final shown = [
      for (final item in items)
        if (item != null && item.isNotEmpty) item,
    ];
    return Container(
      key: const ValueKey('viewer-status'),
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              shown.join('   ·   '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (trailing != null) Text(trailing!, style: style),
        ],
      ),
    );
  }
}

/// A file's size as it is read: 104 KB, 1,2 MB.
String viewerFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0).replaceFirst('.', ',')} MB';
}

/// A sheet's size in millimetres from its points, named when it is A4:
/// "A4 · 210 × 297 mm".
String viewerSheetSize(double widthPoints, double heightPoints) {
  final w = (widthPoints * 25.4 / 72).round();
  final h = (heightPoints * 25.4 / 72).round();
  final short = w < h ? w : h, long = w < h ? h : w;
  final name = (short - 210).abs() <= 1 && (long - 297).abs() <= 1
      ? 'A4 · '
      : (short - 297).abs() <= 1 && (long - 420).abs() <= 1
      ? 'A3 · '
      : (short - 148).abs() <= 1 && (long - 210).abs() <= 1
      ? 'A5 · '
      : '';
  return '$name$w × $h mm';
}

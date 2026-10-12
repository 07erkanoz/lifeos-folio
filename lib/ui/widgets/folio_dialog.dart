import 'package:flutter/material.dart';

/// A dialog in Folio's own shape: a heading with its icon and a line under
/// it, a close button in the corner, the body scrolling between them, and
/// the buttons on a quiet band at the bottom.
///
/// Material's AlertDialog is a title over text over buttons, all on one
/// white sheet; the logins and the signing, with a choice, fields and a
/// state to tell, read as a form crammed into a message box.
class FolioDialog extends StatelessWidget {
  const FolioDialog({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.accent,
    this.actions = const [],
    this.width = 480,
    this.onClose,
    this.canClose = true,
    this.progress = false,
    this.footerNote,
  });

  final String title;

  /// One line under the heading: what the dialog is for, or what it acts on.
  final String? subtitle;

  final IconData? icon;

  /// The colour of the icon's badge; the theme's blue when not given.
  final Color? accent;

  final Widget child;
  final List<Widget> actions;
  final double width;

  /// What the close button in the corner does; without it, there is none.
  final VoidCallback? onClose;

  /// False while something runs that closing would leave half done: the
  /// close button stays where it is, greyed.
  final bool canClose;

  /// A thin bar under the heading while something is under way.
  final bool progress;

  /// A small line under the body: how long a session lasts, what is not
  /// kept.
  final Widget? footerNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tint = accent ?? colors.primary;
    final phone = MediaQuery.sizeOf(context).width < 700;
    final side = phone ? 20.0 : 24.0;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(side, phone ? 6 : 20, 14, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, size: 21, color: tint),
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: theme.dialogTheme.titleTextStyle),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (onClose != null)
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: canClose ? onClose : null,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 2,
              child: progress
                  ? const LinearProgressIndicator(minHeight: 2)
                  : null,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(side, 12, side, 20),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(fontSize: 13, height: 1.45),
                  child: footerNote == null
                      ? child
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            child,
                            const SizedBox(height: 16),
                            DefaultTextStyle.merge(
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.35,
                                color: colors.onSurfaceVariant,
                              ),
                              child: footerNote!,
                            ),
                          ],
                        ),
                ),
              ),
            ),
            if (actions.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow.withValues(alpha: .6),
                  border: Border(top: BorderSide(color: colors.outlineVariant)),
                ),
                padding: EdgeInsets.fromLTRB(
                  side,
                  12,
                  side - 6,
                  phone ? 12 + MediaQuery.paddingOf(context).bottom : 12,
                ),
                // Side by side while they fit, one above the other when
                // they do not, as an AlertDialog's do.
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  overflowSpacing: 8,
                  overflowAlignment: OverflowBarAlignment.end,
                  children: actions,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One of a few ways to do the same thing, as a card that is chosen by a
/// press: its icon, its name and a line on what it needs.
class FolioChoiceCard extends StatelessWidget {
  const FolioChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;

  /// Null when it cannot be chosen now.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final tint = selected ? colors.primary : colors.onSurfaceVariant;
    return Opacity(
      opacity: enabled || selected ? 1 : .55,
      child: Material(
        color: selected
            ? colors.primaryContainer.withValues(alpha: .7)
            : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: tint),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected ? colors.primary : colors.onSurface,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.3,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum CalloutTone { info, success, warning, error }

/// A tinted note inside a dialog: what will happen, what went wrong, what
/// to look for on the phone.
class FolioCallout extends StatelessWidget {
  const FolioCallout({
    super.key,
    required this.child,
    this.icon,
    this.tone = CalloutTone.info,
    this.trailing,
  });

  final Widget child;
  final IconData? icon;
  final CalloutTone tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = switch (tone) {
      CalloutTone.info => colors.primary,
      CalloutTone.success => const Color(0xFF16A34A),
      CalloutTone.warning => const Color(0xFFD97706),
      CalloutTone.error => colors.error,
    };
    final text = switch (tone) {
      CalloutTone.info => dark ? colors.onSurface : const Color(0xFF1E3A8A),
      CalloutTone.success => dark ? colors.onSurface : const Color(0xFF14532D),
      CalloutTone.warning => dark ? colors.onSurface : const Color(0xFF78350F),
      CalloutTone.error => dark ? colors.onSurface : const Color(0xFF7F1D1D),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: dark ? .14 : .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tint.withValues(alpha: dark ? .3 : .18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              icon ??
                  switch (tone) {
                    CalloutTone.info => Icons.info_outline_rounded,
                    CalloutTone.success => Icons.check_circle_outline_rounded,
                    CalloutTone.warning => Icons.warning_amber_rounded,
                    CalloutTone.error => Icons.error_outline_rounded,
                  },
              size: 17,
              color: tint,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DefaultTextStyle.merge(
              style: TextStyle(fontSize: 12.5, height: 1.45, color: text),
              child: child,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// The small capitals over a group of fields: "İMZA YÖNTEMİ", "HESAP".
class FolioSectionLabel extends StatelessWidget {
  const FolioSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              // Dart's toUpperCase knows no Turkish: "giriş" would come out
              // "GIRIŞ".
              text.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// The state of something under way: a small spinner while it runs and
/// the words of where it is.
class FolioStatusLine extends StatelessWidget {
  const FolioStatusLine(this.text, {super.key, this.busy = false});

  final String text;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (busy) ...[
          SizedBox.square(
            dimension: 13,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 9),
        ],
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: busy ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

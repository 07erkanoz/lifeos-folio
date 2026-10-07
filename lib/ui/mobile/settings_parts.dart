import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../agenda/agenda_page.dart' show AgendaColors;

/// The pieces the phone's settings are made of (docs/design/mobil-ayarlar-
/// taslak.png): a section's heading, a white group of rows, a row with its
/// tinted icon, the UYAP card and a field with its label on its border.

/// The page's background, the agenda's.
Color settingsPage(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? Theme.of(context).colorScheme.surface
    : AgendaColors.page;

/// A page of settings: a white bar with the way back and, maybe, an action.
PreferredSizeWidget settingsBar(
  BuildContext context,
  String title, {
  Widget? action,
}) {
  final scheme = Theme.of(context).colorScheme;
  return AppBar(
    backgroundColor: scheme.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    titleSpacing: 0,
    title: Text(
      title,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    ),
    actions: [?action],
    shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
  );
}

class SettingsSection extends StatelessWidget {
  const SettingsSection(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 16, 6, 6),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: .8,
        color: AgendaColors.muted,
      ),
    ),
  );
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children, this.padding});
  final List<Widget> children;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && padding == null) {
        rows.add(Divider(height: 1, color: scheme.outlineVariant));
      }
      rows.add(children[i]);
    }
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.status,
    this.fill = AgendaColors.hearingFill,
    this.tint = AgendaColors.hearing,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// A dot before the subtitle: green for connected, grey for not.
  final Color? status;
  final Color fill, tint;

  /// A switch or a choice; a chevron when null and the row leads on.
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      if (status != null) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: status,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AgendaColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing ??
              (onTap == null
                  ? const SizedBox.shrink()
                  : const Icon(Icons.chevron_right, color: Color(0xFF9AA2B1))),
        ],
      ),
    ),
  );
}

/// A switch in a row, the app's own colour.
Widget settingsSwitch(bool value, ValueChanged<bool>? onChanged, {Key? key}) =>
    Switch.adaptive(key: key, value: value, onChanged: onChanged);

/// "UYAP Mobil ile doldur": the profile from UYAP, in the teal of the
/// cases.
class UyapFillCard extends StatelessWidget {
  const UyapFillCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.button,
    required this.onTap,
    this.busy = false,
  });

  final String title, subtitle, button;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AgendaColors.eHearingFill,
      border: Border.all(color: const Color(0xFFBFE5DE)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(Icons.gavel_rounded, color: AgendaColors.eHearingText),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AgendaColors.eHearingText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const ValueKey('uyap-fill'),
          onPressed: busy ? null : onTap,
          style: FilledButton.styleFrom(
            backgroundColor: AgendaColors.eHearing,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 38),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(fontFamily: 'LiberationSans', 
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(button),
        ),
      ],
    ),
  );
}

/// A field with its label on its border.
class ProfileField extends StatelessWidget {
  const ProfileField(
    this.controller,
    this.label, {
    super.key,
    this.digits = false,
    this.maxLength,
    this.keyboard,
    this.obscure = false,
  });

  final TextEditingController controller;
  final String label;
  final bool digits, obscure;
  final int? maxLength;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      maxLength: maxLength,
      obscureText: obscure,
      keyboardType: digits ? TextInputType.number : keyboard,
      inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        counterText: '',
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    ),
  );
}

/// Two fields side by side.
Widget fieldPair(Widget a, Widget b) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Expanded(child: a),
    const SizedBox(width: 8),
    Expanded(child: b),
  ],
);

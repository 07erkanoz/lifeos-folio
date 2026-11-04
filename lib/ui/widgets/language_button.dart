import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart' show lookupAppLocalizations;
import '../../services/platform/app_language.dart';

/// LifeOS Ofis's language menu: the system's language, or one of those
/// there are, each named in its own words.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.instance;
    final now = Localizations.localeOf(context);
    return PopupMenuButton<String>(
      key: const ValueKey('language-button'),
      tooltip: context.l.languageMenu,
      onSelected: (code) => unawaited(
        language.choose(
          code.isEmpty
              ? null
              : AppLanguage.supported.firstWhere((l) => l.languageCode == code),
        ),
      ),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: '',
          checked: language.chosen == null,
          child: Text(context.l.languageSystem),
        ),
        const PopupMenuDivider(),
        for (final l in AppLanguage.supported)
          CheckedPopupMenuItem(
            value: l.languageCode,
            checked: language.chosen?.languageCode == l.languageCode,
            child: Text(lookupAppLocalizations(l).languageName),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language_rounded, size: 18),
            const SizedBox(width: 6),
            Text(
              lookupAppLocalizations(now).languageName,
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

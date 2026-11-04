import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../l10n/gen/app_localizations.dart';
import 'app_directories.dart';
import 'app_edition.dart';

export '../../l10n/gen/app_localizations.dart' show AppLocalizations;

/// The language LifeOS Ofis speaks: the computer's or the phone's own, or
/// one the user chose in its menu. Folio speaks Turkish alone, whatever the
/// system's language: its lawyers' words are Turkish law's.
class AppLanguage extends ChangeNotifier {
  AppLanguage({this.settingsPath});

  static final instance = AppLanguage();

  final String? settingsPath;

  /// The language chosen; null to follow the system's.
  Locale? chosen;

  /// Turkish for Folio; for Ofis the one chosen, or null for the system's
  /// (resolved by [resolve]).
  Locale? get locale => AppEdition.isOfis ? chosen : turkish;

  static const turkish = Locale('tr');

  /// The languages there are, each named in its own words.
  static List<Locale> get supported => AppLocalizations.supportedLocales;

  /// The system's language if there is a translation of it; English when
  /// there is not; Turkish in Folio.
  static Locale resolve(Locale? wanted, Iterable<Locale> supported) {
    if (!AppEdition.isOfis) return turkish;
    if (wanted != null) {
      for (final l in supported) {
        if (l.languageCode == wanted.languageCode) return l;
      }
    }
    return const Locale('en');
  }

  /// The words in the language now spoken, for code with no [BuildContext]
  /// at hand (a notice, a dialog's title written before it opens).
  static AppLocalizations get t => lookupAppLocalizations(
    instance.locale ?? resolve(PlatformDispatcher.instance.locale, supported),
  );

  Future<String> _file() async =>
      settingsPath ??
      p.join((await folioSupportDirectory()).path, 'language.json');

  Future<void> load() async {
    try {
      final file = File(await _file());
      if (!await file.exists()) return;
      final code = (jsonDecode(await file.readAsString()) as Map)['language'];
      chosen = code is String && code.isNotEmpty
          ? supported.where((l) => l.languageCode == code).firstOrNull
          : null;
      notifyListeners();
    } catch (_) {
      // A missing or damaged choice is the system's language.
    }
  }

  /// [locale] chosen, or the system's language with null; kept for the
  /// next start.
  Future<void> choose(Locale? locale) async {
    chosen = locale;
    notifyListeners();
    try {
      final file = File(await _file());
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'language': locale?.languageCode ?? ''}),
      );
    } catch (_) {}
  }
}

/// `context.l.ofisOpen`: the words of the language spoken where [this] is;
/// Turkish in a tree with no translations of its own (a test, Folio's
/// older windows).
extension AppWords on BuildContext {
  AppLocalizations get l =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      AppLanguage.t;
}

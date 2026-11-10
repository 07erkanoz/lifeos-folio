import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/editor/spell_check.dart';
import 'package:evrak_convert/services/platform/app_edition.dart';
import 'package:evrak_convert/services/platform/app_language.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// LifeOS Ofis speaks the system's language, or the one chosen; English
// where there is no translation of the system's; Folio Turkish alone.
void main() {
  tearDown(() => AppEdition.current = AppEdition.folio);

  test('Folio is Turkish whatever the system speaks', () {
    AppEdition.current = AppEdition.folio;
    expect(
      AppLanguage.resolve(const Locale('en', 'US'), AppLanguage.supported),
      const Locale('tr'),
    );
    expect(AppLanguage(settingsPath: '/x').locale, const Locale('tr'));
  });

  test('Ofis follows the system, English where it has no translation', () {
    AppEdition.current = AppEdition.ofis;
    final supported = AppLanguage.supported;
    expect(
      AppLanguage.resolve(const Locale('tr', 'TR'), supported).languageCode,
      'tr',
    );
    expect(
      AppLanguage.resolve(const Locale('en', 'GB'), supported).languageCode,
      'en',
    );
    expect(
      AppLanguage.resolve(const Locale('ja'), supported).languageCode,
      'en',
    );
    expect(AppLanguage.resolve(null, supported).languageCode, 'en');
  });

  test('a language chosen in Ofis is kept for the next start', () async {
    AppEdition.current = AppEdition.ofis;
    final dir = await Directory.systemTemp.createTemp('dil-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/language.json';
    await AppLanguage(settingsPath: path).choose(const Locale('en'));
    final again = AppLanguage(settingsPath: path);
    await again.load();
    expect(again.locale?.languageCode, 'en');
    await again.choose(null);
    final system = AppLanguage(settingsPath: path)..chosen = const Locale('tr');
    await system.load();
    expect(system.chosen, isNull);
  });

  test('every language has every word the Turkish file has', () {
    final words = <String, Set<String>>{};
    for (final f in Directory('lib/l10n').listSync()) {
      if (!f.path.endsWith('.arb')) continue;
      final keys = {
        for (final k
            in (jsonDecode(File(f.path).readAsStringSync()) as Map).keys)
          if (!'$k'.startsWith('@')) '$k',
      };
      words[f.path.split('/').last] = keys;
    }
    final turkish = words.remove('app_tr.arb')!;
    for (final MapEntry(:key, :value) in words.entries) {
      expect(turkish.difference(value), isEmpty, reason: key);
    }
  });
  test('spelling is checked in Ofis\'s language, in Turkish in Folio', () {
    addTearDown(() {
      AppEdition.current = AppEdition.folio;
      AppLanguage.instance.chosen = null;
    });
    AppEdition.current = AppEdition.folio;
    AppLanguage.instance.chosen = const Locale('en');
    expect(SpellCheck.language, 'tr-TR');
    AppEdition.current = AppEdition.ofis;
    expect(SpellCheck.language, 'en-US');
    AppLanguage.instance.chosen = const Locale('tr');
    expect(SpellCheck.language, 'tr-TR');
    expect(SpellCheck.tagOf('de'), 'de-DE');
    expect(SpellCheck.tagOf('uk'), 'uk-UA');
  });
}

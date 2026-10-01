import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/legal/legal_settings.dart';

Future<void> withTempDirectory(Future<void> Function(Directory) body) async {
  final dir = await Directory.systemTemp.createTemp('folio_hukuk_');
  try {
    await body(dir);
  } finally {
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

void main() {
  test('both aids are on until the reader says otherwise', () async {
    await withTempDirectory((dir) async {
      final settings = LegalSettings(directory: dir);
      await settings.load();
      expect(settings.articles, isTrue);
      expect(settings.dictionary, isTrue);
    });
  });

  test('turning one off is remembered, and leaves the other alone', () async {
    await withTempDirectory((dir) async {
      final settings = LegalSettings(directory: dir);
      await settings.load();
      await settings.setArticles(false);

      final later = LegalSettings(directory: dir);
      await later.load();
      expect(later.articles, isFalse);
      expect(later.dictionary, isTrue);
    });
  });

  test('listeners hear about a change', () async {
    await withTempDirectory((dir) async {
      final settings = LegalSettings(directory: dir);
      await settings.load();
      var heard = 0;
      settings.addListener(() => heard++);
      await settings.setDictionary(false);
      expect(heard, 1);
      // Setting it to what it already is says nothing.
      await settings.setDictionary(false);
      expect(heard, 1);
    });
  });

  test(
    'a damaged file falls back to the defaults rather than throwing',
    () async {
      await withTempDirectory((dir) async {
        await File('${dir.path}/hukuk.json').writeAsString('{ yarim');
        final settings = LegalSettings(directory: dir);
        await settings.load();
        expect(settings.articles, isTrue);
        expect(settings.dictionary, isTrue);
        expect(settings.isLoaded, isTrue);
      });
    },
  );

  test('a file written by an older version keeps what it says', () async {
    await withTempDirectory((dir) async {
      await File('${dir.path}/hukuk.json')
          .writeAsString(jsonEncode({'sozluk': false}));
      final settings = LegalSettings(directory: dir);
      await settings.load();
      expect(settings.dictionary, isFalse);
      // Adı geçmeyen ayar açık kalır.
      expect(settings.articles, isTrue);
    });
  });
}

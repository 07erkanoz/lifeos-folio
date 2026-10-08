import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'many large records are read apart, and again only when changed',
    () async {
      final dir = Directory.systemTemp.createTempSync('folio-cases-read-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = UyapCaseStore(
        directory: dir,
        settings: UyapSettings(directory: dir, home: dir.path),
      );
      final folder = Directory('${dir.path}/uyap/dosyalar')
        ..createSync(recursive: true);
      // Over the half megabyte read apart: the documents' lists.
      for (var i = 0; i < 4; i++) {
        File('${folder.path}/k$i.json').writeAsStringSync(
          jsonEncode({
            'mahkeme': 'Antalya $i. Asliye Hukuk Mahkemesi',
            'esas': '2026/$i',
            'cekildi': DateTime(2026, 10, 1 + i).toIso8601String(),
            'evraklar': [
              for (var d = 0; d < 4000; d++)
                {'anahtar': 'e$i-$d', 'tur': 'Dilekçe', 'ad': 'Evrak $d' * 3},
            ],
          }),
        );
      }
      final first = await store.cases(counted: false);
      expect(first.map((c) => c.$1.number), [
        '2026/3',
        '2026/2',
        '2026/1',
        '2026/0',
      ]);
      // Unchanged: the same records, not read again.
      final again = await store.cases(counted: false);
      expect(identical(again.first.$1, first.first.$1), isTrue);
    },
  );
}

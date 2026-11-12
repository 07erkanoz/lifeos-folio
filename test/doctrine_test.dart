import 'dart:convert';

import 'package:evrak_convert/services/legal/doctrine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final hit = {
    '_id': '248765',
    '_source': {
      'id': 248765,
      'abstracts': [
        {'language': 'ENG', 'title': 'Rent', 'abstract': 'x'},
        {
          'language': 'TUR',
          'title': 'KİRA TESPİT DAVASI VE ESASLARI',
          'abstract': 'Kira tespit davasında hakkaniyet…',
          'keywords': 'kira, tespit',
        },
      ],
      'authors': [
        {'name': 'Gizem KILIÇ ÖZTÜRK'},
        {'name': 'Gizem KILIÇ ÖZTÜRK'},
      ],
      'journal': {'name': 'Türkiye Barolar Birliği Dergisi'},
      'issue': {'year': 2017, 'volume': '30', 'number': '132'},
      'publicationYear': 2017,
      'startPage': '229',
      'endPage': '260',
      'pdf': 'abc',
    },
  };

  test('a hit as the tool gives it: Turkish abstract, author once, pages', () {
    final p = Doctrine.publication(hit);
    expect(p['kimlik'], 'doktrin:248765');
    expect(p['baslik'], 'KİRA TESPİT DAVASI VE ESASLARI');
    expect(p['yazarlar'], ['Gizem KILIÇ ÖZTÜRK']);
    expect(p['sayfa'], '229-260');
    expect(p['dergi'], 'Türkiye Barolar Birliği Dergisi');
  });

  test(
    'the full text through TR Dizin\'s viewer, from its own hosts only',
    () async {
      final asked = <String>[];
      final d = Doctrine(
        getJson: (u) async {
          asked.add(u.toString());
          if (u.path.contains('publicationById')) {
            return {
              'hits': {
                'hits': [hit],
              },
            };
          }
          return 'https://pdf.trdizin.gov.tr/pdf/ANAHTAR';
        },
        getBytes: (u) async => u.host == 'pdf.trdizin.gov.tr'
            ? utf8.encode('"https://download.trdizin.gov.tr/yayin.pdf"')
            : utf8.encode('%PDF-1.4 ...'),
        pdfText: (path) async => 'Kira tespit davası metni.',
      );
      final got = await d.read('doktrin:248765');
      expect(got['metin_durumu'], 'tam_metin');
      expect(got['metin'], 'Kira tespit davası metni.');
      expect(got.containsKey('pdf'), isFalse);

      final elsewhere = Doctrine(
        getJson: (u) async => u.path.contains('publicationById')
            ? {
                'hits': {
                  'hits': [hit],
                },
              }
            : 'https://kotu.example.com/pdf/X',
        getBytes: (u) async => const [],
      );
      expect((await elsewhere.read('248765'))['metin_durumu'], 'pdf_alinamadi');
    },
  );

  test('a number only', () async {
    expect((await Doctrine().read('../etc'))['durum'], 'yok');
    expect((await Doctrine().search('a'))['durum'], 'yok');
  });
}

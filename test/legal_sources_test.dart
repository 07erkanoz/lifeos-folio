import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/legal/bedesten_legislation.dart';
import 'package:evrak_convert/services/legal/case_law.dart';
import 'package:evrak_convert/services/legal/citation.dart';
import 'package:evrak_convert/services/legal/constitutional_court.dart';
import 'package:evrak_convert/services/legal/decision.dart';
import 'package:evrak_convert/services/legal/legislation.dart';
import 'package:evrak_convert/services/legal/rich_text.dart';
import 'package:evrak_convert/services/legal/uyap_emsal.dart';
import 'package:evrak_convert/ui/widgets/citation_preview.dart';

Future<void> withTempDirectory(Future<void> Function(Directory) body) async {
  final dir = await Directory.systemTemp.createTemp('folio_kaynak_');
  try {
    await body(dir);
  } finally {
    // A law is kept on disk without being waited for. On Windows a folder
    // still being written to cannot be deleted, and under a full test run
    // the write can still be under way here, so it is given time to land.
    for (var attempt = 0; ; attempt++) {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
        break;
      } on FileSystemException {
        if (attempt >= 60) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }
}

final _courts = DecisionScanner.parse(
  File('assets/mevzuat/courts.json').readAsStringSync(),
);
final _laws = CitationScanner.parse(
  File('assets/mevzuat/laws.json').readAsStringSync(),
);

DecisionCitation _cited(String text) => _courts.scan(text).single;
Citation _article(String text) => _laws.scan(text).single;

const _quick = Duration(milliseconds: 1);

// -- the Constitutional Court's bank, as measured on 26 September 2026 --------

String _aymNorm({bool withText = false}) => jsonEncode({
  'total': 1,
  'page': 1,
  'data': [
    {
      'kararTipi': 'NormDenetimi',
      'id': '898f5dfa-2e21-9289-2787-c095e63ea525',
      'kararNo': '2022/3',
      'esasNo': '2020/95',
      'kararTarihi': '2022-01-26',
      'resmiGazeteTarihi': '2022-04-01',
      'resmiGazeteSayisi': 31796,
      'kararTuruDosyaSonucuLabel': 'Esas - Ret',
      'kararKonusu': '<p>3194 sayılı İmar Kanunu</p>',
      if (withText)
        'icerik':
            '<style>p.MsoNormal{font-size:12pt}</style><div class="WordSection1">'
            '<p align="center"><b>ANAYASA MAHKEMESİ KARARI</b></p>'
            '<p><b>Esas Sayısı : 2020/95</b></p>'
            '<p align="justify">İTİRAZ YOLUNA BAŞVURAN: İzmir 2. İdare Mahkemesi</p>'
            '</div>',
    },
  ],
  'page_size': 5,
});

String _aymIndividual({bool withText = false}) => jsonEncode({
  'total': 1,
  'data': [
    {
      'kararTipi': 'BireyselBasvuru',
      'id': 'b908224f-c4df-fbfd-425f-f013de228d84',
      'basvuruNo': '2019/19126',
      'kararTarihi': '2025-01-23',
      'basvuruAdi': 'HASAN DURMUŞ',
      'kararTuruBasvuruSonucuLabel': 'Esas (İhlal)',
      'kararVerenBirimLabel': 'Genel Kurul',
      'resmiGazeteTarihi': '2025-05-21',
      'resmiGazeteSayisi': 32906,
      if (withText) 'icerik': '<p align="center"><b>GENEL KURUL</b></p>',
    },
  ],
});

void main() {
  group('the Constitutional Court’s bank', () {
    test('a review of a law is asked by its numbers, exactly', () async {
      final asked = <Map>[];
      final court = ConstitutionalCourt(
        send: (kind, body) async {
          asked.add(jsonDecode(body) as Map);
          expect(kind, ConstitutionalKind.norm);
          return _aymNorm();
        },
      );
      final found = await court.find(esas: '2020/95', karar: '2022/3');
      expect(asked.single, {
        'kararTipi': 'NormDenetimi',
        'esasNo': '2020/95',
        'kararNo': '2022/3',
        'page': 1,
        'size': 5,
      });
      final one = found.single;
      expect(one.reference, 'AYM, E.2020/95, K.2022/3, 26/1/2022');
      expect(one.gazetteDate, '1/4/2022');
      expect(one.outcome, 'Esas - Ret');
      expect(one.subject, '3194 sayılı İmar Kanunu');
      // Tarayıcıda doğrulandı: bu adres kararı AYM'nin sitesinde açıyor.
      expect(
        one.url,
        'https://normkararlarbilgibankasi.anayasa.gov.tr/kbb/pages/search/'
        'NormDenetimi?id=a2JiOjg5OGY1ZGZhLTJlMjEtOTI4OS0yNzg3LWMwOTVlNjNlYTUyNQ'
        '&type=NormDenetimi',
      );
    });

    test('an individual application is asked by its number', () async {
      final court = ConstitutionalCourt(
        send: (kind, body) async {
          expect(kind, ConstitutionalKind.individual);
          expect((jsonDecode(body) as Map)['basvuruNo'], '2019/19126');
          return _aymIndividual();
        },
      );
      final one = (await court.find(application: '2019/19126')).single;
      expect(one.applicant, 'Hasan Durmuş');
      expect(
        one.reference,
        'AYM, Hasan Durmuş [GK], B. No: 2019/19126, 23/1/2025',
      );
    });

    test('names and dates are written the Court’s way', () {
      expect(courtDate('2022-01-26'), '26/1/2022');
      expect(
        titleCaseTr('ADEM KARAKOÇ VE DİĞERLERİ'),
        'Adem Karakoç ve Diğerleri',
      );
      expect(titleCaseTr('İSMAİL IŞIK'), 'İsmail Işık');
    });
  });

  group('asking the right bank', () {
    test(
      'a Constitutional Court citation is never asked of Bedesten',
      () async {
        await withTempDirectory((dir) async {
          final bank = CaseLaw(
            cache: dir,
            between: _quick,
            send: (path, body) async => fail('Bedesten sorulmamalı: $path'),
            constitutional: ConstitutionalCourt(
              send: (kind, body) async {
                final asked = jsonDecode(body) as Map;
                return asked.containsKey('id')
                    ? _aymNorm(withText: true)
                    : _aymNorm();
              },
            ),
          );
          final got = await bank.lookup(
            _cited(
              "Anayasa Mahkemesi'nin 2020/95 Esas, 2022/3 Karar sayılı kararı",
            ),
          );
          expect(got.outcome, LookupOutcome.found);
          final decision = got.decision!;
          expect(decision.source, DecisionSource.constitutional);
          expect(decision.reference, 'AYM, E.2020/95, K.2022/3, 26/1/2022');
          expect(
            decision.details,
            contains(('Resmî Gazete', '1/4/2022 – 31796')),
          );
          expect(
            decision.paragraphs.first,
            const RichParagraph([
              RichRun('ANAYASA MAHKEMESİ KARARI', bold: true),
            ], alignment: DocAlignment.center),
          );
          expect(
            plainTextOfParagraphs(decision.paragraphs),
            isNot(contains('font-size')),
          );
        });
      },
    );

    test(
      'an individual application is found and titled by its number',
      () async {
        await withTempDirectory((dir) async {
          final bank = CaseLaw(
            cache: dir,
            between: _quick,
            constitutional: ConstitutionalCourt(
              send: (kind, body) async => _aymIndividual(withText: true),
            ),
          );
          final got = await bank.lookup(
            _cited('AYM, Hasan Durmuş [GK], B. No: 2019/19126, 23/1/2025'),
          );
          expect(
            got.decision?.title,
            'Anayasa Mahkemesi Genel Kurul B. No: 2019/19126 23/1/2025',
          );
          expect(got.decision?.isApplication, isTrue);
        });
      },
    );

    test('a regional court is asked of UYAP Emsal when Bedesten has none', () async {
      await withTempDirectory((dir) async {
        final emsalAsked = <String>[];
        final bank = CaseLaw(
          cache: dir,
          between: _quick,
          send: (path, body) async =>
              '{"data":{"total":0,"emsalKararList":[]}}',
          emsal: UyapEmsal(
            send: (path, body) async {
              emsalAsked.add(path);
              if (path.startsWith('/aramadetaylist')) {
                final data = (jsonDecode(body!) as Map)['data'] as Map;
                expect(
                  [
                    data['esasYil'],
                    data['esasIlkSiraNo'],
                    data['esasSonSiraNo'],
                  ],
                  ['2021', '2817', '2817'],
                );
                return jsonEncode({
                  'data': {
                    'data': [
                      {
                        'id': '777',
                        'daire':
                            'İstanbul Bölge Adliye Mahkemesi 22. Hukuk Dairesi',
                        'esasNo': '2021/2817',
                        'kararNo': '2023/1950',
                        'kararTarihi': '12.03.2024',
                        'durum': 'KESİNLEŞTİ',
                      },
                    ],
                    'recordsTotal': 1,
                  },
                });
              }
              return jsonEncode({
                'data': '<html><body><p>T.C.<br>İSTANBUL<br>BÖLGE ADLİYE MAHKEMESİ</p></body></html>',
              });
            },
          ),
        );
        final got = await bank.lookup(
          _cited(
            'İstanbul Bölge Adliye Mahkemesi 22. Hukuk Dairesi 2021/2817 E. 2023/1950 K.',
          ),
        );
        expect(emsalAsked, ['/aramadetaylist', '/getDokuman?id=777']);
        expect(got.outcome, LookupOutcome.found);
        expect(got.decision!.source, DecisionSource.uyapEmsal);
        expect(got.decision!.details, contains(('Durum', 'Kesinleşti')));
        expect(got.chamberDiffers, isFalse);
      });
    });

    test(
      'the Court of Cassation is not asked of UYAP Emsal, which has none',
      () async {
        await withTempDirectory((dir) async {
          final bank = CaseLaw(
            cache: dir,
            between: _quick,
            send: (path, body) async =>
                '{"data":{"total":0,"emsalKararList":[]}}',
            emsal: UyapEmsal(
              send: (path, body) async => fail('Emsal sorulmamalı'),
            ),
          );
          final got = await bank.lookup(
            _cited('Yargıtay 15. Hukuk Dairesi, 2016/1531 E., 2017/3344 K.'),
          );
          expect(got.outcome, LookupOutcome.absent);
        });
      },
    );

    test(
      'a bank that cannot be reached is not remembered as "not there"',
      () async {
        await withTempDirectory((dir) async {
          var tries = 0;
          final bank = CaseLaw(
            cache: dir,
            between: _quick,
            send: (path, body) async {
              tries++;
              throw const SocketException('ağ yok');
            },
          );
          final citation = _cited(
            'Yargıtay 15. Hukuk Dairesi, 2016/1531 E., 2017/3344 K.',
          );
          expect(
            (await bank.lookup(citation)).outcome,
            LookupOutcome.unreachable,
          );
          expect(
            (await bank.lookup(citation)).outcome,
            LookupOutcome.unreachable,
          );
          expect(tries, 2, reason: 'bakılamadı önbelleğe yazılmamalı');
        });
      },
    );

    test('an old "not there", written before other banks were asked, is not believed', () async {
      await withTempDirectory((dir) async {
        await File('${dir.path}/2016-1531_2017-3344.json').writeAsString(
          jsonEncode({
            'daire': '15. Hukuk Dairesi',
            'alindi': DateTime.now().toUtc().toIso8601String(),
            'metin': '',
          }),
        );
        var searches = 0;
        final bank = CaseLaw(
          cache: dir,
          between: _quick,
          send: (path, body) async {
            if (path.contains('search')) searches++;
            return '{"data":{"total":0,"emsalKararList":[]}}';
          },
        );
        await bank.lookup(
          _cited('Yargıtay 15. Hukuk Dairesi, 2016/1531 E., 2017/3344 K.'),
        );
        expect(searches, 1);
      });
    });

    test('a decision filed under another chamber is said to be one', () async {
      // Canlı ölçüm: "Yargıtay 9. HD 2019/5535 E. 2021/3365 K." bankada
      // Danıştay 9. Daire kararı çıkıyor.
      await withTempDirectory((dir) async {
        final bank = CaseLaw(
          cache: dir,
          between: _quick,
          send: (path, body) async {
            if (path.contains('search')) {
              return jsonEncode({
                'data': {
                  'total': 1,
                  'emsalKararList': [
                    {
                      'documentId': '670979800',
                      'birimAdi': '9. Daire',
                      'itemType': {'name': 'DANISTAYKARAR'},
                      'esasNo': '2019/5535',
                      'kararNo': '2021/3365',
                      'kararTarihiStr': '27.05.2021',
                    },
                  ],
                },
              });
            }
            return jsonEncode({
              'data': {
                'content': base64.encode(
                  utf8.encode('<p>Danıştay 9. Daire</p>'),
                ),
              },
            });
          },
        );
        final got = await bank.lookup(
          _cited('Yargıtay 9. Hukuk Dairesi 2019/5535 E. 2021/3365 K.'),
        );
        expect(got.outcome, LookupOutcome.found);
        expect(got.chamberDiffers, isTrue);
        expect(
          got.decision!.reference,
          'Danıştay 9. Daire, 2019/5535 E., 2021/3365 K., 27.05.2021 T.',
        );
        expect(
          got.decision!.url,
          'https://mevzuat.adalet.gov.tr/ictihat/670979800',
        );
      });
    });

    test(
      'a General Assembly esas is asked without its chamber, and shown with it',
      () async {
        await withTempDirectory((dir) async {
          final bank = CaseLaw(
            cache: dir,
            between: _quick,
            send: (path, body) async {
              if (path.contains('search')) {
                final data = (jsonDecode(body!) as Map)['data'] as Map;
                expect([data['esasNoYil'], data['esasNoSira']], [2011, 695]);
                return jsonEncode({
                  'data': {
                    'total': 1,
                    'emsalKararList': [
                      {
                        'documentId': '77291600',
                        'birimAdi': 'Hukuk Genel Kurulu',
                        'esasNo': '2011/695',
                        'kararNo': '2011/673',
                        'kararTarihiStr': '02.11.2011',
                      },
                    ],
                  },
                });
              }
              return jsonEncode({
                'data': {
                  'content': base64.encode(
                    utf8.encode(
                      '<p><b>Hukuk Genel Kurulu 2011/7-695 E. , 2011/673 K.</b></p><p>metin</p>',
                    ),
                  ),
                },
              });
            },
          );
          final got = await bank.lookup(
            _cited('Yargıtay HGK’nın 2011/7-695 Esas ve 2011/673 karar sayılı'),
          );
          expect(got.decision!.esas, '2011/7-695');
          expect(
            got.decision!.reference,
            'Yargıtay Hukuk Genel Kurulu, 2011/7-695 E., 2011/673 K., 02.11.2011 T.',
          );
        });
      },
    );

    test('whether two benches are one', () {
      expect(
        CaseLaw.sameBench('Yargıtay 3. Hukuk Dairesi', '3. HUKUK DAİRESİ'),
        isTrue,
      );
      expect(
        CaseLaw.sameBench('3. Hukuk Dairesi', '13. Hukuk Dairesi'),
        isFalse,
      );
      expect(CaseLaw.sameBench('Danıştay 4. Daire', '4. Daire'), isTrue);
      expect(
        CaseLaw.sameBench(
          'Bölge Adliye Mahkemesi 22. Hukuk Dairesi',
          'İstanbul Bölge Adliye Mahkemesi 22. Hukuk Dairesi',
        ),
        isTrue,
      );
    });
  });

  group('an article from the legislation bank', () {
    // Ölçülen biçim: TBK m.96'nın düğümü m.97'nin başlıklarıyla biter; m.97
    // de m.98'in başlığıyla.
    const page96 =
        '<p style="text-align:justify"><b>MADDE 96- </b>Borçlu, edimini …</p>'
        '<h2><span>VI. Karşılıklı borç yükleyen sözleşmelerde</span></h2>'
        '<h2><span>1. İfada sıra</span></h2>';
    const page97 =
        '<p style="text-align:justify"><b>MADDE 97- </b>Karşılıklı borç '
        'yükleyen<b> </b>bir sözleşmenin ifası …</p>'
        '<h2><span>2. İfa güçsüzlüğü</span></h2>';
    // İİK'da 68/a ayrı düğüm değil, 68'in içinde.
    const page68 =
        '<p><b>Madde 68 – (Değişik: 18/2/1965-538/38 md.)</b></p><p>Talebine …</p>'
        '<p><b>İtirazın muvakkaten kaldırılması:</b></p>'
        '<p><b>Madde 68/a – (Ek: 18/2/1965-538/39 md.)</b></p><p>Takibin dayandığı senet …</p>'
        '<p><b>Madde 68/b – (Ek: 9/11/1988-3494/4 md.)</b></p><p>Borçlu cari hesap …</p>';
    // HMK: kenar başlığı maddenin kendi düğümünde, açılıştan hemen önce.
    const page1 =
        '<p><b><span>Görevin belirlenmesi ve niteliği</span></b></p>'
        '<p><b><span>MADDE 1- </span></b><span>(1) Mahkemelerin görevi …</span></p>';
    // Bedesten'in 26 Eylül 2026'da verdiği biçim: m.106'nın düğümü m.107'nin
    // başlığıyla biter, başlığın yanında kalın olmayan bir dipnot işaretiyle.
    const page106 =
        '<p><b><span>Tespit davası</span></b></p>'
        '<p><b><span>MADDE 106-</span></b><span> (1) Tespit davası yoluyla, '
        'mahkemeden, bir hakkın varlığının belirlenmesi talep edilir.</span></p>'
        '<p><b><span>Belirsiz alacak davası</span></b><a href="#_ftn9" '
        'name="_ftnref9"><sup><span>[9]</span></sup></a></p>';
    const page107 =
        '<p><b><span>MADDE 107– (Mülga:16/7/2026-7589/19 md.)</span></b>'
        '<span> </span></p>';

    Future<String> bank(String path, String body) async {
      final data = (jsonDecode(body) as Map)['data'] as Map;
      Map<String, Object?> ok(Object? payload) => {
        'data': payload,
        'metadata': {'FMTY': 'SUCCESS'},
      };
      switch (path) {
        case '/mevzuat/searchDocuments':
          final number = data['mevzuatNo'];
          return jsonEncode(
            ok({
              'mevzuatList': [
                // A repealed record of the same number, as 2004 has.
                {
                  'mevzuatId': 'eski$number',
                  'mevzuatNo': int.parse('$number'),
                  'mevzuatAdi': 'YÜRÜRLÜKTEN KALDIRILMIŞ HÜKÜMLER',
                  'mevzuatTur': {'name': 'MULGA'},
                  'mevzuatTertip': 3,
                },
                {
                  'mevzuatId': 'id$number',
                  'mevzuatNo': int.parse('$number'),
                  'mevzuatAdi': 'KANUN $number',
                  'mevzuatTur': {'name': 'KANUN'},
                  'mevzuatTertip': 5,
                  'url':
                      'https://www.mevzuat.gov.tr/mevzuat?MevzuatNo=$number&MevzuatTur=1&MevzuatTertip=5',
                },
              ],
            }),
          );
        case '/mevzuat/mevzuatMaddeTree':
          expect(
            data['mevzuatId'],
            startsWith('id'),
            reason: 'yürürlükteki kanun seçilmeli',
          );
          return jsonEncode(
            ok({
              'children': [
                {
                  'maddeId': 'm1',
                  'maddeNo': '1',
                  'maddeBaslik':
                      'Madde No: 1 - Görevin belirlenmesi ve niteliği',
                },
                {
                  'maddeId': 'm68',
                  'maddeNo': '68',
                  'maddeBaslik': 'Madde No: 68',
                },
                {
                  'maddeId': 'm96',
                  'maddeNo': '96',
                  'maddeBaslik': 'Madde No: 96',
                },
                {
                  'maddeId': 'm97',
                  'maddeNo': '97',
                  'maddeBaslik': 'Madde No: 97',
                },
                {
                  'maddeId': 'm106',
                  'maddeNo': '106',
                  'maddeBaslik': 'Madde No: 106 - Tespit davası',
                },
                {
                  'maddeId': 'm107',
                  'maddeNo': '107',
                  'maddeBaslik': 'Madde No: 107',
                },
              ],
            }),
          );
        case '/mevzuat/getDocumentContent':
          final page = switch (data['id']) {
            'm1' => page1,
            'm68' => page68,
            'm96' => page96,
            'm97' => page97,
            'm106' => page106,
            'm107' => page107,
            _ => '',
          };
          return jsonEncode(ok({'content': base64.encode(utf8.encode(page))}));
      }
      fail('beklenmeyen istek: $path');
    }

    Legislation legislation(Directory dir) => Legislation(
      cache: dir,
      bedesten: BedestenLegislation(send: bank, between: _quick),
    );

    test('its headings come from the foot of the article before', () async {
      await withTempDirectory((dir) async {
        final got = await legislation(dir)
            .lookup(_article("TBK'nın 97. maddesi"));
        final article = got.article!;
        expect(article.source, ArticleSource.bedesten);
        expect(article.headings, [
          'VI. Karşılıklı borç yükleyen sözleşmelerde',
          '1. İfada sıra',
        ]);
        expect(
          plainTextOfParagraphs(article.body),
          isNot(contains('İfa güçsüzlüğü')),
        );
        final opening = article.body.first.runs.first;
        expect([opening.text.trim(), opening.bold], ['MADDE 97-', true]);
      });
    });

    test('a kept copy older than a week still answers offline', () async {
      await withTempDirectory((dir) async {
        // Fetched once, and kept.
        final first = legislation(dir);
        expect(
          (await first.lookup(_article("TBK'nın 97. maddesi"))).article,
          isNotNull,
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final kept = File('${dir.path}/bedesten/6098.json');
        expect(kept.existsSync(), isTrue);
        // Ten days later, with no network.
        final json =
            jsonDecode(kept.readAsStringSync()) as Map<String, Object?>;
        json['alindi'] = DateTime.now()
            .subtract(const Duration(days: 10))
            .toUtc()
            .toIso8601String();
        kept.writeAsStringSync(jsonEncode(json));
        final offline = Legislation(
          cache: dir,
          download: (law) async => throw const SocketException('ağ yok'),
          bedesten: BedestenLegislation(
            send: (path, body) async => throw const SocketException('ağ yok'),
            between: _quick,
          ),
        );
        final got = await offline.lookup(_article("TBK'nın 97. maddesi"));
        expect(got.article?.source, ArticleSource.bedesten);
        expect(got.article?.number, 97);
      });
    });

    test('a lettered article is cut out of the article it follows', () async {
      await withTempDirectory((dir) async {
        final laws = legislation(dir);
        final lettered = (await laws.lookup(_article('İİK 68/a'))).article!;
        expect(lettered.body.first.text, startsWith('Madde 68/a'));
        expect(plainTextOfParagraphs(lettered.body), isNot(contains('68/b')));
        expect(lettered.headings, ['İtirazın muvakkaten kaldırılması:']);
        final plain = (await laws.lookup(_article('İİK m. 68'))).article!;
        expect(plain.body.first.text, startsWith('Madde 68 –'));
        expect(plainTextOfParagraphs(plain.body), isNot(contains('68/a')));
      });
    });

    test('a side heading in the article’s own page is its heading', () async {
      await withTempDirectory((dir) async {
        final article = (await legislation(dir).lookup(_article('HMK m. 1')))
            .article!;
        expect(article.headings, ['Görevin belirlenmesi ve niteliği']);
        expect(article.url, contains('MevzuatNo=6100'));
      });
    });

    test('an article repealed whole is said to be, with its heading and '
        'what repealed it', () async {
      await withTempDirectory((dir) async {
        final citation = _article('HMK m. 107');
        final lookup = await legislation(dir).lookup(citation);
        final article = lookup.article!;
        expect(article.repealed, isTrue);
        // Filed at the foot of 106, beside a footnote's plain mark.
        expect(article.headings, ['Belirsiz alacak davası']);
        expect(
          article.repealNotice,
          'Bu madde, 16/7/2026 tarihli ve 7589 sayılı Kanunun 19. maddesiyle '
          'yürürlükten kaldırılmıştır. Resmî güncel metinde maddenin yerinde '
          'yalnızca bu kayıt bulunur; kaldırılmadan önceki metni yer almaz.',
        );
        final preview = articlePreview(citation, lookup);
        expect(preview.title, endsWith('(MÜLGA)'));
        expect(preview.headings, ['Belirsiz alacak davası']);
        expect(preview.warning, article.repealNotice);
      });
    });

    test('the heading of the next article is not left at the foot of this '
        'one, footnote mark and all', () async {
      await withTempDirectory((dir) async {
        final article = (await legislation(dir).lookup(_article('HMK m. 106')))
            .article!;
        expect(article.headings, ['Tespit davası']);
        final text = plainTextOfParagraphs(article.body);
        expect(text, startsWith('MADDE 106-'));
        expect(text, isNot(contains('Belirsiz alacak')));
        expect(article.repealed, isFalse);
        expect(article.repealNotice, isNull);
      });
    });

    test('a repeal note is put in words, a decree-law’s too; another form is '
        'not guessed at', () {
      const rest =
          ' Resmî güncel metinde maddenin yerinde yalnızca bu kayıt bulunur; '
          'kaldırılmadan önceki metni yer almaz.';
      expect(
        repealNoticeOf('MADDE 5 – (Mülga: 2/7/2018-KHK-703/45 md.)'),
        'Bu madde, 2/7/2018 tarihli ve 703 sayılı Kanun Hükmünde '
        'Kararnamenin 45. maddesiyle yürürlükten kaldırılmıştır.$rest',
      );
      expect(
        repealNoticeOf('MADDE 12 – (Mülga: 12/7/2013 – 6496 sayılı)'),
        'Bu madde, 12/7/2013 tarihli ve 6496 sayılı Kanunla yürürlükten '
        'kaldırılmıştır.$rest',
      );
      expect(
        repealNoticeOf('MADDE 9 – (Mülga)'),
        'Bu madde yürürlükten kaldırılmıştır.$rest',
      );
    });

    test(
      'with the bank out of reach, the page on mevzuat.gov.tr is read',
      () async {
        await withTempDirectory((dir) async {
          final laws = Legislation(
            cache: dir,
            download: (law) async =>
                File('test/fixtures/mevzuat_sayfa.html').readAsStringSync(),
            bedesten: BedestenLegislation(
              send: (path, body) async => throw const SocketException('ağ yok'),
              between: _quick,
            ),
          );
          const kvkk = Law(
            number: 6698,
            tertip: 5,
            name: 'Kişisel Verilerin Korunması Kanunu',
          );
          final got = await laws.lookup(
            const Citation(law: kvkk, article: 3, start: 0, length: 4),
          );
          expect(got.article?.source, ArticleSource.mevzuatGov);
          expect(got.article?.text, contains('Açık rıza'));
        });
      },
    );

    test('an article nowhere to be had says which it was', () async {
      await withTempDirectory((dir) async {
        final got = await legislation(dir).lookup(_article('HMK m. 999'));
        expect(got.outcome, ArticleOutcome.absent);
        expect(
          got.url,
          contains('MevzuatNo=6100'),
          reason: 'resmî sayfaya yine gidilebilmeli',
        );
      });
    });
  });

  test('the page of a law keeps its lettered, provisional and added articles apart', () {
    final found = Legislation.articlesKeyedIn(
      'MADDE 68- Talebine itiraz …\n'
      'Madde 68/a – (Ek) Takibin dayandığı senet …\n'
      'GEÇİCİ MADDE 3- Geçiş …\n'
      'EK MADDE 1- Ek hüküm …',
    );
    expect(found.keys, containsAll(['68', '68/a', 'geçici 3', 'ek 1']));
    expect(found['68'], isNot(contains('68/a')));
    expect(Legislation.keyOf(_article('İİK 68/a')), '68/a');
    expect(Legislation.keyOf(_article('HMK geçici madde 3')), 'geçici 3');
  });
}

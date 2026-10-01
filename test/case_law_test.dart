import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/legal/case_law.dart';
import 'package:evrak_convert/services/legal/case_law_search.dart';
import 'package:evrak_convert/services/legal/decision.dart';

Future<void> withTempDirectory(Future<void> Function(Directory) body) async {
  final dir = await Directory.systemTemp.createTemp('folio_ictihat_');
  try {
    await body(dir);
  } finally {
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

DecisionScanner _scanner() => DecisionScanner.parse(
  File('assets/mevzuat/courts.json').readAsStringSync(),
);

DecisionCitation _cited(String text) => _scanner().scan(text).single;

/// Bedesten'in verdiği biçim: künye listesi, sonra base64 gövde.
String _searchAnswer({String bench = '15. Hukuk Dairesi'}) => jsonEncode({
  'data': {
    'total': 1,
    'emsalKararList': [
      {
        'documentId': '610215100',
        'birimAdi': bench,
        'esasNo': '2016/1531',
        'kararNo': '2017/3344',
        'kararTarihiStr': '21.09.2017',
      },
    ],
  },
});

String _contentAnswer(String html) => jsonEncode({
  'data': {'content': base64.encode(utf8.encode(html))},
});

const _empty = '{"data":{"total":0,"emsalKararList":[]}}';

void main() {
  const cited = 'Yargıtay 15. Hukuk Dairesi, 2016/1531 E., 2017/3344 K.';
  const quick = Duration(milliseconds: 1);

  test(
    'a decision is fetched by its numbers and read out of the page',
    () async {
      await withTempDirectory((dir) async {
        final asked = <String>[];
        final bank = CaseLaw(
          cache: dir,
          between: quick,
          send: (path, body) async {
            asked.add(path);
            if (path.contains('search')) {
              // Numaralar gövdeye yapısal girmeli; metinden ayıklanmamalı.
              final sent = jsonDecode(body!) as Map;
              final data = (sent['data'] as Map);
              expect(data['esasNoYil'], 2016);
              expect(data['esasNoSira'], 1531);
              expect(data['kararNoYil'], 2017);
              expect(data['kararNoSira'], 3344);
              return _searchAnswer();
            }
            return _contentAnswer(
              '<html><body><p>MAHKEMESİ : Asliye Hukuk</p>'
              '<p>Davacı vekili, kamulaştırmasız\nel atma iddiasıyla…</p>'
              '</body></html>',
            );
          },
        );

        final got = await bank.decision(_cited(cited));
        expect(got, isNotNull);
        expect(got!.court, '15. Hukuk Dairesi');
        expect(got.date, '21.09.2017');
        // Word'ün satır sarması cümleyi bölmemeli.
        expect(got.text, contains('kamulaştırmasız el atma iddiasıyla'));
        expect(got.text, isNot(contains('<p>')));
        expect(asked, hasLength(2), reason: 'arama + metin, iki istek');
        expect(got.title, contains('15. Hukuk Dairesi'));
      });
    },
  );

  test('a first instance citation is never asked about', () async {
    await withTempDirectory((dir) async {
      var asked = 0;
      final bank = CaseLaw(
        cache: dir,
        between: quick,
        send: (path, body) async {
          asked++;
          return _searchAnswer();
        },
      );
      final one = _cited(
        'Kemer Sulh Hukuk Mahkemesi 2021/1407 E. 2021/1388 K.',
      );
      expect(one.fetchable, isFalse);
      expect(await bank.decision(one), isNull);
      expect(asked, 0, reason: 'ilk derece için bankaya gidilmemeli');
    });
  });

  test('a decision fetched once is not fetched again', () async {
    await withTempDirectory((dir) async {
      var searches = 0;
      Future<String> send(String path, String? body) async {
        if (path.contains('search')) searches++;
        return path.contains('search')
            ? _searchAnswer()
            : _contentAnswer('<p>metin</p>');
      }

      final first = CaseLaw(cache: dir, between: quick, send: send);
      expect((await first.decision(_cited(cited)))?.text, 'metin');
      expect(searches, 1);
      expect((await first.decision(_cited(cited)))?.text, 'metin');
      expect(searches, 1, reason: 'bellekteki kopya kullanılmalı');

      final later = CaseLaw(cache: dir, between: quick, send: send);
      expect((await later.decision(_cited(cited)))?.text, 'metin');
      expect(searches, 1, reason: 'diskteki kopya kullanılmalı');
      expect(await later.isKept(_cited(cited)), isTrue);
    });
  });

  test('a decision the bank has not got is not asked for twice', () async {
    await withTempDirectory((dir) async {
      var searches = 0;
      Future<String> send(String path, String? body) async {
        searches++;
        return _empty;
      }

      final first = CaseLaw(cache: dir, between: quick, send: send);
      expect(await first.decision(_cited(cited)), isNull);
      expect(searches, 1);
      expect(await first.decision(_cited(cited)), isNull);
      expect(searches, 1, reason: 'yokluk da hatırlanmalı');

      // Ve hatırlanan yokluk diskten de okunmalı: üçte ikisi bulunamıyor,
      // her açılışta yeniden beklemek pahalıya gelir.
      final later = CaseLaw(cache: dir, between: quick, send: send);
      expect(await later.decision(_cited(cited)), isNull);
      expect(searches, 1);
    });
  });

  test('the bench the document named is preferred among several', () async {
    await withTempDirectory((dir) async {
      final bank = CaseLaw(
        cache: dir,
        between: quick,
        send: (path, body) async {
          if (!path.contains('search')) return _contentAnswer('<p>x</p>');
          return jsonEncode({
            'data': {
              'total': 2,
              'emsalKararList': [
                {
                  'documentId': '1',
                  'birimAdi': '9. Hukuk Dairesi',
                  'esasNo': '2016/1531',
                  'kararNo': '2017/3344',
                },
                {
                  'documentId': '2',
                  'birimAdi': '15. Hukuk Dairesi',
                  'esasNo': '2016/1531',
                  'kararNo': '2017/3344',
                },
              ],
            },
          });
        },
      );
      final got = await bank.decision(_cited(cited));
      expect(got?.court, '15. Hukuk Dairesi');
    });
  });

  test('a refusal is waited out rather than shown to the reader', () async {
    await withTempDirectory((dir) async {
      var tries = 0;
      final bank = CaseLaw(
        cache: dir,
        between: quick,
        send: (path, body) async {
          if (path.contains('search')) {
            tries++;
            // İlkinde banka "şimdilik yeter" diyor.
            if (tries == 1) return '<html>Erişim Sınırı Aşıldı</html>';
            return _searchAnswer();
          }
          return _contentAnswer('<p>metin</p>');
        },
      );
      expect((await bank.decision(_cited(cited)))?.text, 'metin');
      expect(tries, 2);
    });
  });

  test('with no network nothing is shown and nothing throws', () async {
    await withTempDirectory((dir) async {
      final bank = CaseLaw(
        cache: dir,
        between: quick,
        send: (path, body) async => throw const SocketException('ağ yok'),
      );
      expect(await bank.decision(_cited(cited)), isNull);
      expect(await bank.isKept(_cited(cited)), isFalse);
    });
  });

  test(
    'a damaged file on disk is fetched again rather than thrown over',
    () async {
      await withTempDirectory((dir) async {
        await File('${dir.path}/2016-1531_2017-3344.json')
            .writeAsString('{ yarim');
        final bank = CaseLaw(
          cache: dir,
          between: quick,
          send: (path, body) async => path.contains('search')
              ? _searchAnswer()
              : _contentAnswer('<p>metin</p>'),
        );
        expect((await bank.decision(_cited(cited)))?.text, 'metin');
      });
    },
  );

  test('presses are queued rather than sent all at once', () async {
    await withTempDirectory((dir) async {
      var inFlight = 0, most = 0;
      final bank = CaseLaw(
        cache: dir,
        between: quick,
        send: (path, body) async {
          inFlight++;
          most = most > inFlight ? most : inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          inFlight--;
          return path.contains('search')
              ? _searchAnswer()
              : _contentAnswer('<p>metin</p>');
        },
      );
      await Future.wait([
        for (var i = 0; i < 4; i++)
          bank.decision(
            _scanner()
                .scan('Yargıtay 15. HD 201$i/1531 E., 2017/334$i K.')
                .single,
          ),
      ]);
      expect(most, 1, reason: 'aynı anda tek istek gitmeli');
    });
  });

  test(
    'one request serves several pages, and no run fills the first',
    () async {
      await withTempDirectory((dir) async {
        var searches = 0;
        final bank = CaseLaw(
          cache: dir,
          between: quick,
          send: (path, body) async {
            searches++;
            return jsonEncode({
              'data': {
                'total': 5528,
                'emsalKararList': [
                  // Bir dairenin bir günde çıkardığı sekizli seri; bankada
                  // hepsi başa geliyor, çünkü hepsi sorguya tam uyuyor.
                  for (var n = 5760; n <= 5767; n++)
                    {
                      'documentId': 'a$n',
                      'birimAdi': '9. Hukuk Dairesi',
                      'esasNo': '2014/$n',
                      'kararNo': '2014/1',
                      'kararTarihiStr': '03.03.2014',
                    },
                  for (var n = 0; n < 12; n++)
                    {
                      'documentId': 'b$n',
                      'birimAdi': '${n + 1}. Hukuk Dairesi',
                      'esasNo': '2019/${100 + n * 13}',
                      'kararNo': '2019/9',
                      'kararTarihiStr': '05.05.2019',
                    },
                ],
              },
            });
          },
        );

        final first = await bank.search(const CaseLawQuery(words: 'kıdem'));
        expect(searches, 1);
        expect(first.total, 5528);
        expect(first.hits.length, 10);
        expect(
          first.hits.where((hit) => hit.esas.startsWith('2014/57')).length,
          2,
          reason: 'seriden sayfaya en çok iki karar gelmeli',
        );

        final second = await bank.search(
          const CaseLawQuery(words: 'kıdem', page: 2),
        );
        expect(searches, 1, reason: 'ikinci sayfa aynı toplu getirmeden çıkar');
        expect(
          {
            ...first.hits.map((hit) => hit.documentId),
            ...second.hits.map((hit) => hit.documentId),
          }.length,
          20,
          reason: 'hiçbir karar düşmemeli, tekrarlanmamalı',
        );
      });
    },
  );
}

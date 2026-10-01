import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/legal/citation.dart';
import 'package:evrak_convert/services/legal/html_text.dart';
import 'package:evrak_convert/services/legal/legislation.dart';

/// Bir testin kendi kopyalarini yazdigi, sonunda silinen klasor.
Future<void> withTempDirectory(
  Future<void> Function(Directory dir) body,
) async {
  final dir = await Directory.systemTemp.createTemp('folio_mevzuat_');
  try {
    await body(dir);
  } finally {
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

const _kvkk = Law(
  number: 6698,
  tertip: 5,
  name: 'Kişisel Verilerin Korunması Kanunu',
);

Citation _at(int article) =>
    Citation(law: _kvkk, article: article, start: 0, length: 4);

String get _page => File('test/fixtures/mevzuat_sayfa.html').readAsStringSync();

void main() {
  test('a page written by Word is read without its wrapping', () {
    final text = plainTextOf(_page);
    // Word broke this sentence across two source lines; it has to come back
    // as one, or the article would be cut where the wrap happened to fall.
    expect(
      text,
      contains('Belirli bir konuya ilişkin, bilgilendirilmeye dayanan'),
    );
    // A non-breaking space is still a space.
    expect(text, contains('bu Kanunda ve diğer kanunlarda'));
    expect(text, isNot(contains('<span')));
    expect(text, isNot(contains('&nbsp;')));
  });

  test(
    'articles are split where they begin, in either the old or new style',
    () {
      final found = Legislation.articlesIn(plainTextOf(_page));
      expect(found.keys, containsAll(<int>[3, 4, 5]));
      // The side heading above the article belongs to it, not to the one
      // before: a lawyer reads "Tanımlar" and knows where they are.
      expect(found[3], startsWith('Tanımlar'));
      expect(found[3], contains('MADDE 3-'));
      expect(found[3], contains('Açık rıza'));
      // Article 3 stops where article 4's heading starts.
      expect(found[3], isNot(contains('Genel ilkeler')));
      expect(found[4], startsWith('Genel ilkeler'));
      // The old laws use a long dash, and that is a beginning too.
      expect(found[5], startsWith('Madde 5 –'));
    },
  );

  test('a heading on the article\'s own line still starts a new article', () {
    // Gercek sayfalarda gordugum bicim: "Sürelerin belirlenmesi MADDE 90-".
    // Satir basi sart kosuldugunda bu madde hic gorunmuyor ve bir onceki
    // maddenin govdesine karisiyordu.
    final found = Legislation.articlesIn(plainTextOf(_page));
    expect(found.containsKey(6), isTrue);
    expect(found[6], startsWith('Başlığı aynı satırda'));
    expect(found[6], contains('MADDE 6-'));
    // Ikinci fikrasi da kendisine ait: kesim uzunluga gore degil, sinira gore.
    expect(found[6], contains('(2) İkinci fıkrası da buraya ait.'));
    // Ve bir sonrakini yutmuyor.
    expect(found[6], isNot(contains('MADDE 7-')));
  });

  test('a heading run straight into the article is still a boundary', () {
    // "BoşluksuzyapışıkMADDE 7-": arada bosluk bile yok.
    final found = Legislation.articlesIn(plainTextOf(_page));
    expect(found.containsKey(7), isTrue);
    expect(found[7], contains('MADDE 7-'));
    expect(found[7], contains('Başlıkla arada boşluk yok'));
    expect(found[5], isNot(contains('MADDE 7-')));
  });

  test('an added article ends the one before it without taking its number', () {
    final found = Legislation.articlesIn(plainTextOf(_page));
    // EK MADDE 1 bir sinirdir: m.8 onu yutmamali.
    expect(found[8], isNot(contains('EK MADDE')));
    // Ama 1 numarali maddenin yerine de gecmemeli.
    expect(found[1], isNull);
  });

  test('the tables a law closes with are not part of its last article', () {
    final found = Legislation.articlesIn(plainTextOf(_page));
    for (final article in found.values) {
      expect(
        article,
        isNot(contains('İŞLENEMEYEN HÜKÜMLER')),
        reason: 'kapanış notları maddeye karışmamalı',
      );
    }
  });

  test('every article stops where the next one starts', () {
    // Tek tek degil, topluca: hicbir madde ikinci bir madde basligi tasimamali.
    final found = Legislation.articlesIn(plainTextOf(_page));
    final heading = RegExp(r'(?:MADDE|Madde) \d+ ?[-–—]');
    for (final entry in found.entries) {
      expect(
        heading.allMatches(entry.value.replaceAll(RegExp(r'\s+'), ' ')).length,
        1,
        reason: 'm.${entry.key} birden fazla madde başlığı taşıyor',
      );
    }
  });

  test('a cross-reference inside an article is not a new article', () {
    final found = Legislation.articlesIn(plainTextOf(_page));
    // "Madde 5/1 saklıdır." sits inside article 4 and must stay there.
    expect(found[4], contains('Madde 5/1 saklıdır'));
    expect(found.containsKey(51), isFalse);
  });

  test(
    'entities are unescaped, and an escaped ampersand makes no second one',
    () {
      expect(unescapeEntities('&amp;nbsp; ve &lt;a&gt;'), '&nbsp; ve <a>');
      expect(unescapeEntities('&#39;tek&#39;'), "'tek'");
    },
  );

  test('a law is fetched once and then answered from what was kept', () async {
    await withTempDirectory((dir) async {
      var fetches = 0;
      final kept = Legislation(
        cache: dir,
        download: (law) async {
          fetches++;
          return _page;
        },
      );

      expect((await kept.article(_at(3)))?.text, contains('Açık rıza'));
      expect(fetches, 1);

      // The same law again, and a different article of it: still one fetch.
      expect(
        (await kept.article(_at(4)))?.text,
        contains('Kişisel veriler, ancak'),
        reason: 'ayni kanun',
      );
      expect(fetches, 1);

      // A fresh reader of the same cache directory does not fetch either.
      final later = Legislation(
        cache: dir,
        download: (law) async {
          fetches++;
          return _page;
        },
      );
      expect((await later.article(_at(3)))?.text, contains('Açık rıza'));
      expect(fetches, 1, reason: 'diskteki kopya kullanilmali');
      expect(await later.isKept(_kvkk), isTrue);
    });
  });

  test('an article the law does not have is simply not found', () async {
    await withTempDirectory((dir) async {
      final kept = Legislation(cache: dir, download: (law) async => _page);
      expect(await kept.article(_at(999)), isNull);
    });
  });

  test(
    'a reader with no network is given the older copy rather than nothing',
    () async {
      await withTempDirectory((dir) async {
        // Bir kopya birak, ama saklama suresinden eski olsun.
        final old = DateTime.now().toUtc().subtract(Legislation.keepFor * 2);
        await File('${dir.path}/6698.json').writeAsString(
          jsonEncode({
            'kanun': 6698,
            'alindi': old.toIso8601String(),
            'maddeler': {'3': 'MADDE 3- eski ama elde olan'},
          }),
        );

        final offline = Legislation(
          cache: dir,
          download: (law) async => throw const SocketException('ağ yok'),
        );
        final got = await offline.article(_at(3));
        expect(got?.text, 'MADDE 3- eski ama elde olan');
      });
    },
  );

  test('a copy still within its keep is not fetched again', () async {
    await withTempDirectory((dir) async {
      await File('${dir.path}/6698.json').writeAsString(
        jsonEncode({
          'kanun': 6698,
          'alindi': DateTime.now().toUtc().toIso8601String(),
          'maddeler': {'3': 'MADDE 3- taze kopya'},
        }),
      );
      var fetches = 0;
      final kept = Legislation(
        cache: dir,
        download: (law) async {
          fetches++;
          return _page;
        },
      );
      expect((await kept.article(_at(3)))?.text, 'MADDE 3- taze kopya');
      expect(fetches, 0);
    });
  });

  test(
    'a damaged file on disk is fetched again rather than thrown over',
    () async {
      await withTempDirectory((dir) async {
        await File('${dir.path}/6698.json').writeAsString('{ yarim');
        final kept = Legislation(cache: dir, download: (law) async => _page);
        expect((await kept.article(_at(3)))?.text, contains('Açık rıza'));
      });
    },
  );

  test(
    'with nothing kept and no network, nothing is shown and nothing throws',
    () async {
      await withTempDirectory((dir) async {
        final offline = Legislation(
          cache: dir,
          download: (law) async => throw const SocketException('ağ yok'),
        );
        expect(await offline.article(_at(3)), isNull);
        expect(await offline.isKept(_kvkk), isFalse);
      });
    },
  );

  test('an article carries the name it is shown under', () async {
    await withTempDirectory((dir) async {
      final kept = Legislation(cache: dir, download: (law) async => _page);
      final got = await kept.article(_at(3));
      expect(got!.title, '6698 s. Kişisel Verilerin Korunması Kanunu m. 3');
    });
  });
}

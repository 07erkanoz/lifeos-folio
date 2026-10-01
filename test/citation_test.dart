import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/legal/citation.dart';

CitationScanner _scanner() =>
    CitationScanner.parse(File('assets/mevzuat/laws.json').readAsStringSync());

void main() {
  test('the table the app ships is well formed and has no clashes', () {
    final raw = File('assets/mevzuat/laws.json').readAsStringSync();
    final laws = (jsonDecode(raw) as Map)['kanunlar'] as List;
    expect(laws, isNotEmpty);

    final short = <String, int>{};
    for (final entry in laws) {
      final law = Law.fromJson(entry as Map<String, Object?>);
      expect(law.tertip, inInclusiveRange(1, 5), reason: '${law.number}');
      expect(law.name, isNotEmpty);
      for (final a in law.abbreviations) {
        final key = lookupKey(a);
        expect(
          short[key] ?? law.number,
          law.number,
          reason: '$a iki kanuna birden bağlı: ${short[key]}',
        );
        short[key] = law.number;
      }
    }
  });

  test('Turkish upper case keeps the dotted and dotless i apart', () {
    expect(upperTr('iik'), 'İİK');
    expect(upperTr('ıyuk'), 'IYUK');
    expect(upperTr('TMK'), 'TMK');
  });

  test('the settled ways of pointing at an article are all read', () {
    const text =
        'Davacı vekili, TMK m. 166/1 uyarınca boşanma talep etmiştir. '
        '6100 sayılı Hukuk Muhakemeleri Kanunu\'nun 119. maddesinde sayılan '
        'unsurlar mevcuttur. Müvekkil aleyhine İİK 89/1 haciz ihbarnamesi '
        'gönderilmiştir. Sanık hakkında TCK m.53/1-a gereğince hak '
        'yoksunluğuna hükmedilmesi, HMK\'nın 297. maddesi uyarınca hükmün '
        'gerekçeli yazılması talep olunur. TBK 112 ve TTK m. 18 hükümleri de '
        'uygulanacaktır.';

    final found = _scanner().scan(text);
    final seen = [for (final c in found) '${c.law.number}/${c.article}'];
    expect(
      seen,
      containsAll(<String>[
        '4721/166',
        '6100/119',
        '2004/89',
        '5237/53',
        '6100/297',
        '6098/112',
        '6102/18',
      ]),
    );

    final tmk = found.firstWhere((c) => c.law.number == 4721);
    expect(tmk.paragraph, 1);
    expect(text.substring(tmk.start, tmk.end), contains('TMK'));

    final tck = found.firstWhere((c) => c.law.number == 5237);
    expect(tck.paragraph, 1);
    expect(tck.clause, 'a');
    expect(tck.label, '5237 s. Türk Ceza Kanunu m. 53/1-a');
  });

  test('offsets land on the text that was scanned', () {
    const text = 'Şu hâlde TMK m. 166 uygulanır.';
    final one = _scanner().scan(text).single;
    expect(text.substring(one.start, one.end), 'TMK m. 166');
  });

  test('a citation is not reported twice for the one mention', () {
    // Hem uzun hem kısa biçim aynı yere oturuyor; geniş okuma kazanır.
    const text = '6100 sayılı HMK\'nın 119. maddesi gereğince';
    final found = _scanner().scan(text);
    expect(found.length, 1);
    expect(found.single.law.number, 6100);
    expect(found.single.article, 119);
  });

  test('a number that is not an article number is passed over', () {
    // 5237 burada kanun numarası, madde numarası değil.
    final found = _scanner().scan('5237 sayılı Kanun yürürlüktedir.');
    expect(found.where((c) => c.article > 2000), isEmpty);
  });

  test('a law named rather than numbered is read too', () {
    // Dilekçede en yaygın yazım bu: kanun numarası hiç geçmez.
    final scanner = _scanner();
    const cases = {
      "Türk Borçlar Kanunu'nun 112. maddesi": [6098, 112],
      "Borçlar Kanunu'nun 112. maddesi": [6098, 112],
      "Medeni Kanun'un 166. maddesi": [4721, 166],
      "Hukuk Muhakemeleri Kanununun 119 uncu maddesi": [6100, 119],
      "İcra ve İflas Kanunu m. 89": [2004, 89],
      "Ticaret Kanunu'nun 18 inci maddesi": [6102, 18],
      "Türk Borçlar Kanunu'nda 112. madde": [6098, 112],
    };
    cases.forEach((text, want) {
      final found = scanner.scan(text);
      expect(found, hasLength(1), reason: text);
      expect(found.single.law.number, want[0], reason: text);
      expect(found.single.article, want[1], reason: text);
    });
  });

  test(
    'the fuller name of a law is preferred to the shorter one inside it',
    () {
      final found = _scanner().scan("Türk Ceza Kanunu'nun 53. maddesi");
      expect(found, hasLength(1));
      expect(found.single.law.number, 5237);
      // "Ceza Kanunu" da eşleşirdi; geniş okuma kazanmalı.
      expect(
        found.single.length,
        greaterThan('Ceza Kanunu\'nun 53. madde'.length),
      );
    },
  );

  test('a law\'s name in ordinary prose is not a citation', () {
    final scanner = _scanner();
    for (final text in [
      'Bu kanunu okudum.',
      'Kanun 2024 yılında çıktı.',
      'Ceza Kanunu genel olarak uygulanır.',
    ]) {
      expect(scanner.scan(text), isEmpty, reason: text);
    }
  });

  test('no two laws answer to the same name', () {
    final seen = <String, int>{};
    for (final law in _scanner().laws) {
      for (final name in law.names) {
        final key = lookupKey(name);
        expect(
          seen[key] ?? law.number,
          law.number,
          reason: '"$name" hem ${seen[key]} hem ${law.number} demek olamaz',
        );
        seen[key] = law.number;
      }
    }
    expect(seen, isNotEmpty);
  });

  test('ordinary writing is not mistaken for a citation', () {
    final found = _scanner().scan(
      'Dosya 2024/1234 esas sayılıdır ve 15 Mart tarihlidir.',
    );
    expect(found, isEmpty);
  });

  List<String> short(List<Citation> found) => [
    for (final c in found) '${c.law.number}/${c.article}',
  ];

  test('more laws and short forms are read', () {
    final scanner = _scanner();
    const cases = {
      'CMK 231/5 uyarınca': [5271, 231],
      'TTK m. 18': [6102, 18],
      "İİK'nın 89/1. maddesi": [2004, 89],
      'İşK m. 18': [4857, 18],
      'MÖHUK 40': [5718, 40],
      'KTK 85': [2918, 85],
      "Karayolları Trafik Kanunu'nun 85. maddesi": [2918, 85],
      "İş Kanunu'nun 18. maddesi": [4857, 18],
      "Anayasa'nın 10. maddesi": [2709, 10],
      'hmk m. 119': [6100, 119],
      "Tebligat Kanunu'nun 21/2. maddesi": [7201, 21],
      'Kadastro Kanunu m.14 uyarınca': [3402, 14],
    };
    cases.forEach((text, want) {
      final found = scanner.scan(text);
      expect(found, hasLength(1), reason: '$text → ${short(found)}');
      expect(
        [found.single.law.number, found.single.article],
        want,
        reason: text,
      );
    });
  });

  test('a number written before the short form decides the law', () {
    final scanner = _scanner();
    final bk = scanner.scan('818 s. BK m. 41 uyarınca').single;
    expect(bk.law.number, 818);
    expect(bk.law.repealed, isTrue);
    expect(bk.start, 0, reason: 'the number belongs to the citation');
    final tmk = scanner.scan("3713 sayılı TMK'nın 7/2. maddesi").single;
    expect([tmk.law.number, tmk.article, tmk.paragraph], [3713, 7, 2]);
  });

  test('a law the table does not carry is read by its number', () {
    final scanner = _scanner();
    final one = scanner.scan("5626 sayılı Kanun'un 8. maddesi").single;
    expect([one.law.number, one.law.tertip, one.article], [5626, 0, 8]);
    expect(one.label, '5626 sayılı Kanun m. 8');
    final marked = scanner.scan('5510 sayılı Kanun m. 4/1-a kapsamında').single;
    expect(
      [marked.law.number, marked.article, marked.paragraph, marked.clause],
      [5510, 4, 1, 'a'],
    );
    expect(scanner.scan('1234 sayılı dosyanın 5. maddesi'), isEmpty);
    expect(scanner.scan('2020/123 sayılı kararın 5. maddesi'), isEmpty);
    expect(scanner.scan("1234 sayılı Genelge'nin 5. maddesi"), isEmpty);
  });

  test('the article marked before its number, the long way', () {
    // Ölçüldü: gerçek arşivde ~900 atıf bu biçimde ve hiçbiri okunmuyordu.
    final scanner = _scanner();
    expect(short(scanner.scan("2942 sayılı Kanun m.11 ve m.15'te")), [
      '2942/11',
    ]);
    expect(short(scanner.scan('3402 sayılı Kadastro Kanunu m.14 uyarınca')), [
      '3402/14',
    ]);
  });

  test('a list of articles is a citation for each', () {
    const text =
        "TBK'nın 49, 50 ve 51. maddeleri ile HMK m. 119, 120 ve 121 uyarınca";
    expect(short(_scanner().scan(text)), [
      '6098/49',
      '6098/50',
      '6098/51',
      '6100/119',
      '6100/120',
      '6100/121',
    ]);
  });

  test('a fıkra, a count or a year after a comma is not a list', () {
    final scanner = _scanner();
    expect(short(scanner.scan('TMK m. 166, 2. fıkrası')), ['4721/166']);
    expect(short(scanner.scan('TMK m. 166, 2 çocuk var')), ['4721/166']);
    expect(short(scanner.scan('TMK m. 166, 2023 yılında')), ['4721/166']);
  });

  test('"the same law" is the law cited just before', () {
    final scanner = _scanner();
    const text =
        "HMK m. 119 gereğince dava açılmış; aynı Kanun'un 7. maddesi de "
        'uygulanır.';
    expect(short(scanner.scan(text)), ['6100/119', '6100/7']);
    expect(scanner.scan("Aynı Kanun'un 7. maddesi"), isEmpty);
  });

  test('lettered, provisional and added articles', () {
    final scanner = _scanner();
    final lettered = scanner.scan('İİK 68/a uyarınca').single;
    expect([lettered.article, lettered.letter], [68, 'a']);
    expect(lettered.place, 'm. 68/a');
    for (final text in [
      'HMK geçici madde 3',
      "HMK'nın geçici 3. maddesi",
      'HMK Geçici Madde 3',
    ]) {
      final one = scanner.scan(text).single;
      expect(
        [one.law.number, one.article, one.kind],
        [6100, 3, ArticleKind.provisional],
        reason: text,
      );
      expect(one.place, 'geçici m. 3', reason: text);
    }
    final added = scanner.scan('4857 sayılı Kanun ek madde 2').single;
    expect(
      [added.law.number, added.article, added.kind],
      [4857, 2, ArticleKind.additional],
    );
  });

  test('a fıkra written as a number or a Roman numeral, a bent in Turkish', () {
    final scanner = _scanner();
    final a = scanner.scan("Türk Medeni Kanunu'nun 166/1 maddesi").single;
    expect([a.law.number, a.article, a.paragraph], [4721, 166, 1]);
    final b = scanner.scan('HMK 119/1-ğ bendi').single;
    expect([b.article, b.paragraph, b.clause], [119, 1, 'ğ']);
    final roman = scanner.scan('(TBK m. 479/II) Bu beyan').single;
    expect([roman.article, roman.paragraph, roman.letter], [479, 2, null]);
    expect(roman.place, 'm. 479/II');
  });

  test('a citation in capitals is read, dotted İ and all', () {
    final scanner = _scanner();
    expect(
      short(scanner.scan("5237 SAYILI TÜRK CEZA KANUNU'NUN 53. MADDESİ")),
      ['5237/53'],
    );
    expect(short(scanner.scan("TÜRK MEDENİ KANUNU'NUN 166. MADDESİ")), [
      '4721/166',
    ]);
    expect(short(scanner.scan("HMK'NIN 353/1-b-2 MADDESİ UYARINCA")), [
      '6100/353',
    ]);
  });

  test('a short form written with dots', () {
    final scanner = _scanner();
    expect(short(scanner.scan('bu madde H.M.K. 193. maddesi anlamında')), [
      '6100/193',
    ]);
    expect(short(scanner.scan("5237 sayılı T.C.K.'nun 62. maddesi")), [
      '5237/62',
    ]);
    expect(scanner.scan('T.C. 22222222220 kimlik numaralı'), isEmpty);
  });

  test('no false alarms: months, days, clock times, small letters', () {
    final scanner = _scanner();
    for (final text in [
      'HÜKÜM: 1 YIL 3 AY 15 GÜN HAPİS',
      'her ay 12 bin lira ödenir',
      'olay 12.03.2004 15:30 sularında',
      'Olay tarihi 13.01.2004 15 gün sonra',
      'SAYI 12 ile başlayan satır',
      'mk 166',
    ]) {
      expect(scanner.scan(text), isEmpty, reason: text);
    }
  });

  test('a two-letter short form is read with the word for an article', () {
    expect(short(_scanner().scan('AY m. 10 ve MK m. 166')), [
      '2709/10',
      '4721/166',
    ]);
  });

  test('each citation keeps the words the document wrote', () {
    const text = 'Davacı, 6100 sayılı HMK\'nın 119. maddesi uyarınca';
    final one = _scanner().scan(text).single;
    expect(one.written, text.substring(one.start, one.end));
    expect(one.written, "6100 sayılı HMK'nın 119. maddesi");
  });

  test('a number a word or two before decides the law', () {
    final scanner = _scanner();
    final one = scanner.scan('(7036 sayılı İş M.K. m. 3/13)').single;
    expect([one.law.number, one.article, one.paragraph], [7036, 3, 13]);
    final named = scanner.scan('(İş M.K. m. 3/19)').single;
    expect(named.law.number, 7036);
    // İki ayrı kanun: sayı sonrakine taşınmaz.
    expect(short(scanner.scan('6100 sayılı Kanun ve TMK m. 166')), [
      '4721/166',
    ]);
  });

  test("a Gazette's number is not a law's", () {
    const text =
        "15/04/2020 tarih ve 13100 sayılı Resmi Gazete'de yayımlanarak aynı "
        'gün yürürlüğe giren 7242 sayılı kanunun 10.maddesi';
    expect(short(_scanner().scan(text)), ['7242/10']);
    expect(
      _scanner().scan(
        "31796 sayılı Resmî Gazete'de yayımlanan Kanunun 5. maddesi",
      ),
      isEmpty,
    );
  });

  test('a lettered article keeps its letter as written, and its fıkra', () {
    final one = _scanner().scan('6325 sayılı Kanun m. 18/A-7 uyarınca').single;
    expect([one.article, one.letter, one.paragraph], [18, 'A', 7]);
    expect(one.place, 'm. 18/A-7');
  });

  test('two letters with a suffix, and a short form after a digit', () {
    final scanner = _scanner();
    expect(short(scanner.scan("BK'nun 355 vd. hükümleri")), ['6098/355']);
    expect(short(scanner.scan('Karar : 2020/64HMK 200 İspat')), ['6100/200']);
    expect(scanner.scan('Soğuk Damga Vardır. BK14 A/S Yazı :36/0'), isEmpty);
    expect(scanner.scan('VEKİL EDEN :ALİ VELİ 11111111110'), isEmpty);
  });

  test('a list whose first article kept its ordinal', () {
    // Kullanıcı bildirdi: "ve"den sonraki madde yakalanmıyordu.
    const text =
        "Konu: 3194 m.42/2'deki \"yapının sahibine\" ibaresinin Anayasa'nın "
        '2. ve 38. maddelerine aykırı olduğu iddiası.';
    expect(short(_scanner().scan(text)), ['3194/42', '2709/2', '2709/38']);
    expect(short(_scanner().scan("TCK'nın 2 nci ve 38 inci maddeleri")), [
      '5237/2',
      '5237/38',
    ]);
    expect(short(_scanner().scan("TMK'nın 166. ve 167. maddeleri")), [
      '4721/166',
      '4721/167',
    ]);
    // Cümle sonu noktası bir sıralama açmaz.
    expect(short(_scanner().scan('TMK m. 166. Ve 2023 yılında')), ['4721/166']);
  });
}

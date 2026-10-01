import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/legal/decision.dart';

DecisionScanner _scanner() => DecisionScanner.parse(
  File('assets/mevzuat/courts.json').readAsStringSync(),
);

void main() {
  test('the court table is well formed and its patterns compile', () {
    final raw = File('assets/mevzuat/courts.json').readAsStringSync();
    final courts = (jsonDecode(raw) as Map)['mahkemeler'] as List;
    expect(courts, isNotEmpty);
    for (final entry in courts) {
      final court = Court.fromJson(entry as Map<String, Object?>);
      expect(court.name, isNotEmpty);
      expect(() => court.pattern.hasMatch('deneme'), returnsNormally);
    }
    // İki taraf da temsil edilmeli, yoksa ayrım anlamsız olur.
    final parsed = _scanner().courts;
    expect(parsed.where((c) => c.published), isNotEmpty);
    expect(parsed.where((c) => !c.published), isNotEmpty);
  });

  group('the ways a decision is actually written', () {
    // Hepsi kullanıcının kendi arşivinden alınmış gerçek yazımlar.
    const real = {
      'Yargıtay 15. Hukuk Dairesi, 2016/1531 E., 2017/3344 K.': [
        '2016/1531',
        '2017/3344',
        true,
      ],
      "Yargıtay Hukuk Genel Kurulu'nun 17.05.2022 tarihli, 2019/811 E., 2022/642 K.":
          ['2019/811', '2022/642', true],
      'İstanbul Bölge Adliye Mahkemesi 22. Hukuk Dairesi 2021/2817 E. 2023/1950 K.':
          ['2021/2817', '2023/1950', true],
      'Antalya BAM 12.HD. 2021/451 E. 2021/2171 K.': [
        '2021/451',
        '2021/2171',
        true,
      ],
      'Yargıtay Ceza Genel Kurulu, 2017/723 E., 2018/562 K.': [
        '2017/723',
        '2018/562',
        true,
      ],
      'Yargıtay 15. Hukuk Dairesi 2017/232E. - 2018/310 K.': [
        '2017/232',
        '2018/310',
        true,
      ],
      // İlk derece: getirilmemeli.
      'Kemer Sulh Hukuk Mahkemesi 2021/1407E. – 2021/1388K.': [
        '2021/1407',
        '2021/1388',
        false,
      ],
      'Kemer 1. Aile Mahkemesi 2019/204E. 2019/871K.': [
        '2019/204',
        '2019/871',
        false,
      ],
      'Kemer 2. AHM 2019/259 E. 2020/444 K.': [
        '2019/259',
        '2020/444',
        false,
      ],
      'Antalya 4. İdare Mahkemesinin 2021/6 E. 2022/5 K.': [
        '2021/6',
        '2022/5',
        false,
      ],
    };

    test('each is read, and placed on the right side of the line', () {
      final scanner = _scanner();
      real.forEach((text, want) {
        final found = scanner.scan(text);
        expect(found, hasLength(1), reason: text);
        final one = found.single;
        expect(one.esas, want[0], reason: text);
        expect(one.karar, want[1], reason: text);
        expect(one.fetchable, want[2], reason: text);
      });
    });
  });

  test('offsets land on the text that was scanned', () {
    const text =
        'Bkz. Yargıtay 2. Hukuk Dairesi 2021/2008 E., 2021/3303 K. '
        'sayılı karar.';
    final one = _scanner().scan(text).single;
    expect(text.substring(one.start, one.end), '2021/2008 E., 2021/3303 K');
  });

  test('the nearest court wins, not the first one named', () {
    // Cümle bir kanunla başlayıp mahkemeyle bitiyor; numaraların sahibi
    // sağdaki. Tablo sırasına göre okumak burada ilk dereceyi Yargıtay
    // sanmaya yol açıyordu.
    const text =
        'HUKUKİ SEBEPLER: TMK m. 2, 3. Yargıtay 15. Hukuk Dairesi '
        'kararı uyarınca Kemer Sulh Hukuk Mahkemesi 2021/1407 E. '
        '2021/1388 K.';
    final one = _scanner().scan(text).single;
    expect(one.court?.published, isFalse);
    expect(one.fetchable, isFalse);
  });

  test('a court that was never named leaves the citation alone', () {
    final one = _scanner()
        .scan('Dosyada 2019/251 E. 2021/947 K. geçiyor.')
        .single;
    expect(one.court, isNull);
    expect(one.fetchable, isFalse);
  });

  test('two numbers that merely stand near each other are not a citation', () {
    final scanner = _scanner();
    // Araya cümle girmiş: bunlar bir kararın iki yarısı değil.
    expect(
      scanner.scan('2019/251 E. sayılı dosyada karar verildi ve 2021/947 K.'),
      isEmpty,
    );
    expect(scanner.scan('Dosya 2024/1234 esas sayılıdır.'), isEmpty);
  });

  test('a citation carries a name it can be shown under', () {
    final one = _scanner()
        .scan('Yargıtay Hukuk Genel Kurulu 2019/811 E., 2022/642 K.')
        .single;
    expect(one.label, contains('Hukuk Genel Kurulu'));
    expect(one.label, contains('E.2019/811'));
    expect(one.esasYear, 2019);
    expect(one.esasNumber, 811);
    expect(one.kararYear, 2022);
    expect(one.kararNumber, 642);
  });

  test('the court table carries where each court is asked', () {
    final courts = _scanner().courts;
    final aym = courts.firstWhere((c) => c.name == 'Anayasa Mahkemesi');
    expect(aym.source, CaseSource.constitutional);
    final bim = courts.firstWhere((c) => c.name == 'Bölge İdare Mahkemesi');
    expect(bim.published, isFalse, reason: 'no bank publishes BİM decisions');
    for (final court in courts.where((c) => c.published)) {
      expect(court.source, isNotNull, reason: court.name);
    }
  });

  group('more ways a decision is written', () {
    // Hepsi gerçek arşivdeki yazımlar (26 Eylül 2026 ölçümü).
    const cases = {
      'Yargıtay 3. Hukuk Dairesi Esas No: 2016/1531 Karar No: 2017/3344': [
        '2016/1531',
        '2017/3344',
        '3. Hukuk Dairesi',
      ],
      'Yargıtay HGK E: 2019/811 K: 2022/642': [
        '2019/811',
        '2022/642',
        'Yargıtay Hukuk Genel Kurulu',
      ],
      'Yargıtay 9. HD 2016/1531 Esas, 2017/3344 Karar sayılı': [
        '2016/1531',
        '2017/3344',
        '9. Hukuk Dairesi',
      ],
      "Danıştay 6. Dairesi'nin 2019/123 E., 2020/456 K. sayılı kararı": [
        '2019/123',
        '2020/456',
        'Danıştay 6. Daire',
      ],
      'Yargıtay 12. HD 2021/1 esas ve 2021/2 karar sayılı': [
        '2021/1',
        '2021/2',
        '12. Hukuk Dairesi',
      ],
      "Anayasa Mahkemesi'nin 08/10/2015 tarih ve 2014/140 Esas, 2015/85 "
          'Karar sayılı kararı': [
        '2014/140',
        '2015/85',
        'Anayasa Mahkemesi',
      ],
      'Anayasa Mahkemesinin 08.10.2015 tarih, 2014/140 esas ve 2015/85 '
          'karar sayılı kararı': [
        '2014/140',
        '2015/85',
        'Anayasa Mahkemesi',
      ],
      'Anayasa Mahkemesinin 08/10/2015 tarih ve 2014/140-2015/85 sayılı '
          'iptal kararı': [
        '2014/140',
        '2015/85',
        'Anayasa Mahkemesi',
      ],
      'Yargıtay Hukuk Genel Kurulu, 2023/3-751 E., 2024/465 K.': [
        '2023/3-751',
        '2024/465',
        'Yargıtay Hukuk Genel Kurulu',
      ],
      'Yargıtay HGK’nın 2011/7-695 Esas ve 2011/673 karar sayılı': [
        '2011/7-695',
        '2011/673',
        'Yargıtay Hukuk Genel Kurulu',
      ],
      'DANIŞTAY 4. Daire Esas: 2019 / 3421 Karar: 2020 / 3243': [
        '2019/3421',
        '2020/3243',
        'Danıştay 4. Daire',
      ],
      'Danıştay Dördüncü Dairesi 29.11.2005 günlü ve E:2005/1293, '
          'K:2005/2286 sayılı kararıyla': [
        '2005/1293',
        '2005/2286',
        'Danıştay 4. Daire',
      ],
      'Danıştay 4. D., E. 2016/20983 K. 2020/3399 T. 30.9.2020': [
        '2016/20983',
        '2020/3399',
        'Danıştay 4. Daire',
      ],
      'Danıştay VDDK., E. 2020/1315 K. 2020/1271 T. 18.11.2020': [
        '2020/1315',
        '2020/1271',
        'Danıştay Vergi Dava Daireleri Kurulu',
      ],
      'Y. 11. HD., T. 5.5.2005, E. 2004/7832, K. 2005/4751': [
        '2004/7832',
        '2005/4751',
        '11. Hukuk Dairesi',
      ],
      'Antalya Bölge Adliye Mahkemesi 3. Hukuk Dairesi 2020/31E. Ve '
          '2021/154K. Sayılı': [
        '2020/31',
        '2021/154',
        'Bölge Adliye Mahkemesi 3. Hukuk Dairesi',
      ],
      'İstanbul BAM 22. HD 2020/191 (E) ve 2021/961 (K) Karar sayılı': [
        '2020/191',
        '2021/961',
        'Bölge Adliye Mahkemesi 22. Hukuk Dairesi',
      ],
      'Yargıtay 2. Hukuk Dairesi 2024/92 Esas - 2024/146K. sayılı': [
        '2024/92',
        '2024/146',
        '2. Hukuk Dairesi',
      ],
      'Bölge Adliye Mahkemesi Gaziantep 13. Ceza Dairesi 2018/44 Esas - '
          '2020/2204 Karar sayılı': [
        '2018/44',
        '2020/2204',
        'Bölge Adliye Mahkemesi 13. Ceza Dairesi',
      ],
      'Yargıtay 3. HD 2021/214-2022/398 E-K sayılı': [
        '2021/214',
        '2022/398',
        '3. Hukuk Dairesi',
      ],
    };

    test('each is read, with the court the document declared', () {
      final scanner = _scanner();
      cases.forEach((text, want) {
        final found = scanner.scan(text);
        expect(found, hasLength(1), reason: '$text → $found');
        final one = found.single;
        expect([one.esas, one.karar, one.courtLabel], want, reason: text);
        expect(one.fetchable, isTrue, reason: text);
        expect(one.written, text.substring(one.start, one.end), reason: text);
      });
    });
  });

  test('a General Assembly esas is searched without its chamber', () {
    final one = _scanner()
        .scan('Yargıtay Hukuk Genel Kurulu, 2023/3-751 E., 2024/465 K.')
        .single;
    expect(
      [one.esasYear, one.esasNumber, one.bankEsas],
      [2023, 751, '2023/751'],
    );
  });

  test('an individual application is read only beside the court', () {
    final scanner = _scanner();
    final one = scanner
        .scan('AYM, Hasan Durmuş [GK], B. No: 2019/19126, 23/1/2025, § 45')
        .single;
    expect(one.application, isTrue);
    expect(one.constitutional, isTrue);
    expect(one.esas, '2019/19126');
    expect(one.label, 'Anayasa Mahkemesi B. No: 2019/19126');
    // Aynı sözcükler her arabuluculuk formunun başında da var.
    expect(
      scanner.scan(
        'Kemer Arabuluculuk Bürosu ARABULUCULUK BAŞVURU FORMU BAŞVURU '
        'NUMARASI : 2022/517 BAŞVURU TARİHİ : 11/10/2023',
      ),
      isEmpty,
    );
  });

  test('a Constitutional Court citation goes to that court', () {
    final one = _scanner()
        .scan('AYM 3.6.2025 E.2024/157 K.2025/121 ile iptal')
        .single;
    expect(one.constitutional, isTrue);
    expect(one.fetchable, isTrue);
  });

  test('a regional administrative court is not offered for fetching', () {
    final one = _scanner()
        .scan(
          'BÖLGE İDARE MAHKEMESİ İstanbul 6. Vergi Dava Dairesi Esas No: '
          '2019/2362 Karar No: 2020/1014',
        )
        .single;
    expect(one.court?.name, 'Bölge İdare Mahkemesi');
    expect(one.fetchable, isFalse);
  });

  test('a chamber written in words is a number', () {
    expect(DecisionScanner.chamberIn('Danıştay Dördüncü Dairesi'), 4);
    expect(DecisionScanner.chamberIn('Yargıtay On Birinci Hukuk Dairesi'), 11);
    expect(DecisionScanner.chamberIn('YİRMİÜÇÜNCÜ CEZA DAİRESİ'), 23);
    expect(DecisionScanner.chamberIn('Onuncu Daire'), 10);
    expect(DecisionScanner.chamberIn('Hukuk Genel Kurulu'), isNull);
  });
}

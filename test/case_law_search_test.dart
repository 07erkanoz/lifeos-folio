import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/legal/case_law_search.dart';

Map<String, Object?> _data(CaseLawQuery query) =>
    (jsonDecode(CaseLawQueryBuilder.body(query)) as Map)['data']
        as Map<String, Object?>;

String? _phrase(CaseLawQuery query) => _data(query)['phrase'] as String?;

void main() {
  group('what the bank will accept', () {
    test('the operators it takes are kept', () {
      expect(CaseLawQueryBuilder.accepted('işçi -istismar'), 'işçi -istismar');
      expect(CaseLawQueryBuilder.accepted('+kıdem -ihbar'), '+kıdem -ihbar');
      expect(CaseLawQueryBuilder.accepted('"haklı fesih"'), '"haklı fesih"');
    });

    test('characters it refuses are cleared rather than sent', () {
      // Bilmediği karakteri yok saymıyor, isteği tümden reddediyor.
      expect(
        CaseLawQueryBuilder.accepted('kıdem? tazminatı: fesih'),
        'kıdem tazminatı fesih',
      );
      // Uzun tire eksi işareti değil; kalırsa istek düşer.
      expect(
        CaseLawQueryBuilder.accepted('kıdem tazminatı — ne diyor'),
        'kıdem tazminatı ne diyor',
      );
    });

    test('Turkish letters are kept', () {
      expect(
        CaseLawQueryBuilder.accepted('şüpheli müdafi ığdır'),
        'şüpheli müdafi ığdır',
      );
    });

    test('an article keeps its number and loses its paragraph', () {
      // Bölü işareti reddediliyor; "4857/25" avukatın yazdığı hâliyle
      // gönderilemez, ama çıplak "25" de gürültü üretir.
      expect(CaseLawQueryBuilder.accepted('4857/25 fesih'), '4857 fesih');
      expect(CaseLawQueryBuilder.accepted('166/3'), '166');
      // Künye bozulmaz: onun kendi alanları var.
      expect(CaseLawQueryBuilder.accepted('2023/7868'), '2023 7868');
    });
  });

  group('the words a reader types', () {
    test('two words mean both, not either', () {
      // Bankanın varsayılanı VEYA: "kira tahliye" iki yüz bin karar döndürüyor,
      // oysa ikisini birden içeren yirmi dört bin isteniyordu.
      expect(
        CaseLawQueryBuilder.phraseFor('kira tahliye', WordJoin.all),
        'kira AND tahliye',
      );
      expect(
        CaseLawQueryBuilder.phraseFor('kira tahliye', WordJoin.any),
        'kira OR tahliye',
      );
    });

    test('words that are in every decision are not searched for', () {
      // "yargıtay ne diyor" aramasında "ne" ve "diyor" asıl kelimeyi boğuyordu.
      expect(
        CaseLawQueryBuilder.phraseFor('yargıtay ne diyor kira', WordJoin.all),
        'yargıtay AND kira',
      );
    });

    test('a word asked to be left out is carried as an exclusion', () {
      expect(
        CaseLawQueryBuilder.phraseFor('tazminat zamanaşımı', WordJoin.all),
        'tazminat AND zamanaşımı',
      );
      expect(
        CaseLawQueryBuilder.phraseFor('tazminat -zamanaşımı', WordJoin.all),
        'tazminat -zamanaşımı',
      );
    });

    test('a query the reader wrote themselves is not rebuilt', () {
      for (final written in [
        '"haksız tahliye"',
        'kira AND tahliye',
        '+kira +tahliye',
      ]) {
        expect(
          CaseLawQueryBuilder.phraseFor(written, WordJoin.all),
          written,
          reason: written,
        );
      }
    });

    test('one word is left as it is', () {
      expect(CaseLawQueryBuilder.phraseFor('kira', WordJoin.all), 'kira');
      expect(CaseLawQueryBuilder.phraseFor('   ', WordJoin.all), '');
    });
  });

  group('the body the bank is sent', () {
    test('the benches asked for are the ones sent', () {
      final data = _data(
        const CaseLawQuery(
          words: 'kira',
          kinds: {CourtKind.yargitay, CourtKind.danistay},
        ),
      );
      expect(data['itemTypeList'], ['YARGITAYKARARI', 'DANISTAYKARAR']);
    });

    test('a chamber goes as birimAdi, which is the one that filters', () {
      // birimId iki ayrı daire için aynı sayıyı veriyor: süzmüş gibi yapıp
      // ada göre süzmüyor.
      final data = _data(
        const CaseLawQuery(words: 'kira', chamber: '3. Hukuk Dairesi'),
      );
      expect(data['birimAdi'], '3. Hukuk Dairesi');
      expect(data.containsKey('birimId'), isFalse);
    });

    test('a half-given date range is not sent at all', () {
      final half = _data(CaseLawQuery(words: 'kira', from: DateTime.utc(2020)));
      expect(half.containsKey('kararTarihiStart'), isFalse);

      final whole = _data(
        CaseLawQuery(
          words: 'kira',
          from: DateTime.utc(2020),
          to: DateTime.utc(2020, 12, 31),
        ),
      );
      expect(whole['kararTarihiStart'], '2020-01-01T00:00:00.000Z');
      expect(whole['kararTarihiEnd'], '2020-12-31T00:00:00.000Z');
    });

    test('case numbers go as numbers, and need no words beside them', () {
      final data = _data(
        const CaseLawQuery(
          esasYear: 2018,
          esasNumber: 5662,
          kararYear: 2020,
          kararNumber: 5173,
        ),
      );
      expect(data['esasNoYil'], 2018);
      expect(data['esasNoSira'], 5662);
      expect(data['kararNoYil'], 2020);
      expect(data['kararNoSira'], 5173);
      expect(data.containsKey('phrase'), isFalse);
    });

    test('nothing empty is sent', () {
      expect(_phrase(const CaseLawQuery(words: '  ')), isNull);
    });

    test('a hundred are asked for, whatever page is being read', () {
      // Yüz kayıt, onla aynı tek isteğe ve aynı 0.4 saniyeye mal oluyor;
      // on istemek, bir dairenin bir oturumda ürettiğini almak demekti.
      final data = _data(const CaseLawQuery(words: 'kira'));
      expect(data['pageSize'], 100);
      expect(data['pageNumber'], 1);
    });

    test('the reader\'s page is found inside the batch, not asked for', () {
      for (var page = 1; page <= 10; page++) {
        final query = CaseLawQuery(words: 'kira', page: page);
        expect(_data(query)['pageNumber'], 1);
        expect(query.offsetInBatch, (page - 1) * 10);
      }
      const eleventh = CaseLawQuery(words: 'kira', page: 11);
      expect(_data(eleventh)['pageNumber'], 2);
      expect(eleventh.offsetInBatch, 0);
    });
  });

  group('the query as the reader set it up', () {
    test('a search with neither words nor numbers asks for nothing', () {
      expect(const CaseLawQuery().isEmpty, isTrue);
      expect(const CaseLawQuery(words: 'kira').isEmpty, isFalse);
      expect(const CaseLawQuery(esasYear: 2018).isEmpty, isFalse);
    });

    test('a filter can be taken off again', () {
      const set = CaseLawQuery(words: 'kira', chamber: '3. Hukuk Dairesi');
      expect(set.copyWith(clearChamber: true).chamber, isNull);
      expect(set.copyWith(clearChamber: true).words, 'kira');
    });
  });

  group('a decision in a list of results', () {
    test('it is read out of what the bank sends', () {
      final hit = CaseLawHit.fromJson(const {
        'documentId': 610215100,
        'birimAdi': '8. Hukuk Dairesi',
        'itemType': {'name': 'YARGITAYKARARI'},
        'esasNo': '2018/5662',
        'kararNo': '2020/5173',
        'kararTarihiStr': '21.09.2020',
      });
      expect(hit, isNotNull);
      expect(hit!.documentId, '610215100');
      expect(hit.kind, 'YARGITAYKARARI');
      expect(hit.title, '8. Hukuk Dairesi E.2018/5662 K.2020/5173 21.09.2020');
    });

    test('a row with no document behind it is passed over', () {
      expect(CaseLawHit.fromJson(const {'birimAdi': 'x'}), isNull);
    });
  });

  group('the order a page of results is put in', () {
    CaseLawHit hit(String id, {String court = '3. Hukuk Dairesi'}) =>
        CaseLawHit(
          documentId: id,
          court: court,
          kind: 'YARGITAYKARARI',
          esas: '2020/1',
          karar: '2020/2',
          date: '01.01.2020',
        );

    test('the decision on the point comes first', () {
      final order = CaseLawRanking.of(
        'kıdem tazminatı',
        [hit('a'), hit('b')],
        {
          'a': 'Kira sözleşmesinin feshine ilişkin uyuşmazlıktır.',
          'b': 'Davacının kıdem tazminatı talebi yerinde görülmüştür.',
        },
      );
      expect(order.first.documentId, 'b');
      expect(order.first.snippet, contains('kıdem tazminatı'));
      expect(order.first.score, greaterThan(order.last.score));
    });

    test('a higher bench separates two that are equally on the point', () {
      const same = 'Kıdem tazminatı talebi yerinde görülmüştür.';
      final order = CaseLawRanking.of(
        'kıdem tazminatı',
        [hit('daire'), hit('kurul', court: 'Hukuk Genel Kurulu')],
        {'daire': same, 'kurul': same},
      );
      expect(order.first.documentId, 'kurul');
    });

    test('one reasoning takes one row, however many carry it', () {
      // Bir daire aynı gün aynı işverene karşı yirmi davayı aynı gerekçeyle
      // karara bağlar. Bunları aşağı itmek işe yaramıyor, çünkü sayfanın
      // tamamı onlar oluyor; sayılıp tek satırda toplanıyorlar.
      const same =
          'Davacının kıdem tazminatı talebi yerinde görülmüştür ve '
          'mahkemece kabulüne karar verilmiştir.';
      final order = CaseLawRanking.of(
        'kıdem tazminatı',
        [hit('ilk'), hit('kopya'), hit('baska')],
        {
          'ilk': same,
          'kopya': same,
          'baska': 'Kıdem tazminatı hesabında giydirilmiş ücret esas alınır.',
        },
      );
      expect(order, hasLength(2));
      expect(order.firstWhere((h) => h.alike > 0).alike, 1);
      expect(order.where((h) => h.documentId == 'baska'), hasLength(1));
    });

    test('a decision whose text could not be had is gathered with nothing', () {
      // İmzasız olan "bilinmiyor" demektir, "aynısı" demek değil.
      final order = CaseLawRanking.of('kıdem', [hit('a'), hit('b')], const {});
      expect(order, hasLength(2));
      expect(order.every((h) => h.alike == 0), isTrue);
    });

    test('nothing in, nothing out', () {
      expect(CaseLawRanking.of('kira', const [], const {}), isEmpty);
    });
  });

  group('spreading a batch', () {
    CaseLawHit row(
      String esas, {
      String court = '9. Hukuk Dairesi',
      String date = '03.03.2014',
    }) => CaseLawHit(
      documentId: esas,
      court: court,
      kind: 'YARGITAYKARARI',
      esas: esas,
      karar: '2014/1',
      date: date,
    );

    test('one sitting of one chamber cannot fill the page', () {
      // Bankadan gerçekten böyle geldi: 9. HD, 03.03.2014, E.5760–5767.
      final rows = [
        for (var n = 5760; n <= 5767; n++) row('2014/$n'),
        row('2013/99', court: '7. Hukuk Dairesi', date: '03.09.2013'),
        row('2016/12', court: '22. Hukuk Dairesi', date: '14.01.2016'),
      ];
      final spread = CaseLawSpread.of(rows);
      expect(spread.map((hit) => hit.esas).take(4), [
        '2014/5760',
        '2014/5761',
        '2013/99',
        '2016/12',
      ]);
    });

    test('a run is spread, never cut', () {
      // Gizlemek en kötü hata: metni okunmadan aynı sayılamaz. Bankada
      // on iki kararlık bir seri iki ayrı gerekçe taşıyordu.
      final rows = [
        for (var n = 8635; n <= 8656; n++) row('2014/$n', date: '24.02.2014'),
      ];
      final spread = CaseLawSpread.of(rows);
      expect(spread.length, rows.length);
      expect(spread.map((hit) => hit.esas).toSet().length, rows.length);
      expect(spread.skip(2).first.esas, '2014/8637', reason: 'sıra korunur');
    });

    test('the same numbers on another day are not one filing', () {
      expect(
        CaseLawSpread.runsIn([
          row('2014/5760'),
          row('2014/5761', date: '04.03.2014'),
        ]),
        isEmpty,
      );
    });

    test('another chamber the same day is not one filing', () {
      expect(
        CaseLawSpread.runsIn([
          row('2014/5760'),
          row('2014/5761', court: '22. Hukuk Dairesi'),
        ]),
        isEmpty,
      );
    });

    test('numbers far apart are separate filings', () {
      expect(
        CaseLawSpread.runsIn([row('2014/5760'), row('2014/5790')]),
        isEmpty,
      );
    });

    test('where there is no run the bank order is left untouched', () {
      final rows = [
        row('2014/10'),
        row('2015/900', date: '01.01.2015'),
        row('2016/3', date: '02.02.2016'),
      ];
      expect(CaseLawSpread.of(rows), same(rows));
    });
  });
}

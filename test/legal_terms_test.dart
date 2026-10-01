import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/legal/legal_terms.dart';

LegalTerms _terms() => LegalTerms.parse(
  File('assets/sozluk/terms.json').readAsStringSync(),
  statutes: File('assets/mevzuat/terms.json').readAsStringSync(),
);

void main() {
  test('Turkish lower case keeps the dotted and dotless i apart', () {
    // Dart'ın kendi lower'ı İ'yi birleşik noktalı i yapıyor ve terim kayboluyor.
    expect(lowerTr('İSTİNAF'), 'istinaf');
    expect(lowerTr('İstinaf'), 'istinaf');
    expect(lowerTr('IRZ'), 'ırz');
    expect(lowerTr('İstinaf').contains('̇'), isFalse);
  });

  test('the shipped dictionary is whole and well formed', () {
    final terms = _terms();
    expect(terms.length, greaterThan(2000));
    // Mevzuatın tanımlar maddesinden asla çıkmayacak olanlar.
    for (final word in ['vedia', 'müstenif', 'muhami', 'tefhim', 'müddeabih']) {
      expect(terms.forWord(word), isNotNull, reason: word);
    }
  });

  test('a term written with İ is found', () {
    // 180 terim bu harfi taşıyor; yanlış katlama hepsini kaybederdi.
    expect(_terms().forWord('İstinaf')?.term, 'İstinaf');
    expect(_terms().forWord('istinaf')?.term, 'İstinaf');
    expect(_terms().forWord('İSTİNAF')?.term, 'İstinaf');
  });

  test('a word carrying a suffix still finds its term', () {
    final terms = _terms();
    expect(terms.forWord('müddeabihi')?.term, 'Müddeabih');
    expect(terms.forWord('tefhiminden')?.term, 'Tefhim');
    // Kaynak terimleri yazdığı gibi saklıyor; kimi büyük, kimi küçük harfle.
    expect(lowerTr(terms.forWord('vediaya')?.term ?? ''), 'vedia');
  });

  test('a softened final consonant is allowed for', () {
    // sanık -> sanığın: son ünsüz ekten önce yumuşuyor.
    final terms = _terms();
    final sanik = terms.forWord('sanık');
    if (sanik != null) {
      expect(terms.forWord('sanığın')?.term, sanik.term);
    }
  });

  test('a short word is not stretched to reach a term', () {
    // Dört harften kısa bir kök neredeyse her kelimeye bir şey buldurur.
    final terms = _terms();
    expect(terms.forWord('a'), isNull);
    expect(terms.forWord('bu'), isNull);
  });

  test('the longest phrase that fits wins', () {
    final terms = _terms();
    final single = terms.forWord('aciz');
    final phrase = terms.forPhrase(['aciz', 'vesikası']);
    expect(single, isNotNull);
    expect(phrase, isNotNull);
    expect(
      phrase!.term,
      isNot(single!.term),
      reason: 'iki kelimelik terim tek kelimeliğe yeğlenmeli',
    );
    expect(phrase.term.toLowerCase(), contains('vesika'));
  });

  test('a clipped entry says so rather than pretending to end', () {
    final terms = _terms();
    final clipped = terms.forWord('acenta');
    expect(clipped, isNotNull);
    expect(
      clipped!.clipped,
      isTrue,
      reason: 'kaynak bu tanımı kesiyor, işaretlenmeli',
    );
  });

  test('a word that is not a term of art finds nothing', () {
    expect(_terms().forWord('bilgisayarcılık'), isNull);
  });

  group('the two sources together', () {
    test('the statutes are shipped and carry their laws', () {
      final terms = _terms();
      expect(terms.statuteLength, greaterThan(200));
      final acik = terms.statutesFor('açık rıza');
      expect(acik, isNotEmpty);
      expect(acik.first.law, contains('6698'));
      expect(acik.first.meaning, contains('özgür iradeyle'));
    });

    test('a word the dictionary has not got is still answered', () {
      // "Açık rıza" kanunun icat ettigi bir terim; sozlukte yok.
      final match = _terms().matchPhrase(['açık', 'rıza']);
      expect(match, isNotNull);
      expect(match!.dictionary, isNull);
      expect(match.statutes, isNotEmpty);
      // Kaynaktaki yazilisiyla adlandirilmali, aranan kelimeyle degil.
      expect(match.term, 'Açık rıza');
    });

    test('a word both sources know brings both', () {
      final match = _terms().matchPhrase(['tüketici']);
      expect(match, isNotNull);
      expect(match!.statutes, isNotEmpty);
      expect(match.isEmpty, isFalse);
    });

    test(
      'one word meaning different things in different laws keeps them all',
      () {
        // Bakanlık sekiz kanunda sekiz ayrı kurum; biri secilip otekilerin adi
        // ona iliştirilirse o kanunlara söylemedikleri şey söyletilmiş olur.
        final found = _terms().statutesFor('bakanlık');
        expect(found.length, greaterThan(1));
        expect(found.map((s) => s.law).toSet().length, found.length);
        expect(found.map((s) => s.meaning).toSet().length, found.length);
      },
    );

    test('a statutory term carrying a suffix is still found', () {
      expect(_terms().statutesFor('tüketicinin'), isNotEmpty);
    });

    test('a compound is not answered with the short word inside it', () {
      // "bilgi" hem sozlukte hem kanunlarda var; "bilgisayarcılık" onun bir
      // cekimi degil, baska bir kelime.
      final terms = _terms();
      expect(terms.matchPhrase(['bilgisayarcılık']), isNull);
      expect(terms.statutesFor('bilgisayarcılık'), isEmpty);
      // Ama gercek bir ek hala bulunmali.
      expect(terms.statutesFor('bilgiyi'), isNotEmpty);
    });

    test('the statutes can be left out entirely', () {
      final alone = LegalTerms.parse(
        File('assets/sozluk/terms.json').readAsStringSync(),
      );
      expect(alone.statuteLength, 0);
      expect(alone.statutesFor('açık rıza'), isEmpty);
      // Sozluk yine de calisir.
      expect(alone.forWord('vedia'), isNotNull);
    });
  });
}

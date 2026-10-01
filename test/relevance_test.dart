import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/legal/relevance.dart';

void main() {
  group('what a decision is worth against a question', () {
    test('a decision on the point beats one that is not', () {
      final onPoint = Relevances.score(
        'iş kazası manevi tazminat',
        'Uyuşmazlık iş kazası nedeniyle manevi tazminat istemine ilişkindir. '
            'Mahkeme iş kazasını ve manevi zararı değerlendirmiştir.',
      );
      final elsewhere = Relevances.score(
        'iş kazası manevi tazminat',
        'Uyuşmazlık kira sözleşmesinin feshi ve tahliye istemidir.',
      );
      expect(onPoint.score, greaterThan(elsewhere.score));
      expect(onPoint.matched, contains('tazminat'));
    });

    test('the words standing together beat the words scattered', () {
      const asked = 'kıdem tazminatı';
      final together = Relevances.score(
        asked,
        'Davacının kıdem tazminatı talebi yerinde görülmüştür.',
      );
      final scattered = Relevances.score(
        asked,
        'Kıdem süresi tartışmalıdır. Başka bir paragrafta tazminat işlenir.',
      );
      expect(together.score, greaterThan(scattered.score));
    });

    test('a word asked to be left out costs the decision that has it', () {
      final without = Relevances.score(
        'tazminat -zamanaşımı',
        'Tazminat istemi kabul edilmiştir.',
      );
      final with_ = Relevances.score(
        'tazminat -zamanaşımı',
        'Tazminat istemi zamanaşımı nedeniyle reddedilmiştir.',
      );
      expect(without.score, greaterThan(with_.score));
    });

    test('repeating one word a hundred times does not win', () {
      final spam = List.filled(500, 'tazminat').join(' ');
      expect(Relevances.score('tazminat', spam).score, lessThanOrEqualTo(150));
    });
  });

  group('the piece shown in the list', () {
    test('it comes from where the words are, not from the top', () {
      final long = '${'A' * 2000} kıdem tazminatı fark alacağı ${'B' * 2000}';
      final found = Relevances.score('kıdem tazminatı', long);
      expect(found.snippet.toLowerCase(), contains('kıdem tazminatı'));
    });
  });

  group('inflection does not hide a match', () {
    test('a plural question finds a singular decision', () {
      final found = Relevances.score(
        'iş kazaları',
        'Davacının iş kazası sonucu maluliyeti söz konusudur.',
      );
      expect(found.matched, hasLength(2), reason: 'hem iş hem kazaları');
      expect(found.score, greaterThan(60));
    });

    test('the same word inflected scores the same', () {
      const text = 'Tazminat talebi; tazminatın hesabı mahkemece yapılır.';
      final inflected = Relevances.score('tazminatın', text).score;
      final plain = Relevances.score('tazminat', text).score;
      expect(plain, greaterThan(0));
      expect((inflected - plain).abs(), lessThan(1));
    });

    test('but two different words still do not merge', () {
      // Over-stripping would answer a search for earnings with an accident.
      final found = Relevances.score('kazanç', 'Trafik kazası raporu okundu.');
      expect(found.matched, isEmpty);
    });
  });

  group('the words that are not the question', () {
    test('question words are not searched for', () {
      // "yargıtay ne diyor" aramasında "ne" ve "diyor" her kararda geçer ve
      // asıl iki kelimeyi boğuyordu.
      expect(Relevances.termsIn('yargıtay ne diyor kira'), [
        'yargıtay',
        'kira',
      ]);
    });

    test('a word written joined is found written apart', () {
      // Kararlar "el atma" ayrı yazar, okuyucu "elatma" bitişik arar.
      expect(Relevances.termsIn('elatma'), ['el', 'atma']);
    });

    test('an excluded word is not also a searched word', () {
      expect(Relevances.termsIn('tazminat -zamanaşımı'), ['tazminat']);
      expect(Relevances.excludedIn('tazminat -zamanaşımı'), ['zamanaşımı']);
    });
  });

  group('which bench decided it', () {
    test('an assembly outranks a chamber, and a chamber the courts below', () {
      expect(Relevances.authorityOf('Hukuk Genel Kurulu', 'YARGITAYKARARI'), 4);
      expect(Relevances.authorityOf('3. Hukuk Dairesi', 'YARGITAYKARARI'), 3);
      expect(Relevances.authorityOf('12. Hukuk Dairesi', 'ISTINAFHUKUK'), 2);
      expect(Relevances.authorityOf('Asliye Hukuk', 'YERELHUKUK'), 1);
    });

    test('it separates equals rather than overruling relevance', () {
      // En yüksek otorite bonusu 12; tek bir terim eşleşmesi bile 24 puan.
      expect(Relevances.authorityBonus(4), lessThan(24));
      expect(Relevances.authorityBonus(1), 0);
    });
  });

  group('a word that is rare among the results', () {
    test('it counts for more than one every result shares', () {
      // Hepsi kamulaştırmaysa sıralamayı belirleyen "faiz" olmalı.
      final bonuses = Relevances.rarityBonuses([
        ['kamulaştırma', 'faiz'],
        ['kamulaştırma'],
        ['kamulaştırma'],
        ['kamulaştırma'],
      ]);
      expect(bonuses.first, greaterThan(bonuses[1]));
      expect(bonuses[1], 0);
    });

    test('too few results to tell rare from common adds nothing', () {
      expect(
        Relevances.rarityBonuses([
          ['a'],
          ['b'],
        ]),
        [0, 0],
      );
    });
  });

  group('the same decision published twice', () {
    test('two copies carry the same mark and two decisions do not', () {
      const one =
          'Davacının kıdem tazminatı talebi yerinde görülmüştür ve '
          'mahkemece kabulüne karar verilmiştir.';
      expect(Relevances.signatureOf(one), Relevances.signatureOf(one));
      expect(
        Relevances.signatureOf(one),
        isNot(Relevances.signatureOf('Kira sözleşmesinin feshine ilişkindir.')),
      );
    });

    test('too little text to judge carries no mark', () {
      expect(Relevances.signatureOf('kısa'), '');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/legal/turkish_stem.dart';

void main() {
  void onlyOne(String name, List<String> words) {
    test('$name: every inflection lands on one stem', () {
      final stems = words.map(TurkishStem.of).toSet();
      expect(
        stems.length,
        1,
        reason: '$words → ${words.map(TurkishStem.of).toList()}',
      );
    });
  }

  group('inflections of one word meet each other', () {
    onlyOne('kaza', ['kaza', 'kazası', 'kazaları', 'kazada', 'kazanın']);
    onlyOne('madde', ['madde', 'maddesi', 'maddede', 'maddenin', 'maddeler']);
    onlyOne('tazminat', [
      'tazminat',
      'tazminatı',
      'tazminata',
      'tazminatın',
      'tazminatlar',
    ]);
    onlyOne('karar', [
      'karar',
      'kararı',
      'kararın',
      'kararda',
      'kararlar',
      'kararların',
    ]);
    onlyOne('dava', [
      'dava',
      'davası',
      'davaya',
      'davayı',
      'davanın',
      'davalar',
    ]);
    onlyOne('sözleşme', [
      'sözleşme',
      'sözleşmesi',
      'sözleşmeler',
      'sözleşmenin',
      'sözleşmesinin',
    ]);
  });

  group('a short word keeps its shape', () {
    test('kanun stays kanun, and never becomes kan', () {
      expect(TurkishStem.of('kanun'), 'kanun');
      expect(TurkishStem.of('kanunu'), 'kanun');
      expect(TurkishStem.of('kanunun'), 'kanun');
    });

    test('dava and kaza are left whole', () {
      expect(TurkishStem.of('dava'), 'dava');
      expect(TurkishStem.of('kaza'), 'kaza');
    });
  });

  group('words that are not the same word do not merge', () {
    // Over-stripping would quietly widen every search: a lawyer looking for
    // "kaza" would be answered with "kazanç".
    test('kaza is not kazanç', () {
      expect(TurkishStem.of('kaza'), isNot(TurkishStem.of('kazanç')));
    });

    test('kara is not karar', () {
      expect(TurkishStem.of('kara'), isNot(TurkishStem.of('karar')));
    });

    test('kanun is not kan', () {
      expect(TurkishStem.of('kanun'), isNot(TurkishStem.of('kan')));
    });
  });
}

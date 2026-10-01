import 'package:evrak_convert/services/editor/text_diff.dart';
import 'package:flutter_test/flutter_test.dart';

String _side(TextDiff diff, DiffKind drop) => diff.pieces
    .where((piece) => piece.kind != drop)
    .map((piece) => piece.text)
    .join();

void main() {
  test('both texts can be read back out of the pieces', () {
    const before = 'Davacı vekili dilekçesinde,\nalacağın tahsilini istemiştir.\n';
    const after =
        'Davacı vekili dava dilekçesinde,\nalacağın faiziyle tahsilini '
        'istemiştir.\nEk: vekaletname\n';
    final diff = TextDiff.between(before, after);
    expect(_side(diff, DiffKind.added), before);
    expect(_side(diff, DiffKind.removed), after);
    expect(diff.addedWords, 4);
    expect(diff.removedWords, 0);
    expect(
      diff.pieces
          .where((piece) => piece.kind == DiffKind.added)
          .map((piece) => piece.text.trim()),
      containsAll(['dava', 'faiziyle', 'Ek: vekaletname']),
    );
  });

  test('a replaced word is one removal and one addition', () {
    final diff = TextDiff.between('Ankara 3. İş Mahkemesi\n', 'Ankara 5. İş Mahkemesi\n');
    expect(diff.removedWords, 1);
    expect(diff.addedWords, 1);
    expect(
      diff.pieces.firstWhere((piece) => piece.kind == DiffKind.removed).text,
      '3',
    );
  });

  test('identical texts, and a missing final line break, are no change', () {
    expect(TextDiff.between('aynı metin\n', 'aynı metin\n').identical, isTrue);
    expect(TextDiff.between('aynı metin', 'aynı metin\n').identical, isTrue);
    expect(TextDiff.between('', '').pieces, isEmpty);
  });

  test('a long document with one edit is compared by its paragraphs', () {
    final paragraphs = [for (var i = 0; i < 3000; i++) 'Paragraf $i metni.'];
    final before = '${paragraphs.join('\n')}\n';
    paragraphs[1500] = 'Paragraf 1500 değişti.';
    final after = '${paragraphs.join('\n')}\n';
    final watch = Stopwatch()..start();
    final diff = TextDiff.between(before, after);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(diff.removedWords, 1);
    expect(diff.addedWords, 1);
    expect(_side(diff, DiffKind.added), before);
    expect(_side(diff, DiffKind.removed), after);
  });

  test('texts with nothing in common are one replacement', () {
    final diff = TextDiff.between('bir iki üç\n', 'dört beş\n');
    expect(diff.removedWords, 3);
    expect(diff.addedWords, 2);
  });
}

import 'package:evrak_convert/services/editor/text_anchor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Boxes for [lines] set one under another on a page 800 points high: every
/// character 6 points wide, every line 14 high, the first at the top.
List<CharBox> _boxes(List<String> lines) {
  final boxes = <CharBox>[];
  for (var row = 0; row < lines.length; row++) {
    final top = 780.0 - row * 14;
    for (var i = 0; i < lines[row].length; i++) {
      boxes.add((
        left: 50.0 + i * 6,
        top: top,
        right: 56.0 + i * 6,
        bottom: top - 12,
      ));
    }
    // The line break the text layer puts between lines has no box.
    if (row < lines.length - 1) {
      boxes.add((left: 0, top: 0, right: 0, bottom: 0));
    }
  }
  return boxes;
}

void main() {
  const document =
      'İSTANBUL ANADOLU 3. İŞ MAHKEMESİNE\n'
      'DAVACI: Ayşe Yılmaz\n'
      'AÇIKLAMALAR\n'
      'Müvekkil işyerinde 2019 yılından beri çalışmaktadır ve ücreti '
      'düzenli ödenmemiştir.\n'
      'Davalı işveren fesih bildiriminde bulunmamıştır.\n'
      'SONUÇ VE İSTEM\n'
      'Davanın kabulüne karar verilmesini saygıyla arz ederim.\n';

  test('a line is found whatever the drawing did to its spaces and breaks, '
      'and the caret goes to the letter pointed at', () {
    // The paragraph drawn over two lines, a gap doubled by justification.
    const line = 'yılından  beri çalışmaktadır ve ücreti';
    final anchor = TextAnchor(
      page: 1,
      pages: 1,
      down: .4,
      line: line,
      at: line.indexOf('beri'),
    );
    expect(document.substring(anchor.locate(document)), startsWith('beri '));
  });

  test('a list mark the drawing added is looked past', () {
    const line = '•  Davalı işveren fesih bildiriminde bulunmamıştır.';
    final anchor = TextAnchor(
      page: 1,
      pages: 1,
      down: .6,
      line: line,
      at: line.indexOf('işveren'),
    );
    expect(document.substring(anchor.locate(document)), startsWith('işveren'));
  });

  test('a line that is not in the text as drawn is found by the letters '
      'around the pointer', () {
    const line = 'Sayfa 1 — Müvekkil işyerinde 2019 yılından beri';
    final anchor = TextAnchor(
      page: 1,
      pages: 1,
      down: .5,
      line: line,
      at: line.indexOf('2019'),
    );
    expect(document.substring(anchor.locate(document)), startsWith('2019'));
  });

  test('of a line written twice, the one about as far down as the page '
      'is taken', () {
    final text = List.generate(40, (i) => 'Paragraf ${i + 1}\nTekrar\n').join();
    String before(TextAnchor anchor) => text.substring(0, anchor.locate(text));
    expect(
      before(const TextAnchor(page: 1, pages: 4, line: 'Tekrar')),
      'Paragraf 1\n',
    );
    // Five eighths of the way in: about the twenty-fifth of forty.
    final middle = before(
      const TextAnchor(page: 3, pages: 4, down: .5, line: 'Tekrar'),
    );
    expect(middle, contains('Paragraf 25\n'));
    expect(middle, isNot(contains('Paragraf 28\n')));
    expect(
      before(const TextAnchor(page: 4, pages: 4, down: 1, line: 'Tekrar')),
      endsWith('Paragraf 40\n'),
    );
  });

  test('a line written the same way in many places is told apart by the '
      'lines around it, not by how far down the page it is', () {
    final text = List.generate(
      30,
      (i) => 'Madde ${i + 1} hükmü uygulanır.\nSaygılarımla arz ederim.\n',
    ).join();
    // Near the top of the last page, where the page alone would point at
    // far less than the end of the text.
    const anchor = TextAnchor(
      page: 3,
      pages: 3,
      down: .05,
      line: 'Saygılarımla arz ederim.',
      before: 'Saygılarımla arz ederim.\nMadde 27 hükmü uygulanır.',
      after: 'Madde 28 hükmü uygulanır.',
    );
    final at = anchor.locate(text);
    expect(text.substring(0, at), endsWith('Madde 27 hükmü uygulanır.\n'));
    expect(text.substring(at), startsWith('Saygılarımla'));
  });

  test(
    'where nothing matches, the start of the line as far in as the page',
    () {
      final text = List.generate(10, (i) => 'Satır numarası $i\n').join();
      const anchor = TextAnchor(
        page: 2,
        pages: 2,
        down: 0,
        line: 'Sayfa 2 / 2',
      );
      final at = anchor.locate(text);
      expect(at, closeTo(text.length / 2, 20));
      expect(text[at - 1], '\n');
      expect(const TextAnchor(page: 1, pages: 1).locate(text), 0);
      expect(const TextAnchor(page: 1, pages: 1).locate(''), 0);
    },
  );

  test('on a page, the line under the pointer and the letter on it are read '
      'from the text layer', () {
    const lines = ['DAVACI: Ayşe Yılmaz', 'AÇIKLAMALAR', 'Müvekkil işyerinde'];
    final text = lines.join('\n');
    final boxes = _boxes(lines);
    // Over the fourth letter of the second line.
    final anchor = TextAnchor.onPage(
      page: 2,
      pages: 3,
      height: 800,
      x: 50 + 3 * 6 + 2,
      y: 780 - 14 - 6,
      text: text,
      boxes: boxes,
    );
    expect(anchor.line, 'AÇIKLAMALAR');
    expect(anchor.at, 3);
    expect(anchor.page, 2);
    expect(anchor.down, closeTo(.05, .001));

    // Past the end of the first line: its last letter.
    final after = TextAnchor.onPage(
      page: 1,
      pages: 1,
      height: 800,
      x: 400,
      y: 775,
      text: text,
      boxes: boxes,
    );
    expect(after.line, 'DAVACI: Ayşe Yılmaz');
    expect(after.at, lines.first.length - 1);

    // Far below every line: only the page.
    final blank = TextAnchor.onPage(
      page: 1,
      pages: 1,
      height: 800,
      x: 60,
      y: 100,
      text: text,
      boxes: boxes,
    );
    expect(blank.line, isEmpty);
    expect(blank.down, closeTo(.875, .001));
  });
}

import 'package:evrak_convert/services/ocr/ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tesseract's TSV: a header, then one row per page, block, paragraph, line
/// and word; only level-5 rows are words, and non-word rows carry conf -1.
String tsv(List<(int, int, int, int, double, String)> words) {
  final rows = [
    'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop'
        '\twidth\theight\tconf\ttext',
    '1\t1\t0\t0\t0\t0\t0\t0\t1654\t2339\t-1\t',
    for (final (block, par, line, height, conf, text) in words)
      '5\t1\t$block\t$par\t$line\t1\t10\t10\t50\t$height\t$conf\t$text',
  ];
  return rows.join('\n');
}

void main() {
  test('text keeps lines and paragraphs as Tesseract writes them', () {
    final page = OcrPageRead.fromTsv(
      tsv([
        (1, 1, 1, 30, 96, 'DAVACI'),
        (1, 1, 1, 30, 95, ':'),
        (1, 1, 2, 30, 93, 'Ayşe'),
        (1, 2, 1, 30, 90, 'Açıklamalar'),
      ]),
    );
    expect(page.text, 'DAVACI :\nAyşe\n\nAçıklamalar');
    expect(page.words, 4);
    // ':' is not a word and 'Ayşe' is; three letters or more, with letters.
    expect(page.good, 3);
    expect(page.confidence, closeTo(93.5, .01));
    expect(page.wordHeight, 30);
  });

  test('a confident page of ordinary print is read once', () {
    final page = OcrPageRead.fromTsv(
      tsv([for (var i = 0; i < 20; i++) (1, 1, i, 25, 93, 'dilekçe')]),
    );
    expect(page.retryDpi(200), isNull);
  });

  test('small print is read again enlarged, within 150 to 400 dpi', () {
    final small = OcrPageRead.fromTsv(
      tsv([for (var i = 0; i < 20; i++) (1, 1, i, 15, 92, 'tutanak')]),
    );
    // 200 × 40.5 / 15 = 540, kept to 400.
    expect(small.retryDpi(200), 400);
    final middling = OcrPageRead.fromTsv(
      tsv([for (var i = 0; i < 20; i++) (1, 1, i, 17, 92, 'tutanak')]),
    );
    expect(middling.retryDpi(200), 400);
    // Some words read surely at 60 px, the rest poorly: unsure overall.
    final large = OcrPageRead.fromTsv(
      tsv([
        for (var i = 0; i < 10; i++) (1, 1, i, 60, 90, 'BAŞLIK'),
        for (var i = 10; i < 20; i++) (1, 1, i, 60, 50, 'BAŞLIK'),
      ]),
    );
    expect(large.wordHeight, 60);
    // Unsure, and large: drawn smaller, not below 150.
    expect(large.retryDpi(200), 150);
  });

  test('an unsure page with nothing read confidently is retried as is', () {
    final page = OcrPageRead.fromTsv(
      tsv([for (var i = 0; i < 10; i++) (1, 1, i, 30, 40, 'xq')]),
    );
    expect(page.good, 0);
    expect(page.retryDpi(200), 200);
  });

  test('a blank page is not read twice', () {
    final page = OcrPageRead.fromTsv(tsv(const []));
    expect(page.text, isEmpty);
    expect(page.retryDpi(200), isNull);
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/pdf/pdf_service.dart';

import 'support/pdf_readback.dart';

/// The preview is laid out by UYAP's rules, which were read off UYAP itself
/// (see ParagraphRows); these check that the PDF it draws keeps them. Letters
/// are placed by their ink, so positions hold to about half a point.
void main() {
  const margin = 42.525;
  final font = PdfTtfFont(
    PdfDocument(),
    ByteData.sublistView(
      File('fonts/pdf/LiberationSerif-Regular.ttf').readAsBytesSync(),
    ),
  );
  double width(String text) => font.stringMetrics(text).advanceWidth * 12;
  const long =
      'Davacı ile müvekkil arasında imzalanan sözleşme gereğince yapılan '
      'ödemelerin iadesi talep edilmiş olup mahkemece yapılan yargılama '
      'sonucunda davanın kısmen kabulüne karar verilmiştir ve bu karar usul '
      've yasaya aykırıdır.';

  Future<PdfReadback> draw(
    WidgetTester tester,
    List<DocBlock> blocks, {
    Map<String, dynamic> metadata = const {'formatId': '1.8'},
  }) async {
    final bytes = await tester.runAsync(
      () => PdfService.modelToPdfBytes(
        DocModel(blocks: blocks, metadata: metadata),
      ),
    );
    return (await tester.runAsync(() => PdfReadback.of(bytes!)))!;
  }

  testWidgets('past the last stop a tab moves five points', (tester) async {
    // Not to another stop an inch on: UYAP moved C five points past the
    // whole point B ended on.
    final pdf = await draw(tester, [
      DocBlock(plainText: 'Ad\tB\tC', tabSet: '50.0:0:0'),
    ]);
    expect(pdf.start('B').$1, closeTo(margin + 50, .6));
    final c = (50 + width('B')).roundToDouble() + 5;
    expect(pdf.start('C').$1, closeTo(margin + c, .6));
  });

  testWidgets('a centre stop centres the text on it', (tester) async {
    // The court's name in a filing's heading, centred on a stop at 67.
    final pdf = await draw(tester, [
      DocBlock(plainText: '\tMANAVGAT', tabSet: '67.0:2:0'),
    ]);
    expect(
      pdf.start('MANAVGAT').$1,
      closeTo(margin + 67 - width('MANAVGAT') / 2, .6),
    );
  });

  testWidgets('a justified first line starts right at its indent', (
    tester,
  ) async {
    // The preview used to spread room between the indent and the first word
    // too. UYAP keeps indents in whole points: 35.4375 is drawn at 35.
    final pdf = await draw(tester, [
      DocBlock(
        plainText: long,
        alignment: DocAlignment.justify,
        firstLineIndent: 35.4375,
      ),
    ]);
    expect(pdf.start('Davacı').$1, closeTo(margin + 35, .6));
  });

  testWidgets('a hanging indent carries the rows after the first', (
    tester,
  ) async {
    const text = 'DAVACI\t: $long';
    final pdf = await draw(tester, [
      DocBlock(plainText: text, tabSet: '150.0:0:0', hanging: 160),
    ]);
    // A colon's ink starts about a point after its pen.
    expect(pdf.start(':').$1, closeTo(margin + 150, 1.2));
    // Somewhere past the first row every word starts at or beyond 160.
    final first = pdf.start('DAVACI');
    final wrapped = pdf.start('verilmiştir');
    expect(wrapped.$2, greaterThan(first.$2));
    expect(pdf.start('aykırıdır.').$1, greaterThanOrEqualTo(margin + 159.5));
  });

  testWidgets('a line break inside a UDF paragraph is not drawn', (
    tester,
  ) async {
    // UYAP draws "KONU\t:\n İtirazın…" as one line; so does the preview.
    final udf = await draw(tester, [
      DocBlock(plainText: 'Birinci satır\nİkinci satır'),
    ]);
    expect(udf.start('İkinci').$2, closeTo(udf.start('Birinci').$2, .5));
    // A Word document's own line break does break.
    final word = await draw(
      tester,
      [DocBlock(plainText: 'Birinci satır\nİkinci satır')],
      metadata: const {'tabRules': 'word', 'defaultTabStop': 35.4},
    );
    expect(word.start('İkinci').$2, greaterThan(word.start('Birinci').$2));
  });

  testWidgets('an em space keeps its width', (tester) async {
    // Twelve points at twelve point; the pdf package drew it as a plain space.
    final pdf = await draw(tester, [DocBlock(plainText: 'A\u2003B')]);
    expect(pdf.start('B').$1, closeTo(margin + width('A') + 12, .6));
  });
}

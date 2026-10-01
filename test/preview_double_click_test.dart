import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/editor/text_anchor.dart';
import 'package:evrak_convert/services/pdf/pdf_service.dart';
import 'package:evrak_convert/services/pdf/pdfium_setup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'support/pdfium.dart';

String _paragraph(int n) =>
    'Paragraf $n: davalı işveren, müvekkilin $n. ay ücretini bildirilen '
    'tarihte ödememiş, fazla çalışma karşılığını da hesaplamamıştır; bu '
    'nedenle alacağın faiziyle birlikte tahsiline karar verilmelidir.';

void main() {
  // The export reads its fonts from the asset bundle. A plain test rather
  // than testWidgets: pdfrx answers from a worker isolate, which the widget
  // tester's fake clock never lets through.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a double-click on the page the preview draws finds the same word in '
      'the text the editor holds, on a wrapped line too', () async {
    // flutter_tester has no PDFium of its own; the built bundle does.
    final bundled = pdfiumLibrary();
    if (bundled == null) {
      markTestSkipped('paketlenmiş PDFium yok');
      return;
    }
    PdfiumSetup.pathOverride = bundled;
    addTearDown(() => PdfiumSetup.pathOverride = null);
    expect(await PdfiumSetup.ensure(), isTrue);

    final model = DocModel(
      blocks: [for (var n = 1; n <= 40; n++) DocBlock(plainText: _paragraph(n))],
    );
    // What the editor holds: a line per paragraph.
    final plain = model.blocks.map((b) => b.plainText).join('\n');
    final document = await PdfDocument.openData(
      await PdfService.modelToPdfBytes(model),
    );
    addTearDown(document.dispose);
    expect(document.pages.length, greaterThan(1));

    /// Double-clicks the middle of [word] in paragraph [n], wherever the
    /// drawing put it, and answers the paragraph and word the anchor finds.
    Future<(int, String)> click(int n, String word) async {
      for (final page in document.pages) {
        final text = await page.loadText();
        if (text == null) continue;
        final start = text.fullText.indexOf('Paragraf $n:');
        if (start < 0) continue;
        final at = text.fullText.indexOf(word, start);
        final box = text.charRects[at + word.length ~/ 2];
        final anchor = TextAnchor.onPage(
          page: page.pageNumber,
          pages: document.pages.length,
          height: page.height,
          x: (box.left + box.right) / 2,
          y: (box.top + box.bottom) / 2,
          text: text.fullText,
          boxes: [
            for (final r in text.charRects)
              (left: r.left, top: r.top, right: r.right, bottom: r.bottom),
          ],
        );
        final found = anchor.locate(plain);
        final paragraph = int.parse(
          RegExp(r'Paragraf (\d+):')
              .allMatches(plain.substring(0, found + 1))
              .last
              .group(1)!,
        );
        final end = plain.indexOf(RegExp(r'[\s,;.]'), found);
        final letters = plain.substring(
          plain.lastIndexOf(RegExp(r'[\s,;.]'), found) + 1,
          end < 0 ? plain.length : end,
        );
        return (paragraph, letters);
      }
      fail('Paragraf $n çizilen sayfalarda yok');
    }

    // The start of a paragraph, the words after its first line break, and
    // the end of it — on the first page and on a later one.
    expect(await click(3, 'davalı'), (3, 'davalı'));
    expect(await click(3, 'hesaplamamıştır'), (3, 'hesaplamamıştır'));
    expect(await click(3, 'verilmelidir'), (3, 'verilmelidir'));
    expect(await click(31, 'ücretini'), (31, 'ücretini'));
    expect(await click(31, 'tahsiline'), (31, 'tahsiline'));
  });
}

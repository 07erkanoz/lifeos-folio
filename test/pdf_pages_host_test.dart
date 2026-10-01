import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'package:evrak_convert/services/ocr/ocr_service.dart';
import 'package:evrak_convert/services/pdf/pdf_pages.dart';
import 'package:evrak_convert/services/search/text_extractor.dart';

import 'support/pdfium.dart';

/// One page set in Tahoma without embedding it, so PDFium has to ask the
/// font mapper pdfrx installed — the callback that belongs to one isolate.
Uint8List unembeddedFontPdf() {
  const content = 'BT /F1 12 Tf 72 720 Td (Davaci vekili dilekcesi) Tj ET';
  return Uint8List.fromList(
    ('%PDF-1.4\n'
            '1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n'
            '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n'
            '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 595 842]'
            '/Resources<</Font<</F1 4 0 R>>>>/Contents 5 0 R>>endobj\n'
            '4 0 obj<</Type/Font/Subtype/TrueType/BaseFont/Tahoma'
            '/Encoding/WinAnsiEncoding/FirstChar 32/LastChar 126>>endobj\n'
            '5 0 obj<</Length ${content.length}>>stream\n$content\n'
            'endstream endobj\n'
            'trailer<</Root 1 0 R>>\n%%EOF\n')
        .codeUnits,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  configurePdfiumForTest();

  late File file;
  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('pdf-pages-host-');
    addTearDown(() => dir.delete(recursive: true));
    file = File('${dir.path}/dilekce.pdf')
      ..writeAsBytesSync(unembeddedFontPdf());
  });

  test('indexing a PDF leaves the preview able to open one', () async {
    // This isolate plays the interface, with pdfrx as the previews use it.
    await pdfrxInitialize();
    final host = PdfPagesHost.start();

    // The indexer's isolate reads through the host. Before, it started pdfrx
    // of its own, whose font mapper replaced this one's, and the page opened
    // below aborted the whole process.
    final indexed = await Isolate.run(() async {
      PdfPages.host = host;
      return (await IndexTextExtractor.extract(file.path))['text'];
    });
    expect(indexed, contains('Davaci vekili'));

    final document = await PdfDocument.openFile(file.path);
    addTearDown(document.dispose);
    final page = document.pages.first;
    expect((await page.loadText())?.fullText, contains('dilekcesi'));
    final image = await page.render(width: 100, height: 140);
    expect(image, isNotNull);
    image!.dispose();
  });

  test('pages for OCR are drawn by the host and come back whole', () async {
    final host = PdfPagesHost.start();
    final drawn = await Isolate.run(() async {
      PdfPages.host = host;
      final document = await PdfPages.open(file.path);
      try {
        final (width, height) = document.sizes.single;
        final pixels = await document.render(
          0,
          (width * OcrService.renderDpi / 72).round(),
          (height * OcrService.renderDpi / 72).round(),
        );
        return (
          width: pixels!.width,
          height: pixels.height,
          bytes: pixels.bgra.length,
          ink: pixels.bgra.any((value) => value < 128),
        );
      } finally {
        await document.close();
      }
    });
    // A4 at 200 dpi, four bytes a pixel, and the words drawn on it.
    expect(drawn.width, 1653);
    expect(drawn.height, 2339);
    expect(drawn.bytes, 1653 * 2339 * 4);
    expect(drawn.ink, isTrue);
  });
}

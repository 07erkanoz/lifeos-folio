import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/convert/converter_service.dart';
import 'package:evrak_convert/services/editor/doc_delta_map.dart';
import 'package:evrak_convert/services/pdf/pdf_native_reader.dart';
import 'package:evrak_convert/services/pdf/pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/styled_pdf.dart';
import 'support/pdfium.dart';

DocSpan spanOf(DocModel model, String word) {
  final block = model.blocks.firstWhere((b) => b.plainText.contains(word));
  final at = block.plainText.indexOf(word);
  return block.spans.firstWhere((s) => s.startOffset <= at && s.endOffset > at);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  configurePdfiumForTest();
  test(
    'PDF font, size and mixed emphasis survive into Quill and back',
    () async {
      final model = (await ConverterService.extractDocModel(
        await styledPdf(),
        EvrakFormat.pdf,
      ))!;
      final title = spanOf(model, 'Bold');
      expect(title.fontFamily, 'Helvetica');
      expect(title.fontSize, closeTo(20, .1));
      expect(title.bold, isTrue);
      expect(spanOf(model, 'Normal').bold, isFalse);
      expect(spanOf(model, 'Normal').fontFamily, 'Times New Roman');
      expect(spanOf(model, 'Italic').italic, isTrue);
      expect(spanOf(model, 'Italic').fontFamily, 'Courier');
      final restored = DocDeltaMap.deltadanModel(
        DocDeltaMap.modeldenDelta(model).delta,
      );
      expect(spanOf(restored, 'Bold').bold, isTrue);
      expect(spanOf(restored, 'Italic').italic, isTrue);
    },
  );

  test(
    'file import gets text and styles from the same PDFium character stream',
    () async {
      final directory = await Directory.systemTemp.createTemp('styled-pdf-');
      addTearDown(() => directory.delete(recursive: true));
      final file = await File('${directory.path}/source.pdf')
          .writeAsBytes(await styledPdf());
      const text = '  Bold title\n\nNormal      Italic\n';
      final model = (await ConverterService.extractFileDocModel(
        file.path,
        EvrakFormat.pdf,
        extractedPdfText: text,
      ))!;
      expect(model.toPlainText(), contains('Bold title'));
      expect(model.toPlainText(), contains('Italic'));
      expect(spanOf(model, 'Bold').bold, isTrue);
      expect(spanOf(model, 'Italic').italic, isTrue);
    },
  );

  test('image-only PDF still requests OCR', () async {
    await expectLater(
      PdfNativeReader.read(await emptyPdf()),
      throwsFormatException,
    );
  });

  test(
    'a PDF over 1 MB with embedded fonts is read, not the app brought down',
    () async {
      // Over 1 MB pdfrx opens a document through a read callback owned by its
      // PDFium isolate. Reading it from any other isolate made the VM abort
      // the process, so converting or editing such a PDF closed the app. Every
      // PDF these tests used was far below the threshold.
      // The words need an embedded TrueType font — what real filings carry,
      // and what PDFium fetches through that callback when it reads the page —
      // and the file has to pass 1 MB, which a picture of noise makes sure of.
      final random = math.Random(7);
      final noise = img.Image(width: 700, height: 700);
      for (final pixel in noise) {
        pixel
          ..r = random.nextInt(256)
          ..g = random.nextInt(256)
          ..b = random.nextInt(256);
      }
      final bytes = await PdfService.modelToPdfBytes(
        DocModel(
          blocks: [
            DocBlock(
              type: DocBlockType.image,
              plainText: '',
              imageBase64: base64Encode(img.encodePng(noise)),
              imageWidth: 400,
              imageHeight: 400,
            ),
            for (var i = 0; i < 40; i++)
              DocBlock(plainText: 'Davacı vekili dilekçesi $i'),
          ],
        ),
      );
      expect(
        bytes.length,
        greaterThan(1 << 20),
        reason: 'eşiğin üstünde olmalı',
      );

      final directory = await Directory.systemTemp.createTemp('large-pdf-');
      addTearDown(() => directory.delete(recursive: true));
      final file = await File('${directory.path}/large.pdf')
          .writeAsBytes(bytes);
      final model = (await ConverterService.extractFileDocModel(
        file.path,
        EvrakFormat.pdf,
      ))!;
      expect(model.toPlainText(), contains('vekili'));
    },
  );
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/pdf/pdf_service.dart';
import 'package:evrak_convert/services/pdf/pdfium_setup.dart';
import 'package:evrak_convert/services/search/index_database.dart';
import 'package:evrak_convert/services/search/text_extractor.dart';

import 'support/pdfium.dart';

void main() {
  // The export reads its fonts from the asset bundle. A plain test rather
  // than testWidgets: pdfrx answers from a worker isolate, which the widget
  // tester's fake clock never lets through.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a PDF is indexed through PDFium, Turkish letters intact', () async {
    // flutter_tester has no PDFium of its own; the built bundle does.
    final bundled = pdfiumLibrary();
    if (bundled == null) {
      markTestSkipped('paketlenmiş PDFium yok');
      return;
    }
    PdfiumSetup.pathOverride = bundled;
    addTearDown(() => PdfiumSetup.pathOverride = null);
    expect(await PdfiumSetup.ensure(), isTrue);

    final bytes = await PdfService.modelToPdfBytes(
      DocModel(
        blocks: [
          DocBlock(plainText: 'Davacının açtığı boşanma davası'),
          DocBlock(plainText: 'İŞ MAHKEMESİNE ŞIK ÇÖZÜM'),
        ],
      ),
    );
    final dir = await Directory.systemTemp.createTemp('folio-pdf-text-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/dilekce.pdf');
    await file.writeAsBytes(bytes);

    final result = await IndexTextExtractor.extract(file.path);
    expect(result['state'], 'ready');
    final text = result['text'] as String;
    expect(text, contains('açtığı boşanma'));
    expect(text, contains('MAHKEMESİNE'));
    // Syncfusion wrote these in place of Turkish letters in 93 of 311 real
    // PDFs; a word spelled that way is one no search finds.
    expect(text, isNot(matches(RegExp('breve|cedilla|dotaccent|dieresis'))));
  });

  test('PDFs read by the old reader are queued again, scans are not', () async {
    final dir = await Directory.systemTemp.createTemp('folio-pdf-requeue-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/index.sqlite';
    var db = IndexDatabase(path);
    final source = db.addSource('/arsiv', true, true);
    int row(String name, String text, String state, {bool ocr = false}) {
      final id = db.registerFile(
        sourceId: source,
        token: 1,
        path: '/arsiv/$name',
        size: 10,
        modified: 1,
        changed: 1,
        changedContent: true,
      );
      db.setContent(id, text, state, null, ocr: ocr);
      return id;
    }

    row('dilekce.pdf', 'oldugbreveu', 'ready');
    row('iddianame.pdf', '', 'error');
    row('taranmis.pdf', 'MAHKEMESİ', 'ready', ocr: true);
    row('bos.pdf', '', 'no_text');
    row('dilekce.udf', 'olduğu', 'ready');
    db.db.execute('PRAGMA user_version=9');
    db.close();

    db = IndexDatabase(path);
    addTearDown(db.close);
    String state(String name) =>
        db.db.select('SELECT state FROM documents WHERE path=?', [
              '/arsiv/$name',
            ]).first['state']
            as String;
    expect(state('dilekce.pdf'), 'pending');
    expect(state('iddianame.pdf'), 'pending');
    expect(state('taranmis.pdf'), 'ready', reason: 'OCR yeniden koşmamalı');
    expect(state('bos.pdf'), 'no_text', reason: 'OCR yeniden koşmamalı');
    expect(state('dilekce.udf'), 'ready');
  });
}

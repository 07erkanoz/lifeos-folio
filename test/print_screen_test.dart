import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import 'package:evrak_convert/services/print/print_job.dart';
import 'package:evrak_convert/services/print/print_selection.dart';
import 'package:evrak_convert/ui/widgets/print_screen.dart';

import 'support/pdfium.dart';

/// A PDF of [count] pages, each saying which it is.
Future<Uint8List> pages(int count) async {
  final doc = pw.Document();
  for (var i = 1; i <= count; i++) {
    doc.addPage(pw.Page(build: (_) => pw.Text('Sayfa numarasi $i')));
  }
  return doc.save();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  configurePdfiumForTest();

  group('which pages', () {
    test('a range reads as Word reads one', () {
      expect(PrintSelection.parse('1-3, 5', 8), [1, 2, 3, 5]);
      expect(PrintSelection.parse('6-', 8), [6, 7, 8]);
      expect(PrintSelection.parse('-2;4', 8), [1, 2, 4]);
      expect(PrintSelection.parse(' 2 ', 8), [2]);
      // A page the document does not have, or nothing at all.
      expect(PrintSelection.parse('9', 8), isNull);
      expect(PrintSelection.parse('3-1', 8), isNull);
      expect(PrintSelection.parse('a', 8), isNull);
      expect(PrintSelection.parse('', 8), isNull);
    });

    test('all, the current page, or a range, then odd or even ones', () {
      expect(PrintSelection.pages(pageCount: 5, which: PrintPages.all), [
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(
        PrintSelection.pages(
          pageCount: 5,
          which: PrintPages.current,
          current: 4,
        ),
        [4],
      );
      expect(
        PrintSelection.pages(
          pageCount: 5,
          which: PrintPages.all,
          parity: PrintParity.even,
        ),
        [2, 4],
      );
      expect(
        PrintSelection.pages(
          pageCount: 5,
          which: PrintPages.custom,
          range: '2-5',
          parity: PrintParity.odd,
        ),
        [3, 5],
      );
    });

    test('copies come collated, or each page together', () {
      expect(PrintSelection.sheets([1, 2], copies: 2), [1, 2, 1, 2]);
      expect(PrintSelection.sheets([1, 2], copies: 2, collate: false), [
        1,
        1,
        2,
        2,
      ]);
    });
  });

  test('the chosen pages are taken out of the PDF as they are', () async {
    await pdfrxInitialize();
    final out = await PrintJob.extract(await pages(3), [3, 1, 1]);
    final document = await PdfDocument.openData(out);
    addTearDown(document.dispose);
    expect(document.pages.length, 3);
    final first = await document.pages.first.loadText();
    expect(first?.fullText, contains('Sayfa numarasi 3'));
    final second = await document.pages[1].loadText();
    expect(second?.fullText, contains('Sayfa numarasi 1'));
  });

  testWidgets('the screen shows the pages and what a range prints', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(pdfrxInitialize);
    final pdf = (await tester.runAsync(() => pages(5)))!;
    final document = (await tester.runAsync(() => PdfDocument.openData(pdf)))!;
    addTearDown(document.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrintScreen(pdf: pdf, name: 'dilekce.udf', document: document),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Tüm sayfalar (5)'), findsOneWidget);
    expect(find.text('1 / 5'), findsOneWidget);
    expect(find.text('5 sayfa · 5 yaprak A4'), findsOneWidget);

    await tester.tap(find.text('Sayfa aralığı'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('print-range')), '2-3');
    await tester.pump();
    expect(find.text('2 sayfa · 2 yaprak A4'), findsOneWidget);
    // Page 1 is shown, and is not among them.
    expect(find.text('Yazdırılmayacak'), findsOneWidget);
    await tester.tap(find.byTooltip('Sonraki sayfa'));
    await tester.pump();
    expect(find.text('2 / 5'), findsOneWidget);
    expect(find.text('Yazdırılmayacak'), findsNothing);

    // Two copies: four sheets.
    await tester.tap(find.byTooltip('Bir kopya fazla'));
    await tester.pump();
    expect(find.text('2 sayfa × 2 kopya · 4 yaprak A4'), findsOneWidget);
    expect(find.text('Harmanla'), findsOneWidget);

    // A page the document does not have.
    await tester.enterText(find.byKey(const ValueKey('print-range')), '9');
    await tester.pump();
    expect(
      find.text('Belgede 5 sayfa var; aralığı kontrol edin.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
}

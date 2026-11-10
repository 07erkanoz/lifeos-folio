import 'dart:io';
import 'dart:typed_data';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/pdf/pdf_service.dart';
import 'package:evrak_convert/services/pdf/pdf_tools.dart';
import 'package:evrak_convert/services/pdf/pdfium_setup.dart';
import 'package:evrak_convert/l10n/gen/app_localizations.dart';
import 'package:evrak_convert/ui/widgets/pdf_tools_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

import 'support/pdfium.dart';

// PDFs put together from what the lawyer has: pictures as pages, chosen
// pages of a PDF as a PDF of their own, and both mixed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('folio-pdf-araci-'));
  tearDown(() => dir.deleteSync(recursive: true));

  String picture(String name, int width, int height, {bool png = false}) {
    final image = img.Image(width: width, height: height)
      ..clear(img.ColorRgb8(240, 240, 240));
    final file = File('${dir.path}/$name')
      ..writeAsBytesSync(png ? img.encodePng(image) : img.encodeJpg(image));
    return file.path;
  }

  Future<bool> pdfium() async {
    final bundled = pdfiumLibrary();
    if (bundled == null) {
      markTestSkipped('paketlenmiş PDFium yok');
      return false;
    }
    PdfiumSetup.pathOverride = bundled;
    addTearDown(() => PdfiumSetup.pathOverride = null);
    return PdfiumSetup.ensure();
  }

  Future<List<(double, double)>> sizes(Uint8List pdf) async {
    final document = await PdfDocument.openData(pdf);
    try {
      return [for (final page in document.pages) (page.width, page.height)];
    } finally {
      await document.dispose();
    }
  }

  test('page ranges read and written', () {
    expect(PdfTools.parseRanges('1-3, 5', 10), [1, 2, 3, 5]);
    expect(PdfTools.parseRanges('5 2 2', 10), [5, 2]);
    expect(PdfTools.parseRanges('3–4', 10), [3, 4]);
    expect(PdfTools.parseRanges('0', 10), isNull);
    expect(PdfTools.parseRanges('9-11', 10), isNull);
    expect(PdfTools.parseRanges('iki', 10), isNull);
    expect(PdfTools.parseRanges('', 10), isNull);
    expect(PdfTools.formatRanges([5, 1, 2, 3, 8, 9]), '1-3, 5, 8-9');
  });

  test('a JPEG\'s frame is read from its header', () {
    final jpeg = File(picture('a.jpg', 300, 200)).readAsBytesSync();
    expect(PdfTools.jpegFrame(jpeg), (width: 300, height: 200, components: 3));
    expect(PdfTools.jpegFrame(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });

  test(
    'pictures become pages: a standing one A4 wide, a lying one on a '
    'lying sheet, a photograph kept as it is, a large one made smaller',
    () async {
      if (!await pdfium()) return;
      final standing = picture('dik.jpg', 600, 800);
      final lying = picture('yatik.png', 800, 400, png: true);
      final large = picture('buyuk.jpg', 5000, 2500);
      final pdf = await PdfTools.fromImages([standing, lying, large]);
      final pages = await sizes(pdf);
      expect(pages, hasLength(3));
      expect(pages[0].$1, closeTo(595.28, .5));
      expect(pages[0].$2, closeTo(595.28 * 800 / 600, .5));
      expect(pages[1].$1, closeTo(841.89, .5));
      expect(pages[1].$2, closeTo(841.89 / 2, .5));
      // The small photograph's own bytes are in the file; the large one's
      // are not, and it weighs less than it did.
      final small = File(standing).readAsBytesSync();
      expect(_contains(pdf, small), isTrue);
      expect(pdf.length, lessThan(File(large).lengthSync() + small.length * 4));
    },
  );

  test('chosen pages of a PDF are a PDF of their own, in the order asked; '
      'pictures and pages mix', () async {
    if (!await pdfium()) return;
    final source = await PdfService.modelToPdfBytes(
      DocModel(
        blocks: [
          DocBlock(plainText: 'Birinci'),
          DocBlock(plainText: 'İkinci', pageBreakBefore: true),
          DocBlock(plainText: 'Üçüncü', pageBreakBefore: true),
        ],
      ),
    );
    Future<List<String>> texts(Uint8List pdf) async {
      final document = await PdfDocument.openData(pdf);
      try {
        return [
          for (final page in document.pages)
            (await page.loadText())?.fullText.trim() ?? '',
        ];
      } finally {
        await document.dispose();
      }
    }

    expect(await texts(source), ['Birinci', 'İkinci', 'Üçüncü']);
    expect(await texts(await PdfTools.extract(source, [3, 1])), [
      'Üçüncü',
      'Birinci',
    ]);

    final file = File('${dir.path}/belge.pdf')..writeAsBytesSync(source);
    final mixed = await PdfTools.build([
      PdfPart(picture('kapak.jpg', 600, 800)),
      PdfPart(file.path, pages: const [2]),
      PdfPart(file.path),
    ]);
    expect(await texts(mixed), ['', 'İkinci', 'Birinci', 'İkinci', 'Üçüncü']);

    // A scan of several pages joins too, its pages chosen like a PDF's.
    final scan = PdfPart('test/fixtures/ocr_cok_sayfali.tif');
    expect(scan.paged, isTrue);
    expect(PdfPart.supports(scan.path), isTrue);
    final whole = await sizes(await PdfTools.build([scan]));
    expect(whole.length, greaterThan(1));
    final withScan = await PdfTools.build([
      PdfPart(scan.path, pages: const [2]),
      PdfPart(file.path, pages: const [1]),
    ]);
    expect(await sizes(withScan), hasLength(2));
    expect((await texts(withScan)).last, 'Birinci');
  });
  testWidgets('the PDF builder: pictures listed as pages, one taken out, '
      'more added', (tester) async {
    final a = picture('bir.jpg', 60, 80),
        b = picture('iki.png', 80, 40, png: true);
    final c = picture('üç.jpg', 60, 80);
    PdfBuilderDialog.pickForTesting = () async => [c, '${dir.path}/olmaz.txt'];
    addTearDown(() => PdfBuilderDialog.pickForTesting = null);
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => PdfBuilderDialog.show(context, initial: [a, b]),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('bir.jpg'), findsOneWidget);
    expect(find.text('iki.png'), findsOneWidget);
    expect(find.text('2 sayfalık PDF'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pdf-build-add')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // The text file is not taken.
    expect(find.text('üç.jpg'), findsOneWidget);
    expect(find.text('olmaz.txt'), findsNothing);
    expect(find.text('3 sayfalık PDF'), findsOneWidget);

    await tester.tap(find.byTooltip('Çıkar').first);
    await tester.pump();
    expect(find.text('bir.jpg'), findsNothing);
    expect(find.text('2 sayfalık PDF'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('pdf-build-save')))
          .onPressed,
      isNotNull,
    );
  });
}

bool _contains(Uint8List all, Uint8List part) {
  outer:
  for (var i = 0; i <= all.length - part.length; i++) {
    for (var j = 0; j < part.length; j++) {
      if (all[i + j] != part[j]) continue outer;
    }
    return true;
  }
  return false;
}

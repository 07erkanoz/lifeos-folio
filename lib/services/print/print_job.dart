import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' show PdfPageFormat, PdfVersion;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';

/// Sends the pages chosen on the print screen to a printer.
///
/// The pages are taken out of the document's PDF as they are, text and
/// all, rather than as pictures of them, so a page prints as sharp as the
/// document is. Copies are the same pages again, since the printer is not
/// asked for them: not every driver honours it.
abstract final class PrintJob {
  /// A PDF of [pages] of [pdf] (from 1, in order, repeats allowed).
  static Future<Uint8List> extract(Uint8List pdf, List<int> pages) async {
    await pdfrxFlutterInitialize();
    final source = await PdfDocument.openData(pdf);
    final out = await PdfDocument.createNew(sourceName: 'yazdir.pdf');
    try {
      out.pages = [for (final p in pages) source.pages[p - 1]];
      return await out.encodePdf();
    } finally {
      await out.dispose();
      await source.dispose();
    }
  }

  /// Prints [pdf] on [printer] with no dialog in between where the system
  /// allows it, and through the system's own print dialog where it does
  /// not, or when no printer is chosen. True when it went to the printer.
  static Future<bool> send(
    Uint8List pdf, {
    required String name,
    Printer? printer,
  }) async {
    // On Linux the PDF goes to CUPS as it is, as other programs send it:
    // the plugin draws each page with a PDFium of its own and closes it
    // when done, under the one Folio's preview has open, and the pages
    // came out blank.
    if ((linuxForTesting ?? Platform.isLinux) &&
        printer != null &&
        _lp() != null) {
      return _toCups(pdf, name: name, queue: printer.url);
    }
    final info = await Printing.info();
    if (printer != null && info.directPrint) {
      return await Printing.directPrintPdf(
        printer: printer,
        name: name,
        format: PdfPageFormat.a4,
        dynamicLayout: false,
        usePrinterSettings: true,
        onLayout: (_) async => pdf,
      );
    }
    return Printing.layoutPdf(
      name: name,
      format: PdfPageFormat.a4,
      dynamicLayout: false,
      onLayout: (_) async => pdf,
    );
  }

  @visibleForTesting
  static Future<ProcessResult> Function(String program, List<String> args)?
  runForTesting;

  @visibleForTesting
  static bool? linuxForTesting;

  @visibleForTesting
  static Future<Uint8List> Function(Uint8List pdf)? flattenForTesting;

  static String? _lp() {
    if (runForTesting != null) return 'lp';
    for (final dir in ['/usr/bin', '/usr/local/bin', '/bin']) {
      if (File(p.join(dir, 'lp')).existsSync()) return p.join(dir, 'lp');
    }
    return null;
  }

  /// [pdf] drawn again page by page, as a document viewer sends it: each
  /// page a picture at [dpi] in a plain PDF. A printer that reads PDF
  /// itself printed blank pages of one a converter wrote (object streams,
  /// PDF 1.7); a plain one it prints.
  static Future<Uint8List> flatten(Uint8List pdf, {int dpi = 200}) async {
    await pdfrxFlutterInitialize();
    final source = await PdfDocument.openData(pdf);
    // A cross-reference table, not a stream: PDF 1.4, as plain as it goes.
    final out = pw.Document(version: PdfVersion.pdf_1_4);
    try {
      for (final page in source.pages) {
        final width = (page.width / 72 * dpi).round();
        final height = (page.height / 72 * dpi).round();
        final drawn = await page.render(
          fullWidth: width.toDouble(),
          fullHeight: height.toDouble(),
          backgroundColor: 0xFFFFFFFF,
          annotationRenderingMode:
              PdfAnnotationRenderingMode.annotationAndForms,
        );
        if (drawn == null) {
          throw StateError('Sayfa ${page.pageNumber} çizilemedi.');
        }
        final jpeg = await compute(_jpeg, (
          bgra: drawn.pixels,
          width: drawn.width,
          height: drawn.height,
        ));
        drawn.dispose();
        out.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(page.width, page.height),
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Image(pw.MemoryImage(jpeg), fit: pw.BoxFit.fill),
          ),
        );
      }
      return await out.save();
    } finally {
      await source.dispose();
    }
  }

  static Uint8List _jpeg(({Uint8List bgra, int width, int height}) page) {
    final image = img.Image.fromBytes(
      width: page.width,
      height: page.height,
      bytes: page.bgra.buffer,
      numChannels: 4,
      order: img.ChannelOrder.bgra,
    );
    return Uint8List.fromList(img.encodeJpg(image, quality: 90));
  }

  static Future<bool> _toCups(
    Uint8List pdf, {
    required String name,
    required String queue,
  }) async {
    final folder = await Directory.systemTemp.createTemp('folio-yazdir-');
    try {
      final file = File(p.join(folder.path, 'belge.pdf'));
      await file.writeAsBytes(
        flattenForTesting != null
            ? await flattenForTesting!(pdf)
            : await flatten(pdf),
        flush: true,
      );
      final run = runForTesting ?? Process.run;
      final r = await run(_lp()!, [
        '-d',
        queue,
        '-t',
        name,
        '-o',
        'fit-to-page',
        file.path,
      ]);
      if (r.exitCode != 0) {
        final said = '${r.stderr}'.trim();
        throw StateError(said.isEmpty ? 'Yazıcı işi kabul etmedi.' : said);
      }
      return true;
    } finally {
      // CUPS has copied the file by the time lp returns.
      unawaited(
        folder.delete(recursive: true).catchError((Object _) => folder),
      );
    }
  }

  /// The printers there are, the default first; none where the system cannot
  /// list them, and printing then goes through its own dialog.
  static Future<List<Printer>> printers() async {
    try {
      final info = await Printing.info();
      if (!info.canListPrinters || !info.directPrint) return const [];
      final all = await Printing.listPrinters();
      return [
        ...all.where((p) => p.isDefault),
        ...all.where((p) => !p.isDefault && p.isAvailable),
      ];
    } catch (_) {
      return const [];
    }
  }
}

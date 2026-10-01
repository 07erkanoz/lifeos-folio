import 'dart:typed_data';

import 'package:pdf/pdf.dart' show PdfPageFormat;
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

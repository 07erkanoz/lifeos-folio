import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// A file kept with a client's record (a power of attorney's scan, signed
/// minutes, a receipt) seen in its own page, to be printed or shared from
/// there; a picture made a page of A4 first.
Future<void> showClientAttachment(
  BuildContext context, {
  required String title,
  required Future<Uint8List> Function() pdf,
  String fileName = 'belge.pdf',
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PdfPreview(
        build: (_) => pdf(),
        pdfFileName: fileName,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        allowPrinting: true,
        allowSharing: true,
      ),
    ),
  ),
);

/// [file] as a PDF: itself when it is one, else its picture on A4 pages.
Future<Uint8List> attachmentPdf(File file) async {
  final bytes = await file.readAsBytes();
  final ext = p.extension(file.path).toLowerCase();
  if (ext == '.pdf') return bytes;
  // TIFF and the rest the pdf package cannot draw: decoded, as PNG.
  final picture = ext == '.jpg' || ext == '.jpeg' || ext == '.png'
      ? bytes
      : () {
          final decoded = img.decodeImage(bytes);
          if (decoded == null) throw const FormatException('okunamadı');
          return Uint8List.fromList(img.encodePng(decoded));
        }();
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(18),
      build: (_) => pw.Center(
        child: pw.Image(pw.MemoryImage(picture), fit: pw.BoxFit.contain),
      ),
    ),
  );
  return doc.save();
}

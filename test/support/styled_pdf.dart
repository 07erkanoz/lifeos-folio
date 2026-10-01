import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One page in three of the standard fonts, not embedded, the way many
/// office exports write them: a bold Helvetica title and, on one line, a
/// Times word and an oblique Courier one.
Future<Uint8List> styledPdf() async {
  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Stack(
        children: [
          pw.Positioned(
            left: 0,
            top: 0,
            child: pw.Text(
              'Bold title',
              style: pw.TextStyle(font: pw.Font.helveticaBold(), fontSize: 20),
            ),
          ),
          pw.Positioned(
            left: 0,
            top: 60,
            child: pw.Text(
              'Normal',
              style: pw.TextStyle(font: pw.Font.times(), fontSize: 12),
            ),
          ),
          pw.Positioned(
            left: 65,
            top: 60,
            child: pw.Text(
              'Italic',
              style: pw.TextStyle(font: pw.Font.courierOblique(), fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
  return document.save();
}

/// A page with nothing on it: a scan's shape without the scan.
Future<Uint8List> emptyPdf() async {
  final document = pw.Document();
  document.addPage(pw.Page(build: (_) => pw.SizedBox()));
  return document.save();
}

/// One empty page carrying an unsigned signature field (/FT /Sig), written
/// out by hand with a correct cross-reference table.
Uint8List signatureFieldPdf() {
  final objects = [
    '<</Type/Catalog/Pages 2 0 R/AcroForm<</Fields[4 0 R]>>>>',
    '<</Type/Pages/Kids[3 0 R]/Count 1>>',
    '<</Type/Page/Parent 2 0 R/MediaBox[0 0 595 842]/Resources<<>>'
        '/Annots[4 0 R]>>',
    '<</Type/Annot/Subtype/Widget/FT/Sig/T(signature)'
        '/Rect[0 0 0 0]/P 3 0 R/F 132>>',
  ];
  final out = StringBuffer('%PDF-1.7\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<</Size ${objects.length + 1}/Root 1 0 R>>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(ascii.encode(out.toString()));
}

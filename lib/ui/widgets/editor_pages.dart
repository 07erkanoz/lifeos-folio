import 'dart:math' as math;

import 'package:flutter_quill/flutter_quill.dart';
import 'package:pdf/pdf.dart';

import '../../models/document_model.dart';
import 'editor_sheets.dart';
import 'editor_units.dart';

/// Where the text goes on the editor's pages, by UYAP's rule, the one the
/// printed page follows too: the header and footer are drawn in the margins
/// at their offsets from the edge, and only one taller than its margin
/// pushes the text away from it (test/fixtures/pages).
abstract final class EditorPages {
  static const pixelsPerPoint = EditorUnits.pixelsPerPoint;

  /// The text area's distance from the top and the bottom of the sheet, in
  /// points, for a header [header] points tall and a footer [footer] points
  /// tall, as the printed page measures them
  /// (`PdfService.regionHeights`); null for one the document does not have.
  static ({double top, double bottom}) textArea(
    DocPageProperties page, {
    double? header,
    double? footer,
  }) => (
    top: header == null
        ? page.marginTop
        : math.max(page.marginTop, page.headerOffset + header),
    bottom: footer == null
        ? page.marginBottom
        : math.max(page.marginBottom, page.footerOffset + footer),
  );

  /// The sheet, in points: A4, turned for a landscape page.
  static ({double width, double height}) sheet(DocPageProperties page) =>
      page.landscape
      ? (width: PdfPageFormat.a4.height, height: PdfPageFormat.a4.width)
      : (width: PdfPageFormat.a4.width, height: PdfPageFormat.a4.height);

  /// The pages the editor lays its lines out on, in pixels.
  static QuillPageGeometry geometry(
    DocPageProperties page, {
    double? header,
    double? footer,
  }) {
    final area = textArea(page, header: header, footer: footer);
    final height = sheet(page).height;
    return QuillPageGeometry(
      height: (height - area.top - area.bottom) * pixelsPerPoint,
      stride: height * pixelsPerPoint + EditorSheetsPainter.room,
    );
  }
}

import 'dart:typed_data';

import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'pdfium.dart';

/// What a PDF holds, read back with PDFium — the reader the app itself uses —
/// so a test measures the file the way a user's preview will see it.
class PdfReadback {
  PdfReadback._(this.pageSizes, this._pages);

  /// Width and height of each page, in points.
  final List<(double, double)> pageSizes;
  final List<PdfPageRawText?> _pages;

  int get pageCount => pageSizes.length;

  /// Every page's text, in order.
  String get text =>
      [for (final page in _pages) page?.fullText ?? ''].join('\n');

  /// The text of [page] alone.
  String pageText(int page) => _pages[page]?.fullText ?? '';

  /// Left and right edge, in points from the page's left, of the first
  /// place [needle] is drawn on [page].
  (double, double) horizontalExtent(String needle, {int page = 0}) {
    final text = _pages[page]!;
    final at = text.fullText.indexOf(needle);
    if (at < 0) throw StateError('"$needle" sayfada yok: ${text.fullText}');
    final rects = text.charRects.sublist(at, at + needle.length);
    return (
      rects.map((r) => r.left).reduce((a, b) => a < b ? a : b),
      rects.map((r) => r.right).reduce((a, b) => a > b ? a : b),
    );
  }

  /// Where the first letter of the first place [needle] is drawn on [page]:
  /// its left edge from the page's left, and its baseline row from the top.
  (double, double) start(String needle, {int page = 0}) {
    final text = _pages[page]!;
    final at = text.fullText.indexOf(needle);
    if (at < 0) throw StateError('"$needle" sayfada yok: ${text.fullText}');
    final rect = text.charRects[at];
    return (rect.left, pageSizes[page].$2 - rect.bottom);
  }

  static Future<PdfReadback> of(Uint8List bytes) async {
    configurePdfiumForTest();
    await pdfrxInitialize();
    final document = await PdfDocument.openData(bytes);
    try {
      return PdfReadback._(
        [for (final page in document.pages) (page.width, page.height)],
        [for (final page in document.pages) await page.loadText()],
      );
    } finally {
      await document.dispose();
    }
  }
}

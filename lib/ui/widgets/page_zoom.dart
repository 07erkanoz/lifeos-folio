import 'dart:math' as math;

/// How large a page is first shown, in the preview and the editor alike.
///
/// A percentage of the page's printed size on a 96 dpi screen, which is what
/// 100% means to Word and to the editor's zoom bar. The two used to open at
/// different sizes — the preview at up to 130% of a point per pixel, the
/// editor at 100% of 96 dpi, 97.5% against 100% — so the page jumped when the
/// reader pressed Düzenle, and a tab that had not moved looked as though it
/// had. Both now open at [initial].
class PageZoom {
  PageZoom._();

  /// 120%, the size UYAP's editor opens at as it is set up here.
  static const initial = 1.2;

  /// The page is drawn at 96 dpi; a PDF point is 1/72 of an inch.
  static const pixelsPerPoint = 96 / 72;

  /// [zoom] as the PDF viewer counts it: pdfrx draws a point as one pixel.
  static double forPdfViewer(double zoom) => zoom * pixelsPerPoint;

  /// The zoom to open a page [pageWidth] pixels wide at, in a view [available]
  /// pixels wide: [initial], or less where that would not fit.
  static double opening(double pageWidth, double available) {
    if (!available.isFinite || pageWidth <= 0) return initial;
    return math.max(.5, math.min(initial, available / pageWidth));
  }
}

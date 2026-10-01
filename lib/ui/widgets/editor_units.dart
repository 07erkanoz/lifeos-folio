/// The editor's units.
///
/// The page is laid out in points — a pixel of layout is a point of paper —
/// and drawn 96/72 larger, at the size it prints at. Laid out at 96 dpi, a
/// row UYAP makes 14 points tall would be 18.67 pixels, and the text engine
/// rounds every row to a whole pixel, here as on the reader's machine: 19,
/// and a page held 49 rows where UYAP's holds 50. In points it is 14.
abstract final class EditorUnits {
  /// Layout pixels to a point.
  static const pixelsPerPoint = 1.0;

  /// How much larger the page is drawn than it is laid out.
  static const screenScale = 96 / 72;

  /// A run's `size` as documents and snippets keep it: in 96 dpi pixels,
  /// the editor's unit before it laid out in points.
  static const sizePixelsPerPoint = 96 / 72;

  /// A run's kept `size` as the editor lays it out.
  static double fontSize(double keptPixels) =>
      keptPixels / sizePixelsPerPoint * pixelsPerPoint;
}

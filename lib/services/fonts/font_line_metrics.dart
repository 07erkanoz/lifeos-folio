import 'dart:typed_data';

/// How tall a line of a font is, as fractions of its size.
///
/// UYAP lays text out with Java Swing, where a row is the font's ascent,
/// descent and leading — the `hhea` table — and a paragraph's LineSpacing
/// adds that fraction of the row below it. Measured with Swing on Times New
/// Roman at 12: LineSpacing 0 gives a 15 px row, 0.15 gives 17 and 0.5 gives
/// 22, which is 15 + ⌊15 × LineSpacing⌋ each time. So a row is
/// `natural × size × (1 + LineSpacing)`, and it depends on the font: 1.15 for
/// Times New Roman, Arial and their Liberation twins, 1.21 for Tahoma, 1.22
/// for Calibri.
class FontLineMetrics {
  const FontLineMetrics({required this.natural, required this.tight});

  /// Times New Roman and Arial both come to 2355/2048, and so do the
  /// metric-compatible Liberation fonts the app falls back on.
  static const common = FontLineMetrics(
    natural: 2355 / 2048,
    tight: 2268 / 2048,
  );

  /// Ascent + descent + line gap: the row Swing lays out.
  final double natural;

  /// Ascent + descent without the gap: the line box the `pdf` package lays
  /// out, which the preview has to make up the difference to.
  final double tight;

  /// Reads `hhea` and `head` from a TrueType/OpenType file. Null when the
  /// data is not a font or lacks either table.
  static FontLineMetrics? read(ByteData data) {
    try {
      if (data.lengthInBytes < 12) return null;
      final tables = data.getUint16(4);
      int? hhea, head;
      for (var i = 0; i < tables; i++) {
        final at = 12 + i * 16;
        if (at + 16 > data.lengthInBytes) return null;
        final tag = data.getUint32(at);
        final offset = data.getUint32(at + 8);
        if (tag == 0x68686561) hhea = offset; // 'hhea'
        if (tag == 0x68656164) head = offset; // 'head'
      }
      if (hhea == null || head == null) return null;
      final unitsPerEm = data.getUint16(head + 18);
      if (unitsPerEm == 0) return null;
      final ascender = data.getInt16(hhea + 4);
      final descender = data.getInt16(hhea + 6);
      final lineGap = data.getInt16(hhea + 8);
      final tight = (ascender - descender) / unitsPerEm;
      if (tight <= 0) return null;
      return FontLineMetrics(
        natural:
            (ascender - descender + (lineGap > 0 ? lineGap : 0)) / unitsPerEm,
        tight: tight,
      );
    } on RangeError {
      return null;
    }
  }

  /// The distance from one row to the next for text of [size], with the
  /// paragraph's [lineSpacing] as the model stores it (1 + LineSpacing).
  double row(double size, double? lineSpacing) =>
      natural *
      size *
      (lineSpacing == null || lineSpacing < 1 ? 1 : lineSpacing);

  /// The row UYAP lays out, in whole points: the font's natural row rounded
  /// up, with the line spacing added as two insets, above and below, each
  /// rounded down. Measured in UYAP over eleven sizes, two fonts and four
  /// spacings (test/fixtures/pages): 12 pt is 14, at 1.5 lines 14 + 3 + 3 =
  /// 20, not 13.8 × 1.5 = 20.7 — a difference that moved every page break
  /// of a long petition.
  double uyapRow(double size, double? lineSpacing) {
    final height = (natural * size - 1e-6).ceilToDouble();
    final extra = lineSpacing == null || lineSpacing <= 1
        ? 0.0
        : (height * (lineSpacing - 1) / 2).floorToDouble();
    return height + 2 * extra;
  }
}

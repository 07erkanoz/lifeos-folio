/// Page numbers as UYAP keeps them: attributes on a header or footer, and
/// drawn inside it, over its text, taking no room.
///
/// Read off UYAP's own editor (its page number dialog and the view that
/// draws the number), and held against the 140 numbered headers and footers
/// of a real archive:
///
/// * `pageNumber-spec` is a set of bits, written `BSP32_<value>`: 4 puts the
///   number at the top of the header or footer, 8 at its bottom; 16 left,
///   32 centre, 64 right; 2048 adds the page count after a separator
///   ("3/7"); 4096 leaves the first page without one, and 8192 a document of
///   one page. The archive holds 68 (top right), 40 (bottom centre), 72,
///   2088 and 2120.
/// * The number is drawn 2 points inside the top or bottom of the region's
///   box, its baseline below the top by the ink's own height; 1 point in
///   from the right, centred to the whole point, or flush left.
/// * It reads prefix, number (counted from `pageStartNumStr`, else 1), the
///   separator and the page count when asked for, then the suffix; in the
///   font the attributes name, Arial 11 unless they say otherwise.
///
/// A header or footer is drawn at all only from `startPage` on (38 headers
/// of the archive start on page 2), and up to `stopPage` when it has one.
library;

import '../../models/document_model.dart';

enum PageNumberAlign { left, center, right }

class PageNumbering {
  const PageNumbering({
    this.top = false,
    this.align = PageNumberAlign.center,
    this.withTotal = false,
    this.skipFirst = false,
    this.skipSingle = false,
    this.prefix = '',
    this.suffix = '',
    this.separator = '/',
    this.fontFace = 'Arial',
    this.fontSize = 11,
    this.bold = false,
    this.italic = false,
    this.color = 0xff000000,
    this.startNumber,
  });

  /// At the top of its region, or at the bottom.
  final bool top;
  final PageNumberAlign align;

  /// "3/7" rather than "3".
  final bool withTotal;
  final bool skipFirst;
  final bool skipSingle;
  final String prefix, suffix, separator;
  final String fontFace;
  final double fontSize;
  final bool bold, italic;

  /// ARGB.
  final int color;

  /// What the first page is numbered, when not 1.
  final int? startNumber;

  static const _top = 4,
      _bottom = 8,
      _left = 16,
      _center = 32,
      _right = 64,
      _total = 2048,
      _notFirst = 4096,
      _notSingle = 8192;

  /// Every attribute page numbering is written with, which a region that
  /// loses its numbering drops.
  static const attributeNames = [
    'pageNumber-spec',
    'pageNumber-seperator',
    'pageNumber-fontBold',
    'pageNumber-fontItalic',
    'pageNumber-fontUnderline',
    'pageNumber-fontFace',
    'pageNumber-fontSize',
    'pageNumber-color',
    'pageNumber-foreStr',
    'pageNumber-afterStr',
    'pageNumber-pageStartNumStr',
  ];

  /// The numbering a region's attributes ask for, or null for none.
  static PageNumbering? parse(Map<dynamic, dynamic>? attrs) {
    if (attrs == null) return null;
    final spec = '${attrs['pageNumber-spec'] ?? ''}';
    if (!spec.startsWith('BSP32_')) return null;
    final bits = int.tryParse(spec.substring(6)) ?? 0;
    if (bits == 0) return null;
    String text(String key) => '${attrs[key] ?? ''}';
    final color = int.tryParse(text('pageNumber-color'));
    return PageNumbering(
      top: bits & _bottom == 0,
      align: bits & _right != 0
          ? PageNumberAlign.right
          : bits & _center != 0
          ? PageNumberAlign.center
          : PageNumberAlign.left,
      withTotal: bits & _total != 0,
      skipFirst: bits & _notFirst != 0,
      skipSingle: bits & _notSingle != 0,
      prefix: text('pageNumber-foreStr'),
      suffix: text('pageNumber-afterStr'),
      separator: attrs['pageNumber-seperator'] == null
          ? '/'
          : text('pageNumber-seperator'),
      fontFace: text('pageNumber-fontFace').isEmpty
          ? 'Arial'
          : text('pageNumber-fontFace'),
      fontSize: double.tryParse(text('pageNumber-fontSize')) ?? 11,
      bold: text('pageNumber-fontBold') == 'true',
      italic: text('pageNumber-fontItalic') == 'true',
      color: color == null ? 0xff000000 : color | 0xff000000,
      startNumber: int.tryParse(text('pageNumber-pageStartNumStr')),
    );
  }

  int get bits =>
      (top ? _top : _bottom) |
      switch (align) {
        PageNumberAlign.left => _left,
        PageNumberAlign.center => _center,
        PageNumberAlign.right => _right,
      } |
      (withTotal ? _total : 0) |
      (skipFirst ? _notFirst : 0) |
      (skipSingle ? _notSingle : 0);

  /// The attributes as UYAP writes them: the set its dialog leaves on a
  /// region, the separator, weight and slant only with the page count, as
  /// in the archive's files.
  Map<String, String> toAttributes() => {
    'pageNumber-spec': 'BSP32_$bits',
    if (withTotal) 'pageNumber-seperator': separator,
    if (withTotal) 'pageNumber-fontBold': '$bold',
    if (withTotal) 'pageNumber-fontItalic': '$italic',
    'pageNumber-fontFace': fontFace,
    'pageNumber-fontSize': fontSize == fontSize.roundToDouble()
        ? '${fontSize.round()}'
        : '$fontSize',
    // A Java colour, signed: black is -16777216.
    'pageNumber-color': '${(color | 0xff000000).toSigned(32)}',
    'pageNumber-foreStr': prefix,
    if (suffix.isNotEmpty) 'pageNumber-afterStr': suffix,
    'pageNumber-pageStartNumStr': startNumber == null ? '' : '$startNumber',
  };

  /// [attrs] with this numbering in place of whatever numbering they held.
  static Map<String, String> apply(
    Map<dynamic, dynamic>? attrs,
    PageNumbering? numbering,
  ) => {
    for (final e in (attrs ?? const {}).entries)
      if (!attributeNames.contains(e.key)) '${e.key}': '${e.value}',
    ...?numbering?.toAttributes(),
  };

  /// Whether page [page] (from 1) of [total] shows a number.
  bool shows(int page, int total) =>
      !(page == 1 && (skipFirst || (skipSingle && total <= 1)));

  /// What page [page] (from 1) of [total] reads.
  String label(int page, int total) {
    final first = startNumber ?? 1;
    final number = page - 1 + first;
    return '$prefix$number'
        '${withTotal ? '$separator${total - 1 + first}' : ''}'
        '$suffix';
  }

  /// Where the label goes in a region [width] by [height] points: its left
  /// edge and its baseline from the region's top-left, for a label
  /// [advance] wide whose ink is [ink] tall.
  ({double x, double baseline}) place({
    required double width,
    required double height,
    required double advance,
    required double ink,
  }) {
    // In whole points, as UYAP's view works them out.
    final w = width.truncateToDouble(), a = advance.truncateToDouble();
    final h = height.truncateToDouble(), i = ink.truncateToDouble();
    return (
      x: switch (align) {
        PageNumberAlign.left => 0.0,
        PageNumberAlign.center => ((w - a) / 2).truncateToDouble(),
        PageNumberAlign.right => w - a - 1,
      },
      baseline: top ? i + 2 : h - 2,
    );
  }

  /// How tall the ink of [label] is at this size: what UYAP measures the
  /// number's place by. Arial's figures and capitals stand 0.716 of the size
  /// above the baseline, its tallest lower-case letters 0.733, and its
  /// descenders reach 0.21 below it.
  double ink(String label) {
    final tall = RegExp(r'[a-zA-ZçğıöşüÇĞİÖŞÜ/]').hasMatch(label);
    final deep = RegExp(r'[gjpqyçşğ,;]').hasMatch(label);
    return fontSize * ((tall ? .733 : .716) + (deep ? .21 : 0));
  }

  /// Whether a region holds nothing but empty lines, and so, numbered, only
  /// its number.
  static bool onlyNumber(List<DocBlock> region) => region.every(
    (b) => b.type == DocBlockType.paragraph && b.plainText.trim().isEmpty,
  );

  /// Whether a region with [attrs] is drawn on page [page] (from 1).
  static bool regionShows(Map<dynamic, dynamic>? attrs, int page) {
    final start = int.tryParse('${attrs?['startPage'] ?? ''}');
    final stop = int.tryParse('${attrs?['stopPage'] ?? ''}');
    if (start != null && page < start) return false;
    if (stop != null && stop >= 0 && page > stop) return false;
    return true;
  }
}

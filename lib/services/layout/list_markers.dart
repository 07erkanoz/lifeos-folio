/// A list item's number or bullet, as UYAP draws it, for the preview and
/// the editor alike.
///
/// Read off UYAP's own paragraph view (its list marker painting), and held
/// against UYAP's rendering of every number and bullet kind the archive
/// uses (33 of 907 documents have lists, 231 items):
///
/// * The item's text is laid out as any paragraph's, from its left indent;
///   the marker takes no room. It is drawn in the indent, left of where the
///   text begins: a number ending about 8 points before it, a bullet 15
///   points before it.
/// * An item is numbered among the items of its own list (`ListId`) at its
///   own level, counting back to the first or to one at a higher level.
/// * A number is in the item's own font; a bullet is a shape a third of the
///   font's size, level with the middle of the first row.
library;

import 'dart:math' as math;

import '../../models/document_model.dart';

enum BulletShape { circle, square, squareOutline, arrow, diamond, triangle }

abstract final class ListMarkers {
  /// The number each numbered item of [blocks] carries, by its index in
  /// [blocks], counted as UYAP counts: within its list, at its level, back
  /// to the list's first item or to one at a higher level.
  static Map<int, int> numbers(List<DocBlock> blocks) {
    final out = <int, int>{};
    // For each list, the count reached at each level so far.
    final counts = <int, Map<int, int>>{};
    var anonymous = -1;
    var previousWasList = false;
    for (final (i, b) in blocks.indexed) {
      if (b.listType == DocListType.none) {
        previousWasList = false;
        continue;
      }
      // A list the document gave no number: the items next to each other
      // are one, as a list made in the editor is.
      var id = b.listId;
      if (id == 0) {
        if (!previousWasList) anonymous--;
        id = anonymous;
      }
      previousWasList = true;
      final levels = counts.putIfAbsent(id, () => {});
      final level = b.listLevel;
      // A higher level starts the lower ones over.
      levels.removeWhere((l, _) => l > level);
      final n = (levels[level] ?? 0) + 1;
      levels[level] = n;
      if (b.listType == DocListType.ordered) out[i] = n;
    }
    return out;
  }

  /// What number [n] reads as in UYAP's [numberType]; "n." when the file
  /// names none, as UYAP draws it.
  static String label(String? numberType, int n) {
    final type = numberType ?? '';
    final String body;
    if (type.startsWith('NUMBER_TYPE_CHAR_SMALL')) {
      body = _letters(n).toLowerCase();
    } else if (type.startsWith('NUMBER_TYPE_CHAR_BIG')) {
      body = _letters(n);
    } else if (type.startsWith('NUMBER_TYPE_ROMAN_SMALL')) {
      body = _roman(n).toLowerCase();
    } else if (type.startsWith('NUMBER_TYPE_ROMAN_BIG')) {
      body = _roman(n);
    } else {
      body = '$n';
    }
    if (type.endsWith('_D_PARANTHESE')) return '($body)';
    if (type.endsWith('_PARANTHESE')) return '$body)';
    if (type.endsWith('_TRE')) return '$body-';
    return '$body.';
  }

  /// The shape UYAP draws for [bulletType]; a filled circle for any it
  /// does not name.
  static BulletShape shape(String? bulletType) => switch (bulletType) {
    'BULLET_TYPE_RECTANGLE' => BulletShape.square,
    'BULLET_TYPE_RECTANGLE_D' => BulletShape.squareOutline,
    'BULLET_TYPE_ARROW' => BulletShape.arrow,
    'BULLET_TYPE_DIAMOND' || 'BULLET_TYPE_DIAMOND_2' => BulletShape.diamond,
    'BULLET_TYPE_TRIANGLE' => BulletShape.triangle,
    _ => BulletShape.circle,
  };

  /// Where a number goes: its left edge from where the paragraph's rows
  /// are measured, for a label [advance] wide, and its baseline below the
  /// top of the first row, [row] tall, in a font [size] big. UYAP puts it
  /// 15 points left of the text, less 2 — or its width less 10 when wider
  /// than 12 — and its baseline a quarter of the size below the row's
  /// middle.
  static ({double x, double baseline}) numberAt({
    required double textStart,
    required double advance,
    required double row,
    required double size,
  }) {
    final width = advance.truncate();
    final shift = width > 12 ? width - 10 : 2;
    final half = size.truncate() ~/ 2;
    return (
      x: textStart - 15 - shift,
      baseline: (row.truncate() ~/ 2 - half ~/ 2 + 1 + half).toDouble(),
    );
  }

  /// Where a bullet goes: its box from where the paragraph's rows are
  /// measured and from the top of the first row, [row] tall, in a font
  /// [size] big. A third of the size across, centred on the row.
  static ({double x, double y, double side}) bulletAt({
    required double textStart,
    required double row,
    required double size,
  }) {
    final third = size.truncate() ~/ 3;
    return (
      x: textStart - 15,
      y: (row.truncate() ~/ 2 - third ~/ 2 + 1).toDouble(),
      side: (third + 1).toDouble(),
    );
  }

  static String _letters(int n) {
    var rest = math.max(1, n);
    final out = StringBuffer();
    final letters = <String>[];
    while (rest > 0) {
      rest--;
      letters.insert(0, String.fromCharCode(0x41 + rest % 26));
      rest ~/= 26;
    }
    out.writeAll(letters);
    return out.toString();
  }

  static String _roman(int n) {
    const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    const glyphs = [
      'M',
      'CM',
      'D',
      'CD',
      'C',
      'XC',
      'L',
      'XL',
      'X',
      'IX',
      'V',
      'IV',
      'I',
    ];
    var rest = math.max(1, n);
    final out = StringBuffer();
    for (var i = 0; i < values.length; i++) {
      while (rest >= values[i]) {
        out.write(glyphs[i]);
        rest -= values[i];
      }
    }
    return out.toString();
  }
}

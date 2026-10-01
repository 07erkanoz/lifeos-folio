import 'dart:math' as math;

/// The box of one character on a PDF page, in points, the origin at the
/// page's foot: [top] is above [bottom].
typedef CharBox = ({double left, double top, double right, double bottom});

/// A place in a document as it was pointed at on its rendered page: the line
/// under the pointer, and where on that line.
///
/// The preview is a PDF drawn from the same document the editor opens, so the
/// line is in the editor's text too — give or take what drawing adds and
/// takes away: a paragraph broken over several lines, a tab drawn as a gap,
/// the bullet or number of a list, which is formatting and not text.
/// Whitespace is therefore not compared at all, a line with a list mark in
/// front is also looked for without it, and a line not found whole is looked
/// for by the letters around the pointer.
class TextAnchor {
  const TextAnchor({
    required this.page,
    required this.pages,
    this.down = 0,
    this.line = '',
    this.at = 0,
    this.before = '',
    this.after = '',
  });

  /// The anchor at ([x], [y]) on a page [height] points high, whose text
  /// layer is [text] with [boxes] the box of each of its characters. A point
  /// far from any text gives only the page, and how far down it is.
  factory TextAnchor.onPage({
    required int page,
    required int pages,
    required double height,
    required double x,
    required double y,
    String text = '',
    List<CharBox> boxes = const [],
  }) {
    final down = height <= 0 ? 0.0 : (1 - y / height).clamp(0.0, 1.0);
    var best = -1;
    var bestDy = double.infinity, bestDx = double.infinity;
    for (var i = 0; i < boxes.length && i < text.length; i++) {
      final box = boxes[i];
      if (box.left >= box.right || box.top <= box.bottom) continue;
      if (_isSpace(text.codeUnitAt(i))) continue;
      final dy = y > box.top
          ? y - box.top
          : y < box.bottom
          ? box.bottom - y
          : 0.0;
      final dx = x < box.left
          ? box.left - x
          : x > box.right
          ? x - box.right
          : 0.0;
      // The line first, then the place on it: a letter straight above is
      // further than the end of the line the pointer is on.
      if (dy < bestDy - .5 || ((dy - bestDy).abs() <= .5 && dx < bestDx)) {
        best = i;
        bestDy = dy;
        bestDx = dx;
      }
    }
    if (best < 0 || bestDy > _near) {
      return TextAnchor(page: page, pages: pages, down: down);
    }
    final lines = <(int, int)>[];
    for (var from = 0, i = 0; i <= text.length; i++) {
      if (i == text.length || _isBreak(text.codeUnitAt(i))) {
        lines.add((from, i));
        // A break is one character, or two for \r\n.
        if (i + 1 < text.length &&
            text.codeUnitAt(i) == 0x0D &&
            text.codeUnitAt(i + 1) == 0x0A) {
          i++;
        }
        from = i + 1;
      }
    }
    final index = lines.indexWhere((l) => l.$1 <= best && best < l.$2);
    final (start, end) = lines[index];
    String join(Iterable<(int, int)> some) =>
        some.map((l) => text.substring(l.$1, l.$2)).join('\n');
    return TextAnchor(
      page: page,
      pages: pages,
      down: down,
      line: text.substring(start, end),
      at: best - start,
      before: join(lines.sublist(math.max(0, index - 2), index)),
      after: join(lines.skip(index + 1).take(1)),
    );
  }

  /// Further than this from any letter, in points, a click is not on text.
  static const _near = 24.0;

  /// The page pointed at, one based, and how many there are.
  final int page, pages;

  /// How far down the page, from 0 at its top to 1 at its foot.
  final double down;

  /// The line under the pointer as the page's text layer has it, and the
  /// index in it of the character pointed at.
  final String line;
  final int at;

  /// The lines around [line] on the page, up to two above and one below.
  /// They tell apart lines written the same way — a closing formula, the
  /// end of a clause every paragraph ends with — which the page alone
  /// often cannot: the last page may be half empty.
  final String before, after;

  /// The offset in [text] of the character pointed at.
  ///
  /// Where the line is not in [text] — a page number, a header, a table drawn
  /// from its cells — the start of the line about as far into [text] as the
  /// page is into the document. Where it is there more than once, the one
  /// nearest to that.
  int locate(String text) {
    if (text.isEmpty) return 0;
    final count = math.max(pages, 1);
    final into = (page - 1).clamp(0, count - 1) + down.clamp(0.0, 1.0);
    final expected = (into / count * text.length).round();
    final (squeezed, positions) = _squeeze(text);
    for (final (needle, pointer) in _candidates()) {
      var best = -1;
      for (
        var from = squeezed.indexOf(needle);
        from >= 0;
        from = squeezed.indexOf(needle, from + 1)
      ) {
        if (best < 0 ||
            (positions[from] - expected).abs() <
                (positions[best] - expected).abs()) {
          best = from;
        }
      }
      if (best >= 0) return positions[best + pointer];
    }
    var start = math.min(expected, text.length);
    while (start > 0 && text.codeUnitAt(start - 1) != 0x0A) {
      start--;
    }
    return start;
  }

  /// A list's mark as drawing puts it in front of the text: a bullet, or a
  /// number or letter with a dot or a bracket, and the gap after it.
  static final _listMark = RegExp(
    r'^\s*(?:[•◦▪■●○‣∙·\-–—*]|\(?\d{1,3}[.)]|\(?[a-zA-ZçğıöşüÇĞİÖŞÜ][.)])\s+',
  );

  /// What to look for, the most telling first, each with the index in it of
  /// the character pointed at.
  Iterable<(String, int)> _candidates() sync* {
    final (whole, _) = _squeeze(line);
    if (whole.isEmpty) return;
    final pointer = math.min(_letters(line, at), whole.length - 1);
    // With its neighbours first; a neighbour the document does not have,
    // such as a page's header, leaves the others to try.
    final (above, _) = _squeeze(before);
    final (below, _) = _squeeze(after);
    if (above.isNotEmpty && below.isNotEmpty) {
      yield (above + whole + below, above.length + pointer);
    }
    if (above.isNotEmpty) yield (above + whole, above.length + pointer);
    if (below.isNotEmpty) yield (whole + below, pointer);
    yield (whole, pointer);

    final mark = _listMark.firstMatch(line);
    if (mark != null) {
      final (rest, _) = _squeeze(line.substring(mark.end));
      final skipped = whole.length - rest.length;
      if (rest.isNotEmpty) {
        yield (rest, (pointer - skipped).clamp(0, rest.length - 1));
      }
    }

    // The letters around the pointer, for a line that is not in the text as
    // it is drawn: a table row, or one with a mark the pattern above missed.
    const reach = 10;
    if (whole.length > 2 * reach) {
      final from = (pointer - reach).clamp(0, whole.length - 2 * reach);
      yield (whole.substring(from, from + 2 * reach), pointer - from);
    }
  }

  /// How many letters — anything but whitespace — [text] has before [index].
  static int _letters(String text, int index) {
    var count = 0;
    for (var i = 0; i < index && i < text.length; i++) {
      if (!_isSpace(text.codeUnitAt(i))) count++;
    }
    return count;
  }

  /// [text] without its whitespace, and where each of its letters was.
  static (String, List<int>) _squeeze(String text) {
    final out = StringBuffer();
    final positions = <int>[];
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (_isSpace(unit)) continue;
      out.writeCharCode(unit);
      positions.add(i);
    }
    return (out.toString(), positions);
  }

  static bool _isBreak(int unit) => unit == 0x0A || unit == 0x0D;

  /// Whitespace, and what a document holds in place of an embedded object
  /// or as an invisible hint, none of which a drawn page shows as a letter.
  static bool _isSpace(int unit) =>
      unit <= 0x20 ||
      unit == 0x85 ||
      unit == 0xA0 ||
      unit == 0xAD ||
      (unit >= 0x2000 && unit <= 0x200B) ||
      unit == 0x2028 ||
      unit == 0x2029 ||
      unit == 0x202F ||
      unit == 0x205F ||
      unit == 0x3000 ||
      unit == 0xFEFF ||
      unit == 0xFFFC;
}

/// How a paragraph falls into rows, for the preview and the editor alike.
///
/// The preview is drawn with the `pdf` package and the editor with Flutter,
/// and each used to break lines, place tabs and spread a justified row in its
/// own way — so the same document moved when the reader pressed Düzenle. Both
/// now ask this one class where things go, and only measure text themselves.
///
/// The rules are UYAP's, read off UYAP itself: its editor was run on
/// documents built to test each one and asked where it had drawn every
/// character. What it does:
///
/// * The first row starts at the left indent plus the first line indent, the
///   others at the left indent plus the hanging indent (`Hanging`, a UYAP
///   attribute: 1279 paragraphs in 78 of 1007 documents, the headings of
///   court decisions whose values wrap under themselves).
/// * A line breaks only at a space, and a word stays up only if the spaces
///   after it fit as well, against the row's width rounded up to a whole
///   point; a word wider than the row is cut where it stops fitting. Unlike Flutter, UYAP does not break after a hyphen or a
///   slash, so "Manavgat/ANTALYA" moves down whole. The wider spaces — an em
///   space is twelve points at twelve point — break and stretch like spaces;
///   a no-break space does neither.
/// * A line break inside a paragraph is not drawn at all: UYAP sets it as an
///   empty letter and carries on along the row. 525 paragraphs in 224 of 1007
///   documents have one, mostly pasted in from Word ("KONU\t:\n İtirazın…"),
///   and UYAP shows every one of them as a single line. A Word document's own
///   line breaks do break, as they do in Word; see [lineBreaks].
/// * Tabs are placed row by row, counted from the left indent (see
///   [TabStops]); a tab that does not fit starts the next row, and is
///   counted from there.
/// * A justified row spreads the room left over between its words and keeps
///   every tab as wide as it was before spreading, so spaces before a tab
///   push it along. Spaces at the start of such a row take no room.
///
/// Where Flutter cannot follow UYAP, the editor's way is kept, because the
/// point is that preview and editor agree: a justified row runs its last word
/// to the edge with the trailing space hanging past it, and each run of spaces
/// between two words gets an equal share rather than each space. Both differ
/// from UYAP by less than a space.
library;

import '../editor/tab_stops.dart';

enum RowAlign { left, center, right, justify }

enum PieceKind { text, space, tab }

/// A stretch of one row: a word, a space, or a tab, with where it is drawn.
class RowPiece {
  RowPiece(this.kind, this.start, this.end, this.x, this.width);

  final PieceKind kind;

  /// Offsets into the paragraph's text; a space and a tab are one each.
  final int start, end;

  /// From the left edge of the text area, the margin.
  double x;
  double width;

  @override
  String toString() => '${kind.name}[$start,$end)@${x.toStringAsFixed(1)}';
}

class ParagraphRow {
  ParagraphRow(this.pieces, {required this.start, required this.left});

  final List<RowPiece> pieces;

  /// Where the row's text begins in the paragraph.
  final int start;

  /// Where the row starts, from the margin: the indent it is laid out from.
  final double left;

  /// The row closes the paragraph, or a line break inside it: it is set as it
  /// stands rather than spread.
  bool last = false;

  /// Where the row's last piece ends before it is aligned, trailing spaces
  /// and all: how far the row reaches when the next word is weighed.
  double reach = 0;

  int get end => pieces.isEmpty ? start : pieces.last.end;

  /// Where the row's content ends, trailing spaces left out.
  double get right {
    for (final p in pieces.reversed) {
      if (p.kind != PieceKind.space) return p.x + p.width;
    }
    return left;
  }
}

class ParagraphRows {
  ParagraphRows({
    required this.text,
    required this.measure,
    required this.space,
    required this.width,
    this.leftIndent = 0,
    this.rightIndent = 0,
    this.firstLineIndent = 0,
    this.hanging = 0,
    this.align = RowAlign.left,
    this.tabs = const TabStops(),
    this.lead = 0,
    this.lineBreaks = false,
  });

  final String text;

  /// Width of `text.substring(start, end)` in its own styles, in points.
  final double Function(int start, int end) measure;

  /// Width of a space in the style at [offset].
  final double Function(int offset) space;

  /// The text area's width, margin to margin; infinite to lay the paragraph
  /// out as one row.
  final double width;

  final double leftIndent, rightIndent, firstLineIndent, hanging;
  final RowAlign align;
  final TabStops tabs;

  /// Room taken at the start of the first row before the text, such as a
  /// list's number.
  final double lead;

  /// Whether a `\n` in the text starts a new row, as a Word line break does,
  /// rather than being an empty letter, as it is in UYAP. A line separator,
  /// U+2028 — how the editor carries a Word line break — always does.
  final bool lineBreaks;

  /// Where tabs are counted from: the left indent under UYAP's rules, the
  /// margin under Word's.
  double get _tabBase => tabs.rules == TabRules.uyap ? leftIndent : 0;

  /// How far a row may run past its width and still be one row: what
  /// Flutter allows, measured — about four thousandths of a pixel — so that
  /// a word that just fits stays up in the preview as it does in the editor.
  static const _epsilon = .003;

  List<ParagraphRow> layout() {
    final rows = <ParagraphRow>[];
    final limit = width - rightIndent;
    var first = true;
    late ParagraphRow row;
    late double pen;
    var content = false;

    void open(int start) {
      final left = leftIndent + (first ? firstLineIndent : hanging);
      row = ParagraphRow([], start: start, left: left);
      pen = left + (first ? lead : 0);
      content = false;
      first = false;
    }

    void close({bool last = false}) {
      row
        ..last = last
        ..reach = pen;
      rows.add(row);
    }

    void place(PieceKind kind, int start, int end, double w) {
      row.pieces.add(RowPiece(kind, start, end, pen, w));
      pen += w;
      if (kind != PieceKind.space) content = true;
    }

    double tabEnd(int at) {
      var next = text.indexOf('\t', at + 1);
      if (next < 0) next = text.length;
      final lineEnd = text.indexOf('\n', at + 1);
      if (lineEnd >= 0 && lineEnd < next) next = lineEnd;
      final base = _tabBase;
      return base +
          tabs.end(
            pen - base,
            following: () => measure(at + 1, next),
            toDecimal: () {
              final dot = text.indexOf('.', at + 1);
              return measure(at + 1, dot < 0 || dot > next ? next : dot);
            },
            space: space(at),
          );
    }

    open(0);
    var i = 0;
    while (i < text.length) {
      final c = text.codeUnitAt(i);
      if (_breaksRow(c)) {
        close(last: true);
        open(i + 1);
        i++;
      } else if (_isSpace(c)) {
        place(PieceKind.space, i, i + 1, measure(i, i + 1));
        i++;
      } else if (c == _tab) {
        var end = tabEnd(i);
        if (end > limit + _epsilon && content) {
          close();
          open(i);
          end = tabEnd(i);
        }
        place(PieceKind.tab, i, i + 1, end - pen);
        i++;
      } else {
        var j = i;
        while (j < text.length && !_separator(text.codeUnitAt(j))) {
          j++;
        }
        if (j == i) {
          // Nothing else claims a character; it cannot hold the loop still.
          j = i + 1;
        }
        var w = measure(i, j);
        // UYAP breaks a row between a word with the spaces after it and the
        // next word, and a word goes up only if its spaces fit too
        // (test/fixtures/pages, and 2,634 paragraphs of a real archive held
        // against UYAP). Word lets them hang.
        var k = j;
        while (tabs.rules == TabRules.uyap &&
            k < text.length &&
            _isSpace(text.codeUnitAt(k))) {
          k++;
        }
        // Against the edge in whole points, as UYAP's rows are laid out in
        // whole points: 453.55 points of room hold a word whose space ends at
        // 453.56, not one whose space ends at 455.5.
        final trailing = k > j ? measure(j, k) : 0.0;
        final edge = tabs.rules == TabRules.uyap ? limit.ceilToDouble() : limit;
        if (pen + w + trailing > edge + _epsilon && content) {
          close();
          open(i);
        }
        // Against the same edge: a word that went up by the whole point is
        // not then cut short of it.
        while (pen + w > edge + _epsilon && j - i > 1) {
          // Wider than a whole row: cut it where it stops fitting, keeping at
          // least one character so the row moves on.
          var k = i + 1;
          while (k < j && pen + measure(i, k + 1) <= edge + _epsilon) {
            k++;
          }
          place(PieceKind.text, i, k, measure(i, k));
          close();
          open(k);
          i = k;
          w = measure(i, j);
        }
        place(PieceKind.text, i, j, w);
        i = j;
      }
    }
    close(last: true);
    if (width.isFinite) {
      for (final r in rows) {
        _align(r, limit);
      }
    }
    return rows;
  }

  void _align(ParagraphRow row, double limit) {
    final pieces = row.pieces;
    if (pieces.isEmpty) return;
    // Spaces after the last word hang: they neither count towards the row's
    // width nor get a share of it. A centred or right-aligned paragraph's own
    // closing spaces are the exception, as UYAP counts them.
    var lastContent = pieces.length - 1;
    while (lastContent >= 0 && pieces[lastContent].kind == PieceKind.space) {
      lastContent--;
    }
    if (lastContent < 0) return;
    final keepTrailing =
        row.last && (align == RowAlign.center || align == RowAlign.right);
    final contentRight = keepTrailing
        ? pieces.last.x + pieces.last.width
        : pieces[lastContent].x + pieces[lastContent].width;
    switch (align) {
      case RowAlign.left:
        return;
      case RowAlign.center:
        _shift(pieces, (limit - contentRight) / 2);
      case RowAlign.right:
        _shift(pieces, limit - contentRight);
      case RowAlign.justify:
        if (row.last) return;
        _justify(row, lastContent, limit);
    }
  }

  static void _shift(List<RowPiece> pieces, double by) {
    if (by <= 0) return;
    for (final p in pieces) {
      p.x += by;
    }
  }

  void _justify(ParagraphRow row, int lastContent, double limit) {
    final pieces = row.pieces;
    // Where the first piece sits: past the indent and anything reserved
    // ahead of the text, such as a list's number.
    final start = pieces.first.x;
    var firstContent = 0;
    while (pieces[firstContent].kind == PieceKind.space) {
      firstContent++;
    }
    var solid = 0.0;
    var runs = 0;
    for (var k = firstContent; k <= lastContent; k++) {
      final p = pieces[k];
      if (p.kind == PieceKind.space) {
        if (pieces[k - 1].kind != PieceKind.space) runs++;
      } else {
        solid += p.width;
      }
    }
    // A row with nothing to spread between is set as it stands, leading
    // spaces and all, as Flutter sets it.
    if (runs == 0) return;
    final gap = (limit - start - solid) / runs;
    if (gap <= 0) return;
    // Spaces before the first word take no room; each run of spaces between
    // two words becomes one gap.
    var x = start;
    for (var k = 0; k < pieces.length; k++) {
      final p = pieces[k];
      if (k < firstContent) {
        p
          ..x = start
          ..width = 0;
        continue;
      }
      if (k > lastContent) {
        p.x = x;
        x += p.width;
        continue;
      }
      if (p.kind == PieceKind.space) {
        // A run's share goes to its first space; the rest of the run sits at
        // its end with no width, so every run is one gap wide.
        final opens = pieces[k - 1].kind != PieceKind.space;
        p.x = x;
        p.width = opens ? gap : 0;
        x += p.width;
      } else {
        p.x = x;
        x += p.width;
      }
    }
  }

  bool _breaksRow(int c) =>
      c == _lineSeparator || (lineBreaks && c == _newline);

  bool _separator(int c) => _isSpace(c) || c == _tab || _breaksRow(c);

  /// A space a line may break at and a justified row may stretch: the plain
  /// one and the wider typographic ones, but not the no-break spaces.
  static bool isSpace(int c) =>
      c == _space ||
      (c >= 0x2000 && c <= 0x200a && c != 0x2007) ||
      c == 0x205f ||
      c == 0x3000;

  static bool _isSpace(int c) => isSpace(c);

  static const _space = 0x20,
      _tab = 0x09,
      _newline = 0x0a,
      _lineSeparator = 0x2028;
}

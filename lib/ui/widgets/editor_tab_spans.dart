import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../services/editor/spell_check.dart';
import '../../services/fonts/document_fonts.dart';
import '../../services/layout/paragraph_rows.dart';
import 'editor_citations.dart';
import 'editor_line_layout.dart';
import 'editor_spelling.dart';
import 'editor_units.dart';
import 'text_marks.dart';

/// Draws tabs at their stops instead of as single spaces.
///
/// Flutter's text engine has no notion of a tab stop: a `\t` advances by one
/// space and nothing lines up. The document itself is fine — the character
/// survives every round trip through UDF and the editor — so the whole of the
/// fix belongs here, at the point the line is turned into spans.
///
/// Each tab becomes a [WidgetSpan] as wide as the distance to its stop. A
/// WidgetSpan occupies exactly one character in the laid-out text, the same as
/// the tab it replaces, so every offset the editor computes from this span —
/// caret position, selection, hit testing — stays where it was.
///
/// Where each tab ends is not worked out here but asked of [ParagraphRows],
/// the layout the preview is drawn by, so a tab lands in the editor where it
/// lands in the preview: row by row, by UYAP's rules, with the text measured
/// the way both of them measure it (see [plainFeatures]).
class EditorTabSpans {
  /// Points to logical pixels. The editor lays the page out at the same ratio,
  /// so a stop in points arrives where the margins say it should.
  static const _pixelsPerPoint = EditorUnits.pixelsPerPoint;

  /// Letters set at their own widths, with neither kerning nor ligatures.
  ///
  /// That is how UYAP draws them — Java2D applies neither unless asked — and
  /// how the preview does. Flutter kerns by default, which drew a line of
  /// capitals up to five points shorter than the preview did, so a centred
  /// heading sat off-centre and a justified line broke in another place.
  static const plainFeatures = <FontFeature>[
    FontFeature.disable('kern'),
    FontFeature.disable('liga'),
  ];

  /// [spelling] carries what the checker last found, so a word it did not
  /// know is underlined as the line is drawn; [citations] carries the laws
  /// the document points at, so each is drawn as something to press. Either
  /// left out, that kind of mark is simply not drawn.
  ///
  /// [pageWidth] is the width of the page's text area in points, margin to
  /// margin. With it a tab that runs past the end of a row is placed on the
  /// next one, as it is printed; without it — a table cell — each paragraph
  /// is taken as one row.
  static TextSpanBuilder builder({
    SpellingMarks? spelling,
    CitationMarks? citations,
    double? pageWidth,
  }) =>
      (context, node, nodeOffset, text, style, recognizer) => _build(
        context,
        node,
        nodeOffset,
        text,
        style,
        recognizer,
        spelling,
        citations,
        pageWidth,
      );

  /// [style] with the letter widths the preview uses.
  static TextStyle plain(TextStyle style) =>
      style.copyWith(fontFeatures: [...?style.fontFeatures, ...plainFeatures]);

  /// The two kinds of mark, as one list for the splitter.
  ///
  /// A citation is offered first and so keeps its ground: TMK and İİK are not
  /// words the spelling checker knows, and a reader who has written a proper
  /// citation should see it drawn as one rather than as a mistake.
  static List<TextMark> _marksFor(
    BuildContext context,
    SpellingMarks? spelling,
    CitationMarks? citations,
  ) {
    final cited =
        citations?.textMarks(Theme.of(context).colorScheme) ??
        const <TextMark>[];
    final misspelt = spelling?.marks ?? const <Misspelling>[];
    if (misspelt.isEmpty) return cited;
    return [
      ...cited,
      for (final mark in misspelt)
        if (!cited.any((c) => mark.start < c.end && c.start < mark.end))
          TextMark(
            start: mark.start,
            length: mark.length,
            style: spellingUnderline,
          ),
    ];
  }

  /// Where the rows of [line] start after the first, on a page [pageWidth]
  /// points wide: the rows the printed page lays it out in (ParagraphRows),
  /// which the editor is then made to break at. None for a heading, a list
  /// or a line with a picture or table in it, whose rows are left to Quill.
  static List<int>? rowStarts(Line line, double pageWidth) {
    final attrs = line.style.attributes;
    // A picture or table is taken by that layout as taking no room.
    if (attrs.containsKey(Attribute.header.key) ||
        attrs.containsKey(Attribute.list.key) ||
        line.hasEmbed) {
      return null;
    }
    return _LineTabs._of(line, _body, pageWidth).rows;
  }

  /// A paragraph's own style in the page's editor: twelve point Times New
  /// Roman, laid out in points.
  static final _body = TextStyle(
    fontFamily: DocumentFonts.family('Times New Roman'),
    fontSize: 12,
  );

  static InlineSpan _build(
    BuildContext context,
    Node node,
    int nodeOffset,
    String text,
    TextStyle? style,
    GestureRecognizer? recognizer,
    SpellingMarks? spelling,
    CitationMarks? citations,
    double? pageWidth,
  ) {
    // Every run sets its own row, from its own font (see EditorLineLayout).
    // A run's own size is kept in 96 dpi pixels; the page is laid out in
    // points (see EditorUnits).
    final kept = node.style.attributes[Attribute.size.key]?.value;
    final size = kept is num ? kept.toDouble() : double.tryParse('$kept');
    style = plain(
      (style ?? const TextStyle()).copyWith(
        height: EditorLineLayout.runHeight(node),
        fontSize: size == null ? null : EditorUnits.fontSize(size),
      ),
    );
    final marks = _marksFor(context, spelling, citations);
    final line = node.parent;
    if (pageWidth != null &&
        line is Line &&
        rowStarts(line, pageWidth) != null) {
      final holds = _LineTabs._of(line, _body, pageWidth).holds;
      if (holds.isNotEmpty) {
        final units = text.codeUnits.toList();
        for (var i = 0; i < units.length; i++) {
          if (holds.contains(node.offset + i)) units[i] = 0xa0;
        }
        text = String.fromCharCodes(units);
      }
    }
    final tabs = line is Line && text.contains('\t')
        ? _LineTabs.of(context, line, pageWidth)
        : null;
    final closing = line is Line ? _closingSpaces(line, node, text) : 0;
    if (tabs == null && closing == 0) {
      final spans = markedSpans(text, node.documentOffset, style, marks);
      if (spans == null) {
        return defaultSpanBuilder(
          context,
          node,
          nodeOffset,
          text,
          style,
          recognizer,
        );
      }
      return TextSpan(style: style, recognizer: recognizer, children: spans);
    }
    final children = <InlineSpan>[];
    final body = text.length - closing;
    var start = 0;
    void flush(int end) {
      if (end <= start) return;
      final piece = text.substring(start, end);
      children.addAll(
        markedSpans(piece, node.documentOffset + start, style, marks) ??
            [TextSpan(text: piece, style: style)],
      );
    }

    WidgetSpan room(double width) => WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: SizedBox(width: width),
    );

    for (var i = 0; i < body; i++) {
      if (text.codeUnitAt(i) != 0x09) continue;
      flush(i);
      final points = tabs?.widths[node.offset + i] ?? 1 / _pixelsPerPoint;
      children.add(room(points * _pixelsPerPoint));
      start = i + 1;
    }
    flush(body);
    if (closing > 0) {
      // A centred or right-aligned paragraph's closing spaces count towards
      // its width in UYAP, as they do in the preview; Flutter lets trailing
      // spaces hang and would set the text half a space to a space further
      // right. Each is drawn as room of a space's width instead.
      final space = _width(' ', style);
      for (var i = 0; i < closing; i++) {
        children.add(room(space));
      }
    }
    return TextSpan(style: style, recognizer: recognizer, children: children);
  }

  /// Spaces closing a centred or right-aligned paragraph, if [node] holds
  /// them.
  static int _closingSpaces(Line line, Node node, String text) {
    if (node.next != null) return 0;
    final align = line.style.attributes[Attribute.align.key]?.value;
    if (align != 'center' && align != 'right') return 0;
    var count = 0;
    while (count < text.length &&
        text.codeUnitAt(text.length - 1 - count) == 0x20) {
      count++;
    }
    return count;
  }

  static double _width(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

/// Where the tabs of one line end, from the same layout the preview uses.
class _LineTabs {
  _LineTabs(this.key, this.widths, this.rows, this.holds);

  final String key;

  /// Width in points of the tab at each offset within the line.
  final Map<int, double> widths;

  /// Where each row after the first starts, as an offset in the line.
  final List<int> rows;

  /// Spaces drawn as no-break spaces (see [_holds]).
  final Set<int> holds;

  static final _cache = Expando<_LineTabs>();

  static const _pixelsPerPoint = EditorUnits.pixelsPerPoint;

  static _LineTabs of(BuildContext context, Line line, double? pageWidth) =>
      _of(
        line,
        _lineStyle(line, QuillStyles.getStyles(context, true)),
        pageWidth,
      );

  static _LineTabs _of(Line line, TextStyle base, double? pageWidth) {
    String attributes(Style style) =>
        style.attributes.values.map((a) => '${a.key}=${a.value}').join(';');
    // Everything the widths depend on, so an edit anywhere in the line lays
    // it out again and nothing else does.
    final key = [
      pageWidth,
      attributes(line.style),
      for (final leaf in line.children)
        '${leaf.toPlainText()}|${attributes(leaf.style)}',
    ].join('\u0000');
    final cached = _cache[line];
    if (cached != null && cached.key == key) return cached;
    final laid = _lay(line, base, pageWidth, key);
    _cache[line] = laid;
    return laid;
  }

  static _LineTabs _lay(
    Line line,
    TextStyle base,
    double? pageWidth,
    String key,
  ) {
    // Each leaf laid out once; a stretch of it is then the distance between
    // two caret positions, which with kerning off is the sum of its letters.
    final leaves = <({int start, String text, TextPainter? painter})>[];
    final spaces = <TextPainter>[];
    var offset = 0;
    for (final leaf in line.children) {
      if (leaf is QuillText) {
        final style = EditorTabSpans.plain(
          base.merge(_inlineStyle(leaf.style)),
        );
        leaves.add((
          start: offset,
          text: leaf.value,
          painter: TextPainter(
            text: TextSpan(text: leaf.value, style: style),
            textDirection: TextDirection.ltr,
          )..layout(),
        ));
        spaces.add(
          TextPainter(
            text: TextSpan(text: ' ', style: style),
            textDirection: TextDirection.ltr,
          )..layout(),
        );
        offset += leaf.value.length;
      } else {
        // An embed on a line with tabs is rare; it is taken as taking no room.
        leaves.add((start: offset, text: '￼', painter: null));
        spaces.add(
          TextPainter(
            text: TextSpan(text: ' ', style: EditorTabSpans.plain(base)),
            textDirection: TextDirection.ltr,
          )..layout(),
        );
        offset += leaf.length;
      }
    }
    final text = leaves.map((l) => l.text).join();
    double caret(TextPainter painter, int at) =>
        painter.getOffsetForCaret(TextPosition(offset: at), Rect.zero).dx;
    double measure(int start, int end) {
      var total = 0.0;
      for (final leaf in leaves) {
        final to = leaf.start + leaf.text.length;
        if (to <= start || leaf.painter == null) continue;
        if (leaf.start >= end) break;
        final a = (start - leaf.start).clamp(0, leaf.text.length);
        final b = (end - leaf.start).clamp(0, leaf.text.length);
        total += caret(leaf.painter!, b) - caret(leaf.painter!, a);
      }
      return total / _pixelsPerPoint;
    }

    double space(int at) {
      for (var k = 0; k < leaves.length; k++) {
        final leaf = leaves[k];
        if (at < leaf.start + leaf.text.length) {
          return spaces[k].width / _pixelsPerPoint;
        }
      }
      return spaces.isEmpty ? 3 : spaces.last.width / _pixelsPerPoint;
    }

    final indents = EditorLineLayout.indents(line);
    final align = line.style.attributes[Attribute.align.key]?.value;
    final laid = ParagraphRows(
      text: text,
      measure: measure,
      space: space,
      // A list is laid out by Quill's own leading, which this does not know.
      width: indents == null ? double.infinity : pageWidth ?? double.infinity,
      leftIndent: indents?.left ?? 0,
      rightIndent: indents?.right ?? 0,
      firstLineIndent: indents?.first ?? 0,
      hanging: indents?.hanging ?? 0,
      align: switch (align) {
        'center' => RowAlign.center,
        'right' => RowAlign.right,
        'justify' => RowAlign.justify,
        _ => RowAlign.left,
      },
      tabs: EditorLineLayout.tabsOf(line),
    ).layout();
    for (final leaf in leaves) {
      leaf.painter?.dispose();
    }
    for (final painter in spaces) {
      painter.dispose();
    }
    return _LineTabs(
      key,
      {
        for (final row in laid)
          for (final piece in row.pieces)
            if (piece.kind == PieceKind.tab) piece.start: piece.width,
      },
      [for (final row in laid.skip(1)) row.start],
      pageWidth == null || indents == null
          ? const {}
          : _holds(laid, pageWidth - indents.right),
    );
  }

  /// The spaces after a row's first word, where the row before would take
  /// that word up in Flutter but not in UYAP.
  ///
  /// UYAP keeps a word on a row only if the spaces after it fit as well;
  /// Flutter lets them hang past the edge, and breaks at any space whatever
  /// joiner stands beside it. A word that fits only without its spaces would
  /// go up in the editor and down on the page. Drawn as no-break spaces, the
  /// spaces are no longer a place to break, so the word goes down with the
  /// one after it — at the cost of that one gap not being stretched when the
  /// row is justified, which is why only these spaces are held.
  static Set<int> _holds(List<ParagraphRow> rows, double limit) {
    // The editor's line is as wide as the text area rounded up to a pixel.
    final edge = limit.ceilToDouble() + .5;
    final holds = <int>{};
    for (var k = 1; k < rows.length; k++) {
      final before = rows[k - 1];
      final pieces = rows[k].pieces;
      if (before.last || pieces.isEmpty) continue;
      final word = pieces.first;
      if (word.kind != PieceKind.text) continue;
      if (before.reach + word.width > edge) continue;
      for (final p in pieces.skip(1)) {
        if (p.kind != PieceKind.space) break;
        holds.add(p.start);
      }
    }
    return holds;
  }

  /// The style every run of [line] inherits: its heading's, or a paragraph's.
  static TextStyle _lineStyle(Line line, DefaultStyles? styles) {
    final header = line.style.attributes[Attribute.header.key]?.value;
    final block = switch (header) {
      1 => styles?.h1,
      2 => styles?.h2,
      3 => styles?.h3,
      _ => styles?.paragraph,
    };
    return block?.style ?? const TextStyle(fontSize: 12);
  }

  /// A run's own attributes as the editor draws them: the family through the
  /// fonts it registered, the size in pixels, and weight and slant only where
  /// the run says so.
  static TextStyle _inlineStyle(Style style) {
    final attrs = style.attributes;
    final size = attrs[Attribute.size.key]?.value;
    final font = attrs[Attribute.font.key]?.value;
    return TextStyle(
      fontWeight: attrs.containsKey(Attribute.bold.key)
          ? FontWeight.bold
          : null,
      fontStyle: attrs.containsKey(Attribute.italic.key)
          ? FontStyle.italic
          : null,
      fontFamily: font is String ? DocumentFonts.family(font) : null,
      fontSize: switch (size is num
          ? size.toDouble()
          : double.tryParse('$size')) {
        final double kept => EditorUnits.fontSize(kept),
        null => null,
      },
    );
  }
}

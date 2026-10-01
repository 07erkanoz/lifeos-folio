// FOLIO PATCH: characters put into a line that the document does not have:
// the room of a hanging indent, and marks that make a line break where UYAP
// breaks it.
// See third_party/flutter_quill/FOLIO_PATCH.md.
import 'package:flutter/widgets.dart';

/// Characters put into a line's laid-out text: where, as a document offset,
/// and how many. The paragraph proxy hides them from every offset the editor
/// sees; see [HangingIndent.toRender] and [HangingIndent.toDocument].
typedef LineInsertion = ({int offset, int length});

/// A single character put into a line: a word joiner or a zero-width space.
typedef LineMark = ({int offset, String mark});

/// What is put in at one place, in the order things at one place go in.
enum _Kind { indent, mark, room, end }

typedef _Item = ({int offset, _Kind kind, String mark});

/// Room ahead of every visual line of a paragraph but the first, and joins
/// after slashes and dashes.
///
/// Flutter lays a paragraph out at one width and starts every line at the
/// same place, so a hanging indent cannot be asked of it. It is drawn instead
/// by laying the line out once, finding where each visual line after the
/// first begins, and putting there a box as wide as the indent. Each box
/// comes with a no-break space too small to see, which ties it to the text
/// after it: a line may break before a box and after one, and it must not
/// end on one.
///
/// Flutter also breaks lines by other rules than UYAP, which breaks at spaces
/// and nowhere else (see ParagraphRows). It will end a line after a slash or
/// a dash inside a word — "Manavgat/" above "Antalya" — or before a bracket
/// that follows a comma, where UYAP moves the word down whole; a word joiner
/// there, drawn as nothing, takes that break away. And it will not break at a space before a slash, a colon
/// or a closing bracket, so "No:33 /Z01" and "NEDENLER :" move down as one;
/// a zero-width space there gives the break back.
class HangingIndent {
  HangingIndent._();

  /// Characters put ahead of each line after the first.
  static const width = 2;

  static const _glue = '\u00a0';
  static const _join = '\u2060';
  static const _break = '\u200b';

  /// The marks [text] needs to break where UYAP does: a join just after a
  /// slash, dash or `!?` with more of the word after it, and before an
  /// opening bracket that follows more of the word ("ettiği,(Sanıklar"); and
  /// a break just before a slash, colon, stop or closing bracket that follows
  /// a space.
  static List<LineMark> marks(String text) {
    final out = <LineMark>[];
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      final after = i > 0 ? text.codeUnitAt(i - 1) : 0x20;
      if (_space(after) && _heldToPrevious(c)) {
        out.add((offset: i, mark: _break));
      } else if (!_space(after) && _opens(c) && !_breaksAfter(after)) {
        out.add((offset: i, mark: _join));
      }
      if (i + 1 < text.length &&
          _breaksAfter(c) &&
          !_space(text.codeUnitAt(i + 1))) {
        out.add((offset: i + 1, mark: _join));
      }
      if (_opens(c) && i + 1 < text.length && text.codeUnitAt(i + 1) == 0x20) {
        // Nor after an opening bracket and its spaces: "Kiracı ( taahhüt…"
        // went down whole.
        var j = i + 1;
        while (j < text.length && text.codeUnitAt(j) == 0x20) {
          j++;
        }
        if (j < text.length && !_space(text.codeUnitAt(j))) {
          out.add((offset: j, mark: _break));
        }
      }
    }
    out.sort((a, b) => a.offset.compareTo(b.offset));
    return out;
  }

  /// Marks that let [text] break where [rows] start and nowhere else: a
  /// join before every word or tab that follows a space or a tab, before
  /// every tab and before every space that follows a dash, unless a row
  /// starts there, and a break where each row starts. The joins [marks] puts inside words stay.
  static List<LineMark> rowMarks(String text, List<int> rows) {
    final starts = rows.toSet();
    final at = <int, String>{
      for (final m in marks(text))
        if (m.mark == _join && !starts.contains(m.offset)) m.offset: m.mark,
    };
    for (var i = 1; i < text.length; i++) {
      if (starts.contains(i)) continue;
      final c = text.codeUnitAt(i);
      final before = text.codeUnitAt(i - 1);
      final opens = (before == 0x20 || before == 0x09) && c != 0x20;
      // A space after a dash may be drawn as a no-break space, to hold the
      // word before it down (see EditorTabSpans), and a line may still break
      // between a dash and a no-break space.
      final held = c == 0x20 && _breaksAfter(before);
      if (opens || held || c == 0x09) at[i] = _join;
    }
    for (final start in starts) {
      if (start > 0 && start < text.length) at[start] = _break;
    }
    return [
      for (final e in at.entries) (offset: e.key, mark: e.value),
    ]..sort((a, b) => a.offset.compareTo(b.offset));
  }

  static bool _space(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0a || c == 0x2028;

  static bool _breaksAfter(int c) =>
      c == 0x2f ||
      c == 0x2d ||
      c == 0x21 ||
      c == 0x3f ||
      (c >= 0x2010 && c <= 0x2014);

  static bool _opens(int c) => c == 0x28 || c == 0x5b || c == 0x7b;

  /// Characters Unicode keeps on the line before them even across a space
  /// (UAX #14, LB13 and LB16): closing brackets, `!`, `?`, `/` and the infix
  /// separators `,` `.` `:` `;`.
  static bool _heldToPrevious(int c) =>
      c == 0x2f ||
      c == 0x3a ||
      c == 0x3b ||
      c == 0x2c ||
      c == 0x2e ||
      c == 0x21 ||
      c == 0x3f ||
      c == 0x29 ||
      c == 0x5d ||
      c == 0x7d;

  /// [span] with its first line indent, [marks] and, where [hanging] and
  /// [width] allow, the room of a hanging indent put in; every insertion made,
  /// for the proxy; and the lines the room went ahead of, which [breaks] takes
  /// back to skip finding them again. Where a line holds something whose
  /// width is not known before it is laid out, it gets no hanging indent.
  ///
  /// A [paragraphMark] offset puts there a join in the line's own style, so
  /// the row it is on is at least as tall as that style's.
  ///
  /// The first line indent goes after the spaces [text] opens with, not
  /// before them. UYAP counts those spaces when it fills the first row and
  /// then, spreading a justified row, gives them no room; Flutter does the
  /// same with spaces at the very start of a line, and only there.
  static ({
    InlineSpan span,
    List<LineInsertion> insertions,
    List<int> breaks,
  })
  apply({
    required InlineSpan span,
    required String text,
    required List<LineMark> marks,
    required double firstLine,
    required double hanging,
    required double? width,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required StrutStyle? strutStyle,
    List<int>? breaks,
    Locale? locale,
    int? paragraphMark,
  }) {
    var opening = 0;
    if (firstLine > 0) {
      while (opening < text.length && text.codeUnitAt(opening) == 0x20) {
        opening++;
      }
    }
    List<_Item> items(List<int> rows) => [
          if (firstLine > 0) (offset: opening, kind: _Kind.indent, mark: ''),
          for (final m in marks)
            (offset: m.offset, kind: _Kind.mark, mark: m.mark),
          for (final at in rows) (offset: at, kind: _Kind.room, mark: ''),
          if (paragraphMark != null)
            (offset: paragraphMark, kind: _Kind.end, mark: _join),
        ]..sort((a, b) => a.offset != b.offset
            ? a.offset.compareTo(b.offset)
            : a.kind.index.compareTo(b.kind.index));
    ({InlineSpan span, List<LineInsertion> insertions, List<int> breaks})
        done(List<int> rows) {
      final all = items(rows);
      return (
        span: _insert(span, all, firstLine, hanging),
        insertions: List.unmodifiable(_insertions(all)),
        breaks: List.unmodifiable(rows),
      );
    }

    if (breaks != null) return done(breaks);
    if (hanging <= 0 || width == null || !width.isFinite || width <= 0) {
      return done(const []);
    }
    final rows = <int>[];
    // Each round finds one more line to indent; indenting it can only move
    // the lines after it.
    for (var round = 0; round < 256; round++) {
      final all = items(rows);
      final built = _insert(span, all, firstLine, hanging);
      final dimensions = _dimensions(built);
      if (dimensions == null) return done(const []);
      final painter = TextPainter(
        text: built,
        textDirection: textDirection,
        textScaler: textScaler,
        strutStyle: strutStyle,
        locale: locale,
      )
        ..setPlaceholderDimensions(dimensions)
        ..layout(maxWidth: width);
      int? next;
      final inserted = _insertions(all);
      final lines = painter.computeLineMetrics();
      for (var i = 1; i < lines.length && next == null; i++) {
        final line = lines[i];
        final at = painter
            .getPositionForOffset(Offset(0, line.baseline - line.ascent / 2))
            .offset;
        final start = painter.getLineBoundary(TextPosition(offset: at)).start;
        final offset = toDocument(start, 0, inserted);
        if (offset > 0 && !rows.contains(offset)) next = offset;
      }
      painter.dispose();
      if (next == null) return done(rows);
      rows
        ..add(next)
        ..sort();
    }
    return done(const []);
  }

  static List<LineInsertion> _insertions(List<_Item> items) => [
        for (final item in items)
          (offset: item.offset, length: item.kind == _Kind.room ? width : 1),
      ];

  /// Everything in [span] that decides where its lines break: its text, the
  /// font, size, weight, slant and spacing of each run, and the width of each
  /// box. Two spans with one key are laid out alike.
  static String layoutKey(InlineSpan span) {
    final key = StringBuffer();
    void style(TextStyle? s) {
      if (s == null) return;
      key
        ..write(s.fontFamily)
        ..write(',')
        ..write(s.fontSize)
        ..write(',')
        ..write(s.fontWeight?.value)
        ..write(',')
        ..write(s.fontStyle?.index)
        ..write(',')
        ..write(s.height)
        ..write(',')
        ..write(s.letterSpacing)
        ..write(',')
        ..write(s.wordSpacing)
        ..write(',')
        ..write(s.fontFeatures?.length);
    }

    void walk(InlineSpan node) {
      key.write('{');
      style(node.style);
      if (node is WidgetSpan) {
        final box = node.child;
        key.write(box is SizedBox ? '|${box.width}' : '|?');
      } else if (node is TextSpan) {
        key
          ..write('|')
          ..write(node.text ?? '');
        for (final child in node.children ?? const <InlineSpan>[]) {
          walk(child);
        }
      }
      key.write('}');
    }

    walk(span);
    return key.toString();
  }

  /// The document offset of [render], a position in text laid out with
  /// [leading] placeholders ahead of it and [items] put in. A position inside
  /// an insertion is the offset it was put before.
  static int toDocument(int render, int leading, List<LineInsertion> items) {
    final position = render - leading;
    if (position <= 0) return 0;
    var added = 0;
    for (final item in items) {
      final at = item.offset + added;
      if (position < at) break;
      if (position < at + item.length) return item.offset;
      added += item.length;
    }
    return position - added;
  }

  /// Where the document offset [offset] is in the laid out text.
  static int toRender(int offset, int leading, List<LineInsertion> items) {
    var render = offset + leading;
    for (final item in items) {
      if (item.offset > offset) break;
      render += item.length;
    }
    return render;
  }

  /// [span] with each of [items], in order, put before the character at its
  /// offset: a first line indent [firstLine] wide, a mark, or the room of a
  /// hanging indent [hanging] wide. One at the very end goes after the text.
  static InlineSpan _insert(
    InlineSpan span,
    List<_Item> items,
    double firstLine,
    double hanging,
  ) {
    if (items.isEmpty) return span;
    var offset = 0;
    var next = 0;
    List<InlineSpan> room(_Item item) => switch (item.kind) {
          _Kind.indent => [WidgetSpan(child: SizedBox(width: firstLine))],
          _Kind.mark => [TextSpan(text: item.mark)],
          _Kind.room => [
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: SizedBox(width: hanging),
              ),
              const TextSpan(text: _glue, style: TextStyle(fontSize: .01)),
            ],
          _Kind.end => [TextSpan(text: item.mark, style: span.style)],
        };

    InlineSpan walk(InlineSpan node) {
      if (node is WidgetSpan) {
        // Something put before a box goes ahead of it.
        final before = <InlineSpan>[];
        while (next < items.length && items[next].offset <= offset) {
          before.addAll(room(items[next]));
          next++;
        }
        offset += 1;
        return before.isEmpty
            ? node
            : TextSpan(children: [...before, node]);
      }
      if (node is! TextSpan) return node;
      final text = node.text;
      final parts = <InlineSpan>[];
      if (text != null && text.isNotEmpty) {
        var from = 0;
        while (next < items.length &&
            items[next].offset < offset + text.length) {
          final item = items[next];
          final at = item.offset - offset;
          next++;
          if (at < from) continue;
          if (at > from) parts.add(_piece(node, text.substring(from, at)));
          parts.addAll(room(item));
          from = at;
        }
        if (parts.isNotEmpty && from < text.length) {
          parts.add(_piece(node, text.substring(from)));
        }
        offset += text.length;
      }
      final children = node.children;
      final walked = children == null
          ? null
          : [for (final child in children) walk(child)];
      if (parts.isEmpty) {
        if (walked == null) return node;
        return TextSpan(
          text: text,
          style: node.style,
          recognizer: node.recognizer,
          mouseCursor: node.mouseCursor,
          semanticsLabel: node.semanticsLabel,
          locale: node.locale,
          spellOut: node.spellOut,
          children: walked,
        );
      }
      return TextSpan(
        style: node.style,
        locale: node.locale,
        spellOut: node.spellOut,
        children: [...parts, ...?walked],
      );
    }

    final walked = walk(span);
    if (next >= items.length) return walked;
    return TextSpan(
      style: walked.style,
      children: [
        walked,
        for (final item in items.skip(next)) ...room(item),
      ],
    );
  }

  /// A stretch of [node]'s own text, keeping what makes it pressable.
  static TextSpan _piece(TextSpan node, String text) => TextSpan(
        text: text,
        recognizer: node.recognizer,
        mouseCursor: node.mouseCursor,
      );

  /// The size of every box in [span], in order, or null if one is not a box
  /// of known width.
  static List<PlaceholderDimensions>? _dimensions(InlineSpan span) {
    final out = <PlaceholderDimensions>[];
    var known = true;
    span.visitChildren((child) {
      if (child is! WidgetSpan) return true;
      final box = child.child;
      if (box is! SizedBox || box.width == null || box.child != null) {
        known = false;
        return false;
      }
      out.add(PlaceholderDimensions(
        size: Size(box.width!, box.height ?? 0),
        alignment: child.alignment,
        baseline: child.baseline,
        baselineOffset: child.alignment == PlaceholderAlignment.baseline
            ? box.height ?? 0
            : null,
      ));
      return true;
    });
    return known ? out : null;
  }
}

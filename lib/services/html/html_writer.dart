import 'dart:convert';
import 'dart:typed_data';

import '../../models/document_model.dart';
import '../editor/doc_delta_map.dart';
import '../editor/tab_stops.dart';

/// Writes a document model as HTML for the clipboard.
///
/// Word, LibreOffice, Google Docs and every browser take HTML, and each reads
/// only what is written on the element itself, so every paragraph and every
/// run carries its whole style inline: no stylesheet to lose, no class to
/// resolve. A tab is written the way Word and Google Docs both read one — a
/// tab character that keeps its width — and runs of spaces as non-breaking
/// ones, since HTML otherwise collapses them into one.
abstract final class HtmlWriter {
  /// Where Folio's own copy of the content travels: a meta element in the
  /// head, which every program ignores and [RichClipboard] looks for first.
  static const folioMeta = 'folio-clipboard';

  /// A whole HTML document around the content, marked the way Windows and
  /// Chrome mark the part that was copied.
  static String document(DocModel model, {String? folio}) {
    final out = StringBuffer()
      ..write('<html><head><meta charset="utf-8">')
      ..write('<meta name="generator" content="LifeOS Folio">');
    if (folio != null) out.write('<meta name="$folioMeta" content="$folio">');
    out
      ..write('</head><body>')
      ..write('<!--StartFragment-->')
      ..write(fragment(model))
      ..write('<!--EndFragment-->')
      ..write('</body></html>');
    return out.toString();
  }

  /// The content alone.
  static String fragment(DocModel model) {
    final out = StringBuffer();
    final openEnd = model.metadata['openEnd'] == true;
    _blocks(
      out,
      model.blocks,
      openEnd: openEnd,
      wordTabs: model.metadata['tabRules'] == 'word',
    );
    return out.toString();
  }

  /// Windows' "HTML Format": the document behind a header giving the byte
  /// offsets of the document and of the copied fragment in it.
  static Uint8List cfHtml(String html) {
    const start = '<!--StartFragment-->';
    const end = '<!--EndFragment-->';
    final body = utf8.encode(html);
    final fragmentStart = utf8
        .encode(html.substring(0, html.indexOf(start) + start.length))
        .length;
    final fragmentEnd = utf8
        .encode(html.substring(0, html.indexOf(end)))
        .length;
    String header(int offset) =>
        'Version:0.9\r\n'
        'StartHTML:${_pad(offset)}\r\n'
        'EndHTML:${_pad(offset + body.length)}\r\n'
        'StartFragment:${_pad(offset + fragmentStart)}\r\n'
        'EndFragment:${_pad(offset + fragmentEnd)}\r\n';
    // Every number is ten digits, so the header's length is known up front.
    final length = header(0).length;
    return Uint8List.fromList([...ascii.encode(header(length)), ...body]);
  }

  static String _pad(int value) => value.toString().padLeft(10, '0');

  static void _blocks(
    StringBuffer out,
    List<DocBlock> blocks, {
    bool openEnd = false,
    bool wordTabs = false,
  }) {
    Map<String, String> style(DocBlock b) =>
        _paragraphStyle(b, wordTabs: wordTabs);
    // Open lists, innermost last: the tag each level was opened with.
    final lists = <String>[];
    void closeLists([int depth = 0]) {
      while (lists.length > depth) {
        out.write('</${lists.removeLast()}>');
      }
    }

    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final last = i == blocks.length - 1;
      if (block.type == DocBlockType.table && block.table != null) {
        closeLists();
        _table(out, block, wordTabs: wordTabs);
        continue;
      }
      if (block.type == DocBlockType.image && block.imageBase64 != null) {
        closeLists();
        out.write('<p${_style(style(block))}>');
        _image(out, block);
        out.write('</p>');
        continue;
      }
      if (block.listType != DocListType.none) {
        final tag = block.listType == DocListType.ordered ? 'ol' : 'ul';
        final depth = block.listLevel.clamp(0, 8) + 1;
        if (lists.length > depth) closeLists(depth);
        if (lists.length == depth && lists.last != tag) closeLists(depth - 1);
        while (lists.length < depth) {
          lists.add(tag);
          out.write('<$tag style="margin-top:0pt;margin-bottom:0pt">');
        }
        out.write('<li${_style(style(block))}>');
        _runs(out, block);
        out.write('</li>');
        continue;
      }
      closeLists();
      // A copy that stopped inside its last paragraph gives that paragraph's
      // runs alone, as a browser does: wrapped in a paragraph, the text would
      // arrive as one wherever it is pasted.
      if (last && openEnd && blocks.length == 1) {
        _runs(out, block);
        continue;
      }
      final heading = DocDeltaMap.headingLevelOf(block.styleName);
      final tag = heading == null ? 'p' : 'h$heading';
      out.write('<$tag${_style(style(block))}>');
      _runs(out, block);
      out.write('</$tag>');
    }
    closeLists();
  }

  static Map<String, String> _paragraphStyle(
    DocBlock b, {
    bool wordTabs = false,
  }) {
    // UYAP's hanging indent moves every row but the first; in CSS the left
    // margin is where the other rows start and the first line is set off
    // from it, as Word's own HTML does.
    final left = b.leftIndent + b.hanging;
    final first = b.firstLineIndent - b.hanging;
    final stops = _tabStops(b, word: wordTabs);
    return {
      'tab-stops': ?stops,
      'margin-top': _pt(b.spacingBefore),
      'margin-bottom': _pt(b.spacingAfter),
      if (left != 0) 'margin-left': _pt(left),
      if (b.rightIndent != 0) 'margin-right': _pt(b.rightIndent),
      if (first != 0) 'text-indent': _pt(first),
      if (b.alignment != DocAlignment.left)
        'text-align': switch (b.alignment) {
          DocAlignment.center => 'center',
          DocAlignment.right => 'right',
          DocAlignment.justify => 'justify',
          DocAlignment.left => 'left',
        },
      if (b.lineSpacing != null && (b.lineSpacing! - 1).abs() > .001)
        'line-height': '${(b.lineSpacing! * 100).round()}%',
    };
  }

  /// Word's `tab-stops`, which it reads back from HTML: positions from the
  /// margin, each after its alignment. UYAP counts its stops from the left
  /// indent, a Word document from the margin already.
  static String? _tabStops(DocBlock block, {required bool word}) {
    final stops = TabStops.parse(block.tabSet).stops;
    if (stops.isEmpty) return null;
    return [
      for (final stop in stops)
        [
          switch (stop.align) {
            TabAlign.right => 'right ',
            TabAlign.centre => 'center ',
            TabAlign.decimal => 'decimal ',
            TabAlign.bar => 'bar ',
            TabAlign.left => '',
          },
          _pt(word ? stop.position : block.leftIndent + stop.position),
        ].join(),
    ].join(' ');
  }

  static void _runs(StringBuffer out, DocBlock block) {
    final text = block.plainText;
    if (text.isEmpty) {
      // An empty paragraph still takes a line.
      out.write('<br>');
      return;
    }
    final edges = <int>{0, text.length};
    for (final span in block.spans) {
      edges.add(span.startOffset.clamp(0, text.length));
      edges.add(span.endOffset.clamp(0, text.length));
    }
    final sorted = edges.toList()..sort();
    var atLineStart = true;
    for (var i = 0; i + 1 < sorted.length; i++) {
      final start = sorted[i], end = sorted[i + 1];
      if (end <= start) continue;
      DocSpan? style;
      for (final span in block.spans) {
        if (span.startOffset <= start && span.endOffset >= end) style = span;
      }
      final css = style == null ? const <String, String>{} : _runStyle(style);
      out.write('<span${_style(css)}>');
      atLineStart = _text(out, text, start, end, atLineStart);
      out.write('</span>');
    }
  }

  static Map<String, String> _runStyle(DocSpan s) => {
    if (s.fontFamily != null) 'font-family': _family(s.fontFamily!),
    if (s.fontSize != null) 'font-size': _pt(s.fontSize!),
    if (s.bold) 'font-weight': 'bold',
    if (s.italic) 'font-style': 'italic',
    if (s.underline || s.strikethrough)
      'text-decoration': [
        if (s.underline) 'underline',
        if (s.strikethrough) 'line-through',
      ].join(' '),
    if (s.color != null) 'color': s.color!,
    if (s.background != null) 'background-color': s.background!,
    if (s.superscript) 'vertical-align': 'super',
    if (s.subscript) 'vertical-align': 'sub',
  };

  /// Writes [text] so that what HTML would collapse survives: a tab keeps its
  /// width, a run of spaces stays a run and a line break breaks the line.
  /// Returns whether the text ends at the start of a line.
  static bool _text(
    StringBuffer out,
    String text,
    int from,
    int to,
    bool atLineStart,
  ) {
    var lineStart = atLineStart;
    for (var i = from; i < to; i++) {
      final c = text[i];
      switch (c) {
        case '\t':
          // Word counts the tab from mso-tab-count, a browser keeps the
          // character itself.
          out.write('<span style="mso-tab-count:1;white-space:pre">\t</span>');
          lineStart = false;
        case '\n' || '\u2028':
          out.write('<br>');
          lineStart = true;
        case ' ':
          // A space at the start of a line, or after another space, is a
          // non-breaking one; the last of a run stays breakable.
          // So is the paragraph's last one, which HTML would not draw. The
          // next character is looked at across runs: two spaces in two
          // runs collapse just the same.
          final next = i + 1 < text.length ? text[i + 1] : '';
          out.write(
            lineStart || next == ' ' || next == '\n' || next.isEmpty
                ? '&nbsp;'
                : ' ',
          );
          lineStart = false;
        case '&':
          out.write('&amp;');
          lineStart = false;
        case '<':
          out.write('&lt;');
          lineStart = false;
        case '>':
          out.write('&gt;');
          lineStart = false;
        case '\u200b' || '\u2060':
          // The editor's own zero-width marks.
          break;
        default:
          out.write(c);
          lineStart = false;
      }
    }
    return lineStart;
  }

  static void _table(
    StringBuffer out,
    DocBlock block, {
    required bool wordTabs,
  }) {
    final table = block.table!;
    final widths = table.columnWidths;
    final total = widths?.fold<double>(0, (a, b) => a + b) ?? 0;
    final border = table.bordered
        ? 'border:0.5pt solid #000000;'
        : 'border:none;';
    out.write(
      '<table style="border-collapse:collapse;width:100%" '
      'cellspacing="0" cellpadding="0">',
    );
    for (final row in table.rows) {
      out.write('<tr>');
      var column = 0;
      for (final cell in row.cells) {
        final tag = row.isHeader ? 'th' : 'td';
        final width = widths != null && total > 0 && column < widths.length
            ? widths
                      .skip(column)
                      .take(cell.colspan)
                      .fold<double>(0, (a, b) => a + b) /
                  total *
                  100
            : null;
        column += cell.colspan;
        out.write('<$tag');
        if (cell.colspan > 1) out.write(' colspan="${cell.colspan}"');
        if (cell.rowspan > 1) out.write(' rowspan="${cell.rowspan}"');
        out.write(
          ' style="${border}padding:0pt 5.4pt;vertical-align:top;'
          'text-align:left;font-weight:normal',
        );
        if (width != null) out.write(';width:${width.toStringAsFixed(1)}%');
        if (cell.backgroundColor != null) {
          out.write(';background-color:${cell.backgroundColor}');
        }
        out.write('">');
        _blocks(
          out,
          cell.blocks.isEmpty ? [DocBlock(plainText: '')] : cell.blocks,
          wordTabs: wordTabs,
        );
        out.write('</$tag>');
      }
      out.write('</tr>');
    }
    out.write('</table>');
  }

  static void _image(StringBuffer out, DocBlock block) {
    final mime = block.imageMime ?? 'image/png';
    out.write('<img src="data:$mime;base64,${block.imageBase64}"');
    // Points on the page, pixels in HTML.
    if (block.imageWidth != null) {
      out.write(' width="${(block.imageWidth! * 96 / 72).round()}"');
    }
    if (block.imageHeight != null) {
      out.write(' height="${(block.imageHeight! * 96 / 72).round()}"');
    }
    out.write('>');
  }

  static String _style(Map<String, String> css) => css.isEmpty
      ? ''
      : ' style="${_attribute(css.entries.map((e) => '${e.key}:${e.value}').join(';'))}"';

  static String _attribute(String value) =>
      value.replaceAll('&', '&amp;').replaceAll('"', '&quot;');

  /// A family as CSS takes it, quoted, with the generic fallback a reader
  /// without the font should draw instead.
  static String _family(String family) {
    final generic =
        RegExp(r'courier|mono|consol', caseSensitive: false).hasMatch(family)
        ? 'monospace'
        : RegExp(
                r'times|serif|georgia|garamond|cambria|book',
                caseSensitive: false,
              ).hasMatch(family) &&
              !RegExp(r'sans', caseSensitive: false).hasMatch(family)
        ? 'serif'
        : 'sans-serif';
    return "'${family.replaceAll("'", '')}',$generic";
  }

  static String _pt(double value) {
    final rounded = (value * 100).round() / 100;
    final text = rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toString();
    return '${text}pt';
  }
}

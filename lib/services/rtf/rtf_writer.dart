import 'dart:convert';

import '../../models/document_model.dart';
import '../layout/page_numbers.dart';
import '../editor/tab_stops.dart';

/// Writes Rich Text Format.
///
/// Everything outside plain ASCII is written as a `\uNNNN` escape rather than
/// as bytes in a codepage. It costs a few characters and removes the entire
/// class of bug the reader has to defend against: a file written here reads
/// the same whether the machine that opens it is Turkish, Polish or neither.
class RtfWriter {
  /// RTF measures in twentieths of a point.
  static const _twip = 20;

  static List<int> writeBytes(DocModel model) =>
      latin1.encode(write(model).replaceAll(RegExp(r'[^\x00-\xff]'), '?'));

  static String write(DocModel model) {
    final fonts = <String>['Times New Roman'];
    final colors = <String>[];
    // Where the writing goes: the body, or while one is written, a header
    // or footer of its own.
    var body = StringBuffer();
    var number = 0;
    // UYAP counts a stop from the left indent, RTF from the margin; a Word
    // document's stops already count from the margin.
    final wordTabs = model.metadata['tabRules'] == 'word';

    int fontIndex(String? family) {
      if (family == null || family.isEmpty) return 0;
      final at = fonts.indexOf(family);
      if (at >= 0) return at;
      fonts.add(family);
      return fonts.length - 1;
    }

    int? colorIndex(String? color) {
      if (color == null || color.isEmpty) return null;
      final at = colors.indexOf(color);
      if (at >= 0) return at + 1;
      colors.add(color);
      return colors.length;
    }

    void runs(DocBlock block) {
      final text = block.plainText;
      final edges = <int>{0, text.length};
      for (final span in block.spans) {
        edges.add(span.startOffset.clamp(0, text.length));
        edges.add((span.startOffset + span.length).clamp(0, text.length));
      }
      final sorted = edges.toList()..sort();
      for (var i = 0; i + 1 < sorted.length; i++) {
        final start = sorted[i], end = sorted[i + 1];
        if (end <= start) continue;
        DocSpan? style;
        for (final span in block.spans) {
          if (span.startOffset <= start && span.endOffset >= end) style = span;
        }
        body.write('{');
        var controls = false;
        void control(String word) {
          body.write(word);
          controls = true;
        }

        if (style != null) {
          if (style.bold) control('\\b');
          if (style.italic) control('\\i');
          if (style.underline) control('\\ul');
          if (style.strikethrough) control('\\strike');
          if (style.superscript) control('\\super');
          if (style.subscript) control('\\sub');
          if (style.fontFamily != null) {
            control('\\f${fontIndex(style.fontFamily)}');
          }
          if (style.fontSize != null) {
            control('\\fs${(style.fontSize! * 2).round()}');
          }
          final color = colorIndex(style.color);
          if (color != null) control('\\cf$color');
          final background = colorIndex(style.background);
          if (background != null) control('\\highlight$background');
        }
        // The space after a control word is its delimiter; without one in
        // front of it there is nothing to delimit, and the space would be
        // text.
        if (controls) body.write(' ');
        body.write(escape(text.substring(start, end)));
        body.write('}');
      }
    }

    void paragraph(DocBlock block, {bool inCell = false}) {
      body.write('\\pard');
      if (inCell) body.write('\\intbl');
      final tabs = TabStops.parse(block.tabSet);
      for (final stop in tabs.stops) {
        final at =
            ((wordTabs ? stop.position : block.leftIndent + stop.position) *
                    _twip)
                .round();
        body.write(switch (stop.align) {
          TabAlign.right => '\\tqr\\tx$at',
          TabAlign.centre => '\\tqc\\tx$at',
          TabAlign.decimal => '\\tqdec\\tx$at',
          TabAlign.bar => '\\tb$at',
          TabAlign.left => '\\tx$at',
        });
      }
      body.write(switch (block.alignment) {
        DocAlignment.center => '\\qc',
        DocAlignment.right => '\\qr',
        DocAlignment.justify => '\\qj',
        DocAlignment.left => '\\ql',
      });
      // UYAP's hanging indent moves the rows after the first; RTF, like
      // Word, sets the left indent where those rows start and the first line
      // off from it.
      final left = block.leftIndent + block.hanging;
      final first = block.firstLineIndent - block.hanging;
      if (left != 0) body.write('\\li${(left * _twip).round()}');
      if (block.rightIndent != 0) {
        body.write('\\ri${(block.rightIndent * _twip).round()}');
      }
      if (first != 0) body.write('\\fi${(first * _twip).round()}');
      if (block.spacingBefore != 0) {
        body.write('\\sb${(block.spacingBefore * _twip).round()}');
      }
      if (block.spacingAfter != 0) {
        body.write('\\sa${(block.spacingAfter * _twip).round()}');
      }
      if (block.lineSpacing != null) {
        body.write('\\sl${(block.lineSpacing! * 240).round()}\\slmult1');
      }
      if (block.listType != DocListType.none) {
        // RTF's own paragraph numbering, which every reader of RTF since
        // Word 6 understands, and the marker as text for one that does not.
        final ordered = block.listType == DocListType.ordered;
        body.write(
          ordered
              ? '{\\*\\pn\\pnlvlbody\\pndec\\pnstart1\\pnindent360{\\pntxta .}}'
              : '{\\*\\pn\\pnlvlblt\\pnf0\\pnindent360{\\pntxtb \\u8226?}}',
        );
        body.write(
          ordered ? '{\\pntext ${++number}.\\tab}' : '{\\pntext \\u8226?\\tab}',
        );
      } else {
        number = 0;
      }
      runs(block);
    }

    void table(DocTable value) {
      final widths = value.columnWidths;
      for (final row in value.rows) {
        body.write('\\trowd');
        var edge = 0.0;
        for (var c = 0; c < row.cells.length; c++) {
          edge += widths != null && c < widths.length && widths[c] > 0
              ? widths[c]
              : 468 / row.cells.length; // The text column, shared out.
          body.write('\\cellx${(edge * _twip).round()}');
        }
        for (final cell in row.cells) {
          final blocks = cell.blocks.isEmpty
              ? [DocBlock(plainText: '')]
              : cell.blocks;
          for (final block in blocks) {
            paragraph(block, inCell: true);
          }
          body.write('\\cell');
        }
        body.write('\\row\n');
      }
      body.write('\\pard\n');
    }

    void blocks(List<DocBlock> all, {bool openEnd = false}) {
      for (final (i, block) in all.indexed) {
        if (block.type == DocBlockType.table && block.table != null) {
          table(block.table!);
          continue;
        }
        if (block.type == DocBlockType.image && block.imageBase64 != null) {
          _picture(body, block);
          continue;
        }
        paragraph(block);
        if (openEnd && i == all.length - 1) {
          body.write('\n');
        } else {
          body.write('\\par\n');
        }
      }
    }

    // A page number as a paragraph of its own at the top or the bottom of
    // its region, aligned as UYAP draws it, with RTF's own fields.
    void pageNumber(PageNumbering n, {bool framed = false}) {
      body.write('\\pard\\plain');
      // Over the region's text, as UYAP draws it: a frame at the region's
      // top that the text runs through.
      if (framed) {
        body.write(switch (n.align) {
          PageNumberAlign.left => '\\pvpara\\phmrg\\posxl\\posy0\\wrapthrough',
          PageNumberAlign.center =>
            '\\pvpara\\phmrg\\posxc\\posy0\\wrapthrough',
          PageNumberAlign.right => '\\pvpara\\phmrg\\posxr\\posy0\\wrapthrough',
        });
      }
      body
        ..write(switch (n.align) {
          PageNumberAlign.left => '\\ql',
          PageNumberAlign.center => '\\qc',
          PageNumberAlign.right => '\\qr',
        })
        ..write('{\\f${fontIndex(n.fontFace)}\\fs${(n.fontSize * 2).round()}')
        ..write(n.bold ? '\\b' : '')
        ..write(n.italic ? '\\i' : '')
        ..write(' ${escape(n.prefix)}')
        ..write('{\\field{\\*\\fldinst PAGE}{\\fldrslt 1}}');
      if (n.withTotal) {
        body
          ..write(escape(n.separator))
          ..write('{\\field{\\*\\fldinst NUMPAGES}{\\fldrslt 1}}');
      }
      body.write('${escape(n.suffix)}}\\par\n');
    }

    // The header and footer, written as a group of their own ahead of the
    // text, on the pages their startPage and stopPage leave them: a first
    // page of its own (\\titlepg) when either differs there.
    final regions = StringBuffer();
    final allAttrs = model.metadata['pageRegionAttrs'];
    final placed = <(String kind, String written, bool first, bool later)>[];
    for (final kind in ['header', 'footer']) {
      final key = [
        kind,
        'odd_page_$kind',
        'first_page_$kind',
      ].where(model.pageRegions.containsKey).firstOrNull;
      if (key == null) continue;
      final attrs = allAttrs is Map ? allAttrs[key] : null;
      final regionAttrs = attrs is Map ? attrs : null;
      final numbering = PageNumbering.parse(regionAttrs);
      final saved = body;
      body = StringBuffer();
      final region = model.pageRegions[key]!;
      if (numbering != null && PageNumbering.onlyNumber(region)) {
        // Nothing but the number, which UYAP draws over the empty line.
        pageNumber(numbering);
      } else {
        if (numbering != null && numbering.top) {
          pageNumber(numbering, framed: true);
        }
        blocks(region);
        if (numbering != null && !numbering.top) pageNumber(numbering);
      }
      placed.add((
        kind,
        body.toString(),
        PageNumbering.regionShows(regionAttrs, 1),
        PageNumbering.regionShows(regionAttrs, 2),
      ));
      body = saved;
    }
    final titlePage = placed.any((r) => r.$3 != r.$4);
    for (final (kind, written, first, later) in placed) {
      if (later || !titlePage) regions.write('{\\$kind $written}\n');
      if (titlePage) {
        regions.write('{\\${kind}f ${first ? written : ''}}\n');
      }
    }

    // A copy that stopped inside its last paragraph leaves that paragraph
    // open, so the reader carries it on into the one it is pasted into.
    blocks(model.blocks, openEnd: model.metadata['openEnd'] == true);

    final page = model.pageProperties;
    // Where a tab goes with no stop of its own: every 72 points in UYAP, at
    // the document's own interval in a Word document.
    final interval = model.metadata['tabRules'] == 'word'
        ? (model.metadata['defaultTabStop'] as num?)?.toDouble() ?? 36
        : TabStops.defaultInterval;
    final head = StringBuffer()
      ..write('{\\rtf1\\ansi\\ansicpg1254\\uc1\\deff0')
      ..write('\\deftab${(interval * _twip).round()}\n')
      ..write('{\\fonttbl')
      ..writeAll([
        for (var i = 0; i < fonts.length; i++)
          '{\\f$i\\fcharset162 ${escape(fonts[i])};}',
      ])
      ..write('}\n');
    if (colors.isNotEmpty) {
      head.write('{\\colortbl;');
      for (final color in colors) {
        final value = int.tryParse(color.replaceFirst('#', ''), radix: 16) ?? 0;
        head.write(
          '\\red${(value >> 16) & 0xff}'
          '\\green${(value >> 8) & 0xff}'
          '\\blue${value & 0xff};',
        );
      }
      head.write('}\n');
    }
    head
      ..write('\\paperw${((page.landscape ? 841.89 : 595.28) * _twip).round()}')
      ..write('\\paperh${((page.landscape ? 595.28 : 841.89) * _twip).round()}')
      ..write('\\margl${(page.marginLeft * _twip).round()}')
      ..write('\\margr${(page.marginRight * _twip).round()}')
      ..write('\\margt${(page.marginTop * _twip).round()}')
      ..write('\\margb${(page.marginBottom * _twip).round()}')
      ..write('\\headery${(page.headerOffset * _twip).round()}')
      ..write('\\footery${(page.footerOffset * _twip).round()}')
      ..write(titlePage ? '\\titlepg\n' : '\n');
    return '$head$regions$body}';
  }

  static void _picture(StringBuffer body, DocBlock block) {
    final data = base64Decode(block.imageBase64!);
    final kind = block.imageMime == 'image/jpeg' ? 'jpegblip' : 'pngblip';
    // A paragraph of its own, in its own alignment: left to carry on from
    // the one before, it took that one's indents and frame with it.
    body
      ..write('\\pard\\plain')
      ..write(switch (block.alignment) {
        DocAlignment.center => '\\qc',
        DocAlignment.right => '\\qr',
        _ => '\\ql',
      })
      ..write('{\\pict\\$kind');
    if (block.imageWidth != null) {
      body.write('\\picwgoal${(block.imageWidth! * _twip).round()}');
    }
    if (block.imageHeight != null) {
      body.write('\\pichgoal${(block.imageHeight! * _twip).round()}');
    }
    body.write(' ');
    for (final byte in data) {
      body.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    body.write('}\\par\n');
  }

  /// RTF's three special characters, and everything a codepage could get
  /// wrong.
  static String escape(String text) {
    final out = StringBuffer();
    for (final rune in text.runes) {
      switch (rune) {
        case 0x5c:
          out.write('\\\\');
        case 0x7b:
          out.write('\\{');
        case 0x7d:
          out.write('\\}');
        case 0x09:
          out.write('\\tab ');
        case 0x0a:
        case 0x0d:
          out.write('\\line ');
        default:
          if (rune < 0x80) {
            out.writeCharCode(rune);
          } else if (rune <= 0xffff) {
            // Signed 16-bit, followed by the one character a reader that
            // cannot do Unicode should show instead.
            out.write('\\u${rune > 32767 ? rune - 65536 : rune}?');
          } else {
            // Outside the basic plane: two escapes, one per surrogate.
            final value = rune - 0x10000;
            final high = 0xd800 + (value >> 10);
            final low = 0xdc00 + (value & 0x3ff);
            out.write('\\u${high > 32767 ? high - 65536 : high}?');
            out.write('\\u${low > 32767 ? low - 65536 : low}?');
          }
      }
    }
    return out.toString();
  }
}

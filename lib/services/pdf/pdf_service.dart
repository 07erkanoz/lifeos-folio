import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show Matrix4;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/document_model.dart';
import '../fonts/document_fonts.dart';
import '../fonts/font_line_metrics.dart';
import '../editor/doc_delta_map.dart';
import '../editor/tab_stops.dart';
import '../layout/paragraph_rows.dart';
import '../layout/image_box.dart';
import '../layout/list_markers.dart';
import '../layout/page_numbers.dart';
import '../layout/table_columns.dart';

class PdfService {
  static bool isHeading(String line) {
    final value = line.trim();
    if (value.length < 3 || value.length > 130) return false;
    final letters = value.replaceAll(RegExp(r'[^A-Za-zÇĞİÖŞÜçğıöşü]'), '');
    return letters.isNotEmpty &&
        value == value.toUpperCase() &&
        value != value.toLowerCase();
  }

  static Future<Uint8List> modelToPdfBytes(
    DocModel model, {
    String? title,
  }) async => compute(_renderPdf, await _request(model, title));

  /// Every body row the PDF draws for [model]: which block, which row of
  /// it, how tall with its spacing, and the offset it starts at. For tests
  /// that hold the layout against UYAP's, row by row.
  @visibleForTesting
  static Future<List<({int block, int row, double height, int offset})>>
  bodyRows(DocModel model) async {
    final rows = _trace = [];
    try {
      await _renderPdf(await _request(model, null));
    } finally {
      _trace = null;
    }
    return rows;
  }

  static List<({int block, int row, double height, int offset})>? _trace;

  /// How tall [model]'s header and footer are, in points, measured as the
  /// PDF lays them out: the tallest of each kind, or null for a kind the
  /// document does not have. The editor sets its pages by these, so its text
  /// area is the printed page's.
  static Future<({double? header, double? footer})> regionHeights(
    DocModel model,
  ) async {
    final regions = model.pageRegions;
    if (!regions.keys.any(
      (k) => k.endsWith('header') || k.endsWith('footer'),
    )) {
      return (header: null, footer: null);
    }
    final measured = _regionTrace = {};
    try {
      await _renderPdf(
        await _request(
          DocModel(
            pageProperties: model.pageProperties,
            styles: model.styles,
            metadata: model.metadata,
            pageRegions: regions,
            blocks: const [],
          ),
          null,
        ),
      );
    } finally {
      _regionTrace = null;
    }
    return (header: measured['header'], footer: measured['footer']);
  }

  static Map<String, double>? _regionTrace;

  static Future<({DocModel model, String? title, Map<String, ByteData> data})>
  _request(DocModel model, String? title) async {
    final families = DocumentFonts.modelFamilies(model);
    final names = [
      for (final family in families)
        for (final face in DocumentFonts.faces) (family: family, face: face),
    ];
    final loaded = await Future.wait(
      names.map((font) => DocumentFonts.loadFace(font.family, font.face)),
    );
    final data = {
      for (var i = 0; i < names.length; i++)
        '${names[i].family}-${names[i].face}': loaded[i],
    };
    return (model: model, title: title, data: data);
  }

  static Future<Uint8List> _renderPdf(
    ({DocModel model, String? title, Map<String, ByteData> data}) request,
  ) async {
    final model = request.model;
    final title = request.title;
    final fonts = {
      for (final entry in request.data.entries)
        entry.key: pw.Font.ttf(entry.value),
    };
    // Row heights come from the same files the text is drawn with.
    FontLineMetrics lineMetrics(String? family) {
      final data = request.data['${family ?? 'Times New Roman'}-Regular'];
      return (data == null ? null : FontLineMetrics.read(data)) ??
          FontLineMetrics.common;
    }

    pw.Font getFont(String? family, bool bold, bool italic) =>
        fonts['${family ?? 'Times New Roman'}-${bold && italic
            ? 'BoldItalic'
            : bold
            ? 'Bold'
            : italic
            ? 'Italic'
            : 'Regular'}']!;
    final baseStyle =
        model.styles
            .where((s) => s.name == model.metadata['resolver'])
            .firstOrNull ??
        model.styles.where((s) => s.name == 'hvl-default').firstOrNull;
    final baseFamily = baseStyle?.family ?? 'Times New Roman';
    final baseSize = baseStyle?.size ?? 12.0;
    final p = model.pageProperties;
    final pageFormat = p.landscape
        ? PdfPageFormat.a4.landscape
        : PdfPageFormat.a4;
    final width = pageFormat.width - p.marginLeft - p.marginRight;
    final height = pageFormat.height - p.marginTop - p.marginBottom;
    if (width <= 0 || height <= 0) {
      throw const FormatException('Sayfa kenar boşlukları geçersiz.');
    }
    final pdf = pw.Document(title: title ?? 'Evrak');
    // Measuring needs a resolved PdfFont, which only a context can hand over.
    // It is the document being written, so a font measured here is the one
    // that gets drawn.
    final measuring = pw.Context(document: pdf.document);
    // The advance, not the ink: the pdf package moves its pen by each glyph's
    // advance, and `width` leaves out the side bearings of the first and last
    // letters. Measured by ink, a tab after "Ad" came out 0.06 pt past its
    // stop in Times New Roman and 0.26 pt in Liberation Serif.
    //
    // A space the font has no glyph for takes the width Unicode gives it:
    // Times New Roman as some machines have it lacks the em space, which the
    // pdf package then measured as nothing, while Flutter draws it from
    // another font an em wide, and UYAP drew it twelve points at twelve.
    double measure(String text, pw.TextStyle style) {
      if (text.isEmpty) return 0;
      final font = style.font!.getFont(measuring);
      final size = style.fontSize ?? baseSize;
      var width = font.stringMetrics(text).advanceWidth;
      if (font is PdfTtfFont) {
        for (final c in text.runes) {
          final em = _spaceEms[c];
          if (em == null || font.font.charToGlyphIndexMap.containsKey(c)) {
            continue;
          }
          width += em - font.glyphMetrics(c).advanceWidth;
        }
      }
      return width * size;
    }

    PdfColor? color(String? hex) => hex == null ? null : PdfColor.fromHex(hex);
    // Each numbered list item's number, counted as UYAP counts it within
    // the body, a header or footer, or a table cell.
    final listNumbers = Expando<int>();
    void countLists(List<DocBlock> blocks) {
      ListMarkers.numbers(blocks).forEach((i, n) => listNumbers[blocks[i]] = n);
      for (final b in blocks) {
        for (final row in b.table?.rows ?? const <DocTableRow>[]) {
          for (final cell in row.cells) {
            countLists(cell.blocks);
          }
        }
      }
    }

    countLists(model.blocks);
    model.pageRegions.values.forEach(countLists);
    // Whose rules the tabs follow: a Word document's own default stops, or
    // UYAP's, which every other source is laid out by.
    final rules = model.metadata['tabRules'] == 'word'
        ? TabRules.word
        : TabRules.uyap;
    final interval =
        (model.metadata['defaultTabStop'] as num?)?.toDouble() ??
        (rules == TabRules.word ? 36.0 : TabStops.defaultInterval);
    // UYAP holds a paragraph's indents and spacing as whole points — Swing
    // keeps them in `short` insets — so 35.4375 is drawn at 35.
    double points(double value) =>
        rules == TabRules.uyap ? value.truncateToDouble() : value;

    /// A list item's number or bullet, placed over its first row where UYAP
    /// draws it: [textStart] is where the row's text begins, [top] how far
    /// below the paragraph's top the row does.
    pw.Widget marker(
      DocBlock b, {
      required double textStart,
      required double top,
      required double row,
      required pw.TextStyle style,
    }) {
      final size = style.fontSize ?? baseSize;
      if (b.listType == DocListType.ordered) {
        final label = ListMarkers.label(b.numberType, listNumbers[b] ?? 1);
        final at = ListMarkers.numberAt(
          textStart: textStart,
          advance: measure(label, style),
          row: row,
          size: size,
        );
        final ascent = style.font!.getFont(measuring).ascent * size;
        return pw.Positioned(
          left: at.x,
          top: top + at.baseline - ascent,
          child: pw.Text(label, style: style.copyWith(color: PdfColors.black)),
        );
      }
      final at = ListMarkers.bulletAt(
        textStart: textStart,
        row: row,
        size: size,
      );
      return pw.Positioned(
        left: at.x,
        top: top + at.y,
        child: pw.CustomPaint(
          size: PdfPoint(at.side, at.side),
          painter: (canvas, box) =>
              _bullet(canvas, ListMarkers.shape(b.bulletType), box.x),
        ),
      );
    }

    /// The rows [b] is drawn in, for a text area [available] points wide.
    ///
    /// Where every word, space and tab goes comes from [ParagraphRows], the
    /// same layout the editor places its tabs by; this only draws it. Each row
    /// is its own widget, so a page can break between any two of them.
    List<pw.Widget> paragraphRows(DocBlock b, double available, {int? block}) {
      final text = b.plainText;
      final boundaries = <int>{0, text.length};
      for (final s in b.spans) {
        boundaries.add(s.startOffset.clamp(0, text.length));
        boundaries.add(s.endOffset.clamp(0, text.length));
      }
      final sorted = boundaries.toList()..sort();
      final runs = <({int start, int end, pw.TextStyle style, double shift})>[];
      for (var i = 0; i + 1 < sorted.length; i++) {
        final start = sorted[i], end = sorted[i + 1];
        var bold = false,
            italic = false,
            superscript = false,
            subscript = false;
        String? family = baseFamily, foreground, background;
        // A heading carries its weight and size through the style rather than
        // on every run, so the export has to read it from the block.
        final heading = DocDeltaMap.headingLevelOf(b.styleName);
        var size = DocDeltaMap.headingSizes[heading] ?? baseSize;
        if (heading != null) bold = true;
        final decorations = <pw.TextDecoration>[];
        for (final s in b.spans) {
          if (s.startOffset > start || s.endOffset < end) continue;
          superscript |= s.superscript;
          subscript |= s.subscript;
          bold |= s.bold;
          italic |= s.italic;
          family = s.fontFamily ?? family;
          size = s.fontSize ?? size;
          foreground = s.color ?? foreground;
          background = s.background ?? background;
          if (s.underline) decorations.add(pw.TextDecoration.underline);
          if (s.strikethrough) decorations.add(pw.TextDecoration.lineThrough);
        }
        runs.add((
          start: start,
          end: end,
          shift: superscript
              ? -size * .35
              : subscript
              ? size * .2
              : 0,
          style: pw.TextStyle(
            font: getFont(family, bold, italic),
            fontSize: superscript || subscript ? size * .75 : size,
            color: color(foreground),
            background: background == null
                ? null
                : pw.BoxDecoration(color: color(background)),
            decoration: pw.TextDecoration.combine(decorations),
          ),
        ));
      }
      final plain = pw.TextStyle(
        font: getFont(baseFamily, false, false),
        fontSize: baseSize,
      );
      pw.TextStyle styleAt(int offset) =>
          runs
              .where((r) => r.start <= offset && offset < r.end)
              .firstOrNull
              ?.style ??
          (runs.isEmpty ? plain : runs.last.style);
      // A line break inside a UYAP paragraph is an empty letter (see
      // ParagraphRows); a Word one never reaches a row. Nor do the invisible
      // formatting characters take room — a direction override UYAP puts
      // ahead of an amount, a zero-width space — though a font without them
      // would draw each as a missing-glyph box six points wide.
      String drawn(String piece) => piece.replaceAll(_invisible, '');
      // Rows are filled at the size Flutter sets type at, which is cut down to
      // whole 64ths of a pixel. The editor lays its page out in points, so
      // that is 64ths of a point, and every size a document uses, in halves
      // of a point, is kept whole; laid out in 96 dpi pixels, eleven point
      // was 14.656 px, a line of it 0.07% shorter, and a word at the edge of
      // a row went down in one and stayed up in the other. The letters are
      // still drawn at the size asked for.
      double laidOut(double width, pw.TextStyle style) {
        final size = style.fontSize ?? baseSize;
        return width * ((size * 64).floorToDouble() / 64) / size;
      }

      double widthOf(int start, int end) {
        var total = 0.0;
        for (final r in runs) {
          if (r.end <= start) continue;
          if (r.start >= end) break;
          total += laidOut(
            measure(
              drawn(
                text.substring(math.max(start, r.start), math.min(end, r.end)),
              ),
              r.style,
            ),
            r.style,
          );
        }
        return total;
      }

      // A list item is laid out as any paragraph; its number or bullet takes
      // no room, and is drawn in the indent beside the first row, as UYAP
      // draws it (see ListMarkers).
      final laid = ParagraphRows(
        text: text,
        measure: widthOf,
        space: (offset) =>
            laidOut(measure(' ', styleAt(offset)), styleAt(offset)),
        width: available,
        leftIndent: math.max(0, points(b.leftIndent)),
        rightIndent: math.max(0, points(b.rightIndent)),
        // A negative first line indent is drawn flush, as the editor, which
        // cannot pull a first line out past the rest, draws it.
        firstLineIndent: math.max(0, points(b.firstLineIndent)),
        hanging: math.max(0, points(b.hanging)),
        align: switch (b.alignment) {
          DocAlignment.left => RowAlign.left,
          DocAlignment.center => RowAlign.center,
          DocAlignment.right => RowAlign.right,
          DocAlignment.justify => RowAlign.justify,
        },
        tabs: TabStops.parse(b.tabSet, interval: interval, rules: rules),
        lineBreaks: rules == TabRules.word,
      ).layout();

      // A row is the font's natural height times (1 + LineSpacing), the way
      // UYAP's Swing lays it out, with the extra below every row — the last
      // one included. The `pdf` line box is only ascent to descent, so the
      // rest goes under each row.
      // Each row is as tall as the tallest run in it, as a Swing row is; the
      // last one counts the paragraph's closing line break too, which is all
      // an empty paragraph has. Its font and size, where no run says, are
      // the paragraph's.
      final headingSize =
          DocDeltaMap.headingSizes[DocDeltaMap.headingLevelOf(b.styleName)];
      ({double row, double above, double below, double tight}) rowOf(
        int start,
        int end,
        bool last,
      ) {
        final runs = <(String?, double)>[
          for (final s in b.spans)
            if (s.length > 0 &&
                s.startOffset < end &&
                s.startOffset + s.length > start)
              (s.fontFamily, headingSize ?? s.fontSize ?? baseSize),
          if (last && (b.endFontSize != null || b.endFontFamily != null))
            (b.endFontFamily, headingSize ?? b.endFontSize ?? baseSize),
        ];
        if (runs.isEmpty) runs.add((null, headingSize ?? baseSize));
        var best = (row: -1.0, above: 0.0, below: 0.0, tight: 0.0);
        for (final (family, size) in runs) {
          final metrics = lineMetrics(family ?? baseFamily);
          final row = rules == TabRules.uyap
              ? metrics.uyapRow(size, b.lineSpacing)
              : metrics.row(size, b.lineSpacing);
          if (row <= best.row) continue;
          // UYAP puts a row's line spacing half above its text and half
          // below (its rows' top and bottom insets, each (short)(height ×
          // spacing / 2)); a Word row has it all below.
          final above = rules == TabRules.uyap
              ? (row - metrics.uyapRow(size, null)) / 2
              : 0.0;
          final tight = metrics.tight * size;
          best = (
            row: row,
            above: above,
            below: math.max(0.0, row - tight - above),
            tight: tight,
          );
        }
        return best;
      }

      final before = math.max(0.0, points(b.spacingBefore));
      final after = math.max(0.0, points(b.spacingAfter));
      // Space below goes after the last row as a widget of its own, cut off
      // where a page ends: UYAP does not count it towards whether a row fits,
      // nor carry it over to the next page.
      final below = [if (after > 0) _SpaceBelow(after)];
      if (text.isEmpty) {
        final row = rowOf(0, 0, true).row;
        if (block != null) {
          _trace?.add((block: block, row: 0, height: row + before, offset: 0));
        }
        return [pw.SizedBox(height: row + before), ...below];
      }

      final widgets = <pw.Widget>[];
      for (final (index, r) in laid.indexed) {
        final last = index == laid.length - 1;
        final size = rowOf(
          r.start,
          last ? text.length : laid[index + 1].start,
          last,
        );
        final spans = <pw.InlineSpan>[];
        var pen = 0.0;
        var written = false;
        void gap(double width) {
          if (width <= .001) return;
          spans.add(pw.WidgetSpan(child: pw.SizedBox(width: width)));
          pen += width;
        }

        void write(int start, int end) {
          for (final run in runs) {
            if (run.end <= start) continue;
            if (run.start >= end) break;
            final piece = drawn(
              text.substring(
                math.max(start, run.start),
                math.min(end, run.end),
              ),
            );
            // The `pdf` package takes any white space for a gap between words
            // and draws it a plain space wide; an em space is four times that.
            // Anything but a plain space is left as room of its own width.
            var from = 0;
            void letters(int to) {
              if (to <= from) return;
              final part = piece.substring(from, to);
              spans.add(
                pw.TextSpan(text: part, baseline: run.shift, style: run.style),
              );
              pen += measure(part, run.style);
              written = true;
            }

            for (var k = 0; k < piece.length; k++) {
              final c = piece.codeUnitAt(k);
              if (c == 0x20 || !_whiteSpace.hasMatch(piece[k])) continue;
              letters(k);
              gap(measure(piece[k], run.style));
              from = k + 1;
            }
            letters(piece.length);
          }
        }

        for (final piece in r.pieces) {
          gap(piece.x - pen);
          switch (piece.kind) {
            case PieceKind.text:
              write(piece.start, piece.end);
            case PieceKind.tab:
              gap(piece.width);
            case PieceKind.space:
              // A plain space at its own width is written as one, so the
              // preview's text can be searched and copied with its spaces; a
              // spread or collapsed one is only room.
              final natural = widthOf(piece.start, piece.end);
              if (text.codeUnitAt(piece.start) == 0x20 &&
                  (piece.width - natural).abs() < .001) {
                write(piece.start, piece.end);
              } else {
                gap(piece.width);
              }
          }
        }
        final top = (index == 0 ? before : 0.0) + size.above;
        final bottom = size.below;
        if (block != null) {
          _trace?.add((
            block: block,
            row: index,
            height: top + size.tight + bottom,
            offset: r.start,
          ));
        }
        // Every row exactly as tall as UYAP's, whatever the pdf package makes
        // of its letters: a page holds the rows UYAP's does only if each
        // weighs what it weighs there.
        final rowBox = pw.SizedBox(
          height: top + size.tight + bottom,
          child: written
              ? pw.Padding(
                  padding: pw.EdgeInsets.only(top: top),
                  child: pw.RichText(
                    softWrap: false,
                    overflow: pw.TextOverflow.visible,
                    text: pw.TextSpan(style: plain, children: spans),
                  ),
                )
              // A row of nothing but tabs still takes a row's height.
              : null,
        );
        widgets.add(
          index == 0 && b.listType != DocListType.none
              ? pw.Stack(
                  overflow: pw.Overflow.visible,
                  children: [
                    rowBox,
                    marker(
                      b,
                      textStart: r.left,
                      top: index == 0 ? before : 0,
                      row: size.row,
                      style: runs.isEmpty ? plain : runs.first.style,
                    ),
                  ],
                )
              : rowBox,
        );
      }
      return [...widgets, ...below];
    }

    // Laid out at the width it is given, which inside a table cell is only
    // known once the table has settled its columns.
    pw.Widget paragraph(DocBlock b) => _AtWidth(
      (available) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: paragraphRows(b, available),
      ),
    );

    PdfColor? fill(String? hex) => hex == null
        ? null
        : PdfColor.fromInt(
            (int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0xffffff) |
                0xff000000,
          );

    // A UYAP table is laid out as UYAP lays it out: columns on whole points,
    // cells with no padding, and each cell's rows going on on the next page
    // where the page ends (see _TableRow).
    late final List<pw.Widget> Function(DocBlock b, double available) tableRows;

    pw.Widget render(DocBlock b) {
      if (b.type == DocBlockType.image && b.imageBase64 != null) {
        final bytes = base64Decode(b.imageBase64!);
        final image = pw.MemoryImage(bytes);
        final pixels = ImageBox.pixels(bytes);
        // As UYAP draws it (see ImageBox), in whatever it stands in: the
        // page, a table cell, a header.
        return _AtWidth((available) {
          final size = ImageBox.size(
            width: b.imageWidth,
            height: b.imageHeight,
            pixels: pixels,
            available: available,
          );
          var w = size.width, h = size.height;
          // Taller than a page could never be placed; fitted to one.
          if (h > height) {
            w = w * height / h;
            h = height;
          }
          return pw.Align(
            alignment: b.alignment == DocAlignment.right
                ? pw.Alignment.topRight
                : b.alignment == DocAlignment.center
                ? pw.Alignment.topCenter
                : pw.Alignment.topLeft,
            child: pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: ImageBox.border),
              child: pw.Image(image, width: w, height: h, fit: pw.BoxFit.fill),
            ),
          );
        });
      }
      if (b.type == DocBlockType.table &&
          b.table != null &&
          rules == TabRules.uyap) {
        return _AtWidth(
          (available) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: tableRows(b, available),
          ),
        );
      }
      if (b.type == DocBlockType.table && b.table != null) {
        return pw.Table(
          // A table that names no column widths shares the row equally.
          // Sized by their contents instead, the columns are measured
          // without a width, which a picture in a cell cannot be laid out
          // in.
          defaultColumnWidth: const pw.FlexColumnWidth(),
          border: b.table!.bordered
              ? pw.TableBorder.all(color: PdfColors.grey600, width: .5)
              : null,
          columnWidths: b.table!.columnWidths == null
              ? null
              : {
                  for (var i = 0; i < b.table!.columnWidths!.length; i++)
                    i: pw.FlexColumnWidth(b.table!.columnWidths![i]),
                },
          children: [
            for (final row in b.table!.rows)
              pw.TableRow(
                repeat: row.isHeader,
                children: [
                  for (final cell in row.cells)
                    pw.Container(
                      // A filled cell prints filled: shading a heading row is
                      // the usual reason a table has any colour at all.
                      decoration: cell.backgroundColor == null
                          ? null
                          : pw.BoxDecoration(
                              color: PdfColor.fromInt(
                                (int.tryParse(
                                          cell.backgroundColor!.replaceFirst(
                                            '#',
                                            '',
                                          ),
                                          radix: 16,
                                        ) ??
                                        0xffffff) |
                                    0xff000000,
                              ),
                            ),
                      // UYAP draws a cell's text against its borders; its
                      // paragraphs carry their own indents.
                      padding: rules == TabRules.uyap
                          ? pw.EdgeInsets.zero
                          : const pw.EdgeInsets.all(4),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          for (final block in cell.blocks) render(block),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        );
      }
      return paragraph(b);
    }

    tableRows = (b, available) {
      final table = b.table!;
      final columns = table.rows.fold<int>(
        0,
        (most, row) => math.max(
          most,
          row.cells.fold<int>(0, (n, c) => n + math.max(1, c.colspan)),
        ),
      );
      final widths = TableColumns.widths(
        available,
        columns,
        shares: table.columnWidths,
      );
      return [
        for (final row in table.rows)
          () {
            final cellWidths = <double>[];
            var column = 0;
            for (final cell in row.cells) {
              final span = math.max(1, cell.colspan);
              var w = 0.0;
              for (
                var k = column;
                k < column + span && k < widths.length;
                k++
              ) {
                w += widths[k];
              }
              cellWidths.add(w);
              column += span;
            }
            return _TableRow(
              widths: cellWidths,
              bordered: table.bordered,
              fills: [for (final cell in row.cells) fill(cell.backgroundColor)],
              cells: [
                for (final (k, cell) in row.cells.indexed)
                  [
                    if (cell.blocks.isEmpty)
                      ...paragraphRows(DocBlock(plainText: ''), cellWidths[k]),
                    for (final block in cell.blocks)
                      if (block.type == DocBlockType.paragraph ||
                          block.type == DocBlockType.listItem)
                        ...paragraphRows(block, cellWidths[k])
                      else
                        render(block),
                  ],
              ],
            );
          }(),
      ];
    };

    pw.Widget region(pw.Context context, String suffix) {
      final variants = model.pageRegions;
      final page = context.pageNumber;
      final key = [
        if (page == 1) 'first_page_$suffix',
        '${page.isOdd ? 'odd' : 'even'}_page_$suffix',
        suffix,
      ].where(variants.containsKey).firstOrNull;
      final allAttrs = model.metadata['pageRegionAttrs'];
      final attrs = allAttrs is Map ? allAttrs[key] : null;
      final regionAttrs = attrs is Map ? attrs : null;
      // A header UYAP starts on page 2 is not on page 1.
      if (key == null || !PageNumbering.regionShows(regionAttrs, page)) {
        return pw.SizedBox();
      }
      final column = pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [for (final b in variants[key]!) render(b)],
      );
      final numbering = PageNumbering.parse(regionAttrs);
      if (numbering == null || !numbering.shows(page, context.pagesCount)) {
        return column;
      }
      return _PageNumbered(
        column,
        numbering,
        numbering.label(page, context.pagesCount),
        getFont(numbering.fontFace, numbering.bold, numbering.italic),
      );
    }

    // The header and footer are drawn in the margins, at their offsets from
    // the edge, as UYAP draws them; only one taller than its margin pushes
    // the text away from the edge, on every page. So the page's own margins
    // are the offsets, and the slot a region is drawn in reaches to the
    // margin, or to the region's end where it runs past it.
    final theme = pw.ThemeData.withFont(
      base: getFont(baseFamily, false, false),
      bold: getFont(baseFamily, true, false),
      italic: getFont(baseFamily, false, true),
      boldItalic: getFont(baseFamily, true, true),
    );
    double tallest(String suffix) {
      var height = 0.0;
      for (final entry in model.pageRegions.entries) {
        if (!entry.key.endsWith(suffix)) continue;
        final column = pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [for (final b in entry.value) render(b)],
        );
        column.layout(
          measuring.inheritFrom(theme),
          // Bounded: a picture in a header is fitted to the page.
          pw.BoxConstraints(maxWidth: width, maxHeight: pageFormat.height),
        );
        height = math.max(height, column.box!.height);
      }
      return height;
    }

    final hasHeader = model.pageRegions.keys.any((k) => k.endsWith('header'));
    final hasFooter = model.pageRegions.keys.any((k) => k.endsWith('footer'));
    final regionTrace = _regionTrace;
    if (regionTrace != null) {
      if (hasHeader) regionTrace['header'] = tallest('header');
      if (hasFooter) regionTrace['footer'] = tallest('footer');
      return pdf.save();
    }
    final textTop = hasHeader
        ? math.max(p.marginTop, p.headerOffset + tallest('header'))
        : p.marginTop;
    final textBottom = hasFooter
        ? math.max(p.marginBottom, p.footerOffset + tallest('footer'))
        : p.marginBottom;

    pdf.addPage(
      pw.MultiPage(
        maxPages: 1000,
        pageFormat: pageFormat,
        theme: theme,
        margin: pw.EdgeInsets.fromLTRB(
          p.marginLeft,
          hasHeader ? p.headerOffset : p.marginTop,
          p.marginRight,
          hasFooter ? p.footerOffset : p.marginBottom,
        ),
        header: hasHeader
            ? (c) => pw.Container(
                height: textTop - p.headerOffset,
                alignment: pw.Alignment.topLeft,
                child: region(c, 'header'),
              )
            : null,
        footer: hasFooter
            ? (c) => pw.Container(
                height: textBottom - p.footerOffset,
                alignment: pw.Alignment.bottomLeft,
                child: region(c, 'footer'),
              )
            : null,
        build: (_) => [
          if (model.blocks.isEmpty) pw.SizedBox(height: 1),
          for (final (i, b) in model.blocks.indexed)
            if (b.type == DocBlockType.table &&
                b.table != null &&
                rules == TabRules.uyap)
              ...tableRows(b, width)
            else if (b.type == DocBlockType.table ||
                b.type == DocBlockType.image)
              _trace == null ? render(b) : _Traced(render(b), i)
            else
              ...paragraphRows(b, width, block: i),
        ],
      ),
    );
    return pdf.save();
  }

  static final _whiteSpace = RegExp(r'\s');

  /// The widths of the spaces, in ems, for a font that lacks one.
  static const _spaceEms = <int, double>{
    0x00a0: .25,
    0x2000: .5,
    0x2001: 1,
    0x2002: .5,
    0x2003: 1,
    0x2004: 1 / 3,
    0x2005: .25,
    0x2006: 1 / 6,
    0x2007: .5,
    0x2008: .25,
    0x2009: .2,
    0x200a: .1,
    0x202f: .2,
    0x205f: 4 / 18,
    0x3000: 1,
  };

  /// A line break, and the characters that only steer the text: soft hyphen,
  /// zero-width spaces and joiners, direction marks and overrides.
  static final _invisible = RegExp(
    '[\n\u00ad\u200b-\u200f\u202a-\u202e\u2060-\u2064\ufeff]',
  );

  static Future<Uint8List> textToPdfBytes(String text, {String? title}) =>
      modelToPdfBytes(
        DocModel(
          blocks: [
            for (final line in text.split('\n')) DocBlock(plainText: line),
          ],
        ),
        title: title,
      );

  static Future<File> saveBytesToFile(
    Uint8List bytes,
    String targetPath,
  ) async {
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    return file.writeAsBytes(bytes, flush: true);
  }
}

/// A widget built for the width it is laid out at, and built again when that
/// changes.
///
/// `pw.LayoutBuilder` builds once, for whatever width it is first handed, and
/// a table lays its cells out more than once while it settles the columns —
/// first without a width at all.
class _AtWidth extends pw.Widget {
  _AtWidth(this.builder);

  final pw.Widget Function(double width) builder;
  pw.Widget? _child;
  double? _width;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    final width = constraints.maxWidth;
    if (_child == null || _width != width) {
      _child = builder(width);
      _width = width;
    }
    _child!.layout(context, constraints, parentUsesSize: parentUsesSize);
    box = _child!.box;
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    final child = _child;
    if (child == null) return;
    context.canvas
      ..saveContext()
      ..setTransform(
        Matrix4.identity()..translateByDouble(box!.left, box!.bottom, 0, 1),
      );
    child.paint(context);
    context.canvas.restoreContext();
  }
}

/// A header or footer with its page number drawn over it, where UYAP draws
/// one (see [PageNumbering]): taking no room, so the region is as tall as
/// its text.
class _PageNumbered extends pw.Widget {
  _PageNumbered(this.child, this.numbering, this.label, this.font);

  final pw.Widget child;
  final PageNumbering numbering;
  final String label;
  final pw.Font font;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    child.layout(context, constraints, parentUsesSize: true);
    box = PdfRect(0, 0, constraints.maxWidth, child.box!.height);
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    context.canvas
      ..saveContext()
      ..setTransform(
        Matrix4.identity()..translateByDouble(box!.left, box!.bottom, 0, 1),
      );
    child.paint(context);
    context.canvas.restoreContext();
    final pdfFont = font.getFont(context);
    final size = numbering.fontSize;
    final advance = pdfFont.stringMetrics(label).advanceWidth * size;
    final at = numbering.place(
      width: box!.width,
      height: box!.height,
      advance: advance,
      ink: numbering.ink(label),
    );
    context.canvas
      ..setFillColor(PdfColor.fromInt(numbering.color))
      ..drawString(
        pdfFont,
        size,
        label,
        box!.left + at.x,
        box!.top - at.baseline,
      );
  }
}

/// One row of a UYAP table, which UYAP lets run on to the next page a cell
/// row at a time: each cell lays its own rows down the page, a row that does
/// not fit on what is left of it starts the next page, and the other cells
/// go on beside it regardless (test/fixtures/pages, 10-tablo-uzun-hucre).
class _TableRow extends pw.Widget with pw.SpanningWidget {
  _TableRow({
    required this.cells,
    required this.widths,
    required this.bordered,
    required this.fills,
  }) : _context = _TableRowContext(
         first: List.filled(cells.length, 0),
         last: List.filled(cells.length, 0),
       );

  /// Each cell's rows, spaces below and pictures, in order.
  final List<List<pw.Widget>> cells;
  final List<double> widths;
  final bool bordered;
  final List<PdfColor?> fills;

  final _TableRowContext _context;

  static const _line = .5;

  @override
  bool get canSpan => true;

  @override
  bool get hasMoreWidgets {
    for (var c = 0; c < cells.length; c++) {
      if (_context.last[c] < cells[c].length) return true;
    }
    return false;
  }

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    final room = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : double.infinity;
    var tallest = 0.0;
    var placed = false;
    for (var c = 0; c < cells.length; c++) {
      var y = 0.0;
      var k = _context.first[c];
      while (k < cells[c].length) {
        final piece = cells[c][k];
        final spaceBelow = piece is _SpaceBelow;
        piece.layout(
          context,
          pw.BoxConstraints(
            maxWidth: widths[c],
            maxHeight: spaceBelow ? math.max(0, room - y) : double.infinity,
          ),
          parentUsesSize: true,
        );
        final height = piece.box!.height;
        // A piece taller than a whole page goes where it is, rather than
        // starting page after page; so does the first one, once a page has
        // been started with nothing placed.
        final forced = k == _context.first[c] && _context.stalled;
        if (!spaceBelow && y + height > room + .01 && !forced) break;
        y += height;
        k++;
        if (!spaceBelow) placed = true;
      }
      _context.last[c] = k;
      tallest = math.max(tallest, math.min(y, room));
    }
    _context.placedNothing = !placed;
    box = PdfRect(0, 0, widths.fold(0.0, (a, b) => a + b), tallest);
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    final canvas = context.canvas;
    final height = box!.height;
    final done = !hasMoreWidgets;
    var x = 0.0;
    for (var c = 0; c < cells.length; c++) {
      final w = widths[c];
      final fill = fills[c];
      if (fill != null) {
        canvas
          ..setFillColor(fill)
          ..drawRect(box!.left + x, box!.bottom, w, height)
          ..fillPath();
      }
      var y = 0.0;
      for (var k = _context.first[c]; k < _context.last[c]; k++) {
        final piece = cells[c][k];
        final h = math.min(piece.box!.height, math.max(0.0, height - y));
        piece.box = PdfRect(
          box!.left + x,
          box!.top - y - h,
          piece.box!.width,
          h,
        );
        piece.paint(context);
        y += h;
      }
      x += w;
    }
    if (!bordered) return;
    canvas
      ..setStrokeColor(PdfColors.grey600)
      ..setLineWidth(_line);
    final left = box!.left, right = box!.left + x;
    final top = box!.top, bottom = box!.bottom;
    var edge = left;
    for (var c = 0; c <= cells.length; c++) {
      canvas
        ..moveTo(edge, top)
        ..lineTo(edge, bottom);
      if (c < cells.length) edge += widths[c];
    }
    if (_context.opens) {
      canvas
        ..moveTo(left, top)
        ..lineTo(right, top);
    }
    if (done) {
      canvas
        ..moveTo(left, bottom)
        ..lineTo(right, bottom);
    }
    canvas.strokePath();
  }

  @override
  _TableRowContext saveContext() => _context;

  @override
  void restoreContext(_TableRowContext context) {
    // The next page starts where the last one stopped.
    _context
      ..first = [...context.last]
      ..last = [...context.last]
      ..opens = false
      ..stalled = context.placedNothing;
  }
}

class _TableRowContext extends pw.WidgetContext {
  _TableRowContext({required this.first, required this.last});

  /// Where each cell's pieces on this page start, and where they stop.
  List<int> first, last;

  /// This part of the row is its start, which draws its top line.
  bool opens = true;

  /// The page before placed nothing, so this one must place something.
  bool stalled = false;
  bool placedNothing = false;

  @override
  void apply(_TableRowContext other) {
    first = [...other.first];
    last = [...other.last];
    opens = other.opens;
    stalled = other.stalled;
    placedNothing = other.placedNothing;
  }

  @override
  _TableRowContext clone() =>
      _TableRowContext(first: [...first], last: [...last])
        ..opens = opens
        ..stalled = stalled
        ..placedNothing = placedNothing;
}

/// A paragraph's space below: its full height where it fits, and only what
/// is left of the page where it does not, without starting the next page
/// with the rest.
class _SpaceBelow extends pw.Widget with pw.SpanningWidget {
  _SpaceBelow(this.height);

  final double height;

  @override
  bool get canSpan => true;

  @override
  bool get hasMoreWidgets => false;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    final fits = constraints.hasBoundedHeight
        ? math.min(height, math.max(0.0, constraints.maxHeight))
        : height;
    box = PdfRect(
      0,
      0,
      constraints.hasBoundedWidth ? constraints.maxWidth : 0,
      fits,
    );
  }

  @override
  pw.WidgetContext saveContext() => _NoContext();

  @override
  void restoreContext(_NoContext context) {}
}

class _NoContext extends pw.WidgetContext {
  @override
  _NoContext clone() => _NoContext();

  @override
  void apply(_NoContext other) {}
}

/// A table or picture that notes its height in the test trace.
class _Traced extends pw.StatelessWidget {
  _Traced(this.child, this.block);

  final pw.Widget child;
  final int block;

  @override
  pw.Widget build(pw.Context context) => child;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    super.layout(context, constraints, parentUsesSize: parentUsesSize);
    if (!(PdfService._trace?.any((r) => r.block == block) ?? true)) {
      PdfService._trace!.add((
        block: block,
        row: -1,
        height: box!.height,
        offset: 0,
      ));
    }
  }
}

/// A bullet of [shape], [side] points across, in a box whose origin is its
/// bottom left, as the pdf package paints.
void _bullet(PdfGraphics canvas, BulletShape shape, double side) {
  canvas.setFillColor(PdfColors.black);
  switch (shape) {
    case BulletShape.circle:
      canvas
        ..drawEllipse(side / 2, side / 2, side / 2, side / 2)
        ..fillPath();
    case BulletShape.square:
      canvas
        ..drawRect(0, 0, side, side)
        ..fillPath();
    case BulletShape.squareOutline:
      canvas
        ..setStrokeColor(PdfColors.black)
        ..setLineWidth(.6)
        ..drawRect(0, 0, side, side)
        ..strokePath();
    case BulletShape.arrow:
      canvas
        ..moveTo(0, 0)
        ..lineTo(side, side / 2)
        ..lineTo(0, side)
        ..lineTo(side * .3, side / 2)
        ..closePath()
        ..fillPath();
    case BulletShape.diamond:
      canvas
        ..moveTo(side / 2, 0)
        ..lineTo(side, side / 2)
        ..lineTo(side / 2, side)
        ..lineTo(0, side / 2)
        ..closePath()
        ..fillPath();
    case BulletShape.triangle:
      canvas
        ..moveTo(0, 0)
        ..lineTo(side, 0)
        ..lineTo(side / 2, side)
        ..closePath()
        ..fillPath();
  }
}

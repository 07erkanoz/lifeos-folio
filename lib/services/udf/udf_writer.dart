import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../models/document_model.dart';
import '../editor/doc_delta_map.dart';

class UdfWriter {
  /// Generates a new unsigned document. Existing signatures cover the original
  /// content.xml bytes and must never be carried over to regenerated content.
  static List<int> writeBytes(DocModel model) {
    final text = StringBuffer();
    XmlElement element(
      String name,
      Map<String, Object?> attrs, [
      List<XmlNode> children = const [],
    ]) => XmlElement(XmlName.qualified(name), [
      for (final e in attrs.entries)
        if (e.value != null)
          XmlAttribute(XmlName.qualified(e.key), '${e.value}'),
    ], children);
    int? color(String? value) {
      final rgb = int.tryParse((value ?? '').replaceFirst('#', ''), radix: 16);
      if (rgb == null) return null;
      return (rgb | 0xff000000).toSigned(32);
    }

    List<XmlNode> runs(DocBlock block) {
      final offset = text.length;
      text.write('${block.plainText}\n');
      final boundaries = <int>{0, block.plainText.length};
      for (final s in block.spans) {
        boundaries.add(s.startOffset.clamp(0, block.plainText.length));
        boundaries.add(s.endOffset.clamp(0, block.plainText.length));
      }
      final sorted = boundaries.toList()..sort();
      final result = <XmlNode>[];
      for (var i = 0; i + 1 < sorted.length; i++) {
        final start = sorted[i], end = sorted[i + 1];
        final attrs = <String, Object?>{};
        for (final s in block.spans) {
          if (s.startOffset > start || s.endOffset < end) continue;
          if (s.bold) attrs['bold'] = true;
          if (s.italic) attrs['italic'] = true;
          if (s.underline) attrs['underline'] = true;
          if (s.strikethrough) attrs['strikethrough'] = true;
          if (s.superscript) attrs['superscript'] = true;
          if (s.subscript) attrs['subscript'] = true;
          if (s.fontFamily != null) attrs['family'] = s.fontFamily;
          if (s.fontSize != null) attrs['size'] = s.fontSize;
          if (s.color != null) attrs['foreground'] = color(s.color);
          if (s.background != null) attrs['background'] = color(s.background);
        }
        // Explicit false values override a bold/italic resolver style.
        for (final key in [
          'bold',
          'italic',
          'underline',
          'strikethrough',
          'superscript',
          'subscript',
        ]) {
          attrs.putIfAbsent(key, () => false);
        }
        result.add(
          element('content', {
            ...attrs,
            'startOffset': offset + start,
            'length': end - start,
          }),
        );
      }
      result.add(
        element('content', {
          'startOffset': offset + block.plainText.length,
          'length': 1,
        }),
      );
      return result;
    }

    XmlElement blockXml(DocBlock b) {
      if (b.type == DocBlockType.table && b.table != null) {
        final table = b.table!;
        final count = table.rows.fold<int>(0, (n, r) {
          final columns = r.cells.fold<int>(0, (s, c) => s + c.colspan);
          return columns > n ? columns : n;
        });
        // Column widths are declared only when the document declared them.
        // Inventing 100,100 for a table that sized nothing pins every column
        // to the same width, and the columns never fit their text again.
        final widths = table.columnWidths;
        return element(
          'table',
          {
            'tableName': widths == null ? null : 'Sabit',
            'columnCount': widths == null ? null : count,
            'columnSpans': widths?.join(','),
            'border': table.bordered ? 'borderCell' : 'borderNone',
          },
          [
            for (final row in table.rows)
              element(
                'row',
                {'rowType': row.isHeader ? 'headerRow' : 'dataRow'},
                [
                  for (final cell in row.cells)
                    element(
                      'cell',
                      {
                        'cellSpan': cell.colspan,
                        'rowSpan': cell.rowspan,
                        'background': color(cell.backgroundColor),
                      },
                      [for (final child in cell.blocks) blockXml(child)],
                    ),
                ],
              ),
          ],
        );
      }
      final attrs = <String, Object?>{
        // UDF resolves named styles through `resolver`, so a paragraph points
        // at one declared below rather than carrying invented attributes that
        // another editor would ignore.
        //
        // Every style the document declares counts, not only headings. UYAP
        // writes its body paragraphs against names of its own — hvl-default,
        // edf_1456817714676 — and dropping the reference cut 4475 paragraphs
        // across 91 of 517 archived documents loose from the style that gave
        // them their font, size and spacing. A name nothing declares is still
        // left out: pointing at a style that is not in the file is worse than
        // pointing at nothing.
        'resolver':
            DocDeltaMap.headingLevelOf(b.styleName) != null ||
                model.styles.any((s) => s.name == b.styleName)
            ? b.styleName
            : null,
        'Alignment': b.alignment.index,
        'LineSpacing': b.lineSpacing == null ? null : b.lineSpacing! - 1,
        'LeftIndent': b.leftIndent,
        'RightIndent': b.rightIndent,
        'FirstLineIndent': b.firstLineIndent,
        if (b.hanging != 0) 'Hanging': b.hanging,
        'SpaceAbove': b.spacingBefore,
        'SpaceBelow': b.spacingAfter,
        'TabSet': b.tabSet,
        if (b.listType != DocListType.none)
          b.listType == DocListType.ordered ? 'Numbered' : 'Bulleted': true,
        // Written whenever they hold something, not only while the paragraph
        // is a list item. UYAP leaves the level and the number style on a
        // paragraph whose numbering is currently off, and tying them to the
        // list flag dropped both on the way back out.
        if (b.listId != 0) 'ListId': b.listId,
        if (b.listLevel != 0) 'ListLevel': b.listLevel,
        'BulletType': b.bulletType,
        'NumberType': b.numberType,
      };
      if (b.type == DocBlockType.image && b.imageBase64 != null) {
        // As UYAP writes a picture: a character of its own, U+00B8 (every
        // one of 80 pictures in a real archive), then the line break that
        // ends the paragraph, as content of its own. The size it is drawn
        // at goes with it, as UYAP's own files carry it; without one UYAP
        // draws a picture as large as it likes.
        final offset = text.length;
        text.write('\u00b8\n');
        return element('paragraph', attrs, [
          element('image', {
            'imageData': b.imageBase64,
            'width': b.imageWidth,
            'height': b.imageHeight,
            'startOffset': offset,
            'length': 1,
          }),
          element('content', {'startOffset': offset + 1, 'length': 1}),
        ]);
      }
      return element('paragraph', attrs, runs(b));
    }

    final regionAttrs = model.metadata['pageRegionAttrs'] as Map? ?? const {};
    XmlElement region(MapEntry<String, List<DocBlock>> entry) => element(
      entry.key,
      {...?(regionAttrs[entry.key] as Map?)?.cast<String, Object?>()},
      [for (final b in entry.value) blockXml(b)],
    );
    // In UYAP's order, text and all: the header before the body, the footer
    // after it (every file of a real archive). Written ahead of the body, a
    // footer took a row of the first page in UYAP, as if it were text.
    final regions = model.pageRegions.entries.toList();
    final elements = <XmlNode>[
      for (final entry in regions)
        if (!entry.key.endsWith('footer')) region(entry),
      for (final b in model.blocks) blockXml(b),
      for (final entry in regions)
        if (entry.key.endsWith('footer')) region(entry),
    ];
    final p = model.pageProperties;
    final styles = model.styles.isEmpty
        ? const [
            DocStyleDef(
              name: 'hvl-default',
              family: 'Times New Roman',
              size: 12,
            ),
          ]
        : model.styles;
    // Declare the heading styles the document actually uses, so the file
    // carries its own definitions and opens the same way elsewhere.
    final headingsUsed = <int>{
      for (final b in model.blocks) ?DocDeltaMap.headingLevelOf(b.styleName),
      for (final region in model.pageRegions.values)
        for (final b in region) ?DocDeltaMap.headingLevelOf(b.styleName),
    };
    final headingStyles = [
      for (final level in headingsUsed.toList()..sort())
        if (!styles.any((s) => s.name == DocDeltaMap.headingNames[level]))
          DocStyleDef(
            name: DocDeltaMap.headingNames[level]!,
            family: styles.first.family,
            size: DocDeltaMap.headingSizes[level]!,
            bold: true,
          ),
    ];
    final resolver = model.metadata['resolver'] as String?;
    final parts = text.toString().split(']]>');
    final contentNodes = [
      for (var i = 0; i < parts.length; i++)
        XmlCDATA(
          '${i > 0 ? '>' : ''}${parts[i]}${i < parts.length - 1 ? ']]' : ''}',
        ),
    ];
    final root = element(
      'template',
      {'format_id': model.metadata['formatId'] ?? '1.8'},
      [
        // Split CDATA terminators without changing the shared text or its offsets.
        element('content', {}, contentNodes),
        element('properties', {}, [
          element('pageFormat', {
            'mediaSizeName': 1,
            'paperOrientation': p.landscape ? 2 : 1,
            'leftMargin': p.marginLeft,
            'rightMargin': p.marginRight,
            'topMargin': p.marginTop,
            'bottomMargin': p.marginBottom,
            'headerFOffset': p.headerOffset,
            'footerFOffset': p.footerOffset,
          }),
        ]),
        element('elements', {
          'resolver': styles.any((s) => s.name == resolver)
              ? resolver
              : styles.first.name,
        }, elements),
        element('styles', {}, [
          for (final s in [...styles, ...headingStyles])
            element('style', {
              'name': s.name,
              'family': s.family,
              'size': s.size,
              'bold': s.bold,
              'italic': s.italic,
              'description': s.description,
            }),
        ]),
      ],
    );
    final xml = XmlDocument([
      XmlProcessing('xml', 'version="1.0" encoding="UTF-8"'),
      root,
    ]);
    final bytes = utf8.encode(xml.toXmlString());
    return ZipEncoder().encode(
      Archive()..addFile(ArchiveFile('content.xml', bytes.length, bytes)),
    );
  }
}

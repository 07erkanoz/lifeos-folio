/// DOCX dosya okuma/yazma köprüsü. docx_creator paketi üzerinden çalışır.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:docx_creator/docx_creator.dart';
import 'package:xml/xml.dart' show XmlBuilder;

import '../../models/document_model.dart';
import '../layout/page_numbers.dart';

class DocxBridge {
  static Future<DocModel?> readFile(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      return await readBytes(bytes);
    } catch (e) {
      debugPrint('DocxBridge.readFile hatası: $e');
      return null;
    }
  }

  static Future<DocModel?> readBytes(Uint8List bytes) async {
    try {
      final patched = _preprocessDocxForReading(bytes);
      final doc = await DocxReader.loadFromBytes(patched);
      return _docxToModel(doc, defaultTabStop: _defaultTabStop(bytes));
    } catch (e) {
      debugPrint('DocxBridge.readBytes hatası: $e');
      return null;
    }
  }

  static Uint8List _preprocessDocxForReading(Uint8List rawBytes) {
    try {
      final input = ZipDecoder().decodeBytes(rawBytes);
      final output = Archive();

      for (final file in input) {
        if (!file.isFile) continue;

        List<int> content = file.content as List<int>;

        final isPatchableXml =
            file.name == 'word/document.xml' ||
            file.name == 'word/styles.xml' ||
            file.name == 'word/numbering.xml' ||
            (file.name.startsWith('word/header') &&
                file.name.endsWith('.xml')) ||
            (file.name.startsWith('word/footer') && file.name.endsWith('.xml'));

        if (isPatchableXml) {
          content = _stripFalseToggleElements(content);
        }

        output.addFile(ArchiveFile(file.name, content.length, content));
      }

      return Uint8List.fromList(ZipEncoder().encode(output));
    } catch (e) {
      debugPrint('DocxBridge._preprocessDocxForReading hatası: $e');
      return rawBytes;
    }
  }

  static List<int> _stripFalseToggleElements(List<int> content) {
    try {
      var xml = String.fromCharCodes(content);

      const toggles = [
        'b',
        'i',
        'u',
        'strike',
        'dstrike',
        'caps',
        'smallCaps',
        'outline',
        'shadow',
        'emboss',
        'imprint',
        'vanish',
        'specVanish',
      ];

      for (final tag in toggles) {
        final selfClosing = RegExp(
          '<w:$tag\\s+w:val="(0|false|off)"\\s*/>',
          caseSensitive: false,
        );
        xml = xml.replaceAll(selfClosing, '');

        final openClose = RegExp(
          '<w:$tag\\s+w:val="(0|false|off)"\\s*>\\s*</w:$tag>',
          caseSensitive: false,
        );
        xml = xml.replaceAll(openClose, '');
      }

      return xml.codeUnits;
    } catch (_) {
      return content;
    }
  }

  static Future<void> writeFile(DocModel model, String filePath) async {
    try {
      final bytes = await writeBytes(model);
      await File(filePath).writeAsBytes(bytes);
    } catch (e) {
      debugPrint('DocxBridge.writeFile hatası: $e');
      rethrow;
    }
  }

  static Future<Uint8List> writeBytes(DocModel model) async {
    final doc = _modelToDocx(model);
    final rawBytes = await DocxExporter().exportToBytes(doc);
    return _fixDocxPackage(rawBytes, model);
  }

  /// A page number over a header's text, as UYAP draws it, rather than on a
  /// line of its own above it: the number's paragraph framed (`w:framePr`)
  /// at the region's top, with the text running through it. Measured in
  /// LibreOffice, a letterhead numbered at its top right took a row of the
  /// page as a line, and none framed. Only a number at the top of a region
  /// that holds more than it: one alone is the region, and one at the
  /// bottom has nothing after it to hang from.
  static List<int> _framePageNumber(List<int> content) {
    var xml = String.fromCharCodes(content);
    if (!xml.contains(' PAGE ')) return content;
    if (RegExp('<w:p[ >]').allMatches(xml).length < 2) return content;
    final first = RegExp(r'<w:p>(<w:pPr>(.*?)</w:pPr>)?').firstMatch(xml);
    final firstEnd = xml.indexOf('</w:p>');
    if (first == null || firstEnd < 0) return content;
    if (!xml.substring(first.start, firstEnd).contains(' PAGE ')) {
      return content;
    }
    final properties = first[2] ?? '';
    final align = RegExp(r'<w:jc w:val="(\w+)"/>').firstMatch(properties)?[1];
    final x = switch (align) {
      'end' || 'right' => 'right',
      'center' => 'center',
      _ => 'left',
    };
    final frame =
        '<w:framePr w:wrap="through" w:vAnchor="text" w:hAnchor="margin" '
        'w:xAlign="$x" w:y="1"/>';
    xml = xml.replaceRange(
      first.start,
      first.end,
      '<w:p><w:pPr>$frame$properties</w:pPr>',
    );
    return xml.codeUnits;
  }

  /// Where the header and footer print, as UYAP prints them: at their
  /// offsets from the edge, and on the pages their startPage and stopPage
  /// leave them — the first page on its own, or all but the first — which
  /// Word says with a first page of its own (`w:titlePg`).
  static List<int> _regionPlacement(List<int> content, DocModel model) {
    var xml = String.fromCharCodes(content);
    final p = model.pageProperties;
    xml = xml.replaceFirstMapped(RegExp(r'<w:pgMar\b([^>]*?)(/?)>'), (m) {
      final attrs = m[1]!.replaceAll(
        RegExp(r'\s+w:(header|footer)="[^"]*"'),
        '',
      );
      return '<w:pgMar$attrs'
          ' w:header="${(p.headerOffset * 20).round()}"'
          ' w:footer="${(p.footerOffset * 20).round()}"${m[2]}>';
    });
    final allAttrs = model.metadata['pageRegionAttrs'];
    final placed = <(String kind, Match reference, bool first, bool later)>[];
    for (final kind in ['header', 'footer']) {
      final reference = RegExp(
        '<w:${kind}Reference\\b[^>]*w:type="default"[^>]*r:id="([^"]+)"[^>]*/>',
      ).firstMatch(xml);
      if (reference == null) continue;
      final attrs = allAttrs is Map ? allAttrs[kind] : null;
      final regionAttrs = attrs is Map ? attrs : null;
      placed.add((
        kind,
        reference,
        PageNumbering.regionShows(regionAttrs, 1),
        PageNumbering.regionShows(regionAttrs, 2),
      ));
    }
    // A first page of its own is the first page's for header and footer
    // alike: one that is on every page is then named for it too.
    if (placed.any((r) => r.$3 != r.$4)) {
      for (final (kind, reference, first, later) in placed) {
        final id = reference[1];
        final element = 'w:${kind}Reference';
        xml = xml.replaceFirst(
          reference[0]!,
          [
            if (later) '<$element w:type="default" r:id="$id"/>',
            if (first) '<$element w:type="first" r:id="$id"/>',
          ].join(),
        );
      }
      if (!xml.contains('<w:titlePg')) {
        xml = xml.replaceFirst('</w:sectPr>', '<w:titlePg/></w:sectPr>');
      }
    }
    return xml.codeUnits;
  }

  /// Writes a justified paragraph the way OOXML spells it.
  ///
  /// The word for it is `both`. The writer used here emits `justify`, which
  /// Word tolerates, but the reader on the other side of this file accepts
  /// only `both` and `distribute` — so a document saved with justified
  /// paragraphs was read back left aligned. It showed up on 3641 paragraphs
  /// across 131 of 164 archived documents, which is most of them, because a
  /// filing is justified nearly everywhere.
  ///
  /// Only the value changes, and only where it is that one word, so the bytes
  /// around it are left exactly as they were.
  static List<int> _canonicalJustify(List<int> content) {
    final text = String.fromCharCodes(content);
    if (!text.contains('w:jc')) return content;
    return text
        .replaceAllMapped(
          RegExp(r'<w:jc([^>]*)w:val="justify"'),
          (m) => '<w:jc${m[1]}w:val="both"',
        )
        .codeUnits;
  }

  /// Writes a first line pulled out of the indent as OOXML spells it.
  ///
  /// The writer puts it down as a negative `w:firstLine`, which the schema
  /// does not allow — the measure is unsigned — and which Word may refuse. The
  /// same indent is `w:hanging`.
  static List<int> _hangingIndent(List<int> content) {
    final text = String.fromCharCodes(content);
    if (!text.contains('w:firstLine="-')) return content;
    return text
        .replaceAllMapped(
          RegExp(r'w:firstLine="-(\d+)"'),
          (m) => 'w:hanging="${m[1]}"',
        )
        .codeUnits;
  }

  /// Stops the generated style sheet loosening a document that never asked
  /// for it.
  ///
  /// The styles written alongside the text carry `w:line="276"` — a line and
  /// a sixth, which is what a new Word document uses. Nothing in the source
  /// said so: a filing that was single spaced came back at 1.15 and visibly
  /// opened up, on 1614 paragraphs across 32 of 164 archived documents.
  ///
  /// Only the default is removed. A paragraph that does carry a spacing of
  /// its own is written with it on the paragraph, so it is unaffected.
  static List<int> _dropDefaultLineSpacing(List<int> content) {
    final text = String.fromCharCodes(content);
    if (!text.contains('w:line=')) return content;
    return text.replaceAll(RegExp(r'\s*w:line="\d+"'), '').codeUnits;
  }

  static Uint8List _fixDocxPackage(Uint8List rawBytes, [DocModel? model]) {
    try {
      final inputArchive = ZipDecoder().decodeBytes(rawBytes);
      final outputArchive = Archive();

      final existingFiles = <String>{};
      for (final file in inputArchive) {
        if (file.isFile) existingFiles.add(file.name);
      }

      bool hasNumbering = false;
      for (final file in inputArchive) {
        if (file.isFile && file.name == 'word/document.xml') {
          final docXml = String.fromCharCodes(file.content as List<int>);
          hasNumbering = docXml.contains('<w:numPr');
          break;
        }
      }

      for (final file in inputArchive) {
        if (!file.isFile) continue;

        List<int> content = file.content as List<int>;

        if (file.name == 'word/_rels/fontTable.xml.rels') {
          final text = String.fromCharCodes(content);
          if (!text.contains('Target=')) continue;
        }

        if (file.name == '[Content_Types].xml') {
          content = _fixContentTypes(content, existingFiles);
        }

        if (RegExp(r'^word/(header|footer)\d*\.xml$').hasMatch(file.name)) {
          content = _framePageNumber(content);
        }

        if (file.name == 'word/document.xml') {
          content = _hangingIndent(_canonicalJustify(content));
          if (model != null) content = _regionPlacement(content, model);
        }

        if (file.name == 'word/styles.xml') {
          content = _dropDefaultLineSpacing(content);
        }

        if (file.name == 'word/numbering.xml') {
          if (!hasNumbering) continue;
          content = _fixNumberingXml(content);
        }

        if (file.name.endsWith('.rels') &&
            file.name != 'word/_rels/document.xml.rels' &&
            file.name != '_rels/.rels') {
          final text = String.fromCharCodes(content);
          if (!text.contains('Target=')) continue;
        }

        outputArchive.addFile(ArchiveFile(file.name, content.length, content));
      }

      return Uint8List.fromList(ZipEncoder().encode(outputArchive));
    } catch (e) {
      debugPrint('DocxBridge._fixDocxPackage hatası: $e');
      return rawBytes;
    }
  }

  static List<int> _fixContentTypes(
    List<int> content,
    Set<String> existingFiles,
  ) {
    try {
      var xml = String.fromCharCodes(content);

      final overridePattern = RegExp(
        r'<Override\s+[^>]*PartName="(/[^"]+)"[^>]*/?>',
      );

      xml = xml.replaceAllMapped(overridePattern, (match) {
        final partName = match.group(1)!;
        final zipPath = partName.startsWith('/')
            ? partName.substring(1)
            : partName;

        if (existingFiles.contains(zipPath)) {
          return match.group(0)!;
        }
        return '';
      });

      return xml.codeUnits;
    } catch (_) {
      return content;
    }
  }

  static List<int> _fixNumberingXml(List<int> content) {
    try {
      var xml = String.fromCharCodes(content);

      if (xml.contains('<w:abstractNum') && !xml.contains('<w:num ')) {
        final absPattern = RegExp(r'w:abstractNumId="(\d+)"');
        final absIds = absPattern
            .allMatches(xml)
            .map((m) => m.group(1)!)
            .toSet();

        final numElements = StringBuffer();
        var numId = 1;
        for (final absId in absIds) {
          numElements.write(
            '<w:num w:numId="$numId">'
            '<w:abstractNumId w:val="$absId"/>'
            '</w:num>',
          );
          numId++;
        }

        xml = xml.replaceFirst(
          '</w:numbering>',
          '${numElements.toString()}</w:numbering>',
        );
      }

      return xml.codeUnits;
    } catch (_) {
      return content;
    }
  }

  /// The document's default tab stop in points, from `word/settings.xml`.
  ///
  /// Word puts a tab past a paragraph's own stops on the next of these, and
  /// 407 of 503 archived documents set it to 708 twips — 1.25 cm, not the
  /// 72 points a UDF gets.
  static double? _defaultTabStop(Uint8List bytes) {
    try {
      final settings = ZipDecoder()
          .decodeBytes(bytes)
          .findFile('word/settings.xml');
      if (settings == null) return null;
      final xml = utf8.decode(
        settings.content as List<int>,
        allowMalformed: true,
      );
      final twips = RegExp(r'<w:defaultTabStop\s+w:val="(\d+)"')
          .firstMatch(xml)
          ?.group(1);
      final value = int.tryParse(twips ?? '');
      return value == null || value <= 0 ? null : value / 20;
    } catch (_) {
      return null;
    }
  }

  static DocModel _docxToModel(
    DocxBuiltDocument doc, {
    double? defaultTabStop,
  }) {
    final blocks = <DocBlock>[];

    for (final element in doc.elements) {
      if (element is DocxParagraph) {
        final images = element.children.whereType<DocxInlineImage>();
        final paragraph = _paragraphToBlock(element);
        // A picture on a line of its own arrives as a paragraph holding
        // nothing but the picture. Keeping both the paragraph and the picture
        // adds a blank line that was never in the document, and the blank line
        // survives the next save: writing puts the picture back in a paragraph
        // of its own, so every round trip through DOCX grew the document by
        // one empty paragraph per picture.
        if (images.isEmpty || paragraph.plainText.isNotEmpty) {
          blocks.add(paragraph);
        }
        for (final image in images) {
          blocks.add(_imageToBlock(image));
        }
      } else if (element is DocxImage) {
        blocks.add(_imageToBlock(element.asInline));
      } else if (element is DocxList) {
        for (final item in element.items) {
          blocks.add(_listItemToBlock(item, element.style));
        }
      } else if (element is DocxTable) {
        final tableRows = <DocTableRow>[];
        for (int rowIdx = 0; rowIdx < element.rows.length; rowIdx++) {
          final row = element.rows[rowIdx];
          final tableCells = <DocTableCell>[];
          for (final cell in row.cells) {
            final cellBlocks = <DocBlock>[];
            for (final child in cell.children) {
              if (child is DocxParagraph) {
                cellBlocks.add(_paragraphToBlock(child));
                for (final image
                    in child.children.whereType<DocxInlineImage>()) {
                  cellBlocks.add(_imageToBlock(image));
                }
              }
            }
            if (cellBlocks.isEmpty) {
              cellBlocks.add(DocBlock(plainText: ''));
            }
            tableCells.add(
              DocTableCell(
                blocks: cellBlocks,
                colspan: cell.colSpan,
                rowspan: cell.rowSpan,
              ),
            );
          }
          tableRows.add(DocTableRow(cells: tableCells, isHeader: rowIdx == 0));
        }
        blocks.add(
          DocBlock(
            type: DocBlockType.table,
            plainText: '',
            table: DocTable(rows: tableRows),
          ),
        );
      }
    }

    if (blocks.isEmpty) {
      blocks.add(DocBlock(plainText: ''));
    }

    final section = doc.section;
    return DocModel(
      blocks: blocks,
      // Word's tab rules, not UYAP's: see TabRules.
      metadata: {'tabRules': 'word', 'defaultTabStop': defaultTabStop ?? 36.0},
      pageProperties: section == null
          ? const DocPageProperties()
          : DocPageProperties(
              marginLeft: section.marginLeft / 20,
              marginRight: section.marginRight / 20,
              marginTop: section.marginTop / 20,
              marginBottom: section.marginBottom / 20,
              landscape: section.orientation == DocxPageOrientation.landscape,
            ),
    );
  }

  static DocBlock _imageToBlock(DocxInlineImage image) => DocBlock(
    type: DocBlockType.image,
    plainText: '',
    imageBase64: base64Encode(image.bytes),
    imageMime: image.extension == 'jpg' || image.extension == 'jpeg'
        ? 'image/jpeg'
        : 'image/png',
    imageWidth: image.width,
    imageHeight: image.height,
  );

  static DocBlock _paragraphToBlock(DocxParagraph para) {
    final buffer = StringBuffer();
    final spans = <DocSpan>[];

    for (final child in para.children) {
      if (child is DocxLineBreak) buffer.write('\n');
      if (child is DocxTab) buffer.write('\t');
      if (child is DocxText) {
        final start = buffer.length;
        buffer.write(child.content);

        final isBold = child.fontWeight == DocxFontWeight.bold;
        final isItalic = child.fontStyle == DocxFontStyle.italic;
        final isUnderline = child.decoration == DocxTextDecoration.underline;
        final isStrike = child.decoration == DocxTextDecoration.strikethrough;
        final hasFont = child.fontFamily != null;
        final hasSize = child.fontSize != null;

        if (isBold ||
            isItalic ||
            isUnderline ||
            isStrike ||
            hasFont ||
            hasSize ||
            child.color != null ||
            child.shadingFill != null ||
            child.isSuperscript ||
            child.isSubscript) {
          spans.add(
            DocSpan(
              startOffset: start,
              length: child.content.length,
              bold: isBold,
              italic: isItalic,
              underline: isUnderline,
              strikethrough: isStrike,
              fontFamily: child.fontFamily,
              fontSize: child.fontSize,
              color: child.color?.hex == 'auto'
                  ? null
                  : child.color == null
                  ? null
                  : '#${child.color!.hex}',
              background: child.shadingFill == null
                  ? null
                  : '#${child.shadingFill}',
              superscript: child.isSuperscript,
              subscript: child.isSubscript,
            ),
          );
        }
      }
    }

    DocAlignment alignment = DocAlignment.left;
    switch (para.align) {
      case DocxAlign.center:
        alignment = DocAlignment.center;
        break;
      case DocxAlign.right:
        alignment = DocAlignment.right;
        break;
      case DocxAlign.justify:
        alignment = DocAlignment.justify;
        break;
      default:
        alignment = DocAlignment.left;
    }

    double twipsToPt(int? twips) => twips == null ? 0.0 : twips / 20.0;

    double? resolveLineSpacing(int? lineTwips, String? rule) {
      if (lineTwips == null) return null;
      return lineTwips / 240.0;
    }

    // Word writes a hanging indent as a first line pulled out of the left
    // indent. It is held the way UYAP holds one — where the first row starts,
    // and how far in the others start from there — since the preview and the
    // editor draw that, and neither can pull a first line out past the rest.
    final left = twipsToPt(para.indentLeft);
    final first = twipsToPt(para.indentFirstLine);
    final hanging = first < 0 ? math.min(-first, left) : 0.0;
    return DocBlock(
      alignment: alignment,
      plainText: buffer.toString(),
      spans: spans,
      leftIndent: left - hanging,
      rightIndent: twipsToPt(para.indentRight),
      firstLineIndent: first < 0 ? 0 : first,
      hanging: hanging,
      spacingBefore: twipsToPt(para.spacingBefore),
      spacingAfter: twipsToPt(para.spacingAfter),
      lineSpacing: resolveLineSpacing(para.lineSpacing, para.lineRule),
    );
  }

  static DocBlock _listItemToBlock(DocxListItem item, DocxListStyle style) {
    final buffer = StringBuffer();
    for (final child in item.children) {
      if (child is DocxText) {
        buffer.write(child.content);
      }
    }
    final text = buffer.toString();
    final listType = _isOrderedStyle(style)
        ? DocListType.ordered
        : DocListType.unordered;

    return DocBlock(
      type: DocBlockType.listItem,
      plainText: text,
      listType: listType,
      listLevel: item.level,
    );
  }

  static bool _isOrderedStyle(DocxListStyle style) {
    return style == DocxListStyle.decimal ||
        style == DocxListStyle.lowerAlpha ||
        style == DocxListStyle.upperAlpha ||
        style == DocxListStyle.lowerRoman ||
        style == DocxListStyle.upperRoman;
  }

  /// [blocks] as Word blocks: the body's, or a header's or footer's.
  static List<DocxBlock> _docxBlocks(List<DocBlock> blocks) {
    final out = <DocxBlock>[];
    for (final block in blocks) {
      if (block.type == DocBlockType.table && block.table != null) {
        final docxRows = <DocxTableRow>[];
        for (final row in block.table!.rows) {
          final docxCells = <DocxTableCell>[];
          for (final cell in row.cells) {
            final cellChildren = <DocxBlock>[];
            for (final cellBlock in cell.blocks) {
              final children = _buildDocxChildren(cellBlock);
              cellChildren.add(
                DocxParagraph(
                  children: children,
                  align: _toDocxAlign(cellBlock.alignment),
                ),
              );
            }
            if (cellChildren.isEmpty) {
              cellChildren.add(DocxParagraph(children: [DocxText('')]));
            }
            docxCells.add(
              DocxTableCell(
                children: cellChildren,
                colSpan: cell.colspan,
                rowSpan: cell.rowspan,
                // Word writes a fill as six hex digits with no hash.
                shadingFill: cell.backgroundColor?.replaceFirst('#', ''),
              ),
            );
          }
          docxRows.add(DocxTableRow(cells: docxCells));
        }
        out.add(DocxTable(rows: docxRows));
      } else if (block.type == DocBlockType.image &&
          block.imageBase64 != null) {
        out.add(
          DocxImage(
            bytes: base64Decode(block.imageBase64!),
            extension: block.imageMime == 'image/jpeg' ? 'jpg' : 'png',
            width: block.imageWidth ?? 200,
            height: block.imageHeight ?? 150,
            align: _toDocxAlign(block.alignment),
          ),
        );
      } else if (block.type == DocBlockType.listItem) {
        final children = _buildDocxChildren(block);
        final listItem = DocxListItem(children, level: block.listLevel);
        final list = DocxList(
          items: [listItem],
          isOrdered: block.listType == DocListType.ordered,
        );
        out.add(list);
      } else {
        out.add(
          DocxParagraph(
            children: _buildDocxChildren(block),
            align: _toDocxAlign(block.alignment),
            // Word's own way round: the rows after the first set in, and the
            // first pulled back out by the hanging indent.
            indentLeft: ((block.leftIndent + block.hanging) * 20).round(),
            indentRight: (block.rightIndent * 20).round(),
            indentFirstLine: ((block.firstLineIndent - block.hanging) * 20)
                .round(),
            spacingBefore: (block.spacingBefore * 20).round(),
            spacingAfter: (block.spacingAfter * 20).round(),
            lineSpacing: block.lineSpacing == null
                ? null
                : (block.lineSpacing! * 240).round(),
            lineRule: 'auto',
          ),
        );
      }
    }
    return out;
  }

  /// A header's or footer's page number as a paragraph of its own, at the
  /// top or the bottom of the region and aligned as UYAP draws it: Word
  /// cannot draw one over the region's text, as UYAP does, so it takes a
  /// line of it. The number and the page count are Word's own fields.
  static DocxParagraph _pageNumberParagraph(PageNumbering numbering) {
    DocxText text(String value) => DocxText(
      value,
      fontFamily: numbering.fontFace,
      fontSize: numbering.fontSize,
      fontWeight: numbering.bold ? DocxFontWeight.bold : DocxFontWeight.normal,
      fontStyle: numbering.italic ? DocxFontStyle.italic : DocxFontStyle.normal,
    );
    _DocxField field(String instruction, String shown) => _DocxField(
      instruction,
      shown,
      font: numbering.fontFace,
      size: numbering.fontSize,
      bold: numbering.bold,
      italic: numbering.italic,
    );
    return DocxParagraph(
      align: switch (numbering.align) {
        PageNumberAlign.left => DocxAlign.left,
        PageNumberAlign.center => DocxAlign.center,
        PageNumberAlign.right => DocxAlign.right,
      },
      children: [
        if (numbering.prefix.isNotEmpty) text(numbering.prefix),
        field('PAGE', '1'),
        if (numbering.withTotal) ...[
          text(numbering.separator),
          field('NUMPAGES', '1'),
        ],
        if (numbering.suffix.isNotEmpty) text(numbering.suffix),
      ],
    );
  }

  /// The document's header or footer of [kind] as Word blocks, its page
  /// number with it; null when it has none.
  static List<DocxBlock>? _region(DocModel model, String kind) {
    final key = [
      kind,
      'odd_page_$kind',
      'first_page_$kind',
    ].where(model.pageRegions.containsKey).firstOrNull;
    if (key == null) return null;
    final attrs = (model.metadata['pageRegionAttrs'] as Map?)?[key];
    final numbering = PageNumbering.parse(attrs is Map ? attrs : null);
    final region = model.pageRegions[key]!;
    final blocks = _docxBlocks(region);
    if (numbering == null) return blocks;
    final number = _pageNumberParagraph(numbering);
    // A region that holds nothing but the number, as footers mostly do, is
    // the number: set beside an empty line it would take two, where UYAP
    // draws it over the one.
    if (PageNumbering.onlyNumber(region)) return [number];
    return numbering.top ? [number, ...blocks] : [...blocks, number];
  }

  static DocxBuiltDocument _modelToDocx(DocModel model) {
    final builder = DocxDocumentBuilder();
    for (final block in _docxBlocks(model.blocks)) {
      builder.add(block);
    }

    final built = builder.build();
    final p = model.pageProperties;
    return DocxBuiltDocument(
      elements: built.elements,
      section: DocxSectionDef(
        pageSize: DocxPageSize.a4,
        orientation: p.landscape
            ? DocxPageOrientation.landscape
            : DocxPageOrientation.portrait,
        marginLeft: (p.marginLeft * 20).round(),
        marginRight: (p.marginRight * 20).round(),
        marginTop: (p.marginTop * 20).round(),
        marginBottom: (p.marginBottom * 20).round(),
        header: switch (_region(model, 'header')) {
          final blocks? => DocxHeader(children: blocks),
          null => null,
        },
        footer: switch (_region(model, 'footer')) {
          final blocks? => DocxFooter(children: blocks),
          null => null,
        },
      ),
    );
  }

  static List<DocxInline> _buildDocxChildren(DocBlock block) {
    final children = <DocxInline>[];
    final text = block.plainText;

    // A tab or a line break inside `w:t` is only white space to Word, and
    // LibreOffice drops it: UYAP's column of values after "DOSYA NO\t:" came
    // out as "DOSYA NO:". Each has an element of its own.
    void add(String value, DocxText Function(String piece) run) {
      var start = 0;
      for (var i = 0; i < value.length; i++) {
        final c = value[i];
        if (c != '\t' && c != '\n') continue;
        if (i > start) children.add(run(value.substring(start, i)));
        children.add(c == '\t' ? const DocxTab() : const DocxLineBreak());
        start = i + 1;
      }
      if (start < value.length) children.add(run(value.substring(start)));
    }

    DocxText plain(String piece) => DocxText(piece);

    if (block.spans.isEmpty) {
      add(text, plain);
      if (children.isEmpty) children.add(DocxText(text));
      return children;
    }

    final sortedSpans = List<DocSpan>.from(block.spans)
      ..sort((a, b) => a.startOffset.compareTo(b.startOffset));

    int pos = 0;
    for (final span in sortedSpans) {
      if (span.startOffset > pos && span.startOffset <= text.length) {
        final plainPart = text.substring(pos, span.startOffset);
        if (plainPart.isNotEmpty) add(plainPart, plain);
      }

      final end = (span.startOffset + span.length).clamp(0, text.length);
      final start = span.startOffset.clamp(0, text.length);
      if (start < end) {
        add(
          text.substring(start, end),
          (piece) => DocxText(
            piece,
            fontWeight: span.bold ? DocxFontWeight.bold : DocxFontWeight.normal,
            fontStyle: span.italic
                ? DocxFontStyle.italic
                : DocxFontStyle.normal,
            // A list since docx_creator 1.1, so a run can be both.
            decorations: [
              if (span.underline) DocxTextDecoration.underline,
              if (span.strikethrough) DocxTextDecoration.strikethrough,
            ],
            fontFamily: span.fontFamily,
            fontSize: span.fontSize,
            color: span.color == null ? null : DocxColor(span.color!),
            shadingFill: span.background?.replaceFirst('#', ''),
            isSuperscript: span.superscript,
            isSubscript: span.subscript,
          ),
        );
      }

      pos = end;
    }

    if (pos < text.length) add(text.substring(pos), plain);

    if (children.isEmpty) {
      children.add(DocxText(text));
    }

    return children;
  }

  static DocxAlign _toDocxAlign(DocAlignment align) {
    switch (align) {
      case DocAlignment.center:
        return DocxAlign.center;
      case DocAlignment.right:
        return DocxAlign.right;
      case DocAlignment.justify:
        return DocxAlign.justify;
      case DocAlignment.left:
        return DocxAlign.left;
    }
  }
}

/// A Word field — the page number, the page count — in the number's own
/// font, with what it shows until Word works it out.
class _DocxField extends DocxInline {
  const _DocxField(
    this.instruction,
    this.shown, {
    required this.font,
    required this.size,
    this.bold = false,
    this.italic = false,
  });

  final String instruction, shown, font;
  final double size;
  final bool bold, italic;

  @override
  void accept(DocxVisitor visitor) => visitor.visitText(this);

  @override
  void buildXml(XmlBuilder builder) {
    void run(void Function() content) => builder.element(
      'w:r',
      nest: () {
        builder.element(
          'w:rPr',
          nest: () {
            builder.element(
              'w:rFonts',
              nest: () {
                builder
                  ..attribute('w:ascii', font)
                  ..attribute('w:hAnsi', font)
                  ..attribute('w:cs', font);
              },
            );
            if (bold) builder.element('w:b');
            if (italic) builder.element('w:i');
            builder.element(
              'w:sz',
              nest: () => builder.attribute('w:val', '${(size * 2).round()}'),
            );
          },
        );
        content();
      },
    );
    run(
      () => builder.element(
        'w:fldChar',
        nest: () => builder.attribute('w:fldCharType', 'begin'),
      ),
    );
    run(
      () => builder.element(
        'w:instrText',
        nest: () {
          builder
            ..attribute('xml:space', 'preserve')
            ..text(' $instruction ');
        },
      ),
    );
    run(
      () => builder.element(
        'w:fldChar',
        nest: () => builder.attribute('w:fldCharType', 'separate'),
      ),
    );
    run(() => builder.element('w:t', nest: () => builder.text(shown)));
    run(
      () => builder.element(
        'w:fldChar',
        nest: () => builder.attribute('w:fldCharType', 'end'),
      ),
    );
  }
}

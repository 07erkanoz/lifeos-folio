/// UDF (UYAP Doküman Formatı) okuyucu.
/// ZIP arşivi içindeki content.xml'den formatlı DocModel üretir.
/// UTF-8 ve Windows-1254 (ISO-8859-9) çift kodlama ve RTF kaçışlarını destekler.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import '../../models/document_model.dart';
import 'signature_parser.dart';

class UdfReader {
  static const Map<int, int> _win1254Table = {
    0x80: 0x20AC,
    0x82: 0x201A,
    0x83: 0x0192,
    0x84: 0x201E,
    0x85: 0x2026,
    0x86: 0x2020,
    0x87: 0x2021,
    0x88: 0x02C6,
    0x89: 0x2030,
    0x8A: 0x0160,
    0x8B: 0x2039,
    0x8C: 0x0152,
    0x91: 0x2018,
    0x92: 0x2019,
    0x93: 0x201C,
    0x94: 0x201D,
    0x95: 0x2022,
    0x96: 0x2013,
    0x97: 0x2014,
    0x98: 0x02DC,
    0x99: 0x2122,
    0x9A: 0x0161,
    0x9B: 0x203A,
    0x9C: 0x0153,
    0x9F: 0x0178,
    0xD0: 0x011E, // Ğ
    0xDD: 0x0130, // İ
    0xDE: 0x015E, // Ş
    0xF0: 0x011F, // ğ
    0xFD: 0x0131, // ı
    0xFE: 0x015F, // ş
  };

  static DocModel? readFile(String filePath) {
    try {
      final bytes = File(filePath).readAsBytesSync();
      return readBytes(bytes);
    } catch (e) {
      debugPrint('UdfReader.readFile hatası: $e');
      return null;
    }
  }

  static DocModel? readBytes(List<int> bytes) {
    try {
      List<int>? xmlBytes;
      bool hasSignature = false;
      List<int>? signatureBytes;

      try {
        final archive = ZipDecoder().decodeBytes(bytes);
        for (final file in archive) {
          if (file.isFile && file.name.toLowerCase() == 'content.xml') {
            xmlBytes = file.content as List<int>;
          }
          if (file.isFile && file.name.toLowerCase() == 'sign.sgn') {
            hasSignature = true;
            signatureBytes = file.content as List<int>;
          }
        }
      } catch (e) {
        debugPrint('UdfReader: Standart ZIP başarısız: $e');
      }

      if (xmlBytes == null) {
        try {
          final result = _readZipFromLocalHeaders(bytes);
          xmlBytes = result['content.xml'];
          signatureBytes ??= result['sign.sgn'];
          hasSignature = signatureBytes != null;
        } catch (e2) {
          debugPrint('UdfReader: local headers başarısız: $e2');
        }
      }

      if (xmlBytes == null) return null;

      final xmlContent = _smartDecode(xmlBytes);
      return _parseXml(xmlContent, hasSignature, signatureBytes);
    } catch (e) {
      debugPrint('UdfReader.readBytes hatası: $e');
      return null;
    }
  }

  static Map<String, List<int>> _readZipFromLocalHeaders(List<int> bytes) {
    final result = <String, List<int>>{};
    var offset = 0;

    while (offset + 30 < bytes.length) {
      if (bytes[offset] != 0x50 ||
          bytes[offset + 1] != 0x4B ||
          bytes[offset + 2] != 0x03 ||
          bytes[offset + 3] != 0x04) {
        break;
      }

      final compressionMethod = bytes[offset + 8] | (bytes[offset + 9] << 8);
      var compressedSize =
          bytes[offset + 18] |
          (bytes[offset + 19] << 8) |
          (bytes[offset + 20] << 16) |
          (bytes[offset + 21] << 24);
      final fileNameLen = bytes[offset + 26] | (bytes[offset + 27] << 8);
      final extraLen = bytes[offset + 28] | (bytes[offset + 29] << 8);

      final fileName = String.fromCharCodes(
        bytes.sublist(offset + 30, offset + 30 + fileNameLen),
      );
      final dataStart = offset + 30 + fileNameLen + extraLen;
      final flags = bytes[offset + 6] | (bytes[offset + 7] << 8);
      final hasDataDescriptor = (flags & 0x08) != 0;

      if (compressedSize == 0 && hasDataDescriptor) {
        var searchPos = dataStart;
        while (searchPos < bytes.length - 4) {
          if (bytes[searchPos] == 0x50 && bytes[searchPos + 1] == 0x4B) {
            if ((bytes[searchPos + 2] == 0x03 &&
                    bytes[searchPos + 3] == 0x04) ||
                (bytes[searchPos + 2] == 0x07 &&
                    bytes[searchPos + 3] == 0x08)) {
              break;
            }
          }
          searchPos++;
        }
        compressedSize = searchPos - dataStart;
        if (searchPos + 4 < bytes.length &&
            bytes[searchPos] == 0x50 &&
            bytes[searchPos + 1] == 0x4B &&
            bytes[searchPos + 2] == 0x07 &&
            bytes[searchPos + 3] == 0x08) {
          offset = searchPos + 16;
        } else {
          offset = searchPos;
        }
      } else {
        offset = dataStart + compressedSize;
      }

      if (dataStart + compressedSize > bytes.length) break;
      final compressedData = bytes.sublist(
        dataStart,
        dataStart + compressedSize,
      );

      try {
        List<int> fileData;
        if (compressionMethod == 8) {
          fileData = ZLibCodec(raw: true).decode(compressedData);
        } else if (compressionMethod == 0) {
          fileData = compressedData;
        } else {
          continue;
        }
        result[fileName.toLowerCase()] = fileData;
      } catch (e) {
        debugPrint('UdfReader decompress error ($fileName): $e');
      }
    }

    return result;
  }

  static String _smartDecode(List<int> bytes) {
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
            (bytes[0] == 0xfe && bytes[1] == 0xff))) {
      final littleEndian = bytes[0] == 0xff;
      if (bytes.length.isOdd) {
        throw const FormatException('UTF-16 içerik eksik.');
      }
      return String.fromCharCodes([
        for (var i = 2; i + 1 < bytes.length; i += 2)
          littleEndian
              ? bytes[i] | (bytes[i + 1] << 8)
              : (bytes[i] << 8) | bytes[i + 1],
      ]);
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return _decodeWindows1254(bytes);
    }
  }

  static String _decodeWindows1254(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      final mapped = _win1254Table[b];
      sb.writeCharCode(mapped ?? b);
    }
    return sb.toString();
  }

  static int _win1254ToUnicode(int byte) {
    return _win1254Table[byte] ?? byte;
  }

  static (String decoded, List<int> offsetMap) _decodeRtfEscapes(String raw) {
    if (!raw.contains("\\'")) {
      final identity = List<int>.generate(raw.length + 1, (i) => i);
      return (raw, identity);
    }

    final sb = StringBuffer();
    final mapping = List<int>.filled(raw.length + 1, 0);
    int i = 0;
    int decodedPos = 0;

    while (i < raw.length) {
      mapping[i] = decodedPos;

      if (i + 3 < raw.length && raw[i] == '\\' && raw[i + 1] == "'") {
        final hexStr = raw.substring(i + 2, i + 4);
        final byte = int.tryParse(hexStr, radix: 16);
        if (byte != null) {
          sb.writeCharCode(_win1254ToUnicode(byte));
          mapping[i + 1] = decodedPos;
          mapping[i + 2] = decodedPos;
          mapping[i + 3] = decodedPos;
          i += 4;
          decodedPos++;
          continue;
        }
      }

      sb.write(raw[i]);
      i++;
      decodedPos++;
    }

    mapping[raw.length] = decodedPos;
    return (sb.toString(), mapping);
  }

  static DocModel? _parseXml(
    String xmlString,
    bool hasSignature,
    List<int>? signatureBytes,
  ) {
    try {
      final doc = XmlDocument.parse(xmlString);
      final template = doc.findAllElements('template').firstOrNull;
      if (template == null) return null;

      final contentEl = template.findAllElements('content').firstOrNull;
      final rawText = _extractCdata(contentEl);
      // A header's and footer's own attributes, as the file writes them:
      // resolving styles below writes the font into every element, and
      // kept from after that, it went out with every save onto regions UYAP
      // had written without it.
      final regionAttrs = {
        for (final region
            in template.findElements('elements').firstOrNull?.childElements ??
                const <XmlElement>[])
          if (_isPageRegion(region.name.local))
            region.name.local: {
              for (final a in region.attributes) a.name.local: a.value,
            },
      };
      _resolveStyles(template);

      final (decodedText, offsetMap) = _decodeRtfEscapes(rawText);
      final pageProps = _parsePageProperties(template);
      final styles = _parseStyles(template);
      final fields = _fieldValues(template);
      final blocks = _parseElements(
        template,
        rawText,
        decodedText,
        offsetMap,
        fields,
      );
      final formatId = template.getAttribute('format_id') ?? '1.8';

      final elementsEl = template.findAllElements('elements').firstOrNull;
      String? headerXml;
      String? footerXml;
      if (elementsEl != null) {
        for (final el in elementsEl.childElements) {
          final name = el.name.local.toLowerCase();
          if (name == 'header') {
            headerXml = el.toXmlString();
          } else if (name == 'footer') {
            footerXml = el.toXmlString();
          }
        }
      }

      return DocModel(
        pageProperties: pageProps,
        styles: styles,
        blocks: blocks,
        pageRegions: {
          if (elementsEl != null)
            for (final region in elementsEl.childElements)
              if (_isPageRegion(region.name.local))
                region.name.local: _parseContainer(
                  region,
                  rawText,
                  decodedText,
                  offsetMap,
                  fields,
                ),
        },
        metadata: {
          'hasSignature': hasSignature,
          'signatureBytes': ?signatureBytes,
          if (signatureBytes != null)
            'signatureInfos': UdfSignatureParser.parse(signatureBytes),
          'formatId': formatId,
          'resolver': template
              .findElements('elements')
              .firstOrNull
              ?.getAttribute('resolver'),
          'headerXml': ?headerXml,
          'footerXml': ?footerXml,
          // How the header prints: which page it starts on, and how UYAP
          // numbers the pages in the footer. None of it is text, so nothing
          // else in the document carries it, and a save without it silently
          // restarts page numbering from one.
          'pageRegionAttrs': regionAttrs,
        },
      );
    } catch (e) {
      debugPrint('UdfReader._parseXml hatası: $e');
      return null;
    }
  }

  static String _extractCdata(XmlElement? element) {
    if (element == null) return '';
    return element.innerText;
  }

  static bool _isPageRegion(String name) =>
      name == 'header' ||
      name == 'footer' ||
      name.endsWith('_header') ||
      name.endsWith('_footer');

  static void _resolveStyles(XmlElement template) {
    final styles = <String, XmlElement>{
      for (final style
          in template
              .findElements('styles')
              .expand((e) => e.findElements('style')))
        ?style.getAttribute('name'): style,
    };
    Map<String, String> attributes(XmlElement e) => {
      for (final a in e.attributes) a.name.local: a.value,
    };
    Map<String, String> resolve(String? name, [Set<String>? seen]) {
      if (name == null || !styles.containsKey(name)) return {};
      final visited = {...?seen};
      if (!visited.add(name)) return {};
      final style = styles[name]!;
      return {
        ...resolve(style.getAttribute('resolver'), visited),
        ...attributes(style),
      };
    }

    void visit(XmlElement e, Map<String, String> inherited) {
      final merged = {
        ...inherited,
        ...resolve(e.getAttribute('resolver') ?? e.getAttribute('style')),
        ...attributes(e),
      };
      for (final key in [
        'family',
        'size',
        'bold',
        'italic',
        'underline',
        'strikethrough',
        'superscript',
        'subscript',
        'foreground',
        'background',
      ]) {
        if (merged[key] case final value?) e.setAttribute(key, value);
      }
      // A paragraph resolves its own layout the same way: UYAP justifies a
      // paragraph that says nothing about alignment when its style does.
      // Measured across 870 documents, 72 paragraphs in 8 of them take their
      // alignment or spacing from a style, and UYAP's clipboard, which
      // resolves every attribute, shows them so.
      // Only what differs from having no value is written in: a paragraph
      // is read the same without LineSpacing="0.0" as with it.
      if (e.name.local == 'paragraph') {
        for (final key in _paragraphKeys) {
          final value = merged[key];
          if (value == null || e.getAttribute(key) != null) continue;
          final unset = key == 'TabSet'
              ? value.trim().isEmpty
              : double.tryParse(value) == 0;
          if (!unset) e.setAttribute(key, value);
        }
      }
      for (final child in e.childElements) {
        visit(child, merged);
      }
    }

    final elements = template.findElements('elements').firstOrNull;
    if (elements != null) {
      final defaultStyle = styles.containsKey('hvl-default')
          ? 'hvl-default'
          : 'default';
      visit(elements, {
        'family': 'Times New Roman',
        'size': '12',
        ...resolve(elements.getAttribute('resolver') ?? defaultStyle),
      });
    }
  }

  /// What a paragraph in UYAP may leave to its style or its container.
  static const _paragraphKeys = [
    'Alignment',
    'LeftIndent',
    'RightIndent',
    'FirstLineIndent',
    'Hanging',
    'SpaceAbove',
    'SpaceBelow',
    'LineSpacing',
    'TabSet',
  ];

  static DocPageProperties _parsePageProperties(XmlElement template) {
    final propsEl = template.findAllElements('properties').firstOrNull;
    if (propsEl == null) return const DocPageProperties();

    final pageFormat = propsEl.findAllElements('pageFormat').firstOrNull;
    if (pageFormat == null) return const DocPageProperties();

    return DocPageProperties(
      marginLeft: _parseDouble(pageFormat.getAttribute('leftMargin'), 42.525),
      marginRight: _parseDouble(pageFormat.getAttribute('rightMargin'), 42.525),
      marginTop: _parseDouble(pageFormat.getAttribute('topMargin'), 42.525),
      marginBottom: _parseDouble(
        pageFormat.getAttribute('bottomMargin'),
        42.525,
      ),
      landscape: pageFormat.getAttribute('paperOrientation') == '2',
      headerOffset: _parseDouble(
        pageFormat.getAttribute('headerFOffset'),
        20.0,
      ),
      footerOffset: _parseDouble(
        pageFormat.getAttribute('footerFOffset'),
        20.0,
      ),
    );
  }

  static List<DocStyleDef> _parseStyles(XmlElement template) {
    final stylesEl = template.findAllElements('styles').firstOrNull;
    if (stylesEl == null) return [];

    return stylesEl.findAllElements('style').map((el) {
      return DocStyleDef(
        name: el.getAttribute('name') ?? 'default',
        family: el.getAttribute('family') ?? 'Times New Roman',
        size: _parseDouble(el.getAttribute('size'), 12.0),
        description: el.getAttribute('description'),
        bold: el.getAttribute('bold') == 'true',
        italic: el.getAttribute('italic') == 'true',
      );
    }).toList();
  }

  static List<DocBlock> _parseElements(
    XmlElement template,
    String rawText,
    String decodedText,
    List<int> offsetMap,
    Map<String, String> fields,
  ) {
    final elementsEl = template.findAllElements('elements').firstOrNull;
    if (elementsEl == null) return _fallbackParse(decodedText);

    return _parseContainer(elementsEl, rawText, decodedText, offsetMap, fields);
  }

  /// A template's filled-in values, by field name.
  ///
  /// A document UYAP makes from a template — a request to the enforcement
  /// office, a mediation application — keeps each blank as a `field` whose
  /// text is its own name, `il_Ilce`, and the value in a `<data>` section at
  /// the end: `<il_Ilce>MANAVGAT</il_Ilce>`. UYAP shows the value. A name
  /// may appear twice, the second time empty; the value is the first one
  /// with anything in it.
  static Map<String, String> _fieldValues(XmlElement template) {
    final values = <String, String>{};
    for (final data in template.findElements('data')) {
      for (final field in data.childElements) {
        final name = field.name.local;
        final value = field.innerText;
        if (values[name]?.isNotEmpty != true) values[name] = value;
      }
    }
    return values;
  }

  /// Blocks from UYAP's element tree without the file around it: [elements]
  /// is laid out as a UDF's `<elements>`, and its runs point into [text] the
  /// way a UDF's point into its content. UYAP's clipboard carries this same
  /// tree (see [UyapClipboard]), so what is pasted from UYAP is read by the
  /// code that reads the file.
  static List<DocBlock> readElements(XmlElement elements, String text) =>
      _parseContainer(
        elements,
        text,
        text,
        List<int>.generate(text.length + 1, (i) => i),
        const {},
      );

  static List<DocBlock> _parseContainer(
    XmlElement container,
    String rawText,
    String decodedText,
    List<int> offsetMap,
    Map<String, String> fields,
  ) {
    final blocks = <DocBlock>[];
    for (final el in container.childElements) {
      if (el.name.local == 'paragraph') {
        blocks.addAll(
          _parseParagraph(el, rawText, decodedText, offsetMap, fields),
        );
        for (final image in el.findElements('image')) {
          final block = _parseImageElement(
            image,
            alignment: DocAlignment
                .values[_parseInt(el.getAttribute('Alignment'), 0).clamp(0, 3)],
          );
          if (block != null) blocks.add(block);
        }
      } else if (el.name.local == 'table') {
        final block = _parseTable(el, rawText, decodedText, offsetMap, fields);
        if (block != null) blocks.add(block);
      } else if (el.name.local == 'image') {
        final block = _parseImageElement(el);
        if (block != null) blocks.add(block);
      } else if (['body', 'section'].contains(el.name.local)) {
        blocks.addAll(
          _parseContainer(el, rawText, decodedText, offsetMap, fields),
        );
      }
    }
    return blocks;
  }

  static DocBlock? _parseTable(
    XmlElement tableEl,
    String rawText,
    String decodedText,
    List<int> offsetMap,
    Map<String, String> fields,
  ) {
    final columnSpansAttr = tableEl.getAttribute('columnSpans') ?? '';
    final columnSpans = columnSpansAttr
        .split(',')
        .map((s) => double.tryParse(s.trim()))
        .where((v) => v != null)
        .map((v) => v!)
        .toList();
    final totalSpan = columnSpans.fold<double>(0, (a, b) => a + b);
    final columnWidths = totalSpan > 0 ? columnSpans : null;

    final rows = <DocTableRow>[];
    for (final rowEl in tableEl.childElements.where(
      (e) => e.name.local == 'row',
    )) {
      final isHeader =
          (rowEl.getAttribute('rowType') ?? '').toLowerCase() == 'headerrow';
      final cells = <DocTableCell>[];
      for (final cellEl in rowEl.childElements.where(
        (e) => e.name.local == 'cell',
      )) {
        final cellBlocks = _parseContainer(
          cellEl,
          rawText,
          decodedText,
          offsetMap,
          fields,
        );
        if (cellBlocks.isEmpty) {
          cellBlocks.add(DocBlock(plainText: ''));
        }
        final cellSpan =
            int.tryParse(cellEl.getAttribute('cellSpan') ?? '1') ?? 1;
        // Written the way a run's colour is: Swing's own Background, packed
        // into one signed integer.
        final shade = int.tryParse(cellEl.getAttribute('background') ?? '');
        cells.add(
          DocTableCell(
            blocks: cellBlocks,
            colspan: cellSpan,
            rowspan: _parseInt(cellEl.getAttribute('rowSpan'), 1),
            backgroundColor: shade == null
                ? null
                : '#${(shade & 0xffffff).toRadixString(16).padLeft(6, '0')}',
          ),
        );
      }
      rows.add(DocTableRow(cells: cells, isHeader: isHeader));
    }

    if (rows.isEmpty) return null;
    return DocBlock(
      type: DocBlockType.table,
      plainText: '',
      table: DocTable(
        rows: rows,
        columnWidths: columnWidths,
        bordered:
            (tableEl.getAttribute('border') ?? 'borderCell') != 'borderNone',
      ),
    );
  }

  static DocBlock? _parseImageElement(
    XmlElement imgEl, {
    DocAlignment? alignment,
  }) {
    // UYAP wraps imageData at 76 characters. Dart's base64 decoder rejects the
    // line breaks outright, so every consumer — the preview, the PDF writer,
    // the editor — has to be handed data it can actually decode.
    final base64Data = imgEl
        .getAttribute('imageData')
        ?.replaceAll(RegExp(r'\s'), '');
    if (base64Data == null || base64Data.isEmpty) return null;
    final width = double.tryParse(imgEl.getAttribute('width') ?? '');
    final height = double.tryParse(imgEl.getAttribute('height') ?? '');
    String mime = 'image/png';
    try {
      final head = base64Data.length > 16
          ? base64Data.substring(0, 16)
          : base64Data;
      if (head.startsWith('/9j/')) {
        mime = 'image/jpeg';
      } else if (head.startsWith('SUkq') || head.startsWith('TU0A')) {
        mime = 'image/tiff';
      }
    } catch (_) {}

    return DocBlock(
      type: DocBlockType.image,
      alignment: alignment ?? DocAlignment.left,
      plainText: '',
      imageBase64: base64Data,
      imageMime: mime,
      imageWidth: width,
      imageHeight: height,
    );
  }

  static List<DocBlock> _parseParagraph(
    XmlElement paraEl,
    String rawText,
    String decodedText,
    List<int> offsetMap,
    Map<String, String> fields,
  ) {
    final alignStr = paraEl.getAttribute('Alignment');
    DocAlignment alignment = DocAlignment.left;
    if (alignStr == '1') alignment = DocAlignment.center;
    if (alignStr == '2') alignment = DocAlignment.right;
    if (alignStr == '3') alignment = DocAlignment.justify;

    final tabSet = paraEl.getAttribute('TabSet');
    final lineSpacingStr = paraEl.getAttribute('LineSpacing');
    final rawLineSpacing = double.tryParse(lineSpacingStr ?? '');
    final lineSpacing = rawLineSpacing == null ? null : 1 + rawLineSpacing;

    final isNumbered = paraEl.getAttribute('Numbered') == 'true';
    final isBulleted = paraEl.getAttribute('Bulleted') == 'true';
    final listLevel = _parseInt(paraEl.getAttribute('ListLevel'), 0);
    final listId = _parseInt(paraEl.getAttribute('ListId'), 0);
    final leftIndent = _parseDouble(paraEl.getAttribute('LeftIndent'), 0.0);
    final numberTypeAttr = paraEl.getAttribute('NumberType');
    final bulletTypeAttr = paraEl.getAttribute('BulletType');

    DocListType listType = DocListType.none;
    if (isBulleted) {
      listType = DocListType.unordered;
    } else if (isNumbered) {
      listType = DocListType.ordered;
    }

    final text = StringBuffer();
    final spans = <DocSpan>[];
    for (final child in paraEl.childElements) {
      if (!['content', 'space', 'tab', 'field'].contains(child.name.local)) {
        continue;
      }
      final start = _parseInt(child.getAttribute('startOffset'), -1);
      final length = _parseInt(child.getAttribute('length'), 0);
      if (start < 0 || length < 0 || start + length > rawText.length) {
        throw const FormatException(
          'UDF metin aralığı içerik sınırlarının dışında.',
        );
      }
      var part = decodedText.substring(
        offsetMap[start],
        offsetMap[start + length],
      );
      // A blank still showing its own name, filled in from the template's
      // data. Most fields in the archive already hold their value, split
      // into words by UYAP, and are read as they are.
      if (child.name.local == 'field') {
        final name = child.getAttribute('fieldName');
        final value = fields[name];
        if (value != null && part.trim() == name) {
          // A line break in a value is a new paragraph in UYAP, as though
          // it had been typed.
          part = value.replaceAll('\r\n', '\n').replaceAll('\n', _valueBreak);
        }
      }
      final offset = text.length;
      text.write(part);
      String? color(String key) {
        final value = int.tryParse(child.getAttribute(key) ?? '');
        return value == null
            ? null
            : '#${(value & 0xffffff).toRadixString(16).padLeft(6, '0')}';
      }

      spans.add(
        DocSpan(
          startOffset: offset,
          length: part.length,
          bold: child.getAttribute('bold') == 'true',
          italic: child.getAttribute('italic') == 'true',
          underline: child.getAttribute('underline') == 'true',
          strikethrough: child.getAttribute('strikethrough') == 'true',
          superscript: child.getAttribute('superscript') == 'true',
          subscript: child.getAttribute('subscript') == 'true',
          fontFamily: child.getAttribute('family'),
          fontSize: double.tryParse(child.getAttribute('size') ?? ''),
          color: color('foreground'),
          background: color('background'),
        ),
      );
    }
    if (text.isEmpty && paraEl.findElements('image').isNotEmpty) return [];
    // A paragraph that holds only a picture and its line break is the
    // picture, read on its own below.
    if (text.toString() == '\n' && paraEl.findElements('image').isNotEmpty) {
      return [];
    }
    var value = text.toString();
    // The run that holds the closing line break: its size counts in the
    // paragraph's last row, as UYAP lays the break out with the row.
    final closing = value.endsWith('\n')
        ? spans
              .where((s) => s.startOffset + s.length >= value.length)
              .lastOrNull
        : null;
    // Only the paragraph terminator is structural; internal line breaks count
    // towards UTF-16 offsets and must remain in place.
    if (value.endsWith('\n')) value = value.substring(0, value.length - 1);
    final block = DocBlock(
      type: listType == DocListType.none
          ? DocBlockType.paragraph
          : DocBlockType.listItem,
      alignment: alignment,
      // The style this paragraph resolves to, so a heading written here — or in
      // another editor that names them the same way — comes back as a heading
      // rather than as text that merely looks large.
      styleName:
          paraEl.getAttribute('resolver') ?? paraEl.getAttribute('style'),
      plainText: value,
      spans: [
        for (final s in spans)
          if (s.startOffset < value.length)
            DocSpan(
              startOffset: s.startOffset,
              length: s.length.clamp(0, value.length - s.startOffset),
              bold: s.bold,
              italic: s.italic,
              underline: s.underline,
              strikethrough: s.strikethrough,
              superscript: s.superscript,
              subscript: s.subscript,
              fontFamily: s.fontFamily,
              fontSize: s.fontSize,
              color: s.color,
              background: s.background,
            ),
      ],
      listType: listType,
      listLevel: listLevel,
      listId: listId,
      endFontSize: closing?.fontSize,
      endFontFamily: closing?.fontFamily,
      leftIndent: leftIndent,
      rightIndent: _parseDouble(paraEl.getAttribute('RightIndent'), 0),
      firstLineIndent: _parseDouble(paraEl.getAttribute('FirstLineIndent'), 0),
      hanging: _parseDouble(paraEl.getAttribute('Hanging'), 0),
      spacingBefore: _parseDouble(paraEl.getAttribute('SpaceAbove'), 0),
      spacingAfter: _parseDouble(paraEl.getAttribute('SpaceBelow'), 0),
      tabSet: tabSet,
      lineSpacing: lineSpacing,
      bulletType: bulletTypeAttr,
      numberType: numberTypeAttr,
    );
    return value.contains(_valueBreak) ? _splitAt(block) : [block];
  }

  /// Where a template value broke its line; see [_fieldValues].
  static const _valueBreak = '\u2029';

  /// One paragraph per line a template value put in it, each with the
  /// paragraph's own layout and the runs that fall inside it.
  static List<DocBlock> _splitAt(DocBlock block) {
    final result = <DocBlock>[];
    final text = block.plainText;
    var start = 0;
    while (true) {
      final at = text.indexOf(_valueBreak, start);
      final end = at < 0 ? text.length : at;
      result.add(
        DocBlock(
          type: block.type,
          alignment: block.alignment,
          styleName: block.styleName,
          plainText: text.substring(start, end),
          spans: [
            for (final s in block.spans)
              if (s.endOffset > start && s.startOffset < end)
                DocSpan(
                  startOffset: math.max(s.startOffset, start) - start,
                  length:
                      math.min(s.endOffset, end) -
                      math.max(s.startOffset, start),
                  bold: s.bold,
                  italic: s.italic,
                  underline: s.underline,
                  strikethrough: s.strikethrough,
                  superscript: s.superscript,
                  subscript: s.subscript,
                  fontFamily: s.fontFamily,
                  fontSize: s.fontSize,
                  color: s.color,
                  background: s.background,
                ),
          ],
          listType: block.listType,
          listLevel: block.listLevel,
          listId: block.listId,
          leftIndent: block.leftIndent,
          rightIndent: block.rightIndent,
          firstLineIndent: block.firstLineIndent,
          hanging: block.hanging,
          spacingBefore: block.spacingBefore,
          spacingAfter: block.spacingAfter,
          tabSet: block.tabSet,
          lineSpacing: block.lineSpacing,
          bulletType: block.bulletType,
          numberType: block.numberType,
        ),
      );
      if (at < 0) return result;
      start = at + 1;
    }
  }

  static List<DocBlock> _fallbackParse(String text) {
    final lines = text.split('\n');
    final blocks = <DocBlock>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        blocks.add(DocBlock(plainText: trimmed));
      } else if (blocks.isNotEmpty && blocks.last.plainText.isNotEmpty) {
        blocks.add(DocBlock(plainText: ''));
      }
    }

    if (blocks.isEmpty) blocks.add(DocBlock(plainText: ''));
    return blocks;
  }

  static double _parseDouble(String? s, double defaultValue) {
    if (s == null) return defaultValue;
    return double.tryParse(s) ?? defaultValue;
  }

  static int _parseInt(String? s, int defaultValue) {
    if (s == null) return defaultValue;
    return int.tryParse(s) ?? defaultValue;
  }
}

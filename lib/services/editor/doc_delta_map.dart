import 'dart:math' as math;

import 'package:flutter_quill/quill_delta.dart';

import '../../models/document_model.dart';

/// DocModel ↔ Quill Delta dönüştürücü.
/// Zengin metin düzenleme ve UDF/DOCX arasında biçimlendirme kaybını önler.
class DocDeltaMap {
  static const kKorunanAttr = 'korunan-blok';

  /// What a line break inside a UDF paragraph is in the editor: a zero-width
  /// space, drawn as nothing, as UYAP draws the break.
  static const innerBreakUdf = '\u200b';

  /// What a Word line break is in the editor: a line separator, which starts
  /// a new row without ending the paragraph.
  static const innerBreakWord = '\u2028';

  /// Tables. The embed carries only an index into the list the mapper keeps
  /// aside, the way the placeholder did: a table is far more than Quill knows
  /// how to store, and reading it back from a delta would lose its borders,
  /// its column widths and any table nested inside it.
  static const kTableEmbed = 'doc-table';

  /// Quill's own embed type for a picture. Named here so the mapper stays free
  /// of the widget layer; [EditorImageEmbed] asserts it matches Quill's.
  static const kImageEmbed = 'image';

  /// Carries a picture's printed size on the line that holds it. The embed
  /// itself is only the bytes, and a size measured in points is what UDF, DOCX
  /// and PDF each need back.
  static const kImageAttr = 'doc-image';

  /// A picture as the editor carries it: self-contained, so nothing is read
  /// from disk while typing and a copied document keeps its images.
  static String imageUri(String base64Data, String? mime) =>
      'data:${mime ?? 'image/png'};base64,$base64Data';

  /// Heading levels the editor offers, mapped to the names written into the
  /// document. Quill's own `header` attribute carries them, so the editor draws
  /// headings without a custom renderer; the name is what survives a save.
  static const headingNames = {1: 'Başlık 1', 2: 'Başlık 2', 3: 'Başlık 3'};

  /// Point sizes and weight a heading is drawn and exported at. Word's defaults
  /// for Heading 1-3 relative to a 12 pt body, so a document opened elsewhere
  /// looks like the one that was written here.
  static const headingSizes = {1: 16.0, 2: 14.0, 3: 12.0};

  static int? headingLevelOf(String? styleName) {
    if (styleName == null) return null;
    for (final entry in headingNames.entries) {
      if (entry.value == styleName) return entry.key;
    }
    // Documents written elsewhere name these differently; match the number.
    final match = RegExp(
      r'(?:başlık|heading|h)\s*([123])',
      caseSensitive: false,
    ).firstMatch(styleName);
    return match == null ? null : int.parse(match.group(1)!);
  }

  /// DocModel → (Delta, korunanlar).
  static ({Delta delta, List<DocBlock> korunanlar}) modeldenDelta(
    DocModel model,
  ) {
    final delta = Delta();
    final korunanlar = <DocBlock>[];
    // A line break inside a paragraph cannot reach Quill as '\n', which ends
    // the line there and leaves the text before it without the paragraph's
    // indents, stops and alignment. UYAP draws such a break as nothing at all
    // (see ParagraphRows), so a UDF's goes to the editor as a zero-width
    // space; a Word document's is a line separator, which breaks the row
    // inside the paragraph as Word does. Both are '\n' again on the way back.
    // Anything else — a paste, a text file — keeps its breaks as lines.
    final innerBreak = model.metadata['formatId'] != null
        ? innerBreakUdf
        : model.metadata['tabRules'] == 'word'
        ? innerBreakWord
        : null;

    for (final b in model.blocks) {
      // A picture is drawn where it sits rather than standing in as a label:
      // the bytes were always carried through a save, but the writer could not
      // see what they were writing around.
      if (b.type == DocBlockType.image && b.imageBase64 != null) {
        delta.insert({kImageEmbed: imageUri(b.imageBase64!, b.imageMime)});
        final imageAttrs = <String, dynamic>{
          kImageAttr: {'w': b.imageWidth, 'h': b.imageHeight},
        };
        final hiza = _alignName(b.alignment);
        if (hiza != null) imageAttrs['align'] = hiza;
        delta.insert('\n', imageAttrs);
        continue;
      }
      if (b.type == DocBlockType.table || b.type == DocBlockType.image) {
        final idx = korunanlar.length;
        korunanlar.add(b);
        delta.insert({kTableEmbed: idx});
        final tableAttrs = <String, dynamic>{};
        final hizala = _alignName(b.alignment);
        if (hizala != null) tableAttrs['align'] = hizala;
        delta.insert('\n', tableAttrs.isEmpty ? null : tableAttrs);
        continue;
      }

      final text = b.plainText;
      final sinirlar = <int>{0, text.length};
      for (final s in b.spans) {
        sinirlar.add(s.startOffset.clamp(0, text.length));
        sinirlar.add((s.startOffset + s.length).clamp(0, text.length));
      }
      final sirali = sinirlar.toList()..sort();

      for (var i = 0; i + 1 < sirali.length; i++) {
        final bas = sirali[i];
        final son = sirali[i + 1];
        if (son <= bas) continue;
        var parca = text.substring(bas, son);
        if (innerBreak != null) parca = parca.replaceAll('\n', innerBreak);
        final baseStyle =
            model.styles
                .where((s) => s.name == model.metadata['resolver'])
                .firstOrNull ??
            model.styles.where((s) => s.name == 'hvl-default').firstOrNull;
        final attrs = <String, dynamic>{
          'font': baseStyle?.family ?? 'Times New Roman',
          'size': _puntoStr(baseStyle?.size ?? 12),
        };
        for (final s in b.spans) {
          if (s.startOffset <= bas && s.startOffset + s.length >= son) {
            if (s.bold) attrs['bold'] = true;
            if (s.italic) attrs['italic'] = true;
            if (s.underline) attrs['underline'] = true;
            if (s.strikethrough) attrs['strike'] = true;
            if (s.fontFamily != null) attrs['font'] = s.fontFamily;
            if (s.fontSize != null) {
              attrs['size'] = _puntoStr(s.fontSize!);
            }
            if (s.color != null) attrs['color'] = s.color;
            if (s.background != null) attrs['background'] = s.background;
            if (s.superscript) attrs['script'] = 'super';
            if (s.subscript) attrs['script'] = 'sub';
          }
        }
        delta.insert(parca, attrs.isEmpty ? null : attrs);
      }

      final blokAttrs = <String, dynamic>{
        'doc-layout': {
          'left': b.leftIndent,
          'editorIndent': b.listType == DocListType.none
              ? (b.leftIndent / 36).floor().clamp(0, 8)
              : b.listLevel,
          'right': b.rightIndent,
          'first': b.firstLineIndent,
          'hanging': b.hanging,
          'before': b.spacingBefore,
          'after': b.spacingAfter,
          'line': b.lineSpacing,
          'tabs': b.tabSet,
          // A Word document's tabs follow Word's rules and its own default
          // stop; the line carries that, since the line is what is drawn.
          if (model.metadata['tabRules'] == 'word') ...{
            'rules': 'word',
            'interval': model.metadata['defaultTabStop'],
          },
          'listId': b.listId,
          'bullet': b.bulletType,
          'number': b.numberType,
          // The closing line break's size and font: an empty line's row.
          'endSize': ?b.endFontSize,
          'endFamily': ?b.endFontFamily,
        },
      };
      final hiza = _alignName(b.alignment);
      if (hiza != null) blokAttrs['align'] = hiza;
      if (b.listType == DocListType.ordered) blokAttrs['list'] = 'ordered';
      if (b.listType == DocListType.unordered) blokAttrs['list'] = 'bullet';
      final editorIndent = b.listType == DocListType.none
          ? (b.leftIndent / 36).floor().clamp(0, 8)
          : b.listLevel;
      if (editorIndent > 0) blokAttrs['indent'] = editorIndent;
      if (b.lineSpacing != null) blokAttrs['line-height'] = b.lineSpacing;
      final heading = headingLevelOf(b.styleName);
      if (heading != null) blokAttrs['header'] = heading;

      delta.insert('\n', blokAttrs.isEmpty ? null : blokAttrs);
    }

    if (delta.isEmpty) delta.insert('\n');
    return (delta: delta, korunanlar: korunanlar);
  }

  /// Delta → DocModel.
  static DocModel deltadanModel(
    Delta delta, {
    List<DocBlock> korunanlar = const [],
    DocPageProperties sayfa = const DocPageProperties(),
    Map<String, dynamic> metadata = const {'formatId': '1.8'},
    List<DocStyleDef> styles = const [],
    Map<String, List<DocBlock>> pageRegions = const {},
  }) {
    final blocks = <DocBlock>[];
    var buffer = StringBuffer();
    var spans = <DocSpan>[];

    void spanEkle(String parca, Map<String, dynamic>? a) {
      if (parca.isEmpty) return;
      final bas = buffer.length;
      buffer.write(
        parca.replaceAll(innerBreakUdf, '\n').replaceAll(innerBreakWord, '\n'),
      );
      if (a == null || a.isEmpty) return;
      final bold = a['bold'] == true;
      final italic = a['italic'] == true;
      final underline = a['underline'] == true;
      final strike = a['strike'] == true;
      final font = a['font'] as String?;
      final size = _puntoDouble(a['size']);
      final color = a['color'] as String?;
      final background = a['background'] as String?;
      final script = a['script'];
      if (!bold &&
          !italic &&
          !underline &&
          !strike &&
          font == null &&
          size == null &&
          color == null &&
          background == null &&
          script == null) {
        return;
      }
      spans.add(
        DocSpan(
          startOffset: bas,
          length: parca.length,
          bold: bold,
          italic: italic,
          underline: underline,
          strikethrough: strike,
          fontFamily: font,
          fontSize: size,
          color: color,
          background: background,
          superscript: script == 'super',
          subscript: script == 'sub',
        ),
      );
    }

    String? bekleyenGorsel;

    // A list made in the editor names no list of its own. UYAP numbers an
    // item among its list's (ListId), so each run of such items is given a
    // list of its own, above any the document already has; without one,
    // every list in the document would count on from the one before.
    var nextListId = 0;
    for (final op in delta.toList()) {
      final layout = op.attributes?['doc-layout'];
      final id = layout is Map ? layout['listId'] : null;
      if (id is int && id > nextListId) nextListId = id;
    }
    var madeListId = 0;
    DocBlock? bekleyenKorunan;

    void paragrafEkle(Map<String, dynamic>? a) {
      final hiza = _alignOf(a?['align']);
      var liste = DocListType.none;
      if (a?['list'] == 'ordered') liste = DocListType.ordered;
      if (a?['list'] == 'bullet') liste = DocListType.unordered;
      final indent = a?['indent'];
      final header = a?['header'];
      final layout = a?['doc-layout'] as Map? ?? const {};
      double value(String key) => (layout[key] as num?)?.toDouble() ?? 0;

      blocks.add(
        DocBlock(
          plainText: buffer.toString(),
          spans: spans,
          styleName: header is int ? headingNames[header] : null,
          alignment: hiza,
          listType: liste,
          // UYAP's first level is 1.
          listLevel: liste == DocListType.none
              ? (indent is int ? indent : 0)
              : math.max(1, indent is int ? indent : 0),
          type: liste == DocListType.none
              ? DocBlockType.paragraph
              : DocBlockType.listItem,
          leftIndent: liste == DocListType.none
              ? (value('left') +
                        ((indent is int ? indent : 0) - value('editorIndent')) *
                            36)
                    .clamp(0, 1000)
              // A list item steps in 25 points a level, as UYAP sets its
              // lists; one made in the editor starts at the first level's.
              : layout.containsKey('left')
              ? (value('left') +
                        ((indent is int ? indent : 0) - value('editorIndent')) *
                            25)
                    .clamp(0, 1000)
              : 25.0 * math.max(1, indent is int ? indent : 0),
          rightIndent: value('right'),
          firstLineIndent: value('first'),
          hanging: value('hanging'),
          spacingBefore: value('before'),
          spacingAfter: value('after'),
          lineSpacing:
              (a?['line-height'] as num?)?.toDouble() ??
              (layout['line'] as num?)?.toDouble(),
          tabSet: layout['tabs'] as String?,
          listId: liste == DocListType.none
              ? layout['listId'] as int? ?? 0
              : switch (layout['listId']) {
                  final int id when id != 0 => id,
                  _ =>
                    blocks.isNotEmpty &&
                            blocks.last.listType != DocListType.none &&
                            blocks.last.listId == madeListId &&
                            madeListId != 0
                        ? madeListId
                        : (madeListId = ++nextListId),
                },
          // UYAP's own kinds, which it writes on every list item: a list
          // made here is numbered "1." or bulleted with a dot.
          bulletType:
              layout['bullet'] as String? ??
              (liste == DocListType.unordered ? 'BULLET_TYPE_ELLIPSE' : null),
          numberType:
              layout['number'] as String? ??
              (liste == DocListType.ordered ? 'NUMBER_TYPE_NUMBER_DOT' : null),
          endFontSize: (layout['endSize'] as num?)?.toDouble(),
          endFontFamily: layout['endFamily'] as String?,
        ),
      );
      buffer = StringBuffer();
      spans = <DocSpan>[];
    }

    void blokKapat(Map<String, dynamic>? a) {
      final korunan = bekleyenKorunan;
      bekleyenKorunan = null;
      if (korunan != null) {
        if (buffer.isNotEmpty) paragrafEkle(a);
        blocks.add(korunan);
        buffer = StringBuffer();
        spans = <DocSpan>[];
        return;
      }
      final gorsel = bekleyenGorsel;
      bekleyenGorsel = null;
      if (gorsel != null) {
        // Text typed on the same line as a picture becomes the paragraph
        // before it: UDF and DOCX both give an image a paragraph of its own.
        if (buffer.isNotEmpty) paragrafEkle(a);
        blocks.add(_imageBlock(gorsel, a));
        buffer = StringBuffer();
        spans = <DocSpan>[];
        return;
      }
      final korunanIdx = a?[kKorunanAttr];
      if (korunanIdx is int &&
          korunanIdx >= 0 &&
          korunanIdx < korunanlar.length) {
        blocks.add(korunanlar[korunanIdx]);
        buffer = StringBuffer();
        spans = <DocSpan>[];
        return;
      }
      paragrafEkle(a);
    }

    for (final op in delta.toList()) {
      final veri = op.data;
      // An embed: the only one the editor writes is a picture, and it closes
      // with the newline that follows it, which carries the size and alignment.
      if (veri is Map) {
        final data = veri[kImageEmbed];
        if (data is String) bekleyenGorsel = data;
        final table = veri[kTableEmbed];
        if (table is int && table >= 0 && table < korunanlar.length) {
          bekleyenKorunan = korunanlar[table];
        }
        continue;
      }
      if (veri is! String) continue;
      var kalan = veri;
      while (true) {
        final ni = kalan.indexOf('\n');
        if (ni < 0) {
          spanEkle(kalan, op.attributes);
          break;
        }
        spanEkle(kalan.substring(0, ni), op.attributes);
        blokKapat(op.attributes);
        kalan = kalan.substring(ni + 1);
      }
    }
    if (buffer.isNotEmpty ||
        bekleyenGorsel != null ||
        bekleyenKorunan != null) {
      blokKapat(null);
    }

    if (blocks.isEmpty) blocks.add(DocBlock(plainText: ''));
    return DocModel(
      blocks: blocks,
      pageProperties: sayfa,
      metadata: metadata,
      styles: styles,
      pageRegions: pageRegions,
    );
  }

  static String? _alignName(DocAlignment alignment) => switch (alignment) {
    DocAlignment.center => 'center',
    DocAlignment.right => 'right',
    DocAlignment.justify => 'justify',
    DocAlignment.left => null,
  };

  static DocAlignment _alignOf(Object? name) => switch (name) {
    'center' => DocAlignment.center,
    'right' => DocAlignment.right,
    'justify' => DocAlignment.justify,
    _ => DocAlignment.left,
  };

  /// Rebuilds an image block from what the editor carries: the bytes from the
  /// embed, the printed size and alignment from the line holding it.
  static DocBlock _imageBlock(String uri, Map<String, dynamic>? a) {
    final olcu = a?[kImageAttr] as Map? ?? const {};
    final comma = uri.indexOf(',');
    final header = comma < 0 ? '' : uri.substring(0, comma);
    final mime = RegExp(r'^data:([^;,]+)').firstMatch(header)?.group(1);
    return DocBlock(
      type: DocBlockType.image,
      plainText: '',
      alignment: _alignOf(a?['align']),
      imageBase64: comma < 0 ? uri : uri.substring(comma + 1),
      imageMime: mime == null || mime.isEmpty ? 'image/png' : mime,
      imageWidth: (olcu['w'] as num?)?.toDouble(),
      imageHeight: (olcu['h'] as num?)?.toDouble(),
    );
  }

  static const double _ptToPx = 96.0 / 72.0;

  static String _puntoStr(double punto) => (punto * _ptToPx).toString();

  static double? _puntoDouble(Object? v) {
    if (v == null) return null;
    final px = v is num ? v.toDouble() : double.tryParse(v.toString());
    if (px == null) return null;
    // To a thousandth of a point: 14 pt is 18.666… px in the editor, and
    // dividing back gives 13.999999999999998, which is not what was set.
    return (px / _ptToPx * 1000).round() / 1000;
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../../models/document_model.dart';
import '../editor/doc_delta_map.dart';
import '../editor/doc_model_json.dart';
import 'docx_bridge.dart';

/// A Word file saved without losing what the editor cannot show.
///
/// Folio writes a Word file anew from what the editor holds, and whatever
/// the editor has no place for was gone after the first save: a paragraph's
/// style by its name, a comment, a tracked change, a footnote, a drawn
/// line, Word's own settings. Here the file the document was opened from is
/// read again as it is saved, each paragraph the editor gives back is held
/// against the one it was read as, and every paragraph and table not
/// touched is written with the very bytes it had; only what was changed is
/// written anew, in its own paragraph's properties where it has them. The
/// rest of the package (styles, numbering, comments, notes, pictures,
/// headers and footers) is copied as it is.
///
/// Whenever that cannot be done safely (a list or a picture put in, the
/// page or its header changed, a file whose paragraphs cannot be told
/// apart) null is given, and the file is written anew as before. Measured
/// on 551 real documents: a paragraph taken through the editor once comes
/// back the same every time after (29.687 of 29.687), which is what lets a
/// touched one be told from an untouched one.
abstract final class DocxSplice {
  /// [model] written into [original]'s package; null when it has to be
  /// written anew.
  static Future<Uint8List?> save(Uint8List original, DocModel model) async {
    try {
      final read = await DocxBridge.readBytes(original);
      if (read == null) return null;
      final origin = DocxOrigin.of(original, read);
      if (origin == null) return null;
      // The page, its header and footer are in parts of their own, written
      // only by the full writer.
      if (_pagePrint(model) != _pagePrint(read)) return null;
      final body = await _body(origin, model);
      if (body == null) return null;
      // What is written is read back and held against what was to be
      // written: a file that does not say the same is not kept. Read
      // without its pictures, which say nothing and take the longest.
      final back = await DocxBridge.readBytes(
        origin.repack(body, pictures: false),
      );
      if (back == null || _letters(back.blocks) != _letters(model.blocks)) {
        return null;
      }
      return origin.repack(body);
    } catch (e) {
      debugPrint('DocxSplice.save: $e');
      return null;
    }
  }

  /// A block as the editor gives it back, to tell a touched one by.
  static String print(DocBlock block) => jsonEncode(
    (DocModelJson.encode(DocModel(blocks: [block]))['blocks'] as List).single,
  );

  /// [model] taken through the editor's own document and back: what it
  /// gives back for a document nothing was done to.
  static DocModel throughEditor(DocModel model) {
    final quill = DocDeltaMap.modeldenDelta(model);
    return DocDeltaMap.deltadanModel(
      quill.delta,
      korunanlar: quill.korunanlar,
      sayfa: model.pageProperties,
      metadata: model.metadata,
      styles: model.styles,
      pageRegions: model.pageRegions,
    );
  }

  static String _pagePrint(DocModel model) {
    final p = model.pageProperties;
    return jsonEncode([
      p.marginLeft.round(),
      p.marginRight.round(),
      p.marginTop.round(),
      p.marginBottom.round(),
      p.landscape,
      p.paperWidth.round(),
      p.paperHeight.round(),
      p.headerOffset.round(),
      p.footerOffset.round(),
      for (final key in model.pageRegions.keys.toList()..sort()) ...[
        key,
        for (final block in model.pageRegions[key]!) print(block),
      ],
      // None and an empty one are the same: the editor gives an empty one.
      switch (model.metadata['pageRegionAttrs']) {
        final Map attrs when attrs.isNotEmpty => jsonEncode(attrs),
        _ => '',
      },
    ]);
  }

  static String _letters(List<DocBlock> blocks) {
    final out = StringBuffer();
    void take(List<DocBlock> list) {
      for (final block in list) {
        out.write(block.plainText.replaceAll(_space, ''));
        for (final row in block.table?.rows ?? const <DocTableRow>[]) {
          for (final cell in row.cells) {
            take(cell.blocks);
          }
        }
      }
    }

    take(blocks);
    return out.toString();
  }

  static final _space = RegExp(r'\s+');

  /// What only a paragraph has of its own, apart from its text: when these
  /// are as they were, a paragraph whose words changed keeps its own
  /// properties (its style, its numbering, its tabs) as Word wrote them.
  static String _shape(DocBlock b) => jsonEncode([
    b.type.name,
    b.alignment.name,
    b.listType.name,
    b.listLevel,
    b.leftIndent,
    b.rightIndent,
    b.firstLineIndent,
    b.hanging,
    b.spacingBefore,
    b.spacingAfter,
    b.lineSpacing,
    b.tabSet,
    b.styleName,
    b.pageBreakBefore,
  ]);

  /// The body as it is written: untouched units as they were, the rest
  /// anew. Null when a block cannot be written here.
  static Future<String?> _body(DocxOrigin origin, DocModel model) async {
    final saved = [for (final block in model.blocks) print(block)];
    final match = _match(origin.prints, saved);
    // For each saved block, the original block it is, or -1.
    final from = List.filled(saved.length, -1);
    for (final (o, s) in match.indexed) {
      if (s >= 0) from[s] = o;
    }
    final out = StringBuffer();
    final anew = <int>[]; // saved blocks written by the full writer
    final plan = <Object>[]; // String (as it was) or _Anew
    var written = 0; // units written so far, passive ones with them
    void passive(int until) {
      for (; written < until; written++) {
        final unit = origin.units[written];
        if (unit.blocks == 0) plan.add(unit.xml);
      }
    }

    var s = 0;
    while (s < saved.length) {
      final o = from[s];
      final unit = o < 0 ? null : origin.unitOf[o];
      // A unit all of whose blocks follow one another as they were.
      if (unit != null && origin.units[unit].first == o) {
        final u = origin.units[unit];
        var whole = s + u.blocks <= saved.length;
        for (var k = 0; whole && k < u.blocks; k++) {
          whole = from[s + k] == o + k;
        }
        if (whole && unit >= written) {
          passive(unit);
          plan.add(u.xml);
          written = unit + 1;
          s += u.blocks;
          continue;
        }
      }
      // Touched, or new. Its own unit, when it is the next one not yet
      // written and holds this one block: a paragraph whose words changed.
      final block = model.blocks[s];
      if (block.type == DocBlockType.table ||
          block.type == DocBlockType.image ||
          block.spans.any((span) => span.link != null)) {
        return null;
      }
      int? own;
      for (var u = written; u < origin.units.length; u++) {
        final unit = origin.units[u];
        if (unit.blocks == 0) continue;
        // The next unit with blocks, if none of them was kept.
        final kept = [
          for (var k = 0; k < unit.blocks; k++) match[unit.first + k],
        ].any((m) => m >= 0);
        if (!kept &&
            unit.blocks == 1 &&
            unit.paragraph &&
            _shape(origin.blocks[unit.first]) == _shape(block)) {
          own = u;
        }
        break;
      }
      if (own == null && block.listType != DocListType.none) return null;
      if (own != null) passive(own);
      plan.add(_Anew(anew.length, own));
      anew.add(s);
      if (own != null) written = own + 1;
      s++;
    }
    // Units left: dropped by the lawyer, but for what has no block.
    for (; written < origin.units.length; written++) {
      final unit = origin.units[written];
      if (unit.blocks == 0) {
        plan.add(unit.xml);
      } else if (unit.xml.contains('<w:sectPr')) {
        // A section ends in it: its page and columns go with it.
        return null;
      }
    }

    var fresh = const <String>[];
    if (anew.isNotEmpty) {
      final bytes = await DocxBridge.writeBytes(
        DocModel(
          blocks: [for (final i in anew) model.blocks[i]],
          metadata: model.metadata,
          pageProperties: model.pageProperties,
        ),
      );
      final written = DocxOrigin.scan(
        utf8.decode(
          ZipDecoder().decodeBytes(bytes).findFile('word/document.xml')!.content
              as List<int>,
        ),
      );
      if (written == null) return null;
      fresh = [
        for (final unit in written.units)
          if (unit.paragraph) unit.xml,
      ];
      if (fresh.length != anew.length) return null;
    }
    for (final piece in plan) {
      if (piece is String) {
        out.write(piece);
        continue;
      }
      final one = piece as _Anew;
      final xml = fresh[one.index];
      if (one.own == null) {
        out.write(xml);
        continue;
      }
      // The paragraph's own opening and properties, the new runs in them.
      final was = origin.units[one.own!].xml;
      final head = _paragraphHead(was);
      final runs = _paragraphRuns(xml);
      if (head == null || runs == null) return null;
      out
        ..write(head)
        ..write(runs)
        ..write('</w:p>');
    }
    return out.toString();
  }

  /// `<w:p …>` and its `<w:pPr>…</w:pPr>`, as they are.
  static String? _paragraphHead(String xml) {
    final open = _open.matchAsPrefix(xml);
    if (open == null || open.group(0)!.endsWith('/>')) return null;
    var end = open.end;
    if (xml.startsWith('<w:pPr>', end)) {
      final close = xml.indexOf('</w:pPr>', end);
      if (close < 0) return null;
      end = close + '</w:pPr>'.length;
    } else if (xml.startsWith('<w:pPr/>', end)) {
      end += '<w:pPr/>'.length;
    }
    return xml.substring(0, end);
  }

  /// What a paragraph written anew holds after its properties.
  static String? _paragraphRuns(String xml) {
    final head = _paragraphHead(xml);
    if (head == null || !xml.endsWith('</w:p>')) return null;
    return xml.substring(head.length, xml.length - '</w:p>'.length);
  }

  static final _open = RegExp(r'<w:p(?: [^>]*)?>');

  /// For each of [was], the index in [now] of the same print, in order
  /// (the longest run of them), or -1.
  static List<int> _match(List<String> was, List<String> now) {
    final out = List.filled(was.length, -1);
    // The same at both ends first: the common case, and what keeps the
    // table below small in a long document.
    var head = 0;
    while (head < was.length && head < now.length && was[head] == now[head]) {
      out[head] = head;
      head++;
    }
    var a = was.length, b = now.length;
    while (a > head && b > head && was[a - 1] == now[b - 1]) {
      a--;
      b--;
      out[a] = b;
    }
    final n = a - head, m = b - head;
    if (n == 0 || m == 0) return out;
    if (n * m > 4000000) return out;
    final table = List.generate(n + 1, (_) => Uint16List(m + 1));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        table[i][j] = was[head + i] == now[head + j]
            ? table[i + 1][j + 1] + 1
            : (table[i + 1][j] >= table[i][j + 1]
                  ? table[i + 1][j]
                  : table[i][j + 1]);
      }
    }
    var i = 0, j = 0;
    while (i < n && j < m) {
      if (was[head + i] == now[head + j]) {
        out[head + i] = head + j;
        i++;
        j++;
      } else if (table[i + 1][j] >= table[i][j + 1]) {
        i++;
      } else {
        j++;
      }
    }
    return out;
  }
}

class _Anew {
  const _Anew(this.index, this.own);

  /// Which of the blocks written anew, and the unit whose properties it
  /// keeps, if it is that unit's paragraph with other words.
  final int index;
  final int? own;
}

/// One thing of a Word file's body, as it is written there: a paragraph, a
/// table, or something the editor has nothing for (a bookmark's end, a
/// section's break on its own).
class DocxUnit {
  DocxUnit(this.xml, {required this.paragraph, required this.table});

  final String xml;
  final bool paragraph, table;

  /// The first of the blocks read from it, and how many: none for what
  /// the editor has nothing for.
  int first = 0, blocks = 0;
}

/// A Word file as it was opened: its body taken apart into units, each
/// with the blocks read from it and those blocks' prints.
class DocxOrigin {
  DocxOrigin._(this._archive, this.head, this.units, this.tail);

  final Archive _archive;
  bool _marked = false;

  /// The document part before the body's first unit, and after its last
  /// (the last section's properties and the closing tags).
  final String head, tail;
  final List<DocxUnit> units;

  /// The blocks read, as the editor gives them back, their prints, and for
  /// each the unit it was read from.
  late final List<DocBlock> blocks;
  late final List<String> prints;
  late final List<int> unitOf;

  /// [bytes] taken apart, with [read] (what was read from them) laid
  /// against its units; null when the two cannot be laid together.
  static DocxOrigin? of(Uint8List bytes, DocModel read) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final part = archive.findFile('word/document.xml');
    if (part == null) return null;
    final content = part.content as List<int>;
    final scanned = scan(utf8.decode(content));
    if (scanned == null) return null;
    final origin = DocxOrigin._(
      archive,
      scanned.head,
      scanned.units,
      scanned.tail,
    );
    // The mark some programs begin the part with is read away with the
    // text; written back, the part is what it was to the byte.
    origin._marked =
        content.length > 2 &&
        content[0] == 0xEF &&
        content[1] == 0xBB &&
        content[2] == 0xBF;
    final through = DocxSplice.throughEditor(read);
    if (through.blocks.length != read.blocks.length) return null;
    if (!origin._lay(read.blocks)) return null;
    origin.blocks = through.blocks;
    origin.prints = [for (final b in through.blocks) DocxSplice.print(b)];
    return origin;
  }

  /// The body's units in [xml], what is before them and after.
  static ({String head, List<DocxUnit> units, String tail})? scan(String xml) {
    final body = xml.indexOf('<w:body>');
    final end = xml.lastIndexOf('</w:body>');
    if (body < 0 || end < 0) return null;
    final start = body + '<w:body>'.length;
    final units = <DocxUnit>[];
    var at = start, tailFrom = end;
    while (at < end) {
      final close = _elementEnd(xml, at, end);
      if (close == null) return null;
      final name = _name(xml, at);
      if (name == 'w:sectPr') {
        tailFrom = at;
        break;
      }
      units.add(
        DocxUnit(
          xml.substring(at, close),
          paragraph: name == 'w:p',
          table: name == 'w:tbl',
        ),
      );
      at = close;
    }
    return (
      head: xml.substring(0, start),
      units: units,
      tail: xml.substring(tailFrom),
    );
  }

  static String _name(String xml, int at) {
    var i = at + 1;
    while (i < xml.length) {
      final c = xml.codeUnitAt(i);
      if (c == 0x20 || c == 0x3E || c == 0x2F || c == 0x0A || c == 0x09) break;
      i++;
    }
    return xml.substring(at + 1, i);
  }

  /// Where the element starting at [at] ends, by counting what opens and
  /// what closes; null when [xml] is not what it should be there.
  static int? _elementEnd(String xml, int at, int limit) {
    if (xml.codeUnitAt(at) != 0x3C) return null;
    var depth = 0, i = at;
    while (i < limit) {
      final open = xml.indexOf('<', i);
      if (open < 0 || open >= limit) return null;
      final close = _tagEnd(xml, open);
      if (close < 0) return null;
      final second = xml.codeUnitAt(open + 1);
      if (second == 0x2F) {
        depth--;
      } else if (second == 0x21 || second == 0x3F) {
        // A comment or an instruction: neither opens nor closes.
      } else if (xml.codeUnitAt(close - 1) != 0x2F) {
        depth++;
      }
      i = close + 1;
      if (depth == 0) return i;
      if (depth < 0) return null;
    }
    return null;
  }

  /// The `>` that ends the tag opened at [open], past any quoted value.
  static int _tagEnd(String xml, int open) {
    var quote = 0;
    for (var i = open + 1; i < xml.length; i++) {
      final c = xml.codeUnitAt(i);
      if (quote != 0) {
        if (c == quote) quote = 0;
      } else if (c == 0x22 || c == 0x27) {
        quote = c;
      } else if (c == 0x3E) {
        return i;
      }
    }
    return -1;
  }

  /// Lays [read] against the units by what each says; false when they do
  /// not go together block for block.
  bool _lay(List<DocBlock> read) {
    unitOf = List.filled(read.length, -1);
    var at = 0;
    for (final (u, unit) in units.indexed) {
      unit.first = at;
      if (!unit.paragraph && !unit.table) {
        // A content control holds paragraphs of its own, taken out of it
        // as it is read; anything else has no block.
        if (!unit.xml.startsWith('<w:sdt>')) continue;
      }
      final wanted = lettersOf(unit.xml);
      final pictures = _pictures.allMatches(unit.xml).length;
      if (unit.table) {
        if (at >= read.length || read[at].type != DocBlockType.table) {
          return false;
        }
        if (_lettersOfBlocks([read[at]]) != wanted) return false;
        unitOf[at++] = u;
        unit.blocks = 1;
        continue;
      }
      var said = '';
      // Its paragraphs (its own, a text box's after it, a control's), until
      // what they say is what it says; then the pictures it holds. One
      // that says nothing takes one empty paragraph, if one was read of it.
      var took = 0;
      final most = _paragraphs.allMatches(unit.xml).length;
      while (at < read.length &&
          took < most &&
          read[at].type != DocBlockType.table &&
          read[at].type != DocBlockType.image) {
        if (took > 0 && said == wanted) break;
        final next = said + _lettersOfBlocks([read[at]]);
        if (!wanted.startsWith(next)) break;
        said = next;
        unitOf[at++] = u;
        took++;
      }
      if (said != wanted) return false;
      for (
        var k = 0;
        k < pictures && at < read.length && read[at].type == DocBlockType.image;
        k++
      ) {
        unitOf[at++] = u;
        took++;
      }
      unit.blocks = took;
    }
    return at == read.length;
  }

  static final _pictures = RegExp(r'<a:blip |<v:imagedata ');
  static final _paragraphs = RegExp(r'<w:p[ >]');

  /// What a unit says, as the reader reads it: its letters with no space
  /// between them.
  @visibleForTesting
  static String lettersOf(String unit) {
    final ready = utf8.decode(
      DocxBridge.splitMixedRuns(
        DocxBridge.textBoxesAsParagraphs(
          DocxBridge.openContentControls(utf8.encode(unit)),
        ),
      ),
    );
    final out = StringBuffer();
    for (final m in _text.allMatches(ready)) {
      out.write(m.group(1));
    }
    return out
        .toString()
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll(_space, '');
  }

  static String _lettersOfBlocks(List<DocBlock> blocks) {
    final out = StringBuffer();
    void take(List<DocBlock> list) {
      for (final block in list) {
        out.write(block.plainText.replaceAll(_space, ''));
        for (final row in block.table?.rows ?? const <DocTableRow>[]) {
          for (final cell in row.cells) {
            take(cell.blocks);
          }
        }
      }
    }

    take(blocks);
    return out.toString();
  }

  static final _text = RegExp(r'<w:t(?: [^>]*)?>([^<]*)</w:t>');
  static final _space = RegExp(r'\s+');

  /// The package with [body] as the document's body, every other part as
  /// it was.
  Uint8List repack(String body, {bool pictures = true}) {
    final out = Archive();
    for (final file in _archive) {
      if (!file.isFile) continue;
      if (!pictures && file.name.startsWith('word/media/')) continue;
      if (file.name == 'word/document.xml') {
        final content = [
          if (_marked) ...const [0xEF, 0xBB, 0xBF],
          ...utf8.encode('$head$body$tail'),
        ];
        out.addFile(ArchiveFile(file.name, content.length, content));
      } else {
        // As it is in the file, still compressed: a picture of megabytes
        // is not opened and pressed again at every save.
        out.addFile(file);
      }
    }
    return Uint8List.fromList(ZipEncoder().encode(out));
  }
}

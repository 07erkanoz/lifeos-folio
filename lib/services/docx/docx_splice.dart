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
      final plan = _plan(origin, model);
      final sheet = _sheetPrint(model) != _sheetPrint(read);
      final regions = [
        for (final kind in const ['header', 'footer'])
          if (_regionPrint(model, kind) != _regionPrint(read, kind)) kind,
      ];
      final package = _Package(origin._archive);
      var head = origin.head, tail = origin.tail;
      var fresh = const <String>[];
      _Import? import;
      if (plan.anew.isNotEmpty || sheet || regions.isNotEmpty) {
        // What is new or changed, written by the full writer into a
        // package of its own, and taken from there with all it needs.
        final written = ZipDecoder().decodeBytes(
          await DocxBridge.writeBytes(
            DocModel(
              blocks: plan.anew.isEmpty
                  ? [DocBlock(plainText: '')]
                  : [for (final i in plan.anew) model.blocks[i]],
              metadata: model.metadata,
              pageProperties: model.pageProperties,
              pageRegions: model.pageRegions,
              styles: model.styles,
            ),
          ),
        );
        final part = written.findFile('word/document.xml');
        if (part == null) return null;
        final scanned = DocxOrigin.scan(utf8.decode(part.content as List<int>));
        if (scanned == null) return null;
        if (plan.anew.isNotEmpty) {
          final units = [
            for (final unit in scanned.units)
              if (unit.paragraph || unit.table) unit.xml,
          ];
          if (units.length != plan.anew.length) return null;
          fresh = units;
          import = _Import(written, package, 'word/document.xml');
        }
        if (sheet) tail = _withSheet(tail, scanned.tail);
        for (final kind in regions) {
          final next = _withRegion(tail, kind, written, scanned.tail, package);
          if (next == null) return null;
          tail = next;
          head = _withNamespaces(head, tail);
        }
      }
      // Only what is written of each is taken in with what it needs: a
      // paragraph that keeps its own properties brings its runs alone.
      final body = _write(origin, plan, fresh, import?.take ?? (xml) => xml);
      if (body == null) return null;
      head = _withNamespaces(head, body);
      // What is written is read back and held against what was to be
      // written: a file that does not say the same is not kept. Read
      // without the body's pictures, which say nothing and take longest,
      // unless a header's own may be among them.
      final document = '$head$body$tail';
      final back = await DocxBridge.readBytes(
        origin._repack(document, package, pictures: regions.isNotEmpty),
      );
      if (back == null ||
          _letters(back.blocks) != _letters(model.blocks) ||
          _sheetPrint(back) != _sheetPrint(model)) {
        return null;
      }
      for (final kind in regions) {
        if (_regionLetters(back, kind) != _regionLetters(model, kind)) {
          return null;
        }
      }
      return origin._repack(document, package);
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

  /// The sheet: its size, which way it lies, its margins.
  static String _sheetPrint(DocModel model) {
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
    ]);
  }

  /// A header or a footer: what it holds, and where its page number is.
  static String _regionPrint(DocModel model, String kind) => jsonEncode([
    for (final block in model.pageRegions[kind] ?? const <DocBlock>[])
      print(block),
    // None and an empty one are the same: the editor gives an empty one.
    switch (model.metadata['pageRegionAttrs']) {
      final Map attrs when attrs[kind] != null => jsonEncode(attrs[kind]),
      _ => '',
    },
  ]);

  static String _regionLetters(DocModel model, String kind) =>
      _letters(model.pageRegions[kind] ?? const []);

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

  /// What is written where: each unit kept as it was, each block written
  /// anew and whose properties it takes, and the section breaks of what
  /// was taken out handed to what is beside them.
  static _Plan _plan(DocxOrigin origin, DocModel model) {
    final saved = [for (final block in model.blocks) print(block)];
    final match = _match(origin.prints, saved);
    // For each saved block, the original block it is, or -1.
    final from = List.filled(saved.length, -1);
    for (final (o, s) in match.indexed) {
      if (s >= 0) from[s] = o;
    }
    final pieces = <_Piece>[];
    final anew = <int>[];
    var written = 0;

    // A section's break outlives the paragraph it was written in: the
    // paragraph before takes it, or one made for it alone.
    void carry(String section) {
      final last = pieces.lastOrNull;
      if (last != null && last.paragraph) {
        if (last.xml != null && !last.xml!.contains('<w:sectPr')) {
          last.xml = _withSection(last.xml!, section);
          return;
        }
        if (last.fresh != null && last.section == null && !last.ownHead) {
          last.section = section;
          return;
        }
      }
      pieces.add(_Piece.kept('<w:p><w:pPr>$section</w:pPr></w:p>', null, true));
    }

    void advance(int until) {
      for (; written < until; written++) {
        final unit = origin.units[written];
        if (unit.blocks == 0) {
          pieces.add(_Piece.kept(unit.xml, null, false));
        } else if (_sectionOf(unit.xml) case final section?) {
          carry(section);
        }
      }
    }

    var s = 0;
    while (s < saved.length) {
      final o = from[s];
      final unit = o < 0 ? null : origin.unitOf[o];
      // A unit all of whose blocks follow one another as they were.
      if (unit != null && unit >= written && origin.units[unit].first == o) {
        final u = origin.units[unit];
        var whole = s + u.blocks <= saved.length;
        for (var k = 0; whole && k < u.blocks; k++) {
          whole = from[s + k] == o + k;
        }
        if (whole) {
          advance(unit);
          pieces.add(_Piece.kept(u.xml, unit, u.paragraph));
          written = unit + 1;
          s += u.blocks;
          continue;
        }
      }
      // Touched, or new. Its own unit, when that is the next one not yet
      // written, holds this one block and none of it was kept: a
      // paragraph whose words or shape changed.
      final block = model.blocks[s];
      final writable =
          block.type == DocBlockType.paragraph ||
          block.type == DocBlockType.listItem;
      int? own;
      for (var u = written; writable && u < origin.units.length; u++) {
        final candidate = origin.units[u];
        if (candidate.blocks == 0) continue;
        if (candidate.blocks == 1 &&
            candidate.paragraph &&
            match[candidate.first] < 0) {
          own = u;
        }
        break;
      }
      final piece = _Piece.anew(anew.length);
      if (own != null) {
        advance(own);
        final unit = origin.units[own];
        piece
          ..unit = own
          ..ownHead = _shape(origin.blocks[unit.first]) == _shape(block);
        // Its shape changed: its properties are written anew, the
        // section it ends kept with it.
        if (!piece.ownHead) piece.section = _sectionOf(unit.xml);
        written = own + 1;
      } else if (block.listType != DocListType.none) {
        // An item put into a list goes on with that list's numbering:
        // the item before it lends its properties.
        final before = pieces.lastOrNull?.unit;
        if (before != null && origin.units[before].blocks == 1) {
          final was = origin.blocks[origin.units[before].first];
          if (was.listType == block.listType &&
              was.listLevel == block.listLevel) {
            piece.borrow = before;
          }
        }
      }
      pieces.add(piece);
      anew.add(s);
      s++;
    }
    advance(origin.units.length);
    return _Plan(pieces, anew);
  }

  /// The body as it is written from [plan], [fresh] holding what was
  /// written anew; null when a piece cannot be put together.
  static String? _write(
    DocxOrigin origin,
    _Plan plan,
    List<String> fresh,
    String Function(String xml) take,
  ) {
    final out = StringBuffer();
    for (final piece in plan.pieces) {
      if (piece.xml case final kept?) {
        out.write(kept);
        continue;
      }
      var xml = fresh[piece.fresh!];
      final lender = piece.ownHead ? piece.unit : piece.borrow;
      if (lender != null) {
        // The paragraph's own opening and properties (or the list item's
        // before it), the new runs in them.
        var head = _paragraphHead(origin.units[lender].xml);
        final runs = _paragraphRuns(xml);
        if (head == null || runs == null) return null;
        if (!piece.ownHead) {
          head = '<w:p>${_properties(head)}'
              .replaceAll(_sectionPattern, '')
              .replaceAll(_breakBefore, '');
        }
        xml = '$head${take(runs)}</w:p>';
      } else {
        xml = take(xml);
      }
      if (piece.section case final section?) xml = _withSection(xml, section);
      out.write(xml);
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

  /// The properties alone of a paragraph's [head].
  static String _properties(String head) {
    final at = head.indexOf('<w:pPr');
    return at < 0 ? '' : head.substring(at);
  }

  /// What a paragraph written anew holds after its properties.
  static String? _paragraphRuns(String xml) {
    final head = _paragraphHead(xml);
    if (head == null || !xml.endsWith('</w:p>')) return null;
    return xml.substring(head.length, xml.length - '</w:p>'.length);
  }

  /// The section a paragraph ends, written in its properties; null when
  /// it ends none.
  static String? _sectionOf(String xml) {
    final head = _paragraphHead(xml);
    if (head == null) return null;
    return _sectionPattern.firstMatch(head)?.group(0);
  }

  /// [paragraph] ending [section].
  static String _withSection(String paragraph, String section) {
    final open = _open.matchAsPrefix(paragraph);
    if (open == null) return paragraph;
    if (open.group(0)!.endsWith('/>')) {
      final tag = open.group(0)!;
      return '${tag.substring(0, tag.length - 2)}>'
          '<w:pPr>$section</w:pPr></w:p>';
    }
    final end = open.end;
    if (paragraph.startsWith('<w:pPr/>', end)) {
      return '${paragraph.substring(0, end)}<w:pPr>$section</w:pPr>'
          '${paragraph.substring(end + '<w:pPr/>'.length)}';
    }
    if (paragraph.startsWith('<w:pPr>', end)) {
      final close = paragraph.indexOf('</w:pPr>', end);
      if (close < 0) return paragraph;
      // A paragraph's properties end with the run properties of its mark
      // and its section; the section last.
      return '${paragraph.substring(0, close)}$section'
          '${paragraph.substring(close)}';
    }
    return '${paragraph.substring(0, end)}<w:pPr>$section</w:pPr>'
        '${paragraph.substring(end)}';
  }

  static final _open = RegExp(r'<w:p(?: [^>]*)?>');
  static final _sectionPattern = RegExp(
    r'<w:sectPr(?: [^>]*)?/>|<w:sectPr(?: [^>]*)?>.*?</w:sectPr>',
    dotAll: true,
  );
  static final _breakBefore = RegExp(r'<w:pageBreakBefore(?: [^>]*)?/>');

  /// The document's opening with the names what is put in is written in
  /// (`r:` for a picture's and a link's ties, `wp:` for a picture), when
  /// it does not have them.
  static String _withNamespaces(String head, String put) {
    const names = {
      'r':
          'http://schemas.openxmlformats.org/officeDocument/2006/'
          'relationships',
      'wp':
          'http://schemas.openxmlformats.org/drawingml/2006/'
          'wordprocessingDrawing',
    };
    final open = RegExp(r'<w:document\b[^>]*>').firstMatch(head);
    if (open == null) return head;
    var tag = open.group(0)!;
    for (final MapEntry(key: name, value: uri) in names.entries) {
      if (put.contains('<$name:') || put.contains(' $name:')) {
        if (!tag.contains('xmlns:$name=')) {
          tag = '${tag.substring(0, tag.length - 1)} xmlns:$name="$uri">';
        }
      }
    }
    return head.replaceRange(open.start, open.end, tag);
  }

  static final _lastSection = RegExp(
    r'<w:sectPr(?: [^>]*)?>.*?</w:sectPr>|<w:sectPr(?: [^>]*)?/>',
    dotAll: true,
  );

  /// The last section of [tail] as an element that can hold more.
  static (String tail, int start, int end)? _section(String tail) {
    final found = _lastSection.firstMatch(tail);
    if (found == null) {
      // No section written: one is, for what is to be said of the page.
      final at = tail.indexOf('</w:body>');
      if (at < 0) return null;
      const empty = '<w:sectPr></w:sectPr>';
      return (
        '${tail.substring(0, at)}$empty${tail.substring(at)}',
        at,
        at + empty.length,
      );
    }
    var section = found.group(0)!;
    if (section.endsWith('/>')) {
      section = '${section.substring(0, section.length - 2)}></w:sectPr>';
      return (
        tail.replaceRange(found.start, found.end, section),
        found.start,
        found.start + section.length,
      );
    }
    return (tail, found.start, found.end);
  }

  /// [tail] with the sheet's size and margins as [written]'s section has
  /// them, the rest of its own section as it was.
  static String _withSheet(String tail, String written) {
    final at = _section(tail);
    if (at == null) return tail;
    var (text, start, end) = at;
    var section = text.substring(start, end);
    for (final name in const ['w:pgSz', 'w:pgMar']) {
      final element = RegExp('<$name\\b[^>]*/>');
      final now = element.firstMatch(written)?.group(0);
      if (now == null) continue;
      if (element.hasMatch(section)) {
        section = section.replaceFirst(element, now);
      } else {
        // After the header's and footer's ties, which come first.
        final ties = RegExp(r'<w:(?:header|footer)Reference\b[^>]*/>')
            .allMatches(section)
            .lastOrNull;
        final open = ties?.end ?? section.indexOf('>') + 1;
        section = section.replaceRange(open, open, now);
      }
    }
    return text.replaceRange(start, end, section);
  }

  /// [tail] with the header or footer of [kind] as [written] has it: its
  /// part put into [package] in the place of the one the section showed,
  /// or as a new part tied to it; taken off when [written] has none.
  static String? _withRegion(
    String tail,
    String kind,
    Archive written,
    String writtenTail,
    _Package package,
  ) {
    final at = _section(tail);
    if (at == null) return null;
    var (text, start, end) = at;
    var section = text.substring(start, end);
    RegExp tie(String type) =>
        RegExp('<w:${kind}Reference\\b(?=[^>]*w:type="$type")[^>]*/>');
    final type =
        'http://schemas.openxmlformats.org/officeDocument/2006/'
        'relationships/$kind';
    final now = tie('default').firstMatch(writtenTail)?.group(0);
    final was = tie('default').firstMatch(section)?.group(0);
    if (now == null) {
      // None now: the section shows none.
      if (was != null) section = section.replaceFirst(was, '');
      return text.replaceRange(start, end, section);
    }
    final id = _attribute(now, 'r:id');
    final source = id == null
        ? null
        : _Rels.of(written, 'word/document.xml').target(id);
    final part = source == null ? null : written.findFile('word/$source');
    if (part == null) return null;
    // The part the section showed, written over; or a new one.
    String? name;
    if (was != null) {
      final old = _attribute(was, 'r:id');
      final target = old == null
          ? null
          : package.rels('word/document.xml').target(old);
      if (target != null) name = 'word/$target';
    }
    if (name == null) {
      name = package.free(
        'word/folio${kind == 'header' ? 'Header' : 'Footer'}',
        'xml',
      );
      final tied = package
          .rels('word/document.xml')
          .add(type, name.substring('word/'.length));
      package.contentType(
        '/$name',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.'
            '$kind+xml',
      );
      final reference = '<w:${kind}Reference w:type="default" r:id="$tied"/>';
      section = was != null
          ? section.replaceFirst(was, reference)
          : section.replaceRange(
              section.indexOf('>') + 1,
              section.indexOf('>') + 1,
              reference,
            );
    }
    // Its own ties (a picture in a letterhead) come with it.
    package.dropRels(name);
    final import = _Import(written, package, name, from: 'word/$source');
    package.put(
      name,
      utf8.encode(import.take(utf8.decode(part.content as List<int>))),
    );
    return text.replaceRange(start, end, section);
  }

  static String? _attribute(String element, String name) =>
      RegExp('\\b$name="([^"]*)"').firstMatch(element)?.group(1);

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

class _Plan {
  const _Plan(this.pieces, this.anew);

  final List<_Piece> pieces;

  /// The saved blocks written anew, in the order they are written.
  final List<int> anew;
}

/// One thing written into the body: a unit as it was, or a block written
/// anew.
class _Piece {
  _Piece.kept(this.xml, this.unit, this.paragraph) : fresh = null;
  _Piece.anew(this.fresh) : paragraph = true;

  /// As it was (and as it is written, a section handed to it added).
  String? xml;

  /// Which of the blocks written anew.
  final int? fresh;

  /// The unit it was, or whose paragraph it is with other words.
  int? unit;
  final bool paragraph;

  /// Whether it keeps its own unit's properties as Word wrote them.
  bool ownHead = false;

  /// A list item before it whose properties it takes, to go on with that
  /// list's numbering.
  int? borrow;

  /// A section it ends, handed to it.
  String? section;
}

/// A part's ties to other parts and to addresses outside the file.
class _Rels {
  _Rels(this.xml);

  static const _empty =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/'
      '2006/relationships"></Relationships>';

  static String nameOf(String part) {
    final slash = part.lastIndexOf('/');
    return '${part.substring(0, slash)}/_rels/'
        '${part.substring(slash + 1)}.rels';
  }

  static _Rels of(Archive archive, String part) {
    final file = archive.findFile(nameOf(part));
    return _Rels(
      file == null ? _empty : utf8.decode(file.content as List<int>),
    );
  }

  String xml;
  var _made = 0;

  static final _one = RegExp(r'<Relationship\b[^>]*/>');

  String? _find(String id) {
    for (final m in _one.allMatches(xml)) {
      if (DocxSplice._attribute(m.group(0)!, 'Id') == id) return m.group(0);
    }
    return null;
  }

  String? target(String id) {
    final found = _find(id);
    return found == null ? null : DocxSplice._attribute(found, 'Target');
  }

  String? type(String id) {
    final found = _find(id);
    return found == null ? null : DocxSplice._attribute(found, 'Type');
  }

  bool external(String id) =>
      DocxSplice._attribute(_find(id) ?? '', 'TargetMode') == 'External';

  /// A new tie, by an id no other has.
  String add(String type, String target, {bool external = false}) {
    String id;
    do {
      id = 'rIdFolio${++_made}';
    } while (xml.contains('Id="$id"'));
    final one =
        '<Relationship Id="$id" Type="$type" Target="$target"'
        '${external ? ' TargetMode="External"' : ''}/>';
    final at = xml.lastIndexOf('</Relationships>');
    xml = at < 0
        ? xml.replaceFirst(
            RegExp(r'<Relationships\b([^>]*)/>'),
            '<Relationships\$1>$one</Relationships>',
          )
        : xml.replaceRange(at, at, one);
    return id;
  }
}

/// The original package with what is put into it: parts changed, parts
/// added, every other part as it was.
class _Package {
  _Package(this.archive);

  final Archive archive;
  final parts = <String, List<int>>{};
  final _rels = <String, _Rels>{};
  final _dropped = <String>{};

  bool has(String name) =>
      parts.containsKey(name) || archive.findFile(name) != null;

  String? text(String name) {
    if (parts[name] case final bytes?) return utf8.decode(bytes);
    final file = archive.findFile(name);
    return file == null ? null : utf8.decode(file.content as List<int>);
  }

  void put(String name, List<int> bytes) => parts[name] = bytes;

  /// A name no part has: [stem], or [stem] with a number, and [extension].
  String free(String stem, String extension) {
    for (var i = 1; ; i++) {
      final name = '$stem${i == 1 ? '' : i}.$extension';
      if (!has(name)) return name;
    }
  }

  _Rels rels(String part) => _rels.putIfAbsent(
    part,
    () =>
        _dropped.contains(part) ? _Rels(_Rels._empty) : _Rels.of(archive, part),
  );

  /// [part]'s ties forgotten: it is written over with a part of other
  /// ties.
  void dropRels(String part) {
    _dropped.add(part);
    _rels[part] = _Rels(_Rels._empty);
  }

  /// The kind of [part] (`/word/x.xml`) said in the package's list, when
  /// it is not said there yet.
  void contentType(String part, String type) {
    const name = '[Content_Types].xml';
    final xml = text(name);
    if (xml == null || xml.contains('PartName="$part"')) return;
    final at = xml.lastIndexOf('</Types>');
    if (at < 0) return;
    put(
      name,
      utf8.encode(
        xml.replaceRange(
          at,
          at,
          '<Override PartName="$part" ContentType="$type"/>',
        ),
      ),
    );
  }

  /// The kind of every file ending in [extension], when it is not said.
  void defaultType(String extension, String type) {
    const name = '[Content_Types].xml';
    final xml = text(name);
    if (xml == null ||
        RegExp('Extension="$extension"', caseSensitive: false).hasMatch(xml)) {
      return;
    }
    final at = xml.indexOf('>', xml.indexOf('<Types')) + 1;
    if (at <= 0) return;
    put(
      name,
      utf8.encode(
        xml.replaceRange(
          at,
          at,
          '<Default Extension="$extension" ContentType="$type"/>',
        ),
      ),
    );
  }

  /// The parts to write: those changed and added, and the ties changed.
  Map<String, List<int>> get written => {
    ...parts,
    for (final MapEntry(key: part, value: rels) in _rels.entries)
      if (rels.xml != _Rels._empty || _dropped.contains(part))
        if (rels.xml != (text(_Rels.nameOf(part)) ?? ''))
          _Rels.nameOf(part): utf8.encode(rels.xml),
  };
}

/// What was written anew taken into the original package with what it
/// needs: a picture's file and its tie, a link's address, a list's
/// numbering, a style the original does not have.
class _Import {
  _Import(this.written, this.package, this.part, {String? from})
    : _from = _Rels.of(written, from ?? 'word/document.xml');

  final Archive written;
  final _Package package;

  /// The part of the original what is taken goes into.
  final String part;
  final _Rels _from;
  final _ids = <String, String>{};
  final _nums = <String, String>{};
  final _abstracts = <String, String>{};

  static final _tie = RegExp(r'\br:(embed|id|link|pict)="([^"]+)"');
  static final _num = RegExp(r'<w:numId w:val="(\d+)"/>');
  static final _style = RegExp(
    r'<w:(?:pStyle|rStyle|tblStyle) w:val="([^"]+)"',
  );

  static const _mime = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'bmp': 'image/bmp',
    'webp': 'image/webp',
  };

  String take(String xml) {
    xml = xml.replaceAllMapped(_tie, (m) {
      final id = _tied(m.group(2)!);
      return id == null ? m.group(0)! : 'r:${m.group(1)}="$id"';
    });
    xml = xml.replaceAllMapped(_num, (m) {
      final id = _numbered(m.group(1)!);
      return '<w:numId w:val="${id ?? m.group(1)}"/>';
    });
    for (final m in _style.allMatches(xml)) {
      _styled(m.group(1)!);
    }
    return xml;
  }

  /// The id in the original of what [id] ties in what was written.
  String? _tied(String id) {
    if (_ids[id] case final known?) return known;
    final type = _from.type(id), target = _from.target(id);
    if (type == null || target == null) return null;
    final rels = package.rels(part);
    if (_from.external(id)) {
      return _ids[id] = rels.add(type, target, external: true);
    }
    final source = written.findFile('word/$target');
    if (source == null) return null;
    final extension = target.contains('.')
        ? target.substring(target.lastIndexOf('.') + 1).toLowerCase()
        : 'bin';
    final name = package.free('word/media/folio', extension);
    package.put(name, source.content as List<int>);
    if (_mime[extension] case final mime?) {
      package.defaultType(extension, mime);
    }
    return _ids[id] = rels.add(type, name.substring('word/'.length));
  }

  static const _numbering = 'word/numbering.xml';

  /// The number in the original of the list [id] is in what was written,
  /// its definition taken with it.
  String? _numbered(String id) {
    if (_nums[id] case final known?) return known;
    final source = written.findFile(_numbering);
    if (source == null) return null;
    final from = utf8.decode(source.content as List<int>);
    final num = RegExp(
      '<w:num w:numId="$id"(?: [^>]*)?>.*?</w:num>',
      dotAll: true,
    ).firstMatch(from)?.group(0);
    if (num == null) return null;
    final abstractId = RegExp(r'<w:abstractNumId w:val="(\d+)"/>')
        .firstMatch(num)
        ?.group(1);
    if (abstractId == null) return null;
    var into = package.text(_numbering);
    if (into == null) {
      // The original numbers nothing: a part for what does now.
      final root = RegExp(r'<w:numbering\b[^>]*>').firstMatch(from)?.group(0);
      if (root == null) return null;
      into =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '$root</w:numbering>';
      package
          .rels('word/document.xml')
          .add(
            'http://schemas.openxmlformats.org/officeDocument/2006/'
                'relationships/numbering',
            'numbering.xml',
          );
      package.contentType(
        '/$_numbering',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.'
            'numbering+xml',
      );
    }
    // A numbering part that holds nothing may be written closed.
    if (!into.contains('</w:numbering>')) {
      final closed = RegExp(r'<w:numbering\b([^>]*)/>').firstMatch(into);
      if (closed == null) return null;
      into = into.replaceRange(
        closed.start,
        closed.end,
        '<w:numbering${closed.group(1)}></w:numbering>',
      );
    }
    int next(String pattern) =>
        RegExp(pattern)
            .allMatches(into!)
            .map((m) => int.parse(m.group(1)!))
            .fold(0, (a, b) => a > b ? a : b) +
        1;
    var abstract = _abstracts[abstractId];
    if (abstract == null) {
      final definition = RegExp(
        '<w:abstractNum w:abstractNumId="$abstractId"(?: [^>]*)?>.*?'
        '</w:abstractNum>',
        dotAll: true,
      ).firstMatch(from)?.group(0);
      if (definition == null) return null;
      abstract = '${next(r'<w:abstractNum w:abstractNumId="(\d+)"')}';
      _abstracts[abstractId] = abstract;
      // Definitions come before the lists that use them.
      final first = into.indexOf('<w:num ');
      final at = first >= 0 ? first : into.lastIndexOf('</w:numbering>');
      into = into.replaceRange(
        at,
        at,
        definition.replaceFirst(
          'w:abstractNumId="$abstractId"',
          'w:abstractNumId="$abstract"',
        ),
      );
    }
    final made = '${next(r'<w:num w:numId="(\d+)"')}';
    final at = into.lastIndexOf('</w:numbering>');
    into = into.replaceRange(
      at,
      at,
      num.replaceFirst('w:numId="$id"', 'w:numId="$made"').replaceFirst(
        '<w:abstractNumId w:val="$abstractId"/>',
        '<w:abstractNumId w:val="$abstract"/>',
      ),
    );
    package.put(_numbering, utf8.encode(into));
    return _nums[id] = made;
  }

  /// The style [id] taken into the original's styles when it has none by
  /// that name.
  void _styled(String id) {
    const name = 'word/styles.xml';
    final into = package.text(name);
    if (into == null || into.contains('w:styleId="$id"')) return;
    final source = written.findFile(name);
    if (source == null) return;
    final style = RegExp(
      '<w:style\\b(?=[^>]*w:styleId="$id")[^>]*>.*?</w:style>',
      dotAll: true,
    ).firstMatch(utf8.decode(source.content as List<int>))?.group(0);
    final at = into.lastIndexOf('</w:styles>');
    if (style == null || at < 0) return;
    package.put(name, utf8.encode(into.replaceRange(at, at, style)));
  }
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

  /// The package with [document] as its document part, what [package]
  /// holds changed or added, and every other part as it was.
  Uint8List _repack(String document, _Package package, {bool pictures = true}) {
    final out = Archive();
    final written = package.written;
    for (final file in _archive) {
      if (!file.isFile) continue;
      if (!pictures && file.name.startsWith('word/media/')) continue;
      if (file.name == 'word/document.xml') {
        final content = [
          if (_marked) ...const [0xEF, 0xBB, 0xBF],
          ...utf8.encode(document),
        ];
        out.addFile(ArchiveFile(file.name, content.length, content));
      } else if (written[file.name] case final content?) {
        out.addFile(ArchiveFile(file.name, content.length, content));
      } else {
        // As it is in the file, still compressed: a picture of megabytes
        // is not opened and pressed again at every save.
        out.addFile(file);
      }
    }
    for (final MapEntry(key: name, value: content) in written.entries) {
      if (_archive.findFile(name) != null) continue;
      if (!pictures && name.startsWith('word/media/')) continue;
      out.addFile(ArchiveFile(name, content.length, content));
    }
    return Uint8List.fromList(ZipEncoder().encode(out));
  }
}

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../layout/page_numbers.dart';

/// What a Word file's last section says of its header and footer, read from
/// the package itself: which part each one is, on which pages it shows,
/// where it prints, and its page number. The reader used for the rest takes
/// the first header and the last footer it meets, whatever pages they are
/// for, and turns a page number into the digit it last showed.
class DocxPageRegions {
  const DocxPageRegions({
    this.headerOffset,
    this.footerOffset,
    this.regions = const {},
  });

  /// Where the header and footer print, from the sheet's edge, in points.
  final double? headerOffset, footerOffset;

  /// 'header' and 'footer', those the document has.
  final Map<String, DocxRegion> regions;

  /// Read from the package's bytes; null when they cannot be.
  static DocxPageRegions? read(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      String? text(String name) {
        final file = archive.findFile(name);
        return file == null
            ? null
            : utf8.decode(file.content as List<int>, allowMalformed: true);
      }

      final document = text('word/document.xml');
      if (document == null) return null;
      final section = _bodySection(document);
      if (section == null) return const DocxPageRegions();
      final targets = _relationships(text('word/_rels/document.xml.rels'));
      final first = RegExp(r'<w:titlePg\b(?![^>]*w:val="(0|false|off)")')
          .hasMatch(section);
      final regions = <String, DocxRegion>{};
      for (final kind in const ['header', 'footer']) {
        final chosen = _choose(section, kind, targets, titlePage: first);
        if (chosen == null) continue;
        final target = targets[chosen.id];
        if (target == null) continue;
        final part = text(
          target.startsWith('/') ? target.substring(1) : 'word/$target',
        );
        if (part == null) continue;
        regions[kind] = DocxRegion._read(part, chosen);
      }
      double? offset(String name) {
        final margins = RegExp(r'<w:pgMar\b[^>]*>').firstMatch(section)?[0];
        final twips = margins == null
            ? null
            : RegExp('\\bw:$name="(-?\\d+)"').firstMatch(margins)?[1];
        final value = int.tryParse(twips ?? '');
        return value == null || value < 0 ? null : value / 20;
      }

      return DocxPageRegions(
        headerOffset: offset('header'),
        footerOffset: offset('footer'),
        regions: regions,
      );
    } catch (_) {
      return null;
    }
  }

  /// [documentXml] (as its bytes' characters, untouched) with only the
  /// chosen header and footer named in the body's section, for the reader
  /// to take those and no other.
  String keepChosen(String documentXml) {
    final start = documentXml.lastIndexOf('<w:sectPr');
    if (start < 0) return documentXml;
    final end = documentXml.indexOf('</w:sectPr>', start);
    if (end < 0) return documentXml;
    final section = documentXml.substring(start, end);
    final kept = section.replaceAllMapped(_reference, (m) {
      final kind = m[1]!;
      final id = _attribute(m[0]!, 'r:id');
      // The writer's own background picture is not a header to choose.
      if (id == 'rIdBgHdr') return m[0]!;
      return regions[kind]?._id == id ? m[0]! : '';
    });
    return documentXml.replaceRange(start, end, kept);
  }

  static final _reference = RegExp(r'<w:(header|footer)Reference\b[^>]*/>');

  static String? _attribute(String element, String name) =>
      RegExp('\\b$name="([^"]*)"').firstMatch(element)?[1];

  /// The body's own section: the last one, after every paragraph's.
  static String? _bodySection(String document) {
    final start = document.lastIndexOf('<w:sectPr');
    if (start < 0) return null;
    final end = document.indexOf('</w:sectPr>', start);
    return end < 0 ? null : document.substring(start, end);
  }

  static Map<String, String> _relationships(String? rels) {
    final targets = <String, String>{};
    for (final m in RegExp(r'<Relationship\b[^>]*>').allMatches(rels ?? '')) {
      final id = _attribute(m[0]!, 'Id');
      final target = _attribute(m[0]!, 'Target');
      if (id != null && target != null) targets[id] = target;
    }
    return targets;
  }

  /// The part Folio keeps for [kind] and the pages it shows on. Word puts a
  /// first page's own region on the first page only when the section has a
  /// title page (`w:titlePg`), and then the default one on the rest; an
  /// even pages' one stands for every page.
  static _Chosen? _choose(
    String section,
    String kind,
    Map<String, String> targets, {
    required bool titlePage,
  }) {
    final refs = <String, String>{};
    for (final m in _reference.allMatches(section)) {
      if (m[1] != kind) continue;
      final id = _attribute(m[0]!, 'r:id');
      if (id == null || id == 'rIdBgHdr') continue;
      refs.putIfAbsent(_attribute(m[0]!, 'w:type') ?? 'default', () => id);
    }
    final all = refs['default'] ?? refs['even'];
    final first = refs['first'];
    if (!titlePage) return all == null ? null : _Chosen(all, const {});
    if (all != null) {
      final same = first != null && targets[first] == targets[all];
      return _Chosen(all, same ? const {} : const {'startPage': '2'});
    }
    return first == null ? null : _Chosen(first, const {'stopPage': '1'});
  }
}

class _Chosen {
  const _Chosen(this.id, this.placement);
  final String id;
  final Map<String, String> placement;
}

/// A header or footer part as Folio keeps it.
class DocxRegion {
  const DocxRegion._(
    this._id, {
    required this.placement,
    required this.blocks,
    this.numberAt,
    this.numbering,
    this.unplaced = false,
  });

  final String _id;

  /// startPage / stopPage, as UYAP's regions say on which pages they show.
  final Map<String, String> placement;

  /// How many paragraphs and tables the part holds at its top level.
  final int blocks;

  /// Which of those is the page number's paragraph, if one is.
  final int? numberAt;
  final PageNumbering? numbering;

  /// A page number Folio cannot take apart from what is around it (in a
  /// table, say): the region is better left out than shown with the digit
  /// it last printed on every page.
  final bool unplaced;

  static DocxRegion _read(String xml, _Chosen chosen) {
    final root = XmlDocument.parse(xml).rootElement;
    final top = [
      for (final child in root.childElements)
        if (child.name.qualified == 'w:p' || child.name.qualified == 'w:tbl')
          child,
    ];
    bool numbered(XmlElement element) => element.descendantElements.any(
      (e) =>
          (e.name.qualified == 'w:instrText' && _isPage(e.innerText)) ||
          (e.name.qualified == 'w:fldSimple' &&
              _isPage(e.getAttribute('w:instr') ?? '')),
    );
    final at = top.indexWhere((e) => e.name.qualified == 'w:p' && numbered(e));
    final anywhere = numbered(root);
    if (at < 0) {
      return DocxRegion._(
        chosen.id,
        placement: chosen.placement,
        blocks: top.length,
        unplaced: anywhere,
      );
    }
    return DocxRegion._(
      chosen.id,
      placement: chosen.placement,
      blocks: top.length,
      numberAt: at,
      numbering: _numbering(top[at], top: at == 0 && top.length > 1),
    );
  }

  static final _page = RegExp(r'(^|\s)PAGE(\s|$|\\)');
  static final _total = RegExp(r'(^|\s)(NUMPAGES|SECTIONPAGES)(\s|$|\\)');

  static bool _isPage(String instruction) => _page.hasMatch(instruction);

  /// The numbering a paragraph holding a PAGE field asks for: its words
  /// before the number, between it and the page count, and after.
  static PageNumbering _numbering(XmlElement paragraph, {required bool top}) {
    final parts = <StringBuffer>[StringBuffer()];
    var sawPage = false, sawTotal = false;
    // Inside a field: its instruction, then (after "separate") the result
    // it last showed, which is not the paragraph's own text.
    var depth = 0, inResult = false;
    final instruction = StringBuffer();
    void field(String code) {
      if (_isPage(code) && !sawPage) {
        sawPage = true;
        parts.add(StringBuffer());
      } else if (_total.hasMatch(code) && sawPage && !sawTotal) {
        sawTotal = true;
        parts.add(StringBuffer());
      }
    }

    for (final e in paragraph.descendantElements) {
      switch (e.name.qualified) {
        case 'w:fldChar':
          switch (e.getAttribute('w:fldCharType')) {
            case 'begin':
              depth++;
              inResult = false;
              instruction.clear();
            case 'separate':
              if (depth == 1) field(instruction.toString());
              inResult = true;
            case 'end':
              if (depth == 1 && !inResult) field(instruction.toString());
              depth = depth > 0 ? depth - 1 : 0;
              inResult = depth > 0;
          }
        case 'w:instrText':
          if (depth == 1) instruction.write(e.innerText);
        case 'w:fldSimple':
          field(e.getAttribute('w:instr') ?? '');
        case 'w:t':
          final inSimple = e.ancestors.whereType<XmlElement>().any(
            (a) => a.name.qualified == 'w:fldSimple',
          );
          if (depth == 0 && !inSimple) parts.last.write(e.innerText);
        case 'w:tab':
          if (depth == 0) parts.last.write('\t');
      }
    }
    final prefix = parts.first.toString();
    final separator = sawTotal && parts.length > 2 ? parts[1].toString() : '/';
    final suffix = parts.length > 1 ? parts.last.toString() : '';
    final align = paragraph
        .findAllElements('w:jc')
        .firstOrNull
        ?.getAttribute('w:val');
    final run = paragraph.findAllElements('w:rPr').firstOrNull;
    final font = run
        ?.findElements('w:rFonts')
        .firstOrNull
        ?.getAttribute('w:ascii');
    final half = int.tryParse(
      run?.findElements('w:sz').firstOrNull?.getAttribute('w:val') ?? '',
    );
    bool on(String name) {
      final flag = run?.findElements(name).firstOrNull;
      if (flag == null) return false;
      final value = flag.getAttribute('w:val');
      return value == null || !const ['0', 'false', 'off'].contains(value);
    }

    return PageNumbering(
      top: top,
      align: switch (align) {
        'center' => PageNumberAlign.center,
        'right' || 'end' => PageNumberAlign.right,
        _ => PageNumberAlign.left,
      },
      withTotal: sawTotal,
      prefix: prefix,
      separator: separator,
      suffix: suffix,
      fontFace: font == null || font.isEmpty ? 'Arial' : font,
      fontSize: half == null ? 11 : half / 2,
      bold: on('w:b'),
      italic: on('w:i'),
    );
  }
}

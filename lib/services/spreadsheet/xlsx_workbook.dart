import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:xml/xml.dart';
import 'package:path/path.dart' as p;

class XlsxCell {
  final String value, formula;
  final String? rawValue;
  final bool bold;
  final String? color, fill;
  const XlsxCell({
    this.value = '',
    this.rawValue,
    this.formula = '',
    this.bold = false,
    this.color,
    this.fill,
  });
  String get input => formula.isEmpty ? (rawValue ?? value) : '=$formula';
}

class XlsxSheet {
  final String name, path;
  final Map<String, XlsxCell> cells;
  final bool protected;
  final List<String> formulaRanges;
  final int rows, columns;
  const XlsxSheet(
    this.name,
    this.path,
    this.cells,
    this.rows,
    this.columns,
    this.protected,
    this.formulaRanges,
  );
}

/// Edit OOXML parts in place; unrelated styles, charts, relationships and sheets
/// remain byte-identical. Formula calculation is left to the spreadsheet app.
class XlsxWorkbook {
  final Map<String, Uint8List> parts;
  final List<XlsxSheet> sheets;
  final bool signed;
  const XlsxWorkbook(this.parts, this.sheets, this.signed);
  static const maxExpandedBytes = 256 * 1024 * 1024;
  static XmlDocument _xml(Uint8List bytes) =>
      XmlDocument.parse(utf8.decode(bytes));
  static Iterable<XmlElement> _nodes(XmlNode node, String name) => node
      .descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == name);
  static String columnName(int col) {
    var name = '';
    for (var n = col + 1; n > 0; n = (n - 1) ~/ 26) {
      name = String.fromCharCode(65 + (n - 1) % 26) + name;
    }
    return name;
  }

  static (int, int) coordinates(String ref) {
    final match = RegExp(r'^\$?([A-Za-z]+)\$?(\d+)$').firstMatch(ref);
    if (match == null) throw FormatException('Geçersiz hücre: $ref');
    var col = 0;
    for (final code in match[1]!.toUpperCase().codeUnits) {
      col = col * 26 + code - 64;
    }
    final row = int.parse(match[2]!);
    if (row < 1 || row > 1048576 || col < 1 || col > 16384) {
      throw FormatException('Geçersiz hücre: $ref');
    }
    return (row - 1, col - 1);
  }

  static String reference(int row, int col) => '${columnName(col)}${row + 1}';
  static bool inRange(String ref, String range) {
    final parts = range.split(':');
    final (r, c) = coordinates(ref);
    final (r1, c1) = coordinates(parts.first);
    final (r2, c2) = coordinates(parts.last);
    return r >= r1 && r <= r2 && c >= c1 && c <= c2;
  }

  static XlsxWorkbook read(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    if (archive.files.fold<int>(0, (n, f) => n + f.size) > maxExpandedBytes) {
      throw const FormatException('Excel dosyası önizleme sınırını aşıyor.');
    }
    final parts = <String, Uint8List>{
      for (final file in archive.files.where((f) => f.isFile))
        file.name: Uint8List.fromList(file.content as List<int>),
    };
    if (!parts.containsKey('xl/workbook.xml') ||
        !parts.containsKey('xl/_rels/workbook.xml.rels')) {
      throw const FormatException('Geçerli bir XLSX çalışma kitabı değil.');
    }
    final workbook = _xml(parts['xl/workbook.xml']!);
    final links = <String, String>{};
    for (final rel in _nodes(
      _xml(parts['xl/_rels/workbook.xml.rels']!),
      'Relationship',
    )) {
      if (rel.getAttribute('TargetMode') == 'External' ||
          !(rel.getAttribute('Type') ?? '').endsWith('/worksheet')) {
        continue;
      }
      final target = rel.getAttribute('Target') ?? '';
      links[rel.getAttribute('Id') ?? ''] = p.posix.normalize(
        target.startsWith('/') ? target.substring(1) : 'xl/$target',
      );
    }
    final shared = parts['xl/sharedStrings.xml'] == null
        ? <String>[]
        : _nodes(_xml(parts['xl/sharedStrings.xml']!), 'si')
              .map((si) => _nodes(si, 't').map((t) => t.innerText).join())
              .toList();
    final styles = parts['xl/styles.xml'] == null
        ? null
        : _xml(parts['xl/styles.xml']!);
    final fonts = styles == null
        ? <XmlElement>[]
        : _nodes(styles, 'font').toList();
    final fills = styles == null
        ? <XmlElement>[]
        : _nodes(styles, 'fill').toList();
    final formats = styles == null
        ? <XmlElement>[]
        : _nodes(styles, 'cellXfs').expand((e) => e.childElements).toList();
    final customFormats = <int, String>{
      if (styles != null)
        for (final format in _nodes(styles, 'numFmt'))
          if (int.tryParse(format.getAttribute('numFmtId') ?? '') != null)
            int.parse(format.getAttribute('numFmtId')!):
                format.getAttribute('formatCode') ?? '',
    };
    final date1904 = _nodes(
      workbook,
      'workbookPr',
    ).any((e) => ['1', 'true'].contains(e.getAttribute('date1904')));
    final sheets = <XlsxSheet>[];
    for (final sheet in _nodes(workbook, 'sheet')) {
      final id = sheet.attributes
          .where((a) => a.name.local == 'id')
          .firstOrNull
          ?.value;
      final path = links[id];
      if (path == null || !parts.containsKey(path)) continue;
      final xml = _xml(parts[path]!);
      final cells = <String, XlsxCell>{};
      final ranges = <String>[];
      var rows = 1, columns = 1;
      for (final cell in _nodes(xml, 'c')) {
        final ref = cell.getAttribute('r');
        if (ref == null) continue;
        final (r, c) = coordinates(ref);
        if (r + 1 > rows) rows = r + 1;
        if (c + 1 > columns) columns = c + 1;
        final raw = cell.getElement('v')?.innerText ?? '';
        final type = cell.getAttribute('t');
        var value = raw;
        if (type == 's') {
          final index = int.tryParse(raw);
          value = index != null && index >= 0 && index < shared.length
              ? shared[index]
              : '';
        }
        if (type == 'inlineStr') {
          value = _nodes(cell, 't').map((e) => e.innerText).join();
        }
        if (type == 'b') value = raw == '1' ? 'TRUE' : 'FALSE';
        final formula = cell.getElement('f');
        if ([
          'shared',
          'array',
          'dataTable',
        ].contains(formula?.getAttribute('t'))) {
          ranges.add(formula?.getAttribute('ref') ?? ref);
        }
        final styleIndex = int.tryParse(cell.getAttribute('s') ?? '') ?? 0;
        final style = styleIndex >= 0 && styleIndex < formats.length
            ? formats[styleIndex]
            : null;
        final fontId = int.tryParse(style?.getAttribute('fontId') ?? '') ?? 0;
        final fillId = int.tryParse(style?.getAttribute('fillId') ?? '') ?? 0;
        final font = fontId >= 0 && fontId < fonts.length
            ? fonts[fontId]
            : null;
        final fill = fillId >= 0 && fillId < fills.length
            ? fills[fillId]
            : null;
        final formatId =
            int.tryParse(style?.getAttribute('numFmtId') ?? '') ?? 0;
        cells[ref] = XlsxCell(
          rawValue: value,
          value: type == null || type == 'n'
              ? _displayNumber(
                  value,
                  formatId,
                  customFormats[formatId],
                  date1904,
                )
              : value,
          formula: formula?.innerText ?? '',
          bold:
              font?.getElement('b') != null &&
              ![
                '0',
                'false',
              ].contains(font?.getElement('b')?.getAttribute('val')),
          color: font?.getElement('color')?.getAttribute('rgb'),
          fill: fill == null
              ? null
              : _nodes(fill, 'fgColor').firstOrNull?.getAttribute('rgb'),
        );
      }
      sheets.add(
        XlsxSheet(
          sheet.getAttribute('name') ?? 'Sayfa ${sheets.length + 1}',
          path,
          cells,
          rows,
          columns,
          _nodes(xml, 'sheetProtection').any(
            (e) => !['0', 'false'].contains(e.getAttribute('sheet') ?? '1'),
          ),
          ranges,
        ),
      );
    }
    if (sheets.isEmpty) {
      throw const FormatException('Excel çalışma sayfası bulunamadı.');
    }
    return XlsxWorkbook(
      parts,
      sheets,
      parts.keys.any((k) => k.startsWith('_xmlsignatures/')),
    );
  }

  // Common Excel formats. Unknown custom formats retain the underlying value.
  static String _displayNumber(
    String raw,
    int id,
    String? custom,
    bool date1904,
  ) {
    final number = double.tryParse(raw);
    if (number == null || !number.isFinite) return raw;
    final code = (custom ?? '').toLowerCase();
    final dateCode = code.replaceAll(RegExp(r'"[^"]*"|\[[^\]]*\]|\\.'), '');
    final date =
        (id >= 14 && id <= 17) ||
        id == 22 ||
        (id >= 27 && id <= 36) ||
        (id >= 50 && id <= 58) ||
        RegExp(r'[dy]').hasMatch(dateCode);
    final time =
        (id >= 18 && id <= 22) ||
        [45, 46, 47].contains(id) ||
        code.contains('h:') ||
        code.contains('mm:ss');
    if ((date || time) && number >= 0 && number < 2958466) {
      if (id == 46 || code.contains('[h]')) {
        final seconds = (number * 86400).round();
        return '${seconds ~/ 3600}:${((seconds ~/ 60) % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
      }
      // Excel's 1900 calendar includes a fictitious leap day.
      if (!date1904 && number.floor() == 60 && date) return '29.02.1900';
      final base = date1904
          ? DateTime.utc(1904, 1, 1)
          : DateTime.utc(1899, 12, number < 60 ? 31 : 30);
      final value = base.add(
        Duration(milliseconds: (number * 86400000).round()),
      );
      return DateFormat(
        date ? (time ? 'dd.MM.yyyy HH:mm' : 'dd.MM.yyyy') : 'HH:mm:ss',
      ).format(value);
    }
    final pattern =
        custom ??
        const {
          1: '0',
          2: '0.00',
          3: '#,##0',
          4: '#,##0.00',
          9: '0%',
          10: '0.00%',
          11: '0.00E+00',
        }[id];
    if (pattern != null && RegExp(r'^[#0,.%]+$').hasMatch(pattern)) {
      try {
        return NumberFormat(pattern, 'tr_TR').format(number);
      } catch (_) {
        /* retain raw */
      }
    }
    return raw;
  }

  String text() => sheets
      .map(
        (sheet) =>
            '${sheet.name}\n${sheet.cells.values.map((c) => c.value.isEmpty ? c.input : c.value).join('\t')}',
      )
      .join('\n');
  void checkEditable(int sheetIndex, String ref) {
    final sheet = sheets[sheetIndex];
    if (signed) {
      throw const FormatException(
        'Dijital imzalı Excel dosyası salt okunur açıldı.',
      );
    }
    if (sheet.protected) {
      throw const FormatException('Bu çalışma sayfası korumalı.');
    }
    if (sheet.formulaRanges.any((range) => inRange(ref, range))) {
      throw const FormatException(
        'Dizi ve paylaşılan formül aralıklarını Excel’de düzenleyin.',
      );
    }
  }

  Uint8List write(Map<String, String> changes) {
    if (changes.isEmpty) return _zip(parts);
    final output = Map<String, Uint8List>.of(parts);
    final documents = <String, XmlDocument>{};
    for (final change in changes.entries) {
      final split = change.key.indexOf(':');
      final sheetIndex = int.parse(change.key.substring(0, split));
      final ref = change.key.substring(split + 1);
      checkEditable(sheetIndex, ref);
      final sheet = sheets[sheetIndex];
      final xml = documents.putIfAbsent(
        sheet.path,
        () => _xml(parts[sheet.path]!),
      );
      final data = _nodes(xml, 'sheetData').first;
      final (rowIndex, colIndex) = coordinates(ref);
      var row = data.childElements
          .where((r) => r.getAttribute('r') == '${rowIndex + 1}')
          .firstOrNull;
      if (row == null) {
        row = XmlElement(XmlName.qualified('row'), [
          XmlAttribute(XmlName.qualified('r'), '${rowIndex + 1}'),
        ]);
        final next = data.childElements
            .where(
              (r) =>
                  (int.tryParse(r.getAttribute('r') ?? '') ?? 0) > rowIndex + 1,
            )
            .firstOrNull;
        if (next == null) {
          data.children.add(row);
        } else {
          data.children.insert(data.children.indexOf(next), row);
        }
      }
      var cell = row.childElements
          .where((c) => c.getAttribute('r') == ref)
          .firstOrNull;
      if (cell == null) {
        cell = XmlElement(XmlName.qualified('c'), [
          XmlAttribute(XmlName.qualified('r'), ref),
        ]);
        final next = row.childElements
            .where(
              (c) => coordinates(c.getAttribute('r') ?? 'A1').$2 > colIndex,
            )
            .firstOrNull;
        if (next == null) {
          row.children.add(cell);
        } else {
          row.children.insert(row.children.indexOf(next), cell);
        }
      }
      cell.children.removeWhere(
        (n) => n is XmlElement && ['f', 'v', 'is'].contains(n.name.local),
      );
      cell.removeAttribute('t');
      final value = change.value;
      if (value.startsWith('=') && value.length > 1) {
        cell.children.add(
          XmlElement(XmlName.qualified('f'), [], [XmlText(value.substring(1))]),
        );
      } else if (['TRUE', 'FALSE'].contains(value.toUpperCase())) {
        cell.setAttribute('t', 'b');
        cell.children.add(
          XmlElement(XmlName.qualified('v'), [], [
            XmlText(value.toUpperCase() == 'TRUE' ? '1' : '0'),
          ]),
        );
      } else if (value.isNotEmpty && double.tryParse(value)?.isFinite == true) {
        cell.children.add(
          XmlElement(XmlName.qualified('v'), [], [XmlText(value)]),
        );
      } else if (value.isNotEmpty) {
        cell.setAttribute('t', 'inlineStr');
        cell.children.add(
          XmlElement(XmlName.qualified('is'), [], [
            XmlElement(
              XmlName.qualified('t'),
              [XmlAttribute(XmlName.qualified('xml:space'), 'preserve')],
              [XmlText(value)],
            ),
          ]),
        );
      }
      // Dimensions are optional; omitting stale bounds lets readers infer them.
      _nodes(
        xml,
        'dimension',
      ).toList().forEach((e) => e.parent?.children.remove(e));
    }
    // Any input change can affect formulas on another sheet. Never keep stale
    // cached answers or calc-chain references after editing.
    for (final sheet in sheets) {
      final xml = documents.putIfAbsent(
        sheet.path,
        () => _xml(parts[sheet.path]!),
      );
      for (final cell in _nodes(
        xml,
        'c',
      ).where((c) => c.getElement('f') != null)) {
        cell.getElement('v')?.parent?.children.remove(cell.getElement('v'));
      }
      output[sheet.path] = Uint8List.fromList(utf8.encode(xml.toXmlString()));
    }
    final workbook = _xml(parts['xl/workbook.xml']!);
    var calc = _nodes(workbook, 'calcPr').firstOrNull;
    if (calc == null) {
      calc = XmlElement(XmlName.qualified('calcPr'));
      workbook.rootElement.children.add(calc);
    }
    calc.setAttribute('fullCalcOnLoad', '1');
    calc.setAttribute('forceFullCalc', '1');
    calc.setAttribute('calcMode', 'auto');
    output['xl/workbook.xml'] = Uint8List.fromList(
      utf8.encode(workbook.toXmlString()),
    );
    final rels = _xml(parts['xl/_rels/workbook.xml.rels']!);
    for (final rel
        in _nodes(rels, 'Relationship')
            .where((r) => (r.getAttribute('Type') ?? '').endsWith('/calcChain'))
            .toList()) {
      final target = rel.getAttribute('Target') ?? '';
      output.remove(
        p.posix.normalize(
          target.startsWith('/') ? target.substring(1) : 'xl/$target',
        ),
      );
      rel.parent?.children.remove(rel);
    }
    output['xl/_rels/workbook.xml.rels'] = Uint8List.fromList(
      utf8.encode(rels.toXmlString()),
    );
    if (output['[Content_Types].xml'] != null) {
      final types = _xml(output['[Content_Types].xml']!);
      for (final type
          in _nodes(types, 'Override')
              .where(
                (t) =>
                    (t.getAttribute('ContentType') ?? '').contains('calcChain'),
              )
              .toList()) {
        type.parent?.children.remove(type);
      }
      output['[Content_Types].xml'] = Uint8List.fromList(
        utf8.encode(types.toXmlString()),
      );
    }
    return _zip(output);
  }

  static Uint8List _zip(Map<String, Uint8List> parts) {
    final archive = Archive();
    for (final part in parts.entries) {
      archive.addFile(ArchiveFile(part.key, part.value.length, part.value));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}

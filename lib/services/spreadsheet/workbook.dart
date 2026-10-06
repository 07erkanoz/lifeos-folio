import 'dart:async';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:excel_plus/excel_plus.dart' as xl;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' hide BorderStyle;
import 'package:worksheet/worksheet.dart';

import 'formula_locale.dart';

/// A workbook held twice: as excel_plus reads and writes it, and as the
/// worksheet widget shows and edits it.
///
/// Edits travel from the grid to excel_plus one changed cell at a time, the
/// formulas that depend on them are worked out again there, and saving writes
/// the excel_plus side. A cell nobody touched is therefore written back as it
/// was read: on the twenty workbooks this was tried on, a round trip lost no
/// part of the file, no value and no style.
///
/// Formulas show what Excel last worked out until something they depend on
/// changes. The engine does not know every function, and a result it cannot
/// reproduce is not replaced by an error the file never had.
class Workbook {
  Workbook._(this._excel, this.signed);

  final xl.Excel _excel;

  /// Whether the package carries a digital signature, which any change would
  /// break. Such a workbook is only shown.
  final bool signed;
  late final List<WorkbookSheet> sheets;
  final _changed = ValueNotifier(false);
  final _edits = ValueNotifier(0);
  bool _scheduled = false, _disposed = false;

  /// Whether the workbook differs from the file it was read from, or from
  /// what was last saved.
  ValueListenable<bool> get changed => _changed;

  /// Counts the edits that reached the workbook, one tick per batch.
  ValueListenable<int> get edits => _edits;

  static Future<Workbook> read(Uint8List bytes, {bool changed = false}) async {
    final excel = await xl.Excel.decodeBytesAsync(bytes);
    _functions(excel);
    final book = Workbook._(excel, _isSigned(bytes));
    book.sheets = [
      for (final entry in excel.tables.entries)
        if (entry.value.visibility == xl.SheetVisibility.visible)
          WorkbookSheet._(book, entry.key, entry.value),
    ];
    book._changed.value = changed;
    // Formulas a tool saved without results are worked out once; the others
    // keep what Excel computed.
    final unresolved = [
      for (final sheet in book.sheets) ...sheet._unresolved(),
    ];
    if (unresolved.isNotEmpty) {
      book._recalculate(unresolved);
    }
    return book;
  }

  /// The workbook as an .xlsx file, every pending edit included.
  Future<Uint8List> write() async {
    flush();
    final bytes = await _excel.encodeAsync();
    if (bytes == null) {
      throw StateError('Çalışma kitabı yazılamadı.');
    }
    return Uint8List.fromList(bytes);
  }

  void markSaved() => _changed.value = false;

  /// The text of every sheet, a tab between cells and a line per row, for
  /// comparing two versions of a workbook.
  String text() {
    flush();
    final out = StringBuffer();
    for (final sheet in sheets) {
      out.writeln('## ${sheet.name}');
      sheet._text(out);
    }
    return out.toString();
  }

  /// The same text, straight from a file, for versions nobody has open.
  static Future<String?> textOf(Uint8List bytes) async {
    try {
      final book = await read(bytes);
      final text = book.text();
      book.dispose();
      return text;
    } catch (_) {
      return null;
    }
  }

  /// Applies the grid's pending edits now rather than at the end of the
  /// current event.
  void flush() {
    if (_disposed) return;
    _scheduled = false;
    final refs = <String>[];
    for (final sheet in sheets) {
      refs.addAll(sheet._apply());
    }
    if (refs.isEmpty) return;
    _changed.value = true;
    _recalculate(refs);
    _edits.value++;
  }

  /// A size change is not a cell change, so it does not pass through [flush].
  void _resized() {
    _changed.value = true;
    _edits.value++;
  }

  void _schedule() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    scheduleMicrotask(flush);
  }

  void _recalculate(List<String> refs) {
    try {
      _excel.recalculate(changed: refs);
    } catch (e) {
      debugPrint('Workbook recalculation failed: $e');
    }
    for (final sheet in sheets) {
      sheet._refresh();
    }
  }

  void dispose() {
    _disposed = true;
    for (final sheet in sheets) {
      sheet._dispose();
    }
    _changed.dispose();
    _edits.dispose();
  }

  static bool _isSigned(List<int> bytes) {
    try {
      return ZipDecoder()
          .decodeBytes(bytes)
          .files
          .any((file) => file.name.toLowerCase().startsWith('_xmlsignatures/'));
    } catch (_) {
      return false;
    }
  }

  /// Functions Excel has and the engine does not, where a file is known to
  /// use them.
  static void _functions(xl.Excel excel) {
    excel.formula.registerFunction(
      'HYPERLINK',
      (args) => args.length > 1 && args[1] != null
          ? args[1]!
          : args.firstOrNull ?? xl.TextCellValue(''),
    );
  }
}

/// One sheet of a [Workbook]: what the grid edits ([raw], formulas as
/// written) and what it shows ([display], formulas as results).
class WorkbookSheet {
  WorkbookSheet._(this._book, this.name, xl.Sheet sheet)
    : protected = sheet.isProtected,
      rowCount = math.max(1000, sheet.maxRows + 500),
      columnCount = math.max(26, sheet.maxColumns + 10),
      freeze = FreezeConfig(
        frozenRows: sheet.frozenRows,
        frozenColumns: sheet.frozenColumns,
      ) {
    raw = SparseWorksheetData(rowCount: rowCount, columnCount: columnCount);
    _load(sheet);
    display = FormulaResults._(raw);
    for (final coord in _formulas) {
      display._results[coord] = _result(coord, _cached(sheet, coord));
    }
    _subscription = raw.changes.listen(_heard);
  }

  final Workbook _book;
  final String name;
  final bool protected;
  final int rowCount, columnCount;
  final FreezeConfig freeze;
  late final SparseWorksheetData raw;
  late final FormulaResults display;

  /// Widths and heights the file sets, in logical pixels.
  final columnWidths = <int, double>{};
  final rowHeights = <int, double>{};

  late final StreamSubscription<DataChangeEvent> _subscription;
  final _formulas = <CellCoordinate>{};

  /// Cells excel_plus holds for this sheet, so that clearing a range reaches
  /// the ones the grid no longer has.
  final _held = <CellCoordinate>{};
  final _pending = <CellCoordinate>{};
  final _ranges = <CellRange>[];
  final _merges = <(CellRange, bool)>[];

  xl.Sheet get _sheet => _book._excel.tables[name]!;

  void _load(xl.Sheet sheet) {
    for (final row in sheet.rows) {
      for (final data in row) {
        if (data == null) continue;
        final coord = CellCoordinate(data.rowIndex, data.columnIndex);
        _held.add(coord);
        final value = _fromExcel(data.value);
        final style = data.cellStyle;
        final format = style == null ? null : _format(style.numberFormat);
        if (value != null) raw.setCell(coord, value);
        if (value?.isFormula == true) _formulas.add(coord);
        if (format != null) raw.setFormat(coord, format);
        if (style != null) {
          final cellStyle = _cellStyle(style);
          if (cellStyle != null) raw.setStyle(coord, cellStyle);
        }
        final spans = _spans(data.value, style);
        if (spans != null) raw.setRichText(coord, spans);
      }
    }
    for (final merged in sheet.spannedItems) {
      final range = _range(merged);
      if (range != null && range.cellCount > 1) raw.mergeCells(range);
    }
    for (final entry in sheet.getColumnWidths.entries) {
      // Excel measures columns in characters of its default font: seven
      // pixels each, and five of padding.
      columnWidths[entry.key] = entry.value * 7 + 5;
    }
    for (final entry in sheet.getRowHeights.entries) {
      rowHeights[entry.key] = entry.value * 96 / 72;
    }
  }

  /// A column dragged to [pixels] wide, kept in Excel's own unit.
  void resizeColumn(int column, double pixels) {
    columnWidths[column] = pixels;
    _sheet.setColumnWidth(column, math.max(0, (pixels - 5) / 7));
    _book._resized();
  }

  /// A row dragged to [pixels] high, kept in points.
  void resizeRow(int row, double pixels) {
    rowHeights[row] = pixels;
    _sheet.setRowHeight(row, pixels * 72 / 96);
    _book._resized();
  }

  void _heard(DataChangeEvent event) {
    switch (event.type) {
      case DataChangeType.cellValue:
      case DataChangeType.cellStyle:
      case DataChangeType.cellFormat:
        if (event.cell != null) _pending.add(event.cell!);
      case DataChangeType.range:
        if (event.range != null) _ranges.add(event.range!);
      case DataChangeType.merge:
        if (event.range != null) _merges.add((event.range!, true));
      case DataChangeType.unmerge:
        if (event.range != null) _merges.add((event.range!, false));
      case DataChangeType.reset:
        _ranges.add(CellRange(0, 0, rowCount - 1, columnCount - 1));
      case DataChangeType.rowInserted:
      case DataChangeType.rowDeleted:
      case DataChangeType.columnInserted:
      case DataChangeType.columnDeleted:
        // The grid never shifts rows or columns by itself.
        return;
    }
    _book._schedule();
  }

  /// Writes the pending edits to excel_plus. The changed cells, qualified
  /// with the sheet, for recalculation.
  List<String> _apply() {
    if (_pending.isEmpty && _ranges.isEmpty && _merges.isEmpty) return const [];
    final sheet = _sheet;
    for (final (range, merge) in _merges) {
      final start = _index(CellCoordinate(range.startRow, range.startColumn));
      final end = _index(CellCoordinate(range.endRow, range.endColumn));
      try {
        if (merge) {
          sheet.merge(start, end);
        } else {
          sheet.unMerge('${start.cellId}:${end.cellId}');
        }
      } catch (e) {
        debugPrint('Workbook merge failed: $e');
      }
    }
    _merges.clear();
    final cells = {..._pending};
    _pending.clear();
    for (final range in _ranges) {
      cells.addAll(_populatedIn(range));
    }
    _ranges.clear();
    final refs = <String>[];
    for (final coord in cells) {
      _write(sheet, coord);
      refs.add(_qualified(coord));
    }
    return refs;
  }

  Iterable<CellCoordinate> _populatedIn(CellRange range) => {
    for (final entry in raw.getCellsInRange(range)) entry.key,
    for (final entry in raw.getStylesInRange(range)) entry.key,
    for (final entry in raw.getFormatsInRange(range)) entry.key,
    for (final entry in raw.getRichTextInRange(range)) entry.key,
    ..._held.where(range.contains),
  };

  void _write(xl.Sheet sheet, CellCoordinate coord) {
    final index = _index(coord);
    final value = raw.getCell(coord);
    final style = raw.getStyle(coord);
    final format = raw.getFormat(coord);
    final spans = raw.getRichText(coord);
    if (value == null &&
        style == null &&
        format == null &&
        (spans == null || spans.isEmpty)) {
      if (_held.remove(coord)) {
        sheet.updateCell(index, null);
        sheet.cell(index).cellStyle = null;
      }
      _forget(coord);
      return;
    }
    final base = _held.contains(coord) ? sheet.cell(index).cellStyle : null;
    sheet.updateCell(
      index,
      _toExcel(value, spans),
      cellStyle: _excelStyle(base, style, spans, format),
    );
    _held.add(coord);
    if (value?.isFormula == true) {
      _formulas.add(coord);
    } else {
      _forget(coord);
    }
  }

  void _forget(CellCoordinate coord) {
    if (_formulas.remove(coord)) display._set(coord, null);
  }

  /// Formulas with no result in the file, as references to work out.
  List<String> _unresolved() => [
    for (final coord in _formulas)
      if (_cached(_sheet, coord) == null) _qualified(coord),
  ];

  /// Shows every formula's current result.
  void _refresh() {
    final sheet = _sheet;
    for (final coord in _formulas) {
      display._set(coord, _result(coord, _cached(sheet, coord)));
    }
  }

  String? _cached(xl.Sheet sheet, CellCoordinate coord) {
    final value = sheet.cell(_index(coord)).value;
    return value is xl.FormulaCellValue ? value.cachedValue : null;
  }

  CellValue? _result(CellCoordinate coord, String? cached) {
    if (cached == null) return null;
    if (cached.startsWith('#')) return CellValue.error(cached);
    final number = double.tryParse(cached);
    if (number == null) return CellValue.text(cached);
    final format = raw.getFormat(coord);
    // A date is a number of days to Excel, and only its format says so.
    if (format != null &&
        (format.type == CellFormatType.date ||
            format.type == CellFormatType.time)) {
      return CellValue.date(_fromSerial(number));
    }
    return CellValue.number(number);
  }

  String _qualified(CellCoordinate coord) {
    final plain = RegExp(r'^[A-Za-z_][A-Za-z0-9_.]*$').hasMatch(name);
    final sheet = plain ? name : "'${name.replaceAll("'", "''")}'";
    return '$sheet!${coord.toNotation()}';
  }

  void _text(StringBuffer out) {
    final rows = <int, Map<int, String>>{};
    for (final entry in raw.getCellsInRange(
      CellRange(0, 0, rowCount - 1, columnCount - 1),
    )) {
      final shown = display.getCell(entry.key);
      if (shown == null) continue;
      (rows[entry.key.row] ??= {})[entry.key.column] = shown.displayValue;
    }
    for (final row in rows.keys.toList()..sort()) {
      final cells = rows[row]!;
      final last = cells.keys.reduce(math.max);
      out.writeln([for (var c = 0; c <= last; c++) cells[c] ?? ''].join('\t'));
    }
  }

  void _dispose() {
    _subscription.cancel();
    display.dispose();
    raw.dispose();
  }
}

/// What the grid shows: the sheet's cells, with every formula replaced by what
/// it comes to. [Worksheet] still edits the formula, read from the raw data.
class FormulaResults extends DelegatingWorksheetData {
  FormulaResults._(SparseWorksheetData super.inner) {
    _forward = inner.changes.listen(_events.add);
  }

  final _results = <CellCoordinate, CellValue?>{};
  final _events = StreamController<DataChangeEvent>.broadcast();
  late final StreamSubscription<DataChangeEvent> _forward;

  @override
  CellValue? getCell(CellCoordinate coord) {
    final value = inner.getCell(coord);
    if (value == null || !value.isFormula) return value;
    return _results[coord] ?? value;
  }

  /// Typed the way a Turkish Excel shows formulas, kept the way a file needs
  /// them; see [excelFormula].
  @override
  void setCell(CellCoordinate coord, CellValue? value) {
    if (value != null && value.isFormula) {
      value = CellValue.formula(excelFormula(value.rawValue as String));
    }
    inner.setCell(coord, value);
  }

  @override
  Stream<DataChangeEvent> get changes => _events.stream;

  void _set(CellCoordinate coord, CellValue? result) {
    if (_results[coord] == result) return;
    if (result == null) {
      _results.remove(coord);
    } else {
      _results[coord] = result;
    }
    if (!_events.isClosed) _events.add(DataChangeEvent.cellValue(coord));
  }

  @override
  void dispose() {
    _forward.cancel();
    _events.close();
  }
}

xl.CellIndex _index(CellCoordinate coord) => xl.CellIndex.indexByColumnRow(
  columnIndex: coord.column,
  rowIndex: coord.row,
);

CellRange? _range(String span) {
  final parts = span.split(':');
  if (parts.length != 2) return null;
  try {
    final a = CellCoordinate.fromNotation(parts[0].replaceAll(r'$', ''));
    final b = CellCoordinate.fromNotation(parts[1].replaceAll(r'$', ''));
    return CellRange.fromCoordinates(a, b);
  } catch (_) {
    return null;
  }
}

DateTime _fromSerial(double days) => DateTime(
  1899,
  12,
  30,
).add(Duration(milliseconds: (days * 86400000).round()));

CellValue? _fromExcel(xl.CellValue? value) => switch (value) {
  null => null,
  xl.FormulaCellValue(:final formula) => CellValue.formula('=$formula'),
  xl.TextCellValue(:final value) => CellValue.text(value.toString()),
  xl.IntCellValue(:final value) => CellValue.number(value.toDouble()),
  xl.DoubleCellValue(:final value) => CellValue.number(value),
  xl.BoolCellValue(:final value) => CellValue.boolean(value),
  xl.DateCellValue(:final year, :final month, :final day) => CellValue.date(
    DateTime(year, month, day),
  ),
  final xl.DateTimeCellValue v => CellValue.date(
    DateTime(v.year, v.month, v.day, v.hour, v.minute, v.second),
  ),
  final xl.TimeCellValue v => CellValue.duration(
    Duration(hours: v.hour, minutes: v.minute, seconds: v.second),
  ),
  _ => CellValue.text(value.toString()),
};

xl.CellValue? _toExcel(CellValue? value, List<TextSpan>? spans) {
  if (value == null) return null;
  switch (value.type) {
    case CellValueType.formula:
      final formula = value.rawValue as String;
      return xl.FormulaCellValue(
        formula.startsWith('=') ? formula.substring(1) : formula,
      );
    case CellValueType.number:
      final number = value.rawValue as double;
      return number == number.truncateToDouble() && number.abs() < 1e15
          ? xl.IntCellValue(number.toInt())
          : xl.DoubleCellValue(number);
    case CellValueType.boolean:
      return xl.BoolCellValue(value.rawValue as bool);
    case CellValueType.date:
      final date = value.rawValue as DateTime;
      return date.hour == 0 && date.minute == 0 && date.second == 0
          ? xl.DateCellValue.fromDateTime(date)
          : xl.DateTimeCellValue.fromDateTime(date);
    case CellValueType.duration:
      final d = value.rawValue as Duration;
      return xl.TimeCellValue(
        hour: d.inHours,
        minute: d.inMinutes.remainder(60),
        second: d.inSeconds.remainder(60),
      );
    case CellValueType.text:
    case CellValueType.error:
      final text = value.rawValue as String;
      final runs = spans?.where((s) => (s.text ?? '').isNotEmpty).toList();
      // Runs styled differently from one another are written as rich text;
      // one style for the whole cell goes into the cell's style instead.
      if (runs != null && runs.length > 1 && _uniform(runs) == null) {
        return xl.TextCellValue.span(
          xl.TextSpan(
            children: [
              for (final run in runs)
                xl.TextSpan(text: run.text, style: _runStyle(run.style)),
            ],
          ),
        );
      }
      return xl.TextCellValue(text);
  }
}

/// The style every run shares, or null when they differ.
TextStyle? _uniform(List<TextSpan> spans) {
  final first = spans.first.style ?? const TextStyle();
  for (final span in spans.skip(1)) {
    final style = span.style ?? const TextStyle();
    if (style.fontWeight != first.fontWeight ||
        style.fontStyle != first.fontStyle ||
        style.decoration != first.decoration ||
        style.color != first.color ||
        style.fontSize != first.fontSize ||
        style.fontFamily != first.fontFamily) {
      return null;
    }
  }
  return first;
}

xl.CellStyle? _runStyle(TextStyle? style) {
  if (style == null) return null;
  return xl.CellStyle(
    bold: style.fontWeight == FontWeight.bold,
    italic: style.fontStyle == FontStyle.italic,
    underline: _underlined(style) ? xl.Underline.Single : xl.Underline.None,
    fontColorHex: style.color == null
        ? xl.ExcelColor.black
        : _excelColor(style.color!),
    fontSize: style.fontSize == null
        ? null
        : (style.fontSize! * 72 / 96).round(),
    fontFamily: style.fontFamily,
  );
}

bool _underlined(TextStyle style) =>
    style.decoration?.contains(TextDecoration.underline) == true;

/// The cell-wide text style of [spans]: a single empty span carries it for
/// the whole cell, and runs that all look alike say the same.
TextStyle? _cellText(List<TextSpan>? spans) {
  if (spans == null || spans.isEmpty) return null;
  if (spans.length == 1) return spans.single.style;
  final runs = spans.where((s) => (s.text ?? '').isNotEmpty).toList();
  return runs.isEmpty ? spans.first.style : _uniform(runs);
}

List<TextSpan>? _spans(xl.CellValue? value, xl.CellStyle? style) {
  if (value is xl.TextCellValue) {
    final runs = <TextSpan>[];
    void collect(xl.TextSpan span, xl.CellStyle? inherited) {
      final own = span.style ?? inherited;
      if (span.text != null && span.text!.isNotEmpty) {
        runs.add(TextSpan(text: span.text, style: _textStyle(own ?? style)));
      }
      for (final child in span.children ?? const <xl.TextSpan>[]) {
        collect(child, own);
      }
    }

    collect(value.value, null);
    final styled = runs.where((r) => r.style != null).length;
    if (runs.length > 1 && styled > 0) return runs;
  }
  final cell = style == null ? null : _textStyle(style);
  return cell == null ? null : [TextSpan(text: '', style: cell)];
}

/// The font side of an Excel style, with the defaults left out so the grid's
/// own apply.
TextStyle? _textStyle(xl.CellStyle? style) {
  if (style == null) return null;
  final color = _color(style.fontColor);
  final size = style.fontSize;
  final family = style.fontFamily;
  final underline = style.underline != xl.Underline.None;
  final black = color == null || color == const Color(0xFF000000);
  if (!style.isBold &&
      !style.isItalic &&
      !underline &&
      black &&
      (size == null || size == 11) &&
      (family == null || family == 'Calibri')) {
    return null;
  }
  return TextStyle(
    fontWeight: style.isBold ? FontWeight.bold : null,
    fontStyle: style.isItalic ? FontStyle.italic : null,
    decoration: underline ? TextDecoration.underline : null,
    color: black ? null : color,
    fontSize: size == null || size == 11 ? null : size * 96 / 72,
    fontFamily: family == null || family == 'Calibri' ? null : family,
  );
}

CellStyle? _cellStyle(xl.CellStyle style) {
  final fill = _color(style.backgroundColor);
  final align = switch (style.horizontalAlignment) {
    xl.HorizontalAlign.Center => CellTextAlignment.center,
    xl.HorizontalAlign.Right => CellTextAlignment.right,
    // Excel's default puts numbers right and text left, which is what the
    // grid does when told nothing; an explicit left is not told apart from it.
    xl.HorizontalAlign.Left => null,
  };
  final vertical = switch (style.verticalAlignment) {
    xl.VerticalAlign.Top => CellVerticalAlignment.top,
    xl.VerticalAlign.Center => CellVerticalAlignment.middle,
    xl.VerticalAlign.Bottom => CellVerticalAlignment.bottom,
  };
  final wrap = style.wrap == xl.TextWrapping.WrapText ? true : null;
  final borders = _borders(style);
  return CellStyle(
    backgroundColor: fill,
    textAlignment: align,
    verticalAlignment: vertical,
    wrapText: wrap,
    borders: borders,
  );
}

CellBorders? _borders(xl.CellStyle style) {
  BorderStyle side(xl.Border border) {
    final (width, line) = switch (border.borderStyle) {
      null || xl.BorderStyle.None => (0.0, BorderLineStyle.none),
      xl.BorderStyle.Dotted ||
      xl.BorderStyle.Hair => (1.0, BorderLineStyle.dotted),
      xl.BorderStyle.Dashed ||
      xl.BorderStyle.DashDot ||
      xl.BorderStyle.DashDotDot ||
      xl.BorderStyle.SlantDashDot => (1.0, BorderLineStyle.dashed),
      xl.BorderStyle.MediumDashed ||
      xl.BorderStyle.MediumDashDot ||
      xl.BorderStyle.MediumDashDotDot => (2.0, BorderLineStyle.dashed),
      xl.BorderStyle.Double => (3.0, BorderLineStyle.double),
      xl.BorderStyle.Medium => (2.0, BorderLineStyle.solid),
      xl.BorderStyle.Thick => (3.0, BorderLineStyle.solid),
      _ => (1.0, BorderLineStyle.solid),
    };
    if (line == BorderLineStyle.none) return BorderStyle.none;
    final hex = border.borderColorHex;
    final color = hex == null ? null : _color(xl.ExcelColor.fromHexString(hex));
    return BorderStyle(
      width: width,
      lineStyle: line,
      color: color ?? const Color(0xFF000000),
    );
  }

  final borders = CellBorders(
    top: side(style.topBorder),
    right: side(style.rightBorder),
    bottom: side(style.bottomBorder),
    left: side(style.leftBorder),
  );
  final none =
      borders.top == BorderStyle.none &&
      borders.right == BorderStyle.none &&
      borders.bottom == BorderStyle.none &&
      borders.left == BorderStyle.none;
  return none ? null : borders;
}

xl.Border _excelBorder(BorderStyle side) {
  if (side.lineStyle == BorderLineStyle.none || side.width <= 0) {
    return xl.Border(borderStyle: xl.BorderStyle.None);
  }
  final style = switch (side.lineStyle) {
    BorderLineStyle.dotted => xl.BorderStyle.Dotted,
    BorderLineStyle.dashed =>
      side.width >= 2 ? xl.BorderStyle.MediumDashed : xl.BorderStyle.Dashed,
    BorderLineStyle.double => xl.BorderStyle.Double,
    _ =>
      side.width >= 3
          ? xl.BorderStyle.Thick
          : side.width >= 2
          ? xl.BorderStyle.Medium
          : xl.BorderStyle.Thin,
  };
  return xl.Border(borderStyle: style, borderColorHex: _excelColor(side.color));
}

Color? _color(xl.ExcelColor color) {
  final hex = color.colorHex;
  if (hex == 'none' || hex.isEmpty) return null;
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return null;
  return Color(hex.length <= 6 ? value | 0xFF000000 : value);
}

xl.ExcelColor _excelColor(Color color) => xl.ExcelColor.fromHexString(
  color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase(),
);

CellFormat? _format(xl.NumFormat format) {
  final code = format.formatCode;
  if (code.isEmpty || code.toLowerCase() == 'general') return null;
  return CellFormat(type: _formatType(code), formatCode: code);
}

CellFormatType _formatType(String code) {
  // Quoted text and escapes are not letters of a date.
  final bare = code
      .replaceAll(RegExp(r'"[^"]*"'), '')
      .replaceAll(RegExp(r'\\.'), '')
      .replaceAll(RegExp(r'\[[^\]]*\]'), '')
      .toLowerCase();
  if (bare.contains('%')) return CellFormatType.percentage;
  if (RegExp('[dy]').hasMatch(bare)) return CellFormatType.date;
  if (RegExp('[hs]').hasMatch(bare) || bare.contains('am/pm')) {
    return CellFormatType.time;
  }
  if (bare.contains('m') && !bare.contains('0') && !bare.contains('#')) {
    return CellFormatType.date;
  }
  if (bare == '@') return CellFormatType.text;
  return CellFormatType.number;
}

/// [base] with what the grid can change set from it: fill, alignment,
/// wrapping, borders, the font of the whole cell and the number format.
/// Everything else the file set on the cell stays as it was.
xl.CellStyle _excelStyle(
  xl.CellStyle? base,
  CellStyle? style,
  List<TextSpan>? spans,
  CellFormat? format,
) {
  final start = base ?? xl.CellStyle();
  final text = _cellText(spans) ?? const TextStyle();
  final borders = style?.borders;
  final numberFormat = format == null
      ? xl.NumFormat.standard_0
      : format.formatCode == start.numberFormat.formatCode
      ? start.numberFormat
      : xl.NumFormat.custom(formatCode: format.formatCode);
  return start.copyWith(
    backgroundColorHexVal: style?.backgroundColor == null
        ? xl.ExcelColor.none
        : _excelColor(style!.backgroundColor!),
    horizontalAlignVal: switch (style?.textAlignment) {
      CellTextAlignment.center => xl.HorizontalAlign.Center,
      CellTextAlignment.right => xl.HorizontalAlign.Right,
      _ => xl.HorizontalAlign.Left,
    },
    verticalAlignVal: switch (style?.verticalAlignment) {
      CellVerticalAlignment.top => xl.VerticalAlign.Top,
      CellVerticalAlignment.middle => xl.VerticalAlign.Center,
      _ => xl.VerticalAlign.Bottom,
    },
    textWrappingVal: style?.wrapText == true
        ? xl.TextWrapping.WrapText
        : xl.TextWrapping.Clip,
    boldVal: text.fontWeight == FontWeight.bold,
    italicVal: text.fontStyle == FontStyle.italic,
    underlineVal: _underlined(text) ? xl.Underline.Single : xl.Underline.None,
    fontColorHexVal: text.color == null
        ? xl.ExcelColor.black
        : _excelColor(text.color!),
    fontSizeVal: text.fontSize == null
        ? start.fontSize
        : (text.fontSize! * 72 / 96).round(),
    fontFamilyVal: text.fontFamily ?? start.fontFamily,
    leftBorderVal: borders == null ? xl.Border() : _excelBorder(borders.left),
    rightBorderVal: borders == null ? xl.Border() : _excelBorder(borders.right),
    topBorderVal: borders == null ? xl.Border() : _excelBorder(borders.top),
    bottomBorderVal: borders == null
        ? xl.Border()
        : _excelBorder(borders.bottom),
    numberFormat: numberFormat,
  );
}

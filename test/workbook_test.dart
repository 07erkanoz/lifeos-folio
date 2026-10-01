import 'dart:typed_data';

import 'package:evrak_convert/services/spreadsheet/formula_locale.dart';
import 'package:evrak_convert/services/spreadsheet/workbook.dart';
import 'package:excel_plus/excel_plus.dart' as xl;
import 'package:flutter/painting.dart' hide BorderStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:worksheet/worksheet.dart';

Uint8List _sample() {
  final excel = xl.Excel.createExcel();
  excel.rename(excel.getDefaultSheet()!, 'Hesap');
  final hesap = excel['Hesap'];
  xl.CellIndex at(String ref) => xl.CellIndex.indexByString(ref);
  hesap.updateCell(
    at('A1'),
    xl.IntCellValue(2),
    cellStyle: xl.CellStyle(
      bold: true,
      backgroundColorHex: xl.ExcelColor.fromHexString('FFFFFF00'),
    ),
  );
  hesap.updateCell(at('A2'), xl.IntCellValue(3));
  hesap.updateCell(at('A3'), xl.FormulaCellValue('SUM(A1:A2)'));
  hesap.updateCell(at('B1'), xl.TextCellValue('Başlık'));
  hesap.merge(at('B1'), at('C1'));
  final ozet = excel['Özet Tablo'];
  ozet.updateCell(at('A1'), xl.FormulaCellValue('Hesap!A3*2'));
  return Uint8List.fromList(excel.encode()!);
}

const _a1 = CellCoordinate(0, 0),
    _a2 = CellCoordinate(1, 0),
    _a3 = CellCoordinate(2, 0),
    _a4 = CellCoordinate(3, 0);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('Turkish formulas are kept the way a file needs them', () {
    expect(excelFormula('=TOPLA(A1;A9)'), '=SUM(A1,A9)');
    expect(
      excelFormula('=EĞER(B2>0;"evet;hayır";YUVARLA(B2;2))'),
      '=IF(B2>0,"evet;hayır",ROUND(B2,2))',
    );
    expect(excelFormula('=SUM(A1:A9)'), '=SUM(A1:A9)');
    expect(excelFormula('=INDEX({1,2;3,4},2,1)'), '=INDEX({1,2;3,4},2,1)');
    expect(excelFormula('=düşeyara(A1;B:C;2;0)'), '=VLOOKUP(A1,B:C,2,0)');
  });

  test('a workbook shows results, recomputes what an edit reaches, and '
      'writes back what it read', () async {
    final book = await Workbook.read(_sample());
    addTearDown(book.dispose);
    expect(book.sheets.map((s) => s.name), ['Hesap', 'Özet Tablo']);
    final hesap = book.sheets.first, ozet = book.sheets.last;

    // Formulas the file saved without results are worked out on reading.
    expect(hesap.raw.getCell(_a3), CellValue.formula('=SUM(A1:A2)'));
    expect(hesap.display.getCell(_a3), CellValue.number(5));
    expect(ozet.display.getCell(_a1), CellValue.number(10));
    // The font of the cell and its fill.
    expect(
      hesap.raw.getRichText(_a1)?.single.style?.fontWeight,
      FontWeight.bold,
    );
    expect(hesap.raw.getStyle(_a1)?.backgroundColor, const Color(0xFFFFFF00));
    expect(
      hesap.raw.mergedCells.getRegion(const CellCoordinate(0, 1))?.range,
      const CellRange(0, 1, 0, 2),
    );
    expect(book.changed.value, isFalse);

    // An edit as the grid makes it: through what it shows.
    hesap.display.setCell(_a1, CellValue.number(10));
    await _settle();
    expect(hesap.display.getCell(_a3), CellValue.number(13));
    expect(ozet.display.getCell(_a1), CellValue.number(26));
    expect(book.changed.value, isTrue);

    // Typed the Turkish way.
    hesap.display.setCell(_a4, CellValue.formula('=TOPLA(A1;A2)'));
    await _settle();
    expect(hesap.raw.getCell(_a4), CellValue.formula('=SUM(A1,A2)'));
    expect(hesap.display.getCell(_a4), CellValue.number(13));

    // Clearing a cell reaches the formulas that read it.
    hesap.raw.clearRange(CellRange.single(_a2));
    await _settle();
    expect(hesap.display.getCell(_a3), CellValue.number(10));

    final saved = xl.Excel.decodeBytes(await book.write());
    final sheet = saved['Hesap'];
    xl.Data cell(String ref) => sheet.cell(xl.CellIndex.indexByString(ref));
    expect(cell('A1').value, xl.IntCellValue(10));
    expect(cell('A1').cellStyle?.isBold, isTrue);
    expect(cell('A1').cellStyle?.backgroundColor.colorHex, 'FFFFFF00');
    expect(cell('A2').value, isNull);
    final sum = cell('A3').value as xl.FormulaCellValue;
    expect(sum.formula, 'SUM(A1:A2)');
    expect(sum.cachedValue, '10');
    expect((cell('A4').value as xl.FormulaCellValue).formula, 'SUM(A1,A2)');
    expect(sheet.spannedItems, contains('B1:C1'));
    expect(
      (saved['Özet Tablo']
                  .cell(xl.CellIndex.indexByString('A1'))
                  .value
              as xl.FormulaCellValue)
          .cachedValue,
      '20',
    );
  });
}

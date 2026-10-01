import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/spreadsheet/xlsx_workbook.dart';
import 'package:evrak_convert/services/search/index_service.dart';
import 'package:evrak_convert/services/search/search_models.dart';

import 'fixtures/xlsx_fixture.dart';

void main() {
  test('XLSX reads sheets, rich strings and number formats without changing inputs', () {
    final book = XlsxWorkbook.read(xlsxFixture());
    expect(book.sheets.map((s) => s.name), ['Hesaplar', 'Notlar']);
    final cells = book.sheets.first.cells;
    expect(cells['A1']!.value, 'Erkan ÖZ');
    expect(cells['A1']!.bold, true);
    expect(cells['A1']!.fill, 'FFE1F0E8');
    expect(cells['C1']!.input, '=B1*2');
    expect(cells['C1']!.value, '24');
    expect(cells['A2']!.value, '01.01.2026');
    expect(cells['A2']!.input, '46023');
    expect(cells['B2']!.value, '12,50%');
    expect(book.text(), contains('İhtiyati haciz'));
  });
  test(
    'XLSX saves values, additions, formulas and keeps unrelated OOXML parts',
    () {
      final source = XlsxWorkbook.read(xlsxFixture());
      final book = XlsxWorkbook.read(
        source.write({
          '0:B1': '25',
          '0:E10': ' Yeni hücre ',
          '1:A1': 'İtiraz kabul edildi',
          '1:D2': '=SUM(Hesaplar!B1,3)',
        }),
      );
      expect(book.sheets[0].cells['B1']!.value, '25');
      expect(book.sheets[0].cells['E10']!.value, ' Yeni hücre ');
      expect(book.sheets[1].cells['D2']!.input, '=SUM(Hesaplar!B1,3)');
      expect(book.sheets[0].cells['C1']!.value, isEmpty);
      expect(book.sheets[1].cells['B1']!.value, isEmpty);
      for (final path in [
        'xl/styles.xml',
        'xl/sharedStrings.xml',
        'xl/drawings/drawing1.xml',
        'docProps/custom.xml',
      ]) {
        expect(book.parts[path], source.parts[path]);
      }
      expect(
        utf8.decode(book.parts['xl/worksheets/sheet1.xml']!),
        contains('ref="C3:D3"'),
      );
      expect(book.parts.containsKey('xl/calcChain.xml'), false);
      expect(
        utf8.decode(book.parts['xl/workbook.xml']!),
        contains('fullCalcOnLoad="1"'),
      );
      expect(source.sheets[0].cells['B1']!.value, '12');
      expect(() => source.write({'0:A4': '3'}), throwsFormatException);
      expect(
        () =>
            XlsxWorkbook.read(xlsxFixture(protected: true))
                .write({'0:B1': '4'}),
        throwsFormatException,
      );
      expect(
        () => XlsxWorkbook.read(xlsxFixture(signed: true)).write({'1:A1': '4'}),
        throwsFormatException,
      );
    },
  );
  test('persistent index discovers, searches and refreshes XLSX content across every sheet', () async {
    final dir = await Directory.systemTemp.createTemp('folio-xlsx-index-');
    IndexService? service;
    try {
      final docs = await Directory('${dir.path}/documents').create();
      final file = File('${docs.path}/Mali hesaplar.xlsx');
      await file.writeAsBytes(xlsxFixture());
      service = await IndexService.open('${dir.path}/index.sqlite');
      await service.request('add', {
        'paths': [docs.path],
        'recursive': true,
      });
      await service.waitForIdle();
      final result = await service.search(
        const SearchQuery(text: 'ihtiyati haciz', extensions: ['xlsx']),
      );
      expect(result.total, 1);
      expect(result.hits.single.file.format, EvrakFormat.spreadsheet);
      expect(result.hits.single.excerpt, contains('haciz'));
      expect(
        (await service.search(const SearchQuery(text: 'Mali hesaplar'))).total,
        1,
      );
      expect(
        (await service.search(const SearchQuery(text: 'erkan oz'))).total,
        1,
      );
      await file.writeAsBytes(
        XlsxWorkbook.read(xlsxFixture())
            .write({'1:A1': 'Kesinleşmiş tahsilat çizelgesi'}),
      );
      await service.request('refresh');
      await service.waitForIdle();
      expect(
        (await service.search(const SearchQuery(text: 'ihtiyati haciz'))).total,
        0,
      );
      expect(
        (await service.search(const SearchQuery(text: 'kesinlesmis tahsilat')))
            .total,
        1,
      );
      await service.close();
      service = await IndexService.open('${dir.path}/index.sqlite');
      expect(
        (await service.search(const SearchQuery(text: 'tahsilat'))).total,
        1,
      );
      expect((await service.request<Map>('catalog'))['pending'], 0);
    } finally {
      await service?.close();
      await dir.delete(recursive: true);
    }
  });
}

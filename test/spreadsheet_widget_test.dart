import 'dart:io';

import 'package:excel_plus/excel_plus.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/main.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/editor/editor_drafts.dart';
import 'package:evrak_convert/services/spreadsheet/xlsx_workbook.dart';
import 'package:evrak_convert/ui/widgets/spreadsheet_editor.dart';
import 'package:evrak_convert/ui/widgets/spreadsheet_viewer.dart';
import 'package:worksheet/worksheet.dart' show Worksheet;

import 'fixtures/xlsx_fixture.dart';
import 'editor_drafts_test.dart' as helpers;
import 'support/temp_directory.dart';

/// Taps the cell at [row], [column] of the grid on screen, at its default
/// size: 46 pixels of row numbers, 72 per column, 22 per row.
Future<void> _tapCell(WidgetTester tester, int row, int column) async {
  final grid = tester.getTopLeft(find.byType(Worksheet));
  await tester.tapAt(grid + Offset(46 + 72.0 * column + 30, 22 + 22.0 * row + 11));
  await tester.pump();
}

Future<T> _pumped<T>(WidgetTester tester, Future<T> Function() action) async {
  var done = false;
  late T value;
  Object? error;
  action().then(
    (result) {
      value = result;
      done = true;
    },
    onError: (Object e) {
      error = e;
      done = true;
    },
  );
  await helpers.ready(tester, () => done);
  if (error != null) throw error!;
  return value;
}

Future<void> _type(WidgetTester tester, String text) async {
  final bar = find.byKey(const ValueKey('formula-bar'));
  await tester.tap(bar);
  await tester.pump();
  await tester.enterText(bar, text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
}

void main() {
  for (final width in [1200.0, 390.0]) {
    testWidgets('XLSX preview, edit, Ctrl+S and unsaved exit at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('folio-xlsx-ui-'),
      ))!;
      final history = DocumentHistory.instance;
      DocumentHistory.instance = DocumentHistory(
        directory: Directory('${dir.path}/history'),
      );
      addTearDown(() => DocumentHistory.instance = history);
      final file = File('${dir.path}/Hesaplar.xlsx');
      await tester.runAsync(() => file.writeAsBytes(xlsxFixture()));
      await tester.pumpWidget(EvrakConvertApp(initialPaths: [file.path]));
      await helpers.ready(
        tester,
        () => find.text('Hesaplar').evaluate().isNotEmpty,
      );
      expect(
        tester
            .widget<SpreadsheetViewer>(find.byType(SpreadsheetViewer))
            .readOnly,
        true,
      );
      await helpers.click(tester, 'Notlar');
      final search = find.widgetWithText(TextField, 'Hücrelerde ara…');
      await tester.enterText(search, 'ihtiyati');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('İhtiyati haciz değerlendirmesi'), findsWidgets);
      await helpers.click(tester, 'Düzenle');
      // excel_plus rejects this synthetic styles.xml, so the editor falls
      // back to the plain one, which patches the file in place.
      await helpers.ready(
        tester,
        () => find.byTooltip('Kaydet · Ctrl+S').evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(SpreadsheetEditor), findsOneWidget);
      expect(find.textContaining('basit editörle açıldı'), findsOneWidget);
      final editor = tester.widget<SpreadsheetViewer>(
        find.byType(SpreadsheetViewer),
      );
      expect(editor.readOnly, false);
      final value = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Değer veya =formül',
      );
      await tester.enterText(value, 'Güncellenmiş hesap');
      expect(editor.draft!.hasChanges, true);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await helpers.ready(tester, () => !editor.draft!.hasChanges);
      final saved = await tester.runAsync(
        () async => XlsxWorkbook.read(await file.readAsBytes()),
      );
      expect(saved!.sheets[0].cells['A1']!.value, 'Güncellenmiş hesap');
      await tester.enterText(value, 'Kaydedilmeyecek');
      await helpers.click(tester, width < 600 ? 'Önizleme' : 'Önizlemeye Dön');
      expect(find.text('Değişiklikler kaydedilsin mi?'), findsOneWidget);
      await helpers.click(tester, 'Kaydetmeden çık');
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Güncellenmiş hesap'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 350));
      await removeTemporaryDirectory(tester, dir);
    });
  }

  testWidgets('a formula typed the Turkish way is worked out, and a bold '
      'cell is saved bold, in the same file', (tester) async {
    tester.view.physicalSize = const Size(1300, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-xlsx-editor-'),
    ))!;
    final history = DocumentHistory.instance;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    addTearDown(() => DocumentHistory.instance = history);
    final file = File('${dir.path}/Masraf.xlsx');
    final source = xl.Excel.createExcel();
    source[source.getDefaultSheet()!].updateCell(
      xl.CellIndex.indexByString('A1'),
      xl.IntCellValue(10),
    );
    await tester.runAsync(() => file.writeAsBytes(source.encode()!));
    final draft = EditorDraft('Masraf.xlsx');
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SpreadsheetEditor(path: file.path, draft: draft),
        ),
      ),
    );
    await helpers.ready(tester, () => find.byType(Worksheet).evaluate().isNotEmpty);
    expect(draft.hasChanges, isFalse);

    await _tapCell(tester, 1, 1);
    await _type(tester, '=TOPLA(A1;5)');
    await helpers.ready(tester, () => draft.hasChanges);
    await tester.tap(find.byKey(const ValueKey('sheet-bold')));
    await tester.pump();
    // Waited for while pumping: the history's queue has the editor's own
    // work ahead of the save, and that only moves when the test pumps.
    expect(await _pumped(tester, () => draft.save!()), isTrue);
    await helpers.ready(tester, () => !draft.hasChanges);

    final saved = xl.Excel.decodeBytes(
      (await tester.runAsync(file.readAsBytes))!,
    );
    final b2 = saved[saved.getDefaultSheet()!].cell(
      xl.CellIndex.indexByString('B2'),
    );
    final formula = b2.value as xl.FormulaCellValue;
    expect(formula.formula, 'SUM(A1,5)');
    expect(formula.cachedValue, '15');
    expect(b2.cellStyle?.isBold, isTrue);
    final versions = await _pumped(
      tester,
      () => DocumentHistory.instance.versions(
        DocumentHistory.documentKey(file.path),
      ),
    );
    expect(versions.map((v) => v.kind), containsAll(['saved', 'original']));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 350));
    await removeTemporaryDirectory(tester, dir);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}

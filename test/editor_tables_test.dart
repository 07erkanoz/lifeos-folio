import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/doc_delta_map.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/editor_paged_table.dart';
import 'package:evrak_convert/ui/widgets/editor_table_embed.dart';
import 'package:evrak_convert/ui/widgets/editor_toolbar.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';

import 'editor_shortcuts_test.dart' show shortcut, waitFor;

DocTableCell _cell(String text) =>
    DocTableCell(blocks: [DocBlock(plainText: text)]);

DocModel _withTable() => DocModel(
  blocks: [
    DocBlock(plainText: 'Taraflar'),
    DocBlock(
      type: DocBlockType.table,
      plainText: '',
      table: DocTable(
        columnWidths: const [120, 240],
        rows: [
          DocTableRow(isHeader: true, cells: [_cell('Sıfat'), _cell('Ad')]),
          DocTableRow(cells: [_cell('Davacı'), _cell('Özlem Şenoğlu')]),
        ],
      ),
    ),
    DocBlock(plainText: 'Saygılarımla'),
  ],
);

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    FlutterQuillLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

Future<File> _file(WidgetTester tester, DocModel model, String prefix) async {
  final dir = (await tester.runAsync(
    () => Directory.systemTemp.createTemp(prefix),
  ))!;
  DocumentHistory.instance = DocumentHistory(
    directory: Directory('${dir.path}/history'),
  );
  final file = File('${dir.path}/belge.udf');
  await tester.runAsync(() => file.writeAsBytes(UdfWriter.writeBytes(model)));
  return file;
}

QuillController _body(WidgetTester tester) => tester
    .widgetList<QuillEditor>(find.byType(QuillEditor))
    .firstWhere((e) => e.focusNode.debugLabel == 'document-editor')
    .controller;

void main() {
  test('a table reaches the editor as a table, not a label', () {
    final mapped = DocDeltaMap.modeldenDelta(_withTable());
    final embed = mapped.delta.toList().firstWhere((op) => op.data is Map);
    expect((embed.data as Map)[DocDeltaMap.kTableEmbed], 0);
    expect(mapped.korunanlar.single.table!.rows.length, 2);
    expect(
      mapped.delta.toList().any(
        (op) => op.data is String && (op.data as String).contains('Tablo'),
      ),
      isFalse,
      reason: 'yer tutucu metin kalmamalı',
    );
  });

  test('a table survives the trip to the editor and back', () {
    final model = _withTable();
    final mapped = DocDeltaMap.modeldenDelta(model);
    final back = DocDeltaMap.deltadanModel(
      mapped.delta,
      korunanlar: mapped.korunanlar,
    );
    expect(back.blocks.map((b) => b.type), [
      DocBlockType.paragraph,
      DocBlockType.table,
      DocBlockType.paragraph,
    ]);
    final table = back.blocks[1].table!;
    expect(table.rows.first.isHeader, isTrue);
    expect(table.columnWidths, [120, 240]);
    expect(table.rows[1].cells[1].blocks.single.plainText, 'Özlem Şenoğlu');
  });

  test('deleting the table in the editor deletes it from the document', () {
    final mapped = DocDeltaMap.modeldenDelta(_withTable());
    final kept = Delta();
    for (final op in mapped.delta.toList()) {
      if (op.data is Map) continue;
      kept.insert(op.data, op.attributes);
    }
    final back = DocDeltaMap.deltadanModel(kept, korunanlar: mapped.korunanlar);
    expect(back.blocks.any((b) => b.type == DocBlockType.table), isFalse);
  });

  test('a draft written by the old placeholder still opens', () {
    // Recovery files from before tables were drawn carry the index as a block
    // attribute on the line instead of an embed.
    final mapped = DocDeltaMap.modeldenDelta(_withTable());
    final old = Delta()
      ..insert('Taraflar\n')
      ..insert('〔Tablo 1 — kaydetmede korunur〕')
      ..insert('\n', {DocDeltaMap.kKorunanAttr: 0});
    final back = DocDeltaMap.deltadanModel(old, korunanlar: mapped.korunanlar);
    expect(back.blocks.last.type, DocBlockType.table);
  });

  testWidgets('a table is drawn and its cells are typed in', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = await _file(tester, _withTable(), 'editor-table-');

    await tester.pumpWidget(
      _app(
        EditorWidget(
          initialFilePath: file.path,
          initialFormat: EvrakFormat.udf,
        ),
      ),
    );
    await waitFor(
      tester,
      () => find.byType(EditorTableView).evaluate().isNotEmpty,
    );
    // Drawn as a real table, with a cell editor per cell.
    expect(find.byType(EditorPagedTable), findsOneWidget);
    final cells = tester
        .widgetList<QuillEditor>(find.byType(QuillEditor))
        .where((e) => e.focusNode.debugLabel == 'table-cell')
        .toList();
    expect(cells.length, 4);
    expect(cells.map((e) => e.controller.document.toPlainText().trim()), [
      'Sıfat',
      'Ad',
      'Davacı',
      'Özlem Şenoğlu',
    ]);

    final name = cells[3].controller;
    name.replaceText(
      0,
      name.document.length - 1,
      'Çiğdem Şenoğlu',
      const TextSelection.collapsed(offset: 16),
    );
    await tester.pump();

    _body(tester); // The body editor is still reachable beside the cells.
    tester
        .widgetList<QuillEditor>(find.byType(QuillEditor))
        .firstWhere((e) => e.focusNode.debugLabel == 'document-editor')
        .focusNode
        .requestFocus();
    await tester.pump();
    await shortcut(tester, LogicalKeyboardKey.keyS);
    await waitFor(
      tester,
      () => find.textContaining('Başarıyla kaydedildi:').evaluate().isNotEmpty,
    );
    final saved = (await tester.runAsync(
      () async => UdfReader.readFile(file.path),
    ))!;
    expect(saved.toPlainText(), contains('Çiğdem Şenoğlu'));
    expect(saved.toPlainText(), contains('Sıfat | Ad'));
    expect(saved.toPlainText(), startsWith('Taraflar'));
    await tester.pumpAndSettle();
  });

  testWidgets('the document editor leaves the keyboard to the cell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = await _file(tester, _withTable(), 'editor-keyboard-');

    await tester.pumpWidget(
      _app(
        EditorWidget(
          initialFilePath: file.path,
          initialFormat: EvrakFormat.udf,
        ),
      ),
    );
    await waitFor(
      tester,
      () => find.byType(EditorTableView).evaluate().isNotEmpty,
    );

    QuillRawEditorState editor(String label) => tester
        .stateList<QuillRawEditorState>(find.byType(QuillRawEditor))
        .firstWhere((st) => st.widget.config.focusNode.debugLabel == label);

    tester
        .widgetList<QuillEditor>(find.byType(QuillEditor))
        .firstWhere((e) => e.focusNode.debugLabel == 'document-editor')
        .focusNode
        .requestFocus();
    await tester.pump();
    expect(editor('document-editor').hasConnection, isTrue);

    // Put the cursor in a cell.
    await tester.tap(
      find
          .byWidgetPredicate(
            (w) => w is QuillEditor && w.focusNode.debugLabel == 'table-cell',
          )
          .first,
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(editor('table-cell').hasConnection, isTrue);
    expect(editor('document-editor').hasConnection, isFalse);

    // On a desktop Quill asks for the keyboard again on every change and
    // every selection it notices, and it grants the request whenever its own
    // focus node reports focus. A focused cell sits under that node, so the
    // document editor used to answer yes, take the platform's text input
    // back, and collect what was being typed into the cell.
    editor('document-editor').requestKeyboard();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      editor('document-editor').hasConnection,
      isFalse,
      reason: 'the document editor took the keyboard back from the cell',
    );
    expect(editor('table-cell').hasConnection, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('a table is taken out of the document from its controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = await _file(tester, _withTable(), 'editor-table-delete-');

    await tester.pumpWidget(
      _app(
        EditorWidget(
          initialFilePath: file.path,
          initialFormat: EvrakFormat.udf,
        ),
      ),
    );
    await waitFor(
      tester,
      () => find.byType(EditorTableView).evaluate().isNotEmpty,
    );

    // The controls only show once the cursor is in the table.
    tester
        .widgetList<QuillEditor>(find.byType(QuillEditor))
        .firstWhere((e) => e.focusNode.debugLabel == 'table-cell')
        .focusNode
        .requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Tabloyu sil'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(EditorTableView), findsNothing);

    // And it is gone from the file too, with the text around it kept.
    await shortcut(tester, LogicalKeyboardKey.keyS);
    await waitFor(
      tester,
      () => find.textContaining('Başarıyla kaydedildi:').evaluate().isNotEmpty,
    );
    final saved = (await tester.runAsync(
      () async => UdfReader.readFile(file.path),
    ))!;
    expect(saved.blocks.any((b) => b.type == DocBlockType.table), isFalse);
    expect(saved.toPlainText(), contains('Taraflar'));
    expect(saved.toPlainText(), contains('Saygılarımla'));
    expect(saved.toPlainText(), isNot(contains('Özlem Şenoğlu')));
    await tester.pumpAndSettle();
  });

  testWidgets('a cell keeps its own keys, and keeps the toolbar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = await _file(tester, _withTable(), 'editor-cell-keys-');

    await tester.pumpWidget(
      _app(
        EditorWidget(
          initialFilePath: file.path,
          initialFormat: EvrakFormat.udf,
        ),
      ),
    );
    await waitFor(
      tester,
      () => find.byType(EditorTableView).evaluate().isNotEmpty,
    );

    final cellFinder = find.byWidgetPredicate(
      (w) => w is QuillEditor && w.focusNode.debugLabel == 'table-cell',
    );
    QuillController cell() =>
        tester.widget<QuillEditor>(cellFinder.first).controller;
    String docText() => _body(tester).document.toPlainText();
    final documentBefore = docText();

    await tester.tap(cellFinder.first, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Delete at the end of a cell reaches nothing. Quill registers its
    // delete with Action.overridable, which prefers a handler from the
    // widgets above it, and a cell is drawn inside the document's editor:
    // the document's handler measured what to remove against the document
    // and the result was written into the cell, filling it with the whole
    // document.
    cell().updateSelection(
      TextSelection.collapsed(offset: cell().document.length - 1),
      ChangeSource.local,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(cell().document.toPlainText().trim(), 'Sıfat');
    expect(docText(), documentBefore);

    // Inside the cell it still deletes, and only there.
    cell().updateSelection(
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(cell().document.toPlainText().trim(), 'ıfat');
    expect(docText(), documentBefore);

    // Picking a font opens a dialog, which takes the focus off the cell. The
    // toolbar has to go on pointing at the cell it was last in, or nothing
    // inside a table can be restyled.
    cell().updateSelection(
      TextSelection(baseOffset: 0, extentOffset: cell().document.length - 1),
      ChangeSource.local,
    );
    await tester.pump();
    tester.widgetList<QuillEditor>(cellFinder).first.focusNode.unfocus();
    await tester.pump();
    await tester.tap(find.byTooltip('İtalik · Ctrl+I'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      cell().document.toDelta().toJson().toString(),
      contains('italic: true'),
      reason: 'the toolbar lost the cell when the focus left it',
    );
    expect(
      _body(tester).document.toDelta().toJson().toString(),
      isNot(contains('italic')),
    );

    // Typing in the document again hands the toolbar back to the document.
    tester
        .widgetList<QuillEditor>(find.byType(QuillEditor))
        .firstWhere((e) => e.focusNode.debugLabel == 'document-editor')
        .focusNode
        .requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    _body(tester).updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 8),
      ChangeSource.local,
    );
    await tester.pump();
    await tester.tap(find.byTooltip('İtalik · Ctrl+I'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      _body(tester).document.toDelta().toJson().toString(),
      contains('italic: true'),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('the whole table is picked, and restyled at once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = await _file(tester, _withTable(), 'editor-whole-table-');

    await tester.pumpWidget(
      _app(
        EditorWidget(
          initialFilePath: file.path,
          initialFormat: EvrakFormat.udf,
        ),
      ),
    );
    await waitFor(
      tester,
      () => find.byType(EditorTableView).evaluate().isNotEmpty,
    );

    final cellFinder = find.byWidgetPredicate(
      (w) => w is QuillEditor && w.focusNode.debugLabel == 'table-cell',
    );
    List<String> deltas() => tester
        .widgetList<QuillEditor>(cellFinder)
        .map((e) => e.controller.document.toDelta().toJson().toString())
        .toList();

    // The controls only show once the cursor is in the table.
    tester.widgetList<QuillEditor>(cellFinder).first.focusNode.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Tüm tabloyu seç'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Bigger type, a different family and bold: every cell takes all three,
    // and the text around the table is left alone.
    await tester.tap(find.byTooltip('Yazıyı büyüt'), warnIfMissed: false);
    await tester.pump();
    await tester.tap(find.byTooltip('Kalın · Ctrl+B'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(deltas().length, 4);
    for (final delta in deltas()) {
      expect(delta, contains('bold: true'), reason: delta);
      expect(delta, contains('size:'), reason: delta);
    }
    expect(
      _body(tester).document.toDelta().toJson().toString(),
      isNot(contains('bold')),
    );

    // Clicking back into a cell lets the table go, so the next change is
    // that cell's alone.
    await tester.tap(cellFinder.at(1), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final one = tester.widgetList<QuillEditor>(cellFinder).elementAt(1);
    one.controller.updateSelection(
      TextSelection(
        baseOffset: 0,
        extentOffset: one.controller.document.length - 1,
      ),
      ChangeSource.local,
    );
    await tester.pump();
    final before = deltas();
    await tester.tap(find.byTooltip('İtalik · Ctrl+I'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final after = deltas();
    expect(
      after.where((d) => d.contains('italic')).length,
      1,
      reason: 'letting the table go should leave one cell being edited',
    );
    expect(after.length, before.length);
    await tester.pumpAndSettle();
  });

  testWidgets('the cursor leaves the table when the body is clicked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = await _file(tester, _withTable(), 'editor-leave-');

    await tester.pumpWidget(
      _app(
        EditorWidget(
          initialFilePath: file.path,
          initialFormat: EvrakFormat.udf,
        ),
      ),
    );
    await waitFor(
      tester,
      () => find.byType(EditorTableView).evaluate().isNotEmpty,
    );

    QuillRawEditorState editor(String label) => tester
        .stateList<QuillRawEditorState>(find.byType(QuillRawEditor))
        .firstWhere((st) => st.widget.config.focusNode.debugLabel == label);

    final cellFinder = find.byWidgetPredicate(
      (w) => w is QuillEditor && w.focusNode.debugLabel == 'table-cell',
    );
    await tester.tap(cellFinder.first, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(editor('table-cell').hasConnection, isTrue);
    final cellText = tester
        .widget<QuillEditor>(cellFinder.first)
        .controller
        .document
        .toPlainText();

    // Now put the cursor in the body. Quill moves the focus to an editor
    // from inside requestKeyboard, and only when its own node says it has
    // none — a focused cell sits under the document's node, so that never
    // happened and everything typed went on landing in the cell.
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is QuillEditor && w.focusNode.debugLabel == 'document-editor',
      ),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      editor('table-cell').hasConnection,
      isFalse,
      reason: 'the cell still holds the keyboard',
    );
    expect(editor('document-editor').hasConnection, isTrue);
    expect(
      tester.widget<QuillEditor>(cellFinder.first).focusNode.hasFocus,
      isFalse,
    );

    // And what is typed lands in the document, not in the cell.
    _body(tester)
        .replaceText(0, 0, 'X', const TextSelection.collapsed(offset: 1));
    await tester.pump();
    expect(_body(tester).document.toPlainText(), startsWith('X'));
    expect(
      tester
          .widget<QuillEditor>(cellFinder.first)
          .controller
          .document
          .toPlainText(),
      cellText,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('a column edge is dragged, and the width is saved', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = await _file(tester, _withTable(), 'editor-column-');

    await tester.pumpWidget(
      _app(
        EditorWidget(
          initialFilePath: file.path,
          initialFormat: EvrakFormat.udf,
        ),
      ),
    );
    await waitFor(
      tester,
      () => find.byType(EditorTableView).evaluate().isNotEmpty,
    );

    // The grips only show once the cursor is in the table.
    tester
        .widgetList<QuillEditor>(find.byType(QuillEditor))
        .firstWhere((e) => e.focusNode.debugLabel == 'table-cell')
        .focusNode
        .requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    double firstColumn() {
      final cells = tester
          .widget<EditorPagedTable>(find.byType(EditorPagedTable))
          .cells;
      return cells[0].width / (cells[0].width + cells[1].width);
    }

    final before = firstColumn();
    final tableBox = tester.renderObject<RenderBox>(
      find.byType(EditorPagedTable),
    );
    final total = tableBox.size.width;

    final grips = find.byWidgetPredicate(
      (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
    );
    expect(grips, findsOneWidget, reason: 'two columns, one line between them');

    await tester.drag(grips.first, const Offset(60, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final after = firstColumn();
    expect(
      after,
      greaterThan(before),
      reason: 'the first column should have taken the room',
    );
    // The table keeps the width of the page: what one column takes the
    // other gives up.
    expect(
      tester.renderObject<RenderBox>(find.byType(EditorPagedTable)).size.width,
      closeTo(total, 1),
    );
    // Flutter eats the first few pixels of a drag as slop, so the edge
    // moves by somewhat less than the gesture asked for.
    expect((after - before) * total, greaterThan(20));

    // And it is in the file.
    await shortcut(tester, LogicalKeyboardKey.keyS);
    await waitFor(
      tester,
      () => find.textContaining('Başarıyla kaydedildi:').evaluate().isNotEmpty,
    );
    final saved = (await tester.runAsync(
      () async => UdfReader.readFile(file.path),
    ))!;
    final widths = saved.blocks
        .firstWhere((b) => b.type == DocBlockType.table)
        .table!
        .columnWidths!;
    expect(
      widths[0] / (widths[0] + widths[1]),
      closeTo(after, 0.01),
      reason: 'the width did not survive the save',
    );
    await tester.pumpAndSettle();
  });

  test('a cell keeps the colour it was filled with, through a UDF', () {
    final model = DocModel(
      blocks: [
        DocBlock(
          type: DocBlockType.table,
          plainText: '',
          table: DocTable(
            rows: [
              DocTableRow(
                cells: [
                  DocTableCell(
                    blocks: [DocBlock(plainText: 'Sıfat')],
                    backgroundColor: '#f1f3f7',
                  ),
                  _cell('Ad'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    final back = UdfReader.readBytes(
      Uint8List.fromList(UdfWriter.writeBytes(model)),
    )!;
    final cells = back.blocks
        .firstWhere((b) => b.type == DocBlockType.table)
        .table!
        .rows
        .first
        .cells;
    expect(cells[0].backgroundColor, '#f1f3f7');
    expect(cells[1].backgroundColor, isNull);
  });

  testWidgets('a cell is filled from the table controls', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = await _file(tester, _withTable(), 'editor-shade-');

    await tester.pumpWidget(
      _app(
        EditorWidget(
          initialFilePath: file.path,
          initialFormat: EvrakFormat.udf,
        ),
      ),
    );
    await waitFor(
      tester,
      () => find.byType(EditorTableView).evaluate().isNotEmpty,
    );

    tester
        .widgetList<QuillEditor>(find.byType(QuillEditor))
        .firstWhere((e) => e.focusNode.debugLabel == 'table-cell')
        .focusNode
        .requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Hücreyi boya'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sarı').last);
    await tester.pumpAndSettle();

    // Drawn filled, and only the one cell.
    final filled = tester
        .widget<EditorPagedTable>(find.byType(EditorPagedTable))
        .cells
        .where((c) => c.fill == const Color(0xFFFFF3C4))
        .length;
    expect(filled, 1);

    // And it is in the file.
    await shortcut(tester, LogicalKeyboardKey.keyS);
    await waitFor(
      tester,
      () => find.textContaining('Başarıyla kaydedildi:').evaluate().isNotEmpty,
    );
    final saved = (await tester.runAsync(
      () async => UdfReader.readFile(file.path),
    ))!;
    final cells = saved.blocks
        .firstWhere((b) => b.type == DocBlockType.table)
        .table!
        .rows
        .expand((r) => r.cells)
        .toList();
    expect(
      cells.where((c) => c.backgroundColor == '#fff3c4').length,
      1,
      reason: 'the fill did not survive the save',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('a borderless table shows guides, and shares the page out as '
      'UYAP does', (tester) async {
    // 150 of the tables on this machine declare borderNone against 30 that
    // declare a border: an invisible grid is how UYAP lays out the block
    // naming the parties. 110 of them size no columns at all, and UYAP then
    // gives every column an even share, on whole points (four columns of
    // 453 are 113, 114, 113 and 113 in UYAP's own layout of such tables);
    // the preview does the same, and so does the editor.
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final model = DocModel(
      blocks: [
        DocBlock(
          type: DocBlockType.table,
          plainText: '',
          table: DocTable(
            bordered: false,
            rows: [
              DocTableRow(
                cells: [
                  _cell('VEKİLİ'),
                  _cell(
                    'Av. ERKAN ÖZ, Bahçelievler Mah. Çetin Emeç Bulvarı 5068 '
                    'Sokak, Kemer / ANTALYA',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    final file = await _file(tester, model, 'editor-borderless-');
    await tester.pumpWidget(
      _app(
        EditorWidget(
          initialFilePath: file.path,
          initialFormat: EvrakFormat.udf,
        ),
      ),
    );
    await waitFor(
      tester,
      () => find.byType(EditorTableView).evaluate().isNotEmpty,
    );
    final drawn = tester.widget<EditorPagedTable>(
      find.byType(EditorPagedTable),
    );
    final label = drawn.cells[0].width, body = drawn.cells[1].width;
    expect((label - body).abs(), lessThanOrEqualTo(1));
    expect(label, label.roundToDouble(), reason: 'tam punto');
    // The address wraps in its half, and the label sits on one line.
    final cells = tester
        .widgetList<QuillEditor>(find.byType(QuillEditor))
        .where((e) => e.focusNode.debugLabel == 'table-cell')
        .toList();
    expect(tester.getSize(find.byWidget(cells.first)).height, lessThan(20));
    expect(tester.getSize(find.byWidget(cells.last)).height, greaterThan(20));

    // Saving keeps the table borderless.
    tester
        .widgetList<QuillEditor>(find.byType(QuillEditor))
        .firstWhere((e) => e.focusNode.debugLabel == 'document-editor')
        .focusNode
        .requestFocus();
    await tester.pump();
    await shortcut(tester, LogicalKeyboardKey.keyS);
    await waitFor(
      tester,
      () => find.textContaining('Başarıyla kaydedildi:').evaluate().isNotEmpty,
    );
    final saved = (await tester.runAsync(
      () async => UdfReader.readFile(file.path),
    ))!;
    expect(
      saved.blocks
          .firstWhere((b) => b.type == DocBlockType.table)
          .table!
          .bordered,
      isFalse,
      reason: 'kaydetmek çerçevesiz tabloyu çerçeveli yapmamalı',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('a table is added from the toolbar', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = await _file(
      tester,
      DocModel(blocks: [DocBlock(plainText: 'Sade belge')]),
      'editor-newtable-',
    );
    await tester.pumpWidget(
      _app(
        EditorWidget(
          initialFilePath: file.path,
          initialFormat: EvrakFormat.udf,
        ),
      ),
    );
    await waitFor(
      tester,
      () => find.byType(TableSizeButton).evaluate().isNotEmpty,
    );
    expect(find.byType(EditorTableView), findsNothing);

    await tester.tap(find.byType(TableSizeButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('table-size-2-3')));
    await tester.pumpAndSettle();

    expect(find.byType(EditorTableView), findsOneWidget);
    final view = tester.widget<EditorTableView>(find.byType(EditorTableView));
    expect(view.table.rows.length, 2);
    expect(view.table.rows.first.cells.length, 3);

    tester
        .widgetList<QuillEditor>(find.byType(QuillEditor))
        .firstWhere((e) => e.focusNode.debugLabel == 'document-editor')
        .focusNode
        .requestFocus();
    await tester.pump();
    await shortcut(tester, LogicalKeyboardKey.keyS);
    await waitFor(
      tester,
      () => find.textContaining('Başarıyla kaydedildi:').evaluate().isNotEmpty,
    );
    final saved = (await tester.runAsync(
      () async => UdfReader.readFile(file.path),
    ))!;
    final table = saved.blocks.firstWhere((b) => b.type == DocBlockType.table);
    expect(table.table!.rows.length, 2);
    expect(table.table!.rows.first.cells.length, 3);
    await tester.pumpAndSettle();
  });

  testWidgets('rows and columns are added and taken away', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = await _file(tester, _withTable(), 'editor-rows-');
    await tester.pumpWidget(
      _app(
        EditorWidget(
          initialFilePath: file.path,
          initialFormat: EvrakFormat.udf,
        ),
      ),
    );
    await waitFor(
      tester,
      () => find.byType(EditorTableView).evaluate().isNotEmpty,
    );
    // The controls only appear once a cell holds the cursor.
    expect(find.byTooltip('Satır ekle'), findsNothing);
    tester
        .widgetList<QuillEditor>(find.byType(QuillEditor))
        .firstWhere((e) => e.focusNode.debugLabel == 'table-cell')
        .focusNode
        .requestFocus();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Satır ekle'), findsOneWidget);

    await tester.tap(find.byTooltip('Satır ekle'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sütun ekle'));
    await tester.pumpAndSettle();

    List<EditorPagedCell> drawn() =>
        tester.widget<EditorPagedTable>(find.byType(EditorPagedTable)).cells;
    int rows() => drawn().map((c) => c.row).toSet().length;
    expect(rows(), 3);
    expect(drawn().where((c) => c.row == 0).length, 3);

    await tester.tap(find.byTooltip('Satırı sil'));
    await tester.pumpAndSettle();
    expect(rows(), 2);

    tester
        .widgetList<QuillEditor>(find.byType(QuillEditor))
        .firstWhere((e) => e.focusNode.debugLabel == 'document-editor')
        .focusNode
        .requestFocus();
    await tester.pump();
    await shortcut(tester, LogicalKeyboardKey.keyS);
    await waitFor(
      tester,
      () => find.textContaining('Başarıyla kaydedildi:').evaluate().isNotEmpty,
    );
    final saved = (await tester.runAsync(
      () async => UdfReader.readFile(file.path),
    ))!;
    final table = saved.blocks
        .firstWhere((b) => b.type == DocBlockType.table)
        .table!;
    expect(table.rows.length, 2);
    expect(table.rows.first.cells.length, 3);
    expect(saved.toPlainText(), contains('Özlem Şenoğlu'));
    await tester.pumpAndSettle();
  });

  testWidgets('a nested table is shown and left alone', (tester) async {
    // Three of the files here nest tables four deep. They are drawn, not typed
    // in, and the outer cell hands its content back exactly as it was read.
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final nested = DocModel(
      blocks: [
        DocBlock(
          type: DocBlockType.table,
          plainText: '',
          table: DocTable(
            rows: [
              DocTableRow(
                cells: [
                  DocTableCell(
                    blocks: [
                      DocBlock(
                        type: DocBlockType.table,
                        plainText: '',
                        table: DocTable(
                          rows: [
                            DocTableRow(cells: [_cell('İç hücre')]),
                          ],
                        ),
                      ),
                    ],
                  ),
                  _cell('Dış hücre'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    final file = await _file(tester, nested, 'editor-nested-');
    await tester.pumpWidget(
      _app(
        EditorWidget(
          initialFilePath: file.path,
          initialFormat: EvrakFormat.udf,
        ),
      ),
    );
    await waitFor(
      tester,
      () => find.byType(EditorTableView).evaluate().isNotEmpty,
    );
    expect(find.byType(EditorTableView), findsNWidgets(2));
    final inner = tester
        .widgetList<EditorTableView>(find.byType(EditorTableView))
        .firstWhere((v) => v.readOnly);
    expect(
      inner.table.rows.single.cells.single.blocks.single.plainText,
      'İç hücre',
    );

    tester
        .widgetList<QuillEditor>(find.byType(QuillEditor))
        .firstWhere((e) => e.focusNode.debugLabel == 'document-editor')
        .focusNode
        .requestFocus();
    await tester.pump();
    await shortcut(tester, LogicalKeyboardKey.keyS);
    await waitFor(
      tester,
      () => find.textContaining('Başarıyla kaydedildi:').evaluate().isNotEmpty,
    );
    final saved = (await tester.runAsync(
      () async => UdfReader.readFile(file.path),
    ))!;
    // toPlainText does not walk into a nested table, so check the shape.
    final outer = saved.blocks
        .firstWhere((b) => b.type == DocBlockType.table)
        .table!;
    final innerBlock = outer.rows.single.cells.first.blocks.single;
    expect(innerBlock.type, DocBlockType.table);
    expect(
      innerBlock.table!.rows.single.cells.single.blocks.single.plainText,
      'İç hücre',
    );
    expect(saved.toPlainText(), contains('Dış hücre'));
    await tester.pumpAndSettle();
  });
}

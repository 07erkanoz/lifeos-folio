import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/editor_table_embed.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:evrak_convert/ui/widgets/editor_units.dart';
import 'package:evrak_convert/ui/widgets/editor_paged_table.dart';

import 'editor_shortcuts_test.dart' show waitFor;

/// A4 less the 1.5cm margins UYAP writes, in the pixels the page
/// is drawn in.
const _textColumn = (595.28 - 2 * 42.525) * EditorUnits.pixelsPerPoint;

DocTableCell _cell(String text) =>
    DocTableCell(blocks: [DocBlock(plainText: text)]);

/// The shape of a UYAP petition: Times New Roman at twelve point, and a four
/// column table that declares equal spans, which is what `columnSpans` in
/// these files almost always says.
DocModel _petition() => DocModel(
  styles: const [
    DocStyleDef(name: 'hvl-default', family: 'Times New Roman', size: 12),
  ],
  blocks: [
    DocBlock(
      plainText: "ANTALYA 9. ASLİYE HUKUK MAHKEMESİ SAYIN HAKİMLİĞİ'NE",
      alignment: DocAlignment.center,
      spans: [
        const DocSpan(
          startOffset: 0,
          length: 51,
          bold: true,
          fontFamily: 'Times New Roman',
          fontSize: 12,
        ),
      ],
    ),
    DocBlock(plainText: 'DAVALILAR :'),
    DocBlock(
      type: DocBlockType.table,
      plainText: '',
      table: DocTable(
        columnWidths: const [100, 100, 100, 100],
        rows: [
          DocTableRow(
            cells: [
              _cell('Sıra'),
              _cell('Ad Soyad'),
              _cell('T.C. Kimlik'),
              _cell('Sıfat'),
            ],
          ),
          DocTableRow(
            cells: [
              _cell('3'),
              _cell('TURHAN BİLGİN'),
              _cell('00000000000'),
              _cell('Davalı'),
            ],
          ),
        ],
      ),
    ),
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

void main() {
  for (final scale in [1.0, 1.25, 1.5]) {
    testWidgets('a page is the size it prints at, text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('page-scale-'),
      ))!;
      DocumentHistory.instance = DocumentHistory(
        directory: Directory('${dir.path}/history'),
      );
      final file = File('${dir.path}/dilekce.udf');
      await tester.runAsync(
        () => file.writeAsBytes(UdfWriter.writeBytes(_petition())),
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
        () => find.byType(EditorTableView).evaluate().isNotEmpty,
      );

      // The page is a facsimile of paper. Windows' "make text bigger" is a
      // preference about the app's own writing, not about the document's:
      // left to reach the page it grew the type while the page kept the
      // width it prints at, and a table that fits on paper spilled over
      // three lines a cell.
      final table = tester.renderObject<RenderBox>(
        find.byType(EditorPagedTable),
      );
      expect(table.size.width, closeTo(_textColumn, 4));

      for (final element
          in find
              .descendant(
                of: find.byType(EditorPagedTable),
                matching: find.byType(RichText),
              )
              .evaluate()) {
        final text = (element.widget as RichText).text;
        if (text.toPlainText().trim().isEmpty) continue;
        final box = element.renderObject as RenderBox;
        final painter = TextPainter(
          text: text,
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        expect(
          painter.width,
          lessThan(box.size.width),
          reason: '"${text.toPlainText().trim()}" no longer fits its column',
        );
        expect(
          box.size.height,
          lessThan(30),
          reason: '"${text.toPlainText().trim()}" wrapped onto another line',
        );
      }
      await tester.pumpAndSettle();
    });
  }
}

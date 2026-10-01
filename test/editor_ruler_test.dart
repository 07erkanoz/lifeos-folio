import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/document_ruler.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';

import 'editor_shortcuts_test.dart' show waitFor;

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
  testWidgets('a side ruler beside every page, put away from the menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-ruler-'),
    ))!;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    final file = File('${dir.path}/belge.udf');
    await tester.runAsync(
      () => file.writeAsBytes(
        UdfWriter.writeBytes(
          // Sixty rows: two pages.
          DocModel(
            blocks: [
              for (var i = 0; i < 60; i++)
                DocBlock(plainText: 'Kenar boşluğu denemesi $i'),
            ],
          ),
        ),
      ),
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
      () => find.byKey(const ValueKey('editor-paper')).evaluate().isNotEmpty,
    );

    // One across the top, and one down the side of each page now that the
    // text is laid out on pages.
    final rulers = tester.widgetList<DocumentRuler>(find.byType(DocumentRuler));
    expect(rulers.map((r) => r.axis), [
      Axis.horizontal,
      Axis.vertical,
      Axis.vertical,
    ]);
    expect(find.byKey(const ValueKey('vertical-ruler-1')), findsOneWidget);

    // Put away for whoever does not want it.
    await tester.tap(find.byTooltip('Görünüm ve cetveller'));
    await tester.pumpAndSettle();
    // The tap lands on the menu item; the paragraph inside it is not itself
    // the hit target, and where the menu opens differs between platforms.
    // Whether the tap did anything is settled by the check below.
    await tester.tap(find.text('Dikey cetvel').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<DocumentRuler>(find.byType(DocumentRuler))
          .map((r) => r.axis),
      [Axis.horizontal],
    );
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}

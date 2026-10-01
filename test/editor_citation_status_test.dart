import 'dart:io';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_citation_tap_test.dart' show waitFor;
import 'support/fake_path_provider.dart';
import 'support/temp_directory.dart';

Future<Directory> _open(WidgetTester tester, List<String> paragraphs) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  useFakePathProvider();
  final dir = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('folio_cite_status_'),
  ))!;
  final previous = DocumentHistory.instance;
  DocumentHistory.instance = DocumentHistory(
    directory: Directory('${dir.path}/history'),
  );
  addTearDown(() => DocumentHistory.instance = previous);
  final file = File('${dir.path}/dilekce.udf');
  await tester.runAsync(
    () => file.writeAsBytes(
      UdfWriter.writeBytes(
        DocModel(blocks: [for (final p in paragraphs) DocBlock(plainText: p)]),
      ),
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      home: Scaffold(
        body: EditorWidget(
          initialFilePath: file.path,
          initialFormat: EvrakFormat.udf,
        ),
      ),
    ),
  );
  await waitFor(tester, () => find.byType(QuillEditor).evaluate().isNotEmpty);
  return dir;
}

void main() {
  testWidgets('what a filing rests on is counted under the page, once each, '
      'and opens the list there', (tester) async {
    final dir = await _open(tester, [
      'Boşanma talebi TMK m. 166 uyarınca sunulmuştur.',
      // The same article again is one article, as the list shows it.
      'TMK m. 166 ve HMK m. 119 hükümleri birlikte değerlendirilmelidir.',
    ]);
    final status = find.byKey(const ValueKey('citation-status'));
    await waitFor(tester, () => status.evaluate().isNotEmpty);
    expect(find.text('2 dayanak'), findsOneWidget);
    expect(
      find.byTooltip('2 kanun maddesi · dayanakları göster'),
      findsOneWidget,
    );
    // No longer among the tools.
    expect(find.byTooltip('Dayanaklar · 2 atıf'), findsNothing);

    expect(find.byKey(const ValueKey('citation-list')), findsNothing);
    await tester.tap(status);
    await tester.pump();
    expect(find.byKey(const ValueKey('citation-list')), findsOneWidget);
    // Between the page and the bar: the bar is still under it.
    expect(
      tester.getTopLeft(status).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const ValueKey('citation-list'))).dy,
      ),
    );
    await tester.tap(status);
    await tester.pump();
    expect(find.byKey(const ValueKey('citation-list')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await removeTemporaryDirectory(tester, dir);
  });

  testWidgets('a filing that cites nothing shows nothing under the page', (
    tester,
  ) async {
    final dir = await _open(tester, ['Bu belgede hiçbir atıf yok.']);
    // Long enough for a scan to have found something, had there been any.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('citation-status')), findsNothing);
    expect(find.textContaining('dayanak'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await removeTemporaryDirectory(tester, dir);
  });
}

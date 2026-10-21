import 'dart:io';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/editor/document_lock.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:evrak_convert/ui/widgets/share_document_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> ready(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 150 && !condition(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}

void main() {
  testWidgets('the editor shares the document as it is on disk; what is '
      'not saved is asked about first', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-paylas-'),
    ))!;
    addTearDown(() => dir.deleteSync(recursive: true));
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    final lockFolder = DocumentLock.folder;
    DocumentLock.folder = () async => Directory('${dir.path}/acik');
    addTearDown(() => DocumentLock.folder = lockFolder);
    final file = File('${dir.path}/dilekce.udf');
    await tester.runAsync(
      () => file.writeAsBytes(
        UdfWriter.writeBytes(
          DocModel(blocks: [DocBlock(plainText: 'Davacı vekili')]),
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
    final menu = find.byKey(const ValueKey('editor-file-menu'));
    await ready(tester, () => menu.evaluate().isNotEmpty);
    Future<void> share() async {
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paylaş…'));
      await tester.pumpAndSettle();
    }

    // Nothing unsaved: the file goes as it is.
    await share();
    expect(find.byType(ShareDocumentDialog), findsOneWidget);
    expect(
      tester.widget<ShareDocumentDialog>(find.byType(ShareDocumentDialog)).path,
      file.path,
    );
    Navigator.of(tester.element(find.byType(ShareDocumentDialog))).pop();
    await tester.pumpAndSettle();

    // Written in, not saved: asked first; the saved file may still go.
    tester
        .widget<QuillEditor>(find.byType(QuillEditor).first)
        .controller
        .replaceText(0, 0, 'x', const TextSelection.collapsed(offset: 1));
    await tester.pump();
    await share();
    expect(find.text('Kaydedilmemiş değişiklikler var'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share-saved')));
    await tester.pumpAndSettle();
    expect(find.byType(ShareDocumentDialog), findsOneWidget);
    Navigator.of(tester.element(find.byType(ShareDocumentDialog))).pop();
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });
}

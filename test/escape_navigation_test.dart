import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/main.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/document_preview_widget.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:evrak_convert/ui/widgets/editor_find_replace.dart';
import 'package:evrak_convert/ui/widgets/convert_dialog.dart';
import 'package:evrak_convert/ui/widgets/new_document_dialog.dart';

import 'editor_drafts_test.dart' as helpers;
import 'support/fake_path_provider.dart';
import 'support/temp_directory.dart';

Future<void> escape(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets(
    'Escape closes one layer: document menu, dialog, editor, preview and focused search',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('folio-escape-'),
      ))!;
      useFakePathProvider();
      final history = DocumentHistory.instance;
      DocumentHistory.instance = DocumentHistory(
        directory: Directory('${dir.path}/history'),
      );
      addTearDown(() => DocumentHistory.instance = history);
      final file = File('${dir.path}/document.udf');
      await tester.runAsync(
        () => file.writeAsBytes(
          UdfWriter.writeBytes(
            DocModel(blocks: [DocBlock(plainText: 'Kaynak belge')]),
          ),
        ),
      );
      await tester.pumpWidget(EvrakConvertApp(initialPaths: [file.path]));
      await helpers.ready(
        tester,
        () => find.byTooltip('Belge işlemleri').evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('Belge işlemleri'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Paylaş / Gönder'), findsOneWidget);
      await escape(tester);
      expect(find.text('Paylaş / Gönder'), findsNothing);
      expect(find.byType(DocumentPreviewWidget), findsOneWidget);
      await tester.tap(find.byTooltip('Belge işlemleri'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await helpers.click(tester, 'Dönüştür');
      expect(find.byType(ConvertDialog), findsOneWidget);
      await escape(tester);
      expect(find.byType(ConvertDialog), findsNothing);
      expect(find.byType(DocumentPreviewWidget), findsOneWidget);
      await helpers.click(tester, 'Düzenle');
      await helpers.ready(
        tester,
        () => find.byType(QuillEditor).evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('Belge işlemleri'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Dönüştür'), findsOneWidget);
      await escape(tester);
      expect(find.byType(EditorWidget), findsOneWidget);
      await helpers.click(tester, 'Değiştir');
      expect(find.byType(EditorFindReplace), findsOneWidget);
      await escape(tester);
      expect(find.byType(EditorFindReplace), findsNothing);
      expect(find.byType(EditorWidget), findsOneWidget);
      final controller = tester
          .widget<QuillEditor>(find.byType(QuillEditor))
          .controller;
      controller.replaceText(
        0,
        0,
        'Yeni ',
        const TextSelection.collapsed(offset: 5),
      );
      await tester.pump();
      await escape(tester);
      expect(find.text('Değişiklikler kaydedilsin mi?'), findsOneWidget);
      await escape(tester);
      expect(find.text('Değişiklikler kaydedilsin mi?'), findsNothing);
      expect(controller.document.toPlainText(), contains('Yeni '));
      expect(find.byType(EditorWidget), findsOneWidget);
      await escape(tester);
      await helpers.click(tester, 'Kaydetmeden çık');
      await helpers.ready(
        tester,
        () => find.byType(DocumentPreviewWidget).evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(EditorWidget), findsNothing);
      await escape(tester);
      expect(find.byType(DocumentPreviewWidget), findsNothing);
      final search = find.byType(TextField).first;
      await tester.enterText(search, 'aranan içerik');
      await escape(tester);
      expect(tester.widget<TextField>(search).controller!.text, '');
      await escape(tester);
      expect(find.text('Yeni belge oluştur'), findsOneWidget);
      await helpers.click(tester, 'Yeni belge oluştur');
      expect(find.byType(NewDocumentDialog), findsOneWidget);
      await escape(tester);
      expect(find.byType(NewDocumentDialog), findsNothing);
      expect(find.text('Yeni belge oluştur'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      // On Linux the app asks the session bus whether a tray host is running
      // and gives that question two seconds. There is no bus on a runner, so
      // the question never gets an answer and the timeout is still on the
      // clock when the test ends, which fails it on a pending timer. Windows
      // never sees this: the probe returns on its first line. Let the two
      // seconds pass so the probe finishes and closes its bus.
      await tester.pump(const Duration(seconds: 3));
      await removeTemporaryDirectory(tester, dir);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}

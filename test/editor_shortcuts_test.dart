import 'dart:io';

import 'package:evrak_convert/services/editor/document_history.dart';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/document_ruler.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:evrak_convert/ui/widgets/editor_find_replace.dart';

Future<void> shortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// Waits in real time for [ready], up to about eight seconds. Saving a
/// signed document takes three of them here, which left CI, a slower
/// machine, failing on a budget of two.
Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 400 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(ready(), isTrue);
}

void main() {
  testWidgets(
    'rulers save real margins; keyboard save, alignment, search and save-as work',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('editor-keys-'),
      ))!;
      DocumentHistory.instance = DocumentHistory(
        directory: Directory('${dir.path}/history'),
      );
      final file = File('${dir.path}/document.udf');
      const initial = DocPageProperties();
      await tester.runAsync(
        () => file.writeAsBytes(
          UdfWriter.writeBytes(
            DocModel(blocks: [DocBlock(plainText: 'Deneme belge')]),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
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
      await waitFor(
        tester,
        () => find.byType(QuillEditor).evaluate().isNotEmpty,
      );
      final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
      // Dark application chrome must not turn document text white on white paper.
      final paperTheme = Theme.of(tester.element(find.byType(QuillEditor)));
      expect(paperTheme.textTheme.bodyLarge?.color, Colors.black);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('editor-font-label')))
            .data,
        'Times New Roman',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('editor-font-size-label')))
            .data,
        '12', // Quill stores 16 pixels; the toolbar must display 12 points.
      );
      final originalDelta = editor.controller.document.toDelta().toJson();
      final scaledPage = find.byKey(const ValueKey('editor-scaled-page'));
      final originalWidth = tester.getSize(scaledPage).width;
      final pointer =
          tester.getTopLeft(find.byType(QuillEditor)) + const Offset(50, 8);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: pointer,
          scrollDelta: const Offset(0, -120),
        ),
      );
      await tester.pump();
      expect(tester.getSize(scaledPage).width, greaterThan(originalWidth));
      expect(editor.controller.document.toDelta().toJson(), originalDelta);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: pointer,
          scrollDelta: const Offset(0, 120),
        ),
      );
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(tester.getSize(scaledPage).width, closeTo(originalWidth, .1));
      await tester.sendEventToBinding(
        PointerScrollEvent(position: pointer, scrollDelta: const Offset(0, 80)),
      );
      await tester.pump();
      expect(tester.getSize(scaledPage).width, closeTo(originalWidth, .1));
      // Return to the upper ruler after ordinary scrolling.
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: pointer,
          scrollDelta: const Offset(0, -80),
        ),
      );
      await tester.pump();
      editor.focusNode.requestFocus();
      await tester.pump();
      // Margins alone must persist even when the document delta has not changed.
      await tester.drag(
        find.byKey(const ValueKey('horizontal-ruler-start')),
        const Offset(48, 0),
      );
      await tester.pump();
      // The side ruler beside the first page sets the top margin.
      await tester.drag(
        find.byKey(const ValueKey('vertical-ruler-start')),
        const Offset(0, 48),
      );
      await tester.pump();
      final horizontal = tester
          .widgetList<DocumentRuler>(find.byType(DocumentRuler))
          .firstWhere((r) => r.axis == Axis.horizontal);
      final vertical = tester
          .widgetList<DocumentRuler>(find.byType(DocumentRuler))
          .firstWhere((r) => r.axis == Axis.vertical);
      expect(horizontal.leading, greaterThan(initial.marginLeft));
      expect(vertical.leading, greaterThan(initial.marginTop));
      editor.focusNode.requestFocus();
      await tester.pump();
      await shortcut(tester, LogicalKeyboardKey.keyS);
      await waitFor(
        tester,
        () =>
            find.textContaining('Başarıyla kaydedildi:').evaluate().isNotEmpty,
      );
      final model = await tester.runAsync(
        () async => UdfReader.readFile(file.path)!,
      );
      expect(
        model!.pageProperties.marginLeft,
        closeTo(horizontal.leading, .01),
      );
      expect(model.pageProperties.marginTop, closeTo(vertical.leading, .01));
      expect(model.toPlainText(), 'Deneme belge');

      final controller = editor.controller;
      controller.updateSelection(
        const TextSelection.collapsed(offset: 0),
        ChangeSource.local,
      );
      await shortcut(tester, LogicalKeyboardKey.keyE);
      expect(
        controller.getSelectionStyle().attributes[Attribute.align.key]?.value,
        'center',
      );
      controller.replaceText(
        0,
        0,
        'Yeni ',
        const TextSelection.collapsed(offset: 5),
      );
      ScaffoldMessenger.of(tester.element(find.byType(EditorWidget)))
          .clearSnackBars();
      await tester.pumpAndSettle();
      await shortcut(tester, LogicalKeyboardKey.keyS);
      await waitFor(
        tester,
        () =>
            find.textContaining('Başarıyla kaydedildi:').evaluate().isNotEmpty,
      );
      expect(
        (await tester.runAsync(() async => UdfReader.readFile(file.path)))!
            .toPlainText(),
        'Yeni Deneme belge',
      );

      await shortcut(tester, LogicalKeyboardKey.keyS, shift: true);
      await tester.pumpAndSettle();
      expect(find.text('UYAP UDF Olarak Kaydet'), findsOneWidget);
      expect(
        controller.getSelectionStyle().attributes[Attribute.strikeThrough.key],
        isNull,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      editor.focusNode.requestFocus();
      await tester.pump();
      editor.controller.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 4),
        ChangeSource.local,
      );
      editor.controller.formatSelection(
        Attribute.clone(Attribute.font, 'Arial'),
      );
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('editor-font-label')))
            .data,
        'Arial',
      );
      editor.controller.updateSelection(
        const TextSelection.collapsed(offset: 10),
        ChangeSource.local,
      );
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('editor-font-label')))
            .data,
        'Times New Roman',
      );
      editor.controller.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 10),
        ChangeSource.local,
      );
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('editor-font-label')))
            .data,
        'Karışık',
      );
      editor.focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(
        const LogicalKeyboardKey(0x131),
        physicalKey: PhysicalKeyboardKey.keyI,
        platform: 'macos',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(
        controller.getSelectionStyle().attributes[Attribute.italic.key]?.value,
        true,
      );
      await shortcut(tester, LogicalKeyboardKey.keyH);
      await tester.pumpAndSettle();
      expect(find.text('Tümünü değiştir'), findsOneWidget);
      await tester.tap(find.text('Kapat'));
      await tester.pumpAndSettle();
      editor.focusNode.requestFocus();
      await tester.pump();
      await shortcut(tester, LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();
      expect(find.byType(EditorFindReplace), findsOneWidget);
      await tester.tap(find.text('Kapat'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Görünüm ve cetveller'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(
          of: find.text('Yatay cetvel'),
          matching: find.byType(CheckedPopupMenuItem<String>),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<DocumentRuler>(find.byType(DocumentRuler))
            .map((r) => r.axis),
        [Axis.vertical],
      );
      await tester.tap(find.byTooltip('Görünüm ve cetveller'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(
          of: find.text('Dikey cetvel'),
          matching: find.byType(CheckedPopupMenuItem<String>),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DocumentRuler), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => dir.delete(recursive: true));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}

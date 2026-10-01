import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';

import 'editor_shortcuts_test.dart' show shortcut, waitFor;

/// Linux, not the Android flutter_test assumes: Quill draws touch handles on
/// a phone, and they catch clicks a desktop never sees.
final linux = TargetPlatformVariant.only(TargetPlatform.linux);

QuillController body(WidgetTester t) => t
    .widgetList<QuillEditor>(find.byType(QuillEditor))
    .firstWhere((e) => e.focusNode.debugLabel == 'document-editor')
    .controller;

RenderEditor bodyRender(WidgetTester t) => t
    .stateList<QuillRawEditorState>(find.byType(QuillRawEditor))
    .firstWhere(
      (s) => s.widget.config.focusNode.debugLabel == 'document-editor',
    )
    .renderEditor;

Offset at(WidgetTester t, int offset) {
  final box = bodyRender(t);
  final caret = box.getLocalRectForCaret(TextPosition(offset: offset));
  return box.localToGlobal(caret.centerLeft + const Offset(0.5, 0));
}

/// Selects [word] by dragging over it with the mouse, as a reader does.
Future<void> dragSelect(WidgetTester t, String word) async {
  final start = body(t).document.toPlainText().indexOf(word);
  final from = at(t, start), to = at(t, start + word.length);
  final gesture = await t.startGesture(from, kind: PointerDeviceKind.mouse);
  await t.pump(const Duration(milliseconds: 50));
  for (var i = 1; i <= 5; i++) {
    await gesture.moveTo(Offset.lerp(from, to, i / 5)!);
    await t.pump(const Duration(milliseconds: 20));
  }
  await gesture.up();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> clickTool(WidgetTester t, String tooltip) async {
  await t.tap(find.byTooltip(tooltip), kind: PointerDeviceKind.mouse);
  await t.pumpAndSettle();
}

bool isBold(WidgetTester t, String word) {
  final document = body(t).document;
  final at = document.toPlainText().indexOf(word);
  return document
      .collectStyle(at, word.length)
      .attributes
      .containsKey(Attribute.bold.key);
}

Future<void> openEditor(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dir = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('folio-focus-'),
  ))!;
  DocumentHistory.instance = DocumentHistory(
    directory: Directory('${dir.path}/history'),
  );
  final file = File('${dir.path}/belge.udf');
  await tester.runAsync(
    () => file.writeAsBytes(
      UdfWriter.writeBytes(
        DocModel(
          blocks: [
            DocBlock(plainText: 'Birinci paragraf alfa beta gama delta.'),
            DocBlock(plainText: 'İkinci paragraf epsilon zeta eta teta.'),
          ],
        ),
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
        body: Column(
          children: [
            // Something outside the editor that can hold the keyboard.
            const SizedBox(width: 200, child: TextField(key: Key('outside'))),
            Expanded(
              child: EditorWidget(
                initialFilePath: file.path,
                initialFormat: EvrakFormat.udf,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await waitFor(tester, () => find.byType(QuillEditor).evaluate().isNotEmpty);
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets(
    'the toolbar leaves the keyboard with the text it just styled',
    variant: linux,
    (tester) async {
      await openEditor(tester);
      await dragSelect(tester, 'epsilon');
      await clickTool(tester, 'Kalın · Ctrl+B');
      expect(isBold(tester, 'epsilon'), isTrue);
      // No new click in the text: the keys go straight on. A click on the
      // toolbar counted as one outside the editor, which dropped the focus,
      // so these reached nothing.
      await shortcut(tester, LogicalKeyboardKey.keyB);
      expect(isBold(tester, 'epsilon'), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(body(tester).document.toPlainText(), isNot(contains('epsilon')));
    },
  );

  testWidgets(
    'a toolbar menu opened and closed leaves the keyboard in the text',
    variant: linux,
    (tester) async {
      await openEditor(tester);
      await dragSelect(tester, 'zeta');
      await clickTool(tester, 'Yazı boyutu (punto)');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(body(tester).document.toPlainText(), isNot(contains('zeta')));
    },
  );

  testWidgets(
    'dragging over text in an editor without the keyboard takes it',
    variant: linux,
    (tester) async {
      await openEditor(tester);
      await tester.tap(find.byKey(const Key('outside')));
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('document-editor'),
      );
      // Selecting with the mouse is not a tap; before, only a tap asked for
      // the keyboard, so this was highlighted and deaf.
      await dragSelect(tester, 'gama');
      await shortcut(tester, LogicalKeyboardKey.keyB);
      expect(isBold(tester, 'gama'), isTrue);
    },
  );
}

import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/ui/widgets/editor_page_viewport.dart';

/// A document long enough to run well past one screen.
Document longDocument() {
  final delta = Delta();
  for (var i = 0; i < 80; i++) {
    delta.insert('Satır $i: davacı vekili dilekçesini sunar.\n');
  }
  return Document.fromDelta(delta);
}

/// The editor as the page shows it: not scrolling itself, inside a view that
/// scrolls, and scaled by a zoom the way EditorPageViewport scales it.
Future<(QuillController, ScrollController)> pumpZoomed(
  WidgetTester tester, {
  required double zoom,
}) async {
  final controller = QuillController(
    document: longDocument(),
    selection: const TextSelection.collapsed(offset: 0),
  );
  final scroll = ScrollController();
  final focus = FocusNode();
  addTearDown(() {
    controller.dispose();
    scroll.dispose();
    focus.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: SingleChildScrollView(
            controller: scroll,
            child: SizedBox(
              width: 500 * zoom,
              child: FittedBox(
                alignment: Alignment.topCenter,
                fit: BoxFit.fitWidth,
                child: SizedBox(
                  width: 500,
                  child: QuillEditor.basic(
                    controller: controller,
                    focusNode: focus,
                    config: const QuillEditorConfig(
                      scrollable: false,
                      expands: false,
                      padding: EdgeInsets.zero,
                      autoFocus: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  focus.requestFocus();
  await tester.pumpAndSettle();
  return (controller, scroll);
}

QuillRawEditorState editorState(WidgetTester tester) =>
    tester.state<QuillRawEditorState>(find.byType(QuillRawEditor));

void main() {
  for (final (window, label) in [(1400.0, '%120'), (700.0, '%84')]) {
    testWidgets('a page opens at the preview\'s size, $label in $window px', (
      tester,
    ) async {
      // 120%, the size the preview opens the same page at, unless the window
      // is too narrow to hold it; then as wide as it is, less the padding.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(window, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EditorPageViewport(
              pageWidth: 800,
              background: Colors.grey,
              child: SizedBox(width: 800, height: 1100),
            ),
          ),
        ),
      );
      final text = tester.widget<Text>(
        find.byKey(const ValueKey('editor-zoom-label')),
      );
      expect(text.data, label);
    });
  }

  for (final zoom in [0.5, 2.0]) {
    testWidgets('at ${zoom * 100}% the menu is anchored to the selection', (
      tester,
    ) async {
      final (controller, _) = await pumpZoomed(tester, zoom: zoom);
      // A word on the fifth line, still on screen at either zoom.
      final line = controller.document.toPlainText().indexOf('Satır 4');
      controller.updateSelection(
        TextSelection(baseOffset: line, extentOffset: line + 5),
        ChangeSource.local,
      );
      await tester.pump();
      final state = editorState(tester);
      final box = state.renderEditor;
      final end = box.localToGlobal(
        box.getEndpointsForSelection(controller.selection).last.point,
      );
      // Fifth line down: at 200% the old sum put the menu at half this
      // height, at 50% twice it.
      expect(state.contextMenuAnchors.secondaryAnchor!.dy, closeTo(end.dy, 1));
    });
  }

  testWidgets('a right click opens the menu where the mouse is', (
    tester,
  ) async {
    await pumpZoomed(tester, zoom: 2);
    final at =
        tester.getTopLeft(find.byType(QuillRawEditor)) + const Offset(120, 90);
    await tester.tapAt(at, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(editorState(tester).contextMenuAnchors.primaryAnchor, at);
  });

  testWidgets('arrowing down past the bottom scrolls the page after it', (
    tester,
  ) async {
    final (controller, scroll) = await pumpZoomed(tester, zoom: 2);
    expect(scroll.offset, 0);
    for (var i = 0; i < 20; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    // Twenty lines at 200% are well past a 400 px view.
    expect(scroll.offset, greaterThan(0));
    final state = editorState(tester);
    final caret = state.renderEditor.getLocalRectForCaret(
      controller.selection.extent,
    );
    final top = state.renderEditor.localToGlobal(caret.topLeft).dy;
    final bottom = state.renderEditor.localToGlobal(caret.bottomLeft).dy;
    expect(top, greaterThanOrEqualTo(0));
    expect(bottom, lessThanOrEqualTo(400));
  });
}

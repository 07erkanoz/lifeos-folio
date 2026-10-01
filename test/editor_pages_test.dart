import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

/// The editor on pages: rows of 20 px, a text area of 100 px — five rows —
/// and the next page's text area starting 140 px below the last.
const pages = QuillPageGeometry(height: 100, stride: 140);

Future<(RenderEditor, QuillController)> pump(
  WidgetTester tester,
  Delta delta, {
  QuillLineLayoutBuilder? layout,
  bool focus = false,
}) async {
  final controller = QuillController(
    document: Document.fromDelta(delta),
    selection: const TextSelection.collapsed(offset: 0),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: QuillEditor.basic(
                controller: controller,
                config: QuillEditorConfig(
                  pages: pages,
                  lineLayoutBuilder: layout,
                  scrollable: false,
                  expands: false,
                  autoFocus: focus,
                  padding: EdgeInsets.zero,
                  customStyles: const DefaultStyles(
                    paragraph: DefaultTextBlockStyle(
                      TextStyle(fontSize: 20, height: 1, color: Colors.black),
                      HorizontalSpacing(0, 0),
                      VerticalSpacing(0, 0),
                      VerticalSpacing(0, 0),
                      null,
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
  await tester.pump();
  return (tester.allRenderObjects.whereType<RenderEditor>().first, controller);
}

/// The top of the row [offset] is on: the caret's, less how far below the
/// top of the first row the caret is drawn.
double top(RenderEditor editor, int offset) =>
    editor.getLocalRectForCaret(TextPosition(offset: offset)).top -
    editor.getLocalRectForCaret(const TextPosition(offset: 0)).top;

/// Twelve words, two to a 300 px row in the test font: six rows.
const long =
    'birinci ikinci ucuncu dorduncu besinci altinci yedinci sekizinci '
    'dokuzuncu onuncu onbirinci onikinci';

void main() {
  testWidgets('a line that does not fit starts the next page', (tester) async {
    final delta = Delta();
    for (var i = 0; i < 8; i++) {
      delta.insert('satir $i\n');
    }
    final (editor, _) = await pump(tester, delta);
    const line = 'satir 0\n'.length;
    expect(
      [for (var i = 0; i < 8; i++) top(editor, i * line)],
      [
        0, 20, 40, 60, 80, // page 1
        140, 160, 180, // page 2
      ],
    );
    // To the end of the second page's text area, so its sheet is whole.
    expect(editor.size.height, 240);
  });

  testWidgets('a paragraph splits at the row that does not fit, and its '
      'rows go on on the next page', (tester) async {
    final delta = Delta()
      ..insert('bir\niki\nuc\n')
      ..insert('$long\n');
    final (editor, _) = await pump(tester, delta);
    final start = 'bir\niki\nuc\n'.length;
    final rows = <double>{};
    for (var i = 0; i < long.length; i++) {
      rows.add(top(editor, start + i));
    }
    // Two rows fill the first page; the other four start the second.
    // Two rows fill the first page, five the second, and the rest go on.
    expect(rows.toList()..sort(), [60, 80, 140, 160, 180, 200, 220, 280, 300]);
  });

  testWidgets('space above a paragraph goes with its first row', (
    tester,
  ) async {
    final delta = Delta();
    for (var i = 0; i < 4; i++) {
      delta.insert('satir $i\n');
    }
    // 15 points above: 20 px, which with its row no longer fits after
    // four rows.
    delta
      ..insert('aralikli')
      ..insert('\n', {
        'doc-layout': {'before': 15},
      });
    final (editor, _) = await pump(
      tester,
      delta,
      layout: (line) => line.style.attributes.containsKey('doc-layout')
          ? const QuillLineLayout(top: 20)
          : null,
    );
    expect(top(editor, 4 * 'satir 0\n'.length), 140 + 20);
  });

  testWidgets('a tap in the room between pages lands on the nearer row, and '
      'one on the next page on its own row', (tester) async {
    final delta = Delta()
      ..insert('bir\niki\nuc\n')
      ..insert('$long\n');
    final (editor, _) = await pump(tester, delta);
    final start = 'bir\niki\nuc\n'.length;
    final shift = editor
        .getLocalRectForCaret(const TextPosition(offset: 0))
        .top;
    TextPosition at(double y) =>
        editor.getPositionForOffset(editor.localToGlobal(Offset(5, y + shift)));
    // Row 3 of the paragraph, drawn at 140.
    expect(top(editor, at(145).offset), 140);
    // Just under the last row of page one: back on it.
    expect(top(editor, at(103).offset), 80);
    // Just above the first row of page two: on it.
    expect(top(editor, at(137).offset), 140);
    expect(at(145).offset, greaterThan(start));
  });

  testWidgets('the arrow down steps from the bottom of a page to the top of '
      'the next', (tester) async {
    final delta = Delta()
      ..insert('bir\niki\nuc\n')
      ..insert('$long\n');
    final (editor, controller) = await pump(tester, delta, focus: true);
    final start = 'bir\niki\nuc\n'.length;
    // The second row of the paragraph, the last of page one.
    final last = [
      for (var i = 0; i < long.length; i++)
        if (top(editor, start + i) == 80) start + i,
    ].first;
    controller.updateSelection(
      TextSelection.collapsed(offset: last),
      ChangeSource.local,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(top(editor, controller.selection.baseOffset), 140);
    // The caret blinks on a timer; the test ends with the editor gone.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a selection across the break has an end on each page', (
    tester,
  ) async {
    final delta = Delta()
      ..insert('bir\niki\nuc\n')
      ..insert('$long\n');
    final (editor, _) = await pump(tester, delta);
    final start = 'bir\niki\nuc\n'.length;
    final ends = editor.getEndpointsForSelection(
      TextSelection(baseOffset: start, extentOffset: start + long.length),
    );
    expect(ends.first.point.dy, lessThanOrEqualTo(100));
    expect(ends.last.point.dy, greaterThan(140));
  });

  testWidgets('without pages the lines run on in one column', (tester) async {
    final delta = Delta();
    for (var i = 0; i < 8; i++) {
      delta.insert('satir $i\n');
    }
    final controller = QuillController(
      document: Document.fromDelta(delta),
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: QuillEditor.basic(
              controller: controller,
              config: const QuillEditorConfig(
                scrollable: false,
                padding: EdgeInsets.zero,
                customStyles: DefaultStyles(
                  paragraph: DefaultTextBlockStyle(
                    TextStyle(fontSize: 20, height: 1),
                    HorizontalSpacing(0, 0),
                    VerticalSpacing(0, 0),
                    VerticalSpacing(0, 0),
                    null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final editor = tester.allRenderObjects.whereType<RenderEditor>().first;
    expect(top(editor, 5 * 'satir 0\n'.length), 100);
    expect(editor.pages, isNull);
  });
}

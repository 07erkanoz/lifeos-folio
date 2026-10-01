import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/ui/widgets/editor_line_layout.dart';
import 'package:evrak_convert/ui/widgets/editor_tab_spans.dart';
import 'package:evrak_convert/ui/widgets/editor_units.dart';

/// The test font draws every letter and space one em wide, so at 16 px a word
/// of four letters and its space take 80 px and a 480 px row holds six.
/// Thirty letters of the test font, which draws every letter an em wide,
/// at twelve point.
const _width = 360.0;

/// Points to layout pixels: the page is laid out in points.
const _px = EditorUnits.pixelsPerPoint;

Future<RenderEditor> _pump(
  WidgetTester tester,
  String text, {
  Map<String, Object?> layout = const {},
}) async {
  final controller = QuillController(
    document: Document.fromDelta(
      Delta()
        ..insert(text)
        ..insert('\n', {'doc-layout': layout}),
    ),
    selection: const TextSelection.collapsed(offset: 0),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery.withNoTextScaling(
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: _width,
              child: QuillEditor.basic(
                controller: controller,
                config: QuillEditorConfig(
                  textSpanBuilder: EditorTabSpans.builder(
                    pageWidth: _width / _px,
                  ),
                  lineLayoutBuilder: EditorLineLayout.builder(
                    pageWidth: _width / _px,
                  ),
                  scrollable: false,
                  expands: false,
                  padding: EdgeInsets.zero,
                  customStyles: const DefaultStyles(
                    paragraph: DefaultTextBlockStyle(
                      TextStyle(fontSize: 12, height: 1, color: Colors.black),
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
  return tester.allRenderObjects.whereType<RenderEditor>().first;
}

Rect _caret(RenderEditor editor, int offset) =>
    editor.getLocalRectForCaret(TextPosition(offset: offset));

void main() {
  const words = 'AAAA BBBB CCCC DDDD EEEE FFFF GGGG HHHH IIII JJJJ';

  testWidgets('every line but the first starts at the hanging indent', (
    tester,
  ) async {
    // A court decision's heading value, wrapping under itself: 60 pt, one
    // word of the test font in, so the second row holds four.
    final editor = await _pump(tester, words, layout: {'hanging': 60.0});
    final first = _caret(editor, 0);
    final second = _caret(editor, words.indexOf('GGGG'));
    expect(first.left, closeTo(0, .5));
    expect(second.top, greaterThan(first.top));
    expect(second.left, closeTo(60 * _px, .5));
    // Every word of the second row is where the indent puts it.
    expect(_caret(editor, words.indexOf('HHHH')).left, closeTo(120 * _px, .5));
    expect(_caret(editor, words.indexOf('JJJJ')).top, second.top);
  });

  testWidgets('a tap and the caret agree about the room put in', (
    tester,
  ) async {
    final editor = await _pump(tester, words, layout: {'hanging': 60.0});
    final second = _caret(editor, words.indexOf('HHHH'));
    // Where the caret is drawn is where a tap lands back on the document.
    final position = editor.getPositionForOffset(
      editor.localToGlobal(second.center),
    );
    expect(position.offset, words.indexOf('HHHH'));
  });

  testWidgets('a first line indent and a hanging one are each their own', (
    tester,
  ) async {
    final editor = await _pump(
      tester,
      words,
      layout: {'first': 30.0, 'hanging': 60.0},
    );
    expect(_caret(editor, 0).left, closeTo(30 * _px, .5));
    final wrapped = [
      for (var i = 0; i < words.length; i++)
        if (i == 0 || words[i - 1] == ' ') _caret(editor, i),
    ].where((r) => r.top > _caret(editor, 0).top);
    expect(wrapped, isNotEmpty);
    expect(wrapped.first.left, closeTo(60 * _px, .5));
  });

  testWidgets('a word with a slash in it moves down whole, as in UYAP', (
    tester,
  ) async {
    // Flutter would end the row on "FF/" and start the next with the rest;
    // UYAP breaks at spaces only.
    const text = 'AAAA BBBB CCCC DDDD EEEE FF/GGGGGGGG';
    final editor = await _pump(tester, text);
    final row = _caret(editor, 0).top;
    expect(_caret(editor, text.indexOf('FF/')).top, greaterThan(row));
    expect(
      _caret(editor, text.indexOf('GG')).top,
      _caret(editor, text.indexOf('FF/')).top,
    );
  });

  testWidgets('a line may break at the space before a slash or colon', (
    tester,
  ) async {
    // Unicode keeps "/Z01" on the line of the word before it, so Flutter
    // moved "FFFF /Z01" down together; UYAP leaves FFFF where it fits.
    const text = 'AAAA BBBB CCCC DDDD EEEE FFFF /Z01';
    final editor = await _pump(tester, text);
    final row = _caret(editor, 0).top;
    expect(_caret(editor, text.indexOf('FFFF')).top, row);
    expect(_caret(editor, text.indexOf('/Z01')).top, greaterThan(row));
    const colon = 'AAAA BBBB CCCC DDDD EEEE FFFF :GGG';
    final second = await _pump(tester, colon);
    expect(_caret(second, colon.indexOf('FFFF')).top, _caret(second, 0).top);
  });
}

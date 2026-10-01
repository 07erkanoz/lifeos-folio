import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/fonts/font_line_metrics.dart';
import 'package:evrak_convert/ui/widgets/editor_line_layout.dart';
import 'package:evrak_convert/ui/widgets/editor_list_marker.dart';
import 'package:evrak_convert/ui/widgets/editor_tab_spans.dart';
import 'package:evrak_convert/ui/widgets/editor_units.dart';

/// Points to the pixels the page is drawn in.
const px = EditorUnits.pixelsPerPoint;

/// Where the second paragraph starts in [document].
const second = 'Birinci paragraf\n'.length;

Delta document(Map<String, Object?> layout, {Map<String, Object?>? extra}) =>
    Delta()
      ..insert('Birinci paragraf\n')
      ..insert('İkinci paragraf')
      ..insert('\n', {'doc-layout': layout, ...?extra});

Future<RenderEditor> pump(
  WidgetTester tester,
  Delta delta, {
  bool runs = false,
}) async {
  final controller = QuillController(
    document: Document.fromDelta(delta),
    selection: const TextSelection.collapsed(offset: 0),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 600,
            child: QuillEditor.basic(
              controller: controller,
              config: QuillEditorConfig(
                lineLayoutBuilder: EditorLineLayout.of,
                textSpanBuilder: runs
                    ? EditorTabSpans.builder()
                    : defaultSpanBuilder,
                scrollable: false,
                expands: false,
                padding: EdgeInsets.zero,
                customStyles: const DefaultStyles(
                  paragraph: DefaultTextBlockStyle(
                    TextStyle(fontSize: 16, height: 1, color: Colors.black),
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
  );
  return tester.allRenderObjects.whereType<RenderEditor>().first;
}

Rect caret(RenderEditor editor, int offset) =>
    editor.getLocalRectForCaret(TextPosition(offset: offset));

void main() {
  test('points become pixels, and a plain line gets no indent', () {
    Line line(Delta delta) {
      final node = Document.fromDelta(delta).root.children.last;
      return node is Block ? node.children.first as Line : node as Line;
    }

    final layout = EditorLineLayout.of(
      line(
        document({
          'left': 25.0,
          'right': 10.0,
          'first': 35.4375,
          'before': 6.0,
          'after': 12.0,
        }),
      ),
    )!;
    expect(layout.horizontal!.left, closeTo(25 * px, 1e-9));
    expect(layout.horizontal!.right, closeTo(10 * px, 1e-9));
    // UYAP keeps indents in whole points, so 35.4375 is drawn at 35.
    expect(layout.firstLine, closeTo(35 * px, 1e-9));
    expect(layout.top, closeTo(6 * px, 1e-9));
    expect(layout.bottom, closeTo(12 * px, 1e-9));

    final plain = EditorLineLayout.of(line(document({})))!;
    expect(plain.horizontal!.left, 0);
    expect(plain.firstLine, 0);
    // A list item is set as UYAP sets it: from its left indent, its bullet
    // drawn in the indent rather than by Quill.
    final item = EditorLineLayout.of(
      line(document({'left': 25.0}, extra: {'list': 'bullet'})),
    )!;
    expect(item.horizontal!.left, closeTo(25 * px, 1e-9));
    expect(item.leading, isA<EditorListMarker>());
    // A hanging indent is drawn flush with the left indent, not pulled out.
    expect(
      EditorLineLayout.of(line(document({'first': -18.0})))?.firstLine ?? 0,
      0,
    );
  });

  test('an indent step pressed in the editor is the step the save writes', () {
    // Opened at 3 pt with no step, then indented once: the save makes that
    // 3 + 36 pt (DocDeltaMap.deltadanModel), so that is what is drawn.
    final line =
        Document.fromDelta(
              document({'left': 3.0, 'editorIndent': 0}, extra: {'indent': 1}),
            ).root.children.last
            as Block;
    final layout = EditorLineLayout.of(line.children.first as Line)!;
    expect(layout.horizontal!.left, closeTo(39 * px, 1e-9));
  });

  testWidgets('space above a paragraph pushes it down by that much', (
    tester,
  ) async {
    final plain = caret(await pump(tester, document({'left': 0.0})), second);
    final spaced = caret(
      await pump(tester, document({'before': 12.0})),
      second,
    );
    expect(spaced.top - plain.top, closeTo(12 * px, 0.01));
  });

  testWidgets('a justified paragraph gets its spacing too', (tester) async {
    // Aligned lines sit in a Quill block and are laid out by other code than
    // plain lines; half of the archive is justified.
    final plain = caret(
      await pump(tester, document({}, extra: {'align': 'justify'})),
      second,
    );
    final spaced = caret(
      await pump(
        tester,
        document({'before': 12.0, 'left': 25.0}, extra: {'align': 'justify'}),
      ),
      second,
    );
    expect(spaced.top - plain.top, closeTo(12 * px, 0.01));
    expect(spaced.left - plain.left, closeTo(25 * px, 0.01));
  });

  testWidgets('the first line starts at its indent and the caret knows it', (
    tester,
  ) async {
    final editor = await pump(tester, document({'first': 36.0}));
    final start = caret(editor, second);
    expect(start.left, closeTo(36 * px, 0.01));
    // The next character is one glyph further, not one glyph plus a
    // placeholder: document offsets do not count the indent.
    final next = caret(editor, second + 1);
    expect(next.left - start.left, closeTo(16, 0.5));

    // A click on the first character lands on it, and a click inside the
    // indent lands at the start of the paragraph, not in the one above.
    final y = start.center.dy;
    expect(editor.getPositionForOffset(Offset(36 * px + 4, y)).offset, second);
    expect(editor.getPositionForOffset(Offset(5, y)).offset, second);

    // Selecting the first character highlights that character.
    final points = editor.getEndpointsForSelection(
      const TextSelection(baseOffset: second, extentOffset: second + 1),
    );
    expect(points.first.point.dx, closeTo(36 * px, 0.5));
    expect(points.last.point.dx, closeTo(36 * px + 16, 0.5));
  });

  testWidgets('a left indent holds for every line and a right one narrows', (
    tester,
  ) async {
    final long = List.filled(40, 'kelime').join(' ');
    Delta wrapped(Map<String, Object?> layout) =>
        Delta()..insert('$long\n', {'doc-layout': layout});
    final plain = await pump(tester, wrapped({}));
    // The first character of the second visual line.
    int secondLineStart(RenderEditor editor) {
      final top = caret(editor, 0).top;
      for (var i = 1; i < long.length; i++) {
        if (caret(editor, i).top > top) return i;
      }
      fail('satır kırılmadı');
    }

    final plainBreak = secondLineStart(plain);
    final indented = await pump(tester, wrapped({'left': 25.0, 'right': 50.0}));
    final indentedBreak = secondLineStart(indented);
    expect(caret(indented, indentedBreak).left, closeTo(25 * px, 0.01));
    expect(indentedBreak, lessThan(plainBreak));
  });

  test('a row is read from the font file, gap included', () {
    final serif = FontLineMetrics.read(
      File('fonts/pdf/LiberationSerif-Regular.ttf')
          .readAsBytesSync()
          .buffer
          .asByteData(),
    )!;
    // hhea: ascender 1825, descender -443, line gap 87, 2048 units — what
    // Swing lays a Times New Roman row out from.
    expect(serif.natural, 2355 / 2048);
    expect(serif.tight, 2268 / 2048);
    expect(FontLineMetrics.read(ByteData(40)), isNull);
  });

  group('rows are as far apart as UYAP puts them', () {
    final long = List.filled(40, 'kelime').join(' ');
    Future<List<double>> rowTops(
      WidgetTester tester, {
      double? spacing,
      String size = '16.0',
    }) async {
      final editor = await pump(
        tester,
        Delta()
          ..insert(long, {'font': 'Times New Roman', 'size': size})
          ..insert('\n', {
            'doc-layout': {'line': ?spacing},
          }),
        runs: true,
      );
      final tops = <double>[];
      for (var i = 0; i < long.length; i++) {
        final top = caret(editor, i).top;
        if (tops.isEmpty || top > tops.last + 0.5) tops.add(top);
      }
      return tops;
    }

    for (final spacing in [null, 1.15, 1.5]) {
      testWidgets('LineSpacing ${(spacing ?? 1) - 1}', (tester) async {
        final tops = await rowTops(tester, spacing: spacing);
        expect(tops.length, greaterThan(2));
        // Twelve point, in whole points as UYAP lays it out: 14, 16 and 20
        // (test/fixtures/pages), in pixels.
        final pitch = FontLineMetrics.common.uyapRow(12, spacing) * px;
        // The test engine rounds a row to whole pixels.
        expect(tops[2] - tops[1], closeTo(pitch, 0.5));
      });
    }

    testWidgets('small type is not held to the paragraph default size', (
      tester,
    ) async {
      // 11 pt: the strut used to hold every row to 12 pt's height.
      // Kept as documents keep a run's size, in 96 dpi pixels.
      final tops = await rowTops(
        tester,
        spacing: 1.15,
        size: '${11 * EditorUnits.sizePixelsPerPoint}',
      );
      final pitch = FontLineMetrics.common.uyapRow(11, 1.15) * px;
      // 13 points, 17.3 px; held to the default size it came out at 21.
      expect(tops[2] - tops[1], closeTo(pitch, 0.5));
    });
  });
}

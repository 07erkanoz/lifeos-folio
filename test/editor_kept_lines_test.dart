import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
// ignore: implementation_imports
import 'package:flutter_quill/src/editor/widgets/text/text_line.dart';
import 'package:flutter_test/flutter_test.dart';

/// third_party/flutter_quill/FOLIO_PATCH.md: a line nothing of which
/// changed keeps its text as built; only its frame, the selection and the
/// caret, follows.
void main() {
  testWidgets('a key in one line builds that line alone; a line formatted '
      'or reached by the caret is drawn as it is now', (tester) async {
    final controller = QuillController(
      document: Document.fromDelta(
        Delta()..insert('Birinci satır\nİkinci satır\nÜçüncü satır\n'),
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuillEditor.basic(
            controller: controller,
            config: const QuillEditorConfig(autoFocus: true),
          ),
        ),
      ),
    );
    await tester.pump();

    final built = <String>[];
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is TextLine) {
        built.add((element.widget as TextLine).line.toPlainText().trim());
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    // Typed in the first: the others are not built again.
    controller.replaceText(7, 0, 'x', const TextSelection.collapsed(offset: 8));
    await tester.pump();
    expect(built, ['Birincix satır']);

    // The third made bold: drawn bold.
    built.clear();
    final third = controller.document.toPlainText().indexOf('Üçüncü');
    controller.formatText(third, 'Üçüncü satır'.length, Attribute.bold);
    await tester.pump();
    expect(built, ['Üçüncü satır']);
    final bold = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text)
        .whereType<TextSpan>()
        .expand((s) => [s, ...?s.children?.whereType<TextSpan>()])
        .where((s) => s.text?.contains('Üçüncü') ?? false);
    expect(bold.any((s) => s.style?.fontWeight == FontWeight.bold), isTrue);

    // The caret moved to the second: its line's frame knows, its text is
    // the same and not built again.
    built.clear();
    final secondAt = controller.document.toPlainText().indexOf('İkinci');
    controller.updateSelection(
      TextSelection.collapsed(offset: secondAt + 2),
      ChangeSource.local,
    );
    await tester.pump();
    expect(built, isEmpty);
    final editor = tester.allRenderObjects.whereType<RenderEditor>().first;
    final caret = editor.getLocalRectForCaret(
      TextPosition(offset: secondAt + 2),
    );
    final start = editor.getLocalRectForCaret(TextPosition(offset: secondAt));
    expect(caret.left, greaterThan(start.left));
    expect(tester.takeException(), isNull);
    // The caret's blinking let go of.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}

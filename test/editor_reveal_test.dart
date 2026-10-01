import 'dart:io';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/editor/text_anchor.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_shortcuts_test.dart' show waitFor;
import 'support/temp_directory.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    FlutterQuillLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

String _paragraph(int n) =>
    'Paragraf $n: davalı işveren $n. ay ücretini zamanında ödememiştir.';

/// The line of paragraph [n] the preview would read, pointing at "ücretini".
TextAnchor _anchor(int n, {required int page}) {
  final line = _paragraph(n);
  return TextAnchor(
    page: page,
    pages: 4,
    down: .5,
    line: line,
    at: line.indexOf('ücretini'),
  );
}

void main() {
  testWidgets('the editor opens at the line double-clicked in the preview, '
      'scrolled into view, and moves on a second double-click', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('editor-reveal-'),
    ))!;
    final previous = DocumentHistory.instance;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    addTearDown(() => DocumentHistory.instance = previous);
    final file = File('${dir.path}/uzun.udf');
    await tester.runAsync(
      () => file.writeAsBytes(
        UdfWriter.writeBytes(
          DocModel(
            blocks: [
              for (var n = 1; n <= 80; n++) DocBlock(plainText: _paragraph(n)),
            ],
          ),
        ),
      ),
    );

    Widget editor(TextAnchor anchor) => _app(
      EditorWidget(
        initialFilePath: file.path,
        initialFormat: EvrakFormat.udf,
        reveal: anchor,
      ),
    );
    QuillController controller() =>
        tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
    int target(int n) {
      final text = controller().document.toPlainText();
      return text.indexOf('ücretini', text.indexOf('Paragraf $n:'));
    }

    /// Where the caret is drawn, in the window.
    Offset caret() {
      final state = tester.state<EditorState>(find.byType(QuillRawEditor));
      final editor = state.renderEditor;
      final rect = editor.getLocalRectForCaret(
        TextPosition(offset: controller().selection.baseOffset),
      );
      return editor.localToGlobal(rect.center);
    }

    await tester.pumpWidget(editor(_anchor(60, page: 3)));
    await waitFor(
      tester,
      () =>
          find.byType(QuillEditor).evaluate().isNotEmpty &&
          controller().selection.baseOffset == target(60),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(controller().selection.isCollapsed, isTrue);
    // The page was scrolled to it: the caret is inside the window, well away
    // from its edges, although paragraph 60 starts far below the first view.
    expect(caret().dy, inInclusiveRange(150, 750));

    // Back in the preview and double-clicked again, further up.
    await tester.pumpWidget(editor(_anchor(12, page: 1)));
    await waitFor(
      tester,
      () => controller().selection.baseOffset == target(12),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(caret().dy, inInclusiveRange(150, 750));

    await tester.pumpWidget(const SizedBox());
    await removeTemporaryDirectory(tester, dir);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}

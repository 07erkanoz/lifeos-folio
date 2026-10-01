import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
// ignore: implementation_imports
import 'package:flutter_quill/src/editor/widgets/proxy.dart';
// ignore: implementation_imports
import 'package:flutter_quill/src/editor/widgets/text/text_line.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/editor/doc_delta_map.dart';
import 'package:evrak_convert/services/fonts/document_fonts.dart';
import 'package:evrak_convert/services/pdf/pdf_service.dart';
import 'package:evrak_convert/ui/widgets/editor_line_layout.dart';
import 'package:evrak_convert/ui/widgets/editor_pages.dart';
import 'package:evrak_convert/ui/widgets/editor_tab_spans.dart';

/// Sizes mixed on one page and in one paragraph: each row is as tall as the
/// tallest run on it, and the paragraph mark counts on the last row, in the
/// editor as in the preview.
void main() {
  setUpAll(() async {
    Future<void> family(String name, String file) async {
      final loader = FontLoader(name);
      for (final style in ['Regular', 'Bold', 'Italic', 'BoldItalic']) {
        loader.addFont(
          Future.value(
            ByteData.sublistView(
              File('fonts/pdf/$file-$style.ttf').readAsBytesSync(),
            ),
          ),
        );
      }
      await loader.load();
    }

    await family(DocumentFonts.family('Times New Roman'), 'LiberationSerif');
    await family(DocumentFonts.family('Arial'), 'LiberationSans');
  });

  String words(int count, String seed) =>
      List.generate(count, (i) => '$seed${i % 7}').join(' ');

  DocBlock sized(
    String text,
    List<(int, int, double, String?)> runs, {
    double? end,
    double? lineSpacing,
  }) => DocBlock(
    plainText: text,
    alignment: DocAlignment.justify,
    lineSpacing: lineSpacing,
    endFontSize: end,
    endFontFamily: end == null ? null : 'Times New Roman',
    spans: [
      for (final (start, length, size, family) in runs)
        DocSpan(
          startOffset: start,
          length: length,
          fontSize: size,
          fontFamily: family ?? 'Times New Roman',
        ),
    ],
  );

  testWidgets('rows of mixed sizes are as tall in the editor as on the page', (
    tester,
  ) async {
    final a = words(60, 'metin');
    final b = words(30, 'büyük');
    final c = words(8, 'kısa');
    final d = words(50, 'karışık');
    final e = words(50, 'yazı');
    DocModel model() => DocModel(
      blocks: [
        // 12 pt with one 16 pt stretch in its second row.
        sized(a, [
          (0, 110, 12, null),
          (110, 12, 16, null),
          (122, a.length - 122, 12, null),
        ], end: 12),
        // All 16 pt.
        sized(b, [(0, b.length, 16, null)], end: 16),
        // 12 pt text whose paragraph mark is 16 pt.
        sized(c, [(0, c.length, 12, null)], end: 16),
        // 20 pt and 10 pt, at one and a half lines.
        sized(
          d,
          [
            (0, 150, 10, null),
            (150, 20, 20, null),
            (170, d.length - 170, 10, null),
          ],
          end: 10,
          lineSpacing: 1.5,
        ),
        // Arial 16 among Times 12.
        sized(e, [
          (0, 60, 12, null),
          (60, 30, 16, 'Arial'),
          (90, e.length - 90, 12, null),
        ], end: 12),
      ],
    );

    final pdfRows = (await tester.runAsync(
      () => PdfService.bodyRows(model()),
    ))!;
    final page = model().pageProperties;
    final width =
        EditorPages.sheet(page).width - page.marginLeft - page.marginRight;
    final mapped = DocDeltaMap.modeldenDelta(model());
    final controller = QuillController(
      document: Document.fromDelta(mapped.delta),
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width.ceilToDouble(),
                child: QuillEditor.basic(
                  controller: controller,
                  config: QuillEditorConfig(
                    textSpanBuilder: EditorTabSpans.builder(pageWidth: width),
                    lineLayoutBuilder: EditorLineLayout.builder(
                      pageWidth: width,
                    ),
                    scrollable: false,
                    expands: false,
                    padding: EdgeInsets.zero,
                    customStyles: DefaultStyles(
                      paragraph: DefaultTextBlockStyle(
                        TextStyle(
                          color: Colors.black,
                          fontFamily: DocumentFonts.family('Times New Roman'),
                          fontSize: 12,
                          height: 1.15,
                        ),
                        const HorizontalSpacing(0, 0),
                        const VerticalSpacing(0, 0),
                        const VerticalSpacing(0, 0),
                        null,
                      ),
                    ),
                    customStyleBuilder: (attribute) => attribute.key == 'font'
                        ? TextStyle(
                            fontFamily: DocumentFonts.family(
                              attribute.value as String?,
                            ),
                          )
                        : const TextStyle(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final lines = <RenderEditableTextLine>[];
    void collect(RenderObject o) {
      if (o is RenderEditableTextLine) {
        lines.add(o);
        return;
      }
      o.visitChildren(collect);
    }

    tester.allRenderObjects.whereType<RenderEditor>().first.visitChildren(
      collect,
    );
    for (var block = 0; block < 5; block++) {
      RenderParagraphProxy? proxy;
      void find(RenderObject o) {
        if (o is RenderParagraphProxy) {
          proxy = o;
          return;
        }
        o.visitChildren(find);
      }

      lines[block].visitChildren(find);
      final editor = [for (final r in proxy!.rows) r.bottom - r.top];
      final pdf = [
        for (final r in pdfRows)
          if (r.block == block) r.height,
      ];
      expect(editor, pdf, reason: 'paragraf $block');
    }
    // The stretch of 16 pt makes its row taller than the 12 pt rows
    // around it, and only that row.
    final first = [
      for (final r in pdfRows)
        if (r.block == 0) r.height,
    ];
    expect(first.toSet(), {14.0, 19.0});
  });
}

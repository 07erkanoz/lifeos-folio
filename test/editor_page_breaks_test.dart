import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/editor/doc_delta_map.dart';
import 'package:evrak_convert/services/fonts/document_fonts.dart';
import 'package:evrak_convert/services/pdf/pdf_service.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/ui/widgets/editor_line_layout.dart';
import 'package:evrak_convert/ui/widgets/editor_pages.dart';
import 'package:evrak_convert/ui/widgets/editor_tab_spans.dart';
import 'package:evrak_convert/ui/widgets/editor_table_embed.dart';

/// Where UYAP's own editor starts each page, held against Folio's editor:
/// the same synthetic documents and measurements as page_breaks_test,
/// which holds the PDF to them.
///
/// Laid out in Liberation Serif, whose widths are Times New Roman's, so a
/// long paragraph breaks into the rows UYAP's does.
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

  final expected =
      (jsonDecode(File('test/fixtures/pages/pages.json').readAsStringSync())
              as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as List).cast<String>()));

  String squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  for (final MapEntry(key: name, value: starts) in expected.entries) {
    testWidgets('pages start where UYAP starts them: $name', (tester) async {
      final model = UdfReader.readBytes(
        File('test/fixtures/pages/udf/$name').readAsBytesSync(),
      )!;
      final page = model.pageProperties;
      // The header and footer as tall as the preview measures them.
      final regions = (await tester.runAsync(
        () => PdfService.regionHeights(model),
      ))!;
      final pages = EditorPages.geometry(
        page,
        header: regions.header,
        footer: regions.footer,
      );
      final width =
          EditorPages.sheet(page).width - page.marginLeft - page.marginRight;
      final mapped = DocDeltaMap.modeldenDelta(model);
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
                  width: width * EditorPages.pixelsPerPoint,
                  child: QuillEditor.basic(
                    controller: controller,
                    config: QuillEditorConfig(
                      pages: pages,
                      textSpanBuilder: EditorTabSpans.builder(pageWidth: width),
                      lineLayoutBuilder: EditorLineLayout.builder(
                        pageWidth: width,
                      ),
                      embedBuilders: [
                        EditorTableEmbed(
                          blocks: () => mapped.korunanlar,
                          onChanged: (_, _) {},
                          onFocus: (_) {},
                          onDelete: (_) {},
                          onCellsGone: () {},
                          onPointerInside: () {},
                        ),
                      ],
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
      // The body's editor, and one in every table cell.
      final editors = tester.allRenderObjects.whereType<RenderEditor>();
      final body = editors.first;
      // Where every character is drawn, table cells and all, and the first
      // on each page.
      final drawn = <({double top, double x, String rest})>[];
      for (final editor in editors) {
        final text = editor.document.toPlainText();
        for (var i = 0; i < text.length; i++) {
          if (text[i] == '\n' || text[i] == '\uFFFC') continue;
          final caret = editor.getLocalRectForCaret(TextPosition(offset: i));
          final at = body.globalToLocal(editor.localToGlobal(caret.topLeft));
          drawn.add((
            top: at.dy,
            x: at.dx,
            rest: text.substring(i).split('\n').first,
          ));
        }
      }
      // Row by row, and along each row from the left.
      drawn.sort(
        (a, b) => (a.top - b.top).abs() > 1
            ? a.top.compareTo(b.top)
            : a.x.compareTo(b.x),
      );
      final first = <int, String>{};
      for (final d in drawn) {
        first.putIfAbsent(pages.pageOf(d.top + 1), () => d.rest);
      }
      final got = [
        for (final page in first.keys.toList()..sort()) first[page]!,
      ];
      final want = [for (final s in starts) squash(s)];
      expect(got.length, want.length, reason: 'sayfa sayısı: $got');
      for (var i = 0; i < want.length; i++) {
        // An empty paragraph starting a page draws no text.
        if (want[i].isEmpty) continue;
        expect(
          squash(got[i]).startsWith(want[i]),
          isTrue,
          reason: 'sayfa ${i + 1} "${want[i]}" ile başlamalı, "${got[i]}"',
        );
      }
    });
  }
}

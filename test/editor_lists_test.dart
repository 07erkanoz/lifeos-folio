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
import 'package:evrak_convert/services/layout/list_markers.dart';
import 'package:evrak_convert/services/pdf/pdf_service.dart';
import 'package:evrak_convert/ui/widgets/editor_line_layout.dart';
import 'package:evrak_convert/ui/widgets/editor_list_marker.dart';
import 'package:evrak_convert/ui/widgets/editor_pages.dart';
import 'package:evrak_convert/ui/widgets/editor_tab_spans.dart';

/// A list as UYAP sets it, in the editor as in the preview: each item laid
/// out as a paragraph from its left indent, its rows breaking where the
/// preview's do, and numbered as UYAP numbers it.
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

  const long =
      'Davacı vekili dava dilekçesinde özetle müvekkilinin davalı şirkette '
      'uzun yıllar çalıştığını, iş akdinin haksız olarak feshedildiğini ve '
      'alacaklarının ödenmediğini ileri sürmüştür.';
  DocBlock item(String text, {bool numbered = true, String? kind}) => DocBlock(
    type: DocBlockType.listItem,
    plainText: text,
    alignment: DocAlignment.justify,
    listType: numbered ? DocListType.ordered : DocListType.unordered,
    listId: numbered ? 1 : 2,
    listLevel: 1,
    leftIndent: 25,
    numberType: numbered ? kind : null,
    bulletType: numbered ? null : kind,
    spans: [DocSpan(startOffset: 0, length: text.length, fontSize: 12)],
  );

  testWidgets('list items break and number in the editor as on the page', (
    tester,
  ) async {
    DocModel model() => DocModel(
      blocks: [
        DocBlock(plainText: 'Talepler:'),
        item('Birinci madde', kind: 'NUMBER_TYPE_NUMBER_TRE'),
        item(long, kind: 'NUMBER_TYPE_NUMBER_TRE'),
        item('Üçüncü madde', kind: 'NUMBER_TYPE_NUMBER_TRE'),
        item('Nokta', numbered: false, kind: 'BULLET_TYPE_ELLIPSE'),
        item(long, numbered: false, kind: 'BULLET_TYPE_ARROW'),
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
                      lists: DefaultListBlockStyle(
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
                        null,
                      ),
                      indent: DefaultTextBlockStyle(
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
    for (var block = 0; block < 6; block++) {
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
    // Laid out as the page lays them out: the long item in two rows.
    expect(
      [
        for (final r in pdfRows)
          if (r.block == 2) r.offset,
      ],
      [0, 104],
    );
    // Numbered as UYAP numbers them, and the bullets as bullets.
    final markers = tester
        .widgetList<EditorListMarker>(find.byType(EditorListMarker))
        .toList();
    expect(markers.map((m) => m.label).toList(), [
      '1-',
      '2-',
      '3-',
      null,
      null,
    ]);
    expect(markers[3].shape, BulletShape.circle);
    expect(markers[4].shape, BulletShape.arrow);
    // From the text's start, where UYAP draws it.
    expect(markers.first.textStart, 25);
  });
}

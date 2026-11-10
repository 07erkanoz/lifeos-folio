import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/docx/docx_bridge.dart';
import 'package:evrak_convert/services/editor/doc_delta_map.dart';
import 'package:evrak_convert/services/html/html_reader.dart';
import 'package:evrak_convert/services/html/html_writer.dart';
import 'package:evrak_convert/services/pdf/pdf_service.dart';
import 'package:evrak_convert/services/rtf/rtf_reader.dart';
import 'package:evrak_convert/services/rtf/rtf_writer.dart';
import 'package:evrak_convert/ui/widgets/editor_pages.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

// Where Word starts a new page: a page break, a paragraph's "page break
// before", a section that begins on a new page. Kept through the editor,
// written back, and printed on a page of its own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mark = '<w:r><w:t></w:t></w:r>';
  String marks(String xml) =>
      utf8.decode(DocxBridge.pageBreaksAsMarks(utf8.encode(xml)));
  String p(String text, {String pPr = '', String before = ''}) =>
      '<w:p>$pPr$before<w:r><w:t>$text</w:t></w:r></w:p>';
  const pageBreak = '<w:r><w:br w:type="page"/></w:r>';

  test('a page break after a paragraph\'s text marks the next paragraph; '
      'before its text, the paragraph itself', () {
    expect(
      marks('<w:p><w:r><w:t>Bir</w:t></w:r>$pageBreak</w:p>${p('İki')}'),
      '${p('Bir')}<w:p>$mark<w:r><w:t>İki</w:t></w:r></w:p>',
    );
    expect(
      marks('${p('Bir')}${p('İki', before: pageBreak)}'),
      '${p('Bir')}<w:p>$mark<w:r><w:t>İki</w:t></w:r></w:p>',
    );
    // A paragraph of the break alone: the one after it starts the page.
    expect(
      marks('${p('Bir')}<w:p>$pageBreak</w:p>${p('İki')}'),
      '${p('Bir')}<w:p></w:p><w:p>$mark<w:r><w:t>İki</w:t></w:r></w:p>',
    );
  });

  test('"page break before" marks its paragraph; a section that goes on on '
      'the same page marks none, one that does not marks what follows', () {
    expect(
      marks(p('Bir') + p('İki', pPr: '<w:pPr><w:pageBreakBefore/></w:pPr>')),
      contains('<w:pPr><w:pageBreakBefore/></w:pPr>$mark<w:r><w:t>İki'),
    );
    String sections(String type) => marks(
      '${p('Bir', pPr: '<w:pPr><w:sectPr><w:pgSz/></w:sectPr></w:pPr>')}'
      '${p('İki')}<w:sectPr>$type<w:pgSz/></w:sectPr>',
    );
    expect(sections('<w:type w:val="continuous"/>'), isNot(contains(mark)));
    expect(sections(''), contains('<w:p>$mark<w:r><w:t>İki'));
    // Nothing to mark: the bytes as they were.
    expect(marks(p('Bir') + p('İki')), p('Bir') + p('İki'));
  });

  test('a page break survives the editor and Word, and prints on a page of '
      'its own', () async {
    final model = DocModel(
      blocks: [
        DocBlock(plainText: 'Birinci sayfa'),
        DocBlock(plainText: 'İkinci sayfa', pageBreakBefore: true),
      ],
    );
    final quill = DocDeltaMap.modeldenDelta(model);
    final edited = DocDeltaMap.deltadanModel(
      quill.delta,
      korunanlar: quill.korunanlar,
    );
    expect(edited.blocks.map((b) => b.pageBreakBefore), [false, true]);

    final again = await DocxBridge.readBytes(
      await DocxBridge.writeBytes(edited),
    );
    expect(again!.blocks.map((b) => b.plainText), [
      'Birinci sayfa',
      'İkinci sayfa',
    ]);
    expect(again.blocks.map((b) => b.pageBreakBefore), [false, true]);

    int pages(DocModel m, List<int> pdf) =>
        RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(pdf)).length;
    expect(pages(again, await PdfService.modelToPdfBytes(again)), 2);
    expect(
      pages(
        model,
        await PdfService.modelToPdfBytes(
          DocModel(
            blocks: [
              DocBlock(plainText: 'Birinci sayfa'),
              DocBlock(plainText: 'İkinci sayfa'),
            ],
          ),
        ),
      ),
      1,
    );
  });
  test('a page break is written to RTF and HTML and read back; a break '
      'inside an RTF paragraph starts the page with the next one', () {
    final model = DocModel(
      blocks: [
        DocBlock(plainText: 'Birinci sayfa'),
        DocBlock(plainText: 'İkinci sayfa', pageBreakBefore: true),
        DocBlock(plainText: 'Yine ikinci'),
      ],
    );
    final rtf = RtfWriter.write(model);
    expect(rtf, contains(r'\pagebb'));
    expect(
      RtfReader.readBytes(utf8.encode(rtf))!.blocks
          .map((b) => b.pageBreakBefore),
      [false, true, false],
    );
    final broken = RtfReader.readBytes(
      latin1.encode(r'{\rtf1\ansi Bir\page\par Iki\par\page Uc\par}'),
    )!;
    expect(broken.blocks.map((b) => b.plainText), ['Bir', 'Iki', 'Uc']);
    expect(broken.blocks.map((b) => b.pageBreakBefore), [false, true, true]);

    final html = HtmlWriter.document(model);
    expect(html, contains('page-break-before:always'));
    expect(HtmlReader.read(html).blocks.map((b) => b.pageBreakBefore), [
      false,
      true,
      false,
    ]);
  });

  testWidgets('in the editor the paragraph that starts a page is at the top '
      'of the next one', (tester) async {
    const page = DocPageProperties();
    final pages = EditorPages.geometry(page);
    Future<double> secondTop({required bool broken}) async {
      final mapped = DocDeltaMap.modeldenDelta(
        DocModel(
          blocks: [
            DocBlock(plainText: 'Birinci sayfa'),
            DocBlock(plainText: 'İkinci sayfa', pageBreakBefore: broken),
          ],
        ),
      );
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
          key: ValueKey(broken),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 600,
                  child: QuillEditor.basic(
                    controller: controller,
                    config: QuillEditorConfig(
                      pages: pages,
                      scrollable: false,
                      expands: false,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final editor = tester.allRenderObjects.whereType<RenderEditor>().first;
      return editor
          .getLocalRectForCaret(
            TextPosition(offset: 'Birinci sayfa'.length + 1),
          )
          .top;
    }

    final plain = await secondTop(broken: false);
    expect(pages.pageOf(plain), 0);
    final broken = await secondTop(broken: true);
    expect(pages.pageOf(broken), 1);
    expect(broken, closeTo(pages.topOf(1), 1));
  });
  testWidgets('Ctrl+Enter in the editor: what follows the cursor starts a '
      'page; again at its start, it no longer does', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('editor-break-'),
    ))!;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    final file = File('${dir.path}/belge.docx');
    await tester.runAsync(
      () async => file.writeAsBytes(
        await DocxBridge.writeBytes(
          DocModel(blocks: [DocBlock(plainText: 'Birinci İkinci')]),
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
          body: EditorWidget(
            initialFilePath: file.path,
            initialFormat: EvrakFormat.docx,
          ),
        ),
      ),
    );
    for (var i = 0; i < 400; i++) {
      if (find.byType(QuillEditor).evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    final controller = tester
        .widget<QuillEditor>(find.byType(QuillEditor))
        .controller;
    Future<void> press() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    List<bool> breaks() => [
      for (final op in controller.document.toDelta().toList())
        if (op.data == '\n' || (op.data as String).endsWith('\n'))
          (op.attributes?['doc-layout'] as Map?)?['break'] == true,
    ];

    await tester.tap(find.byType(QuillEditor));
    await tester.pump();
    controller.updateSelection(
      const TextSelection.collapsed(offset: 'Birinci '.length),
      ChangeSource.local,
    );
    await press();
    expect(controller.document.toPlainText(), 'Birinci \nİkinci\n');
    expect(breaks(), [false, true]);
    // At the start of the paragraph that starts the page: taken off.
    expect(controller.selection.baseOffset, 'Birinci \n'.length);
    await press();
    expect(controller.document.toPlainText(), 'Birinci \nİkinci\n');
    expect(breaks(), [false, false]);
    await tester.pumpWidget(const SizedBox.shrink());
    // The draft's and the spell check's timers run out.
    await tester.pump(const Duration(seconds: 30));
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}

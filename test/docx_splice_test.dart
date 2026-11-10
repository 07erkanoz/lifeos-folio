import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/docx/docx_bridge.dart';
import 'package:evrak_convert/services/docx/docx_splice.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// A Word file saved into the file it was opened from: what the editor has
// no place for (a style's name, a comment, a bookmark, Word's own parts)
// is still there after a save, and only what was touched is written anew.

const _w =
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';

const _heading =
    '<w:p w:rsidR="00AA11BB"><w:pPr><w:pStyle w:val="Balk1"/></w:pPr>'
    '<w:bookmarkStart w:id="0" w:name="_Toc1"/><w:r><w:t>Açıklamalar</w:t></w:r>'
    '<w:bookmarkEnd w:id="0"/></w:p>';
const _commented =
    '<w:p><w:pPr><w:jc w:val="both"/></w:pPr><w:commentRangeStart w:id="1"/>'
    '<w:r><w:t>Davalı kira bedelini ödememiştir.</w:t></w:r>'
    '<w:commentRangeEnd w:id="1"/><w:r><w:commentReference w:id="1"/></w:r>'
    '</w:p>';
const _plain =
    '<w:p><w:pPr><w:pStyle w:val="GvdeMetni"/><w:spacing w:after="120"/>'
    '</w:pPr><w:r><w:t xml:space="preserve">Kira sözleşmesi </w:t></w:r>'
    '<w:r><w:rPr><w:b/></w:rPr><w:t>01.01.2025</w:t></w:r>'
    '<w:r><w:t xml:space="preserve"> tarihlidir.</w:t></w:r></w:p>';
const _last = '<w:p><w:r><w:t>Saygılarımla.</w:t></w:r></w:p>';
const _section =
    '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1417" '
    'w:right="1417" w:bottom="1417" w:left="1417" w:header="708" '
    'w:footer="708" w:gutter="0"/></w:sectPr>';

const _listItem =
    '<w:p><w:pPr><w:pStyle w:val="ListeParagraf"/><w:numPr><w:ilvl w:val="0"/>'
    '<w:numId w:val="5"/></w:numPr></w:pPr><w:r><w:t>Kira bedeli</w:t></w:r>'
    '</w:p>';
const _landscape =
    '<w:p><w:pPr><w:sectPr><w:pgSz w:w="16838" w:h="11906" w:orient='
    '"landscape"/></w:sectPr></w:pPr><w:r><w:t>Ek tablo sayfası</w:t></w:r>'
    '</w:p>';

Uint8List _word({String? body, bool numbering = false}) {
  ArchiveFile file(String name, String content) =>
      ArchiveFile(name, 0, utf8.encode(content));
  const head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
  final archive = Archive()
    ..addFile(
      file(
        '[Content_Types].xml',
        '$head<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
            'content-types"><Default Extension="rels" ContentType="application/'
            'vnd.openxmlformats-package.relationships+xml"/><Default Extension='
            '"xml" ContentType="application/xml"/><Override PartName="/word/'
            'document.xml" ContentType="application/vnd.openxmlformats-'
            'officedocument.wordprocessingml.document.main+xml"/><Override '
            'PartName="/word/styles.xml" ContentType="application/vnd.'
            'openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
            '<Override PartName="/word/comments.xml" ContentType="application/'
            'vnd.openxmlformats-officedocument.wordprocessingml.comments+xml"/>'
            '</Types>',
      ),
    )
    ..addFile(
      file(
        '_rels/.rels',
        '$head<Relationships xmlns="http://schemas.openxmlformats.org/package/'
            '2006/relationships"><Relationship Id="rId1" Type="http://schemas.'
            'openxmlformats.org/officeDocument/2006/relationships/'
            'officeDocument" Target="word/document.xml"/></Relationships>',
      ),
    )
    ..addFile(
      file(
        'word/_rels/document.xml.rels',
        '$head<Relationships xmlns="http://schemas.openxmlformats.org/package/'
            '2006/relationships"><Relationship Id="rId1" Type="http://schemas.'
            'openxmlformats.org/officeDocument/2006/relationships/styles" '
            'Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.'
            'openxmlformats.org/officeDocument/2006/relationships/comments" '
            'Target="comments.xml"/></Relationships>',
      ),
    )
    ..addFile(
      file(
        'word/styles.xml',
        '$head<w:styles $_w><w:style w:type="paragraph" w:default="1" '
            'w:styleId="Normal"><w:name w:val="Normal"/></w:style><w:style '
            'w:type="paragraph" w:styleId="Balk1"><w:name w:val="heading 1"/>'
            '<w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="32"/></w:rPr>'
            '</w:style><w:style w:type="paragraph" w:styleId="GvdeMetni">'
            '<w:name w:val="Body Text"/><w:basedOn w:val="Normal"/></w:style>'
            '</w:styles>',
      ),
    )
    ..addFile(
      file(
        'word/comments.xml',
        '$head<w:comments $_w><w:comment w:id="1" w:author="Av. Deniz" '
            'w:initials="AD"><w:p><w:r><w:t>Ödeme dekontu eklenecek.</w:t></w:r>'
            '</w:p></w:comment></w:comments>',
      ),
    )
    ..addFile(
      file(
        'word/document.xml',
        '$head<w:document $_w><w:body>'
            '${body ?? '$_heading$_commented$_plain$_last'}'
            '$_section</w:body></w:document>',
      ),
    );
  if (numbering) {
    archive.addFile(
      file(
        'word/numbering.xml',
        '$head<w:numbering $_w><w:abstractNum w:abstractNumId="9">'
            '<w:multiLevelType w:val="hybridMultilevel"/><w:lvl w:ilvl="0">'
            '<w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText '
            'w:val="%1)"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="720" '
            'w:hanging="360"/></w:pPr></w:lvl></w:abstractNum><w:num '
            'w:numId="5"><w:abstractNumId w:val="9"/></w:num></w:numbering>',
      ),
    );
    final rels = archive.findFile('word/_rels/document.xml.rels')!;
    final text = utf8
        .decode(rels.content as List<int>)
        .replaceFirst(
          '</Relationships>',
          '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/'
              'officeDocument/2006/relationships/numbering" Target='
              '"numbering.xml"/></Relationships>',
        );
    archive
      ..removeFile(rels)
      ..addFile(file('word/_rels/document.xml.rels', text));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

List<String> _names(List<int> zip) => [
  for (final f in ZipDecoder().decodeBytes(zip).files)
    if (f.isFile) f.name,
];

String _part(List<int> zip, String name) => utf8.decode(
  ZipDecoder().decodeBytes(zip).findFile(name)!.content as List<int>,
);

DocBlock _reworded(DocBlock b, String text) => DocBlock(
  type: b.type,
  alignment: b.alignment,
  plainText: text,
  listType: b.listType,
  listLevel: b.listLevel,
  listId: b.listId,
  leftIndent: b.leftIndent,
  rightIndent: b.rightIndent,
  firstLineIndent: b.firstLineIndent,
  hanging: b.hanging,
  spacingBefore: b.spacingBefore,
  spacingAfter: b.spacingAfter,
  styleName: b.styleName,
  tabSet: b.tabSet,
  lineSpacing: b.lineSpacing,
  endFontSize: b.endFontSize,
  endFontFamily: b.endFontFamily,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List word;
  late DocModel opened;
  setUp(() async {
    word = _word();
    opened = DocxSplice.throughEditor((await DocxBridge.readBytes(word))!);
  });

  DocModel withBlocks(List<DocBlock> blocks) => DocModel(
    blocks: blocks,
    metadata: opened.metadata,
    pageProperties: opened.pageProperties,
    pageRegions: opened.pageRegions,
    styles: opened.styles,
  );

  test('saved with nothing done to it, the document part is byte for byte '
      'what it was, and so is every other part', () async {
    final saved = (await DocxSplice.save(word, opened))!;
    for (final name in [
      'word/document.xml',
      'word/styles.xml',
      'word/comments.xml',
      'word/_rels/document.xml.rels',
      '[Content_Types].xml',
    ]) {
      expect(_part(saved, name), _part(word, name), reason: name);
    }
  });

  test('one paragraph\'s words changed: the others keep their bytes, the '
      'comment and the heading\'s style with them; the changed one keeps '
      'its own style and spacing', () async {
    final blocks = [...opened.blocks];
    expect(blocks[2].plainText, 'Kira sözleşmesi 01.01.2025 tarihlidir.');
    blocks[2] = DocxSplice.throughEditor(
      withBlocks([_reworded(blocks[2], 'Kira sözleşmesi feshedilmiştir.')]),
    ).blocks.single;
    final saved = (await DocxBridge.writeBytes(
      withBlocks(blocks),
      original: word,
    ));
    final document = _part(saved, 'word/document.xml');
    expect(document, contains(_heading));
    expect(document, contains(_commented));
    expect(document, contains(_last));
    expect(document, contains(_section));
    expect(document, isNot(contains('01.01.2025')));
    expect(document, contains('feshedilmiştir'));
    // Its own properties, as Word wrote them.
    expect(
      document,
      contains(
        '<w:p><w:pPr><w:pStyle w:val="GvdeMetni"/><w:spacing w:after="120"/>'
        '</w:pPr>',
      ),
    );
    expect(_part(saved, 'word/comments.xml'), _part(word, 'word/comments.xml'));
    expect(_part(saved, 'word/styles.xml'), _part(word, 'word/styles.xml'));
    final back = (await DocxBridge.readBytes(saved))!;
    expect(back.blocks.map((b) => b.plainText), [
      'Açıklamalar',
      'Davalı kira bedelini ödememiştir.',
      'Kira sözleşmesi feshedilmiştir.',
      'Saygılarımla.',
    ]);
  });

  test('a paragraph put in and one taken out: the rest as they were', () async {
    final added = DocxSplice.throughEditor(
      withBlocks([DocBlock(plainText: 'Yeni eklenen paragraf.')]),
    ).blocks.single;
    final blocks = [
      opened.blocks[0],
      added,
      opened.blocks[1],
      opened.blocks[3],
    ];
    final saved = (await DocxSplice.save(word, withBlocks(blocks)))!;
    final document = _part(saved, 'word/document.xml');
    expect(document, contains(_heading));
    expect(document, contains(_commented));
    expect(document, contains(_last));
    expect(document, isNot(contains('01.01.2025')));
    expect(
      document.indexOf('Açıklamalar') < document.indexOf('Yeni eklenen') &&
          document.indexOf('Yeni eklenen') < document.indexOf('Davalı kira'),
      isTrue,
    );
  });

  DocBlock through(DocBlock block) =>
      DocxSplice.throughEditor(withBlocks([block])).blocks.single;

  test('a list item, a link, a picture and a table put in: each comes with '
      'what it needs, and the rest keep their bytes', () async {
    final png = base64Encode(img.encodePng(img.Image(width: 4, height: 4)));
    final blocks = [
      ...opened.blocks.take(2),
      through(
        DocBlock(
          plainText: 'Birinci madde',
          type: DocBlockType.listItem,
          listType: DocListType.ordered,
          listId: 7,
        ),
      ),
      through(
        DocBlock(
          plainText: 'Karar için tıklayın.',
          spans: const [
            DocSpan(
              startOffset: 11,
              length: 8,
              link: 'https://karararama.yargitay.gov.tr/?a=1&b=2',
            ),
          ],
        ),
      ),
      DocBlock(
        type: DocBlockType.image,
        plainText: '',
        imageBase64: png,
        imageMime: 'image/png',
        imageWidth: 40,
        imageHeight: 40,
      ),
      DocBlock(
        type: DocBlockType.table,
        plainText: '',
        table: DocTable(
          rows: [
            DocTableRow(
              cells: [
                DocTableCell(blocks: [DocBlock(plainText: 'Ay')]),
                DocTableCell(blocks: [DocBlock(plainText: 'Tutar')]),
              ],
            ),
          ],
        ),
      ),
      ...opened.blocks.skip(2),
    ];
    final saved = (await DocxSplice.save(word, withBlocks(blocks)))!;
    final document = _part(saved, 'word/document.xml');
    for (final kept in [_heading, _commented, _plain, _last, _section]) {
      expect(document, contains(kept));
    }
    expect(_part(saved, 'word/comments.xml'), _part(word, 'word/comments.xml'));
    // The list's numbering, which the file did not have; the link's
    // address; the picture's file; the table's style.
    final names = _names(saved);
    expect(names, contains('word/numbering.xml'));
    expect(names.where((n) => n.startsWith('word/media/')), hasLength(1));
    final rels = _part(saved, 'word/_rels/document.xml.rels');
    expect(rels, contains('relationships/numbering'));
    expect(rels, contains('karararama.yargitay.gov.tr/?a=1&amp;b=2'));
    expect(rels, contains('relationships/image'));
    final types = _part(saved, '[Content_Types].xml');
    expect(types, contains('Extension="png"'));
    expect(types, contains('/word/numbering.xml'));
    expect(_part(saved, 'word/styles.xml'), contains('w:styleId="TableGrid"'));
    // The original's own styles are still there.
    expect(_part(saved, 'word/styles.xml'), contains('w:styleId="Balk1"'));

    final back = (await DocxBridge.readBytes(saved))!;
    expect(back.blocks.map((b) => b.type), [
      DocBlockType.paragraph,
      DocBlockType.paragraph,
      DocBlockType.listItem,
      DocBlockType.paragraph,
      DocBlockType.image,
      DocBlockType.table,
      DocBlockType.paragraph,
      DocBlockType.paragraph,
    ]);
    expect(back.blocks[2].listType, DocListType.ordered);
    expect(
      back.blocks[3].spans.map((s) => s.link).nonNulls.single,
      'https://karararama.yargitay.gov.tr/?a=1&b=2',
    );
    expect(back.blocks[4].imageBase64, isNotEmpty);
    expect(back.blocks[5].table!.rows.single.cells.length, 2);
  });

  test(
    'an item put into a list goes on with that list\'s own numbering',
    () async {
      final listed = _word(body: '$_heading$_listItem$_last', numbering: true);
      final was = DocxSplice.throughEditor(
        (await DocxBridge.readBytes(listed))!,
      );
      expect(was.blocks[1].listType, DocListType.ordered);
      final item = DocxSplice.throughEditor(
        DocModel(
          blocks: [
            DocBlock(
              plainText: 'Depozito',
              type: DocBlockType.listItem,
              listType: DocListType.ordered,
              listId: was.blocks[1].listId,
            ),
          ],
          metadata: was.metadata,
        ),
      ).blocks.single;
      final saved = (await DocxSplice.save(
        listed,
        DocModel(
          blocks: [was.blocks[0], was.blocks[1], item, was.blocks[2]],
          metadata: was.metadata,
          pageProperties: was.pageProperties,
        ),
      ))!;
      final document = _part(saved, 'word/document.xml');
      expect(document, contains(_listItem));
      // The same list, by its own number and style.
      expect('<w:numId w:val="5"/>'.allMatches(document).length, 2);
      expect('w:val="ListeParagraf"'.allMatches(document).length, 2);
      expect(
        _part(saved, 'word/numbering.xml'),
        _part(listed, 'word/numbering.xml'),
      );
    },
  );

  test('the margins changed: the section says so, the body keeps its '
      'bytes', () async {
    final wider = DocModel(
      blocks: opened.blocks,
      metadata: opened.metadata,
      pageRegions: opened.pageRegions,
      pageProperties: DocPageProperties(
        marginLeft: 100,
        marginRight: opened.pageProperties.marginRight,
        marginTop: opened.pageProperties.marginTop,
        marginBottom: opened.pageProperties.marginBottom,
        headerOffset: opened.pageProperties.headerOffset,
        footerOffset: opened.pageProperties.footerOffset,
        paperWidth: opened.pageProperties.paperWidth,
        paperHeight: opened.pageProperties.paperHeight,
      ),
    );
    final saved = (await DocxSplice.save(word, wider))!;
    final document = _part(saved, 'word/document.xml');
    for (final kept in [_heading, _commented, _plain, _last]) {
      expect(document, contains(kept));
    }
    expect(document, contains('w:left="2000"'));
    expect((await DocxBridge.readBytes(saved))!.pageProperties.marginLeft, 100);
  });

  test('a header written, changed and taken off: its own part, the body '
      'and the comments as they were', () async {
    DocModel headed(String? text) => DocModel(
      blocks: opened.blocks,
      metadata: opened.metadata,
      pageProperties: opened.pageProperties,
      pageRegions: {
        if (text != null) 'header': [through(DocBlock(plainText: text))],
      },
    );
    final first = (await DocxSplice.save(word, headed('Av. Deniz Yılmaz')))!;
    var document = _part(first, 'word/document.xml');
    for (final kept in [_heading, _commented, _plain, _last]) {
      expect(document, contains(kept));
    }
    expect(document, contains('<w:headerReference w:type="default"'));
    expect(_part(first, 'word/comments.xml'), _part(word, 'word/comments.xml'));
    var back = (await DocxBridge.readBytes(first))!;
    expect(back.pageRegions['header']!.single.plainText, 'Av. Deniz Yılmaz');

    // Changed: the same part written over, no second one.
    final second = (await DocxSplice.save(
      first,
      headed('Av. Deniz Yılmaz — Antalya'),
    ))!;
    expect(
      _names(second).where((n) => n.contains('Header')),
      _names(first).where((n) => n.contains('Header')),
    );
    back = (await DocxBridge.readBytes(second))!;
    expect(
      back.pageRegions['header']!.single.plainText,
      'Av. Deniz Yılmaz — Antalya',
    );

    // Taken off: the section shows none.
    final third = (await DocxSplice.save(second, headed(null)))!;
    document = _part(third, 'word/document.xml');
    expect(document, isNot(contains('headerReference')));
    expect(document, contains(_commented));
    expect((await DocxBridge.readBytes(third))!.pageRegions['header'], isNull);
  });

  test('a paragraph that ends a section taken out: the section is still '
      'ended, by the paragraph before', () async {
    final sectioned = _word(body: '$_heading$_plain$_landscape$_last');
    final was = DocxSplice.throughEditor(
      (await DocxBridge.readBytes(sectioned))!,
    );
    expect(was.blocks.map((b) => b.plainText), contains('Ek tablo sayfası'));
    final saved = (await DocxSplice.save(
      sectioned,
      DocModel(
        blocks: [
          for (final b in was.blocks)
            if (b.plainText != 'Ek tablo sayfası') b,
        ],
        metadata: was.metadata,
        pageProperties: was.pageProperties,
      ),
    ))!;
    final document = _part(saved, 'word/document.xml');
    expect(document, isNot(contains('Ek tablo sayfası')));
    expect(document, contains('w:orient="landscape"'));
    expect(document, contains(_heading));
    // In the properties of the paragraph before it, after its own.
    expect(
      document,
      contains(
        '<w:spacing w:after="120"/><w:sectPr><w:pgSz w:w="16838" '
        'w:h="11906" w:orient="landscape"/></w:sectPr></w:pPr>',
      ),
    );
    // Its shape changed instead: written anew, the section kept in it.
    final centred = [...was.blocks];
    final i = centred.indexWhere((b) => b.plainText == 'Ek tablo sayfası');
    centred[i] = through(
      DocBlock(plainText: 'Ek tablo sayfası', alignment: DocAlignment.center),
    );
    final again = (await DocxSplice.save(
      sectioned,
      DocModel(
        blocks: centred,
        metadata: was.metadata,
        pageProperties: was.pageProperties,
      ),
    ))!;
    final rewritten = _part(again, 'word/document.xml');
    expect(rewritten, contains('w:orient="landscape"'));
    expect(rewritten, contains('Ek tablo sayfası'));
    expect(rewritten, contains(_plain));
  });

  testWidgets('in the editor: opened and saved with Ctrl+S, the Word file\'s '
      'document part is what it was; a word typed, the comment is still '
      'there', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('editor-word-'),
    ))!;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    final file = File('${dir.path}/dilekce.docx');
    final original = _word();
    await tester.runAsync(() => file.writeAsBytes(original));
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
    Future<void> until(bool Function() ready) async {
      for (var i = 0; i < 400 && !ready(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(ready(), isTrue);
    }

    await until(() => find.byType(QuillEditor).evaluate().isNotEmpty);
    final controller = tester
        .widget<QuillEditor>(find.byType(QuillEditor))
        .controller;
    Future<void> save() async {
      final before = file.lastModifiedSync();
      final size = file.lengthSync();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      for (var i = 0; i < 300; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (i > 20 &&
            (file.lastModifiedSync() != before || file.lengthSync() != size)) {
          break;
        }
      }
      await tester.pump(const Duration(milliseconds: 300));
    }

    // A word typed at the end of the last paragraph.
    await tester.tap(find.byType(QuillEditor));
    await tester.pump();
    final end = controller.document.length - 1;
    controller.replaceText(
      end,
      0,
      ' Arz ederim.',
      TextSelection.collapsed(offset: end + 12),
    );
    await tester.pump();
    await save();
    final document = _part(file.readAsBytesSync(), 'word/document.xml');
    expect(document, contains('Arz ederim.'));
    // The heading's style and bookmark, the comment and its range: as
    // they were written.
    expect(document, contains(_heading));
    expect(document, contains(_commented));
    expect(document, contains(_plain));
    expect(
      _part(file.readAsBytesSync(), 'word/comments.xml'),
      _part(original, 'word/comments.xml'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}

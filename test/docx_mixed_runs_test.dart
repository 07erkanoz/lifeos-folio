import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/docx/docx_bridge.dart';
import 'package:evrak_convert/services/editor/doc_delta_map.dart';
import 'package:flutter_test/flutter_test.dart';

// Word writes a label, its tab and what follows as one run. The reader takes
// one thing of a run, so the run is split before it reads: on 551 real
// documents 399 lost text without this, some nine tenths of theirs.
void main() {
  String split(String xml) =>
      utf8.decode(DocxBridge.splitMixedRuns(utf8.encode(xml)));

  test('a run of text, tabs and text becomes a run of each, its '
      'properties kept', () {
    expect(
      split(
        '<w:r><w:rPr><w:b/></w:rPr><w:t>ADRES</w:t><w:tab/>'
        '<w:t xml:space="preserve"> : Side</w:t></w:r>',
      ),
      '<w:r><w:rPr><w:b/></w:rPr><w:t>ADRES</w:t></w:r>'
      '<w:r><w:rPr><w:b/></w:rPr><w:tab/></w:r>'
      '<w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve"> : Side</w:t></w:r>',
    );
  });

  test('a line break keeps its text; what Word last laid out is dropped; a '
      'hyphen that does not break stays a hyphen', () {
    expect(
      split('<w:r><w:t>bir</w:t><w:br/><w:t>iki</w:t></w:r>'),
      '<w:r><w:t>bir</w:t></w:r><w:r><w:br/></w:r><w:r><w:t>iki</w:t></w:r>',
    );
    expect(
      split('<w:r><w:lastRenderedPageBreak/><w:t>metin</w:t></w:r>'),
      '<w:r><w:t>metin</w:t></w:r>',
    );
    expect(
      split('<w:r><w:t>e</w:t><w:noBreakHyphen/><w:t>imza</w:t></w:r>'),
      '<w:r><w:t>e</w:t></w:r><w:r><w:t>\u2011</w:t></w:r>'
      '<w:r><w:t>imza</w:t></w:r>',
    );
  });

  test('a run of one thing, a field and a drawing are left as they are', () {
    for (final run in [
      '<w:r><w:rPr><w:i/></w:rPr><w:t>tek</w:t></w:r>',
      '<w:r><w:fldChar w:fldCharType="begin"/></w:r>',
      '<w:r><w:t>1</w:t><w:footnoteReference w:id="2"/></w:r>',
      '<w:r><w:pict><w:txbxContent><w:p><w:r><w:t>kutu</w:t><w:tab/>'
          '</w:r></w:p></w:txbxContent></w:pict></w:r>',
    ]) {
      expect(split(run), run);
    }
  });

  test('a content control is opened: what it holds stays', () {
    String open(String xml) =>
        utf8.decode(DocxBridge.openContentControls(utf8.encode(xml)));
    expect(
      open(
        '<w:sdt><w:sdtPr><w:id w:val="1"/><w:docPartObj><w:docPartGallery '
        'w:val="Page Numbers"/></w:docPartObj></w:sdtPr><w:sdtEndPr/>'
        '<w:sdtContent><w:p><w:r><w:t>Sayfa</w:t></w:r></w:p>'
        '</w:sdtContent></w:sdt><w:p/>',
      ),
      '<w:p><w:r><w:t>Sayfa</w:t></w:r></w:p><w:p/>',
    );
  });

  test('a text box\'s paragraphs come after the paragraph it hangs on, '
      'once, though Word keeps the box twice', () {
    String boxes(String xml) =>
        utf8.decode(DocxBridge.textBoxesAsParagraphs(utf8.encode(xml)));
    const box =
        '<w:txbxContent><w:p><w:r><w:t>Kutudaki yazı</w:t></w:r></w:p>'
        '</w:txbxContent>';
    final out = boxes(
      '<w:p><w:r><w:t>Önce</w:t></w:r><w:r><mc:AlternateContent><mc:Choice>'
      '<w:drawing>$box</w:drawing></mc:Choice><mc:Fallback><w:pict>$box'
      '</w:pict></mc:Fallback></mc:AlternateContent></w:r></w:p>'
      '<w:p><w:r><w:t>Sonra</w:t></w:r></w:p>',
    );
    expect('Kutudaki yazı'.allMatches(out).length, 1);
    expect(out, isNot(contains('txbxContent')));
    expect(
      out.indexOf('Önce') < out.indexOf('Kutudaki yazı') &&
          out.indexOf('Kutudaki yazı') < out.indexOf('Sonra'),
      isTrue,
    );
    // The box's paragraph is beside the one it hung on, not inside it.
    expect(
      out,
      contains('</w:r></w:p><w:p><w:r><w:t>Kutudaki yazı</w:t></w:r></w:p>'),
    );
    // Two boxes saying different things are both kept.
    final two = boxes(
      '<w:p><w:r><w:pict><w:txbxContent><w:p><w:r><w:t>Bir</w:t></w:r></w:p>'
      '</w:txbxContent></w:pict></w:r><w:r><w:pict><w:txbxContent><w:p><w:r>'
      '<w:t>İki</w:t></w:r></w:p></w:txbxContent></w:pict></w:r></w:p>',
    );
    expect(two, contains('Bir'));
    expect(two, contains('İki'));
  });

  test('read from a document: the text after a tab is in the model', () async {
    final document =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/'
        'wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>ADRESİ</w:t>'
        '<w:tab/><w:t xml:space="preserve">: Side Mah. No: 34</w:t></w:r>'
        '</w:p><w:sectPr/></w:body></w:document>';
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          '[Content_Types].xml',
          '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://'
              'schemas.openxmlformats.org/package/2006/content-types">'
              '<Default Extension="rels" ContentType="application/vnd.'
              'openxmlformats-package.relationships+xml"/><Default '
              'Extension="xml" ContentType="application/xml"/><Override '
              'PartName="/word/document.xml" ContentType="application/vnd.'
              'openxmlformats-officedocument.wordprocessingml.document.'
              'main+xml"/></Types>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          '_rels/.rels',
          '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns='
              '"http://schemas.openxmlformats.org/package/2006/'
              'relationships"><Relationship Id="rId1" Type="http://schemas.'
              'openxmlformats.org/officeDocument/2006/relationships/'
              'officeDocument" Target="word/document.xml"/></Relationships>',
        ),
      )
      ..addFile(ArchiveFile('word/document.xml', 0, utf8.encode(document)));
    final model = await DocxBridge.readBytes(
      Uint8List.fromList(ZipEncoder().encode(archive)),
    );
    expect(model!.toPlainText(), contains('ADRESİ'));
    expect(model.toPlainText(), contains(': Side Mah. No: 34'));
  });
  test('a link and a highlighter pen survive Word → editor → Word', () async {
    final model = DocModel(
      blocks: [
        DocBlock(
          plainText: 'Karar için tıklayın, önemli.',
          spans: const [
            DocSpan(
              startOffset: 11,
              length: 8,
              underline: true,
              link: 'https://karararama.yargitay.gov.tr/',
            ),
            DocSpan(startOffset: 21, length: 6, background: '#FFFF00'),
          ],
        ),
      ],
    );
    // Through the editor's own document and back.
    final quill = DocDeltaMap.modeldenDelta(model);
    final edited = DocDeltaMap.deltadanModel(
      quill.delta,
      korunanlar: quill.korunanlar,
    );
    expect(
      edited.blocks.first.spans.map((s) => s.link).nonNulls.single,
      'https://karararama.yargitay.gov.tr/',
    );
    final again = await DocxBridge.readBytes(
      await DocxBridge.writeBytes(edited),
    );
    final spans = again!.blocks.first.spans;
    final link = spans.firstWhere((s) => s.link != null);
    expect(link.link, 'https://karararama.yargitay.gov.tr/');
    expect(
      again.blocks.first.plainText.substring(link.startOffset, link.endOffset),
      'tıklayın',
    );
    expect(spans.any((s) => s.background == '#FFFF00'), isTrue);
  });
}

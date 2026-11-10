import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:evrak_convert/services/docx/docx_bridge.dart';
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
}

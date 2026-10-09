import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:evrak_convert/services/docx/docx_bridge.dart';
import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutter_quill/src/common/utils/color.dart' show stringToColor;
import 'package:flutter_test/flutter_test.dart';

/// A Word file of one paragraph and its runs, as LibreOffice writes it.
Uint8List _docx(String runs) {
  final archive = Archive();
  void add(String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>',
  );
  add(
    '_rels/.rels',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>',
  );
  add(
    'word/document.xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body><w:p>$runs</w:p></w:body></w:document>',
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test('a Word file\'s "auto" colour, in any case, is no colour; a real one '
      'is kept as the editor reads it', () async {
    final model = (await DocxBridge.readBytes(
      _docx(
        '<w:r><w:rPr><w:b/><w:color w:val="auto"/></w:rPr>'
        '<w:t>Kira sözleşmesi</w:t></w:r>'
        '<w:r><w:rPr><w:color w:val="C00000"/></w:rPr>'
        '<w:t> madde 1</w:t></w:r>',
      ),
    ))!;
    final spans = model.blocks.first.spans;
    expect(spans.first.color, isNull);
    expect(spans.last.color?.toUpperCase(), '#C00000');
  });

  test('a colour that is no number leaves the text as it was, not the page '
      'broken', () {
    expect(stringToColor('#AUTO', Colors.red), Colors.red);
    expect(stringToColor('#', null), Colors.black);
    expect(stringToColor('#C00000'), const Color(0xFFC00000));
  });
}

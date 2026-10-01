import 'package:archive/archive.dart';

class DocxService {
  static List<int> build(String text) {
    final archive = Archive()
      ..add(ArchiveFile.string('[Content_Types].xml', _contentTypes))
      ..add(ArchiveFile.string('_rels/.rels', _rels))
      ..add(ArchiveFile.string('word/document.xml', _document(text)));
    return ZipEncoder().encode(archive);
  }

  static String _document(String text) {
    final buffer = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>',
    );
    for (final line in text.split('\n')) {
      final value = line.trimRight();
      if (value.trim().isEmpty) {
        buffer.write('<w:p/>');
        continue;
      }
      final isUpperHeading =
          value.length > 3 &&
          value.length < 100 &&
          value == value.toUpperCase() &&
          value != value.toLowerCase();

      buffer
        ..write('<w:p><w:pPr>')
        ..write(
          isUpperHeading ? '<w:jc w:val="center"/>' : '<w:jc w:val="both"/>',
        )
        ..write('</w:pPr><w:r><w:rPr>')
        ..write(
          '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>',
        )
        ..write('<w:sz w:val="24"/><w:szCs w:val="24"/>')
        ..write(isUpperHeading ? '<w:b/>' : '')
        ..write('</w:rPr><w:t xml:space="preserve">')
        ..write(_escape(value))
        ..write('</w:t></w:r></w:p>');
    }
    buffer.write(
      '<w:sectPr><w:pgMar w:top="1417" w:right="1417" w:bottom="1417" w:left="1417"/></w:sectPr>'
      '</w:body></w:document>',
    );
    return buffer.toString();
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static const _contentTypes =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '</Types>';

  static const _rels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>';
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/docx/docx_bridge.dart';
import 'package:evrak_convert/services/layout/page_numbers.dart';
import 'package:evrak_convert/services/rtf/rtf_writer.dart';

/// A Word file opened and saved again keeps its sheet, its header and its
/// footer: they used to come back A4, and without either.
void main() {
  Future<DocModel> roundTrip(DocModel model) async =>
      (await DocxBridge.readBytes(await DocxBridge.writeBytes(model)))!;

  String text(List<DocBlock>? blocks) =>
      (blocks ?? const []).map((b) => b.plainText).join('\n');

  Map<dynamic, dynamic>? attrs(DocModel m, String kind) =>
      ((m.metadata['pageRegionAttrs'] as Map?)?[kind]) as Map?;

  test('a Letter sheet stays Letter, upright or turned', () async {
    // 8.5 × 11 in.
    const letter = DocPageProperties(paperWidth: 612, paperHeight: 792);
    final read = await roundTrip(
      DocModel(
        pageProperties: letter,
        blocks: [DocBlock(plainText: 'A')],
      ),
    );
    expect(read.pageProperties.paperWidth, closeTo(612, .05));
    expect(read.pageProperties.paperHeight, closeTo(792, .05));
    expect(read.pageProperties.isA4, isFalse);
    expect(read.pageProperties.landscape, isFalse);

    final turned = await roundTrip(
      DocModel(
        pageProperties: letter.copyWith(landscape: true),
        blocks: [DocBlock(plainText: 'A')],
      ),
    );
    expect(turned.pageProperties.landscape, isTrue);
    expect(turned.pageProperties.paperWidth, closeTo(612, .05));
    expect(turned.pageProperties.sheet.width, closeTo(792, .05));
  });

  test('A4 stays A4, as before', () async {
    final read = await roundTrip(DocModel(blocks: [DocBlock(plainText: 'A')]));
    expect(read.pageProperties.isA4, isTrue);
  });

  test('the header and the footer come back, the page number a number, '
      'not the digit it last showed', () async {
    const numbered = PageNumbering(
      align: PageNumberAlign.center,
      withTotal: true,
      prefix: 'Sayfa ',
      fontFace: 'Times New Roman',
      fontSize: 10,
    );
    final read = await roundTrip(
      DocModel(
        pageProperties: const DocPageProperties(
          headerOffset: 20,
          footerOffset: 25,
        ),
        blocks: [DocBlock(plainText: 'Gövde')],
        pageRegions: {
          'header': [DocBlock(plainText: 'AV. DENEME HUKUK BÜROSU')],
          'footer': [DocBlock(plainText: '')],
        },
        metadata: {
          'pageRegionAttrs': {'footer': numbered.toAttributes()},
        },
      ),
    );
    expect(text(read.pageRegions['header']), 'AV. DENEME HUKUK BÜROSU');
    expect(attrs(read, 'header')?['pageNumber-spec'], isNull);
    // The footer's only paragraph was the number: the region is empty and
    // numbered, as UYAP keeps it.
    expect(text(read.pageRegions['footer']).trim(), isEmpty);
    final number = PageNumbering.parse(attrs(read, 'footer'))!;
    expect(number.align, PageNumberAlign.center);
    expect(number.withTotal, isTrue);
    expect(number.prefix, 'Sayfa ');
    expect(number.separator, '/');
    expect(number.fontFace, 'Times New Roman');
    expect(number.fontSize, 10);
    expect(read.pageProperties.headerOffset, 20);
    expect(read.pageProperties.footerOffset, 25);
    expect(read.blocks.map((b) => b.plainText), ['Gövde']);

    // And saved again, the same.
    final again = await roundTrip(read);
    expect(text(again.pageRegions['header']), 'AV. DENEME HUKUK BÜROSU');
    expect(
      PageNumbering.parse(attrs(again, 'footer'))?.toAttributes(),
      number.toAttributes(),
    );
  });

  test(
    'a letterhead on the first page alone stays on the first page alone',
    () async {
      final read = await roundTrip(
        DocModel(
          blocks: [DocBlock(plainText: 'Gövde')],
          pageRegions: {
            'header': [DocBlock(plainText: 'ANTET')],
          },
          metadata: {
            'pageRegionAttrs': {
              'header': {'stopPage': '1'},
            },
          },
        ),
      );
      expect(text(read.pageRegions['header']), 'ANTET');
      expect(attrs(read, 'header')?['stopPage'], '1');
      expect(PageNumbering.regionShows(attrs(read, 'header'), 2), isFalse);
    },
  );

  /// A Word file written by Word: an even, a default and a first page
  /// header (the reader took the first it met), a title page, and a page
  /// number Word spells with fldChar runs between words.
  Uint8List word({required String footer, bool titlePage = true}) {
    String part(String root, String body) =>
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:$root xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '$body</w:$root>';
    String p(String text) => '<w:p><w:r><w:t>$text</w:t></w:r></w:p>';
    final files = {
      '[Content_Types].xml':
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          '</Types>',
      '_rels/.rels':
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
          '</Relationships>',
      'word/_rels/document.xml.rels':
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rIdE" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>'
          '<Relationship Id="rIdD" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header2.xml"/>'
          '<Relationship Id="rIdF" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header3.xml"/>'
          '<Relationship Id="rIdG" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>'
          '</Relationships>',
      'word/document.xml': part(
        'document',
        '<w:body>${p('Gövde')}<w:sectPr>'
            '<w:headerReference w:type="even" r:id="rIdE"/>'
            '<w:headerReference w:type="default" r:id="rIdD"/>'
            '<w:headerReference w:type="first" r:id="rIdF"/>'
            '<w:footerReference w:type="default" r:id="rIdG"/>'
            '<w:pgSz w:w="12240" w:h="15840"/>'
            '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" '
            'w:header="708" w:footer="708" w:gutter="0"/>'
            '${titlePage ? '<w:titlePg/>' : ''}'
            '</w:sectPr></w:body>',
      ),
      'word/header1.xml': part('hdr', p('ÇİFT SAYFA')),
      'word/header2.xml': part('hdr', p('HER SAYFA')),
      'word/header3.xml': part('hdr', p('İLK SAYFA')),
      'word/footer1.xml': part('ftr', footer),
    };
    final archive = Archive();
    files.forEach((name, content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    });
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  const pageInWords =
      '<w:p><w:pPr><w:jc w:val="right"/></w:pPr>'
      '<w:r><w:rPr><w:rFonts w:ascii="Calibri"/><w:sz w:val="18"/></w:rPr>'
      '<w:t xml:space="preserve">Sayfa </w:t></w:r>'
      '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
      '<w:r><w:instrText xml:space="preserve"> PAGE   \\* MERGEFORMAT </w:instrText></w:r>'
      '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
      '<w:r><w:t>7</w:t></w:r>'
      '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
      '<w:r><w:t xml:space="preserve"> / </w:t></w:r>'
      '<w:r><w:fldSimple w:instr=" NUMPAGES "><w:r><w:t>9</w:t></w:r></w:fldSimple></w:r>'
      '</w:p>';

  test('Word\'s own file: the default header, on every page but the title '
      'page, and its page number spelled Word\'s way', () async {
    final read = (await DocxBridge.readBytes(word(footer: pageInWords)))!;
    expect(text(read.pageRegions['header']), 'HER SAYFA');
    expect(attrs(read, 'header')?['startPage'], '2');
    expect(read.pageProperties.paperWidth, closeTo(612, .05));
    expect(read.pageProperties.headerOffset, closeTo(35.4, .01));
    final number = PageNumbering.parse(attrs(read, 'footer'))!;
    expect(number.align, PageNumberAlign.right);
    expect(number.prefix, 'Sayfa ');
    expect(number.withTotal, isTrue);
    expect(number.separator, ' / ');
    expect(number.fontFace, 'Calibri');
    expect(number.fontSize, 9);
    // Not the "7" Word showed when it last saved.
    expect(text(read.pageRegions['footer']), isNot(contains('7')));

    // Without a title page the default one is on every page.
    final plain = (await DocxBridge.readBytes(
      word(footer: pageInWords, titlePage: false),
    ))!;
    expect(text(plain.pageRegions['header']), 'HER SAYFA');
    expect(attrs(plain, 'header')?['startPage'], isNull);
  });

  test(
    'a page number in a table is not taken apart: that footer is left '
    'out, as before, rather than show its last digit on every page',
    () async {
      final read = (await DocxBridge.readBytes(
        word(
          footer:
              '<w:tbl><w:tr><w:tc>$pageInWords</w:tc></w:tr></w:tbl>'
              '<w:p><w:r><w:t>Adres</w:t></w:r></w:p>',
        ),
      ))!;
      expect(read.pageRegions.containsKey('footer'), isFalse);
      expect(text(read.pageRegions['header']), 'HER SAYFA');
    },
  );

  test('RTF takes the document\'s sheet too', () {
    final rtf = RtfWriter.write(
      DocModel(
        pageProperties: const DocPageProperties(
          paperWidth: 612,
          paperHeight: 792,
        ),
        blocks: [DocBlock(plainText: 'A')],
      ),
    );
    expect(rtf, contains(r'\paperw12240'));
    expect(rtf, contains(r'\paperh15840'));
  });
}

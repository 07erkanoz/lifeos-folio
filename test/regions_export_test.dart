import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/docx/docx_bridge.dart';
import 'package:evrak_convert/services/layout/page_numbers.dart';
import 'package:evrak_convert/services/rtf/rtf_writer.dart';

/// The header, the footer and the page numbers leave Folio in a Word file
/// and in RTF too, where UYAP prints them: checked page by page in
/// LibreOffice against UYAP's own editor on the same documents.
void main() {
  const numbered = PageNumbering(
    align: PageNumberAlign.center,
    withTotal: true,
    prefix: 'Sayfa ',
  );
  const topRight = PageNumbering(top: true, align: PageNumberAlign.right);
  DocModel model({Map<String, String> headerAttrs = const {}}) => DocModel(
    pageProperties: const DocPageProperties(headerOffset: 20, footerOffset: 25),
    blocks: [DocBlock(plainText: 'Gövde')],
    pageRegions: {
      'header': [
        DocBlock(
          plainText: 'AV. DENEME HUKUK BÜROSU',
          alignment: DocAlignment.center,
        ),
      ],
      'footer': [DocBlock(plainText: '')],
    },
    metadata: {
      'pageRegionAttrs': {
        'header': {...headerAttrs, ...topRight.toAttributes()},
        'footer': numbered.toAttributes(),
      },
    },
  );

  Future<Map<String, String>> parts(DocModel m) async {
    final zip = ZipDecoder().decodeBytes(await DocxBridge.writeBytes(m));
    return {
      for (final f in zip)
        if (f.isFile && f.name.startsWith('word/'))
          f.name: utf8.decode(f.content as List<int>),
    };
  }

  test('a Word file carries the header, the footer and their page numbers, '
      'the count and the offsets', () async {
    final files = await parts(model());
    final header = files['word/header1.xml']!;
    final footer = files['word/footer1.xml']!;
    final document = files['word/document.xml']!;
    expect(header, contains('AV. DENEME HUKUK BÜROSU'));
    expect(header, contains(' PAGE '));
    // Over the header's text at its top right, as UYAP draws it.
    expect(header, contains('w:framePr w:wrap="through"'));
    expect(header, contains('w:xAlign="right"'));
    // A footer of nothing but the number is the number.
    expect(footer, contains('Sayfa '));
    expect(footer, contains(' PAGE '));
    expect(footer, contains(' NUMPAGES '));
    expect(RegExp('<w:p[ >]').allMatches(footer).length, 1);
    expect(footer, isNot(contains('w:framePr')));
    expect(document, contains('w:header="400"'));
    expect(document, contains('w:footer="500"'));
    expect(document, isNot(contains('w:titlePg')));
  });

  test('a letterhead on the first page alone is a first page of its own in '
      'Word, the footer named for it too', () async {
    final document = (await parts(
      model(headerAttrs: {'stopPage': '1'}),
    ))['word/document.xml']!;
    expect(document, contains('<w:titlePg/>'));
    expect(
      RegExp(r'<w:headerReference w:type="(\w+)"')
          .allMatches(document)
          .map((m) => m[1])
          .toList(),
      ['first'],
    );
    expect(
      RegExp(r'<w:footerReference w:type="(\w+)"')
          .allMatches(document)
          .map((m) => m[1])
          .toList(),
      ['default', 'first'],
    );
  });

  test('RTF carries them too, with its own fields and first page', () {
    final rtf = RtfWriter.write(model(headerAttrs: {'startPage': '2'}));
    expect(rtf, contains('{\\header '));
    expect(rtf, contains('{\\footer '));
    expect(rtf, contains('{\\field{\\*\\fldinst PAGE}{\\fldrslt 1}}'));
    expect(rtf, contains('{\\field{\\*\\fldinst NUMPAGES}{\\fldrslt 1}}'));
    expect(rtf, contains('\\posxr'));
    expect(rtf, contains('\\headery400'));
    expect(rtf, contains('\\footery500'));
    // Not on page 1: a first page with an empty header of its own.
    expect(rtf, contains('\\titlepg'));
    expect(rtf, contains('{\\headerf }'));
    expect(rtf.indexOf('{\\header '), lessThan(rtf.indexOf('vde')));
  });

  test('an RTF picture is a paragraph of its own, in its own alignment', () {
    final rtf = RtfWriter.write(
      DocModel(
        blocks: [
          DocBlock(plainText: 'Önce', alignment: DocAlignment.right),
          DocBlock(
            type: DocBlockType.image,
            plainText: '',
            alignment: DocAlignment.center,
            imageBase64: base64Encode([137, 80, 78, 71]),
            imageMime: 'image/png',
          ),
        ],
      ),
    );
    expect(rtf, contains('\\pard\\plain\\qc{\\pict'));
  });
}

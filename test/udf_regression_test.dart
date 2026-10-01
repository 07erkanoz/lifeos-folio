import 'dart:convert';

import 'support/pdfium.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:xml/xml.dart';
import 'package:image/image.dart' as img;
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/services/pdf/pdf_service.dart';
import 'package:evrak_convert/services/editor/doc_delta_map.dart';
import 'package:evrak_convert/services/convert/converter_service.dart';
import 'package:evrak_convert/services/fonts/document_fonts.dart';
import 'package:evrak_convert/services/preview/preview_cache.dart';
import 'package:evrak_convert/services/docx/docx_bridge.dart';
import 'package:evrak_convert/services/docx/docx_service.dart';

import 'support/pdf_readback.dart';

Uint8List fixture(
  String xml, {
  bool signed = false,
  bool localOnly = false,
  List<int>? encoded,
}) {
  final data = encoded ?? utf8.encode(xml);
  final archive = Archive()
    ..addFile(ArchiveFile('content.xml', data.length, data));
  if (signed) archive.addFile(ArchiveFile('sign.sgn', 3, [1, 2, 3]));
  final bytes = ZipEncoder().encode(archive);
  if (!localOnly) return Uint8List.fromList(bytes);
  for (var i = 0; i < bytes.length - 3; i++) {
    if (bytes[i] == 0x50 &&
        bytes[i + 1] == 0x4b &&
        bytes[i + 2] == 1 &&
        bytes[i + 3] == 2) {
      return Uint8List.fromList(bytes.sublist(0, i));
    }
  }
  throw StateError('central directory missing');
}

String xml(
  String text,
  String elements, {
  String styles = '',
  String resolver = '',
}) =>
    '<template><content><![CDATA[$text]]></content><elements resolver="$resolver">$elements</elements><styles>$styles</styles></template>';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a paragraph takes the layout its style gives it, as UYAP does', () {
    // hvl-default justifies; the first paragraph says nothing, the second
    // sets its own, the third has a style of its own that centres.
    final model = UdfReader.readBytes(
      fixture(
        xml(
          'Bir\nİki\nÜç\n',
          '<paragraph><content startOffset="0" length="4"/></paragraph>'
              '<paragraph Alignment="0" SpaceAbove="0.0">'
              '<content startOffset="4" length="4"/></paragraph>'
              '<paragraph resolver="baslik">'
              '<content startOffset="8" length="3"/></paragraph>',
          resolver: 'hvl-default',
          styles:
              '<style name="hvl-default" family="Times New Roman" size="12" '
              'Alignment="3" SpaceAbove="2.0" LineSpacing="0.0"/>'
              '<style name="baslik" resolver="hvl-default" Alignment="1"/>',
        ),
      ),
    )!;
    expect(model.blocks[0].alignment, DocAlignment.justify);
    expect(model.blocks[0].spacingBefore, 2);
    // A value the paragraph writes, even the default, is its own.
    expect(model.blocks[1].alignment, DocAlignment.left);
    expect(model.blocks[1].spacingBefore, 0);
    expect(model.blocks[2].alignment, DocAlignment.center);
    // LineSpacing="0.0" is single spacing, the same as none.
    expect(model.blocks[0].lineSpacing, isNull);
  });

  test('a template shows its filled-in values, as UYAP does', () {
    // A document UYAP makes from a template keeps each blank as a field
    // holding its own name, and the values in <data>.
    const text = 'T.C.\nil_Ilce\nicraDairesi\'NE\ntalep\nİmza\n';
    final model = UdfReader.readBytes(
      fixture(
        '<template><content><![CDATA[$text]]></content><elements>'
        '<paragraph><content startOffset="0" length="5"/></paragraph>'
        '<paragraph><field fieldName="il_Ilce" bold="true" startOffset="5" '
        'length="7"/><content startOffset="12" length="1"/></paragraph>'
        '<paragraph><field fieldName="icraDairesi" startOffset="13" '
        'length="11"/><content startOffset="24" length="4"/></paragraph>'
        '<paragraph><field fieldName="talep" startOffset="28" length="5"/>'
        '<content startOffset="33" length="1"/></paragraph>'
        '<paragraph><content startOffset="34" length="5"/></paragraph>'
        '</elements><styles/>'
        '<data><il_Ilce>MANAVGAT</il_Ilce><icraDairesi>İCRA DAİRESİ</icraDairesi>'
        '<talep>Birinci satır\nİkinci satır</talep><il_Ilce></il_Ilce></data>'
        '</template>',
      ),
    )!;
    expect(model.blocks.map((b) => b.plainText), [
      'T.C.',
      'MANAVGAT',
      "İCRA DAİRESİ'NE",
      // A line break in a value is a new paragraph, with the same layout.
      'Birinci satır',
      'İkinci satır',
      'İmza',
    ]);
    // The value takes the field's formatting.
    expect(model.blocks[1].spans.single.bold, isTrue);
  });

  test('a field that already holds its value is read as it is', () {
    // Most fields in the archive: UYAP filled them in and split the value
    // into words; the <data> beside them must not be pasted in again.
    const text = 'İCRA DAİRESİ\n';
    final model = UdfReader.readBytes(
      fixture(
        '<template><content><![CDATA[$text]]></content><elements>'
        '<paragraph><field fieldName="icra" startOffset="0" length="4"/>'
        '<space startOffset="4" length="1"/>'
        '<field fieldName="icra" startOffset="5" length="8"/></paragraph>'
        '</elements><styles/><data><icra>İCRA DAİRESİ</icra></data></template>',
      ),
    )!;
    expect(model.blocks.single.plainText, 'İCRA DAİRESİ');
  });

  test(
    'resolver inheritance and explicit false retain family, size and style',
    () {
      final model = UdfReader.readBytes(
        fixture(
          xml(
            'İşĞ\n',
            '<paragraph><content startOffset="0" length="1"/><content startOffset="1" length="2" bold="false" family="Courier New"/><content startOffset="3" length="1"/></paragraph>',
            resolver: 'body',
            styles: '<style name="base" family="Arial" size="13.5" bold="true"/><style name="body" resolver="base" italic="true"/>',
          ),
        ),
      )!;
      final spans = model.blocks.single.spans;
      expect(spans.first.fontFamily, 'Arial');
      expect(spans.first.fontSize, 13.5);
      expect(spans.first.bold, isTrue);
      expect(spans.first.italic, isTrue);
      expect(spans[1].bold, isFalse);
      expect(spans[1].fontFamily, 'Courier New');
    },
  );
  test(
    'split CDATA, entities, whitespace and UTF-16 offsets survive write/read',
    () {
      final source = DocModel(
        blocks: [
          DocBlock(
            plainText: '  İ😀\nŞ ]]> & <son>  ',
            spans: [
              const DocSpan(
                startOffset: 6,
                length: 1,
                bold: true,
                fontSize: 10.5,
                fontFamily: 'A"&B',
              ),
            ],
          ),
          DocBlock(plainText: ''),
          DocBlock(plainText: ''),
          DocBlock(plainText: 'Son'),
        ],
      );
      final bytes = UdfWriter.writeBytes(source);
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(
        () => XmlDocument.parse(utf8.decode(archive.first.content)),
        returnsNormally,
      );
      final model = UdfReader.readBytes(bytes)!;
      expect(
        model.blocks.map((b) => b.plainText),
        source.blocks.map((b) => b.plainText),
      );
      final bold = model.blocks.first.spans.singleWhere((s) => s.bold);
      expect(bold.startOffset, 6);
      expect(bold.fontSize, 10.5);
      expect(bold.fontFamily, 'A"&B');
      final split = UdfReader.readBytes(
        fixture(
          '<template><content><![CDATA[A]]]]><![CDATA[>B\n]]></content><elements><paragraph><content startOffset="0" length="6"/></paragraph></elements></template>',
        ),
      );
      expect(split!.blocks.single.plainText, 'A]]>B');
    },
  );
  test('Windows-1254 and RTF escapes preserve Turkish offset ranges', () {
    final latinXml = xml(
      'Şİğ\n',
      '<paragraph><content startOffset="0" length="3"/><content startOffset="3" length="1"/></paragraph>',
    );
    final encoded = latinXml.codeUnits
        .map((c) => {0x15e: 0xde, 0x130: 0xdd, 0x11f: 0xf0}[c] ?? c)
        .toList();
    expect(
      UdfReader.readBytes(fixture('', encoded: encoded))!
          .blocks
          .single
          .plainText,
      'Şİğ',
    );
    final model = UdfReader.readBytes(
      fixture(
        xml(
          "A\\'deB\n",
          '<paragraph><content startOffset="0" length="1"/><content startOffset="1" length="4" bold="true"/><content startOffset="5" length="2"/></paragraph>',
        ),
      ),
    )!;
    expect(model.blocks.single.plainText, 'AŞB');
    expect(model.blocks.single.spans[1].length, 1);
  });
  test(
    'out-of-bounds ranges are rejected, not rendered as an empty success',
    () {
      expect(
        UdfReader.readBytes(
          fixture(
            xml(
              'a\n',
              '<paragraph><content startOffset="0" length="3"/></paragraph>',
            ),
          ),
        ),
        isNull,
      );
    },
  );
  test('the header goes before the body and the footer after it, text and '
      'all, as UYAP writes them', () {
    final bytes = UdfWriter.writeBytes(
      DocModel(
        blocks: [DocBlock(plainText: 'Gövde')],
        pageRegions: {
          'footer': [DocBlock(plainText: 'Alt')],
          'header': [DocBlock(plainText: 'Üst')],
        },
      ),
    );
    final doc = XmlDocument.parse(
      utf8.decode(
        ZipDecoder().decodeBytes(bytes).findFile('content.xml')!.content,
      ),
    );
    final elements = doc.findAllElements('elements').single.childElements;
    expect(elements.map((e) => e.name.local).toList(), [
      'header',
      'paragraph',
      'footer',
    ]);
    expect(doc.findAllElements('content').first.innerText, 'Üst\nGövde\nAlt\n');
    final back = UdfReader.readBytes(bytes)!;
    expect(back.pageRegions['footer']!.single.plainText, 'Alt');
    expect(back.pageRegions['header']!.single.plainText, 'Üst');
    expect(back.blocks.single.plainText, 'Gövde');
  });

  test('a picture is written as UYAP writes one, and read back as itself', () {
    final png = base64Encode(img.encodePng(img.Image(width: 40, height: 10)));
    final model = DocModel(
      blocks: [
        DocBlock(plainText: 'Önce'),
        DocBlock(
          type: DocBlockType.image,
          plainText: '',
          imageBase64: png,
          imageMime: 'image/png',
          imageWidth: 200,
          imageHeight: 50,
        ),
        DocBlock(plainText: 'Sonra'),
      ],
    );
    final bytes = UdfWriter.writeBytes(model);
    final xml = utf8.decode(
      ZipDecoder().decodeBytes(bytes).findFile('content.xml')!.content,
    );
    final doc = XmlDocument.parse(xml);
    final text = doc.findAllElements('content').first.innerText;
    final image = doc.findAllElements('image').single;
    final at = int.parse(image.getAttribute('startOffset')!);
    // Its own character, U+00B8, then the paragraph's own line break.
    expect(text.substring(at, at + 2), '\u00b8\n');
    final paragraph = image.parentElement!;
    expect(
      paragraph.childElements.map((e) => e.name.local).toList(),
      ['image', 'content'],
    );
    expect(image.getAttribute('width'), '200.0');
    expect(image.getAttribute('height'), '50.0');
    // Read back: the picture once, no empty paragraph beside it.
    final back = UdfReader.readBytes(bytes)!;
    expect(back.blocks.map((b) => b.type).toList(), [
      DocBlockType.paragraph,
      DocBlockType.image,
      DocBlockType.paragraph,
    ]);
    expect(back.blocks.map((b) => b.plainText).toList(), ['Önce', '', 'Sonra']);
    // And again: nothing gathers on the way round.
    final twice = UdfReader.readBytes(UdfWriter.writeBytes(back))!;
    expect(twice.blocks.length, 3);
  });

  test('empty and image-only documents open', () {
    expect(
      UdfReader.readBytes(UdfWriter.writeBytes(DocModel(blocks: []))),
      isNotNull,
    );
    final data = base64Encode(img.encodePng(img.Image(width: 4, height: 4)));
    final source = DocModel(
      blocks: [
        DocBlock(
          type: DocBlockType.image,
          plainText: '',
          imageBase64: data,
          alignment: DocAlignment.right,
        ),
      ],
    );
    final result = UdfReader.readBytes(UdfWriter.writeBytes(source))!;
    expect(result.blocks.single.type, DocBlockType.image);
    expect(result.blocks.single.alignment, DocAlignment.right);
  });
  test(
    'local ZIP headers and signature detection; regenerated output is unsigned',
    () {
      final input = fixture(
        xml(
          'İmza\n',
          '<paragraph><content startOffset="0" length="5"/></paragraph>',
        ),
        signed: true,
        localOnly: true,
      );
      final model = UdfReader.readBytes(input)!;
      expect(model.metadata['hasSignature'], isTrue);
      expect(model.metadata['signatureBytes'], [1, 2, 3]);
      expect(
        UdfReader.readBytes(UdfWriter.writeBytes(model))!
            .metadata['hasSignature'],
        isFalse,
      );
    },
  );
  test('headers/footers rebase their offsets after body changes', () {
    final input = fixture(
      xml(
        'Üst\nGövde\nAlt\n',
        '<header><paragraph><content startOffset="0" length="4"/></paragraph></header><paragraph><content startOffset="4" length="6"/></paragraph><footer><paragraph><content startOffset="10" length="4"/></paragraph></footer>',
      ),
    );
    final source = UdfReader.readBytes(input)!;
    final changed = DocModel(
      blocks: [DocBlock(plainText: 'Daha uzun yeni gövde')],
      pageRegions: source.pageRegions,
    );
    final parsed = UdfReader.readBytes(UdfWriter.writeBytes(changed))!;
    expect(parsed.pageRegions['header']!.single.plainText, 'Üst');
    expect(parsed.pageRegions['footer']!.single.plainText, 'Alt');
    expect(parsed.blocks.single.plainText, 'Daha uzun yeni gövde');
  });
  test('table spans, merged cells and fractional widths round trip', () {
    final model = DocModel(
      blocks: [
        DocBlock(
          type: DocBlockType.table,
          plainText: '',
          table: DocTable(
            columnWidths: [40, 80],
            rows: [
              DocTableRow(
                isHeader: true,
                cells: [
                  DocTableCell(
                    colspan: 2,
                    rowspan: 2,
                    blocks: [
                      DocBlock(
                        plainText: 'Başlık',
                        spans: [
                          const DocSpan(
                            startOffset: 0,
                            length: 6,
                            bold: true,
                            color: '#ff0000',
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    final table = UdfReader.readBytes(UdfWriter.writeBytes(model))!
        .blocks
        .single
        .table!;
    expect(table.columnWidths, [40, 80]);
    expect(table.rows.single.isHeader, isTrue);
    final cell = table.rows.single.cells.single;
    expect(cell.colspan, 2);
    expect(cell.rowspan, 2);
    expect(cell.blocks.single.spans.first.bold, isTrue);
  });
  test('overlapping spans serialize once per character, clipped at bounds', () {
    final source = DocModel(
      blocks: [
        DocBlock(
          plainText: 'abc',
          spans: [
            const DocSpan(startOffset: -1, length: 3, bold: true),
            const DocSpan(startOffset: 1, length: 50, italic: true),
          ],
        ),
      ],
    );
    final result = UdfReader.readBytes(UdfWriter.writeBytes(source))!;
    expect(result.blocks.single.plainText, 'abc');
    final middle = result.blocks.single.spans[1];
    expect(middle.bold && middle.italic, isTrue);
  });
  test('a hanging indent survives UDF, the editor and UDF again', () {
    // Court decisions set their heading values with it; a save that dropped
    // it sent every wrapped value back under its label.
    final model = UdfReader.readBytes(
      fixture(
        xml(
          'DAVACI\t: Ahmet\n',
          '<paragraph TabSet="150.0:0:0" Hanging="182.0">'
              '<content startOffset="0" length="15"/></paragraph>',
        ),
      ),
    )!;
    expect(model.blocks.single.hanging, 182);
    final mapped = DocDeltaMap.modeldenDelta(model);
    final edited = DocDeltaMap.deltadanModel(
      Document.fromDelta(mapped.delta).toDelta(),
      metadata: model.metadata,
    );
    expect(edited.blocks.single.hanging, 182);
    final again = UdfReader.readBytes(UdfWriter.writeBytes(edited))!;
    expect(again.blocks.single.hanging, 182);
  });

  test(
    'a line break inside a paragraph keeps it one paragraph in the editor',
    () {
      // Everything before the break used to become a line of its own, without
      // the paragraph's indent, stops or alignment.
      DocModel model(Map<String, dynamic> metadata) => DocModel(
        metadata: metadata,
        blocks: [
          DocBlock(
            plainText: 'KONU\t:\n İtirazın kaldırılması',
            tabSet: '36.0:0:0',
            alignment: DocAlignment.justify,
            firstLineIndent: 35,
          ),
        ],
      );
      Document edit(DocModel source) =>
          Document.fromDelta(DocDeltaMap.modeldenDelta(source).delta);

      // A UDF's is drawn as nothing, as UYAP draws it; a Word one breaks the
      // row inside the paragraph. Both come back as the line break they were.
      for (final (metadata, mark) in [
        (const {'formatId': '1.8'}, DocDeltaMap.innerBreakUdf),
        (
          const {'tabRules': 'word', 'defaultTabStop': 35.4},
          DocDeltaMap.innerBreakWord,
        ),
      ]) {
        final document = edit(model(metadata));
        expect(document.root.children.length, 1, reason: '$metadata');
        expect(document.toPlainText(), contains(mark));
        final back = DocDeltaMap.deltadanModel(document.toDelta());
        expect(back.blocks.single.plainText, 'KONU\t:\n İtirazın kaldırılması');
        expect(back.blocks.single.tabSet, '36.0:0:0');
        expect(back.blocks.single.firstLineIndent, 35);
      }
      // A paste or a text file keeps its breaks as lines of their own.
      expect(edit(model(const {})).root.children.length, 2);
    },
  );

  test('a hanging indent goes to Word as one and comes back', () async {
    // A court decision's heading, rows after the first set in under the
    // value: Word's w:left with w:hanging, never a negative w:firstLine,
    // which the schema does not allow.
    final bytes = await DocxBridge.writeBytes(
      DocModel(
        blocks: [
          DocBlock(plainText: 'DAVACI\t: Ahmet', hanging: 182, leftIndent: 10),
        ],
      ),
    );
    final xml = utf8.decode(
      ZipDecoder().decodeBytes(bytes).findFile('word/document.xml')!.content
          as List<int>,
    );
    expect(xml, contains('w:left="3840"'));
    expect(xml, contains('w:hanging="3640"'));
    expect(xml, isNot(contains('w:firstLine="-')));
    final back = (await DocxBridge.readBytes(bytes))!.blocks.single;
    expect(back.leftIndent, 10);
    expect(back.hanging, 182);
    expect(back.firstLineIndent, 0);
  });

  test('a DOCX brings its default tab stop and Word\'s tab rules', () async {
    final archive = ZipDecoder().decodeBytes(DocxService.build('Ad\tSoyad'));
    const settings =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:settings xmlns:w="http://schemas.openxmlformats.org/'
        'wordprocessingml/2006/main"><w:defaultTabStop w:val="708"/>'
        '</w:settings>';
    archive.addFile(
      ArchiveFile('word/settings.xml', settings.length, utf8.encode(settings)),
    );
    final model = await DocxBridge.readBytes(
      Uint8List.fromList(ZipEncoder().encode(archive)),
    );
    expect(model!.metadata['tabRules'], 'word');
    expect(model.metadata['defaultTabStop'], closeTo(35.4, 1e-9));
  });

  test('Quill document retains protected blocks and paragraph layout', () {
    final table = DocBlock(
      type: DocBlockType.table,
      plainText: '',
      table: DocTable(rows: []),
    );
    final source = DocModel(
      blocks: [
        DocBlock(
          plainText: 'İlk',
          leftIndent: 23,
          lineSpacing: 1.5,
          spans: [
            const DocSpan(
              startOffset: 0,
              length: 3,
              fontSize: 10.5,
              background: '#ff0000',
            ),
          ],
        ),
        table,
        DocBlock(plainText: ''),
      ],
    );
    final mapped = DocDeltaMap.modeldenDelta(source);
    final document = Document.fromDelta(mapped.delta);
    document.insert(0, 'X');
    final result = DocDeltaMap.deltadanModel(
      document.toDelta(),
      korunanlar: mapped.korunanlar,
    );
    expect(result.blocks[0].plainText, 'Xİlk');
    expect(result.blocks[0].leftIndent, 23);
    expect(result.blocks[0].lineSpacing, 1.5);
    expect(result.blocks[1], same(table));
    expect(result.blocks.last.plainText, '');
    expect(result.blocks[0].spans.last.fontSize, 10.5);
  });
  test('PDF embeds all three families, Turkish text, images and landscape page', () async {
    final model = DocModel(
      pageProperties: const DocPageProperties(landscape: true),
      blocks: [
        for (final family in ['Times New Roman', 'Arial', 'Courier New'])
          DocBlock(
            plainText: 'İıŞşĞğÇçÖöÜü $family',
            spans: [
              DocSpan(
                startOffset: 0,
                length: 100,
                fontFamily: family,
                bold: true,
                italic: true,
              ),
            ],
          ),
        DocBlock(
          type: DocBlockType.image,
          plainText: '',
          imageBase64: base64Encode(
            img.encodePng(img.Image(width: 4, height: 4)),
          ),
        ),
      ],
    );
    final bytes = await PdfService.modelToPdfBytes(model);
    final pdf = await PdfReadback.of(bytes);
    final (width, height) = pdf.pageSizes.first;
    expect(width, greaterThan(height));
    expect(pdf.text, contains('İıŞşĞğÇçÖöÜü'));
    final raw = latin1.decode(bytes);
    expect(RegExp(r'/Subtype\s*/Image').hasMatch(raw), isTrue);
    // Prefer installed fonts; bundled Liberation remains the offline fallback.
    for (final names in [
      ['TimesNewRoman', 'LiberationSerif'],
      ['Arial', 'LiberationSans'],
      ['CourierNew', 'LiberationMono'],
    ]) {
      expect(
        names.any(raw.contains),
        isTrue,
        reason: 'Missing embedded family: $names',
      );
    }
    expect(
      RegExp(r'/FontFile2\s+\d+').allMatches(raw).length,
      greaterThanOrEqualTo(3),
    );
  });
  test('DOCX reload preserves ruler margins and orientation', () async {
    const page = DocPageProperties(
      marginLeft: 73.25,
      marginRight: 38.5,
      marginTop: 56.75,
      marginBottom: 48.25,
      landscape: true,
    );
    final bytes = await DocxBridge.writeBytes(
      DocModel(
        pageProperties: page,
        blocks: [DocBlock(plainText: 'Cetvel ölçüleri')],
      ),
    );
    final loaded = (await DocxBridge.readBytes(bytes))!;
    expect(loaded.pageProperties.marginLeft, page.marginLeft);
    expect(loaded.pageProperties.marginRight, page.marginRight);
    expect(loaded.pageProperties.marginTop, page.marginTop);
    expect(loaded.pageProperties.marginBottom, page.marginBottom);
    expect(loaded.pageProperties.landscape, isTrue);
  });
  test('font aliases are stable and available offline', () {
    expect(DocumentFonts.family('TimesNewRomanPSMT'), 'LiberationSerif');
    expect(DocumentFonts.family('ArialMT'), 'LiberationSans');
    expect(DocumentFonts.family('Consolas'), 'LiberationMono');
  });
  test(
    'conversion preserves dotted names and never overwrites previous output',
    () async {
      final dir = await Directory.systemTemp.createTemp('evrak-test-');
      try {
        final source = File('${dir.path}/dosya.v2.txt');
        await source.writeAsString('İşlem');
        final a = await ConverterService.convertFile(
          sourcePath: source.path,
          targetFormat: EvrakFormat.udf,
        );
        final b = await ConverterService.convertFile(
          sourcePath: source.path,
          targetFormat: EvrakFormat.udf,
        );
        expect(a.success && b.success, isTrue);
        expect(a.outputPath, contains('dosya.v2_donusturuldu'));
        expect(a.outputPath, isNot(b.outputPath));
        expect(await source.readAsString(), 'İşlem');
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('scanned PDF conversion reports OCR requirement', () async {
    configurePdfiumForTest();
    final image = img.encodePng(img.Image(width: 4, height: 4));
    final bytes = await ConverterService.convertBytes(
      bytes: Uint8List.fromList(image),
      sourceFormat: EvrakFormat.image,
      targetFormat: EvrakFormat.pdf,
    );
    await expectLater(
      ConverterService.convertBytes(
        bytes: bytes!,
        sourceFormat: EvrakFormat.pdf,
        targetFormat: EvrakFormat.udf,
      ),
      throwsFormatException,
    );
  });
  test(
    'legacy formats are labelled by what can actually be done with them',
    () {
      // Both are read here now. RTF is also written; the old binary .doc is
      // not, so a document opened from one is saved in another format.
      expect(EvrakFormat.fromExtension('rtf'), EvrakFormat.rtf);
      expect(EvrakFormat.fromExtension('doc'), EvrakFormat.doc);
      expect(EvrakFormat.rtf.canEdit, isTrue);
      expect(
        EvrakFormat.pdf.canEdit,
        isTrue,
        reason: 'metin katmanı düzenlenebilir bir kopyaya aktarılabilir',
      );
      expect(EvrakFormat.rtf.defaultExtension, 'rtf');
      expect(EvrakFormat.doc.defaultExtension, 'udf');
      expect(EvrakFormat.rtf.availableConversions, contains(EvrakFormat.pdf));
      expect(EvrakFormat.doc.availableConversions, contains(EvrakFormat.rtf));
      expect(EvrakFormat.tif.availableConversions, [EvrakFormat.pdf]);
    },
  );
  test('UTF-16 BOM document retains Turkish text', () {
    final value = xml(
      'Şİğ\n',
      '<paragraph><content startOffset="0" length="4"/></paragraph>',
    );
    final encoded = [
      0xff,
      0xfe,
      for (final c in value.codeUnits) ...[c & 255, c >> 8],
    ];
    expect(
      UdfReader.readBytes(fixture('', encoded: encoded))!
          .blocks
          .single
          .plainText,
      'Şİğ',
    );
  });
  test('preview cache coalesces requests, reuses bytes and invalidates changed files', () async {
    final dir = await Directory.systemTemp.createTemp('evrak-preview-');
    try {
      final file = File('${dir.path}/ornek.udf');
      final model = DocModel(
        blocks: [
          for (var i = 0; i < 100; i++)
            DocBlock(plainText: 'Türkçe önizleme satırı $i: İıŞşĞğÇçÖöÜü'),
        ],
      );
      await file.writeAsBytes(UdfWriter.writeBytes(model));
      final evrak = EvrakFile.fromPath(file.path);
      final cold = Stopwatch()..start();
      final results = await Future.wait([
        PreviewCache.load(evrak),
        PreviewCache.load(evrak),
      ]);
      cold.stop();
      expect(identical(results[0], results[1]), isTrue);
      final warm = Stopwatch()..start();
      final cached = await PreviewCache.load(evrak);
      warm.stop();
      expect(identical(cached, results.first), isTrue);
      // Synthetic performance sample; no user document content is logged.
      // ignore: avoid_print
      print(
        'Preview sample (100 paragraphs): cold=${cold.elapsedMilliseconds} ms, cache=${warm.elapsedMicroseconds} us',
      );
      await file.writeAsBytes(
        UdfWriter.writeBytes(
          DocModel(blocks: [DocBlock(plainText: 'Yeni içerik')]),
        ),
      );
      final changed = await PreviewCache.load(evrak);
      expect(identical(changed, cached), isFalse);
      expect(changed.model.toPlainText(), 'Yeni içerik');
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('DOCX export retains a picture, cell spans, paragraph geometry and text colors', () async {
    final model = DocModel(
      blocks: [
        DocBlock(
          plainText: 'Türkçe',
          leftIndent: 24,
          spans: [
            const DocSpan(
              startOffset: 0,
              length: 6,
              color: '#ff0000',
              fontFamily: 'Arial',
              fontSize: 13.5,
            ),
          ],
        ),
        DocBlock(
          type: DocBlockType.image,
          plainText: '',
          imageBase64: base64Encode(
            img.encodePng(img.Image(width: 4, height: 4)),
          ),
        ),
      ],
    );
    final archive = ZipDecoder().decodeBytes(
      await DocxBridge.writeBytes(model),
    );
    expect(archive.files.any((f) => f.name.startsWith('word/media/')), isTrue);
    final document = XmlDocument.parse(
      utf8.decode(archive.findFile('word/document.xml')!.content),
    );
    expect(
      document
          .findAllElements('w:color')
          .any((e) => e.getAttribute('w:val') == 'FF0000'),
      isTrue,
    );
    expect(
      document
          .findAllElements('w:ind')
          .any((e) => e.getAttribute('w:left') == '480'),
      isTrue,
    );
  });
  test('a long UDF paragraph spans pages without dropping the end', () async {
    final text =
        '${List.filled(1500, 'Türkçe uzun paragraf.').join(' ')} SONİŞARET';
    final bytes = await PdfService.modelToPdfBytes(
      DocModel(blocks: [DocBlock(plainText: text)]),
    );
    final pdf = await PdfReadback.of(bytes);
    expect(pdf.pageCount, greaterThan(1));
    expect(pdf.text, contains('SONİŞARET'));
  });
}

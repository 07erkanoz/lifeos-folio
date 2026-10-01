import 'dart:convert';
import 'dart:typed_data';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/editor/doc_model_json.dart';
import 'package:evrak_convert/services/html/html_writer.dart';
import 'package:evrak_convert/services/platform/rich_clipboard.dart';
import 'package:flutter_test/flutter_test.dart';

DocModel _sample() => DocModel(
  blocks: [
    DocBlock(
      plainText: 'KONU\t: Değer',
      alignment: DocAlignment.justify,
      leftIndent: 10,
      firstLineIndent: 5,
      hanging: 113,
      spacingBefore: 6,
      lineSpacing: 1.5,
      tabSet: '113.0:0:0',
      styleName: 'hvl-default',
      spans: const [
        DocSpan(
          startOffset: 0,
          length: 4,
          bold: true,
          fontFamily: 'Arial',
          fontSize: 14,
          color: '#c00000',
          background: '#ffff00',
        ),
      ],
    ),
    DocBlock(
      plainText: 'Madde',
      type: DocBlockType.listItem,
      listType: DocListType.ordered,
      listLevel: 1,
      listId: 3,
      numberType: 'NUMBER_TYPE_DIGIT',
    ),
    DocBlock(
      type: DocBlockType.table,
      plainText: '',
      table: DocTable(
        columnWidths: const [1, 3],
        bordered: false,
        rows: [
          DocTableRow(
            isHeader: true,
            cells: [
              DocTableCell(
                blocks: [DocBlock(plainText: 'Ad')],
                backgroundColor: '#eeeeee',
              ),
              DocTableCell(
                colspan: 2,
                blocks: [
                  DocBlock(
                    type: DocBlockType.table,
                    plainText: '',
                    table: DocTable(
                      rows: [
                        DocTableRow(
                          cells: [
                            DocTableCell(blocks: [DocBlock(plainText: 'İç')]),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
    DocBlock(
      type: DocBlockType.image,
      plainText: '',
      imageBase64: 'iVBORw0KGgo=',
      imageMime: 'image/png',
      imageWidth: 16,
      imageHeight: 12,
    ),
  ],
  metadata: {'formatId': '1.8', 'openEnd': true, 'ignored': 'x'},
);

void main() {
  test('a model survives JSON whole, down to a table in a table', () {
    final json = jsonDecode(jsonEncode(DocModelJson.encode(_sample())));
    final back = DocModelJson.decode(json)!;
    final first = back.blocks[0];
    expect(first.plainText, 'KONU\t: Değer');
    expect(first.alignment, DocAlignment.justify);
    expect(first.leftIndent, 10);
    expect(first.firstLineIndent, 5);
    expect(first.hanging, 113);
    expect(first.spacingBefore, 6);
    expect(first.lineSpacing, 1.5);
    expect(first.tabSet, '113.0:0:0');
    expect(first.styleName, 'hvl-default');
    final span = first.spans.single;
    expect(span.bold, isTrue);
    expect(span.fontFamily, 'Arial');
    expect(span.fontSize, 14);
    expect(span.color, '#c00000');
    expect(span.background, '#ffff00');
    expect(back.blocks[1].listType, DocListType.ordered);
    expect(back.blocks[1].listLevel, 1);
    expect(back.blocks[1].numberType, 'NUMBER_TYPE_DIGIT');
    final table = back.blocks[2].table!;
    expect(table.bordered, isFalse);
    expect(table.columnWidths, [1, 3]);
    expect(table.rows.single.isHeader, isTrue);
    expect(table.rows.single.cells.first.backgroundColor, '#eeeeee');
    expect(table.rows.single.cells.last.colspan, 2);
    expect(
      table
          .rows
          .single
          .cells
          .last
          .blocks
          .single
          .table!
          .rows
          .single
          .cells
          .single
          .blocks
          .single
          .plainText,
      'İç',
    );
    expect(back.blocks[3].imageWidth, 16);
    // Only the settings a block is read against travel.
    expect(back.metadata, {'formatId': '1.8', 'openEnd': true});
  });

  test('what another program put there is read defensively', () {
    final back = DocModelJson.decode({
      'version': 1,
      'blocks': [
        {
          'text': 'Metin',
          'align': 'sideways',
          'left': 'far',
          'spans': [
            {'at': 0, 'length': 99, 'color': 'red', 'size': 'big'},
            {'at': 7, 'length': 1},
            'nonsense',
          ],
        },
        {'type': 'table'},
        42,
      ],
    })!;
    final block = back.blocks.single;
    expect(block.alignment, DocAlignment.left);
    expect(block.leftIndent, 0);
    // A run is kept to the text it is on; a colour Quill cannot draw is none.
    expect(block.spans.single.length, 5);
    expect(block.spans.single.color, isNull);
    expect(block.spans.single.fontSize, isNull);
    expect(DocModelJson.decode({'version': 2, 'blocks': []}), isNull);
  });

  test("Windows' HTML Format points at the copy, and Folio finds its own", () {
    final model = _sample();
    final folio = base64Encode(
      utf8.encode(jsonEncode(DocModelJson.encode(model))),
    );
    final cf = HtmlWriter.cfHtml(HtmlWriter.document(model, folio: folio));
    final header = ascii.decode(cf.sublist(0, 200), allowInvalid: true);
    int offset(String key) =>
        int.parse(RegExp('$key:([0-9]+)').firstMatch(header)!.group(1)!);
    final fragment = utf8.decode(
      cf.sublist(offset('StartFragment'), offset('EndFragment')),
    );
    expect(fragment, startsWith('<p'));
    expect(fragment, contains('İç'));
    expect(utf8.decode(cf.sublist(offset('StartHTML'))), startsWith('<html>'));
    expect(offset('EndHTML'), cf.length);
    final back = RichClipboard.decode({
      'format': 'html',
      'data': Uint8List.fromList(cf),
    })!;
    expect(back.blocks.first.hanging, 113);
    expect(back.metadata['openEnd'], isTrue);
  });
}

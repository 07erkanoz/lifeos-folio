import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/doc_delta_map.dart';
import 'package:evrak_convert/services/preview/structured_reader.dart';
import 'package:evrak_convert/services/platform/rich_clipboard.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:flutter_test/flutter_test.dart';

DocModel _read(String html) => StructuredReader.read((
  bytes: Uint8List.fromList(utf8.encode(html)),
  format: EvrakFormat.html,
));

void main() {
  test('Word CF_HTML keeps selection, inherited CSS and UTF-8 byte offsets', () {
    const prefix =
        '<html><head><style>p.MsoNormal {font-family:Calibri;'
        'font-size:14pt;text-align:center}</style></head><body>'
        '<p>Seçilmemiş İÇERİK</p><p class="MsoNormal"><b>önce ';
    const fragment = 'İstanbul Şğü';
    const suffix = ' sonra</b></p><p>Seçilmemiş son</p></body></html>';
    String header(int startHtml, int endHtml, int start, int end) =>
        'Version:1.0\r\nStartHTML:${startHtml.toString().padLeft(10, '0')}\r\n'
        'EndHTML:${endHtml.toString().padLeft(10, '0')}\r\n'
        'StartFragment:${start.toString().padLeft(10, '0')}\r\n'
        'EndFragment:${end.toString().padLeft(10, '0')}\r\n';
    final startHtml = header(0, 0, 0, 0).length;
    final start = startHtml + utf8.encode(prefix).length;
    final end = start + utf8.encode(fragment).length;
    final source =
        header(startHtml, end + suffix.length, start, end) +
        prefix +
        fragment +
        suffix;
    final model = RichClipboard.decode({
      'format': 'html',
      'data': Uint8List.fromList(utf8.encode(source)),
    })!;
    expect(model.blocks, hasLength(1));
    final paragraph = model.blocks.single;
    expect(paragraph.plainText, fragment);
    expect(paragraph.alignment, DocAlignment.center);
    expect(paragraph.spans.single.bold, true);
    expect(paragraph.spans.single.fontFamily, 'Calibri');
    expect(paragraph.spans.single.fontSize, 14);
  });

  test('Word RTF preserves Turkish characters and mixed inline formatting', () {
    final model = RichClipboard.decode({
      'format': 'rtf',
      'data': Uint8List.fromList(
        r'{\rtf1\ansi\ansicpg1254{\fonttbl{\f0 Calibri;}}'
                r'{\colortbl;\red192\green0\blue0;}\f0\fs28\qc'
                r'\b\cf1 \u304?stanbul\b0\cf0  \i\ul italik\ul0\i0\par}'
            .codeUnits,
      ),
    })!;
    final paragraph = model.blocks.first;
    expect(paragraph.plainText, contains('İstanbul'));
    expect(paragraph.alignment, DocAlignment.center);
    expect(paragraph.spans.first.fontFamily, 'Calibri');
    expect(paragraph.spans.first.fontSize, 14);
    expect(paragraph.spans.first.bold, true);
    expect(paragraph.spans.first.color, '#c00000');
    expect(paragraph.spans.any((s) => s.italic && s.underline), true);
  });

  test('actual LibreOffice clipboard preserves alignment and starts with styled text', () {
    final source = File('test/fixtures/clipboard/libreoffice-copy.html')
        .readAsStringSync()
        .replaceAll('\u0000', '');
    final model = _read(source);
    final title = model.blocks.first;
    expect(title.plainText, 'Bold heading');
    expect(title.alignment, DocAlignment.center);
    expect(title.spans.first.bold, true);
    expect(title.spans.first.fontFamily, 'Arial');
    expect(title.spans.first.fontSize, 18);
    expect(model.blocks[1].plainText, 'plain body');
  });

  test(
    'bare clipboard inline fragments keep their styles in one paragraph',
    () {
      final model = _read(
        '<span style="font-family: Arial; font-size: 18pt; '
        'color: #123456"><b>Kalın</b> <i>eğik</i></span> son',
      );
      expect(model.blocks, hasLength(1));
      expect(model.blocks.single.plainText, 'Kalın eğik son');
      expect(model.blocks.single.spans.first.fontFamily, 'Arial');
      expect(model.blocks.single.spans.first.fontSize, 18);
      expect(model.blocks.single.spans.first.bold, isTrue);
      expect(model.blocks.single.spans.any((s) => s.italic), isTrue);
    },
  );

  test('body and div styles inherit into paragraphs and table cells', () {
    final model = _read(
      '<body style="font-family: Arial; font-size: 16pt">'
      '<div style="color: #123456; text-align: center"><p>Bir</p>'
      '<p><b>İki</b></p></div><div><i>Üç</i></div>'
      '<table><tr><td><p>Dört</p></td></tr></table></body>',
    );
    expect(model.blocks, hasLength(4));
    expect(model.blocks[0].spans.single.fontFamily, 'Arial');
    expect(model.blocks[0].spans.single.fontSize, 16);
    expect(model.blocks[0].spans.single.color, '#123456');
    expect(model.blocks[0].alignment, DocAlignment.center);
    expect(model.blocks[1].spans.single.bold, isTrue);
    expect(model.blocks[2].spans.single.italic, isTrue);
    expect(
      model
          .blocks[3]
          .table!
          .rows
          .single
          .cells
          .single
          .blocks
          .single
          .spans
          .single
          .fontFamily,
      'Arial',
    );
  });

  test('browser RGB and short hex colours normalize for Quill and export', () {
    final model = _read(
      '<div style="color: rgb(192, 0, 0); background-color: #ff0">'
      '<b>Renkli</b><span style="color: nonsense"> geçersiz</span></div>',
    );
    expect(model.blocks.single.spans.first.color, '#c00000');
    expect(model.blocks.single.spans.first.background, '#ffff00');
    expect(model.blocks.single.spans.last.color, isNull);
  });

  test('Word HTML keeps inline font, size, colour and emphasis', () {
    final model = _read('''
      <html><head><style>
        p.MsoNormal { font-family: "Times New Roman"; font-size: 12pt; }
        .vurgu { color: #c00000; font-weight: 700; }
      </style></head><body>
        <p class="MsoNormal">Düz <span class="vurgu"
          style="font-family: Arial; font-size: 14pt; text-decoration: underline">
          biçimli</span> metin</p>
      </body></html>
    ''');

    final block = model.blocks.single;
    final styled = block.spans.firstWhere(
      (span) => span.bold && span.fontFamily == 'Arial',
    );
    expect(block.plainText, contains('biçimli'));
    expect(styled.fontSize, 14);
    expect(styled.color, '#c00000');
    expect(styled.underline, isTrue);
  });

  test('HTML table becomes an editable document table and survives UDF', () {
    final model = _read('''
      <table><tr><th><b>Ad</b></th><th>Değer</th></tr>
      <tr><td><span style="font-family: Arial; color: #006600">Dosya</span></td>
      <td colspan="2">2026/1</td></tr></table>
    ''');

    final tableBlock = model.blocks.single;
    expect(tableBlock.type, DocBlockType.table);
    expect(tableBlock.table!.rows, hasLength(2));
    expect(tableBlock.table!.rows.first.isHeader, isTrue);
    expect(tableBlock.table!.rows.last.cells.last.colspan, 2);
    expect(
      tableBlock
          .table!
          .rows
          .last
          .cells
          .first
          .blocks
          .single
          .spans
          .first
          .fontFamily,
      'Arial',
    );

    final mapped = DocDeltaMap.modeldenDelta(model);
    expect(mapped.korunanlar.single.type, DocBlockType.table);
    expect(mapped.delta.toJson().first['insert'], {DocDeltaMap.kTableEmbed: 0});

    final restored = UdfReader.readBytes(UdfWriter.writeBytes(model));
    expect(restored, isNotNull);
    final udfCell =
        restored!.blocks.single.table!.rows.last.cells.first.blocks.single;
    expect(udfCell.plainText, 'Dosya');
    expect(udfCell.spans.single.fontFamily, 'Arial');
    expect(udfCell.spans.single.color, '#006600');
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/platform/uyap_clipboard.dart';
import 'package:evrak_convert/services/platform/rich_clipboard.dart';
import 'package:evrak_convert/services/editor/doc_delta_map.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';

/// The fixtures are what UYAP's own editor put on the clipboard for
/// uyap-document.udf, a synthetic document (make_uyap_document.py), captured
/// with capture_uyap.sh: all of it, a range from one paragraph into a list
/// item (38:366), and a range ending inside the table (370:395).
Uint8List _fixture(String name) =>
    File('test/fixtures/clipboard/$name').readAsBytesSync();

/// Paragraphs in reading order, a table's cells in turn.
List<DocBlock> _flat(List<DocBlock> blocks) => [
  for (final b in blocks)
    if (b.table != null)
      for (final row in b.table!.rows)
        for (final cell in row.cells) ..._flat(cell.blocks)
    else if (b.type != DocBlockType.image)
      b,
];

Map<String, Object?> _run(DocBlock block, int at) {
  final s = block.spans.lastWhere(
    (s) => s.startOffset <= at && s.endOffset > at,
  );
  return {
    'font': s.fontFamily,
    'size': s.fontSize,
    'bold': s.bold,
    'italic': s.italic,
    'underline': s.underline,
    'color': s.color,
    'background': s.background,
  };
}

Map<String, Object?> _layout(DocBlock b) => {
  'align': b.alignment,
  'left': b.leftIndent,
  'right': b.rightIndent,
  'first': b.firstLineIndent,
  'hanging': b.hanging,
  'before': b.spacingBefore,
  'after': b.spacingAfter,
  'line': b.lineSpacing,
  'tabs': b.tabSet,
  'list': b.listType,
  'bullet': b.bulletType,
};

void main() {
  final document = _fixture('uyap-document.bin');

  test('a whole document copied out of UYAP reads as the file does', () {
    final pasted = UyapClipboard.read(document);
    final file = UdfReader.readBytes(_fixture('uyap-document.udf'))!;
    expect(pasted.metadata['openEnd'], isFalse);
    expect(pasted.blocks.map((b) => b.type), file.blocks.map((b) => b.type));
    final a = _flat(file.blocks), b = _flat(pasted.blocks);
    expect(b.map((p) => p.plainText), a.map((p) => p.plainText));
    for (var i = 0; i < a.length; i++) {
      expect(_layout(b[i]), _layout(a[i]), reason: a[i].plainText);
      for (var at = 0; at < a[i].plainText.length; at++) {
        expect(
          _run(b[i], at),
          _run(a[i], at),
          reason: '${a[i].plainText} @$at',
        );
      }
    }

    // What the fixture is there to carry, spelled out.
    final heading = pasted.blocks.first;
    expect(heading.alignment, DocAlignment.center);
    expect(heading.spans.first.color, '#c00000');
    expect(heading.spans.first.fontSize, 14);
    expect(pasted.blocks[1].tabSet, '113.0:0:0');
    expect(pasted.blocks[3].hanging, 113);
    // Nothing on the paragraph says so; UYAP justifies it from its style.
    expect(pasted.blocks[4].alignment, DocAlignment.justify);
    expect(pasted.blocks[4].firstLineIndent, 35.4375);
    expect(pasted.blocks[5].listType, DocListType.unordered);
    final table = pasted.blocks.singleWhere((b) => b.table != null).table!;
    expect(table.columnWidths, [120, 280]);
    expect(table.rows[1].cells[1].blocks.single.plainText, 'Örnek Kişi');
    final picture = pasted.blocks.singleWhere((b) => b.imageBase64 != null);
    expect(picture.imageWidth, 16);
    final spaced = pasted.blocks.firstWhere(
      (b) => b.plainText.startsWith('Satır aralığı'),
    );
    expect(spaced.lineSpacing, 1.5);
    expect(spaced.spacingBefore, 6);
  });

  test('a range starts in its first paragraph and stops in its last', () {
    final pasted = UyapClipboard.read(_fixture('uyap-partial.bin'));
    // The paragraph the selection began in keeps its own layout.
    expect(pasted.blocks.first.plainText, 'Asliye Hukuk Mahkemesi');
    expect(pasted.blocks.first.tabSet, '113.0:0:0');
    final last = pasted.blocks.last;
    expect(
      last.plainText,
      'İkinci madde, altı çizili ve sarı zeminli bir sözcükle: öne',
    );
    expect(last.listType, DocListType.unordered);
    expect(last.spans.last.underline, isTrue);
    expect(last.spans.last.background, '#ffff00');
    // It stops before that paragraph's end.
    expect(pasted.metadata['openEnd'], isTrue);
  });

  test(
    'a range that ends inside a table brings the table and nothing more',
    () {
      final pasted = UyapClipboard.read(_fixture('uyap-table-end.bin'));
      final table = pasted.blocks.last.table!;
      expect(table.rows, hasLength(2));
      expect(table.rows.last.cells.last.blocks.single.plainText, 'Örnek');
      // UYAP ends such a copy with a space its own paste joins away.
      expect(pasted.blocks.where((b) => b.plainText == ' '), isEmpty);
    },
  );

  test('native payload dispatch supports UYAP and RTF without plain-text conversion', () {
    expect(
      RichClipboard.decode({'format': 'uyap', 'data': document})!
          .blocks
          .first
          .spans
          .first
          .bold,
      true,
    );
    final rtf = Uint8List.fromList(
      r'{\rtf1\ansi{\fonttbl{\f0 Arial;}}\f0\fs32\b Bold\b0 plain}'.codeUnits,
    );
    final model = RichClipboard.decode({'format': 'rtf', 'data': rtf})!;
    expect(model.blocks.single.spans.first.bold, true);
    expect(model.blocks.single.spans.first.fontFamily, 'Arial');
    expect(model.blocks.single.spans.first.fontSize, 16);
  });

  test('what is pasted from UYAP maps to the editor as a UDF does', () {
    final delta = DocDeltaMap.modeldenDelta(UyapClipboard.read(document)).delta
        .toJson();
    expect(delta.first['attributes']['bold'], true);
    expect(delta.any((op) => op['attributes']?['align'] == 'center'), true);
    expect(
      delta.any(
        (op) =>
            (op['attributes']?['doc-layout'] as Map?)?['tabs'] == '113.0:0:0',
      ),
      true,
    );
  });

  test('malformed Java streams are rejected without loading Java classes', () {
    for (final length in [0, 3, 10, document.length - 5]) {
      expect(
        () => UyapClipboard.read(Uint8List.sublistView(document, 0, length)),
        throwsFormatException,
      );
    }
    expect(
      () => UyapClipboard.read(
        Uint8List.fromList([0xac, 0xed, 0, 5, 0x73, 0x70]),
      ),
      throwsFormatException,
    );
  });

  test('a broken preferred format falls back to another rich format', () {
    final model = RichClipboard.decode({
      'candidates': [
        {'format': 'uyap', 'data': Uint8List(4)},
        {'format': 'html', 'data': Uint8List.fromList('<p> </p>'.codeUnits)},
        {
          'format': 'rtf',
          'data': Uint8List.fromList(r'{\rtf1\ansi\b Bold fallback}'.codeUnits),
        },
      ],
    });
    expect(model!.blocks.first.plainText, 'Bold fallback');
    expect(model.blocks.first.spans.first.bold, true);
  });
}

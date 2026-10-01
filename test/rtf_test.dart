import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/rtf/rtf_reader.dart';
import 'package:evrak_convert/services/rtf/rtf_writer.dart';

/// RTF is bytes, not text: `\'fe` means a different letter depending on the
/// codepage in force, which is the whole difficulty of the format. Test
/// sources are written in Turkish and encoded the way Word would.
List<int> rtf(String source) => [
  for (final rune in source.runes)
    rune < 0x100 ? rune : (_cp1254[rune] ?? 0x3f),
];

const _cp1254 = {
  0x011e: 0xd0, // Ğ
  0x0130: 0xdd, // İ
  0x015e: 0xde, // Ş
  0x011f: 0xf0, // ğ
  0x0131: 0xfd, // ı
  0x015f: 0xfe, // ş
};

void main() {
  test('Turkish written in the Turkish codepage comes back as Turkish', () {
    // \'fd is ı and \'fe is ş in Windows-1254; read as Latin-1 they would be
    // ý and þ.
    final model = RtfReader.readBytes(
      rtf(
        r'{\rtf1\ansi\ansicpg1254\deff0'
        r'{\fonttbl{\f0\fcharset162 Times New Roman;}}'
        "\\pard kiralam\\'fd\\'fe olan ta\\'fe\\'fdnmaz\\par}",
      ),
    )!;
    expect(model.toPlainText(), 'kiralamış olan taşınmaz');
  });

  test('a file that names no codepage is read by the fonts it uses', () {
    // Word leaves \ansicpg out often enough; the font table still says which
    // alphabet the bytes are in.
    final model = RtfReader.readBytes(
      rtf(
        r'{\rtf1\ansi'
        r'{\fonttbl{\f0\fcharset0 Segoe UI;}{\f1\fcharset162 Times New Roman;}}'
        "\\pard\\f1 ba\\'feka\\par}",
      ),
    )!;
    expect(model.toPlainText(), 'başka');
  });

  test('Central European bytes are not read as Western European', () {
    // Word writes Turkish with these fonts more often than it should. 0xBA is
    // ş in Windows-1250 and º in Windows-1252.
    final model = RtfReader.readBytes(
      rtf(
        r'{\rtf1\ansi'
        r'{\fonttbl{\f0\fcharset238 Times New Roman;}}'
        "\\pard\\f0 ta\\'bak\\'fdr\\par}",
      ),
    )!;
    expect(model.toPlainText(), startsWith('taş'));
    expect(model.toPlainText(), isNot(contains('º')));
  });

  test('a Unicode escape wins over the letter standing in for it', () {
    // `\u304 ?` is İ followed by the character an old reader would show
    // instead. Letting the ? through spells İhtar as İ?htar.
    final model = RtfReader.readBytes(
      rtf(r'{\rtf1\ansi\uc1\pard \u304 ?htarname\par}'),
    )!;
    expect(model.toPlainText(), 'İhtarname');
  });

  test('style names do not leak into the document', () {
    // A stylesheet holds ignorable destinations of its own. Letting one of
    // those end the skip spills every style name into the text.
    final model = RtfReader.readBytes(
      rtf(
        r'{\rtf1\ansi'
        r'{\stylesheet{\s1\ql{\*\panose 02020603}Normal (Web);}'
        r'{\s2\ql No Spacing;}}'
        r'\pard Dilekçe metni\par}',
      ),
    )!;
    expect(model.toPlainText(), 'Dilekçe metni');
    expect(model.toPlainText(), isNot(contains('Spacing')));
  });

  test('bold and italic survive as runs, not as markup', () {
    final model = RtfReader.readBytes(
      rtf(
        r'{\rtf1\ansi\ansicpg1254\pard Sayın {\b DAVALI} vekili {\i Av.}\par}',
      ),
    )!;
    final block = model.blocks.first;
    expect(block.plainText, 'Sayın DAVALI vekili Av.');
    final bold = block.spans.firstWhere((s) => s.bold);
    expect(
      block.plainText.substring(bold.startOffset, bold.endOffset),
      'DAVALI',
    );
    final italic = block.spans.firstWhere((s) => s.italic);
    expect(
      block.plainText.substring(italic.startOffset, italic.endOffset),
      'Av.',
    );
  });

  test('a table is read as a table, with the columns it declares', () {
    final model = RtfReader.readBytes(
      rtf(
        r'{\rtf1\ansi\ansicpg1254'
        r'\trowd\cellx2000\cellx8000'
        r'\pard\intbl ALACAKLI\cell\pard\intbl Ayla Taş\cell\row'
        r'\trowd\cellx2000\cellx8000'
        r'\pard\intbl BORÇLU\cell\pard\intbl Murat Koyuncu\cell\row'
        r'\pard Devamı\par}',
      ),
    )!;
    final table = model.blocks
        .firstWhere((b) => b.type == DocBlockType.table)
        .table!;
    expect(table.rows.length, 2);
    expect(table.rows.first.cells.first.blocks.first.plainText, 'ALACAKLI');
    expect(table.rows[1].cells[1].blocks.first.plainText, 'Murat Koyuncu');
    // 2000 and 8000 twips are the right-hand edges, so the columns are 100 and
    // 300 points wide.
    expect(table.columnWidths, [100, 300]);
    // A layout grid, which is what these almost always are.
    expect(table.bordered, isFalse);
    expect(model.blocks.last.plainText, 'Devamı');
  });

  test('a document survives being written and read again', () {
    final model = DocModel(
      blocks: [
        DocBlock(
          plainText: 'İHTARNAME',
          alignment: DocAlignment.center,
          spans: [const DocSpan(startOffset: 0, length: 9, bold: true)],
        ),
        DocBlock(
          plainText: 'Sayın Çiğdem Şenoğlu, ödemeniz gereken tutar:',
          leftIndent: 24,
        ),
        DocBlock(
          type: DocBlockType.table,
          plainText: '',
          table: DocTable(
            columnWidths: const [120, 240],
            rows: [
              DocTableRow(
                cells: [
                  DocTableCell(blocks: [DocBlock(plainText: 'Anapara')]),
                  DocTableCell(blocks: [DocBlock(plainText: '15.225,17 EUR')]),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    final back = RtfReader.readBytes(RtfWriter.writeBytes(model))!;
    expect(back.blocks.first.plainText, 'İHTARNAME');
    expect(back.blocks.first.alignment, DocAlignment.center);
    expect(back.blocks.first.spans.single.bold, isTrue);
    expect(
      back.blocks[1].plainText,
      'Sayın Çiğdem Şenoğlu, ödemeniz gereken tutar:',
    );
    expect(back.blocks[1].leftIndent, closeTo(24, .1));
    final table = back.blocks
        .firstWhere((b) => b.type == DocBlockType.table)
        .table!;
    expect(table.rows.single.cells[1].blocks.first.plainText, '15.225,17 EUR');
    expect(table.columnWidths, [120, 240]);
  });

  test('a picture survives being written and read again', () {
    // A one-pixel PNG is enough to show the bytes make the round trip.
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    final back = RtfReader.readBytes(
      RtfWriter.writeBytes(
        DocModel(
          blocks: [
            DocBlock(
              type: DocBlockType.image,
              plainText: '',
              imageBase64: png,
              imageMime: 'image/png',
              imageWidth: 90,
              imageHeight: 60,
            ),
          ],
        ),
      ),
    )!;
    final image = back.blocks.firstWhere((b) => b.type == DocBlockType.image);
    expect(image.imageBase64, png);
    expect(image.imageMime, 'image/png');
    expect(image.imageWidth, closeTo(90, .1));
  });

  test('tab stops, a hanging indent and a list survive a round trip', () {
    // What a UYAP heading line holds: a stop 113 points in from the left
    // indent, and a value that wraps under itself.
    final model = DocModel(
      blocks: [
        DocBlock(
          plainText: 'KONU\t: Uzun bir konu satırı',
          leftIndent: 10,
          hanging: 113,
          tabSet: '113.0:0:0,300.0:2:0',
        ),
        DocBlock(
          plainText: 'Birinci madde',
          type: DocBlockType.listItem,
          listType: DocListType.ordered,
        ),
        DocBlock(
          plainText: 'İkinci madde',
          type: DocBlockType.listItem,
          listType: DocListType.unordered,
        ),
      ],
    );
    final back = RtfReader.readBytes(RtfWriter.writeBytes(model))!;
    final heading = back.blocks.first;
    expect(heading.plainText, 'KONU\t: Uzun bir konu satırı');
    // RTF counts stops from the margin, and reads back under Word's rules.
    expect(heading.tabSet, '123.0:0:0,310.0:2:0');
    expect(back.metadata['tabRules'], 'word');
    expect(heading.leftIndent, closeTo(10, .1));
    expect(heading.hanging, closeTo(113, .1));
    expect(heading.firstLineIndent, 0);
    // The marker is read to tell a numbered list from a bulleted one, and is
    // not left in the text.
    expect(back.blocks[1].listType, DocListType.ordered);
    expect(back.blocks[1].plainText, 'Birinci madde');
    expect(back.blocks[2].listType, DocListType.unordered);
    expect(back.blocks[2].plainText, 'İkinci madde');
  });

  test('line spacing is a multiple only when slmult says so', () {
    DocModel read(String spacing) =>
        RtfReader.readBytes(rtf('{\\rtf1\\ansi\\pard$spacing Metin\\par}'))!;
    expect(read('\\sl360\\slmult1').blocks.single.lineSpacing, 1.5);
    expect(read('\\sl240\\slmult1').blocks.single.lineSpacing, isNull);
    // Exactly 18 points of 12-point text: about 1.3 lines.
    expect(read('\\sl-360\\slmult0').blocks.single.lineSpacing, 1.3);
  });

  test(
    'LibreOffice names the font it drew with, and the document\'s after it',
    () {
      final model = RtfReader.readBytes(
        rtf(
          '{\\rtf1\\ansi{\\fonttbl{\\f0\\froman Liberation Serif{\\*\\falt '
          'Times New Roman};}{\\f1\\fswiss Arial;}}'
          '\\pard\\f0 Metin \\f1 ikinci\\par}',
        ),
      )!;
      expect(model.blocks.single.spans.first.fontFamily, 'Times New Roman');
      expect(model.blocks.single.spans.last.fontFamily, 'Arial');
    },
  );

  test('a table with cell borders draws them, one without does not', () {
    DocTable table(String borders) => RtfReader.readBytes(
      rtf(
        '{\\rtf1\\ansi{\\colortbl;\\red255\\green255\\blue0;}\\trowd'
        '$borders\\clcbpat1\\cellx2000\\cellx4000'
        '\\pard\\intbl A\\cell B\\cell\\row\\pard Son\\par}',
      ),
    )!.blocks.firstWhere((b) => b.table != null).table!;
    final lined = table('\\clbrdrt\\brdrs\\brdrw10');
    expect(lined.bordered, isTrue);
    expect(lined.rows.single.cells.first.backgroundColor, '#ffff00');
    expect(table('').bordered, isFalse);
  });

  test(
    'a clipboard copy says whether it stopped inside its last paragraph',
    () {
      expect(
        RtfReader.readClipboard(rtf('{\\rtf1\\ansi\\pard Bir\\par İki}'))!
            .metadata['openEnd'],
        isTrue,
      );
      expect(
        RtfReader.readClipboard(rtf('{\\rtf1\\ansi\\pard Bir\\par}'))!
            .metadata['openEnd'],
        isFalse,
      );
      // The NUL a clipboard owner leaves at the end is not text.
      expect(
        RtfReader.readBytes([...rtf('{\\rtf1\\ansi\\pard Bir\\par}'), 0])!
            .blocks
            .single
            .plainText,
        'Bir',
      );
    },
  );

  test('a file that is not RTF is refused rather than guessed at', () {
    expect(RtfReader.readBytes(utf8.encode('Bu düz metin.')), isNull);
    expect(RtfReader.readBytes(const [0x50, 0x4b, 0x03, 0x04]), isNull);
    expect(RtfReader.looksLikeRtf(rtf(r'{\rtf1\ansi}')), isTrue);
  });
}

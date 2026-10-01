import 'dart:io';
import 'dart:typed_data';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/platform/rich_clipboard.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:flutter_test/flutter_test.dart';

/// What real programs put on the clipboard for one synthetic document,
/// uyap-document.udf (see make_uyap_document.py):
///
/// - chrome-copy.html: Chrome 154 on Linux, Ctrl+A and Ctrl+C on the page
///   Folio's HTML writer makes of it, with no Folio copy inside.
/// - libreoffice-document.html and .rtf: LibreOffice 26.8, the same after
///   opening the DOCX Folio writes for it.
Uint8List _fixture(String name) =>
    File('test/fixtures/clipboard/$name').readAsBytesSync();

DocModel _decode(List<(String, String)> representations) =>
    RichClipboard.decode({
      'candidates': [
        for (final (format, name) in representations)
          {'format': format, 'data': _fixture(name)},
      ],
    })!;

DocBlock _starting(DocModel model, String text) =>
    model.blocks.firstWhere((b) => b.plainText.startsWith(text));

void main() {
  final original = UdfReader.readBytes(_fixture('uyap-document.udf'))!;

  test('Chrome: a page copied in a browser keeps what the page showed', () {
    final model = _decode([('html', 'chrome-copy.html')]);
    // The text, paragraph by paragraph, tabs and all.
    expect(
      model.blocks
          .where((b) => b.table == null && b.imageBase64 == null)
          .map((b) => b.plainText),
      original.blocks
          .where((b) => b.table == null && b.imageBase64 == null)
          .map((b) => b.plainText),
    );
    final heading = model.blocks.first;
    expect(heading.alignment, DocAlignment.center);
    expect(heading.spans.first.bold, isTrue);
    expect(heading.spans.first.fontSize, 14);
    expect(heading.spans.first.color, '#c00000');
    expect(_starting(model, 'KONU').hanging, 113);
    expect(_starting(model, 'Stilden').alignment, DocAlignment.justify);
    expect(_starting(model, 'Stilden').spans.first.fontFamily, 'Arial');
    expect(_starting(model, 'Birinci').listType, DocListType.unordered);
    final table = model.blocks.singleWhere((b) => b.table != null).table!;
    expect(table.rows.last.cells.last.blocks.single.plainText, 'Örnek Kişi');
    expect(model.blocks.where((b) => b.imageBase64 != null), hasLength(1));
    expect(
      _starting(model, 'İkinci').spans.any((s) => s.background == '#ffff00'),
      isTrue,
    );
  });

  test('LibreOffice: its RTF is read before its HTML, and keeps more', () {
    final model = _decode([
      ('html', 'libreoffice-document.html'),
      ('rtf', 'libreoffice-document.rtf'),
    ]);
    // The RTF's: a list item's indents, which the HTML leaves to the list.
    expect(_starting(model, 'Birinci').leftIndent, 54);
    expect(_starting(model, 'Birinci').hanging, 18);
    final heading = model.blocks.first;
    expect(heading.plainText, 'ÖRNEK DİLEKÇE BAŞLIĞI');
    expect(heading.alignment, DocAlignment.center);
    expect(heading.spans.first.bold, isTrue);
    expect(heading.spans.first.fontSize, 14);
    expect(heading.spans.first.color, '#c00000');
    expect(heading.spans.first.fontFamily, 'Times New Roman');
    expect(
      _starting(model, 'MAHKEME').plainText,
      'MAHKEME\t: Örnek Asliye Hukuk Mahkemesi',
    );
    expect(_starting(model, 'KONU').hanging, closeTo(113, .1));
    expect(_starting(model, 'Satır aralığı').lineSpacing, 1.5);
    expect(_starting(model, 'Satır aralığı').spacingBefore, 6);
    final table = model.blocks.singleWhere((b) => b.table != null).table!;
    expect(table.bordered, isTrue);
    expect(table.rows.first.cells.first.blocks.single.plainText, 'Taraf');
    expect(model.metadata['openEnd'], isFalse);
  });

  test('LibreOffice: its HTML alone keeps tabs, lists and tables clean', () {
    final model = _decode([('html', 'libreoffice-document.html')]);
    expect(
      _starting(model, 'MAHKEME').plainText,
      'MAHKEME\t: Örnek Asliye Hukuk Mahkemesi',
    );
    // LibreOffice indents its own markup with tabs; those are not text.
    expect(_starting(model, 'Birinci').plainText, 'Birinci madde metni.');
    final table = model.blocks.singleWhere((b) => b.table != null).table!;
    expect(table.rows.last.cells.last.blocks.single.plainText, 'Örnek Kişi');
    expect(model.blocks.first.alignment, DocAlignment.center);
    expect(_starting(model, 'KONU').hanging, closeTo(113, .2));
  });
}

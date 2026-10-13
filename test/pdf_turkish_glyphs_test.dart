import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'package:evrak_convert/services/pdf/pdfium_setup.dart';
import 'package:evrak_convert/services/preview/pdf_fonts.dart';

import 'support/pdfium.dart';

/// A one-page PDF writing [text] (cp1254 bytes) in a font it does not
/// embed, as UYAP's papers do: [font] is its dictionary.
Uint8List _pdf(String font, List<int> text) {
  final escaped = [
    for (final b in text)
      if (b < 0x80) String.fromCharCode(b) else '\\${b.toRadixString(8)}',
  ].join();
  final stream = 'BT /F1 40 Tf 10 30 Td ($escaped) Tj ET';
  return Uint8List.fromList(
    latin1.encode(
      '%PDF-1.4\n'
      '1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n'
      '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n'
      '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 300 100]'
      '/Resources<</Font<</F1 4 0 R>>>>/Contents 6 0 R>>endobj\n'
      '4 0 obj$font endobj\n'
      '5 0 obj<</Type/FontDescriptor/FontName/Arial/Flags 32'
      '/FontBBox[-665 -325 2000 1006]/ItalicAngle 0/Ascent 905'
      '/Descent -212/CapHeight 716/StemV 80>>endobj\n'
      '6 0 obj<</Length ${stream.length}>>stream\n$stream\nendstream endobj\n'
      'trailer<</Root 1 0 R>>\n%%EOF\n',
    ),
  );
}

const _encoding =
    '/Encoding<</Type/Encoding/BaseEncoding/WinAnsiEncoding'
    '/Differences[208/Gbreve 221/Idotaccent 222/Scedilla 240/gbreve'
    ' 253/dotlessi 254/scedilla]>>';

/// How many dark pixels [text] draws in [font].
Future<int> _ink(String font, List<int> text) async {
  final doc = await PdfDocument.openData(_pdf(font, text));
  try {
    final image = await doc.pages[0].render(
      fullWidth: 300,
      fullHeight: 100,
      backgroundColor: 0xffffffff,
    );
    final pixels = image!.pixels;
    var dark = 0;
    for (var i = 0; i < pixels.length; i += 4) {
      if (pixels[i] < 128 && pixels[i + 1] < 128 && pixels[i + 2] < 128) {
        dark++;
      }
    }
    image.dispose();
    return dark;
  } finally {
    await doc.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Its own file, so that no other test has loaded the fonts first: PDFium
  // keeps them for the whole process.
  test('an unembedded font draws every Turkish letter the first time a '
      'paper is opened, no viewer asking for it', () async {
    final bundled = pdfiumLibrary();
    if (bundled == null) {
      markTestSkipped('paketlenmiş PDFium yok');
      return;
    }
    PdfiumSetup.pathOverride = bundled;
    addTearDown(() => PdfiumSetup.pathOverride = null);
    expect(await PdfiumSetup.ensure(), isTrue);
    await loadCommonPdfFonts();

    const fonts = {
      'TrueType Arial':
          '<</Type/Font/Subtype/TrueType/BaseFont/Arial/FirstChar 32'
          '/LastChar 255/FontDescriptor 5 0 R$_encoding>>',
      'TrueType Arial bold':
          '<</Type/Font/Subtype/TrueType/BaseFont/Arial,Bold/FirstChar 32'
          '/LastChar 255/FontDescriptor 5 0 R$_encoding>>',
      'Type1 Helvetica':
          '<</Type/Font/Subtype/Type1/BaseFont/Helvetica$_encoding>>',
      'Type1 Times':
          '<</Type/Font/Subtype/Type1/BaseFont/Times-Roman$_encoding>>',
    };
    // İ Ş ğ ı ş Ğ.
    const turkish = {
      0xDD: 'İ',
      0xDE: 'Ş',
      0xF0: 'ğ',
      0xFD: 'ı',
      0xFE: 'ş',
      0xD0: 'Ğ',
    };
    for (final MapEntry(key: name, value: font) in fonts.entries) {
      for (final MapEntry(key: byte, value: letter) in turkish.entries) {
        expect(
          await _ink(font, [byte]),
          greaterThan(20),
          reason: '$name: $letter çizilmedi',
        );
      }
    }
  });
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/src/pdf/font/ttf_parser.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:evrak_convert/services/preview/pdf_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unembedded PDF fallbacks contain every Turkish glyph in all styles', () async {
    const resolver = BundledPdfFontResolver();
    for (final face in ['TimesNewRomanPSMT', 'Arial', 'CourierNew']) {
      for (final weight in [400, 700]) {
        for (final italic in [false, true]) {
          final query = PdfFontQuery(
            face: face,
            weight: weight,
            isItalic: italic,
            charset: PdfFontCharset.ansi,
            pitchFamily: 0,
          );
          final resolution = resolver.resolve(
            query,
            const PdfFontResolveContext(),
          )!;
          final data = await resolution.loadData!();
          final font = TtfParser(ByteData.sublistView(data));
          for (final character in 'İıŞşĞğÇçÖöÜü'.runes) {
            expect(
              font.charToGlyphIndexMap[character],
              greaterThan(0),
              reason:
                  '$face / $weight / italic=$italic: ${String.fromCharCode(character)}',
            );
          }
        }
      }
    }
  });
}

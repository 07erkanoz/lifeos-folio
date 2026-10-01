import '../fonts/document_fonts.dart';

import 'package:pdfrx/pdfrx.dart';

/// Resolve unembedded document fonts locally, including Turkish glyphs.
/// One manager shares registered fonts across viewers; no network is involved.
final previewFontManager = PdfFontManager.platform(
  resolvers: [const BundledPdfFontResolver()],
);

class BundledPdfFontResolver implements PdfFontResolver {
  const BundledPdfFontResolver();

  @override
  PdfFontResolution? resolve(
    PdfFontQuery query,
    PdfFontResolveContext context,
  ) {
    if (query.charset == PdfFontCharset.symbol) return null;
    final face = query.face.toLowerCase();
    final String family;
    if (face.contains('courier') || face.contains('mono') || query.isFixed) {
      family = 'Mono';
    } else if (face.contains('arial') ||
        face.contains('helvetica') ||
        face.contains('sans')) {
      family = 'Sans';
    } else if (face.contains('times') ||
        face.contains('serif') ||
        query.isRoman) {
      family = 'Serif';
    } else {
      return null;
    }
    final bold = query.weight >= 600 || face.contains('bold');
    final italic =
        query.isItalic || face.contains('italic') || face.contains('oblique');
    final style = bold
        ? (italic ? 'BoldItalic' : 'Bold')
        : (italic ? 'Italic' : 'Regular');
    final asset = 'fonts/pdf/Liberation$family-$style.ttf';
    return PdfFontResolution(
      targetFace: query.face,
      resolvedFace: 'Liberation $family $style',
      source: Uri(scheme: 'asset', path: asset),
      loadData: ({onProgress}) async {
        final data = await DocumentFonts.loadFace('Liberation $family', style);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      },
    );
  }
}

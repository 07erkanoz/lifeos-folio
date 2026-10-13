import '../fonts/document_fonts.dart';

import 'package:pdfrx/pdfrx.dart';

/// Resolve unembedded document fonts locally, including Turkish glyphs.
/// One manager shares registered fonts across viewers; no network is involved.
final previewFontManager = PdfFontManager.platform(
  resolvers: [const BundledPdfFontResolver()],
);

/// The fonts unembedded papers name most, loaded before any document opens.
///
/// PDFium asks for them by their standard names (an Arial UYAP did not
/// embed is asked for as Helvetica), and until one is loaded it draws the
/// text in a font of its own that has no İ, ı, Ş, ş, Ğ or ğ. Loaded only
/// when a document first asked, the first one opened in a session showed
/// those letters as gaps until it was opened again, and what reads pages
/// without the viewer (thumbnails, printing) never had them.
Future<void> loadCommonPdfFonts() => _common ??= () async {
  try {
    await previewFontManager.loadMissingFonts([
      for (final (family, roman, slant) in const [
        ('Helvetica', 'Helvetica', 'Oblique'),
        ('Times', 'Times-Roman', 'Italic'),
        ('Courier', 'Courier', 'Oblique'),
      ])
        for (final (bold, italic) in const [
          (false, false),
          (true, false),
          (false, true),
          (true, true),
        ])
          PdfFontQuery(
            face: !bold && !italic
                ? roman
                : '$family-${bold ? 'Bold' : ''}${italic ? slant : ''}',
            weight: bold ? 700 : 400,
            isItalic: italic,
            charset: PdfFontCharset.ansi,
            pitchFamily: 0,
          ),
    ]);
  } catch (_) {
    _common = null;
  }
}();

Future<void>? _common;

/// [loadCommonPdfFonts] in a window with Flutter's PDFium set up.
Future<void> preloadPdfFonts() async {
  try {
    await pdfrxFlutterInitialize();
  } catch (_) {
    return;
  }
  await loadCommonPdfFonts();
}

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

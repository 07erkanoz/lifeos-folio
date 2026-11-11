import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../models/evrak_file.dart';
import '../ocr/ocr_service.dart';
import '../pdf/pdf_pages.dart';
import '../tiff/tiff_service.dart';
import 'ai_assistant.dart';

/// A page or picture given to the AI program as it is.
class AiImage {
  const AiImage(this.mime, this.bytes);
  final String mime;
  final Uint8List bytes;
}

/// A document the lawyer added to a conversation, made ready for the AI
/// program it goes to: one with text (UDF, Word, a PDF with a text layer)
/// as its text; a scan or a picture as it is — a scanned PDF whole to
/// Claude, its pages as pictures to Codex — and to a program that takes no
/// pictures (Antigravity) as the text OCR reads in it, said so.
///
/// The rules are banaozel's web chat's (server/ek_kabul.py), measured on
/// real documents there: what a document means is in its pictures, so a
/// PDF with text and a screenshot or an embedded scan goes as it is, its
/// text alone would lose the evidence; but a whole text is better than
/// half the pages, so a scan too long to go whole goes as what OCR reads
/// in all of it, the file itself left where it is.
class AiAttachment {
  const AiAttachment({
    required this.path,
    this.text,
    this.images = const [],
    this.pdf,
    this.ocr = false,
    this.pagesLeft = 0,
    this.note,
  });

  final String path;
  String get name => p.basename(path);

  /// What goes in the question as text.
  final String? text;

  /// Pages or pictures as they are.
  final List<AiImage> images;

  /// A scanned PDF as it is (Claude reads it whole).
  final Uint8List? pdf;

  /// Whether [text] is what OCR read in a scan.
  final bool ocr;

  /// Pages of a long scan not sent, past [maxPages].
  final int pagesLeft;

  /// What the program is told of the document beside it: pictures in it
  /// too small to be read, so that it does not guess at them.
  final String? note;

  bool get visual => images.isNotEmpty || pdf != null;

  /// The most pages of a scan sent as pictures, and how wide.
  static const maxPages = 20, pageWidth = 1400;

  /// The most of a PDF Claude is given whole, and the most pages.
  static const maxPdfBytes = 30 * 1024 * 1024, maxPdfPages = 100;

  /// The most pages OCR reads of a scan too long to go as it is.
  static const maxOcrPages = 200;

  /// An embedded picture that carries meaning: a screenshot, a scan; not a
  /// QR code, a barcode, a logo or a letterhead's strip (banaozel measured
  /// 251 real PDFs: the small ones at most ~122 thousand pixels, the large
  /// at least ~250 thousand).
  static const meaningfulArea = 250000, meaningfulShortSide = 300;

  /// A PDF with small pictures alone goes as it is up to so many pages; a
  /// long text is not sent as pictures for a stamp in it.
  static const smallPicturesPages = 10;

  /// A picture whose long side is shorter than this is not read by OCR or
  /// by a model: an e-mail's print with its attachments as thumbnails.
  static const readableLongSide = 320;

  /// A QR code, an icon, a logo's strip: UYAP's 51×51 code on every page,
  /// its 16×17 marks, a bank's 232×29 logo. Nothing to read there, nor to
  /// be warned of; an e-mail's 76×166 thumbnail is.
  static const iconSide = 64;

  /// A PDF is taken for a scan when its text is shorter than this a page.
  static const scanText = 40;

  static const _pictures = {
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.webp': 'image/webp',
    '.gif': 'image/gif',
  };

  /// [path] made ready for [provider]; [mask] hides identity numbers in
  /// the text sent (a picture's cannot be).
  static Future<AiAttachment> prepare(
    String path,
    AiProvider provider, {
    bool mask = true,
  }) async {
    final ext = p.extension(path).toLowerCase();
    final format = EvrakFormat.fromExtension(ext);
    String masked(String t) => mask ? AiAssistant.maskIdentityNumbers(t) : t;
    final pictures = provider.seesPictures;
    if (format == EvrakFormat.pdf) {
      final text = (await AiAssistant.documentText(path, ocr: false)).trim();
      final pages = await _pageCount(path);
      final bytes = await File(path).readAsBytes();
      final embedded = embeddedImages(bytes);
      final note = unreadablePictures(embedded);
      if (text.length >= scanText * (pages == 0 ? 1 : pages)) {
        // Text, and pictures in it that may be the evidence.
        final meaningful = embedded.any((s) => meaningfulPicture(s.$1, s.$2));
        // A short one with small pictures too (an e-mail's print, its
        // attachments as thumbnails); not for UYAP's QR code on its pages.
        final visual =
            meaningful ||
            (embedded.any((s) => s.$1 > iconSide && s.$2 > iconSide) &&
                pages > 0 &&
                pages <= smallPicturesPages);
        if (visual && pictures) {
          if (await _whole(path, bytes, pages, provider, note)
              case final whole?) {
            return whole;
          }
        }
        return AiAttachment(path: path, text: masked(text), note: note);
      }
      // A scan.
      if (pictures) {
        if (await _whole(path, bytes, pages, provider, note)
            case final whole?) {
          return whole;
        }
      }
      return _read(path, format, masked, pages: pages, note: note);
    }
    if (format == EvrakFormat.tif) {
      if (pictures) {
        final pages = await TiffService.decodeAllPages(
          await File(path).readAsBytes(),
        );
        // Too long to go whole: what OCR reads in all of it.
        if (pages.isNotEmpty && pages.length <= maxPages) {
          return AiAttachment(
            path: path,
            images: [
              for (final page in pages) AiImage('image/png', page.pngBytes),
            ],
          );
        }
      }
      return _read(path, format, masked);
    }
    if (_pictures[ext] case final mime?) {
      if (pictures) {
        return AiAttachment(
          path: path,
          images: [AiImage(mime, await File(path).readAsBytes())],
        );
      }
      return _read(path, format, masked);
    }
    // A document with text: UDF, Word, ODT, RTF, a text file.
    final text = (await AiAssistant.documentText(path, ocr: false)).trim();
    return AiAttachment(path: path, text: masked(text));
  }

  /// The PDF at [path] as it is, when it goes whole to [provider]: to
  /// Claude the file, to Codex its pages as pictures; null when it does
  /// not fit.
  static Future<AiAttachment?> _whole(
    String path,
    Uint8List bytes,
    int pages,
    AiProvider provider,
    String? note,
  ) async {
    if (provider == AiProvider.claude) {
      if (bytes.length <= maxPdfBytes && pages <= maxPdfPages) {
        return AiAttachment(path: path, pdf: bytes, note: note);
      }
      return null;
    }
    if (pages == 0 || pages > maxPages) return null;
    final (images, _) = await _pdfPages(path);
    if (images.length < pages) return null;
    return AiAttachment(path: path, images: images, note: note);
  }

  /// What OCR reads in the scan at [path], every page of it, said to be so.
  static Future<AiAttachment> _read(
    String path,
    EvrakFormat format,
    String Function(String) masked, {
    int pages = 0,
    String? note,
  }) async {
    final text = await OcrService.recognize(
      path,
      format,
      thorough: true,
      pdfPages: format == EvrakFormat.pdf && pages > 0
          ? (pages < maxOcrPages ? pages : maxOcrPages)
          : null,
    );
    return AiAttachment(
      path: path,
      text: masked(text ?? ''),
      ocr: true,
      note: note,
      pagesLeft: pages > maxOcrPages ? pages - maxOcrPages : 0,
    );
  }

  /// Whether a picture [width] by [height] carries meaning.
  static bool meaningfulPicture(int width, int height) =>
      width * height >= meaningfulArea &&
      (width < height ? width : height) >= meaningfulShortSide;

  /// What the program is told when a PDF's pictures are all too small to
  /// be read; null when there are none or one can be.
  static String? unreadablePictures(List<(int, int)> embedded) {
    final pictures = [
      for (final s in embedded)
        if (s.$1 > iconSide && s.$2 > iconSide) s,
    ];
    if (pictures.isEmpty) return null;
    final longest = pictures
        .map((s) => s.$1 > s.$2 ? s.$1 : s.$2)
        .reduce((a, b) => a > b ? a : b);
    if (longest >= readableLongSide) return null;
    return 'Belgede ${pictures.length} küçük gömülü görsel var (en büyüğünün '
        'uzun kenarı $longest piksel; karekod, logo ya da bir ekin '
        'önizlemesi olabilir): içleri okunamaz. Onları görmüş gibi yorum '
        'yapma; içerikleri gerekiyorsa avukattan asıllarını iste.';
  }

  /// The width and height of every raster picture in the PDF [bytes]. A
  /// picture is a stream, and a stream's dictionary is never compressed
  /// (nor in an object stream), so it is read where it is written. A soft
  /// mask is counted beside its picture, of the same size: no matter here.
  static List<(int, int)> embeddedImages(Uint8List bytes) {
    final out = <(int, int)>[];
    final source = latin1.decode(bytes, allowInvalid: true);
    for (final m in _imageType.allMatches(source)) {
      final start = source.lastIndexOf('<<', m.start);
      final end = source.indexOf('stream', m.end);
      if (start < 0 || end < 0 || end - start > 4096) continue;
      final dictionary = source.substring(start, end);
      final w = _width.firstMatch(dictionary)?.group(1);
      final h = _height.firstMatch(dictionary)?.group(1);
      if (w == null || h == null) continue;
      out.add((int.parse(w), int.parse(h)));
    }
    return out;
  }

  static final _imageType = RegExp(r'/Subtype\s*/Image\b');
  static final _width = RegExp(r'/Width\s+(\d+)(?!\s+\d+\s+R)');
  static final _height = RegExp(r'/Height\s+(\d+)(?!\s+\d+\s+R)');

  static Future<int> _pageCount(String path) async {
    try {
      final source = await PdfPages.open(path);
      try {
        return source.sizes.length;
      } finally {
        await source.close();
      }
    } catch (_) {
      return 0;
    }
  }

  /// A scanned PDF's pages as PNG pictures, [maxPages] at most, and how
  /// many were left out.
  static Future<(List<AiImage>, int)> _pdfPages(String path) async {
    final out = <AiImage>[];
    try {
      final source = await PdfPages.open(path);
      try {
        final sizes = source.sizes;
        for (var i = 0; i < sizes.length && i < maxPages; i++) {
          final (w, h) = sizes[i];
          final height = (pageWidth * h / w).round();
          final pixels = await source.render(i, pageWidth, height);
          if (pixels == null) continue;
          out.add(AiImage('image/png', await compute(_png, pixels)));
        }
        return (out, sizes.length > maxPages ? sizes.length - maxPages : 0);
      } finally {
        await source.close();
      }
    } catch (_) {
      return (out, 0);
    }
  }

  static Uint8List _png(PdfPagePixels pixels) {
    final image = img.Image.fromBytes(
      width: pixels.width,
      height: pixels.height,
      bytes: pixels.bgra.buffer,
      numChannels: 4,
      order: img.ChannelOrder.bgra,
    );
    return Uint8List.fromList(img.encodePng(image, level: 4));
  }

  /// The text attachments as the question carries them.
  static String block(List<AiAttachment> attachments) => [
    for (final a in attachments)
      if (a.text != null && a.text!.isNotEmpty) ...[
        '<ek ad="${a.name.replaceAll('"', "'")}"'
            '${a.ocr ? ' okuma="OCR; yanlış okunmuş olabilir"' : ''}>',
        if (a.note case final note?) '[Not: $note]',
        a.text!.length > AiAssistant.maxCharacters
            ? '${a.text!.substring(0, AiAssistant.maxCharacters)}\n'
                  '[Ekin geri kalanı uzunluğu yüzünden gönderilmedi.]'
            : a.text!,
        if (a.ocr && a.pagesLeft > 0)
          '[Taramanın son ${a.pagesLeft} sayfası okunmadı.]',
        '</ek>',
      ] else if (a.visual)
        '[Ek: ${a.name} — sayfaları görsel olarak eklendi'
            '${a.pagesLeft > 0 ? '; ${a.pagesLeft} sayfası gönderilmedi' : ''}.'
            '${a.note == null ? '' : ' ${a.note}'}]',
  ].join('\n');
}

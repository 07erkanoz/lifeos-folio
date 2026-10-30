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
class AiAttachment {
  const AiAttachment({
    required this.path,
    this.text,
    this.images = const [],
    this.pdf,
    this.ocr = false,
    this.pagesLeft = 0,
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

  bool get visual => images.isNotEmpty || pdf != null;

  /// The most pages of a scan sent as pictures, and how wide.
  static const maxPages = 20, pageWidth = 1400;

  /// The most of a PDF Claude is given whole.
  static const maxPdfBytes = 30 * 1024 * 1024;

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
    final pictures = provider != AiProvider.antigravity;
    if (format == EvrakFormat.pdf) {
      final text = (await AiAssistant.documentText(path, ocr: false)).trim();
      final pages = await _pageCount(path);
      if (text.length >= scanText * (pages == 0 ? 1 : pages)) {
        return AiAttachment(path: path, text: masked(text));
      }
      // A scan.
      if (provider == AiProvider.claude) {
        final bytes = await File(path).readAsBytes();
        if (bytes.length <= maxPdfBytes) {
          return AiAttachment(path: path, pdf: bytes);
        }
      }
      if (pictures) {
        final (images, left) = await _pdfPages(path);
        if (images.isNotEmpty) {
          return AiAttachment(path: path, images: images, pagesLeft: left);
        }
      }
      return _read(path, format, masked);
    }
    if (format == EvrakFormat.tif) {
      if (pictures) {
        final pages = await TiffService.decodeAllPages(
          await File(path).readAsBytes(),
        );
        if (pages.isNotEmpty) {
          return AiAttachment(
            path: path,
            images: [
              for (final page in pages.take(maxPages))
                AiImage('image/png', page.pngBytes),
            ],
            pagesLeft: pages.length > maxPages ? pages.length - maxPages : 0,
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

  /// What OCR reads in the scan at [path], said to be so.
  static Future<AiAttachment> _read(
    String path,
    EvrakFormat format,
    String Function(String) masked,
  ) async {
    final text = await OcrService.recognize(path, format, thorough: true);
    return AiAttachment(path: path, text: masked(text ?? ''), ocr: true);
  }

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
        a.text!.length > AiAssistant.maxCharacters
            ? '${a.text!.substring(0, AiAssistant.maxCharacters)}\n'
                  '[Ekin geri kalanı uzunluğu yüzünden gönderilmedi.]'
            : a.text!,
        '</ek>',
      ] else if (a.visual)
        '[Ek: ${a.name} — sayfaları görsel olarak eklendi'
            '${a.pagesLeft > 0 ? '; ${a.pagesLeft} sayfası gönderilmedi' : ''}.]',
  ].join('\n');
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../tiff/image_pdf_writer.dart';
import '../tiff/tiff_service.dart';

/// What a PDF is put together from: a picture, as a page of its own, or
/// pages of a PDF ([pages] from 1, in the order wanted; all of them when
/// null).
class PdfPart {
  const PdfPart(this.path, {this.pages});

  final String path;
  final List<int>? pages;

  bool get isPdf => p.extension(path).toLowerCase() == '.pdf';

  /// A scan of several pages: a TIFF, taken as the PDF made of it.
  bool get isTiff => scans.contains(p.extension(path).toLowerCase());

  /// Whether it has pages to choose from: a PDF or a TIFF.
  bool get paged => isPdf || isTiff;

  static const scans = {'.tif', '.tiff'};

  static const pictures = {'.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif'};

  static bool supports(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.pdf' || scans.contains(ext) || pictures.contains(ext);
  }
}

/// PDFs made of what the lawyer has: pictures put together as pages (the
/// photographs of a contract, scans), chosen pages of a PDF taken out as a
/// PDF of their own, and both mixed. Pages of a PDF are taken as they are,
/// text and all; a photograph keeps its own bytes when it can.
abstract final class PdfTools {
  /// The longest side a picture keeps, in pixels: A4 at 300 dots an inch.
  /// A phone's 12 megapixels would make every page several megabytes for
  /// nothing a printer or a court's screen shows.
  static const maxSide = 3508;

  /// A4, in points; a picture's page is as wide as it (or as tall, lying
  /// on its side) and keeps the picture's own shape.
  static const _a4Short = 595.28, _a4Long = 841.89;

  /// A PDF of [pages] of [pdf] (from 1, in order, repeats allowed).
  static Future<Uint8List> extract(Uint8List pdf, List<int> pages) async {
    await pdfrxFlutterInitialize();
    final source = await PdfDocument.openData(pdf);
    final out = await PdfDocument.createNew(sourceName: 'sayfalar.pdf');
    try {
      out.pages = [
        for (final page in pages)
          if (page >= 1 && page <= source.pages.length) source.pages[page - 1],
      ];
      return await out.encodePdf();
    } finally {
      await out.dispose();
      await source.dispose();
    }
  }

  /// One PDF of [parts], in their order.
  static Future<Uint8List> build(List<PdfPart> parts, {String? title}) async {
    // Pictures alone: written directly, nothing opened.
    if (parts.every((part) => !part.paged)) {
      return fromImages([for (final part in parts) part.path], title: title);
    }
    await pdfrxFlutterInitialize();
    final opened = <PdfDocument>[];
    final out = await PdfDocument.createNew(sourceName: 'birlesik.pdf');
    try {
      final pages = <PdfPage>[];
      for (final part in parts) {
        final bytes = part.isPdf
            ? await File(part.path).readAsBytes()
            : part.isTiff
            // Each page with its own pixels, a bilevel scan still one bit.
            ? await TiffService.tiffToPdf(await File(part.path).readAsBytes())
            : await fromImages([part.path]);
        final document = await PdfDocument.openData(bytes);
        opened.add(document);
        final wanted =
            part.pages ?? [for (var i = 1; i <= document.pages.length; i++) i];
        for (final page in wanted) {
          if (page >= 1 && page <= document.pages.length) {
            pages.add(document.pages[page - 1]);
          }
        }
      }
      out.pages = pages;
      return await out.encodePdf();
    } finally {
      await out.dispose();
      for (final document in opened) {
        await document.dispose();
      }
    }
  }

  /// A PDF with each of the pictures at [paths] as a page.
  static Future<Uint8List> fromImages(
    List<String> paths, {
    String? title,
  }) async {
    final pages = <_ImagePage>[];
    for (final path in paths) {
      pages.add(await compute(_page, await File(path).readAsBytes()));
    }
    final pdf = ImagePdfWriter(title: title);
    for (final page in pages) {
      final lying = page.width > page.height;
      // As wide as an A4 sheet standing, or as one lying, and no taller
      // than it: a long receipt is fitted to the sheet's height.
      var pageWidth = lying ? _a4Long : _a4Short;
      var pageHeight = pageWidth * page.height / page.width;
      final limit = lying ? _a4Short : _a4Long;
      if (pageHeight > limit) {
        pageHeight = limit;
        pageWidth = pageHeight * page.width / page.height;
      }
      pdf.addJpegPage(
        width: page.width,
        height: page.height,
        pageWidth: pageWidth,
        pageHeight: pageHeight,
        components: page.components,
        jpeg: page.jpeg,
      );
    }
    return pdf.close();
  }

  /// [bytes] as a JPEG a PDF page takes: a JPEG that stands upright and is
  /// not too large as it is, anything else drawn upright, made smaller if
  /// it has to be, and written as one.
  static _ImagePage _page(Uint8List bytes) {
    final frame = jpegFrame(bytes);
    if (frame != null &&
        _orientation(bytes) <= 1 &&
        frame.width <= maxSide &&
        frame.height <= maxSide &&
        (frame.components == 3 || frame.components == 1)) {
      return _ImagePage(frame.width, frame.height, frame.components, bytes);
    }
    var image = img.decodeImage(bytes);
    if (image == null) throw const FormatException('Resim okunamadı.');
    image = img.bakeOrientation(image);
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > maxSide) {
      image = img.copyResize(
        image,
        width: image.width >= image.height ? maxSide : null,
        height: image.height > image.width ? maxSide : null,
        interpolation: img.Interpolation.average,
      );
    }
    // On white: a PDF page has no see-through, and a PNG's would be black.
    if (image.numChannels == 4) {
      final flat = img.Image(width: image.width, height: image.height)
        ..clear(img.ColorRgb8(255, 255, 255));
      image = img.compositeImage(flat, image);
    }
    return _ImagePage(
      image.width,
      image.height,
      3,
      Uint8List.fromList(
        img.encodeJpg(image.convert(numChannels: 3), quality: 88),
      ),
    );
  }

  /// A JPEG's size and how many colours it has, from its frame header;
  /// null when [bytes] are not a JPEG.
  static ({int width, int height, int components})? jpegFrame(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
    var at = 2;
    while (at + 9 < bytes.length) {
      if (bytes[at] != 0xFF) return null;
      final marker = bytes[at + 1];
      if (marker == 0xFF) {
        at++;
        continue;
      }
      final length = (bytes[at + 2] << 8) | bytes[at + 3];
      // A frame header: SOF0…SOF15, but for the tables among them.
      if (marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC) {
        return (
          height: (bytes[at + 5] << 8) | bytes[at + 6],
          width: (bytes[at + 7] << 8) | bytes[at + 8],
          components: bytes[at + 9],
        );
      }
      if (marker == 0xDA || length < 2) return null;
      at += 2 + length;
    }
    return null;
  }

  /// A JPEG's EXIF orientation, 1 (upright) when it says none.
  static int _orientation(Uint8List bytes) {
    try {
      final exif = img.decodeJpgExif(bytes);
      return exif?.imageIfd.orientation ?? 1;
    } catch (_) {
      return 1;
    }
  }

  /// "1-3, 5, 8-10" as page numbers in that order, each once, within
  /// [count]; null when it is not that.
  static List<int>? parseRanges(String text, int count) {
    final pages = <int>[];
    for (final piece in text.split(RegExp(r'[,;\s]+'))) {
      if (piece.isEmpty) continue;
      final m = RegExp(r'^(\d+)(?:\s*[-–]\s*(\d+))?$').firstMatch(piece);
      if (m == null) return null;
      final from = int.parse(m.group(1)!);
      final to = m.group(2) == null ? from : int.parse(m.group(2)!);
      if (from < 1 || to > count || from > to) return null;
      for (var page = from; page <= to; page++) {
        if (!pages.contains(page)) pages.add(page);
      }
    }
    return pages.isEmpty ? null : pages;
  }

  /// [pages] as the shortest text that says them: [1, 2, 3, 5] is "1-3, 5".
  static String formatRanges(List<int> pages) {
    final sorted = [...pages]..sort();
    final out = <String>[];
    for (var i = 0; i < sorted.length;) {
      var j = i;
      while (j + 1 < sorted.length && sorted[j + 1] == sorted[j] + 1) {
        j++;
      }
      out.add(i == j ? '${sorted[i]}' : '${sorted[i]}-${sorted[j]}');
      i = j + 1;
    }
    return out.join(', ');
  }
}

class _ImagePage {
  const _ImagePage(this.width, this.height, this.components, this.jpeg);
  final int width, height, components;
  final Uint8List jpeg;
}

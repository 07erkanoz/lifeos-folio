import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'image_pdf_writer.dart';

class TiffPagePng {
  final int pageIndex;
  final int width;
  final int height;
  final Uint8List pngBytes;

  const TiffPagePng({
    required this.pageIndex,
    required this.width,
    required this.height,
    required this.pngBytes,
  });
}

class TiffService {
  static const int _maxDisplayDim = 2000;

  /// TIFF içindeki toplam sayfa sayısı (header-only, hızlı).
  static Future<int> pageCount(Uint8List tiffBytes) async {
    return compute(_countPagesInIsolate, tiffBytes);
  }

  /// Tek bir sayfayı PNG olarak decode et.
  static Future<TiffPagePng?> decodePageAsPng(
    Uint8List tiffBytes,
    int pageIndex,
  ) async {
    return compute(
      _decodePageAsPngIsolate,
      _PageRequest(tiffBytes, pageIndex, _maxDisplayDim),
    );
  }

  /// Tüm sayfaları PNG olarak decode et.
  static Future<List<TiffPagePng>> decodeAllPages(Uint8List tiffBytes) async {
    return compute(
      _decodeAllAsPngIsolate,
      _PrintRequest(tiffBytes, _maxDisplayDim),
    );
  }

  /// TIFF dosyasını çok sayfalı PDF'e çevirir.
  static Future<Uint8List> tiffToPdf(Uint8List tiffBytes) async {
    if (tiffBytes.isEmpty) return Uint8List(0);
    return compute(_tiffToPdfIsolate, tiffBytes);
  }

  // ─── Isolate Fonksiyonları ──────────────────────────────────────

  static int _countPagesInIsolate(Uint8List bytes) {
    try {
      final decoder = img.TiffDecoder();
      final info = decoder.startDecode(bytes);
      if (info == null) return 0;
      return decoder.numFrames();
    } catch (_) {
      return 0;
    }
  }

  static TiffPagePng? _decodePageAsPngIsolate(_PageRequest req) {
    try {
      final decoder = img.TiffDecoder();
      final info = decoder.startDecode(req.bytes);
      if (info == null) return null;

      final frameCount = decoder.numFrames();
      if (req.pageIndex < 0 || req.pageIndex >= frameCount) return null;

      var frame = decoder.decodeFrame(req.pageIndex);
      if (frame == null) return null;

      frame = _resizeIfNeeded(frame, req.maxDim);
      final pngBytes = Uint8List.fromList(img.encodePng(frame, level: 4));

      return TiffPagePng(
        pageIndex: req.pageIndex,
        width: frame.width,
        height: frame.height,
        pngBytes: pngBytes,
      );
    } catch (_) {
      return null;
    }
  }

  static List<TiffPagePng> _decodeAllAsPngIsolate(_PrintRequest req) {
    try {
      final decoder = img.TiffDecoder();
      final info = decoder.startDecode(req.bytes);
      if (info == null) return [];

      final frameCount = decoder.numFrames();
      final pages = <TiffPagePng>[];

      for (int i = 0; i < frameCount; i++) {
        var frame = decoder.decodeFrame(i);
        if (frame == null) continue;

        frame = _resizeIfNeeded(frame, req.maxDim);
        final pngBytes = Uint8List.fromList(img.encodePng(frame, level: 4));

        pages.add(
          TiffPagePng(
            pageIndex: i,
            width: frame.width,
            height: frame.height,
            pngBytes: pngBytes,
          ),
        );
      }

      return pages;
    } catch (_) {
      return [];
    }
  }

  static Future<Uint8List> _tiffToPdfIsolate(Uint8List bytes) async {
    try {
      final decoder = img.TiffDecoder();
      final info = decoder.startDecode(bytes);
      if (info == null) return Uint8List(0);
      final frameCount = decoder.numFrames();
      if (frameCount == 0) return Uint8List(0);

      final pdf = ImagePdfWriter(title: 'Evrak TIF Dönüşümü');
      for (int i = 0; i < frameCount; i++) {
        try {
          final frame = decoder.decodeFrame(i);
          if (frame == null) return Uint8List(0);

          // Preserve each page's physical dimensions, not an assumed DPI.
          final tags = info.images[i].tags;
          final unit = tags[0x0128]?.read()?.toInt() ?? 2;
          double dpi(int tag) {
            final value = tags[tag]?.read()?.toDouble();
            if (value == null || !value.isFinite || value <= 0 || unit == 1) {
              return 150;
            }
            return unit == 3 ? value * 2.54 : value;
          }

          final page = pageSamples(frame);
          pdf.addPage(
            width: frame.width,
            height: frame.height,
            pageWidth: frame.width * 72 / dpi(0x011a),
            pageHeight: frame.height * 72 / dpi(0x011b),
            bitsPerComponent: page.bits,
            colorSpace: page.colorSpace,
            samples: page.samples,
          );
        } catch (e) {
          debugPrint('TiffService sayfa $i dönüştürme hatası: $e');
          return Uint8List(0);
        }
      }
      return pdf.close();
    } catch (e) {
      debugPrint('TiffService tiffToPdf hatası: $e');
      return Uint8List(0);
    }
  }

  /// A decoded page as PDF image samples, losing nothing: a bilevel page
  /// stays one bit per pixel (the `image` package keeps 1 as white, as a PDF
  /// DeviceGray image reads it), a greyscale page stays grey, and anything
  /// else becomes 8-bit RGB. Alpha is dropped; a document page has none.
  @visibleForTesting
  static ({int bits, String colorSpace, Uint8List samples}) pageSamples(
    img.Image frame,
  ) {
    final w = frame.width, h = frame.height;
    if (frame.format == img.Format.uint1 &&
        frame.numChannels == 1 &&
        !frame.hasPalette) {
      final stride = (w + 7) >> 3;
      final data = frame.toUint8List();
      if (frame.rowStride == stride && data.length >= stride * h) {
        return (
          bits: 1,
          colorSpace: 'DeviceGray',
          samples: Uint8List.sublistView(data, 0, stride * h),
        );
      }
      final out = Uint8List(stride * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (frame.getPixel(x, y).r != 0) {
            out[y * stride + (x >> 3)] |= 0x80 >> (x & 7);
          }
        }
      }
      return (bits: 1, colorSpace: 'DeviceGray', samples: out);
    }
    final grey = frame.numChannels == 1 && !frame.hasPalette;
    final eight = frame.convert(
      format: img.Format.uint8,
      numChannels: grey ? 1 : 3,
    );
    final channels = grey ? 1 : 3;
    final data = eight.toUint8List();
    final samples = eight.rowStride == w * channels
        ? Uint8List.sublistView(data, 0, w * channels * h)
        : Uint8List.fromList([
            for (var y = 0; y < h; y++)
              ...data.sublist(
                y * eight.rowStride,
                y * eight.rowStride + w * channels,
              ),
          ]);
    return (
      bits: 8,
      colorSpace: grey ? 'DeviceGray' : 'DeviceRGB',
      samples: samples,
    );
  }

  static img.Image _resizeIfNeeded(img.Image image, int maxDim) {
    final longestSide = image.width > image.height ? image.width : image.height;
    if (longestSide <= maxDim) return image;

    int newW, newH;
    if (image.width > image.height) {
      newW = maxDim;
      newH = (image.height * maxDim / image.width).round();
    } else {
      newH = maxDim;
      newW = (image.width * maxDim / image.height).round();
    }

    return img.copyResize(
      image,
      width: newW.clamp(1, maxDim),
      height: newH.clamp(1, maxDim),
      interpolation: img.Interpolation.average,
    );
  }
}

class _PageRequest {
  final Uint8List bytes;
  final int pageIndex;
  final int maxDim;
  const _PageRequest(this.bytes, this.pageIndex, this.maxDim);
}

class _PrintRequest {
  final Uint8List bytes;
  final int maxDim;
  const _PrintRequest(this.bytes, this.maxDim);
}

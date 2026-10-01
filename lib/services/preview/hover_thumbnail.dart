import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import '../../models/evrak_file.dart';
import 'preview_cache.dart';

/// Pixel box the hover card can show, in device pixels.
///
/// Documents are rendered to this width and cropped to this height rather than
/// scaled down to a whole-page thumbnail, so body text stays at roughly its
/// printed size and remains readable while browsing the archive.
class HoverThumbnailRequest {
  final int width;
  final int height;
  const HoverThumbnailRequest({required this.width, required this.height});

  /// Renders stay comparable across displays without producing huge rasters on
  /// high-DPI screens.
  HoverThumbnailRequest get clamped => HoverThumbnailRequest(
    width: width.clamp(320, 1600),
    height: height.clamp(320, 2000),
  );
  String get cacheKey => '${width}x$height';
}

/// One thumbnail job at a time; abandoned queued hovers never open files.
class HoverThumbnail {
  static final _cache = <String, Uint8List>{};
  static Future<void> _tail = Future.value();
  static Future<Uint8List?> load(
    EvrakFile file,
    bool Function() wanted,
    HoverThumbnailRequest request,
  ) {
    final target = request.clamped;
    final task = _tail.then((_) async {
      if (!wanted()) return null;
      final stat = await File(file.path).stat();
      final key =
          '${file.path}:${stat.size}:${stat.modified}:${stat.changed}'
          ':${target.cacheKey}';
      final cached = _cache.remove(key);
      if (cached != null) {
        _cache[key] = cached;
        return cached;
      }
      // Large documents remain available through normal preview; hover must
      // not trigger an expensive conversion just while browsing the archive.
      if (!wanted() || stat.size > 8 * 1024 * 1024) return null;
      ui.Image? image;
      PdfDocument? document;
      PdfImage? rendered;
      try {
        if (file.format == EvrakFormat.image) {
          final codec = await ui.instantiateImageCodec(
            await File(file.path).readAsBytes(),
            targetWidth: target.width,
            allowUpscaling: false,
          );
          try {
            image = (await codec.getNextFrame()).image;
          } finally {
            codec.dispose();
          }
        } else if ([
          EvrakFormat.pdf,
          EvrakFormat.udf,
          EvrakFormat.docx,
          EvrakFormat.odt,
          EvrakFormat.rtf,
          EvrakFormat.doc,
          EvrakFormat.text,
        ].contains(file.format)) {
          await pdfrxFlutterInitialize();
          if (!wanted()) return null;
          if (file.format == EvrakFormat.pdf) {
            document = await PdfDocument.openFile(file.path);
          } else {
            final preview = await PreviewCache.load(file);
            if (!wanted()) return null;
            document = await PdfDocument.openData(preview.pdfBytes);
          }
          if (!wanted() || document.pages.isEmpty) return null;
          final page = document.pages.first;
          // Fit the page width, then keep only the top of it. Fitting the whole
          // page instead would leave body text a few pixels tall.
          final fullHeight = page.height * target.width / page.width;
          rendered = await page.render(
            width: target.width,
            height: math.min(target.height, fullHeight.ceil()),
            fullWidth: target.width.toDouble(),
            fullHeight: fullHeight,
            backgroundColor: 0xFFFFFFFF,
          );
          image = await rendered?.createImage();
        }
        final data = await image?.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) return null;
        final bytes = data.buffer.asUint8List();
        _cache[key] = bytes;
        while (_cache.length > 8 ||
            _cache.values.fold<int>(0, (n, b) => n + b.length) >
                16 * 1024 * 1024) {
          _cache.remove(_cache.keys.first);
        }
        return bytes;
      } finally {
        image?.dispose();
        rendered?.dispose();
        await document?.dispose();
      }
    });
    _tail = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }
}

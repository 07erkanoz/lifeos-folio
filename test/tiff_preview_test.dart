import 'package:flutter/foundation.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:evrak_convert/services/platform/native_tools.dart';
import 'package:evrak_convert/services/tiff/tiff_preview_session.dart';
import 'package:evrak_convert/services/tiff/tiff_service.dart';

import 'support/pdf_readback.dart';

void main() {
  test('TIFF session reuses one decoder and deduplicates prefetched pages; PDF preserves DPI and pixels', () async {
    final dir = await Directory.systemTemp.createTemp('folio-tiff-session-');
    TiffPreviewSession? session;
    try {
      for (var i = 0; i < 2; i++) {
        final image = img.Image(
          width: i == 0 ? 4200 : 300,
          height: 60,
          numChannels: 3,
        );
        img.fill(
          image,
          color: img.ColorRgb8(i == 0 ? 255 : 0, 40, i == 0 ? 0 : 255),
        );
        image.exif.imageIfd.xResolution = [300, 1];
        image.exif.imageIfd.yResolution = [300, 1];
        image.exif.imageIfd.resolutionUnit = 2;
        await File('${dir.path}/$i.tif').writeAsBytes(img.encodeTiff(image));
      }
      final source = File('${dir.path}/two.tiff');
      // The copy the checkout ships, as the app itself runs it: PATH on a
      // Windows machine has no tiffcp.
      final joined = await Process.run(await NativeTools.executable('tiffcp'), [
        '-c',
        'zip',
        '${dir.path}/0.tif',
        '${dir.path}/1.tif',
        source.path,
      ]);
      expect(joined.exitCode, 0);
      session = await TiffPreviewSession.open(source.path);
      expect(session.pageCount, 2);
      final first = await session.page(0);
      expect(first.width, 2000); // Display only; PDF keeps 4200 source pixels.
      final watch = Stopwatch()..start();
      final prefetch = session.page(1, priority: false);
      final clicked = session.page(1);
      expect(identical(prefetch, clicked), true);
      final next = await clicked;
      expect(next.width, 300);
      expect(next.rgba.take(4), [0, 40, 255, 255]);
      expect(session.decodedPages, 2);
      debugPrint(
        'TIFF persistent decoder, next page: ${watch.elapsedMilliseconds} ms',
      );
      final original = await source.readAsBytes();
      final bytes = await TiffService.tiffToPdf(original);
      final pdf = await PdfReadback.of(bytes);
      expect(pdf.pageCount, 2);
      expect(pdf.pageSizes[0].$1, closeTo(1008, .01));
      expect(pdf.pageSizes[0].$2, closeTo(14.4, .01));
      expect(pdf.pageSizes[1].$1, closeTo(72, .01));
      expect(String.fromCharCodes(bytes), contains('/Width 4200'));
      expect(await source.readAsBytes(), original);
      session.close();
      await expectLater(session.page(0), throwsStateError);
    } finally {
      session?.close();
      await dir.delete(recursive: true);
    }
  });
}

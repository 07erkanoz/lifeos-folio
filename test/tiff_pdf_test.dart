import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:evrak_convert/services/tiff/tiff_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fixtures were drawn, not scanned, and written by libtiff (Pillow): a
/// bilevel page shaped like UYAP's TIFFs (CCITT G4, min-is-black, eight rows
/// a strip) and an 8-bit grey LZW page. The `.pgm` beside each is libtiff's
/// own decoding, so the check does not trust the decoder it is checking.
void main() {
  ({int width, int height, Uint8List grey}) pgm(String path) {
    final bytes = File(path).readAsBytesSync();
    final header = latin1.decode(bytes.sublist(0, 32)).split(RegExp(r'\s+'));
    final width = int.parse(header[1]), height = int.parse(header[2]);
    return (
      width: width,
      height: height,
      grey: Uint8List.sublistView(bytes, bytes.length - width * height),
    );
  }

  /// The single image of a one-page PDF, decoded to one byte per pixel.
  ({int width, int height, int bits, String space, Uint8List grey, String box})
  image(Uint8List pdf) {
    final text = latin1.decode(pdf);
    final m = RegExp(
      r'/Subtype/Image/Width (\d+)/Height (\d+)/ColorSpace/(\w+)'
      r'/BitsPerComponent (\d+)/Filter/FlateDecode/Length (\d+)>>\nstream\n',
    ).firstMatch(text)!;
    final width = int.parse(m[1]!), height = int.parse(m[2]!);
    final bits = int.parse(m[4]!);
    final data = ZLibDecoder().convert(
      pdf.sublist(m.end, m.end + int.parse(m[5]!)),
    );
    final grey = Uint8List(width * height);
    if (bits == 1) {
      final stride = (width + 7) >> 3;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final on = data[y * stride + (x >> 3)] & (0x80 >> (x & 7));
          grey[y * width + x] = on == 0 ? 0 : 255;
        }
      }
    } else {
      grey.setAll(0, data);
    }
    final box = RegExp(r'/MediaBox\[([^\]]+)\]').firstMatch(text)![1]!;
    return (
      width: width,
      height: height,
      bits: bits,
      space: m[3]!,
      grey: grey,
      box: box,
    );
  }

  test(
    'a UYAP-style G4 page stays one bit per pixel, pixel for pixel',
    () async {
      final tiff = File('test/fixtures/tiff/g4-strips.tif').readAsBytesSync();
      final pdf = await TiffService.tiffToPdf(tiff);
      final got = image(pdf);
      final want = pgm('test/fixtures/tiff/g4-strips.pgm');
      expect(got.bits, 1);
      expect(got.space, 'DeviceGray');
      expect((got.width, got.height), (want.width, want.height));
      expect(got.grey, want.grey);
      // 200 dpi: 203 px is 73.08 pt wide, 97 px is 34.92 pt high.
      expect(got.box, '0 0 73.08 34.92');
    },
  );

  test('a grey page stays 8-bit grey, pixel for pixel', () async {
    final tiff = File('test/fixtures/tiff/grey-lzw.tif').readAsBytesSync();
    final got = image(await TiffService.tiffToPdf(tiff));
    final want = pgm('test/fixtures/tiff/grey-lzw.pgm');
    expect(got.bits, 8);
    expect(got.space, 'DeviceGray');
    expect(got.grey, want.grey);
    expect(got.box, '0 0 46.08 28.8');
  });

  test('the written PDF is well formed for a strict reader', () async {
    final pdf = await TiffService.tiffToPdf(
      File('test/fixtures/tiff/g4-strips.tif').readAsBytesSync(),
    );
    final text = latin1.decode(pdf);
    expect(text, startsWith('%PDF-1.4'));
    expect(text.trimRight(), endsWith('%%EOF'));
    // Every xref offset points at the object it names.
    final start = int.parse(RegExp(r'startxref\n(\d+)').firstMatch(text)![1]!);
    final rows = RegExp(r'(\d{10}) 00000 n ')
        .allMatches(text.substring(start))
        .toList();
    for (var i = 0; i < rows.length; i++) {
      final at = int.parse(rows[i][1]!);
      expect(text.substring(at), startsWith('${i + 1} 0 obj'));
    }
  });
}

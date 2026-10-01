import 'dart:typed_data';

import 'package:evrak_convert/services/ocr/grey_resize.dart';
import 'package:flutter_test/flutter_test.dart';

/// The expected values are Pillow's `Image.resize(size, Image.BICUBIC)` of
/// the same 7 × 5 grey image, which the OCR measurements were made with.
void main() {
  final source = Uint8List.fromList([
    for (var y = 0; y < 5; y++)
      for (var x = 0; x < 7; x++) (x * 37 + y * 91 + x * y * 13) % 256,
  ]);

  void matchesPillow(Uint8List got, List<int> pillow) {
    expect(got.length, pillow.length);
    for (var i = 0; i < got.length; i++) {
      expect((got[i] - pillow[i]).abs(), lessThanOrEqualTo(1), reason: '$i');
    }
  }

  test('enlarging matches Pillow bicubic', () {
    matchesPillow(resizeGrey(source, 7, 5, 17, 12), const [
      0, 0, 7, 25, 39, 54, 69, 82, 98, 122, 149, 169, 183, 197, 215, 227, //
      234, 6, 10, 23, 43, 59, 75, 92, 109, 122, 129, 134, 146, 162, 178, 198,
      212, 220, 39, 45, 59, 82, 105, 131, 155, 181, 187, 146, 91, 79, 100,
      126, 155, 178, 188, 82, 90, 108, 133, 156, 178, 203, 239, 240, 162, 59,
      29, 56, 88, 115, 135, 144, 131, 140, 167, 191, 179, 152, 152, 186, 201,
      156, 94, 84, 117, 136, 118, 95, 87, 174, 185, 221, 243, 187, 98, 66, 94,
      129, 143, 154, 177, 216, 216, 140, 63, 33, 154, 166, 203, 228, 176, 91,
      63, 93, 130, 145, 159, 186, 229, 233, 160, 84, 54, 65, 77, 108, 140,
      142, 131, 143, 183, 204, 164, 109, 110, 159, 191, 181, 164, 158, 9, 21,
      50, 88, 119, 150, 185, 231, 244, 176, 86, 65, 101, 142, 181, 213, 226,
      42, 56, 94, 130, 129, 110, 120, 165, 193, 174, 139, 112, 89, 90, 133,
      178, 196, 91, 107, 154, 188, 144, 65, 43, 84, 130, 169, 198, 171, 91,
      48, 83, 130, 147, 108, 125, 175, 209, 150, 48, 15, 54, 107, 167, 220,
      192, 90, 30, 63, 113, 131,
    ]);
  });

  test('shrinking matches Pillow bicubic, without aliasing', () {
    matchesPillow(resizeGrey(source, 7, 5, 4, 3), const [
      57, 131, 126, 162, 155, 148, 148, 139, 103, 127, 143, 130, //
    ]);
  });

  test('a flat grey stays flat at any size', () {
    final flat = Uint8List(40 * 30)..fillRange(0, 1200, 173);
    for (final (w, h) in [(100, 75), (13, 9), (40, 30)]) {
      expect(resizeGrey(flat, 40, 30, w, h), everyElement(173));
    }
  });
}

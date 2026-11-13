import 'dart:typed_data';

import 'package:evrak_convert/services/ocr/ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

// A page scanned on its side reads as nonsense: it is turned a quarter
// either way and read again, and the turned reading kept only when it is
// far better (measured on 257 scanned pages, 13 November 2026).
void main() {
  OcrPageRead read({required int good, required int words}) => OcrPageRead(
    text: '',
    good: good,
    confidence: 30,
    wordHeight: 20,
    words: words,
  );

  test('a page on its side: many words, hardly one read with confidence', () {
    expect(read(good: 0, words: 455).sideways, isTrue);
    expect(read(good: 3, words: 259).sideways, isTrue);
    // Read well, or too few words to judge.
    expect(read(good: 108, words: 394).sideways, isFalse);
    expect(read(good: 2, words: 20).sideways, isFalse);
  });

  test('a turned reading kept only when far better', () {
    final asItIs = read(good: 11, words: 106);
    // 11 → 20 on an upright page: noise, not the right way round.
    expect(read(good: 20, words: 168).betterThan(asItIs), isFalse);
    expect(
      read(good: 212, words: 510).betterThan(read(good: 0, words: 455)),
      isTrue,
    );
  });

  test('a quarter turn either way, and back', () {
    // 3 wide, 2 tall:
    //   1 2 3
    //   4 5 6
    final luma = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
    final (cw, w, h) = OcrService.turn(luma, 3, 2, clockwise: true);
    expect((w, h), (2, 3));
    expect(cw, [4, 1, 5, 2, 6, 3]);
    final (ccw, _, _) = OcrService.turn(luma, 3, 2, clockwise: false);
    expect(ccw, [3, 6, 2, 5, 1, 4]);
    final (back, bw, bh) = OcrService.turn(cw, w, h, clockwise: false);
    expect((bw, bh), (3, 2));
    expect(back, luma);
  });
}

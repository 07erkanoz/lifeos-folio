import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/docx/docx_bridge.dart';

/// Smallest valid PNG: 8x8, greyscale, all white.
Uint8List pixel() => Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x08,
  0x08, 0x00, 0x00, 0x00, 0x00, 0x3A, 0x2A, 0xF4,
  0xBF, 0x00, 0x00, 0x00, 0x16, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0xFC, 0xCF, 0x80, 0x1B,
  0xFC, 0xFF, 0xFF, 0xFF, 0x19, 0x18, 0x00, 0x00,
  0xFF, 0xFF, 0x03, 0x00, 0x3B, 0x61, 0x09, 0xF1,
  0x1F, 0x6D, 0x3E, 0xD9, 0x00, 0x00, 0x00, 0x00,
  0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

String plain(DocModel m) => m.blocks.map((b) => b.plainText).join('\n');
int images(DocModel m) =>
    m.blocks.where((b) => b.type == DocBlockType.image).length;

void main() {
  testWidgets('a document with pictures does not grow when it is saved', (
    tester,
  ) async {
    // A picture on a line of its own is a paragraph holding nothing else.
    // Reading that as both a paragraph and a picture put a blank line into
    // the document, and because saving gives the picture its own paragraph
    // again the blank line came back doubled on the next save: a filing with
    // three exhibits gained three empty lines every time it was opened and
    // written out.
    final model = DocModel(
      blocks: [
        DocBlock(plainText: 'EK 1:'),
        DocBlock(
          type: DocBlockType.image,
          plainText: '',
          imageBase64: base64Png(),
          imageMime: 'image/png',
          imageWidth: 80,
          imageHeight: 80,
        ),
        DocBlock(plainText: 'EK 2:'),
        DocBlock(
          type: DocBlockType.image,
          plainText: '',
          imageBase64: base64Png(),
          imageMime: 'image/png',
          imageWidth: 80,
          imageHeight: 80,
        ),
      ],
    );

    var current = model;
    for (var round = 1; round <= 3; round++) {
      final bytes = await tester.runAsync(() => DocxBridge.writeBytes(current));
      final back = await tester.runAsync<DocModel?>(
        () => DocxBridge.readBytes(bytes!),
      );
      expect(back, isNotNull, reason: '$round. turda okunamadı');
      expect(
        images(back!),
        images(model),
        reason: '$round. turda resim sayısı değişti',
      );
      expect(
        plain(back).trim(),
        plain(model).trim(),
        reason: '$round. turda metin değişti',
      );
      // Saving the same document repeatedly has to reach the same place, not
      // drift a line at a time.
      expect(
        back.blocks.length,
        model.blocks.length,
        reason: '$round. turda blok sayısı değişti',
      );
      current = back;
    }
  });

  testWidgets('a paragraph that has both text and a picture keeps both', (
    tester,
  ) async {
    // The blank paragraph is only dropped when the picture is all there was.
    // Text beside a picture still has to survive.
    final model = DocModel(
      blocks: [
        DocBlock(plainText: 'Ekteki görsel:'),
        DocBlock(
          type: DocBlockType.image,
          plainText: '',
          imageBase64: base64Png(),
          imageMime: 'image/png',
          imageWidth: 80,
          imageHeight: 80,
        ),
      ],
    );
    final bytes = await tester.runAsync(() => DocxBridge.writeBytes(model));
    final back = await tester.runAsync<DocModel?>(
      () => DocxBridge.readBytes(bytes!),
    );
    expect(plain(back!), contains('Ekteki görsel:'));
    expect(images(back), 1);
  });
}

String base64Png() => _b64 ??= _encode(pixel());
String? _b64;
String _encode(Uint8List bytes) => const Base64Codec().encode(bytes);

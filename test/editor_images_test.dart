import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:image/image.dart' as img;
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/editor/doc_delta_map.dart';
import 'package:evrak_convert/services/editor/editor_images.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/editor_image_embed.dart';

String _pngBase64(int width, int height) =>
    base64Encode(img.encodePng(img.Image(width: width, height: height)));

DocModel _withImage({
  DocAlignment alignment = DocAlignment.left,
  double? width = 300,
  double? height = 200,
}) => DocModel(
  blocks: [
    DocBlock(plainText: 'Ekli fotoğraf:'),
    DocBlock(
      type: DocBlockType.image,
      plainText: '',
      alignment: alignment,
      imageBase64: _pngBase64(40, 20),
      imageMime: 'image/png',
      imageWidth: width,
      imageHeight: height,
    ),
    DocBlock(plainText: 'Saygılarımla'),
  ],
);

void main() {
  test('a picture reaches the editor as a picture, not a label', () {
    final delta = DocDeltaMap.modeldenDelta(_withImage()).delta;
    final ops = delta.toList();
    final embed = ops.firstWhere((op) => op.data is Map);
    final uri = (embed.data as Map)[DocDeltaMap.kImageEmbed] as String;
    expect(uri, startsWith('data:image/png;base64,'));
    expect(
      delta.toList().whereType<Operation>().any(
        (op) => op.data is String && (op.data as String).contains('Görsel'),
      ),
      isFalse,
      reason: 'yer tutucu metin kalmamalı',
    );
  });

  test('a picture survives the trip to the editor and back', () {
    final model = _withImage(alignment: DocAlignment.center);
    final mapped = DocDeltaMap.modeldenDelta(model);
    final back = DocDeltaMap.deltadanModel(mapped.delta);

    expect(back.blocks.length, 3);
    final image = back.blocks[1];
    expect(image.type, DocBlockType.image);
    expect(image.imageBase64, model.blocks[1].imageBase64);
    expect(image.imageMime, 'image/png');
    expect(image.imageWidth, 300);
    expect(image.imageHeight, 200);
    expect(image.alignment, DocAlignment.center);
    expect(back.blocks.first.plainText, 'Ekli fotoğraf:');
    expect(back.blocks.last.plainText, 'Saygılarımla');
  });

  test('deleting the picture in the editor deletes it from the document', () {
    // The old placeholder was restored from a side list whatever the editor
    // did, so the image came back however hard it was deleted.
    final delta = DocDeltaMap.modeldenDelta(_withImage()).delta;
    final kept = Delta();
    for (final op in delta.toList()) {
      if (op.data is Map) continue;
      kept.insert(op.data, op.attributes);
    }
    final back = DocDeltaMap.deltadanModel(kept);
    expect(back.blocks.any((b) => b.type == DocBlockType.image), isFalse);
  });

  test('a picture written next to text keeps both', () {
    // Someone can type on the picture's line; UDF gives an image a paragraph
    // of its own, so the text has to become one too rather than disappear.
    final delta = Delta()
      ..insert('Ek-1 ')
      ..insert({DocDeltaMap.kImageEmbed: 'data:image/png;base64,AAAA'})
      ..insert('\n');
    final back = DocDeltaMap.deltadanModel(delta);
    expect(back.blocks.map((b) => b.type), [
      DocBlockType.paragraph,
      DocBlockType.image,
    ]);
    expect(back.blocks.first.plainText, 'Ek-1 ');
  });

  test('a picture at the very end is not dropped', () {
    final delta = Delta()
      ..insert('Metin\n')
      ..insert({DocDeltaMap.kImageEmbed: 'data:image/jpeg;base64,AAAA'});
    final back = DocDeltaMap.deltadanModel(delta);
    expect(back.blocks.last.type, DocBlockType.image);
    expect(back.blocks.last.imageMime, 'image/jpeg');
  });

  test('a picture survives a UDF save and reopen', () {
    final model = _withImage(alignment: DocAlignment.center);
    final editor = DocDeltaMap.deltadanModel(
      DocDeltaMap.modeldenDelta(model).delta,
    );
    final reopened = UdfReader.readBytes(UdfWriter.writeBytes(editor))!;
    final image = reopened.blocks.firstWhere(
      (b) => b.type == DocBlockType.image,
    );
    expect(image.imageBase64, model.blocks[1].imageBase64);
    expect(image.imageWidth, 300);
    expect(image.imageHeight, 200);
  });

  test('a picture whose data is line-wrapped still decodes', () {
    // UYAP writes imageData wrapped at 76 characters. Dart's base64 decoder
    // rejects the line breaks, so a document with a picture would not preview
    // at all until the wrapping is taken out on the way in.
    final data = _pngBase64(16, 16);
    final wrapped = [
      for (var i = 0; i < data.length; i += 76)
        data.substring(i, i + 76 > data.length ? data.length : i + 76),
    ].join('\n');
    expect(wrapped, contains('\n'));
    final xml = UdfWriter.writeBytes(
      DocModel(
        blocks: [
          DocBlock(
            type: DocBlockType.image,
            plainText: '',
            imageBase64: wrapped,
            imageMime: 'image/png',
            imageWidth: 12,
            imageHeight: 12,
          ),
        ],
      ),
    );
    final read = UdfReader.readBytes(xml)!;
    final image = read.blocks.firstWhere((b) => b.type == DocBlockType.image);
    expect(image.imageBase64, data);
    expect(() => base64Decode(image.imageBase64!), returnsNormally);
  });

  test('the embed builder answers to the type the mapper writes', () {
    expect(EditorImageEmbed().key, DocDeltaMap.kImageEmbed);
    expect(BlockEmbed.imageType, DocDeltaMap.kImageEmbed);
  });

  test('the editor can read back the bytes it was given', () {
    final data = _pngBase64(8, 8);
    final bytes = EditorImageEmbed.decode(
      DocDeltaMap.imageUri(data, 'image/png'),
    );
    expect(bytes, isNotNull);
    expect(img.findDecoderForData(bytes!)?.startDecode(bytes)?.width, 8);
    expect(
      EditorImageEmbed.decode('/home/kullanici/resim.png'),
      isNull,
      reason: 'dosya yolu gövde sanılmamalı',
    );
  });

  test('a wide picture is scaled to the text column, a small one is not', () {
    // A phone photograph is some 3000 px across; the column is 450 pt.
    final photo = EditorImages.fit(3024, 4032);
    expect(photo.width, EditorImages.columnWidth);
    expect(photo.height, closeTo(600, 1), reason: 'oran korunmalı');

    // A scanned seal stays its own size rather than being blown up.
    final seal = EditorImages.fit(120, 120);
    expect(seal.width, 90);
    expect(seal.height, 90);
  });

  test('a picture is measured without decoding all of it', () {
    final size = EditorImages.measure(base64Decode(_pngBase64(200, 100)));
    expect(size, isNotNull);
    expect(size!.width, 150);
    expect(size.height, 75);
    expect(EditorImages.measure(utf8.encode('bu bir görsel değil')), isNull);
  });

  test('inserting puts the picture on a line of its own', () {
    final controller = QuillController.basic();
    controller.document.insert(0, 'Dilekçe metni');
    controller.updateSelection(
      const TextSelection.collapsed(offset: 6),
      ChangeSource.local,
    );
    EditorImages.insert(
      controller,
      base64Data: _pngBase64(40, 20),
      mime: 'image/png',
      size: (width: 30, height: 15),
    );

    final model = DocDeltaMap.deltadanModel(controller.document.toDelta());
    final image = model.blocks.firstWhere((b) => b.type == DocBlockType.image);
    expect(image.imageWidth, 30);
    expect(image.imageHeight, 15);
    expect(
      model.blocks.where((b) => b.plainText.isNotEmpty).map((b) => b.plainText),
      ['Dilekç', 'e metni'],
      reason: 'imleçteki satır bölünmeli, metin kaybolmamalı',
    );
  });

  testWidgets('the editor draws the picture it was handed', (tester) async {
    // The mapper and the editor agree on a type name, but only Quill itself
    // can say whether the builder is reached; a wrong signature would show a
    // grey box at runtime and nowhere else.
    final controller = QuillController.basic();
    controller.document.insert(0, 'Ekli fotoğraf:');
    EditorImages.insert(
      controller,
      base64Data: _pngBase64(40, 20),
      mime: 'image/png',
      size: (width: 30, height: 15),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuillEditor.basic(
            controller: controller,
            config: QuillEditorConfig(embedBuilders: [EditorImageEmbed()]),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
  });

  test('inserting at the start of an empty document needs no blank line', () {
    final controller = QuillController.basic();
    EditorImages.insert(
      controller,
      base64Data: _pngBase64(40, 20),
      mime: 'image/png',
      size: (width: 30, height: 15),
    );
    final model = DocDeltaMap.deltadanModel(controller.document.toDelta());
    expect(model.blocks.first.type, DocBlockType.image);
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/docx/docx_bridge.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';

/// What saving and reopening a document does to the way it looks.
///
/// Each of these was found by comparing every paragraph and every character
/// of an archive against itself after a round trip, and each was losing
/// formatting on most of the documents it applied to.
void main() {
  group('UDF', () {
    test('a paragraph keeps the style it resolves to', () {
      // UYAP writes its body paragraphs against names of its own and carries
      // their font, size and spacing in the style rather than on the text.
      // Only headings used to keep the reference, so everything else came
      // back pointing at nothing: 4475 paragraphs across 91 of 517 documents.
      final model = DocModel(
        styles: const [
          DocStyleDef(name: 'hvl-default', family: 'Times New Roman', size: 12),
          DocStyleDef(name: 'edf_1456817714676', family: 'Arial', size: 10),
        ],
        blocks: [DocBlock(plainText: 'Gövde', styleName: 'edf_1456817714676')],
      );
      final back = UdfReader.readBytes(UdfWriter.writeBytes(model))!;
      expect(back.blocks.first.styleName, 'edf_1456817714676');
    });

    test('a style nothing declares is not referenced', () {
      // Pointing at a style that is not in the file is worse than pointing at
      // nothing: the reader on the other side has nothing to resolve.
      final model = DocModel(
        styles: const [
          DocStyleDef(name: 'hvl-default', family: 'Times New Roman', size: 12),
        ],
        blocks: [DocBlock(plainText: 'Gövde', styleName: 'yok-böyle-bir-stil')],
      );
      final back = UdfReader.readBytes(UdfWriter.writeBytes(model))!;
      expect(back.blocks.first.styleName, isNot('yok-böyle-bir-stil'));
    });

    test('list level and number style survive without the list flag', () {
      // UYAP leaves both on a paragraph whose numbering is currently off.
      // Writing them only while the paragraph was a list item dropped them.
      final model = DocModel(
        blocks: [
          DocBlock(
            plainText: 'Madde',
            listLevel: 1,
            numberType: 'NUMBER_TYPE_NUMBER_DOT',
          ),
        ],
      );
      final back = UdfReader.readBytes(UdfWriter.writeBytes(model))!;
      expect(back.blocks.first.listLevel, 1);
      expect(back.blocks.first.numberType, 'NUMBER_TYPE_NUMBER_DOT');
    });
  });

  group('DOCX', () {
    testWidgets('a justified paragraph is still justified', (tester) async {
      // OOXML spells it `both`. The writer emitted `justify`, which Word
      // tolerates but the reader here does not, so a filing — justified
      // nearly everywhere — came back left aligned: 3641 paragraphs across
      // 131 of 164 documents.
      final model = DocModel(
        blocks: [
          DocBlock(
            plainText: 'İki yana yaslı',
            alignment: DocAlignment.justify,
          ),
          DocBlock(plainText: 'Ortalı', alignment: DocAlignment.center),
          DocBlock(plainText: 'Sağa', alignment: DocAlignment.right),
        ],
      );
      final bytes = await tester.runAsync(() => DocxBridge.writeBytes(model));
      final back = await tester.runAsync<DocModel?>(
        () => DocxBridge.readBytes(bytes!),
      );
      expect(back!.blocks.map((b) => b.alignment), [
        DocAlignment.justify,
        DocAlignment.center,
        DocAlignment.right,
      ]);
    });

    testWidgets('a paragraph that set no line spacing does not gain any', (
      tester,
    ) async {
      // The generated style sheet carried a line and a sixth, which is what a
      // new Word document uses. A single spaced filing came back at 1.15 and
      // visibly opened up.
      final model = DocModel(blocks: [DocBlock(plainText: 'Aralık verilmedi')]);
      final bytes = await tester.runAsync(() => DocxBridge.writeBytes(model));
      final back = await tester.runAsync<DocModel?>(
        () => DocxBridge.readBytes(bytes!),
      );
      expect(back!.blocks.first.lineSpacing, isNull);
    });

    testWidgets('a paragraph that set its own line spacing keeps it', (
      tester,
    ) async {
      // Only the injected default is dropped; a real value is written on the
      // paragraph and has to survive.
      final model = DocModel(
        blocks: [DocBlock(plainText: 'Bir buçuk', lineSpacing: 1.5)],
      );
      final bytes = await tester.runAsync(() => DocxBridge.writeBytes(model));
      final back = await tester.runAsync<DocModel?>(
        () => DocxBridge.readBytes(bytes!),
      );
      expect(back!.blocks.first.lineSpacing, closeTo(1.5, 0.01));
    });
  });
}

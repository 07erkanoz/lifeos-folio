import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/editor/doc_delta_map.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';

void main() {
  test('a heading survives the trip to the editor and back', () {
    final model = DocModel(
      blocks: [
        DocBlock(plainText: 'İTİRAZ DİLEKÇESİ', styleName: 'Başlık 1'),
        DocBlock(plainText: 'Gövde metni'),
      ],
    );
    final mapped = DocDeltaMap.modeldenDelta(model);
    final back = DocDeltaMap.deltadanModel(mapped.delta);
    expect(back.blocks.first.styleName, 'Başlık 1');
    expect(
      back.blocks[1].styleName,
      isNull,
      reason: 'düz paragraf başlığa dönüşmemeli',
    );
  });

  test('the editor carries headings as Quill header attributes', () {
    final model = DocModel(
      blocks: [DocBlock(plainText: 'Başlık', styleName: 'Başlık 2')],
    );
    final delta = DocDeltaMap.modeldenDelta(model).delta;
    final newline = delta.toList().last;
    expect(
      (newline.attributes ?? {})['header'],
      2,
      reason: 'Quill kendi header özniteliğiyle çizsin',
    );
  });

  test('headings written elsewhere are recognised by name', () {
    // A document from Word or UYAP names them differently; the level is what
    // identifies them.
    expect(DocDeltaMap.headingLevelOf('Heading 1'), 1);
    expect(DocDeltaMap.headingLevelOf('başlık 3'), 3);
    expect(DocDeltaMap.headingLevelOf('Normal'), isNull);
    expect(DocDeltaMap.headingLevelOf(null), isNull);
  });

  test(
    'a saved UDF declares its heading style and points the paragraph at it',
    () {
      final model = DocModel(
        blocks: [
          DocBlock(
            plainText: 'MANAVGAT 1. AİLE MAHKEMESİ',
            styleName: 'Başlık 1',
          ),
          DocBlock(plainText: 'Gövde'),
        ],
      );
      final bytes = UdfWriter.writeBytes(model);
      final read = UdfReader.readBytes(bytes)!;
      // UDF resolves named styles, so the heading must come back as one rather
      // than as text that merely looks large.
      expect(read.blocks.first.styleName, 'Başlık 1');
      expect(DocDeltaMap.headingLevelOf(read.blocks.first.styleName), 1);
      expect(read.blocks.first.plainText, 'MANAVGAT 1. AİLE MAHKEMESİ');
      expect(read.blocks[1].styleName, isNot('Başlık 1'));
    },
  );

  test('a document without headings gains no style declarations', () {
    final plain = DocModel(blocks: [DocBlock(plainText: 'Yalnız metin')]);
    final read = UdfReader.readBytes(UdfWriter.writeBytes(plain))!;
    expect(
      read.styles.any((s) => DocDeltaMap.headingLevelOf(s.name) != null),
      isFalse,
      reason: 'kullanılmayan stil dosyaya yazılmamalı',
    );
  });

  test('an empty delta still produces a usable document', () {
    final back = DocDeltaMap.deltadanModel(Delta()..insert('\n'));
    expect(back.blocks, isNotEmpty);
    expect(back.blocks.first.styleName, isNull);
  });
}

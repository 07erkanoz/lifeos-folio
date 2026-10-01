import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/editor/document_search.dart';
import 'package:evrak_convert/services/editor/doc_delta_map.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/services/docx/docx_bridge.dart';

void main() {
  test(
    'Turkish literal whole-word search reaches the end of a long document',
    () {
      final document = Document.fromDelta(
        Delta()
          ..insert('${'evrak ' * 100000}İZMİR İzmirli IĞDIR ığdır [a+b]\n'),
      );
      final found = DocumentSearch.find(document, 'izmir', wholeWord: true);
      expect(found.length, 1);
      expect(found.single.start, 600000);
      expect(DocumentSearch.find(document, 'ığdır').length, 2);
      expect(DocumentSearch.find(document, 'izmir', matchCase: true), isEmpty);
      expect(DocumentSearch.find(document, '[a+b]').length, 1);
      expect(DocumentSearch.find(document, '\n'), isEmpty);
      document.close();
    },
  );
  test('replace all retains run formatting and supports undo; protected objects stay intact', () {
    final original = Delta()
      ..insert('Merhaba', {'bold': true, 'font': 'Arial'})
      ..insert(' dünya ')
      ..insert('Merhaba', {'italic': true})
      ..insert('\n')
      ..insert('Merhaba tablo')
      ..insert('\n', {'korunan-blok': 0});
    final controller = QuillController(
      document: Document.fromDelta(original),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final found = DocumentSearch.find(controller.document, 'Merhaba');
    expect(found.length, 2);
    DocumentSearch.replace(controller, found, 'Selam');
    expect(
      controller.document.toPlainText(),
      'Selam dünya Selam\nMerhaba tablo\n',
    );
    final delta = controller.document.toDelta();
    expect(delta.first.attributes?['bold'], true);
    expect(delta.slice(12, 13).first.attributes?['italic'], true);
    controller.undo();
    expect(controller.document.toDelta(), original);
    controller.dispose();
  });
  test('new toolbar line spacing, point size and character formats survive UDF/DOCX', () async {
    final delta = Delta()
      ..insert('Profesyonel belge', {
        'size': '16',
        'font': 'Times New Roman',
        'bold': true,
        'script': 'super',
        'color': '#123456',
      })
      ..insert('\n', {'line-height': 1.5, 'indent': 2, 'align': 'justify'});
    final model = DocDeltaMap.deltadanModel(delta);
    expect(model.blocks.single.spans.single.fontSize, 12);
    expect(model.blocks.single.lineSpacing, 1.5);
    expect(model.blocks.single.leftIndent, 72);
    final udf = UdfReader.readBytes(UdfWriter.writeBytes(model))!;
    expect(udf.blocks.single.lineSpacing, 1.5);
    expect(udf.blocks.single.leftIndent, 72);
    expect(
      DocDeltaMap.deltadanModel(DocDeltaMap.modeldenDelta(udf).delta)
          .blocks
          .single
          .leftIndent,
      72,
    );
    expect(udf.blocks.single.spans.single.superscript, true);
    final docx = await DocxBridge.readBytes(await DocxBridge.writeBytes(model));
    expect(docx!.blocks.single.lineSpacing, 1.5);
    expect(docx.blocks.single.spans.single.fontSize, 12);
    expect(
      DocDeltaMap.modeldenDelta(udf).delta.last.attributes?['line-height'],
      1.5,
    );
  });
}

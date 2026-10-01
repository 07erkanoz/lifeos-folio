import 'dart:convert';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/editor/doc_delta_map.dart';
import 'package:evrak_convert/services/editor/doc_model_json.dart';
import 'package:evrak_convert/services/html/html_writer.dart';
import 'package:evrak_convert/ui/widgets/editor_clipboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('lifeos_evrak/rich_clipboard');

/// What the system clipboard holds, as the runner would hand it over.
Map<String, Object>? _clipboard;

/// What the last copy put there.
Map<String, Object?>? _written;

/// Folio's own HTML for [model], as a copy in Folio would write it.
Map<String, Object> _folio(DocModel model) {
  final folio = base64Encode(
    utf8.encode(jsonEncode(DocModelJson.encode(model))),
  );
  return {
    'format': 'html',
    'data': Uint8List.fromList(
      utf8.encode(HtmlWriter.document(model, folio: folio)),
    ),
  };
}

Map<String, Object> _html(String source) => {
  'format': 'html',
  'data': Uint8List.fromList(utf8.encode(source)),
};

ClipboardController _controller(
  Delta delta, {
  int offset = 0,
  int? extent,
  PasteTarget target = PasteTarget.body,
}) {
  final controller = ClipboardController(target: target);
  controller.document = Document.fromDelta(delta);
  controller.updateSelection(
    TextSelection(baseOffset: offset, extentOffset: extent ?? offset),
    ChangeSource.local,
  );
  return controller;
}

Future<void> _paste(WidgetTester tester, QuillController controller) =>
    // ignore: experimental_member_use
    tester.runAsync(() => controller.clipboardPaste());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _clipboard = null;
    _written = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'getRichData') return _clipboard;
          if (call.method == 'setRichData') {
            _written = Map<String, Object?>.from(call.arguments as Map);
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') return {'text': ''};
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('words copied from inside a paragraph go into one inline', (
    tester,
  ) async {
    final controller = _controller(Delta()..insert('Önce sonra\n'), offset: 5);
    addTearDown(controller.dispose);
    _clipboard = _folio(
      DocModel(
        blocks: [
          DocBlock(
            plainText: 'yeni ',
            alignment: DocAlignment.center,
            spans: const [DocSpan(startOffset: 0, length: 5, bold: true)],
          ),
        ],
        metadata: {'openEnd': true},
      ),
    );
    await _paste(tester, controller);
    expect(controller.document.toPlainText(), 'Önce yeni sonra\n');
    // The paragraph it landed in keeps its own layout.
    expect(
      controller.document.root.children.single.style.attributes['align'],
      isNull,
    );
    final bold = controller.document.toDelta().toList().firstWhere(
      (op) => op.attributes?['bold'] == true,
    );
    expect(bold.data, 'yeni ');
    // The caret is after what came in, not where Quill counts operations.
    expect(controller.selection.baseOffset, 10);
  });

  testWidgets('whole paragraphs arrive with their own layout', (tester) async {
    final controller = _controller(Delta()..insert('\n'));
    addTearDown(controller.dispose);
    _clipboard = _folio(
      DocModel(
        blocks: [
          DocBlock(plainText: 'Bir', alignment: DocAlignment.center),
          DocBlock(plainText: 'İki\tdeğer', hanging: 113, tabSet: '113.0:0:0'),
        ],
        metadata: {'openEnd': false, 'formatId': '1.8'},
      ),
    );
    await _paste(tester, controller);
    final lines = controller.document.root.children.toList();
    expect(controller.document.toPlainText(), 'Bir\nİki\tdeğer\n\n');
    expect(lines[0].style.attributes['align']?.value, 'center');
    final layout = lines[1].style.attributes['doc-layout']!.value as Map;
    expect(layout['hanging'], 113);
    expect(layout['tabs'], '113.0:0:0');
  });

  testWidgets('a paragraph from a web page keeps its layout on an empty line', (
    tester,
  ) async {
    final empty = _controller(
      Delta()..insert('Önceki\n\nSonraki\n'),
      offset: 7,
    );
    addTearDown(empty.dispose);
    _clipboard = _html('<p style="text-align:center">Başlık</p>');
    await _paste(tester, empty);
    expect(empty.document.toPlainText(), 'Önceki\nBaşlık\nSonraki\n');
    expect(
      empty.document.root.children
          .elementAt(1)
          .style
          .attributes['align']
          ?.value,
      'center',
    );

    // Pasted into a sentence it joins the sentence, which keeps its own.
    final sentence = _controller(Delta()..insert('abc\n'), offset: 1);
    addTearDown(sentence.dispose);
    await _paste(tester, sentence);
    expect(sentence.document.toPlainText(), 'aBaşlıkbc\n');
    expect(
      sentence.document.root.children.single.style.attributes['align'],
      isNull,
    );
  });

  testWidgets('a table goes into the list the document keeps beside it', (
    tester,
  ) async {
    final controller = _controller(Delta()..insert('\n'));
    addTearDown(controller.dispose);
    final kept = <DocBlock>[DocBlock(plainText: 'önceki tablo')];
    controller.keepTables = (tables) {
      final base = kept.length;
      kept.addAll(tables);
      return base;
    };
    _clipboard = _html(
      '<table><tr><td>Ad</td><td>Değer</td></tr></table><p>Son</p>',
    );
    await _paste(tester, controller);
    final embed = controller.document.toDelta().toList().firstWhere(
      (op) => op.data is Map,
    );
    // Pointing past the tables already there.
    expect((embed.data as Map)[DocDeltaMap.kTableEmbed], 1);
    expect(
      kept.last.table!.rows.single.cells.last.blocks.single.plainText,
      'Değer',
    );
  });

  testWidgets('a table pasted into a cell is set as text', (tester) async {
    final controller = _controller(
      Delta()..insert('\n'),
      target: PasteTarget.cell,
    );
    addTearDown(controller.dispose);
    _clipboard = _html(
      '<table><tr><td><b>Ad</b></td><td>Değer</td></tr></table>',
    );
    await _paste(tester, controller);
    expect(controller.document.toPlainText(), 'Ad\tDeğer\n');
    expect(
      controller.document.toDelta().toList().any((op) => op.data is Map),
      isFalse,
    );
  });

  testWidgets('one undo takes the whole paste back', (tester) async {
    final controller = _controller(Delta()..insert('Metin\n'), offset: 5);
    addTearDown(controller.dispose);
    _clipboard = _folio(
      DocModel(
        blocks: [
          DocBlock(plainText: 'bir'),
          DocBlock(plainText: 'iki', alignment: DocAlignment.right),
        ],
        metadata: {'openEnd': false},
      ),
    );
    await _paste(tester, controller);
    expect(controller.document.toPlainText(), 'Metinbir\niki\n\n');
    controller.undo();
    expect(controller.document.toPlainText(), 'Metin\n');
  });

  testWidgets('a copy offers HTML, RTF and text, a table as tabbed rows', (
    tester,
  ) async {
    final controller = _controller(
      Delta()
        ..insert('Başlık', {'bold': true})
        ..insert('\n', {'align': 'center'})
        ..insert({DocDeltaMap.kTableEmbed: 0})
        ..insert('\n')
        ..insert('Son\n'),
      extent: 13,
    );
    addTearDown(controller.dispose);
    controller.tables = () => [
      DocBlock(
        type: DocBlockType.table,
        plainText: '',
        table: DocTable(
          rows: [
            DocTableRow(
              cells: [
                DocTableCell(blocks: [DocBlock(plainText: 'Ad')]),
                DocTableCell(blocks: [DocBlock(plainText: 'Değer')]),
              ],
            ),
          ],
        ),
      ),
    ];
    await tester.runAsync(() async {
      // ignore: experimental_member_use
      expect(controller.clipboardSelection(true), isTrue);
      for (var i = 0; i < 300 && _written == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    final written = _written!;
    // Word's table as text: cells separated by tabs, no object characters.
    expect(written['text'], 'Başlık\nAd\tDeğer\nSon');
    final html = utf8.decode(written['html'] as Uint8List);
    expect(html, contains('name="${HtmlWriter.folioMeta}"'));
    expect(html, contains('<table'));
    expect(html, contains('font-weight:bold'));
    final rtf = latin1.decode(written['rtf'] as Uint8List);
    expect(rtf, startsWith(r'{\rtf1'));
    expect(rtf, contains(r'\qc'));
  });

  testWidgets('what Folio copies, Folio pastes exactly', (tester) async {
    final layout = {
      'left': 10.0,
      'first': 0.0,
      'hanging': 113.0,
      'tabs': '113.0:0:0',
      'before': 6.0,
    };
    final source = _controller(
      Delta()
        ..insert('KONU', {'bold': true, 'font': 'Arial', 'size': '16.0'})
        ..insert('\t: Değer', {'color': '#c00000'})
        ..insert('\n', {'align': 'justify', 'doc-layout': layout})
        ..insert('Sonraki satır\n'),
      extent: 13,
    );
    addTearDown(source.dispose);
    source.documentMetadata = () => {'formatId': '1.8'};
    await tester.runAsync(() async {
      // ignore: experimental_member_use
      source.clipboardSelection(true);
      for (var i = 0; i < 300 && _written == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    _clipboard = {'format': 'html', 'data': _written!['html']!};

    final target = _controller(Delta()..insert('\n'));
    addTearDown(target.dispose);
    await _paste(tester, target);
    final ops = target.document.toDelta().toList();
    expect(target.document.toPlainText(), 'KONU\t: Değer\n\n');
    expect(ops[0].attributes?['bold'], isTrue);
    expect(ops[0].attributes?['font'], 'Arial');
    expect(
      double.parse(ops[0].attributes!['size'] as String),
      closeTo(16, .01),
    );
    expect(ops[1].attributes?['color'], '#c00000');
    // A justified line sits inside a block; the line itself has its layout.
    final line = (target.document.queryChild(0).node! as Line).style.attributes;
    expect(line['align']?.value, 'justify');
    final pasted = line['doc-layout']!.value as Map;
    for (final entry in layout.entries) {
      expect(pasted[entry.key], entry.value, reason: entry.key);
    }
  });
}

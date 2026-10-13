import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/docx/docx_bridge.dart';
import 'package:evrak_convert/services/editor/tab_stops.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/document_ruler.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'editor_shortcuts_test.dart' show waitFor;

void main() {
  test('the triangles as the model holds them: a first row further in is '
      'a first line indent, one further out a hanging indent', () {
    expect(const RulerParagraph(firstRow: 50, otherRows: 20).indents, (
      left: 20.0,
      first: 30.0,
      hanging: 0.0,
    ));
    expect(const RulerParagraph(firstRow: 10, otherRows: 40).indents, (
      left: 10.0,
      first: 0.0,
      hanging: 30.0,
    ));
    expect(
      const RulerParagraph(
        stops: [TabStop(56.7), TabStop(113.4, TabAlign.centre)],
      ).tabSet,
      '56.7:0,113.4:2',
    );
  });

  Future<List<RulerParagraph>> pump(
    WidgetTester tester,
    RulerParagraph paragraph,
  ) async {
    final told = <RulerParagraph>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 20),
              child: DocumentRuler(
                axis: Axis.horizontal,
                // A page of 600 points drawn 600 pixels wide.
                pagePoints: 600,
                pixels: 600,
                leading: 60,
                trailing: 60,
                onChanged: (_, _) {},
                paragraph: paragraph,
                onParagraph: told.add,
              ),
            ),
          ),
        ),
      ),
    );
    return told;
  }

  testWidgets('a click puts a stop of the kind chosen, snapped to a quarter '
      'centimetre; a double click takes it off', (tester) async {
    final told = await pump(tester, const RulerParagraph());
    await tester.tap(find.byKey(const ValueKey('ruler-tab-kind')));
    await tester.pump();
    // 60 points of margin, then 100 more: 3.53 cm, which snaps to 3.5 cm.
    final ruler = tester.getTopLeft(find.byKey(const ValueKey('ruler-track')));
    await tester.tapAt(ruler + const Offset(160, 18));
    await tester.pump();
    final stop = told.single.stops.single;
    expect(stop.align, TabAlign.centre);
    expect(stop.position, closeTo(3.5 * DocumentRuler.pointsPerCm, .01));

    final again = await pump(tester, told.single);
    final mark = find.byKey(const ValueKey('ruler-tab-0'));
    await tester.tap(mark);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(mark);
    await tester.pumpAndSettle();
    expect(again.single.stops, isEmpty);
  });

  testWidgets('the first row\'s triangle dragged sets a first line indent, '
      'told once when let go, a guide down the page meanwhile', (tester) async {
    final told = await pump(tester, const RulerParagraph());
    final first = find.byKey(const ValueKey('ruler-first'));
    final gesture = await tester.startGesture(tester.getCenter(first));
    // Past the drag's slop first, then 1.25 cm (35.4 points here).
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(35.4, 0));
    await tester.pump();
    expect(find.byKey(const ValueKey('ruler-guide')), findsOneWidget);
    expect(told, isEmpty);
    await gesture.up();
    await tester.pump();
    expect(find.byKey(const ValueKey('ruler-guide')), findsNothing);
    expect(
      told.single.indents.first,
      closeTo(1.25 * DocumentRuler.pointsPerCm, 1.5),
    );
    expect(told.single.indents.left, 0);
  });

  test('a paragraph\'s stops and indents are kept in the UDF, and written '
      'into the DOCX where Word reads them', () async {
    final model = DocModel(
      blocks: [
        DocBlock(
          plainText: 'DAVACI\t: Ayşe Karaca',
          leftIndent: 10,
          firstLineIndent: 20,
          tabSet: '56.7:0,113.4:2',
        ),
      ],
    );
    final back = UdfReader.readBytes(UdfWriter.writeBytes(model))!;
    final block = back.blocks.first;
    expect(block.tabSet, '56.7:0,113.4:2');
    expect(block.leftIndent, 10);
    expect(block.firstLineIndent, 20);

    final docx = await DocxBridge.writeBytes(model);
    final xml = utf8.decode(
      ZipDecoder()
              .decodeBytes(docx)
              .files
              .firstWhere((f) => f.name == 'word/document.xml')
              .content
          as List<int>,
    );
    // Counted from the left indent, as UYAP counts them: 10 + 56.7 points.
    expect(xml, contains('<w:tab w:val="left" w:pos="1334"/>'));
    expect(xml, contains('<w:tab w:val="center" w:pos="2468"/>'));
    expect(xml, isNot(contains('folio-tabs')));
    final props = RegExp(r'<w:pPr>(.*?)</w:pPr>').firstMatch(xml)![1]!;
    expect(props.indexOf('<w:tabs>'), lessThan(props.indexOf('<w:ind')));
  });

  testWidgets('in the editor a stop put on the ruler goes on every '
      'paragraph chosen, and one undo takes it off them all', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-ruler-tabs-'),
    ))!;
    final file = File('${dir.path}/belge.udf');
    await tester.runAsync(
      () => file.writeAsBytes(
        UdfWriter.writeBytes(
          DocModel(
            blocks: [
              DocBlock(plainText: 'DAVACI\t: Ayşe'),
              DocBlock(plainText: 'DAVALI\t: Yılmaz'),
              DocBlock(plainText: 'Açıklama'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: EditorWidget(
            initialFilePath: file.path,
            initialFormat: EvrakFormat.udf,
          ),
        ),
      ),
    );
    await waitFor(
      tester,
      () => find.byKey(const ValueKey('editor-paper')).evaluate().isNotEmpty,
    );
    final controller = tester
        .widget<QuillEditor>(find.byType(QuillEditor).first)
        .controller;
    controller.updateSelection(
      const TextSelection(baseOffset: 2, extentOffset: 18),
      ChangeSource.local,
    );
    await tester.pump();
    final track = find.byKey(const ValueKey('ruler-track'));
    expect(track, findsOneWidget);
    final ruler = tester.getRect(track);
    // Well inside the text's width, past the left margin.
    await tester.tapAt(Offset(ruler.left + ruler.width * .4, ruler.center.dy));
    await tester.pump();
    List<String?> tabs() => [
      for (final line in controller.document.root.children.whereType<Line>())
        (line.style.attributes['doc-layout']?.value as Map?)?['tabs']
            as String?,
    ];
    final set = tabs();
    expect(set[0], isNotNull);
    expect(set[1], set[0]);
    // The third paragraph was not chosen.
    expect(set[2], isNull);
    controller.undo();
    await tester.pump();
    expect(tabs().whereType<String>(), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 4));
    await tester.runAsync(() => dir.delete(recursive: true));
    // A computer's editor: a phone's has no rulers.
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}

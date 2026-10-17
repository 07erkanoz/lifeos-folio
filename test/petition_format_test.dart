import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/petition_format.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/editor_ribbon.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';

import 'editor_shortcuts_test.dart' show waitFor;

const _petition = [
  "ANTALYA 3. ASLİYE HUKUK MAHKEMESİ'NE",
  '',
  'DAVACI      : Ayşe Karaca',
  'VEKİLİ : Av. Deniz Kaya',
  'DOSYA NO:2025/412 Esas',
  'KONU    : Bilirkişi raporuna itirazlarımızın sunulmasından ibarettir.',
  '',
  'AÇIKLAMALAR',
  'Bilirkişi raporunda davalının kusur oranı hatalı belirlenmiştir ve '
      'rapor dosyadaki delillerle çelişmektedir.',
  '1- Rapor tarafımıza süresi içinde tebliğ edilmemiştir.',
  '2) Kusur oranı hatalıdır.',
  'SONUÇ VE İSTEM : Yukarıda açıklanan nedenlerle itirazlarımızın kabulüne.',
  'SONUÇ VE İSTEM',
  'kısa satır',
  'Davacı Vekili',
  'Av. Deniz Kaya',
];

void main() {
  // Six points a character: enough to set the labels' column.
  double measure(String text) => text.length * 6.0;
  final plan = PetitionFormat.plan(_petition, measure: measure);
  PetitionLine kind(int i) => plan[i].kind;

  test('each line is known for what it is', () {
    expect(kind(0), PetitionLine.court);
    expect(kind(1), PetitionLine.other);
    expect(kind(2), PetitionLine.label);
    expect(kind(3), PetitionLine.label);
    expect(kind(4), PetitionLine.label);
    expect(kind(5), PetitionLine.label);
    expect(kind(7), PetitionLine.heading);
    expect(kind(8), PetitionLine.body);
    expect(kind(9), PetitionLine.numbered);
    expect(kind(10), PetitionLine.numbered);
    expect(kind(12), PetitionLine.heading);
    expect(kind(13), PetitionLine.other);
    expect(kind(14), PetitionLine.signature);
    expect(kind(15), PetitionLine.signature);
  });

  test('the court is centred and bold; the body justified with its first '
      'row set in 1.25 cm', () {
    expect(plan[0].align, 'center');
    expect(plan[0].bold, isTrue);
    expect(plan[8].align, 'justify');
    expect(plan[8].first, closeTo(35.43, .01));
    expect(plan[14].align, 'right');
  });

  test('the labels are written with a tab, their colons in one column by '
      'the widest label, a second row of the value under the first', () {
    expect(plan[2].text, 'DAVACI\t: Ayşe Karaca');
    expect(plan[4].text, 'DOSYA NO\t: 2025/412 Esas');
    // "SONUÇ VE İSTEM" as a label is the widest: 14 letters, 84 points.
    final stop = (14 * 6.0 + PetitionFormat.labelGap).ceilToDouble();
    for (final i in [2, 3, 4, 5, 11]) {
      expect(plan[i].tabs, '${stop.toStringAsFixed(1)}:0');
      expect(plan[i].hanging, stop + 12);
    }
  });

  test('a numbered item\'s rows after the first start under its text', () {
    expect(plan[9].hanging, measure('1- '));
    expect(plan[10].hanging, measure('2) '));
  });

  testWidgets('Biçimlendir sets the petition in the editor, and one undo '
      'takes it all back', (tester) async {
    tester.view.physicalSize = const Size(1700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => editorRibbonTab.value = RibbonTab.home);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-format-'),
    ))!;
    final file = File('${dir.path}/dilekce.udf');
    await tester.runAsync(
      () => file.writeAsBytes(
        UdfWriter.writeBytes(
          DocModel(blocks: [for (final t in _petition) DocBlock(plainText: t)]),
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
    final before = controller.document.toPlainText();
    editorRibbonTab.value = RibbonTab.legal;
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('legal-format')));
    await tester.pump();
    // The lines, those an alignment groups into a block too, each with its
    // block's attributes.
    List<(Line, Map<String, Object?>)> lines() => [
      for (final node in controller.document.root.children)
        if (node is Line)
          (node, {for (final a in node.style.attributes.values) a.key: a.value})
        else if (node is Block)
          for (final line in node.children.whereType<Line>())
            (
              line,
              {
                for (final a in node.style.attributes.values) a.key: a.value,
                for (final a in line.style.attributes.values) a.key: a.value,
              },
            ),
    ];
    final now = lines();
    expect(now[0].$2['align'], 'center');
    expect(now[2].$1.toPlainText(), 'DAVACI\t: Ayşe Karaca\n');
    expect((now[2].$2['doc-layout'] as Map)['tabs'], isNotNull);
    expect(now[8].$2['align'], 'justify');
    expect(now[15].$2['align'], 'right');
    expect(find.text('Biçimlendirildi'), findsOneWidget);
    controller.undo();
    await tester.pump();
    expect(controller.document.toPlainText(), before);
    expect(lines()[0].$2['align'], isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 4));
    await tester.runAsync(() => dir.delete(recursive: true));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Biçimlendir keeps a bold label bold and its value plain, and '
      'leaves a list item where it was', (tester) async {
    tester.view.physicalSize = const Size(1700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => editorRibbonTab.value = RibbonTab.home);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-format-styles-'),
    ))!;
    final file = File('${dir.path}/dilekce.udf');
    const item =
        'Rapor tarafımıza süresi içinde tebliğ edilmemiştir ve bu nedenle '
        'itiraz süresi işlemeye başlamamıştır.';
    await tester.runAsync(
      () => file.writeAsBytes(
        UdfWriter.writeBytes(
          DocModel(
            blocks: [
              DocBlock(plainText: "ANTALYA 3. ASLİYE HUKUK MAHKEMESİ'NE"),
              DocBlock(
                plainText: 'DAVACI      : Ayşe Karaca',
                spans: [DocSpan(startOffset: 0, length: 6, bold: true)],
              ),
              DocBlock(plainText: 'VEKİLİ : Av. Deniz Kaya'),
              DocBlock(
                type: DocBlockType.listItem,
                listType: DocListType.ordered,
                listLevel: 1,
                leftIndent: 25,
                plainText: item,
              ),
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
    Line line(int n) {
      final all = <Line>[
        for (final node in controller.document.root.children)
          if (node is Line)
            node
          else if (node is Block)
            ...node.children.whereType<Line>(),
      ];
      return all[n];
    }

    Object? itemLayout() => line(3).style.attributes['doc-layout']?.value;
    final itemBefore = itemLayout();
    editorRibbonTab.value = RibbonTab.legal;
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('legal-format')));
    await tester.pump();

    final label = line(1);
    expect(label.toPlainText(), 'DAVACI\t: Ayşe Karaca\n');
    bool boldAt(String part) {
      final at = label.toPlainText().indexOf(part);
      final leaf = label.queryChild(at, false).node as Leaf;
      return leaf.style.attributes[Attribute.bold.key] != null;
    }

    expect(boldAt('DAVACI'), isTrue);
    expect(boldAt('Ayşe'), isFalse);
    expect(line(3).toPlainText(), '$item\n');
    expect(itemLayout(), itemBefore);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 4));
    await tester.runAsync(() => dir.delete(recursive: true));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}

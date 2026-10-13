import 'package:evrak_convert/services/editor/editor_drafts.dart';
import 'package:evrak_convert/services/legal/case_law.dart';
import 'package:evrak_convert/services/legal/decision_insert.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

const _decision = Decision(
  court: 'Yargıtay 9. Hukuk Dairesi',
  esas: '2023/1234',
  karar: '2024/567',
  date: '12.03.2024',
  text: 'Karar metni.',
);

void main() {
  test('the court takes its genitive as Turkish gives it', () {
    expect(
      DecisionInsert.genitive('Yargıtay 9. Hukuk Dairesi'),
      "Yargıtay 9. Hukuk Dairesi'nin",
    );
    expect(
      DecisionInsert.genitive('Yargıtay Hukuk Genel Kurulu'),
      "Yargıtay Hukuk Genel Kurulu'nun",
    );
    expect(
      DecisionInsert.genitive('Anayasa Mahkemesi'),
      "Anayasa Mahkemesi'nin",
    );
    expect(
      DecisionInsert.genitive('Danıştay 10. Daire'),
      "Danıştay 10. Daire'nin",
    );
    expect(DecisionInsert.genitive('Yargıtay'), "Yargıtay'ın");
    expect(DecisionInsert.genitive('BAM'), "BAM'ın");
  });

  test('with a passage chosen, it is quoted; without, the particulars say '
      'the decision is to the same end', () {
    String text(List<({String text, bool bold, bool italic})> runs) =>
        runs.map((r) => r.text).join();
    expect(
      text(DecisionInsert.runs(_decision)),
      "Yargıtay 9. Hukuk Dairesi'nin 12.03.2024 tarihli, 2023/1234 E. ve "
      '2024/567 K. sayılı kararı da bu yöndedir.',
    );
    final quoted = DecisionInsert.runs(
      _decision,
      quote: 'işçinin\n  kıdem tazminatı',
    );
    expect(
      text(quoted),
      "Yargıtay 9. Hukuk Dairesi'nin 12.03.2024 tarihli, 2023/1234 E. ve "
      '2024/567 K. sayılı kararında; “işçinin kıdem tazminatı” şeklinde '
      'hüküm kurulmuştur.',
    );
    expect(quoted.first.bold, isTrue);
    expect(quoted.firstWhere((r) => r.text.startsWith('“')).italic, isTrue);
    expect(
      text(DecisionInsert.runs(_decision, same: true)),
      startsWith('Aynı yönde, '),
    );
  });

  test('the conclusion heading is found at the start of its line', () {
    const plain = 'AÇIKLAMALAR\nmetin\nSONUÇ VE İSTEM : yukarıda\n';
    expect(DecisionInsert.conclusionAt(plain), plain.indexOf('SONUÇ'));
    expect(DecisionInsert.conclusionAt('sonuç olarak\n'), isNull);
  });

  testWidgets('written before the conclusion as a paragraph of its own, the '
      'next one joined by "Aynı yönde"; undone in one step each', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: EditorWidget(draft: EditorDrafts().draft('new', 'Yeni evrak')),
        ),
      ),
    );
    await tester.pump();
    final controller = tester
        .widget<QuillEditor>(find.byType(QuillEditor).first)
        .controller;
    // As a paste comes: the editor's typing style is not laid over it.
    controller.replaceText(
      0,
      0,
      Delta()..insert('AÇIKLAMALAR\nOlaylar.\nSONUÇ VE İSTEM\nKabulüne.'),
      const TextSelection.collapsed(offset: 5),
    );
    await tester.pump();
    expect(DecisionInsert.target, isNotNull);
    DecisionInsert.target!(_decision, beforeConclusion: true);
    DecisionInsert.target!(_decision, beforeConclusion: true);
    await tester.pump();
    final lines = controller.document.toPlainText().split('\n');
    expect(lines[2], contains('kararı da bu yöndedir.'));
    expect(lines[3], startsWith('Aynı yönde, '));
    expect(lines[4], 'SONUÇ VE İSTEM');
    // The particulars bold.
    final runs = controller.document.toDelta().toList();
    expect(
      runs.any(
        (op) =>
            '${op.data}'.startsWith("Yargıtay 9. Hukuk Dairesi'nin") &&
            op.attributes?['bold'] == true,
      ),
      isTrue,
    );
    controller.undo();
    await tester.pump();
    expect(controller.document.toPlainText(), isNot(contains('Aynı yönde')));
    expect(controller.document.toPlainText(), contains('bu yöndedir'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 4));
    expect(DecisionInsert.target, isNull);
  });
}

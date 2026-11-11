import 'package:evrak_convert/services/ai/ai_assistant.dart';
import 'package:evrak_convert/ui/ai/ai_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// What an answer rests on, under it: Folio reads the articles and decisions
// it cites in its text itself, each once, to be opened in full.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // No AI program is looked for on the machine the test runs on: where
  // none is installed the panel showed no conversation at all, and the
  // test failed on the build server alone.
  setUp(() {
    AiAssistant.statusesForTest = const [
      AiStatus(AiProvider.claude, path: '/bin/claude', signedIn: true),
    ];
  });
  tearDown(() => AiAssistant.statusesForTest = null);

  testWidgets('a kept answer shows its articles and decisions', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiPanel(
              embedded: true,
              chat: const {
                'id': 'sohbet-1',
                'turlar': [
                  {
                    'soru': 'Kıdem tazminatı?',
                    'yazan': 'Claude',
                    'cevap':
                        'İşçi 4857 sayılı İş Kanunu m.17 uyarınca bildirim '
                        'süresine hak kazanır; 4857 sayılı İş Kanunu m.17 '
                        'aynı zamanda... Yargıtay 9. HD, 2016/12345 E., '
                        '2017/6789 K.',
                  },
                ],
              },
            ),
          ),
        ),
      );
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        if (find.text('Dayanakları').evaluate().isNotEmpty) break;
      }
    });
    expect(find.text('Dayanakları'), findsOneWidget);
    final chips = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('ai-source-'),
    );
    // The article once, though cited twice, and the decision.
    expect(chips, findsNWidgets(2));
    // Tapped, the article opens over the page as in the editor.
    await tester.tap(chips.first);
    await tester.pump();
    expect(find.byKey(const ValueKey('article-panel')), findsOneWidget);
  });
}

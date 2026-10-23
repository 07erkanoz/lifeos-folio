import 'package:evrak_convert/ui/help/help_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const all = [
    Help.home,
    Help.portfolio,
    Help.caseDetail,
    Help.uyapNotices,
    Help.uets,
    Help.agenda,
    Help.clients,
    Help.cash,
    Help.office,
    Help.tasks,
    Help.messages,
    Help.sync,
    Help.editor,
    Help.library,
    Help.settings,
    Help.inbox,
  ];

  test('every page\'s help says what it is for and how, in steps', () {
    for (final t in all) {
      expect(t.title, isNotEmpty);
      expect(t.intro.length, greaterThan(40), reason: t.title);
      expect(t.parts, isNotEmpty, reason: t.title);
      for (final part in t.parts) {
        expect(part.heading, isNotEmpty, reason: t.title);
        expect(part.lines, isNotEmpty, reason: '${t.title} › ${part.heading}');
      }
    }
    // What the lawyer most needs told: the office network, tasks, roles,
    // sending, Senkron and the live sharing.
    final office = all.firstWhere((t) => t == Help.office);
    expect(
      office.parts.map((p) => p.heading),
      containsAll([
        'Kim neyi görür?',
        'Büroyu kurmak (yönetici)',
        'Büroya katılmak',
        'Yetki vermek (yönetici)',
        'Dosya göndermek',
      ]),
    );
    expect(
      Help.editor.parts.map((p) => p.heading),
      containsAll(['Canlı paylaşım', 'Canlı paylaşıma katılmak']),
    );
    expect(Help.tasks.parts.first.heading, 'Görev vermek');
    expect(Help.sync.parts.map((p) => p.heading), contains('Ne eşitlenir?'));
  });

  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: HelpButton(Help.office))),
      ),
    );
    await tester.tap(find.byTooltip('Bu sayfa nasıl kullanılır?'));
    await tester.pumpAndSettle();
  }

  testWidgets('on a computer the help is a window over the page', (
    tester,
  ) async {
    await open(tester, const Size(1400, 900));
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Büro ağı'), findsOneWidget);
    expect(find.text('Büroya katılmak'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('İpucu:'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('İpucu:'), findsOneWidget);
    await tester.tap(find.byTooltip('Kapat'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone it is a sheet from below that scrolls', (
    tester,
  ) async {
    await open(tester, const Size(390, 800));
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Büro ağı'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.textContaining('İpucu:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

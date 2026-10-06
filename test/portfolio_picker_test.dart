import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/ui/widgets/portfolio_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const a3 = 'Antalya 3. Asliye Hukuk Mahkemesi';
  const i1 = 'Antalya 1. İcra Dairesi';
  final cases = [
    PortalCase.create(number: '2025/412', court: a3),
    PortalCase.create(number: '2026/10', court: a3),
    PortalCase.create(number: '2026/77', court: i1),
    PortalCase.create(number: '2026/78', court: i1),
  ];

  Future<List<PortalCase>?> Function() open(WidgetTester tester) {
    List<PortalCase>? chosen;
    var done = false;
    return () async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                chosen = await PortfolioPicker.show(context, cases);
                done = true;
              },
              child: const Text('aç'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      return done ? chosen : null;
    };
  }

  testWidgets('a whole unit, and one case of another, are added', (
    tester,
  ) async {
    await open(tester)();
    // A unit's box takes all its cases.
    await tester.tap(find.byKey(const ValueKey('portfolio-unit-check-$a3')));
    await tester.pump();
    expect(find.text('2 / 2 seçili'), findsOne);
    // Another unit opened, one of its cases taken.
    await tester.tap(find.byKey(const ValueKey('portfolio-unit-$i1')));
    await tester.pump();
    await tester.tap(find.text('2026/77'));
    await tester.pump();
    expect(find.text('1 / 2 seçili'), findsOne);
    expect(find.text('3 dosyayı ekle'), findsOne);
  });

  testWidgets('the search narrows to a unit or a number', (tester) async {
    await open(tester)();
    await tester.enterText(
      find.byKey(const ValueKey('portfolio-search')),
      'icra',
    );
    await tester.pump();
    expect(find.text(a3), findsNothing);
    expect(find.text('2026/78'), findsOne);
  });
}

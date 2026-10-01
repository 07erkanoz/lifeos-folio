import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/ui/widgets/page_jump.dart';

void main() {
  testWidgets('the page counter is the way to a page by its number', (
    tester,
  ) async {
    final went = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PageJump(
              label: '3 / 40',
              current: 3,
              count: 40,
              onGo: went.add,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('3 / 40'));
    await tester.pumpAndSettle();
    expect(find.text('Sayfaya git'), findsOneWidget);
    expect(find.text('1 – 40'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '31');
    await tester.tap(find.text('Git'));
    await tester.pumpAndSettle();
    expect(went, [31]);
  });

  testWidgets('a page outside the document is not gone to', (tester) async {
    final went = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PageJump(
              label: '1 / 5',
              current: 1,
              count: 5,
              onGo: went.add,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('1 / 5'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '9');
    await tester.tap(find.text('Git'));
    await tester.pumpAndSettle();
    expect(went, isEmpty);
    expect(find.text('Sayfaya git'), findsOneWidget, reason: 'stays open');

    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(went, isEmpty);
  });

  testWidgets('a single page document offers nothing to jump to', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PageJump(label: '1 / 1', current: 1, count: 1, onGo: (_) {}),
          ),
        ),
      ),
    );
    await tester.tap(find.text('1 / 1'));
    await tester.pumpAndSettle();
    expect(find.text('Sayfaya git'), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/ui/library/collapsing_overview.dart';

void main() {
  testWidgets('scroll gives documents more room and top restores overview', (
    tester,
  ) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CollapsingOverview(
            header: const SizedBox(height: 180, child: Text('Overview')),
            child: Column(
              children: [
                const SizedBox(height: 48, child: Text('Filters')),
                Expanded(
                  child: ListView.builder(
                    controller: controller,
                    itemExtent: 72,
                    itemCount: 40,
                    itemBuilder: (_, i) => Text('Document $i'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final list = find.byType(ListView);
    final initialHeight = tester.getSize(list).height;
    await tester.drag(list, const Offset(0, -250));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    final duringHeight = tester.getSize(list).height;
    expect(duringHeight, greaterThan(initialHeight));
    await tester.pumpAndSettle();
    expect(tester.getSize(list).height, closeTo(initialHeight + 180, 1));
    expect(find.text('Filters').hitTestable(), findsOneWidget);
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.getSize(list).height, closeTo(initialHeight, 1));
    expect(find.text('Overview').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'short list stays collapsed when expanded viewport clamps scroll',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CollapsingOverview(
              header: const SizedBox(height: 180),
              child: ListView.builder(
                itemCount: 7,
                itemExtent: 72,
                itemBuilder: (_, i) => Text('Document $i'),
              ),
            ),
          ),
        ),
      );
      final list = find.byType(ListView);
      final initialHeight = tester.getSize(list).height;
      await tester.drag(list, const Offset(0, -70));
      await tester.pumpAndSettle();
      expect(tester.getSize(list).height, closeTo(initialHeight + 180, 1));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getSize(list).height, closeTo(initialHeight + 180, 1));
      await tester.drag(list, const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(tester.getSize(list).height, closeTo(initialHeight, 1));
      expect(tester.takeException(), isNull);
    },
  );
}

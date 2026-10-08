import 'package:evrak_convert/ui/mobile/scroll_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget page(double content) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          const FoldingChrome(child: SizedBox(height: 300, width: 400)),
          Expanded(
            child: ChromeScrollWatcher(
              child: ListView(children: [SizedBox(height: content)]),
            ),
          ),
        ],
      ),
    ),
  );

  setUp(ScrollChrome.show);

  testWidgets('a list that folded would fit is not folded for', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 800 - 300 = 500 seen of 700: 200 to scroll, less than the 300 folded.
    await tester.pumpWidget(page(700));
    await tester.drag(find.byType(ListView), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(ScrollChrome.hidden.value, isFalse);
  });

  testWidgets('a long list folds the headings, and pulled back shows them', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(page(3000));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(ScrollChrome.hidden.value, isTrue);
    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(ScrollChrome.hidden.value, isFalse);
  });
}

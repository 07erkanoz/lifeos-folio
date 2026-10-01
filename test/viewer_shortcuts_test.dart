import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/ui/widgets/shortcuts_dialog.dart';
import 'package:evrak_convert/ui/widgets/viewer_shortcuts.dart';

void main() {
  testWidgets('a page answers to the keyboard once it is clicked', (
    tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ViewerShortcuts(
            onPrevious: () => log.add('önceki'),
            onNext: () => log.add('sonraki'),
            onFirst: () => log.add('ilk'),
            onLast: () => log.add('son'),
            onZoomIn: () => log.add('yakın'),
            onZoomOut: () => log.add('uzak'),
            onFit: () => log.add('sığdır'),
            onRotate: () => log.add('döndür'),
            onFind: () => log.add('bul'),
            child: const SizedBox.expand(
              child: Placeholder(key: ValueKey('sayfa')),
            ),
          ),
        ),
      ),
    );

    // Nothing before the page is clicked: choosing a document leaves the
    // cursor in the list, and the arrow keys belong to the list until the
    // reader puts them somewhere else.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(log, isEmpty);

    await tester.tap(find.byKey(const ValueKey('sayfa')));
    await tester.pump();

    for (final key in [
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.pageUp,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
      LogicalKeyboardKey.equal,
      LogicalKeyboardKey.minus,
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.keyR,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(log, [
      'sonraki',
      'sonraki',
      'sonraki',
      'önceki',
      'önceki',
      'ilk',
      'son',
      'yakın',
      'uzak',
      'sığdır',
      'döndür',
      'bul',
    ]);
  });

  testWidgets('a viewer only offers the keys it can carry out', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ViewerShortcuts(
            onNext: () => log.add('sonraki'),
            child: const SizedBox.expand(
              child: Placeholder(key: ValueKey('sayfa')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('sayfa')));
    await tester.pump();
    // A picture does not rotate here and does not pretend to.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(log, ['sonraki']);
  });

  testWidgets('the guide names the keys the app answers to', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ShortcutsDialog())),
    );
    await tester.pump();
    for (final expected in [
      'Ctrl+K',
      'Ctrl+Shift+E',
      'Alt+← / Alt+→',
      'F1 / Ctrl+/',
      'Home / End',
      'Ctrl+S · Ctrl+Shift+S',
      'Ctrl+F',
    ]) {
      expect(
        find.text(expected),
        findsOneWidget,
        reason: '$expected kılavuzda yok',
      );
    }
  });
}

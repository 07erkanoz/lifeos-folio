import 'dart:io';

import 'package:evrak_convert/services/security/app_lock.dart';
import 'package:evrak_convert/ui/security/security_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the lock turned on in the settings turns off again', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('folio_lockset_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final lock = AppLock(
      file: () async => File('${dir.path}/kilit.json'),
      iterations: 1000,
    );
    await tester.runAsync(lock.load);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: SecuritySettings(lock: lock)),
        ),
      ),
    );
    Future<void> type(List<String> words) async {
      for (final (i, w) in words.indexed) {
        await tester.enterText(find.byKey(ValueKey('lock-field-$i')), w);
      }
      await tester.testTextInput.receiveAction(TextInputAction.done);
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.tap(find.byKey(const ValueKey('settings-lock-switch')));
    await tester.pumpAndSettle();
    await type(['1234', '1234']);
    // The code, written down.
    if (find.byKey(const ValueKey('lock-written')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('lock-written')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('lock-code-done')));
      await tester.pumpAndSettle();
    }
    expect(lock.enabled, isTrue);
    await tester.tap(find.byKey(const ValueKey('settings-lock-switch')));
    await tester.pumpAndSettle();
    await type(['1234']);
    expect(lock.enabled, isFalse);
  });
}

import 'dart:io';

import 'package:evrak_convert/services/security/app_lock.dart';
import 'package:evrak_convert/ui/security/app_lock_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('folio_lock_'));
  tearDown(() => dir.deleteSync(recursive: true));
  AppLock lock() => AppLock(
    file: () async => File('${dir.path}/kilit.json'),
    iterations: 1000,
  );

  test('a password locks Folio; only its hash is kept', () async {
    final l = lock();
    await l.load();
    expect(l.enabled, isFalse);
    final code = await l.setPassword('büro-şifresi-1');
    expect(code, matches(RegExp(r'^([A-Z2-9]{4}-){5}[A-Z2-9]{4}$')));
    final kept = File('${dir.path}/kilit.json').readAsStringSync();
    expect(kept, isNot(contains('büro-şifresi-1')));
    expect(kept, isNot(contains(code)));
    // Locked at the next start.
    final again = lock();
    await again.load();
    expect(again.locked, isTrue);
    expect(await again.unlock('yanlış-şifre'), isFalse);
    expect(again.locked, isTrue);
    expect(await again.unlock('büro-şifresi-1'), isTrue);
    expect(again.locked, isFalse);
  });

  test('wrong tries are made to wait', () async {
    final l = lock();
    await l.setPassword('büro-şifresi-1');
    for (var i = 0; i < 3; i++) {
      await l.unlock('yanlış');
    }
    expect(l.waitUntil, isNotNull);
    // Even the right one waits now.
    expect(await l.unlock('büro-şifresi-1'), isFalse);
  });

  test('the recovery code sets a new password and is then spent', () async {
    final l = lock();
    final code = await l.setPassword('büro-şifresi-1');
    l.lockNow();
    final next = await l.recover(
      code.toLowerCase().replaceAll('-', ' '),
      'yeni-şifre-22',
    );
    expect(next, isNotNull);
    expect(next, isNot(code));
    expect(await l.checkPassword('yeni-şifre-22'), isTrue);
    expect(await l.recover(code, 'başka-şifre-3'), isNull);
    expect(await l.disable('yeni-şifre-22'), isTrue);
    expect(File('${dir.path}/kilit.json').existsSync(), isFalse);
  });

  testWidgets('the lock covers Folio with the time and the office name', (
    tester,
  ) async {
    final l = lock();
    await tester.runAsync(() async {
      await l.setPassword('büro-şifresi-1');
    });
    l.lockNow();
    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          lock: l,
          office: 'Kaya Hukuk Bürosu',
          child: const Scaffold(body: Text('dilekçe içeriği')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Kaya Hukuk Bürosu'), findsOneWidget);
    expect(find.byKey(const ValueKey('lock-password')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('lock-password')),
      'büro-şifresi-1',
    );
    await tester.runAsync(() async {
      await l.unlock('büro-şifresi-1');
    });
    await tester.pump();
    expect(find.byKey(const ValueKey('lock-password')), findsNothing);
    expect(find.text('dilekçe içeriği'), findsOneWidget);
  });
}

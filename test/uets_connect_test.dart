import 'package:evrak_convert/services/security/secret_store.dart';
import 'package:evrak_convert/services/uets/uets_api.dart';
import 'package:evrak_convert/ui/agenda/uets_connect.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A UETS that never answers: the login fails, after what was typed is
  // kept.
  final api = UetsApi.forTesting(Uri.parse('http://127.0.0.1:9/'));

  Future<void> open(WidgetTester tester, SecretStore secrets) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => connectUets(context, api: api, secrets: secrets),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aç'));
    await settle(tester);
  }

  Future<void> connect(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('uets-connect')));
    await settle(tester);
  }

  testWidgets('the TC number and the phone are kept as soon as a login is '
      'asked for, and filled in next time; unticked, they are dropped', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final secrets = SecretStore();
    await open(tester, secrets);
    final keep = find.byKey(const ValueKey('uets-keep'));
    expect(tester.widget<CheckboxListTile>(keep).value, isTrue);
    await tester.enterText(
      find.byKey(const ValueKey('uets-tckn')),
      '12345678901',
    );
    await tester.enterText(
      find.byKey(const ValueKey('uets-phone')),
      '5321234567',
    );
    await connect(tester);
    final kept = await tester.runAsync(() => secrets.read('uets-login'));
    expect(kept?['tckn'], '12345678901');
    expect(kept?['phone'], '5321234567');

    // Closed, and opened again: the account and the phone are there.
    await tester.tap(find.text('Vazgeç'));
    await settle(tester);
    await open(tester, secrets);
    expect(find.text('Hesap: 123******01'), findsOne);
    expect(find.text('5321234567'), findsOne);

    // Not to be kept: dropped, and the box stays unticked next time.
    await tester.tap(keep);
    await tester.pump();
    await connect(tester);
    final dropped = await tester.runAsync(() => secrets.read('uets-login'));
    expect(dropped?['tckn'], isNull);
    expect(dropped?['phone'], isNull);
    expect(dropped?['keep'], isFalse);
    await tester.tap(find.text('Vazgeç'));
    await settle(tester);
    await open(tester, secrets);
    expect(tester.widget<CheckboxListTile>(keep).value, isFalse);
    expect(find.text('5321234567'), findsNothing);
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

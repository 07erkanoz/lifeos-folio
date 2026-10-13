import 'dart:io';

import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/clients/client_accounts.dart';
import 'package:evrak_convert/services/clients/client_files.dart';
import 'package:evrak_convert/ui/clients/client_accounts_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ClientRecord _record(
  String id,
  ClientRecordKind kind,
  Map<String, Object?> data,
) {
  final at = DateTime(2026, 10, 8, 14, 22);
  return ClientRecord(
    id: id,
    clientId: 'c1',
    kind: kind,
    data: {'dosya': 'k1', 'zaman': at.toIso8601String(), ...data},
    created: at,
    by: 'Av. Deniz Kaya',
    updated: at,
    locked: kind == ClientRecordKind.movement,
  );
}

void main() {
  final client = Client(id: 'c1', name: 'Ayşe Karaca', updated: DateTime(2026));

  testWidgets('a case paid in euro shows its fee in euro and the costs met '
      'in lira on a card of their own; a movement is asked in the card\'s '
      'currency', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    (String, Currency)? asked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientAccountsView(
            client: client,
            records: [
              _record('f1', ClientRecordKind.fee, {
                'tutar': 500000,
                'para': 'EUR',
              }),
              _record('e1', ClientRecordKind.movement, {
                'hesap': MovementKind.feePaid.code,
                'tutar': 200000,
                'para': 'EUR',
              }),
              _record('t1', ClientRecordKind.movement, {
                'hesap': MovementKind.costByLawyer.code,
                'tutar': 350000,
              }),
            ],
            cases: const [(key: 'k1', title: '2026/12 Esas')],
            onMovement: (k, c) => asked = (k, c),
            onFee: (_, _) {},
            onReverse: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2026/12 Esas · Euro'), findsOneWidget);
    expect(find.text('2026/12 Esas · TL'), findsOneWidget);
    expect(find.text('Sabit 5.000 €'), findsOneWidget);
    expect(find.text('Ücret kalan 3.000 €'), findsOneWidget);
    expect(find.text('Avukat masrafı 3.500 TL'), findsOneWidget);
    expect(find.text('+2.000 €'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('movement-k1')).last);
    expect(asked, ('k1', Currency.tl));
  });

  testWidgets('a movement is written in the currency chosen', (tester) async {
    final root = Directory.systemTemp.createTempSync('folio_currency_');
    addTearDown(() => root.deleteSync(recursive: true));
    ClientRecord? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => saved = await showDialog<ClientRecord>(
                context: context,
                builder: (_) => MovementDialog(
                  client: client,
                  caseKey: 'k1',
                  lawyer: 'Av. Deniz Kaya',
                  person: '',
                  files: ClientFiles(root: () async => root),
                  currency: Currency.eur,
                ),
              ),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('movement-amount')),
      '1.250',
    );
    await tester.tap(find.byKey(const ValueKey('currency-USD')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('movement-save')));
    await tester.pumpAndSettle();
    expect(saved!.amount, 125000);
    expect(saved!.currency, Currency.usd);
    expect(saved!.data['para'], 'USD');
  });
}

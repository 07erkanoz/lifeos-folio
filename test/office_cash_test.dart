import 'dart:io';

import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/clients/client_accounts.dart';
import 'package:evrak_convert/services/clients/client_documents.dart'
    show inWords;
import 'package:evrak_convert/services/clients/client_files.dart';
import 'package:evrak_convert/services/clients/office_cash.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/ui/cash/cash_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ClientRecord _move(
  String id,
  MovementKind kind,
  int lira,
  DateTime at, {
  String client = 'c1',
  String reverses = '',
  String currency = '',
}) => ClientRecord(
  id: id,
  clientId: client,
  kind: ClientRecordKind.movement,
  data: {
    'dosya': 'k1',
    'hesap': kind.code,
    'tutar': lira * 100,
    'zaman': at.toIso8601String(),
    'ters': ?(reverses.isEmpty ? null : reverses),
    'para': ?(currency.isEmpty ? null : currency),
  },
  created: at,
  by: 'Av. Deniz Kaya',
  updated: at,
  locked: true,
);

ClientRecord _cash(
  String id,
  int lira,
  DateTime at, {
  bool income = false,
  String category = 'Kira',
  String person = '',
  String currency = '',
}) => ClientRecord(
  id: id,
  clientId: officeCashId,
  kind: ClientRecordKind.cash,
  data: {
    'tur': income ? 'gelir' : 'gider',
    'kategori': category,
    'tutar': lira * 100,
    'zaman': at.toIso8601String(),
    'odeme': 'Banka',
    'para': ?(currency.isEmpty ? null : currency),
  },
  created: at,
  by: 'Av. Deniz Kaya',
  updated: at,
  locked: true,
  person: person,
);

void main() {
  late PortalDatabase db;
  setUp(() {
    db = PortalDatabase.memory();
    db.saveClient(
      Client(id: 'c1', name: 'Ayşe Karaca', updated: DateTime(2026)),
    );
  });
  tearDown(() => db.dispose());

  test('the book reads the clients\' movements as income, trust and costs '
      'met for them, and the office\'s own as income and expense; a '
      'reversal cancels what it takes back', () {
    final oct = DateTime(2026, 10, 8, 14, 22);
    for (final r in [
      _move('m1', MovementKind.feePaid, 15000, oct),
      _move('m2', MovementKind.advanceIn, 5000, oct),
      _move('m3', MovementKind.costFromAdvance, 2500, oct),
      _move('m4', MovementKind.costByLawyer, 1250, oct),
      _move('m5', MovementKind.counterFee, 2000, oct),
      _move('m6', MovementKind.counterFee, 2000, oct, reverses: 'm5'),
      _cash('g1', 18000, oct),
      _cash('g2', 3000, oct, income: true, category: 'Danışmanlık'),
    ]) {
      db.saveClientRecord(r);
    }
    final lines = cashLines(db);
    CashLine of(String id) => lines.singleWhere((l) => l.record.id == id);
    expect(of('m1').side, CashSide.income);
    expect(of('m1').amount, 1500000);
    expect(of('m1').client, 'Ayşe Karaca');
    expect(of('m2').side, CashSide.trust);
    expect(of('m3').amount, -250000);
    expect(of('m4').side, CashSide.onBehalf);
    expect(of('m4').amount, -125000);
    expect(of('m5').struck, isTrue);
    expect(of('m6').amount, -200000);
    expect(of('g1').side, CashSide.expense);
    expect(of('g1').fromClient, isFalse);
    final t = cashTotals(lines);
    // 15.000 fee + 3.000 other income; the counter fee taken back.
    expect(t.income, 1800000);
    expect(t.expense, 1800000);
    expect(t.net, 0);
    final b = clientBalances(db, oct).single;
    expect(b.held[Currency.tl], 250000);
    // The lawyer's cost met for the client, not paid back: apart from the
    // fee owed (none agreed here).
    expect(b.costs[Currency.tl], 125000);
    expect(b.owed.isZero, isTrue);
  });

  test('a monthly expense is written once a month, the same on every '
      'device, until stopped', () {
    final start = DateTime(2026, 7, 31, 9);
    db.saveClientRecord(
      ClientRecord(
        id: 't1',
        clientId: officeCashId,
        kind: ClientRecordKind.cashRepeat,
        data: {
          'kategori': 'Kira',
          'tutar': 1800000,
          'odeme': 'Banka',
          'baslangic': start.toIso8601String(),
          'bitis': '',
        },
        created: start,
        by: 'Av. Deniz Kaya',
        updated: start,
      ),
    );
    final now = DateTime(2026, 10, 9);
    expect(writeRepeats(db, now), 3);
    expect(writeRepeats(db, now), 0);
    final days = [for (final l in cashLines(db)) l.at]..sort();
    // The 31st falls on September's last day.
    expect(days, [
      DateTime(2026, 7, 31, 9),
      DateTime(2026, 8, 31, 9),
      DateTime(2026, 9, 30, 9),
    ]);
    final other = PortalDatabase.memory();
    addTearDown(other.dispose);
    other.clientsMerge(db.clientsExport());
    expect(writeRepeats(other, now), 0);
    final t = db.clientRecord('t1')!;
    db.saveClientRecord(
      t.copyWith(
        data: {...t.data, 'bitis': DateTime(2026, 10, 1).toIso8601String()},
      ),
    );
    expect(writeRepeats(db, DateTime(2026, 12, 31)), 0);
  });

  test('the office\'s book goes to a member only with the money, and only '
      'its writer\'s own lines are taken', () {
    db.saveClientRecord(
      _cash('g1', 18000, DateTime(2026, 10, 7), person: 'ali'),
    );
    final without = db.clientsOfficeExport(money: false, me: 'ali');
    expect(without['muvekkilKayitlari'], isEmpty);
    final withMoney = db.clientsOfficeExport(money: true, me: 'ali');
    expect((withMoney['muvekkilKayitlari'] as List).single['id'], 'g1');

    final member = PortalDatabase.memory();
    addTearDown(member.dispose);
    expect(
      member.clientsOfficeMerge(
        withMoney,
        money: false,
        me: 'veli',
        from: 'ali',
      ),
      isFalse,
    );
    expect(
      member.clientsOfficeMerge(
        withMoney,
        money: true,
        me: 'veli',
        from: 'ali',
      ),
      isTrue,
    );
    expect(member.clientRecord('g1')?.amount, 1800000);
    // Another's word of it is not taken.
    expect(
      member.clientsOfficeMerge(
        withMoney,
        money: true,
        me: 'veli',
        from: 'can',
      ),
      isFalse,
    );
  });

  testWidgets('an expense written on the page is in the book and its sums', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = Directory.systemTemp.createTempSync('folio_cash_');
    addTearDown(() => root.deleteSync(recursive: true));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CashPage(
            lawyer: 'Av. Deniz Kaya',
            database: db,
            files: ClientFiles(root: () async => root),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cash-expense')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('cash-amount')), '18.000');
    await tester.enterText(
      find.byKey(const ValueKey('cash-what')),
      'Ofis kirası',
    );
    await tester.tap(find.byKey(const ValueKey('cash-save')));
    await tester.pumpAndSettle();
    final r = db.allClientRecords().singleWhere(
      (r) => r.kind == ClientRecordKind.cash,
    );
    expect(r.clientId, officeCashId);
    expect(r.amount, 1800000);
    expect(r.locked, isTrue);
    expect(find.text('Ofis kirası'), findsOneWidget);
    expect(find.text('18.000 TL'), findsWidgets);
  });

  test('each currency is a book of its own: a case paid in euro keeps its '
      'costs met in lira apart, and nothing is added across', () {
    final oct = DateTime(2026, 10, 8, 14, 22);
    db.saveClientRecord(
      ClientRecord(
        id: 'f1',
        clientId: 'c1',
        kind: ClientRecordKind.fee,
        data: {'dosya': 'k1', 'tutar': 500000, 'para': 'EUR'},
        created: oct,
        by: 'Av. Deniz Kaya',
        updated: oct,
      ),
    );
    for (final r in [
      _move('e1', MovementKind.feePaid, 2000, oct, currency: 'EUR'),
      _move('t1', MovementKind.costByLawyer, 3500, oct),
      _cash('g1', 18000, oct),
      _cash('u1', 1200, oct, income: true, currency: 'USD'),
    ]) {
      db.saveClientRecord(r);
    }
    final a = caseAccounts(
      db.allClientRecords().where((r) => r.clientId == 'c1'),
    )['k1']!;
    expect(a.currency, Currency.eur);
    expect(a.feeOwed, 300000);
    expect(a.others.single.currency, Currency.tl);
    expect(a.others.single.lawyerOwed, 350000);
    expect(a.feeOwedAll.text, '3.000 €');
    final b = clientBalances(db, oct).single;
    expect(b.owed[Currency.eur], 300000);
    expect(b.owed[Currency.tl], 0);
    expect(b.costs.text, '3.500 TL');

    final lines = cashLines(db);
    expect(cashCurrencies(lines), [Currency.tl, Currency.eur, Currency.usd]);
    final balance = cashBalance(lines);
    expect(balance[Currency.tl], -1800000);
    expect(balance[Currency.eur], 200000);
    expect(balance[Currency.usd], 120000);
    expect(balance.text, '−18.000 TL + 2.000 € + 1.200 \$');
    expect(inWords(150050, Currency.eur), 'bin beş yüz Avro elli sent');
  });

  test('a bank account is the lawyer\'s own word: its name, currency and '
      'balance, told again whenever they like', () {
    expect(bankAccounts(db), isEmpty);
    final at = DateTime(2026, 10, 12);
    final r = ClientRecord(
      id: 'b1',
      clientId: officeCashId,
      kind: ClientRecordKind.bank,
      data: {'ad': 'Garanti Euro', 'bakiye': 1250000, 'para': 'EUR'},
      created: at,
      by: 'Av. Deniz Kaya',
      updated: at,
    );
    db.saveClientRecord(r);
    final bank = bankAccounts(db).single;
    expect(bank.name, 'Garanti Euro');
    expect(bank.currency, Currency.eur);
    expect(bankTotal([bank]).text, '12.500 €');
    expect(ClientRecordKind.bank.money, isTrue);
    db.saveClientRecord(r.copyWith(removed: true));
    expect(bankAccounts(db), isEmpty);
  });

  testWidgets('the page shows a till for each currency, the one chosen '
      'its own; a bank balance may be added, and need not be', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = Directory.systemTemp.createTempSync('folio_cash_');
    addTearDown(() => root.deleteSync(recursive: true));
    final now = DateTime.now();
    db.saveClientRecord(_cash('g1', 18000, now));
    db.saveClientRecord(_cash('e1', 2000, now, income: true, currency: 'EUR'));
    db.saveClientRecord(_move('m1', MovementKind.costByLawyer, 750, now));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CashPage(
            lawyer: 'Av. Deniz Kaya',
            database: db,
            files: ClientFiles(root: () async => root),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('TL kasası'), findsOneWidget);
    expect(find.text('Euro kasası'), findsOneWidget);
    expect(find.text('Dolar kasası'), findsNothing);
    expect(find.text('−18.000 TL'), findsWidgets);
    expect(find.text('2.000 €'), findsWidgets);
    // The costs met for clients, in TL.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('cash-client-costs')),
        matching: find.text('750 TL'),
      ),
      findsOneWidget,
    );
    // TL's book: the euro income is not in it.
    expect(find.byKey(const ValueKey('cash-line-e1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('cash-till-EUR')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('cash-client-costs')),
        matching: find.text('0 €'),
      ),
      findsOneWidget,
    );

    // An expense written while the euro book is shown is in euro.
    await tester.tap(find.byKey(const ValueKey('cash-expense')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('cash-amount')), '300');
    await tester.tap(find.byKey(const ValueKey('cash-save')));
    await tester.pumpAndSettle();
    final written = db.allClientRecords().singleWhere(
      (r) => r.kind == ClientRecordKind.cash && r.amount == 30000,
    );
    expect(written.currency, Currency.eur);

    // A bank: never asked for, added when wanted.
    await tester.tap(find.byKey(const ValueKey('cash-bank-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('bank-name')), 'Ziraat');
    await tester.enterText(
      find.byKey(const ValueKey('bank-balance')),
      '45.000',
    );
    await tester.tap(find.byKey(const ValueKey('currency-TL')));
    await tester.tap(find.byKey(const ValueKey('bank-save')));
    await tester.pumpAndSettle();
    expect(find.text('Ziraat'), findsOneWidget);
    expect(find.text('45.000 TL'), findsOneWidget);
    expect(find.byKey(const ValueKey('cash-bank-add')), findsNothing);
  });

  test('a line is taken back by its writer alone, here and from a colleague '
      '(R6)', () {
    db.saveClientRecord(
      _cash('c1', 5000, DateTime(2026, 10, 1), income: true, person: 'deniz'),
    );
    ClientRecord back(String person) =>
        _cash(
          'b-$person',
          5000,
          DateTime(2026, 10, 2),
          income: true,
          person: person,
        ).copyWith(
          data: {
            ..._cash('x', 5000, DateTime(2026, 10, 2), income: true).data,
            'ters': 'c1',
          },
        );
    // Written here by a colleague: not kept.
    expect(db.saveClientRecord(back('selin')), isFalse);
    // Sent by one: not taken.
    final other = PortalDatabase.memory();
    addTearDown(other.dispose);
    other.saveClientRecord(back('selin'));
    db.clientsOfficeMerge(
      {
        'muvekkilKayitlari': [back('selin').toJson()],
      },
      money: true,
      me: 'deniz',
      from: 'selin',
    );
    expect(db.clientRecord('b-selin'), isNull);
    expect(cashTotals(cashLines(db)).income, 500000);
    // Its writer's own: taken back.
    expect(db.saveClientRecord(back('deniz')), isTrue);
    expect(cashTotals(cashLines(db)).income, 0);
  });
}

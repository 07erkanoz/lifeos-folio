import 'dart:io';

import 'package:evrak_convert/services/legal/interest.dart';
import 'package:evrak_convert/ui/tools/interest_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rates = InterestRates.parse(
    File('assets/mevzuat/faiz.json').readAsStringSync(),
  );

  // The periods as a commentary lists them (legalbank, checked 9 October
  // 2026): the engine must give the same from the bank's own table and
  // 3095's rule, period by period.
  const table = [
    ('2000-01-01', '2002-06-30', 60.0, 70.0),
    ('2002-07-01', '2003-06-30', 55.0, 64.0),
    ('2003-07-01', '2003-12-31', 50.0, 57.0),
    ('2004-01-01', '2004-06-30', 43.0, 48.0),
    ('2004-07-01', '2005-04-30', 38.0, 42.0),
    ('2005-05-01', '2005-06-30', 12.0, 42.0),
    ('2005-07-01', '2005-12-31', 12.0, 30.0),
    ('2006-01-01', '2006-12-31', 9.0, 25.0),
    ('2007-01-01', '2007-12-31', 9.0, 29.0),
    ('2008-01-01', '2009-06-30', 9.0, 27.0),
    ('2009-07-01', '2009-12-31', 9.0, 19.0),
    ('2010-01-01', '2010-12-31', 9.0, 16.0),
    ('2011-01-01', '2011-12-31', 9.0, 15.0),
    ('2012-01-01', '2012-12-31', 9.0, 17.75),
    ('2013-01-01', '2013-12-31', 9.0, 13.75),
    ('2014-01-01', '2014-12-31', 9.0, 11.75),
    ('2015-01-01', '2016-12-31', 9.0, 10.50),
    ('2017-01-01', '2018-06-30', 9.0, 9.75),
    ('2018-07-01', '2019-12-31', 9.0, 19.50),
    ('2020-01-01', '2020-12-31', 9.0, 13.75),
    ('2021-01-01', '2021-12-31', 9.0, 16.75),
    ('2022-01-01', '2022-12-31', 9.0, 15.75),
    ('2023-01-01', '2023-06-30', 9.0, 10.75),
    ('2023-07-01', '2023-12-31', 9.0, 16.75),
    ('2024-01-01', '2024-05-31', 9.0, 44.25),
    ('2024-06-01', '2024-06-30', 24.0, 44.25),
    ('2024-07-01', '2024-12-31', 24.0, 51.75),
    ('2025-01-01', '2025-06-30', 24.0, 49.25),
    ('2025-07-01', '2025-12-31', 24.0, 44.25),
    ('2026-01-01', '2026-07-30', 24.0, 39.75),
    ('2026-07-31', '2026-12-31', 31.0, 39.75),
  ];

  test('every day of every period has the rate the commentary gives', () {
    for (final (from, to, legal, commercial) in table) {
      final end = DateTime.parse(to);
      for (
        var d = DateTime.parse(from);
        !d.isAfter(end);
        d = DateTime(d.year, d.month, d.day + 1)
      ) {
        expect(rates.rateOn(InterestKind.legal, d)?.rate, legal, reason: '$d');
        expect(
          rates.rateOn(InterestKind.commercial, d)?.rate,
          commercial,
          reason: '$d',
        );
      }
    }
  });

  test('a reckoning splits where the rate changes, and a payment goes to '
      'the interest first, then the principal', () {
    final r = reckon(
      rates: rates,
      kind: InterestKind.legal,
      principal: 10000000,
      from: DateTime(2024, 5, 1),
      to: DateTime(2024, 9, 1),
      payments: [(day: DateTime(2024, 7, 1), amount: 2000000)],
    );
    final stretches = [
      for (final row in r.rows)
        if (!row.isPayment) row,
    ];
    // 1-31 May at 9 %, 1-30 June at 24 %, then 1 July-31 August at 24 %
    // on what the payment left.
    expect(stretches.map((s) => (s.days, s.rate)), [
      (31, 9.0),
      (30, 24.0),
      (62, 24.0),
    ]);
    final may = (10000000 * .09 * 31 / 365).round();
    final june = (10000000 * .24 * 30 / 365).round();
    final payment = r.rows.singleWhere((x) => x.isPayment);
    expect(payment.toInterest, may + june);
    expect(payment.toPrincipal, 2000000 - may - june);
    expect(r.principalLeft, 10000000 - payment.toPrincipal);
    final after = (r.principalLeft * .24 * 62 / 365).round();
    expect(r.interestLeft, after);
    expect(r.accrued, may + june + after);
  });

  test('an agreed rate is the rate; before the data reaches, it says so', () {
    final fixed = reckon(
      rates: rates,
      kind: InterestKind.fixed,
      fixedRate: 36,
      principal: 3650000,
      from: DateTime(2026, 1, 1),
      to: DateTime(2026, 1, 11),
    );
    expect(fixed.accrued, 36000);
    final early = reckon(
      rates: rates,
      kind: InterestKind.commercial,
      principal: 100,
      from: DateTime(1999, 12, 1),
      to: DateTime(2000, 1, 2),
    );
    expect(early.missing, isTrue);
  });

  testWidgets('the page reckons as it is written, the rates changing in its '
      'table', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InterestPage(
            rates: rates,
            principal: 25000000,
            from: DateTime(2024, 3, 15),
            to: DateTime(2026, 10, 9),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('%9'), findsOneWidget);
    expect(find.text('%24'), findsOneWidget);
    expect(find.text('%31'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('interest-kind-ticari')));
    await tester.pumpAndSettle();
    expect(find.text('%44,25'), findsWidgets);
    expect(find.text('%39,75'), findsOneWidget);
  });
}

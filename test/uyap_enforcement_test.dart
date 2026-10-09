import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/clients/client_accounts.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/uyap/uyap_case_data.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_enforcement.dart';
import 'package:evrak_convert/ui/portfolio/enforcement_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The account page's lines as UYAP writes them (karararama's comment and
// banaozel's uyapweb.md): its letters folded, its sums in dots.
final _account = [
  {
    'grupId': 1,
    'textAlan': 'Takipte Kesinlesen Miktar',
    'degerAlan': '250000.00',
  },
  {'grupId': 1, 'textAlan': 'Toplam Faiz Miktari', 'degerAlan': '46387.58'},
  {'grupId': 1, 'textAlan': 'Vekalet Ucreti', 'degerAlan': '17320'},
  {'grupId': 1, 'textAlan': 'Masraf Miktari', 'degerAlan': '1.640,40'},
  {'grupId': 1, 'textAlan': 'Basvurma Harci', 'degerAlan': '427.60'},
  {'grupId': 1, 'textAlan': 'Tahsil Harci', 'degerAlan': '1509.68'},
  {'grupId': 1, 'textAlan': 'Toplam Alacak', 'degerAlan': '318640.50'},
  {'grupId': 2, 'textAlan': 'Yatan Para', 'degerAlan': '50033.65'},
  {'grupId': 1, 'textAlan': 'Bakiye Borc Miktari', 'degerAlan': '268606.85'},
];

void main() {
  test('sums are read however UYAP writes them', () {
    expect(parseLira('268606.85'), 268606.85);
    expect(parseLira('268.606,85'), 268606.85);
    expect(parseLira('268.606,85 TL'), 268606.85);
    expect(parseLira('1.250.000'), 1250000);
    expect(parseLira('17320'), 17320);
    expect(parseLira('Var'), isNull);
  });

  test('the folded labels read in Turkish', () {
    expect(readableLabel('Vekalet Ucreti'), 'Vekâlet ücreti');
    expect(
      readableLabel('Takipte Kesinlesen Miktar'),
      'Takipte kesinleşen miktar',
    );
    expect(readableLabel('Basvurma Harci'), 'Başvurma harcı');
    expect(readableLabel('BSMV'), 'BSMV');
  });

  test('the account splits into its totals, items and fees', () {
    final a = UyapAccount.of(UyapEnforcement.linesFromJson(_account));
    expect(a.total, 318640.50);
    expect(a.paid, 50033.65);
    expect(a.left, 268606.85);
    expect(a.items.map((l) => l.title), [
      'Takipte kesinleşen miktar',
      'Toplam faiz miktarı',
      'Vekâlet ücreti',
      'Masraf miktarı',
    ]);
    expect(a.fees.map((l) => l.title), ['Başvurma harcı', 'Tahsil harcı']);
    expect(a.share, closeTo(.157, .001));
    // Wrapped once more, as some answers come.
    expect(UyapEnforcement.linesFromJson([_account]).length, _account.length);
  });

  test('the account as UYAP really lists it: empty taxes left out, the '
      'deposits of a day summed, the balance in a group of its own', () {
    // The labels, groups and value forms of real files (9 October 2026);
    // the sums made up.
    final a = UyapAccount.of(
      UyapEnforcement.linesFromJson([
        for (final (g, t, v) in const [
          (1, 'Takipte Kesinlesen Miktar', '120000.5'),
          (1, 'Basvurma Harci', ''),
          (1, 'Toplam Faiz Miktari', '15000.25'),
          (1, 'Vekalet Ücreti', '18000.1234'),
          (1, 'Masraf Miktari', '850.4'),
          (1, 'BSMV Miktari', ''),
          (1, 'KKDF Miktari', ''),
          (1, 'KDV Miktari', ''),
          (1, 'Tahsil Harcı', '6400.75'),
          (1, 'Özel Iletisim Vergisi', ''),
          (1, 'Toplam Alacak', '160252.0234'),
          (2, 'Yatan Para (10/08/2026-1.1)', '20000.0'),
          (2, 'Yatan Para (12/09/2026-1.2)', '5000.0'),
          (3, 'Bakiye Borç Miktari', '135252.0234'),
        ])
          {'grupId': g, 'textAlan': t, 'degerAlan': v},
      ]),
    );
    expect(a.total, 160252.0234);
    expect(a.paid, 25000);
    expect(a.left, 135252.0234);
    expect(a.items.map((l) => l.title), [
      'Takipte kesinleşen miktar',
      'Toplam faiz miktarı',
      'Vekâlet ücreti',
      'Masraf miktarı',
    ]);
    expect(a.fees.map((l) => l.title), ['Tahsil harcı']);
    expect(readableLabel('Özel Iletisim Vergisi'), 'Özel iletişim vergisi');
    expect(uyapDay('Sep 9, 2026 9:41:05 PM'), DateTime(2026, 9, 9));
  });

  test('a debtor keeps who they are and what the register warns of, not '
      'their parents\' names', () {
    final d = UyapEnforcement.debtorsFromJson([
      {
        'kisiKurumId': 4417,
        'turu': 0,
        'kisiTumDVO': {
          'adi': 'MEHMET',
          'soyadi': 'TUNÇ',
          'tcKimlikNo': '12345678904',
          'anaAdi': 'AYŞE',
          'babaAdi': 'ALİ',
          'olumKaydi': false,
          'mernisDegisiklikVarmi': true,
          'mernisDegisiklikNedeni': 'Adres değişikliği',
        },
      },
    ]).single;
    expect(d.name, 'MEHMET TUNÇ');
    expect(d.idNo, '1•••••••••4');
    expect(d.moved, isTrue);
    expect(d.dead, isFalse);
    final kept = UyapDebtor.stored(d.toJson())!;
    expect(kept.toJson(), d.toJson());
    expect(d.toJson().toString(), isNot(contains('ALİ')));
  });

  test('a stopped file says why only in its words', () {
    expect(
      stoppedBecause('Açık (Durdurulmuş : Takibe İtiraz)'),
      'Takibe İtiraz',
    );
    expect(stoppedBecause('Açık'), isNull);
  });

  test('the record keeps the account and debtors from one fetch to the '
      'next', () {
    final e = UyapEnforcement(
      lines: UyapEnforcement.linesFromJson(_account),
      debtors: [const UyapDebtor(id: '1', name: 'MEHMET TUNÇ', moved: true)],
    );
    final record = UyapCaseRecord(
      court: 'Antalya 6. İcra Dairesi',
      number: '2025/1904',
      fetchedAt: DateTime(2026, 10, 9),
      enforcement: e,
    );
    final back = UyapCaseRecord.fromJson(record.toJson());
    expect(back.enforcement!.account.left, 268606.85);
    expect(back.enforcement!.debtors.single.moved, isTrue);
  });

  testWidgets('a payment out not yet on the client\'s account is written '
      'there once, as money held for them', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    db.setRepresentation('k1', const [(ad: 'BORA YAPI', rol: 'Alacaklı')]);
    final record = UyapCaseRecord(
      court: 'Antalya 6. İcra Dairesi',
      number: '2025/1904',
      fetchedAt: DateTime(2026, 10, 9),
      enforcement: UyapEnforcement(
        lines: UyapEnforcement.linesFromJson(_account),
      ),
      money: const UyapCaseMoney(
        collected: 50033.65,
        paidOut: 8400,
        collections: [
          UyapMoneyItem(kind: 'Haricen', date: '04.05.2026', amount: 32533.65),
        ],
        payments: [
          UyapMoneyItem(
            kind: 'Posta Ücreti Reddiyatı',
            date: 'Sep 9, 2026 9:41:05 AM',
            amount: 12,
            receipt: 'P-1',
          ),
          UyapMoneyItem(
            kind: 'Vekile ödeme',
            date: '25.09.2026',
            amount: 8400,
            receipt: 'R-77',
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EnforcementView(
              record: record,
              caseKey: 'k1',
              title: '2025/1904 · Antalya 6. İcra Dairesi',
              database: () async => db,
              lawyer: 'Av. Deniz Kaya',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('268.606,85 TL'), findsOneWidget);
    // Postage paid out of the file is a cost, not the client's money.
    expect(find.textContaining('Posta Ücreti'), findsWidgets);
    expect(find.textContaining('reddiyatı (12,00 TL)'), findsNothing);
    final book = find.byKey(const ValueKey('book-uyap-reddiyat:k1:R-77'));
    expect(book, findsOneWidget);
    await tester.tap(book);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('book-trust')));
    await tester.pumpAndSettle();
    final m = db.allClientRecords().singleWhere(
      (r) => r.kind == ClientRecordKind.movement,
    );
    expect(m.movement, MovementKind.advanceIn);
    expect(m.amount, 840000);
    expect(m.text('dosya'), 'k1');
    expect(
      find.byKey(const ValueKey('book-uyap-reddiyat:k1:R-77')),
      findsNothing,
    );
  });
}

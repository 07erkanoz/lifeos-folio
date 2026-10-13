import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/clients/client_accounts.dart';
import 'package:evrak_convert/services/clients/office_cash.dart';
import 'package:evrak_convert/services/enforcement/enforcement_ledger.dart';
import 'package:evrak_convert/services/enforcement/enforcement_papers.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/uyap/uyap_case_data.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_enforcement.dart';
import 'package:evrak_convert/ui/portfolio/enforcement_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _at = DateTime(2026, 10, 10, 11);

LedgerEntry _entry(
  String id,
  int lira, {
  LedgerKind kind = LedgerKind.external,
  bool whole = false,
  String official = '',
  DateTime? at,
}) => LedgerEntry(
  ClientRecord(
    id: id,
    clientId: 'c1',
    kind: ClientRecordKind.enforcement,
    data: {
      'dosya': 'k1',
      'tur': kind.code,
      'tutar': lira * 100,
      'zaman': (at ?? _at).toIso8601String(),
      'borclu': 'Mehmet Tunç',
      'odeme': 'Nakit',
      'tamami': whole,
      'resmi': official,
    },
    created: _at,
    by: 'Av. Deniz Kaya',
    updated: _at,
  ),
);

String _text(DocModel m) => m.blocks.map((b) => b.plainText).join('\n');

const _parties = EnforcementParties(
  office: 'Manavgat İcra Dairesi',
  number: '2026/1234',
  creditor: 'Bora Yapı A.Ş.',
  lawyer: 'Av. Deniz Kaya',
  debtors: ['Mehmet Tunç'],
);

final _account = [
  {'grupId': 1, 'textAlan': 'Toplam Alacak', 'degerAlan': '100000.00'},
  {'grupId': 1, 'textAlan': 'Bakiye Borc Miktari', 'degerAlan': '80000.00'},
];

void main() {
  test('a payment made outside is official once UYAP shows a collection of '
      'its sum made no sooner; each collection matches one payment', () {
    final entries = [_entry('a', 5000), _entry('b', 5000), _entry('c', 700)];
    final found = officialMatches(entries, const [
      UyapMoneyItem(kind: 'Haricen Tahsilat', date: '12.10.2026', amount: 5000),
      // Too early to be it.
      UyapMoneyItem(kind: 'Haciz', date: '01.09.2026', amount: 700),
    ], uyapDay);
    expect(found, {'a': 'tahsilat:12.10.2026|5000.0'});
    // UYAP's balance less what it does not show yet.
    expect(folioLeft(80000, [entries[0], ...entries.skip(1)]), 80000 - 10700);
    expect(
      folioLeft(80000, [
        _entry('a', 5000, official: 'makbuz:1'),
        _entry('w', 2000, kind: LedgerKind.waiver),
      ]),
      78000,
    );
    expect(folioLeft(null, entries), isNull);
  });

  test('the request to the office and the debtor\'s receipt say what was '
      'paid, by whom and when, and what is asked', () {
    expect(
      officeHeading('Manavgat İcra Dairesi'),
      "MANAVGAT İCRA DAİRESİ MÜDÜRLÜĞÜ'NE",
    );
    final partial = _text(externalPaymentRequest(_parties, _entry('a', 15000)));
    expect(partial, contains("MANAVGAT İCRA DAİRESİ MÜDÜRLÜĞÜ'NE"));
    expect(partial, contains('DOSYA NO\t: 2026/1234 Esas'));
    expect(partial, contains('ALACAKLI\t: Bora Yapı A.Ş.'));
    expect(partial, contains('BORÇLU\t: Mehmet Tunç'));
    expect(
      partial,
      contains(
        '10.10.2026 tarihinde dosya borcuna mahsuben tarafımıza haricen '
        '15.000 TL (on beş bin Türk lirası) ödeme yapmıştır',
      ),
    );
    expect(partial, contains('bakiye alacak için takibe devam olunmasına'));
    final whole = _text(
      externalPaymentRequest(_parties, _entry('a', 15000, whole: true)),
    );
    expect(whole, contains('haricen tahsil harcının hesaplanarak'));
    expect(whole, contains('dosyanın haricen tahsil nedeniyle kapatılmasına'));

    final waiver = _text(
      waiverRequest(_parties, _entry('w', 2000, kind: LedgerKind.waiver)),
    );
    expect(waiver, contains('2.000 TL (iki bin Türk lirası) tutarındaki'));
    expect(waiver, contains('feragat yetkisine'));

    final receipt = _text(debtorReceipt(_parties, _entry('a', 15000)));
    expect(receipt, contains('TAHSİLAT MAKBUZU VE KISMİ İBRANAME'));
    expect(
      receipt,
      contains(
        "Manavgat İcra Dairesi'nin 2026/1234 Esas sayılı dosyasında alacaklı "
        'Bora Yapı A.Ş. vekili olarak, borçlu Mehmet Tunç tarafından '
        '10.10.2026 tarihinde dosya borcuna mahsuben nakden ödenen',
      ),
    );
    expect(receipt, contains('tutar kadar dosya borcundan ibra'));
  });

  test('what a debtor paid is held for the client until taken as a fee: '
      'then it is the office\'s income', () {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    db.saveClient(Client(id: 'c1', name: 'Bora Yapı', updated: _at));
    ClientRecord move(String id, MovementKind k, int lira) => ClientRecord(
      id: id,
      clientId: 'c1',
      kind: ClientRecordKind.movement,
      data: {
        'dosya': 'k1',
        'hesap': k.code,
        'tutar': lira * 100,
        'zaman': _at.toIso8601String(),
      },
      created: _at,
      by: 'Av. Deniz Kaya',
      updated: _at,
      locked: true,
    );
    db.saveClientRecord(move('h', MovementKind.collected, 10000));
    db.saveClientRecord(move('f', MovementKind.toFee, 4000));
    final a = caseAccounts(db.allClientRecords())['k1']!;
    expect(a.advanceLeft, 600000);
    expect(a.feeIn, 400000);
    final lines = cashLines(db);
    expect(cashTotals(lines).income, 400000);
    expect(
      lines
          .where((l) => l.side == CashSide.trust)
          .fold(0, (n, l) => n + l.amount),
      600000,
    );
    expect(clientBalances(db, _at).single.held[Currency.tl], 600000);
  });

  testWidgets('a payment made outside is written in the file\'s Folio '
      'account, the debt Folio counts falls by it, and once UYAP shows it '
      'it is official', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    db.setRepresentation('k1', const [(ad: 'BORA YAPI', rol: 'Alacaklı')]);
    UyapCaseRecord record(List<UyapMoneyItem> collections) => UyapCaseRecord(
      court: 'Manavgat İcra Dairesi',
      number: '2026/1234',
      fetchedAt: DateTime(2026, 10, 9),
      enforcement: UyapEnforcement(
        lines: UyapEnforcement.linesFromJson(_account),
        debtors: const [UyapDebtor(id: '1', name: 'MEHMET TUNÇ')],
      ),
      money: UyapCaseMoney(collections: collections),
    );
    Widget view(UyapCaseRecord r) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: EnforcementView(
            record: r,
            caseKey: 'k1',
            title: '2026/1234 · Manavgat İcra Dairesi',
            database: () async => db,
            lawyer: 'Av. Deniz Kaya',
          ),
        ),
      ),
    );
    await tester.pumpWidget(view(record(const [])));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger-add-external')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ledger-amount')),
      '10.000',
    );
    await tester.tap(find.byKey(const ValueKey('ledger-target-fee')));
    // No paper in a test: the UYAP folder is the machine's.
    await tester.tap(find.byKey(const ValueKey('ledger-request')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ledger-save')));
    await tester.pumpAndSettle();

    final entry = ledgerOf(db, 'k1').single;
    expect(entry.amount, 1000000);
    expect(entry.debtor, 'Mehmet Tunç');
    expect(entry.isOfficial, isFalse);
    final moves = db.allClientRecords().where(
      (r) => r.kind == ClientRecordKind.movement,
    );
    expect(
      {for (final m in moves) m.movement},
      {MovementKind.collected, MovementKind.toFee},
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('enforcement-folio-left')),
        matching: find.text('70.000,00 TL'),
      ),
      findsOneWidget,
    );
    expect(find.text('Bekliyor'), findsOneWidget);

    // UYAP read anew shows it.
    await tester.pumpWidget(
      view(
        record(const [
          UyapMoneyItem(
            kind: 'Haricen Tahsilat',
            date: '14.10.2026',
            amount: 10000,
            receipt: 'M-9',
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(ledgerOf(db, 'k1').single.official, 'makbuz:M-9');
    expect(find.text("UYAP'ta"), findsOneWidget);
    expect(find.byKey(const ValueKey('enforcement-folio-left')), findsNothing);
  });
}

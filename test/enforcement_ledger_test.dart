import 'dart:io';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/editor/petition_templates.dart';
import 'package:evrak_convert/services/uyap/uyap_case_links.dart';
import 'package:path/path.dart' as p;
import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/clients/client_accounts.dart';
import 'package:evrak_convert/services/clients/office_cash.dart';
import 'package:evrak_convert/services/enforcement/enforcement_ledger.dart';
import 'package:evrak_convert/services/enforcement/ledger_book.dart';
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
      if (official == 'elle') 'resmiKarar': 'elle',
    },
    created: _at,
    by: 'Av. Deniz Kaya',
    updated: _at,
  ),
  // UYAP's match is worked out, never kept (docs/senkron-plan.md R4).
  matched: official == 'elle' ? '' : official,
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
    // Saving makes no paper and opens nothing: they are printed from the
    // payment's card.
    expect(find.byKey(const ValueKey('ledger-request')), findsNothing);
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
    // Not told to the office yet: said so, and marked once it is.
    expect(
      find.byKey(ValueKey('ledger-not-reported-${entry.id}')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('ledger-unreported')), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('ledger-report-${entry.id}')));
    await tester.pumpAndSettle();
    expect(ledgerOf(db, 'k1').single.isReported, isTrue);
    expect(find.byKey(ValueKey('ledger-reported-${entry.id}')), findsOneWidget);
    expect(find.byKey(const ValueKey('ledger-unreported')), findsNothing);
    // Told, but still not shown by UYAP: still taken off Folio's debt.
    expect(
      find.byKey(const ValueKey('ledger-reported-waiting')),
      findsOneWidget,
    );

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
    // Shown as UYAP's, worked out from what it shows; nothing written for
    // it (docs/senkron-plan.md R4).
    expect(ledgerOf(db, 'k1').single.isOfficial, isFalse);
    expect(ledgerOf(db, 'k1').single.record.data.containsKey('resmi'), isFalse);
    expect(find.text("UYAP'ta görüldü"), findsOneWidget);
    expect(find.byKey(const ValueKey('enforcement-folio-left')), findsNothing);
  });

  testWidgets('a payment made outside is corrected and taken off from its '
      'own line: its money in Kasa follows it, with no reversal written', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    db.setRepresentation('k1', const [(ad: 'BORA YAPI', rol: 'Alacaklı')]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EnforcementView(
              record: UyapCaseRecord(
                court: 'Manavgat İcra Dairesi',
                number: '2026/1234',
                fetchedAt: DateTime(2026, 10, 9),
                enforcement: UyapEnforcement(
                  lines: UyapEnforcement.linesFromJson(_account),
                  debtors: const [UyapDebtor(id: '1', name: 'MEHMET TUNÇ')],
                ),
              ),
              caseKey: 'k1',
              title: '2026/1234 · Manavgat İcra Dairesi',
              database: () async => db,
              lawyer: 'Av. Deniz Kaya',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The table is there before anything is written, with its own buttons.
    expect(
      find.byKey(const ValueKey('ledger-box-add-external')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('ledger-box-add-external')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ledger-amount')),
      '10.000',
    );
    await tester.tap(find.byKey(const ValueKey('ledger-target-fee')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ledger-save')));
    await tester.pumpAndSettle();
    final id = ledgerOf(db, 'k1').single.id;
    // On its card, where the money went is said.
    expect(find.textContaining('vekâlet ücretine mahsup'), findsOneWidget);

    // Corrected: the sum changes, the fee it went to stays.
    await tester.tap(find.byKey(ValueKey('ledger-edit-$id')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ledger-amount')),
      '12.500',
    );
    await tester.tap(find.byKey(const ValueKey('ledger-save')));
    await tester.pumpAndSettle();
    final edited = ledgerOf(db, 'k1').single;
    expect(edited.id, id);
    expect(edited.amount, 1250000);
    var account = caseAccounts(db.allClientRecords())['k1']!;
    expect(account.feeIn, 1250000);
    expect(account.advanceLeft, 0);

    // Its movements are made of it: none written of their own, none
    // reversed (docs/senkron-plan.md R3).
    final movements = [
      for (final r in db.allClientRecords())
        if (r.kind == ClientRecordKind.movement) r,
    ];
    expect(movements, hasLength(2), reason: 'held, and its set-off');
    expect(movements.every(LedgerBook.isProjected), isTrue);
    expect(
      db.saveClientRecord(movements.first.copyWith(locked: false)),
      isFalse,
      reason: 'never written by hand',
    );
    expect(
      db.allClientRecords().where(
        (r) => r.kind == ClientRecordKind.movement && r.text('ters').isNotEmpty,
      ),
      isEmpty,
    );

    // Taken off: the line goes, and its money in Kasa with it.
    await tester.tap(find.byKey(ValueKey('ledger-remove-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger-remove-ok')));
    await tester.pumpAndSettle();
    expect(ledgerOf(db, 'k1'), isEmpty);
    expect(caseAccounts(db.allClientRecords())['k1'], isNull);
    expect(find.byKey(ValueKey('ledger-$id')), findsNothing);
  });

  test('the ready requests are filled from the file: the office, the '
      'sides and the law they rest on', () {
    final c = PetitionCase(
      court: 'Manavgat İcra Dairesi',
      number: '2026/1234',
      lawyer: 'Av. Deniz Kaya',
      parties: const [
        ('Alacaklı', 'BORA YAPI A.Ş.'),
        ('Borçlu', 'MEHMET TUNÇ'),
      ],
    );
    String of(String name) => _text(
      enforcementRequests.singleWhere((t) => t.name == name).build(c, _at),
    );
    expect(enforcementRequests.length, greaterThanOrEqualTo(15));
    final salary = of('Maaş haczi');
    expect(salary, contains('MANAVGAT İCRA DAİRESİ MÜDÜRLÜĞÜ’NE'));
    expect(salary, contains('ALACAKLI\t: BORA YAPI A.Ş.'));
    expect(salary, contains('BORÇLU\t: MEHMET TUNÇ'));
    expect(salary, contains('İİK m.83'));
    expect(salary, contains('Alacaklı Vekili'));
    expect(of('Bankalara haciz ihbarnamesi (89/1)'), contains('İİK m.89/1'));
    expect(
      of('Adres araştırması ve MERNİS adresine tebligat'),
      contains('Tebligat Kanunu m.21/2'),
    );
    // Every request is an enforcement one, and in the editor's list too.
    for (final t in enforcementRequests) {
      expect(t.group, 'İcra');
      expect(petitionTemplates, contains(t));
    }
  });

  testWidgets('a ready request is written in the file\'s folder, tied to '
      'the file and opened in the editor', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = Directory.systemTemp.createTempSync('folio_requests_');
    addTearDown(() => root.deleteSync(recursive: true));
    final kept = (UyapSettings.instance, UyapCaseLinks.instance);
    final settings = UyapSettings(directory: root);
    final links = UyapCaseLinks(directory: root);
    await tester.runAsync(() => settings.update(folder: root.path));
    UyapSettings.instance = settings;
    UyapCaseLinks.instance = links;
    addTearDown(() {
      UyapSettings.instance = kept.$1;
      UyapCaseLinks.instance = kept.$2;
    });
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    const link = UyapCaseLink(
      jurisdiction: '2',
      courtType: '1',
      courtId: '1001',
      court: 'Manavgat İcra Dairesi',
      number: '2026/1234',
    );
    final opened = <File>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EnforcementView(
              record: UyapCaseRecord(
                court: 'Manavgat İcra Dairesi',
                number: '2026/1234',
                fetchedAt: DateTime(2026, 10, 9),
                link: link,
                enforcement: UyapEnforcement(
                  lines: UyapEnforcement.linesFromJson(_account),
                  debtors: const [UyapDebtor(id: '1', name: 'MEHMET TUNÇ')],
                ),
              ),
              caseKey: 'k1',
              title: '2026/1234 · Manavgat İcra Dairesi',
              database: () async => db,
              lawyer: 'Av. Deniz Kaya',
              onOpen: opened.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Looked for in the requests' window, by what it is for.
    await tester.tap(find.byKey(const ValueKey('enforcement-requests')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('request-search')),
      'maaş',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('request-Taşınmaz haczi')), findsNothing);
    final chip = find.byKey(const ValueKey('request-Maaş haczi'));
    await tester.tap(chip);
    // The window closes, then the request is written to disk.
    for (var i = 0; i < 100 && opened.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    expect(opened, hasLength(1));
    final file = opened.single;
    expect(file.path, endsWith('Maaş haczi.udf'));
    expect(p.isWithin(root.path, file.path), isTrue);
    final tied = await tester.runAsync(() => links.of(file.path));
    expect(tied?.number, '2026/1234');
  });

  testWidgets('a colleague\'s payment is shown, with who wrote it, and '
      'changed only by them', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final me = ledgerMe, names = ledgerNameOf;
    addTearDown(() {
      ledgerMe = me;
      ledgerNameOf = names;
    });
    ledgerMe = () => 'deniz';
    ledgerNameOf = (p) => p == 'selin' ? 'Av. Selin Aksoy' : '';
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    for (final (id, person) in [('mine', 'deniz'), ('hers', 'selin')]) {
      db.saveClientRecord(
        ClientRecord(
          id: id,
          clientId: 'c1',
          kind: ClientRecordKind.enforcement,
          data: {
            'dosya': 'k1',
            'tur': LedgerKind.external.code,
            'tutar': 1000000,
            'zaman': _at.toIso8601String(),
            'borclu': 'Mehmet Tunç',
            'odeme': 'Nakit',
          },
          created: _at,
          by: 'Av. Deniz Kaya',
          updated: _at,
          person: person,
        ),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EnforcementView(
              record: UyapCaseRecord(
                court: 'Manavgat İcra Dairesi',
                number: '2026/1234',
                fetchedAt: DateTime(2026, 10, 9),
                enforcement: UyapEnforcement(
                  lines: UyapEnforcement.linesFromJson(_account),
                  debtors: const [UyapDebtor(id: '1', name: 'MEHMET TUNÇ')],
                ),
              ),
              caseKey: 'k1',
              title: '2026/1234 · Manavgat İcra Dairesi',
              database: () async => db,
              lawyer: 'Av. Deniz Kaya',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Her own: as before.
    expect(find.byKey(const ValueKey('ledger-edit-mine')), findsOneWidget);
    expect(find.byKey(const ValueKey('ledger-remove-mine')), findsOneWidget);
    expect(find.byKey(const ValueKey('ledger-report-mine')), findsOneWidget);
    expect(find.byKey(const ValueKey('ledger-owner-mine')), findsNothing);
    // A colleague's: who wrote it, and nothing that changes it.
    expect(find.byKey(const ValueKey('ledger-owner-hers')), findsOneWidget);
    expect(find.text('Yazan: Av. Selin Aksoy'), findsOneWidget);
    expect(
      find.text('Bu kaydı yalnız Av. Selin Aksoy değiştirebilir.'),
      findsOneWidget,
    );
    for (final key in [
      'ledger-edit-hers',
      'ledger-remove-hers',
      'ledger-report-hers',
      'ledger-official-hers',
    ]) {
      expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
    }
    expect(tester.takeException(), isNull);
  });
}

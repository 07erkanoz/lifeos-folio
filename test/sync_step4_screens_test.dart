import 'dart:io';

import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/clients/client_accounts.dart';
import 'package:evrak_convert/services/clients/client_files.dart';
import 'package:evrak_convert/services/enforcement/ledger_book.dart';
import 'package:evrak_convert/services/enforcement/ledger_service.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/sync/hlc.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/ui/cash/cash_page.dart';
import 'package:evrak_convert/ui/portfolio/enforcement_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// docs/senkron-plan.md §5 step 4's screens: a set-off waiting on its
/// payment, and the repair report in Kasa.
void main() {
  testWidgets('a set-off past what is held is shown waiting on its payment, '
      'and taken off from there', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    var wall = DateTime.utc(2026, 10, 14, 9);
    LedgerService book() => LedgerService(
      db,
      clock: HlcClock(source: 'a:0', now: () => wall),
    );
    final paid = book().add(
      clientId: 'k1',
      caseKey: 'k1',
      kind: 'haricen',
      amount: 500000,
      at: DateTime(2026, 10, 10),
      by: 'Av. Deniz Kaya',
      debtor: 'Mehmet Tunç',
    );
    // Taken as a fee past what is held: as when two devices set off apart.
    final over = LedgerBook.write(
      paid,
      versions: LedgerBook.versionsOf(paid),
      setOffs: [
        LedgerSetOff(
          id: 's1',
          target: MovementKind.toFee,
          amount: 800000,
          at: DateTime(2026, 10, 11),
          version: Hlc(wall.millisecondsSinceEpoch + 5, 0, 'b:0'),
        ),
      ],
    );
    db.saveClientRecord(over);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EnforcementView(
              record: UyapCaseRecord(
                court: 'Manavgat İcra Dairesi',
                number: '2026/1234',
                fetchedAt: DateTime(2026, 10, 9),
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
    final waiting = find.byKey(ValueKey('ledger-waiting-${paid.id}-s1'));
    expect(waiting, findsOneWidget);
    expect(
      find.descendant(
        of: waiting,
        matching: find.textContaining('Mahsup askıda: 8.000,00 TL'),
      ),
      findsOneWidget,
    );
    wall = wall.add(const Duration(minutes: 1));
    await tester.tap(find.byKey(const ValueKey('ledger-waiting-remove-s1')));
    await tester.pumpAndSettle();
    expect(waiting, findsNothing);
    expect(
      LedgerBook.setOffsOf(db.clientRecord(paid.id)!).single.removed,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kasa shows the payments whose old movements wait for the '
      'lawyer\'s word, and mends one as it showed it', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = Directory.systemTemp.createTempSync('folio_onarim_');
    addTearDown(() => root.deleteSync(recursive: true));
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    db.saveClientRecord(
      ClientRecord(
        id: 'e1',
        clientId: 'k1',
        kind: ClientRecordKind.enforcement,
        data: const {
          'dosya': 'k1',
          'tur': 'haricen',
          'tutar': 1000000,
          'zaman': '2026-10-10T00:00:00',
        },
        created: DateTime(2026, 10, 10),
        by: 'Av. D',
        updated: DateTime(2026, 10, 10),
      ),
    );
    for (final id in ['h1', 'h2']) {
      db.putRecordForTesting(
        ClientRecord(
          id: id,
          clientId: 'k1',
          kind: ClientRecordKind.movement,
          data: {
            'dosya': 'k1',
            'hesap': MovementKind.collected.code,
            'tutar': 1000000,
            'zaman': '2026-10-10T00:00:00',
            'kaynak': 'icra:e1',
          },
          created: DateTime(2026, 10, 10, 1),
          by: 'Av. D',
          updated: DateTime(2026, 10, 10, 1),
          locked: true,
        ),
      );
    }
    db.migrateLedgers();
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
    expect(find.byKey(const ValueKey('ledger-repairs')), findsOneWidget);
    expect(find.textContaining('2 kez işlenmiş'), findsOneWidget);
    expect(
      find.textContaining(
        'Şimdi: 20.000 TL emanet → Onarınca: '
        '10.000 TL emanet',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('ledger-repair-ok-e1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ledger-repairs')), findsNothing);
    expect(caseAccounts(db.allClientRecords())['k1']!.advanceLeft, 1000000);
    expect(tester.takeException(), isNull);
  });
}

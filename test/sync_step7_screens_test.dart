import 'package:evrak_convert/services/clients/client_accounts.dart';
import 'package:evrak_convert/services/enforcement/ledger_service.dart';
import 'package:evrak_convert/services/office/proposals.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/ui/widgets/proposals_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// docs/senkron-plan.md §5 step 7, the screens approved: the owner's
/// waiting proposals, taken or refused; what the one who proposed sees.
void main() {
  late PortalDatabase db;
  late ProposalService Function(PortalDatabase) was;
  late String Function()? person0;
  setUp(() {
    db = PortalDatabase.memory();
    was = proposalsFor;
    person0 = PortalDatabase.clientPerson;
  });
  tearDown(() {
    proposalsFor = was;
    PortalDatabase.clientPerson = person0;
    db.dispose();
  });

  testWidgets('the owner sees what is proposed, now and then, and takes it; '
      'the one who proposed sees it taken', (tester) async {
    PortalDatabase.clientPerson = () => 'deniz';
    final r = LedgerService(db).add(
      clientId: 'k',
      caseKey: '2026/1234 İcra',
      kind: 'haricen',
      amount: 1500000,
      at: DateTime(2026, 10, 10),
      by: 'Av. Deniz Kaya',
      person: 'deniz',
    );
    // Selin's proposal, as it came to Deniz.
    db.putProposal(
      Proposal(
        id: 'p1',
        owner: 'deniz',
        by: 'selin',
        byName: 'Av. Selin Ak',
        kind: 'icra',
        target: r.id,
        seen: ProposalService.versionsOf(db, 'icra', r.id),
        fields: const {'tutar': 1250000},
        reason: 'Makbuzda 12.500 yazıyor',
        at: DateTime(2026, 10, 14, 15, 2),
      ),
    );
    proposalsFor = (db) => ProposalService(db, me: 'deniz', device: 'deniz');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(builder: (_) => ProposalsStrip(db: db)),
        ),
      ),
    );
    expect(find.text('Bekleyen öneriler · 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('proposals-strip')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Av. Selin Ak · Haricen tahsilat'),
      findsOneWidget,
    );
    expect(find.textContaining('Makbuzda 12.500 yazıyor'), findsOneWidget);
    expect(
      find.textContaining('15.000 TL → 12.500 TL', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('proposal-yes-p1')));
    await tester.pumpAndSettle();
    expect(db.clientRecord(r.id)!.amount, 1250000);
    expect(find.text('Bekleyen öneri yok.'), findsOneWidget);

    // Selin's side: the same record and proposal, its decision come.
    proposalsFor = (db) => ProposalService(db, me: 'selin', device: 'b1');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProposalStatus(db: db, target: r.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Onaylandı'), findsOneWidget);
  });

  testWidgets('elsewhere than the device for deciding, only shown', (
    tester,
  ) async {
    PortalDatabase.clientPerson = () => 'deniz';
    final r = LedgerService(db).add(
      clientId: 'k',
      caseKey: 'd',
      kind: 'haricen',
      amount: 100,
      at: DateTime(2026, 10, 10),
      by: 'Av. Deniz Kaya',
      person: 'deniz',
    );
    db.putProposal(
      Proposal(
        id: 'p1',
        owner: 'deniz',
        by: 'selin',
        byName: 'Av. Selin Ak',
        kind: 'icra',
        target: r.id,
        seen: ProposalService.versionsOf(db, 'icra', r.id),
        fields: const {'tutar': 200},
        at: DateTime(2026, 10, 14),
      ),
    );
    proposalsFor = (db) => ProposalService(db, me: 'deniz', device: 'telefon');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProposalsStrip(db: db)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('proposals-strip')));
    await tester.pumpAndSettle();
    expect(find.textContaining('burada yalnız görünür'), findsOneWidget);
    expect(find.byKey(const ValueKey('proposal-yes-p1')), findsNothing);
  });
}

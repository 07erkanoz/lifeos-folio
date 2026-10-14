import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/clients/client_accounts.dart';
import 'package:evrak_convert/services/clients/office_cash.dart';
import 'package:evrak_convert/services/enforcement/ledger_service.dart';
import 'package:evrak_convert/services/office/proposals.dart';
import 'package:evrak_convert/services/office/shared_cases.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/sync/hlc.dart';
import 'package:flutter_test/flutter_test.dart';

/// docs/senkron-plan.md §5 step 8 (as the lawyer chose: no switch): a case
/// shared with one who may see the money brings its payments, read only,
/// in no account nor Kasa of theirs; gone when the share is.
void main() {
  late PortalDatabase a, b;
  late String Function()? person0;
  setUp(() {
    a = PortalDatabase.memory();
    b = PortalDatabase.memory();
    person0 = PortalDatabase.clientPerson;
    PortalDatabase.clientPerson = () => 'deniz';
  });
  tearDown(() {
    PortalDatabase.clientPerson = person0;
    a.dispose();
    b.dispose();
  });

  ClientRecord payment({String note = '', bool secret = false}) =>
      LedgerService(a).add(
        clientId: 'k',
        caseKey: 'dava',
        kind: 'haricen',
        amount: 1500000,
        at: DateTime(2026, 10, 10),
        by: 'Av. Deniz Kaya',
        person: 'deniz',
        note: note,
        noteSecret: secret,
      );

  /// What Deniz's share of 'dava' sends Selin, taken by her.
  bool send({Hlc? version, bool closed = false}) => b.takeSharedLedger(
    'deniz',
    'dava',
    version ?? a.caseShareVersion('dava')!,
    closed: closed,
    ownerName: 'Av. Deniz Kaya',
    records: [
      for (final j in a.caseLedgerForOffice('dava', 'deniz'))
        ?ClientRecord.fromJson(j),
    ],
  );

  test('shared, its payments come read only: in no account nor Kasa of '
      'the one it is shared with', () {
    final r = payment();
    SharedCases.share(a, 'dava', ['selin']);
    expect(send(), isTrue);
    expect(b.sharedLedgersOf('dava')['deniz']!.single.amount, 1500000);
    expect(b.clientRecord(r.id), isNull);
    expect(caseAccounts(b.allClientRecords()), isEmpty);
    expect(cashLines(b), isEmpty);
    // Taken again: nothing changes.
    expect(send(), isFalse);
  });

  test('a change of it there comes; one of before brings nothing back; the '
      'share taken off, it goes, and is said to', () {
    final r = payment();
    SharedCases.share(a, 'dava', ['selin']);
    final first = a.caseShareVersion('dava')!;
    send();
    LedgerService(a).edit(
      a.clientRecord(r.id)!,
      amount: 1200000,
      at: DateTime(2026, 10, 10),
      debtor: '',
      way: '',
      note: '',
      whole: false,
      target: null,
    );
    send();
    expect(b.sharedLedgersOf('dava')['deniz']!.single.amount, 1200000);
    SharedCases.share(a, 'dava', const []);
    expect(send(closed: true), isTrue);
    expect(b.sharedLedgersOf('dava'), isEmpty);
    expect(b.sharedLedgerRemoved('dava'), 'Av. Deniz Kaya');
    // An older package, of the share before: nothing.
    expect(send(version: first), isFalse);
    expect(b.sharedLedgersOf('dava'), isEmpty);
  });

  test('a secret description goes empty; a colleague\'s record here is not '
      'sent on', () {
    payment(note: 'Borçlu ödeme güçlüğünde', secret: true);
    a.putRecordForTesting(
      ClientRecord(
        id: 'x',
        clientId: 'k',
        kind: ClientRecordKind.enforcement,
        data: const {'dosya': 'dava', 'tur': 'haricen', 'tutar': 1},
        created: DateTime(2026, 10, 1),
        by: 'Av. Mert Can',
        updated: DateTime(2026, 10, 1),
        person: 'mert',
      ),
    );
    final sent = a.caseLedgerForOffice('dava', 'deniz');
    expect(sent.length, 1);
    expect('${(sent.single['veri'] as Map)['aciklama']}', isEmpty);
  });

  test('a record here through the card too is kept once, as the card\'s', () {
    final r = payment();
    SharedCases.share(a, 'dava', ['selin']);
    send();
    b.clientsMerge(a.clientsExport());
    expect(b.clientRecord(r.id), isNotNull);
    expect(b.sharedLedgersOf('dava'), isEmpty);
  });

  test('a colleague\'s shared payment may be proposed of, to its owner', () {
    final r = payment();
    SharedCases.share(a, 'dava', ['selin']);
    send();
    PortalDatabase.clientPerson = () => 'selin';
    final p = ProposalService(
      b,
      me: 'selin',
      device: 'b1',
    ).propose(kind: 'icra', target: r.id, fields: {'tutar': 1250000});
    expect(p, isNotNull);
    expect(p!.owner, 'deniz');
  });

  test('the money no longer let: every account shared is forgotten', () {
    payment();
    SharedCases.share(a, 'dava', ['selin']);
    send();
    b.forgetClientMoney(keepPerson: 'selin');
    expect(b.sharedLedgersOf('dava'), isEmpty);
  });

  group('Codex\'s review of step 8', () {
    test('here through the card too: kept alike both ways, so the shared '
        'copy is as new once the card is no longer shared', () {
      final r = payment();
      SharedCases.share(a, 'dava', ['selin']);
      send();
      LedgerService(a).edit(
        a.clientRecord(r.id)!,
        amount: 1200000,
        at: DateTime(2026, 10, 10),
        debtor: '',
        way: '',
        note: '',
        whole: false,
        target: null,
      );
      // The newer comes through the card: the shared copy alike, at once.
      b.clientsMerge(a.clientsExport());
      expect(b.sharedLedgerRecord(r.id)!.amount, 1200000);
    });

    test('a description taken back is taken out of the shared copy too', () {
      final r = payment(note: 'Borçlu ödeme güçlüğünde');
      SharedCases.share(a, 'dava', ['selin']);
      send();
      expect(b.sharedLedgerRecord(r.id)!.text('aciklama'), isNotEmpty);
      LedgerService(a).edit(
        a.clientRecord(r.id)!,
        amount: 1500000,
        at: DateTime(2026, 10, 10),
        debtor: '',
        way: '',
        note: 'Borçlu ödeme güçlüğünde',
        whole: false,
        target: null,
        noteSecret: true,
      );
      final hide = a.hideOf('aciklama:${r.id}')!;
      b.takeNoteHide('deniz', 'aciklama:${r.id}', hide);
      b.applyTakenNoteHides();
      expect(b.sharedLedgerRecord(r.id)!.text('aciklama'), isEmpty);
    });

    test('the money no longer let, then let again: a package of a share of '
        'before brings nothing back', () {
      payment();
      SharedCases.share(a, 'dava', ['selin']);
      final first = a.caseShareVersion('dava')!;
      send();
      SharedCases.share(a, 'dava', const []);
      send(closed: true);
      b.forgetClientMoney(keepPerson: 'selin');
      expect(send(version: first), isFalse);
      expect(b.sharedLedgersOf('dava'), isEmpty);
    });

    test('the one it is shared with: their other device has it too', () {
      final r = payment();
      SharedCases.share(a, 'dava', ['selin']);
      send();
      final b2 = PortalDatabase.memory();
      addTearDown(b2.dispose);
      b2.noteTrackingMerge(b.noteTrackingExport());
      expect(b2.sharedLedgerRecord(r.id), isNotNull);
      // Closed: on the other device too.
      SharedCases.share(a, 'dava', const []);
      send(closed: true);
      b2.noteTrackingMerge(b.noteTrackingExport());
      expect(b2.sharedLedgersOf('dava'), isEmpty);
    });
  });

  group('the last review', () {
    test('whom a case is shared with goes to the person\'s other devices, '
        'a later word over an earlier', () {
      final a2 = PortalDatabase.memory();
      addTearDown(a2.dispose);
      SharedCases.share(a, 'dava', ['selin']);
      expect(SharedCases.ownMerge(a2, SharedCases.ownExport(a)), isTrue);
      expect(SharedCases.sharedWith(a2, 'dava'), ['selin']);
      final before = SharedCases.ownExport(a);
      SharedCases.share(a, 'dava', const []);
      SharedCases.ownMerge(a2, SharedCases.ownExport(a));
      expect(SharedCases.sharedWith(a2, 'dava'), isEmpty);
      // The word of before, come late: nothing.
      expect(SharedCases.ownMerge(a2, before), isFalse);
      expect(SharedCases.sharedWith(a2, 'dava'), isEmpty);
    });

    test('closed for the money, a copy another own device kept of before '
        'does not open it again; its owner\'s word does', () {
      payment();
      SharedCases.share(a, 'dava', ['selin']);
      send();
      final b2 = PortalDatabase.memory();
      addTearDown(b2.dispose);
      b2.noteTrackingMerge(b.noteTrackingExport());
      b.forgetClientMoney(keepPerson: 'selin');
      expect(b.sharedLedgersOf('dava'), isEmpty);
      // The money let again: b2's copy of before, same version.
      b.noteTrackingMerge(b2.noteTrackingExport());
      expect(b.sharedLedgersOf('dava'), isEmpty);
      // The owner's word as it is now opens it.
      PortalDatabase.clientPerson = () => 'deniz';
      expect(send(), isTrue);
      expect(b.sharedLedgersOf('dava'), isNotEmpty);
    });

    test('the money no longer let: proposals of others\' payments go, and '
        'are not taken from another own device', () {
      final r = payment();
      SharedCases.share(a, 'dava', ['selin']);
      send();
      PortalDatabase.clientPerson = () => 'selin';
      final s = ProposalService(b, me: 'selin', device: 'b1');
      s.propose(kind: 'icra', target: r.id, fields: {'tutar': 1});
      final copy = s.ownExport();
      expect(b.proposals(by: 'selin'), isNotEmpty);
      final allowed = PortalDatabase.clientMoneyAllowed;
      addTearDown(() => PortalDatabase.clientMoneyAllowed = allowed);
      PortalDatabase.clientMoneyAllowed = () => false;
      b.forgetClientMoney(keepPerson: 'selin');
      expect(b.proposals(by: 'selin'), isEmpty);
      s.ownMerge(copy);
      expect(b.proposals(by: 'selin'), isEmpty);
    });
  });

  group('the last review, again', () {
    test('a decision whose proposal is not here is not taken', () {
      final r = payment();
      SharedCases.share(a, 'dava', ['selin']);
      send();
      PortalDatabase.clientPerson = () => 'selin';
      final s = ProposalService(b, me: 'selin', device: 'b1');
      final p = s.propose(kind: 'icra', target: r.id, fields: {'tutar': 1})!;
      final decision = ProposalDecision(
        proposal: p.id,
        owner: 'deniz',
        approved: false,
        device: 'deniz',
        generation: 0,
        at: DateTime(2026, 10, 14),
        reason: 'Makbuz 15.000',
      ).toJson();
      final allowed = PortalDatabase.clientMoneyAllowed;
      addTearDown(() => PortalDatabase.clientMoneyAllowed = allowed);
      PortalDatabase.clientMoneyAllowed = () => false;
      b.forgetClientMoney(keepPerson: 'selin');
      s.ownMerge({
        'oneriler': [p.toJson()],
        'kararlar': [decision],
      });
      expect(b.decisionOf(p.id), isNull);
    });

    test('closed, then open again: a closed copy of before is behind', () {
      payment();
      SharedCases.share(a, 'dava', ['selin']);
      final closedAt = a.accessVersion('dava', 'selin', false);
      final openAt = a.accessVersion('dava', 'selin', true);
      expect(openAt > closedAt, isTrue);
      expect(send(version: openAt), isTrue);
      // Another own device of hers still had it closed, of before.
      final b2 = PortalDatabase.memory();
      addTearDown(b2.dispose);
      b2.takeSharedLedger('deniz', 'dava', closedAt, closed: true);
      b.noteTrackingMerge(b2.noteTrackingExport());
      expect(b.sharedLedgersOf('dava'), isNotEmpty);
    });
  });
}

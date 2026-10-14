import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/clients/client_accounts.dart';
import 'package:evrak_convert/services/enforcement/ledger_service.dart';
import 'package:evrak_convert/services/office/proposals.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:flutter_test/flutter_test.dart';

/// docs/senkron-plan.md §5 step 7: a colleague's change of another's
/// record is a proposal, decided by its owner on their one device for
/// deciding (R6, §3 decision 2).
void main() {
  // Deniz owns (devices a1, her first, and a2); Selin proposes (b1).
  late PortalDatabase a, a2, b;
  late String Function()? person0;
  setUp(() {
    a = PortalDatabase.memory();
    a2 = PortalDatabase.memory();
    b = PortalDatabase.memory();
    person0 = PortalDatabase.clientPerson;
  });
  tearDown(() {
    PortalDatabase.clientPerson = person0;
    a.dispose();
    a2.dispose();
    b.dispose();
  });

  ProposalService as(PortalDatabase db, String me, String device) {
    PortalDatabase.clientPerson = () => me;
    return ProposalService(db, me: me, device: device, myName: me);
  }

  /// [from]'s proposals and decisions for [to], as the office part takes
  /// them.
  bool send(
    PortalDatabase from,
    String fromMe,
    PortalDatabase to,
    String toMe, {
    bool money = true,
  }) {
    final out = as(from, fromMe, '').officeExport(toMe, money: money);
    return as(to, toMe, '').officeMerge(out, fromMe, money: money);
  }

  ClientRecord payment() {
    PortalDatabase.clientPerson = () => 'deniz';
    final made = LedgerService(a).add(
      clientId: 'k',
      caseKey: 'dava',
      kind: 'haricen',
      amount: 1500000,
      at: DateTime(2026, 10, 10),
      by: 'Av. Deniz Kaya',
      person: 'deniz',
    );
    b.clientsMerge(a.clientsExport());
    return made;
  }

  test('a colleague proposes, the owner takes it on their device: the '
      'record changes there, and the one who proposed hears', () {
    final r = payment();
    final p = as(b, 'selin', 'b1').propose(
      kind: 'icra',
      target: r.id,
      fields: {'tutar': 1250000},
      reason: 'Makbuzda 12.500 yazıyor',
    )!;
    expect(send(b, 'selin', a, 'deniz'), isTrue);
    final owner = as(a, 'deniz', 'deniz');
    expect(owner.waiting.single.id, p.id);
    final d = owner.decide(p.id, approve: true)!;
    expect(d.approved, isTrue);
    expect(a.clientRecord(r.id)!.amount, 1250000);
    expect(owner.waiting, isEmpty);
    send(a, 'deniz', b, 'selin');
    expect(b.decisionOf(p.id)!.approved, isTrue);
    // Taken again: nothing changes, nothing applied twice.
    expect(send(a, 'deniz', b, 'selin'), isFalse);
    expect(owner.decide(p.id, approve: true), isNull);
  });

  test('refused: nothing changes; made on a record changed since: old, not '
      'taken', () {
    final r = payment();
    final no = as(
      b,
      'selin',
      'b1',
    ).propose(kind: 'icra', target: r.id, fields: {'tutar': 1})!;
    final old = as(
      b,
      'selin',
      'b1',
    ).propose(kind: 'icra', target: r.id, fields: {'tutar': 2})!;
    send(b, 'selin', a, 'deniz');
    final owner = as(a, 'deniz', 'deniz');
    owner.decide(no.id, approve: false, reason: 'Makbuz 15.000');
    expect(a.clientRecord(r.id)!.amount, 1500000);
    // Deniz changes it herself meanwhile.
    PortalDatabase.clientPerson = () => 'deniz';
    LedgerService(a).setReported(a.clientRecord(r.id)!, DateTime(2026, 10, 12));
    expect(owner.current(old), isFalse);
    final d = owner.decide(old.id, approve: true)!;
    expect((d.approved, d.stale), (false, true));
    expect(a.clientRecord(r.id)!.amount, 1500000);
  });

  test('decided only on the device for deciding', () {
    final r = payment();
    final p = as(
      b,
      'selin',
      'b1',
    ).propose(kind: 'icra', target: r.id, remove: true)!;
    send(b, 'selin', a, 'deniz');
    expect(as(a, 'deniz', 'a2').decide(p.id, approve: true), isNull);
    expect(a.clientRecord(r.id)!.removed, isFalse);
    expect(as(a, 'deniz', 'deniz').decide(p.id, approve: true), isNotNull);
    expect(a.clientRecord(r.id)!.removed, isTrue);
  });

  test('the device for deciding lost: a decision of it that comes after '
      'does not hold, what it changed is put back, the proposal open '
      'again; one changed since is a conflict', () {
    final r = payment();
    a2.clientsMerge(a.clientsExport());
    final p = as(
      b,
      'selin',
      'b1',
    ).propose(kind: 'icra', target: r.id, fields: {'tutar': 1250000})!;
    send(b, 'selin', a, 'deniz');
    send(b, 'selin', a2, 'deniz');
    // a1 decides, but is lost before it is heard of.
    as(a, 'deniz', 'deniz').decide(p.id, approve: true);
    final second = as(a2, 'deniz', 'a2').lost()!;
    expect(second.generation, 1);
    // What a1 did comes to a2 after all: the change, then the decision.
    a2.clientsMerge(a.clientsExport());
    expect(a2.clientRecord(r.id)!.amount, 1250000);
    as(a2, 'deniz', 'a2').ownMerge(as(a, 'deniz', 'deniz').ownExport());
    expect(a2.decisionOf(p.id)!.void_, isTrue);
    expect(a2.clientRecord(r.id)!.amount, 1500000);
    final now = as(a2, 'deniz', 'a2');
    expect(now.waiting.single.id, p.id);
    expect(now.decidesHere, isTrue);
    // Decided anew here: it stands, the older one does not come back.
    expect(now.decide(p.id, approve: false), isNotNull);
    as(a2, 'deniz', 'a2').ownMerge(as(a, 'deniz', 'deniz').ownExport());
    expect(a2.decisionOf(p.id)!.approved, isFalse);
    expect(a2.decisionOf(p.id)!.void_, isFalse);
  });

  test('of money only between two who may see it; a card\'s note only of a '
      'card shared', () {
    final r = payment();
    as(
      b,
      'selin',
      'b1',
    ).propose(kind: 'icra', target: r.id, fields: {'tutar': 1});
    expect(send(b, 'selin', a, 'deniz', money: false), isFalse);
    expect(as(a, 'deniz', 'deniz').waiting, isEmpty);
    PortalDatabase.clientPerson = () => 'deniz';
    a.saveClient(
      Client(
        id: 'k2',
        name: 'Ayşe Karaca',
        updated: DateTime(2026, 10, 1),
        person: 'deniz',
      ),
    );
    b.clientsMerge(a.clientsExport());
    as(b, 'selin', 'b1').propose(
      kind: 'kartNotu',
      target: 'k2',
      fields: {'metin': 'Sabah aranır'},
    );
    send(b, 'selin', a, 'deniz', money: false);
    expect(as(a, 'deniz', 'deniz').waiting, isEmpty, reason: 'not shared');
    PortalDatabase.clientPerson = () => 'deniz';
    a.saveClient(a.clientCard('k2')!.copyWith(office: true));
    send(b, 'selin', a, 'deniz', money: false);
    final owner = as(a, 'deniz', 'deniz');
    final p = owner.waiting.single;
    owner.decide(p.id, approve: true);
    expect(a.clientCard('k2')!.note, 'Sabah aranır');
  });

  test('one\'s own record is not proposed', () {
    final r = payment();
    expect(as(a, 'deniz', 'deniz').propose(kind: 'icra', target: r.id), isNull);
    expect(r.amount, 1500000);
  });

  group('Codex\'s review of step 7', () {
    Proposal ask(ClientRecord r, Map<String, Object?> fields) {
      final p = as(
        b,
        'selin',
        'b1',
      ).propose(kind: 'icra', target: r.id, fields: fields)!;
      send(b, 'selin', a, 'deniz');
      send(b, 'selin', a2, 'deniz');
      return p;
    }

    test('given over, every decision of before stands', () {
      final r = payment();
      a2.clientsMerge(a.clientsExport());
      final p = ask(r, {'tutar': 1250000});
      as(a, 'deniz', 'deniz').decide(p.id, approve: true);
      a2.clientsMerge(a.clientsExport());
      as(a, 'deniz', 'deniz').giveTo('a2');
      as(a2, 'deniz', 'a2').ownMerge(as(a, 'deniz', 'deniz').ownExport());
      expect(a2.decisionOf(p.id)!.void_, isFalse);
      expect(a2.clientRecord(r.id)!.amount, 1250000);
      expect(as(a2, 'deniz', 'a2').decidesHere, isTrue);
      expect(as(a, 'deniz', 'deniz').decidesHere, isFalse);
    });

    test('two devices that each took the lost one\'s place at once end '
        'with one, the same on both', () {
      final a3 = PortalDatabase.memory();
      addTearDown(a3.dispose);
      as(a2, 'deniz', 'a2').lost();
      as(a3, 'deniz', 'a3').lost();
      as(a2, 'deniz', 'a2').ownMerge(as(a3, 'deniz', 'a3').ownExport());
      as(a3, 'deniz', 'a3').ownMerge(as(a2, 'deniz', 'a2').ownExport());
      final one = as(a2, 'deniz', 'a2').decidesHere;
      final other = as(a3, 'deniz', 'a3').decidesHere;
      expect(one != other, isTrue);
    });

    test('a later decision stands over an earlier one, whatever came '
        'first; an earlier one not holding never over a later', () {
      final r = payment();
      final p = ask(r, {'tutar': 1});
      final first = ProposalDecision(
        proposal: p.id,
        owner: 'deniz',
        approved: true,
        device: 'deniz',
        generation: 0,
        at: DateTime(2026, 10, 14, 10),
      );
      final later = ProposalDecision(
        proposal: p.id,
        owner: 'deniz',
        approved: false,
        device: 'a2',
        generation: 1,
        at: DateTime(2026, 10, 14, 11),
      );
      b.putDecision(first);
      expect(b.putDecision(later), isTrue);
      expect(b.decisionOf(p.id)!.approved, isFalse);
      expect(b.putDecision(first.voided()), isFalse);
      expect(b.decisionOf(p.id)!.generation, 1);
    });

    test('a note made secret: its text goes from the proposals of it', () {
      PortalDatabase.clientPerson = () => 'deniz';
      a.saveClient(
        Client(
          id: 'k2',
          name: 'Ayşe Karaca',
          updated: DateTime(2026, 10, 1),
          person: 'deniz',
          caseNotes: {'dava': CaseNote('Açık not', DateTime(2026, 10, 1))},
        ).copyWith(office: true),
      );
      b.clientsMerge(a.clientsExport());
      as(b, 'selin', 'b1').propose(
        kind: 'dosyaNotu',
        target: 'k2',
        caseKey: 'dava',
        fields: {'metin': 'Açık not, sınır 50.000'},
      );
      send(b, 'selin', a, 'deniz', money: false);
      PortalDatabase.clientPerson = () => 'deniz';
      final card = a.clientCard('k2')!;
      a.saveClient(
        card.copyWith(
          caseNotes: {
            'dava': CaseNote('Açık not', DateTime(2026, 10, 2), secret: true),
          },
        ),
      );
      expect(a.proposals(owner: 'deniz').single.fields['metin'], isEmpty);
    });

    test('a decision not holding: its sum put back though the record was '
        'marked told since; what it wrote never taken after', () {
      final r = payment();
      a2.clientsMerge(a.clientsExport());
      final p = ask(r, {'tutar': 1250000});
      as(a, 'deniz', 'deniz').decide(p.id, approve: true);
      as(a2, 'deniz', 'a2').lost();
      // a2 marks it told, before anything of a1 comes.
      PortalDatabase.clientPerson = () => 'deniz';
      LedgerService(a2)
          .setReported(a2.clientRecord(r.id)!, DateTime(2026, 10, 12));
      // The decision comes first, then what it wrote.
      as(a2, 'deniz', 'a2').ownMerge(as(a, 'deniz', 'deniz').ownExport());
      expect(a2.decisionOf(p.id)!.void_, isTrue);
      a2.clientsMerge(a.clientsExport());
      final now = a2.clientRecord(r.id)!;
      expect(now.amount, 1500000);
      expect(now.text('bildirildi'), isNotEmpty);
    });

    test('a conflict is kept, and shown till looked at', () {
      final r = payment();
      a2.clientsMerge(a.clientsExport());
      final p = ask(r, {'tutar': 1250000});
      as(a, 'deniz', 'deniz').decide(p.id, approve: true);
      a2.clientsMerge(a.clientsExport());
      as(a2, 'deniz', 'a2').lost();
      // Changed again on a2 after the decision's change came.
      PortalDatabase.clientPerson = () => 'deniz';
      LedgerService(a2).edit(
        a2.clientRecord(r.id)!,
        amount: 1300000,
        at: DateTime(2026, 10, 10),
        debtor: '',
        way: '',
        note: '',
        whole: false,
        target: null,
      );
      as(a2, 'deniz', 'a2').ownMerge(as(a, 'deniz', 'deniz').ownExport());
      final d = a2.decisionOf(p.id)!;
      expect((d.void_, d.conflict), (true, true));
      expect(a2.clientRecord(r.id)!.amount, 1300000);
      expect(as(a2, 'deniz', 'a2').conflicts, isNotEmpty);
      a2.clearDecisionConflict(p.id);
      expect(as(a2, 'deniz', 'a2').conflicts, isEmpty);
    });

    test('made seeing what was shown: changed since, it is old', () {
      final r = payment();
      final shown = ProposalService.versionsOf(b, 'icra', r.id);
      PortalDatabase.clientPerson = () => 'deniz';
      LedgerService(a)
          .setReported(a.clientRecord(r.id)!, DateTime(2026, 10, 12));
      b.clientsMerge(a.clientsExport());
      final p = as(
        b,
        'selin',
        'b1',
      ).propose(kind: 'icra', target: r.id, fields: {'tutar': 1}, seen: shown)!;
      send(b, 'selin', a, 'deniz');
      expect(as(a, 'deniz', 'deniz').current(p), isFalse);
    });

    test('a device whose keys are not kept never decides', () {
      final s = ProposalService(a, me: 'deniz', device: 'deniz', kept: false);
      expect(s.decidesHere, isFalse);
      expect(s.lost(), isNull);
    });
  });
}

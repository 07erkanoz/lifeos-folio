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
    final second = as(a2, 'deniz', 'a2').lost();
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
}

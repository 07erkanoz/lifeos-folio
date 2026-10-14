import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/clients/client_accounts.dart';
import 'package:evrak_convert/services/clients/office_cash.dart';
import 'package:evrak_convert/services/enforcement/ledger_book.dart';
import 'package:evrak_convert/services/enforcement/ledger_service.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/sync/hlc.dart';
import 'package:evrak_convert/services/sync/sync_migration.dart';
import 'package:evrak_convert/ui/clients/client_accounts_view.dart'
    show appliedMovement, ledgerApply, ledgerTakeBack;
import 'package:flutter_test/flutter_test.dart';

/// docs/senkron-plan.md §5 step 4: an enforcement payment's money made of
/// its record, the same on every device, whatever came first (R1, R3, R5,
/// R12).
void main() {
  late PortalDatabase a, b;
  late DateTime wall;
  setUp(() {
    a = PortalDatabase.memory();
    b = PortalDatabase.memory();
    wall = DateTime.utc(2026, 10, 14, 9);
  });
  tearDown(() {
    a.dispose();
    b.dispose();
  });

  LedgerService book(PortalDatabase db, String device) => LedgerService(
    db,
    clock: HlcClock(source: '$device:0', now: () => wall),
  );

  /// [from]'s records, taken by [to] as Senkron takes them.
  bool send(PortalDatabase from, PortalDatabase to) =>
      to.clientsMerge(from.clientsExport());

  ClientRecord pay(LedgerService on, {int lira = 100, MovementKind? target}) =>
      on.add(
        clientId: 'k1',
        caseKey: 'dosya',
        kind: 'haricen',
        amount: lira * 100,
        at: DateTime(2026, 10, 10),
        by: 'Av. Deniz Kaya',
        person: 'deniz',
        debtor: 'Mehmet Tunç',
        target: target,
      );

  CaseAccount? account(PortalDatabase db) =>
      caseAccounts(db.allClientRecords())['dosya'];

  List<String> legs(PortalDatabase db) => [
    for (final r in db.allClientRecords())
      if (LedgerBook.isProjected(r)) '${r.id}=${r.amount}',
  ]..sort();

  group('the record (R1)', () {
    test('what each device changed of it stands: the note on one, the '
        'office told on the other', () {
      final first = pay(book(a, 'a'));
      send(a, b);
      wall = wall.add(const Duration(minutes: 1));
      book(a, 'a').edit(
        a.clientRecord(first.id)!,
        amount: 10000,
        at: DateTime(2026, 10, 10),
        debtor: 'Mehmet Tunç',
        way: '',
        note: 'Elden, makbuzlu',
        whole: false,
        target: null,
      );
      book(
        b,
        'b',
      ).setReported(b.clientRecord(first.id)!, DateTime(2026, 10, 12));
      send(a, b);
      send(b, a);
      for (final db in [a, b]) {
        final r = db.clientRecord(first.id)!;
        expect(r.text('aciklama'), 'Elden, makbuzlu');
        expect(r.text('bildirildi'), isNotEmpty);
      }
    });

    test('two sums made at once: the same one wins on both, whichever came '
        'first, and the money is that one alone', () {
      final first = pay(book(a, 'a'));
      send(a, b);
      wall = wall.add(const Duration(minutes: 1));
      void change(PortalDatabase db, String device, int lira) =>
          book(db, device).edit(
            db.clientRecord(first.id)!,
            amount: lira * 100,
            at: DateTime(2026, 10, 10),
            debtor: 'Mehmet Tunç',
            way: '',
            note: '',
            whole: false,
            target: null,
          );
      change(a, 'a', 120);
      change(b, 'b', 130);
      send(a, b);
      send(b, a);
      expect(
        a.clientRecord(first.id)!.amount,
        b.clientRecord(first.id)!.amount,
      );
      expect(legs(a), legs(b));
      expect(legs(a), hasLength(1), reason: 'one held, no second');
      expect(account(a)!.advanceLeft, a.clientRecord(first.id)!.amount);
    });
  });

  group('the set-offs (R3)', () {
    test('two set-offs made apart past what is held: the earlier is in '
        'effect, the other waits, on both alike', () {
      final first = pay(book(a, 'a'));
      send(a, b);
      book(a, 'a').addSetOff(
        first.id,
        MovementKind.toFee,
        6000,
        seen: LedgerBook.tokenOf(a.clientRecord(first.id)!),
      );
      wall = wall.add(const Duration(seconds: 1));
      book(b, 'b').addSetOff(
        first.id,
        MovementKind.toFee,
        6000,
        seen: LedgerBook.tokenOf(b.clientRecord(first.id)!),
      );
      // Each order of coming.
      send(b, a);
      send(a, b);
      for (final db in [a, b]) {
        final state = LedgerBook.stateOf(db.clientRecord(first.id)!);
        expect(state.active, hasLength(1));
        expect(state.waiting, hasLength(1));
        expect(account(db)!.feeIn, 6000);
        expect(account(db)!.advanceLeft, 4000);
      }
      expect(legs(a), legs(b));
      // In Kasa, as in the account.
      for (final db in [a, b]) {
        final totals = cashTotals(cashLines(db));
        expect(totals.income, 6000);
      }
    });

    test('a sum made smaller than a set-off made apart: the set-off waits; '
        'the sum made whole again, it is in effect', () {
      final first = pay(book(a, 'a'));
      send(a, b);
      wall = wall.add(const Duration(minutes: 1));
      book(a, 'a').edit(
        a.clientRecord(first.id)!,
        amount: 5000,
        at: DateTime(2026, 10, 10),
        debtor: 'Mehmet Tunç',
        way: '',
        note: '',
        whole: false,
        target: null,
      );
      book(b, 'b').addSetOff(
        first.id,
        MovementKind.toFee,
        8000,
        seen: LedgerBook.tokenOf(b.clientRecord(first.id)!),
      );
      send(a, b);
      send(b, a);
      for (final db in [a, b]) {
        final state = LedgerBook.stateOf(db.clientRecord(first.id)!);
        expect(state.held, 5000);
        expect(state.active, isEmpty);
        expect(state.waiting.single.amount, 8000);
        expect(account(db)!.feeIn, 0);
      }
      wall = wall.add(const Duration(minutes: 1));
      book(a, 'a').edit(
        a.clientRecord(first.id)!,
        amount: 10000,
        at: DateTime(2026, 10, 10),
        debtor: 'Mehmet Tunç',
        way: '',
        note: '',
        whole: false,
        target: null,
      );
      expect(
        LedgerBook.stateOf(a.clientRecord(first.id)!).active,
        hasLength(1),
      );
      expect(account(a)!.feeIn, 8000);
    });

    test('taken off and put back, what was held and set off comes back, by '
        'the same ids, with no reversal written', () {
      final first = pay(book(a, 'a'), target: MovementKind.toFee, lira: 100);
      final before = legs(a);
      expect(before, hasLength(2));
      wall = wall.add(const Duration(minutes: 1));
      book(a, 'a').setRemoved(a.clientRecord(first.id)!, true);
      expect(legs(a), isEmpty);
      expect(account(a), isNull);
      wall = wall.add(const Duration(minutes: 1));
      book(a, 'a').setRemoved(a.clientRecord(first.id)!, false);
      expect(legs(a), before);
      expect(
        a.allClientRecords().where((r) => r.text('ters').isNotEmpty),
        isEmpty,
      );
    });

    test('of two set-offs seen in other orders, the first taken off: the '
        'second is in effect on both, by the same id', () {
      final first = pay(book(a, 'a'));
      send(a, b);
      final m1 = book(a, 'a').addSetOff(
        first.id,
        MovementKind.toFee,
        6000,
        seen: LedgerBook.tokenOf(a.clientRecord(first.id)!),
      );
      wall = wall.add(const Duration(seconds: 1));
      book(b, 'b').addSetOff(
        first.id,
        MovementKind.toFee,
        6000,
        seen: LedgerBook.tokenOf(b.clientRecord(first.id)!),
      );
      // A sees the second only after its own; B sees both at once.
      send(b, a);
      send(a, b);
      final firstSetOff = LedgerBook.setOffsOf(m1).single.id;
      wall = wall.add(const Duration(minutes: 1));
      book(a, 'a').removeSetOff(
        first.id,
        firstSetOff,
        seen: LedgerBook.tokenOf(a.clientRecord(first.id)!),
      );
      send(a, b);
      expect(legs(a), legs(b));
      for (final db in [a, b]) {
        final state = LedgerBook.stateOf(db.clientRecord(first.id)!);
        expect(state.active.single.id, isNot(firstSetOff));
        expect(state.waiting, isEmpty);
      }
    });

    test(
      'a part set off from the card stays as it was when the sum is '
      'corrected in the file; only a set-off of the whole follows the sum',
      () {
        final part = pay(book(a, 'a'));
        book(a, 'a').addSetOff(
          part.id,
          MovementKind.toFee,
          4000,
          seen: LedgerBook.tokenOf(a.clientRecord(part.id)!),
        );
        wall = wall.add(const Duration(minutes: 1));
        book(a, 'a').edit(
          a.clientRecord(part.id)!,
          amount: 12000,
          at: DateTime(2026, 10, 10),
          debtor: 'Mehmet Tunç',
          way: '',
          note: '',
          whole: false,
          target: MovementKind.toFee,
          shown: MovementKind.toFee,
        );
        expect(
          LedgerBook.setOffsOf(a.clientRecord(part.id)!).single.amount,
          4000,
        );
        final full = pay(book(a, 'a'), target: MovementKind.toFee);
        wall = wall.add(const Duration(minutes: 1));
        book(a, 'a').edit(
          a.clientRecord(full.id)!,
          amount: 12500,
          at: DateTime(2026, 10, 10),
          debtor: 'Mehmet Tunç',
          way: '',
          note: '',
          whole: false,
          target: MovementKind.toFee,
          shown: MovementKind.toFee,
        );
        expect(
          LedgerBook.setOffsOf(a.clientRecord(full.id)!).single.amount,
          12500,
        );
      },
    );

    test('made again, nothing changes', () {
      final first = pay(book(a, 'a'), target: MovementKind.toFee);
      final once = legs(a);
      a.rebuildLedger(first.id);
      a.rebuildLedger(first.id);
      expect(legs(a), once);
    });
  });

  group('its movements are its own (R3)', () {
    test('they are never sent, nor taken, nor written by hand', () {
      pay(book(a, 'a'), target: MovementKind.toFee);
      final sent = a.clientsExport()['muvekkilKayitlari'] as List;
      expect(sent.cast<Map>().where((r) => r['tur'] == 'hareket'), isEmpty);
      // One forged as another's: not taken.
      final forged = a.allClientRecords().firstWhere(LedgerBook.isProjected);
      b.clientsMerge({
        'muvekkilKayitlari': [forged.toJson()],
      });
      expect(b.allClientRecords(), isEmpty);
      expect(a.saveClientRecord(forged), isFalse);
    });

    test('a set-off from the card goes into the payment\'s record; one past '
        'what is held is refused; taken back, it is held again', () {
      final first = pay(book(a, 'a'));
      final held = a.allClientRecords().singleWhere(LedgerBook.isProjected);
      final via = ledgerApply(
        a,
        held,
        appliedMovement(held, MovementKind.toFee, 4000, lawyer: 'Av. D'),
      );
      expect((via.ledger, via.refused), (true, null));
      expect(LedgerBook.setOffsOf(a.clientRecord(first.id)!), hasLength(1));
      expect(account(a)!.feeIn, 4000);
      final past = ledgerApply(
        a,
        held,
        appliedMovement(held, MovementKind.toFee, 7000, lawyer: 'Av. D'),
      );
      expect(past.refused, isNotNull);
      expect(account(a)!.feeIn, 4000);
      final setOff = a.allClientRecords().singleWhere(
        (r) => LedgerBook.isProjected(r) && r.movement == MovementKind.toFee,
      );
      expect(ledgerTakeBack(a, setOff).refused, isNull);
      expect(account(a)!.feeIn, 0);
      expect(account(a)!.advanceLeft, 10000);
      // What is held is taken off from the file, not reversed here.
      expect(ledgerTakeBack(a, held).refused, isNotNull);
    });

    test('a change from a record shown before another\'s change is refused, '
        'nothing written', () {
      final first = pay(book(a, 'a'));
      final shown = a.clientRecord(first.id)!;
      wall = wall.add(const Duration(minutes: 1));
      book(a, 'a').setReported(shown, DateTime(2026, 10, 12));
      expect(
        () => book(a, 'a').setOfficial(shown, true),
        throwsA(isA<LedgerConflict>()),
      );
      expect(a.clientRecord(first.id)!.text('resmiKarar'), isEmpty);
    });
  });

  group('Kasa takes a line back once (R3)', () {
    test('two reversals of one line, and a reversal of a reversal, take it '
        'back once', () {
      ClientRecord move(String id, {String back = ''}) => ClientRecord(
        id: id,
        clientId: 'k1',
        kind: ClientRecordKind.movement,
        data: {
          'dosya': 'dosya',
          'hesap': MovementKind.feePaid.code,
          'tutar': 10000,
          'zaman': '2026-10-10T10:00:00',
          'ters': ?(back.isEmpty ? null : back),
        },
        created: DateTime(2026, 10, 10, 10, int.parse(id.substring(1))),
        by: 'Av. D',
        updated: DateTime(2026, 10, 10),
        locked: true,
      );
      a.saveClientRecord(move('h1'));
      a.saveClientRecord(move('h2', back: 'h1'));
      a.saveClientRecord(move('h3', back: 'h1'));
      a.saveClientRecord(move('h4', back: 'h2'));
      expect(cashTotals(cashLines(a)).income, 0);
      expect(account(a)!.feeIn, 0);
    });
  });

  group('the migration (R3)', () {
    ClientRecord entry(
      String id, {
      bool removed = false,
      String client = 'k1',
    }) => ClientRecord(
      id: id,
      clientId: client,
      kind: ClientRecordKind.enforcement,
      data: const {
        'dosya': 'dosya',
        'tur': 'haricen',
        'tutar': 10000,
        'zaman': '2026-10-10T00:00:00',
      },
      created: DateTime(2026, 10, 10),
      by: 'Av. D',
      updated: DateTime(2026, 10, 10),
      removed: removed,
    );
    ClientRecord old(
      String id,
      String source,
      MovementKind kind,
      int amount, {
      String back = '',
    }) => ClientRecord(
      id: id,
      clientId: 'k1',
      kind: ClientRecordKind.movement,
      data: {
        'dosya': 'dosya',
        'hesap': kind.code,
        'tutar': amount,
        'zaman': '2026-10-10T00:00:00',
        'kaynak': source,
        'ters': ?(back.isEmpty ? null : back),
      },
      created: DateTime(2026, 10, 10, 1),
      by: 'Av. D',
      updated: DateTime(2026, 10, 10, 1),
      locked: true,
    );

    test('old movements alike with their record give way to its movements: '
        'no total changes, a part set off kept', () {
      a.saveClientRecord(entry('e1'));
      a.putRecordForTesting(old('h', 'icra:e1', MovementKind.collected, 10000));
      a.putRecordForTesting(old('f', 'mahsup:h', MovementKind.toFee, 4000));
      final before = (account(a)!.feeIn, account(a)!.advanceLeft);
      final cash = cashTotals(cashLines(a)).income;
      a.migrateLedgers();
      expect((account(a)!.feeIn, account(a)!.advanceLeft), before);
      expect(cashTotals(cashLines(a)).income, cash);
      expect(a.ledgerRepairs, isEmpty);
      final r = a.clientRecord('e1')!;
      expect(LedgerBook.setOffsOf(r).single.amount, 4000);
      expect(legs(a), ['icra:e1:emanet=10000', 'icra:e1:mahsup:f=4000']);
      // The old ones are moved aside, and never taken back from another.
      expect(a.clientRecord('h'), isNull);
      a.clientsMerge({
        'muvekkilKayitlari': [
          old('h', 'icra:e1', MovementKind.collected, 10000).toJson(),
        ],
      });
      expect(account(a)!.advanceLeft, before.$2);
      // Run again: nothing changes.
      a.migrateLedgers();
      expect(legs(a), ['icra:e1:emanet=10000', 'icra:e1:mahsup:f=4000']);
    });

    test('old movements not alike wait for the lawyer\'s word: booked twice, '
        'a reversal reversed, money of a payment taken off', () {
      a.saveClientRecord(entry('twice'));
      a.putRecordForTesting(
        old('t1', 'icra:twice', MovementKind.collected, 10000),
      );
      a.putRecordForTesting(
        old('t2', 'icra:twice', MovementKind.collected, 10000),
      );
      a.saveClientRecord(entry('again'));
      a.putRecordForTesting(
        old('g1', 'icra:again', MovementKind.collected, 10000),
      );
      a.putRecordForTesting(
        old('g2', 'icra:again', MovementKind.collected, 10000, back: 'g1'),
      );
      a.putRecordForTesting(
        old('g3', 'icra:again', MovementKind.collected, 10000, back: 'g2'),
      );
      a.saveClientRecord(entry('gone', removed: true));
      a.putRecordForTesting(
        old('o1', 'icra:gone', MovementKind.collected, 10000),
      );
      final before = account(a)!.advanceLeft;
      a.migrateLedgers();
      expect(a.ledgerRepairs.toSet(), {'twice', 'again', 'gone'});
      // Nothing mended unseen: the money as it was.
      expect(account(a)!.advanceLeft, before);
      expect(legs(a), isEmpty);
      // The lawyer's word on one, as the report showed it.
      final report = a.ledgerRepairOf('twice')!;
      expect(report['neden'], contains('2 kez'));
      expect(a.resolveLedgerRepair('twice', 'baska'), isFalse);
      expect(a.resolveLedgerRepair('twice', report['ozet'] as String), isTrue);
      expect(a.ledgerRepairs.toSet(), {'again', 'gone'});
      expect(legs(a), ['icra:twice:emanet=10000']);
      expect(a.clientRecord('t1'), isNull);
      expect(a.clientRecord('t2'), isNull);
    });

    test('the migration is a step of the schema: run as the database opens, '
        'once', () {
      a.saveClientRecord(entry('e1'));
      a.putRecordForTesting(old('h', 'icra:e1', MovementKind.collected, 10000));
      // In its old form, the record makes no movement of its own beside its
      // old ones.
      expect(legs(a), isEmpty);
      expect(account(a)!.advanceLeft, 10000);
      expect(SyncMigration.run(a), isTrue);
      expect(SyncMigration.schemaOf(a), 2);
      expect(legs(a), ['icra:e1:emanet=10000']);
      expect(account(a)!.advanceLeft, 10000);
      expect(SyncMigration.run(a), isFalse);
    });
  });

  group('Codex\'s review of step 4', () {
    ClientRecord entry(String id, {String dosya = 'dosya'}) => ClientRecord(
      id: id,
      clientId: 'k1',
      kind: ClientRecordKind.enforcement,
      data: {
        'dosya': dosya,
        'tur': 'haricen',
        'tutar': 10000,
        'zaman': '2026-10-10T00:00:00',
      },
      created: DateTime(2026, 10, 10),
      by: 'Av. D',
      updated: DateTime(2026, 10, 10),
    );
    ClientRecord held(String id, String entryId, {String dosya = 'dosya'}) =>
        ClientRecord(
          id: id,
          clientId: 'k1',
          kind: ClientRecordKind.movement,
          data: {
            'dosya': dosya,
            'hesap': MovementKind.collected.code,
            'tutar': 10000,
            'zaman': '2026-10-10T00:00:00',
            'kaynak': 'icra:$entryId',
          },
          created: DateTime(2026, 10, 10, 1),
          by: 'Av. D',
          updated: DateTime(2026, 10, 10, 1),
          locked: true,
        );

    test('a change made after a version from a clock ahead comes after it, '
        'and is not lost at the next keeping alike', () {
      final ahead = wall.add(const Duration(days: 1));
      final first =
          LedgerService(
            a,
            clock: HlcClock(source: 'a:0', now: () => ahead),
          ).add(
            clientId: 'k1',
            caseKey: 'dosya',
            kind: 'haricen',
            amount: 10000,
            at: DateTime(2026, 10, 10),
            by: 'Av. D',
          );
      send(a, b);
      // B's own clock, the database's: it has seen A's version.
      LedgerService(b).edit(
        b.clientRecord(first.id)!,
        amount: 15000,
        at: DateTime(2026, 10, 10),
        debtor: '',
        way: '',
        note: '',
        whole: false,
        target: null,
      );
      send(b, a);
      expect(a.clientRecord(first.id)!.amount, 15000);
    });

    test('a colleague\'s ledger is changed by no path of this device\'s', () {
      final person = PortalDatabase.clientPerson;
      addTearDown(() => PortalDatabase.clientPerson = person);
      final first = pay(book(a, 'a'));
      PortalDatabase.clientPerson = () => 'selin';
      expect(
        () =>
            book(a, 'a').setReported(a.clientRecord(first.id)!, DateTime.now()),
        throwsA(isA<LedgerNotYours>()),
      );
      final heldMove = a.allClientRecords().singleWhere(LedgerBook.isProjected);
      final via = ledgerApply(
        a,
        heldMove,
        appliedMovement(heldMove, MovementKind.toFee, 4000, lawyer: 'Av. S'),
      );
      expect(via.refused, isNotNull);
      expect(LedgerBook.setOffsOf(a.clientRecord(first.id)!), isEmpty);
    });

    test('the migration run again leaves a ledger it made as it is', () {
      a.saveClientRecord(entry('e1'));
      a.putRecordForTesting(held('h', 'e1'));
      a.migrateLedgers();
      final legsOnce = legs(a);
      final recordOnce = a.clientRecord('e1')!.toJson();
      a.migrateLedgers();
      expect(a.ledgerRepairs, isEmpty);
      expect(legs(a), legsOnce);
      expect(a.clientRecord('e1')!.toJson(), recordOnce);
    });

    test('a movement of another case is not taken for the ledger\'s', () {
      a.saveClientRecord(entry('e1'));
      a.putRecordForTesting(held('h', 'e1', dosya: 'baska'));
      a.migrateLedgers();
      expect(a.ledgerRepairOf('e1')!['neden'], contains('başka'));
    });

    test('a repair agreed to for what has changed since is not made: the '
        'report is made anew', () {
      a.saveClientRecord(entry('e1'));
      a.putRecordForTesting(held('h1', 'e1'));
      a.putRecordForTesting(held('h2', 'e1'));
      a.migrateLedgers();
      final shown = a.ledgerRepairOf('e1')!['ozet'] as String;
      a.putRecordForTesting(held('h3', 'e1'));
      expect(a.resolveLedgerRepair('e1', shown), isFalse);
      final anew = a.ledgerRepairOf('e1')!;
      expect(anew['ozet'], isNot(shown));
      expect(anew['kimlikler'], contains('h3'));
      expect(a.resolveLedgerRepair('e1', anew['ozet'] as String), isTrue);
      expect(legs(a), ['icra:e1:emanet=10000']);
      expect(account(a)!.advanceLeft, 10000);
    });

    test('a ledger in its old form from another device is weighed here: its '
        'money neither lost nor counted twice', () {
      b.saveClientRecord(entry('e1'));
      b.putRecordForTesting(held('h', 'e1'));
      a.clientsMerge(b.clientsExport());
      expect(account(a)!.advanceLeft, 10000);
      expect(legs(a), ['icra:e1:emanet=10000']);
      expect(a.clientRecord('h'), isNull, reason: 'moved aside');
    });

    test('the old movements moved aside are known to the other devices: '
        'they are not taken back from an older one', () {
      a.saveClientRecord(entry('e1'));
      a.putRecordForTesting(held('h', 'e1'));
      a.migrateLedgers();
      send(a, b);
      b.clientsMerge({
        'muvekkilKayitlari': [held('h', 'e1').toJson()],
      });
      expect(b.clientRecord('h'), isNull);
      expect(account(b)!.advanceLeft, 10000);
    });

    test('a reversal of a movement made of a ledger is taken by no path', () {
      pay(book(a, 'a'));
      final move = a.allClientRecords().singleWhere(LedgerBook.isProjected);
      final back = ClientRecord(
        id: 'r1',
        clientId: 'k1',
        kind: ClientRecordKind.movement,
        data: {...move.data, 'ters': move.id}..remove('turetilmis'),
        created: DateTime.now(),
        by: 'Av. D',
        updated: DateTime.now(),
        locked: true,
      );
      expect(a.saveClientRecord(back), isFalse);
      a.clientsMerge({
        'muvekkilKayitlari': [back.toJson()],
      });
      expect(a.clientRecord('r1'), isNull);
      expect(account(a)!.advanceLeft, 10000);
    });

    test('a set-off from a movement shown before the record changed is '
        'refused', () {
      final first = pay(book(a, 'a'));
      final shown = a.allClientRecords().singleWhere(LedgerBook.isProjected);
      wall = wall.add(const Duration(minutes: 1));
      book(a, 'a').setReported(a.clientRecord(first.id)!, DateTime.now());
      final via = ledgerApply(
        a,
        shown,
        appliedMovement(shown, MovementKind.toFee, 4000, lawyer: 'Av. D'),
      );
      expect(via.refused, isNotNull);
      expect(LedgerBook.setOffsOf(a.clientRecord(first.id)!), isEmpty);
    });

    test('the lawyer\'s word that UYAP has it is for the sum it had', () {
      final first = pay(book(a, 'a'));
      wall = wall.add(const Duration(minutes: 1));
      book(a, 'a').setOfficial(a.clientRecord(first.id)!, true);
      expect(LedgerBook.officialByHand(a.clientRecord(first.id)!), isTrue);
      wall = wall.add(const Duration(minutes: 1));
      book(a, 'a').edit(
        a.clientRecord(first.id)!,
        amount: 12000,
        at: DateTime(2026, 10, 10),
        debtor: 'Mehmet Tunç',
        way: '',
        note: '',
        whole: false,
        target: null,
      );
      expect(LedgerBook.officialByHand(a.clientRecord(first.id)!), isFalse);
    });

    test(
      'each change is in the ledger\'s history: what, by whom, from where',
      () {
        final first = pay(book(a, 'a'));
        wall = wall.add(const Duration(minutes: 1));
        book(a, 'a').setReported(a.clientRecord(first.id)!, DateTime.now());
        final lines = a.ledgerHistory(first.id);
        expect([for (final l in lines) l['islem']], ['ekle', 'bildirildi']);
        expect(lines.last['kaynak'], 'a:0');
        expect(lines.last['eski'], isNotNull);
      },
    );
  });
}

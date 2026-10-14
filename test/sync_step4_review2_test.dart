import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/clients/client_accounts.dart';
import 'package:evrak_convert/services/enforcement/ledger_book.dart';
import 'package:evrak_convert/services/enforcement/ledger_service.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/sync/hlc.dart';
import 'package:evrak_convert/ui/clients/client_accounts_view.dart'
    show appliedMovement, ledgerApply, ledgerTakeBack;
import 'package:flutter_test/flutter_test.dart';

/// docs/senkron-plan.md §5 step 4, Codex's second review: an older Folio's
/// ledgers made new only by weighing them, never twice; nothing acts on
/// their old movements but the repair, and only its writer mends it.
void main() {
  late PortalDatabase a, b;
  setUp(() {
    a = PortalDatabase.memory();
    b = PortalDatabase.memory();
  });
  tearDown(() {
    a.dispose();
    b.dispose();
  });

  ClientRecord entry(
    String id, {
    Map<String, Object?> also = const {},
    String person = '',
    DateTime? updated,
  }) => ClientRecord(
    id: id,
    clientId: 'k1',
    kind: ClientRecordKind.enforcement,
    data: {
      'dosya': 'dosya',
      'tur': 'haricen',
      'tutar': 10000,
      'zaman': '2026-10-10T00:00:00',
      ...also,
    },
    created: DateTime(2026, 10, 10),
    by: 'Av. D',
    updated: updated ?? DateTime(2026, 10, 10),
    person: person,
  );
  ClientRecord old(
    String id,
    String source,
    MovementKind kind,
    int amount, {
    String back = '',
    String person = '',
    String dosya = 'dosya',
  }) => ClientRecord(
    id: id,
    clientId: 'k1',
    kind: ClientRecordKind.movement,
    data: {
      'dosya': dosya,
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
    person: person,
  );

  CaseAccount? account(PortalDatabase db) =>
      caseAccounts(db.allClientRecords())['dosya'];

  test('two copies of a ledger in its old form, merged, are weighed: the '
      'money counted once, not as its old movement and its projection', () {
    for (final db in [a, b]) {
      db.putRecordForTesting(entry('e'));
      db.putRecordForTesting(old('h', 'icra:e', MovementKind.collected, 10000));
    }
    b.putRecordForTesting(entry('e', updated: DateTime(2026, 10, 11)));
    a.clientsMerge(b.clientsExport());
    expect(account(a)!.advanceLeft, 10000);
    expect(a.clientRecord('h'), isNull, reason: 'moved aside, weighed');
    expect(LedgerBook.isNewForm(a.clientRecord('e')!), isTrue);
  });

  test('a map of old movements that comes takes the one kept here out of '
      'the account once its ledger is here in its new form', () {
    a.putRecordForTesting(entry('e'));
    a.putRecordForTesting(old('h', 'icra:e', MovementKind.collected, 10000));
    a.migrateLedgers();
    // B kept the old movement, its ledger in a repair it never made.
    b.putRecordForTesting(old('h', 'icra:e', MovementKind.collected, 10000));
    b.clientsMerge(a.clientsExport());
    expect(b.clientRecord('h'), isNull);
    expect(account(b)!.advanceLeft, 10000);
    expect(b.ledgerHistory('e'), isNotEmpty);
  });

  test('an old movement of a ledger waiting for its repair is neither set '
      'off nor taken back, so that no part comes late', () {
    a.putRecordForTesting(entry('e'));
    a.putRecordForTesting(old('h', 'icra:e', MovementKind.collected, 10000));
    a.putRecordForTesting(old('h2', 'icra:e', MovementKind.collected, 10000));
    a.migrateLedgers();
    expect(a.ledgerRepairs, ['e']);
    final h = a.clientRecord('h')!;
    final made = appliedMovement(h, MovementKind.toFee, 4000, lawyer: 'Av. D');
    expect(ledgerApply(a, h, made).refused, isNotNull);
    expect(a.saveClientRecord(made), isFalse);
    expect(ledgerTakeBack(a, h).refused, isNotNull);
  });

  test('only its writer mends a ledger; a colleague\'s report is not this '
      'person\'s to resolve', () {
    final person = PortalDatabase.clientPerson;
    addTearDown(() => PortalDatabase.clientPerson = person);
    a.putRecordForTesting(entry('e', person: 'deniz'));
    for (final id in ['h', 'h2']) {
      a.putRecordForTesting(
        old(id, 'icra:e', MovementKind.collected, 10000, person: 'deniz'),
      );
    }
    a.migrateLedgers();
    final digest = '${a.ledgerRepairOf('e')!['ozet']}';
    PortalDatabase.clientPerson = () => 'selin';
    expect(a.resolveLedgerRepair('e', digest), isFalse);
    expect(a.ledgerRepairs, ['e']);
    PortalDatabase.clientPerson = () => 'deniz';
    expect(a.resolveLedgerRepair('e', digest), isTrue);
    expect(a.ledgerHistory('e').last['islem'], 'onar');
  });

  test('the lawyer\'s word that UYAP has it comes with the sum it was given '
      'for: on every device the same, gone on both when the sum changes', () {
    final made =
        LedgerService(
          a,
          clock: HlcClock(source: 'a:0', now: () => DateTime.utc(2026, 10, 14)),
        ).add(
          clientId: 'k1',
          caseKey: 'dosya',
          kind: 'haricen',
          amount: 10000,
          at: DateTime(2026, 10, 10),
          by: 'Av. D',
        );
    b.clientsMerge(a.clientsExport());
    LedgerService(
      a,
      clock: HlcClock(source: 'a:0', now: () => DateTime.utc(2026, 10, 15)),
    ).setOfficial(a.clientRecord(made.id)!, true);
    b.clientsMerge(a.clientsExport());
    expect(LedgerBook.officialByHand(b.clientRecord(made.id)!), isTrue);
    LedgerService(
      b,
      clock: HlcClock(source: 'b:0', now: () => DateTime.utc(2026, 10, 16)),
    ).edit(
      b.clientRecord(made.id)!,
      amount: 12000,
      at: DateTime(2026, 10, 10),
      debtor: '',
      way: '',
      note: '',
      whole: false,
      target: null,
    );
    a.clientsMerge(b.clientsExport());
    for (final db in [a, b]) {
      expect(LedgerBook.officialByHand(db.clientRecord(made.id)!), isFalse);
    }
    // An older Folio's word is bound in the migration: it stands for the
    // sum it has, and goes with a change of it.
    final c = PortalDatabase.memory();
    addTearDown(c.dispose);
    c.putRecordForTesting(entry('o', also: const {'resmi': 'elle'}));
    c.putRecordForTesting(old('ho', 'icra:o', MovementKind.collected, 10000));
    c.migrateLedgers();
    final bound = c.clientRecord('o')!;
    expect(bound.text('resmiKararSurum'), isNotEmpty);
    expect(LedgerBook.officialByHand(bound), isTrue);
  });

  test('a reversal of a reversal, all the way down, is in the report and '
      'its digest; one of another kind than what it takes back is too', () {
    a.putRecordForTesting(entry('e'));
    a.putRecordForTesting(old('h', 'icra:e', MovementKind.collected, 10000));
    a.putRecordForTesting(
      old('r1', 'icra:e', MovementKind.collected, 10000, back: 'h'),
    );
    a.putRecordForTesting(
      old('r2', 'icra:e', MovementKind.collected, 10000, back: 'r1'),
    );
    a.migrateLedgers();
    expect(a.ledgerRepairOf('e')!['kimlikler'], containsAll(['r1', 'r2']));
    final c = PortalDatabase.memory();
    addTearDown(c.dispose);
    c.putRecordForTesting(entry('e', also: const {'tur': 'feragat'}));
    c.putRecordForTesting(old('h', 'icra:e', MovementKind.collected, 10000));
    c.putRecordForTesting(
      old('r', 'icra:e', MovementKind.feePaid, 10000, back: 'h'),
    );
    c.migrateLedgers();
    expect('${c.ledgerRepairOf('e')!['neden']}', contains('türünden farklı'));
  });

  test('from the office: the map of its writer\'s ledgers is taken, a '
      'reversal of another case is refused, and a client unshared leaves '
      'nothing of others behind', () {
    for (final db in [a, b]) {
      db.saveClient(
        Client(
          id: 'k1',
          name: 'Ayşe Karaca',
          updated: DateTime(2026, 10, 1),
          person: 'deniz',
        ).copyWith(office: true),
      );
    }
    a.putRecordForTesting(entry('e', person: 'deniz'));
    a.putRecordForTesting(
      old('h', 'icra:e', MovementKind.collected, 10000, person: 'deniz'),
    );
    a.migrateLedgers();
    b.putRecordForTesting(
      old('h', 'icra:e', MovementKind.collected, 10000, person: 'deniz'),
    );
    b.clientsOfficeMerge(
      a.clientsOfficeExport(money: true, me: 'deniz'),
      money: true,
      me: 'selin',
      from: 'deniz',
    );
    expect(b.clientRecord('h'), isNull);
    expect(account(b)!.advanceLeft, 10000);
    // A reversal naming a movement of another case.
    a.putRecordForTesting(
      old('p', '', MovementKind.feePaid, 5000, person: 'deniz', dosya: 'baska'),
    );
    b.clientsOfficeMerge(
      a.clientsOfficeExport(money: true, me: 'deniz'),
      money: true,
      me: 'selin',
      from: 'deniz',
    );
    b.clientsOfficeMerge(
      {
        'muvekkiller': const [],
        'muvekkilKayitlari': [
          {
            ...old(
              'rp',
              '',
              MovementKind.feePaid,
              5000,
              back: 'p',
              person: 'deniz',
            ).toJson(),
            'kisi': 'deniz',
          },
        ],
      },
      money: true,
      me: 'selin',
      from: 'deniz',
    );
    expect(b.clientRecord('rp'), isNull);
    // Unshared: the ledger's history and projection go with it.
    a.saveClient(a.clientCard('k1')!.copyWith(office: false));
    b.clientsOfficeMerge(
      a.clientsOfficeExport(money: true, me: 'deniz'),
      money: true,
      me: 'selin',
      from: 'deniz',
    );
    expect(b.clientRecord('e'), isNull);
    expect(b.ledgerHistory('e'), isEmpty);
    expect(account(b), isNull);
  });
}

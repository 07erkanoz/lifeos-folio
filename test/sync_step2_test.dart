import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/clients/client_accounts.dart';
import 'package:evrak_convert/services/enforcement/enforcement_ledger.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// docs/senkron-plan.md §5 step 2: today's gaps closed. An enforcement
/// file's account is money (R11); a member's movement acts only on its own
/// (R6); looking at a file writes nothing (R4).
void main() {
  late PortalDatabase mine, theirs;
  setUp(() {
    mine = PortalDatabase.memory();
    theirs = PortalDatabase.memory();
  });
  tearDown(() {
    mine.dispose();
    theirs.dispose();
  });

  Client card(String id) => Client(
    id: id,
    name: 'Ayşe Karaca',
    updated: DateTime(2026, 10, 1),
    person: 'deniz',
  ).copyWith(office: true);

  ClientRecord record(
    String id,
    ClientRecordKind kind, {
    String client = 'k1',
    String person = 'deniz',
    Map<String, Object?> data = const {},
    bool locked = false,
  }) => ClientRecord(
    id: id,
    clientId: client,
    kind: kind,
    data: {'dosya': 'a', 'tutar': 10000, ...data},
    created: DateTime(2026, 10, 2),
    by: 'Av. Deniz Kaya',
    updated: DateTime(2026, 10, 2),
    person: person,
    locked: locked,
  );

  group('an enforcement file\'s account is money (R11)', () {
    test('it goes to no member who may not see the money, and is taken '
        'from none', () {
      mine.saveClient(card('k1'));
      mine.saveClientRecord(record('i1', ClientRecordKind.enforcement));
      mine.saveClientRecord(record('g1', ClientRecordKind.meeting));
      final none = mine.clientsOfficeExport(money: false, me: 'deniz');
      expect(
        [for (final r in none['muvekkilKayitlari'] as List) (r as Map)['id']],
        ['g1'],
      );
      // Sent forged all the same: not taken.
      theirs.clientsOfficeMerge(
        mine.clientsOfficeExport(money: true, me: 'deniz'),
        money: false,
        me: 'selin',
        from: 'deniz',
      );
      expect(theirs.clientRecord('g1'), isNotNull);
      expect(theirs.clientRecord('i1'), isNull);
      // To one who may: it goes.
      theirs.clientsOfficeMerge(
        mine.clientsOfficeExport(money: true, me: 'deniz'),
        money: true,
        me: 'selin',
        from: 'deniz',
      );
      expect(theirs.clientRecord('i1'), isNotNull);
    });

    test('let no longer see the money, every money record others wrote is '
        'forgotten: the office\'s cash, bank, papers and enforcement '
        'accounts too; this person\'s own stay', () {
      for (final (id, kind) in [
        ('u', ClientRecordKind.fee),
        ('h', ClientRecordKind.movement),
        ('k', ClientRecordKind.cash),
        ('t', ClientRecordKind.cashRepeat),
        ('b', ClientRecordKind.bank),
        ('d', ClientRecordKind.paper),
        ('i', ClientRecordKind.enforcement),
      ]) {
        theirs.saveClientRecord(record('$id-deniz', kind));
        theirs.saveClientRecord(record('$id-selin', kind, person: 'selin'));
      }
      theirs.saveClientRecord(record('g-deniz', ClientRecordKind.meeting));
      theirs.forgetClientMoney(keepPerson: 'selin');
      final left = {for (final r in theirs.allClientRecords()) r.id};
      expect(left, {
        'u-selin',
        'h-selin',
        'k-selin',
        't-selin',
        'b-selin',
        'd-selin',
        'i-selin',
        'g-deniz',
      });
    });

    test('the accounts are as before: an enforcement line counts in no '
        'total', () {
      expect(ClientRecordKind.enforcement.money, isFalse);
      expect(ClientRecordKind.enforcement.financial, isTrue);
      expect(ClientRecordKind.meeting.financial, isFalse);
    });
  });

  group('a member\'s movement acts only on its own (R6)', () {
    setUp(() {
      theirs.saveClient(card('k1'));
      mine.saveClient(card('k1'));
    });

    Map<String, Object?> from(List<ClientRecord> records) => {
      'muvekkiller': const [],
      'muvekkilKayitlari': [
        for (final r in records) {...r.toJson(), 'kisi': r.person},
      ],
    };

    test('a colleague\'s reversal of the owner\'s movement is refused; '
        'their own is taken', () {
      final owners = record(
        'h1',
        ClientRecordKind.movement,
        data: {'hesap': MovementKind.feePaid.code},
        locked: true,
      );
      theirs.saveClientRecord(owners);
      final selins = record(
        'h2',
        ClientRecordKind.movement,
        person: 'selin',
        data: {'hesap': MovementKind.feePaid.code},
        locked: true,
      );
      theirs.saveClientRecord(selins);
      ClientRecord reversal(String id, String of) => record(
        id,
        ClientRecordKind.movement,
        person: 'selin',
        data: {'hesap': MovementKind.feePaid.code, 'ters': of},
        locked: true,
      );
      theirs.clientsOfficeMerge(
        from([reversal('r1', 'h1'), reversal('r2', 'h2')]),
        money: true,
        me: 'deniz',
        from: 'selin',
      );
      expect(theirs.clientRecord('r1'), isNull, reason: 'the owner\'s');
      expect(theirs.clientRecord('r2'), isNotNull, reason: 'her own');
      // A set-off and a booking of the owner's are refused alike.
      theirs.clientsOfficeMerge(
        from([
          record(
            's1',
            ClientRecordKind.movement,
            person: 'selin',
            data: {'kaynak': 'mahsup:h1'},
            locked: true,
          ),
        ]),
        money: true,
        me: 'deniz',
        from: 'selin',
      );
      expect(theirs.clientRecord('s1'), isNull);
    });

    test('one whose other has not come yet waits apart, in no total, and is '
        'taken in when it comes', () {
      ClientRecord paid(String id) => record(
        id,
        ClientRecordKind.movement,
        person: 'selin',
        data: {'hesap': MovementKind.feePaid.code},
        locked: true,
      );
      final back = record(
        'r3',
        ClientRecordKind.movement,
        person: 'selin',
        data: {'hesap': MovementKind.feePaid.code, 'ters': 'h3'},
        locked: true,
      );
      // The reversal comes before what it takes back.
      theirs.clientsOfficeMerge(
        from([back]),
        money: true,
        me: 'deniz',
        from: 'selin',
      );
      expect(theirs.clientRecord('r3'), isNull);
      expect(theirs.waitingRecords, 1);
      // Then what it takes back: both in, the reversal no longer waiting.
      theirs.clientsOfficeMerge(
        from([paid('h3')]),
        money: true,
        me: 'deniz',
        from: 'selin',
      );
      expect(theirs.clientRecord('h3'), isNotNull);
      expect(theirs.clientRecord('r3'), isNotNull);
      expect(theirs.waitingRecords, 0);
      // One that waits for another's is dropped when that comes.
      theirs.clientsOfficeMerge(
        from([
          record(
            'r4',
            ClientRecordKind.movement,
            person: 'selin',
            data: {'ters': 'h4'},
            locked: true,
          ),
        ]),
        money: true,
        me: 'deniz',
        from: 'selin',
      );
      expect(theirs.waitingRecords, 1);
      theirs.saveClientRecord(
        record('h4', ClientRecordKind.movement, locked: true),
      );
      theirs.clientsOfficeMerge(
        from(const []),
        money: true,
        me: 'deniz',
        from: 'selin',
      );
      expect(theirs.waitingRecords, 0);
      expect(theirs.clientRecord('r4'), isNull);
    });
  });

  group('looking at a file writes nothing (R4)', () {
    test('what UYAP shows is worked out each time; the lawyer\'s word is '
        'kept apart', () {
      mine.saveClientRecord(
        record(
          'e1',
          ClientRecordKind.enforcement,
          data: {'tur': 'haricen', 'zaman': '2026-10-10T10:00:00'},
        ),
      );
      final before = mine.clientRecord('e1')!.toJson();
      const shown = [
        UyapMoneyItem(
          kind: 'Haricen Tahsilat',
          date: '14.10.2026',
          amount: 100,
          receipt: 'M-9',
        ),
      ];
      DateTime? day(String raw) {
        final p = raw.split('.');
        return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      }

      final seen = ledgerOf(mine, 'a', collections: shown, parse: day);
      expect(seen.single.official, 'makbuz:M-9');
      // Nothing was written for it.
      expect(mine.clientRecord('e1')!.toJson(), before);
      expect(ledgerOf(mine, 'a').single.isOfficial, isFalse);
      // A key an older Folio kept is not taken for the lawyer's word.
      mine.saveClientRecord(
        mine
            .clientRecord('e1')!
            .copyWith(data: {...before['veri'] as Map, 'resmi': 'makbuz:X'}),
      );
      expect(ledgerOf(mine, 'a').single.isOfficial, isFalse);
      // The lawyer's word, old and new, is.
      for (final word in [
        {'resmi': 'elle'},
        {'resmiKarar': 'elle'},
      ]) {
        mine.saveClientRecord(
          mine
              .clientRecord('e1')!
              .copyWith(data: {...before['veri'] as Map, ...word}),
        );
        expect(ledgerOf(mine, 'a').single.official, 'elle');
      }
    });
  });
}

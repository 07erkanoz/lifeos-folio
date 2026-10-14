import 'dart:convert';
import 'dart:math';

import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/clients/client_accounts.dart';
import 'package:evrak_convert/services/clients/office_cash.dart';
import 'package:evrak_convert/services/enforcement/ledger_book.dart';
import 'package:evrak_convert/services/enforcement/ledger_service.dart';
import 'package:evrak_convert/services/notes/task_notes.dart';
import 'package:evrak_convert/services/office/office_task.dart';
import 'package:evrak_convert/services/office/proposals.dart';
import 'package:evrak_convert/services/office/shared_cases.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/sync/hlc.dart';
import 'package:flutter_test/flutter_test.dart';

/// docs/senkron-plan.md §5 step 9: everything together. Deniz has three
/// devices (A her first, B, C), Selin one (D) in the same office. Every
/// step done on one device, kept alike in any order, again and again, cut
/// short: in the end Deniz's devices say the same, Selin sees what she may
/// and no more, no secret text was ever in what went to the office.
class _Device {
  _Device(this.person, this.device) : db = PortalDatabase.memory();
  final String person, device;
  final PortalDatabase db;
}

void main() {
  late String Function()? person0;
  setUp(() => person0 = PortalDatabase.clientPerson);
  tearDown(() => PortalDatabase.clientPerson = person0);

  const secret = 'GİZLİ-METİN';

  for (var seed = 1; seed <= 40; seed++) {
    test('seed $seed: three own devices and a colleague, in any order', () {
      final a = _Device('deniz', 'deniz'),
          b = _Device('deniz', 'deniz-b'),
          c = _Device('deniz', 'deniz-c'),
          d = _Device('selin', 'selin');
      final own = [a, b, c], all = [a, b, c, d];
      addTearDown(() {
        for (final x in all) {
          x.db.dispose();
        }
      });
      final random = Random(seed);
      final task =
          OfficeTask(
              id: 't1',
              title: 'Bilirkişi raporuna itiraz',
              by: 'deniz',
              byName: 'Av. Deniz Kaya',
              assignees: const {'selin': 'Av. Selin Ak'},
              createdAt: DateTime(2026, 10, 7),
              cases: const [
                TaskCase(caseKey: 'dava', number: '2026/412', court: 'X'),
              ],
            )
            ..events.add(
              TaskEvent.create(TaskEventKind.given, 'deniz', 'Av. Deniz Kaya'),
            );
      String personOf(String device) =>
          device.startsWith('deniz') ? 'deniz' : 'selin';
      T as<T>(_Device x, T Function() f) {
        PortalDatabase.clientPerson = () => x.person;
        return f();
      }

      TaskNotes notes(_Device x) => TaskNotes(
        db: x.db,
        me: () => x.person,
        tasks: () => [task],
        personOf: personOf,
        received: (_, _) => null,
        devicesOf: (p) => [
          for (final y in all)
            if (y.person == p) y.device,
        ],
      );
      ProposalService proposals(_Device x) =>
          ProposalService(x.db, me: x.person, device: x.device);

      // What went to Selin: every payload, to be looked through.
      final toOffice = <String>[];

      // Cut short: a part that does not come this time (the line broken).
      var cutting = true;
      bool comes() => !cutting || random.nextInt(5) > 0;

      /// [f], the line whole: what the scenario's next step needs.
      void whole(void Function() f) {
        final was = cutting;
        cutting = false;
        f();
        cutting = was;
      }

      void ownSync(_Device from, _Device to) {
        final agenda = as(from, () => from.db.agendaExport());
        final tracking = from.db.noteTrackingExport();
        final props = as(from, () => proposals(from).ownExport());
        as(to, () {
          if (comes()) to.db.agendaMerge(agenda);
          if (comes()) to.db.noteTrackingMerge(tracking);
          if (comes()) proposals(to).ownMerge(props);
        });
      }

      void officeSync(_Device from, _Device to) {
        final cards = as(
          from,
          () => from.db.clientsOfficeExport(money: true, me: from.person),
        );
        final taskNotes = as(from, () => notes(from).export(to.device));
        final props = as(
          from,
          () => proposals(from).officeExport(to.person, money: true),
        );
        final version = from.db.caseShareVersion('icra2');
        final ledger = version == null
            ? null
            : as(from, () => from.db.caseLedgerForOffice('icra2', from.person));
        toOffice.add(jsonEncode([cards, taskNotes, props, ledger]));
        as(to, () {
          if (comes()) {
            to.db.clientsOfficeMerge(
              cards,
              money: true,
              me: to.person,
              from: from.person,
            );
          }
          if (comes()) notes(to).merge(taskNotes, from.device);
          if (comes()) {
            proposals(to).officeMerge(props, from.person, money: true);
          }
          if (version != null && comes()) {
            to.db.takeSharedLedger(
              from.person,
              'icra2',
              version,
              ownerName: 'Av. Deniz Kaya',
              records: [for (final j in ledger!) ?ClientRecord.fromJson(j)],
            );
          }
        });
      }

      void somePairs() {
        for (var i = random.nextInt(4); i > 0; i--) {
          final from = all[random.nextInt(all.length)];
          final to = all[random.nextInt(all.length)];
          if (identical(from, to)) continue;
          if (from.person == to.person) {
            ownSync(from, to);
          } else {
            officeSync(from, to);
          }
        }
      }

      // 1. A: a client shared with the office, its note, a case's note; a
      // payment of the case; another case shared alone, with a payment.
      as(a, () {
        a.db.saveClient(
          Client(
            id: 'k',
            name: 'Ayşe Karaca',
            note: 'Telefonla aranır',
            updated: DateTime(2026, 10, 1),
            person: 'deniz',
            caseNotes: {
              'dava': CaseNote('Bilirkişi bekleniyor', DateTime(2026, 10, 1)),
            },
          ).copyWith(office: true),
        );
      });
      final pay = as(
        a,
        () => LedgerService(a.db).add(
          clientId: 'k',
          caseKey: 'dava',
          kind: 'haricen',
          amount: 1500000,
          at: DateTime(2026, 10, 10),
          by: 'Av. Deniz Kaya',
          person: 'deniz',
        ),
      );
      final other = as(
        a,
        () => LedgerService(a.db).add(
          clientId: 'k2',
          caseKey: 'icra2',
          kind: 'haricen',
          amount: 300000,
          at: DateTime(2026, 10, 11),
          by: 'Av. Deniz Kaya',
          person: 'deniz',
        ),
      );
      as(a, () => SharedCases.share(a.db, 'icra2', ['selin']));
      somePairs();

      // 2. B: a note of the case, of the task given to Selin.
      as(b, () {
        b.db.saveAgenda(
          AgendaItem(
            id: 'n1',
            kind: 'note',
            title: 'Tanık listesi',
            body: 'Üç tanık',
            caseKey: 'dava',
            updated: DateTime(2026, 10, 12),
          ),
        );
      });
      somePairs();
      whole(() {
        for (final x in own) {
          ownSync(b, x == b ? a : x);
        }
      });

      // 3. C ticks it done; A changes its title, neither seeing the other.
      as(c, () {
        final n = c.db.agenda().where((i) => i.id == 'n1').firstOrNull;
        if (n != null) c.db.saveAgenda(n.copyWith(done: true));
      });
      as(a, () {
        final n = a.db.agenda().where((i) => i.id == 'n1').firstOrNull;
        if (n != null) a.db.saveAgenda(n.copyWith(title: 'Tanık listesi (3)'));
      });
      somePairs();

      // 4. Selin, once she has the payment, proposes another sum.
      for (var i = 0; i < 3; i++) {
        officeSync(own[random.nextInt(3)], d);
      }
      whole(() => officeSync(a, d));
      final p = as(
        d,
        () => proposals(d).propose(
          kind: 'icra',
          target: pay.id,
          fields: {'tutar': 1250000},
          reason: 'Makbuz',
        ),
      )!;
      somePairs();
      // It reaches A, who decides there (her first device).
      whole(() => officeSync(d, a));
      as(a, () => proposals(a).decide(p.id, approve: true));
      somePairs();

      // 5. B (the card with it by now) makes the card's note secret, its
      // text changed; A the agenda note.
      whole(() => ownSync(a, b));
      as(b, () {
        final card = b.db.clientCard('k')!;
        b.db.saveClient(
          card.copyWith(note: 'Telefonla aranır · $secret', noteSecret: true),
        );
      });
      as(a, () {
        final n = a.db.agenda().where((i) => i.id == 'n1').firstOrNull;
        if (n != null) {
          a.db.saveAgenda(n.copyWith(body: 'Üç tanık · $secret', secret: true));
        }
      });
      somePairs();

      // In the end, everything kept alike, every way, a few times, the line
      // whole again.
      cutting = false;
      for (var round = 0; round < 4; round++) {
        for (final from in all) {
          for (final to in all) {
            if (identical(from, to)) continue;
            if (from.person == to.person) {
              ownSync(from, to);
            } else {
              officeSync(from, to);
            }
          }
        }
      }

      // Deniz's devices say the same.
      String said(_Device x) => Hlc.canonical({
        'ajanda': [
          for (final r in x.db.agendaExport()['satirlar'] as List)
            {...r as Map}..remove('updated'),
        ],
        'kart': x.db.clientCard('k')?.toJson(),
        'hesap': {
          for (final e in caseAccounts(x.db.allClientRecords()).entries)
            e.key: [e.value.feeIn, e.value.advanceLeft],
        },
        'kasa': cashTotals(cashLines(x.db)).income,
        'odeme': LedgerBook.contentOf(x.db.clientRecord(pay.id)!),
        'karar': x.db.decisionOf(p.id)?.approved,
      });
      expect(said(b), said(a));
      expect(said(c), said(a));
      // The proposal taken, once, everywhere.
      for (final x in all) {
        expect(x.db.clientRecord(pay.id)!.amount, 1250000, reason: x.device);
      }
      expect(d.db.decisionOf(p.id)!.approved, isTrue);
      // The agenda note: done and retitled both, secret.
      final n = a.db.agenda().singleWhere((i) => i.id == 'n1');
      expect((n.title, n.done, n.secret), ('Tanık listesi (3)', true, true));
      // Selin: the card's note and the task's note taken back.
      expect(d.db.clientCard('k')!.note, isEmpty);
      expect([
        for (final r in d.db.taskNotes('deniz', 't1', 'dava')) r['title'],
      ], isEmpty);
      // The case shared alone: its payment read only, in no account of hers.
      expect(d.db.sharedLedgersOf('icra2')['deniz']!.single.id, other.id);
      expect(d.db.clientRecord(other.id), isNull);
      // Nothing secret ever went to the office.
      for (final payload in toOffice) {
        expect(payload, isNot(contains(secret)));
      }
    });
  }
}

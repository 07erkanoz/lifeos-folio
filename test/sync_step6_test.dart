import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/enforcement/enforcement_ledger.dart';
import 'package:evrak_convert/services/enforcement/enforcement_papers.dart';
import 'package:evrak_convert/services/enforcement/ledger_service.dart';
import 'package:evrak_convert/services/notes/secret_notes.dart';
import 'package:evrak_convert/services/notes/task_notes.dart';
import 'package:evrak_convert/services/office/office_task.dart';
import 'package:evrak_convert/services/office/task_package.dart';
import 'package:evrak_convert/services/portal/agenda_ics.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_deadline.dart';
import 'package:flutter_test/flutter_test.dart';

/// docs/senkron-plan.md §5 step 6: a secret note stays on the lawyer's own
/// devices (R7, §3 decision 1).
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

  final day = DateTime(2026, 10, 20, 10);
  AgendaItem note(String id, String title, {bool secret = false}) => AgendaItem(
    id: id,
    kind: 'note',
    title: title,
    body: '$title · ayrıntı',
    at: day,
    caseKey: 'dava',
    updated: DateTime(2026, 10, 14),
    secret: secret,
  );

  group('nothing secret leaves (R7)', () {
    test('a secret agenda note goes in no task nor shared case, its title '
        'neither; an open one says which note and version it is', () {
      a.saveAgenda(note('acik', 'Bilirkişi raporu'));
      a.saveAgenda(note('gizli', 'Uzlaşma sınırı', secret: true));
      a.saveAgenda(
        AgendaItem(
          id: 'elle',
          kind: 'deadline',
          title: 'Gizli süre başlığı',
          at: day,
          caseKey: 'dava',
          updated: DateTime(2026, 10, 14),
          secret: true,
        ),
      );
      // The package carries no notes at all now; they go apart, none
      // secret.
      final extras = TaskPackage.caseExtras(a, 'dava');
      expect(extras.containsKey('notlar'), isFalse);
      final notes = a.taskNoteRows('dava');
      final text = jsonEncode([extras, notes.rows]);
      expect(text, isNot(contains('Uzlaşma sınırı')));
      expect(text, isNot(contains('Gizli süre başlığı')));
      final open = notes.rows.single;
      expect(open['id'], 'acik');
      expect(open['surumler'], isA<String>());
      // On the lawyer's own devices, it is there, secret.
      b.agendaMerge(a.agendaExport());
      final there = b.agenda().firstWhere((i) => i.id == 'gizli');
      expect((there.title, there.secret), ('Uzlaşma sınırı', true));
    });

    test('the calendar written out has no secret note; a deadline\'s secret '
        'body is left out, its title kept', () {
      a.saveAgenda(note('gizli', 'Uzlaşma sınırı', secret: true));
      a.saveAgenda(note('acik', 'Bilirkişi raporu'));
      final events = agendaEvents(
        a,
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 11, 1),
        tasks: true,
      );
      final file = calendarFile(events);
      expect(file, isNot(contains('Uzlaşma')));
      expect(file, contains('Bilirkişi raporu'));
    });

    test('a card shared with the office: its secret note and a case\'s '
        'secret note go empty, and write over a member\'s copy of before', () {
      final person = PortalDatabase.clientPerson;
      addTearDown(() => PortalDatabase.clientPerson = person);
      PortalDatabase.clientPerson = () => 'deniz';
      a.saveClient(
        Client(
          id: 'k',
          name: 'Ayşe Karaca',
          note: 'Telefonla aranır',
          updated: DateTime(2026, 10, 1),
          person: 'deniz',
          caseNotes: {
            'dava': CaseNote('Rapor bekleniyor', DateTime(2026, 10, 1)),
          },
        ).copyWith(office: true),
      );
      Map<String, Object?> sent() =>
          a.clientsOfficeExport(money: true, me: 'deniz');
      b.clientsOfficeMerge(sent(), money: true, me: 'selin', from: 'deniz');
      expect(b.clientCard('k')!.note, 'Telefonla aranır');
      final card = a.clientCard('k')!;
      a.saveClient(
        card.copyWith(
          noteSecret: true,
          caseNotes: {
            'dava': CaseNote(
              'Rapor bekleniyor',
              DateTime(2026, 10, 2),
              secret: true,
            ),
          },
        ),
      );
      final text = jsonEncode(sent());
      expect(text, isNot(contains('Telefonla aranır')));
      expect(text, isNot(contains('Rapor bekleniyor')));
      b.clientsOfficeMerge(sent(), money: true, me: 'selin', from: 'deniz');
      final there = b.clientCard('k')!;
      expect((there.note, there.noteSecret), ('', true));
      expect(there.caseNotes['dava']!.text, '');
      // Own devices keep it whole.
      final own = PortalDatabase.memory();
      addTearDown(own.dispose);
      own.clientsMerge(a.clientsExport());
      expect(own.clientCard('k')!.note, 'Telefonla aranır');
    });

    test('a secret description of an enforcement payment goes empty to the '
        'office and is not written in its paper', () {
      final made = LedgerService(a).add(
        clientId: 'k',
        caseKey: 'dava',
        kind: 'feragat',
        amount: 10000,
        at: DateTime(2026, 10, 10),
        by: 'Av. Deniz Kaya',
        note: 'Borçlu ödeme güçlüğünde',
        noteSecret: true,
      );
      a.saveClient(
        Client(
          id: 'k',
          name: 'Ayşe Karaca',
          updated: DateTime(2026, 10, 1),
        ).copyWith(office: true),
      );
      expect(
        jsonEncode(a.clientsOfficeExport(money: true, me: '')),
        isNot(contains('ödeme güçlüğünde')),
      );
      final paper = waiverRequest(
        const EnforcementParties(
          office: 'Manavgat İcra Dairesi',
          number: '2026/1234',
          creditor: 'Bora Yapı A.Ş.',
          lawyer: 'Av. Deniz Kaya',
          debtors: ['Mehmet Tunç'],
        ),
        LedgerEntry(a.clientRecord(made.id)!),
      );
      expect(
        paper.blocks.map((b) => b.plainText).join('\n'),
        isNot(contains('ödeme güçlüğünde')),
      );
    });

    test('the text and whether it is secret are one: a secret text made on '
        'one device is not sent open by another\'s older word', () {
      a.saveAgenda(note('n', 'Ara'));
      b.agendaMerge(a.agendaExport());
      final there = b.agenda().single;
      // A: made secret, its text changed; B: only the title, later.
      a.saveAgenda(
        a.agenda().single.copyWith(body: 'Sınır 50.000 TL', secret: true),
      );
      b.saveAgenda(there.copyWith(title: 'Müvekkili ara'));
      a.agendaMerge(b.agendaExport());
      b.agendaMerge(a.agendaExport());
      for (final db in [a, b]) {
        final n = db.agenda().single;
        expect(
          (n.title, n.body, n.secret),
          ('Müvekkili ara', 'Sınır 50.000 TL', true),
        );
        expect(
          jsonEncode(db.taskNoteRows('dava').rows),
          isNot(contains('50.000')),
        );
      }
    });

    test('a deadline\'s body made secret is kept with its decision', () {
      a.saveDeadlineUser(
        const DeadlineUser(
          deadlineId: 'd',
        ).copyWith(bodyOverride: 'Müvekkil itiraz istemiyor', bodySecret: true),
      );
      b.agendaMerge(a.agendaExport());
      final d = (b.agendaExport()['kararlar'] as List).single as Map;
      expect(
        (d['body_override'], d['govde_gizli']),
        ('Müvekkil itiraz istemiyor', 1),
      );
    });
  });

  group('the tasks\' notes, as they are now, and taken back (R7)', () {
    // Deniz gives the task (device a1, and a2 of hers); Selin does it, on
    // b1 and b2. Mert is of the office, not in it.
    late PortalDatabase a2, b2;
    late Directory dir;
    setUp(() {
      a2 = PortalDatabase.memory();
      b2 = PortalDatabase.memory();
      dir = Directory.systemTemp.createTempSync('gorev-notlari');
    });
    tearDown(() {
      a2.dispose();
      b2.dispose();
      dir.deleteSync(recursive: true);
    });

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
    String person(String device) => switch (device[0]) {
      'a' => 'deniz',
      'b' => 'selin',
      _ => 'mert',
    };
    List<String>? paths;
    TaskNotes notes(PortalDatabase db, String me) => TaskNotes(
      db: db,
      me: () => me,
      tasks: () => [task],
      personOf: person,
      received: (_, _) => paths,
    );
    Future<bool> give(
      PortalDatabase from,
      String fromDevice,
      PortalDatabase to,
      String toDevice,
    ) => notes(
      to,
      person(toDevice),
    ).merge(notes(from, person(fromDevice)).export(toDevice), fromDevice);
    List<String> titles(PortalDatabase db) =>
        [for (final r in db.taskNotes('deniz', 't1', 'dava')) '${r['title']}']
          ..sort();
    ({int done, int of, List<String> waiting})? recall(String id) =>
        SecretNotes.recallOf(a, 'ajanda:$id', caseKey: 'dava');

    test('the notes come apart, note by note; one made secret goes from '
        'both of the doer\'s devices, and is counted taken back only when '
        'both said so', () async {
      a.saveAgenda(note('n1', 'Tanık listesi'));
      a.saveAgenda(note('n2', 'Bilirkişi raporu'));
      await give(a, 'a1', b, 'b1');
      await give(a, 'a1', b2, 'b2');
      expect(titles(b), ['Bilirkişi raporu', 'Tanık listesi']);
      // Each says what it holds.
      await give(b, 'b1', a, 'a1');
      await give(b2, 'b2', a, 'a1');
      a.saveAgenda(
        a.agenda().firstWhere((i) => i.id == 'n1').copyWith(secret: true),
      );
      expect(recall('n1')!.of, 1);
      expect(recall('n1')!.done, 0);
      await give(a, 'a1', b, 'b1');
      await give(b, 'b1', a, 'a1');
      expect(titles(b), ['Bilirkişi raporu']);
      // b2 holds it yet: Selin is not done.
      expect(recall('n1')!.done, 0);
      expect(recall('n1')!.waiting, ['selin']);
      await give(a, 'a1', b2, 'b2');
      await give(b2, 'b2', a, 'a1');
      expect(titles(b2), ['Bilirkişi raporu']);
      expect((recall('n1')!.done, recall('n1')!.of), (1, 1));
    });

    test('a list of before, from the giver\'s own device that did not know, '
        'brings nothing back; once the mark came, that device sends it no '
        'more', () async {
      a.saveAgenda(note('n1', 'Tanık listesi'));
      a2.agendaMerge(a.agendaExport());
      await give(a, 'a1', b, 'b1');
      a.saveAgenda(a.agenda().single.copyWith(secret: true));
      await give(a, 'a1', b, 'b1');
      expect(titles(b), isEmpty);
      // a2 knows nothing of it yet: its list of before.
      await give(a2, 'a2', b, 'b1');
      expect(titles(b), isEmpty);
      // The notes' tracking comes to a2, the agenda's part off.
      a2.noteTrackingMerge(a.noteTrackingExport());
      expect(a2.taskNoteRows('dava').rows, isEmpty);
      expect(SecretNotes.rowHidden(a2, a2.agenda().single), isTrue);
    });

    test('open, secret, open again, secret again: each time it goes and '
        'comes as it is', () async {
      a.saveAgenda(note('n1', 'Tanık listesi'));
      await give(a, 'a1', b, 'b1');
      AgendaItem n() => a.agenda().single;
      a.saveAgenda(n().copyWith(secret: true));
      await give(a, 'a1', b, 'b1');
      expect(titles(b), isEmpty);
      a.saveAgenda(n().copyWith(secret: false, body: 'Yeni ayrıntı'));
      await give(a, 'a1', b, 'b1');
      expect(titles(b), ['Tanık listesi']);
      await give(b, 'b1', a, 'a1');
      a.saveAgenda(n().copyWith(secret: true));
      expect(recall('n1')!.done, 0);
      await give(a, 'a1', b, 'b1');
      await give(b, 'b1', a, 'a1');
      expect(titles(b), isEmpty);
      expect(recall('n1')!.done, 1);
    });

    test('what one not giving the task sends is not taken', () async {
      final mert = PortalDatabase.memory();
      addTearDown(mert.dispose);
      mert.saveAgenda(note('m1', 'Sahte not'));
      await notes(b, 'selin').merge({
        'gorevler': [
          {
            'gorev': 't1',
            'dosya': 'dava',
            'notlar': mert.taskNoteRows('dava').rows,
          },
        ],
      }, 'm1');
      expect(titles(b), isEmpty);
    });

    test('an older Folio\'s package here is cleaned of its notes once the '
        'giver\'s notes come apart, its documents kept', () async {
      final details = File('${dir.path}/dosya.json')
        ..writeAsStringSync(
          jsonEncode({
            'evrakAdlari': {'k': 'rapor.json'},
            'notlar': [
              {'baslik': 'Eski not', 'metin': 'Uzlaşma sınırı'},
            ],
            'sureler': [
              {'baslik': 'Eski süre'},
            ],
          }),
        );
      final document = File('${dir.path}/rapor.json')
        ..writeAsStringSync(jsonEncode({'notlar': 'evrakın kendisi'}));
      paths = [details.path, document.path];
      addTearDown(() => paths = null);
      b.setTaskNotesCleaning('t1', 'dava', 'bekliyor');
      a.recordHold('eski:t1|dava', 'b1', 'selin', 'gorev:t1|dava');
      a.saveAgenda(note('n1', 'Tanık listesi'));
      await give(a, 'a1', b, 'b1');
      final j = jsonDecode(details.readAsStringSync()) as Map;
      expect(j.containsKey('notlar'), isFalse);
      expect(j.containsKey('sureler'), isFalse);
      expect(document.readAsStringSync(), contains('evrakın kendisi'));
      // Said so: the older package counted taken back.
      a.saveAgenda(a.agenda().single.copyWith(secret: true));
      await give(a, 'a1', b, 'b1');
      await give(b, 'b1', a, 'a1');
      expect((recall('n1')!.done, recall('n1')!.of), (1, 1));
    });

    test(
      'a card\'s note taken back reaches a member who no longer gets the '
      'card (shares off, no money), and no copy of before brings it back',
      () async {
        final person0 = PortalDatabase.clientPerson;
        addTearDown(() => PortalDatabase.clientPerson = person0);
        PortalDatabase.clientPerson = () => 'deniz';
        a.saveClient(
          Client(
            id: 'k',
            name: 'Ayşe Karaca',
            note: 'Telefonla aranır',
            updated: DateTime(2026, 10, 1),
            person: 'deniz',
          ).copyWith(office: true),
        );
        final before = a.clientsOfficeExport(money: false, me: 'deniz');
        b.clientsOfficeMerge(before, money: false, me: 'selin', from: 'deniz');
        expect(b.clientCard('k')!.note, 'Telefonla aranır');
        a.saveClient(a.clientCard('k')!.copyWith(noteSecret: true));
        // Only the notes' part, no card: the mark, no text.
        await give(a, 'a1', b, 'b1');
        expect(b.clientCard('k')!.note, '');
        // The card as it was before, again: still empty.
        b.clientsOfficeMerge(before, money: false, me: 'selin', from: 'deniz');
        expect(b.clientCard('k')!.note, '');
      },
    );

    test('a colleague\'s card\'s note is not changed here', () {
      final person0 = PortalDatabase.clientPerson;
      addTearDown(() => PortalDatabase.clientPerson = person0);
      PortalDatabase.clientPerson = () => 'deniz';
      a.saveClient(
        Client(
          id: 'k',
          name: 'Ayşe Karaca',
          note: 'Sahibinin notu',
          updated: DateTime(2026, 10, 1),
          person: 'deniz',
        ).copyWith(office: true),
      );
      b.clientsOfficeMerge(
        a.clientsOfficeExport(money: true, me: 'deniz'),
        money: true,
        me: 'selin',
        from: 'deniz',
      );
      PortalDatabase.clientPerson = () => 'selin';
      b.saveClient(b.clientCard('k')!.copyWith(note: 'Selin yazdı'));
      expect(b.clientCard('k')!.note, 'Sahibinin notu');
    });
  });
}

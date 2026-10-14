import 'dart:convert';

import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_deadline.dart';
import 'package:evrak_convert/services/sync/hlc.dart';
import 'package:evrak_convert/services/sync/sync_caps.dart';
import 'package:flutter_test/flutter_test.dart';

/// docs/senkron-plan.md §5 step 5: the agenda, the decisions on deadlines,
/// whom the lawyer acts for and the clients' cards kept alike group by
/// group (R1); a row taken off stays off till "Geri al" (R5). Three of the
/// lawyer's devices, A→B→C.
void main() {
  late PortalDatabase a, b, c;
  setUp(() {
    a = PortalDatabase.memory();
    b = PortalDatabase.memory();
    c = PortalDatabase.memory();
  });
  tearDown(() {
    a.dispose();
    b.dispose();
    c.dispose();
  });

  /// [from]'s agenda, taken by [to] as Senkron takes it.
  bool send(PortalDatabase from, PortalDatabase to) =>
      to.agendaMerge(from.agendaExport());

  AgendaItem? item(PortalDatabase db, String id) =>
      db.agenda().where((i) => i.id == id).firstOrNull;

  String said(PortalDatabase db) => Hlc.canonical({
    'satirlar': [
      for (final r in db.agendaExport()['satirlar'] as List)
        {...r as Map}..remove('updated'),
    ],
    'kararlar': [
      for (final r in db.agendaExport()['kararlar'] as List)
        {...r as Map}..remove('updated'),
    ],
    'temsil': [
      for (final r in db.agendaExport()['temsil'] as List)
        {...r as Map}..remove('updated'),
    ],
    // What each taken off said and its lifecycle version, too.
    'silinenler': [
      for (final r in db.agendaExport()['silinenler'] as List)
        {
          'id': (r as Map)['id'],
          'surum': r['surum'],
          'satir': r['satir'] == null
              ? null
              : ({...jsonDecode(r['satir'] as String) as Map}
                  ..remove('updated')),
        },
    ],
  });

  final t0 = DateTime(2026, 10, 14, 9);
  AgendaItem note(String id, String title) =>
      AgendaItem(id: id, kind: 'note', title: title, updated: t0);

  group('the agenda, group by group (R1)', () {
    test('done on one, the title on another: both stand, alike on every '
        'device, whichever came first, and reach C through B', () {
      a.saveAgenda(note('n', 'Bilirkişi raporu'));
      send(a, b);
      a.saveAgenda(item(a, 'n')!.copyWith(done: true));
      b.saveAgenda(item(b, 'n')!.copyWith(title: 'Bilirkişi raporuna itiraz'));
      // C takes B's first, then A's; A and B each other's.
      send(b, c);
      send(a, c);
      send(b, a);
      send(a, b);
      for (final db in [a, b, c]) {
        final n = item(db, 'n')!;
        expect((n.title, n.done), ('Bilirkişi raporuna itiraz', true));
      }
      expect(said(a), said(b));
      expect(said(c), said(a));
      // Taken again: nothing changes.
      expect(send(a, b), isFalse);
      expect(send(b, c), isFalse);
    });

    test('a row an older Folio kept has the same versions on every device, '
        'and only the group changed gets a new one', () {
      final old = {
        'satirlar': [
          {
            'id': 'o',
            'kind': 'task',
            'title': 'Harç yatır',
            'body': 'Gider avansı',
            'at': '2026-10-20T10:00:00.000',
            'all_day': 0,
            'done': 0,
            'case_key': null,
            'hearing_key': null,
            'updated': '2026-10-01T09:00:00.000',
          },
        ],
      };
      a.agendaMerge(old);
      b.agendaMerge(old);
      a.saveAgenda(item(a, 'o')!.copyWith(done: true));
      send(a, b);
      final versions = jsonDecode(
        ((b.agendaExport()['satirlar'] as List).single as Map)['surumler']
            as String,
      ) as Map;
      final made = '${Hlc.fromLegacy('2026-10-01T09:00:00.000')}';
      expect(versions['baslik'], made);
      expect(versions['zaman'], made);
      expect(versions['yasam'], made);
      expect(versions['tamam'], isNot(made));
      expect(item(b, 'o')!.done, isTrue);
    });
  });

  group('taken off (R5)', () {
    test('taken off on one and changed on another without seeing it: it '
        'stays off; "Geri al" brings it back, the change with it', () {
      a.saveAgenda(note('n', 'Müvekkili ara'));
      send(a, b);
      a.removeAgenda('n');
      b.saveAgenda(item(b, 'n')!.copyWith(title: 'Müvekkili yarın ara'));
      send(b, a);
      send(a, b);
      expect(item(a, 'n'), isNull);
      expect(item(b, 'n'), isNull);
      expect(a.restoreAgenda('n'), isTrue);
      send(a, b);
      send(a, c);
      for (final db in [a, b, c]) {
        expect(item(db, 'n')!.title, 'Müvekkili yarın ara');
      }
    });

    test('a change made of it as it was shown does not bring it back', () {
      a.saveAgenda(note('n', 'Müvekkili ara'));
      final shown = item(a, 'n')!;
      a.removeAgenda('n');
      a.saveAgenda(shown.copyWith(done: true));
      expect(item(a, 'n'), isNull);
    });

    test('an older Folio\'s mark of one taken off still takes it off', () {
      a.saveAgenda(note('n', 'Müvekkili ara'));
      a.agendaMerge({
        'silinen': {
          'n': DateTime.now().add(const Duration(minutes: 1)).toIso8601String(),
        },
      });
      expect(item(a, 'n'), isNull);
    });
  });

  group('the decisions on deadlines (R1)', () {
    List<Map> decisions(PortalDatabase db) => [
      for (final r in db.agendaExport()['kararlar'] as List) r as Map,
    ];

    test('a confirmation is one group: never the inputs of one and the day '
        'of another; done on another device stands beside it', () {
      a.saveDeadlineUser(
        DeadlineUser(
          deadlineId: 'd',
          confirmedInputs: 'girdi-a',
          confirmedAt: t0,
          confirmedDay: '2026-10-20',
        ),
      );
      b.saveDeadlineUser(
        DeadlineUser(
          deadlineId: 'd',
          confirmedInputs: 'girdi-b',
          confirmedAt: t0.add(const Duration(hours: 1)),
          confirmedDay: '2026-10-27',
        ),
      );
      c.saveDeadlineUser(const DeadlineUser(deadlineId: 'd', done: true));
      for (final (from, to) in [(a, b), (b, a), (c, a), (a, b), (a, c)]) {
        send(from, to);
      }
      for (final db in [a, b, c]) {
        final d = decisions(db).single;
        expect(
          [
            ('girdi-a', t0.toIso8601String(), '2026-10-20'),
            (
              'girdi-b',
              t0.add(const Duration(hours: 1)).toIso8601String(),
              '2026-10-27',
            ),
          ],
          contains((
            d['confirmed_inputs'],
            d['confirmed_at'],
            d['confirmed_day'],
          )),
        );
        expect(d['done'], 1);
      }
      expect(said(a), said(b));
      expect(said(c), said(a));
    });

    test('a decision first written on another device, of a deadline this one '
        'confirmed, does not take the confirmation away', () {
      a.saveDeadlineUser(
        DeadlineUser(
          deadlineId: 'd',
          confirmedInputs: 'girdi',
          confirmedAt: t0,
          confirmedDay: '2026-10-20',
        ),
      );
      // B's own, later, knowing nothing of A's: only done.
      b.saveDeadlineUser(const DeadlineUser(deadlineId: 'd', done: true));
      send(b, a);
      send(a, b);
      for (final db in [a, b]) {
        final d = decisions(db).single;
        expect((d['confirmed_inputs'], d['done']), ('girdi', 1));
      }
    });
  });

  test('whom the lawyer acts for: the same word chosen on every device for '
      'one said at the same time, the later one after it', () {
    Map<String, Object?> word(String who) => {
      'temsil': [
        {
          'case_key': 'dava',
          'json': jsonEncode([
            {'ad': who, 'rol': 'Davacı'},
          ]),
          'updated': '2026-10-01T09:00:00.000',
        },
      ],
    };
    a.agendaMerge(word('Ayşe Karaca'));
    b.agendaMerge(word('Mehmet Tunç'));
    send(a, b);
    send(b, a);
    expect(a.representation('dava'), b.representation('dava'));
    b.setRepresentation('dava', [(ad: 'Selin Ak', rol: 'Davalı')]);
    send(b, a);
    expect(a.representation('dava').single.ad, 'Selin Ak');
  });

  group('the clients\' cards (R1, R2.1)', () {
    Map<String, Object?> cards(List<Client> list) => {
      'muvekkiller': [for (final x in list) x.toJson()],
    };

    test('the stamps an older Folio kept stand: the phone set later on one, '
        'the address on the other, both kept; a change after them comes '
        'after them', () {
      final made = DateTime(2026, 10, 1, 9);
      Client card({
        String phone = '',
        String address = '',
        DateTime? p,
        DateTime? ad,
      }) => Client(
        id: 'k',
        name: 'Ayşe Karaca',
        phone: phone,
        address: address,
        updated: made,
        stamps: {'telefon': ?p, 'adres': ?ad},
      );
      a.clientsMerge(
        cards([
          card(
            phone: '0532',
            address: 'Konak',
            p: made,
            ad: DateTime(2026, 10, 3),
          ),
        ]),
      );
      b.clientsMerge(
        cards([
          card(
            phone: '0533',
            address: 'Bornova',
            p: DateTime(2026, 10, 2),
            ad: made,
          ),
        ]),
      );
      b.clientsMerge(a.clientsExport());
      a.clientsMerge(b.clientsExport());
      for (final db in [a, b]) {
        final k = db.clientCard('k')!;
        expect((k.phone, k.address), ('0533', 'Konak'));
      }
      a.saveClient(a.clientCard('k')!.copyWith(note: 'Sabah aranır'));
      b.clientsMerge(a.clientsExport());
      c.clientsMerge(b.clientsExport());
      for (final db in [a, b, c]) {
        final k = db.clientCard('k')!;
        expect((k.note, k.phone, k.address), ('Sabah aranır', '0533', 'Konak'));
      }
      expect(c.clientCard('k')!.encode(), a.clientCard('k')!.encode());
    });

    test('a card saved as it was shown keeps what came since: only what '
        'the lawyer changed is theirs', () {
      a.saveClient(Client(id: 'k', name: 'Ayşe Karaca', updated: t0));
      b.clientsMerge(a.clientsExport());
      final shown = a.clientCard('k')!;
      b.saveClient(b.clientCard('k')!.copyWith(phone: '0532'));
      a.clientsMerge(b.clientsExport());
      // A's screen still shows the card as it was, and the note is added.
      a.saveClient(shown.copyWith(note: 'Sabah aranır'));
      final k = a.clientCard('k')!;
      expect((k.phone, k.note), ('0532', 'Sabah aranır'));
      b.clientsMerge(a.clientsExport());
      expect(b.clientCard('k')!.encode(), k.encode());
    });

    test('a case\'s note: an older one by when it was written, a new one '
        'by its version, the same on every device', () {
      final first = Client(
        id: 'k',
        name: 'Ayşe Karaca',
        updated: t0,
        caseNotes: {'dava': CaseNote('Bilirkişi bekleniyor', t0)},
      );
      a.clientsMerge(cards([first]));
      b.clientsMerge(cards([first]));
      a.saveClient(
        a
            .clientCard('k')!
            .copyWith(
              caseNotes: {
                'dava': CaseNote(
                  'Rapor geldi',
                  t0.add(const Duration(hours: 1)),
                ),
              },
            ),
      );
      b.saveClient(
        b
            .clientCard('k')!
            .copyWith(
              caseLinks: {
                'icra': CaseLink(
                  CaseLink.added,
                  t0.add(const Duration(hours: 2)),
                ),
              },
            ),
      );
      a.clientsMerge(b.clientsExport());
      b.clientsMerge(a.clientsExport());
      for (final db in [a, b]) {
        final k = db.clientCard('k')!;
        expect(k.caseNotes['dava']!.text, 'Rapor geldi');
        expect(k.caseNotes['dava']!.version, isNotNull);
        expect(k.caseLinks['icra']!.state, CaseLink.added);
      }
      expect(a.clientCard('k')!.encode(), b.clientCard('k')!.encode());
    });
  });

  test('the agenda part needs the field and lifecycle versions now: it '
      'stops with an older Folio', () {
    expect(
      SyncCaps.needs('ajanda'),
      containsAll([SyncCaps.fieldVersions, SyncCaps.lifecycle]),
    );
    expect(SyncCaps.known, containsAll(SyncCaps.needs('ajanda')));
    expect(
      SyncCaps.missing('ajanda', {SyncCaps.hlc, SyncCaps.ledgerOps}),
      isNotEmpty,
    );
  });

  group('Codex\'s review of step 5', () {
    test('a row saved as it was shown keeps what came since: done ticked '
        'on an old screen does not take the new title back', () {
      a.saveAgenda(note('n', 'Ara'));
      send(a, b);
      final shown = item(a, 'n')!;
      b.saveAgenda(item(b, 'n')!.copyWith(title: 'Yarın ara'));
      send(b, a);
      a.saveAgenda(shown.copyWith(done: true));
      send(a, b);
      for (final db in [a, b]) {
        final n = item(db, 'n')!;
        expect((n.title, n.done), ('Yarın ara', true));
      }
    });

    test('a day given on an old screen does not bring back a deadline '
        'taken off on another device', () {
      final shown = const DeadlineUser(deadlineId: 'd');
      b.saveDeadlineUser(shown.copyWith(dismissed: true));
      send(b, a);
      a.saveDeadlineUser(shown.copyWith(manualDay: '2026-10-30'));
      send(a, b);
      for (final db in [a, b]) {
        final d = (db.agendaExport()['kararlar'] as List).single as Map;
        expect((d['dismissed'], d['manual_day']), (1, '2026-10-30'));
      }
    });

    test('a row an older Folio kept with a clock ahead, taken off here, '
        'stays off: what is kept is seen before it is written after', () {
      final ahead = {
        'satirlar': [
          {
            'id': 'o',
            'kind': 'note',
            'title': 'İleri saatli',
            'updated': '2027-01-01T09:00:00.000',
          },
        ],
      };
      a.agendaMerge(ahead);
      b.agendaMerge(ahead);
      a.removeAgenda('o');
      send(a, b);
      send(b, a);
      expect(item(a, 'o'), isNull);
      expect(item(b, 'o'), isNull);
    });

    test('a confirmation\'s day one device read from its history goes to '
        'the other; two days of the same version end alike; taken again, '
        'nothing changes', () {
      Map<String, Object?> kept(String? day) => {
        'kararlar': [
          {
            'deadline_id': 'd',
            'confirmed_inputs': 'girdi',
            'confirmed_at': '2026-10-01T09:00:00.000',
            'confirmed_day': day,
            'updated': '2026-10-01T09:00:00.000',
          },
        ],
      };
      a.agendaMerge(kept('2026-10-20'));
      b.agendaMerge(kept(null));
      send(a, b);
      send(b, a);
      for (final db in [a, b]) {
        final d = (db.agendaExport()['kararlar'] as List).single as Map;
        expect(d['confirmed_day'], '2026-10-20');
      }
      expect(send(a, b), isFalse);
      expect(send(b, a), isFalse);
      c.agendaMerge(kept('2026-10-27'));
      send(c, a);
      send(a, c);
      expect(said(a), said(c));
      expect(send(c, a), isFalse);
    });

    test('a card saved as it was shown keeps the names and cards taken in '
        'on another device', () {
      a.saveClient(Client(id: 'k', name: 'Ayşe Karaca', updated: t0));
      b.clientsMerge(a.clientsExport());
      final shown = a.clientCard('k')!;
      final there = b.clientCard('k')!;
      b.saveClient(
        there.copyWith(
          names: [...there.names, 'ayse k'],
          absorbed: [...there.absorbed, 'k2'],
        ),
      );
      a.clientsMerge(b.clientsExport());
      a.saveClient(shown.copyWith(note: 'Sabah aranır'));
      final k = a.clientCard('k')!;
      expect(k.names, contains('ayse k'));
      expect(k.absorbed, contains('k2'));
      expect(k.note, 'Sabah aranır');
    });

    test('a case\'s note changed here after one written by a clock ahead '
        'is this one\'s: it wins on both', () {
      final ahead = t0.add(const Duration(days: 1));
      b.saveClient(
        Client(
          id: 'k',
          name: 'Ayşe Karaca',
          updated: t0,
          caseNotes: {'dava': CaseNote('İleri saatli not', ahead)},
        ),
      );
      a.clientsMerge(b.clientsExport());
      a.saveClient(
        a
            .clientCard('k')!
            .copyWith(caseNotes: {'dava': CaseNote('Rapor geldi', t0)}),
      );
      b.clientsMerge(a.clientsExport());
      for (final db in [a, b]) {
        expect(db.clientCard('k')!.caseNotes['dava']!.text, 'Rapor geldi');
      }
    });

    test('a new card has this device\'s versions; whom the lawyer acts for '
        'in a case with no notice, changed, is told as a change', () {
      a.saveClient(Client(id: 'k', name: 'Ayşe Karaca', updated: t0));
      final versions = a.clientCard('k')!.versions;
      expect(versions.keys, containsAll(Client.fields));
      expect(versions['ad']!.source, isNot(Hlc.migrated));
      a.setRepresentation('dava', [(ad: 'Ayşe Karaca', rol: 'Davacı')]);
      expect(send(a, b), isTrue);
      expect(b.representation('dava').single.ad, 'Ayşe Karaca');
    });
  });
}

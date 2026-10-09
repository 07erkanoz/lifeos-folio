import 'dart:io';

import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/clients/client_files.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/ui/clients/clients_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PortalDatabase db;
  late Directory root;
  setUp(() {
    db = PortalDatabase.memory();
    root = Directory.systemTemp.createTempSync('folio_clients_');
    db.setRepresentation('k1', const [(ad: 'AYŞE KARACA', rol: 'Davacı')]);
  });
  tearDown(() {
    db.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('a client of a case is listed; its minutes written are kept '
      'with the time they were written, and its card made then', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientsPage(
            lawyer: 'Av. Deniz Kaya',
            database: db,
            files: ClientFiles(root: () async => root),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ayşe Karaca'), findsOneWidget);
    await tester.tap(find.text('Ayşe Karaca'));
    await tester.pumpAndSettle();
    expect(find.textContaining('AÇIK DOSYALAR'), findsOneWidget);
    expect(find.byKey(const ValueKey('client-case-k1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('client-meeting')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('meeting-decided')),
      'Sulh görüşmesine yetki verildi.',
    );
    await tester.tap(find.byKey(const ValueKey('meeting-save')));
    await tester.pumpAndSettle();

    final card = db.clientCards().single;
    final m = db.clientRecords(card.id).single;
    expect(m.text('kararlar'), 'Sulh görüşmesine yetki verildi.');
    expect(m.by, 'Av. Deniz Kaya');
    expect(m.locked, isFalse);
    expect(find.textContaining('imza bekliyor'), findsWidgets);
    // The card made stands for the name the case wrote.
    expect(
      db.clientEntries(lawyer: 'Av. Deniz Kaya').single.client?.id,
      card.id,
    );
  });

  testWidgets('on a phone, a case opened from a client\'s page comes in '
      'front: the client\'s page closes first, and it is said whose it was', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? opened, from;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientsPage(
            lawyer: 'Av. Deniz Kaya',
            database: db,
            files: ClientFiles(root: () async => root),
            onOpenCase: (kase, client) {
              opened = kase;
              from = client;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayşe Karaca'));
    await tester.pumpAndSettle();
    expect(find.text('Müvekkil'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('case-menu-k1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dosyayı aç'));
    await tester.pumpAndSettle();
    expect(opened, 'k1');
    expect(from, isNotEmpty);
    // The client's page is gone: what opens is not behind it.
    expect(find.text('Müvekkil'), findsNothing);
  });

  testWidgets('a client is written in by hand with a group, listed and '
      'narrowed to by it; hidden, they leave the list, are under "Gizli" and '
      'found when searched for', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientsPage(
            lawyer: 'Av. Deniz Kaya',
            database: db,
            files: ClientFiles(root: () async => root),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clients-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('contact-name')),
      'Kemal Doğan',
    );
    await tester.enterText(find.byKey(const ValueKey('contact-group')), 'Kira');
    await tester.tap(find.byKey(const ValueKey('contact-save')));
    await tester.pumpAndSettle();
    final card = db.clientCards().singleWhere((c) => c.name == 'Kemal Doğan');
    expect(card.group, 'Kira');
    expect(find.text('Kemal Doğan'), findsWidgets);

    // Narrowed to the group: the other client goes.
    await tester.tap(find.byKey(const ValueKey('clients-group')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kira').last);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('client-${card.id}')), findsOneWidget);
    expect(find.text('Ayşe Karaca'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('clients-group')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tüm gruplar'));
    await tester.pumpAndSettle();

    // Hidden from its card's menu.
    await tester.tap(find.byKey(ValueKey('client-${card.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('client-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('client-hide')));
    await tester.pumpAndSettle();
    expect(db.clientCards().singleWhere((c) => c.id == card.id).hidden, isTrue);
    expect(find.byKey(ValueKey('client-${card.id}')), findsNothing);
    // Found again: by search, and under "Gizli".
    await tester.enterText(
      find.byKey(const ValueKey('clients-search')),
      'kemal',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('client-${card.id}')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('clients-search')), '');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clients-filter-hidden')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('client-${card.id}')), findsOneWidget);
    expect(find.text('Ayşe Karaca'), findsNothing);
  });

  testWidgets('a fee agreement made is kept among the client\'s records '
      'with its case, its draft and the day, listed as waiting to be '
      'signed; one who may not see the money has no papers', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? edited;
    Future<void> pump({required bool money}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClientsPage(
              key: ValueKey(money),
              lawyer: 'Av. Deniz Kaya',
              database: db,
              files: ClientFiles(root: () async => root),
              seesMoney: money,
              onEdit: (path) => edited = path,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ayşe Karaca'));
      await tester.pumpAndSettle();
    }

    await pump(money: true);
    await tester.tap(find.byKey(const ValueKey('client-papers')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Avukatlık ücret sözleşmesi'));
      for (var i = 0; i < 40 && edited == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(edited, isNotNull);
    final card = db.clientCards().single;
    final paper = db
        .clientRecords(card.id, kind: ClientRecordKind.paper)
        .single;
    expect(paper.text('tur'), 'sozlesme');
    expect(paper.text('dosya'), 'k1');
    expect(paper.text('yol'), edited);
    expect(paper.locked, isFalse);
    // The draft kept with it, by its digest: to every device it goes to.
    expect(clientFilesOf(paper).single.sha256, paper.text('taslak'));
    expect(find.byKey(ValueKey('client-paper-${paper.id}')), findsOneWidget);
    expect(find.text('imza bekliyor'), findsOneWidget);

    // One who may not see the money: no papers at all.
    await pump(money: false);
    expect(find.byKey(ValueKey('client-paper-${paper.id}')), findsNothing);
  });

  Future<void> open(WidgetTester tester, {bool money = true}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientsPage(
            lawyer: 'Av. Deniz Kaya',
            database: db,
            files: ClientFiles(root: () async => root),
            seesMoney: money,
            inOffice: true,
            person: 'deniz',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayşe Karaca'));
    await tester.pumpAndSettle();
  }

  testWidgets('a fee paid is written to its case\'s account with its time; '
      'one who may not see the money has no accounts at all', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('client-accounts')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('movement-k1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('movement-amount')),
      '15.000',
    );
    await tester.tap(find.byKey(const ValueKey('movement-save')));
    await tester.pumpAndSettle();
    final m = db
        .clientRecords(db.clientCards().single.id)
        .singleWhere((r) => r.kind == ClientRecordKind.movement);
    expect(m.data['tutar'], 1500000);
    expect(m.text('dosya'), 'k1');
    expect(m.locked, isTrue);
    expect(m.person, 'deniz');
    expect(find.textContaining('+15.000 TL'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await open(tester, money: false);
    expect(find.byKey(const ValueKey('client-accounts')), findsNothing);
    expect(find.text('Ücret alacağı'), findsNothing);
    // Shared one client at a time, off until chosen.
    expect(find.text('Yalnız bende'), findsOneWidget);
  });

  testWidgets('a case is taken off a client only when asked twice, and '
      'given back from the cases taken off', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('client-case-k1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('case-menu-k1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('case-remove-k1')));
    await tester.pumpAndSettle();
    // Asked first: backed out of, nothing changes.
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('client-case-k1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('case-menu-k1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('case-remove-k1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('case-remove-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('client-case-k1')), findsNothing);
    expect(find.byKey(const ValueKey('client-removed-k1')), findsOneWidget);
    final entry = db.clientEntries(lawyer: 'Av. Deniz Kaya').single;
    expect(entry.cases, isEmpty);
    expect(entry.removedCases.single.caseKey, 'k1');

    await tester.tap(find.byKey(const ValueKey('case-restore-k1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('client-case-k1')), findsOneWidget);
    expect(
      db.clientEntries(lawyer: 'Av. Deniz Kaya').single.removedCases,
      isEmpty,
    );
  });

  testWidgets('a case opens under its row, and its note is kept on the '
      'card with who wrote it', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('client-case-k1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('case-detail-k1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('case-note-k1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('case-note-text')),
      'Müvekkil sulhe açık.',
    );
    await tester.tap(find.byKey(const ValueKey('case-note-save')));
    await tester.pumpAndSettle();
    final note = db.clientCards().single.caseNotes['k1']!;
    expect(note.text, 'Müvekkil sulhe açık.');
    expect(note.by, 'Av. Deniz Kaya');
    expect(find.text('Müvekkil sulhe açık.'), findsOneWidget);
  });

  test('a case tied by hand is the client\'s; one taken off is not, nor '
      'brought back by its names', () {
    db.setRepresentation('k2', const [(ad: 'BORA YAPI', rol: 'Davalı')]);
    final card = Client(id: 'c1', name: 'Ayşe Karaca', updated: DateTime(2026));
    db.saveClient(
      card.copyWith(
        caseLinks: {
          'k2': CaseLink(CaseLink.added, DateTime(2026, 2), role: 'Davacı'),
          'k1': CaseLink(CaseLink.removed, DateTime(2026, 2)),
        },
      ),
    );
    final e = db
        .clientEntries(lawyer: 'Av. Deniz Kaya')
        .singleWhere((x) => x.key == 'c1');
    expect(e.cases.map((c) => c.caseKey), ['k2']);
    expect(e.cases.single.role, 'Davacı');
    expect(e.addedCases, {'k2'});
    expect(e.removedCases.single.caseKey, 'k1');
  });

  test('two devices that changed different fields of a card keep both, '
      'and the later word on one field wins on both', () {
    final other = PortalDatabase.memory();
    addTearDown(other.dispose);
    final made = Client(id: 'c1', name: 'Ayşe Karaca', updated: DateTime(2026));
    db.saveClient(made);
    other.saveClient(made);
    // Here the phone, there the address and later the phone too.
    db.saveClient(
      made.copyWith(phone: '0532 000 00 41', updated: DateTime(2026, 3)),
    );
    final there = made.copyWith(
      address: 'Muratpaşa',
      updated: DateTime(2026, 4),
    );
    other.saveClient(there);
    expect(db.clientsMerge(other.clientsExport()), isTrue);
    expect(other.clientsMerge(db.clientsExport()), isTrue);
    for (final d in [db, other]) {
      final c = d.clientCard('c1')!;
      expect(c.phone, '0532 000 00 41');
      expect(c.address, 'Muratpaşa');
    }
    other.saveClient(
      other
          .clientCard('c1')!
          .copyWith(phone: '0533 111 11 11', updated: DateTime(2026, 5)),
    );
    db.clientsMerge(other.clientsExport());
    other.clientsMerge(db.clientsExport());
    expect(db.clientCard('c1')!.phone, '0533 111 11 11');
    expect(db.clientCard('c1')!.encode(), other.clientCard('c1')!.encode());
    // Merged again, nothing changes.
    expect(db.clientsMerge(other.clientsExport()), isFalse);
  });

  test('the cases tied and taken off are merged case by case', () {
    final a = Client(id: 'c1', name: 'A', updated: DateTime(2026));
    final mine = a.copyWith(
      caseLinks: {'k1': CaseLink(CaseLink.removed, DateTime(2026, 2))},
    );
    final theirs = a.copyWith(
      caseLinks: {
        'k1': CaseLink(CaseLink.none, DateTime(2026, 3)),
        'k2': CaseLink(CaseLink.added, DateTime(2026, 1)),
      },
    );
    final m = Client.merge(mine, theirs);
    expect(m.caseLinks['k1']!.state, CaseLink.none);
    expect(m.caseLinks['k2']!.state, CaseLink.added);
    expect(Client.merge(theirs, mine).encode(), m.encode());
  });

  test('the minutes print with both signatures and their code', () async {
    ByteData font(String style) => ByteData.sublistView(
      File('fonts/pdf/LiberationSerif-$style.ttf').readAsBytesSync(),
    );
    final client = Client(
      id: 'k',
      name: 'Ayşe Karaca',
      updated: DateTime(2026),
    );
    final bytes = await meetingMinutesPdf(
      client: client,
      meeting: ClientRecord(
        id: 'g',
        clientId: 'k',
        kind: ClientRecordKind.meeting,
        data: const {'kararlar': 'İki tanık bildirilecek.'},
        created: DateTime(2026, 10, 6, 14, 10, 5),
        by: 'Av. Deniz Kaya',
        updated: DateTime(2026, 10, 6, 14, 10, 5),
      ),
      lawyer: 'Av. Deniz Kaya',
      regular: font('Regular'),
      bold: font('Bold'),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(2000));
  });
}

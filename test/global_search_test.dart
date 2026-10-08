import 'dart:io';

import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/search/search_models.dart';
import 'package:evrak_convert/services/uyap/uyap_case_links.dart';
import 'package:evrak_convert/services/uyap/uyap_case_panel_controller.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/desktop/desktop_home.dart';
import 'package:evrak_convert/ui/portfolio/case_detail_page.dart';
import 'package:evrak_convert/ui/search/global_search.dart';
import 'package:evrak_convert/ui/search/global_search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late PortalDatabase db;
  late UyapCaseStore store;
  late UyapCaseLinks links;
  const civil = 'Antalya 3. Asliye Hukuk Mahkemesi';
  const labour = 'Antalya 2. İş Mahkemesi';
  final asked = DateTime.utc(2026, 10, 6);

  PortalCase kase(String number, String court) => PortalCase(
    key: caseKey(number, court),
    number: number,
    court: court,
    status: Observed('Açık', PortalChannel.uyapMobile, asked),
    details: Observed(
      {'yargiTuru': '1', 'tur': 'Dava Dosyası'},
      PortalChannel.uyapMobile,
      asked,
      complete: false,
    ),
  );

  UyapCaseDocument doc(String key, String type, String day) => UyapCaseDocument(
    key: key,
    documentId: key,
    caseId: '1',
    type: type,
    number: key,
    approved: '$day 10:00',
    sender: 'Mahkeme',
    description: '',
  );

  setUp(() async {
    root = Directory.systemTemp.createTempSync('folio_global_search_');
    final support = Directory('${root.path}/destek');
    store = UyapCaseStore(
      directory: support,
      settings: UyapSettings(directory: support, home: '${root.path}/ev'),
    );
    links = UyapCaseLinks(directory: support);
    db = PortalDatabase.memory();
    db.mergeCases(
      [kase('2024/318', civil), kase('2025/77', labour)],
      portfolio: true,
      baseline: true,
    );
    // One party in both cases, one in the first alone.
    await store.keep(
      target: const UyapCase('1', '2024/318', '', civil),
      details: const UyapCaseDetails(),
      parties: const [
        UyapParty('AYŞE KARACA', 'Davacı', 'Av. Deniz Kaya', 'Kişi'),
        UyapParty('B. İNŞAAT LTD. ŞTİ.', 'Davalı', 'Av. Murat Er', 'Kurum'),
      ],
      documents: UyapCaseDocuments([
        doc('a', 'Tensip Zaptı', '01.09.2026'),
        doc('b', 'Bilirkişi Raporu', '06.10.2026'),
      ]),
    );
    await store.keep(
      target: const UyapCase('2', '2025/77', '', labour),
      details: const UyapCaseDetails(),
      parties: const [
        UyapParty('AYŞE KARACA', 'Davacı', 'Av. Deniz Kaya', 'Kişi'),
        UyapParty('C. GIDA A.Ş.', 'Davalı', 'Av. Murat Er', 'Kurum'),
      ],
      documents: UyapCaseDocuments([doc('c', 'Tensip Zaptı', '02.09.2026')]),
    );
    db.saveAgenda(
      AgendaItem(
        id: 'n1',
        kind: 'note',
        title: 'Bilirkişi raporuna itiraz süresi',
        at: DateTime(2026, 10, 20),
        allDay: true,
        updated: asked,
      ),
    );
  });

  tearDown(() {
    db.dispose();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  GlobalSearch search({List<String> files = const []}) => GlobalSearch(
    lawyer: 'Av. Deniz Kaya',
    database: db,
    store: store,
    now: () => DateTime(2026, 10, 8),
    archive: (text, limit) async {
      final found = [
        for (final f in files)
          if (UyapWebService.fold(f).contains(UyapWebService.fold(text))) f,
      ];
      return SearchPage(
        [
          for (final f in found.take(limit))
            SearchHit(file: EvrakFile.fromPath('${root.path}/$f')),
        ],
        found.length,
        0,
      );
    },
  );

  test('the cases, a party once for all its cases, documents and the '
      'agenda, each in its group', () async {
    final s = search(files: ['Karaca vekaletname.pdf']);

    final byName = await s.find('ayşe karaca');
    expect(byName.cases.total, 2);
    expect(byName.parties.total, 1);
    final party = byName.parties.first.single;
    expect(party.name, 'AYŞE KARACA');
    expect(party.cases.map((r) => r.kase.number), {'2024/318', '2025/77'});
    expect(
      (await s.find('vekaletname')).files.first.single.hit.file.name,
      'Karaca vekaletname.pdf',
    );

    final byNumber = await s.find('2024/318');
    expect(byNumber.cases.first.single.row.kase.court, civil);
    expect(byNumber.parties.isEmpty, isTrue);

    final byDocument = await s.find('tensip');
    expect(byDocument.documents.total, 2);
    expect(byDocument.cases.isEmpty, isTrue);

    final byWords = await s.find('bilirkişi');
    expect(byWords.documents.first.single.document.key, 'b');
    expect(byWords.agenda.first.single.item!.id, 'n1');
    expect(byWords.agenda.first.single.day, DateTime(2026, 10, 20));

    expect((await s.find('a')).isEmpty, isTrue);
  });

  test('a group shows five, the rest a press away', () async {
    final s = search(files: [for (var i = 0; i < 9; i++) 'Karaca $i.pdf']);
    final r = await s.find('karaca');
    expect(r.files.first, hasLength(5));
    expect(r.filesTotal, 9);
    for (var i = 0; i < 6; i++) {
      db.saveAgenda(
        AgendaItem(
          id: 'k$i',
          kind: 'task',
          title: 'Karaca dosyasına bak $i',
          at: DateTime(2026, 11, 1 + i),
          updated: asked,
        ),
      );
    }
    final more = await s.find('karaca');
    expect(more.agenda.total, 6);
    expect(more.agenda.first, hasLength(5));
    expect(more.agenda.more, isTrue);
    expect(more.open(agenda: true).agenda.first, hasLength(6));
  });

  testWidgets('typed, the home page lists what it found; Enter and the '
      'arrows open one, a party in two cases opens them all', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = search(files: ['Karaca vekaletname.pdf']);
    // The portfolio read once, outside the test's clock.
    await tester.runAsync(() => s.find('karaca'));
    final opened = <Found>[];
    final shown = <String>[];
    final archive = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopHome(
            name: 'Av. Deniz Kaya',
            recent: const [],
            office: const DesktopHomeOffice(),
            links: links,
            now: () => DateTime(2026, 10, 8, 9),
            search: s,
            onFound: opened.add,
            onShowCases: shown.add,
            onSearch: archive.add,
            onOpen: (_) {},
            onEdit: (_) {},
            onSendUyap: (_) {},
            onArchive: () {},
            onDrafts: () {},
            onAgenda: () {},
            onUets: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    final field = find.byKey(const ValueKey('home-search'));
    await tester.tap(field);
    await tester.enterText(field, 'karaca');
    await tester.pump(const Duration(milliseconds: 250));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('home-search-results')), findsOneWidget);
    expect(find.text('UYAP DOSYALARI · 2'), findsOneWidget);
    expect(find.text('TARAFLAR · 1'), findsOneWidget);
    expect(find.text('ARŞİV BELGELERİ · 1'), findsOneWidget);
    expect(find.text('2 dosyada', findRichText: true), findsNothing);
    expect(find.textContaining('2 dosyada'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Down twice: past the two cases, on the party.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(opened.single, isA<FoundParty>());
    expect((opened.single as FoundParty).cases, hasLength(2));
    expect(find.byKey(const ValueKey('home-search-results')), findsNothing);
    expect(archive, isEmpty);

    // Nothing found: Enter searches the archive as before.
    await tester.tap(field);
    await tester.enterText(field, 'zzqq');
    await tester.pump(const Duration(milliseconds: 250));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.textContaining('bir şey bulunamadı'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(archive, ['zzqq']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a case opened from the search shows its parties, or the '
      'document asked for', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = UyapCasePanelController(
      web: UyapWebService.forTesting(),
      mobile: UyapMobileApi.forTesting(Uri.parse('http://127.0.0.1:9/')),
      store: store,
      links: links,
      pause: Duration.zero,
    );
    Future<void> open({bool parties = false, String? document}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CaseDetailPage(
              key: UniqueKey(),
              caseKey: caseKey('2024/318', civil),
              database: db,
              controller: controller,
              links: links,
              lawyer: 'Av. Deniz Kaya',
              showParties: parties,
              showDocument: document,
              onBack: () {},
              onOpen: (_) {},
            ),
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
    }

    await open(parties: true);
    expect(tester.takeException(), isNull);
    // The parties' tab: each with their lawyer.
    expect(find.text('Davalı · Vekil: Av. Murat Er · Kurum'), findsOneWidget);

    await open(document: 'b');
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('case-preview-close')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone the search fills the screen and leaves for the '
      'row tapped', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = search();
    await tester.runAsync(() => s.find('karaca'));
    SearchExit? exit;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  exit = await Navigator.of(context).push<SearchExit>(
                    MaterialPageRoute(
                      builder: (_) => GlobalSearchPage(search: s),
                    ),
                  );
                },
                child: const Text('ara'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ara'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('phone-search')),
      'tensip',
    );
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('UYAP EVRAKLARI · 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('found-1')));
    await tester.pumpAndSettle();
    final found = (exit as SearchOpened).found as FoundDocument;
    expect(found.document.key, 'a');
    expect(found.row.kase.number, '2024/318');
  });
}

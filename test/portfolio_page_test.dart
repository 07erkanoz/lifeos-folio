import 'dart:io';

import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/uyap/uyap_case_links.dart';
import 'package:evrak_convert/services/uyap/uyap_case_panel_controller.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/portfolio/case_detail_page.dart';
import 'package:evrak_convert/ui/portfolio/portfolio_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late PortalDatabase db;
  late UyapCaseStore store;
  late UyapCaseLinks links;
  const civil = 'Antalya 3. Asliye Hukuk Mahkemesi';
  const criminal = 'Manavgat 1. Ağır Ceza Mahkemesi';
  const enforcement = 'Antalya 5. İcra Dairesi';
  final asked = DateTime.utc(2026, 10, 6);

  PortalCase kase(String number, String court, String code, String status) =>
      PortalCase(
        key: caseKey(number, court),
        number: number,
        court: court,
        status: Observed(status, PortalChannel.uyapMobile, asked),
        details: Observed(
          {'yargiTuru': code, 'tur': 'Dava Dosyası', 'acilis': '12.03.2024'},
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
    root = Directory.systemTemp.createTempSync('folio_portfolio_');
    store = UyapCaseStore(
      directory: Directory('${root.path}/destek'),
      settings: UyapSettings(
        directory: Directory('${root.path}/destek'),
        home: '${root.path}/ev',
      ),
    );
    links = UyapCaseLinks(directory: Directory('${root.path}/destek'));
    db = PortalDatabase.memory();
    // The first reading: nothing in it is news.
    db.mergeCases(
      [
        kase('2024/318', civil, '1', 'Açık'),
        kase('2025/9184', enforcement, '2', 'Kapalı'),
      ],
      portfolio: true,
      baseline: true,
    );
    // A case the next reading brought.
    db.mergeCases([kase('2026/295', criminal, '0', 'Açık')], portfolio: true);
    const target = UyapCase('1', '2024/318', '', civil);
    const parties = [
      UyapParty('AYŞE KARACA', 'Davacı', 'Av. Deniz Kaya', 'Kişi'),
      UyapParty('B. İNŞAAT LTD. ŞTİ.', 'Davalı', 'Av. Murat Er', 'Kurum'),
    ];
    await store.keep(
      target: target,
      details: const UyapCaseDetails(),
      parties: parties,
      documents: UyapCaseDocuments([doc('a', 'Tensip Zaptı', '01.09.2026')]),
    );
    await store.keep(
      target: target,
      details: const UyapCaseDetails(),
      parties: parties,
      documents: UyapCaseDocuments([
        doc('a', 'Tensip Zaptı', '01.09.2026'),
        doc('b', 'Bilirkişi Raporu', '06.10.2026'),
      ]),
    );
  });

  tearDown(() {
    db.dispose();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Lets the page's reading of files and the database finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<List<String>> pumpList(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shown = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PortfolioPage(
            database: db,
            store: store,
            lawyer: 'Av. Deniz Kaya',
            onShowCase: shown.add,
          ),
        ),
      ),
    );
    await settle(tester);
    return shown;
  }

  testWidgets('the portfolio lists the open cases with what is new', (
    tester,
  ) async {
    final shown = await pumpList(tester, const Size(1440, 900));
    expect(tester.takeException(), isNull);
    expect(find.text('2024/318'), findsOneWidget);
    expect(find.text('2026/295'), findsOneWidget);
    // Closed cases wait under their filter.
    expect(find.text('2025/9184'), findsNothing);
    expect(find.text('1 yeni evrak'), findsOneWidget);
    expect(find.text('Yeni dosya'), findsOneWidget);
    expect(find.textContaining('Yeni: Bilirkişi Raporu'), findsOneWidget);
    expect(find.text('MÜVEKKİL'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('portfolio-closed')));
    await tester.pump();
    expect(find.text('2025/9184'), findsOneWidget);
    expect(find.text('2024/318'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('portfolio-open')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('portfolio-search')),
      'karaca',
    );
    await tester.pump();
    expect(find.text('2024/318'), findsOneWidget);
    expect(find.text('2026/295'), findsNothing);
    await tester.tap(find.text('2024/318'));
    expect(shown, [caseKey('2024/318', civil)]);
  });

  testWidgets('the channels’ chips are buttons, on a desktop and a phone', (
    tester,
  ) async {
    for (final size in const [Size(1440, 900), Size(390, 844)]) {
      await pumpList(tester, size);
      for (final key in const [
        'portfolio-connect-mobile',
        'portfolio-connect-web',
      ]) {
        final chip = find.byKey(ValueKey(key));
        expect(chip, findsOneWidget, reason: '$key at $size');
        expect(tester.widget<InkWell>(chip).onTap, isNotNull);
      }
    }
  });

  testWidgets('the portfolio fits a phone', (tester) async {
    await pumpList(tester, const Size(390, 844));
    expect(tester.takeException(), isNull);
    expect(find.text('2024/318'), findsOneWidget);
  });

  testWidgets('a case page marks its new documents and takes them off the '
      'new ones', (tester) async {
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
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CaseDetailPage(
            caseKey: caseKey('2024/318', civil),
            database: db,
            controller: controller,
            links: links,
            lawyer: 'Av. Deniz Kaya',
            onBack: () {},
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('case-number')), findsOneWidget);
    expect(find.text('YENİ'), findsOneWidget);
    expect(find.text('BİZİM TARAF · 1'), findsOneWidget);
    expect(find.text('KARŞI TARAF · 1'), findsOneWidget);
    // Seen: the list no longer counts it new.
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    final kept = await tester.runAsync(() => store.load(civil, '2024/318'));
    expect(kept!.fresh, isEmpty);
    expect(db.caseStates()[caseKey('2024/318', civil)]!.fresh, 0);
    await tester.tap(find.byKey(const ValueKey('case-tab-facts')));
    await tester.pump();
    expect(find.text('Mahkeme'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

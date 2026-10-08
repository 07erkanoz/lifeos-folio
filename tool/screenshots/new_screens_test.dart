// Pictures of the newer pages (the settings, UYAP's notifications), drawn
// from invented data with the app's real fonts, for checking them by eye
// and for lifeos.com.tr. Not part of the test suite:
//
//   flutter test tool/screenshots/new_screens_test.dart
//
// Pictures land in tool/screenshots/out/.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:ui' as ui;

import 'package:evrak_convert/services/office/office_chat.dart';
import 'package:evrak_convert/ui/office/messages_page.dart';
import 'package:evrak_convert/services/office/office_task.dart';
import 'package:evrak_convert/ui/office/tasks_page.dart';
import 'package:evrak_convert/ui/office/task_give_dialog.dart';
import 'package:evrak_convert/services/security/app_lock.dart';
import 'package:evrak_convert/ui/security/app_lock_gate.dart';
import 'package:evrak_convert/services/office/office_transfer.dart';
import 'package:evrak_convert/ui/office/office_offer_dialog.dart';
import 'package:evrak_convert/services/office/office_identity.dart';
import 'package:evrak_convert/services/office/office_known.dart';
import 'package:evrak_convert/services/office/office_ledger.dart';
import 'package:evrak_convert/services/office/office_pairing.dart';
import 'package:evrak_convert/services/security/secret_store.dart';
import 'package:evrak_convert/ui/office/office_pairing_dialog.dart';
import 'package:evrak_convert/services/office/office_network.dart';
import 'package:evrak_convert/services/office/office_peer.dart';
import 'package:evrak_convert/ui/office/office_network_page.dart';
import 'package:evrak_convert/ui/office/send_to_office.dart';
import 'package:evrak_convert/ui/office/inbox_page.dart';
import 'package:evrak_convert/services/office/office_inbox.dart';
import 'package:evrak_convert/ui/sync/sync_page.dart';
import 'package:evrak_convert/services/sync/own_sync.dart';
import 'package:evrak_convert/services/sync/folder_sync.dart';
import 'package:evrak_convert/ui/office/qr_pairing.dart';
import 'package:evrak_convert/services/editor/lawyer_profile.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_hearing.dart';
import 'package:evrak_convert/ui/portfolio/portfolio_rows.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/portal/uyap_notice.dart';
import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/ui/agenda/uyap_notices_page.dart';
import 'package:evrak_convert/ui/settings/settings_page.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/search/search_models.dart';
import 'package:evrak_convert/services/uyap/uyap_case_links.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/desktop/desktop_home.dart';
import 'package:evrak_convert/ui/search/global_search.dart';
import 'package:evrak_convert/ui/search/global_search_page.dart';
import 'package:evrak_convert/ui/theme/app_theme.dart';
import 'package:evrak_convert/ui/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const logical = Size(1440, 900);
const pixelRatio = 1.5;
final _frame = GlobalKey();

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
      );
    }
    await loader.load();
  }

  for (final name in ['FlutterTest', 'Ahem']) {
    await family(name, [
      for (final style in ['Regular', 'Bold'])
        'fonts/pdf/LiberationSans-$style.ttf',
    ]);
  }
  for (final name in ['Sans', 'Serif', 'Mono']) {
    await family('Liberation$name', [
      for (final style in ['Regular', 'Bold', 'Italic', 'BoldItalic'])
        'fonts/pdf/Liberation$name-$style.ttf',
    ]);
  }
  await family('Consolas', [
    for (final style in ['Regular', 'Bold'])
      'fonts/pdf/LiberationMono-$style.ttf',
  ]);
  final flutter = File(Platform.resolvedExecutable).parent.parent.parent.parent;
  final material = '${flutter.path}/artifacts/material_fonts';
  await family('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
  await family('Roboto', [
    for (final style in ['Regular', 'Medium', 'Bold'])
      '$material/Roboto-$style.ttf',
  ]);
}

Future<void> _shot(WidgetTester tester, String name) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  final boundary =
      _frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  final out = File('tool/screenshots/out/$name.png');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(bytes!);
}

Widget _app(Widget home) => RepaintBoundary(
  key: _frame,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    locale: const Locale('tr'),
    supportedLocales: const [Locale('tr')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: home,
  ),
);

void main() {
  setUpAll(_loadFonts);

  testWidgets('settings', (tester) async {
    tester.view.physicalSize = logical * pixelRatio;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    LawyerProfile.use(
      const LawyerProfile(
        lawyers: [
          Lawyer(
            name: 'Deniz Kaya',
            bar: 'Antalya Barosu',
            barNumber: '4821',
            idNumber: '12345678901',
          ),
        ],
      ),
    );
    final library = LibraryController(watchFolders: false);
    final appearance = ThemeController(
      settingsPath: '/nonexistent/appearance.json',
      mode: ThemeMode.light,
    );
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SettingsPage(
            library: library,
            appearance: appearance,
            onBack: () {},
          ),
        ),
      ),
    );
    await _shot(tester, 'ayarlar');
    await tester.tap(find.byKey(const ValueKey('settings-nav-look')));
    await tester.pumpAndSettle();
    await _shot(tester, 'ayarlar-gorunum');
    tester.view.physicalSize = const Size(390, 844) * pixelRatio;
    await tester.pumpWidget(
      _app(SettingsPage(library: library, appearance: appearance)),
    );
    await _shot(tester, 'ayarlar-telefon');
    await tester.pumpWidget(const SizedBox());
    library.dispose();
    appearance.dispose();
    LawyerProfile.use(null);
  });

  testWidgets('notices', (tester) async {
    tester.view.physicalSize = logical * pixelRatio;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    final db = PortalDatabase.memory();
    final sync = PortalSync(database: () async => db);
    db.mergeCases([
      PortalCase.create(
        number: '2024/318',
        court: 'Antalya 3. Asliye Hukuk Mahkemesi',
      ),
      PortalCase.create(number: '2025/4410', court: 'Antalya 6. İcra Dairesi'),
      PortalCase.create(
        number: '2025/201',
        court: 'Manavgat 2. Asliye Hukuk Mahkemesi',
      ),
    ], portfolio: true);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    UyapNoticeRow web(
      int id,
      String title,
      String body,
      DateTime at, {
      bool read = false,
    }) => UyapNoticeRow(
      source: UyapNoticeSource.web,
      id: '$id',
      title: title,
      body: body,
      sentAt: at,
      remoteRead: read,
    );
    db.saveUyapNotices([
      UyapNoticeRow(
        source: UyapNoticeSource.mobile,
        id: 'm1',
        messageId: 'x',
        title: 'Gerekçeli Karar',
        sentAt: today.add(const Duration(hours: 14, minutes: 5)),
      ),
      web(
        1,
        'Gerekçeli Karar',
        'Antalya 3. Asliye Hukuk Mahkemesi Biriminde Bulunan 2024/318 sayılı '
            'dosyaya gerekçeli karar eklenmiştir.',
        today.add(const Duration(hours: 14, minutes: 5, seconds: 31)),
      ),
      web(
        2,
        'İcra Dosyası Borç Tahsilatı',
        "Antalya 6. İcra Dairesi'nin 2025/4410 Esas sayılı dosyasında "
            '18.450,00 TL tahsilat yapılmıştır.',
        today.add(const Duration(hours: 11, minutes: 42)),
      ),
      web(
        3,
        'Bilirkişi Raporu Kaydedilmesi',
        'Manavgat 2. Asliye Hukuk Mahkemesi birimi, 2025/201 dosyasında '
            'bilirkişi raporu kaydedilmiştir.',
        today.add(const Duration(hours: 9, minutes: 18)),
      ),
      web(
        4,
        'Vekil Kaydı',
        'Kurum adına vekil kaydı yapılmıştır.',
        today.subtract(const Duration(hours: 14)),
        read: true,
      ),
      web(
        5,
        'Harç Tahsil Müzekkere Kaydı',
        'Antalya 3. Asliye Hukuk Mahkemesi Biriminde Bulunan 2024/318 sayılı '
            'dosyada harç tahsil müzekkeresi kaydedilmiştir.',
        today.subtract(const Duration(hours: 15)),
        read: true,
      ),
    ]);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: UyapNoticesPage(
            database: db,
            sync: sync,
            onOpenCase: (_) => true,
          ),
        ),
      ),
    );
    await _shot(tester, 'bildirimler-bos');
    await tester.tap(find.text('Gerekçeli Karar').first);
    await _shot(tester, 'bildirimler');
    await tester.pumpWidget(const SizedBox());
    tester.view.physicalSize = const Size(390, 844) * pixelRatio;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: UyapNoticesPage(
            database: db,
            sync: sync,
            onOpenCase: (_) => true,
          ),
        ),
      ),
    );
    await _shot(tester, 'telefon-bildirimler');
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
    db.dispose();
  });

  testWidgets('office network', (tester) async {
    final dir = Directory.systemTemp.createTempSync('folio_office_shot_');
    addTearDown(() => dir.deleteSync(recursive: true));
    OfficePeer peer(
      String id,
      String name,
      String device,
      OfficePlatform platform, {
      bool online = true,
    }) => OfficePeer(
      deviceId: id,
      userId: 'u$id',
      name: name,
      device: device,
      platform: platform,
      online: online,
      lastSeen: DateTime.now().subtract(const Duration(hours: 3)),
    );
    final net = OfficeNetwork(
      settings: () async => File('${dir.path}/buro.json'),
    );
    net.seenForTesting(
      peer('p1', 'Av. Deniz Kaya', 'deniz-telefon', OfficePlatform.android),
      self: peer('s', 'Av. Deniz Kaya', 'deniz-masaustu', OfficePlatform.linux),
    );
    for (final p in [
      peer(
        'p2',
        'Av. Deniz Kaya',
        'deniz-dizustu',
        OfficePlatform.windows,
        online: false,
      ),
      peer('p3', 'Av. Murat Er', 'murat-pc', OfficePlatform.windows),
      peer('p4', 'Av. Murat Er', 'Android telefon', OfficePlatform.android),
      peer('p5', 'Stj. Av. Mert Yıldız', 'mert-macbook', OfficePlatform.macos),
      peer('p6', 'Selin Aksoy', 'sekreterya', OfficePlatform.windows),
    ]) {
      net.seenForTesting(p);
    }
    for (final (size, name) in [
      (logical, 'buro-agi'),
      (const Size(390, 844), 'buro-agi-telefon'),
    ]) {
      tester.view.physicalSize = size * pixelRatio;
      tester.view.devicePixelRatio = pixelRatio;
      await tester.pumpWidget(
        _app(Scaffold(body: OfficeNetworkPage(network: net))),
      );
      await tester.pump();
      await _shot(tester, name);
    }
    tester.view.reset();
  });

  testWidgets('office pairing', (tester) async {
    final dir = Directory.systemTemp.createTempSync('folio_pair_shot_');
    addTearDown(() => dir.deleteSync(recursive: true));
    late OfficeNetwork a, b;
    late OfficePairing asking;
    await tester.runAsync(() async {
      Future<OfficeNetwork> folio(String name, String device) async {
        final net = OfficeNetwork(
          settings: () async => File('${dir.path}/$device.json'),
          known: KnownDevices(
            file: () async => File('${dir.path}/$device-k.json'),
          ),
        );
        final identity = await OfficeIdentity.load(store: _MemoryStore());
        await net.listenForTesting(
          identity,
          OfficePeer(
            deviceId: identity.deviceId,
            userId: identity.userId,
            name: name,
            device: device,
            platform: name.startsWith('Stj')
                ? OfficePlatform.macos
                : OfficePlatform.linux,
          ),
        );
        return net;
      }

      a = await folio('Stj. Av. Mert Yıldız', 'mert-macbook');
      b = await folio('Av. Deniz Kaya', 'deniz-masaustu');
      asking = a.pair(b.self!)!;
      for (var i = 0; i < 200 && b.incoming.value?.code == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    tester.view.physicalSize = logical * pixelRatio;
    tester.view.devicePixelRatio = pixelRatio;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Center(child: OfficePairingDialog(pairing: b.incoming.value!)),
        ),
      ),
    );
    await tester.pump();
    await _shot(tester, 'buro-tanima');
    await tester.runAsync(() async {
      asking.reject();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    tester.view.reset();
  });

  testWidgets('office transfer', (tester) async {
    final dir = Directory.systemTemp.createTempSync('folio_send_shot_');
    addTearDown(() => dir.deleteSync(recursive: true));
    late OfficeNetwork a, b;
    late OfficeTransfer offer;
    await tester.runAsync(() async {
      Future<OfficeNetwork> folio(String name, String device) async {
        final net = OfficeNetwork(
          settings: () async => File('${dir.path}/$device/buro.json'),
          known: KnownDevices(
            file: () async => File('${dir.path}/$device/k.json'),
          ),
          ledger: OfficeLedger(
            file: () async => File('${dir.path}/$device/d.json'),
          ),
          tasks: OfficeTasks(
            file: () async => File('${dir.path}/$device/g.json'),
          ),
          chats: OfficeChats(
            file: () async => File('${dir.path}/$device/m.json'),
          ),
        );
        Directory('${dir.path}/$device/gelen').createSync(recursive: true);
        net.inbox = () async => Directory('${dir.path}/$device/gelen');
        final identity = await OfficeIdentity.load(store: _MemoryStore());
        await net.listenForTesting(
          identity,
          OfficePeer(
            deviceId: identity.deviceId,
            userId: identity.userId,
            name: name,
            device: device,
            platform: OfficePlatform.linux,
          ),
        );
        return net;
      }

      Future<void> until(bool Function() done) async {
        for (var i = 0; i < 300 && !done(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      a = await folio('Av. Deniz Kaya', 'deniz-masaustu');
      b = await folio('Av. Murat Er', 'murat-pc');
      final asking = a.pair(b.self!)!;
      await until(() => b.incoming.value?.code != null);
      b.incoming.value!.confirm();
      asking.confirm();
      await until(() => b.isKnown(a.self!.deviceId));
      a.seenForTesting(b.self!);
      b.seenForTesting(a.self!);
      final f = File('${dir.path}/Bilirkişi Raporuna İtiraz.udf')
        ..writeAsBytesSync(List.filled(48000, 7));
      await a.send(b.self!, [
        f.path,
      ], note: 'Yarın öğlene kadar bakabilir misin?');
      await until(() => b.incomingOffer.value != null);
      offer = b.incomingOffer.value!;
    });
    tester.view.physicalSize = logical * pixelRatio;
    tester.view.devicePixelRatio = pixelRatio;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Center(
            child: OfficeOfferDialog(transfer: offer, onAccept: () async {}),
          ),
        ),
      ),
    );
    await tester.pump();
    await _shot(tester, 'buro-gelen-teklif');
    await tester.runAsync(() async {
      await b.acceptOffer(offer);
      for (var i = 0; i < 300 && !offer.finished; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpWidget(
      _app(Scaffold(body: OfficeNetworkPage(network: b))),
    );
    await tester.pump();
    await _shot(tester, 'buro-aktarimlar');
    await tester.runAsync(() async {
      await a.foundOffice('Kaya Hukuk Bürosu');
      await a.admit(b.self!.deviceId, OfficeRole.lawyer);
    });
    await tester.pumpWidget(
      _app(Scaffold(body: OfficeNetworkPage(network: a))),
    );
    await tester.pump();
    await _shot(tester, 'buro-uyeler');
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Center(child: QrInviteDialog(network: a)),
        ),
      ),
    );
    await _shot(tester, 'buro-qr');
    late OfficeTask shown;
    await tester.runAsync(() async {
      b.seenForTesting(a.self!);
      for (var i = 0; i < 100 && b.ledger.members.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final item = TaskItem.create(
        'İtiraz dilekçesini hazırla',
        assignee: b.self!.deviceId,
      );
      await a.giveTask(
        title: 'Bilirkişi raporuna itiraz',
        to: [b.self!.deviceId],
        note: 'Faiz başlangıcı hatalı; 20.05 tarihli beyanımıza dayanarak itiraz edelim.',
        due: DateTime.now().add(const Duration(days: 2)),
        priority: TaskPriority.high,
        cases: [
          TaskCase(
            caseKey: 'k1',
            number: '2024/318',
            court: 'Antalya 3. Asliye Hukuk Mahkemesi',
            items: [item, TaskItem.create('Tanık listesini güncelle')],
          ),
        ],
      );
      // A due day by a hearing, the hearing since moved.
      await a.giveTask(
        title: 'Bilirkişi raporuna beyan',
        to: [b.self!.deviceId],
        due: DateTime(2026, 11, 5),
        hearing: TaskHearing(
          hearingKey: 'eski-durusma',
          caseKey: caseKey('2025/412', 'Antalya 3. Asliye Hukuk Mahkemesi'),
          at: DateTime(2026, 11, 12, 10, 30),
          daysBefore: 7,
        ),
        cases: [
          TaskCase(
            caseKey: caseKey('2025/412', 'Antalya 3. Asliye Hukuk Mahkemesi'),
            number: '2025/412',
            court: 'Antalya 3. Asliye Hukuk Mahkemesi',
          ),
        ],
      );
      await a.giveTask(
        title: 'Haciz ihbarnamesine itiraz',
        to: [b.self!.deviceId],
        due: DateTime.now().subtract(const Duration(days: 1)),
        cases: const [
          TaskCase(
            caseKey: 'k2',
            number: '2025/4410',
            court: 'Antalya 6. İcra Dairesi',
          ),
        ],
      );
      for (var i = 0; i < 200 && b.tasks.all.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final t = b.tasks.all.firstWhere((t) => t.title.startsWith('Bilirkişi'));
      await b.act(t, TaskEventKind.accepted);
      await b.act(t, TaskEventKind.itemDone, itemId: item.id);
      await b.act(
        t,
        TaskEventKind.message,
        text: 'Taslak hazır, kaynakları kontrol ediyorum.',
      );
      await b.act(
        b.tasks.all.firstWhere((t) => t.title.startsWith('Haciz')),
        TaskEventKind.accepted,
      );
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      shown = a.tasks.all.firstWhere((t) => t.title.startsWith('Bilirkişi'));
    });
    final hearings = PortalDatabase.memory();
    addTearDown(hearings.dispose);
    hearings.mergeHearings(
      PortalChannel.uyapWeb,
      DateTime(2026, 10, 1),
      DateTime(2027, 2, 1),
      [
        PortalHearing(
          key: 'yeni-durusma',
          caseKey: caseKey('2025/412', 'Antalya 3. Asliye Hukuk Mahkemesi'),
          number: '2025/412',
          court: 'Antalya 3. Asliye Hukuk Mahkemesi',
          at: DateTime(2026, 12, 10, 10, 30),
        ),
      ],
      complete: true,
    );
    await tester.pumpWidget(
      _app(Scaffold(body: TasksPage(network: a, database: hearings))),
    );
    await tester.pump();
    await _shot(tester, 'gorevler');
    await tester.tap(find.byKey(const ValueKey('tasks-view-load')));
    await tester.pump();
    await _shot(tester, 'gorevler-is-yuku');
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Center(
            child: SizedBox(
              width: 820,
              height: 760,
              child: Card(
                child: TaskDetail(network: b, task: b.tasks.of(shown.id)!),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await _shot(tester, 'gorev-sayfasi');
    for (final (size, name) in [
      (logical, 'gorev-ver'),
      (const Size(390, 844), 'gorev-ver-telefon'),
    ]) {
      tester.view.physicalSize = size * pixelRatio;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: TaskGiveDialog(network: a, rows: const []),
          ),
        ),
      );
      await tester.pump();
      await _shot(tester, name);
    }
    await tester.tap(find.byKey(const ValueKey('task-more')));
    await tester.pump();
    await _shot(tester, 'gorev-ver-ayrinti');
    // A case with a hearing to come: "duruşmaya göre".
    final withHearing = PortfolioRow(
      kase: PortalCase.create(
        number: '2025/412',
        court: 'Antalya 3. Asliye Hukuk Mahkemesi',
      ),
      state: const CaseState(),
      hearing: PortalHearing(
        key: 'h',
        caseKey: caseKey('2025/412', 'Antalya 3. Asliye Hukuk Mahkemesi'),
        number: '2025/412',
        court: 'Antalya 3. Asliye Hukuk Mahkemesi',
        at: DateTime.now().add(const Duration(days: 35)),
      ),
      ours: const [],
      others: const [],
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: TaskGiveDialog(
            network: a,
            rows: [withHearing],
            initialCaseKey: withHearing.key,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('task-hearing-7')));
    await tester.pump();
    await _shot(tester, 'gorev-ver-durusma');
    tester.view.physicalSize = logical * pixelRatio;
    late String chatId;
    await tester.runAsync(() async {
      final chat = (await a.privateChat(b.self!.deviceId))!;
      chatId = chat.id;
      final pdf = File('${dir.path}/Ara Karar.pdf')
        ..writeAsBytesSync(List.filled(30000, 1));
      await a.post(
        chat,
        text: 'Ara kararı ekledim, duruşmadan önce okur musun?',
        files: [pdf.path],
      );
      for (
        var i = 0;
        i < 200 && (b.chats.of(chat.id)?.messages.isEmpty ?? true);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await b.post(
        b.chats.of(chat.id)!,
        text: 'Tamam, akşama kadar bakıyorum.',
      );
      final word = (await a.broadcastChat())!;
      await a.post(word, text: 'Cuma günü büro 14:00’te kapanacak.');
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Row(
            children: [
              SizedBox(width: 380, child: MessagesPage(network: b)),
              const VerticalDivider(width: 1),
              Expanded(
                child: ChatThread(network: b, chatId: chatId),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await _shot(tester, 'mesajlar');
    tester.view.reset();
  });

  testWidgets('app lock', (tester) async {
    final dir = Directory.systemTemp.createTempSync('folio_lock_shot_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final lock = AppLock(
      file: () async => File('${dir.path}/kilit.json'),
      iterations: 1000,
    );
    await tester.runAsync(() async {
      await lock.setPassword('büro-şifresi-1');
    });
    lock.lockNow();
    for (final (size, name) in [
      (logical, 'kilit'),
      (const Size(390, 844), 'kilit-telefon'),
    ]) {
      tester.view.physicalSize = size * pixelRatio;
      tester.view.devicePixelRatio = pixelRatio;
      await tester.pumpWidget(
        _app(
          AppLockGate(
            lock: lock,
            office: 'Kaya Hukuk Bürosu',
            child: const Scaffold(),
          ),
        ),
      );
      await tester.pump();
      await _shot(tester, name);
    }
    // Forgotten, with e-Devlet at hand.
    await tester.runAsync(() => lock.bindIdentity('12345678901'));
    tester.view.physicalSize = const Size(390, 844) * pixelRatio;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _app(
        AppLockGate(
          lock: lock,
          office: 'Kaya Hukuk Bürosu',
          identify: (_) async => null,
          child: const Scaffold(),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Şifremi unuttum'));
    await tester.pump();
    await _shot(tester, 'kilit-unuttum-telefon');
    lock.dispose();
    tester.view.reset();
  });

  testWidgets('senkron', (tester) async {
    final dir = Directory.systemTemp.createTempSync('folio_sync_shot_');
    addTearDown(() => dir.deleteSync(recursive: true));
    late OfficeNetwork pc;
    late OwnSync sync;
    late FolderSync folders;
    await tester.runAsync(() async {
      Future<OfficeNetwork> folio(String device, OfficePlatform os) async {
        final net = OfficeNetwork(
          settings: () async => File('${dir.path}/$device/buro.json'),
          known: KnownDevices(
            file: () async => File('${dir.path}/$device/k.json'),
          ),
          ledger: OfficeLedger(
            file: () async => File('${dir.path}/$device/d.json'),
          ),
          tasks: OfficeTasks(
            file: () async => File('${dir.path}/$device/g.json'),
          ),
          chats: OfficeChats(
            file: () async => File('${dir.path}/$device/m.json'),
          ),
        );
        final identity = await OfficeIdentity.load(store: _MemoryStore());
        await net.listenForTesting(
          identity,
          OfficePeer(
            deviceId: identity.deviceId,
            userId: identity.userId,
            name: 'Av. Deniz Kaya',
            device: device,
            platform: os,
          ),
        );
        return net;
      }

      pc = await folio('deniz-masaustu', OfficePlatform.windows);
      final phone = await folio('Telefon', OfficePlatform.android);
      pc.seenForTesting(phone.self!);
      phone.seenForTesting(pc.self!);
      final asking = pc.pair(phone.self!)!;
      for (var i = 0; i < 300 && phone.incoming.value?.code == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      phone.incoming.value!.confirm();
      asking.confirm();
      for (var i = 0; i < 300 && pc.self!.userId != phone.self!.userId; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final db = PortalDatabase.memory();
      sync = OwnSync(
        network: pc,
        database: () async => db,
        file: () async => File('${dir.path}/senkron.json'),
        sessions: _ShotSessions({'mobil'}),
      );
      await sync.start();
      await OwnSync(
        network: phone,
        database: () async => PortalDatabase.memory(),
        file: () async => File('${dir.path}/senkron-tel.json'),
        sessions: _ShotSessions({'uets'}),
      ).start();
      FolderSync make(OfficeNetwork net, String device) => FolderSync(
        network: net,
        file: () async => File('${dir.path}/$device/klasor.json'),
        bin: () async => Directory('${dir.path}/$device/cop'),
        root: () => '${dir.path}/$device/Senkron',
      );
      folders = make(pc, 'pc');
      await folders.start();
      final onPhone = make(phone, 'tel');
      await onPhone.start();
      final mine = Directory('${dir.path}/Dilekçeler')..createSync();
      for (var i = 1; i <= 3; i++) {
        File('${mine.path}/Dilekçe $i.pdf').writeAsStringSync('$i');
      }
      await folders.share(mine.path);
      final photos = Directory('${dir.path}/Tutanaklar')..createSync();
      File('${photos.path}/Tutanak.pdf').writeAsStringSync('t');
      await onPhone.share(photos.path);
      await pc.syncOwn();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    for (final (size, name) in [
      (logical, 'senkron'),
      (const Size(390, 844), 'senkron-telefon'),
    ]) {
      tester.view.physicalSize = size * pixelRatio;
      tester.view.devicePixelRatio = pixelRatio;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SyncPage(network: pc, sync: sync, folderSync: folders),
          ),
        ),
      );
      await tester.pump();
      await _shot(tester, name);
    }
    // Not yet on: one button, no office needed.
    final off = OfficeNetwork();
    tester.view.physicalSize = const Size(390, 844) * pixelRatio;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SyncPage(
            network: off,
            sync: OwnSync(network: off, sessions: _ShotSessions({})),
            folderSync: FolderSync(network: off),
          ),
        ),
      ),
    );
    await tester.pump();
    await _shot(tester, 'senkron-kapali');
    tester.view.reset();
  });

  testWidgets('gelenler', (tester) async {
    final inbox = _ShotInbox();
    for (final (size, name) in [
      (logical, 'gelenler'),
      (const Size(390, 844), 'gelenler-telefon'),
    ]) {
      tester.view.physicalSize = size * pixelRatio;
      tester.view.devicePixelRatio = pixelRatio;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: InboxPage(inbox: inbox, onOpen: (_) {}),
          ),
        ),
      );
      await tester.pump();
      await _shot(tester, name);
    }
    tester.view.reset();
  });

  testWidgets('send to office', (tester) async {
    final net = _Targets();
    for (final (size, name) in [
      (logical, 'gonder'),
      (const Size(390, 844), 'gonder-telefon'),
    ]) {
      tester.view.physicalSize = size * pixelRatio;
      tester.view.devicePixelRatio = pixelRatio;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _app(
          Scaffold(
            appBar: AppBar(
              title: const Text('Bilirkişi raporu'),
              actions: [
                SendToOfficeButton(paths: () => const [], network: net),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('send-to-office')));
      await tester.pump();
      await _shot(tester, name);
    }
    tester.view.reset();
  });

  testWidgets('global search', (tester) async {
    tester.view.physicalSize = logical * pixelRatio;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    final root = Directory.systemTemp.createTempSync('folio_shot_search_');
    addTearDown(() => root.deleteSync(recursive: true));
    final support = Directory('${root.path}/destek');
    final store = UyapCaseStore(
      directory: support,
      settings: UyapSettings(directory: support, home: '${root.path}/ev'),
    );
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    final at = DateTime.utc(2026, 10, 6);
    final courts = [
      ('2024/318', 'Antalya 3. Asliye Hukuk Mahkemesi', 'Alacak'),
      ('2025/77', 'Antalya 2. İş Mahkemesi', 'İşçi Alacağı'),
      ('2025/9184', 'Antalya 5. İcra Dairesi', 'İlamsız Takip'),
    ];
    db.mergeCases([
      for (final (n, c, _) in courts)
        PortalCase(
          key: caseKey(n, c),
          number: n,
          court: c,
          status: Observed('Açık', PortalChannel.uyapMobile, at),
        ),
    ], portfolio: true, baseline: true);
    UyapCaseDocument doc(String key, String type, String day) =>
        UyapCaseDocument(
          key: key,
          documentId: key,
          caseId: '1',
          type: type,
          number: key,
          approved: '$day 10:00',
          sender: 'Mahkeme',
          description: '',
        );
    var i = 0;
    for (final (n, c, kind) in courts) {
      i++;
      await tester.runAsync(
        () => store.keep(
          target: UyapCase('$i', n, '', c),
          details: UyapCaseDetails(kind: kind),
          parties: [
            const UyapParty('AYŞE KARACA', 'Davacı', 'Av. Deniz Kaya', 'Kişi'),
            UyapParty('KARACA YAPI A.Ş. $i', 'Davalı', 'Av. Murat Er', 'Kurum'),
          ],
          documents: UyapCaseDocuments([
            doc('a$i', 'Karaca Bilirkişi Raporu', '0$i.10.2026'),
          ]),
        ),
      );
    }
    db.saveAgenda(
      AgendaItem(
        id: 'n1',
        kind: 'deadline',
        title: 'Karaca bilirkişi raporuna itiraz',
        at: DateTime(2026, 10, 20),
        allDay: true,
        updated: at,
      ),
    );
    final search = GlobalSearch(
      lawyer: 'Av. Deniz Kaya',
      database: db,
      store: store,
      archive: (text, limit) async => SearchPage([
        for (final name in [
          'Karaca vekaletname.pdf',
          'Karaca cevap dilekçesi.udf',
        ])
          SearchHit(
            file: EvrakFile.fromPath('${root.path}/$name'),
            excerpt: '… davacı Ayşe Karaca vekili olarak …',
          ),
      ], 2, 0),
    );
    await tester.runAsync(() => search.find('karaca'));
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: DesktopHome(
            name: 'Av. Deniz Kaya',
            recent: const [],
            office: const DesktopHomeOffice(),
            links: UyapCaseLinks(directory: support),
            search: search,
            onFound: (_) {},
            onShowCases: (_) {},
            onSearch: (_) {},
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
    final field = find.byKey(const ValueKey('home-search'));
    await tester.tap(field);
    await tester.enterText(field, 'karaca');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await _shot(tester, 'genel-arama');
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(_app(GlobalSearchPage(search: search)));
    await tester.enterText(
      find.byKey(const ValueKey('phone-search')),
      'karaca',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, 'genel-arama-telefon');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
  });
}

class _MemoryStore extends SecretStore {
  final _kept = <String, Map<String, Object?>>{};
  @override
  Future<bool> write(String name, Map<String, Object?> value) async {
    _kept[name] = value;
    return true;
  }

  @override
  Future<Map<String, Object?>?> read(String name) async => _kept[name];
}

class _Targets extends OfficeNetwork {
  @override
  List<SendTarget> get sendTargets => const [
    SendTarget(
      deviceId: 'a',
      name: 'Av. Deniz Yılmaz',
      detail: 'Stajyer',
      member: true,
      online: true,
    ),
    SendTarget(
      deviceId: 'b',
      name: 'Ayşe Kara',
      detail: 'Sekreter',
      member: true,
      online: false,
    ),
    SendTarget(
      deviceId: 'c',
      name: 'Kendi cihazım',
      detail: 'Telefon',
      member: false,
      online: true,
    ),
  ];
}

class _ShotSessions implements SessionHolder {
  _ShotSessions(this.open);
  final Set<String> open;
  @override
  bool holds(String kind) => open.contains(kind);
  @override
  Map<String, Object?>? sessionOf(String kind) => null;
  @override
  Future<bool> takeSession(String kind, Object? kept) async => false;
  @override
  void listen(VoidCallback changed) {}
  @override
  Future<Map<String, Object?>?> freshMobile() async => null;
  @override
  bool keepMobileAlike(Object? theirs) => false;
  @override
  void renewMobileThrough(Future<Map<String, Object?>?> Function()? ask) {}
  @override
  void listenMobileTokens(VoidCallback changed) {}
}

class _ShotInbox extends OfficeInbox {
  _ShotInbox() : super(network: OfficeNetwork());
  final _now = DateTime.now();
  @override
  List<InboxItem> get items => [
    InboxItem(
      id: '1',
      from: 'Av. Deniz Kaya',
      device: 'Telefon',
      names: const ['2024-12-31 Reddiyat Makbuzu.pdf'],
      paths: const ['/yok/a.pdf'],
      size: 453025,
      note: '2024/318 bilirkişi raporu, yarın bakılacak',
      at: _now.subtract(const Duration(minutes: 5)),
    ),
    InboxItem(
      id: '2',
      from: 'Av. Murat Er',
      device: 'murat-pc',
      names: const ['Bilirkişi Raporuna İtiraz.udf'],
      paths: const ['/yok/b.udf'],
      size: 48000,
      note: 'Yarın öğlene kadar bakabilir misin?',
      at: _now.subtract(const Duration(hours: 2)),
      withMessage: true,
    ),
    InboxItem(
      id: '3',
      from: 'Av. Deniz Kaya',
      device: 'Telefon',
      names: const ['Keşif 1.jpg', 'Keşif 2.jpg', 'Keşif 3.jpg'],
      paths: const ['/yok/c.jpg'],
      size: 6200000,
      note: '',
      at: _now.subtract(const Duration(days: 1)),
    ),
  ];
  @override
  bool isNew(InboxItem i) => i.id != '3';
  @override
  Future<void> reload() async {}
}

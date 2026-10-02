import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/uyap/uyap_case_links.dart';
import 'package:evrak_convert/services/uyap/uyap_case_panel_controller.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/widgets/uyap_case_panel.dart';
import 'package:evrak_convert/ui/widgets/uyap_case_picker.dart';
import 'package:evrak_convert/ui/widgets/uyap_cases_page.dart';

/// A stand-in for the Avukat Portal with one case in it, whose ids change
/// with every login as the real ones do.
class _Portal {
  late HttpServer server;
  var logins = 0;
  final documents = <String>['1', '2'];

  /// Documents of a case tied to this one, listed by UYAP before its own.
  final related = <String>[];
  final fetched = <String>[];

  /// Documents filed as UDF come back as UDF.
  var udf = false;

  /// What UYAP lets be seen of the case; a court case's by default.
  var permissions =
      'ayrinti_bilgileri,taraf_bilgileri,evrak_bilgileri,'
      'tahsilat_reddiyat_bilgileri';
  final asked = <String>[];

  Uri get uri => Uri.parse('http://${server.address.host}:${server.port}');

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final r = request.response;
      r.headers.set('Content-Type', 'text/json; charset=utf-8');
      final session = request.cookies
          .where((c) => c.name == 'JSESSIONID')
          .map((c) => c.value)
          .firstOrNull;
      // This session's id for the case and its documents.
      final id = 'oturum$logins';
      final sent = await utf8.decoder.bind(request).join();
      asked.add(request.uri.path);
      Object? body;
      switch (request.uri.path) {
        case '/portal_baslangic.uyap':
          r.cookies.add(Cookie('JSESSIONID', 'yeni'));
        case '/kullanici_bilgileri.uyap' when request.method == 'GET':
          body = {'level': session == 'girildi$logins' ? 2 : 0, 'random': 0};
        case '/login.uyap':
          logins++;
          r.cookies.add(Cookie('JSESSIONID', 'girildi$logins'));
        case '/kullanici_bilgileri.uyap':
          body = {'adi': 'Ayşe', 'soyadi': 'Kaya'};
        case '/search_phrase_detayli.ajx':
          body = [
            [
              {
                'dosyaId': 'dava-$id',
                'dosyaNo': '2026/1204',
                'birimId': 'c5',
                'birimAdi': 'İstanbul 5. Aile Mahkemesi',
                'dosyaTur': 'Hukuk Dava Dosyası',
                'dosyaTurKod': 15,
                'dosyaDurum': 'Açık',
                'dosyaAcilisTarihi': {
                  'date': {'year': 2026, 'month': 3, 'day': 2},
                  'time': {'hour': 9, 'minute': 5},
                },
              },
            ],
            1,
          ];
        case '/dosya_islem_turleri_sorgula_brd.ajx':
          body = {'15': permissions};
        case '/dosya_tahsilat_reddiyat_bilgileri_brd.ajx':
          // Not answered without the kind of case.
          if (!sent.contains('"dosyaTurKod":15')) break;
          body = {
            'toplamTahsilat': 1250.5,
            'toplamreddiyat': 200,
            'toplamKalan': 1050.5,
            'harcList': [
              {
                'tahsilatTuru': 'Başvurma Harcı',
                'tahsilatTarihi': '02/03/2026',
                'yatirilanMiktar': 615.4,
                'makbuzNo': 'M1',
                'odeyenKisi': 'Ali Veli',
              },
            ],
            'tahsilatList': [],
            'reddiyatList': [
              {
                'reddiyatNedeni': 'Gider avansı iadesi',
                'reddiyatTarihi': '10/09/2026',
                'miktar': 200,
              },
            ],
          };
        case '/dosyaAyrintiBilgileri_brd.ajx':
          body = {
            'davaTurleriStr': 'Boşanma',
            'durusmaTarihiStr': '12/11/2026 10:30',
          };
        case '/dosya_taraf_bilgileri_brd.ajx':
          body = [
            {'adi': 'Ali Veli', 'rol': 'Davacı', 'vekil': 'Av. Ayşe Kaya'},
            {'adi': 'Ayten Veli', 'rol': 'Davalı', 'vekil': ''},
          ];
        case '/list_dosya_evraklar.ajx':
          body = {
            'pageTotal': 1,
            'tumEvraklar': {
              if (related.isNotEmpty)
                '2025/686(Hukuk Dava Dosyası)##y': [
                  for (final n in related)
                    {
                      'evrakId': '$id-evrak$n',
                      'dosyaId': 'dava-$id',
                      'evrakTuruAciklama': 'Görevsizlik Kararı',
                      'birimEvrakNo': n,
                      'onayTarihi': '01/01/2026',
                      'gonderenYerKisi': 'Mahkeme',
                    },
                ],
              '2026/1204(Hukuk Dava Dosyası)##x': [
                for (final n in documents)
                  {
                    'evrakId': '$id-evrak$n',
                    'dosyaId': 'dava-$id',
                    'evrakTuruAciklama': n == '2'
                        ? 'Bilirkişi Raporu'
                        : 'Dava Dilekçesi',
                    'birimEvrakNo': n,
                    'onayTarihi': '0$n/10/2026',
                    'gonderenYerKisi': 'Davacı Vekili',
                  },
              ],
            },
            'son20Evrak': [],
          };
        case '/download_document_brd.uyap':
          final evrak = request.uri.queryParameters['evrakId']!;
          // As the portal's own "Evrak İndir": by the case opened.
          if (request.uri.queryParameters['dosyaId'] != 'dava-$id') break;
          // Only this session's ids are answered; an old one gets nothing.
          if (!evrak.startsWith(id)) break;
          fetched.add(evrak);
          if (udf) {
            r.headers.set('Content-Type', 'application/octet-stream');
            r.add(
              ZipEncoder().encodeBytes(
                Archive()
                  ..add(ArchiveFile.bytes('content.xml', utf8.encode(evrak))),
              ),
            );
          } else {
            r.headers.set('Content-Type', 'application/pdf');
            r.add(utf8.encode('%PDF-1.4 $evrak'));
          }
        default:
          r.statusCode = 404;
      }
      if (body != null) r.write(jsonEncode(body));
      await r.close();
    });
  }

  Future<void> login(UyapWebService web) async {
    final start = await web.beginEdevlet(EdevletMethod.mobile);
    await web.finishEdevlet(start, 'kod');
  }
}

void main() {
  late Directory root;
  late _Portal portal;
  late UyapWebService web;
  late UyapCaseStore store;
  late UyapCaseLinks links;
  final saved = UyapWebService.instance;

  setUp(() async {
    // The widget test below makes this a widget test file, whose binding
    // answers every request with 400; the stand-in portal is a real server.
    HttpOverrides.global = null;
    root = Directory.systemTemp.createTempSync('folio-uyap-panel-');
    portal = _Portal();
    await portal.start();
    web = UyapWebService.forTesting(portal: portal.uri);
    UyapWebService.instance = web;
    store = UyapCaseStore(
      directory: Directory('${root.path}/destek'),
      settings: UyapSettings(
        directory: Directory('${root.path}/destek'),
        home: '${root.path}/ev',
      ),
    );
    links = UyapCaseLinks(directory: Directory('${root.path}/destek'));
  });
  tearDown(() async {
    UyapWebService.instance = saved;
    await portal.server.close(force: true);
    root.deleteSync(recursive: true);
  });

  UyapCasePanelController panel() => UyapCasePanelController(
    web: web,
    store: store,
    links: links,
    pause: Duration.zero,
  );

  const link = UyapCaseLink(
    jurisdiction: '1',
    courtType: '0926',
    courtId: 'c5',
    court: 'İstanbul 5. Aile Mahkemesi',
    number: '2026/1204',
  );

  test('a document tied to a case finds it again, keeps what it fetched, '
      'and reads it back without a connection', () async {
    await portal.login(web);
    final c = panel();
    await c.bind('${root.path}/cevap.udf');
    expect(c.link, isNull);
    await c.choose(link, await web.findCase(link));
    expect(c.error, isNull);
    final record = c.record!;
    expect(record.details.kind, 'Boşanma');
    expect(record.details.hearing, '12/11/2026 10:30');
    expect(record.parties.map((t) => t.name), ['Ali Veli', 'Ayten Veli']);
    expect(c.documents.map((d) => d.title), [
      'Dava Dilekçesi',
      'Bilirkişi Raporu',
    ]);
    c.query = 'bilirkisi';
    expect(c.documents.map((d) => d.key), ['2']);
    c.query = '';

    // Another time, with no connection: the tie and the case are there.
    web.disconnect();
    final later = panel();
    await later.bind('${root.path}/cevap.udf');
    expect(later.link?.number, '2026/1204');
    expect(later.record?.documents.length, 2);
  });

  test('the case goes with the document under a new name, and not to '
      'another document opened in its place', () async {
    await portal.login(web);
    final c = panel();
    // Chosen before the document was ever saved.
    await c.bind(null);
    await c.choose(link, await web.findCase(link));
    await c.bind('${root.path}/cevap.udf', carry: true);
    expect((await links.of('${root.path}/cevap.udf'))?.number, '2026/1204');
    // Saved as another, or signed into a copy.
    await c.bind('${root.path}/cevap_imzali.udf', carry: true);
    expect(
      (await links.of('${root.path}/cevap_imzali.udf'))?.number,
      '2026/1204',
    );
    expect(c.link?.number, '2026/1204');
    // Another document opened in the same editor.
    await c.bind('${root.path}/baska.udf');
    expect(c.link, isNull);
    expect(await links.of('${root.path}/baska.udf'), isNull);
  });

  test('a document is fetched once and opened from disk after, even in a '
      'session whose ids are not the ones the list was fetched with', () async {
    await portal.login(web);
    final c = panel();
    var saves = 0;
    c.onSaved = (_) => saves++;
    await c.bind('${root.path}/cevap.udf');
    await c.choose(link, await web.findCase(link));
    final report = c.documents.last;
    final file = await c.open(report);
    expect(file, isNotNull);
    expect(await file!.readAsString(), '%PDF-1.4 oturum1-evrak2');
    expect(file.path, endsWith('2026-10-02 Bilirkişi Raporu.pdf'));
    expect(c.isSaved(report.key), isTrue);
    expect(saves, 1);

    // A new login: the case and its documents have new ids. What is on
    // disk opens as it is; what is not is fetched by the new ids.
    web.disconnect();
    await portal.login(web);
    final again = panel();
    await again.bind('${root.path}/cevap.udf');
    expect((await again.open(again.documents.last))!.path, file.path);
    expect(portal.fetched, ['oturum1-evrak2']);
    final petition = await again.open(again.documents.first);
    expect(petition, isNotNull, reason: again.error);
    expect(portal.fetched.last, 'oturum2-evrak1');
  });

  test(
    'the document itself is fetched, a UDF as a UDF; the PDF an earlier '
    'Folio saved in its place is not taken for it, and gives way to it',
    () async {
      await portal.login(web);
      final c = panel();
      await c.bind('${root.path}/cevap.udf');
      await c.choose(link, await web.findCase(link));
      // As an earlier Folio left it: the portal's PDF of the document,
      // recorded as the document.
      final folder = store.folderOf(c.record!);
      await Directory(folder).create(recursive: true);
      final old = File('$folder/2026-10-02 Bilirkişi Raporu.pdf')
        ..writeAsStringSync('%PDF eski');
      final legacy = jsonDecode(
        jsonEncode(c.record!.copyWith(files: {'2': old.path}).toJson()),
      ) as Map<String, Object?>;
      legacy['surum'] = 1;
      final records = Directory('${root.path}/destek/uyap/dosyalar');
      File('${records.path}/${c.record!.key}.json')
          .writeAsStringSync(jsonEncode(legacy));

      portal.udf = true;
      final again = panel();
      await again.bind('${root.path}/cevap.udf');
      expect(again.isSaved('2'), isFalse, reason: 'a PDF of it is not it');
      final file = await again.open(again.documents.last);
      expect(file, isNotNull, reason: again.error);
      expect(file!.path, endsWith('2026-10-02 Bilirkişi Raporu.udf'));
      expect(UyapCaseStore.kindOf(await file.readAsBytes()), 'udf');
      expect(old.existsSync(), isFalse);
      expect(again.isSaved('2'), isTrue);
    },
  );

  test('what came since the last fetch is new; everything is downloaded '
      'once', () async {
    await portal.login(web);
    final c = panel();
    await c.bind('${root.path}/cevap.udf');
    await c.choose(link, await web.findCase(link));
    expect(c.isNew('1'), isFalse);
    portal.documents.add('3');
    await c.refresh();
    expect(c.isNew('3'), isTrue);
    expect(c.isNew('1'), isFalse);
    expect(await c.download(), 3);
    expect(c.isNew('3'), isFalse, reason: 'downloaded is looked at');
    expect(await c.download(), 0, reason: 'nothing twice');
  });

  testWidgets('the panel shows the case, marks what is new, and narrows the '
      'list as the lawyer types', (tester) async {
    final c = panel();
    await tester.runAsync(() async {
      await portal.login(web);
      await c.bind('${root.path}/cevap.udf');
      await c.choose(link, await web.findCase(link));
      portal.documents.add('3');
      await c.refresh();
    });
    String? inserted;
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UyapCasePanel(
            controller: c,
            onOpen: (_, _) {},
            onInsert: (text) => inserted = text,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('2026/1204'), findsOneWidget);
    expect(find.text('12/11/2026 10:30'), findsOneWidget);
    expect(find.text('1 yeni'), findsOneWidget);
    expect(find.text('Yeni'), findsOneWidget);
    await tester.tap(find.byTooltip('Metne ekle').first);
    expect(inserted, 'Ali Veli');
    await tester.enterText(
      find.byKey(const ValueKey('uyap-panel-search')),
      'rapor',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('uyap-doc-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('uyap-doc-1')), findsNothing);
  });

  test('a case has a page of its own, with no document, and a document is '
      'tied to a kept case without UYAP', () async {
    await portal.login(web);
    final adding = panel();
    // Added from the page: no document is tied to it.
    await adding.choose(link, await web.findCase(link));
    expect(adding.error, isNull);
    final record = adding.record!;
    expect(record.link?.courtType, '0926', reason: 'where it is in UYAP');
    expect(await links.of('${root.path}/cevap.udf'), isNull);

    // The page, another time: refreshed from UYAP by what the record says.
    final page = panel();
    await page.show((await store.load(link.court, link.number))!);
    expect(page.findable, isTrue);
    portal.documents.add('3');
    await page.refresh();
    expect(page.error, isNull);
    expect(page.record!.fresh, {'3'});

    // A petition tied to the kept case with no connection at all.
    web.disconnect();
    final editor = panel();
    await editor.bind('${root.path}/cevap.udf');
    await editor.attach(record.link!);
    expect(editor.record?.documents.length, 3);
    expect((await links.of('${root.path}/cevap.udf'))?.number, '2026/1204');
  });

  test('a case an earlier Folio kept without its place finds it from a '
      'document tied to it', () async {
    await portal.login(web);
    final c = panel();
    await c.bind('${root.path}/cevap.udf');
    await c.choose(link, await web.findCase(link));
    // As an earlier Folio wrote it: no "bag".
    final file = File(
      '${root.path}/destek/uyap/dosyalar/${c.record!.key}.json',
    );
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>
      ..remove('bag');
    file.writeAsStringSync(jsonEncode(json));
    final old = (await store.load(link.court, link.number))!;
    expect(old.link, isNull);
    final page = panel();
    await page.show(old);
    expect(page.findable, isTrue);
    expect(page.link?.courtId, 'c5');
  });

  testWidgets('the cases page lists the kept cases, offers to connect, and '
      'opens a case with what was downloaded of it', (tester) async {
    final c = panel();
    await tester.runAsync(() async {
      await portal.login(web);
      await c.choose(link, await web.findCase(link));
      await c.download({'2'});
      web.disconnect();
      // A petition tied to the case.
      File('${root.path}/cevap.udf').writeAsStringSync('x');
      await links.link('${root.path}/cevap.udf', link);
    });
    final stores = (
      UyapCaseStore.instance,
      UyapSettings.instance,
      UyapCaseLinks.instance,
    );
    UyapCaseStore.instance = store;
    UyapSettings.instance = store.settings;
    UyapCaseLinks.instance = links;
    addTearDown(() {
      UyapCaseStore.instance = stores.$1;
      UyapSettings.instance = stores.$2;
      UyapCaseLinks.instance = stores.$3;
    });
    tester.view.physicalSize = const Size(1300, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shown = <String?>[];
    File? opened;
    // The kept cases are read from disk on the real clock, a step at a time.
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    Widget page(String? key) => MaterialApp(
      home: Scaffold(
        body: UyapCasesPage(
          caseKey: key,
          onShowCase: shown.add,
          onOpen: (file) => opened = file,
        ),
      ),
    );
    await tester.pumpWidget(page(null));
    await settle();
    expect(find.byKey(const ValueKey('uyap-cases-connect')), findsOneWidget);
    expect(find.byKey(const ValueKey('uyap-cases-add')), findsOneWidget);
    expect(find.text('2026/1204'), findsOneWidget);
    expect(find.text('1 / 2 evrak'), findsOneWidget);
    // The parties by their role, and a search over them.
    expect(find.text('Davacı: Ali Veli · Davalı: Ayten Veli'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('uyap-cases-search')),
      'ayten',
    );
    await tester.pump();
    expect(find.text('2026/1204'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('uyap-cases-search')),
      'mehmet',
    );
    await tester.pump();
    expect(find.text('Aramaya uyan dosya yok.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('uyap-cases-search')), '');
    await tester.pump();
    // Nothing new in it: the filter leaves it out.
    await tester.tap(find.byKey(const ValueKey('uyap-cases-filter-yeni')));
    await tester.pump();
    expect(find.text('2026/1204'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('uyap-cases-filter-yeni')));
    await tester.pump();
    expect(find.text('2026/1204'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('uyap-cases-${c.record!.key}')));
    expect(shown, [c.record!.key]);

    await tester.pumpWidget(page(c.record!.key));
    await settle();
    // On a wide screen the particulars stand beside the tabs.
    expect(find.text('Boşanma'), findsOneWidget);
    expect(find.text('Evraklar · 2'), findsOneWidget);
    // Nothing to write into here.
    expect(find.byTooltip('Metne ekle'), findsNothing);
    await tester.tap(find.text('İndirilen · 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('uyap-saved-2')));
    expect(opened?.path, endsWith('.pdf'));
    // The petition written for the case, by the path its tie keeps.
    await tester.tap(find.text('Dilekçeler · 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('cevap.udf'));
    expect(opened?.path, endsWith('cevap.udf'));

    // A petition begun from here is written for this case.
    UyapCaseLink? petition;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UyapCasesPage(
            caseKey: c.record!.key,
            onShowCase: shown.add,
            onOpen: (file) => opened = file,
            onNewPetition: (link) => petition = link,
          ),
        ),
      ),
    );
    await settle();
    await tester.tap(find.byKey(const ValueKey('uyap-case-new-petition')));
    expect(petition?.number, '2026/1204');
    expect(petition?.courtId, 'c5');

    await tester.tap(find.byTooltip('Dosya işlemleri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Listeden kaldır…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('uyap-case-remove-confirm')));
    await settle();
    expect(shown.last, isNull, reason: 'back to the list');
    expect(await tester.runAsync(store.cases), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tying a document offers the kept cases first, and takes one '
      'with no connection', (tester) async {
    final c = panel();
    await tester.runAsync(() async {
      await portal.login(web);
      await c.choose(link, await web.findCase(link));
      web.disconnect();
    });
    final previous = UyapCaseStore.instance;
    UyapCaseStore.instance = store;
    addTearDown(() => UyapCaseStore.instance = previous);
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    (UyapCaseLink, UyapCase?)? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                chosen = await UyapCasePicker.show(context, offerKept: true),
            child: const Text('bağla'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('bağla'));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('Bu bilgisayardaki dosyalar'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('uyap-kept-${c.record!.key}')));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(chosen?.$1.courtId, 'c5');
    expect(chosen?.$2, isNull, reason: 'not looked for in UYAP');
  });

  test('a refresh asks what UYAP shows of the case first, keeps the list\'s '
      'state and dates, and the fees and collections', () async {
    await portal.login(web);
    final c = panel();
    await c.choose(link, await web.findCase(link));
    expect(c.error, isNull);
    final record = c.record!;
    expect(record.details.fileType, 'Hukuk Dava Dosyası');
    expect(record.details.openedOn, '02.03.2026');
    expect(record.money?.collected, 1250.5);
    expect(record.money?.paidOut, 200, reason: 'toplamreddiyat, lower-case');
    expect(record.money?.fees.single.kind, 'Başvurma Harcı');
    expect(record.money?.payments.single.amount, 200);
    expect(record.hidden, isEmpty);
    // Read back from disk as kept.
    final read = (await store.load(link.court, link.number))!;
    expect(read.money?.fees.single.receipt, 'M1');
    expect(read.details.openedOn, '02.03.2026');
  });

  test('a case of a kind UYAP shows no particulars of is not asked for '
      'them', () async {
    portal.permissions = 'taraf_bilgileri,evrak_bilgileri';
    await portal.login(web);
    final c = panel();
    await c.choose(link, await web.findCase(link));
    expect(c.error, isNull);
    expect(portal.asked, isNot(contains('/dosyaAyrintiBilgileri_brd.ajx')));
    expect(
      portal.asked,
      isNot(contains('/dosya_tahsilat_reddiyat_bilgileri_brd.ajx')),
    );
    expect(c.record!.hidden, {'ayrinti_bilgileri'});
    expect(c.record!.documents, isNotEmpty);
  });

  testWidgets('the case search starts with no year, so it lists every case '
      'of the court; a case looked for comes filled in', (tester) async {
    await tester.runAsync(() => portal.login(web));
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> open(String? number) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => UyapCasePicker.show(context, number: number),
              child: const Text('bağla'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('bağla'));
      await tester.pump();
      await tester.pump();
    }

    String field(String label) => tester
        .widget<TextField>(find.widgetWithText(TextField, label))
        .controller!
        .text;
    await open(null);
    expect(field('Yıl (boş: tümü)'), isEmpty);
    expect(field('Esas sıra no (boş: tümü)'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await open('2026/191');
    expect(field('Yıl (boş: tümü)'), '2026');
    expect(field('Esas sıra no (boş: tümü)'), '191');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the case\'s own documents come first and open; a tied case\'s '
      'come after, closed until opened', (tester) async {
    final c = panel();
    portal.related.add('9');
    await tester.runAsync(() async {
      await portal.login(web);
      await c.bind('${root.path}/cevap.udf');
      await c.choose(link, await web.findCase(link));
    });
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UyapCasePanel(
            controller: c,
            onOpen: (_, _) {},
            onInsert: (_) {},
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    final own = find.byKey(
      const ValueKey('uyap-group-2026/1204(Hukuk Dava Dosyası)'),
    );
    final tied = find.byKey(
      const ValueKey('uyap-group-2025/686(Hukuk Dava Dosyası)'),
    );
    expect(tester.getTopLeft(own).dy, lessThan(tester.getTopLeft(tied).dy));
    expect(find.byKey(const ValueKey('uyap-doc-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('uyap-doc-9')), findsNothing);
    await tester.tap(tied);
    await tester.pump();
    expect(find.byKey(const ValueKey('uyap-doc-9')), findsOneWidget);
    await tester.tap(own);
    await tester.pump();
    expect(find.byKey(const ValueKey('uyap-doc-1')), findsNothing);
    // A search opens what it finds.
    await tester.enterText(
      find.byKey(const ValueKey('uyap-panel-search')),
      'dilekçe',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('uyap-doc-1')), findsOneWidget);
  });
}

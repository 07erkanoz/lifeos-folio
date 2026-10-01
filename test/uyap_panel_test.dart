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

/// A stand-in for the Avukat Portal with one case in it, whose ids change
/// with every login as the real ones do.
class _Portal {
  late HttpServer server;
  var logins = 0;
  final documents = <String>['1', '2'];
  final fetched = <String>[];

  /// Documents filed as UDF come back as UDF.
  var udf = false;

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
              },
            ],
            1,
          ];
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
}

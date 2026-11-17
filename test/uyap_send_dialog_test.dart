import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:evrak_convert/services/uyap/uyap_case_links.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/widgets/uyap_send_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_path_provider.dart';
import 'support/pdfium.dart';

const _court = 'Ankara 3. Asliye Hukuk Mahkemesi';

/// The web portal with one court and its one case.
class _Web extends UyapWebService {
  _Web() : super.forTesting() {
    session.value = UyapSession(
      user: 'DENİZ KAYA',
      since: DateTime.now(),
      route: UyapLoginRoute.tray,
    );
  }

  /// The times a court's cases were listed.
  int listed = 0;

  @override
  bool get connected => true;

  @override
  Future<List<UyapOption>> courtTypes(String jurisdiction) async => const [
    UyapOption('HUKUK', 'Hukuk'),
  ];

  @override
  Future<List<UyapOption>> courts(
    String jurisdiction,
    String courtType, {
    bool closed = false,
  }) async => const [UyapOption('h1', _court)];

  @override
  Future<UyapCasePage> casePage({
    required String jurisdiction,
    required String courtType,
    required UyapOption court,
    int? year,
    int? number,
    bool closed = false,
    int pageNumber = 1,
  }) async {
    listed++;
    return const UyapCasePage([UyapCase('id-1', '2025/80', 'h1', _court)], 1);
  }

  @override
  Future<List<UyapDocumentType>> documentTypes(UyapCase target) async => const [
    UyapDocumentType('1', 'Beyan Dilekçesi', '1', false, 1, 0, {'udf'}),
    UyapDocumentType('2', 'İstinaf Başvurusu', '1', false, 1, 5, {'udf'}),
  ];

  /// The kinds UYAP says take a fee on the case.
  Set<String> paid = const {};

  @override
  Future<Set<String>> paidDocumentCodes(UyapCase target) async => paid;

  @override
  Future<List<UyapParty>> parties(UyapCase target) async => const [
    UyapParty('AYŞE KARACA', 'Davacı', '', 'Kişi'),
  ];
}

void main() {
  test('the kinds UYAP takes a fee for are read as the portal reads them: '
      'a list of codes, a list within it, or records', () {
    expect(UyapWebService.paidCodesOf(['10', '20']), {'10', '20'});
    expect(
      UyapWebService.paidCodesOf([
        ['10'],
        {'turKodu': 30},
        {'tur': '40'},
        '',
        null,
      ]),
      {'10', '30', '40'},
    );
    expect(UyapWebService.paidCodesOf(const []), isEmpty);
  });

  late UyapWebService before;
  setUp(() => before = UyapWebService.instance);
  tearDown(() => UyapWebService.instance = before);

  testWidgets('a case chosen from the list just read is not looked for '
      'again before it is shown', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final web = _Web();
    UyapWebService.instance = web;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UyapSendDialog(
            documentName: 'Beyan.udf',
            documentBytes: Uint8List(0),
            stillCurrent: () async => true,
            // Its number unreadable: the court chosen, the case not.
            target: const UyapCaseLink(
              jurisdiction: '1',
              courtType: 'HUKUK',
              courtId: 'h1',
              court: _court,
              number: 'eski kayıt',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(web.listed, 0);
    await tester.tap(find.text('Dosyaları getir'));
    await tester.pumpAndSettle();
    expect(web.listed, 1);
    await tester.tap(find.text('2025/80'));
    await tester.pumpAndSettle();
    // Chosen with no second listing; the check before sending asks again.
    expect(web.listed, 1);
    expect(find.text('Dosyaları getir'), findsNothing);
    expect(find.textContaining('AYŞE KARACA'), findsWidgets);
  });

  testWidgets('a kind UYAP takes a fee for is finished on the portal: said '
      'so in the list, and chosen it offers no sending from here', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final web = _Web()..paid = {'2'};
    UyapWebService.instance = web;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UyapSendDialog(
            documentName: 'Istinaf.udf',
            documentBytes: Uint8List(0),
            stillCurrent: () async => true,
            target: const UyapCaseLink(
              jurisdiction: '1',
              courtType: 'HUKUK',
              courtId: 'h1',
              court: _court,
              number: 'eski kayıt',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dosyaları getir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2025/80'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Evrak türü'));
    await tester.pumpAndSettle();
    final paid = find.textContaining(
      'İstinaf Başvurusu — harçlı, portalda tamamlanır',
    );
    expect(paid, findsWidgets);
    await tester.tap(paid.last);
    await tester.pumpAndSettle();
    // Finished on the portal: no sending from here, the way there told.
    expect(find.byKey(const ValueKey('uyap-portal-steps')), findsOneWidget);
    expect(find.byKey(const ValueKey('uyap-portal-finish')), findsOneWidget);
    expect(find.text('Gönderimi incele'), findsNothing);
    expect(find.text('Evrak açıklaması'), findsNothing);
    // Another kind sends from here as before.
    await tester.tap(find.textContaining('İstinaf Başvurusu').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beyan Dilekçesi').last);
    await tester.pumpAndSettle();
    expect(find.text('Evrak açıklaması'), findsOneWidget);
    expect(find.byKey(const ValueKey('uyap-portal-finish')), findsNothing);
  });

  testWidgets('Portalda tamamla puts the signed document in a folder of its '
      'own, named after the case', (tester) async {
    tester.view.physicalSize = const Size(1600, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final home = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-portal-'),
    ))!;
    addTearDown(() => home.deleteSync(recursive: true));
    useFakePathProvider(Directory('${home.path}/paths'));
    configurePdfiumForTest();
    final settings = UyapSettings.instance;
    UyapSettings.instance = UyapSettings(directory: home, home: home.path);
    addTearDown(() => UyapSettings.instance = settings);
    final content = File('test/fixtures/signatures/content.xml')
        .readAsBytesSync();
    final signature = File('test/fixtures/signatures/rsa-valid.sgn')
        .readAsBytesSync();
    final signed = Uint8List.fromList(
      ZipEncoder().encode(
        Archive()
          ..addFile(ArchiveFile('content.xml', content.length, content))
          ..addFile(ArchiveFile('sign.sgn', signature.length, signature)),
      ),
    );
    final web = _Web()..paid = {'2'};
    UyapWebService.instance = web;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UyapSendDialog(
            documentName: 'Istinaf.udf',
            documentBytes: signed,
            stillCurrent: () async => true,
            target: const UyapCaseLink(
              jurisdiction: '1',
              courtType: 'HUKUK',
              courtId: 'h1',
              court: _court,
              number: 'eski kayıt',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dosyaları getir'));
    await tester.pumpAndSettle();
    // The real document's preview is drawn on the real clock.
    Future<void> settle() async {
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.tap(find.text('2025/80'));
    await settle();
    // Below the document's preview, in the list that builds as it is
    // scrolled to.
    await tester.scrollUntilVisible(
      find.text('Evrak türü'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Evrak türü'));
    await settle();
    await tester.tap(find.textContaining('İstinaf Başvurusu').last);
    await settle();
    await tester.tap(find.byKey(const ValueKey('uyap-portal-finish')));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    final saved = File(
      '${home.path}/Folio/UYAP/Portalda gönderilecek/$_court 2025-80/'
      'Istinaf.udf',
    );
    expect(saved.existsSync(), isTrue);
    expect(saved.readAsBytesSync(), signed);
    // Done: the button opens it all again.
    expect(find.text('Yeniden aç'), findsOneWidget);
    // The preview's own timers let run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}

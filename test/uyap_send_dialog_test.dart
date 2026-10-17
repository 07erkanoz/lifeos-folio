import 'dart:typed_data';

import 'package:evrak_convert/services/uyap/uyap_case_links.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/widgets/uyap_send_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  ];

  @override
  Future<List<UyapParty>> parties(UyapCase target) async => const [
    UyapParty('AYŞE KARACA', 'Davacı', '', 'Kişi'),
  ];
}

void main() {
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
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/uyap/uyap_case_panel_controller.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';

void main() {
  const court = 'Manavgat İcra Dairesi';
  final web = DateTime.utc(2026, 10, 12, 19);
  final mobile = DateTime.utc(2026, 10, 13, 22, 52);

  PortalCase reading(
    PortalChannel channel,
    DateTime at,
    Map<String, Object?> details,
  ) => PortalCase(
    key: caseKey('2026/126', court),
    number: '2026/126',
    court: court,
    details: Observed(details, channel, at, complete: false),
  );

  test('UYAP Mobil reading a case the web read keeps what only the web said: '
      'the court\'s id on the web, by which it is found there', () {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    db.mergeCases([
      reading(PortalChannel.uyapWeb, web, {
        'tur': 'İcra Dosyası',
        'yargiTuru': '2',
        'yargiBirimi': '1101',
        'birimId': '1001200',
        'acilis': '05.01.2026',
      }),
    ], portfolio: true);
    db.mergeCases([
      reading(PortalChannel.uyapMobile, mobile, {
        'tur': 'İcra Dosyası',
        'yargiTuru': '2',
        'yargiBirimi': '1101',
        'dosyaTurKod': '35',
      }),
    ], portfolio: true);
    final kept = db.caseOf(caseKey('2026/126', court))!.details!.value;
    expect(kept['birimId'], '1001200');
    expect(kept['acilis'], '05.01.2026');
    expect(kept['dosyaTurKod'], '35');
    // The web reading again changes nothing the mobile API said either.
    db.mergeCases([
      reading(PortalChannel.uyapWeb, mobile.add(const Duration(hours: 1)), {
        'birimId': '1001200',
        'yargiTuru': '2',
      }),
    ], portfolio: true);
    expect(
      db.caseOf(caseKey('2026/126', court))!.details!.value['dosyaTurKod'],
      '35',
    );
  });

  test('UYAP Mobil\'s parties add to the web\'s, never take their counsel '
      'away', () {
    const webParties = [
      UyapParty('FATMA ÖZEN', 'Alacaklı', 'Av. Erkan Öz', 'Kişi'),
      UyapParty('MUAMMER ÖZ', 'Borçlu', '', 'Kişi'),
    ];
    const mobileParties = [
      UyapParty('FATMA ÖZEN', 'Alacaklı', '', ''),
      UyapParty('MUAMMER ÖZ', 'Borçlu', 'Av. Karşı Vekil', ''),
      UyapParty('YENİ BORÇLU', 'Borçlu', '', ''),
    ];
    final merged = UyapCasePanelController.mergeParties(
      webParties,
      mobileParties,
    );
    expect(merged.length, 3);
    expect(merged[0].lawyer, 'Av. Erkan Öz');
    expect(merged[0].kind, 'Kişi');
    expect(merged[1].lawyer, 'Av. Karşı Vekil');
    expect(merged[2].name, 'YENİ BORÇLU');
    expect(
      UyapCasePanelController.mergeParties(webParties, const []),
      webParties,
    );
  });

  test('a short name that could be more than one party carries no counsel, '
      'nor across roles', () {
    const web = [
      UyapParty('ALİ VELİ', 'Davacı', 'Av. Bir', 'Kişi'),
      UyapParty('ALİ KAYA', 'Davacı', '', 'Kişi'),
      UyapParty('AYŞE ÖZ', 'Davalı', '', 'Kişi'),
    ];
    final merged = UyapParty.merge(web, const [
      UyapParty('ALİ', 'Davacı', 'Av. Karşı', ''),
      UyapParty('AYŞE ÖZ', 'Tanık', 'Av. Üç', ''),
    ]);
    expect(merged[1].lawyer, isEmpty, reason: 'ALİ: which one?');
    expect(merged.where((t) => t.name == 'ALİ'), isEmpty);
    // Another role is another party.
    expect(merged[2].lawyer, isEmpty);
    expect(merged.last.role, 'Tanık');
  });

  test('one kept party gives its counsel to one of a new list at most', () {
    final filled = UyapParty.fill(
      const [
        UyapParty('ALİ VELİ', 'Davacı', '', ''),
        UyapParty('ALİ KAYA', 'Davacı', '', ''),
      ],
      const [UyapParty('ALİ', 'Davacı', 'Av. Bir', '')],
    );
    expect(filled.where((t) => t.lawyer.isNotEmpty), isEmpty);
  });

  group('the parties kept in the database', () {
    test('UYAP Mobil gives a shortened kept name its whole one, and drops '
        'none of the web\'s', () {
      final db = PortalDatabase.memory();
      addTearDown(db.dispose);
      db.saveCaseParties('k', const [
        UyapParty('F**** Ö***', 'Alacaklı', 'Av. Erkan Öz', 'Kişi'),
        UyapParty('MUAMMER ÖZ', 'Borçlu', 'Av. Web', 'Kişi'),
      ], source: 'uyap_web');
      db.saveCaseParties('k', const [
        UyapParty('FATMA ÖZEN', 'Alacaklı', '', ''),
      ], source: 'uyap_mobil');
      final kept = db.caseParties(caseKey: 'k')['k']!;
      expect(kept.map((t) => t.name), ['FATMA ÖZEN', 'MUAMMER ÖZ']);
      expect(kept[0].lawyer, 'Av. Erkan Öz');
      expect(kept[1].lawyer, 'Av. Web');
    });

    const key = 'k';
    const web = [
      UyapParty('FATMA ÖZEN', 'Alacaklı', 'Av. Erkan Öz', 'Kişi'),
      UyapParty('MUAMMER ÖZ', 'Borçlu', '', 'Kişi'),
    ];

    test('UYAP Mobil after the web adds, never takes counsel away', () {
      final db = PortalDatabase.memory();
      addTearDown(db.dispose);
      db.saveCaseParties(key, web, source: 'uyap_web');
      db.saveCaseParties(key, const [
        UyapParty('FATMA ÖZEN', 'Alacaklı', '', ''),
        UyapParty('MUAMMER', 'Borçlu', 'Av. Karşı', ''),
        UyapParty('YENİ BORÇLU', 'Borçlu', '', ''),
      ], source: 'uyap_mobil');
      final kept = db.caseParties(caseKey: key)[key]!;
      expect(kept.map((t) => t.name), [
        'FATMA ÖZEN',
        'MUAMMER ÖZ',
        'YENİ BORÇLU',
      ]);
      expect(kept[0].lawyer, 'Av. Erkan Öz');
      expect(kept[1].lawyer, 'Av. Karşı');
      expect(db.clientsOf(key, lawyer: 'Erkan Öz').single.ad, 'FATMA ÖZEN');
    });

    test('the web after UYAP Mobil gives the list, keeping counsel the '
        'mobile API knew', () {
      final db = PortalDatabase.memory();
      addTearDown(db.dispose);
      db.saveCaseParties(key, const [
        UyapParty('FATMA ÖZEN', 'Alacaklı', '', ''),
        UyapParty('MUAMMER ÖZ', 'Borçlu', 'Av. Karşı', ''),
      ], source: 'uyap_mobil');
      db.saveCaseParties(key, web, source: 'uyap_web');
      final kept = db.caseParties(caseKey: key)[key]!;
      expect(kept.length, 2);
      expect(kept[0].lawyer, 'Av. Erkan Öz');
      expect(kept[1].lawyer, 'Av. Karşı');
      expect(kept[1].kind, 'Kişi');
    });

    test('names shortened never take the place of names whole', () {
      final db = PortalDatabase.memory();
      addTearDown(db.dispose);
      db.saveCaseParties(key, web, source: 'uyap_web');
      db.saveCaseParties(key, const [
        UyapParty('F**** Ö***', 'Alacaklı', '', ''),
      ], source: 'uyap_web');
      expect(db.caseParties(caseKey: key)[key]!.first.name, 'FATMA ÖZEN');
      // And whole names take the place of shortened ones, whatever their
      // source.
      final other = PortalDatabase.memory();
      addTearDown(other.dispose);
      other.saveCaseParties(key, const [
        UyapParty('F**** Ö***', 'Alacaklı', '', ''),
      ], source: 'uyap_web');
      other.saveCaseParties(key, web, source: 'paket');
      expect(other.caseParties(caseKey: key)[key]!.first.name, 'FATMA ÖZEN');
    });
  });

  group('a case\'s record', () {
    late Directory dir;
    late UyapCaseStore store;
    const target = UyapCase('1', '2026/126', 'c', court);
    UyapCaseDocument doc(String key) => UyapCaseDocument(
      key: key,
      documentId: key,
      caseId: '1',
      type: 'Karar',
      number: key,
      approved: '01.10.2026 10:00',
      sender: 'Mahkeme',
      description: '',
    );

    setUp(() {
      dir = Directory.systemTemp.createTempSync('folio-no-overwrite-');
      store = UyapCaseStore(
        directory: dir,
        settings: UyapSettings(directory: dir, home: dir.path),
      );
    });
    tearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('a reading without parties or documents keeps those kept, and a '
        'new party list keeps the counsel known', () async {
      await store.keep(
        target: target,
        details: const UyapCaseDetails(),
        parties: const [
          UyapParty('FATMA ÖZEN', 'Alacaklı', 'Av. Erkan Öz', 'Kişi'),
        ],
        documents: UyapCaseDocuments([doc('a'), doc('b')]),
      );
      final next = await store.keep(
        target: target,
        details: const UyapCaseDetails(),
        parties: const [],
        documents: const UyapCaseDocuments([]),
      );
      expect(next.parties.single.lawyer, 'Av. Erkan Öz');
      expect(next.documents.map((d) => d.key), ['a', 'b']);
      final again = await store.keep(
        target: target,
        details: const UyapCaseDetails(),
        parties: const [UyapParty('FATMA ÖZEN', 'Alacaklı', '', '')],
        documents: UyapCaseDocuments([doc('a'), doc('b'), doc('c')]),
      );
      expect(again.parties.single.lawyer, 'Av. Erkan Öz');
      expect(again.fresh, {'c'});
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/uyap/uyap_case_panel_controller.dart';
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
    expect(UyapCasePanelController.mergeParties(webParties, const []), webParties);
  });
}

import 'package:evrak_convert/services/clients/client_overview.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a case\'s stage, as UYAP writes its state', () {
    expect(stageOf(''), CaseStage.open);
    expect(stageOf('Açık'), CaseStage.open);
    expect(stageOf('Açık (Durdurulmuş : Takibe İtiraz)'), CaseStage.stopped);
    expect(stageOf('İstinafta'), CaseStage.appeal);
    expect(stageOf('Yargıtaydan Döndü'), CaseStage.appeal);
    expect(stageOf('Karara Çıkmış'), CaseStage.closed);
    expect(stageOf('Kapalı'), CaseStage.closed);
    expect(stageOf('Başka Birime Gönderilmiş'), CaseStage.closed);
    expect(
      stageLabel('Açık (Durdurulmuş : Takibe İtiraz)'),
      'Durdurulmuş · Takibe İtiraz',
    );
    expect(stageLabel('Karara Çıkmış'), 'Karara çıktı');
  });

  test('a case\'s kind and years, from UYAP\'s details', () {
    expect(caseKindOf({'tur': 'Hukuk Dava Dosyası'}), 'Hukuk Dava');
    expect(caseKindOf({'tur': 'İcra Dosyası'}), 'İcra');
    expect(caseKindOf(null), '');
    expect(yearOf('2024-05-21 10:25:10.0'), 2024);
    expect(yearOf(null), isNull);
  });

  test('the other side faces the client\'s role; third parties and the '
      'client are passed over', () {
    const parties = [
      UyapParty('AYŞE KARACA', 'Davacı', 'DENİZ KAYA', 'Kişi'),
      UyapParty('ZİRAAT BANKASI', 'Üçüncü Şahıs', '', 'Kurum'),
      UyapParty('BORA YAPI', 'Davalı', 'CAN ER', 'Kurum'),
    ];
    final other = otherSide(parties, 'Davacı', (p) => p.name == 'AYŞE KARACA');
    expect(other?.name, 'BORA YAPI');
    expect(other?.lawyer, 'CAN ER');
    // A debtor faces the creditor.
    final creditor = otherSide(
      const [
        UyapParty('DENİZ GIDA', 'Alacaklı', '', 'Kurum'),
        UyapParty('MEHMET TUNÇ', 'Borçlu', '', 'Kişi'),
      ],
      'Borçlu',
      (p) => p.name == 'MEHMET TUNÇ',
    );
    expect(creditor?.name, 'DENİZ GIDA');
  });

  test('a notice\'s subject without its court and case repeated', () {
    expect(
      noticeTopic(
        'Antalya 9. Aile Mahkemesi [2020/801] '
            '[Antalya 9. Aile Mahkemesi-5000892057132-0-2020/801]',
        'Antalya 9. Aile Mahkemesi',
      ),
      '',
    );
    expect(
      noticeTopic('Gerekçeli karar [2021/5]', 'Antalya 1. Asliye'),
      'Gerekçeli karar',
    );
  });
}

import 'package:evrak_convert/services/uyap/uyap_case_data.dart';
import 'package:evrak_convert/ui/widgets/uyap_doc_details.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  UyapCaseDocument doc({
    String type = 'Bilirkişi Raporu',
    String description = '',
    String approved = '',
    String sent = '',
    String sender = '',
    String number = '',
    String source = '',
  }) => UyapCaseDocument(
    key: 'k',
    documentId: '',
    caseId: '',
    type: type,
    number: number,
    approved: approved,
    sender: sender,
    description: description,
    source: source,
    sentToSystem: sent,
  );

  test('a document\'s details: both dates with their hour, who sent it, '
      'no empty line, no description that only repeats the type', () {
    final d = doc(
      description: 'bilirkişi raporu',
      sent: '10/10/2026 14:32',
      approved: '2026-10-12 09:15:00.0',
      sender: 'Bilirkişi',
      number: '2026/45',
      source: '2026/123(Hukuk Dava Dosyası)',
    );
    expect(uyapDocDetails(d), [
      ('Sunulma', '10.10.2026 14:32'),
      ('Onay', '12.10.2026 09:15'),
      ('Gönderen', 'Bilirkişi'),
      ('Evrak no', '2026/45'),
      ('Kaynak dosya', '2026/123(Hukuk Dava Dosyası)'),
    ]);
    expect(
      uyapDocTip(d),
      'Sunulma: 10.10.2026 14:32\nOnay: 12.10.2026 09:15\nGönderen: Bilirkişi',
    );

    // An attachment: UYAP gives its description alone.
    expect(uyapDocDetails(doc(type: 'Ek', description: 'Hesap tablosu')), [
      ('Açıklama', 'Hesap tablosu'),
    ]);
    expect(uyapDocDetails(doc()), isEmpty);
    expect(uyapDateText('03/09/2026'), '03.09.2026');
    expect(uyapDateText('belirsiz'), 'belirsiz');
  });
}

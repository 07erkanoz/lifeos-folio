import 'package:evrak_convert/services/uyap/uyap_case_data.dart';
import 'package:evrak_convert/services/uyap/uyap_case_panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';

UyapCaseDocument doc(
  String key, {
  String id = '',
  String type = '',
  String source = '',
  String approved = '',
  List<UyapCaseDocument> attachments = const [],
}) => UyapCaseDocument(
  key: key,
  documentId: id,
  caseId: '',
  type: type,
  number: key.startsWith('~') ? '' : key.split('@').first,
  approved: approved,
  sender: '',
  description: '',
  source: source,
  attachments: attachments,
);

void main() {
  test('the mobile list adds and fills; what the web listed stays', () {
    final kept = [
      doc(
        '10',
        type: 'Tensip Zaptı',
        source: '2026/295(Talimat Dosyası)',
        approved: '11/08/2026 10:00',
      ),
      // A tied case's group, which the mobile API did not list.
      doc(
        '7',
        type: 'Muhabere',
        source: '2026/12(Muhabere Dosyası)',
        approved: '01/08/2026 09:00',
      ),
      doc(
        '20',
        type: 'Talimat Gönderme Yazısı',
        source: '2026/295(Talimat Dosyası)',
        approved: '05/08/2026 09:00',
        attachments: [doc('20:ek:1', type: 'Tensip Zaptı')],
      ),
    ];
    final fetched = [
      doc(
        '10',
        id: 'e10',
        source: '2026/295(Talimat Dosyası)',
        approved: '11.08.2026',
      ),
      doc(
        '20',
        id: 'e20',
        approved: '05.08.2026',
        attachments: [doc('20:ek:1', id: 'a1')],
      ),
      doc('30', id: 'e30', type: 'Tebliğ Mazbatası', approved: '01.09.2026'),
    ];
    final out = UyapCasePanelController.enrichDocuments(fetched, kept);
    expect(out.map((d) => d.key), ['30', '10', '20', '7']);
    final ten = out.firstWhere((d) => d.key == '10');
    expect(ten.type, 'Tensip Zaptı', reason: 'kept where the mobile is empty');
    expect(ten.documentId, 'e10', reason: 'the session ids are the mobile’s');
    final twenty = out.firstWhere((d) => d.key == '20');
    expect(twenty.source, '2026/295(Talimat Dosyası)');
    expect(twenty.attachments.single.type, 'Tensip Zaptı');
    expect(twenty.attachments.single.documentId, 'a1');
  });

  test('a document the web and the mobile API key apart is one document', () {
    final kept = [
      // The web: a number in two groups, so told apart by the group.
      doc(
        '55@2024-700',
        type: 'Duruşma Zaptı',
        source: '2024/700(Ceza Dava Dosyası)',
        approved: '17/06/2026 10:00',
      ),
      // No number: known by what it is; the web writes the date its way.
      doc('~abc', type: 'Tebligat', approved: '01/06/2026 09:00'),
      // An earlier mobile refresh's copy of the first, under its own key.
      doc('55', type: 'Duruşma Zaptı', approved: '17.06.2026'),
    ];
    final fetched = [
      doc('55', id: 'e55', type: 'Duruşma Zaptı', approved: '17.06.2026'),
      doc('~xyz', id: 'e9', type: 'Tebligat', approved: '01.06.2026'),
    ];
    final aligned = UyapCasePanelController.alignKeys(fetched, kept);
    expect(aligned.docs.map((d) => d.key), ['55@2024-700', '~abc']);
    expect(aligned.docs.first.documentId, 'e55');
    expect(aligned.retired, {'55'});
    final merged = UyapCasePanelController.enrichDocuments(aligned.docs, [
      for (final d in kept)
        if (!aligned.retired.contains(d.key)) d,
    ]);
    expect(merged.map((d) => d.key).toSet(), {'55@2024-700', '~abc'});
  });
}

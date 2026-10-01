// A stand-in for UYAP's lawyer portal for the screenshots: it answers the
// send dialog and the operations list with an invented case, invented parties
// and invented records, and never reaches UYAP.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:typed_data';

import 'package:evrak_convert/services/uyap/uyap_web_service.dart';

class DemoUyap extends UyapWebService {
  DemoUyap() : super.forTesting();

  static const court = UyapOption('c5', 'İstanbul Anadolu 5. Aile Mahkemesi');
  static const target = UyapCase(
    'd1',
    '2026/1204',
    'c5',
    'İstanbul Anadolu 5. Aile Mahkemesi',
  );

  bool _connected = false;
  final DateTime _sentAt = DateTime.now();

  @override
  bool get connected => _connected;

  @override
  void disconnect() {
    _connected = false;
    session.value = null;
  }

  @override
  void cancelConnect() {}

  @override
  Future<String> connect(
    String pin, {
    void Function(String stage)? onProgress,
  }) async {
    onProgress?.call('Kart ve sertifika okunuyor');
    _connected = true;
    session.value = UyapSession(
      user: 'Av. Deniz YILMAZ',
      since: DateTime.now(),
      route: UyapLoginRoute.tray,
    );
    return 'Av. Deniz YILMAZ';
  }

  @override
  Future<List<UyapOption>> courtTypes(String jurisdiction) async => const [
    UyapOption('AILE', 'Aile Mahkemesi'),
    UyapOption('ASLIYE', 'Asliye Hukuk Mahkemesi'),
    UyapOption('IS', 'İş Mahkemesi'),
    UyapOption('TUKETICI', 'Tüketici Mahkemesi'),
  ];

  @override
  Future<List<UyapOption>> courts(
    String jurisdiction,
    String courtType, {
    bool closed = false,
  }) async => const [
    court,
    UyapOption('c7', 'İstanbul Anadolu 7. Aile Mahkemesi'),
  ];

  @override
  Future<List<UyapCase>> cases({
    required String jurisdiction,
    required String courtType,
    required UyapOption court,
    int? year,
    int? number,
    bool closed = false,
    int pageNumber = 1,
  }) async => [if (court.id == DemoUyap.court.id) target];

  static final _types = [
    UyapDocumentType('TANIK', 'Tanık Listesi', '1', false, 1, 3, {
      '.udf',
      '.pdf',
    }),
    UyapDocumentType('BEYAN', 'Beyan Dilekçesi', '1', false, 1, 3, {
      '.udf',
      '.pdf',
    }),
    UyapDocumentType('DELIL', 'Delil Listesi', '1', false, 1, 3, {
      '.udf',
      '.pdf',
    }),
  ];

  @override
  Future<List<UyapDocumentType>> documentTypes(UyapCase target) async => _types;

  @override
  Future<List<UyapParty>> parties(UyapCase target) async => const [
    UyapParty('Zeynep KAYA', 'Davacı', '[Av. Deniz YILMAZ]', 'Kişi'),
    UyapParty('Emre KAYA', 'Davalı', '', 'Kişi'),
  ];

  @override
  Future<String?> send({
    required UyapCase target,
    required UyapDocumentType type,
    required List<UyapUpload> files,
    void Function()? onDispatched,
  }) async {
    onDispatched?.call();
    return 'E-1';
  }

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.0';
  }

  @override
  Future<List<UyapOperation>> operations({
    required DateTime from,
    required DateTime to,
  }) async => [
    UyapOperation(
      orderNumber: '18020731144',
      date: _stamp(_sentAt.add(const Duration(seconds: 5))),
      court: target.courtName,
      caseNumber: target.number,
      caseId: target.id,
      name: 'Avukat Evrak Kaydı (Tanık Listesi)',
      status: 'Tamamlandı',
      owner: '',
      documentId: 'e1',
      globalDocumentId: 'g1',
      documentNumber: '2026/5412',
      documentDate: '',
      documentType: 'HKM_TANIK_LISTESI',
    ),
    UyapOperation(
      orderNumber: '18020715392',
      date: _stamp(_sentAt.subtract(const Duration(hours: 3))),
      court: 'Ankara 4. Asliye Ticaret Mahkemesi',
      caseNumber: '2025/912',
      caseId: 'd2',
      name: 'Avukat Evrak Kaydı (Bilirkişi Raporuna İtiraz)',
      status: 'Devam Ediyor',
      owner: 'Yazı İşleri Müdürü',
      documentId: 'e2',
      globalDocumentId: 'g2',
      documentNumber: '',
      documentDate: '',
      documentType: 'HKM_BILIRKISI_RAPORU_ITIRAZ',
    ),
  ];

  @override
  Future<Uint8List> documentBytes(UyapOperation operation) async =>
      throw StateError('Önizleme bu tanıtımda yok.');

  @override
  Future<UyapCaseDetails> caseDetails(UyapCase target) async => details;

  static const details = UyapCaseDetails(
    kind: 'Boşanma (TMK 166/1)',
    opening: 'Dava',
    status: 'Açık',
    hearing: '12/11/2026 10:30',
    preliminary: '16/09/2026 11:05',
    related: [('Birleşen dosya', '2026/1388 Esas')],
  );

  /// The case's documents, the first [count] of them: what came later is
  /// what the panel marks new.
  static List<UyapCaseDocument> documents([int count = 9]) => [
    for (final (number, type, approved, sender, description) in const [
      ('101', 'Dava Dilekçesi', '12/03/2026 10:14', 'Davacı Vekili', ''),
      ('102', 'Tensip Zaptı', '16/03/2026 14:02', 'Mahkeme', ''),
      ('103', 'Cevap Dilekçesi', '21/04/2026 09:40', 'Davalı Vekili', ''),
      (
        '104',
        'Cevaba Cevap Dilekçesi',
        '05/05/2026 16:22',
        'Davacı Vekili',
        '',
      ),
      ('105', 'Ön İnceleme Zaptı', '16/09/2026 11:30', 'Mahkeme', ''),
      ('106', 'Tanık Listesi', '23/09/2026 10:05', 'Davacı Vekili', ''),
      (
        '107',
        'Bilirkişi Raporu',
        '28/09/2026 15:47',
        'Bilirkişi',
        'Sosyal inceleme',
      ),
      ('108', 'Ara Karar', '29/09/2026 09:12', 'Mahkeme', ''),
      (
        '109',
        'Bilirkişi Raporuna İtiraz',
        '30/09/2026 17:31',
        'Davalı Vekili',
        '',
      ),
    ].take(count))
      UyapCaseDocument(
        key: number,
        documentId: 'e$number',
        caseId: target.id,
        type: type,
        number: number,
        approved: approved,
        sender: sender,
        description: description,
        source: '2026/1204(Hukuk Dava Dosyası)',
        attachments: [
          if (number == '101')
            const UyapCaseDocument(
              key: '101:ek:1',
              documentId: 'e101-1',
              caseId: 'd1',
              type: 'Vekaletname',
              number: '',
              approved: '',
              sender: '',
              description: '',
              parentKey: '101',
            ),
        ],
      ),
  ];

  @override
  Future<UyapCaseDocuments> caseDocuments(
    UyapCase target, {
    void Function(int page, int pages)? onPage,
  }) async => UyapCaseDocuments(documents());

  /// What a document is, when it is opened: given by the scene.
  static Uint8List Function(UyapCaseDocument document)? content;

  @override
  Future<Uint8List> caseDocumentBytes(
    UyapCaseDocument document, {
    String? caseId,
  }) async => content!(document);
}

import 'dart:io';

import 'package:evrak_convert/services/legal/deadlines/aidiyet.dart';
import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_deadline.dart';
import 'package:evrak_convert/services/uets/notice_deadlines.dart';
import 'package:evrak_convert/services/uets/notice_documents.dart';
import 'package:evrak_convert/services/uets/notice_matcher.dart';
import 'package:evrak_convert/services/uets/uets_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// Stage B of the audit of 8 October 2026: every document of a notice's
// package read (B01, B02), read again when the reader changes (B21), its
// digest among a deadline's inputs (B24), the package's own description
// of the case read (dosyaBilgileri). Invented documents only.
void main() {
  late Directory root;
  late PortalDatabase db;
  const court = 'Ankara 3. Asliye Hukuk Mahkemesi';

  const caseFileXml = '''<?xml version="1.0" encoding="UTF-8"?>
<dosyabilgileri>
  <versiyon>1</versiyon>
  <barkodNo>12345</barkodNo>
  <dosyano>2026/100</dosyano>
  <dosyatur>Hukuk Dava Dosyası</dosyatur>
  <birim><id>1001</id><adi>Ankara 3. Asliye Hukuk Mahkemesi</adi>
    <il>Ankara</il><ilce>Çankaya</ilce><detsisNo>22334455</detsisNo></birim>
  <taraflar>
    <taraf><tarafadi>Deniz Örnek</tarafadi><tarafrolu>Davacı</tarafrolu>
      <kisiMiKurummu>Kişi</kisiMiKurummu></taraf>
    <taraf><tarafadi>Örnek Yapı A.Ş.</tarafadi><tarafrolu>Davalı</tarafrolu>
      <kisiMiKurummu>Kurum</kisiMiKurummu></taraf>
  </taraflar>
</dosyabilgileri>''';

  setUp(() {
    root = Directory.systemTemp.createTempSync('folio_notice_docs_');
    db = PortalDatabase.memory();
    db.mergeNotices([
      UetsMessage(
        id: 'n1',
        subject: '$court [2026/100]',
        sent: DateTime.utc(2026, 9, 1, 9),
      ),
    ]);
  });
  tearDown(() {
    db.dispose();
    root.deleteSync(recursive: true);
  });

  String file(String name, [String body = 'x']) =>
      (File(p.join(root.path, name))..writeAsStringSync(body)).path;

  /// A package kept with these documents, the list naming [parts].
  void keep(List<String> paths, {List<String> parts = const []}) {
    db.saveManifest('n1', [
      for (var i = 0; i < parts.length; i++)
        (id: 'p$i', name: parts[i], mime: ''),
    ]);
    db.saveEnvelope(
      NoticeEnvelope(
        noticeId: 'n1',
        state: 'indirildi',
        envelopeText: '',
        attachments: [for (final f in paths) (name: p.basename(f), path: f)],
      ),
    );
  }

  test('the package’s description of the case is read', () {
    final f = NoticeCaseFile.parse(caseFileXml)!;
    expect(f.unitId, '1001');
    expect(f.unitName, court);
    expect(f.number, '2026/100');
    expect(f.kind, 'Hukuk Dava Dosyası');
    expect(f.parties.map((t) => (t.role, t.institution)), [
      ('Davacı', false),
      ('Davalı', true),
    ]);
    expect(
      NoticeCaseFile.fromJson(f.toJson())!.parties.last.name,
      'Örnek Yapı A.Ş.',
    );
    expect(NoticeCaseFile.parse('<baska/>'), isNull);
  });

  test('every document is read once by a reader’s version; one gone is '
      'told as such', () async {
    keep(
      [
        file('Tensip Zaptı.pdf'),
        file('dosyaBilgileriV1.xml', caseFileXml),
        p.join(root.path, 'gone.pdf'),
      ],
      parts: ['(1)Tensip Zaptı.pdf', '(2)dosyaBilgileriV1.xml'],
    );
    var asked = 0;
    Future<DocumentReading> read(String path) async {
      asked++;
      return (digest: 'h$asked', state: 'okundu', text: 'metin', note: null);
    }

    final told = <String>[];
    await readNoticeDocuments(db, read: read, onRead: told.add);
    final docs = db.noticeDocuments('n1');
    expect(docs.map((d) => d.state), ['okundu', 'ustveri', 'kayip']);
    expect(docs.first.partId, 'p0');
    expect(docs[1].caseFile!.unitName, court);
    expect(told, ['n1']);
    expect(asked, 1);
    // Read already by this version: not again.
    await readNoticeDocuments(db, read: read, onRead: told.add);
    expect(asked, 1);
    expect(told, ['n1']);
  });

  List<DeadlineRecord> made({
    required List<({String name, String text})> docs,
    List<TarafKaydi> parties = const [],
    String? lawyer,
    List<({String id, String name})> parts = const [],
  }) => noticeDeadlines(
    db.notice('n1')!,
    manifest: (state: 'alindi', fetchedAt: null, parts: parts),
    envelope: const NoticeEnvelope(
      noticeId: 'n1',
      state: 'indirildi',
      envelopeText: '',
    ),
    documents: [
      for (var i = 0; i < docs.length; i++)
        NoticeDocument(
          noticeId: 'n1',
          seq: i,
          name: docs[i].name,
          path: '/sentetik/${docs[i].name}',
          partId: parts.length > i ? parts[i].id : null,
          digest: 'ozet$i',
          state: 'okundu',
          text: docs[i].text,
          reader: noticeReaderVersion,
          readAt: DateTime(2026, 9, 2),
        ),
    ],
    parties: parties,
    lawyer: lawyer,
    now: DateTime(2026, 9, 10),
  );

  test('B01: a tensip’s directive is a deadline, laid on its party', () {
    final rs = made(
      docs: [
        (
          name: 'Tensip Zaptı.pdf',
          text:
              'TENSİP ZAPTI\nDavalıya tebliğden itibaren iki hafta içinde '
              'cevap dilekçesi vermesi ihtar olunur.',
        ),
      ],
      parts: const [(id: 'p0', name: '(1)Tensip Zaptı.pdf')],
      parties: [(rol: 'Davalı', vekil: 'Av. Ayşe Çelik')],
      lawyer: 'Av. Ayşe Çelik',
    );
    final r = rs.singleWhere((r) => r.evidence['kaynak'] == 'ekTalimat');
    expect(r.title, 'Ekteki süre · cevap ve savunma');
    expect(r.law, 'Ekteki talimat');
    expect(r.ownership, AidiyetSinyali.olasiBizim.name);
    expect(r.evidence['ozet'], 'ozet0');
    expect(r.dueDay, isNotNull);
  });

  test('B01: a document whose name tells nothing is known by its heading', () {
    final rs = made(
      docs: [(name: 'Ek-1.pdf', text: 'T.C.\nGEREKÇELİ KARAR\n...')],
      parts: const [(id: 'p0', name: '(1)Ek-1.pdf')],
    );
    expect(rs, isNotEmpty);
    expect(rs.first.evidence['kaynak'], 'ekIcerik');
    expect(rs.first.reasons.map((x) => x.code), contains('turIcerikten'));
  });

  test('a decision’s own words bear out the catalogue’s time and make no '
      'deadline of their own', () {
    final rs = made(
      docs: [
        (
          name: 'Gerekçeli Karar.pdf',
          text:
              'GEREKÇELİ KARAR\nKararın tebliğinden itibaren iki hafta '
              'içinde istinaf kanun yolu açık olmak üzere; dair.',
        ),
      ],
      parts: const [(id: 'p0', name: '(1)Gerekçeli Karar.pdf')],
    );
    expect(rs.where((r) => r.evidence['kaynak'] == 'ekTalimat'), isEmpty);
    expect(rs.single.reasons.map((x) => x.code), contains('zarfIleUyumlu'));
  });

  test('a party’s petition gives no deadline', () {
    final rs = made(
      docs: [
        (
          name: 'Cevap Dilekçesi.pdf',
          text:
              'CEVAP DİLEKÇESİ\nDavacıya tebliğden itibaren iki hafta içinde '
              'delillerini sunması için süre verilmesini talep ederiz.',
        ),
      ],
      parts: const [(id: 'p0', name: '(1)Cevap Dilekçesi.pdf')],
    );
    expect(rs.where((r) => r.evidence['kaynak'] == 'ekTalimat'), isEmpty);
  });

  test('B24: a document read again with another content asks for the '
      'confirmation again', () {
    final once = made(
      docs: [(name: 'Gerekçeli Karar.pdf', text: 'GEREKÇELİ KARAR')],
      parts: const [(id: 'p0', name: '(1)Gerekçeli Karar.pdf')],
    ).single;
    final again = noticeDeadlines(
      db.notice('n1')!,
      manifest: (
        state: 'alindi',
        fetchedAt: null,
        parts: const [(id: 'p0', name: '(1)Gerekçeli Karar.pdf')],
      ),
      documents: [
        NoticeDocument(
          noticeId: 'n1',
          seq: 0,
          name: 'Gerekçeli Karar.pdf',
          path: '/sentetik/x.pdf',
          partId: 'p0',
          digest: 'baska',
          state: 'okundu',
          text: 'GEREKÇELİ KARAR',
          reader: noticeReaderVersion,
          readAt: DateTime(2026, 9, 2),
        ),
      ],
      now: DateTime(2026, 9, 10),
    ).single;
    expect(again.id, once.id);
    expect(again.inputs, isNot(once.inputs));
  });

  test('a notice is tied by its package’s description: the same number and '
      'UYAP’s name of the unit', () async {
    db.mergeCases([
      PortalCase.create(number: '2026/100', court: court),
      PortalCase.create(number: '2026/100', court: 'Ankara 8. İş Mahkemesi'),
    ]);
    keep([file('dosyaBilgileriV1.xml', caseFileXml)]);
    await readNoticeDocuments(db);
    tieByCaseFile(db, 'n1');
    expect(db.notice('n1')!.caseKey, caseKey('2026/100', court));
  });
}

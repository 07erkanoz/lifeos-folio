import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';

/// A case's documents as `list_dosya_evraklar` gives them: grouped by the
/// case each came from, with the last twenty again on the first page.
Map<String, Object?> page({
  int pages = 1,
  Map<String, List<Map<String, Object?>>>? groups,
  List<Map<String, Object?>> latest = const [],
  String? message,
}) => {
  'pageTotal': pages,
  'tumEvraklar': groups ?? {},
  'son20Evrak': latest,
  'message': ?message,
};

Map<String, Object?> doc(
  String no, {
  String id = 'e',
  String type = 'Dilekçe',
  String date = '31/03/2026 09:45',
  List<Map<String, Object?>> attachments = const [],
}) => {
  'evrakId': '"$id$no"',
  'dosyaId': "'d1'",
  'evrakTuruAciklama': type,
  'birimEvrakNo': no,
  'onayTarihi': date,
  'gonderenYerKisi': 'Davacı Vekili',
  // A number where text was expected: it is read, not choked on.
  'gonderenSayi': 42,
  'ekEvrakListesi': attachments,
};

void main() {
  group('reading the documents of a case', () {
    test('each is kept once, known by its number, the case it came from '
        'kept, the ids made usable', () {
      final docs = keyDocuments([
        UyapDocumentPage.fromJson(
          page(
            groups: {
              '2026/1204(Hukuk Dava Dosyası)##abc': [
                doc(
                  '10',
                  attachments: [
                    {'evrakId': 'x1', 'ekTuru': 'Vekaletname', 'sira': 0},
                    // An order seen twice: still two attachments.
                    {'evrakId': 'x2', 'ekTuru': 'Makbuz', 'sira': 0},
                  ],
                ),
                doc('11', type: 'Bilirkişi Raporu'),
              ],
              // A merged case brings a document with the same number.
              '2025/77(Hukuk Dava Dosyası)##def': [doc('10', type: 'Tutanak')],
            },
            // The last twenty again, and one the full list does not have.
            latest: [
              doc('11'),
              doc('0', id: 'yeni', type: 'Ara Karar'),
            ],
          ),
        ),
      ]);
      expect(docs.map((d) => d.key), [
        '10@2026-1204-hukuk-dava-dosyası-',
        '11',
        '10@2025-77-hukuk-dava-dosyası-',
        startsWith('~'),
      ]);
      final first = docs.first;
      expect(first.documentId, 'e10');
      expect(first.caseId, 'd1');
      expect(first.source, '2026/1204(Hukuk Dava Dosyası)');
      expect(first.date, DateTime(2026, 3, 31, 9, 45));
      expect(first.attachments.map((a) => a.key), [
        '10@2026-1204-hukuk-dava-dosyası-:ek:1',
        startsWith('10@2026-1204-hukuk-dava-dosyası-:ek:1~'),
      ]);
      expect(first.attachments.first.title, 'Vekaletname');
      expect(docs[1].title, 'Bilirkişi Raporu');
    });

    test('documents withheld are not "none"', () {
      final withheld = UyapDocumentPage.fromJson(
        page(
          message:
              'Cumhuriyet savcısının onayı sonrası evrak görüntülenebilecektir',
        ),
      );
      expect(withheld.grouped, isEmpty);
      expect(withheld.message, startsWith('Cumhuriyet savcısının'));
      expect(
        () => UyapDocumentPage.fromJson({'pageTotal': 5000}),
        throwsFormatException,
      );
    });

    test('the particulars, under the names UYAP uses', () {
      final details = UyapCaseDetails.fromJson([
        {
          'davaTurleriStr': 'Alacak',
          'dosyaDurumu': 'Açık',
          'durusmaTarihiStr': '31/03/2026 09:45',
          'kesifTarihiStr': '',
          'onIncelemTarihiStr': '16/09/2026 11:05',
          'birlesenDosyaListStr': '2025/77',
        },
      ]);
      expect(details.kind, 'Alacak');
      expect(details.hearing, '31/03/2026 09:45');
      expect(details.inspection, isNull);
      expect(details.preliminary, '16/09/2026 11:05');
      expect(details.related, [('Birleşen dosya', '2025/77')]);
    });
  });

  group('fetching a case', () {
    late HttpServer server;
    late UyapWebService web;
    final requests = <String>[];

    setUp(() async {
      requests.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final response = request.response;
        response.headers.set('Content-Type', 'text/json; charset=utf-8');
        switch (request.uri.path) {
          case '/portal_baslangic.uyap':
            response.cookies.add(Cookie('JSESSIONID', 'oturum'));
          case '/kullanici_bilgileri.uyap' when request.method == 'GET':
            final logged = request.cookies.any((c) => c.value == 'girildi');
            response.write(jsonEncode({'level': logged ? 2 : 0, 'random': 0}));
          case '/login.uyap':
            response.cookies.add(Cookie('JSESSIONID', 'girildi'));
          case '/kullanici_bilgileri.uyap':
            response.write(jsonEncode({'adi': 'Ayşe', 'soyadi': 'Kaya'}));
          case '/list_dosya_evraklar.ajx':
            final body = jsonDecode(await utf8.decodeStream(request)) as Map;
            requests.add('sayfa ${body['pageNumber']}');
            response.write(
              jsonEncode(
                page(
                  pages: 2,
                  groups: {
                    '2026/1204(Hukuk Dava Dosyası)##x': [
                      doc('${body['pageNumber']}'),
                    ],
                  },
                ),
              ),
            );
          case '/dosyaAyrintiBilgileri_brd.ajx':
            response.write(jsonEncode({'davaTurleriStr': 'Alacak'}));
          case '/download_document_brd.uyap':
            response.headers.set('Content-Type', 'application/pdf');
            response.add(utf8.encode('%PDF-1.4 evrak'));
          default:
            response.statusCode = 404;
        }
        await response.close();
      });
      web = UyapWebService.forTesting(
        portal: Uri.parse('http://${server.address.host}:${server.port}'),
      );
      final login = await web.beginEdevlet(EdevletMethod.mobile);
      await web.finishEdevlet(login, 'kod');
    });

    tearDown(() => server.close(force: true));

    const target = UyapCase(
      'd1',
      '2026/1204',
      'c5',
      'İstanbul Anadolu 5. Aile Mahkemesi',
    );

    test('every page is fetched, in turn', () async {
      final seen = <String>[];
      final documents = await web.caseDocuments(
        target,
        onPage: (page, pages) => seen.add('$page/$pages'),
      );
      expect(requests, ['sayfa 1', 'sayfa 2']);
      expect(seen, ['1/1', '2/2']);
      expect(documents.documents.map((d) => d.key), ['1', '2']);
      expect((await web.caseDetails(target)).kind, 'Alacak');
      expect(
        utf8.decode(await web.caseDocumentBytes(documents.documents.first)),
        startsWith('%PDF'),
      );
    });
  });

  group('keeping a case', () {
    late Directory root;
    late UyapCaseStore store;
    const target = UyapCase(
      'd1',
      '2026/1204',
      'c5',
      'İstanbul 5. Aile Mahkemesi',
    );
    setUp(() {
      root = Directory.systemTemp.createTempSync('folio-uyap-');
      store = UyapCaseStore(
        directory: Directory('${root.path}/destek'),
        settings: UyapSettings(
          directory: Directory('${root.path}/destek'),
          home: '${root.path}/ev',
        ),
      );
    });
    tearDown(() => root.deleteSync(recursive: true));

    List<UyapCaseDocument> listOf(List<String> numbers) => keyDocuments([
      UyapDocumentPage.fromJson(
        page(
          groups: {
            'g##x': [for (final n in numbers) doc(n)],
          },
        ),
      ),
    ]);

    test('what came since the last time is new, and stays new until it is '
        'looked at', () async {
      final first = await store.keep(
        target: target,
        details: const UyapCaseDetails(kind: 'Alacak'),
        parties: const [UyapParty('Ali Veli', 'Davacı', 'Av. Ayşe', 'Kişi')],
        documents: UyapCaseDocuments(listOf(['1', '2'])),
        now: DateTime(2026, 10, 1, 9),
      );
      // The first time, nothing is singled out: everything is new.
      expect(first.fresh, isEmpty);
      final second = await store.keep(
        target: target,
        details: const UyapCaseDetails(kind: 'Alacak'),
        parties: first.parties,
        documents: UyapCaseDocuments(listOf(['1', '2', '3'])),
        now: DateTime(2026, 10, 2, 9),
      );
      expect(second.fresh, {'3'});
      expect(second.previousFetchedAt, DateTime(2026, 10, 1, 9));
      final third = await store.keep(
        target: target,
        details: second.details,
        parties: second.parties,
        documents: UyapCaseDocuments(listOf(['1', '2', '3'])),
      );
      expect(third.fresh, {'3'}, reason: 'not looked at yet');
      final looked = await store.seen(third, '3');
      expect(looked.fresh, isEmpty);
      // Read back from disk as it was left, parties and all.
      final read = (await store.load(target.courtName, target.number))!;
      expect(read.parties.single.name, 'Ali Veli');
      expect(read.documents.map((d) => d.key), ['1', '2', '3']);
      expect(
        read.documents.first.documentId,
        isEmpty,
        reason: 'the session’s ids are not kept',
      );
    });

    test('a withheld list keeps the one from before', () async {
      await store.keep(
        target: target,
        details: const UyapCaseDetails(),
        parties: const [],
        documents: UyapCaseDocuments(listOf(['1'])),
      );
      final withheld = await store.keep(
        target: target,
        details: const UyapCaseDetails(),
        parties: const [],
        documents: const UyapCaseDocuments([], withheld: 'Onay bekleniyor'),
      );
      expect(withheld.documents.map((d) => d.key), ['1']);
      expect(withheld.withheld, 'Onay bekleniyor');
    });

    test('a document is saved where Folio searches, under the case, by date '
        'and kind; or in Folio’s cache when that is turned off', () async {
      var record = await store.keep(
        target: target,
        details: const UyapCaseDetails(),
        parties: const [],
        documents: UyapCaseDocuments(listOf(['1'])),
      );
      final udf = Uint8List.fromList(
        ZipEncoder().encodeBytes(
          Archive()..add(ArchiveFile.bytes('content.xml', utf8.encode('<x/>'))),
        ),
      );
      final File file;
      (record, file) = await store.save(record, record.documents.first, udf);
      expect(
        file.path,
        '${root.path}/ev/Folio/UYAP/İstanbul 5. Aile Mahkemesi 2026-1204 Esas/'
        '2026-03-31 Dilekçe.udf',
      );
      expect(store.fileOf(record, '1')?.path, file.path);
      // A second copy of another document of the same name gets a number.
      final again = await store.save(
        record,
        record.documents.first.withKey('2'),
        udf,
      );
      expect(again.$2.path, endsWith('2026-03-31 Dilekçe (2).udf'));
      record = again.$1;

      await store.settings.update(saveDocuments: false);
      final cached = await store.save(
        record,
        record.documents.first.withKey('3'),
        Uint8List.fromList(utf8.encode('%PDF-1.4')),
      );
      expect(cached.$2.path, startsWith('${root.path}/destek/uyap/belgeler/'));
      expect(cached.$2.path, endsWith('.pdf'));
      // Listed with the documents saved where Folio searches, not the
      // cached one.
      final listed = await store.savedCases();
      expect(listed.single.$1.number, '2026/1204');
      expect(listed.single.$2, 2);
    });

    test('what kind of file UYAP sent, by its first bytes', () {
      Uint8List b(List<int> v) => Uint8List.fromList(v);
      expect(UyapCaseStore.kindOf(b(utf8.encode('%PDF-1.7'))), 'pdf');
      expect(UyapCaseStore.kindOf(b([0x49, 0x49, 0x2A, 0x00, 1])), 'tif');
      expect(UyapCaseStore.kindOf(b([0x50, 0x4B, 3, 4])), 'zip');
      expect(UyapCaseStore.kindOf(b([1, 2, 3])), 'bin');
      expect(
        UyapCaseStore.fileName(
          UyapCaseDocument.stored({
            'key': '1',
            'type': 'Cevap: Dilekçesi/Ek?',
            'approved': '01.02.2026',
          }),
          'pdf',
        ),
        '2026-02-01 Cevap Dilekçesi Ek.pdf',
      );
    });
  });
}

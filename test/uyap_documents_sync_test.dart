import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/office/office_network.dart';
import 'package:evrak_convert/services/sync/uyap_documents_sync.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';

const _court = 'Antalya 3. Asliye Hukuk Mahkemesi';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('folio-docs-sync-'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<UyapCaseStore> storeOf(String name) async {
    final store = UyapCaseStore(
      directory: Directory('${dir.path}/$name'),
      settings: UyapSettings(
        directory: Directory('${dir.path}/$name'),
        home: '${dir.path}/$name-ev',
      ),
    );
    UyapCaseDocument doc(String key, String type) => UyapCaseDocument(
      key: key,
      documentId: key,
      caseId: '1',
      type: type,
      number: key,
      approved: '01.10.2026 10:00',
      sender: 'Mahkeme',
      description: '',
    );
    await store.keep(
      target: const UyapCase('1', '2024/318', '', _court),
      details: const UyapCaseDetails(kind: 'Alacak'),
      parties: const [],
      documents: UyapCaseDocuments([
        doc('a', 'Ara Karar'),
        doc('b', 'Bilirkişi Raporu'),
      ]),
    );
    return store;
  }

  test('the computer tells how many documents it has and how big; the '
      'phone puts each that came in its case\'s place', () async {
    final computer = await storeOf('bilgisayar');
    final record = (await computer.load(_court, '2024/318'))!;
    final bytes = utf8.encode('%PDF-1.4 ara karar');
    await computer.save(
      record,
      record.documents.first,
      Uint8List.fromList(bytes),
    );
    final net = OfficeNetwork(
      settings: () async => File('${dir.path}/buro.json'),
    );
    final given = UyapDocumentsSync(network: net, store: computer);
    final here = await given.here();
    expect(here.single.key, 'a');
    expect(await given.answer(const {}), {'evrak': 1, 'bayt': bytes.length});

    final phone = await storeOf('telefon');
    final taken = UyapDocumentsSync(network: net, store: phone);
    final came = File('${dir.path}/gelen-a.pdf')..writeAsBytesSync(bytes);
    final stray = File('${dir.path}/gelen-x.pdf')..writeAsBytesSync([1]);
    final placed = await taken.place(
      [came.path, stray.path],
      {
        'evrak': jsonEncode([
          {'m': _court, 'e': '2024/318', 'k': 'a'},
          {'m': _court, 'e': '2024/318', 'k': 'yok'},
        ]),
      },
    );
    expect(placed, 1);
    final mine = (await phone.load(_court, '2024/318'))!;
    expect(phone.fileOf(mine, 'a')!.readAsBytesSync(), bytes);
    expect(phone.fileOf(mine, 'b'), isNull);
    // What came is not left lying about.
    expect(came.existsSync(), isFalse);
    expect(stray.existsSync(), isFalse);
  });
}

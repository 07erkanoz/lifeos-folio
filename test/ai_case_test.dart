import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/ai/ai_case.dart';
import 'package:evrak_convert/services/ai/folio_mcp.dart';
import 'package:evrak_convert/services/uyap/uyap_case_data.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:flutter_test/flutter_test.dart';

// The case a question is asked of, given to Folio's tools in the AI program:
// only that case, its documents listed with whether they are here, a
// downloaded one read in parts, and a download that waits for the lawyer.
void main() {
  late Directory root;
  late UyapCaseStore store;
  late UyapCaseRecord record;

  UyapCaseDocument doc(String key, String type, {String approved = ''}) =>
      UyapCaseDocument(
        key: key,
        documentId: '',
        caseId: '',
        type: type,
        number: '',
        approved: approved,
        sender: 'İstanbul 5. İş Mahkemesi',
        description: '',
      );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('folio-yz-case-');
    final support = Directory('${root.path}/destek');
    store = UyapCaseStore(
      directory: support,
      settings: UyapSettings(directory: support, home: '${root.path}/ev'),
    );
    final saved = File('${root.path}/ev/Folio/UYAP/bilirkisi.udf')
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    record = UyapCaseRecord(
      court: 'İstanbul 5. İş Mahkemesi',
      number: '2024/123',
      fetchedAt: DateTime(2026, 10, 1),
      details: const UyapCaseDetails(kind: 'İşçi Alacağı', status: 'Açık'),
      parties: const [
        UyapParty('Ali Veli', 'Davacı', 'Av. Ayşe Kaya', 'Kişi'),
        UyapParty('ABC A.Ş.', 'Davalı', '', 'Kurum'),
      ],
      documents: [
        doc('k-rapor', 'Bilirkişi Raporu', approved: '12/09/2026 10:00'),
        doc('k-dilekce', 'Dava Dilekçesi', approved: '01/02/2024 09:00'),
      ],
      files: {'k-rapor': saved.path},
    );
    final file = File(
      '${support.path}/uyap/dosyalar/'
      '${UyapCaseStore.keyOf(record.court, record.number)}.json',
    )..createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(record.toJson()));
  });

  tearDown(() => root.delete(recursive: true));

  Future<(AiCaseSession, FolioCaseTools)> open({
    Future<String> Function(String)? read,
  }) async {
    final session = await AiCaseSession.open(record);
    addTearDown(session.close);
    return (
      session,
      FolioCaseTools(
        session.folder,
        store: store,
        hearings: (_) async => [
          {'tarih': '2026-11-20T10:30', 'tur': 'Tahkikat'},
        ],
        read:
            read ??
            (_) async => 'Davacının yıllık izin ücreti 10000000146 hesaplandı.',
        patience: const Duration(seconds: 5),
        every: const Duration(milliseconds: 20),
      ),
    );
  }

  test('only a question Folio asked has the case\'s tools', () async {
    expect(FolioCaseTools.fromEnvironment(const {}), isNull);
    expect(
      FolioCaseTools.fromEnvironment({
        AiCaseSession.variable: '${root.path}/yok',
      }),
      isNull,
    );
    final (session, tools) = await open();
    expect(
      FolioCaseTools.fromEnvironment({
        AiCaseSession.variable: session.folder.path,
      }),
      isNotNull,
    );
    final without = await FolioMcp().handle({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/list',
    });
    final names = [
      for (final t in ((without!['result'] as Map)['tools'] as List))
        (t as Map)['name'],
    ];
    expect(names, isNot(contains('evrak_oku')));
    final refused = await FolioMcp().handle({
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'tools/call',
      'params': {
        'name': 'evrak_oku',
        'arguments': {'anahtar': 'k-rapor'},
      },
    });
    expect((refused!['error'] as Map)['code'], -32602);
    final withCase = await FolioMcp(caseTools: tools)
        .handle({'jsonrpc': '2.0', 'id': 3, 'method': 'tools/list'});
    expect([
      for (final t in ((withCase!['result'] as Map)['tools'] as List))
        (t as Map)['name'],
    ], containsAll(['dosya_bilgisi', 'dosya_evraklari', 'evrak_oku']));
  });

  test('the case, its parties and hearings; its documents and which are '
      'here', () async {
    final (_, tools) = await open();
    final about = await tools.call('dosya_bilgisi', {});
    expect(about['esas'], '2024/123');
    expect(about['tur'], 'İşçi Alacağı');
    expect((about['taraflar'] as List).first, {
      'ad': 'Ali Veli',
      'rol': 'Davacı',
      'vekil': 'Av. Ayşe Kaya',
    });
    expect(
      (about['durusmalar'] as List).single,
      containsPair('tur', 'Tahkikat'),
    );
    final docs = (await tools.call('dosya_evraklari', {}))['evraklar'] as List;
    expect(docs.map((d) => (d as Map)['indirildi']), [true, false]);
    expect((docs.first as Map)['tarih'], '2026-09-12');
  });

  test('a downloaded document read, identity numbers hidden, in parts; '
      'one not here is said so', () async {
    final long = 'a' * (FolioCaseTools.partSize + 10);
    final (_, tools) = await open();
    final read = await tools.call('evrak_oku', {'anahtar': 'k-rapor'});
    expect(read['durum'], 'bulundu');
    expect(read['metin'], isNot(contains('10000000146')));
    expect(
      (await tools.call('evrak_oku', {'anahtar': 'k-dilekce'}))['durum'],
      'indirilmemis',
    );
    expect(
      (await tools.call('evrak_oku', {'anahtar': 'uydurma'}))['durum'],
      'yok',
    );
    final (_, longTools) = await open(read: (_) async => long);
    final first = await longTools.call('evrak_oku', {'anahtar': 'k-rapor'});
    expect(first['parca_sayisi'], 2);
    final second = await longTools.call('evrak_oku', {
      'anahtar': 'k-rapor',
      'parca': 2,
    });
    expect((second['metin'] as String).length, 10);
  });

  test('a download waits for the lawyer and says what came of it', () async {
    final (session, tools) = await open();
    final asking = tools.call('evrak_indir', {
      'anahtar': 'k-dilekce',
      'neden': 'Talep sonucunu görmek için',
    });
    List<AiDownloadRequest> asked = const [];
    for (var i = 0; i < 100 && asked.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      asked = await session.pending();
    }
    expect(asked.single.key, 'k-dilekce');
    expect(asked.single.reason, 'Talep sonucunu görmek için');
    await session.answer(asked.single, 'reddedildi', 'İstemedi.');
    expect((await asking)['durum'], 'reddedildi');
    expect(await session.pending(), isEmpty);
    // Already here: nothing asked of the lawyer.
    expect(
      (await tools.call('evrak_indir', {
        'anahtar': 'k-rapor',
        'neden': '',
      }))['durum'],
      'indirildi',
    );
    // Not answered in time: the program goes on without it.
    final quick = FolioCaseTools(
      session.folder,
      store: store,
      patience: const Duration(milliseconds: 100),
      every: const Duration(milliseconds: 20),
    );
    expect(
      (await quick.call('evrak_indir', {
        'anahtar': 'k-dilekce',
        'neden': '',
      }))['durum'],
      'yanitsiz',
    );
  });

  test('a document is found to be of its case by where it is', () async {
    final saved = '${root.path}/ev/Folio/UYAP/bilirkisi.udf';
    final found = await AiCaseSession.ofDocument(saved, store);
    expect(found?.number, '2024/123');
    final inFolder = '${store.folderOf(record)}/baska.pdf';
    expect(
      (await AiCaseSession.ofDocument(inFolder, store))?.number,
      '2024/123',
    );
    expect(
      await AiCaseSession.ofDocument('${root.path}/baska.pdf', store),
      isNull,
    );
  });
}

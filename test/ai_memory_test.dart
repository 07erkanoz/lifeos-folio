import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/ai/ai_case.dart';
import 'package:evrak_convert/services/ai/ai_draft.dart';
import 'package:evrak_convert/services/ai/ai_memory.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/services/uyap/uyap_case_data.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:flutter_test/flutter_test.dart';

// What the AI program leaves of a case: kept on the lawyer's devices and
// made alike between them, read back as the case's memory, findings kept
// only with their quotes standing in their documents, drafts as UDF.
void main() {
  test('records kept, taken off and made alike between own devices', () {
    final a = PortalDatabase.memory(), b = PortalDatabase.memory();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    a.putAiRecord('s1', AiMemory.chat, 'dava|1', {'baslik': 'İlk'});
    a.putAiRecord('f1', AiMemory.finding, 'dava|1', {'metin': 'Tespit'});
    expect(b.aiMerge(a.aiExport()), isTrue);
    expect(
      b.aiRecords(AiMemory.chat, caseKey: 'dava|1').single['baslik'],
      'İlk',
    );
    expect(b.aiCounts('dava|1'), {AiMemory.chat: 1, AiMemory.finding: 1});
    // Taken in again: nothing new.
    expect(b.aiMerge(a.aiExport()), isFalse);
    // The later word stands, a taking off as well.
    b.putAiRecord('f1', AiMemory.finding, 'dava|1', {
      'metin': 'Tespit',
      'yanlis': {'neden': 'Değil'},
    });
    a.removeAiRecord('s1');
    expect(a.aiMerge(b.aiExport()), isTrue);
    expect(b.aiMerge(a.aiExport()), isTrue);
    for (final db in [a, b]) {
      expect(db.aiRecords(AiMemory.chat), isEmpty);
      expect(db.aiRecords(AiMemory.finding).single['yanlis'], {
        'neden': 'Değil',
      });
    }
    // Something broken is not taken.
    expect(
      a.aiMerge({
        'kayitlar': [
          {
            'id': 'x',
            'tur': 'bulgu',
            'case_key': 'k',
            'json': '{',
            'surum': '1',
          },
        ],
      }),
      isFalse,
    );
  });

  test('the memory: findings standing and wrong, earlier talks, documents '
      'since; the talk going on left out', () {
    final memory = AiMemory.build(
      chats: [
        {
          'id': 'eski',
          'baslik': 'Rapor',
          'guncellendi': '2026-10-20T10:00:00',
          'turlar': [
            {'soru': 'Raporu incele', 'cevap': 'kısa'},
            {'soru': 'İtiraz ne olur', 'cevap': 'daha uzun bir cevap'},
          ],
        },
        {'id': 'simdi', 'baslik': 'Şimdiki', 'guncellendi': '2026-10-30'},
      ],
      findings: [
        {
          'tur': 'belge',
          'metin': 'İzin hesaplanmamış',
          'kaynaklar': ['evrak:k'],
        },
        {
          'tur': 'acik_soru',
          'metin': 'İzin kullanılmış olabilir',
          'yanlis': {'neden': 'Bordroda yok'},
        },
      ],
      drafts: [
        {'baslik': 'İtiraz dilekçesi', 'zaman': '2026-10-21'},
      ],
      documents: [
        (title: 'Bilirkişi raporu', date: DateTime(2026, 10, 12)),
        (title: 'Ek rapor', date: DateTime(2026, 10, 25)),
      ],
      current: 'simdi',
    );
    expect(
      (memory['bulgular'] as List).single,
      containsPair('tur', 'Belgeden tespit'),
    );
    expect((memory['yanlis_bulunanlar'] as List).single, {
      'metin': 'İzin kullanılmış olabilir',
      'neden': 'Bordroda yok',
    });
    final talks = memory['onceki_sohbetler'] as List;
    expect(talks.single['baslik'], 'Rapor');
    expect(talks.single['en_kapsamli_cevap'], 'daha uzun bir cevap');
    expect(memory['son_sohbetten_beri_gelen_evrak'], ['Ek rapor']);
    expect(AiMemory.hint(const {}), isNull);
    expect(
      AiMemory.hint({AiMemory.finding: 2, AiMemory.chat: 1}),
      contains('dosya_hafizasi'),
    );
    expect(AiMemory.quotes('Raporda "izin defteri bulunmadığından" denmiş'), [
      'izin defteri bulunmadığından',
    ]);
  });

  group('the program\'s findings and drafts', () {
    late Directory root;
    late UyapCaseStore store;
    late UyapCaseRecord record;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('folio-yz-hafiza-');
      final support = Directory('${root.path}/destek');
      store = UyapCaseStore(
        directory: support,
        settings: UyapSettings(directory: support, home: '${root.path}/ev'),
      );
      final saved = File('${root.path}/ev/rapor.udf')
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
      UyapCaseDocument doc(String key, String type) => UyapCaseDocument(
        key: key,
        documentId: '',
        caseId: '',
        type: type,
        number: '',
        approved: '',
        sender: '',
        description: '',
      );
      record = UyapCaseRecord(
        court: 'Manavgat 3. İş Mahkemesi',
        number: '2026/470',
        fetchedAt: DateTime(2026, 10, 1),
        documents: [
          doc('k-rapor', 'Bilirkişi Raporu'),
          doc('k-ara', 'Ara Karar'),
        ],
        files: {'k-rapor': saved.path},
      );
      File(
          '${support.path}/uyap/dosyalar/'
          '${UyapCaseStore.keyOf(record.court, record.number)}.json',
        )
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(record.toJson()));
    });

    tearDown(() => root.delete(recursive: true));

    test('a quote kept only where it stands; unread sources said so; the '
        'lawyer gets what is left', () async {
      final session = await AiCaseSession.open(record, chat: 'simdi');
      addTearDown(session.close);
      final tools = FolioCaseTools(
        session.folder,
        store: store,
        read: (_) async =>
            'Yıllık izin alacağının ise dosyada izin defteri bulunmadığından '
            'hesaplanmadığı görülmüştür.',
        records: (kind, _) async => kind == AiMemory.chat
            ? [
                {'id': 'simdi', 'baslik': 'Şimdiki'},
              ]
            : const [],
      );
      final got = await tools.call('bulgu_oner', {
        'bulgular': [
          {
            'tur': 'belge',
            'metin': 'Rapor "izin defteri bulunmadığından" izni hesaplamamış.',
            'kaynaklar': ['evrak:k-rapor'],
          },
          {
            'tur': 'belge',
            'metin': 'Rapor "izin ücretini tam hesaplamıştır" diyor.',
            'kaynaklar': ['evrak:k-rapor'],
          },
          {
            'tur': 'mahkeme',
            'metin': 'Ara kararda "bilirkişiye izin hesabı" görevi verilmiş.',
            'kaynaklar': ['evrak:k-ara'],
          },
          {'tur': 'uydurma', 'metin': 'Ek rapor istenmeli.'},
        ],
      });
      expect(got['durum'], 'avukata_sunuldu');
      expect(got['sunulan'], 3);
      expect((got['reddedilen'] as List).single['neden'], contains('birebir'));
      final offered = await session.proposals();
      final findings = (offered.single.body['bulgular'] as List).cast<Map>();
      expect(findings.map((f) => f['denetim']), [
        'dogrulandi',
        'dogrulanmadi',
        'dogrulanmadi',
      ]);
      expect(findings.last['tur'], 'cikarim');
      // Taken once.
      expect(await session.proposals(), isEmpty);
      final drafted = await tools.call('taslak_oner', {
        'baslik': 'Rapora itiraz',
        'metin': 'SAYIN MAHKEMEYE\n\nRapora itiraz ederiz.',
      });
      expect(drafted['durum'], 'avukata_sunuldu');
      final draft = (await session.proposals()).single;
      expect(draft.kind, AiMemory.draft);
      expect(draft.body['baslik'], 'Rapora itiraz');
      final memory = await tools.call('dosya_hafizasi', {});
      expect(memory['onceki_sohbetler'], isEmpty);
    });

    test('a draft written as a UDF in the case\'s folder', () async {
      final path = await writeAiDraft(
        store,
        record,
        'Rapora itiraz',
        'SAYIN MAHKEMEYE\n\nDavacı vekili olarak rapora itiraz ederiz.',
      );
      expect(path, startsWith(store.folderOf(record)));
      expect(path, endsWith('Rapora itiraz.udf'));
      final model = UdfReader.readBytes(File(path).readAsBytesSync());
      expect(model!.toPlainText(), contains('rapora itiraz ederiz'));
      final again = await writeAiDraft(store, record, 'Rapora itiraz', 'x');
      expect(again, endsWith('Rapora itiraz (2).udf'));
    });
  });
}

import 'dart:io';

import 'package:evrak_convert/services/ai/ai_external.dart';
import 'package:evrak_convert/services/ai/ai_external_tools.dart';
import 'package:evrak_convert/services/ai/folio_mcp.dart';
import 'package:evrak_convert/services/ai/ai_case.dart';
import 'package:evrak_convert/services/ai/ai_office.dart';
import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/portal/observed.dart' show caseKey;
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_hearing.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PortalDatabase db;
  late Directory folder;
  late FolioExternalTools tools;
  var money = true;
  String? index;
  final now = DateTime(2026, 11, 2, 9);
  const labour = 'Manavgat 3. İş Mahkemesi';
  final labourKey = caseKey('2026/470', labour);
  final debtKey = caseKey('2025/12', 'Manavgat İcra Dairesi');

  setUp(() async {
    money = true;
    index = null;
    folder = await Directory.systemTemp.createTemp('folio-dis-');
    db = PortalDatabase.memory();
    db.mergeCases([
      PortalCase.create(number: '2026/470', court: labour),
      PortalCase.create(number: '2025/12', court: 'Manavgat İcra Dairesi'),
    ], portfolio: true);
    db.mergeHearings(
      PortalChannel.uyapMobile,
      DateTime(2026, 11, 1),
      DateTime(2026, 12, 1),
      [
        PortalHearing.create(
          number: '2026/470',
          court: labour,
          at: DateTime(2026, 11, 25, 10, 30),
        ),
      ],
      complete: true,
    );
    db.setRepresentation(labourKey, const [
      (ad: 'ERKAN YILMAZ', rol: 'Davacı'),
    ]);
    db.setRepresentation(debtKey, const [
      (ad: 'ERKAN YILMAZ', rol: 'Alacaklı'),
    ]);
    tools = FolioExternalTools(
      folder,
      database: () async => db,
      store: UyapCaseStore(
        directory: Directory(p.join(folder.path, 'destek')),
        settings: UyapSettings(
          directory: Directory(p.join(folder.path, 'destek')),
          home: p.join(folder.path, 'ev'),
        ),
      ),
      status: () async => (open: true, money: money),
      indexPath: () async => index,
      read: (_) async => '',
      now: () => now,
    );
  });

  tearDown(() async {
    db.dispose();
    await folder.delete(recursive: true);
  });

  test('a client\'s cases by their name, with the role and the next '
      'hearing', () async {
    final got = await tools.call('muvekkil_dosyalari', {'ifade': 'erkan'});
    expect(got['durum'], 'bulundu');
    final client = (got['muvekkiller'] as List).single as Map;
    expect(client['ad'], 'ERKAN YILMAZ');
    final cases = client['dosyalar'] as List;
    expect(cases, hasLength(2));
    // The one with a hearing coming first.
    expect((cases.first as Map)['esas'], '2026/470');
    expect((cases.first as Map)['rol'], 'Davacı');
    expect((cases.first as Map)['siradaki_durusma'], '2026-11-25T10:30');
    expect(
      (await tools.call('muvekkil_dosyalari', {'ifade': 'Ayşe'}))['durum'],
      'yok',
    );
  });

  test(
    'a client\'s card: its money records only with the right to them',
    () async {
      db.saveClient(
        Client(
          id: 'k1',
          name: 'ERKAN YILMAZ',
          phone: '0555 000 00 00',
          updated: now,
        ),
      );
      final key =
          ((await tools.call('muvekkiller', {'ifade': 'yılmaz'}))['muvekkiller']
                      as List)
                  .single
              as Map;
      expect(key['telefon'], '0555 000 00 00');
      db.putRecordForTesting(
        ClientRecord(
          id: 'r1',
          clientId: 'k1',
          kind: ClientRecordKind.meeting,
          data: const {'metin': 'İşe iade görüşmesi'},
          created: now,
          by: 'Av. Deniz Kaya',
          updated: now,
        ),
      );
      db.putRecordForTesting(
        ClientRecord(
          id: 'r2',
          clientId: 'k1',
          kind: ClientRecordKind.fee,
          data: const {'tutar': 5000000},
          created: now,
          by: 'Av. Deniz Kaya',
          updated: now,
        ),
      );
      var card = await tools.call('muvekkil', {'anahtar': key['anahtar']});
      expect(card['kayitlar'] as List, hasLength(2));
      money = false;
      card = await tools.call('muvekkil', {'anahtar': key['anahtar']});
      expect(card['kayitlar'] as List, hasLength(1));
      expect('${card['not']}', contains('para kaydı'));
      expect((await tools.call('kasa', {}))['durum'], 'yetki_yok');
    },
  );

  test('a task added to the agenda, told to the open Folio', () async {
    final got = await tools.call('ajanda_ekle', {
      'tur': 'gorev',
      'baslik': 'Bilirkişi raporuna itiraz',
      'tarih': '2026-11-10',
      'saat': '14:00',
      'dosya': labourKey,
    });
    expect(got['durum'], 'eklendi');
    final kept = db
        .agenda(from: DateTime(2026, 11, 10), to: DateTime(2026, 11, 11))
        .single;
    expect(kept.kind, 'task');
    expect(kept.at, DateTime(2026, 11, 10, 14));
    expect(kept.allDay, isFalse);
    expect(kept.caseKey, labourKey);
    expect(
      folder.listSync().map((e) => p.basename(e.path)),
      contains(startsWith('degisti-')),
    );
  });

  test('a note, and what is refused', () async {
    final got = await tools.call('not_ekle', {
      'metin': 'Müvekkil tanık listesini cuma getirecek.',
      'dosya': labourKey,
    });
    expect(got['durum'], 'eklendi');
    final note = db
        .agenda(from: DateTime(2026, 11, 2), to: DateTime(2026, 11, 3))
        .single;
    expect(note.kind, 'note');
    expect(note.title, 'Müvekkil tanık listesini cuma getirecek.');
    expect(note.caseKey, labourKey);
    expect(
      (await tools.call('ajanda_ekle', {
        'tur': 'durusma',
        'baslik': 'x',
        'tarih': '2026-11-10',
      }))['durum'],
      'yok',
    );
    expect(
      (await tools.call('not_ekle', {
        'metin': 'x',
        'dosya': 'olmayan|dosya',
      }))['durum'],
      'yok',
    );
  });

  test('the index searched, a document in it read, nothing else', () async {
    final dir = await Directory.systemTemp.createTemp('folio-dizin-');
    addTearDown(() => dir.delete(recursive: true));
    final doc = File(p.join(dir.path, 'ihtarname.txt'))
      ..writeAsStringSync('Kira bedelinin ödenmesi ihtarıdır.');
    index = p.join(dir.path, 'evrak_index.sqlite');
    final made = sqlite3.open(index!);
    made.execute('''
      CREATE TABLE documents (id INTEGER PRIMARY KEY, path TEXT, name TEXT,
        extension TEXT, modified INTEGER, state TEXT, text TEXT);
      CREATE VIRTUAL TABLE search_fts USING fts5(name, body,
        tokenize='unicode61 remove_diacritics 0', prefix='2 3 4');
    ''');
    made.execute('INSERT INTO documents VALUES (1, ?, ?, ?, ?, ?, ?)', [
      doc.path,
      'ihtarname.txt',
      'txt',
      DateTime(2026, 10, 1).millisecondsSinceEpoch,
      'ready',
      'Kira bedelinin ödenmesi ihtarıdır.',
    ]);
    made.execute(
      "INSERT INTO search_fts(rowid, name, body) VALUES (1, 'ihtarname.txt', "
      "'Kira bedelinin ödenmesi ihtarıdır.')",
    );
    made.dispose();

    final found = await tools.call('evrak_ara', {'sorgu': 'kira'});
    expect(found['durum'], 'bulundu');
    final hit = (found['belgeler'] as List).single as Map;
    expect(hit['yol'], doc.path);
    expect(hit['tarih'], '2026-10-01');
    final read = await tools.call('belge_oku', {'yol': doc.path});
    expect(read['metin'], 'Kira bedelinin ödenmesi ihtarıdır.');
    expect(
      (await tools.call('belge_oku', {'yol': '/etc/passwd'}))['durum'],
      'yok',
    );
  });

  test('the server for programs on this computer: the whole of Folio, not '
      'the panel\'s proposals', () async {
    final session = await AiCaseSession.open(null);
    addTearDown(session.close);
    final server = FolioMcp(
      caseTools: FolioCaseTools(session.folder, anyCase: true),
      officeTools: FolioOfficeTools(session.folder),
      externalTools: tools,
    );
    final listed = await server.handle({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/list',
    });
    final names = [
      for (final t in (listed!['result'] as Map)['tools'] as List)
        (t as Map)['name'],
    ];
    expect(
      names,
      containsAll([
        'muvekkil_dosyalari',
        'icra_hesabi',
        'evrak_ara',
        'ajanda_ekle',
        'not_ekle',
        'dosya_bilgisi',
        'ajanda',
      ]),
    );
    expect(names, isNot(contains('bulgu_oner')));
    expect(names, isNot(contains('taslak_oner')));
    final plain = FolioMcp();
    final alone = await plain.handle({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/list',
    });
    expect([
      for (final t in (alone!['result'] as Map)['tools'] as List)
        (t as Map)['name'],
    ], isNot(contains('muvekkiller')));
    expect(FolioExternal.flag, '--dis');
  });
}

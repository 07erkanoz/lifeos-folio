import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/ai/ai_case.dart';
import 'package:evrak_convert/services/ai/ai_refresh.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/services/voice/ajan_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// Folio Ajan's voice has no panel to serve it: what it asks of UYAP is
// answered by the session's own server, not left to wait (22 Kasım 2026).
void main() {
  test('a refresh the voice asked for is answered', () async {
    final session = await AiCaseSession.open(null);
    addTearDown(() => session.folder.delete(recursive: true));
    await File(p.join(session.folder.path, 'guncelle-1.json'))
        .writeAsString(jsonEncode({'kapsam': 'durusmalar'}));
    await AiSessionServer(session).tick();
    final answer = File(p.join(session.folder.path, 'guncelle-1.sonuc.json'));
    expect(await answer.exists(), isTrue);
    final json = jsonDecode(await answer.readAsString()) as Map;
    // No UYAP and no sync in a test: said so, not silence.
    expect(json['durum'], isNot('yanitsiz'));
  });

  test('a download with no case chosen says so', () async {
    final session = await AiCaseSession.open(null);
    addTearDown(() => session.folder.delete(recursive: true));
    await File(p.join(session.folder.path, 'indir-2.json'))
        .writeAsString(jsonEncode({'anahtar': 'x', 'neden': 'okumak'}));
    await AiSessionServer(session).tick();
    final answer = File(p.join(session.folder.path, 'indir-2.sonuc.json'));
    expect(await answer.exists(), isTrue);
  });

  test('a petition spoken for goes to the chosen case as a UDF', () async {
    final root = await Directory.systemTemp.createTemp('folio-ajan-dilekce-');
    addTearDown(() => root.delete(recursive: true));
    final support = Directory('${root.path}/destek');
    final store = UyapCaseStore(
      directory: support,
      settings: UyapSettings(directory: support, home: '${root.path}/ev'),
    );
    const court = 'Manavgat 3. İş Mahkemesi';
    final record = await store.keep(
      target: const UyapCase('1', '2026/470', '', court),
      details: const UyapCaseDetails(),
      parties: const [],
      documents: const UyapCaseDocuments([]),
    );
    final session = await AiCaseSession.open(record);
    final host = AjanToolHost(session, store: store);
    addTearDown(host.close);
    final saved = jsonDecode(
      await host.call(AjanToolHost.petitionTool, {
        'baslik': 'Cevap dilekçesi',
        'metin': 'MANAVGAT 3. İŞ MAHKEMESİNE\n\nDavaya cevaplarımızdır.',
      }),
    ) as Map;
    expect(saved['durum'], 'kaydedildi');
    final file = File('${store.folderOf(record)}/Cevap dilekçesi.udf');
    expect(file.existsSync(), isTrue);
    final model = UdfReader.readBytes(file.readAsBytesSync());
    expect(model!.toPlainText(), contains('Davaya cevaplarımızdır'));
    final names = [for (final t in await host.tools()) t['name']];
    expect(names, containsAll(['ajanda_ekle', 'not_ekle', 'tebligat_oku']));
    expect(names, contains(AjanToolHost.petitionTool));
  });
}

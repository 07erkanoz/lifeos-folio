import 'dart:io';

import 'package:evrak_convert/services/ai/ai_case.dart';
import 'package:evrak_convert/services/ai/ai_office.dart';
import 'package:evrak_convert/services/ai/ai_refresh.dart';
import 'package:evrak_convert/services/ai/folio_mcp.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_hearing.dart';
import 'package:flutter_test/flutter_test.dart';

// The lawyer's whole practice in the program Folio runs for a question:
// the week's hearings and tasks, the cases, what is secret left out, and a
// refresh from UYAP the running Folio does when asked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PortalDatabase db;
  late AiCaseSession session;
  late FolioOfficeTools tools;
  final now = DateTime(2026, 11, 2, 9);

  setUp(() async {
    db = PortalDatabase.memory();
    db.mergeCases([
      PortalCase.create(number: '2026/470', court: 'Manavgat 3. İş Mahkemesi'),
      PortalCase.create(number: '2025/12', court: 'Manavgat İcra Dairesi'),
    ], portfolio: true);
    db.mergeHearings(
      PortalChannel.uyapMobile,
      DateTime(2026, 11, 1),
      DateTime(2026, 12, 1),
      [
        PortalHearing.create(
          number: '2026/470',
          court: 'Manavgat 3. İş Mahkemesi',
          at: DateTime(2026, 11, 4, 10, 30),
        ),
        PortalHearing.create(
          number: '2026/470',
          court: 'Manavgat 3. İş Mahkemesi',
          at: DateTime(2026, 11, 25, 10, 30),
        ),
      ],
      complete: true,
    );
    for (final (id, secret) in [('g1', false), ('g2', true)]) {
      db.saveAgenda(
        AgendaItem(
          id: id,
          kind: 'task',
          title: secret ? 'Gizli görev' : 'Bilirkişi raporuna itiraz',
          at: DateTime(2026, 11, 3, 9),
          updated: now,
          secret: secret,
        ),
      );
    }
    session = await AiCaseSession.open(null, chat: 'c1');
    tools = FolioOfficeTools(
      session.folder,
      database: () async => db,
      now: () => now,
      patience: const Duration(seconds: 5),
      every: const Duration(milliseconds: 20),
    );
  });

  tearDown(() async {
    await session.close();
    db.dispose();
  });

  test('the week: its hearings and tasks, the secret one left out', () async {
    final week = await tools.call('ajanda', {});
    expect(week['aralik'], '2026-11-02 – 2026-11-08');
    final hearings = week['durusmalar'] as List;
    expect(hearings.single, containsPair('tarih', '2026-11-04T10:30'));
    expect(hearings.single, containsPair('esas', '2026/470'));
    final tasks = week['gorev_ve_notlar'] as List;
    expect(tasks.single, containsPair('baslik', 'Bilirkişi raporuna itiraz'));
    final month = await tools.call('ajanda', {
      'bas': '2026-11-01',
      'bit': '2026-11-30',
    });
    expect((month['durusmalar'] as List).length, 2);
  });

  test('the cases, the next hearing first; by a word', () async {
    final all = await tools.call('dosyalar', {});
    expect(all['toplam'], 2);
    final first = (all['dosyalar'] as List).first as Map;
    expect(first['esas'], '2026/470');
    expect(first['siradaki_durusma'], '2026-11-04T10:30');
    final icra = await tools.call('dosyalar', {'ifade': 'icra'});
    expect((icra['dosyalar'] as List).single['esas'], '2025/12');
  });

  test('a refresh asked of the running Folio and answered; with no '
      'connection said so', () async {
    final asking = tools.call('uyap_guncelle', {'kapsam': 'durusmalar'});
    List<({String id, String scope, String key})> asked = const [];
    for (var i = 0; i < 100 && asked.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      asked = await session.refreshes();
    }
    expect(asked.single.scope, 'durusmalar');
    // Given once.
    expect(await session.refreshes(), isEmpty);
    await session.answerRefresh(
      asked.single.id,
      await AiRefresh.run('durusmalar', ''),
    );
    final got = await asking;
    expect(got['durum'], anyOf('bagli_degil', 'yapilamadi'));

    final links = await AiRefresh.run('baglantilar', '');
    expect(links, containsPair('uyap_web', false));
    expect(links['not'], contains('icra hesabını'));
    expect(
      (await tools.call('uyap_guncelle', {'kapsam': 'dosya'}))['durum'],
      'yok',
    );
  });

  test('given only in a question Folio asked, with the case\'s', () async {
    expect(FolioOfficeTools.fromEnvironment(const {}), isNull);
    expect(
      FolioOfficeTools.fromEnvironment({
        AiCaseSession.variable: session.folder.path,
      }),
      isNotNull,
    );
    final listed = await FolioMcp(officeTools: tools)
        .handle({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'});
    expect([
      for (final t in (listed!['result'] as Map)['tools'] as List) t['name'],
    ], containsAll(['ajanda', 'tebligatlar', 'uyap_guncelle', 'dosyalar']));
    expect(FolioMcp.names, contains('uyap_baglantilari'));
    expect(Directory(session.folder.path).existsSync(), isTrue);
  });
}

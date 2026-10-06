import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late UyapMobileApi api;
  late PortalDatabase db;
  final asked = <String>[];

  setUp(() async {
    asked.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final text = await utf8.decoder.bind(r).join();
      final body = text.isEmpty ? const {} : jsonDecode(text) as Map;
      final path = r.uri.path.replaceFirst('/services/', '');
      asked.add(path);
      Object? answer = const {};
      if (path == 'auth/edevlet') {
        answer = {'accessToken': 'a', 'refreshToken': 'r'};
      } else if (path == 'mobile/avukat/user') {
        answer = {'adi': 'Deniz'};
      } else if (path == 'mobile/ortak/yargibirimleri/1') {
        answer = {
          'yargiBirimleri': [
            {'tablo': 'AYM', 'kod': '1'},
          ],
        };
      } else if (path.startsWith('mobile/ortak/yargibirimleri/')) {
        answer = {'yargiBirimleri': []};
      } else if (path == 'mobile/avukat/mahkeme') {
        answer = {
          'birimListesi': [
            {'birimId': 'enc-1', 'birimAdi': 'Antalya 3. Asliye Hukuk'},
          ],
        };
      } else if (path == 'mobile/avukat/dosya') {
        final closed = body['dosyaKapaliMi'] == true;
        answer = {
          'dosyaList': [
            {
              'dosyaId': closed ? 'k1' : 'o1',
              'dosyaNo': closed ? '2019/88' : '2025/412',
              'birimAdi': 'Antalya 3. Asliye Hukuk Mahkemesi',
              'dosyaKapaliMi': closed,
              'dosyaTurAciklama': 'Hukuk Dava Dosyası',
            },
          ],
        };
      } else if (path == 'mobile/avukat/dosya/o1/1') {
        answer = {
          'tumEvraklar': {
            '2025/412(Esas)##x': [
              {'evrakTuruAciklama': 'Ara Karar', 'onayTarihi': '28.09.2026'},
              {
                'evrakTuruAciklama': 'Bilirkişi Raporu',
                'onayTarihi': '03.10.2026',
              },
            ],
          },
        };
      } else if (path == 'mobile/avukat/danistaydaireleri') {
        answer = {'danistayDairesi': []};
      }
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode(answer));
      await r.response.close();
    });
    api = UyapMobileApi.forTesting(
      Uri.parse('http://127.0.0.1:${server.port}/services/'),
    );
    db = PortalDatabase.memory();
  });
  tearDown(() async {
    db.dispose();
    await server.close(force: true);
  });

  test('the mobile API fills the portfolio, open and closed', () async {
    await api.login('kod');
    final result = await syncMobilePortfolio(api, db);
    expect(result.complete, isTrue);
    final cases = db.cases().values.toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    expect(cases.map((c) => c.number), ['2019/88', '2025/412']);
    expect(cases.first.status!.value, 'Kapalı');
    expect(cases.last.ids[PortalChannel.uyapMobile], 'o1');
    // Only the mobile API was asked: no web portal request.
    expect(asked.every((p) => !p.contains('.ajx')), isTrue);
  });

  test('a case is synced on its own, newest document first', () async {
    await api.login('kod');
    await syncMobilePortfolio(api, db);
    final sync = PortalSync(
      web: UyapWebService.forTesting(),
      mobile: api,
      database: () async => db,
    );
    const court = 'Antalya 3. Asliye Hukuk Mahkemesi';
    expect(await sync.syncCase(caseKey('2025/412', court)), isNull);
    final docs = db.cases()[caseKey('2025/412', court)]!.documents!.value;
    expect(docs.map((d) => d['ad']), ['Bilirkişi Raporu', 'Ara Karar']);
    expect(await sync.syncCase('yok'), isNotNull);
  });

  test('the mobile API fills the web’s gaps and keeps its fields', () async {
    const court = 'Antalya 3. Asliye Hukuk Mahkemesi';
    db.mergeCases([
      PortalCase(
        key: caseKey('2025/412', court),
        number: '2025/412',
        court: court,
        ids: const {PortalChannel.uyapWeb: '991'},
        details: Observed(
          {'tur': 'Alacak (Ticari)', 'konu': 'Fatura alacağı'},
          PortalChannel.uyapWeb,
          DateTime.utc(2026, 10, 1),
        ),
      ),
    ]);
    await api.login('kod');
    await syncMobilePortfolio(api, db);
    final one = db.cases()[caseKey('2025/412', court)]!;
    expect(one.details!.value['konu'], 'Fatura alacağı');
    expect(one.status!.value, 'Açık');
    expect(one.ids.keys, containsAll(PortalChannel.values.take(2)));
  });
}

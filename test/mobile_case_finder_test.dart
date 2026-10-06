import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/uyap/mobile_case_finder.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late UyapMobileApi api;
  final asked = <String>[];

  setUp(() async {
    asked.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final text = await utf8.decoder.bind(r).join();
      final body = text.isEmpty ? null : jsonDecode(text) as Map;
      final path = r.uri.path.replaceFirst('/services/', '');
      asked.add(path);
      Object? answer = const {};
      if (path == 'auth/edevlet') {
        answer = {
          'accessToken': 'a',
          'refreshToken': 'r',
          'accessTokenLifetime': 3300,
          'refreshTokenLifetime': 604800,
        };
      } else if (path == 'mobile/avukat/user') {
        answer = {'adi': 'Deniz'};
      } else if (path == 'mobile/ortak/yargibirimleri/0') {
        answer = {
          'yargiBirimleri': [
            {'tablo': '0904'},
            {'tablo': '0905'},
          ],
        };
      } else if (path == 'mobile/avukat/mahkeme') {
        answer = {
          'birimListesi': [
            if (body!['birimTuru2'] == '0905' && body['dosyaKapaliMi'] == false)
              {
                'birimId': 'enc==',
                'birimAdi': 'Manavgat 5. Asliye Ceza Mahkemesi',
              },
          ],
        };
      } else if (path == 'mobile/avukat/dosya') {
        answer = {
          'dosyaList': [
            if (body!['mahkeme'] == 'enc==' &&
                body['dosyaYil'] == '2026' &&
                body['dosyaSira'] == '342')
              {
                'dosyaId': 'm-342',
                'dosyaNo': '2026/342',
                'birimAdi': 'Manavgat 5. Asliye Ceza Mahkemesi',
              },
          ],
        };
      }
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode(answer));
      await r.response.close();
    });
    api = UyapMobileApi.forTesting(
      Uri.parse('http://127.0.0.1:${server.port}/services/'),
    );
    await api.login('code');
  });
  tearDown(() => server.close(force: true));

  test(
    'a case is found by its court and number, without the portfolio',
    () async {
      final finder = MobileCaseFinder(api);
      final id = await finder.find(
        court: 'Manavgat 5. Asliye Ceza Mahkemesi',
        number: '2026/342',
      );
      expect(id, 'm-342');
      // The kinds of unit, the courts of each, the one case: no court's list.
      expect(asked.where((p) => p == 'mobile/avukat/dosya').length, 1);
      asked.clear();
      // Known codes go straight to the court.
      expect(
        await finder.find(
          court: 'Manavgat 5. Asliye Ceza Mahkemesi',
          number: '2026/342',
          jurisdiction: '0',
          unitKind: '0905',
        ),
        'm-342',
      );
      expect(asked, ['mobile/avukat/dosya']);
    },
  );

  test('another court or number is no match', () async {
    final finder = MobileCaseFinder(api);
    expect(
      await finder.find(
        court: 'Manavgat 6. Asliye Ceza Mahkemesi',
        number: '2026/342',
      ),
      isNull,
    );
    expect(
      await finder.find(
        court: 'Manavgat 5. Asliye Ceza Mahkemesi',
        number: '2026/343',
      ),
      isNull,
    );
  });
}

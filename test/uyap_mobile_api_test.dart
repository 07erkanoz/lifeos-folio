import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in for mobilws.uyap.gov.tr that records what it was asked.
class _Fake {
  late HttpServer server;
  final requests = <(String, String, Object?)>[];
  int refreshes = 0;
  String access = 'a1';
  bool refuseNextAsBody = false;
  int fail500 = 0;

  Uri get base => Uri.parse('http://127.0.0.1:${server.port}/services/');

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final text = await utf8.decoder.bind(r).join();
      final body = text.isEmpty ? null : jsonDecode(text);
      final path = r.uri.path.replaceFirst('/services/', '');
      requests.add((r.method, path, body));
      Object? answer;
      var status = 200;
      final bearer = r.headers.value('Authorization');
      if (path == 'auth/edevlet') {
        answer = {
          'accessToken': access,
          'refreshToken': 'r1',
          'accessTokenLifetime': 3300,
          'refreshTokenLifetime': 604800,
        };
      } else if (path == 'auth/refresh') {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        access = 'a${refreshes + 1}';
        answer = {'accessToken': access, 'accessTokenLifetime': 3300};
      } else if (bearer != 'Bearer $access') {
        status = 401;
      } else if (refuseNextAsBody) {
        refuseNextAsBody = false;
        access = 'stale';
        answer = {'status': 403, 'message': 'yetkisiz'};
      } else if (path == 'mobile/avukat/user') {
        answer = {'adi': 'Deniz', 'soyadi': 'Y.', 'baroAdi': 'Antalya'};
      } else if (path.startsWith('mobile/avukat/durusmalarim/')) {
        answer = {
          'listDurusmalar': [
            {'dosyaNo': '2025/412', 'tarihSaat': '06.10.2026 09:20:00'},
          ],
        };
      } else if (path.startsWith('mobile/ortak/evrakV2/')) {
        if (fail500-- > 0) {
          status = 500;
        } else {
          answer = {
            'evrakContentDVO': {
              'content': base64Encode([1, 2, 3]),
            },
          };
        }
      } else if (path == 'mobile/avukat/dosya') {
        final page = (body as Map)['pageCount'] as int;
        answer = {
          'dosyaList': [
            for (var i = 0; i < (page == 1 ? 100 : 7); i++)
              {'dosyaId': '$page-$i', 'dosyaNo': '2026/$i'},
          ],
        };
      }
      r.response.statusCode = status;
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode(answer ?? {}));
      await r.response.close();
    });
  }
}

void main() {
  late _Fake fake;
  late UyapMobileApi api;
  setUp(() async {
    fake = _Fake();
    await fake.start();
    api = UyapMobileApi.forTesting(fake.base);
  });
  tearDown(() => fake.server.close(force: true));

  test('the e-Devlet page and its return belong to the mobile API', () {
    final page = UyapMobileApi.loginPage('482915');
    expect(page.host, 'giris.turkiye.gov.tr');
    expect(
      page.queryParameters['redirect_uri'],
      'https://mobilws.uyap.gov.tr/portaldmz/avukat.html',
    );
    expect(page.queryParameters['state'], '482915');
    expect(
      UyapMobileApi.isReturn(
        Uri.parse('https://mobilws.uyap.gov.tr/portaldmz/avukat.html?code=x'),
      ),
      isTrue,
    );
    // The web portal's return, or a look-alike, is not this API's.
    for (final other in [
      'https://avukat.uyap.gov.tr/login.uyap?code=x',
      'https://mobilws.uyap.gov.tr.example.com/portaldmz/avukat.html?code=x',
      'http://mobilws.uyap.gov.tr/portaldmz/avukat.html?code=x',
    ]) {
      expect(UyapMobileApi.isReturn(Uri.parse(other)), isFalse, reason: other);
    }
  });

  test('a login sends the code with the device fields and reads who', () async {
    final s = await api.login('kod-123');
    final exchange = fake.requests.first;
    expect(exchange.$2, 'auth/edevlet');
    expect(exchange.$3, {
      'code': 'kod-123',
      'model': 'windows_desktop',
      'serial': 'LifeOS_Folio',
      'type': '2',
    });
    expect(s.user, 'Deniz Y.');
    expect(api.connected, isTrue);
    expect(api.session.value?.bar, 'Antalya');
  });

  test('a refused token is renewed once, for every request waiting', () async {
    await api.login('kod');
    fake.access = 'changed-by-uyap';
    final both = await Future.wait([
      api.hearingRows(DateTime(2026, 10, 1), DateTime(2026, 10, 29)),
      api.hearingRows(DateTime(2026, 11, 1), DateTime(2026, 11, 29)),
    ]);
    expect(both.every((rows) => rows.length == 1), isTrue);
    expect(fake.refreshes, 1);
  });

  test('a refusal in the body is renewed as well', () async {
    await api.login('kod');
    fake.refuseNextAsBody = true;
    final rows = await api.hearingRows(
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 29),
    );
    expect(rows, hasLength(1));
    expect(fake.refreshes, 1);
  });

  test('the hearings are asked with dotted, padded dates', () async {
    await api.login('kod');
    await api.hearingRows(DateTime(2026, 10, 1), DateTime(2026, 10, 29));
    expect(
      fake.requests.last.$2,
      'mobile/avukat/durusmalarim/01.10.2026/29.10.2026',
    );
  });

  test('a document is asked again after a passing 500', () async {
    await api.login('kod');
    fake.fail500 = 2;
    expect(await api.documentBytes('e1', 'd1'), [1, 2, 3]);
  });

  test('the cases come page by page until a page is short', () async {
    await api.login('kod');
    final rows = await api.cases(1, 'AYM', 'birim', closed: false);
    expect(rows, hasLength(107));
  });

  test('without a login nothing is asked', () async {
    expect(
      () => api.hearingRows(DateTime(2026, 10, 1), DateTime(2026, 10, 2)),
      throwsStateError,
    );
    expect(fake.requests, isEmpty);
  });
}

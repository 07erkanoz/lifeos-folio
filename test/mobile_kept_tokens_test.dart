import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:flutter_test/flutter_test.dart';

// Two runs of Folio share one UYAP Mobil session (the phone's background
// check and the open app): tokens renewed by one are taken up by the
// other, not renewed again with a refresh token already used.
void main() {
  late HttpServer server;
  final asked = <String>[];

  setUp(() async {
    asked.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      await utf8.decoder.bind(r).join();
      final path = r.uri.path.replaceFirst('/services/', '');
      final bearer = r.headers.value('Authorization') ?? '';
      asked.add('$path $bearer');
      r.response.headers.contentType = ContentType.json;
      if (path == 'auth/edevlet') {
        r.response.write(jsonEncode({'accessToken': 'a', 'refreshToken': 'r'}));
      } else if (path == 'auth/refresh') {
        r.response.write(
          jsonEncode({'accessToken': 'a3', 'refreshToken': 'r3'}),
        );
      } else if (path == 'mobile/avukat/user') {
        r.response.write(jsonEncode({'adi': 'Deniz'}));
      } else if (bearer == 'Bearer a') {
        // The old access token, no longer good.
        r.response.statusCode = 401;
        r.response.write('{}');
      } else {
        r.response.write(jsonEncode({'bildirimler': const []}));
      }
      await r.response.close();
    });
  });
  tearDown(() => server.close(force: true));

  test('tokens renewed elsewhere are taken up, not renewed again', () async {
    final api = UyapMobileApi.forTesting(
      Uri.parse('http://127.0.0.1:${server.port}/services/'),
    );
    await api.login('kod');
    final now = DateTime.now();
    api.keptTokens = () async => MobileTokens(
      access: 'a2',
      refresh: 'r2',
      accessExpires: now.add(const Duration(hours: 1)),
      refreshExpires: now.add(const Duration(days: 6)),
    );
    await api.noticeRows();
    expect(asked.where((a) => a.startsWith('auth/refresh')), isEmpty);
    expect(asked.last, 'mobile/bildirim/bildirimlerim/null Bearer a2');
  });

  test('with nothing newer kept, the session is renewed as before', () async {
    final api = UyapMobileApi.forTesting(
      Uri.parse('http://127.0.0.1:${server.port}/services/'),
    );
    await api.login('kod');
    await api.noticeRows();
    expect(asked.where((a) => a.startsWith('auth/refresh')), hasLength(1));
    expect(asked.last, 'mobile/bildirim/bildirimlerim/null Bearer a3');
  });
}

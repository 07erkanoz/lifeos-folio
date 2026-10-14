import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:flutter_test/flutter_test.dart';

// A kept UYAP Mobil session is dropped only when UYAP refuses it: Folio
// started without a network, or UYAP's own server error, keeps it for the
// next try.
void main() {
  late HttpServer server;
  late UyapMobileApi api;
  var userStatus = 200;
  var refreshStatus = 200;
  // The user's answer in a 200's body: its status, as UYAP Mobil may say an
  // access token is over in it; null for a plain answer.
  String? userBody;
  var bodyOnce = false;
  final told = <MobileTokens?>[];
  final logged = <String>[];

  setUp(() async {
    told.clear();
    logged.clear();
    userStatus = 200;
    refreshStatus = 200;
    userBody = null;
    bodyOnce = false;
    UyapMobileApi.log = logged.add;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final path = r.uri.path.replaceFirst('/services/', '');
      r.response.headers.contentType = ContentType.json;
      if (path == 'mobile/avukat/user') {
        r.response.statusCode = userStatus;
        if (userBody != null) {
          r.response.write(userBody);
          if (bodyOnce) userBody = null;
        } else {
          r.response.write(jsonEncode({'adi': 'Deniz'}));
        }
      } else if (path == 'auth/refresh') {
        r.response.statusCode = refreshStatus;
        r.response.write(jsonEncode({'accessToken': 'a2'}));
      } else {
        r.response.write('{}');
      }
      await r.response.close();
    });
    api = UyapMobileApi.forTesting(
      Uri.parse('http://127.0.0.1:${server.port}/services/'),
    )..onTokens = told.add;
  });
  tearDown(() {
    UyapMobileApi.log = null;
    return server.close(force: true);
  });

  MobileTokens kept({bool accessExpired = false}) {
    final now = DateTime.now();
    return MobileTokens(
      access: 'a1',
      refresh: 'r1',
      accessExpires: accessExpired
          ? now.subtract(const Duration(minutes: 1))
          : now.add(const Duration(minutes: 30)),
      refreshExpires: now.add(const Duration(days: 5)),
    );
  }

  test('a good session comes back', () async {
    final session = await api.restore(kept());
    expect(session?.user, 'Deniz');
    expect(api.connected, isTrue);
    expect(told, isEmpty);
  });

  test('UYAP’s server error keeps the session for the next try', () async {
    userStatus = 503;
    await expectLater(
      api.restore(kept()),
      throwsA(isA<UyapMobileUnreachable>()),
    );
    expect(api.connected, isFalse);
    expect(told, isEmpty, reason: 'the kept tokens are not removed');
  });

  test('a server error while renewing keeps the session too', () async {
    refreshStatus = 502;
    await expectLater(
      api.restore(kept(accessExpired: true)),
      throwsA(isA<UyapMobileUnreachable>()),
    );
    expect(told, isEmpty);
  });

  test('no network keeps the session', () async {
    final port = server.port;
    await server.close(force: true);
    final offline = UyapMobileApi.forTesting(
      Uri.parse('http://127.0.0.1:$port/services/'),
    )..onTokens = told.add;
    await expectLater(
      offline.restore(kept()),
      throwsA(isA<UyapMobileUnreachable>()),
    );
    expect(told, isEmpty);
  });

  test('a refused renewal ends the session and drops it', () async {
    refreshStatus = 401;
    expect(await api.restore(kept(accessExpired: true)), isNull);
    expect(api.connected, isFalse);
    expect(told, [null]);
  });

  test('an access token said over in a 200\'s body is renewed, and the '
      'session goes on', () async {
    userBody = jsonEncode({'status': 401, 'message': 'Token süresi doldu'});
    bodyOnce = true;
    final session = await api.restore(kept());
    expect(session?.user, 'Deniz');
    expect(api.connected, isTrue);
    expect(told.single?.access, 'a2', reason: 'renewed, and kept');
    expect(logged, contains('UYAP Mobil erişim jetonu yenilendi'));
  });

  test('an answer not understood keeps the session for the next try', () async {
    userBody = jsonEncode({'status': 500, 'message': 'Beklenmeyen hata'});
    await expectLater(
      api.restore(kept()),
      throwsA(isA<UyapMobileUnreachable>()),
    );
    expect(told, isEmpty, reason: 'the kept tokens are not removed');
    expect(
      logged.single,
      startsWith('UYAP Mobil oturumu şimdilik açılamadı, saklı kalıyor'),
    );
  });

  test('why a session ended is told in the log, with no token in it', () async {
    refreshStatus = 400;
    expect(await api.restore(kept(accessExpired: true)), isNull);
    expect(told, [null]);
    expect(
      logged,
      contains(startsWith('UYAP Mobil yenileme jetonunu reddetti: HTTP 400')),
    );
    for (final line in logged) {
      expect(line.contains('r1') || line.contains('a1'), isFalse, reason: line);
    }
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/uyap/uyap_web_service.dart';

/// Logging into the Avukat Portal through e-Devlet, against a stand-in for
/// the portal that behaves as the real one was measured to.
void main() {
  late HttpServer server;
  late UyapWebService web;
  final loggedIn = <String>{};
  var alive = true;

  setUp(() async {
    loggedIn.clear();
    alive = true;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var sessions = 0;
    server.listen((request) async {
      final response = request.response;
      final session = request.cookies
          .where((c) => c.name == 'JSESSIONID')
          .map((c) => c.value)
          .firstOrNull;
      switch (request.uri.path) {
        case '/portal_baslangic.uyap':
          expect(request.uri.queryParameters['login_type'], isIn(['m', 't']));
          response.cookies.add(Cookie('JSESSIONID', 'oturum-${++sessions}'));
          response.headers.contentType = ContentType.html;
          response.write('<html></html>');
        case '/kullanici_bilgileri.uyap' when request.method == 'GET':
          // The portal answers this as text/json.
          response.headers.set('Content-Type', 'text/json');
          final level = loggedIn.contains(session) && alive ? 2 : 0;
          response.write(
            jsonEncode({
              'level': level,
              'random': 0,
              'login_type': 'm',
              'user': 'a',
            }),
          );
        case '/login.uyap':
          // The state is bound to the session that asked for it.
          if (session == null) {
            response.statusCode = 401;
            response.write('<root><error>nosessionobject</error></root>');
          } else if (request.uri.queryParameters['code'] == 'dogru-kod' &&
              request.uri.queryParameters['state'] == '0') {
            loggedIn.add(session);
            response.statusCode = 302;
            response.headers.set('Location', '/');
          }
        case '/kullanici_bilgileri.uyap':
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode({'adi': 'Ayşe', 'soyadi': 'Kaya'}));
        default:
          response.statusCode = 404;
      }
      await response.close();
    });
    web = UyapWebService.forTesting(
      portal: Uri.parse('http://${server.address.host}:${server.port}'),
    );
  });

  tearDown(() => server.close(force: true));

  test('a mobile signature on e-Devlet opens a portal session', () async {
    final login = await web.beginEdevlet(EdevletMethod.mobile);
    // Not yet logged in: only the half of a login that waits on e-Devlet.
    expect(web.connected, isFalse);
    expect(login.state, '0');
    expect(login.page.host, 'giris.turkiye.gov.tr');
    expect(login.page.queryParameters, {
      'response_type': 'code',
      'scope': 'Kimlik-Dogrula',
      'redirect_uri': 'https://avukat.uyap.gov.tr/login.uyap',
      'client_id': '27e1dfc0-8536-11e4-b4a9-0800200c9a66',
      'state': '0',
      'loginTypeIndex': '2',
    });

    final before = DateTime.now();
    expect(await web.finishEdevlet(login, 'dogru-kod'), 'Ayşe Kaya');
    expect(web.connected, isTrue);
    final session = web.session.value!;
    expect(session.route, UyapLoginRoute.mobile);
    expect(session.user, 'Ayşe Kaya');
    expect(
      session.expires.difference(before).inMinutes,
      inInclusiveRange(174, 175),
    );
    expect(await web.check(), isTrue);
  });

  test('a code the portal does not take leaves no session', () async {
    final login = await web.beginEdevlet(EdevletMethod.eSignature);
    expect(login.page.queryParameters['loginTypeIndex'], '3');
    await expectLater(
      web.finishEdevlet(login, 'yanlis-kod'),
      throwsA(isA<StateError>()),
    );
    expect(web.connected, isFalse);
    expect(web.session.value, isNull);
  });

  test('a session UYAP has ended is let go of when checked', () async {
    final login = await web.beginEdevlet(EdevletMethod.mobile);
    await web.finishEdevlet(login, 'dogru-kod');
    var heard = 0;
    web.session.addListener(() => heard++);
    alive = false;
    expect(await web.check(), isFalse);
    expect(web.connected, isFalse);
    expect(heard, 1);
  });
}

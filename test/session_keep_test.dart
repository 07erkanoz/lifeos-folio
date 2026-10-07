import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/security/secret_store.dart';
import 'package:evrak_convert/services/uets/uets_api.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// This computer's keystore, in memory.
class _MemorySecrets extends SecretStore {
  final values = <String, Map<String, Object?>>{};
  @override
  Future<bool> write(String name, Map<String, Object?> value) async {
    values[name] = jsonDecode(jsonEncode(value)) as Map<String, Object?>;
    return true;
  }

  @override
  Future<Map<String, Object?>?> read(String name) async => values[name];

  @override
  Future<void> remove(String name) async => values.remove(name);
}

// The web portal's and UETS's sessions outlive Folio's closing until they
// end, kept in the keystore; one its portal no longer holds is dropped.
void main() {
  late HttpServer server;
  var webAlive = true;
  var uetsAlive = true;

  setUp(() async {
    webAlive = true;
    uetsAlive = true;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      await utf8.decoder.bind(r).join();
      final path = r.uri.path;
      var status = 200;
      Object? answer = const {};
      if (path == '/kullanici_bilgileri.uyap') {
        final cookie = r.headers.value('Cookie') ?? '';
        answer = webAlive && cookie.contains('JSESSIONID=good')
            ? {'level': '2', 'adi': 'Deniz'}
            : {'level': '0'};
      } else if (path.startsWith('/v1/auth/_mobil_imza') &&
          r.method == 'POST') {
        status = 201;
        answer = {'transaction_id': 'tx', 'fingerprint': 'AB'};
      } else if (path.startsWith('/v1/auth/_mobil_imza')) {
        answer = {'status': 'ok'};
      } else if (path == '/v1/clients/_authentication') {
        answer = {
          'access_token': 'u' * 40,
          'expire_time':
              DateTime.now()
                  .add(const Duration(minutes: 25))
                  .millisecondsSinceEpoch ~/
              1000,
        };
      } else if (path == '/v1/messages') {
        if (!uetsAlive) {
          status = 401;
          answer = {'code': 602};
        } else {
          answer = [];
        }
      }
      r.response.statusCode = status;
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode(answer));
      await r.response.close();
    });
  });
  tearDown(() => server.close(force: true));

  Uri at(String p) => Uri.parse('http://127.0.0.1:${server.port}$p');

  PortalSync sync(SecretStore secrets, {UyapWebService? web, UetsApi? uets}) =>
      PortalSync(
        web: web ?? UyapWebService.forTesting(portal: at('/')),
        mobile: UyapMobileApi.forTesting(Uri.parse('http://127.0.0.1:9/')),
        uets: uets ?? UetsApi.forTesting(at('/v1/')),
        database: () async => PortalDatabase.memory(),
        secrets: secrets,
      );

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('a UETS session is kept and taken up again after a restart', () async {
    final secrets = _MemorySecrets();
    final first = UetsApi.forTesting(at('/v1/'));
    final s = sync(secrets, uets: first)..start();
    final l = await first.startMobile(
      tckn: '10000000146',
      phone: '5321234567',
      operator: MobileOperator.turkcell,
    );
    await first.finishMobile(l);
    await until(() => secrets.values.containsKey('uets'));
    expect(secrets.values['uets']!['token'], 'u' * 40);
    // Never with the TC number.
    expect(jsonEncode(secrets.values['uets']), isNot(contains('10000000146')));
    s.dispose();

    final next = UetsApi.forTesting(at('/v1/'));
    final again = sync(secrets, uets: next)..start();
    await until(() => next.connected);
    expect(next.connected, isTrue);
    again.dispose();
  });

  test(
    'a UETS session UETS refuses is dropped; an ended one is not tried',
    () async {
      final secrets = _MemorySecrets()
        ..values['uets'] = {
          'token': 'u' * 40,
          'expires': DateTime.now()
              .add(const Duration(minutes: 20))
              .toUtc()
              .toIso8601String(),
        };
      uetsAlive = false;
      final api = UetsApi.forTesting(at('/v1/'));
      final s = sync(secrets, uets: api)..start();
      await until(() => !secrets.values.containsKey('uets'));
      expect(api.connected, isFalse);
      expect(secrets.values.containsKey('uets'), isFalse);
      s.dispose();

      expect(
        await UetsApi.forTesting(at('/v1/')).restoreSession({
          'token': 'u' * 40,
          'expires': DateTime.now()
              .subtract(const Duration(minutes: 1))
              .toUtc()
              .toIso8601String(),
        }),
        isFalse,
      );
    },
  );

  test('a web portal session is taken up again while UYAP holds it, and '
      'dropped when it does not', () async {
    final kept = {
      'cookies': {'JSESSIONID': 'good'},
      'tckn': '',
      'user': 'Deniz',
      'since': DateTime.now()
          .subtract(const Duration(minutes: 30))
          .toUtc()
          .toIso8601String(),
      'route': 'tray',
    };
    final secrets = _MemorySecrets()..values['uyap-web'] = kept;
    final web = UyapWebService.forTesting(portal: at('/'));
    final s = sync(secrets, web: web)..start();
    await until(() => web.connected);
    expect(web.connected, isTrue);
    expect(web.session.value!.user, 'Deniz');
    s.dispose();

    webAlive = false;
    final secrets2 = _MemorySecrets()..values['uyap-web'] = kept;
    final web2 = UyapWebService.forTesting(portal: at('/'));
    final s2 = sync(secrets2, web: web2)..start();
    await until(() => !secrets2.values.containsKey('uyap-web'));
    expect(web2.connected, isFalse);
    expect(secrets2.values.containsKey('uyap-web'), isFalse);
    s2.dispose();
  });

  test('a web session past its three hours is not taken up', () async {
    final web = UyapWebService.forTesting(portal: at('/'));
    expect(
      await web.restoreSession({
        'cookies': {'JSESSIONID': 'good'},
        'user': 'Deniz',
        'since': DateTime.now()
            .subtract(const Duration(hours: 3))
            .toUtc()
            .toIso8601String(),
        'route': 'tray',
      }),
      isFalse,
    );
    expect(web.connected, isFalse);
  });
}

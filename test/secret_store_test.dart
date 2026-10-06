import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/security/secret_store.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('folio-secret-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a token is kept sealed for this Windows user', () async {
    final store = SecretStore(directory: () async => dir);
    expect(await store.write('t', {'access': 'gizli-token'}), isTrue);
    final raw = File('${dir.path}/t.secret').readAsBytesSync();
    expect(utf8.decode(raw, allowMalformed: true), isNot(contains('gizli')));
    expect(await store.read('t'), {'access': 'gizli-token'});
    await store.remove('t');
    expect(await store.read('t'), isNull);
  }, skip: Platform.isWindows ? null : 'DPAPI Windows’ta');

  test(
    'a kept mobile session is taken up again, and ends with logout',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((r) async {
        final path = r.uri.path;
        r.response.headers.contentType = ContentType.json;
        r.response.write(
          jsonEncode(
            path.endsWith('mobile/avukat/user')
                ? {'adi': 'Deniz'}
                : path.endsWith('auth/edevlet')
                ? {'accessToken': 'a', 'refreshToken': 'r'}
                : {},
          ),
        );
        await r.response.close();
      });
      final base = Uri.parse('http://127.0.0.1:${server.port}/services/');
      final store = SecretStore(directory: () async => dir);
      final db = PortalDatabase.memory();
      addTearDown(db.dispose);

      // First run: a login, whose tokens are kept.
      final first = UyapMobileApi.forTesting(base);
      PortalSync(
        web: UyapWebService.forTesting(),
        mobile: first,
        database: () async => db,
        secrets: store,
      ).start();
      await first.login('kod');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await store.read('uyap-mobile'), isNotNull);

      // Next run: taken up again without a login.
      final next = UyapMobileApi.forTesting(base);
      PortalSync(
        web: UyapWebService.forTesting(),
        mobile: next,
        database: () async => db,
        secrets: store,
      ).start();
      for (var i = 0; i < 20 && !next.connected; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(next.connected, isTrue);
      expect(next.session.value?.user, 'Deniz');

      await next.logout();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await store.read('uyap-mobile'), isNull);
    },
    skip: Platform.isWindows ? null : 'DPAPI Windows’ta',
  );
}

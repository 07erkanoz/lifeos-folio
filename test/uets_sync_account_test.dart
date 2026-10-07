import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/security/secret_store.dart';
import 'package:evrak_convert/services/uets/uets_api.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A keystore kept in memory, as a computer with one would.
class _MemorySecrets extends SecretStore {
  final values = <String, Map<String, Object?>>{};
  @override
  Future<bool> write(String name, Map<String, Object?> value) async {
    values[name] = value;
    return true;
  }

  @override
  Future<Map<String, Object?>?> read(String name) async => values[name];

  @override
  Future<void> remove(String name) async => values.remove(name);
}

/// A computer without a keystore: nothing can be kept.
class _NoSecrets extends SecretStore {
  @override
  Future<bool> write(String name, Map<String, Object?> value) async => false;

  @override
  Future<Map<String, Object?>?> read(String name) async => null;
}

// A sync of UETS lists each notice's documents and makes its deadlines;
// Folio keeps one UETS box, and a login to another is refused rather than
// mixed with it.
void main() {
  late HttpServer server;
  late UetsApi uets;
  late PortalDatabase db;
  final asked = <String>[];
  // Whose box the server shows: each box has notices of its own.
  var box = '';

  setUp(() async {
    asked.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final text = await utf8.decoder.bind(r).join();
      if (text.contains('"tcn"')) box = '${(jsonDecode(text) as Map)['tcn']}';
      final path = r.uri.path.replaceFirst('/v1/', '');
      asked.add(path);
      Object? answer = const {};
      var status = 200;
      if (path == 'auth/_mobil_imza' && r.method == 'POST') {
        status = 201;
        answer = {'transaction_id': 'tx', 'fingerprint': 'AB'};
      } else if (path == 'auth/_mobil_imza') {
        answer = {'status': 'ok'};
      } else if (path == 'clients/_authentication') {
        answer = {
          'access_token': 't' * 40,
          'expire_time':
              DateTime.now()
                  .add(const Duration(minutes: 25))
                  .millisecondsSinceEpoch ~/
              1000,
        };
      } else if (path == 'messages') {
        final folder = r.uri.queryParameters['folders_id'];
        if (folder == '4') {
          status = 404;
          answer = {'message': 'yok'};
        } else {
          answer = [
            {
              'id': box == '10000000146' ? 'm1' : 'b-$box',
              'subject': 'Antalya 3. Asliye Hukuk Mahkemesi [2025/412] [x]',
              'inserttime':
                  DateTime.utc(2026, 9, 30, 9).millisecondsSinceEpoch ~/ 1000,
            },
          ];
        }
      } else if (path == 'messages/m1/parts') {
        answer = [
          {'Id': 'p1', 'DosyaAdi': '(1)dosyaBilgileriV1.xml'},
          {'Id': 'p2', 'DosyaAdi': '(2)GerekceliKarar.pdf'},
        ];
      }
      r.response.statusCode = status;
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode(answer));
      await r.response.close();
    });
    uets = UetsApi.forTesting(
      Uri.parse('http://127.0.0.1:${server.port}/v1/'),
      pollEvery: const Duration(milliseconds: 5),
    );
    db = PortalDatabase.memory();
  });
  tearDown(() async {
    db.dispose();
    await server.close(force: true);
  });

  PortalSync sync(SecretStore secrets) => PortalSync(
    web: UyapWebService.forTesting(),
    mobile: UyapMobileApi.forTesting(Uri.parse('http://127.0.0.1:9/')),
    uets: uets,
    database: () async => db,
    secrets: secrets,
  );

  Future<void> login(String tckn) async {
    final l = await uets.startMobile(
      tckn: tckn,
      phone: '5321234567',
      operator: MobileOperator.turkcell,
    );
    await uets.finishMobile(l);
  }

  test(
    'a sync lists the documents and makes the deadlines from them',
    () async {
      final s = sync(_MemorySecrets());
      await login('10000000146');
      await s.syncUets();
      expect(s.state(PortalChannel.uets).problem, isNull);
      expect(db.manifest('m1').state, 'alindi');
      expect(db.manifest('m1').parts.map((p) => p.name), [
        '(1)dosyaBilgileriV1.xml',
        '(2)GerekceliKarar.pdf',
      ]);
      final d = db.deadlines(noticeId: 'm1').single;
      expect(d.record.ruleId, 'hmk345');
      expect(d.record.evidence['parca'], 'p2');
      // Asked once: the next sync does not list them again.
      await s.syncUets();
      expect(asked.where((p) => p == 'messages/m1/parts'), hasLength(1));
      s.dispose();
    },
  );

  test('another UETS box is refused, the kept one is not touched, and the '
      'first box comes back', () async {
    final secrets = _MemorySecrets();
    final s = sync(secrets);
    await login('10000000146');
    await s.syncUets();
    final account = db.meta('uets_account');
    expect(account, startsWith('h:'));
    expect(account, isNot(contains('10000000146')));

    uets.logout();
    await login('20000000082');
    await s.syncUets();
    expect(
      s.state(PortalChannel.uets).problem,
      contains('başka bir UETS hesabının'),
    );
    expect(uets.connected, isFalse);
    expect(db.meta('uets_account'), account);

    // After a restart, with the same keystore: the first box again.
    s.dispose();
    final again = sync(secrets);
    await login('10000000146');
    await again.syncUets();
    expect(again.state(PortalChannel.uets).problem, isNull);
    again.dispose();
  });

  test('a lost key does not lock the lawyer out of their own box', () async {
    final secrets = _MemorySecrets();
    final s = sync(secrets);
    await login('10000000146');
    await s.syncUets();
    final before = db.meta('uets_account');
    // A new keystore: the old key is gone, the digest differs.
    secrets.values.clear();
    uets.logout();
    await login('10000000146');
    await s.syncUets();
    expect(s.state(PortalChannel.uets).problem, isNull);
    expect(db.meta('uets_account'), isNot(before));
    s.dispose();
  });

  test('after a lost key, a first login with another box does not shut the '
      'right one out', () async {
    final secrets = _MemorySecrets();
    final s = sync(secrets);
    await login('10000000146');
    await s.syncUets();
    secrets.values.clear();
    uets.logout();
    await login('20000000082');
    await s.syncUets();
    expect(
      s.state(PortalChannel.uets).problem,
      contains('başka bir UETS hesabının'),
    );
    await login('10000000146');
    await s.syncUets();
    expect(s.state(PortalChannel.uets).problem, isNull);
    // Told again: the other box is refused once more.
    uets.logout();
    await login('20000000082');
    await s.syncUets();
    expect(
      s.state(PortalChannel.uets).problem,
      contains('başka bir UETS hesabının'),
    );
    s.dispose();
  });

  test('without a keystore the box is told by a slow salted digest', () async {
    final s = sync(_NoSecrets());
    await login('10000000146');
    await s.syncUets();
    expect(db.meta('uets_account'), startsWith('p:'));
    expect(db.meta('uets_account_salt'), isNotNull);
    uets.logout();
    await login('20000000082');
    await s.syncUets();
    expect(
      s.state(PortalChannel.uets).problem,
      contains('başka bir UETS hesabının'),
    );
    s.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}

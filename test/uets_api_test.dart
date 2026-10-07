import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/uets/uets_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late UetsApi api;
  final asked = <(String, String, Object?)>[];
  var pendingPolls = 2;
  var total = 120;
  // At most this many a page, whatever is asked: UETS may give fewer.
  var cap = 1000;

  setUp(() async {
    asked.clear();
    pendingPolls = 2;
    total = 120;
    cap = 1000;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final text = await utf8.decoder.bind(r).join();
      final body = text.isEmpty ? null : jsonDecode(text);
      final path = r.uri.path.replaceFirst('/v1/', '');
      asked.add((r.method, '$path?${r.uri.query}', body));
      Object? answer = const {};
      var status = 200;
      final bearer = r.headers.value('Authorization');
      if (path == 'auth/_mobil_imza' && r.method == 'POST') {
        status = 201;
        answer = {'transaction_id': 'tx-1', 'fingerprint': 'AB12'};
      } else if (path == 'auth/_mobil_imza') {
        answer = pendingPolls-- > 0 ? {'status': 'pending'} : {'status': 'ok'};
      } else if (path == 'clients/_authentication') {
        answer = {
          'access_token': 't' * 40,
          'expire_time':
              DateTime.now()
                  .add(const Duration(minutes: 25))
                  .millisecondsSinceEpoch ~/
              1000,
          'login_method': 'mobilimza',
          'clients': [{}, {}],
        };
      } else if (bearer != 'Bearer ${'t' * 40}') {
        status = 401;
        answer = {'status': 401, 'code': 602, 'message': 'Oturum yok'};
      } else if (path == 'messages') {
        final start = int.parse(r.uri.queryParameters['start'] ?? '0');
        final asked = int.parse(r.uri.queryParameters['count']!);
        final count = asked < cap ? asked : cap;
        answer = [
          for (var i = start; i < start + count && i < total; i++)
            {
              'id': 'm$i',
              'subject':
                  'Antalya 3. Asliye Hukuk Mahkemesi [2025/$i] [Gerekçeli Karar]',
              'sender_name': 'Antalya Adliyesi',
              'inserttime': 1790000000 - i * 3600,
              'attributes': {'readtime': i.isEven ? 0 : 1790000100},
            },
        ];
      }
      r.response.statusCode = status;
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode(answer));
      await r.response.close();
    });
    api = UetsApi.forTesting(
      Uri.parse('http://127.0.0.1:${server.port}/v1/'),
      pollEvery: const Duration(milliseconds: 10),
    );
  });
  tearDown(() => server.close(force: true));

  test('the GSM number goes as ten digits', () {
    expect(UetsApi.gsm('0532 123 45 67'), '5321234567');
    expect(UetsApi.gsm('+90 532 123 45 67'), '5321234567');
    expect(UetsApi.gsm('5321234567'), '5321234567');
  });

  test('a mobile-signature login waits for the phone, then opens', () async {
    final login = await api.startMobile(
      tckn: '10000000146',
      phone: '0532 123 45 67',
      operator: MobileOperator.turkcell,
    );
    expect(login.fingerprint, 'AB12');
    expect(asked.first.$3, {
      'tcn': '10000000146',
      'mobile': '5321234567',
      'provider': 'turkcell',
    });
    final s = await api.finishMobile(login);
    expect(api.connected, isTrue);
    expect(s.accounts, 2);
    expect(
      asked.where((a) => a.$1 == 'GET' && a.$2.startsWith('auth/_mobil_imza?')),
      hasLength(3),
    );
  });

  test('a newer login ends the wait of an older one', () async {
    final first = await api.startMobile(
      tckn: '10000000146',
      phone: '5321234567',
      operator: MobileOperator.vodafone,
    );
    pendingPolls = 1000;
    final waiting = api.finishMobile(first);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await api.startMobile(
      tckn: '10000000146',
      phone: '5321234567',
      operator: MobileOperator.vodafone,
    );
    await expectLater(waiting, throwsStateError);
  });

  test('the box comes page by page, newest first', () async {
    final login = await api.startMobile(
      tckn: '10000000146',
      phone: '5321234567',
      operator: MobileOperator.turkcell,
    );
    pendingPolls = 0;
    await api.finishMobile(login);
    final all = await api.allMessages(pageSize: 50);
    expect(all, hasLength(120));
    expect(all.first.read, isNull);
    expect(all[1].read, isNotNull);
    expect(
      all.first.served,
      DateTime(
        all.first.sent!.year,
        all.first.sent!.month,
        all.first.sent!.day + 5,
      ),
    );
  });

  test('a listing says whether it is the whole box', () async {
    final login = await api.startMobile(
      tckn: '10000000146',
      phone: '5321234567',
      operator: MobileOperator.turkcell,
    );
    pendingPolls = 0;
    await api.finishMobile(login);
    final whole = await api.listing(pageSize: 50);
    expect(whole.messages, hasLength(120));
    expect(whole.complete, isTrue);
    // The pages run out before the box does: not taken for the whole.
    final cut = await api.listing(pageSize: 50, maxPages: 2);
    expect(cut.messages, hasLength(100));
    expect(cut.complete, isFalse);
  });

  test('a page shorter than asked is not the end of the box', () async {
    final login = await api.startMobile(
      tckn: '10000000146',
      phone: '5321234567',
      operator: MobileOperator.turkcell,
    );
    pendingPolls = 0;
    await api.finishMobile(login);
    cap = 30;
    final whole = await api.listing();
    expect(whole.messages, hasLength(120));
    expect(whole.complete, isTrue);
  });

  test('an ended session asks for a new login', () async {
    expect(() => api.messages(), throwsStateError);
  });
}

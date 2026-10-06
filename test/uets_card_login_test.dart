import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:evrak_convert/services/uets/uets_api.dart';
import 'package:evrak_convert/services/uets/uets_card_login.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late UetsApi api;
  final posted = <String, Object?>{};
  var polls = 0;

  setUp(() async {
    posted.clear();
    polls = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final text = await utf8.decoder.bind(r).join();
      final body = text.isEmpty ? null : jsonDecode(text) as Map;
      final path = r.uri.path.replaceFirst('/v1/', '');
      Object? answer = const {};
      if (path == 'clients/_authentication' && body?['transactionID'] == null) {
        answer = {'transactionID': 4711};
      } else if (path == 'auth/_eimza' && r.method == 'GET') {
        answer = {
          'data': base64Encode(utf8.encode('imzalanacak')),
          'transactionUUID': 'u-1',
          'signatureType': 'C',
          'displayText': 'UETS girişi',
          'statusCode': 0,
        };
      } else if (path == 'auth/_eimza') {
        posted.addAll(Map<String, Object?>.from(body!));
        answer = {'statusCode': 0};
      } else if (path == 'clients/_authentication') {
        answer = polls++ < 1
            ? {'status': 'pending'}
            : {
                'access_token': 'k' * 40,
                'expire_time':
                    DateTime.now()
                        .add(const Duration(minutes: 25))
                        .millisecondsSinceEpoch ~/
                    1000,
                'login_method': 'eimza',
              };
      }
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

  test('the card signs UETS’s data, attached, and the session opens', () async {
    Uint8List? signedData;
    bool? asAttached;
    final s = await loginWithCard(
      api,
      tckn: '10000000146',
      sign: (data, {required attached}) async {
        signedData = data;
        asAttached = attached;
        return Uint8List.fromList([9, 9, 9]);
      },
    );
    expect(utf8.decode(signedData!), 'imzalanacak');
    expect(asAttached, isTrue);
    expect(posted['signature'], base64Encode([9, 9, 9]));
    expect(posted['transactionUUID'], 'u-1');
    expect(posted['identityNumber'], '10000000146');
    expect(s.method, 'eimza');
    expect(api.connected, isTrue);
  });

  test('a certificate without a TC number is refused before UETS', () async {
    await expectLater(
      loginWithCard(
        api,
        tckn: null,
        sign: (data, {required attached}) async => Uint8List(0),
      ),
      throwsStateError,
    );
  });
}

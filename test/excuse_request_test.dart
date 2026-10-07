import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_hearing.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:flutter_test/flutter_test.dart';

// An excuse goes through the mobile API, with the hearing read afresh from
// that day's list: never with an id kept from before, never to a hearing
// UYAP closed to excuses, never cut short.
void main() {
  late HttpServer server;
  late UyapMobileApi api;
  late PortalSync sync;
  final asked = <String>[];
  final sent = <Map>[];
  var rows = <Map<String, Object?>>[];

  setUp(() async {
    asked.clear();
    sent.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final text = await utf8.decoder.bind(r).join();
      final body = text.isEmpty ? const {} : jsonDecode(text) as Map;
      final path = r.uri.path.replaceFirst('/services/', '');
      asked.add(path);
      Object? answer = const {};
      if (path == 'auth/edevlet') {
        answer = {'accessToken': 'a', 'refreshToken': 'r'};
      } else if (path == 'mobile/avukat/user') {
        answer = {'adi': 'Deniz'};
      } else if (path.startsWith('mobile/avukat/durusmalarim/')) {
        answer = {'listDurusmalar': rows};
      } else if (path == 'mobile/avukat/mazarettalep') {
        sent.add(body);
        answer = {'result': true, 'mesaj': '<b>Talebiniz</b> alınmıştır.'};
      }
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode(answer));
      await r.response.close();
    });
    api = UyapMobileApi.forTesting(
      Uri.parse('http://127.0.0.1:${server.port}/services/'),
    );
    sync = PortalSync(mobile: api, database: () async => PortalDatabase.memory());
    await api.login('kod');
  });
  tearDown(() async {
    sync.dispose();
    await server.close(force: true);
  });

  Map<String, Object?> row({
    String id = 'enc-k1',
    bool open = true,
    String time = '08.10.2026 11:30',
  }) => {
    'kayitId': id,
    'dosyaId': 'fresh-d1',
    'birimId': 'fresh-b1',
    'dosyaNo': '2021/304 - Esas',
    'yerelBirimAd': 'Bakırköy 22. Asliye Ceza Mahkemesi',
    'tarihSaat': time,
    'durusmaTrhStr': time,
    'mazaretButonAktifmi': open,
    'mazaretDurumuAciklama': open ? '' : 'Duruşmaya <i>2 günden az</i> kaldı',
  };

  PortalHearing hearing({String? id}) => PortalHearing.create(
    number: '2021/304',
    court: 'Bakırköy 22. Asliye Ceza Mahkemesi',
    at: DateTime(2026, 10, 8, 11, 30),
    channel: PortalChannel.uyapMobile,
    id: id,
  );

  test('the request carries the fresh row’s own ids', () async {
    rows = [row()];
    final answer = await sync.requestExcuse(
      hearing(id: 'enc-k1'),
      'Aynı saatte başka bir duruşmam var.',
    );
    expect(answer.ok, isTrue);
    expect(answer.message, 'Talebiniz alınmıştır.');
    expect(asked, contains('mobile/avukat/durusmalarim/08.10.2026/08.10.2026'));
    expect(sent.single, {
      'dosyaId': 'fresh-d1',
      'dosyaNo': '2021/304 - Esas',
      'birimId': 'fresh-b1',
      'kayitId': 'enc-k1',
      'durusmaTrhStr': '08.10.2026 11:30',
      'talepMsg': 'Aynı saatte başka bir duruşmam var.',
    });
  });

  test('a hearing known only from the web is found by its case and minute',
      () async {
    rows = [row(time: '08.10.2026 14:00', id: 'other'), row()];
    final answer = await sync.requestExcuse(hearing(), 'Hastalık.');
    expect(answer.ok, isTrue);
    expect(sent.single['kayitId'], 'enc-k1');
  });

  test('a hearing closed to excuses is not asked for', () async {
    rows = [row(open: false)];
    final answer = await sync.requestExcuse(hearing(id: 'enc-k1'), 'Hastalık.');
    expect(answer.ok, isFalse);
    expect(answer.message, contains('2 günden az kaldı'));
    expect(sent, isEmpty);
  });

  test('a hearing gone from the day’s list is not asked for', () async {
    rows = [row(time: '08.10.2026 14:00', id: 'other')];
    final answer = await sync.requestExcuse(hearing(), 'Hastalık.');
    expect(answer.ok, isFalse);
    expect(sent, isEmpty);
  });

  test('a reason past UYAP’s limit is refused, not cut', () async {
    rows = [row()];
    final answer = await sync.requestExcuse(
      hearing(id: 'enc-k1'),
      'x' * (UyapMobileApi.excuseLimit + 1),
    );
    expect(answer.ok, isFalse);
    expect(asked.where((p) => p.contains('durusmalarim')), isEmpty);
    expect(sent, isEmpty);
  });
}

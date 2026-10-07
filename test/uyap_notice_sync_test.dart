import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/portal/uyap_notice.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:flutter_test/flutter_test.dart';

// UYAP Mobil's notifications read page by page, their bodies asked for,
// the first reading telling of nothing, a later one telling of what is
// new, once; read marks go back to UYAP.
void main() {
  late HttpServer server;
  late UyapMobileApi api;
  late PortalSync sync;
  late PortalDatabase db;
  final asked = <String>[];
  var rows = <Map<String, Object?>>[];

  setUp(() async {
    asked.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      await utf8.decoder.bind(r).join();
      final path = r.uri.path.replaceFirst('/services/', '');
      asked.add('${r.method} $path');
      Object? answer = const {};
      if (path == 'auth/edevlet') {
        answer = {'accessToken': 'a', 'refreshToken': 'r'};
      } else if (path == 'mobile/avukat/user') {
        answer = {'adi': 'Deniz'};
      } else if (path == 'mobile/bildirim/bildirimlerim/null') {
        answer = {'bildirimler': rows};
      } else if (path.startsWith('mobile/bildirim/bildirimlerim/')) {
        answer = {'bildirimler': const []};
      } else if (path.startsWith('mobile/bildirim/bildirimmesaj/')) {
        final id = path.split('/').last;
        answer = {
          'mesaj':
              'Antalya 3. Asliye Hukuk Mahkemesi Biriminde Bulunan 2024/318 '
              'sayılı dosyada $id kaydedilmiştir.',
          'dosyaId': 'session-only',
        };
      }
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode(answer));
      await r.response.close();
    });
    api = UyapMobileApi.forTesting(
      Uri.parse('http://127.0.0.1:${server.port}/services/'),
    );
    db = PortalDatabase.memory();
    sync = PortalSync(mobile: api, database: () async => db);
    await api.login('kod');
  });
  tearDown(() async {
    sync.dispose();
    db.dispose();
    await server.close(force: true);
  });

  Map<String, Object?> row(String id, String title, String at) => {
    'bildirimId': id,
    'mesajId': 'msg-$id',
    'baslik': title,
    'gonderilmeTarihi': at,
    'okundumu': false,
  };

  String now(int minutesAgo) {
    final t = DateTime.now().subtract(Duration(minutes: minutesAgo));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
  }

  test('the first reading keeps all and tells of none; the next tells of '
      'the new one once', () async {
    final told = <List<UyapNotice>>[];
    sync.onNewNotices = told.add;
    rows = [row('a', 'Gerekçeli Karar', now(30))];
    await sync.syncNotices(force: true);
    expect(told, isEmpty);
    final kept = db.uyapNoticeRows();
    expect(kept, hasLength(1));
    // The body asked for by the message id, and the case named in it.
    expect(asked, contains('GET mobile/bildirim/bildirimmesaj/msg-a'));
    expect(kept.single.body, contains('2024/318'));
    rows = [
      row('b', 'Bilirkişi Raporu Kaydedilmesi', now(2)),
      row('a', 'Gerekçeli Karar', now(30)),
    ];
    await sync.syncNotices(force: true);
    expect(told, hasLength(1));
    expect(told.single.single.title, 'Bilirkişi Raporu Kaydedilmesi');
    expect(told.single.single.body, contains('msg-b'));
    // Asked again: nothing new to tell.
    await sync.syncNotices(force: true);
    expect(told, hasLength(1));
    // Within a minute and not forced: UYAP is not asked again.
    asked.clear();
    await sync.syncNotices();
    expect(asked, isEmpty);
  });

  test('read is Folio’s own: UYAP is not told', () async {
    rows = [row('0Npv+xBHg==', 'Gerekçeli Karar', now(5))];
    await sync.syncNotices(force: true);
    final notice = db.uyapNotices().single;
    expect(notice.read, isFalse);
    await sync.markNotices([notice], read: true);
    expect(db.uyapNotices().single.read, isTrue);
    expect(asked.where((a) => a.contains('okundu')), isEmpty);
  });
}

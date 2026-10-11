import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _aile = 'Manavgat 2. Aile Mahkemesi';
const _ceza = 'Manavgat 1. Asliye Ceza Mahkemesi';
const _savcilik = 'Manavgat Cumhuriyet Başsavcılığı';
const _yargitay = 'Yargıtay 3. Hukuk Dairesi';
const _mobileCourt = 'Antalya 3. Asliye Hukuk Mahkemesi';

/// The web portal as a lawyer's login shows it: a family court, a criminal
/// court, a prosecutor's office and a chamber of the Court of Cassation.
class _Web extends UyapWebService {
  _Web() : super.forTesting();

  final asked = <String>[];

  @override
  bool get connected => true;

  @override
  Future<List<UyapOption>> courtTypes(String jurisdiction) async {
    asked.add('types $jurisdiction');
    return switch (jurisdiction) {
      '1' => const [UyapOption('HUKUK', '1')],
      '0' => const [UyapOption('CEZA', '0')],
      _ => const [],
    };
  }

  @override
  Future<List<UyapOption>> courts(
    String jurisdiction,
    String courtType, {
    bool closed = false,
  }) async {
    asked.add('courts $jurisdiction $courtType $closed');
    if (closed) return const [];
    return switch (courtType) {
      'HUKUK' => const [UyapOption('w1', _aile)],
      'CEZA' => const [UyapOption('c1', _ceza), UyapOption('s1', _savcilik)],
      _ => const [],
    };
  }

  @override
  Future<List<UyapCase>> cases({
    required String jurisdiction,
    required String courtType,
    required UyapOption court,
    int? year,
    int? number,
    bool closed = false,
    int pageNumber = 1,
  }) async {
    asked.add('cases ${court.id}');
    return [UyapCase('id-${court.id}', '2025/80', court.id, court.label)];
  }

  @override
  Future<List<UyapOption>> chambers(String jurisdiction) async {
    asked.add('chambers $jurisdiction');
    return jurisdiction == 'yargitay'
        ? const [UyapOption('y3', '3. Hukuk Dairesi')]
        : const [];
  }

  @override
  Future<List<UyapCase>> chamberCases(
    String jurisdiction,
    UyapOption chamber,
  ) async {
    asked.add('chamber cases ${chamber.id}');
    return const [UyapCase('id-y3', '2025/9', 'y3', _yargitay)];
  }

  @override
  Future<List<Map<String, Object?>>> hearingRows(
    DateTime from,
    DateTime to,
  ) async => const [];
}

void main() {
  late PortalDatabase db;
  setUp(() => db = PortalDatabase.memory());
  tearDown(() => db.dispose());

  test('with the web portal alone the whole portfolio comes from it, each '
      'case with its place on the web, the prosecutors\' and the Court of '
      'Cassation\'s with their own kind', () async {
    final web = _Web();
    final result = await syncWebPortfolio(web, db);
    expect(result.complete, isTrue);
    final cases = db.cases();
    expect(cases.keys, {
      caseKey('2025/80', _aile),
      caseKey('2025/80', _ceza),
      caseKey('2025/80', _savcilik),
      caseKey('2025/9', _yargitay),
    });
    final aile = cases[caseKey('2025/80', _aile)]!;
    expect(aile.ids[PortalChannel.uyapWeb], 'id-w1');
    expect(aile.details!.value, containsPair('yargiTuru', '1'));
    expect(aile.details!.value, containsPair('yargiBirimi', 'HUKUK'));
    expect(aile.details!.value, containsPair('birimId', 'w1'));
    expect(cases[caseKey('2025/80', _savcilik)]!.family, CaseFamily.prosecutor);
    expect(cases[caseKey('2025/9', _yargitay)]!.family, CaseFamily.yargitay);
  });

  test('beside UYAP Mobil the web reads only what it alone has: the '
      'prosecutors\' offices and the Court of Cassation', () async {
    final web = _Web();
    await syncWebPortfolio(web, db, webOnly: true);
    expect(db.cases().keys, {
      caseKey('2025/80', _savcilik),
      caseKey('2025/9', _yargitay),
    });
    expect(web.asked, contains('cases s1'));
    expect(web.asked, isNot(contains('cases c1')));
    expect(web.asked, isNot(contains('cases w1')));
    expect(web.asked, isNot(contains('types 1')));
    expect(web.asked, isNot(contains('chambers danistay')));
  });

  test('with only the web portal connected, Senkronize et reads the '
      'portfolio from it and never asks for UYAP Mobil', () async {
    final web = _Web();
    final sync = PortalSync(
      web: web,
      mobile: UyapMobileApi.forTesting(Uri.parse('http://127.0.0.1:9/')),
      database: () async => db,
    );
    addTearDown(sync.dispose);
    expect(sync.portfolioChannel, PortalChannel.uyapWeb);
    await sync.syncPortfolio(full: true);
    expect(web.asked, contains('cases w1'));
    expect(db.cases(), hasLength(4));
    expect(sync.state(PortalChannel.uyapWeb).problem, isNull);
  });

  group('with both connected', () {
    late HttpServer server;
    late UyapMobileApi mobile;
    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        final path = r.uri.path.replaceFirst('/services/', '');
        Object? answer = const {};
        if (path == 'auth/edevlet') {
          answer = {'accessToken': 'a', 'refreshToken': 'r'};
        } else if (path == 'mobile/avukat/user') {
          answer = {'adi': 'Deniz'};
        } else if (path == 'mobile/ortak/yargibirimleri/1') {
          answer = {
            'yargiBirimleri': [
              {'tablo': 'AYM', 'kod': '1'},
            ],
          };
        } else if (path.startsWith('mobile/ortak/yargibirimleri/')) {
          answer = {'yargiBirimleri': []};
        } else if (path == 'mobile/avukat/mahkeme') {
          answer = {
            'birimListesi': [
              {'birimId': 'enc-1', 'birimAdi': _mobileCourt},
            ],
          };
        } else if (path == 'mobile/avukat/dosya') {
          answer = {
            'dosyaList': [
              {
                'dosyaId': 'o1',
                'dosyaNo': '2025/412',
                'birimAdi': _mobileCourt,
              },
            ],
          };
        } else if (path == 'mobile/avukat/danistaydaireleri') {
          answer = {'danistayDairesi': []};
        }
        await utf8.decoder.bind(r).join();
        r.response.headers.contentType = ContentType.json;
        r.response.write(jsonEncode(answer));
        await r.response.close();
      });
      mobile = UyapMobileApi.forTesting(
        Uri.parse('http://127.0.0.1:${server.port}/services/'),
      );
      await mobile.login('kod');
    });
    tearDown(() => server.close(force: true));

    test('UYAP Mobil fills the courts\' cases and the web adds the '
        'prosecutors\' and the Court of Cassation\'s', () async {
      final web = _Web();
      final sync = PortalSync(
        web: web,
        mobile: mobile,
        database: () async => db,
      );
      addTearDown(sync.dispose);
      expect(sync.portfolioChannel, PortalChannel.uyapMobile);
      await sync.syncPortfolio(full: true);
      expect(db.cases().keys, {
        caseKey('2025/412', _mobileCourt),
        caseKey('2025/80', _savcilik),
        caseKey('2025/9', _yargitay),
      });
      // The courts the mobile API lists are not read on the web again.
      expect(web.asked, isNot(contains('cases w1')));
      expect(web.asked, isNot(contains('cases c1')));
    });
  });
}

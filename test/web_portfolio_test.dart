import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/sync/uyap_own_sync.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _aile = 'Manavgat 2. Aile Mahkemesi';
const _ceza = 'Manavgat 1. Asliye Ceza Mahkemesi';
const _savcilik = 'Manavgat Cumhuriyet Başsavcılığı';
const _yargitay = 'Yargıtay 3. Hukuk Dairesi';
const _mobileCourt = 'Antalya 3. Asliye Hukuk Mahkemesi';

/// The web portal as a lawyer's login shows it: a family court, a criminal
/// court, a prosecutor's office in Antalya (one open investigation, one
/// closed) and two chambers of the Court of Cassation.
class _Web extends UyapWebService {
  _Web({this.fullPages = false, this.brokenChamber = false})
    : super.forTesting();

  /// The family court answering full pages without end.
  final bool fullPages;

  /// The first chamber failing.
  final bool brokenChamber;

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
      'CEZA' => const [UyapOption('c1', _ceza)],
      _ => const [],
    };
  }

  @override
  Future<UyapCasePage> casePage({
    required String jurisdiction,
    required String courtType,
    required UyapOption court,
    int? year,
    int? number,
    bool closed = false,
    int pageNumber = 1,
  }) async {
    asked.add('cases ${court.id} $pageNumber');
    final one = UyapCase('id-${court.id}', '2025/80', court.id, court.label);
    if (fullPages && court.id == 'w1') {
      return UyapCasePage([one], UyapWebService.pageSize);
    }
    return UyapCasePage([one], 1);
  }

  @override
  Future<List<UyapOption>> provinces() async {
    asked.add('provinces');
    return const [UyapOption('7', 'ANTALYA')];
  }

  @override
  Future<List<UyapOption>> prosecutorOffices(String province) async {
    asked.add('offices $province');
    return const [UyapOption('s1', _savcilik)];
  }

  @override
  Future<UyapCasePage> prosecutorCases(
    UyapOption office, {
    bool closed = false,
    int pageNumber = 1,
  }) async {
    asked.add('investigations ${office.id} $closed');
    return UyapCasePage([
      closed
          ? UyapCase('id-s1k', '2025/6426', office.id, office.label)
          : UyapCase('id-s1', '2026/12', office.id, office.label),
    ], 1);
  }

  @override
  Future<List<UyapOption>> chambers(String jurisdiction) async {
    asked.add('chambers $jurisdiction');
    return jurisdiction == 'yargitay'
        ? const [
            UyapOption('y2', '2. Hukuk Dairesi'),
            UyapOption('y3', '3. Hukuk Dairesi'),
          ]
        : const [];
  }

  @override
  Future<List<UyapCase>> chamberCases(
    String jurisdiction,
    UyapOption chamber,
  ) async {
    asked.add('chamber cases ${chamber.id}');
    if (brokenChamber && chamber.id == 'y2') throw StateError('UYAP');
    return chamber.id == 'y3'
        ? const [UyapCase('id-y3', '2025/9', 'y3', _yargitay)]
        : const [];
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
      caseKey('2026/12', _savcilik),
      caseKey('2025/6426', _savcilik),
      caseKey('2025/9', _yargitay),
    });
    // Closed investigations are most of them: asked always.
    expect(web.asked, contains('investigations s1 true'));
    // Satış and arabuluculuk are asked of the web too.
    expect(web.asked, containsAll(['types 11', 'types 13']));
    final aile = cases[caseKey('2025/80', _aile)]!;
    expect(aile.ids[PortalChannel.uyapWeb], 'id-w1');
    expect(aile.details!.value, containsPair('yargiTuru', '1'));
    expect(aile.details!.value, containsPair('yargiBirimi', 'HUKUK'));
    expect(aile.details!.value, containsPair('birimId', 'w1'));
    expect(cases[caseKey('2026/12', _savcilik)]!.family, CaseFamily.prosecutor);
    expect(cases[caseKey('2025/9', _yargitay)]!.family, CaseFamily.yargitay);
  });

  test('beside UYAP Mobil the web reads only what it alone has: the '
      'prosecutors\' offices and the Court of Cassation', () async {
    final web = _Web();
    await syncWebPortfolio(web, db, webOnly: true);
    expect(db.cases().keys, {
      caseKey('2026/12', _savcilik),
      caseKey('2025/6426', _savcilik),
      caseKey('2025/9', _yargitay),
    });
    expect(web.asked.where((a) => a.startsWith('cases ')), isEmpty);
    expect(web.asked, isNot(contains('types 1')));
    expect(web.asked, isNot(contains('types 0')));
    expect(web.asked, containsAll(['types 11', 'types 13']));
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
    expect(web.asked, contains('cases w1 1'));
    expect(db.cases(), hasLength(5));
    expect(sync.state(PortalChannel.uyapWeb).problem, isNull);
  });

  test('the prosecutors\' offices are looked for in every province the '
      'first time, and then only where a case was found', () async {
    final web = _Web();
    await syncWebPortfolio(web, db);
    expect(web.asked, contains('provinces'));
    web.asked.clear();
    await syncWebPortfolio(web, db);
    expect(web.asked, isNot(contains('provinces')));
    expect(web.asked, contains('investigations s1 false'));
    // A new case may be anywhere: every province again.
    web.asked.clear();
    await syncWebPortfolio(web, db, everyProvince: true);
    expect(web.asked, contains('provinces'));
  });

  test(
    'a list longer than forty pages is said to be incomplete, not cut '
    'short in silence; a chamber that fails leaves the others read',
    () async {
      final web = _Web(fullPages: true, brokenChamber: true);
      final result = await syncWebPortfolio(web, db);
      expect(result.complete, isFalse);
      expect(web.asked, contains('cases w1 40'));
      expect(web.asked, isNot(contains('cases w1 41')));
      expect(db.cases().keys, contains(caseKey('2025/9', _yargitay)));
    },
  );

  test('the open cases are enriched from the web of themselves only while '
      'Folio reads UYAP of itself, and once a day', () async {
    final sync = PortalSync(
      web: _Web(),
      mobile: UyapMobileApi.forTesting(Uri.parse('http://127.0.0.1:9/')),
      database: () async => db,
    );
    addTearDown(sync.dispose);
    await sync.enrichOnWeb();
    expect(db.meta(PortalSync.enrichedKey), isNull, reason: 'off');
    sync.autoFetch = true;
    await sync.enrichOnWeb();
    if (PortalSync.night(DateTime.now())) {
      expect(db.meta(PortalSync.enrichedKey), isNull, reason: 'at night');
      return;
    }
    final first = db.meta(PortalSync.enrichedKey);
    expect(first, isNotNull);
    await sync.enrichOnWeb();
    expect(db.meta(PortalSync.enrichedKey), first, reason: 'once a day');
  });

  test('what one own device read of the web goes whole to another: the '
      'prosecutors\' and the Court of Cassation\'s cases with their place, '
      'and the times, so that the other asks UYAP nothing again', () async {
    final root = await Directory.systemTemp.createTemp('folio-uyap-own-');
    addTearDown(() => root.delete(recursive: true));
    final other = PortalDatabase.memory();
    addTearDown(other.dispose);
    final web = _Web();
    await syncWebPortfolio(web, db);
    db.setMeta('portfolio_at', DateTime.now().toIso8601String());
    db.setMeta('portfolio_web_only_at', DateTime.now().toIso8601String());
    final storeA = UyapCaseStore(directory: Directory('${root.path}/a'));
    final storeB = UyapCaseStore(directory: Directory('${root.path}/b'));
    final a = UyapOwnSync(
      database: () async => db,
      store: storeA,
      ask: (_, _) async => null,
    );
    final b = UyapOwnSync(
      database: () async => other,
      store: storeB,
      ask: (_, body) => a.answer(body),
    );
    await b.merge(await a.summary('masaustu'));
    expect(other.cases().keys, db.cases().keys.toSet());
    final kept = other.cases()[caseKey('2025/6426', _savcilik)]!;
    expect(kept.family, CaseFamily.prosecutor);
    expect(kept.details!.value, containsPair('birimId', 's1'));
    expect(kept.details!.value, containsPair('yargiTuru', '3'));
    expect(other.meta('portfolio_web_only_at'), isNotNull);
    expect(other.meta('web_prosecutor_full_at'), isNotNull);
    // The other device knows the office from the cases it took in: it does
    // not look in every province again.
    final again = _Web();
    await syncWebPortfolio(again, other, webOnly: true);
    expect(again.asked, isNot(contains('provinces')));
    expect(again.asked, contains('investigations s1 true'));
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
        caseKey('2026/12', _savcilik),
        caseKey('2025/6426', _savcilik),
        caseKey('2025/9', _yargitay),
      });
      // The courts the mobile API lists are not read on the web again.
      expect(web.asked.where((a) => a.startsWith('cases ')), isEmpty);
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/portal/case_sections.dart';
import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/sync/uyap_own_sync.dart';
import 'package:evrak_convert/services/uyap/uyap_case_links.dart';
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
    // A whole kind of unit asked: its one court.
    court = court.id.isNotEmpty
        ? court
        : courtType == 'HUKUK'
        ? const UyapOption('w1', _aile)
        : const UyapOption('c1', _ceza);
    asked.add('cases ${court.id} $pageNumber');
    final one = UyapCase('id-${court.id}', '2025/80', court.id, court.label);
    if (fullPages && court.id == 'w1') {
      return UyapCasePage([
        UyapCase('id-w1-$pageNumber', '2025/$pageNumber', 'w1', court.label),
      ], UyapWebService.pageSize);
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

  // A case of itself it does not open: never the real portal from a test.
  @override
  Future<UyapCasePermissions> permissions(UyapCase target) async =>
      throw StateError('UYAP');

  @override
  Future<UyapCaseDetails> caseDetails(UyapCase target) async =>
      throw StateError('UYAP');

  @override
  Future<List<UyapParty>> parties(UyapCase target) async =>
      throw StateError('UYAP');
}

/// A portal that answers the same full page again.
class _RepeatingWeb extends _Web {
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
    // A whole kind of unit asked: its one court.
    court = court.id.isNotEmpty
        ? court
        : courtType == 'HUKUK'
        ? const UyapOption('w1', _aile)
        : const UyapOption('c1', _ceza);
    asked.add('cases ${court.id} $pageNumber');
    return UyapCasePage([
      UyapCase('id-${court.id}', '2025/80', court.id, court.label),
    ], UyapWebService.pageSize);
  }
}

void main() {
  late PortalDatabase db;
  setUp(() => db = PortalDatabase.memory());
  tearDown(() => db.dispose());

  test('with the web portal alone the whole portfolio comes from it, each '
      'case with its place on the web, the prosecutors\' and the Court of '
      'Cassation\'s with their own kind', () async {
    final web = _Web();
    final result = await syncWebPortfolio(web, db, includeClosed: true);
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

  test('the courts\' cases come first, hukuk before the other courts are '
      'even listed, and the provinces\' hundred questions last', () async {
    final web = _Web();
    final seen = <int>[];
    await syncWebPortfolio(
      web,
      db,
      onChanged: () => seen.add(web.asked.length),
    );
    int at(String what) => web.asked.indexOf(what);
    expect(at('cases w1 1'), lessThan(at('types 0')));
    expect(at('cases c1 1'), lessThan(at('provinces')));
    expect(at('chamber cases y3'), lessThan(at('provinces')));
    // The family court's case was in the database when it was read.
    expect(seen.first, at('cases w1 1') + 1);
  });

  test('the closed investigations are read only when the lawyer asked for '
      'the closed cases', () async {
    final web = _Web();
    await syncWebPortfolio(web, db);
    expect(web.asked, contains('investigations s1 false'));
    expect(web.asked, isNot(contains('investigations s1 true')));
    expect(db.cases().keys, isNot(contains(caseKey('2025/6426', _savcilik))));
  });

  test(
    'a whole kind of unit is one list: no court is asked for its own',
    () async {
      final web = _Web();
      await syncWebPortfolio(web, db);
      expect(web.asked.where((a) => a.startsWith('courts ')), isEmpty);
      expect(db.cases().keys, contains(caseKey('2025/80', _aile)));
    },
  );

  test('beside UYAP Mobil the web reads only what it alone has: the '
      'prosecutors\' offices and the Court of Cassation', () async {
    final web = _Web();
    await syncWebPortfolio(web, db, webOnly: true, includeClosed: true);
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
    // The closed ones too, as the lawyer asks for them once.
    await sync.scanClosed();
    expect(web.asked, contains('cases w1 1'));
    expect(db.cases(), hasLength(5));
    // Read whole, the list alone: no case is opened after it.
    expect(db.meta('portfolio_at'), isNotNull);
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
    expect(
      db.meta(PortalSync.enrichedKey),
      isNull,
      reason: 'no case yet: not done',
    );
    await syncWebPortfolio(_Web(), db);
    db.setMeta(
      '${PortalSync.enrichedKey}_try',
      DateTime(2000).toIso8601String(),
    );
    await sync.enrichOnWeb();
    if (PortalSync.night(DateTime.now())) {
      expect(db.meta(PortalSync.enrichedKey), isNull, reason: 'at night');
      return;
    }
    // No case filled from the web yet: nothing is read of itself (the
    // lawyer's completion fills them), and the day is done.
    expect(db.meta(PortalSync.enrichedKey), isNotNull, reason: 'none due');
    // A case the web read a week ago, which does not answer here (no
    // portal answers the panel): tried, and not counted done, so it is
    // tried again in two hours.
    db.setMeta(PortalSync.enrichedKey, '');
    db.saveSections(db.cases().keys.first, PortalChannel.uyapWeb, const [
      SectionOutcome(CaseSection.money, SectionResult.read),
    ], at: DateTime.now().subtract(const Duration(days: 8)));
    db.setMeta(
      '${PortalSync.enrichedKey}_try',
      DateTime(2000).toIso8601String(),
    );
    await sync.enrichOnWeb();
    final tried = db.meta('${PortalSync.enrichedKey}_try');
    expect(tried, isNot(DateTime(2000).toIso8601String()));
    expect(db.meta(PortalSync.enrichedKey), isEmpty, reason: 'not done');
    await sync.enrichOnWeb();
    expect(
      db.meta('${PortalSync.enrichedKey}_try'),
      tried,
      reason: 'not again within two hours',
    );
    // Done today: not begun again, whatever was tried.
    db.setMeta(PortalSync.enrichedKey, DateTime.now().toIso8601String());
    db.setMeta(
      '${PortalSync.enrichedKey}_try',
      DateTime(2000).toIso8601String(),
    );
    await sync.enrichOnWeb();
    expect(
      db.meta('${PortalSync.enrichedKey}_try'),
      DateTime(2000).toIso8601String(),
      reason: 'once a day',
    );
  });

  test('what one own device read of the web goes whole to another: the '
      'prosecutors\' and the Court of Cassation\'s cases with their place, '
      'and the times, so that the other asks UYAP nothing again', () async {
    final root = await Directory.systemTemp.createTemp('folio-uyap-own-');
    addTearDown(() => root.delete(recursive: true));
    final other = PortalDatabase.memory();
    addTearDown(other.dispose);
    final web = _Web();
    await syncWebPortfolio(web, db, includeClosed: true);
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
    await syncWebPortfolio(again, other, webOnly: true, includeClosed: true);
    expect(again.asked, isNot(contains('provinces')));
    expect(again.asked, contains('investigations s1 true'));
  });

  test('another own device\'s case counts read by the web here only where '
      'it says the web read it whole: money kept from before is no web '
      'reading', () async {
    final root = await Directory.systemTemp.createTemp('folio-uyap-bolum-');
    addTearDown(() => root.delete(recursive: true));
    final other = PortalDatabase.memory();
    addTearDown(other.dispose);
    final storeA = UyapCaseStore(directory: Directory('${root.path}/a'));
    final storeB = UyapCaseStore(directory: Directory('${root.path}/b'));
    const court = 'Manavgat 1. İcra Dairesi';
    final key = caseKey('2025/3311', court);
    Future<void> read(double collected, DateTime at) => storeA.keep(
      target: const UyapCase('x', '2025/3311', 'i7', court),
      details: const UyapCaseDetails(),
      parties: const [UyapParty('A', 'Alacaklı', '', '')],
      documents: const UyapCaseDocuments([]),
      money: UyapCaseMoney(collected: collected),
      now: at,
    );
    // Read by UYAP Mobil there, its money kept from an older web reading.
    await read(10, DateTime(2026, 10, 11, 9));
    db.saveSections(key, PortalChannel.uyapMobile, const [
      SectionOutcome(CaseSection.parties, SectionResult.read),
    ], at: DateTime(2026, 10, 11, 9));
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
    expect(other.meta(PortalSync.webCheckedKey(key)), isNull);
    expect(
      other.sections(key).single.channel,
      PortalChannel.uyapMobile,
      reason: 'what it said came',
    );
    // Then read whole by the web there: counted here too.
    final at = DateTime(2026, 10, 12, 9);
    // The web brings this year's collections.
    await read(25, at);
    db.saveSections(key, PortalChannel.uyapWeb, [
      for (final s in CaseSection.values) SectionOutcome(s, SectionResult.read),
    ], at: at);
    await b.merge(await a.summary('masaustu'));
    expect(other.meta(PortalSync.webCheckedKey(key)), at.toIso8601String());
    // Read again there, nothing changed in the case: its record is the
    // same, its sections newer, and they come all the same.
    final later = DateTime(2026, 10, 13, 9);
    await read(25, later);
    db.saveSections(key, PortalChannel.uyapWeb, [
      for (final s in CaseSection.values) SectionOutcome(s, SectionResult.read),
    ], at: later);
    await b.merge(await a.summary('masaustu'));
    expect(
      other
          .sections(key)
          .where((s) => s.channel == PortalChannel.uyapWeb)
          .map((s) => s.succeeded),
      everyElement(later),
    );
    expect(other.meta(PortalSync.webCheckedKey(key)), later.toIso8601String());
  });

  test('a case read later on another own device wins there though its '
      'record did not change, data and sections together; asking stops once '
      'alike', () async {
    final root = await Directory.systemTemp.createTemp('folio-uyap-surum-');
    addTearDown(() => root.delete(recursive: true));
    final other = PortalDatabase.memory();
    addTearDown(other.dispose);
    final storeA = UyapCaseStore(directory: Directory('${root.path}/a'));
    final storeB = UyapCaseStore(directory: Directory('${root.path}/b'));
    const court = 'Manavgat 1. İcra Dairesi';
    final key = caseKey('2025/3311', court);
    Future<void> read(UyapCaseStore store, double collected, DateTime at) =>
        store.keep(
          target: const UyapCase('x', '2025/3311', 'i7', court),
          details: const UyapCaseDetails(),
          parties: const [UyapParty('A', 'Alacaklı', '', '')],
          documents: const UyapCaseDocuments([]),
          money: UyapCaseMoney(collected: collected),
          now: at,
        );
    // A read 100 on day 10, and again on day 13: the same, its record
    // still says day 10; B read 200 on day 12.
    await read(storeA, 100, DateTime(2026, 10, 10, 9));
    db.saveSections(key, PortalChannel.uyapWeb, const [
      SectionOutcome(CaseSection.money, SectionResult.read),
    ], at: DateTime(2026, 10, 13, 9));
    await read(storeB, 200, DateTime(2026, 10, 12, 9));
    other.saveSections(key, PortalChannel.uyapWeb, const [
      SectionOutcome(CaseSection.money, SectionResult.read),
    ], at: DateTime(2026, 10, 12, 9));
    var asks = 0;
    final a = UyapOwnSync(
      database: () async => db,
      store: storeA,
      ask: (_, _) async => null,
    );
    final b = UyapOwnSync(
      database: () async => other,
      store: storeB,
      ask: (_, body) {
        if (body['parca'] == 'kayitlar') asks++;
        return a.answer(body);
      },
    );
    await b.merge(await a.summary('masaustu'));
    final kept = (await storeB.load(court, '2025/3311'))!;
    expect(kept.money!.collected, 100, reason: 'read later there');
    expect(other.sections(key).single.succeeded, DateTime(2026, 10, 13, 9));
    // Alike now: asked no more.
    final before = asks;
    await b.merge(await a.summary('masaustu'));
    expect(asks, before);
    // A failed try there since does not make it asked again and again.
    db.saveSections(key, PortalChannel.uyapWeb, const [
      SectionOutcome(CaseSection.money, SectionResult.failed),
    ], at: DateTime(2026, 10, 14, 9));
    await b.merge(await a.summary('masaustu'));
    await b.merge(await a.summary('masaustu'));
    expect(asks, before);
  });

  test('a newer reading by UYAP Mobil on another own device keeps what '
      'only the web gave here: the money and the case\'s place', () async {
    final root = await Directory.systemTemp.createTemp('folio-uyap-kayit-');
    addTearDown(() => root.delete(recursive: true));
    final store = UyapCaseStore(directory: Directory(root.path));
    const place = UyapCaseLink(
      jurisdiction: '2',
      courtType: 'ICRA',
      courtId: 'i7',
      court: 'Manavgat 1. İcra Dairesi',
      number: '2025/3311',
    );
    final fromWeb = UyapCaseRecord(
      court: place.court,
      number: place.number,
      fetchedAt: DateTime(2026, 10, 10, 9),
      link: place,
      money: const UyapCaseMoney(collected: 1250.5, remaining: 800),
    );
    expect(await store.adoptChecked(fromWeb.toJson()), AdoptResult.kept);
    final fromMobile = UyapCaseRecord(
      court: place.court,
      number: place.number,
      fetchedAt: DateTime(2026, 10, 11, 9),
    );
    expect(await store.adoptChecked(fromMobile.toJson()), AdoptResult.kept);
    final kept = (await store.load(place.court, place.number))!;
    expect(kept.fetchedAt, DateTime(2026, 10, 11, 9));
    expect(kept.money?.collected, 1250.5);
    expect(kept.link?.courtId, 'i7');
    // An older one changes nothing.
    expect(await store.adoptChecked(fromWeb.toJson()), AdoptResult.older);
    expect(await store.adoptChecked({'esas': 'bozuk'}), AdoptResult.failed);
  });

  test('a list whose page comes again is said to be incomplete', () async {
    final web = _RepeatingWeb();
    final result = await syncWebPortfolio(web, db);
    expect(result.complete, isFalse);
    expect(web.asked, contains('cases w1 2'));
    expect(web.asked, isNot(contains('cases w1 3')));
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
      await sync.scanClosed();
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

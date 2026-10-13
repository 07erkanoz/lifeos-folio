import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:flutter_test/flutter_test.dart';

const _komisyon = 'Ankara Tazminat Komisyonu';
const _savcilik = 'Manavgat Cumhuriyet Başsavcılığı';

/// UYAP Mobil as measured live (14 Ekim 2026): a Tazminat Komisyonu case
/// under kind 26, and three investigations at Manavgat's office.
class _Mobile extends UyapMobileApi {
  _Mobile() : super.forTesting(Uri.parse('http://127.0.0.1:9/'));

  final asked = <String>[];

  @override
  bool get connected => true;

  @override
  Future<List<Map<String, Object?>>> unitTypes(int type) async {
    asked.add('types $type');
    return type == 26
        ? [
            {'tablo': 'TAZMINAT'},
          ]
        : const [];
  }

  @override
  Future<List<Map<String, Object?>>> courts(
    int type,
    String unitKind, {
    required bool closed,
  }) async => closed
      ? const []
      : [
          {'birimId': 'k1', 'birimAdi': _komisyon},
        ];

  @override
  Future<List<Map<String, Object?>>> cases(
    int type,
    String unitKind,
    String court, {
    required bool closed,
  }) async => [
    {'dosyaId': 'k-1', 'dosyaNo': '2025/5984', 'birimAdi': _komisyon},
  ];

  @override
  Future<List<Map<String, Object?>>> danistayChambers() async => const [];

  @override
  Future<List<Map<String, Object?>>> provinces() async {
    asked.add('provinces');
    return [
      {'il': '7', 'ad': 'ANTALYA'},
      {'il': '6', 'ad': 'ANKARA'},
    ];
  }

  @override
  Future<List<Map<String, Object?>>> prosecutorOffices(String code) async {
    asked.add('offices $code');
    return code == '7'
        ? [
            {'birimId': 's7', 'birimAdi': _savcilik},
            {'birimId': 's8', 'birimAdi': 'Alanya Cumhuriyet Başsavcılığı'},
          ]
        : const [];
  }

  @override
  Future<List<Map<String, Object?>>> prosecutorCases(
    String office, {
    required bool closed,
  }) async {
    asked.add('investigations $office $closed');
    return office == 's7' && !closed
        ? [
            for (final n in ['2026/12', '2025/6426', '2025/7001'])
              {'dosyaId': 'i$n', 'dosyaNo': n, 'birimAdi': _savcilik},
          ]
        : const [];
  }
}

void main() {
  late PortalDatabase db;
  setUp(() => db = PortalDatabase.memory());
  tearDown(() => db.dispose());

  test('UYAP Mobil is asked the kinds the live test found cases under, '
      'the Tazminat Komisyonu\'s among them, and not the two that repeat '
      'others', () async {
    final mobile = _Mobile();
    final result = await syncMobilePortfolio(mobile, db);
    expect(result.complete, isTrue);
    for (final type in [1, 0, 2, 6, 26, 11, 25]) {
      expect(mobile.asked, contains('types $type'));
    }
    expect(mobile.asked, isNot(contains('types 12')));
    expect(mobile.asked, isNot(contains('types 13')));
    expect(db.cases().keys, contains(caseKey('2025/5984', _komisyon)));
  });

  test('the prosecutors\' offices come from UYAP Mobil: every province the '
      'first time, then only the office a case was found at; the closed '
      'ones only when asked', () async {
    final mobile = _Mobile();
    await syncMobilePortfolio(mobile, db);
    final kept = db.caseOf(caseKey('2026/12', _savcilik))!;
    expect(kept.family, CaseFamily.prosecutor);
    // No unit code: the web finds the office by its own list.
    expect(kept.details?.value['yargiTuru'], isNull);
    expect(mobile.asked, containsAll(['provinces', 'offices 7', 'offices 6']));
    expect(mobile.asked, contains('investigations s8 false'));
    expect(mobile.asked, isNot(contains('investigations s7 true')));

    mobile.asked.clear();
    await syncMobilePortfolio(mobile, db);
    expect(mobile.asked, isNot(contains('provinces')));
    expect(mobile.asked.where((a) => a.startsWith('investigations')), [
      'investigations s7 false',
    ]);

    mobile.asked.clear();
    await syncMobilePortfolio(
      mobile,
      db,
      everyProvince: true,
      includeClosed: true,
    );
    expect(mobile.asked, contains('provinces'));
    expect(mobile.asked, contains('investigations s7 true'));
  });

  test('closed cases are listed only when the lawyer asks: no setting keeps '
      'it on', () async {
    final mobile = _Mobile();
    final sync = PortalSync(mobile: mobile, database: () async => db);
    addTearDown(sync.dispose);
    // A setting an earlier Folio kept is let go of.
    db.setMeta('portfolio_closed', '1');
    await sync.syncMobile(full: true);
    expect(mobile.asked, isNot(contains('investigations s7 true')));
    mobile.asked.clear();
    await sync.scanClosed();
    expect(mobile.asked, contains('investigations s7 true'));
    expect(await sync.closedScannedAt(), isNotNull);
  });
}

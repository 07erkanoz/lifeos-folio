import 'dart:io';

import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_enforcement.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _hukuk = 'Antalya 3. Asliye Hukuk Mahkemesi';
const _icra = 'Antalya 5. İcra Dairesi';
const _lawyer = 'Av. Deniz Kaya';

/// The parties of both cases: the lawyer's client, and the other side.
const _parties = [
  UyapParty('AYŞE KARACA', 'Davacı', 'DENİZ KAYA', 'Kişi'),
  UyapParty('BERK İNŞAAT LTD. ŞTİ.', 'Davalı', 'MURAT ER', 'Kurum'),
];

/// The web portal of a lawyer with one hukuk case and one icra file: each
/// with its parties, money, and the icra file's account and debtors.
class _Web extends UyapWebService {
  _Web() : super.forTesting() {
    session.value = UyapSession(
      user: 'DENİZ KAYA',
      since: DateTime.now(),
      route: UyapLoginRoute.tray,
    );
  }

  bool on = true;
  final asked = <String>[];

  /// The hukuk case's money not answered.
  bool moneyFails = false;

  @override
  bool get connected => on;

  static UyapCase _case(String courtId) => courtId == 'h1'
      ? const UyapCase('id-h1', '2025/80', 'h1', _hukuk)
      : const UyapCase('id-i1', '2025/4410', 'i1', _icra);

  @override
  Future<List<UyapOption>> courtTypes(String jurisdiction) async =>
      switch (jurisdiction) {
        '1' => const [UyapOption('HUKUK', 'Hukuk')],
        '2' => const [UyapOption('ICRA', 'İcra')],
        _ => const [],
      };

  @override
  Future<List<UyapOption>> courts(
    String jurisdiction,
    String courtType, {
    bool closed = false,
  }) async => closed
      ? const []
      : switch (courtType) {
          'HUKUK' => const [UyapOption('h1', _hukuk)],
          'ICRA' => const [UyapOption('i1', _icra)],
          _ => const [],
        };

  @override
  Future<UyapCasePage> casePage({
    required String jurisdiction,
    required String courtType,
    required UyapOption court,
    int? year,
    int? number,
    bool closed = false,
    int pageNumber = 1,
  }) async => UyapCasePage([_case(court.id)], 1);

  @override
  Future<List<UyapOption>> provinces() async => const [];

  @override
  Future<List<UyapOption>> chambers(String jurisdiction) async => const [];

  @override
  Future<List<Map<String, Object?>>> hearingRows(
    DateTime from,
    DateTime to,
  ) async => const [];

  @override
  Future<UyapCasePermissions> permissions(UyapCase target) async =>
      target.id == 'id-i1'
      ? const UyapCasePermissions(2, {
          'ayrinti_bilgileri',
          'taraf_bilgileri',
          'evrak_bilgileri',
          'tahsilat_reddiyat_bilgileri',
          'hesap_bilgileri',
          'borclu_bilgileri',
        })
      : const UyapCasePermissions(1, null);

  @override
  Future<UyapCaseDetails> caseDetails(UyapCase target) async {
    asked.add('details ${target.id}');
    return const UyapCaseDetails();
  }

  @override
  Future<List<UyapParty>> parties(UyapCase target) async {
    asked.add('parties ${target.id}');
    return _parties;
  }

  @override
  Future<UyapCaseDocuments> caseDocuments(
    UyapCase target, {
    void Function(int page, int pages)? onPage,
  }) async => const UyapCaseDocuments([]);

  @override
  Future<UyapCaseMoney> caseMoney(UyapCase target, int typeCode) async {
    if (moneyFails && target.id == 'id-h1') throw StateError('UYAP');
    return const UyapCaseMoney(
      fees: [
        UyapMoneyItem(
          kind: 'Peşin Harç',
          date: '12.03.2025 10:41',
          amount: 3415.5,
        ),
      ],
    );
  }

  @override
  Future<List<UyapAccountLine>> accountLines(UyapCase target) async => const [
    UyapAccountLine(1, 'Asıl alacak', '10.000,00'),
  ];

  @override
  Future<List<UyapDebtor>> debtors(UyapCase target) async => const [
    UyapDebtor(id: 'd1', name: 'SELİN AKSOY'),
  ];
}

/// UYAP Mobil with the same two cases: their parties and documents.
class _Mobile extends UyapMobileApi {
  _Mobile() : super.forTesting(Uri.parse('http://127.0.0.1:9/'));

  bool on = true;
  final asked = <String>[];

  @override
  bool get connected => on;

  @override
  Future<List<Map<String, Object?>>> hearingRows(
    DateTime from,
    DateTime to,
  ) async => const [];

  /// The same codes as the web's: a case it lists is found there.
  @override
  Future<List<Map<String, Object?>>> unitTypes(int type) async =>
      switch (type) {
        1 => [
          {'tablo': 'HUKUK'},
        ],
        2 => [
          {'tablo': 'ICRA'},
        ],
        _ => const [],
      };

  @override
  Future<List<Map<String, Object?>>> courts(
    int type,
    String unitKind, {
    required bool closed,
  }) async => closed
      ? const []
      : [
          {'birimId': 'm$type', 'birimAdi': type == 2 ? _icra : _hukuk},
        ];

  /// Answered late: the web is done with its own part by then.
  Duration late = Duration.zero;

  @override
  Future<List<Map<String, Object?>>> cases(
    int type,
    String unitKind,
    String court, {
    required bool closed,
  }) async {
    await Future<void>.delayed(late);
    return [
      {
        'dosyaId': 'mid-$type',
        'dosyaNo': type == 2 ? '2025/4410' : '2025/80',
        'birimAdi': type == 2 ? _icra : _hukuk,
        'dosyaDurumAciklama': 'Açık',
      },
    ];
  }

  @override
  Future<List<Map<String, Object?>>> danistayChambers() async => const [];

  @override
  Future<List<Map<String, Object?>>> findCase(
    int type,
    String unitKind,
    String court, {
    required String year,
    required String sequence,
    required bool closed,
  }) async => [
    {
      'dosyaId': 'mid-$type',
      'dosyaNo': '$year/$sequence',
      'birimAdi': type == 2 ? _icra : _hukuk,
    },
  ];

  @override
  Future<List<Map<String, Object?>>> parties(
    String caseId, {
    String? caseType,
  }) async {
    asked.add('parties $caseId');
    return [
      for (final t in _parties)
        {'adi': t.name, 'rol': t.role, 'vekil': t.lawyer, 'kisiKurum': t.kind},
    ];
  }

  @override
  Future<Map<String, Object?>> caseDocuments(String caseId) async => const {};
}

void main() {
  late Directory root;
  late PortalDatabase db;
  late UyapCaseStore store;
  late UyapCaseStore real;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('folio-ilk-dolum-');
    db = PortalDatabase.memory();
    real = UyapCaseStore.instance;
    store = UyapCaseStore(
      directory: Directory('${root.path}/destek'),
      settings: UyapSettings(
        directory: Directory('${root.path}/destek'),
        home: '${root.path}/ev',
      ),
    );
    UyapCaseStore.instance = store;
    PortalSync.caseGap = Duration.zero;
  });
  tearDown(() async {
    UyapCaseStore.instance = real;
    db.dispose();
    await root.delete(recursive: true);
  });

  PortalSync syncOf(_Web web, _Mobile mobile) {
    final sync = PortalSync(web: web, mobile: mobile, database: () async => db);
    addTearDown(sync.dispose);
    return sync;
  }

  final hukuk = caseKey('2025/80', _hukuk);
  final icra = caseKey('2025/4410', _icra);

  Iterable<String> clients() =>
      db.clientEntries(lawyer: _lawyer).map((e) => e.name);

  test('with the web portal alone the first reading brings every case with '
      'its parties, so the clients are there, and its money; an icra file '
      'its account and debtors', () async {
    final web = _Web();
    final sync = syncOf(web, _Mobile()..on = false);
    await sync.syncPortfolio(full: true);
    expect(db.cases().keys, containsAll([hukuk, icra]));
    expect(db.caseParties().keys, containsAll([hukuk, icra]));
    expect(clients(), contains('AYŞE KARACA'));
    expect(clients(), isNot(contains('BERK İNŞAAT LTD. ŞTİ.')));
    final kept = (await store.load(_hukuk, '2025/80'))!;
    expect(kept.money!.fees.single.kind, 'Peşin Harç');
    final file = (await store.load(_icra, '2025/4410'))!;
    expect(file.enforcement!.lines.single.label, 'Asıl alacak');
    expect(file.enforcement!.debtors.single.name, 'SELİN AKSOY');
    expect(db.meta(PortalSync.webCheckedKey(icra)), isNotNull);
    // Read once: the next reading does not ask each case again.
    web.asked.clear();
    await sync.syncPortfolio();
    expect(web.asked, isEmpty);
  });

  test('with UYAP Mobil alone its parties make the clients; the web, '
      'connected later, reads each case again for what only it has: the '
      'money and the icra account', () async {
    final web = _Web()..on = false;
    final mobile = _Mobile();
    final sync = syncOf(web, mobile);
    // The courts' list as UYAP Mobil read it this week.
    await syncWebPortfolio(_Web(), db);
    db.setMeta('portfolio_at', DateTime.now().toIso8601String());
    await sync.syncMobile();
    expect(mobile.asked, containsAll(['parties mid-1', 'parties mid-2']));
    expect(clients(), contains('AYŞE KARACA'));
    expect((await store.load(_icra, '2025/4410'))!.enforcement, isNull);
    // The web comes: it does the rest, and UYAP Mobil is not asked again.
    web.on = true;
    mobile.asked.clear();
    await sync.syncPortfolio();
    expect(web.asked, containsAll(['parties id-h1', 'parties id-i1']));
    expect(mobile.asked, isEmpty);
    final file = (await store.load(_icra, '2025/4410'))!;
    expect(file.enforcement!.lines, isNotEmpty);
    expect((await store.load(_hukuk, '2025/80'))!.money, isNotNull);
  });

  test('with both connected UYAP Mobil reads no case of itself: the web '
      'enriches them all', () async {
    final web = _Web();
    final mobile = _Mobile();
    final sync = syncOf(web, mobile);
    await syncWebPortfolio(_Web(), db);
    db.setMeta('portfolio_at', DateTime.now().toIso8601String());
    await sync.syncPortfolio();
    expect(mobile.asked, isEmpty);
    expect(web.asked, containsAll(['parties id-h1', 'parties id-i1']));
    expect(clients(), contains('AYŞE KARACA'));
    expect(
      (await store.load(_icra, '2025/4410'))!.enforcement!.debtors,
      isNotEmpty,
    );
  });

  test('a case whose money did not come is not counted read: it is asked '
      'again', () async {
    final web = _Web()..moneyFails = true;
    final sync = syncOf(web, _Mobile()..on = false);
    await sync.syncPortfolio(full: true);
    expect(db.meta(PortalSync.webCheckedKey(hukuk)), isNull);
    expect(db.meta(PortalSync.webCheckedKey(icra)), isNotNull);
    // Its parties came all the same: the client is there.
    expect(clients(), contains('AYŞE KARACA'));
    expect(
      sync.state(PortalChannel.uyapWeb).problem,
      'Bazı kayıtlar alınamadı',
    );
  });

  test('with both connected, the cases UYAP Mobil lists when the web has '
      'nothing of its own to read are read by the web all the same', () async {
    final web = _Web();
    final mobile = _Mobile()..late = const Duration(milliseconds: 300);
    final sync = syncOf(web, mobile);
    // The web has nothing of its own due today: only UYAP Mobil reads.
    final now = DateTime.now().toIso8601String();
    db.setMeta('portfolio_web_only_at', now);
    db.setMeta('hearings_at:${PortalChannel.uyapWeb.name}', now);
    await sync.syncMobile();
    // What runs after UYAP Mobil's reading.
    for (
      var i = 0;
      i < 50 && db.meta(PortalSync.webCheckedKey(icra)) == null;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(db.cases().keys, containsAll([hukuk, icra]));
    expect(mobile.asked, isEmpty, reason: 'the web reads the cases');
    expect(web.asked, containsAll(['parties id-h1', 'parties id-i1']));
    expect(clients(), contains('AYŞE KARACA'));
    expect(
      (await store.load(_icra, '2025/4410'))!.enforcement!.lines,
      isNotEmpty,
    );
  });

  test('the parties of every case come first, a request each, before any '
      'case is read whole: the clients are there in minutes', () async {
    final web = _Web();
    final sync = syncOf(web, _Mobile()..on = false);
    await sync.syncPortfolio(full: true);
    final firstDetails = web.asked.indexWhere((a) => a.startsWith('details'));
    expect(web.asked.indexOf('parties id-h1'), lessThan(firstDetails));
    expect(web.asked.indexOf('parties id-i1'), lessThan(firstDetails));
    expect(clients(), contains('AYŞE KARACA'));
  });
}

import 'dart:async';
import 'dart:io';

import 'package:evrak_convert/services/portal/case_sections.dart';
import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/portal/uyap_job.dart';
import 'package:evrak_convert/services/uyap/uyap_case_links.dart';
import 'package:evrak_convert/services/uyap/uyap_case_panel_controller.dart';
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
  }) async {
    // A whole kind of unit asked: its one court.
    final id = court.id.isNotEmpty
        ? court.id
        : courtType == 'ICRA'
        ? 'i1'
        : 'h1';
    return UyapCasePage([_case(id)], 1);
  }

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
  }) async {
    asked.add('documents ${target.id}');
    return const UyapCaseDocuments([]);
  }

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
    if (partiesFail) throw StateError('UYAP');
    // The session ending after this many answers.
    if (--answersLeft == 0) on = false;
    return [
      for (final t in _parties)
        {'adi': t.name, 'rol': t.role, 'vekil': t.lawyer, 'kisiKurum': t.kind},
    ];
  }

  /// Parties' answers before the session ends; endless when below zero.
  int answersLeft = -1;

  /// The parties never answered, the session staying.
  bool partiesFail = false;

  /// UYAP's notifications: a Vekil Kaydı for a case not in the portfolio.
  bool vekilKaydi = false;

  @override
  Future<List<Map<String, Object?>>> noticeRows({String? after}) async =>
      vekilKaydi && after == null
      ? [
          {
            'bildirimId': 'b1',
            'mesajId': 'm1',
            'baslik': 'Vekil Kaydı',
            'mesaj':
                'Antalya 3. Asliye Ceza Mahkemesi birimi, 2026/91 dosyasında '
                ', Sanık Deniz Yılmaz vekili olarak Vekil Kaydı yapıldı.',
          },
        ]
      : const [];

  /// The documents' answer: none, or (null) one without the list.
  Map<String, Object?>? documents = const {'tumEvraklar': {}, 'son20Evrak': []};

  @override
  Future<Map<String, Object?>> caseDocuments(String caseId) async {
    asked.add('documents $caseId');
    return documents ?? const {'hata': 'yok'};
  }
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

  Map<(CaseSection, PortalChannel), SectionState> sections(String key) => {
    for (final s in db.sections(key)) (s.section, s.channel): s,
  };

  // docs/uyap-hedef-harita.md §2.3: a list is a list; no case is read
  // after it of itself.
  test('the web\'s portfolio is its list alone: no case\'s parties, '
      'particulars or money are asked after it', () async {
    final web = _Web();
    final sync = syncOf(web, _Mobile()..on = false);
    await sync.syncPortfolio(full: true);
    expect(db.cases().keys, containsAll([hukuk, icra]));
    expect(web.asked, isEmpty);
    expect(db.caseParties(), isEmpty);
    expect(await store.load(_icra, '2025/4410'), isNull);
    expect(sync.state(PortalChannel.uyapWeb).problem, isNull);
  });

  test('UYAP Mobil\'s portfolio is its list alone, the web connected or '
      'not', () async {
    for (final webOn in [false, true]) {
      final web = _Web()..on = webOn;
      final mobile = _Mobile();
      final sync = syncOf(web, mobile);
      await sync.syncMobile(full: true);
      expect(db.cases().keys, containsAll([hukuk, icra]));
      expect(mobile.asked, isEmpty, reason: 'web ${webOn ? 'on' : 'off'}');
      expect(web.asked, isEmpty, reason: 'web ${webOn ? 'on' : 'off'}');
      // Nothing waits to run after it.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(web.asked, isEmpty);
    }
  });

  test('the lawyer\'s "Tümünü tazele" reads every open case on the web: '
      'its parties make the clients, and its money; an icra file its account '
      'and debtors', () async {
    final web = _Web();
    final sync = syncOf(web, _Mobile()..on = false);
    await sync.syncPortfolio(full: true);
    await sync.refreshAllOnWeb();
    expect(clients(), contains('AYŞE KARACA'));
    expect(clients(), isNot(contains('BERK İNŞAAT LTD. ŞTİ.')));
    final kept = (await store.load(_hukuk, '2025/80'))!;
    expect(kept.money!.fees.single.kind, 'Peşin Harç');
    final file = (await store.load(_icra, '2025/4410'))!;
    expect(file.enforcement!.lines.single.label, 'Asıl alacak');
    expect(file.enforcement!.debtors.single.name, 'SELİN AKSOY');
    expect(db.meta(PortalSync.webCheckedKey(icra)), isNotNull);
  });

  test('each reading leaves what came of each section on its channel: the '
      'web\'s icra file whole, a failed sum asked again', () async {
    final web = _Web()..moneyFails = true;
    final sync = syncOf(web, _Mobile()..on = false);
    await sync.syncPortfolio(full: true);
    await sync.refreshAllOnWeb();
    expect(db.meta(PortalSync.webCheckedKey(hukuk)), isNull);
    const w = PortalChannel.uyapWeb;
    final file = sections(icra);
    for (final s in [
      CaseSection.parties,
      CaseSection.money,
      CaseSection.account,
      CaseSection.debtors,
    ]) {
      expect(file[(s, w)]!.result, SectionResult.read, reason: s.name);
      expect(file[(s, w)]!.complete, isTrue, reason: s.name);
    }
    expect(file[(CaseSection.documents, w)]!.result, SectionResult.empty);
    final kase = sections(hukuk);
    expect(kase[(CaseSection.money, w)]!.result, SectionResult.failed);
    expect(kase[(CaseSection.money, w)]!.succeeded, isNull);
    expect(kase[(CaseSection.money, w)]!.tries, 1);
    // A court case's account and debtors: not shown, not asked again.
    expect(kase[(CaseSection.account, w)]!.result, SectionResult.notShown);
    expect(kase[(CaseSection.parties, w)]!.result, SectionResult.read);
  });

  test('UYAP Mobil\'s reading is its own: the web\'s sections stay unread, '
      'and an answer without the documents is not "none"', () async {
    final web = _Web()..on = false;
    final mobile = _Mobile()..documents = null;
    final sync = syncOf(web, mobile);
    await syncWebPortfolio(_Web(), db);
    final panel = UyapCasePanelController(
      web: web,
      mobile: mobile,
      sync: sync,
      store: store,
      pause: Duration.zero,
    );
    addTearDown(panel.dispose);
    await panel.attach(
      const UyapCaseLink(
        jurisdiction: '1',
        courtType: 'HUKUK',
        courtId: 'h1',
        court: _hukuk,
        number: '2025/80',
      ),
    );
    await panel.readSections(PortalChannel.uyapMobile, {
      CaseSection.particulars,
      CaseSection.parties,
      CaseSection.documents,
    });
    const m = PortalChannel.uyapMobile;
    final kase = sections(hukuk);
    expect(kase[(CaseSection.parties, m)]!.result, SectionResult.read);
    expect(kase[(CaseSection.documents, m)]!.result, SectionResult.failed);
    expect(kase[(CaseSection.particulars, m)]!.partial, isTrue);
    expect(kase.keys.where((k) => k.$2 == PortalChannel.uyapWeb), isEmpty);
    expect(kase.containsKey((CaseSection.money, m)), isFalse);
  });

  test('opening a case\'s page reads only its sections never read or older '
      'than a day, and not again within three minutes', () async {
    final web = _Web();
    final mobile = _Mobile();
    final sync = syncOf(web, mobile);
    await syncWebPortfolio(_Web(), db);
    final panel = UyapCasePanelController(
      web: web,
      mobile: mobile,
      sync: sync,
      store: store,
      pause: Duration.zero,
    );
    addTearDown(panel.dispose);
    await panel.attach(
      const UyapCaseLink(
        jurisdiction: '2',
        courtType: 'ICRA',
        courtId: 'i1',
        court: _icra,
        number: '2025/4410',
      ),
    );
    // Its parties and particulars read on the web an hour ago.
    db.saveSections(icra, PortalChannel.uyapWeb, const [
      SectionOutcome(CaseSection.particulars, SectionResult.read),
      SectionOutcome(CaseSection.parties, SectionResult.read),
    ], at: DateTime.now().subtract(const Duration(hours: 1)));
    await sync.readOpened(panel, icra);
    expect(web.asked, isNot(contains('parties id-i1')));
    expect(web.asked, isNot(contains('details id-i1')));
    expect(mobile.asked, isEmpty);
    expect(panel.record!.money, isNotNull);
    expect(panel.record!.enforcement!.debtors, isNotEmpty);
    expect(
      sections(icra)[(CaseSection.money, PortalChannel.uyapWeb)],
      isNotNull,
    );
    // Opened again at once: nothing asked.
    web.asked.clear();
    db.saveSections(icra, PortalChannel.uyapWeb, const [
      SectionOutcome(CaseSection.money, SectionResult.failed),
    ]);
    await sync.readOpened(panel, icra);
    expect(web.asked, isEmpty);
  });

  test(
    'a Vekil Kaydı for a case not in the portfolio reads the portfolio '
    'only while Folio reads UYAP of itself; else the lawyer is told',
    () async {
      for (final auto in [false, true]) {
        db.dispose();
        db = PortalDatabase.memory();
        PortalSync.newCaseNotice.value = null;
        final mobile = _Mobile()..vekilKaydi = true;
        final sync = syncOf(_Web()..on = false, mobile);
        await sync.setAutoFetch(auto);
        // Not the first reading of the notifications: what comes is news.
        db.setMeta('uyap_notice_mobile', DateTime(2026).toIso8601String());
        await sync.syncNotices(force: true);
        for (var i = 0; i < 20 && auto && db.cases().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(db.cases().isNotEmpty, auto, reason: 'auto $auto');
        expect(
          PortalSync.newCaseNotice.value != null,
          !auto,
          reason: 'auto $auto',
        );
      }
    },
  );

  group('the lawyer\'s setup and the web\'s completion', () {
    test('the setup on UYAP Mobil reads the list, then each case\'s '
        'parties, then its documents\' list, on UYAP Mobil alone though the '
        'web is connected', () async {
      final web = _Web();
      final mobile = _Mobile();
      final sync = syncOf(web, mobile);
      await sync.startSetup(PortalChannel.uyapMobile);
      expect(sync.job.value!.done, isTrue);
      expect(web.asked, isEmpty);
      // Every case's parties before any case's documents.
      expect(
        mobile.asked.take(2),
        unorderedEquals(['parties mid-1', 'parties mid-2']),
      );
      expect(
        mobile.asked.skip(2),
        unorderedEquals(['documents mid-1', 'documents mid-2']),
      );
      expect(clients(), contains('AYŞE KARACA'));
      const m = PortalChannel.uyapMobile;
      for (final key in [hukuk, icra]) {
        expect(sections(key)[(CaseSection.parties, m)]!.complete, isTrue);
        expect(sections(key)[(CaseSection.documents, m)]!.complete, isTrue);
      }
    });

    test('the session ending stops it; connected again it goes on where it '
        'was, no case asked twice', () async {
      final web = _Web()..on = false;
      final mobile = _Mobile()..answersLeft = 1;
      final sync = syncOf(web, mobile);
      await sync.startSetup(PortalChannel.uyapMobile);
      expect(sync.job.value!.done, isFalse);
      expect(sync.job.value!.stopped, UyapJobStop.session);
      expect(sync.job.value!.stage, UyapJobStage.parties);
      final first = mobile.asked.single;
      mobile
        ..on = true
        ..asked.clear();
      await sync.resumeJob();
      expect(sync.job.value!.done, isTrue);
      expect(mobile.asked.where((a) => a.startsWith('parties')), [
        isNot(first),
      ]);
    });

    test('cases that would not be read leave the job waiting, not done; '
        'tried three times, a case is given up', () async {
      final mobile = _Mobile()..partiesFail = true;
      final sync = syncOf(_Web()..on = false, mobile);
      await sync.startSetup(PortalChannel.uyapMobile);
      expect(sync.job.value!.done, isFalse);
      expect(sync.job.value!.stopped, UyapJobStop.incomplete);
      expect(sync.job.value!.stage, UyapJobStage.parties);
      await sync.resumeJob();
      expect(sync.job.value!.stopped, UyapJobStop.incomplete);
      await sync.resumeJob();
      // Three tries each: given up, shown failed; the documents read.
      expect(sync.job.value!.done, isTrue);
      expect(
        sections(
          hukuk,
        )[(CaseSection.parties, PortalChannel.uyapMobile)]!.result,
        SectionResult.failed,
      );
      expect(mobile.asked.where((a) => a.startsWith('parties')).length, 6);
    });

    test('paused by the lawyer it waits for them', () async {
      final mobile = _Mobile();
      final sync = syncOf(_Web()..on = false, mobile);
      // Paused as soon as the list is read.
      sync.portfolioVersion.addListener(() => unawaited(sync.pauseJob()));
      await sync.startSetup(PortalChannel.uyapMobile);
      expect(sync.job.value!.stopped, UyapJobStop.user);
      expect(mobile.asked, isEmpty);
    });

    test('the web\'s completion asks what only the web has, not the '
        'documents\' list UYAP Mobil gave whole; the case is then read '
        'whole', () async {
      final web = _Web();
      final mobile = _Mobile();
      final sync = syncOf(web, mobile);
      await sync.startSetup(PortalChannel.uyapMobile);
      await sync.startWebCompletion();
      expect(sync.job.value!.done, isTrue);
      expect(web.asked, containsAll(['parties id-h1', 'parties id-i1']));
      expect(web.asked.where((a) => a.startsWith('documents')), isEmpty);
      final file = (await store.load(_icra, '2025/4410'))!;
      expect(file.enforcement!.debtors, isNotEmpty);
      expect(db.meta(PortalSync.webCheckedKey(icra)), isNotNull);
      // Its counsel came from the web: the client stays.
      expect(clients(), contains('AYŞE KARACA'));
    });
  });

  group('reading chosen sections on a chosen channel', () {
    const place = UyapCaseLink(
      jurisdiction: '2',
      courtType: 'ICRA',
      courtId: 'i1',
      court: _icra,
      number: '2025/4410',
    );

    Future<UyapCasePanelController> panelOf(_Web web, _Mobile mobile) async {
      final sync = syncOf(web, mobile);
      final panel = UyapCasePanelController(
        web: web,
        mobile: mobile,
        sync: sync,
        store: store,
        pause: Duration.zero,
        background: true,
      );
      addTearDown(panel.dispose);
      await panel.attach(place);
      return panel;
    }

    test('UYAP Mobil\'s stays on UYAP Mobil though the web is connected, '
        'and asks only what was asked', () async {
      final web = _Web();
      final mobile = _Mobile();
      final panel = await panelOf(web, mobile);
      await panel.readSections(PortalChannel.uyapMobile, {CaseSection.parties});
      expect(panel.error, isNull);
      expect(web.asked, isEmpty);
      expect(mobile.asked, ['parties mid-2']);
      expect(panel.usedWeb, isFalse);
      expect(panel.outcomes.map((o) => o.section), [CaseSection.parties]);
      expect(panel.record!.parties, isNotEmpty);
    });

    test('the web\'s asks only the money and the account, keeps the rest, '
        'and does not go to UYAP Mobil when the web is gone', () async {
      final web = _Web();
      final mobile = _Mobile();
      final panel = await panelOf(web, mobile);
      await panel.readSections(PortalChannel.uyapMobile, {CaseSection.parties});
      await panel.readSections(PortalChannel.uyapWeb, {
        CaseSection.money,
        CaseSection.account,
      });
      expect(panel.error, isNull);
      expect(web.asked, isEmpty, reason: 'no particulars, no parties');
      expect(panel.outcomes.map((o) => o.section).toSet(), {
        CaseSection.money,
        CaseSection.account,
      });
      final kept = panel.record!;
      expect(kept.money, isNotNull);
      expect(kept.enforcement!.lines, isNotEmpty);
      expect(kept.parties, isNotEmpty, reason: 'kept as they were');
      web.on = false;
      mobile.asked.clear();
      await panel.readSections(PortalChannel.uyapWeb, {CaseSection.money});
      expect(panel.error, isNotNull);
      expect(mobile.asked, isEmpty);
      expect(panel.outcomes, isEmpty);
    });
  });
}

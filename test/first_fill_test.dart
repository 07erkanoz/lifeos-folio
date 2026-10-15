import 'dart:async';
import 'dart:io';

import 'package:evrak_convert/services/portal/case_sections.dart';
import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/portal/sync_log.dart';
import 'package:evrak_convert/services/portal/uyap_job.dart';
import 'package:evrak_convert/services/portal/uyap_job_owner.dart';
import 'package:evrak_convert/services/portal/uyap_status.dart';
import 'package:evrak_convert/services/sync/hlc.dart';
import 'package:evrak_convert/services/sync/sync_generation.dart';
import 'package:evrak_convert/services/uyap/uyap_case_links.dart';
import 'package:evrak_convert/services/uyap/uyap_case_panel_controller.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_enforcement.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/portfolio/portfolio_rows.dart';
import 'package:evrak_convert/ui/portfolio/uyap_status_dialog.dart';
import 'package:flutter/material.dart';
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

  /// How often its hearings and its notifications were asked for.
  int hearingsAsked = 0, noticesAsked = 0;

  @override
  Future<List<Map<String, Object?>>> hearingRows(
    DateTime from,
    DateTime to,
  ) async {
    hearingsAsked++;
    return const [];
  }

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
    await onParties?.call(caseId);
    if (partiesFail || partiesFailFor.contains(caseId)) {
      throw StateError('UYAP');
    }
    // The session ending after this many answers.
    if (--answersLeft == 0) on = false;
    return [
      for (final t in _parties)
        {'adi': t.name, 'rol': t.role, 'vekil': t.lawyer, 'kisiKurum': t.kind},
    ];
  }

  /// Parties' answers before the session ends; endless when below zero.
  int answersLeft = -1;

  /// Told of each case whose parties are asked for, before the answer.
  Future<void> Function(String caseId)? onParties;

  /// The parties never answered, the session staying.
  bool partiesFail = false;

  /// The cases whose parties are never answered.
  final partiesFailFor = <String>{};

  /// UYAP's notifications: a Vekil Kaydı for a case not in the portfolio.
  bool vekilKaydi = false;

  @override
  Future<List<Map<String, Object?>>> noticeRows({String? after}) async {
    noticesAsked++;
    return vekilKaydi && after == null
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
  }

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

    test('a case whose parties would not come does not hold back the '
        'other cases documents: the job reads them, then waits for the lawyer '
        'to try that one again', () async {
      final mobile = _Mobile()..partiesFailFor.add('mid-1');
      final sync = syncOf(_Web()..on = false, mobile);
      await sync.startSetup(PortalChannel.uyapMobile);
      expect(sync.job.value!.stopped, UyapJobStop.incomplete);
      expect(sync.job.value!.stage, UyapJobStage.parties);
      expect(
        mobile.asked.where((a) => a.startsWith('documents')),
        unorderedEquals(['documents mid-1', 'documents mid-2']),
      );
      // Sürdür asks only the parties left, nothing read again.
      mobile
        ..partiesFailFor.clear()
        ..asked.clear();
      await sync.resumeJob();
      expect(sync.job.value!.done, isTrue);
      expect(mobile.asked, ['parties mid-1']);
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

  // A portfolio an earlier Folio listed whole, its reading of each case
  // stopped half way: the cases never read are filled at the lawyer's
  // asking, from Dava Dosyalarım's "UYAP durumu".
  group('the cases listed but never read one by one', () {
    /// The list read, the hukuk case read one by one before, the icra
    /// file never.
    Future<PortalSync> listedHalfRead(
      _Web web,
      _Mobile mobile, {
      UyapCaseMoney? money,
    }) async {
      final sync = syncOf(web, mobile);
      await sync.syncPortfolio(full: true);
      await store.keep(
        target: const UyapCase('id-h1', '2025/80', 'h1', _hukuk),
        details: const UyapCaseDetails(),
        parties: _parties,
        documents: const UyapCaseDocuments([
          UyapCaseDocument(
            key: 'a',
            documentId: 'a',
            caseId: 'id-h1',
            type: 'Tensip Zaptı',
            number: '1',
            approved: '01.09.2026 10:00',
            sender: 'Mahkeme',
            description: '',
          ),
        ]),
        money: money,
      );
      return sync;
    }

    test('are filled on UYAP Mobil, those alone, their list not read '
        'again', () async {
      final mobile = _Mobile();
      final sync = await listedHalfRead(_Web()..on = false, mobile);
      expect(await sync.unreadCases(), {icra});
      final listed = db.meta('portfolio_at');
      mobile.asked.clear();
      await sync.startFill();
      expect(sync.job.value!.kind, UyapJobKind.fill);
      expect(sync.job.value!.done, isTrue);
      expect(db.meta('portfolio_at'), listed);
      expect(mobile.asked, ['parties mid-2', 'documents mid-2']);
      const m = PortalChannel.uyapMobile;
      expect(sections(icra)[(CaseSection.parties, m)]!.complete, isTrue);
      expect(sections(icra)[(CaseSection.documents, m)]!.complete, isTrue);
      expect(sections(hukuk), isEmpty);
      expect(await sync.unreadCases(), isEmpty);
    });

    test('a fill stopped after its parties stage and started anew still '
        'reads the documents lists: what is missing is counted from what '
        'came', () async {
      final mobile = _Mobile();
      final sync = await listedHalfRead(_Web()..on = false, mobile);
      // Paused as soon as the icra file's parties are kept.
      sync.portfolioVersion.addListener(() {
        if (sync.job.value?.stage == UyapJobStage.parties) {
          unawaited(sync.pauseJob());
        }
      });
      await sync.startFill();
      expect(sync.job.value!.stopped, UyapJobStop.user);
      expect((await store.load(_icra, '2025/4410'))!.parties, isNotEmpty);
      final status = await readUyapStatus(database: db, store: store);
      expect(status.unread, isEmpty);
      expect(status.documentsMissing, {icra});
      mobile.asked.clear();
      await sync.startFill();
      expect(sync.job.value!.done, isTrue);
      // Its parties not asked again; its documents' list read.
      expect(mobile.asked, ['documents mid-2']);
      expect(
        (await readUyapStatus(database: db, store: store)).documentsMissing,
        isEmpty,
      );
    });

    test('on the web, only the cases whose money it never brought are read, '
        'though UYAP Mobil is connected', () async {
      final web = _Web();
      final mobile = _Mobile();
      final sync = await listedHalfRead(
        web,
        mobile,
        money: const UyapCaseMoney(
          fees: [UyapMoneyItem(kind: 'Peşin Harç', date: '', amount: 1)],
        ),
      );
      final status = await readUyapStatus(database: db, store: store);
      expect(status.webMissing, {icra});
      web.asked.clear();
      mobile.asked.clear();
      await sync.startFill(channel: PortalChannel.uyapWeb);
      expect(sync.job.value!.done, isTrue);
      expect(sync.job.value!.channel, PortalChannel.uyapWeb);
      expect(mobile.asked, isEmpty);
      expect(web.asked, contains('parties id-i1'));
      expect(web.asked.where((a) => a.contains('id-h1')), isEmpty);
      final file = (await store.load(_icra, '2025/4410'))!;
      expect(file.money, isNotNull);
      expect(file.enforcement!.debtors, isNotEmpty);
      expect(
        (await readUyapStatus(database: db, store: store)).webMissing,
        isEmpty,
      );
    });

    test('the session ending, the fill goes on where it was, the case read '
        'in its first stage still read in its next', () async {
      final mobile = _Mobile()..answersLeft = 1;
      final sync = await listedHalfRead(_Web()..on = false, mobile);
      mobile.asked.clear();
      await sync.startFill();
      expect(sync.job.value!.stopped, UyapJobStop.session);
      // Kept with the job: read now, the icra file is still the fill's.
      expect(sync.job.value!.cases, {icra});
      mobile.on = true;
      await sync.resumeJob();
      expect(sync.job.value!.done, isTrue);
      expect(
        sections(
          icra,
        )[(CaseSection.documents, PortalChannel.uyapMobile)]!.complete,
        isTrue,
      );
    });

    test('UYAP durumu counts them, says the list read and a reading of it '
        'left unfinished, and the log says what the reading did', () async {
      final log = File('${root.path}/uyap-senkron.log');
      final before = SyncLog.file;
      SyncLog.file = () async => log;
      addTearDown(() async {
        // What is being written finished before the folder goes.
        await SyncLog.tail(0);
        SyncLog.file = before;
      });
      await listedHalfRead(_Web()..on = false, _Mobile());
      var status = await readUyapStatus(database: db, store: store);
      expect(status.open, 2);
      expect(status.read, 1);
      expect(status.withParties, 1);
      expect(status.unread, {icra});
      // Its prosecutors' offices not answered: the list came in part.
      expect(status.listWhole, isNull);
      expect(status.listTried, isNotNull);
      expect(status.listStarted, isEmpty);
      final lines = await SyncLog.tail(20);
      expect(lines.any((l) => l.contains('portföy listesi okunuyor')), isTrue);
      expect(lines.any((l) => l.contains('portföyü okundu')), isTrue);
      // Folio closed in the middle of a reading: its start stays.
      db.setMeta(
        PortalSync.listStartedKey(PortalChannel.uyapMobile),
        DateTime(2026, 10, 15, 20, 23).toIso8601String(),
      );
      status = await readUyapStatus(database: db, store: store);
      expect(status.listStarted.keys, [PortalChannel.uyapMobile]);
    });

    testWidgets('UYAP durumu shows them and fills them at a press', (
      tester,
    ) async {
      final mobile = _Mobile();
      late PortalSync sync;
      await tester.runAsync(() async {
        sync = await listedHalfRead(_Web()..on = false, mobile);
      });
      mobile.asked.clear();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UyapStatusDialog(sync: sync, database: db, store: store),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
        }
      }

      await settle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Hiç okunmamış: 1'), findsOneWidget);
      expect(find.textContaining('Evrak listesi gelen: 1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('uyap-status-fill')));
      // The job's own waits are the test clock's: let it go on to its end.
      for (var i = 0; i < 30 && !(sync.job.value?.done ?? false); i++) {
        await settle();
        await tester.pump(const Duration(seconds: 1));
      }
      expect(mobile.asked, ['parties mid-2', 'documents mid-2']);
      expect(sync.job.value!.done, isTrue);
      // Counted again a little after the job: none left.
      await tester.pump(const Duration(seconds: 4));
      await settle();
      expect(find.text('Evrak listesi gelmemiş dosya yok.'), findsOneWidget);
    });

    test('the portfolio shows the parties the list gave a case never '
        'read', () async {
      await listedHalfRead(_Web()..on = false, _Mobile());
      db.saveCaseParties(icra, _parties, source: 'uyap');
      final rows = await loadPortfolio(
        lawyer: _lawyer,
        database: db,
        store: store,
      );
      final row = rows.singleWhere((r) => r.kase.key == icra);
      expect(row.record, isNull);
      expect([...row.ours, ...row.others].map((p) => p.name), [
        'AYŞE KARACA',
        'BERK İNŞAAT LTD. ŞTİ.',
      ]);
    });
  });

  // docs/uyap-is-sahipligi.md: of the lawyer's own devices, one runs the
  // job; the others show it.
  group('two of the lawyer\'s own devices', () {
    late PortalDatabase home;
    setUp(() => home = PortalDatabase.memory());
    tearDown(() => home.dispose());

    /// The office computer (on [db]) and the home one (on [home]), each
    /// telling the other of the job, as when on one network.
    (PortalSync, PortalSync) pair(_Mobile office, _Mobile atHome) {
      late PortalSync a, b;
      Future<List<Object?>> Function(Map<String, Object?>) to(
        PortalSync Function() other,
      ) => (claim) async {
        await other().mergeJob(claim, direct: true);
        return [other().jobExport()];
      };
      a = PortalSync(
        web: _Web()..on = false,
        mobile: office,
        database: () async => db,
        deviceName: 'Ofis bilgisayarı',
        tellJob: to(() => b),
      );
      b = PortalSync(
        web: _Web()..on = false,
        mobile: atHome,
        database: () async => home,
        deviceName: 'Ev bilgisayarı',
        tellJob: to(() => a),
      );
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      return (a, b);
    }

    /// The office computer's setup at [stage], said [ago] to run.
    Map<String, Object?> runningAtOffice({
      Duration ago = Duration.zero,
      UyapJobStage stage = UyapJobStage.list,
    }) {
      final at = DateTime.now().toUtc().subtract(ago);
      return UyapJobClaim.start(
        UyapJob(
          kind: UyapJobKind.setup,
          channel: PortalChannel.uyapMobile,
          stage: stage,
          started: at,
        ),
        owner: 'ofis',
        ownerName: 'Ofis bilgisayarı',
        version: Hlc(at.millisecondsSinceEpoch, 0, 'ofis'),
      ).toJson();
    }

    PortalSync atHome(_Mobile mobile) {
      final sync = PortalSync(
        web: _Web()..on = false,
        mobile: mobile,
        database: () async => home,
        deviceName: 'Ev bilgisayarı',
      );
      addTearDown(sync.dispose);
      return sync;
    }

    test('a job started on one is shown on the other, which runs nothing of '
        'it: not on connecting, not on Sürdür', () async {
      final office = _Mobile()..answersLeft = 1;
      final mobile = _Mobile();
      final (a, b) = pair(office, mobile);
      await a.startSetup(PortalChannel.uyapMobile);
      await pumpEventQueue();
      expect(a.job.value!.stopped, UyapJobStop.session);
      expect(b.jobElsewhere, isTrue);
      expect(b.job.value!.stopped, UyapJobStop.session);
      expect(b.jobClaim.value!.ownerName, 'Ofis bilgisayarı');
      await b.connectedForTesting(PortalChannel.uyapMobile);
      await b.resumeJob();
      await b.pauseJob();
      await pumpEventQueue();
      expect(mobile.asked, isEmpty);
      expect(home.meta('portfolio_at'), isNull);
      expect(b.job.value!.stopped, UyapJobStop.session);
      expect(b.jobElsewhere, isTrue);
    });

    test('heard of within three minutes there, a start here waits for it to '
        'be taken over; taken over, it runs here a generation on', () async {
      final mobile = _Mobile();
      final b = atHome(mobile);
      await b.mergeJob(runningAtOffice(), direct: true);
      expect(b.jobRunningElsewhere(), isTrue);
      await b.startSetup(PortalChannel.uyapMobile);
      expect(mobile.asked, isEmpty);
      expect(b.jobClaim.value!.owner, 'ofis');
      await b.takeOverJob();
      expect(b.job.value!.done, isTrue);
      expect(b.jobElsewhere, isFalse);
      expect(b.jobClaim.value!.owner, SyncClock.localDeviceId(home));
      expect(b.jobClaim.value!.generation, 2);
      expect(mobile.asked, isNotEmpty);
    });

    test('heard of no more (off, or on another network): nothing runs of '
        'itself, and a start of the lawyer\'s here comes after it', () async {
      final mobile = _Mobile();
      final b = atHome(mobile);
      final office = runningAtOffice(ago: const Duration(minutes: 10));
      await b.mergeJob(office);
      expect(b.jobElsewhere, isTrue);
      expect(b.jobRunningElsewhere(), isFalse);
      await b.connectedForTesting(PortalChannel.uyapMobile);
      await pumpEventQueue();
      expect(mobile.asked, isEmpty);
      await b.startSetup(PortalChannel.uyapMobile);
      expect(b.job.value!.done, isTrue);
      expect(b.jobElsewhere, isFalse);
      // Where the two meet, this one stands.
      final there = UyapJobClaim.fromJson(office)!;
      expect(UyapJobClaim.pick(there, b.jobClaim.value!), b.jobClaim.value);
    });

    test('taken over on the other while it runs here, it stops at its next '
        'step and writes nothing more', () async {
      final office = _Mobile();
      final (a, b) = pair(office, _Mobile());
      office.onParties = (_) async {
        office.onParties = null;
        await b.takeOverJob();
        await pumpEventQueue();
      };
      await a.startSetup(PortalChannel.uyapMobile);
      expect(office.asked.where((x) => x.startsWith('parties')).length, 1);
      expect(office.asked.where((x) => x.startsWith('documents')), isEmpty);
      expect(a.jobElsewhere, isTrue);
      expect(a.jobClaim.value!.owner, SyncClock.localDeviceId(home));
      expect(a.jobClaim.value!.ownerName, 'Ev bilgisayarı');
      // The parties that came after the job left are not kept here.
      for (final key in [hukuk, icra]) {
        expect(
          sections(key)[(CaseSection.parties, PortalChannel.uyapMobile)],
          isNull,
        );
      }
    });

    test('let go of on its owner, it is let go of on the other; an older '
        'word does not bring it back', () async {
      final (a, b) = pair(_Mobile(), _Mobile());
      await a.startSetup(PortalChannel.uyapMobile);
      await pumpEventQueue();
      expect(b.job.value!.done, isTrue);
      final before = a.jobExport();
      await a.dropJob();
      await pumpEventQueue();
      expect(a.job.value, isNull);
      expect(b.job.value, isNull);
      expect(await b.mergeJob(before), isFalse);
      expect(b.job.value, isNull);
    });

    test('a job kept before jobs had owners is this device\'s, and goes on '
        'here', () async {
      db.setMeta(
        'uyap_job',
        UyapJob(
          kind: UyapJobKind.setup,
          channel: PortalChannel.uyapMobile,
          stage: UyapJobStage.list,
          started: DateTime.now(),
          stopped: UyapJobStop.session,
        ).encode(),
      );
      final mobile = _Mobile();
      final sync = syncOf(_Web()..on = false, mobile);
      await sync.resumeJob();
      expect(sync.job.value!.done, isTrue);
      expect(sync.jobClaim.value!.owner, SyncClock.localDeviceId(db));
      expect(sync.jobClaim.value!.generation, 1);
      expect(mobile.asked, isNotEmpty);
    });
  });

  // docs/uyap-otomatik-okuma-tek-cihaz.md: a channel another own computer
  // reads of itself is not read of itself here.
  group('reading of itself, left to another own computer', () {
    PortalSync withReader(
      _Mobile mobile, {
      _Web? web,
      String? Function(PortalChannel)? reader,
    }) {
      // Turned on as the lawyer turns it on: kept, and read back at start.
      db.setMeta(PortalSync.autoKey, '1');
      final sync = PortalSync(
        web: web ?? (_Web()..on = false),
        mobile: mobile,
        database: () async => db,
        autoReader: reader,
      )..autoFetch = true;
      addTearDown(sync.dispose);
      return sync;
    }

    Future<void> settle(bool Function() done) async {
      for (var i = 0; i < 100 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    String? office(PortalChannel c) =>
        c == PortalChannel.uyapMobile ? 'Ofis bilgisayarı' : null;

    test('what is due is not read on the channel the other reads; read when '
        'none does', () async {
      final left = _Mobile();
      withReader(left, reader: office).readDueForTesting();
      await settle(() => left.hearingsAsked > 0);
      expect(left.hearingsAsked, 0);

      final mine = _Mobile();
      withReader(mine).readDueForTesting();
      await settle(() => mine.hearingsAsked > 0);
      expect(mine.hearingsAsked, greaterThan(0));
    });

    test('connected, the channel the other reads is not read, nor the '
        'notifications when it is the only one here', () async {
      final mobile = _Mobile();
      final sync = withReader(mobile, reader: office);
      await sync.connectedForTesting(PortalChannel.uyapMobile);
      await settle(() => mobile.hearingsAsked > 0 || mobile.noticesAsked > 0);
      expect(mobile.hearingsAsked, 0);
      expect(mobile.noticesAsked, 0);
      // None reading it elsewhere, connecting reads both.
      final alone = _Mobile();
      await withReader(alone).connectedForTesting(PortalChannel.uyapMobile);
      await settle(() => alone.hearingsAsked > 0 && alone.noticesAsked > 0);
      expect(alone.hearingsAsked, greaterThan(0));
      expect(alone.noticesAsked, greaterThan(0));
    });

    test('a channel here the other does not read keeps the notifications '
        'read here', () async {
      final mobile = _Mobile();
      final sync = withReader(mobile, web: _Web(), reader: office);
      await sync.connectedForTesting(PortalChannel.uyapMobile);
      await settle(() => mobile.noticesAsked > 0);
      expect(mobile.hearingsAsked, 0);
      expect(mobile.noticesAsked, greaterThan(0));
    });

    test('what the lawyer asks for is asked here all the same', () async {
      final mobile = _Mobile();
      final sync = withReader(mobile, reader: office);
      await sync.syncMobile(full: true);
      expect(mobile.hearingsAsked, greaterThan(0));
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

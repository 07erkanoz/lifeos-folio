// How much Folio asks of UYAP after the first setup (docs/uyap-hedef-
// harita.md): the real sync over two counting portals that hold a portfolio
// of the size measured on a lawyer's disk (562 open cases). Each figure is
// printed; the rules that must hold are asserted.
import 'dart:io';

import 'package:evrak_convert/services/portal/case_sections.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/uyap/uyap_case_panel_controller.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_enforcement.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// One court of the portfolio and its open cases.
class _Court {
  _Court(this.jurisdiction, this.kind, this.id, this.name, int count)
    : numbers = [for (var i = 1; i <= count; i++) '2025/${100 + i}'];
  final int jurisdiction;
  final String kind;
  final String id;
  final String name;
  final List<String> numbers;
}

/// 240 hukuk, 250 icra, 40 ceza, 10 idari cases; 12 investigations at
/// three prosecutors' offices; 10 Yargıtay cases in two chambers.
final _courts = [
  for (var i = 1; i <= 20; i++)
    _Court(1, 'HUKUK', 'h$i', 'Antalya $i. Asliye Hukuk Mahkemesi', 12),
  for (var i = 1; i <= 10; i++)
    _Court(2, 'ICRA', 'i$i', 'Antalya $i. İcra Dairesi', 25),
  for (var i = 1; i <= 5; i++)
    _Court(0, 'CEZA', 'c$i', 'Antalya $i. Asliye Ceza Mahkemesi', 8),
  for (var i = 1; i <= 2; i++)
    _Court(6, 'IDARI', 'd$i', 'Antalya $i. İdare Mahkemesi', 5),
];
final _offices = [
  for (var i = 1; i <= 3; i++)
    _Court(3, '', 's$i', 'Savcılık $i Cumhuriyet Başsavcılığı', 4),
];
final _chambers = [
  for (var i = 1; i <= 2; i++)
    _Court(-1, '', 'y$i', 'Yargıtay $i. Hukuk Dairesi', 5),
];

class _Counter {
  final asked = <String, int>{};
  void add(String what) => asked[what] = (asked[what] ?? 0) + 1;
  int get total => asked.values.fold(0, (a, b) => a + b);
  Map<String, int> snapshot() => {...asked};
}

class _Web extends UyapWebService {
  _Web(this.count) : super.forTesting() {
    session.value = UyapSession(
      user: 'DENİZ KAYA',
      since: DateTime.now(),
      route: UyapLoginRoute.tray,
    );
  }
  final _Counter count;

  @override
  bool get connected => true;

  static UyapCase _case(_Court c, String n) =>
      UyapCase('w-${c.id}-$n', n, c.id, c.name);

  @override
  Future<List<UyapOption>> courtTypes(String jurisdiction) async {
    count.add('web courtTypes');
    return [
      for (final k in {
        for (final c in _courts)
          if ('${c.jurisdiction}' == jurisdiction) c.kind,
      })
        UyapOption(k, k),
    ];
  }

  @override
  Future<List<UyapOption>> courts(
    String jurisdiction,
    String courtType, {
    bool closed = false,
  }) async {
    count.add('web courts');
    return closed
        ? const []
        : [
            for (final c in _courts)
              if (c.kind == courtType) UyapOption(c.id, c.name),
          ];
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
    count.add(
      year == null ? 'web casePage (liste)' : 'web casePage (dosya bul)',
    );
    if (closed) return const UyapCasePage([], 0);
    final cases = [
      for (final c in _courts)
        if (c.kind == courtType && (court.id.isEmpty || court.id == c.id))
          for (final n in c.numbers)
            if (year == null || n == '$year/$number') _case(c, n),
    ];
    return UyapCasePage(cases, cases.length);
  }

  @override
  Future<List<UyapOption>> provinces() async {
    count.add('web provinces');
    return [for (var i = 1; i <= 81; i++) UyapOption('$i', 'İl $i')];
  }

  @override
  Future<List<UyapOption>> prosecutorOffices(String province) async {
    count.add('web prosecutorOffices');
    return province == '7'
        ? [for (final o in _offices) UyapOption(o.id, o.name)]
        : const [];
  }

  @override
  Future<UyapCasePage> prosecutorCases(
    UyapOption office, {
    bool closed = false,
    int pageNumber = 1,
  }) async {
    count.add('web prosecutorCases');
    if (closed) return const UyapCasePage([], 0);
    final cases = [
      for (final o in _offices)
        if (o.id == office.id)
          for (final n in o.numbers) _case(o, n),
    ];
    return UyapCasePage(cases, cases.length);
  }

  @override
  Future<List<UyapOption>> chambers(String jurisdiction) async {
    count.add('web chambers');
    return jurisdiction == 'yargitay'
        ? [for (final c in _chambers) UyapOption(c.id, c.name)]
        : const [];
  }

  @override
  Future<List<UyapCase>> chamberCases(
    String jurisdiction,
    UyapOption chamber,
  ) async {
    count.add('web chamberCases');
    return [
      for (final c in _chambers)
        if (c.id == chamber.id)
          for (final n in c.numbers) _case(c, n),
    ];
  }

  @override
  Future<List<Map<String, Object?>>> hearingRows(
    DateTime from,
    DateTime to,
  ) async {
    count.add('web hearingRows');
    return const [];
  }

  @override
  Future<List<Map<String, Object?>>> noticeRows(
    DateTime from,
    DateTime to,
  ) async {
    count.add('web noticeRows');
    return const [];
  }

  @override
  Future<UyapCasePermissions> permissions(UyapCase target) async {
    count.add('web permissions');
    final icra = target.courtName.contains('İcra');
    return UyapCasePermissions(icra ? 2 : 1, {
      'ayrinti_bilgileri',
      'taraf_bilgileri',
      'evrak_bilgileri',
      'tahsilat_reddiyat_bilgileri',
      if (icra) 'hesap_bilgileri',
      if (icra) 'borclu_bilgileri',
    });
  }

  @override
  Future<UyapCaseDetails> caseDetails(UyapCase target) async {
    count.add('web caseDetails');
    return const UyapCaseDetails(kind: 'Alacak');
  }

  @override
  Future<List<UyapParty>> parties(UyapCase target) async {
    count.add('web parties');
    return const [
      UyapParty('AYŞE KARACA', 'Davacı', 'DENİZ KAYA', 'Kişi'),
      UyapParty('BERK İNŞAAT LTD. ŞTİ.', 'Davalı', 'MURAT ER', 'Kurum'),
    ];
  }

  @override
  Future<UyapCaseDocuments> caseDocuments(
    UyapCase target, {
    void Function(int page, int pages)? onPage,
  }) async {
    count.add('web caseDocuments');
    return const UyapCaseDocuments([]);
  }

  @override
  Future<UyapCaseMoney> caseMoney(UyapCase target, int typeCode) async {
    count.add('web caseMoney');
    return const UyapCaseMoney(collected: 10);
  }

  @override
  Future<List<UyapAccountLine>> accountLines(UyapCase target) async {
    count.add('web accountLines');
    return const [UyapAccountLine(1, 'Asıl alacak', '10.000,00')];
  }

  @override
  Future<List<UyapDebtor>> debtors(UyapCase target) async {
    count.add('web debtors');
    return const [UyapDebtor(id: 'd1', name: 'SELİN AKSOY')];
  }
}

class _Mobile extends UyapMobileApi {
  _Mobile(this.count) : super.forTesting(Uri.parse('http://127.0.0.1:9/'));
  final _Counter count;

  @override
  bool get connected => true;

  static Map<String, Object?> _row(_Court c, String n) => {
    'dosyaId': 'm-${c.id}-$n',
    'dosyaNo': n,
    'birimAdi': c.name,
    'dosyaDurumAciklama': 'Açık',
  };

  @override
  Future<List<Map<String, Object?>>> unitTypes(int type) async {
    count.add('mobil unitTypes');
    return [
      for (final k in {
        for (final c in _courts)
          if (c.jurisdiction == type) c.kind,
      })
        {'tablo': k},
    ];
  }

  @override
  Future<List<Map<String, Object?>>> courts(
    int type,
    String unitKind, {
    required bool closed,
  }) async {
    count.add('mobil courts');
    return closed
        ? const []
        : [
            for (final c in _courts)
              if (c.kind == unitKind)
                {'birimId': 'm${c.id}', 'birimAdi': c.name},
          ];
  }

  @override
  Future<List<Map<String, Object?>>> cases(
    int type,
    String unitKind,
    String court, {
    required bool closed,
  }) async {
    count.add('mobil cases');
    return closed
        ? const []
        : [
            for (final c in _courts)
              if ('m${c.id}' == court)
                for (final n in c.numbers) _row(c, n),
          ];
  }

  @override
  Future<List<Map<String, Object?>>> findCase(
    int type,
    String unitKind,
    String court, {
    required String year,
    required String sequence,
    required bool closed,
  }) async {
    count.add('mobil findCase');
    return [
      for (final c in _courts)
        if ('m${c.id}' == court)
          for (final n in c.numbers)
            if (n == '$year/$sequence') _row(c, n),
    ];
  }

  @override
  Future<List<Map<String, Object?>>> danistayChambers() async {
    count.add('mobil danistayChambers');
    return const [];
  }

  @override
  Future<List<Map<String, Object?>>> provinces() async {
    count.add('mobil provinces');
    return [
      for (var i = 1; i <= 81; i++) {'il': '$i', 'ad': 'İL $i'},
    ];
  }

  @override
  Future<List<Map<String, Object?>>> prosecutorOffices(String code) async {
    count.add('mobil prosecutorOffices');
    return code == '7'
        ? [
            for (final o in _offices) {'birimId': o.id, 'birimAdi': o.name},
          ]
        : const [];
  }

  @override
  Future<List<Map<String, Object?>>> prosecutorCases(
    String office, {
    required bool closed,
  }) async {
    count.add('mobil prosecutorCases');
    return closed
        ? const []
        : [
            for (final o in _offices)
              if (o.id == office)
                for (final n in o.numbers) _row(o, n),
          ];
  }

  @override
  Future<List<Map<String, Object?>>> hearingRows(
    DateTime from,
    DateTime to,
  ) async {
    count.add('mobil hearingRows');
    return const [];
  }

  @override
  Future<List<Map<String, Object?>>> noticeRows({String? after}) async {
    count.add('mobil noticeRows');
    return const [];
  }

  @override
  Future<List<Map<String, Object?>>> parties(
    String caseId, {
    String? caseType,
  }) async {
    count.add('mobil parties');
    return [
      {'adi': 'AYŞE KARACA', 'rol': 'Davacı', 'vekil': '', 'kisiKurum': ''},
    ];
  }

  @override
  Future<Map<String, Object?>> caseDocuments(String caseId) async {
    count.add('mobil caseDocuments');
    return const {'tumEvraklar': {}, 'son20Evrak': []};
  }
}

void main() {
  late Directory root;
  late PortalDatabase db;
  late UyapCaseStore real;
  final report = StringBuffer();

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('folio-uyap-butce-');
    db = PortalDatabase.memory();
    real = UyapCaseStore.instance;
    UyapCaseStore.instance = UyapCaseStore(
      directory: Directory('${root.path}/destek'),
      settings: UyapSettings(
        directory: Directory('${root.path}/destek'),
        home: '${root.path}/ev',
      ),
    );
    PortalSync.caseGap = Duration.zero;
  });
  tearDownAll(() async {
    UyapCaseStore.instance = real;
    db.dispose();
    await root.delete(recursive: true);
    // ignore: avoid_print
    print(report);
  });

  final count = _Counter();
  late PortalSync sync;

  /// What [step] asked of UYAP, by channel and kind, written to the report.
  Future<int> measure(String name, Future<void> Function() step) async {
    final before = count.snapshot();
    await step();
    final diff = <String, int>{
      for (final e in count.asked.entries)
        if (e.value - (before[e.key] ?? 0) > 0)
          e.key: e.value - (before[e.key] ?? 0),
    };
    final total = diff.values.fold(0, (a, b) => a + b);
    final web = diff.entries
        .where((e) => e.key.startsWith('web'))
        .fold(0, (a, e) => a + e.value);
    report.writeln(
      '\n## $name: $total istek (web $web, mobil ${total - web}) · '
      '~${(total * 1.5 / 60).toStringAsFixed(0)} dk (istek başına 1,5 sn)',
    );
    for (final e in diff.entries.toList()..sort((a, b) => b.value - a.value)) {
      report.writeln('  ${e.value.toString().padLeft(5)}  ${e.key}');
    }
    return total;
  }

  /// Today's count of cases freshened of themselves, from nought: a new
  /// day's. The count is kept by the calendar's day, which [age] does not
  /// move.
  void newDay() {
    final now = DateTime.now();
    db.setMeta('web_enriched_count:${now.year}-${now.month}-${now.day}', '0');
  }

  /// Every kept time pushed back [by]: the days going by.
  void age(Duration by) {
    for (final c in db.cases().values) {
      for (final s in db.sections(c.key)) {
        if (s.succeeded == null) continue;
        db.saveSections(c.key, s.channel, [
          SectionOutcome(s.section, s.result, partial: s.partial),
        ], at: s.succeeded!.subtract(by));
      }
    }
    for (final key in [
      'portfolio_at',
      'portfolio_web_only_at',
      'hearings_at:${PortalChannel.uyapWeb.name}',
      'hearings_at:${PortalChannel.uyapMobile.name}',
      PortalSync.noticesAtKey,
      PortalSync.enrichedKey,
      '${PortalSync.enrichedKey}_try',
    ]) {
      if (DateTime.tryParse(db.meta(key) ?? '') case final at?) {
        db.setMeta(key, at.subtract(by).toIso8601String());
      }
    }
  }

  test('setup on UYAP Mobil, the web connected', () async {
    sync = PortalSync(
      web: _Web(count),
      mobile: _Mobile(count),
      database: () async => db,
    );
    final n = await measure(
      'Kurulum (UYAP Mobil: liste, taraflar, evrak listeleri)',
      () => sync.startSetup(PortalChannel.uyapMobile),
    );
    expect(sync.job.value!.done, isTrue);
    expect(n, greaterThan(0));
    report.writeln(
      '  açık dosya: ${db.cases().values.where((c) => !isClosedStatus(c.status?.value)).length}',
    );
  });

  test('the web\'s completion', () async {
    await measure(
      'Web tamamlaması (Yargıtay; künye, taraf, para, hesap, borçlu)',
      sync.startWebCompletion,
    );
    expect(sync.job.value!.done, isTrue);
  });

  test(
    'the same day, the setting off: connecting, pages, cases opened',
    () async {
      final asked = await measure(
        'Aynı gün, kendiliğinden okuma kapalı: 20 dosya sayfası açıldı',
        () async {
          for (final c in db.cases().values.take(20)) {
            final panel = UyapCasePanelController(
              web: sync.web,
              mobile: sync.mobile,
              sync: sync,
              pause: Duration.zero,
            );
            await panel.attach(linkOf(c));
            await sync.readOpened(panel, c.key);
            panel.dispose();
          }
        },
      );
      expect(asked, 0, reason: 'everything read today');
    },
  );

  test('two days on, the setting off: cases opened', () async {
    age(const Duration(days: 2));
    final asked = await measure(
      '2 gün sonra, kapalı: 20 dosya sayfası açıldı (eskiyen bölümler)',
      () async {
        // Other cases than those opened this morning: a case is not read
        // again within three minutes, and these were.
        for (final c in db.cases().values.skip(40).take(20)) {
          final panel = UyapCasePanelController(
            web: sync.web,
            mobile: sync.mobile,
            sync: sync,
            pause: Duration.zero,
          );
          await panel.attach(linkOf(c));
          await sync.readOpened(panel, c.key);
          panel.dispose();
        }
      },
    );
    report.writeln('  dosya başına ~${(asked / 20).toStringAsFixed(1)} istek');
  });

  test('the lawyer\'s own buttons', () async {
    await measure('Duruşmaları yenile (ajanda)', sync.refreshHearings);
    await measure('Bildirimleri yenile', () => sync.syncNotices(force: true));
    age(const Duration(hours: 4));
    await measure(
      'Portföyü yenile (iki kanal)',
      () => sync.syncPortfolio(full: true),
    );
  });

  test('the setting on: a day, then a week on', () async {
    await sync.setAutoFetch(true);
    // What setAutoFetch started settles.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    age(const Duration(days: 1));
    await measure('Kendiliğinden okuma açık: sıradan bir gün', () async {
      await sync.syncNotices(auto: true);
      await Future.wait([sync.syncWeb(), sync.syncMobile()]);
      await sync.enrichOnWeb();
    });
    age(const Duration(days: 7));
    await measure(
      'Kendiliğinden okuma açık: bir hafta sonraki gün (haftalık portföy + '
      'eskiyen web bölümleri, günde açık dosyaların yedide biri)',
      () async {
        await sync.syncNotices(auto: true);
        await Future.wait([sync.syncWeb(), sync.syncMobile()]);
        await sync.enrichOnWeb();
      },
    );
    // The week after: each day a seventh, none left out.
    for (var day = 2; day <= 8; day++) {
      age(const Duration(days: 1));
      newDay();
      final n = await measure(
        'Kendiliğinden okuma açık: sonraki haftanın $day. günü',
        () async {
          await Future.wait([sync.syncWeb(), sync.syncMobile()]);
          await sync.enrichOnWeb();
        },
      );
      expect(n, lessThan(700), reason: 'day $day: spread, not one burst');
    }
    await sync.setAutoFetch(false);
    sync.dispose();
  });
}

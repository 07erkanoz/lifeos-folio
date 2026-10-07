// Pictures of the office pages (the first page, the agenda, UETS, UYAP
// Dosyalarım and a case with a document open), drawn from invented cases
// with the app's real fonts, for lifeos.com.tr. Not part of the test suite:
//
//   flutter test tool/screenshots/office_screens_test.dart
//
// Pictures land in tool/screenshots/out/. Every name, court and number in
// them is made up.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:ui' as ui;

import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_deadline.dart';
import 'package:evrak_convert/services/portal/portal_hearing.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/portal/uyap_notice.dart';
import 'package:evrak_convert/services/uets/notice_deadlines.dart';
import 'package:evrak_convert/services/uets/notice_matcher.dart';
import 'package:evrak_convert/services/uets/uets_api.dart';
import 'package:evrak_convert/services/uyap/uyap_case_links.dart';
import 'package:evrak_convert/services/uyap/uyap_case_panel_controller.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/agenda/agenda_page.dart';
import 'package:evrak_convert/ui/agenda/uets_page.dart';
import 'package:evrak_convert/ui/desktop/desktop_home.dart';
import 'package:evrak_convert/ui/portfolio/case_detail_page.dart';
import 'package:evrak_convert/ui/portfolio/portfolio_page.dart';
import 'package:evrak_convert/ui/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../../test/support/pdfium.dart';

const logical = Size(1440, 900);
const phone = Size(390, 844);
const pixelRatio = 1.5;
final _frame = GlobalKey();

const _fallbacks = [
  ('FallbackSymbols', '/usr/share/fonts/TTF/DejaVuSans.ttf'),
  ('FallbackEmoji', '/usr/share/fonts/noto/NotoColorEmoji.ttf'),
];

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
      );
    }
    await loader.load();
  }

  for (final name in ['FlutterTest', 'Ahem']) {
    await family(name, [
      for (final style in ['Regular', 'Bold'])
        'fonts/pdf/LiberationSans-$style.ttf',
    ]);
  }
  for (final name in ['Sans', 'Serif', 'Mono']) {
    await family('Liberation$name', [
      for (final style in ['Regular', 'Bold', 'Italic', 'BoldItalic'])
        'fonts/pdf/Liberation$name-$style.ttf',
    ]);
  }
  // What the system supplies for a symbol the text font lacks (⏱, ↻):
  // flutter_tester falls back on nothing, so these are named instead.
  for (final (name, file) in _fallbacks) {
    if (File(file).existsSync()) await family(name, [file]);
  }
  await family('Consolas', [
    for (final style in ['Regular', 'Bold'])
      'fonts/pdf/LiberationMono-$style.ttf',
  ]);
  final flutter = File(Platform.resolvedExecutable).parent.parent.parent.parent;
  final material = '${flutter.path}/artifacts/material_fonts';
  await family('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
  await family('Roboto', [
    for (final style in ['Regular', 'Medium', 'Bold'])
      '$material/Roboto-$style.ttf',
  ]);
}

/// Lets both clocks move: file and database work on the real one, timers
/// on the fake one.
Future<void> _settle(
  WidgetTester tester, {
  bool Function()? ready,
  int rounds = 30,
}) async {
  for (var i = 0; i < rounds && !(ready?.call() ?? false); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Text with no family at all (a button whose own text style names none)
/// is drawn by flutter_tester in its stand-in font of boxes, whatever is
/// loaded; on a computer it is the system's font. Liberation Sans, the
/// theme's, is put in for the picture, and the symbols' fonts behind each.
void _fixFonts(WidgetTester tester) {
  for (final p in tester.allRenderObjects.whereType<RenderParagraph>()) {
    final span = p.text;
    final style = span.style;
    if (span is! TextSpan || style == null) continue;
    if (style.fontFamilyFallback?.isNotEmpty ?? false) continue;
    p.text = TextSpan(
      text: span.text,
      children: span.children,
      style: style.copyWith(
        fontFamily: style.fontFamily ?? 'LiberationSans',
        fontFamilyFallback: [for (final (name, _) in _fallbacks) name],
      ),
      recognizer: span.recognizer,
      semanticsLabel: span.semanticsLabel,
      locale: span.locale,
      spellOut: span.spellOut,
    );
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  await _settle(tester, rounds: 8);
  _fixFonts(tester);
  await tester.pump();
  final boundary =
      _frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  final out = File('tool/screenshots/out/$name.png');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(bytes!);
}

Widget _app(Widget home) => RepaintBoundary(
  key: _frame,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    locale: const Locale('tr'),
    supportedLocales: const [Locale('tr')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: home,
  ),
);

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * pixelRatio;
  tester.view.devicePixelRatio = pixelRatio;
}

// The office: one lawyer's invented cases.

const lawyer = 'Av. Deniz Kaya';

/// A weekday morning: today, or the Monday after a weekend.
final DateTime today = () {
  final n = DateTime.now();
  var d = DateTime(n.year, n.month, n.day);
  while (d.weekday > DateTime.friday) {
    d = d.add(const Duration(days: 1));
  }
  return d;
}();
final DateTime now = today.add(const Duration(hours: 8, minutes: 20));
DateTime day(int offset, [int hour = 0, int minute = 0]) =>
    DateTime(today.year, today.month, today.day + offset, hour, minute);
String two(int v) => v.toString().padLeft(2, '0');
String dmy(DateTime d) => '${two(d.day)}.${two(d.month)}.${d.year}';

class _Case {
  const _Case(
    this.number,
    this.court,
    this.code,
    this.type,
    this.ours,
    this.others, {
    this.status = 'Açık',
    this.opened = '12.03.2024',
  });
  final String number, court, code, type, status, opened;
  final List<UyapParty> ours, others;
  String get key => caseKey(number, court);
}

const _civil = 'Antalya 3. Asliye Hukuk Mahkemesi';

final _cases = [
  const _Case(
    '2024/318',
    _civil,
    '1',
    'Alacak (İtirazın İptali)',
    [UyapParty('AYŞE KARACA', 'Davacı', lawyer, 'Kişi')],
    [UyapParty('BERK İNŞAAT LTD. ŞTİ.', 'Davalı', 'Av. Murat Er', 'Kurum')],
    opened: '12.03.2024',
  ),
  const _Case(
    '2025/4410',
    'Antalya 6. İcra Dairesi',
    '2',
    'İlamsız Takip',
    [UyapParty('MERT YILDIZ', 'Alacaklı', lawyer, 'Kişi')],
    [UyapParty('SELİN AKSOY', 'Borçlu', '', 'Kişi')],
    opened: '04.02.2025',
  ),
  const _Case(
    '2025/201',
    'Manavgat 2. Asliye Hukuk Mahkemesi',
    '1',
    'Tazminat (Trafik Kazasından Kaynaklanan)',
    [UyapParty('HAKAN ÖZTÜRK', 'Davacı', lawyer, 'Kişi')],
    [
      UyapParty('KARAYEL SİGORTA A.Ş.', 'Davalı', 'Av. Sevgi Tan', 'Kurum'),
      UyapParty('OSMAN GÜLER', 'Davalı', '', 'Kişi'),
    ],
    opened: '21.01.2025',
  ),
  const _Case(
    '2026/112',
    'Antalya 2. Ağır Ceza Mahkemesi',
    '0',
    'Kasten Yaralama',
    [UyapParty('EMRE ÇELİK', 'Katılan', lawyer, 'Kişi')],
    [UyapParty('TUNA ERDEM', 'Sanık', 'Av. Leyla Acar', 'Kişi')],
    opened: '09.03.2026',
  ),
  const _Case(
    '2025/1876',
    'Antalya 1. İdare Mahkemesi',
    '6',
    'İptal (İmar Para Cezası)',
    [UyapParty('ZEYNEP ARSLAN', 'Davacı', lawyer, 'Kişi')],
    [UyapParty('İL ÇEVRE VE ŞEHİRCİLİK MÜDÜRLÜĞÜ', 'Davalı', '', 'Kurum')],
    opened: '17.11.2025',
  ),
  const _Case(
    '2026/87',
    'Antalya 4. Aile Mahkemesi',
    '1',
    'Boşanma (Anlaşmalı)',
    [UyapParty('ELİF DEMİR', 'Davacı', lawyer, 'Kişi')],
    [UyapParty('CAN DEMİR', 'Davalı', 'Av. Okan Sarı', 'Kişi')],
    opened: '02.02.2026',
  ),
  const _Case(
    '2025/933',
    'Antalya 5. İş Mahkemesi',
    '1',
    'İşçilik Alacağı',
    [UyapParty('MUSTAFA ŞAHİN', 'Davacı', lawyer, 'Kişi')],
    [
      UyapParty(
        'LİMAN TURİZM OTELCİLİK A.Ş.',
        'Davalı',
        'Av. Ece Kurt',
        'Kurum',
      ),
    ],
    opened: '30.06.2025',
  ),
  const _Case(
    '2026/2210',
    'Antalya 9. İcra Dairesi',
    '2',
    'Kambiyo Senetlerine Dayalı Takip',
    [
      UyapParty(
        'DENİZ YAPI MALZEMELERİ LTD. ŞTİ.',
        'Alacaklı',
        lawyer,
        'Kurum',
      ),
    ],
    [UyapParty('OKAN POLAT', 'Borçlu', '', 'Kişi')],
    opened: '14.05.2026',
  ),
  const _Case(
    '2024/1544',
    'Antalya 2. Sulh Hukuk Mahkemesi',
    '1',
    'Kira Alacağı',
    [UyapParty('GÜLAY KOÇ', 'Davacı', lawyer, 'Kişi')],
    [UyapParty('SERKAN AYDIN', 'Davalı', '', 'Kişi')],
    status: 'Kapalı',
    opened: '08.10.2024',
  ),
];

_Case _of(String number) => _cases.firstWhere((c) => c.number == number);

PortalCase _portal(_Case c) {
  final asked = now.toUtc();
  return PortalCase(
    key: c.key,
    number: c.number,
    court: c.court,
    status: Observed(c.status, PortalChannel.uyapMobile, asked),
    details: Observed(
      {
        'yargiTuru': c.code,
        'tur': c.code == '2' ? 'İcra Dosyası' : 'Dava Dosyası',
        'davaTuru': c.type,
        'acilis': c.opened,
      },
      PortalChannel.uyapMobile,
      asked,
      complete: false,
    ),
  );
}

PortalHearing _hearing(String number, DateTime at, String kind) {
  final c = _of(number);
  final asked = now.toUtc();
  return PortalHearing.create(
    number: c.number,
    court: c.court,
    at: at,
    channel: PortalChannel.uyapWeb,
    id: '${c.number}-${at.millisecondsSinceEpoch}',
    kind: Observed(kind, PortalChannel.uyapWeb, asked),
    parties: Observed(
      [
        for (final p in [...c.ours, ...c.others]) {'adi': p.name},
      ],
      PortalChannel.uyapWeb,
      asked,
    ),
  );
}

/// The portal database every page reads: the cases, a fortnight of
/// hearings, the deadlines, UETS's notices and UYAP's notifications.
PortalDatabase _office() {
  final db = PortalDatabase.memory();
  db.mergeCases(
    [for (final c in _cases) _portal(c)],
    portfolio: true,
    baseline: true,
  );
  final week = today.subtract(Duration(days: today.weekday - 1));
  int at(int weekday) =>
      week.add(Duration(days: weekday - 1)).difference(today).inDays;
  db.mergeHearings(PortalChannel.uyapWeb, day(-30), day(90), [
    _hearing('2025/1876', day(at(1), 10, 30), 'Duruşma'),
    _hearing('2026/87', day(at(2), 13, 45), 'Duruşma'),
    _hearing('2024/318', day(0, 9, 35), 'Ön inceleme duruşması'),
    _hearing('2025/933', day(0, 14, 10), 'Tanık dinlenmesi'),
    _hearing('2025/201', day(at(4), 10, 15), 'Bilirkişi incelemesi'),
    _hearing('2026/112', day(at(4), 11, 40), 'Duruşma'),
    _hearing('2025/201', day(at(5) + 21, 9, 30), 'Duruşma'),
    _hearing('2026/87', day(at(5), 9, 20), 'Duruşma'),
    _hearing('2026/112', day(at(1) + 9, 11, 0), 'Duruşma'),
  ], complete: true);
  AgendaItem item(
    String id,
    String kind,
    String title,
    DateTime when, {
    String? number,
    bool allDay = true,
    String body = '',
  }) => AgendaItem(
    id: id,
    kind: kind,
    title: title,
    body: body,
    at: when,
    allDay: allDay,
    caseKey: number == null ? null : _of(number).key,
    updated: now,
  );
  for (final i in [
    item(
      'd1',
      'deadline',
      'Delil listesi sunma süresi',
      day(0),
      number: '2025/933',
    ),
    item(
      'd2',
      'deadline',
      'Bilirkişi raporuna itiraz',
      day(2),
      number: '2025/201',
    ),
    item(
      'd3',
      'deadline',
      'Cevaba cevap dilekçesi',
      day(6),
      number: '2025/1876',
    ),
    item(
      'd4',
      'deadline',
      'Gider avansı tamamlama',
      day(9),
      number: '2024/318',
    ),
    item(
      't1',
      'task',
      'Tanık listesini hazırla',
      day(at(3), 16, 0),
      number: '2025/201',
      allDay: false,
    ),
    item(
      't2',
      'task',
      'Müvekkille görüşme',
      day(at(2), 16, 30),
      number: '2026/87',
      allDay: false,
    ),
  ]) {
    db.saveAgenda(i);
  }

  // UETS: what came by e-notification, two of them unread.
  UetsMessage notice(
    String id,
    String number,
    String what,
    DateTime sent, {
    DateTime? read,
  }) {
    final c = _of(number);
    return UetsMessage(
      id: id,
      subject: '${c.court} [${c.number}] [$what]',
      sender: c.court,
      sent: sent,
      read: read,
      barcode: '1${id.hashCode.abs().toString().padLeft(9, '7')}',
    );
  }

  db.mergeNotices([
    notice('m1', '2024/318', 'Bilirkişi Raporu', day(-4, 10, 12)),
    notice('m2', '2024/1544', 'Gerekçeli Karar', day(-2, 15, 40)),
    notice(
      'm3',
      '2025/4410',
      'Haciz İhbarnamesi',
      day(-8, 9, 5),
      read: day(-7, 9),
    ),
    notice(
      'm4',
      '2025/1876',
      'Cevap Dilekçesi',
      day(-6, 11, 30),
      read: day(-5, 10),
    ),
    notice(
      'm5',
      '2026/87',
      'Duruşma Davetiyesi',
      day(-15, 14, 2),
      read: day(-14, 9),
    ),
    notice('m6', '2025/933', 'Ara Karar', day(-1, 16, 20)),
    notice(
      'm7',
      '2026/2210',
      'Ödeme Emri',
      day(-19, 10, 0),
      read: day(-18, 11),
    ),
  ]);
  db.saveManifest('m1', [(id: 'p1', name: '(1)BilirkisiRaporu.pdf', mime: '')]);
  db.saveManifest('m2', [(id: 'p2', name: '(1)GerekceliKarar.pdf', mime: '')]);
  db.saveManifest('m4', [(id: 'p4', name: '(1)CevapDilekcesi.pdf', mime: '')]);
  db.saveEnvelope(
    NoticeEnvelope(
      noticeId: 'm1',
      state: 'indirildi',
      folder: '/home/deniz/UETS/Antalya 3. Asliye Hukuk',
      envelopePath:
          '/home/deniz/UETS/Antalya 3. Asliye Hukuk/Tebligat zarfı.pdf',
      envelopeText:
          'Dosyaya sunulan bilirkişi raporunun bir örneği ekte gönderilmiştir. '
          'Rapora karşı itirazlarınızı tebliğden itibaren iki hafta içinde '
          'bildirmeniz, aksi halde rapora itiraz hakkından vazgeçmiş '
          'sayılacağınız ihtar olunur.',
      attachments: const [
        (
          name: 'BilirkisiRaporu.pdf',
          path: '/home/deniz/UETS/Antalya 3. Asliye Hukuk/BilirkisiRaporu.pdf',
        ),
      ],
      fetchedAt: day(-4, 10, 20),
    ),
  );
  // A notice of a case not in the portfolio: not tied.
  db.mergeNotices([
    UetsMessage(
      id: 'm8',
      subject: 'Muratpaşa 1. Sulh Ceza Hakimliği [2026/1408] [Karar]',
      sender: 'Muratpaşa 1. Sulh Ceza Hakimliği',
      sent: day(-11, 13, 25),
      read: day(-10, 9, 40),
      barcode: '1749520311',
    ),
  ]);
  // Whose each deadline is: the parties, and the lawyer's own name.
  NoticeDeadlineContext.parties = {
    for (final c in _cases)
      c.key: [
        for (final t in [...c.ours, ...c.others])
          (rol: t.role, vekil: t.lawyer),
      ],
  };
  NoticeDeadlineContext.lawyer = 'Deniz Kaya';
  matchNotices(db, now: now);

  // UYAP's notifications.
  UyapNoticeRow web(
    int id,
    String title,
    String body,
    DateTime at, {
    bool read = false,
  }) => UyapNoticeRow(
    source: UyapNoticeSource.web,
    id: '$id',
    title: title,
    body: body,
    sentAt: at,
    remoteRead: read,
  );
  db.saveUyapNotices([
    web(
      1,
      'Bilirkişi Raporu Kaydedilmesi',
      'Manavgat 2. Asliye Hukuk Mahkemesi birimi, 2025/201 dosyasında '
          'bilirkişi raporu kaydedilmiştir.',
      day(0, 8, 12),
    ),
    web(
      2,
      'İcra Dosyası Borç Tahsilatı',
      "Antalya 6. İcra Dairesi'nin 2025/4410 Esas sayılı dosyasında "
          '18.450,00 TL tahsilat yapılmıştır.',
      day(-1, 17, 42),
    ),
    web(
      3,
      'Ara Karar',
      'Antalya 5. İş Mahkemesi Biriminde Bulunan 2025/933 sayılı dosyaya '
          'ara karar eklenmiştir.',
      day(-1, 16, 18),
    ),
    web(
      4,
      'Vekil Kaydı',
      'Antalya 9. İcra Dairesi Biriminde Bulunan 2026/2210 sayılı dosyaya '
          'vekil kaydı yapılmıştır.',
      day(-3, 11),
      read: true,
    ),
  ]);
  return db;
}

/// What the desktop's first page shows of [db], gathered as the home page
/// gathers it.
DesktopHomeOffice _homeOffice(PortalDatabase db) {
  final tomorrow = day(1);
  final notices = db.notices().where((n) => n.message.read == null).toList()
    ..sort(
      (a, b) => (b.message.sent ?? DateTime(0)).compareTo(
        a.message.sent ?? DateTime(0),
      ),
    );
  final unread = [
    for (final n in db.uyapNotices())
      if (!n.read) n,
  ];
  final cases = db.cases();
  return DesktopHomeOffice(
    noticesUnread: unread.length,
    notices: [
      for (final n in unread.take(3))
        (
          notice: n,
          caseLine: switch (cases[n.caseKey]) {
            null => null,
            final c => '${c.number} · ${c.court}',
          },
        ),
    ],
    today: db.hearings(from: today, to: tomorrow),
    next: db.hearings(from: tomorrow, to: day(90)).firstOrNull,
    deadlines: db
        .agenda(from: today, to: day(60))
        .where((i) => i.kind == 'deadline' && !i.done && i.at != null)
        .toList(),
    unread: notices.length,
    newest: notices.firstOrNull?.message,
  );
}

PortalSync _sync(PortalDatabase db) => PortalSync(
  web: UyapWebService.forTesting(),
  mobile: UyapMobileApi.forTesting(Uri.parse('http://127.0.0.1:9/')),
  uets: UetsApi.forTesting(Uri.parse('http://127.0.0.1:9/')),
  database: () async => db,
);

// The case opened, with its documents.

UyapCaseDocument _doc(
  String key,
  String type,
  DateTime at, {
  String sender = 'Antalya 3. Asliye Hukuk Mahkemesi',
  String description = '',
}) => UyapCaseDocument(
  key: key,
  documentId: key,
  caseId: '1',
  type: type,
  number: key,
  approved: '${dmy(at)} ${two(at.hour)}:${two(at.minute)}',
  sender: sender,
  description: description,
);

final _documents = [
  _doc('e01', 'Dava Dilekçesi', day(-570, 10, 4), sender: lawyer),
  _doc('e02', 'Tensip Zaptı', day(-565, 14, 20)),
  _doc('e03', 'Cevap Dilekçesi', day(-530, 16, 2), sender: 'Av. Murat Er'),
  _doc('e04', 'Cevaba Cevap Dilekçesi', day(-515, 11, 45), sender: lawyer),
  _doc(
    'e05',
    'İkinci Cevap Dilekçesi',
    day(-500, 9, 30),
    sender: 'Av. Murat Er',
  ),
  _doc('e06', 'Ön İnceleme Duruşma Zaptı', day(-420, 10, 50)),
  _doc('e07', 'Tanık Listesi', day(-410, 15, 12), sender: lawyer),
  _doc(
    'e08',
    'Müzekkere Cevabı',
    day(-380, 9, 3),
    description: 'Banka hesap kayıtları',
  ),
  _doc('e09', 'Duruşma Zaptı', day(-300, 11, 25)),
  _doc('e10', 'Bilirkişi Görevlendirme Yazısı', day(-295, 13, 40)),
  _doc(
    'e11',
    'Bilirkişi Raporu',
    day(-150, 17, 5),
    sender: 'Mali Müşavir Bilirkişi',
  ),
  _doc(
    'e12',
    'Beyan Dilekçesi',
    day(-140, 10, 30),
    sender: lawyer,
    description: 'Bilirkişi raporuna itiraz',
  ),
  _doc('e13', 'Duruşma Zaptı', day(-60, 12, 5)),
  _doc('e14', 'Ara Karar', day(-12, 15, 30)),
  _doc(
    'e15',
    'Ek Bilirkişi Raporu',
    day(-4, 10, 12),
    sender: 'Mali Müşavir Bilirkişi',
  ),
];

/// A one-page court paper with [lines] of invented text.
Future<Uint8List> _pdf(String title, List<String> lines) async {
  final regular = pw.Font.ttf(
    ByteData.sublistView(
      File('fonts/pdf/LiberationSerif-Regular.ttf').readAsBytesSync(),
    ),
  );
  final bold = pw.Font.ttf(
    ByteData.sublistView(
      File('fonts/pdf/LiberationSerif-Bold.ttf').readAsBytesSync(),
    ),
  );
  final doc = pw.Document();
  final body = pw.TextStyle(font: regular, fontSize: 11.5, lineSpacing: 3);
  final strong = pw.TextStyle(font: bold, fontSize: 11.5);
  pw.Widget field(String k, String v) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(width: 110, child: pw.Text(k, style: strong)),
        pw.Text(': ', style: strong),
        pw.Expanded(child: pw.Text(v, style: body)),
      ],
    ),
  );
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(70, 60, 60, 60),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text('T.C.', style: strong.copyWith(fontSize: 12.5)),
          ),
          pw.Center(
            child: pw.Text('ANTALYA', style: strong.copyWith(fontSize: 12.5)),
          ),
          pw.Center(
            child: pw.Text(
              '3. ASLİYE HUKUK MAHKEMESİ',
              style: strong.copyWith(fontSize: 12.5),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(
              title,
              style: strong.copyWith(fontSize: 13, letterSpacing: 1),
            ),
          ),
          pw.SizedBox(height: 18),
          field('ESAS NO', '2024/318 Esas'),
          field('CELSE TARİHİ', dmy(day(-12))),
          pw.SizedBox(height: 8),
          field('HAKİM', 'Selda Uçar 112233'),
          field('KATİP', 'Burak Ilgaz 445566'),
          pw.SizedBox(height: 8),
          field('DAVACI', 'AYŞE KARACA'),
          field('VEKİLİ', 'Av. DENİZ KAYA'),
          field('DAVALI', 'BERK İNŞAAT LTD. ŞTİ.'),
          field('VEKİLİ', 'Av. MURAT ER'),
          field('DAVA', 'Alacak (İtirazın İptali)'),
          pw.SizedBox(height: 16),
          for (final line in lines)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(
                line,
                style: body,
                textAlign: pw.TextAlign.justify,
              ),
            ),
          pw.Spacer(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              pw.Text('Katip 445566\ne-imzalıdır', style: body),
              pw.Text('Hakim 112233\ne-imzalıdır', style: body),
            ],
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

final _interim = [
  'Açık yargılamaya devam olundu. Davacı vekili Av. Deniz Kaya ile davalı '
      'vekili Av. Murat Er geldi, başka gelen olmadı.',
  'Dosyaya ibraz edilen bilirkişi raporu okundu. Davacı vekili: "Rapor '
      'lehimize olup kabul ediyoruz, ancak faiz başlangıcının hesabı '
      'yönünden ek rapor alınmasını talep ediyoruz" dedi.',
  'Davalı vekili: "Raporda yer alan fatura bedellerinin bir kısmı '
      'ödenmiştir, ödeme belgelerini sunacağız, süre talep ediyoruz" dedi.',
  'Dosya incelendi.',
  'GEREĞİ DÜŞÜNÜLDÜ:',
  '1- Taraf vekillerinin itirazları doğrultusunda dosyanın, kök raporu '
      'düzenleyen mali müşavir bilirkişiye tevdi ile, davalı tarafından '
      'sunulacak ödeme belgeleri ve faiz başlangıç tarihi yönünden '
      'denetime elverişli ek rapor alınmasına,',
  '2- Davalı vekiline ödeme belgelerini sunması için iki haftalık kesin '
      'süre verilmesine, aksi halde bu delile dayanmaktan vazgeçmiş '
      'sayılacağının ihtarına,',
  '3- Ek rapor için 1.500,00 TL bilirkişi ücretinin davacı tarafından '
      'yatırılan gider avansından karşılanmasına,',
  '4- Duruşmanın ${dmy(day(0))} günü saat 09:35\'e bırakılmasına karar '
      'verildi. Açıkça okunup anlatıldı.',
];

const _minutes = [
  'Belirli gün ve saatte açık yargılamaya başlandı. Taraf vekilleri hazır.',
  'Davacı tanıkları dinlendi; beyanları tutanağa geçirildi.',
  'GEREĞİ DÜŞÜNÜLDÜ: Dosyanın hesap uzmanı bilirkişiye tevdiine, '
      'duruşmanın ertelenmesine karar verildi.',
];

const _report = [
  'Sayın mahkemenin ara kararı uyarınca dosya ve ekleri incelenmiş, '
      'taraflar arasındaki cari hesap ilişkisi defter kayıtları üzerinden '
      'değerlendirilmiştir.',
  'Davacının takip tarihi itibarıyla davalıdan 84.320,00 TL asıl alacak '
      'talep edebileceği kanaatine varılmıştır.',
];

Future<UyapCaseStore> _store(Directory root) async {
  final store = UyapCaseStore(
    directory: Directory('${root.path}/destek'),
    settings: UyapSettings(
      directory: Directory('${root.path}/destek'),
      home: '${root.path}/ev',
    ),
  );
  for (final c in _cases) {
    final target = UyapCase('1', c.number, '', c.court);
    final details = UyapCaseDetails(kind: c.type, status: c.status);
    final parties = [...c.ours, ...c.others];
    final own = c.number == '2024/318';
    // The first reading; the second brings the new documents.
    await store.keep(
      target: target,
      details: details,
      parties: parties,
      documents: UyapCaseDocuments(
        own
            ? _documents.take(13).toList()
            : [_doc('${c.number}-1', 'Tensip Zaptı', day(-200, 10))],
      ),
      now: now.subtract(const Duration(days: 3)),
    );
    final fresh = switch (c.number) {
      '2024/318' => _documents,
      '2025/201' => [
        _doc('${c.number}-1', 'Tensip Zaptı', day(-200, 10)),
        _doc('${c.number}-2', 'Bilirkişi Raporu', day(0, 8, 12)),
      ],
      '2025/933' => [
        _doc('${c.number}-1', 'Tensip Zaptı', day(-200, 10)),
        _doc('${c.number}-2', 'Ara Karar', day(-1, 16, 18)),
        _doc('${c.number}-3', 'Duruşma Zaptı', day(-1, 16, 10)),
      ],
      _ => null,
    };
    if (fresh != null) {
      await store.keep(
        target: target,
        details: details,
        parties: parties,
        documents: UyapCaseDocuments(fresh),
        now: now.subtract(const Duration(hours: 1)),
      );
    }
  }
  // Three documents of the case are on this computer.
  var record = (await store.load(_civil, '2024/318'))!;
  for (final (key, title, lines) in [
    ('e14', 'ARA KARAR', _interim),
    ('e13', 'DURUŞMA TUTANAĞI', _minutes),
    ('e11', 'BİLİRKİŞİ RAPORU', _report),
  ]) {
    final d = _documents.firstWhere((d) => d.key == key);
    (record, _) = await store.save(record, d, await _pdf(title, lines));
  }
  return store;
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    Pdfrx.pdfiumModulePath = pdfiumLibrary();
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  });

  testWidgets('the first page', (tester) async {
    _size(tester, logical);
    addTearDown(tester.view.reset);
    final db = _office();
    final dir = Directory.systemTemp.createTempSync('folio_office_home_');
    final links = UyapCaseLinks(directory: dir);
    final docs = Directory('${dir.path}/Belgeler')..createSync();
    final recent = <EvrakFile>[];
    await tester.runAsync(() async {
      for (final (name, edited) in [
        ('Bilirkişi raporuna itiraz dilekçesi.udf', day(0, 8, 4)),
        ('Cevaba cevap dilekçesi.udf', day(-1, 18, 2)),
        ('Tanık listesi.udf', day(-1, 15, 47)),
        ('Tarama ${dmy(day(-1))}.pdf', day(-1, 10, 49)),
        ('Vekaletname - Mustafa Şahin.pdf', day(-2, 16, 31)),
        ('İhtarname taslağı.docx', day(-3, 11, 12)),
        ('Islah dilekçesi.udf', day(-5, 14, 5)),
      ]) {
        final file = File('${docs.path}/$name')..writeAsStringSync('x');
        file.setLastModifiedSync(edited);
        recent.add(EvrakFile.fromPath(file.path));
      }
      final c = _of('2025/201');
      await links.link(
        recent.first.path,
        UyapCaseLink(
          jurisdiction: '1',
          courtType: '',
          courtId: '',
          court: c.court,
          number: c.number,
        ),
      );
    });
    debugDisableShadows = false;
    try {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: DesktopHome(
              name: lawyer,
              recent: recent,
              office: _homeOffice(db),
              links: links,
              now: () => now,
              onSearch: (_) {},
              onOpen: (_) {},
              onEdit: (_) {},
              onSendUyap: (_) {},
              onArchive: () {},
              onDrafts: () {},
              onAgenda: () {},
              onUets: () {},
              onNotices: () {},
            ),
          ),
        ),
      );
      await _settle(tester);
      await _shot(tester, 'ofis-anasayfa');
    } finally {
      debugDisableShadows = true;
    }
    await tester.pumpWidget(const SizedBox());
    db.dispose();
    dir.deleteSync(recursive: true);
  });

  testWidgets('the agenda and UETS', (tester) async {
    addTearDown(tester.view.reset);
    final db = _office();
    final sync = _sync(db);
    debugDisableShadows = false;
    try {
      for (final (size, suffix) in [(logical, ''), (phone, 'telefon-')]) {
        _size(tester, size);
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: AgendaPage(
                database: db,
                sync: sync,
                now: () => now,
                onOpenCase: (_) => true,
                onPetition: (_) {},
                onOpenNotice: (_) {},
              ),
            ),
          ),
        );
        await _settle(tester);
        await _shot(tester, '${suffix}ajanda');
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: UetsPage(
                database: db,
                sync: sync,
                now: () => now,
                onOpenCase: (_) => true,
                onOpenFile: (_) {},
                initialNotice: size == logical ? 'm1' : null,
              ),
            ),
          ),
        );
        await _settle(tester);
        await _shot(tester, '${suffix}uets');
        await tester.pumpWidget(const SizedBox());
      }
    } finally {
      debugDisableShadows = true;
    }
    db.dispose();
  });

  testWidgets('UYAP Dosyalarım and a case with a document open', (
    tester,
  ) async {
    _size(tester, logical);
    addTearDown(tester.view.reset);
    final db = _office();
    final root = Directory.systemTemp.createTempSync('folio_office_cases_');
    final store = (await tester.runAsync(() => _store(root)))!;
    final links = UyapCaseLinks(directory: Directory('${root.path}/destek'));
    debugDisableShadows = false;
    try {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: PortfolioPage(
              database: db,
              store: store,
              lawyer: lawyer,
              onShowCase: (_) {},
            ),
          ),
        ),
      );
      await _settle(
        tester,
        ready: () => find.text('2025/933').evaluate().isNotEmpty,
        rounds: 150,
      );
      await _shot(tester, 'uyap-dosyalarim');
      await tester.pumpWidget(const SizedBox());
      _size(tester, phone);
      await tester.pumpWidget(
        _app(
          Scaffold(
            drawer: const Drawer(),
            body: PortfolioPage(
              database: db,
              store: store,
              lawyer: lawyer,
              onShowCase: (_) {},
            ),
          ),
        ),
      );
      await _settle(
        tester,
        ready: () => find.text('2025/933').evaluate().isNotEmpty,
        rounds: 150,
      );
      await _shot(tester, 'telefon-uyap-dosyalarim');
      // Scrolled: the heading goes, the list has the screen.
      await tester.drag(
        find.byKey(const ValueKey('portfolio-scroll')),
        const Offset(0, -420),
      );
      await _settle(tester, rounds: 10);
      await _shot(tester, 'telefon-uyap-dosyalarim-kaydirilmis');
      await tester.drag(
        find.byKey(const ValueKey('portfolio-scroll')),
        const Offset(0, 600),
      );
      await _settle(tester, rounds: 10);
      // A filter's list from below, the list it leaves, a search's counts.
      await tester.tap(find.byKey(const ValueKey('portfolio-kind')));
      await _settle(tester, rounds: 20);
      await _shot(tester, 'telefon-portfoy-tur');
      await tester.tap(find.byKey(const ValueKey('portfolio-pick-Hukuk')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('portfolio-pick-apply')));
      await _settle(tester, rounds: 20);
      await _shot(tester, 'telefon-portfoy-suzgecli');
      await tester.tap(find.byKey(const ValueKey('portfolio-clear')));
      await tester.enterText(
        find.byKey(const ValueKey('portfolio-search')),
        'öztürk',
      );
      await _settle(tester, rounds: 20);
      await _shot(tester, 'telefon-portfoy-arama');
      await tester.pumpWidget(const SizedBox());
      _size(tester, logical);

      final controller = UyapCasePanelController(
        web: UyapWebService.forTesting(),
        mobile: UyapMobileApi.forTesting(Uri.parse('http://127.0.0.1:9/')),
        store: store,
        links: links,
        pause: Duration.zero,
      );
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: CaseDetailPage(
              caseKey: _of('2024/318').key,
              database: db,
              controller: controller,
              links: links,
              lawyer: lawyer,
              onBack: () {},
              onOpen: (_) {},
            ),
          ),
        ),
      );
      final row = find.byKey(const ValueKey('case-doc-e14'));
      await _settle(tester, ready: () => row.evaluate().isNotEmpty);
      await tester.tap(row);
      await _settle(tester, rounds: 60);
      await _shot(tester, 'dosya-onizleme');
      await tester.pumpWidget(const SizedBox());
      // The same case on a phone: its page, then a document on its own.
      _size(tester, phone);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: CaseDetailPage(
              caseKey: _of('2024/318').key,
              database: db,
              controller: controller,
              links: links,
              lawyer: lawyer,
              onBack: () {},
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await _settle(tester, rounds: 40);
      await _shot(tester, 'telefon-dosya');
      await tester.scrollUntilVisible(
        row,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(row);
      await _settle(tester, rounds: 60);
      await _shot(tester, 'telefon-evrak');
      await tester.pumpWidget(const SizedBox());
      _size(tester, logical);
    } finally {
      debugDisableShadows = true;
    }
    db.dispose();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });
}

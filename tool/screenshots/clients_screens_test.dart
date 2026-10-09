// Pictures of the newer pages (the settings, UYAP's notifications), drawn
// from invented data with the app's real fonts, for checking them by eye
// and for lifeos.com.tr. Not part of the test suite:
//
//   flutter test tool/screenshots/new_screens_test.dart
//
// Pictures land in tool/screenshots/out/.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/clients/client_accounts.dart';
import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_hearing.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/ui/theme/app_theme.dart';
import 'package:evrak_convert/ui/cash/cash_page.dart';
import 'package:evrak_convert/ui/clients/clients_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const pixelRatio = 1.5;
final _frame = GlobalKey();

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

Future<void> _shot(WidgetTester tester, String name) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
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

void main() {
  setUpAll(_loadFonts);

  Future<PortalDatabase> data() async {
    final db = PortalDatabase.memory();
    db.mergeCases(
      [
        for (final (n, c) in const [
          ('2024/318', 'Antalya 3. Asliye Hukuk Mahkemesi'),
          ('2025/77', 'Antalya 2. İş Mahkemesi'),
          ('2025/1904', 'Antalya 6. İcra Dairesi'),
          ('2023/55', 'Antalya BAM 4. Hukuk Dairesi'),
        ])
          PortalCase(key: caseKey(n, c), number: n, court: c),
      ],
      portfolio: true,
      baseline: true,
    );
    db.setRepresentation(
      caseKey('2024/318', 'Antalya 3. Asliye Hukuk Mahkemesi'),
      const [(ad: 'AYŞE KARACA', rol: 'Davacı')],
    );
    db.setRepresentation(caseKey('2025/77', 'Antalya 2. İş Mahkemesi'), const [
      (ad: 'AYŞE KARACA', rol: 'Davacı'),
    ]);
    db.setRepresentation('x', const [
      (ad: 'BORA YAPI LTD. ŞTİ.', rol: 'Alacaklı'),
    ]);
    final card = Client(
      id: 'k1',
      name: 'AYŞE KARACA',
      phone: '0532 000 00 41',
      email: 'ayse@ornek.com',
      address: 'Muratpaşa / Antalya',
      note: '18:00\'den sonra aranmak istemiyor.',
      updated: DateTime(2026, 10, 8),
      caseLinks: {
        caseKey('2025/1904', 'Antalya 6. İcra Dairesi'): CaseLink(
          CaseLink.added,
          DateTime(2026, 10, 8),
          role: 'Alacaklı',
        ),
        caseKey('2023/55', 'Antalya BAM 4. Hukuk Dairesi'): CaseLink(
          CaseLink.removed,
          DateTime(2026, 10, 8),
          role: 'Davacı',
        ),
      },
    );
    db.saveClient(card);
    db.saveClientRecord(
      ClientRecord(
        id: 'g1',
        clientId: 'k1',
        kind: ClientRecordKind.meeting,
        data: const {
          'kanal': 'Yüz yüze',
          'baslangic': '2026-10-06T14:10:00',
          'kararlar':
              'İki tanık bildirilecek; kalan ücret dava sonunda ödenecek.',
        },
        created: DateTime(2026, 10, 6, 14, 40),
        by: 'Av. Deniz Kaya',
        updated: DateTime(2026, 10, 6, 14, 40),
        locked: true,
      ),
    );
    db.saveClientRecord(
      ClientRecord(
        id: 'v1',
        clientId: 'k1',
        kind: ClientRecordKind.attorney,
        data: const {
          'noter': 'Antalya 5. Noterliği',
          'tarih': '12.03.2024',
          'yevmiye': '04418',
          'kapsam': 'Genel dava',
          'yetkiler': ['ahzu kabz', 'feragat', 'sulh'],
        },
        created: DateTime(2024, 3, 12),
        by: 'Av. Deniz Kaya',
        updated: DateTime(2024, 3, 12),
      ),
    );
    final key = caseKey('2024/318', 'Antalya 3. Asliye Hukuk Mahkemesi');
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    Observed<String> seen(String v) => Observed(v, PortalChannel.uyapWeb, now);
    db.mergeHearings(
      PortalChannel.uyapWeb,
      DateTime(2000),
      day.add(const Duration(days: 400)),
      [
        for (final (at, kind, result) in [
          (
            day.add(const Duration(days: 13, hours: 10, minutes: 30)),
            'Tahkikat',
            '',
          ),
          (
            day
                .subtract(const Duration(days: 148))
                .add(const Duration(hours: 9)),
            'Ön inceleme',
            'Tanık listesi için iki hafta süre verildi',
          ),
        ])
          PortalHearing(
            key: hearingKey(
              '2024/318',
              'Antalya 3. Asliye Hukuk Mahkemesi',
              at,
            ),
            caseKey: key,
            number: '2024/318',
            court: 'Antalya 3. Asliye Hukuk Mahkemesi',
            at: at,
            kind: seen(kind),
            result: result.isEmpty ? null : seen(result),
          ),
      ],
      complete: true,
    );
    db.saveClient(
      db
          .clientCard('k1')!
          .copyWith(
            caseNotes: {
              key: CaseNote(
                'Tanıklar: Ali Kaya (komşu), Elif Su. Müvekkil sulhe açık; '
                'alt sınır 250.000 TL.',
                DateTime(2026, 10, 6, 15),
                by: 'Av. Deniz Kaya',
              ),
            },
          ),
    );
    db.saveClientRecord(
      ClientRecord(
        id: 'f1',
        clientId: 'k1',
        kind: ClientRecordKind.fee,
        data: {
          'dosya': key,
          'tutar': 4500000,
          'yuzde': 0,
          'taksitler': [
            for (final (d, t) in [
              (DateTime(2026, 3, 12), 1500000),
              (DateTime(2026, 6, 12), 1500000),
              (DateTime(2026, 10, 3), 1500000),
            ])
              {'tarih': d.toIso8601String(), 'tutar': t},
          ],
        },
        created: DateTime(2026, 3, 12),
        by: 'Av. Deniz Kaya',
        updated: DateTime(2026, 3, 12),
      ),
    );
    var n = 0;
    for (final (kind, lira, at, what) in [
      (MovementKind.feePaid, 15000, DateTime(2026, 3, 12, 16, 38), '1. taksit'),
      (MovementKind.advanceIn, 5000, DateTime(2026, 3, 12, 16, 40), ''),
      (
        MovementKind.costFromAdvance,
        2500,
        DateTime(2026, 5, 21, 10, 5),
        'Bilirkişi ücreti',
      ),
      (MovementKind.feePaid, 15000, DateTime(2026, 6, 14, 14, 22), '2. taksit'),
      (
        MovementKind.costByLawyer,
        1250,
        DateTime(2026, 10, 2, 9, 12),
        'Keşif gideri',
      ),
    ]) {
      db.saveClientRecord(
        ClientRecord(
          id: 'h${n++}',
          clientId: 'k1',
          kind: ClientRecordKind.movement,
          data: {
            'dosya': key,
            'hesap': kind.code,
            'tutar': lira * 100,
            'zaman': at.toIso8601String(),
            'aciklama': what,
            if (kind.sign > 0) 'odeme': 'Havale / EFT',
            'makbuz': kind == MovementKind.feePaid ? '01${n}2' : '',
          },
          created: at,
          by: 'Av. Deniz Kaya',
          updated: at,
          locked: true,
        ),
      );
    }
    return db;
  }

  // A 1366 screen's window, the sidebar folded (76) and the title and
  // task bars off: what the page has.
  for (final (name, size, fold) in const [
    ('muvekkil-1366', Size(1290, 560), false),
    ('muvekkil-1366-liste-kapali', Size(1290, 560), true),
    ('muvekkil-genis', Size(1600, 860), false),
    ('muvekkil-telefon', Size(390, 844), false),
  ]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = size * pixelRatio;
      tester.view.devicePixelRatio = pixelRatio;
      addTearDown(tester.view.reset);
      // The computer's sizes for the computer's picture.
      if (size.width > 900) {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      }
      final db = await data();
      addTearDown(db.dispose);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: ClientsPage(
              lawyer: 'Av. Deniz Kaya',
              database: db,
              inOffice: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ayşe Karaca').first);
      await tester.pumpAndSettle();
      if (fold) {
        await tester.tap(find.byKey(const ValueKey('clients-fold')));
        await tester.pumpAndSettle();
      }
      await _shot(tester, name);
      if (!fold) {
        final row = find.byKey(
          ValueKey(
            'client-case-${caseKey('2024/318', 'Antalya 3. Asliye Hukuk Mahkemesi')}',
          ),
        );
        await tester.tap(row);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          row,
          100,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await _shot(tester, '$name-dosya');
        await tester.tap(row);
        await tester.pumpAndSettle();
      }
      if (fold || size.width > 1500) {
        debugDefaultTargetPlatformOverride = null;
        return;
      }
      final menu = find.byKey(
        ValueKey('case-menu-${caseKey('2025/77', 'Antalya 2. İş Mahkemesi')}'),
      );
      await tester.scrollUntilVisible(
        menu,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await _shot(tester, '$name-menu');
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('client-accounts')),
        -200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('client-accounts')));
      await tester.pumpAndSettle();
      await _shot(tester, '$name-hesap');
      debugDefaultTargetPlatformOverride = null;
    });
  }

  // The Kasa: a 1366 screen's window beside the sidebar, and a phone.
  for (final (name, size) in const [
    ('kasa-1366', Size(1130, 560)),
    ('kasa-telefon', Size(390, 844)),
  ]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = size * pixelRatio;
      tester.view.devicePixelRatio = pixelRatio;
      addTearDown(tester.view.reset);
      if (size.width > 900) {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      }
      final db = await data();
      addTearDown(db.dispose);
      final now = DateTime.now();
      var n = 0;
      for (var back = 0; back < 10; back++) {
        final m = DateTime(now.year, now.month - back);
        for (final (cat, what, lira, day) in [
          ('Kira', 'Ofis kirası', 18000, 1),
          ('Maaş ve SGK', 'Stajyer SGK primi', 7840, 3),
          ('Ulaşım', 'Adliye otoparkı', 650 + back * 40, 6),
          if (back.isEven) ('Kırtasiye', 'Toner ve kâğıt', 1450, 4),
        ]) {
          final at = DateTime(m.year, m.month, day, 9, 10);
          if (at.isAfter(now)) continue;
          db.saveClientRecord(
            ClientRecord(
              id: 'kasa${n++}',
              clientId: officeCashId,
              kind: ClientRecordKind.cash,
              data: {
                'tur': 'gider',
                'kategori': cat,
                'tutar': lira * 100,
                'zaman': at.toIso8601String(),
                'aciklama': what,
                'odeme': cat == 'Ulaşım' ? 'Nakit' : 'Banka',
              },
              created: at,
              by: 'Av. Deniz Kaya',
              updated: at,
              locked: true,
            ),
          );
        }
        final paid = DateTime(m.year, m.month, 5, 14, 22);
        if (back > 0 || !paid.isAfter(now)) {
          db.saveClientRecord(
            ClientRecord(
              id: 'tah$back',
              clientId: 'k1',
              kind: ClientRecordKind.movement,
              data: {
                'dosya': caseKey('2025/77', 'Antalya 2. İş Mahkemesi'),
                'hesap': MovementKind.feePaid.code,
                'tutar': (22000 + back * 3500) * 100,
                'zaman': paid.toIso8601String(),
                'aciklama': 'Danışmanlık ücreti',
                'odeme': 'Havale / EFT',
              },
              created: paid,
              by: 'Av. Deniz Kaya',
              updated: paid,
              locked: true,
            ),
          );
        }
      }
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: CashPage(lawyer: 'Av. Deniz Kaya', database: db),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _shot(tester, name);
      await tester.tap(find.text('Raporlar'));
      await tester.pumpAndSettle();
      await _shot(tester, '$name-rapor');
      debugDefaultTargetPlatformOverride = null;
    });
  }
}

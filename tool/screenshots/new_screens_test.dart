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

import 'package:evrak_convert/services/editor/lawyer_profile.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/portal/uyap_notice.dart';
import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/ui/agenda/uyap_notices_page.dart';
import 'package:evrak_convert/ui/settings/settings_page.dart';
import 'package:evrak_convert/ui/theme/app_theme.dart';
import 'package:evrak_convert/ui/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const logical = Size(1440, 900);
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

  testWidgets('settings', (tester) async {
    tester.view.physicalSize = logical * pixelRatio;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    LawyerProfile.use(
      const LawyerProfile(
        lawyers: [
          Lawyer(
            name: 'Deniz Kaya',
            bar: 'Antalya Barosu',
            barNumber: '4821',
            idNumber: '12345678901',
          ),
        ],
      ),
    );
    final library = LibraryController(watchFolders: false);
    final appearance = ThemeController(
      settingsPath: '/nonexistent/appearance.json',
      mode: ThemeMode.light,
    );
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SettingsPage(
            library: library,
            appearance: appearance,
            onBack: () {},
          ),
        ),
      ),
    );
    await _shot(tester, 'ayarlar');
    await tester.tap(find.byKey(const ValueKey('settings-nav-look')));
    await tester.pumpAndSettle();
    await _shot(tester, 'ayarlar-gorunum');
    tester.view.physicalSize = const Size(390, 844) * pixelRatio;
    await tester.pumpWidget(
      _app(SettingsPage(library: library, appearance: appearance)),
    );
    await _shot(tester, 'ayarlar-telefon');
    await tester.pumpWidget(const SizedBox());
    library.dispose();
    appearance.dispose();
    LawyerProfile.use(null);
  });

  testWidgets('notices', (tester) async {
    tester.view.physicalSize = logical * pixelRatio;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    final db = PortalDatabase.memory();
    final sync = PortalSync(database: () async => db);
    db.mergeCases([
      PortalCase.create(
        number: '2024/318',
        court: 'Antalya 3. Asliye Hukuk Mahkemesi',
      ),
      PortalCase.create(number: '2025/4410', court: 'Antalya 6. İcra Dairesi'),
      PortalCase.create(
        number: '2025/201',
        court: 'Manavgat 2. Asliye Hukuk Mahkemesi',
      ),
    ], portfolio: true);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
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
      UyapNoticeRow(
        source: UyapNoticeSource.mobile,
        id: 'm1',
        messageId: 'x',
        title: 'Gerekçeli Karar',
        sentAt: today.add(const Duration(hours: 14, minutes: 5)),
      ),
      web(
        1,
        'Gerekçeli Karar',
        'Antalya 3. Asliye Hukuk Mahkemesi Biriminde Bulunan 2024/318 sayılı '
            'dosyaya gerekçeli karar eklenmiştir.',
        today.add(const Duration(hours: 14, minutes: 5, seconds: 31)),
      ),
      web(
        2,
        'İcra Dosyası Borç Tahsilatı',
        "Antalya 6. İcra Dairesi'nin 2025/4410 Esas sayılı dosyasında "
            '18.450,00 TL tahsilat yapılmıştır.',
        today.add(const Duration(hours: 11, minutes: 42)),
      ),
      web(
        3,
        'Bilirkişi Raporu Kaydedilmesi',
        'Manavgat 2. Asliye Hukuk Mahkemesi birimi, 2025/201 dosyasında '
            'bilirkişi raporu kaydedilmiştir.',
        today.add(const Duration(hours: 9, minutes: 18)),
      ),
      web(
        4,
        'Vekil Kaydı',
        'Kurum adına vekil kaydı yapılmıştır.',
        today.subtract(const Duration(hours: 14)),
        read: true,
      ),
      web(
        5,
        'Harç Tahsil Müzekkere Kaydı',
        'Antalya 3. Asliye Hukuk Mahkemesi Biriminde Bulunan 2024/318 sayılı '
            'dosyada harç tahsil müzekkeresi kaydedilmiştir.',
        today.subtract(const Duration(hours: 15)),
        read: true,
      ),
    ]);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: UyapNoticesPage(
            database: db,
            sync: sync,
            onOpenCase: (_) => true,
          ),
        ),
      ),
    );
    await _shot(tester, 'bildirimler-bos');
    await tester.tap(find.text('Gerekçeli Karar').first);
    await _shot(tester, 'bildirimler');
    await tester.pumpWidget(const SizedBox());
    tester.view.physicalSize = const Size(390, 844) * pixelRatio;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: UyapNoticesPage(
            database: db,
            sync: sync,
            onOpenCase: (_) => true,
          ),
        ),
      ),
    );
    await _shot(tester, 'telefon-bildirimler');
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
    db.dispose();
  });
}

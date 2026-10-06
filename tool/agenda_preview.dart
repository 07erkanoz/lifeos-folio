import 'dart:io';

import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_hearing.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/agenda/agenda_page.dart';
import 'package:evrak_convert/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

/// The agenda with the design's sample week, to set beside
/// docs/design/ajanda-taslak.png. flutter build windows --debug -t
/// tool/agenda_preview.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final now = DateTime(2026, 10, 6, 12, 55);
  final db = PortalDatabase.memory();
  const web = PortalChannel.uyapWeb, mobile = PortalChannel.uyapMobile;
  final asked = DateTime.utc(2026, 10, 6);
  PortalHearing h(
    int day,
    int hour,
    int minute,
    String court,
    String number, {
    bool e = false,
  }) => PortalHearing.create(
    number: number,
    court: court,
    at: DateTime(2026, 10, day, hour, minute),
    channel: e ? mobile : web,
    id: '$day$hour',
    kind: Observed('Ön inceleme duruşması', web, asked),
    parties: Observed(
      [
        {'adi': 'Davacı Ayşe K.'},
        {'adi': 'Davalı B. İnşaat Ltd.'},
      ],
      web,
      asked,
    ),
    eHearing: e ? Observed('https://edurusma', mobile, asked) : null,
  );
  db.mergeHearings(web, DateTime(2026, 9, 1), DateTime(2026, 12, 1), [
    h(6, 9, 20, 'Antalya 3. Asliye Hukuk Mahkemesi', '2025/412'),
    h(6, 14, 10, 'Manavgat 2. İş Mahkemesi', '2026/57'),
    h(7, 9, 45, 'İzmir BAM 4. Hukuk Dairesi', '2025/1903', e: true),
    h(8, 10, 30, 'Antalya 1. Ağır Ceza Mahkemesi', '2026/31'),
    h(8, 12, 40, 'Kepez 2. Sulh Hukuk Mahkemesi', '2026/210'),
    h(9, 13, 30, 'Alanya 1. Aile Mahkemesi', '2025/980'),
    h(10, 10, 0, 'Antalya 6. İcra Hukuk Mahkemesi', '2026/77'),
  ], complete: true);
  var n = 0;
  void item(
    String kind,
    String title,
    DateTime at, {
    bool allDay = false,
    String body = '',
    bool done = false,
    String? hearing,
  }) => db.saveAgenda(
    AgendaItem(
      id: '${n++}',
      kind: kind,
      title: title,
      body: body,
      at: at,
      allDay: allDay,
      done: done,
      hearingKey: hearing,
      updated: now,
    ),
  );
  final first = hearingKey(
    '2025/412',
    'Antalya 3. Asliye Hukuk Mahkemesi',
    DateTime(2026, 10, 6, 9, 20),
  );
  item(
    'deadline',
    'İstinaf süresi son gün',
    DateTime(2026, 10, 7),
    allDay: true,
    body: 'Antalya 2. Asliye Ticaret · 2024/615',
  );
  item(
    'deadline',
    'Cevap dilekçesi',
    DateTime(2026, 10, 10),
    allDay: true,
    body: 'Kepez 1. Asliye Hukuk · 2026/144',
  );
  item(
    'deadline',
    'Tebligattan itibaren 2 hafta',
    DateTime(2026, 10, 14),
    allDay: true,
    body: 'UETS · Manavgat İcra Dairesi',
  );
  item('note', 'Bilirkişi raporuna itiraz', DateTime(2026, 10, 6, 11, 30));
  item('task', 'Müvekkil görüşmesi', DateTime(2026, 10, 9, 9, 0));
  item(
    'task',
    'Tanık listesini hazırla',
    DateTime(2026, 10, 5),
    done: true,
    hearing: first,
  );
  item(
    'task',
    'Bilirkişi raporuna itiraz taslağı',
    DateTime(2026, 10, 6),
    hearing: first,
  );
  item(
    'task',
    'Müvekkile duruşma saatini bildir',
    DateTime(2026, 10, 6),
    hearing: first,
  );

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('tr', 'TR')],
      locale: const Locale('tr', 'TR'),
      home: Scaffold(
        body: AgendaPage(
          database: db,
          web: UyapWebService.instance,
          now: () => now,
          onOpenCase: (_) => true,
          onPetition: (_) => true,
        ),
      ),
    ),
  );
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1206, 900),
      center: true,
      title: 'Ajanda önizleme',
    ),
    () async {
      await windowManager.show();
      if (Platform.environment['FOLIO_PREVIEW_TOP'] == '1') {
        await windowManager.setAlwaysOnTop(true);
      }
    },
  );
}

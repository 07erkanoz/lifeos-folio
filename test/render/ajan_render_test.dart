import 'dart:async';
// Renders Folio Ajan's screens with made-up data into PNGs, to set them
// beside the approved mock-ups. Not a check: run on purpose, with
// FOLIO_RENDER=<folder>.
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/ai/ai_refresh.dart';
import 'package:evrak_convert/services/voice/ajan_link.dart';
import 'package:evrak_convert/ui/desktop/ajan_skins.dart';
import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/services/voice/folio_ajan.dart';
import 'package:evrak_convert/services/voice/live_conversation.dart';
import 'package:evrak_convert/services/voice/voice_settings.dart';
import 'package:evrak_convert/ui/desktop/ajan_float.dart';
import 'package:evrak_convert/ui/desktop/jarvis_view.dart';
import 'package:evrak_convert/ui/theme/app_theme.dart';
import 'package:evrak_convert/ui/desktop/quick_search_palette.dart';

class _Ajan extends FolioAjan {
  @override
  bool get available => true;
  @override
  Future<void> loadSettings({bool quick = false}) async {}
  @override
  Future<void> loadBrief() async {}
  void poke() => notifyListeners();
}

AjanBrief _brief() {
  final now = DateTime.now();
  return AjanBrief(
    deadlines: [
      const BriefItem(
        'İstinaf süresi doluyor',
        '2024/77 · Örnek 2. Asliye Ticaret',
        when: 'Bugün',
        days: 0,
        urgent: true,
      ),
      BriefItem(
        'Bilirkişi raporuna itiraz',
        '2025/318',
        when: '${now.add(const Duration(days: 2)).day} Kasım',
        days: 2,
        urgent: true,
      ),
    ],
    hearings: const [
      BriefItem(
        'Büro · Örnek Ltd.',
        'Müvekkil görüşmesi',
        clock: '14:00',
        when: 'Bugün 14:00',
        days: 0,
      ),
      BriefItem(
        '2023/412 · Örnek 5. Asliye Ceza',
        'Duruşma',
        clock: '11:10',
        when: '18.11 11:10',
        days: -3,
      ),
      BriefItem(
        '2025/318 · Örnek 4. Sulh Hukuk',
        'Duruşma · keşif',
        clock: '10:30',
        when: '23.11 10:30',
        days: 2,
      ),
    ],
    incoming: const [
      BriefItem('Tebligat: ara karar', '2024/77', when: 'dün'),
      BriefItem('UYAP: ara karar yüklendi', '2024/77', when: 'dün 17:05'),
    ],
    tasks: const [
      BriefItem('Keşif masrafını yatır', ''),
      BriefItem('İtiraz dilekçesini gözden geçir', ''),
    ],
  );
}

Future<void> _fonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
      );
    }
    await loader.load();
  }

  await family('Inter', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold'])
      'fonts/ui/Inter-$w.ttf',
  ]);
  await family('JetBrainsMono', [
    'fonts/mono/JetBrainsMono-Regular.ttf',
    'fonts/mono/JetBrainsMono-Medium.ttf',
  ]);
  final flutter = File(Platform.resolvedExecutable).parent.parent.parent.parent;
  await family('MaterialIcons', [
    '${flutter.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  final out = Platform.environment['FOLIO_RENDER']!;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  final out = Platform.environment['FOLIO_RENDER'];
  testWidgets('palette', (tester) async {
    await tester.runAsync(_fonts);
    tester.view.physicalSize = const Size(800, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-render-'),
    ))!;
    final library = LibraryController(
      databasePath: ':memory:',
      watchFolders: false,
    );
    await tester.runAsync(() async {
      final f = Directory('${dir.path}/2025-318 Örnek 4. Sulh Hukuk')
        ..createSync();
      await File('${f.path}/Bilirkişi raporu – kira tespiti.txt').writeAsString(
        'Dava konusu taşınmazın kira bedelinin tespiti amacıyla mahallinde '
        'yapılan keşifte bilirkişi raporu düzenlendi. Emsal taşınmazlarla '
        'karşılaştırıldığında aylık kira bedeli hakkaniyete uygundur.',
      );
      await File('${f.path}/Bilirkişi raporuna itiraz.txt').writeAsString(
        'Kira tespit davasında bilirkişi raporuna itiraz ediyoruz.',
      );
      await library.addPaths([dir.path]);
      await library.waitForIdle();
    });
    final now = DateTime.now();
    final ajan = _Ajan()
      ..dark = true
      ..brief = AjanBrief(
        deadlines: [
          const BriefItem(
            'İstinaf süresi doluyor',
            '2024/77 · Örnek 2. Asliye Ticaret',
            when: 'Bugün',
            days: 0,
            urgent: true,
          ),
          BriefItem(
            'Bilirkişi raporuna itiraz',
            '2025/318',
            when: '${now.day + 2}.${now.month}',
            days: 2,
            urgent: true,
          ),
        ],
        hearings: const [
          BriefItem(
            'Büro · Örnek Ltd.',
            'Müvekkil görüşmesi',
            clock: '14:00',
            when: 'Bugün 14:00',
            days: 0,
          ),
        ],
        incoming: const [
          BriefItem('a', ''),
          BriefItem('b', ''),
          BriefItem('c', ''),
        ],
      );
    final key = GlobalKey();
    Widget app() => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Inter'),
      home: RepaintBoundary(
        key: key,
        child: ColoredBox(
          color: const Color(0xFF222A33),
          child: FloatingPalette(
            onOutside: () {},
            child: QuickSearchPalette(
              library: library,
              ajan: ajan,
              onOpen: (_) {},
              onDismiss: () {},
              onMain: () {},
              onJarvis: () {},
            ),
          ),
        ),
      ),
    );
    library.query = '';
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 200));
    await _shot(tester, key, 'panel-bos');
    library.setQuery('kira tespit bilirkişi');
    await tester.runAsync(library.searchNow);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await _shot(tester, key, 'panel-arama');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      library.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await dir.delete(recursive: true);
    });
  }, skip: out == null);

  testWidgets('folio ajan', (tester) async {
    await tester.runAsync(_fonts);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final ajan = _Ajan()..brief = _brief();
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Inter'),
        home: RepaintBoundary(
          key: key,
          child: JarvisView(
            ajan: ajan,
            onMinimize: () {},
            onMain: () {},
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await _shot(tester, key, 'ajan-bos');
    ajan
      ..question = 'Bu hafta duruşmam var mı?'
      ..answer =
          'Bu hafta iki duruşmanız var. Çarşamba 11:10’daki ceza duruşması '
          'geçti; pazartesi 10:30’da Sulh Hukuk’ta keşif var.'
      ..steps.addAll(['ajanda · 37 ms', 'dosya_bilgisi · 52 ms'])
      ..poke();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await _shot(tester, key, 'ajan-konusma');
    for (final skin in AjanSkin.values) {
      ajan
        ..settings = ajan.settings.copyWith(skin: skin.name)
        ..poke();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await _shot(tester, key, 'ajan-${skin.name}');
    }
    unawaited(
      AjanLinks.instance.request(
        UyapNeed.uets,
        'Tebligatlara bakmak için UETS’e e-imzanızla bağlanın.',
      ),
    );
    for (final skin in [AjanSkin.kure, AjanSkin.hologram, AjanSkin.kehribar]) {
      ajan
        ..settings = ajan.settings.copyWith(skin: skin.name)
        ..poke();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await _shot(tester, key, 'ajan-pin-${skin.name}');
    }
    AjanLinks.instance.cancel();
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: out == null);

  testWidgets('voice window', (tester) async {
    await tester.runAsync(_fonts);
    tester.view.physicalSize = const Size(900, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final ajan = _Ajan()..settings = const VoiceSettings(on: true);
    ajan.voice.lines.add(
      LiveLine(
        'ajan',
        'Yarın duruşmanız yok. Pazartesi 10:30’da Sulh Hukuk’ta keşif var.',
      ),
    );
    ajanFloatOpen.value = true;
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme.copyWith(
          textTheme: AppTheme.lightTheme.textTheme.apply(fontFamily: 'Inter'),
        ),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            backgroundColor: const Color(0xFFF5F6F8),
            body: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 38,
                  child: ColoredBox(
                    color: Colors.white,
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        const Text('LifeOS Folio'),
                        const Spacer(),
                        AjanVoicePill(ajan: ajan),
                        const SizedBox(width: 140),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 46,
                  right: 16,
                  child: AjanFloat(ajan: ajan, onFull: () {}),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await _shot(tester, key, 'yuzen');
    ajanFloatOpen.value = false;
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: out == null);
}

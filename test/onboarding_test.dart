import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/editor/lawyer_profile.dart';
import 'package:evrak_convert/services/platform/onboarding_store.dart';
import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/ui/theme/theme_controller.dart';
import 'package:evrak_convert/ui/widgets/onboarding_gate.dart';

class _Store extends OnboardingStore {
  OnboardingStatus status = const OnboardingStatus();
  @override
  Future<OnboardingStatus> load() async => status;
  @override
  Future<void> save({required bool completed}) async {
    status = OnboardingStatus(licenseAccepted: true, completed: completed);
  }
}

class _Library extends LibraryController {
  final added = <String>[];
  @override
  Future<void> initialize() async {
    ready = true;
  }

  @override
  Future<void> addPaths(List<String> paths, {bool recursive = true}) async {
    ready = true;
    added.addAll(paths);
  }
}

Future<void> _io(WidgetTester tester) async {
  // Pump async stages separately: transitions can start asset I/O on a new frame.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    if (i > 2 &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() => rootBundle.evict('assets/legal/LICENSE.txt'));
  test('license and completion persist independently and malformed data is recoverable', () async {
    final dir = await Directory.systemTemp.createTemp('folio-onboard-');
    addTearDown(() => dir.delete(recursive: true));
    final store = OnboardingStore(path: '${dir.path}/setup.json');
    expect((await store.load()).licenseAccepted, isFalse);
    await store.save(completed: false);
    final deferred = await store.load();
    expect(deferred.licenseAccepted, isTrue);
    expect(deferred.completed, isFalse);
    await store.save(completed: true);
    expect((await store.load()).completed, isTrue);
    await File(store.path!).writeAsString('{bad');
    expect((await store.load()).licenseAccepted, isFalse);
  });
  testWidgets(
    'theme, required consent, folder selection and restart skip work',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('folio-onboard-ui-'),
      ))!;
      final store = _Store();
      final appearance = ThemeController(
        settingsPath: '${dir.path}/theme.json',
      );
      final library = _Library();
      var done = 0;
      final saved = <LawyerProfile>[];
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            library: library,
            appearance: appearance,
            store: store,
            status: const OnboardingStatus(),
            onDone: () => done++,
            pickFolder: () async => '/documents',
            loadProfile: () async => const LawyerProfile(),
            saveProfile: (p) async => saved.add(p),
          ),
        ),
      );
      await tester.runAsync(() => tester.tap(find.text('Siyah')));
      await tester.pump();
      expect(appearance.mode, ThemeMode.dark);
      await tester.runAsync(() => tester.tap(find.text('Başlayalım')));
      await _io(tester);
      final button = find.widgetWithText(FilledButton, 'Onayla ve devam et');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.runAsync(() => tester.tap(find.byType(CheckboxListTile)));
      await tester.pump();
      await tester.runAsync(() => tester.tap(button));
      await _io(tester);
      // The lawyer's profile: typed, kept, and on to the folders.
      expect(find.text('03 / AVUKAT PROFİLİ'), findsOneWidget);
      expect(find.text('UYAP Mobil ile doldur'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Ad soyad'),
        'Deniz Yılmaz',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Baro'), 'Antalya');
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('onboarding-profile-next'))),
      );
      await _io(tester);
      expect(saved.single.lawyer?.titled, 'Av. Deniz Yılmaz');
      expect(saved.single.lawyer?.barName, 'Antalya Barosu');
      expect(find.text('Klasör seç ve ekle'), findsOneWidget);
      expect((await tester.runAsync(store.load))!.licenseAccepted, isTrue);
      await tester.runAsync(() => tester.tap(find.text('Klasör seç ve ekle')));
      await _io(tester);
      expect(library.added, ['/documents']);
      await tester.runAsync(() => tester.tap(find.text('Folio’yu aç')));
      await _io(tester);
      expect(done, 1);
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingGate(
            library: library,
            appearance: appearance,
            store: store,
            child: const Text('Kütüphane hazır'),
          ),
        ),
      );
      await _io(tester);
      expect(find.text('Kütüphane hazır'), findsOneWidget);
      final restored = ThemeController(settingsPath: appearance.settingsPath);
      await tester.runAsync(restored.load);
      expect(restored.mode, ThemeMode.dark);
      await tester.pumpWidget(const SizedBox.shrink());
      appearance.dispose();
      restored.dispose();
      library.dispose();
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );
  testWidgets(
    'external preview can defer folders after accepting the license',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('folio-onboard-external-'),
      ))!;
      final store = _Store();
      final library = _Library();
      final appearance = ThemeController(
        settingsPath: '${dir.path}/theme.json',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingGate(
            library: library,
            appearance: appearance,
            store: store,
            externalDocument: true,
            child: const Text('Belge önizlemesi'),
          ),
        ),
      );
      await _io(tester);
      await tester.runAsync(() => tester.tap(find.text('Başlayalım')));
      await _io(tester);
      await tester.runAsync(() => tester.tap(find.byType(CheckboxListTile)));
      await tester.pump();
      await tester.runAsync(() => tester.tap(find.text('Onayla, belgeye geç')));
      await _io(tester);
      expect(find.text('Belge önizlemesi'), findsOneWidget);
      expect((await tester.runAsync(store.load))!.completed, isFalse);
      expect(library.added, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      library.dispose();
      appearance.dispose();
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );
}

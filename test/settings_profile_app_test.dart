import 'dart:io';

import 'package:evrak_convert/main.dart';
import 'package:evrak_convert/services/editor/lawyer_profile.dart';
import 'package:evrak_convert/services/security/app_lock.dart';
import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/ui/mobile/lawyer_profile_page.dart';
import 'package:evrak_convert/ui/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('in Folio’s window, Ayarlar › Profil opens the profile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    LawyerProfile.use(const LawyerProfile());
    addTearDown(() => LawyerProfile.use(null));
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('profile-app-'),
    ))!;
    final library = LibraryController(
      databasePath: ':memory:',
      watchFolders: false,
    );
    final theme = ThemeController(
      settingsPath: '${dir.path}/appearance.json',
      mode: ThemeMode.light,
    );
    await tester.runAsync(library.initialize);
    // As on the lawyer's computer: the lock on, opened.
    final lock = AppLock(
      file: () async => File('${dir.path}/kilit.json'),
      iterations: 1000,
    );
    await tester.runAsync(() async {
      await lock.load();
      await lock.setPassword('1234');
      lock.lockNow();
    });
    final before = AppLock.instance;
    AppLock.instance = lock;
    addTearDown(() => AppLock.instance = before);
    await tester.pumpWidget(
      EvrakConvertApp(library: library, appearance: theme),
    );
    await tester.pump();
    // Locked at the start, opened on the lock screen: the lock's own
    // navigator came and went, and what is opened after must still open.
    await tester.enterText(find.byKey(const ValueKey('lock-password')), '1234');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    for (var i = 0; i < 10 && lock.locked; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(lock.locked, isFalse);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ayarlar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayarlar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-nav-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-profile')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(LawyerProfilePage), findsOneWidget);
    // Back, and the lock turned off from the same page.
    Navigator.of(tester.element(find.byType(LawyerProfilePage))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-nav-security')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-lock-switch')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lock-field-0')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('lock-field-0')), '1234');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(lock.enabled, isFalse);
    lock.dispose();
  });
}

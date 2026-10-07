import 'package:evrak_convert/services/editor/lawyer_profile.dart';
import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/ui/settings/settings_page.dart';
import 'package:evrak_convert/ui/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The settings (docs/design/ayarlar-taslak.png): a page in the window on a
// computer, its sections on the left, a search that finds a setting.
void main() {
  testWidgets('wide: the sections on the left, the theme chosen, a setting '
      'found by its words, the way back', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    LawyerProfile.use(const LawyerProfile());
    addTearDown(() => LawyerProfile.use(null));
    final library = LibraryController(watchFolders: false);
    addTearDown(library.dispose);
    final appearance = ThemeController(
      settingsPath: '/nonexistent/appearance.json',
    );
    addTearDown(appearance.dispose);
    var back = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          library: library,
          appearance: appearance,
          onBack: () => back++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final id in [
      'profile',
      'connections',
      'notices',
      'documents',
      'editor',
      'citations',
      'signing',
      'look',
      'update',
      'about',
    ]) {
      expect(find.byKey(ValueKey('settings-nav-$id')), findsOneWidget);
    }
    // The theme, on the computer as cards.
    await tester.tap(find.byKey(const ValueKey('settings-nav-look')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-theme-dark')));
    await tester.pump();
    expect(appearance.mode, ThemeMode.dark);
    // A search leaves only what it names.
    await tester.enterText(
      find.byKey(const ValueKey('settings-search')),
      'ocr',
    );
    await tester.pump();
    expect(find.text('Taranmış belgeleri oku (OCR)'), findsOneWidget);
    expect(find.text('Kalıplarım'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('settings-search')), '');
    await tester.pump();
    await tester.tap(find.byTooltip('Geri'));
    expect(back, 1);
    expect(tester.takeException(), isNull);
  });
}

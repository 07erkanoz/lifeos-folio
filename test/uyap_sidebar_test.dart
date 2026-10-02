import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/ui/library/library_sidebar.dart';
import 'package:evrak_convert/ui/theme/theme_controller.dart';

/// The lawyer's own cases, under UYAP among the folders.
void main() {
  testWidgets('UYAP stands among the folders, and its cases open beneath it '
      'once it is chosen', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final library = LibraryController(watchFolders: false);
    addTearDown(library.dispose);
    final chosen = <String>[];
    Widget sidebar(String group) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 280,
          child: LibrarySidebar(
            library: library,
            appearance: ThemeController(),
            compact: false,
            group: group,
            pickFiles: () {},
            pickFolder: () {},
            showStatus: () {},
            selectGroup: chosen.add,
            selectFolder: (_) {},
            uyapAvailable: true,
            uyapCases: const [
              ('k1', '2026/1204', 'İstanbul 5. Aile Mahkemesi', 3),
              ('k2', '2025/77', 'Ankara 3. Asliye Hukuk Mahkemesi', 0),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(sidebar('all'));
    // No list of its own on the home screen any more: UYAP, closed.
    expect(find.text('UYAP DOSYALARI'), findsNothing);
    expect(find.text('UYAP Dosyalarım'), findsOneWidget);
    expect(find.text('2026/1204'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('uyap-folder')));
    expect(chosen, ['uyap']);

    await tester.pumpWidget(sidebar('uyap'));
    expect(find.text('2026/1204'), findsOneWidget);
    expect(find.text('Ankara 3. Asliye Hukuk Mahkemesi'), findsOneWidget);
    expect(find.text('3 yeni'), findsOneWidget);
    await tester.tap(find.text('2025/77'));
    expect(chosen.last, 'uyap:k2');
    await tester.pumpWidget(sidebar('uyap:k2'));
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('uyap-case-k2')))
          .selected,
      isTrue,
    );
  });
}

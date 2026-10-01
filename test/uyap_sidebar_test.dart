import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/ui/library/library_sidebar.dart';
import 'package:evrak_convert/ui/theme/theme_controller.dart';

/// The lawyer's own cases, among the ways of looking at the archive.
void main() {
  testWidgets('each UYAP case with documents saved is listed, and opens to '
      'its own documents', (tester) async {
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
            uyapCases: const [
              ('k1', '2026/1204', 'İstanbul 5. Aile Mahkemesi', 7),
              ('k2', '2025/77', 'Ankara 3. Asliye Hukuk Mahkemesi', 2),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(sidebar('all'));
    expect(find.text('UYAP DOSYALARI'), findsOneWidget);
    expect(find.text('2026/1204'), findsOneWidget);
    expect(find.text('Ankara 3. Asliye Hukuk Mahkemesi'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    await tester.tap(find.text('2025/77'));
    expect(chosen, ['uyap:k2']);
    await tester.pumpWidget(sidebar('uyap:k2'));
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('uyap-case-k2')))
          .selected,
      isTrue,
    );
  });
}

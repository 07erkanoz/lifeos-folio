import 'dart:io';
import 'dart:typed_data';

import 'package:evrak_convert/services/editor/editor_drafts.dart';
import 'package:evrak_convert/ui/theme/app_theme.dart';
import 'package:evrak_convert/ui/widgets/editor_ribbon.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:evrak_convert/ui/widgets/uyap_case_panel.dart';
import 'package:evrak_convert/ui/legal/case_law_search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ribbon as a laptop shows it, in the face Folio draws it with: the
/// test's own letters are twice as wide, and every ribbon test so far was
/// laid out 2300 points wide.
void main() {
  setUpAll(() async {
    final loader = FontLoader(AppTheme.uiFont);
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(
            File('fonts/ui/Inter-$weight.ttf').readAsBytesSync(),
          ),
        ),
      );
    }
    await loader.load();
  });

  testWidgets('the UYAP case and the case-law search are two panels, open '
      'together, each closed on its own', (tester) async {
    tester.view.physicalSize = const Size(1920, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    editorRibbonTab.value = RibbonTab.legal;
    addTearDown(() => editorRibbonTab.value = RibbonTab.home);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: AppTheme.uiFont),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: EditorWidget(draft: EditorDrafts().draft('new', 'Yeni evrak')),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final uyap = find.byType(UyapCasePanel);
    final caseLaw = find.byType(CaseLawSearchScreen);
    await tester.tap(find.text('UYAP dosyası'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('legal-case-law')));
    await tester.pump();
    expect(uyap, findsOneWidget);
    expect(caseLaw, findsOneWidget);
    // The case at the left of the page, the search at its right.
    expect(tester.getRect(uyap).right, lessThan(tester.getRect(caseLaw).left));
    expect(find.byKey(const ValueKey('side-tab-uyap')), findsNothing);

    // The search closed, the case stays; and the other way round.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('editor-case-law-panel')),
        matching: find.byTooltip('Paneli kapat'),
      ),
    );
    await tester.pump();
    expect(caseLaw, findsNothing);
    expect(uyap, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('legal-case-law')));
    await tester.pump();
    await tester.tap(
      find.descendant(of: uyap, matching: find.byTooltip('Paneli kapat')),
    );
    await tester.pump();
    expect(uyap, findsNothing);
    expect(caseLaw, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }, skip: !(Platform.isLinux || Platform.isWindows));

  // The editor alone, and beside Folio's menu: a narrower one.
  for (final width in const [1366.0, 1100.0]) {
    testWidgets('on the Hukuk tab "İçtihat ara" is in sight without '
        'scrolling, $width points wide', (tester) async {
      tester.view.physicalSize = Size(width, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      editorRibbonTab.value = RibbonTab.legal;
      addTearDown(() => editorRibbonTab.value = RibbonTab.home);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: AppTheme.uiFont),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          home: Scaffold(
            body: EditorWidget(
              draft: EditorDrafts().draft('new', 'Yeni evrak'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final button = find.byKey(const ValueKey('legal-case-law'));
      expect(button, findsOneWidget);
      // Inside the strip, left of the "…" kept at its right.
      expect(tester.getRect(button).right, lessThan(width - 48));
      await tester.tap(button);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    });
  }
}

import 'package:evrak_convert/services/editor/editor_drafts.dart';
import 'package:evrak_convert/ui/widgets/editor_ribbon.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Size size, {
    bool hostTabs = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => editorRibbonTab.value = RibbonTab.home);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: Column(
            children: [
              if (hostTabs) const EditorRibbonTabs(),
              Expanded(
                child: EditorWidget(
                  hostTabs: hostTabs,
                  draft: EditorDrafts().draft('new', 'Yeni evrak'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String text(WidgetTester tester) => tester
      .widget<QuillEditor>(find.byType(QuillEditor).first)
      .controller
      .document
      .toPlainText();

  testWidgets('Hukuk: its groups, and a template written into the page', (
    tester,
  ) async {
    await pump(tester, const Size(1600, 900));
    await tester.tap(find.byKey(const ValueKey('ribbon-tab-legal')));
    await tester.pump();
    for (final group in [
      'Dilekçe',
      'İmzala ve gönder',
      'Ajanda',
      'Araştırma',
    ]) {
      expect(find.text(group), findsOneWidget, reason: group);
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('legal-templates')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cevap dilekçesi'));
    await tester.pumpAndSettle();
    expect(text(tester), contains('CEVAP VEREN'));
    expect(text(tester), contains('SONUÇ VE TALEP'));
    await tester.tap(find.text('Taraf satırı'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VEKİLİ'));
    await tester.pumpAndSettle();
    expect(text(tester), contains('VEKİLİ          : '));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Ekle and Görünüm draw their groups', (tester) async {
    await pump(tester, const Size(1440, 900));
    await tester.tap(find.byKey(const ValueKey('ribbon-tab-insert')));
    await tester.pump();
    expect(find.text('Üst ve alt bilgi'), findsOneWidget);
    expect(find.text('Antet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ribbon-tab-view')));
    await tester.pump();
    expect(find.text('Cetveller'), findsOneWidget);
    expect(find.text('Mobil görünüm'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a low window has one row and the rest in "…"', (tester) async {
    await pump(tester, const Size(960, 700));
    await tester.tap(find.byKey(const ValueKey('ribbon-tab-legal')));
    await tester.pump();
    expect(find.text('Şablon'), findsOneWidget);
    expect(find.text('Dilekçe'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('legal-more')));
    await tester.pumpAndSettle();
    expect(find.text('Bölüm başlığı'), findsOneWidget);
    expect(find.text('İmza bloğu'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('without a heading the tabs are a button', (tester) async {
    await pump(tester, const Size(420, 800), hostTabs: false);
    await tester.tap(find.byKey(const ValueKey('ribbon-tab-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ribbon-pick-legal')));
    await tester.pumpAndSettle();
    expect(editorRibbonTab.value, RibbonTab.legal);
    expect(find.text('Şablon'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}

// What a ribbon tab change rebuilds and how long it takes, with a long
// document open: a measurement, not part of the test suite.
//
//   systemd-run --user --scope -p MemoryMax=4G \
//     flutter test tool/measure_ribbon_test.dart
// ignore_for_file: avoid_print
import 'package:evrak_convert/services/editor/editor_drafts.dart';
import 'package:evrak_convert/ui/widgets/editor_ribbon.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a tab change with a 40 page document', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
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
              const EditorRibbonTabs(),
              Expanded(
                child: EditorWidget(
                  draft: EditorDrafts().draft('new', 'Yeni evrak'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final controller = tester
        .widget<QuillEditor>(find.byType(QuillEditor).first)
        .controller;
    final paragraph =
        'Davacı vekili olarak dosyaya sunulan bilirkişi raporuna karşı '
            'itirazlarımızı aşağıda sunuyoruz. ' *
        4;
    controller.document.insert(
      0,
      List.filled(
        int.parse(const String.fromEnvironment('N', defaultValue: '600')),
        paragraph,
      ).join('\n'),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    final rebuilt = <String, int>{};
    var counting = false;
    widgets.debugOnRebuildDirtyWidget = (element, _) {
      if (!counting) return;
      final name = element.widget.runtimeType.toString();
      rebuilt[name] = (rebuilt[name] ?? 0) + 1;
    };
    addTearDown(() => widgets.debugOnRebuildDirtyWidget = null);

    for (final tab in [
      RibbonTab.legal,
      RibbonTab.home,
      RibbonTab.insert,
      RibbonTab.view,
      RibbonTab.home,
      RibbonTab.legal,
      RibbonTab.home,
      RibbonTab.legal,
      RibbonTab.home,
    ]) {
      rebuilt.clear();
      counting = true;
      final watch = Stopwatch()..start();
      await tester.tap(find.byKey(ValueKey('ribbon-tab-${tab.name}')));
      await tester.pump();
      final first = watch.elapsedMilliseconds;
      await tester.pump(const Duration(milliseconds: 300));
      counting = false;
      final total = rebuilt.values.fold(0, (a, b) => a + b);
      final top =
          (rebuilt.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
              .take(12)
              .map((e) => '${e.key}:${e.value}')
              .join(', ');
      print(
        '${tab.label}: ilk kare $first ms, '
        'toplam ${watch.elapsedMilliseconds} ms, $total yeniden kurulum · $top',
      );
    }
    // Typing on Hukuk, Giriş built and hidden.
    for (final tab in [RibbonTab.legal, RibbonTab.home]) {
      await tester.tap(find.byKey(ValueKey('ribbon-tab-${tab.name}')));
      await tester.pump(const Duration(milliseconds: 300));
      rebuilt.clear();
      counting = true;
      final watch = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        controller.replaceText(
          10 + i,
          0,
          'a',
          TextSelection.collapsed(offset: 11 + i),
        );
        await tester.pump();
      }
      counting = false;
      final total = rebuilt.values.fold(0, (a, b) => a + b);
      print(
        'Yazma (${tab.label}): 20 harf ${watch.elapsedMilliseconds} ms, '
        '$total yeniden kurulum',
      );
      print(
        'QuillEditor:${rebuilt['QuillEditor'] ?? 0} '
        'QuillRawEditor:${rebuilt['QuillRawEditor'] ?? 0} '
        'EditorWidget:${rebuilt['EditorWidget'] ?? 0} '
        'EditableTextLine:${rebuilt['EditableTextLine'] ?? 0}',
      );
      print(
        (rebuilt.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .take(25)
            .map((e) => '${e.key}:${e.value}')
            .join(', '),
      );
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}

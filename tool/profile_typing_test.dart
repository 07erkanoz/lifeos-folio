// Where a keystroke's time goes in a long document: the Dart VM's own CPU
// samples, summed by function. A measurement, not part of the test suite.
//
//   systemd-run --user --scope -p MemoryMax=4G flutter test \
//     --enable-vmservice --dart-define=N=600 tool/profile_typing_test.dart
// ignore_for_file: avoid_print
import 'dart:developer' as dev;
import 'dart:isolate';

import 'package:evrak_convert/services/editor/editor_drafts.dart';
import 'package:evrak_convert/ui/widgets/editor_ribbon.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart' as vmio;

void main() {
  testWidgets('typing in a long document', (tester) async {
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
    final n = int.parse(const String.fromEnvironment('N', defaultValue: '600'));
    controller.document.insert(0, List.filled(n, paragraph).join('\n'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    final info = (await tester.runAsync(
      () => dev.Service.controlWebServer(enable: true),
    ))!;
    final service = (await tester.runAsync(
      () => vmio.vmServiceConnectUri('${info.serverWebSocketUri}'),
    ))!;
    final isolate = dev.Service.getIsolateId(Isolate.current)!;
    await tester.runAsync(() => service.clearCpuSamples(isolate));
    final from = (await tester.runAsync(service.getVMTimelineMicros))!;
    Future<String> heap() async {
      final i = (await tester.runAsync(() => service.getIsolate(isolate)))!;
      final heaps = i.json!['_heaps'] as Map? ?? const {};
      return [
        for (final e in heaps.entries)
          '${e.key}: ${(e.value as Map)['collections']} toplama, '
              '${(((e.value as Map)['time'] as num) * 1000).round()} ms',
      ].join(' · ');
    }

    print('Önce: ${await heap()}');

    var replace = 0, pump = 0;
    final inReplace = <(int, int)>[];
    for (var i = 0; i < 20; i++) {
      final r = Stopwatch()..start();
      final at = dev.Timeline.now;
      controller.replaceText(
        10 + i,
        0,
        'a',
        TextSelection.collapsed(offset: 11 + i),
      );
      replace += r.elapsedMicroseconds;
      inReplace.add((at, dev.Timeline.now));
      final p = Stopwatch()..start();
      await tester.pump();
      pump += p.elapsedMicroseconds;
    }
    final to = (await tester.runAsync(service.getVMTimelineMicros))!;
    print('Sonra: ${await heap()}');
    print(
      'N=$n · 20 harf · replaceText ${replace ~/ 1000} ms · '
      'kare ${pump ~/ 1000} ms',
    );

    final samples = (await tester.runAsync(
      () => service.getCpuSamples(
        isolate,
        from.timestamp!,
        to.timestamp! - from.timestamp!,
      ),
    ))!;
    final functions = samples.functions!;
    String name(int i) {
      final f = functions[i].function;
      if (f is vm.FuncRef) {
        final owner = f.owner;
        return owner is vm.ClassRef ? '${owner.name}.${f.name}' : '${f.name}';
      }
      return f is vm.NativeFunction ? '${f.name}' : '$f';
    }

    bool native(String n) =>
        n.startsWith('[') ||
        n.startsWith('__') ||
        const {'malloc', 'free', 'prctl'}.contains(n);
    final self = <String, int>{}, total = <String, int>{};
    final replaceSelf = <String, int>{}, replaceTotal = <String, int>{};
    var onlyNative = 0;
    for (final s in samples.samples!) {
      final t = s.timestamp!;
      if (inReplace.any((w) => t >= w.$1 && t <= w.$2)) {
        final names = [for (final i in s.stack!) name(i)];
        final own = names.firstWhere((n) => !native(n), orElse: () => '?');
        replaceSelf[own] = (replaceSelf[own] ?? 0) + 1;
        for (final k in {for (final n in names) n}) {
          replaceTotal[k] = (replaceTotal[k] ?? 0) + 1;
        }
      }
      final names = [for (final i in s.stack!) name(i)];
      if (names.isEmpty) continue;
      if (names.every(native)) onlyNative++;
      final own = names.firstWhere((n) => !native(n), orElse: () => '?');
      self[own] = (self[own] ?? 0) + 1;
      for (final k in {for (final n in names) n}) {
        total[k] = (total[k] ?? 0) + 1;
      }
    }
    String top(Map<String, int> m, int count) =>
        (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .take(count)
            .map((e) => '${e.value}\t${e.key}')
            .join('\n');
    print('Örnek ${samples.samples!.length}, yalnız yerel kod: $onlyNative');
    print('--- replaceText içinde, kendi\n${top(replaceSelf, 15)}');
    print('--- replaceText içinde, toplam\n${top(replaceTotal, 60)}');
    print(
      '--- Kendi zamanı (yerel kod en yakın Dart işlevine)\n${top(self, 30)}',
    );
    print('--- Toplam\n${top(total, 90)}');
    await tester.runAsync(service.dispose);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}

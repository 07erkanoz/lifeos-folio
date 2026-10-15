// How long a keystroke takes in a long document, in a real build (profile),
// as the engine counts its frames. A measurement, not part of the app.
//
//   flutter build linux --profile -t tool/typing_bench.dart --dart-define=N=600
//   env -u WAYLAND_DISPLAY GDK_BACKEND=x11 xvfb-run -a \
//     -s '-screen 0 1600x1000x24' build/linux/x64/profile/bundle/lifeos_folio
// ignore_for_file: avoid_print, depend_on_referenced_packages
import 'dart:async';
import 'dart:developer' as dev;
import 'dart:isolate';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart' as vmio;

import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/editor_drafts.dart';
import 'package:evrak_convert/ui/widgets/editor_ribbon.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';

const paragraphs = int.fromEnvironment('N', defaultValue: 600);

/// A document to open instead, as the archive opens it (--dart-define=FILE=).
const file = String.fromEnvironment('FILE');
const keys = 60;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
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
              child: file.isEmpty
                  ? EditorWidget(draft: EditorDrafts().draft('bench', 'Ölçüm'))
                  : EditorWidget(
                      initialFilePath: file,
                      initialFormat: EvrakFormat.fromExtension(
                        file.split('.').last,
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
  await Future<void>.delayed(Duration(seconds: file.isEmpty ? 3 : 12));
  final editor = _find<QuillEditor>()!;
  final controller = editor.controller;
  print(
    'BENCH belge: ${controller.document.root.childCount} satır/blok, '
    '${controller.document.length} karakter',
  );
  const paragraph =
      'Davacı vekili olarak dosyaya sunulan bilirkişi raporuna karşı '
      'itirazlarımızı aşağıda sunuyoruz. Davacı vekili olarak dosyaya '
      'sunulan bilirkişi raporuna karşı itirazlarımızı aşağıda sunuyoruz. '
      'Davacı vekili olarak dosyaya sunulan bilirkişi raporuna karşı '
      'itirazlarımızı aşağıda sunuyoruz.';
  if (file.isEmpty) {
    controller.document.insert(
      0,
      List.filled(paragraphs, paragraph).join('\n'),
    );
  }
  editor.focusNode.requestFocus();
  controller.updateSelection(
    const TextSelection.collapsed(offset: 10),
    ChangeSource.local,
  );
  await Future<void>.delayed(const Duration(seconds: 3));

  final frames = <FrameTiming>[];
  SchedulerBinding.instance.addTimingsCallback(frames.addAll);
  // Warmed first: the first keys pay for compiling nothing (AOT) but for
  // the caches the editor fills.
  for (var i = 0; i < 10; i++) {
    await _key(controller, 10 + i);
  }
  await Future<void>.delayed(const Duration(milliseconds: 500));
  frames.clear();

  // The VM's own samples of the keys, by function (--dart-define=PROFILE=1).
  const profile = bool.fromEnvironment('PROFILE');
  vm.VmService? service;
  String? isolate;
  int? from;
  if (profile) {
    final info = await dev.Service.controlWebServer(enable: true);
    print('PROF servis ${info.serverWebSocketUri}');
    service = await vmio.vmServiceConnectUri('${info.serverWebSocketUri}');
    print('PROF bağlandı');
    isolate = dev.Service.getIsolateId(Isolate.current)!;
    await service.clearCpuSamples(isolate);
    from = (await service.getVMTimelineMicros()).timestamp;
  }
  final replace = <int>[];
  for (var i = 0; i < keys; i++) {
    replace.add(await _key(controller, 20 + i));
  }
  if (service != null) {
    final to = (await service.getVMTimelineMicros()).timestamp!;
    print('PROF örnekler isteniyor');
    final samples = await service.getCpuSamples(isolate!, from!, to - from);
    final functions = samples.functions!;
    String name(int i) {
      final f = functions[i].function;
      if (f is vm.FuncRef) {
        final owner = f.owner;
        return owner is vm.ClassRef ? '${owner.name}.${f.name}' : '${f.name}';
      }
      return f is vm.NativeFunction ? '${f.name}' : '$f';
    }

    final total = <String, int>{}, self = <String, int>{};
    for (final s in samples.samples!) {
      final names = [for (final i in s.stack!) name(i)];
      if (names.isEmpty) continue;
      self[names.first] = (self[names.first] ?? 0) + 1;
      for (final k in {for (final n in names) n}) {
        total[k] = (total[k] ?? 0) + 1;
      }
    }
    String top(Map<String, int> m, int n) =>
        (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .take(n)
            .map((e) => 'PROF ${e.value}\t${e.key}')
            .join('\n');
    print('PROF örnek ${samples.samples!.length}');
    print('PROF --- kendi\n${top(self, 25)}');
    print('PROF --- toplam\n${top(total, 110)}');
  }
  // Timings are handed over in batches: waited for.
  await Future<void>.delayed(const Duration(seconds: 2));

  String ms(Iterable<int> us) {
    final l = us.toList()..sort();
    if (l.isEmpty) return '—';
    final median = l[l.length ~/ 2] / 1000;
    final p90 = l[((l.length * 9) ~/ 10).clamp(0, l.length - 1)] / 1000;
    final max = l.last / 1000;
    return 'ortanca ${median.toStringAsFixed(1)} · %90 '
        '${p90.toStringAsFixed(1)} · en çok ${max.toStringAsFixed(1)} ms';
  }

  // The frames a key made: those with work in them, not the caret's blink.
  final worked = [
    for (final f in frames)
      if (f.buildDuration.inMicroseconds > 2000) f,
  ];
  print(
    'BENCH N=$paragraphs paragraf, $keys tuş, ${frames.length} kare, '
    'işli ${worked.length}',
  );
  print(
    'BENCH işli kare, arayüz: '
    '${ms(worked.map((f) => f.buildDuration.inMicroseconds))}',
  );
  print(
    'BENCH işli kare, çizim: '
    '${ms(worked.map((f) => f.rasterDuration.inMicroseconds))}',
  );
  print('BENCH metin değişikliği (replaceText): ${ms(replace)}');
  print(
    'BENCH kare, arayüz (build+layout+paint): '
    '${ms(frames.map((f) => f.buildDuration.inMicroseconds))}',
  );
  print(
    'BENCH kare, çizim (raster): '
    '${ms(frames.map((f) => f.rasterDuration.inMicroseconds))}',
  );
  print(
    'BENCH kare, toplam: '
    '${ms(frames.map((f) => f.totalSpan.inMicroseconds))}',
  );
  exit(0);
}

/// One key: the letter written, then the frame it makes waited for.
Future<int> _key(QuillController controller, int at) async {
  final watch = Stopwatch()..start();
  controller.replaceText(at, 0, 'a', TextSelection.collapsed(offset: at + 1));
  final took = watch.elapsedMicroseconds;
  await SchedulerBinding.instance.endOfFrame;
  // Two keys a frame apart at most, as a fast typist's are.
  await Future<void>.delayed(const Duration(milliseconds: 60));
  return took;
}

T? _find<T extends Widget>() {
  T? found;
  void visit(Element e) {
    if (found != null) return;
    if (e.widget is T) {
      found = e.widget as T;
      return;
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

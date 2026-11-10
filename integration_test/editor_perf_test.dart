import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/docx/docx_bridge.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';

/// How long the editor takes over a keystroke, a selection and a format,
/// in a document of 20, 150 and 600 paragraphs (about 75 pages), on a real
/// window and as the built app runs. Run as a profile build, where the
/// times are those the lawyer meets:
///
///   env -u WAYLAND_DISPLAY GDK_BACKEND=x11 xvfb-run -a \
///     -s '-screen 0 1400x1000x24' dbus-run-session -- flutter drive \
///     --profile --driver=test_driver/integration_test.dart \
///     --target=integration_test/editor_perf_test.dart -d linux
///
/// Each line printed says the time the interface thread took over a frame
/// (what a slow frame is made of) and the whole time until the frame was
/// on screen. A frame over 16 ms is one the eye can miss.
const _paragraph =
    'Davalı işveren, müvekkilin iş sözleşmesini 14.03.2026 tarihinde haklı '
    'bir neden göstermeksizin feshetmiştir. İş Kanunu m. 18 ve TMK m. 2 '
    'uyarınca feshin geçerli bir nedene dayanması gerekir; Yargıtay 9. '
    'Hukuk Dairesi\'nin 2021/1234 E., 2021/5678 K. sayılı kararı da bu '
    'yöndedir. Kıdem ve ihbar tazminatı ile yıllık izin ücreti ödenmemiştir.';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  for (final count in [20, 150, 600]) {
    testWidgets('editor timings, $count paragraphs', (tester) async {
      final dir = await Directory.systemTemp.createTemp('folio-perf-');
      addTearDown(() => dir.delete(recursive: true));
      DocumentHistory.instance = DocumentHistory(
        directory: Directory('${dir.path}/history'),
      );
      final file = File('${dir.path}/belge.docx');
      await file.writeAsBytes(
        await DocxBridge.writeBytes(
          DocModel(
            blocks: [
              for (var i = 0; i < count; i++)
                DocBlock(
                  plainText: '${i + 1}. $_paragraph',
                  alignment: DocAlignment.justify,
                  spans: const [
                    DocSpan(startOffset: 0, length: 12, bold: true),
                  ],
                ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          home: Scaffold(
            body: EditorWidget(
              initialFilePath: file.path,
              initialFormat: EvrakFormat.docx,
            ),
          ),
        ),
      );
      for (
        var i = 0;
        i < 400 && find.byType(QuillEditor).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(seconds: 3));
      final controller = tester
          .widget<QuillEditor>(find.byType(QuillEditor))
          .controller;
      await tester.tap(find.byType(QuillEditor));
      await tester.pump(const Duration(milliseconds: 500));
      final length = controller.document.length;

      final frames = <FrameTiming>[];
      void collect(List<FrameTiming> timings) => frames.addAll(timings);
      SchedulerBinding.instance.addTimingsCallback(collect);
      addTearDown(
        () => SchedulerBinding.instance.removeTimingsCallback(collect),
      );

      /// [act] done [times] times, a frame after each; the interface
      /// thread's worst and middle frame, and the whole time of one.
      Future<void> measure(
        String name,
        void Function(int i) act, {
        int times = 20,
      }) async {
        await tester.pump(const Duration(milliseconds: 400));
        frames.clear();
        final whole = Stopwatch()..start();
        for (var i = 0; i < times; i++) {
          act(i);
          await tester.pump();
        }
        final each = whole.elapsedMicroseconds / times / 1000;
        await tester.pump(const Duration(milliseconds: 300));
        final builds = [
          for (final f in frames) f.buildDuration.inMicroseconds / 1000,
        ]..sort();
        final rasters = [
          for (final f in frames) f.rasterDuration.inMicroseconds / 1000,
        ]..sort();
        String ms(double v) => v.toStringAsFixed(1);
        // ignore: avoid_print
        print(
          'PERF n=$count ${name.padRight(28)} '
          'arayüz ortanca ${builds.isEmpty ? '-' : ms(builds[builds.length ~/ 2])} ms, '
          'en uzun ${builds.isEmpty ? '-' : ms(builds.last)} ms; '
          'çizim ortanca ${rasters.isEmpty ? '-' : ms(rasters[rasters.length ~/ 2])} ms; '
          'bir adım ${ms(each)} ms',
        );
      }

      var at = length ~/ 2;
      controller.updateSelection(
        TextSelection.collapsed(offset: at),
        ChangeSource.local,
      );
      await measure('harf yazma (ortada)', (_) {
        controller.replaceText(
          at,
          0,
          'a',
          TextSelection.collapsed(offset: at + 1),
        );
        at++;
      });
      await measure('harf silme', (_) {
        controller.replaceText(
          at - 1,
          1,
          '',
          TextSelection.collapsed(offset: at - 1),
        );
        at--;
      });
      await measure('imleci gezdirme', (i) {
        controller.updateSelection(
          TextSelection.collapsed(offset: at + i * 37),
          ChangeSource.local,
        );
      });
      var end = at;
      await measure('seçimi genişletme', (_) {
        end = (end + 400).clamp(0, length - 1);
        controller.updateSelection(
          TextSelection(baseOffset: at, extentOffset: end),
          ChangeSource.local,
        );
      });
      await measure('seçiliyi kalın yapma', (i) {
        controller.formatSelection(
          i.isEven ? Attribute.bold : Attribute.clone(Attribute.bold, null),
        );
      }, times: 6);
      await measure('tümünü seçme', (i) {
        controller.updateSelection(
          i.isEven
              ? TextSelection(baseOffset: 0, extentOffset: length - 1)
              : TextSelection.collapsed(offset: at),
          ChangeSource.local,
        );
      }, times: 6);
      controller.updateSelection(
        TextSelection(baseOffset: 0, extentOffset: length - 1),
        ChangeSource.local,
      );
      await measure('tümünü italik yapma', (i) {
        controller.formatSelection(
          i.isEven ? Attribute.italic : Attribute.clone(Attribute.italic, null),
        );
      }, times: 2);
      controller.updateSelection(
        TextSelection.collapsed(offset: at),
        ChangeSource.local,
      );
      await measure('yeni paragraf (Enter)', (_) {
        controller.replaceText(
          at,
          0,
          '\n',
          TextSelection.collapsed(offset: at + 1),
        );
        at++;
      }, times: 6);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });
  }
}

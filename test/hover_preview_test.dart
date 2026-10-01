import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/ui/widgets/hover_document_preview.dart';
import 'package:evrak_convert/ui/theme/theme_controller.dart';

void main() {
  testWidgets(
    'hover waits, closes on exit/Escape/click/scroll and ignores late results',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final file = EvrakFile(
        path: '/tmp/hover.udf',
        name: 'Dilekçe.udf',
        format: EvrakFormat.udf,
        sizeInBytes: 1,
      );
      var calls = 0, opens = 0;
      var enabled = true;
      final pending = <Completer<HoverPreviewContent?>>[];
      late StateSetter update;
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: ListView(
                  controller: scroll,
                  children: [
                    HoverDocumentPreview(
                      file: file,
                      excerpt: 'Belge içeriğinden kısa alıntı',
                      enabled: enabled,
                      loader: (wanted) {
                        calls++;
                        final result = Completer<HoverPreviewContent?>();
                        pending.add(result);
                        return result.future;
                      },
                      child: SizedBox(
                        height: 100,
                        child: TextButton(
                          onPressed: () => opens++,
                          child: const Text('Evrak'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 1800),
                  ],
                ),
              );
            },
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1080, 700));
      Future<void> enter() async {
        await mouse.moveTo(const Offset(80, 50));
        await tester.pump();
      }

      Future<void> show() async {
        await enter();
        await tester.pump(const Duration(milliseconds: 551));
        await tester.pump(const Duration(milliseconds: 150));
      }

      final popup = find.byKey(const ValueKey('hover-document-preview'));
      await enter();
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, 0);
      await mouse.moveTo(const Offset(80, 200));
      await tester.pump(const Duration(milliseconds: 600));
      expect(calls, 0);
      await show();
      expect(popup, findsOneWidget);
      expect(calls, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(popup, findsNothing);
      pending.removeAt(0).complete(null);
      await tester.pump();
      expect(popup, findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 1);
      await mouse.moveTo(const Offset(80, 200));
      await show();
      await mouse.down(const Offset(80, 50));
      await mouse.up();
      await tester.pump();
      expect(opens, 1);
      expect(popup, findsNothing);
      await mouse.moveTo(const Offset(80, 200));
      await show();
      scroll.jumpTo(30);
      await tester.pump();
      expect(popup, findsNothing);
      scroll.jumpTo(0);
      await tester.pump();
      await mouse.moveTo(const Offset(80, 200));
      await show();
      update(() => enabled = false);
      await tester.pump();
      await tester.pump();
      expect(popup, findsNothing);
      final before = calls;
      await mouse.moveTo(const Offset(80, 200));
      await show();
      expect(calls, before);
      for (final result in pending) {
        result.complete(null);
      }
      await tester.pump();
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      scroll.dispose();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  test(
    'hover is on by default and its persisted setting survives theme changes',
    () async {
      final dir = await Directory.systemTemp.createTemp('folio-hover-setting-');
      final path = '${dir.path}/appearance.json';
      final settings = ThemeController(settingsPath: path);
      expect(settings.hoverPreview, true);
      settings.setHoverPreview(false);
      settings.setMode(ThemeMode.dark);
      await settings.saved;
      final reloaded = ThemeController(settingsPath: path);
      await reloaded.load();
      expect(reloaded.hoverPreview, false);
      expect(reloaded.mode, ThemeMode.dark);
      reloaded.setHoverPreview(true);
      await reloaded.saved;
      final again = ThemeController(settingsPath: path);
      await again.load();
      expect(again.hoverPreview, true);
      settings.dispose();
      reloaded.dispose();
      again.dispose();
      await dir.delete(recursive: true);
    },
  );
}

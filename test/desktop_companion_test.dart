import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/desktop/desktop_companion.dart';

void main() {
  testWidgets(
    'hidden-window palette does not wait for a frame and restores main bounds',
    (tester) async {
      const channel = MethodChannel('window_manager');
      bool visible = true;
      final calls = <String>[];
      final bounds = <String, double>{
        'x': 40,
        'y': 70,
        'width': 1200,
        'height': 800,
      };
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        switch (call.method) {
          case 'isVisible':
            return visible;
          case 'isMaximized':
          case 'isFullScreen':
          case 'isMinimized':
            return false;
          case 'getBounds':
            return bounds;
          case 'hide':
            visible = false;
          case 'show':
            visible = true;
          case 'setBounds':
            final value = call.arguments as Map;
            for (final key in bounds.keys.toList()) {
              if (value[key] is num) {
                bounds[key] = (value[key] as num).toDouble();
              }
            }
        }
        return null;
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.leanflutter.plugins/screen_retriever'),
        (call) async {
          final display = {
            'id': '1',
            'name': 'Test',
            'size': {'width': 1600.0, 'height': 1000.0},
            'visiblePosition': {'dx': 0.0, 'dy': 0.0},
            'visibleSize': {'width': 1600.0, 'height': 1000.0},
          };
          return switch (call.method) {
            'getAllDisplays' => {
              'displays': [display],
            },
            'getCursorScreenPoint' => {'dx': 100.0, 'dy': 100.0},
            _ => display,
          };
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.erkanoz.folio/quick_search'),
        (_) async => null,
      );
      var homeRequests = 0;
      final companion = DesktopCompanion(onShowHome: () => homeRequests++);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.expand()));
      // Intentionally no pump while transition is running: hidden Linux windows
      // cannot produce a frame, but native show must still be reached.
      await companion.toggleQuick();
      expect(companion.quick, isTrue);
      expect(visible, isTrue);
      expect(calls, contains('show'));
      expect(companion.error, isNull);
      final launched = companion.launches.stream.first;
      await companion.showMain(paths: ['/synthetic/document.udf']);
      expect(await launched, ['/synthetic/document.udf']);
      expect(companion.quick, isFalse);
      expect(bounds['width'], 1200);
      expect(bounds['height'], 800);
      expect(
        homeRequests,
        0,
        reason: 'a document request must open its preview',
      );
      await companion.toggleQuick();
      await companion.dismiss();
      expect(
        homeRequests,
        0,
        reason: 'Escape from the palette restores the previous screen',
      );
      companion.enabled = true;
      companion.trayReady = true;
      companion.onWindowClose();
      await tester.pump();
      expect(visible, isFalse);
      await companion.showMain();
      expect(visible, isTrue);
      expect(
        homeRequests,
        1,
        reason: 'normal tray reopening requests the homepage',
      );
      companion.onWindowRestore();
      expect(
        homeRequests,
        1,
        reason: 'OS minimize/restore does not change navigation',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      companion.dispose();
      await tester.pump();
    },
  );
}

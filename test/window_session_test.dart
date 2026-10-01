import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/desktop/window_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'normal size and fullscreen survive restart; palette size is ignored',
    () async {
      final dir = await Directory.systemTemp.createTemp('folio-window-');
      addTearDown(() => dir.delete(recursive: true));
      var fullscreen = false;
      var maximized = false;
      var size = const Size(1300, 850);
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('window_manager'), (
            call,
          ) async {
            calls.add(call.method);
            switch (call.method) {
              case 'isFullScreen':
                return fullscreen;
              case 'isMaximized':
                return maximized;
              case 'isMinimized':
                return false;
              case 'getBounds':
                return {
                  'x': 0.0,
                  'y': 0.0,
                  'width': size.width,
                  'height': size.height,
                };
              case 'setBounds':
                final args = call.arguments as Map;
                if (args['width'] != null) {
                  size = Size(
                    (args['width'] as num).toDouble(),
                    (args['height'] as num).toDouble(),
                  );
                }
              case 'setFullScreen':
                fullscreen = true;
              case 'maximize':
                maximized = true;
            }
            return null;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dev.leanflutter.plugins/screen_retriever'),
            (call) async {
              final display = {
                'id': '1',
                'name': 'Test',
                'size': {'width': 1920.0, 'height': 1080.0},
                'visiblePosition': {'dx': 0.0, 'dy': 0.0},
                'visibleSize': {'width': 1920.0, 'height': 1080.0},
              };
              return switch (call.method) {
                'getAllDisplays' => {
                  'displays': [display],
                },
                'getCursorScreenPoint' => {'dx': 10.0, 'dy': 10.0},
                _ => display,
              };
            },
          );
      final file = File('${dir.path}/session.json');
      var session = await WindowSession.load(file: file);
      await session.restore();
      size = const Size(1300, 850);
      await session.save();
      maximized = true;
      await session.save();
      fullscreen = true;
      size = const Size(1920, 1080);
      await session.save();
      session.suspended = true;
      size = const Size(740, 580);
      fullscreen = false;
      maximized = false;
      await session.save();
      session.dispose();
      session = await WindowSession.load(file: file);
      expect(session.data.size, const Size(1300, 850));
      expect(session.data.maximized, isTrue);
      expect(session.data.fullscreen, isTrue);
      await session.restore();
      expect(fullscreen, isTrue);
      expect(maximized, isTrue);
      session.dispose();
      await file.writeAsString('invalid json');
      session = await WindowSession.load(file: file);
      expect(session.data.size, const Size(1200, 800));
      session.dispose();
    },
  );
}

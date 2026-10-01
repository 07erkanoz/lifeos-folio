import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/ui/widgets/desktop_frame.dart';
import 'package:evrak_convert/ui/widgets/folio_about_dialog.dart';

void main() {
  testWidgets('window controls toggle native state; F11 exits fullscreen', (
    tester,
  ) async {
    const channel = MethodChannel('window_manager');
    bool maximized = false, fullscreen = false;
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      switch (call.method) {
        case 'isMaximized':
          return maximized;
        case 'isFullScreen':
          return fullscreen;
        case 'maximize':
          maximized = true;
        case 'unmaximize':
          maximized = false;
        case 'setFullScreen':
          fullscreen = (call.arguments as Map)['isFullScreen'] as bool;
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    var about = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            DesktopFrame(onAbout: () => about++, child: child!),
        home: const Focus(autofocus: true, child: SizedBox.expand()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('folio-titlebar'))).height,
      38,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(find.byTooltip('Ekranı kapla')),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
    await tester.tap(find.byTooltip('Ekranı kapla'));
    await tester.pumpAndSettle();
    expect(maximized, isTrue);
    await tester.tap(find.byTooltip('Önceki boyut'));
    await tester.pumpAndSettle();
    expect(maximized, isFalse);
    await tester.tap(find.byTooltip('Tam ekran (F11)'));
    await tester.pumpAndSettle();
    expect(fullscreen, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(fullscreen, isFalse);
    await tester.tap(find.byTooltip('Hakkında'));
    expect(about, 1);
    await tester.tap(find.byTooltip('Simge durumuna küçült'));
    await tester.pumpAndSettle();
    expect(calls, contains('minimize'));
    await tester.tap(find.byTooltip('Uygulamayı kapat'));
    await tester.pumpAndSettle();
    expect(calls, contains('close'));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'about page includes attribution, domains and readable free-use license',
    (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: FolioAboutDialog())),
      );
      expect(
        find.text('Erkan ÖZ tarafından geliştirilmiştir.'),
        findsOneWidget,
      );
      expect(find.text('lifeos.com.tr'), findsOneWidget);
      expect(find.text('erkanoz.com'), findsOneWidget);
      await tester.tap(find.text('Kullanım lisansı'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ücretsiz kullanım lisansı'), findsOneWidget);
      expect(find.textContaining('kişisel ve iş amaçlı'), findsOneWidget);
      await tester.tap(find.text('Kapat'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(390, 600);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:evrak_convert/ui/widgets/image_viewer_widget.dart';
import 'package:evrak_convert/ui/widgets/swipe_pages.dart';

/// A finger, as opposed to a mouse.
Future<void> swipe(WidgetTester tester, Finder target, double dx) async {
  final gesture = await tester.startGesture(
    tester.getCenter(target),
    kind: PointerDeviceKind.touch,
  );
  for (var i = 0; i < 8; i++) {
    await gesture.moveBy(Offset(dx / 8, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump();
}

void main() {
  testWidgets('a finger turns the page, a mouse does not', (tester) async {
    final turned = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipePages(
            enabled: () => true,
            onSwipe: turned.add,
            child: const SizedBox.expand(child: ColoredBox(color: Colors.grey)),
          ),
        ),
      ),
    );
    final target = find.byType(SwipePages);

    await swipe(tester, target, -200);
    expect(turned, [true], reason: 'sola kaydırmak ileri gitmeli');
    await swipe(tester, target, 200);
    expect(turned, [true, false]);

    // A mouse drag is how text gets selected; it must not turn anything.
    final mouse = await tester.startGesture(
      tester.getCenter(target),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(-200, 0));
    await mouse.up();
    await tester.pump();
    expect(turned.length, 2);
  });

  testWidgets('a small or slanted movement is left alone', (tester) async {
    final turned = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipePages(
            enabled: () => true,
            onSwipe: turned.add,
            child: const SizedBox.expand(child: ColoredBox(color: Colors.grey)),
          ),
        ),
      ),
    );
    final target = find.byType(SwipePages);

    // Too short to be meant.
    await swipe(tester, target, -30);
    expect(turned, isEmpty);

    // Scrolling down a long document, which drifts sideways a little.
    final gesture = await tester.startGesture(
      tester.getCenter(target),
      kind: PointerDeviceKind.touch,
    );
    await gesture.moveBy(const Offset(-80, -300));
    await gesture.up();
    await tester.pump();
    expect(turned, isEmpty, reason: 'aşağı kaydırma sayfa çevirmemeli');
  });

  testWidgets('a zoomed picture pans instead of moving on', (tester) async {
    var allowed = false;
    final turned = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipePages(
            enabled: () => allowed,
            onSwipe: turned.add,
            child: const SizedBox.expand(child: ColoredBox(color: Colors.grey)),
          ),
        ),
      ),
    );
    final target = find.byType(SwipePages);
    await swipe(tester, target, -200);
    expect(turned, isEmpty);
    allowed = true;
    await swipe(tester, target, -200);
    expect(turned, [true]);
  });

  testWidgets('full screen leaves the viewer nothing but the picture', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('fullscreen-image-'),
    ))!;
    final file = File('${dir.path}/foto.png');
    await tester.runAsync(
      () async => file.writeAsBytesSync(
        img.encodePng(img.Image(width: 1600, height: 1200)),
      ),
    );

    Future<double> pictureHeight({required bool chrome}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImageViewerWidget(filePath: file.path, chrome: chrome),
          ),
        ),
      );
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        if (tester.getSize(find.byType(Image)).width > 0) break;
      }
      // The area the picture is given, not the picture's own size: a wide
      // photograph is letterboxed either way.
      return tester.getSize(find.byType(SwipePages)).height;
    }

    final withChrome = await pictureHeight(chrome: true);
    // The viewer's own row of buttons: rotate, zoom, fit, read text.
    expect(find.byIcon(Icons.rotate_right_rounded), findsOneWidget);

    final full = await pictureHeight(chrome: false);
    expect(find.byIcon(Icons.rotate_right_rounded), findsNothing);
    expect(full, greaterThan(withChrome));
    expect(full, closeTo(892, 1));

    await tester.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('swiping a picture asks for the one beside it', (tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('swipe-image-'),
    ))!;
    final file = File('${dir.path}/foto.png');
    await tester.runAsync(
      () async => file.writeAsBytesSync(
        img.encodePng(img.Image(width: 1600, height: 1200)),
      ),
    );
    final moved = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageViewerWidget(filePath: file.path, onPastEnd: moved.add),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (tester.getSize(find.byType(Image)).width > 0) break;
    }

    // A fitted picture decodes only what the screen can show.
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain);
    expect(tester.getSize(find.byType(Image)).width, lessThanOrEqualTo(412.5));

    await swipe(tester, find.byType(SwipePages), -200);
    expect(moved, [true]);
    await swipe(tester, find.byType(SwipePages), 200);
    expect(moved, [true, false]);

    await tester.runAsync(() => dir.delete(recursive: true));
  });
}

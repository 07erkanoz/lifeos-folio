import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:evrak_convert/services/preview/image_crop.dart';
import 'package:evrak_convert/ui/widgets/image_crop_overlay.dart';
import 'package:evrak_convert/ui/widgets/image_viewer_widget.dart';

import 'support/temp_directory.dart';

/// A picture whose corners can be told apart, so a turn can be seen.
img.Image _marked() {
  final picture = img.Image(width: 4, height: 2);
  img.fill(picture, color: img.ColorRgb8(0, 0, 0));
  picture.setPixelRgb(0, 0, 255, 0, 0); // sol üst kırmızı
  picture.setPixelRgb(3, 0, 0, 255, 0); // sağ üst yeşil
  return picture;
}

({int r, int g, int b}) _at(img.Image picture, int x, int y) {
  final pixel = picture.getPixel(x, y);
  return (r: pixel.r.round(), g: pixel.g.round(), b: pixel.b.round());
}

void main() {
  test('a quarter turn goes the way the screen turns it', () {
    // Flutter'ın RotatedBox(quarterTurns: 1) saat yönünde çevirir; kaydedilen
    // dosya ekrandakiyle aynı olmalı. Yönü varsaymak yerine ölçüyoruz:
    // saat yönünde sol üst köşe sağ üste gider.
    final turned = img.decodeImage(
      cutOut((
        bytes: img.encodePng(_marked()),
        turns: 1,
        left: 0,
        top: 0,
        width: 1,
        height: 1,
        jpeg: false,
      )),
    )!;
    expect(turned.width, 2, reason: 'çeyrek tur kutuyu çevirir');
    expect(turned.height, 4);
    expect(_at(turned, 1, 0), (r: 255, g: 0, b: 0), reason: 'kırmızı sağ üste');
    expect(_at(turned, 1, 3), (r: 0, g: 255, b: 0), reason: 'yeşil sağ alta');
  });

  test('only the framed part is kept', () {
    final cut = img.decodeImage(
      cutOut((
        bytes: img.encodePng(img.Image(width: 400, height: 200)),
        turns: 0,
        left: .25,
        top: .5,
        width: .5,
        height: .5,
        jpeg: false,
      )),
    )!;
    expect(cut.width, 200);
    expect(cut.height, 100);
  });

  test('a selection dragged past the edge is brought back, not thrown', () {
    final cut = img.decodeImage(
      cutOut((
        bytes: img.encodePng(img.Image(width: 100, height: 100)),
        turns: 0,
        left: .9,
        top: .9,
        width: .5,
        height: .5,
        jpeg: false,
      )),
    )!;
    expect(cut.width, 10);
    expect(cut.height, 10);
  });

  test('the original is left alone and the crop lands beside it', () async {
    final dir = await Directory.systemTemp.createTemp('crop-');
    addTearDown(() => dir.delete(recursive: true));
    final original = File('${dir.path}/tatil.png');
    await original.writeAsBytes(
      img.encodePng(img.Image(width: 60, height: 40)),
    );
    final before = await original.readAsBytes();

    final first = await ImageCrop.save(
      source: original.path,
      original: original.path,
      quarterTurns: 0,
      fraction: const Rect.fromLTWH(0, 0, .5, .5),
    );
    expect(first.path, endsWith('tatil (kırpılmış).png'));
    expect(await original.readAsBytes(), before, reason: 'aslına dokunulmaz');
    final saved = img.decodeImage(await first.readAsBytes())!;
    expect(saved.width, 30);

    // İkincisi birincisinin üstüne yazmaz.
    final second = await ImageCrop.save(
      source: original.path,
      original: original.path,
      quarterTurns: 0,
      fraction: const Rect.fromLTWH(0, 0, .25, .25),
    );
    expect(second.path, endsWith('tatil (kırpılmış 2).png'));
  });

  testWidgets('a frame dragged over a photograph is cut and kept beside it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('crop-ui-'),
    ))!;
    final original = File('${dir.path}/tatil.png');
    await tester.runAsync(
      () async => original.writeAsBytesSync(
        img.encodePng(img.Image(width: 400, height: 400)),
      ),
    );

    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageViewerWidget(
            filePath: original.path,
            onCropped: (path) => saved = path,
          ),
        ),
      ),
    );

    // Kırpma, görselin kaç piksel olduğu okunana kadar açılmaz.
    final button = find.byKey(const ValueKey('image-crop'));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (button.evaluate().isNotEmpty &&
          tester.widget<IconButton>(button).onPressed != null) {
        break;
      }
    }
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);

    await tester.tap(button);
    await tester.pump();
    final save = find.byKey(const ValueKey('image-crop-save'));
    expect(
      tester.widget<FilledButton>(save).onPressed,
      isNull,
      reason: 'çerçeve çizilmeden kırpılacak bir şey yok',
    );
    expect(find.textContaining('sürükleyin'), findsOneWidget);

    final over = tester.getRect(find.byType(CropOverlay));
    await tester.dragFrom(
      over.center - const Offset(70, 70),
      const Offset(140, 140),
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    expect(find.textContaining('Aslı olduğu gibi kalır'), findsOneWidget);

    await tester.tap(save);
    for (var i = 0; i < 80 && saved == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(saved, isNotNull);
    expect(saved, endsWith('tatil (kırpılmış).png'));

    final cut = img.decodeImage(File(saved!).readAsBytesSync())!;
    expect(cut.width, lessThan(400));
    expect(cut.width, greaterThan(40));
    // Aslına dokunulmadı.
    expect(img.decodeImage(original.readAsBytesSync())!.width, 400);
    // Çerçeve kaydedilince kapanır.
    expect(find.byKey(const ValueKey('image-crop-save')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await removeTemporaryDirectory(tester, dir);
  });
}

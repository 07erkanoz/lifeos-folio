import 'dart:io';
import 'dart:ui' show Offset, Rect;

import 'package:evrak_convert/services/preview/photo_edit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  final picture = img.Image(width: 200, height: 100)
    ..clear(img.ColorRgb8(200, 150, 100));
  final bytes = img.encodePng(picture);

  RenderedPhoto render(PhotoEdit edit, PhotoStage stage) => PhotoEditing.render(
    (bytes: bytes, edit: edit, stage: stage, maxSide: 0, jpeg: false),
  );

  test('a quarter turn, a crop and the page straightened change its size', () {
    expect(render(const PhotoEdit(turns: 1), PhotoStage.finished).width, 100);
    final cropped = render(
      const PhotoEdit(crop: Rect.fromLTRB(0, 0, .5, 1)),
      PhotoStage.finished,
    );
    expect((cropped.width, cropped.height), (100, 100));
    // Uncropped while cropping: the whole picture to frame.
    expect(
      render(
        const PhotoEdit(crop: Rect.fromLTRB(0, 0, .5, 1)),
        PhotoStage.uncropped,
      ).width,
      200,
    );
    final page = render(
      const PhotoEdit(
        corners: [
          Offset(.25, 0),
          Offset(.75, 0),
          Offset(.75, 1),
          Offset(.25, 1),
        ],
      ),
      PhotoStage.finished,
    );
    expect(page.width, closeTo(100, 2));
  });

  test(
    'the document look is gray; a black box is burnt in only when saved',
    () {
      final gray = img.decodePng(
        render(
          const PhotoEdit(filter: PhotoFilter.gray),
          PhotoStage.finished,
        ).bytes,
      )!;
      final px = gray.getPixel(10, 10);
      expect(px.r, px.g);
      expect(px.g, px.b);
      const boxed = PhotoEdit(redactions: [Rect.fromLTRB(.4, .4, .6, .6)]);
      final shown = img.decodePng(render(boxed, PhotoStage.finished).bytes)!;
      expect(
        shown.getPixel(100, 50).r,
        isNot(0),
        reason: 'the screen draws it',
      );
      final saved = img.decodePng(render(boxed, PhotoStage.saved).bytes)!;
      expect(saved.getPixel(100, 50).r, 0);
    },
  );

  test('the copy lands beside the photograph, never over it', () async {
    final dir = Directory.systemTemp.createTempSync('folio-photo-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final original = File('${dir.path}/foto.png')..writeAsBytesSync(bytes);
    final copy = await PhotoEditing.save(
      source: original.path,
      original: original.path,
      edit: const PhotoEdit(turns: 1),
      fallback: () async => dir,
    );
    expect(copy.path, endsWith('foto (düzenlenmiş).png'));
    expect(original.readAsBytesSync(), bytes);
    expect(img.decodePng(copy.readAsBytesSync())!.width, 100);
  });
}

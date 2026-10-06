import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// The looks a photographed page can be given.
enum PhotoFilter { original, document, gray, colorDocument }

/// A line drawn on the picture, its points as shares of the picture.
@immutable
class PhotoStroke {
  const PhotoStroke(this.points);
  final List<Offset> points;
}

/// A note written on the picture, at a share of it.
@immutable
class PhotoText {
  const PhotoText(this.at, this.text);
  final Offset at;
  final String text;
}

/// What is done to a photograph, in the order it is done (docs/design/
/// mobil-galeri-taslak.png): the page's four corners straightened, quarter
/// turns, a crop, a look and its adjustments, black boxes over what must
/// not be seen, and lines and notes drawn on it. Every place is a share of
/// the picture at its stage, so that the small copy on the screen and the
/// photograph itself are edited alike. The photograph is never written
/// over; [PhotoEditing.save] writes a copy.
@immutable
class PhotoEdit {
  const PhotoEdit({
    this.corners,
    this.turns = 0,
    this.crop,
    this.filter = PhotoFilter.original,
    this.brightness = 0,
    this.contrast = 0,
    this.sharpness = 0,
    this.redactions = const [],
    this.strokes = const [],
    this.texts = const [],
  });

  /// The page's corners on the photograph as taken: top left, top right,
  /// bottom right, bottom left. Null: the photograph as it is.
  final List<Offset>? corners;

  /// Quarter turns clockwise, after the corners.
  final int turns;

  /// The part kept, of the straightened and turned picture.
  final Rect? crop;
  final PhotoFilter filter;

  /// -1 to 1, 0 changing nothing; [sharpness] 0 to 1.
  final double brightness, contrast, sharpness;

  /// On the finished picture: black boxes, lines, notes.
  final List<Rect> redactions;
  final List<PhotoStroke> strokes;
  final List<PhotoText> texts;

  bool get isEmpty =>
      corners == null &&
      turns % 4 == 0 &&
      crop == null &&
      filter == PhotoFilter.original &&
      brightness == 0 &&
      contrast == 0 &&
      sharpness == 0 &&
      redactions.isEmpty &&
      strokes.isEmpty &&
      texts.isEmpty;

  PhotoEdit copyWith({
    Object? corners = _keep,
    int? turns,
    Object? crop = _keep,
    PhotoFilter? filter,
    double? brightness,
    double? contrast,
    double? sharpness,
    List<Rect>? redactions,
    List<PhotoStroke>? strokes,
    List<PhotoText>? texts,
  }) => PhotoEdit(
    corners: identical(corners, _keep)
        ? this.corners
        : corners as List<Offset>?,
    turns: turns ?? this.turns,
    crop: identical(crop, _keep) ? this.crop : crop as Rect?,
    filter: filter ?? this.filter,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    sharpness: sharpness ?? this.sharpness,
    redactions: redactions ?? this.redactions,
    strokes: strokes ?? this.strokes,
    texts: texts ?? this.texts,
  );

  static const _keep = Object();
}

/// How far a picture is taken: the photograph untouched (to place the
/// corners on), straightened and turned with its look but uncropped (to
/// crop), all but what is drawn on it (the screen draws that itself), or
/// everything (the copy saved).
enum PhotoStage { untouched, uncropped, finished, saved }

/// A picture made, with its size.
typedef RenderedPhoto = ({Uint8List bytes, int width, int height});

typedef PhotoJob = ({
  Uint8List bytes,
  PhotoEdit edit,
  PhotoStage stage,
  int maxSide,
  bool jpeg,
});

abstract final class PhotoEditing {
  /// [job]'s picture made; run with `compute`, away from the screen.
  static RenderedPhoto render(PhotoJob job) {
    var picture = img.decodeImage(job.bytes);
    if (picture == null) throw const FormatException('Görsel çözülemedi.');
    picture = img.bakeOrientation(picture);
    if (job.maxSide > 0 &&
        math.max(picture.width, picture.height) > job.maxSide) {
      picture = picture.width >= picture.height
          ? img.copyResize(picture, width: job.maxSide)
          : img.copyResize(picture, height: job.maxSide);
    }
    final edit = job.edit;
    if (job.stage != PhotoStage.untouched) {
      picture = _straighten(picture, edit.corners);
      final turns = edit.turns % 4;
      if (turns != 0) picture = img.copyRotate(picture, angle: turns * 90);
      if (job.stage != PhotoStage.uncropped && edit.crop != null) {
        picture = _crop(picture, edit.crop!);
      }
      picture = _look(picture, edit);
      if (job.stage == PhotoStage.saved) _draw(picture, edit);
    }
    final bytes = job.jpeg
        ? img.encodeJpg(picture, quality: 92)
        : img.encodePng(picture, level: 1);
    return (bytes: bytes, width: picture.width, height: picture.height);
  }

  /// The page cut out along its corners and laid flat, as large as its
  /// edges are long.
  static img.Image _straighten(img.Image picture, List<Offset>? corners) {
    if (corners == null || corners.length != 4) return picture;
    img.Point at(Offset o) => img.Point(
      (o.dx.clamp(0, 1) * (picture.width - 1)),
      (o.dy.clamp(0, 1) * (picture.height - 1)),
    );
    final tl = at(corners[0]), tr = at(corners[1]);
    final br = at(corners[2]), bl = at(corners[3]);
    double length(img.Point a, img.Point b) =>
        math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
    final width = math.max(2, ((length(tl, tr) + length(bl, br)) / 2).round());
    final height = math.max(2, ((length(tl, bl) + length(tr, br)) / 2).round());
    return img.copyRectify(
      picture,
      topLeft: tl,
      topRight: tr,
      bottomLeft: bl,
      bottomRight: br,
      interpolation: img.Interpolation.linear,
      toImage: img.Image(
        width: width,
        height: height,
        numChannels: picture.numChannels,
      ),
    );
  }

  static img.Image _crop(img.Image picture, Rect share) {
    final x = (share.left * picture.width).round().clamp(0, picture.width - 1);
    final y = (share.top * picture.height).round().clamp(0, picture.height - 1);
    final width = (share.width * picture.width).round().clamp(
      1,
      picture.width - x,
    );
    final height = (share.height * picture.height).round().clamp(
      1,
      picture.height - y,
    );
    return img.copyCrop(picture, x: x, y: y, width: width, height: height);
  }

  static img.Image _look(img.Image picture, PhotoEdit edit) {
    switch (edit.filter) {
      case PhotoFilter.original:
        break;
      case PhotoFilter.document:
        // Black type on white paper, as a scanner gives it.
        img.grayscale(picture);
        img.adjustColor(picture, contrast: 1.7, brightness: 1.18);
      case PhotoFilter.gray:
        img.grayscale(picture);
      case PhotoFilter.colorDocument:
        img.adjustColor(
          picture,
          contrast: 1.3,
          brightness: 1.12,
          saturation: 1.15,
        );
    }
    if (edit.brightness != 0 || edit.contrast != 0) {
      img.adjustColor(
        picture,
        brightness: 1 + edit.brightness * .6,
        contrast: 1 + edit.contrast * .8,
      );
    }
    if (edit.sharpness > 0) {
      picture = img.convolution(
        picture,
        filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0],
        amount: edit.sharpness,
      );
    }
    return picture;
  }

  static void _draw(img.Image picture, PhotoEdit edit) {
    final w = picture.width, h = picture.height;
    final black = img.ColorRgb8(0, 0, 0);
    for (final r in edit.redactions) {
      img.fillRect(
        picture,
        x1: (r.left * w).round(),
        y1: (r.top * h).round(),
        x2: (r.right * w).round(),
        y2: (r.bottom * h).round(),
        color: black,
      );
    }
    final red = img.ColorRgb8(220, 38, 38);
    final thick = math.max(3, (math.min(w, h) / 180).round());
    for (final s in edit.strokes) {
      for (var i = 1; i < s.points.length; i++) {
        img.drawLine(
          picture,
          x1: (s.points[i - 1].dx * w).round(),
          y1: (s.points[i - 1].dy * h).round(),
          x2: (s.points[i].dx * w).round(),
          y2: (s.points[i].dy * h).round(),
          color: red,
          thickness: thick,
          antialias: true,
        );
      }
    }
    final font = math.min(w, h) >= 1400
        ? img.arial48
        : math.min(w, h) >= 700
        ? img.arial24
        : img.arial14;
    for (final t in edit.texts) {
      img.drawString(
        picture,
        _ascii(t.text),
        font: font,
        x: (t.at.dx * w).round(),
        y: (t.at.dy * h).round(),
        color: red,
      );
    }
  }

  /// The bitmap fonts know only ASCII: Turkish letters as their nearest.
  static String _ascii(String text) => text
      .replaceAll('ı', 'i')
      .replaceAll('İ', 'I')
      .replaceAll('ş', 's')
      .replaceAll('Ş', 'S')
      .replaceAll('ğ', 'g')
      .replaceAll('Ğ', 'G')
      .replaceAll('ü', 'u')
      .replaceAll('Ü', 'U')
      .replaceAll('ö', 'o')
      .replaceAll('Ö', 'O')
      .replaceAll('ç', 'c')
      .replaceAll('Ç', 'C');

  /// Where the copy of [original] lands: beside it, "(düzenlenmiş)", never
  /// over anything.
  static File placeFor(String original, {required String extension}) {
    final folder = p.dirname(original);
    final stem = p.basenameWithoutExtension(original);
    var file = File(p.join(folder, '$stem (düzenlenmiş).$extension'));
    for (var n = 2; file.existsSync(); n++) {
      file = File(p.join(folder, '$stem (düzenlenmiş $n).$extension'));
    }
    return file;
  }

  /// [edit] applied to the photograph at [source], written beside
  /// [original] (or into [fallback] when that folder takes no writing).
  static Future<File> save({
    required String source,
    required String original,
    required PhotoEdit edit,
    required Future<Directory> Function() fallback,
  }) async {
    final bytes = await File(source).readAsBytes();
    final suffix = p.extension(source).toLowerCase();
    final jpeg = suffix == '.jpg' || suffix == '.jpeg' || suffix == '.heic';
    final made = await compute(render, (
      bytes: bytes,
      edit: edit,
      stage: PhotoStage.saved,
      maxSide: 0,
      jpeg: jpeg,
    ));
    final extension = jpeg ? 'jpg' : 'png';
    var file = placeFor(original, extension: extension);
    try {
      await file.writeAsBytes(made.bytes, flush: true);
    } on FileSystemException {
      final folder = await fallback();
      await folder.create(recursive: true);
      file = placeFor(
        p.join(folder.path, p.basename(original)),
        extension: extension,
      );
      await file.writeAsBytes(made.bytes, flush: true);
    }
    return file;
  }
}

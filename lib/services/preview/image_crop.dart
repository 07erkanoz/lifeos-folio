import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Cutting a photograph down to the part of it that was wanted.
///
/// The original is never written over. A crop is a new file beside it,
/// named after it, because a gallery is where people keep the only copy
/// of a thing and a tool that overwrites that copy is a shredder.
class ImageCrop {
  const ImageCrop._();

  /// Where the crop of [original] lands: beside it, under a name that says
  /// what it is, and never over something already there.
  static File placeFor(String original, {required String extension}) {
    final folder = p.dirname(original);
    final stem = p.basenameWithoutExtension(original);
    var file = File(p.join(folder, '$stem (kırpılmış).$extension'));
    for (var n = 2; file.existsSync(); n++) {
      file = File(p.join(folder, '$stem (kırpılmış $n).$extension'));
    }
    return file;
  }

  /// Cuts [fraction] out of [source] and writes it beside [original].
  ///
  /// [fraction] is a share of the picture as it is being looked at, turns
  /// and all, so what lands on disk is what was framed on the screen. The
  /// two paths differ only for an iPhone photograph, where the file drawn
  /// from is the decoded copy and the name must still come from the one
  /// the reader knows.
  static Future<File> save({
    required String source,
    required String original,
    required int quarterTurns,
    required Rect fraction,
  }) async {
    final bytes = await File(source).readAsBytes();
    final suffix = p.extension(source).toLowerCase();
    final jpeg = suffix == '.jpg' || suffix == '.jpeg';
    // Off the interface thread: a twelve megapixel photograph takes long
    // enough to decode and encode that the window would stop answering.
    final cut = await compute(cutOut, (
      bytes: bytes,
      turns: quarterTurns,
      left: fraction.left,
      top: fraction.top,
      width: fraction.width,
      height: fraction.height,
      jpeg: jpeg,
    ));
    final file = placeFor(original, extension: jpeg ? 'jpg' : 'png');
    await file.writeAsBytes(cut);
    return file;
  }
}

/// The turning and cutting itself, run away from the interface thread.
///
/// Public because it is worth testing on its own: the direction a quarter
/// turn goes is the one thing here that cannot be reasoned out, only
/// measured.
@visibleForTesting
Uint8List cutOut(
  ({
    Uint8List bytes,
    int turns,
    double left,
    double top,
    double width,
    double height,
    bool jpeg,
  })
  job,
) {
  var picture = img.decodeImage(job.bytes);
  if (picture == null) throw const FormatException('Görsel çözülemedi.');
  final turns = job.turns % 4;
  if (turns != 0) picture = img.copyRotate(picture, angle: turns * 90);
  // Clamped rather than trusted. A selection is dragged with a finger and
  // can be asked for a pixel past the edge; a crop that throws there would
  // lose the reader's work for a rounding error.
  final x = (job.left * picture.width).round().clamp(0, picture.width - 1);
  final y = (job.top * picture.height).round().clamp(0, picture.height - 1);
  final width = (job.width * picture.width).round().clamp(1, picture.width - x);
  final height = (job.height * picture.height).round().clamp(
    1,
    picture.height - y,
  );
  final cut = img.copyCrop(picture, x: x, y: y, width: width, height: height);
  return job.jpeg ? img.encodeJpg(cut, quality: 92) : img.encodePng(cut);
}

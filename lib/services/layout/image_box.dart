import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// How large a picture is drawn, for the preview and the editor alike, as
/// UYAP draws it (measured in UYAP's own editor): at the width and height
/// the file gives it, which UYAP scales the picture to; without them, a
/// pixel to the point, narrowed to the text area if wider. The row it takes
/// is a point taller and wider than the picture: a picture 453 by 113 sat
/// in a view 454 by 114.
abstract final class ImageBox {
  /// What UYAP adds to the picture for the row it takes.
  static const border = 1.0;

  /// The size drawn, in points, for a picture the file sizes as [width] by
  /// [height] (either may be null) and [pixels] big, in a text area
  /// [available] points wide.
  static ({double width, double height}) size({
    double? width,
    double? height,
    ({int width, int height})? pixels,
    required double available,
  }) {
    if (width != null && height != null && width > 0 && height > 0) {
      return (width: width, height: height);
    }
    final w = (pixels?.width ?? 0).toDouble();
    final h = (pixels?.height ?? 0).toDouble();
    if (w <= 0 || h <= 0) return (width: 0, height: 0);
    // One given, the other kept in proportion.
    if (width != null && width > 0)
      return (width: width, height: h * width / w);
    if (height != null && height > 0) {
      return (width: w * height / h, height: height);
    }
    final scale = available > 0 ? math.min(1.0, available / w) : 1.0;
    return (width: w * scale, height: h * scale);
  }

  /// The picture's size in pixels, from its header only, or null.
  static ({int width, int height})? pixels(Uint8List bytes) {
    try {
      final info = img.findDecoderForData(bytes)?.startDecode(bytes);
      if (info == null || info.width <= 0 || info.height <= 0) return null;
      return (width: info.width, height: info.height);
    } catch (_) {
      return null;
    }
  }
}

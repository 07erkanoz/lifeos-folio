import 'dart:typed_data';

/// Resizes a one-byte-a-pixel grey image with a bicubic filter, as Pillow's
/// BICUBIC does: separable (rows, then columns), Keys' cubic with a = -0.5,
/// and the kernel widened when shrinking so nothing aliases.
///
/// Written for OCR's second reading of a picture. The image package's
/// resize took 14 s to enlarge a 1920 × 1080 screenshot 2.5 times, which made
/// reading a folder of pictures twelve times slower; enlarging bilinearly
/// instead lost a third of what the second reading gained (measured on 30
/// real pictures: 2592 confident words bicubic, 2410 bilinear).
Uint8List resizeGrey(
  Uint8List source,
  int width,
  int height,
  int newWidth,
  int newHeight,
) {
  final rows = _rows(source, width, height, newWidth);
  final out = _columns(rows, newWidth, height, newHeight);
  final result = Uint8List(newWidth * newHeight);
  for (var i = 0; i < result.length; i++) {
    final v = out[i].round();
    result[i] = v < 0 ? 0 : (v > 255 ? 255 : v);
  }
  return result;
}

double _cubic(double x) {
  const a = -0.5;
  x = x.abs();
  if (x < 1) return ((a + 2) * x - (a + 3)) * x * x + 1;
  if (x < 2) return (((x - 5) * x + 8) * x - 4) * a;
  return 0;
}

/// Where each output sample starts reading, how many inputs it reads, and
/// with what weights, for resizing [length] samples to [size].
({Int32List starts, Int32List counts, Float32List weights, int taps}) _filter(
  int length,
  int size,
) {
  final scale = size / length;
  final stretch = scale < 1 ? 1 / scale : 1.0;
  final support = 2 * stretch;
  final taps = (support * 2).ceil() + 1;
  final starts = Int32List(size);
  final counts = Int32List(size);
  final weights = Float32List(size * taps);
  for (var o = 0; o < size; o++) {
    final centre = (o + 0.5) / scale;
    var first = (centre - support).floor();
    var last = (centre + support).ceil();
    if (first < 0) first = 0;
    if (last > length) last = length;
    var total = 0.0;
    var n = 0;
    for (var s = first; s < last && n < taps; s++, n++) {
      final w = _cubic((s + 0.5 - centre) / stretch);
      weights[o * taps + n] = w;
      total += w;
    }
    if (total != 0) {
      for (var k = 0; k < n; k++) {
        weights[o * taps + k] /= total;
      }
    }
    starts[o] = first;
    counts[o] = n;
  }
  return (starts: starts, counts: counts, weights: weights, taps: taps);
}

/// Along each row, [width] samples to [size].
Float32List _rows(Uint8List source, int width, int height, int size) {
  final f = _filter(width, size);
  final out = Float32List(size * height);
  for (var y = 0; y < height; y++) {
    final row = y * width;
    final to = y * size;
    for (var o = 0; o < size; o++) {
      var sum = 0.0;
      final start = row + f.starts[o];
      final w = o * f.taps;
      final n = f.counts[o];
      for (var k = 0; k < n; k++) {
        sum += source[start + k] * f.weights[w + k];
      }
      // Pillow keeps eight bits between the passes; so does this, which
      // also clips the overshoot the cubic kernel makes at sharp edges.
      final v = sum.round();
      out[to + o] = (v < 0 ? 0 : (v > 255 ? 255 : v)).toDouble();
    }
  }
  return out;
}

/// Down each column, [height] rows to [size].
Float32List _columns(Float32List source, int width, int height, int size) {
  final f = _filter(height, size);
  final out = Float32List(width * size);
  for (var o = 0; o < size; o++) {
    final to = o * width;
    final w = o * f.taps;
    final n = f.counts[o];
    for (var k = 0; k < n; k++) {
      final weight = f.weights[w + k];
      final from = (f.starts[o] + k) * width;
      for (var x = 0; x < width; x++) {
        out[to + x] += source[from + x] * weight;
      }
    }
  }
  return out;
}

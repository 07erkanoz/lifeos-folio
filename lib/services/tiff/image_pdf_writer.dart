import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A PDF of whole-page images, written directly so each page keeps its pixels
/// exactly as they came: a bilevel scan stays one bit per pixel, a greyscale
/// one stays grey, and nothing is resampled.
///
/// The `pdf` package re-encodes every image as 8-bit RGB. For UYAP's bilevel
/// TIFFs that doubled the file (measured on 39 real TIFFs: 22 MB of TIFF made
/// 43 MB of PDF), while one-bit Flate keeps the same pixels in about 20 MB.
class ImagePdfWriter {
  ImagePdfWriter({this.title});

  final String? title;

  /// Object bodies, numbered from 3: 1 is the catalogue and 2 the page tree.
  final _objects = <List<int>>[];
  final _pages = <int>[];

  int _add(List<int> body) {
    _objects.add(body);
    return _objects.length + 2;
  }

  static String _num(double value) {
    final text = value.toStringAsFixed(3);
    return text.contains('.') ? text.replaceFirst(RegExp(r'\.?0+$'), '') : text;
  }

  static Uint8List _stream(String dict, List<int> data) =>
      (BytesBuilder(copy: false)
            ..add(latin1.encode('<<$dict/Length ${data.length}>>\nstream\n'))
            ..add(data)
            ..add(latin1.encode('\nendstream')))
          .takeBytes();

  /// Adds a page [pageWidth] × [pageHeight] points filled by one image.
  ///
  /// [samples] are rows padded to whole bytes, most significant bit first:
  /// one bit per pixel (1 is white) when [bitsPerComponent] is 1, otherwise
  /// one byte per component in [colorSpace] (`DeviceGray` or `DeviceRGB`).
  void addPage({
    required int width,
    required int height,
    required double pageWidth,
    required double pageHeight,
    required int bitsPerComponent,
    required String colorSpace,
    required Uint8List samples,
  }) {
    final image = _add(
      _stream(
        '/Type/XObject/Subtype/Image/Width $width/Height $height'
        '/ColorSpace/$colorSpace/BitsPerComponent $bitsPerComponent'
        '/Filter/FlateDecode',
        ZLibEncoder(level: 9).convert(samples),
      ),
    );
    final w = _num(pageWidth), h = _num(pageHeight);
    final content = _add(
      _stream('', latin1.encode('q $w 0 0 $h 0 0 cm /Im0 Do Q')),
    );
    _pages.add(
      _add(
        latin1.encode(
          '<</Type/Page/Parent 2 0 R/MediaBox[0 0 $w $h]'
          '/Resources<</XObject<</Im0 $image 0 R>>>>/Contents $content 0 R>>',
        ),
      ),
    );
  }

  /// A text string as PDF wants it outside ASCII: UTF-16BE with a BOM, in hex.
  static String _text(String value) {
    final hex = StringBuffer('<FEFF');
    for (final unit in value.codeUnits) {
      hex.write(unit.toRadixString(16).padLeft(4, '0').toUpperCase());
    }
    return '${hex.toString()}>';
  }

  Uint8List close() {
    final info = _add(
      latin1.encode(
        '<<${title == null ? '' : '/Title ${_text(title!)}'}'
        '/Producer ${_text('LifeOS Folio')}>>',
      ),
    );
    final bodies = <List<int>>[
      latin1.encode('<</Type/Catalog/Pages 2 0 R>>'),
      latin1.encode(
        '<</Type/Pages/Kids[${_pages.map((p) => '$p 0 R').join(' ')}]'
        '/Count ${_pages.length}>>',
      ),
      ..._objects,
    ];
    final out = BytesBuilder(copy: false)
      ..add(latin1.encode('%PDF-1.4\n%âãÏÓ\n'));
    final offsets = <int>[];
    for (var i = 0; i < bodies.length; i++) {
      offsets.add(out.length);
      out
        ..add(latin1.encode('${i + 1} 0 obj\n'))
        ..add(bodies[i])
        ..add(latin1.encode('\nendobj\n'));
    }
    final xref = out.length;
    final table = StringBuffer('xref\n0 ${bodies.length + 1}\n')
      ..write('0000000000 65535 f \n');
    for (final offset in offsets) {
      table.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    table.write(
      'trailer\n<</Size ${bodies.length + 1}/Root 1 0 R/Info $info 0 R>>\n'
      'startxref\n$xref\n%%EOF\n',
    );
    out.add(latin1.encode(table.toString()));
    return out.takeBytes();
  }
}

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pdfrx_engine/pdfrx_engine.dart';

/// PDFium for isolates that have no Flutter engine, where
/// `pdfrxFlutterInitialize` cannot run: the indexing and OCR isolates.
class PdfiumSetup {
  PdfiumSetup._();

  /// Test hook: `flutter test` runs under flutter_tester, which has no PDFium
  /// beside it, so a test points this at a built bundle's copy.
  static String? pathOverride;

  static bool _ready = false;

  /// Whether PDFium is loaded and answering in this isolate. Only success is
  /// remembered: a test that sets [pathOverride] after an earlier miss still
  /// gets it.
  static Future<bool> ensure() async {
    if (_ready) return true;
    // The release bundle ships PDFium beside the executable on Windows and in
    // lib/ on Linux. Missing both, pdfrx falls back to its native asset.
    final executable = p.dirname(Platform.resolvedExecutable);
    final candidates = [
      ?pathOverride,
      if (Platform.isWindows) p.join(executable, 'pdfium.dll'),
      p.join(
        executable,
        'lib',
        Platform.isWindows ? 'pdfium.dll' : 'libpdfium.so',
      ),
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) {
        Pdfrx.pdfiumModulePath ??= candidate;
        break;
      }
    }
    try {
      // The cache folder is given, not left to pdfrx: without one it falls
      // back to $HOME, which an Android app process need not have.
      await pdfrxInitialize(
        tmpPath: p.join(Directory.systemTemp.path, 'pdfrx.cache'),
      );
      // Initializing only records where the library is; loading it happens
      // on first use. Open a one-page document to know it really works.
      final probe = await PdfDocument.openData(_probe);
      await probe.dispose();
      return _ready = true;
    } catch (_) {
      return false;
    }
  }

  /// The smallest document PDFium opens: one empty page. PDFium rebuilds the
  /// missing cross-reference table itself.
  static final _probe = Uint8List.fromList(
    '%PDF-1.4\n'
            '1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n'
            '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n'
            '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 10 10]>>endobj\n'
            'trailer<</Root 1 0 R>>\n%%EOF\n'
        .codeUnits,
  );
}

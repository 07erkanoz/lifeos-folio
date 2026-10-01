import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

import 'android_document_save.dart';

/// Camera to PDF on Android, through Google's ML Kit document scanner: it
/// finds the page's edges, straightens it, takes as many pages as wanted and
/// returns one PDF. The camera opens in Google Play services' own screen, so
/// Folio asks for no camera permission of its own.
class DocumentScan {
  static bool get available => debugAvailable ?? Platform.isAndroid;

  /// For screenshots and tests on a desktop host, which is never Android.
  @visibleForTesting
  static bool? debugAvailable;

  /// Scans, has the reader choose where the PDF goes, and returns a local
  /// copy to open; null when the reader backed out at either step.
  static Future<String?> toPdf() async {
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.pdf},
        pageLimit: 100,
        isGalleryImport: true,
      ),
    );
    try {
      final DocumentScanningResult result;
      try {
        result = await scanner.scanDocument();
      } on PlatformException catch (e) {
        if (e.message == 'Operation cancelled') return null;
        throw StateError(
          'Belge tarayıcı açılamadı. Bu özellik Google Play Hizmetleri '
          'olan bir telefon gerektirir.',
        );
      }
      final uri = result.pdf?.uri;
      if (uri == null) return null;
      final source = File(Uri.parse(uri).toFilePath());
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final name =
          'Tarama ${now.year}-${two(now.month)}-${two(now.day)} '
          '${two(now.hour)}.${two(now.minute)}.pdf';
      try {
        return await AndroidDocumentSave.save(
          fileName: name,
          bytes: await source.readAsBytes(),
        );
      } finally {
        // The scanner's copy sits in the app cache; the saved one is kept.
        if (await source.exists()) await source.delete();
      }
    } finally {
      await scanner.close();
    }
  }
}

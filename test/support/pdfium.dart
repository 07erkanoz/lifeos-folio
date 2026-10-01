import 'dart:io';

import 'package:pdfrx_engine/pdfrx_engine.dart';

/// The PDFium library a test can load, or null when there is none anywhere.
///
/// flutter_tester has no PDFium beside it, so tests borrow the copy a build
/// put in place. Looked for in the order a checkout gets them: an explicit
/// override, the app bundles `flutter build` leaves in `build/`, the native
/// assets the build copies from, and last the build hook's own download —
/// whose folder names the hook has changed before (`windows-x64` became
/// `chromium_7811/win-x64`), which is why no one of these is relied on.
String? pdfiumLibrary() {
  final override = Platform.environment['PDFIUM_TEST_LIBRARY'];
  if (override != null && File(override).existsSync()) return override;
  final windows = Platform.isWindows;
  final name = windows ? 'pdfium.dll' : 'libpdfium.so';
  final candidates = windows
      ? [
          for (final mode in ['Release', 'Profile', 'Debug'])
            'build/windows/x64/runner/$mode/$name',
          'build/native_assets/windows/$name',
          '.dart_tool/lib/$name',
        ]
      : [
          for (final mode in ['release', 'profile', 'debug'])
            'build/linux/x64/$mode/bundle/lib/$name',
          'build/native_assets/linux/$name',
          '.dart_tool/lib/$name',
        ];
  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) return file.absolute.path;
  }
  final cache = Directory('.dart_tool/hooks_runner/shared/pdfium_dart/build');
  if (cache.existsSync()) {
    final platforms = windows
        ? const ['win-x64', 'windows-x64']
        : const ['linux-x64'];
    for (final file in cache.listSync(recursive: true).whereType<File>()) {
      final path = file.path.replaceAll('\\', '/');
      if (platforms.any((platform) => path.endsWith('$platform/$name'))) {
        return file.absolute.path;
      }
    }
  }
  return null;
}

/// Points pdfrx at [pdfiumLibrary], and says plainly what is missing when
/// there is nothing to point it at.
void configurePdfiumForTest() {
  final library = pdfiumLibrary();
  if (library == null) {
    throw StateError(
      'PDFium test library missing; run `flutter build windows` (or linux) '
      'once, or set PDFIUM_TEST_LIBRARY.',
    );
  }
  Pdfrx.pdfiumModulePath = library;
}

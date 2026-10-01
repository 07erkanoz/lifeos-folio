import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Application-local executables, independent of the user's PATH or installed
/// Office/utilities. The build copies `native_tools/<platform>-x64` to tools/,
/// beside the executable; on macOS `native_tools/macos-universal` goes to the
/// app's Contents/Resources/tools, the place a bundle keeps what it carries.
class NativeTools {
  static const supported = {'qpdf', 'tiffcp', 'jpegtran'};

  static bool get _desktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static String _bundled(String filename) {
    final executable = p.dirname(Platform.resolvedExecutable);
    return Platform.isMacOS
        ? p.join(executable, '..', 'Resources', 'tools', 'bin', filename)
        : p.join(executable, 'tools', 'bin', filename);
  }

  static String get _development => Platform.isWindows
      ? 'windows-x64'
      : Platform.isMacOS
      ? 'macos-universal'
      : 'linux-x64';

  /// Tools the app can use when present but works without. Unlike [executable]
  /// this never throws: a missing optional tool disables one feature instead of
  /// failing the operation. The bundled copy wins so behaviour does not depend
  /// on what the user happens to have installed; PATH is a fallback until the
  /// tool ships with the release.
  static Future<String?> optional(String name) async {
    if (!_desktop) return null;
    final filename = Platform.isWindows ? '$name.exe' : name;
    final bundled = _bundled(filename);
    if (await File(bundled).exists()) return p.normalize(bundled);
    for (final dir in (Platform.environment['PATH'] ?? '').split(
      Platform.isWindows ? ';' : ':',
    )) {
      if (dir.isEmpty) continue;
      final candidate = p.join(dir, filename);
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }

  static Future<String> executable(String name) async {
    if (!supported.contains(name)) throw ArgumentError.value(name);
    if (!_desktop) {
      throw UnsupportedError(
        'Bu işlem bilgisayar sürümlerinde kullanılabilir.',
      );
    }
    final filename = Platform.isWindows ? '$name.exe' : name;
    final installed = _bundled(filename);
    if (await File(installed).exists()) return p.normalize(installed);
    if (kDebugMode) {
      final development = p.join(
        Directory.current.path,
        'native_tools',
        _development,
        'bin',
        filename,
      );
      if (await File(development).exists()) return development;
    }
    throw UnsupportedError(
      'Folio paketindeki $name bileşeni eksik. Uygulamayı tüm klasörüyle yeniden kurun.',
    );
  }
}

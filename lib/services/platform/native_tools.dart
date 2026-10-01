import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Application-local executables, independent of the user's PATH or installed
/// Office/utilities. The build copies `native_tools/<platform>-x64` to tools/.
class NativeTools {
  static const supported = {'qpdf', 'tiffcp', 'jpegtran'};

  /// Tools the app can use when present but works without. Unlike [executable]
  /// this never throws: a missing optional tool disables one feature instead of
  /// failing the operation. The bundled copy wins so behaviour does not depend
  /// on what the user happens to have installed; PATH is a fallback until the
  /// tool ships with the release.
  static Future<String?> optional(String name) async {
    if (!Platform.isWindows && !Platform.isLinux) return null;
    final filename = Platform.isWindows ? '$name.exe' : name;
    final bundled = p.join(
      p.dirname(Platform.resolvedExecutable),
      'tools',
      'bin',
      filename,
    );
    if (await File(bundled).exists()) return bundled;
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
    if (!Platform.isWindows && !Platform.isLinux) {
      throw UnsupportedError(
        'Bu işlem Windows ve Linux sürümlerinde kullanılabilir.',
      );
    }
    final platform = Platform.isWindows ? 'windows' : 'linux';
    final filename = Platform.isWindows ? '$name.exe' : name;
    final installed = p.join(
      p.dirname(Platform.resolvedExecutable),
      'tools',
      'bin',
      filename,
    );
    if (await File(installed).exists()) return installed;
    if (kDebugMode) {
      final development = p.join(
        Directory.current.path,
        'native_tools',
        '$platform-x64',
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

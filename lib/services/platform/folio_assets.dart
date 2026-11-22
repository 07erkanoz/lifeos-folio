import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

/// Folio's assets wherever its code runs: through Flutter in the window's
/// isolate, read from the installed `flutter_assets` folder in one of its
/// own (Folio Ajan's tools), and from the project in a test of the tools
/// that starts no Flutter. `rootBundle` lives only in the window's isolate:
/// there, in a release build, it failed with "Null check operator used on
/// a null value" and Folio Ajan's voice did not open (22 Kasım 2026).
Future<ByteData> loadAsset(String key) async {
  try {
    return await rootBundle.load(key);
  } catch (_) {
    final bytes = await _file(key).readAsBytes();
    return ByteData.sublistView(bytes);
  }
}

Future<String> loadAssetString(String key) async {
  try {
    return await rootBundle.loadString(key);
  } catch (_) {
    return _file(key).readAsString();
  }
}

File _file(String key) {
  final exe = File(Platform.resolvedExecutable).parent.path;
  for (final dir in [
    p.join(exe, 'data', 'flutter_assets'),
    p.join(
      exe,
      '..',
      'Frameworks',
      'App.framework',
      'Resources',
      'flutter_assets',
    ),
  ]) {
    final file = File(p.join(dir, key));
    if (file.existsSync()) return file;
  }
  return File(key);
}

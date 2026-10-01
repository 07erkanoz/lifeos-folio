import 'dart:io';

import 'package:path/path.dart' as p;

import 'document_intents.dart';

/// Where this machine keeps its photographs.
///
/// A gallery is only a gallery if it already knows where to look. Asking
/// someone to find their own camera folder before they can see a photograph
/// is how a file manager behaves, not how a gallery does.
class PictureFolders {
  /// The folders worth offering, most interesting first, that actually exist.
  ///
  /// On Android this asks for permission to read the media folders; without
  /// it the answer is empty and the caller says so rather than showing an
  /// empty gallery. Elsewhere it is a matter of looking.
  static Future<List<String>> find() async {
    if (Platform.isAndroid) return DocumentIntents.pictureFolders();
    final home = _home;
    if (home == null) return const [];
    final candidates = <String>[
      ?await _xdgPictures(home),
      if (Platform.isWindows) p.join(home, 'Pictures'),
      if (Platform.isWindows) p.join(home, 'OneDrive', 'Pictures'),
      p.join(home, 'Resimler'),
      p.join(home, 'Pictures'),
      p.join(home, 'DCIM'),
    ];
    final seen = <String>{};
    final out = <String>[];
    for (final candidate in candidates) {
      final path = p.normalize(candidate);
      if (!seen.add(path)) continue;
      if (await Directory(path).exists()) out.add(path);
    }
    return out;
  }

  static String? get _home =>
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

  /// Linux keeps the name of the pictures folder in a file, because the name
  /// is translated: here it is "Resimler", elsewhere "Bilder" or "Изображения".
  static Future<String?> _xdgPictures(String home) async {
    if (!Platform.isLinux) return null;
    try {
      final file = File(p.join(home, '.config', 'user-dirs.dirs'));
      if (!await file.exists()) return null;
      for (final line in await file.readAsLines()) {
        final match = RegExp(r'^\s*XDG_PICTURES_DIR\s*=\s*"?(.*?)"?\s*$')
            .firstMatch(line);
        if (match == null) continue;
        final value = match.group(1)!;
        if (value.isEmpty) return null;
        return value.replaceFirst(r'$HOME', home);
      }
    } catch (_) {}
    return null;
  }
}

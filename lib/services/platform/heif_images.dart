import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'app_directories.dart';
import 'document_intents.dart';

/// Photographs from an iPhone.
///
/// HEIC is what every iPhone sends, so it is most of what arrives over
/// WhatsApp, and nothing in Flutter can decode one: the format is a still
/// frame of HEVC video, and neither Flutter nor the `image` package carries
/// that decoder.
///
/// Android has carried one since Android 9, so on a phone the picture is
/// handed to the system and comes back as a JPEG that everything else here
/// already understands — the viewer, the thumbnails, the search text and the
/// converter. On a desktop there is no such decoder to borrow, and the
/// picture is reported as unreadable rather than shown as a broken box.
class HeifImages {
  static const extensions = {'heic', 'heif', 'heics', 'heifs'};

  static bool isHeif(String path) => extensions.contains(
    p.extension(path).toLowerCase().replaceFirst('.', ''),
  );

  /// Whether this machine can decode one at all.
  static bool get supported => Platform.isAndroid;

  static Directory? _cache;

  /// A JPEG of [path] that the rest of the application can open, or null when
  /// there is no decoder or the file cannot be read.
  ///
  /// The result is kept, keyed by the file and the moment it was last written,
  /// so scrolling a gallery of holiday photographs decodes each one once.
  static Future<String?> decoded(String path) async {
    if (!supported || !isHeif(path)) return null;
    try {
      final source = File(path);
      final stat = await source.stat();
      final key = sha256
          .convert(
            '$path:${stat.size}:${stat.modified.microsecondsSinceEpoch}'
                .codeUnits,
          )
          .toString()
          .substring(0, 24);
      final directory = _cache ??= Directory(
        p.join((await folioSupportDirectory()).path, 'heif'),
      );
      await directory.create(recursive: true);
      final target = File(p.join(directory.path, '$key.jpg'));
      if (await target.exists() && await target.length() > 0) {
        return target.path;
      }
      final decoded = await DocumentIntents.decodeHeif(path, target.path);
      return decoded == true && await target.exists() ? target.path : null;
    } catch (_) {
      return null;
    }
  }

  /// Throws away what was decoded earlier. Nothing here is a document; it can
  /// always be made again from the photograph itself.
  static Future<void> clearCache() async {
    final directory = _cache;
    if (directory == null || !await directory.exists()) return;
    try {
      await directory.delete(recursive: true);
    } catch (_) {}
  }
}

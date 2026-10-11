import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_directories.dart';
import 'store_package.dart';

/// Ayarlar › Tüm verileri temizle: everything Folio keeps of its own, gone,
/// as if it had never run. The profile, the clients and the cash book, the
/// cases, the agenda, the settings, the index, the UYAP and UETS sessions,
/// the office network's keys and the e-Devlet window's cookies. Not the
/// lawyer's documents, in the folders they keep them in, nor what UYAP gave
/// and was saved in the UYAP folder: those are theirs, not Folio's.
///
/// A file Folio still holds open (Windows will not delete one) is deleted
/// when it starts next, before anything is read: a mark outside Folio's
/// folders says it is to be done.
abstract final class DataReset {
  /// The mark that the next start is to finish the clearing; beside the
  /// folders, so that clearing them does not clear it.
  @visibleForTesting
  static File Function() marker = () =>
      File(p.join(Directory.systemTemp.path, 'lifeos-folio-sifirla'));

  /// The folders cleared; replaced under test.
  @visibleForTesting
  static Future<List<Directory>> Function() folders = _folders;

  /// The keychain cleared; replaced under test.
  @visibleForTesting
  static Future<void> Function() keychain = _keychain;

  /// Clears what can be cleared now and marks the rest for the next start.
  /// True when nothing is left.
  static Future<bool> clear() async {
    await marker().writeAsString(DateTime.now().toIso8601String());
    return _clear();
  }

  /// At start, before anything is read: what a clearing left, cleared,
  /// once. The mark goes first: what cannot be cleared even now (a keyring
  /// that is not there, a file held by another program) must not have
  /// every later start clear what was made since.
  static Future<void> finishPending() async {
    try {
      final mark = marker();
      if (!await mark.exists()) return;
      await mark.delete();
      await _clear(keepMark: false);
    } catch (_) {
      // Folio starts all the same.
    }
  }

  static Future<bool> _clear({bool keepMark = true}) async {
    var whole = true;
    for (final dir in await folders()) {
      // Never a disk, the user's folder, AppData, nor one just under them:
      // only Folio's own folders deep below.
      if (!safeToClear(dir.path)) continue;
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {
        whole = false;
      }
    }
    try {
      await keychain();
    } catch (_) {
      whole = false;
    }
    if (whole || !keepMark) {
      try {
        final mark = marker();
        if (await mark.exists()) await mark.delete();
      } catch (_) {}
    }
    return whole;
  }

  /// Whether [path] is Folio's own to clear and no place of the person's:
  /// never a disk, the user's folder, AppData or the temporary folder, nor
  /// one holding them; on a computer one named for Folio. A phone's app
  /// keeps to its own sandbox, where depth is enough.
  @visibleForTesting
  static bool safeToClear(
    String path, {
    Map<String, String>? env,
    bool? windows,
    bool? phone,
  }) {
    final context = (windows ?? Platform.isWindows) ? p.windows : p.posix;
    final at = context.normalize(path);
    if (!context.isAbsolute(at) || context.split(at).length < 4) return false;
    final e = env ?? Platform.environment;
    for (final key in [
      'HOME',
      'USERPROFILE',
      'APPDATA',
      'LOCALAPPDATA',
      'XDG_DATA_HOME',
      'TEMP',
      'TMP',
    ]) {
      final v = e[key];
      if (v == null || v.isEmpty) continue;
      final top = context.normalize(v);
      if (context.equals(at, top) || context.isWithin(at, top)) return false;
    }
    if (phone ?? (Platform.isAndroid || Platform.isIOS)) return true;
    final parts = context.split(at);
    return parts
        .skip(parts.length > 3 ? parts.length - 3 : 0)
        .map((s) => s.toLowerCase())
        .any(
          (s) =>
              s.contains('folio') ||
              s.contains('lifeos') ||
              s.contains('evrak') ||
              s.contains('erkanoz') ||
              s == 'pdfrx.cache',
        );
  }

  static Future<List<Directory>> _folders() async {
    final out = <String>{};
    Future<void> add(Future<Directory> Function() find) async {
      try {
        out.add(p.normalize((await find()).path));
      } catch (_) {}
    }

    await add(folioSupportDirectory);
    await add(folioSharedDirectory);
    await add(getApplicationSupportDirectory);
    if (Platform.isWindows) {
      // Both places the data has had, whichever is used now (see
      // windowsDataFolder), and the Store package's.
      final roaming = Platform.environment['APPDATA'];
      if (roaming != null) {
        for (final company in ['com.erkanoz', 'LifeOS']) {
          out.add(p.join(roaming, company, 'LifeOS Evrakçı'));
          out.add(p.join(roaming, company, 'LifeOS Folio'));
        }
      }
      final home = Platform.environment['USERPROFILE'];
      if (home != null && runsFromStorePackage) {
        out.add(storeDataFolder(home));
      }
    }
    if (Platform.isLinux) {
      // LifeOS Editör's folder of its own name, before it was Folio's.
      final share =
          Platform.environment['XDG_DATA_HOME'] ??
          p.join(Platform.environment['HOME'] ?? '', '.local', 'share');
      out.add(p.join(share, 'com.erkanoz.lifeos_editor'));
    }
    // The e-Devlet window's cookies and the conversions' scratch.
    final temp = Directory.systemTemp.path;
    for (final name in ['folio-edevlet', 'folio-klasor', 'pdfrx.cache']) {
      out.add(p.join(temp, name));
    }
    return [for (final path in out) Directory(path)];
  }

  /// The sessions and keys kept in the phone's keystore or the Mac's and
  /// Linux's keychain (SecretStore); on Windows they are files in the
  /// folders.
  static Future<void> _keychain() async {
    if (Platform.isWindows) return;
    await const FlutterSecureStorage(
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ).deleteAll();
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../editor/editor_settings.dart';
import '../editor/lawyer_profile.dart';
import '../editor/letterheads.dart';
import '../editor/snippets.dart';
import '../legal/legal_settings.dart';
import '../platform/app_directories.dart';

/// The person's own settings kept alike on their devices (Senkron): the
/// lawyer profile, the snippets, the letterheads, the editor's and the
/// legal tools' choices. Each file whole, the newer one kept: they are one
/// person's, changed on one device at a time.
///
/// Not these: the lock (each device has its own), the library's folders
/// (paths of this disk), the portal sessions (the Bağlantılar part).
class SettingsSync {
  SettingsSync({Future<Directory> Function()? folder, this.onChanged})
    : _folder = folder ?? folioSupportDirectory;

  final Future<Directory> Function() _folder;

  /// Told the names of the files written: what reads them reads again.
  final void Function(Set<String> names)? onChanged;

  static const profile = 'profil.json';

  /// The settings part's files. Not how Folio looks: a phone and a
  /// computer may well be kept apart in that.
  static const settings = [
    'kaliplar.json',
    'antetler.json',
    'editor.json',
    'hukuk.json',
  ];

  /// A device being set up takes what its own other device has, whatever
  /// the times, and gives nothing back: the defaults it made a minute ago
  /// are newer, and must not replace the lawyer's years of snippets.
  static bool receiveOnly = false;

  Future<Map<String, Object?>> export(List<String> names) async {
    if (receiveOnly) return const {};
    final dir = await _folder();
    final out = <String, Object?>{};
    for (final name in names) {
      final file = File(p.join(dir.path, name));
      try {
        if (!await file.exists()) continue;
        out[name] = {
          'at': (await file.lastModified()).toUtc().toIso8601String(),
          'json': await file.readAsString(),
        };
      } catch (_) {}
    }
    return out;
  }

  /// Theirs kept where it is newer than this device's, or this device has
  /// none. Written with their time, so that neither sends it back as new.
  /// True when anything was written.
  Future<bool> merge(Object? theirs, List<String> names) async {
    if (theirs is! Map) return false;
    final dir = await _folder();
    final written = <String>{};
    for (final name in names) {
      final one = theirs[name];
      if (one is! Map) continue;
      final at = DateTime.tryParse('${one['at']}');
      final text = one['json'];
      if (at == null || text is! String) continue;
      try {
        // Only what reads as JSON: a broken file never replaces a good one.
        jsonDecode(text);
      } catch (_) {
        continue;
      }
      final file = File(p.join(dir.path, name));
      try {
        if (await file.exists()) {
          final mine = await file.lastModified();
          if (await file.readAsString() == text ||
              (!receiveOnly &&
                  !at.isAfter(mine.toUtc().add(const Duration(seconds: 1))))) {
            continue;
          }
        }
        await file.parent.create(recursive: true);
        final pending = File('${file.path}.senkron');
        await pending.writeAsString(text, flush: true);
        await pending.rename(file.path);
        await file.setLastModified(at);
        written.add(name);
      } catch (_) {}
    }
    if (written.isEmpty) return false;
    await reload(written);
    onChanged?.call(written);
    return true;
  }

  /// What reads the files written reads them again.
  static Future<void> reload(Set<String> names) async {
    try {
      if (names.contains(profile)) await LawyerProfile.reload();
      if (names.contains('editor.json')) await EditorSettings.instance.load();
      if (names.contains('hukuk.json')) await LegalSettings.instance.load();
      if (names.contains('kaliplar.json')) await SnippetStore.reloadShared();
      if (names.contains('antetler.json')) {
        await LetterheadStore.reloadShared();
      }
    } catch (_) {}
  }
}

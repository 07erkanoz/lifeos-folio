import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Windows path_provider uses ProductName. Keep the established data location
/// when the visible brand changes, including the index, theme and signing setup.
Future<Directory> folioSupportDirectory() async {
  final current = await getApplicationSupportDirectory();
  if (!Platform.isWindows) return current;
  final stable = Directory(p.join(current.parent.path, 'LifeOS Evrakçı'));
  await stable.create(recursive: true);
  return stable;
}

/// What every window of Folio's must see alike: the UYAP cases and what is
/// tied to them, the claims windows hold on documents, the voice models.
///
/// On Linux, LifeOS Editör is a program of its own name, and the system
/// gives it a folder of its own; what it kept there no Folio window saw,
/// and two windows each holding "the" lock on a document held two. Here it
/// keeps them in Folio's folder, beside Folio's. Elsewhere the two are one
/// folder already.
Future<Directory> folioSharedDirectory() =>
    _shared ??= _resolveShared().catchError((Object e) {
      _shared = null;
      throw e;
    });
Future<Directory>? _shared;

const _editorId = 'com.erkanoz.lifeos_editor';
const _folioId = 'com.erkanoz.evrak_convert';

Future<Directory> _resolveShared() async {
  final own = await folioSupportDirectory();
  if (!Platform.isLinux) return own;
  final name = p.basename(own.path);
  if (name != _editorId && name != _folioId) return own;
  final folio = Directory(p.join(own.parent.path, _folioId));
  await folio.create(recursive: true);
  final editor = Directory(p.join(own.parent.path, _editorId));
  if (await editor.exists()) await bringOverEditorData(editor, folio);
  return folio;
}

/// What an earlier LifeOS Editör left in its own folder, moved to Folio's:
/// a UYAP case kept twice keeps the newer copy, and the ties are merged.
@visibleForTesting
Future<void> bringOverEditorData(Directory from, Directory to) async {
  try {
    final cases = Directory(p.join(from.path, 'uyap', 'dosyalar'));
    if (await cases.exists()) {
      final target = Directory(p.join(to.path, 'uyap', 'dosyalar'));
      await target.create(recursive: true);
      await for (final entry in cases.list()) {
        if (entry is! File) continue;
        final there = File(p.join(target.path, p.basename(entry.path)));
        if (!await there.exists() ||
            (await entry.lastModified()).isAfter(await there.lastModified())) {
          await entry.copy(there.path);
        }
        await entry.delete();
      }
    }
    final links = File(p.join(from.path, 'uyap', 'baglar.json'));
    if (await links.exists()) {
      final there = File(p.join(to.path, 'uyap', 'baglar.json'));
      final merged = <String, Object?>{
        if (await there.exists())
          ...(jsonDecode(await there.readAsString()) as Map)
              .cast<String, Object?>(),
        ...(jsonDecode(await links.readAsString()) as Map)
            .cast<String, Object?>(),
      };
      await there.parent.create(recursive: true);
      await there.writeAsString(jsonEncode(merged), flush: true);
      await links.delete();
    }
    for (final name in ['uyap.json', 'ses']) {
      final entry = p.join(from.path, name);
      final there = p.join(to.path, name);
      if (await FileSystemEntity.type(entry) == FileSystemEntityType.notFound ||
          await FileSystemEntity.type(there) != FileSystemEntityType.notFound) {
        continue;
      }
      await (await FileSystemEntity.isDirectory(entry)
              ? Directory(entry)
              : File(entry))
          .rename(there);
    }
  } catch (_) {
    // What cannot be moved stays where it was; nothing is lost.
  }
}

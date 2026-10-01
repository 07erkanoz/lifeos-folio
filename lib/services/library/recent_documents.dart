import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/evrak_file.dart';
import '../platform/app_directories.dart';
import '../platform/atomic_file.dart';

/// Small independent recents list: opening a document never waits for indexing.
class RecentDocuments {
  final String? storagePath;
  final List<EvrakFile> files = [];
  Future<void> _writes = Future.value();
  Future<void>? _loading;
  RecentDocuments({this.storagePath});
  Future<File> _file() async => File(
    storagePath ??
        p.join((await folioSupportDirectory()).path, 'recent-documents.json'),
  );
  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final rows = jsonDecode(await file.readAsString()) as List;
      final openedDuringLoad = files.map((f) => f.path).toSet();
      for (final row in rows.take(30)) {
        final path = row['path'] as String;
        if (!openedDuringLoad.add(path)) continue;
        files.add(
          EvrakFile(
            path: path,
            name: row['name'] as String,
            sizeInBytes: row['size'] as int,
            format: EvrakFormat.fromExtension(p.extension(path)),
          ),
        );
      }
      if (files.length > 30) files.removeRange(30, files.length);
    } catch (_) {
      /* Recents are optional; direct opening remains available. */
    }
  }

  Future<void> remember(Iterable<EvrakFile> opened) async {
    final selected = opened.toList();
    await load();
    for (final file in selected.reversed) {
      files.removeWhere((item) => item.path == file.path);
      files.insert(0, file);
    }
    if (files.length > 30) files.removeRange(30, files.length);
    return _persist();
  }

  Future<void> remove(String path) async {
    await load();
    files.removeWhere((file) => file.path == path);
    return _persist();
  }

  Future<void> _persist() {
    final bytes = utf8.encode(
      jsonEncode([
        for (final file in files)
          {'path': file.path, 'name': file.name, 'size': file.sizeInBytes},
      ]),
    );
    _writes = _writes
        .then((_) async => replaceFileIfChanged(await _file(), bytes))
        .then<void>((_) {})
        .catchError((Object _) {});
    return _writes;
  }
}

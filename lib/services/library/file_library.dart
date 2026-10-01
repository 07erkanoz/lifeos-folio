import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/evrak_file.dart';

typedef ScannedFile = ({String path, int size, int modified, int changed});

class FolderScanResult {
  final List<String> paths;
  final List<ScannedFile> files;
  final int skipped;
  final List<String> unreadable;
  const FolderScanResult(
    this.paths,
    this.skipped,
    this.unreadable, [
    this.files = const [],
  ]);
}

/// Does not follow symlinks. Every input path goes through the same filter.
class FileLibrary {
  static bool supports(String path) => EvrakFormat.supportedExtensions.contains(
    p.extension(path).replaceFirst('.', '').toLowerCase(),
  );

  static Future<FolderScanResult> collect(
    List<String> paths, {
    bool recursive = true,
    bool metadata = false,
    bool sort = true,
    bool Function()? shouldCancel,
  }) async {
    final found = <String>{};
    final unreadable = <String>[];
    final files = <ScannedFile>[];
    Future<void> add(String raw) async {
      final path = p.normalize(p.absolute(raw));
      if (!found.add(path) || !metadata) return;
      final stat = await File(path).stat();
      if (stat.type != FileSystemEntityType.file) {
        unreadable.add(path);
        return;
      }
      files.add((
        path: path,
        size: stat.size,
        modified: stat.modified.microsecondsSinceEpoch,
        changed: stat.changed.microsecondsSinceEpoch,
      ));
    }

    var skipped = 0;
    Future<void> visit(String path) async {
      try {
        if (shouldCancel?.call() == true) return;
        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type == FileSystemEntityType.file) {
          if (supports(path)) {
            await add(path);
          } else {
            skipped++;
          }
        } else if (type == FileSystemEntityType.directory) {
          final dirs = <String>[path];
          while (dirs.isNotEmpty) {
            if (shouldCancel?.call() == true) return;
            final current = dirs.removeLast();
            try {
              await for (final entry in Directory(
                current,
              ).list(followLinks: false)) {
                if (shouldCancel?.call() == true) return;
                if (entry is Directory && recursive) {
                  dirs.add(entry.path);
                } else if (entry is File) {
                  if (supports(entry.path)) {
                    await add(entry.path);
                  } else {
                    skipped++;
                  }
                }
              }
            } on FileSystemException {
              unreadable.add(current);
            }
          }
        } else {
          skipped++;
        }
      } on FileSystemException {
        unreadable.add(path);
      }
    }

    for (final path in paths) {
      await visit(path);
    }
    final pathsFound = found.toList();
    if (sort) {
      pathsFound.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    return FolderScanResult(pathsFound, skipped, unreadable, files);
  }
}

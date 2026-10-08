import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// [folder] packed as one zip with its subfolders, in the system's temp
/// folder, for a folder to be sent or shared as easily as a document; off
/// the window's isolate. Its path.
Future<String> zipFolder(String folder) => compute(_zip, folder);

/// A folder sent as a zip ([zipFolder]), opened beside it as the folder
/// it was; its path. The same name again is opened where it already is.
Future<String> unzipFolder(String zip) => compute(_unzip, zip);

Future<String> _unzip(String zip) async {
  final target = p.join(p.dirname(zip), p.basenameWithoutExtension(zip));
  if (await Directory(target).exists()) return target;
  // Opened in a folder of its own first, put in place once whole: one
  // that failed halfway is not taken for the folder.
  final work = await Directory(p.dirname(zip)).createTemp('.acilis-');
  try {
    final input = InputFileStream(zip);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final root = p.normalize(p.absolute(work.path));
      for (final entry in archive) {
        // No links: a link to "../" lets the next entry be written outside.
        if (entry.isSymbolicLink) continue;
        final name = entry.name.replaceAll('\\', '/');
        if (name.startsWith('/') || p.isAbsolute(name)) continue;
        final out = p.normalize(p.join(root, name));
        if (!p.isWithin(root, out)) continue;
        if (!entry.isFile) {
          await Directory(out).create(recursive: true);
          continue;
        }
        await Directory(p.dirname(out)).create(recursive: true);
        final sink = OutputFileStream(out);
        try {
          entry.writeContent(sink);
        } finally {
          await sink.close();
        }
      }
    } finally {
      await input.close();
    }
    await work.rename(target);
    return target;
  } catch (_) {
    if (await work.exists()) await work.delete(recursive: true);
    rethrow;
  }
}

Future<String> _zip(String folder) async {
  final name = p.basename(
    folder.endsWith(p.separator)
        ? folder.substring(0, folder.length - 1)
        : folder,
  );
  final out = Directory(p.join(Directory.systemTemp.path, 'folio-klasor'));
  await out.create(recursive: true);
  final target = p.join(out.path, '$name.zip');
  final old = File(target);
  if (await old.exists()) await old.delete();
  await ZipFileEncoder().zipDirectory(Directory(folder), filename: target);
  return target;
}

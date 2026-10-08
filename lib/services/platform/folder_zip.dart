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
  if (!await Directory(target).exists()) {
    await extractFileToDisk(zip, target);
  }
  return target;
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

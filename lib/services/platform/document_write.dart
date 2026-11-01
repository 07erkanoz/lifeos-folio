import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// A document written whole or not at all. The new bytes go to a file in
/// the document's own folder (the same disk, so the last step is a rename),
/// are read back and compared, take the old file's permissions, and only
/// then replace it: a crash or a full disk halfway leaves the document as
/// it was, never half-written.
///
/// Through a symbolic link the file it points at is replaced and the link
/// stays. Where the folder cannot take the new file (no right to create
/// files in it, a share that cannot rename over a file, permissions that
/// cannot be copied) the document is written in place, as before.
Future<void> writeDocument(String path, List<int> bytes) async {
  var target = path;
  if (await FileSystemEntity.isLink(path)) {
    try {
      target = await File(path).resolveSymbolicLinks();
    } on FileSystemException {
      // A link to nothing: writing through it makes the file it names.
      await File(path).writeAsBytes(bytes, flush: true);
      return;
    }
  }
  final file = File(target);
  final Directory stage;
  try {
    stage = await file.parent.createTemp('.folio-save-');
  } on FileSystemException {
    await file.writeAsBytes(bytes, flush: true);
    return;
  }
  try {
    final pending = File(p.join(stage.path, p.basename(target)));
    // A full disk or a failing write stops here; the document is untouched.
    await pending.writeAsBytes(bytes, flush: true);
    if (!listEquals(await pending.readAsBytes(), bytes)) {
      throw FileSystemException(
        'Kaydedilen dosya doğrulanamadı; belge değiştirilmedi.',
        target,
      );
    }
    if (!await _keepMode(file, pending)) {
      await file.writeAsBytes(bytes, flush: true);
      return;
    }
    try {
      await pending.rename(target);
    } on FileSystemException {
      await file.writeAsBytes(bytes, flush: true);
    }
  } finally {
    try {
      await stage.delete(recursive: true);
    } catch (_) {}
  }
}

/// [pending] given [file]'s permissions (rw for the owner only stays so);
/// false when they could not be. Windows keeps none of these bits.
Future<bool> _keepMode(File file, File pending) async {
  if (Platform.isWindows) return true;
  final old = await file.stat();
  if (old.type == FileSystemEntityType.notFound) return true;
  final mode = old.mode & 0x1ff;
  if ((await pending.stat()).mode & 0x1ff == mode) return true;
  try {
    final result = await Process.run('chmod', [
      mode.toRadixString(8),
      pending.path,
    ]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// What the document on disk looked like when the editor last read or
/// wrote it: enough to tell that another program changed it since.
@immutable
class DiskStamp {
  const DiskStamp(this.path, this.modified, this.size);

  final String path;
  final DateTime modified;
  final int size;

  /// [path] as it is now; null when it is not a file.
  static Future<DiskStamp?> of(String path) async {
    try {
      final stat = await File(path).stat();
      if (stat.type != FileSystemEntityType.file) return null;
      return DiskStamp(p.absolute(path), stat.modified, stat.size);
    } catch (_) {
      return null;
    }
  }

  /// Whether [path] is this stamp's file and has changed since: false when
  /// it is another file, or is gone (nothing to lose by writing it).
  Future<bool> changedAt(String path) async {
    if (!p.equals(p.absolute(path), this.path)) return false;
    final now = await of(path);
    return now != null && (now.modified != modified || now.size != size);
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Never expose a truncated desktop entry or icon to desktop file watchers.
/// Unchanged files are not touched, so repeated registration emits no events.
Future<bool> replaceFileIfChanged(File target, List<int> bytes) async {
  if (await target.exists() && listEquals(await target.readAsBytes(), bytes)) {
    return false;
  }
  await target.parent.create(recursive: true);
  final staging = await target.parent.createTemp('.folio-install-');
  try {
    final pending = File(p.join(staging.path, 'payload'));
    await pending.writeAsBytes(bytes, flush: true);
    await pending.rename(target.path);
    return true;
  } finally {
    await staging.delete(recursive: true);
  }
}

/// A lock on a file beside [target], for one process at a time to read it,
/// change it and write it back: waited for a little while another holds
/// it; none when it cannot be had, and the caller goes on without it.
/// Closing the handle lets it go.
Future<RandomAccessFile?> lockBeside(File target) async {
  final RandomAccessFile handle;
  try {
    await target.parent.create(recursive: true);
    handle = await File('${target.path}.lock').open(mode: FileMode.append);
  } catch (_) {
    return null;
  }
  for (var i = 0; i < 80; i++) {
    try {
      await handle.lock(FileLock.exclusive);
      return handle;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }
  await handle.close();
  return null;
}

import 'dart:io';

import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';
import 'document_history.dart';

/// A claim on something only one Folio window may hold at a time: a
/// document being edited, or the recovery draft an open editor writes.
///
/// Each editor window is a process of its own, so what one window holds has
/// to be visible to the others. A lock file held with the operating
/// system's own lock does that, and lets go of itself when the process
/// ends, a crash included, so nothing is left claimed by a window that is
/// gone.
///
/// Within one window a claim is shared: Folio itself sees to two editors of
/// its own on one document, as when a document saved under a new name opens
/// under it while the editor that saved it is still closing.
class DocumentLock {
  DocumentLock._(this.name);

  /// Where the lock files are kept; replaced under test.
  static Future<Directory> Function() folder = () async =>
      Directory(p.join((await folioSharedDirectory()).path, 'acik-belgeler'));

  /// What this process holds: the open lock file, and how many claims
  /// share it.
  static final _held = <String, (RandomAccessFile, int)>{};

  /// Claims being made, so that two at once in this process open the file
  /// once.
  static final _pending = <String, Future<RandomAccessFile?>>{};

  final String name;
  bool _released = false;

  /// The claim on editing the document at [path].
  static Future<DocumentLock?> document(String path) =>
      acquire('belge-${DocumentHistory.documentKey(path)}');

  /// Whether another window is editing the document at [path].
  static Future<bool> documentHeld(String path) =>
      heldElsewhere('belge-${DocumentHistory.documentKey(path)}');

  /// Claims [name]; null when another process holds it.
  static Future<DocumentLock?> acquire(String name) async {
    final held = _held[name];
    if (held != null) {
      _held[name] = (held.$1, held.$2 + 1);
      return DocumentLock._(name);
    }
    final pending = _pending[name] ??= _open(name);
    final handle = await pending;
    _pending.remove(name);
    if (handle == null) return null;
    final again = _held[name];
    _held[name] = again == null ? (handle, 1) : (again.$1, again.$2 + 1);
    return DocumentLock._(name);
  }

  static Future<RandomAccessFile?> _open(String name) async {
    final dir = await folder();
    await dir.create(recursive: true);
    RandomAccessFile? handle;
    try {
      handle = await File(
        p.join(dir.path, '$name.lock'),
      ).open(mode: FileMode.append);
      await handle.lock(FileLock.exclusive);
      return handle;
    } on FileSystemException {
      await handle?.close();
      return null;
    }
  }

  /// Whether [name] is held by another process.
  static Future<bool> heldElsewhere(String name) async {
    if (_held.containsKey(name)) return false;
    final lock = await acquire(name);
    if (lock == null) return true;
    await lock.release();
    return false;
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    final held = _held[name];
    if (held == null) return;
    if (held.$2 > 1) {
      _held[name] = (held.$1, held.$2 - 1);
      return;
    }
    _held.remove(name);
    // The file stays: deleting it would let a window that opened it a
    // moment ago hold a lock on a file no one else can find any more, while
    // the next window makes a new one and holds that too.
    try {
      await held.$1.unlock();
      await held.$1.close();
    } on FileSystemException {
      // Already let go of.
    }
  }
}

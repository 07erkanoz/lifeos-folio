import 'dart:io';

import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';

/// Which of a program's windows is on the network for live documents.
/// LifeOS Ofis opens every document in a window of its own, each a
/// program with this computer's one identity: two of them on the network
/// at once, a device reached either at random (21 Ekim 2026). The first
/// window to ask holds a lock for as long as it runs; the others share
/// from that window.
abstract final class LiveOwner {
  static RandomAccessFile? _held;

  /// Whether this window holds the network, taking it if no other does.
  static Future<bool> claim() async {
    if (_held != null) return true;
    RandomAccessFile? file;
    try {
      final dir = await folioSupportDirectory();
      await dir.create(recursive: true);
      file = await File(p.join(dir.path, 'canli.kilit'))
          .open(mode: FileMode.append);
      await file.lock(FileLock.exclusive);
      _held = file;
      return true;
    } catch (_) {
      await file?.close().catchError((Object _) => file!);
      return false;
    }
  }
}

/// Puts this window on the network for live documents, where a program
/// is not there from its start (LifeOS Ofis): set by the program's shell,
/// asked by the editor before it shares. False when another window of
/// the program holds it.
Future<bool> Function()? startLiveHere;

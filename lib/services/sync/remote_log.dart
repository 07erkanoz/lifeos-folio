import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';

/// What the own devices' relay did, a line each, in Folio's own folder
/// (`uzak-senkron.log`): rooms waited in and why the relay shut them,
/// keepings alike and documents sent, and why one failed. Never what was
/// carried, nor a room's name: for finding out on the lawyer's computer
/// why two devices did not meet.
abstract final class RemoteLog {
  static const _keep = 2000;
  static Future<void> _last = Future.value();

  /// Where it is written; replaced under test.
  static Future<File?> Function() file = () async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
    return File(
      p.join((await folioSupportDirectory()).path, 'uzak-senkron.log'),
    );
  };

  /// [line] written, after what was written before it.
  static Future<void> note(String line) =>
      _last = _last.then((_) => _write(line)).catchError((Object _) {});

  /// The first characters of a device's id: enough to tell them apart.
  static String short(String id) => id.length > 6 ? id.substring(0, 6) : id;

  static Future<void> _write(String line) async {
    final f = await file();
    if (f == null) return;
    final at = DateTime.now().toIso8601String().substring(0, 19);
    await f.parent.create(recursive: true);
    await f.writeAsString('$at  $line\n', mode: FileMode.append, flush: true);
    if (await f.length() > 300 * 1024) {
      final lines = await f.readAsLines();
      await f.writeAsString(
        '${lines.skip(max(0, lines.length - _keep)).join('\n')}\n',
        flush: true,
      );
    }
  }
}

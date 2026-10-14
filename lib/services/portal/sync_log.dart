import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';

/// What UYAP's readings did, a line each, in Folio's own folder
/// (`uyap-senkron.log`): when a reading began and ended, how many cases it
/// read, which were not read and why, and why it stopped. For finding out
/// on the lawyer's computer what went wrong; the last lines kept.
abstract final class SyncLog {
  static const _keep = 3000;
  static Future<void> _last = Future.value();

  /// Where it is written; replaced under test.
  static Future<File?> Function() file = () async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
    return File(
      p.join((await folioSupportDirectory()).path, 'uyap-senkron.log'),
    );
  };

  /// [line] written, after what was written before it.
  static Future<void> note(String line) =>
      _last = _last.then((_) => _write(line)).catchError((Object _) {});

  static Future<void> _write(String line) async {
    final f = await file();
    if (f == null) return;
    final at = DateTime.now().toIso8601String().substring(0, 19);
    await f.parent.create(recursive: true);
    await f.writeAsString('$at  $line\n', mode: FileMode.append, flush: true);
    if (await f.length() > 600 * 1024) {
      final lines = await f.readAsLines();
      await f.writeAsString(
        '${lines.skip(max(0, lines.length - _keep)).join('\n')}\n',
        flush: true,
      );
    }
  }
}

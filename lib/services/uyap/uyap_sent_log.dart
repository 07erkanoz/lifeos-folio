import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';
import '../platform/atomic_file.dart';
import 'uyap_web_service.dart';

/// The documents sent to UYAP from any window, kept beside the ties for
/// as long as they are followed: an editor window is a process of its
/// own, and what it sent was followed in it alone, never in Folio's
/// "İşlemlerim", and was forgotten when it closed.
class UyapSentLog {
  UyapSentLog({this._directory});

  static UyapSentLog instance = UyapSentLog();

  final Directory? _directory;

  /// This process's writes, one after another.
  Future<void> _writing = Future.value();

  /// How long a send is kept: as long as "İşlemlerim" follows it.
  static const keep = Duration(days: 2);

  Future<File> _file() async => File(
    p.join(
      (_directory ?? await folioSharedDirectory()).path,
      'uyap',
      'gonderilenler.json',
    ),
  );

  /// The sends kept, those of the last [keep]; none when there is no
  /// folder to keep them in.
  Future<List<UyapSendReceipt>> read() async {
    try {
      final json = jsonDecode(await (await _file()).readAsString());
      final now = DateTime.now();
      return [
        for (final row in json is List ? json : const [])
          if (UyapSendReceipt.fromJson(row) case final r?
              when now.difference(r.startedAt) < keep)
            r,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Keeps [receipt] with the others, the file as it is now read under a
  /// lock the other windows wait on.
  Future<void> add(UyapSendReceipt receipt) {
    final run = _writing.then((_) => _add(receipt));
    _writing = run.catchError((Object _) {});
    return run;
  }

  Future<void> _add(UyapSendReceipt receipt) async {
    final file = await _file();
    final claim = await lockBeside(file);
    try {
      final all = {
        for (final r in [...await read(), receipt]) r.key: r,
      };
      await replaceFileIfChanged(
        file,
        utf8.encode(jsonEncode([for (final r in all.values) r.toJson()])),
      );
    } finally {
      try {
        await claim?.close();
      } catch (_) {}
    }
  }
}

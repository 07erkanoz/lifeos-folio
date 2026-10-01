import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import 'uyap_web_service.dart';

/// The e-Devlet page in a window of its own on Linux and macOS:
/// `folio-edevlet`, beside Folio in its bundle, a small program on the
/// system's WebKit (WebKitGTK on Linux).
/// It stops at UYAP's return address before loading it and hands back the
/// code e-Devlet put there.
class EdevletWindow {
  EdevletWindow._(this._process);

  final Process _process;

  static String get _helper =>
      p.join(p.dirname(Platform.resolvedExecutable), 'folio-edevlet');

  /// Replaced under test.
  @visibleForTesting
  static bool Function() check = _found;

  static bool get available => check();

  static bool _found() =>
      (Platform.isLinux || Platform.isMacOS) && File(_helper).existsSync();

  /// Opens [page]; the window stays until e-Devlet sends the lawyer back or
  /// the window is closed.
  static Future<EdevletWindow> open(Uri page, {required String hint}) async {
    try {
      return EdevletWindow._(
        await Process.start(_helper, [
          '--url',
          '$page',
          '--redirect',
          UyapWebService.edevletReturn,
          '--hint',
          hint,
        ]),
      );
    } on ProcessException {
      throw StateError(_missing);
    }
  }

  static String get _missing => Platform.isMacOS
      ? 'e-Devlet penceresi açılamadı. Folio\'yu yeniden kurmayı deneyin; '
            'e-imza kartınız varsa Adalet E-İmza uygulamasıyla '
            'bağlanabilirsiniz.'
      : 'e-Devlet penceresi açılamadı. Sistemde WebKitGTK (libwebkit2gtk-4.1) '
            'kurulu olmayabilir; e-imza kartınız varsa Adalet E-İmza '
            'uygulamasıyla bağlanabilirsiniz.';

  /// The code, or null when the window was closed without one.
  Future<String?> get code async {
    String? code;
    final errors = StringBuffer();
    final read = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          if (line.startsWith('kod=')) code = line.substring(4).trim();
        });
    final complaints = _process.stderr
        .transform(utf8.decoder)
        .forEach(errors.write);
    final exit = await _process.exitCode;
    await read;
    await complaints;
    if (code != null && code!.isNotEmpty) return code;
    // 2: closed by the lawyer. Anything else is the window failing to run,
    // a missing WebKitGTK the likeliest.
    if (exit == 2) return null;
    throw StateError(_missing);
  }

  /// Closes the window, as when the lawyer gives up from Folio's side.
  void close() => _process.kill();
}

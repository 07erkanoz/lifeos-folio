import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// The Adalet E-İmza application, which signs the card login to UYAP: is
/// it on this computer, and where it is had from.
abstract final class AdaletEimza {
  /// The Ministry of Justice's own page, with a download for each system.
  /// The page rather than a file: the version changes, the page does not.
  static const downloadPage = 'https://eimza.adalet.gov.tr';

  /// Replaced under test.
  @visibleForTesting
  static Future<bool> Function() check = _installed;

  static Future<bool> installed() => check();

  static Future<bool> _installed() async {
    if (!(Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      return false;
    }
    // Running: installed, whatever it was installed as.
    if (await _listening()) return true;
    if (Platform.isMacOS) {
      // An app in Applications, by whatever exact name this version has.
      try {
        return await Directory('/Applications')
            .list()
            .any((entry) => entry.path.toLowerCase().contains('adalet'));
      } on FileSystemException {
        return false;
      }
    }
    if (Platform.isLinux) {
      for (final path in const [
        '/usr/lib/adalet-eimza-tray',
        '/opt/adalet-eimza-tray',
        '/usr/lib/systemd/user/adalet-eimza-tray.service',
      ]) {
        if (await FileSystemEntity.type(path) !=
            FileSystemEntityType.notFound) {
          return true;
        }
      }
      return _run('systemctl', ['--user', 'cat', 'adalet-eimza-tray']);
    }
    // Windows: among the programs installed, for the machine or the user.
    for (final key in const [
      r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
      r'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
      r'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    ]) {
      if (await _run('reg', ['query', key, '/s', '/f', 'Adalet', '/d'])) {
        return true;
      }
    }
    return false;
  }

  /// Its signing service answers on port 5975 while it runs.
  static Future<bool> _listening() async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        5975,
        timeout: const Duration(milliseconds: 600),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _run(String command, List<String> arguments) async {
    try {
      final result = await Process.run(
        command,
        arguments,
      ).timeout(const Duration(seconds: 5));
      return result.exitCode == 0 &&
          (command != 'reg' || '${result.stdout}'.contains('Adalet'));
    } catch (_) {
      return false;
    }
  }
}

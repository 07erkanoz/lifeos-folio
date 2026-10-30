import 'dart:async';
import 'dart:io';

/// Linux Adalet E-İmza tray restarted for a login when the running one does
/// not answer or reads no card: the certificate is then read from a fresh
/// one.
class TrayRecovery {
  static const _unit = 'adalet-eimza-tray';

  static Future<void> prepare() async {
    if (!Platform.isLinux) return;
    final installed = await _systemctl(['cat', _unit], seconds: 5);
    if (installed?.exitCode != 0) return;
    // A few logins in a row would otherwise reach the service's start limit
    // (LifeOS allows four in five minutes), and systemd would refuse it.
    await _systemctl(['reset-failed', _unit], seconds: 5);
    // A copy opened from the menu holds port 5975 outside the service, and
    // the service then does not start at all (LifeOS skips it while the
    // port is taken): that copy goes, so that a fresh one reads the card.
    await _systemctl(['stop', _unit], seconds: 30);
    await _killPortHolders();
    await _systemctl(['start', _unit], seconds: 30);
    if (await _ready()) return;

    // A stuck Java sign request can ignore SIGTERM while holding port 5975.
    // Kill only the named user service, then let systemd start a fresh copy.
    await _systemctl(['kill', '--signal=SIGKILL', _unit], seconds: 10);
    await _killPortHolders();
    await _systemctl(['reset-failed', _unit], seconds: 5);
    await _systemctl(['start', _unit], seconds: 15);
    if (!await _ready()) {
      throw StateError('Adalet E-İmza yeniden başladı ancak hazır olmadı.');
    }
  }

  static Future<ProcessResult?> _systemctl(
    List<String> arguments, {
    required int seconds,
  }) async {
    try {
      return await Process.run('systemctl', [
        '--user',
        ...arguments,
      ]).timeout(Duration(seconds: seconds));
    } catch (_) {
      return null;
    }
  }

  /// Windows: Adalet E-İmza reads the card readers once, when it starts. One
  /// started before the reader was plugged in, or behind Windows Hello's
  /// virtual reader, reports no certificate until it is started again.
  /// Restarts it and waits for its port; false where it is not installed in
  /// the user's folder or does not come back.
  static Future<bool> restartOnWindows() async {
    if (!Platform.isWindows) return false;
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null) return false;
    final exe = File('$local\\Adalet E-imza\\Adalet E-imza.exe');
    if (!await exe.exists()) return false;
    try {
      await Process.run('taskkill', [
        '/F',
        '/IM',
        'Adalet E-imza.exe',
      ]).timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(seconds: 1));
      await Process.start(
        exe.path,
        const [],
        workingDirectory: exe.parent.path,
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      return false;
    }
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          5975,
          timeout: const Duration(seconds: 1),
        );
        socket.destroy();
        return true;
      } catch (_) {}
    }
    return false;
  }

  /// The user's own processes listening on port 5975: Adalet E-İmza's,
  /// whether the service's or one opened from the menu.
  static Future<void> _killPortHolders() async {
    for (final signal in ['-TERM', '-KILL']) {
      final pids = await _portHolders();
      if (pids.isEmpty) return;
      try {
        await Process.run('kill', [
          signal,
          ...pids,
        ]).timeout(const Duration(seconds: 5));
      } catch (_) {}
      for (var i = 0; i < 10 && (await _portHolders()).isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  static Future<List<String>> _portHolders() async {
    try {
      final r = await Process.run('ss', [
        '-Hltnp',
        'sport = :5975',
      ]).timeout(const Duration(seconds: 5));
      return {
        for (final m in RegExp(r'pid=(\d+)').allMatches('${r.stdout}'))
          m.group(1)!,
      }.toList();
    } catch (_) {
      return const [];
    }
  }

  /// Its port answering: the service is up. Java starts slowly at the low
  /// priority LifeOS gives the service, so it is given half a minute.
  static Future<bool> _ready() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          5975,
          timeout: const Duration(seconds: 1),
        );
        socket.destroy();
        await Future<void>.delayed(const Duration(seconds: 5));
        return true;
      } catch (_) {}
    }
    return false;
  }
}

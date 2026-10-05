import 'dart:async';
import 'dart:io';

/// Linux Adalet E-İmza tray preparation used before a new login, matching the
/// working web login flow: obtain the certificate only after a fresh tray.
class TrayRecovery {
  static const _unit = 'adalet-eimza-tray';

  static Future<void> prepare() async {
    if (!Platform.isLinux) return;
    final installed = await _systemctl(['cat', _unit], seconds: 5);
    if (installed?.exitCode != 0) return;
    final restarted = await _systemctl(['restart', _unit], seconds: 30);
    if (restarted?.exitCode != 0) {
      throw StateError('Adalet E-İmza yeniden başlatılamadı.');
    }
    if (await _ready()) return;

    // A stuck Java sign request can ignore SIGTERM while holding port 5975.
    // Kill only the named user service, then let systemd start a fresh copy.
    await _systemctl(['kill', '--signal=SIGKILL', _unit], seconds: 10);
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

  static Future<bool> _ready() async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final state = await _systemctl(['is-active', _unit], seconds: 5);
      if (state?.stdout.toString().trim() != 'active') continue;
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

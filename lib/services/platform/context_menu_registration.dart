import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'app_directories.dart';
import 'viewer_registration.dart';

class ContextMenuRegistration {
  static Future<String> register() async {
    if (!Platform.isLinux && !Platform.isWindows) {
      throw UnsupportedError(
        'Dosya yöneticisi bağlantıları masaüstünde kullanılır.',
      );
    }
    final root = await folioSupportDirectory();
    await root.create(recursive: true);
    final windows = Platform.isWindows;
    final asset = windows
        ? 'packaging/windows/register-viewer.ps1'
        : 'packaging/linux/context_menu.py';
    final script = File(
      p.join(
        root.path,
        windows ? 'register-context-menu.ps1' : 'register-context-menu.py',
      ),
    );
    await script.writeAsString(
      '${windows ? '\uFEFF' : ''}${await rootBundle.loadString(asset)}',
      flush: true,
    );
    final result = await ViewerRegistration.runCommand(
      windows ? 'powershell.exe' : 'python3',
      windows
          ? [
              '-NoProfile',
              '-NonInteractive',
              '-ExecutionPolicy',
              'Bypass',
              '-File',
              script.path,
              '-Executable',
              Platform.resolvedExecutable,
              '-ContextMenuOnly',
            ]
          : [script.path, Platform.resolvedExecutable],
    );
    if (result.exitCode != 0) {
      throw StateError('Sağ tuş bağlantıları eklenemedi: ${result.stderr}');
    }
    return windows
        ? 'Önizle ve düzenle bağlantıları eklendi. Windows 11’de “Daha fazla seçenek göster” altında bulunabilir.'
        : 'Bağlantılar eklendi. GNOME/Nemo: sağ tuş → Betikler. KDE: sağ tuş → Folio ile önizle / düzenle.';
  }
}

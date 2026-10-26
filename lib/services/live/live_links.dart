import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'live_remote.dart';

/// An invitation to a live document, opened as a link (approved mockup,
/// 26 Ekim 2026): `https://canli.lifeos.com.tr/#K7Q4MP2XD` on an Android
/// phone, where the system hands it to Folio; `lifeos-folio://katil/…` on a
/// computer, from the invitation page's "Folio'da aç". The page, the
/// phone, the computer and the system's notice all give it here, and the
/// home page asks to join with the code in place.
abstract final class LiveLinks {
  static const scheme = 'lifeos-folio';

  /// The last code a link brought, each one a new value (the same code
  /// opened twice asks twice).
  static final came = ValueNotifier<({String code, int n})?>(null);
  static int _n = 0;

  /// The code in [link], if it is an invitation's.
  static String? codeOf(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null) return null;
    if (uri.scheme == scheme) {
      final parts = [uri.host, ...uri.pathSegments].where((s) => s.isNotEmpty);
      return parts.length >= 2 && parts.first == 'katil'
          ? RemoteCode.read(parts.elementAt(1))
          : null;
    }
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == LiveRelay.page.host) {
      return RemoteCode.read(uri.fragment);
    }
    return null;
  }

  /// [link] taken, if it is an invitation's; false when it is not.
  static bool take(String link) {
    final code = codeOf(link);
    if (code == null) return false;
    came.value = (code: code, n: ++_n);
    return true;
  }

  /// What a computer's page link opens: `lifeos-folio://katil/K7Q4MP2XD`.
  static String deepLink(String code) => '$scheme://katil/$code';
}

/// Folio named on a computer as what opens `lifeos-folio://` links, for
/// the person alone and without asking: each start, as Folio's own path
/// may have moved. A store's package (MSIX) declares its own instead.
abstract final class LiveLinkRegistration {
  static Future<void> ensure() async {
    try {
      if (Platform.isWindows) {
        await _windows();
      } else if (Platform.isLinux) {
        await _linux();
      }
    } catch (_) {
      // Not having it costs a typed code, nothing more.
    }
  }

  static Future<void> _windows() async {
    final exe = Platform.resolvedExecutable;
    if (exe.toLowerCase().contains(r'\windowsapps\')) return;
    const key = r'HKCU\Software\Classes\' + LiveLinks.scheme;
    final command = '"$exe" "%1"';
    final now = await Process.run('reg', [
      'query',
      '$key\\shell\\open\\command',
      '/ve',
    ]);
    if (now.exitCode == 0 && '${now.stdout}'.contains(command)) return;
    for (final args in [
      ['add', key, '/ve', '/d', 'URL:LifeOS Folio', '/f'],
      ['add', key, '/v', 'URL Protocol', '/d', '', '/f'],
      ['add', '$key\\shell\\open\\command', '/ve', '/d', command, '/f'],
    ]) {
      await Process.run('reg', args);
    }
  }

  static Future<void> _linux() async {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return;
    final exe = Platform.resolvedExecutable;
    final dir = Directory(p.join(home, '.local', 'share', 'applications'));
    final file = File(p.join(dir.path, 'lifeos-folio-davet.desktop'));
    final entry =
        '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=LifeOS Folio\n'
        'Comment=Canlı belge davetini Folio’da açar\n'
        'Exec="$exe" %u\n'
        'NoDisplay=true\n'
        'Terminal=false\n'
        'MimeType=x-scheme-handler/${LiveLinks.scheme};\n';
    if (await file.exists() && await file.readAsString() == entry) return;
    await dir.create(recursive: true);
    await file.writeAsString(entry);
    await Process.run('xdg-mime', [
      'default',
      'lifeos-folio-davet.desktop',
      'x-scheme-handler/${LiveLinks.scheme}',
    ]);
  }
}

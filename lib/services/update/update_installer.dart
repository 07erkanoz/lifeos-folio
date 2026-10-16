import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';
import '../platform/file_actions.dart';
import 'update_manifest.dart';
import '../platform/store_package.dart';

/// A newer Folio fetched and installed from inside Folio: the package the
/// signed manifest names, downloaded, held to the manifest's size and
/// SHA-256 (the manifest's own Ed25519 signature having been checked by
/// [UpdateManifest.verify]), then handed to the system's way of
/// installing: Windows's setup, Linux's kur.sh, Android's installer, the
/// Mac's .app put in place of this one (or, where it cannot be, the disk
/// image opened in Finder).
abstract final class UpdateInstaller {
  /// Where Folio's own Linux setup (kur.sh) puts it; only a Folio living
  /// there is updated in place.
  static String get _linuxHome => p.join(
    Platform.environment['XDG_DATA_HOME'] ??
        p.join(Platform.environment['HOME'] ?? '', '.local', 'share'),
    'lifeos-folio',
  );

  /// Whether this Folio can install an update itself; elsewhere the
  /// download page is opened.
  static bool get canInstall {
    // The Store updates its own package.
    if (runsFromStorePackage) return false;
    if (Platform.isWindows || Platform.isAndroid || Platform.isMacOS) {
      return true;
    }
    if (Platform.isLinux) {
      return p.isWithin(_linuxHome, Platform.resolvedExecutable);
    }
    return false;
  }

  /// Whether the new Folio replaces this one where it stands and starts in
  /// its place, as on Linux; on a Mac where it cannot, the disk image is
  /// opened and the reader drags Folio into Applications.
  static bool get replacesInPlace {
    if (Platform.isLinux) return canInstall;
    if (Platform.isMacOS) {
      return macReplaceable(macBundleOf(Platform.resolvedExecutable));
    }
    return false;
  }

  /// The .app around [executable] (…/LifeOS Folio.app/Contents/MacOS/
  /// LifeOS Folio), or null when it is not in one: `flutter run`, say.
  @visibleForTesting
  static String? macBundleOf(String executable) {
    final macos = p.posix.dirname(executable);
    final contents = p.posix.dirname(macos);
    final app = p.posix.dirname(contents);
    if (p.posix.basename(macos) != 'MacOS' ||
        p.posix.basename(contents) != 'Contents' ||
        p.posix.extension(app) != '.app') {
      return null;
    }
    return app;
  }

  /// Whether the Folio at [app] may be swapped for the new one: not run
  /// from the disk image itself, nor from the copy macOS runs a just
  /// downloaded app from (App Translocation), and in a folder this user
  /// can write to. Applications is, for an administrator.
  @visibleForTesting
  static bool macReplaceable(String? app) {
    if (app == null) return false;
    if (p.posix.isWithin('/Volumes', app) ||
        app.contains('/AppTranslocation/')) {
      return false;
    }
    final probe = File(p.join(p.dirname(app), '.folio-yazma-$pid'));
    try {
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The package of [manifest], downloaded into Folio's folder and found
  /// whole and unchanged; a package already there and checked is used
  /// again. [progress] is told the bytes come and the bytes to come.
  static Future<File> download(
    UpdateManifest manifest, {
    void Function(int done, int total)? progress,
    HttpClient? client,
  }) async {
    if (runsFromStorePackage) {
      throw StateError('Microsoft Store’dan kurulan Folio’yu Store günceller.');
    }
    final folder = Directory(
      p.join((await folioSupportDirectory()).path, 'guncelleme'),
    );
    await folder.create(recursive: true);
    final name = manifest.url.pathSegments.isEmpty
        ? 'LifeOS-Folio-${manifest.version}'
        : manifest.url.pathSegments.last;
    final file = File(p.join(folder.path, name));
    if (await file.exists() && await _matches(file, manifest)) return file;
    // Older packages are not kept.
    await for (final old in folder.list()) {
      if (old is File) {
        try {
          await old.delete();
        } catch (_) {}
      }
    }
    final part = File('${file.path}.part');
    final http = client ?? HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await http.getUrl(manifest.url);
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      if (response.statusCode != 200) {
        throw StateError('Paket indirilemedi (HTTP ${response.statusCode}).');
      }
      final sink = part.openWrite();
      var done = 0;
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 60),
        )) {
          done += chunk.length;
          // Never more than the manifest says: a bigger answer is not it.
          if (done > manifest.size) {
            throw StateError('Paket beklenenden büyük geldi.');
          }
          sink.add(chunk);
          progress?.call(done, manifest.size);
        }
      } finally {
        await sink.close();
      }
      if (!await _matches(part, manifest)) {
        throw StateError(
          'İndirilen paket imzalı sürüm bilgisiyle uyuşmuyor; kurulmadı.',
        );
      }
      return await part.rename(file.path);
    } finally {
      if (client == null) http.close(force: true);
      if (await part.exists()) {
        try {
          await part.delete();
        } catch (_) {}
      }
    }
  }

  /// [file]'s size and SHA-256 are the manifest's; hashed off the window.
  static Future<bool> _matches(File file, UpdateManifest manifest) async {
    if (await file.length() != manifest.size) return false;
    final path = file.path;
    final digest = await Isolate.run(() async {
      final output = _DigestSink();
      final input = sha256.startChunkedConversion(output);
      await for (final chunk in File(path).openRead()) {
        input.add(chunk);
      }
      input.close();
      return output.value.toString();
    });
    return digest.toLowerCase() == manifest.sha256.toLowerCase();
  }

  /// Starts installing [package]. Windows: its setup, which closes Folio
  /// and offers to open the new one. Linux: kur.sh puts it in place, and
  /// Folio starts again as the new one ([restart], given the way to quit).
  /// Android: the phone's installer. Mac: the new .app is checked and
  /// copied beside this one, takes its place once Folio has quit and is
  /// opened; where this one cannot be replaced (run from the image, or
  /// from a folder the reader may not write to), the image is opened.
  static Future<void> install(
    File package, {
    required Future<void> Function() restart,
  }) async {
    if (runsFromStorePackage) {
      throw StateError('Microsoft Store’dan kurulan Folio’yu Store günceller.');
    }
    if (Platform.isWindows) {
      await Process.start(package.path, const [
        '/SP-',
        '/CLOSEAPPLICATIONS',
      ], mode: ProcessStartMode.detached);
      return;
    }
    if (Platform.isAndroid) {
      try {
        await FileActions.channel.invokeMethod<void>('install', {
          'path': package.path,
        });
      } on PlatformException catch (e) {
        throw StateError(e.message ?? 'Kurulum açılamadı.');
      }
      return;
    }
    if (Platform.isLinux) {
      final work = await Directory.systemTemp.createTemp('folio-guncelleme-');
      final open = await Process.run('tar', [
        '-xzf',
        package.path,
        '-C',
        work.path,
      ]);
      if (open.exitCode != 0) {
        throw StateError('Paket açılamadı: ${open.stderr}');
      }
      final setup = File(p.join(work.path, 'LifeOS-Folio', 'kur.sh'));
      if (!await setup.exists()) {
        throw StateError('Pakette kur.sh bulunamadı.');
      }
      final ran = await Process.run('sh', [setup.path]);
      if (ran.exitCode != 0) {
        throw StateError('Kurulum tamamlanamadı: ${ran.stderr}');
      }
      unawaited(work.delete(recursive: true).catchError((Object _) => work));
      // The new one starts once this one has let go of its lock.
      await Process.start('sh', [
        '-c',
        'sleep 2; exec "\$0"',
        p.join(_linuxHome, 'lifeos_folio'),
      ], mode: ProcessStartMode.detached);
      await restart();
      return;
    }
    if (Platform.isMacOS) {
      final app = macBundleOf(Platform.resolvedExecutable);
      if (app == null || !macReplaceable(app)) {
        // Finder shows the image's window: Folio and Applications.
        final opened = await Process.run('open', [package.path]);
        if (opened.exitCode != 0) {
          throw StateError('Paket açılamadı: ${opened.stderr}');
        }
        return;
      }
      final staged = await stageMac(package, app);
      // The new one takes this one's place once this one has quit.
      await Process.start('/bin/sh', [
        '-c',
        macSwapScript,
        'folio-guncelleme',
        '$pid',
        app,
        staged,
      ], mode: ProcessStartMode.detached);
      await restart();
      return;
    }
    throw StateError('Bu sistemde güncelleme Folio içinden kurulamıyor.');
  }

  /// The new Folio from the disk image [package], copied beside [app] as a
  /// hidden `.LifeOS Folio.app.yeni`, on the same disk so that putting it
  /// in place is a rename. Its code signature must hold and be the same
  /// developer's as [app]'s; the image's own SHA-256 was already held to
  /// the signed manifest.
  @visibleForTesting
  static Future<String> stageMac(
    File package,
    String app, {
    Future<ProcessResult> Function(String command, List<String> arguments)? run,
  }) async {
    final exec = run ?? Process.run;
    final work = await Directory.systemTemp.createTemp('folio-guncelleme-');
    final mount = p.join(work.path, 'disk');
    try {
      final attached = await exec('hdiutil', [
        'attach',
        '-nobrowse',
        '-readonly',
        '-noautoopen',
        '-mountpoint',
        mount,
        package.path,
      ]);
      if (attached.exitCode != 0) {
        throw StateError('Paket açılamadı: ${attached.stderr}');
      }
      try {
        final apps = Directory(mount).existsSync()
            ? [
                for (final e in Directory(mount).listSync(followLinks: false))
                  if (e is Directory && e.path.endsWith('.app')) e.path,
              ]
            : const <String>[];
        if (apps.length != 1) {
          throw StateError('Pakette LifeOS Folio bulunamadı.');
        }
        final source = apps.single;
        final verified = await exec('codesign', [
          '--verify',
          '--deep',
          '--strict',
          source,
        ]);
        if (verified.exitCode != 0) {
          throw StateError(
            'Paketteki uygulamanın imzası doğrulanamadı; kurulmadı.',
          );
        }
        final team = macTeamOf(
          (await exec('codesign', ['-dv', '--verbose=2', app])).stderr,
        );
        if (team != null &&
            macTeamOf(
                  (await exec('codesign', [
                    '-dv',
                    '--verbose=2',
                    source,
                  ])).stderr,
                ) !=
                team) {
          throw StateError(
            'Paketteki uygulama başka bir geliştiricinin imzasını taşıyor; '
            'kurulmadı.',
          );
        }
        final staged = p.join(p.dirname(app), '.${p.basename(app)}.yeni');
        final left = Directory(staged);
        if (left.existsSync()) await left.delete(recursive: true);
        final copied = await exec('ditto', [source, staged]);
        if (copied.exitCode != 0) {
          throw StateError('Yeni sürüm yerine kopyalanamadı: ${copied.stderr}');
        }
        return staged;
      } finally {
        await exec('hdiutil', ['detach', mount, '-force']);
      }
    } finally {
      unawaited(work.delete(recursive: true).catchError((Object _) => work));
    }
  }

  /// The developer's Team ID in `codesign -dv`'s report, null when the app
  /// carries none (signed ad hoc, a test build).
  @visibleForTesting
  static String? macTeamOf(Object? report) {
    final team = RegExp(
      r'^TeamIdentifier=(.+?)\s*$',
      multiLine: true,
    ).firstMatch('$report')?.group(1);
    return team == null || team == 'not set' ? null : team;
  }

  /// Run by /bin/sh with Folio's pid, its .app and the staged new one:
  /// waits for Folio to quit (two minutes at most, else leaves it as it
  /// is), swaps the two, putting the old one back if the new one cannot
  /// take its place, and opens Folio.
  @visibleForTesting
  static const macSwapScript = r'''
pid=$1 app=$2 new=$3
old="$(dirname "$app")/.$(basename "$app").eski"
i=0
while kill -0 "$pid" 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -gt 240 ]; then rm -rf "$new"; exit 1; fi
  sleep 0.5
done
rm -rf "$old"
if ! mv "$app" "$old"; then rm -rf "$new"; open "$app"; exit 1; fi
if mv "$new" "$app"; then rm -rf "$old"; else mv "$old" "$app"; fi
open "$app"
''';
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

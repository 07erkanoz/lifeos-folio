import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';
import '../platform/file_actions.dart';
import 'update_manifest.dart';

/// A newer Folio fetched and installed from inside Folio: the package the
/// signed manifest names, downloaded, held to the manifest's size and
/// SHA-256 (the manifest's own Ed25519 signature having been checked by
/// [UpdateManifest.verify]), then handed to the system's way of
/// installing: Windows's setup, Linux's kur.sh, Android's installer.
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
    if (Platform.isWindows || Platform.isAndroid) return true;
    if (Platform.isLinux) {
      return p.isWithin(_linuxHome, Platform.resolvedExecutable);
    }
    return false;
  }

  /// The package of [manifest], downloaded into Folio's folder and found
  /// whole and unchanged; a package already there and checked is used
  /// again. [progress] is told the bytes come and the bytes to come.
  static Future<File> download(
    UpdateManifest manifest, {
    void Function(int done, int total)? progress,
    HttpClient? client,
  }) async {
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
  /// Android: the phone's installer.
  static Future<void> install(
    File package, {
    required Future<void> Function() restart,
  }) async {
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
    throw StateError('Bu sistemde güncelleme Folio içinden kurulamıyor.');
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

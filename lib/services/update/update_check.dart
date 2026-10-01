import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';
import 'update_manifest.dart';

/// Looks, now and then, whether a newer Folio has been published, and says
/// so through [available]. It never downloads or installs anything itself:
/// the reader is told, and chooses.
class UpdateCheck {
  UpdateCheck({
    @visibleForTesting Future<String?> Function(Uri address)? fetch,
    @visibleForTesting Future<int> Function()? currentBuild,
    @visibleForTesting Future<File> Function()? settings,
    @visibleForTesting String? platform,
    @visibleForTesting List<int>? key,
  }) : _fetch = fetch ?? _get,
       _currentBuild = currentBuild ?? _installedBuild,
       _settings = settings ?? _settingsFile,
       _platform = platform ?? platformName,
       // A named argument may not begin with an underscore, so `this._key`
       // cannot be one.
       // ignore: prefer_initializing_formals
       _key = key;

  static final instance = UpdateCheck();

  final Future<String?> Function(Uri address) _fetch;
  final Future<int> Function() _currentBuild;
  final Future<File> Function() _settings;
  final String? _platform;
  final List<int>? _key;

  /// The newer release, while there is one the reader has not skipped.
  final available = ValueNotifier<UpdateManifest?>(null);

  Timer? _first, _every;

  /// The platform name a manifest is published under; null where Folio is
  /// not distributed from lifeos.com.tr.
  static String? get platformName {
    if (kIsWeb) return null;
    if (Platform.isWindows) return 'windows-x64';
    if (Platform.isLinux) return 'linux-x64';
    if (Platform.isAndroid) return 'android';
    return null;
  }

  /// Checks a little after start, so opening Folio never waits on it, then
  /// every six hours while it stays open.
  void start() {
    // Under flutter test a pending timer fails the test, and there is no
    // network to ask anyway.
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    if (_platform == null || _first != null) return;
    _first = Timer(const Duration(seconds: 10), () => unawaited(check()));
    _every = Timer.periodic(
      const Duration(hours: 6),
      (_) => unawaited(check()),
    );
  }

  void stop() {
    _first?.cancel();
    _every?.cancel();
    _first = _every = null;
  }

  /// Looks once. Quiet on every failure: no network, nothing published yet,
  /// a manifest that does not verify. None of those is the reader's concern.
  Future<UpdateManifest?> check() async {
    final platform = _platform;
    if (platform == null) return null;
    try {
      final text = await _fetch(UpdateManifest.addressFor(platform));
      if (text == null) return null;
      final manifest = await UpdateManifest.verify(
        text,
        platform: platform,
        key: _key,
      );
      final newer = manifest.build > await _currentBuild();
      final skipped = manifest.build == await _skipped();
      available.value = newer && !skipped ? manifest : null;
      return available.value;
    } catch (e) {
      debugPrint('Güncelleme denetimi: $e');
      return null;
    }
  }

  /// Never offers [manifest]'s build again; a later one still will be.
  Future<void> skip(UpdateManifest manifest) async {
    available.value = null;
    try {
      final file = await _settings();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'skippedBuild': manifest.build}));
    } catch (_) {}
  }

  /// Hides the notice until the next check.
  void later() => available.value = null;

  Future<int?> _skipped() async {
    try {
      final file = await _settings();
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      return json is Map && json['skippedBuild'] is int
          ? json['skippedBuild'] as int
          : null;
    } catch (_) {
      return null;
    }
  }

  static Future<File> _settingsFile() async =>
      File(p.join((await folioSupportDirectory()).path, 'update.json'));

  static Future<int> _installedBuild() async =>
      int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;

  static Future<String?> _get(Uri address) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(address);
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      // Nothing published yet for this platform: not an error.
      if (response.statusCode == HttpStatus.notFound) return null;
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('${response.statusCode}', uri: address);
      }
      return await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
    } finally {
      client.close(force: true);
    }
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';
import 'office_peer.dart';

/// A device this Folio knows (docs/buro.md, Tanıma): its public key, which
/// every talk with it is checked against from now on, and how it was
/// called when it was known.
class KnownDevice {
  const KnownDevice({
    required this.deviceId,
    required this.userId,
    required this.publicKey,
    required this.name,
    required this.device,
    required this.platform,
    required this.knownAt,
    this.code = '',
  });

  final String deviceId, userId;

  /// The device's Ed25519 public key, base64.
  final String publicKey;
  final String name, device;
  final OfficePlatform platform;
  final DateTime knownAt;

  /// The six digits both screens showed when they knew each other: to be
  /// compared later, by telephone, by whoever wants to be sure.
  final String code;

  Map<String, Object?> toJson() => {
    'id': deviceId,
    'u': userId,
    'dk': publicKey,
    'n': name,
    'c': device,
    'p': platform.name,
    'at': knownAt.toUtc().toIso8601String(),
    'kod': code,
  };

  static KnownDevice? fromJson(Object? json) {
    if (json is! Map) return null;
    String text(String key) => json[key] is String ? json[key] as String : '';
    final id = text('id'), key = text('dk');
    if (id.isEmpty || key.isEmpty) return null;
    return KnownDevice(
      deviceId: id,
      userId: text('u'),
      publicKey: key,
      name: text('n'),
      device: text('c'),
      platform: OfficePlatform.of(text('p')),
      knownAt: DateTime.tryParse(text('at'))?.toLocal() ?? DateTime(2026),
      code: text('kod'),
    );
  }

  /// As the list shows it while it is not on the network.
  OfficePeer asAbsent(DateTime? lastSeen) => OfficePeer(
    deviceId: deviceId,
    userId: userId,
    name: name,
    device: device,
    platform: platform,
    online: false,
    lastSeen: lastSeen,
  );
}

/// The devices known, kept beside Folio's settings. Only public keys and
/// names: nothing in it opens anything.
class KnownDevices {
  KnownDevices({Future<File> Function()? file}) : _file = file ?? _default;

  static Future<File> _default() async =>
      File(p.join((await folioSupportDirectory()).path, 'buro_cihazlar.json'));

  final Future<File> Function() _file;
  Map<String, KnownDevice>? _devices;

  Future<Map<String, KnownDevice>> _load() async {
    final held = _devices;
    if (held != null) return held;
    final devices = <String, KnownDevice>{};
    try {
      final file = await _file();
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is List) {
          for (final one in json) {
            final d = KnownDevice.fromJson(one);
            if (d != null) devices[d.deviceId] = d;
          }
        }
      }
    } catch (_) {}
    return _devices = devices;
  }

  Future<List<KnownDevice>> all() async => (await _load()).values.toList();

  Future<KnownDevice?> of(String deviceId) async => (await _load())[deviceId];

  Future<void> remember(KnownDevice device) async {
    final devices = await _load();
    devices[device.deviceId] = device;
    await _save(devices);
  }

  /// [device], told of by another own device's list: taken only if the
  /// user did not forget it here. Checked and kept with no wait between,
  /// so that a forgetting cannot fall in between.
  Future<bool> rememberUnlessForgotten(KnownDevice device) async {
    final devices = await _load();
    final gone = await _loadForgotten();
    if (gone.contains(device.deviceId)) return false;
    if (devices.containsKey(device.deviceId)) return false;
    devices[device.deviceId] = device;
    await _save(devices);
    return true;
  }

  /// Known again by a code typed or compared: no longer one forgotten.
  Future<void> unforget(String deviceId) async {
    final gone = await _loadForgotten();
    if (gone.remove(deviceId)) await _saveForgotten(gone);
  }

  /// The devices the user forgot here.
  Future<Set<String>> forgottenIds() async => {...await _loadForgotten()};

  Future<void> forget(String deviceId) async {
    final devices = await _load();
    final gone = await _loadForgotten();
    // Not let back in by another own device's list (the directory).
    if (gone.add(deviceId)) await _saveForgotten(gone);
    if (devices.remove(deviceId) == null) return;
    await _save(devices);
  }

  /// Whether the user forgot [deviceId] here: another own device's list
  /// does not bring it back; only a code does.
  Future<bool> forgot(String deviceId) async =>
      (await _loadForgotten()).contains(deviceId);

  Set<String>? _forgotten;

  Future<File> _forgottenFile() async {
    final file = await _file();
    return File('${file.path}.unutulan');
  }

  Future<Set<String>> _loadForgotten() async {
    final held = _forgotten;
    if (held != null) return held;
    final gone = <String>{};
    try {
      final file = await _forgottenFile();
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is List) gone.addAll(json.whereType<String>());
      }
    } catch (_) {}
    return _forgotten = gone;
  }

  Future<void> _saveForgotten(Set<String> gone) => _saving = _saving
      .then((_) async {
        final file = await _forgottenFile();
        await file.parent.create(recursive: true);
        final part = File('${file.path}.part');
        await part.writeAsString(jsonEncode(gone.toList()), flush: true);
        await part.rename(file.path);
      })
      .catchError((Object _) {});

  // One write at a time: two at once raced for the same part file.
  Future<void> _saving = Future.value();

  Future<void> _save(Map<String, KnownDevice> devices) =>
      _saving = _saving.then((_) => _write(devices)).catchError((Object _) {});

  Future<void> _write(Map<String, KnownDevice> devices) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final part = File('${file.path}.part');
    await part.writeAsString(
      jsonEncode([for (final d in devices.values) d.toJson()]),
      flush: true,
    );
    await part.rename(file.path);
  }
}

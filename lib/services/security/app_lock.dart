import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';

/// Folio's sign-in password and its recovery code (Ayarlar › Güvenlik).
///
/// Only a slowed hash of each is kept (PBKDF2-HMAC-SHA256, worked out off
/// the screen's isolate), never the words. Folio is locked at its start
/// and after the chosen minutes unused, and wrong tries are made to wait
/// longer each time. It keeps Folio from being opened; it does not encrypt
/// the files on the disk.
class AppLock extends ChangeNotifier {
  AppLock({Future<File> Function()? file, this.iterations = 210000})
    : _file = file ?? _default;

  static AppLock? _instance;
  static AppLock get instance => _instance ??= AppLock();
  @visibleForTesting
  static set instance(AppLock lock) => _instance = lock;

  static Future<File> _default() async =>
      File(p.join((await folioSupportDirectory()).path, 'kilit.json'));

  final Future<File> Function() _file;
  final int iterations;

  Map<String, Object?>? _kept;
  bool _loaded = false, _locked = false;
  int _wrong = 0;
  DateTime? _waitUntil;
  Timer? _idle;

  bool get loaded => _loaded;
  bool get enabled => _kept != null;
  bool get locked => _locked;

  /// Minutes unused after which Folio locks itself; 0 for never.
  int get idleMinutes => (_kept?['bosta'] as int?) ?? 15;

  /// When the next try may be made, after wrong ones.
  DateTime? get waitUntil => _waitUntil;

  Future<void> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is Map<String, Object?> && json['hash'] is String) {
          _kept = json;
        }
      }
    } catch (_) {}
    _loaded = true;
    _locked = enabled;
    notifyListeners();
  }

  static List<int> _random(int n) {
    final r = Random.secure();
    return [for (var i = 0; i < n; i++) r.nextInt(256)];
  }

  /// A code to write down: six groups of four letters and digits, none of
  /// those mistaken for each other.
  static String newRecoveryCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return [
      for (var g = 0; g < 6; g++)
        [for (var i = 0; i < 4; i++) alphabet[r.nextInt(alphabet.length)]]
            .join(),
    ].join('-');
  }

  static String _plainCode(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  Future<String> _hash(String secret, List<int> salt) {
    final rounds = iterations;
    return Isolate.run(() async {
      final key = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: rounds,
        bits: 256,
      ).deriveKeyFromPassword(password: secret, nonce: salt);
      return base64Encode(await key.extractBytes());
    });
  }

  Future<bool> _matches(String secret, String saltKey, String hashKey) async {
    final kept = _kept;
    final salt = kept?[saltKey], hash = kept?[hashKey];
    if (salt is! String || hash is! String) return false;
    final got = await _hash(secret, base64Decode(salt));
    // Compared in full, not stopping at the first difference.
    var diff = got.length ^ hash.length;
    for (var i = 0; i < min(got.length, hash.length); i++) {
      diff |= got.codeUnitAt(i) ^ hash.codeUnitAt(i);
    }
    return diff == 0;
  }

  static String? weakness(String password) =>
      password.length < 8 ? 'Şifre en az 8 karakter olmalı.' : null;

  /// Sets the password (and turns the lock on); the recovery code it
  /// returns is shown once and kept only as its hash.
  Future<String> setPassword(String password, {int? idleMinutes}) async {
    final code = newRecoveryCode();
    final salt = _random(16), recoverySalt = _random(16);
    _kept = {
      'v': 1,
      'tuz': base64Encode(salt),
      'hash': await _hash(password, salt),
      'ktuz': base64Encode(recoverySalt),
      'khash': await _hash(_plainCode(code), recoverySalt),
      'bosta': idleMinutes ?? this.idleMinutes,
    };
    await _save();
    _loaded = true;
    _locked = false;
    _wrong = 0;
    _waitUntil = null;
    notifyListeners();
    touch();
    return code;
  }

  Future<void> _save() async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final kept = _kept;
    if (kept == null) {
      if (await file.exists()) await file.delete();
      return;
    }
    final part = File('${file.path}.part');
    await part.writeAsString(jsonEncode(kept), flush: true);
    await part.rename(file.path);
  }

  Future<bool> _try(Future<bool> Function() check) async {
    final wait = _waitUntil;
    if (wait != null && DateTime.now().isBefore(wait)) return false;
    final ok = await check();
    if (ok) {
      _wrong = 0;
      _waitUntil = null;
    } else {
      _wrong++;
      // After three wrong tries, 30 seconds, then twice as long each time.
      if (_wrong >= 3) {
        _waitUntil = DateTime.now().add(
          Duration(seconds: 30 * (1 << min(_wrong - 3, 6))),
        );
      }
    }
    notifyListeners();
    return ok;
  }

  Future<bool> unlock(String password) async {
    final ok = await _try(() => _matches(password, 'tuz', 'hash'));
    if (ok) {
      _locked = false;
      notifyListeners();
      touch();
    }
    return ok;
  }

  /// With the recovery code, a new password; a new code is returned, as
  /// the old one has been seen.
  Future<String?> recover(String code, String newPassword) async {
    final ok = await _try(() => _matches(_plainCode(code), 'ktuz', 'khash'));
    if (!ok) return null;
    return setPassword(newPassword);
  }

  Future<bool> checkPassword(String password) =>
      _try(() => _matches(password, 'tuz', 'hash'));

  /// Turns the lock off, with the password.
  Future<bool> disable(String password) async {
    if (!await checkPassword(password)) return false;
    _kept = null;
    _locked = false;
    _idle?.cancel();
    await _save();
    notifyListeners();
    return true;
  }

  Future<void> setIdleMinutes(int minutes) async {
    final kept = _kept;
    if (kept == null) return;
    kept['bosta'] = minutes;
    await _save();
    notifyListeners();
    touch();
  }

  void lockNow() {
    if (!enabled) return;
    _idle?.cancel();
    _locked = true;
    notifyListeners();
  }

  /// The user did something: the idle time starts again.
  void touch() {
    _idle?.cancel();
    if (!enabled || _locked || idleMinutes == 0) return;
    _idle = Timer(Duration(minutes: idleMinutes), lockNow);
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }
}

import 'dart:convert';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

import '../security/secret_store.dart';

/// Who this Folio is on the office's network (docs/buro.md, Kimlik): a key
/// of its own, the device's, and the person's, which the person's devices
/// will share once they know each other. Both are kept in the system's
/// safe store and nowhere else; where there is none, they last as long as
/// Folio runs and the device is seen anew at its next start.
class OfficeIdentity {
  OfficeIdentity._({
    required this.device,
    required this.devicePublic,
    required this.user,
    required this.userPublic,
    required this.kept,
  });

  final SimpleKeyPair device, user;
  final SimplePublicKey devicePublic, userPublic;

  /// False when the keys could not be kept and are this run's only.
  final bool kept;

  /// Short, stable names of the two public keys: what the network sees.
  String get deviceId => idOf(devicePublic.bytes);
  String get userId => idOf(userPublic.bytes);

  static const _name = 'buro_kimlik';

  /// The first sixteen hex digits of the key's SHA-256: enough to tell an
  /// office's devices apart, short enough for a DNS-SD name.
  static String idOf(List<int> key) =>
      hash.sha256.convert(key).toString().substring(0, 16);

  static Future<OfficeIdentity> load({SecretStore? store}) async {
    final safe = store ?? SecretStore();
    // A keyring that does not answer (a Linux session without one) must not
    // hold the network: the keys are then this run's.
    const wait = Duration(seconds: 5);
    final kept = await safe
        .read(_name)
        .timeout(wait, onTimeout: () => null)
        .catchError((Object _) => null);
    final ed = Ed25519();
    List<int>? seed(String key) {
      final value = kept?[key];
      if (value is! String) return null;
      try {
        final bytes = base64Decode(value);
        return bytes.length == 32 ? bytes : null;
      } catch (_) {
        return null;
      }
    }

    final deviceSeed = seed('cihaz'), userSeed = seed('kullanici');
    final device = deviceSeed != null
        ? await ed.newKeyPairFromSeed(deviceSeed)
        : await ed.newKeyPair();
    final user = userSeed != null
        ? await ed.newKeyPairFromSeed(userSeed)
        : await ed.newKeyPair();
    var stored = deviceSeed != null && userSeed != null;
    if (!stored) {
      stored = await safe
          .write(_name, {
            'cihaz': base64Encode(await device.extractPrivateKeyBytes()),
            'kullanici': base64Encode(await user.extractPrivateKeyBytes()),
          })
          .timeout(wait, onTimeout: () => false)
          .catchError((Object _) => false);
    }
    return OfficeIdentity._(
      device: device,
      devicePublic: await device.extractPublicKey(),
      user: user,
      userPublic: await user.extractPublicKey(),
      kept: stored,
    );
  }
}

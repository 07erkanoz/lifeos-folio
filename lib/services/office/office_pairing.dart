import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter/foundation.dart';

import 'office_identity.dart';
import 'office_known.dart';
import 'office_link.dart';
import 'office_peer.dart';

enum PairingState {
  /// Reaching the other device.
  connecting,

  /// Waiting for the other device to say its part.
  waiting,

  /// The code is on both screens; the user is to compare it.
  code,

  /// This side said the codes match; the other has not yet.
  confirmed,

  /// Both said so: the other device is known.
  done,
  rejected,
  failed,
}

/// Knowing a new device by a code (docs/buro.md, Tanıma).
///
/// The one who starts commits to a random number before hearing the
/// other's, and shows it only after; the six digits are made from both
/// devices' public keys and both numbers. Someone between the two could
/// not choose a number that makes the two screens show the same code, so
/// when the users see the same code each holds the other's real key.
class OfficePairing extends ChangeNotifier {
  OfficePairing._(
    this._link,
    this._identity,
    this._self, {
    required this.incoming,
    required this.onKnown,
  }) {
    _timeout = Timer(limit, () => _fail('Süre doldu.'));
    _listen = _link?.messages.listen(_heard, onDone: _ended);
  }

  /// How long a pairing may wait for the two users.
  static const limit = Duration(minutes: 3);

  OfficeLink? _link;
  final OfficeIdentity _identity;
  final OfficePeer _self;
  final Future<void> Function(KnownDevice device) onKnown;
  StreamSubscription<Map<String, Object?>>? _listen;
  late final Timer _timeout;

  /// Whether the other device started it.
  final bool incoming;

  PairingState _state = PairingState.connecting;
  PairingState get state => _state;

  /// "482 917", once both numbers are known.
  String? get code => _code;
  String? _code;

  /// The other device, as it says it is.
  OfficePeer? get other => _other;
  OfficePeer? _other;
  String? _otherKey;

  /// Why it failed, in the user's words.
  String? get reason => _reason;
  String? _reason;

  late final List<int> _mineNonce = _random(32);
  List<int>? _theirNonce, _theirCommit;
  bool _mine = false, _theirs = false;

  bool get finished =>
      _state == PairingState.done ||
      _state == PairingState.rejected ||
      _state == PairingState.failed;

  static List<int> _random(int n) {
    final r = Random.secure();
    return [for (var i = 0; i < n; i++) r.nextInt(256)];
  }

  List<int> get _myKey => _identity.devicePublic.bytes;

  Map<String, Object?> get _about => {
    'v': OfficePeer.protocol,
    'id': _identity.deviceId,
    'dk': base64Encode(_myKey),
    'u': _self.userId,
    'n': _self.name,
    'c': _self.device,
    'p': _self.platform.name,
  };

  /// Starts knowing [peer], reached at its address.
  static OfficePairing start({
    required OfficeIdentity identity,
    required OfficePeer self,
    required OfficePeer peer,
    required Future<void> Function(KnownDevice device) onKnown,
  }) {
    final pairing = OfficePairing._(
      null,
      identity,
      self,
      incoming: false,
      onKnown: onKnown,
    );
    pairing._other = peer;
    unawaited(pairing._connect(peer));
    return pairing;
  }

  Future<void> _connect(OfficePeer peer) async {
    final host = peer.host;
    if (host == null || peer.port == 0) {
      _fail('Cihazın adresi henüz bilinmiyor.');
      return;
    }
    try {
      final link = await OfficeLink.connect(host, peer.port);
      if (finished) {
        await link.close();
        return;
      }
      _link = link;
      _listen = link.messages.listen(_heard, onDone: _ended);
      link.send({
        't': 'pair',
        ..._about,
        'commit': base64Encode(
          hash.sha256.convert([..._myKey, ..._mineNonce]).bytes,
        ),
      });
      _set(PairingState.waiting);
    } catch (_) {
      _fail('Cihaza ulaşılamadı.');
    }
  }

  /// Answers a device that started knowing this one, with what it said
  /// first.
  static OfficePairing answer({
    required OfficeLink link,
    required Map<String, Object?> first,
    required OfficeIdentity identity,
    required OfficePeer self,
    required Future<void> Function(KnownDevice device) onKnown,
  }) {
    final pairing = OfficePairing._(
      link,
      identity,
      self,
      incoming: true,
      onKnown: onKnown,
    );
    pairing._opened(first);
    return pairing;
  }

  void _opened(Map<String, Object?> first) {
    final commit = _bytes(first['commit']);
    if (!_learn(first) || commit == null || commit.length != 32) {
      _fail('Karşı cihaz anlaşılamadı.');
      return;
    }
    _theirCommit = commit;
    _link?.send({'t': 'pair-ok', ..._about, 'nonce': base64Encode(_mineNonce)});
    _set(PairingState.waiting);
  }

  /// Takes the other device's word for who it is, if its id is its key's.
  bool _learn(Map<String, Object?> about) {
    final key = _bytes(about['dk']);
    final id = about['id'];
    if (key == null || key.length != 32 || id != OfficeIdentity.idOf(key)) {
      return false;
    }
    if (id == _identity.deviceId) return false;
    final peer = OfficePeer.fromAnnouncement(
      {
        for (final e in about.entries)
          if (e.value is String || e.value is int) e.key: '${e.value}',
      },
      host: _other?.host,
      port: _other?.port ?? 0,
    );
    if (peer == null) return false;
    _other = peer;
    _otherKey = base64Encode(key);
    return true;
  }

  static List<int>? _bytes(Object? value) {
    if (value is! String) return null;
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  void _heard(Map<String, Object?> m) {
    if (finished) return;
    switch (m['t']) {
      case 'pair-ok' when !incoming && _theirNonce == null:
        final nonce = _bytes(m['nonce']);
        if (!_learn(m) || nonce == null || nonce.length != 32) {
          _fail('Karşı cihaz anlaşılamadı.');
          return;
        }
        _theirNonce = nonce;
        _link?.send({'t': 'reveal', 'nonce': base64Encode(_mineNonce)});
        _showCode(
          starter: _myKey,
          answerer: base64Decode(_otherKey!),
          starterNonce: _mineNonce,
          answererNonce: nonce,
        );
      case 'reveal' when incoming && _theirNonce == null:
        final nonce = _bytes(m['nonce']);
        final theirKey = base64Decode(_otherKey!);
        if (nonce == null ||
            nonce.length != 32 ||
            !listEquals(
              hash.sha256.convert([...theirKey, ...nonce]).bytes,
              _theirCommit,
            )) {
          // What it shows now is not what it committed to: someone between.
          _fail('Karşı cihazın söyledikleri tutmadı; tanıma durduruldu.');
          return;
        }
        _theirNonce = nonce;
        _showCode(
          starter: theirKey,
          answerer: _myKey,
          starterNonce: nonce,
          answererNonce: _mineNonce,
        );
      case 'confirm' when _code != null:
        _theirs = true;
        unawaited(_maybeDone());
      case 'reject':
        _end(PairingState.rejected, 'Karşı tarafta reddedildi.');
      case 'busy':
        _fail('Karşı cihaz şu anda başka bir cihazı tanıyor.');
      default:
        _fail('Karşı cihaz anlaşılamadı.');
    }
  }

  void _showCode({
    required List<int> starter,
    required List<int> answerer,
    required List<int> starterNonce,
    required List<int> answererNonce,
  }) {
    _code = codeOf(starter, answerer, starterNonce, answererNonce);
    _set(PairingState.code);
  }

  /// The six digits both screens show.
  @visibleForTesting
  static String codeOf(
    List<int> starterKey,
    List<int> answererKey,
    List<int> starterNonce,
    List<int> answererNonce,
  ) {
    final d = hash.sha256.convert([
      ...utf8.encode('folio-buro-tanima-1'),
      ...starterKey,
      ...answererKey,
      ...starterNonce,
      ...answererNonce,
    ]).bytes;
    final n = ((d[0] << 24) | (d[1] << 16) | (d[2] << 8) | d[3]) % 1000000;
    final six = '$n'.padLeft(6, '0');
    return '${six.substring(0, 3)} ${six.substring(3)}';
  }

  /// The user saw the same code on both screens.
  void confirm() {
    if (_code == null || _mine || finished) return;
    _mine = true;
    _link?.send({'t': 'confirm'});
    _set(PairingState.confirmed);
    unawaited(_maybeDone());
  }

  /// The user did not, or does not want this device known.
  void reject() {
    if (finished) return;
    _link?.send({'t': 'reject'});
    _end(PairingState.rejected, null);
  }

  Future<void> _maybeDone() async {
    if (!_mine || !_theirs || finished) return;
    final other = _other!;
    await onKnown(
      KnownDevice(
        deviceId: other.deviceId,
        userId: other.userId,
        publicKey: _otherKey!,
        name: other.name,
        device: other.device,
        platform: other.platform,
        knownAt: DateTime.now(),
      ),
    );
    _end(PairingState.done, null);
  }

  void _ended() {
    if (!finished) _fail('Bağlantı kesildi.');
  }

  void _fail(String reason) => _end(PairingState.failed, reason);

  void _end(PairingState state, String? reason) {
    if (finished) return;
    _reason = reason;
    _timeout.cancel();
    _set(state);
    unawaited(_listen?.cancel());
    // The last word is let go before the line is put down.
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 200))
          .then((_) => _link?.close()),
    );
  }

  void _set(PairingState state) {
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    if (!finished) reject();
    _timeout.cancel();
    super.dispose();
  }
}

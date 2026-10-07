import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'office_identity.dart';
import 'office_known.dart';
import 'office_link.dart';

/// An encrypted talk between two known devices (docs/buro.md, Aktarım).
///
/// Each side makes a key for this talk alone and signs it with its device
/// key, the one the other kept when they knew each other; an unknown
/// device, or a signature that does not hold, ends it. The two keys give
/// one key each way, and every message after is sealed with
/// ChaCha20-Poly1305 under a counter that only goes up: a message changed,
/// replayed or put out of order is not opened.
class OfficeChannel {
  OfficeChannel._(this._link, this.peer, this._send, this._receive);

  final OfficeLink _link;

  /// The known device on the other side.
  final KnownDevice peer;
  final SecretKey _send, _receive;
  int _sent = 0, _received = 0;
  final _aead = Chacha20.poly1305Aead();
  final _messages = StreamController<Map<String, Object?>>.broadcast();
  StreamSubscription<Map<String, Object?>>? _listen;

  /// What the other side says, opened; done when the talk ends.
  Stream<Map<String, Object?>> get messages => _messages.stream;
  bool get closed => _link.closed;

  static const _context = 'folio-buro-kanal-1';

  static List<int> _signed(List<int> starter, List<int> answerer) => [
    ...utf8.encode(_context),
    ...starter,
    ...answerer,
  ];

  /// Opens a talk to [peer], reached at [host]:[port].
  static Future<OfficeChannel> open({
    required OfficeIdentity identity,
    required KnownDevice peer,
    required String host,
    required int port,
  }) async {
    final link = await OfficeLink.connect(host, port);
    try {
      final mine = await X25519().newKeyPair();
      final minePublic = (await mine.extractPublicKey()).bytes;
      final reply = link.messages.first.timeout(const Duration(seconds: 10));
      link.send({
        't': 'hello',
        'id': identity.deviceId,
        'eph': base64Encode(minePublic),
        'sig': base64Encode(
          (await Ed25519().sign(
            _signed(minePublic, const []),
            keyPair: identity.device,
          )).bytes,
        ),
      });
      final m = await reply;
      final theirs = _bytes(m['eph']);
      if (m['t'] != 'hello-ok' ||
          m['id'] != peer.deviceId ||
          theirs == null ||
          theirs.length != 32 ||
          !await _verify(peer, _signed(minePublic, theirs), m['sig'])) {
        throw const OfficeChannelException('Karşı cihaz doğrulanamadı.');
      }
      final (send, receive) = await _keys(mine, theirs, minePublic, theirs);
      return OfficeChannel._(link, peer, send, receive).._start();
    } catch (e) {
      await link.close();
      if (e is OfficeChannelException) rethrow;
      throw OfficeChannelException('Cihaza bağlanılamadı: $e');
    }
  }

  /// Answers a talk a device opened with [hello], if it is a known one.
  static Future<OfficeChannel?> accept({
    required OfficeLink link,
    required Map<String, Object?> hello,
    required OfficeIdentity identity,
    required Future<KnownDevice?> Function(String deviceId) known,
  }) async {
    try {
      final id = hello['id'];
      final theirs = _bytes(hello['eph']);
      final peer = id is String ? await known(id) : null;
      if (peer == null ||
          theirs == null ||
          theirs.length != 32 ||
          !await _verify(peer, _signed(theirs, const []), hello['sig'])) {
        await link.close();
        return null;
      }
      final mine = await X25519().newKeyPair();
      final minePublic = (await mine.extractPublicKey()).bytes;
      link.send({
        't': 'hello-ok',
        'id': identity.deviceId,
        'eph': base64Encode(minePublic),
        'sig': base64Encode(
          (await Ed25519().sign(
            _signed(theirs, minePublic),
            keyPair: identity.device,
          )).bytes,
        ),
      });
      final (receive, send) = await _keys(mine, theirs, theirs, minePublic);
      return OfficeChannel._(link, peer, send, receive).._start();
    } catch (_) {
      await link.close();
      return null;
    }
  }

  static List<int>? _bytes(Object? v) {
    if (v is! String) return null;
    try {
      return base64Decode(v);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _verify(
    KnownDevice peer,
    List<int> message,
    Object? signature,
  ) async {
    final sig = _bytes(signature);
    if (sig == null) return false;
    try {
      return await Ed25519().verify(
        message,
        signature: Signature(
          sig,
          publicKey: SimplePublicKey(
            base64Decode(peer.publicKey),
            type: KeyPairType.ed25519,
          ),
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// The starter's key to the answerer, then the answerer's to the
  /// starter.
  static Future<(SecretKey, SecretKey)> _keys(
    SimpleKeyPair mine,
    List<int> theirs,
    List<int> starter,
    List<int> answerer,
  ) async {
    final shared = await X25519().sharedSecretKey(
      keyPair: mine,
      remotePublicKey: SimplePublicKey(theirs, type: KeyPairType.x25519),
    );
    final both = await Hkdf(hmac: Hmac.sha256(), outputLength: 64).deriveKey(
      secretKey: shared,
      nonce: [...starter, ...answerer],
      info: utf8.encode(_context),
    );
    final bytes = await both.extractBytes();
    return (SecretKey(bytes.sublist(0, 32)), SecretKey(bytes.sublist(32)));
  }

  static List<int> _nonce(int n) => [
    0,
    0,
    0,
    0,
    for (var i = 7; i >= 0; i--) (n >> (8 * i)) & 0xff,
  ];

  void _start() {
    _listen = _link.messages.listen(
      (m) => unawaited(_open(m)),
      onDone: () => unawaited(close()),
    );
  }

  // Opened one at a time, in the order they came.
  Future<void> _opening = Future.value();

  Future<void> _open(Map<String, Object?> m) =>
      _opening = _opening.then((_) async {
        if (m['t'] != 'e' || m['n'] != _received) return close();
        final sealed = _bytes(m['c']);
        if (sealed == null || sealed.length < 16) return close();
        try {
          final clear = await _aead.decrypt(
            SecretBox(
              sealed.sublist(0, sealed.length - 16),
              nonce: _nonce(_received),
              mac: Mac(sealed.sublist(sealed.length - 16)),
            ),
            secretKey: _receive,
          );
          _received++;
          final message = jsonDecode(utf8.decode(clear));
          if (message is Map<String, Object?> && !_messages.isClosed) {
            _messages.add(message);
          }
        } catch (_) {
          await close();
        }
      });

  // Sealed one at a time: the counter is the order.
  Future<void> _sending = Future.value();

  Future<void> send(Map<String, Object?> message) =>
      _sending = _sending.then((_) async {
        if (_link.closed) return;
        final n = _sent++;
        final box = await _aead.encrypt(
          utf8.encode(jsonEncode(message)),
          secretKey: _send,
          nonce: _nonce(n),
        );
        _link.send({
          't': 'e',
          'n': n,
          'c': base64Encode([...box.cipherText, ...box.mac.bytes]),
        });
      });

  Future<void> close() async {
    await _listen?.cancel();
    await _link.close();
    if (!_messages.isClosed) await _messages.close();
  }
}

class OfficeChannelException implements Exception {
  const OfficeChannelException(this.message);
  final String message;
  @override
  String toString() => message;
}

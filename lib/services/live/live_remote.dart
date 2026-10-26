import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../office/office_channel.dart';
import '../office/office_known.dart';
import '../office/office_link.dart';
import '../office/office_peer.dart';
import 'live_share.dart';

/// A live document shared with another office, over the relay (approved
/// mockup, 26 Ekim 2026): no pairing and no account, one invitation by a
/// code for one person. The code is said to the other office by WhatsApp,
/// mail or telephone, never to the relay.
///
/// Both sides stretch the code (PBKDF2) and name their room on the relay
/// by a hash of that; the relay cannot work the code out of it. Each side
/// then makes a key for this talk alone (X25519), and the two keys with
/// the stretched code give one key each way, as a known device's channel
/// has (ChaCha20-Poly1305 under a counter, see [OfficeChannel]). Each
/// proves it holds the code before anything is said, and both screens
/// show the same four digits, that whoever wants to be sure may compare.
/// The sharer is asked before the one who came sees anything.
abstract final class LiveRelay {
  /// The relay (tool/canli_relay); tests point it at their own.
  static Uri server = Uri.parse('wss://canli.lifeos.com.tr');

  /// The page an invitation's link opens, the code after its `#`.
  static Uri page = Uri.parse('https://canli.lifeos.com.tr/');

  /// The HTTP client the relay is reached with; a test's own, to reach it
  /// by another way.
  @visibleForTesting
  static HttpClient? client;

  /// How long an invitation may wait for the one it is for (the relay
  /// keeps a room no longer).
  static const within = Duration(minutes: 15);

  static const _context = 'folio-canli-uzak-1';

  /// PBKDF2's rounds: a guess at the code from the room's name costs this
  /// many, and there are 2^45 codes.
  static int rounds = 20000;
}

/// An invitation's code: nine of Crockford's 32 letters and digits (no I,
/// L, O, U: none read for another), shown in threes.
abstract final class RemoteCode {
  static const _letters = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const length = 9;

  static String make([Random? random]) {
    final r = random ?? Random.secure();
    return [
      for (var i = 0; i < length; i++) _letters[r.nextInt(_letters.length)],
    ].join();
  }

  /// [input] as typed or pasted, a link with it too; null when it is no
  /// code. O is read as 0, I and L as 1, as Crockford reads them.
  static String? read(String input) {
    var s = input.trim();
    final hash = s.lastIndexOf('#');
    if (hash >= 0) s = s.substring(hash + 1);
    s = s
        .toUpperCase()
        .replaceAll(RegExp(r'[^0-9A-Z]'), '')
        .replaceAll('O', '0')
        .replaceAll(RegExp('[IL]'), '1');
    if (s.length != length) return null;
    for (final c in s.split('')) {
      if (!_letters.contains(c)) return null;
    }
    return s;
  }

  /// K7Q-4MP-2XD.
  static String shown(String code) =>
      '${code.substring(0, 3)}-${code.substring(3, 6)}-${code.substring(6)}';

  /// The room [code] names on the relay: all the relay ever sees of it.
  @visibleForTesting
  static Future<String> roomOf(String code) async =>
      (await _Secret.of(code)).room;

  static Uri link(String code) => LiveRelay.page.replace(fragment: code);

  /// What goes to the other office: the link, and the code to type.
  static String message(String code, String title) =>
      'LifeOS Folio’da “$title” belgesini sizinle canlı paylaşıyorum. '
      'Folio’da Davet koduyla katıl’ı seçip şu kodu yazın: ${shown(code)}\n'
      '${link(code)}\n'
      'Kod 15 dakika geçerlidir.';
}

/// The code stretched, and the room on the relay it names.
class _Secret {
  _Secret(this.stretched, this.room);
  final List<int> stretched;
  final String room;

  static Future<_Secret> of(String code) async {
    final key = await Pbkdf2.hmacSha256(iterations: LiveRelay.rounds, bits: 256)
        .deriveKeyFromPassword(
          password: code,
          nonce: utf8.encode(LiveRelay._context),
        );
    final stretched = await key.extractBytes();
    final hash = await Sha256().hash([
      ...utf8.encode('folio-canli-oda'),
      ...stretched,
    ]);
    final room = base64Url.encode(hash.bytes).replaceAll('=', '');
    return _Secret(stretched, room);
  }
}

/// The keys of one talk: the joiner's to the sharer, the sharer's to the
/// joiner, the one each proves the code with, and the digits both show.
class _Keys {
  _Keys(this.toSharer, this.toJoiner, this.proof, this.digits);
  final SecretKey toSharer, toJoiner, proof;
  final String digits;

  static Future<_Keys> make(
    SimpleKeyPair mine,
    List<int> theirs,
    _Secret secret, {
    required List<int> joiner,
    required List<int> sharer,
  }) async {
    final shared = await X25519().sharedSecretKey(
      keyPair: mine,
      remotePublicKey: SimplePublicKey(theirs, type: KeyPairType.x25519),
    );
    final all = await Hkdf(hmac: Hmac.sha256(), outputLength: 98).deriveKey(
      secretKey: shared,
      nonce: secret.stretched,
      info: [...utf8.encode(LiveRelay._context), ...joiner, ...sharer],
    );
    final b = await all.extractBytes();
    final n = ((b[96] << 8) | b[97]) % 10000;
    final digits = n.toString().padLeft(4, '0');
    return _Keys(
      SecretKey(b.sublist(0, 32)),
      SecretKey(b.sublist(32, 64)),
      SecretKey(b.sublist(64, 96)),
      '${digits.substring(0, 2)} ${digits.substring(2)}',
    );
  }

  Future<String> prove(String side) async => base64Encode(
    (await Hmac.sha256().calculateMac(
      utf8.encode(side),
      secretKey: proof,
    )).bytes,
  );

  Future<bool> proves(String side, Object? said) async {
    if (said is! String) return false;
    final want = utf8.encode(await prove(side));
    final got = utf8.encode(said);
    if (want.length != got.length) return false;
    var diff = 0;
    for (var i = 0; i < want.length; i++) {
      diff |= want[i] ^ got[i];
    }
    return diff == 0;
  }
}

/// The relay's socket as a talk's wire: JSON objects, the first few taken
/// one by one while the two make their keys, the rest handed whole to the
/// sealed channel. Nothing said meanwhile is lost.
class _RelayWire implements OfficeWire {
  _RelayWire(this._ws) {
    _ws.listen(
      (data) {
        if (data is! String || data.length > _max) return unawaited(close());
        Object? m;
        try {
          m = jsonDecode(data);
        } catch (_) {}
        if (m is! Map<String, Object?>) return unawaited(close());
        final rest = _rest;
        final waiter = _waiter;
        if (rest != null) {
          rest.add(m);
        } else if (waiter != null) {
          _waiter = null;
          waiter.complete(m);
        } else {
          _held.add(m);
        }
      },
      onDone: () => unawaited(close()),
      onError: (Object _) => unawaited(close()),
      cancelOnError: true,
    );
  }

  static Future<_RelayWire> connect(String room, String role) async {
    final base = LiveRelay.server;
    final uri = base.replace(
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}/v1/oda/$room',
      queryParameters: {'rol': role},
    );
    final ws = await WebSocket.connect(
      uri.toString(),
      customClient: LiveRelay.client,
    ).timeout(const Duration(seconds: 12));
    ws.pingInterval = const Duration(seconds: 20);
    return _RelayWire(ws);
  }

  static const _max = 2 * 1024 * 1024;
  final WebSocket _ws;
  final _held = <Map<String, Object?>>[];
  Completer<Map<String, Object?>?>? _waiter;
  StreamController<Map<String, Object?>>? _rest;
  bool _closed = false;

  /// Why the relay closed it, once it has.
  int? get closeCode => _ws.closeCode;

  /// The next thing said; null once it is closed.
  Future<Map<String, Object?>?> next(Duration within) {
    if (_held.isNotEmpty) return Future.value(_held.removeAt(0));
    if (_closed) return Future.value(null);
    final waiter = _waiter = Completer<Map<String, Object?>?>();
    return waiter.future.timeout(
      within,
      onTimeout: () {
        if (identical(_waiter, waiter)) _waiter = null;
        return null;
      },
    );
  }

  @override
  Stream<Map<String, Object?>> get messages {
    final rest = _rest ??= StreamController<Map<String, Object?>>();
    for (final m in _held) {
      rest.add(m);
    }
    _held.clear();
    if (_closed) unawaited(rest.close());
    return rest.stream;
  }

  @override
  bool get closed => _closed;

  @override
  void send(Map<String, Object?> message) {
    if (_closed) return;
    try {
      _ws.add(jsonEncode(message));
    } catch (_) {
      unawaited(close());
    }
  }

  @override
  Future<void> drain() async {}

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final waiter = _waiter;
    _waiter = null;
    waiter?.complete(null);
    try {
      await _ws.close().timeout(const Duration(seconds: 3));
    } catch (_) {}
    final rest = _rest;
    if (rest != null && !rest.isClosed) await rest.close();
  }
}

/// The other side, as a sealed channel knows it: no device key, the code
/// vouched for it.
KnownDevice _remotePeer(String room, String name) => KnownDevice(
  deviceId: 'uzak-${room.substring(0, 12)}',
  userId: '',
  publicKey: '',
  name: name,
  device: '',
  platform: OfficePlatform.other,
  knownAt: DateTime.now(),
);

/// Where an invitation is.
enum RemoteInviteState {
  /// The relay being reached.
  opening,

  /// The code made, no one come yet.
  waiting,

  /// Someone came with the code: asked about, the digits shown.
  arrived,

  /// Shown the document.
  accepted,

  /// Turned away, or the invitation withdrawn.
  declined,

  /// No one came in time.
  expired,

  /// The relay not reached, or one came who could not prove the code.
  failed,
}

/// One invitation of the sharer's: its code, and who comes with it.
class RemoteInvite extends ChangeNotifier {
  RemoteInvite._(this.code);

  final String code;
  RemoteInviteState state = RemoteInviteState.opening;

  /// When it may be used until.
  DateTime expires = DateTime.now().add(LiveRelay.within);

  /// Who came, as they said, and the digits both screens show.
  String name = '', office = '', digits = '';

  /// Why it failed, in the lawyer's words.
  String? error;

  _RelayWire? _wire;
  OfficeChannel? _channel;

  /// The one who came's device id on the sharer's list.
  String? deviceId;

  bool get open =>
      state == RemoteInviteState.opening ||
      state == RemoteInviteState.waiting ||
      state == RemoteInviteState.arrived;

  /// A new invitation, waited on until someone comes with its code.
  static RemoteInvite make({String? code}) {
    final invite = RemoteInvite._(code ?? RemoteCode.make());
    unawaited(invite._run());
    return invite;
  }

  void _set(RemoteInviteState s, {String? error}) {
    if (!open && s != RemoteInviteState.accepted) return;
    state = s;
    this.error = error;
    notifyListeners();
  }

  Future<void> _run() async {
    try {
      final secret = await _Secret.of(code);
      if (!open) return;
      final wire = _wire = await _RelayWire.connect(secret.room, 'paylasan');
      if (!open) return unawaited(wire.close());
      expires = DateTime.now().add(LiveRelay.within);
      _set(RemoteInviteState.waiting);
      // The relay's word that someone came, then theirs.
      final came = await wire.next(
        LiveRelay.within + const Duration(minutes: 1),
      );
      if (!open) return;
      if (came == null || came['t'] != 'katilan') {
        await wire.close();
        return _set(
          wire.closeCode == 4408 || came == null
              ? RemoteInviteState.expired
              : RemoteInviteState.failed,
          error: 'Davetin süresi doldu.',
        );
      }
      final hello = await wire.next(const Duration(seconds: 20));
      final theirs = _key(hello?['eph']);
      if (hello?['t'] != 'merhaba' || theirs == null) {
        return _fail('Gelen cihazla bağlantı kurulamadı.');
      }
      final mine = await X25519().newKeyPair();
      final minePublic = (await mine.extractPublicKey()).bytes;
      final keys = await _Keys.make(
        mine,
        theirs,
        secret,
        joiner: theirs,
        sharer: minePublic,
      );
      wire.send({
        't': 'merhaba',
        'v': 1,
        'eph': base64Encode(minePublic),
        'onay': await keys.prove('paylasan'),
      });
      final proof = await wire.next(const Duration(seconds: 20));
      if (proof?['t'] != 'onay' ||
          !await keys.proves('katilan', proof?['mac'])) {
        // Whoever it was did not hold the code: the invitation is spent.
        return _fail('Gelen cihaz kodu doğrulayamadı. Yeni bir kod oluşturun.');
      }
      final peer = _remotePeer(secret.room, '');
      deviceId = peer.deviceId;
      final channel = _channel = OfficeChannel.sealed(
        wire: wire,
        peer: peer,
        send: keys.toJoiner,
        receive: keys.toSharer,
      );
      digits = keys.digits;
      final said = await channel.messages.first.timeout(
        const Duration(seconds: 30),
      );
      if (said['tip'] != 'tanit') {
        return _fail('Gelen cihaz kendini tanıtmadı.');
      }
      name = _clean(said['ad'], 80);
      office = _clean(said['buro'], 80);
      if (!open) return;
      _set(RemoteInviteState.arrived);
      // Gone while asked about: the invitation with it.
      unawaited(
        channel.done.then((_) {
          if (state == RemoteInviteState.arrived) {
            _set(RemoteInviteState.failed, error: 'Gelen kişi ayrıldı.');
          }
        }),
      );
    } on TimeoutException {
      _fail('Gelen cihaz yanıt vermedi.');
    } on StateError {
      _fail('Gelen cihaz ayrıldı.');
    } catch (_) {
      _fail(
        state == RemoteInviteState.opening
            ? 'Canlı paylaşım sunucusuna ulaşılamadı. İnternet bağlantınızı '
                  'denetleyin.'
            : 'Bağlantı koptu.',
      );
    }
  }

  void _fail(String message) {
    unawaited(_channel?.close() ?? _wire?.close() ?? Future.value());
    _set(RemoteInviteState.failed, error: message);
  }

  static String _clean(Object? v, int max) {
    final s = '${v ?? ''}'
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return s.length > max ? s.substring(0, max) : s;
  }

  static List<int>? _key(Object? v) {
    if (v is! String) return null;
    try {
      final b = base64Decode(v);
      return b.length == 32 ? b : null;
    } catch (_) {
      return null;
    }
  }

  /// Who came is shown the document: their sealed channel, to be handed
  /// to the sharing. Null when they are gone meanwhile.
  OfficeChannel? accept() {
    final channel = _channel;
    if (state != RemoteInviteState.arrived ||
        channel == null ||
        channel.closed) {
      return null;
    }
    _set(RemoteInviteState.accepted);
    return channel;
  }

  /// Who came is turned away, told so; or the invitation withdrawn.
  Future<void> decline() async {
    if (!open) return;
    final channel = _channel;
    _set(RemoteInviteState.declined);
    if (channel != null && !channel.closed) {
      try {
        await channel
            .send({'tip': 'reddedildi'})
            .timeout(const Duration(seconds: 2));
        await channel.drain();
      } catch (_) {}
      await channel.close();
    } else {
      await _wire?.close();
    }
  }
}

/// Where joining is.
enum RemoteJoinState {
  connecting,

  /// The code proven both ways: the sharer asked, the digits shown.
  asking,

  /// Shown the document.
  joined,

  /// The sharer said no.
  declined,
  failed,
}

/// Joining a document shared from another office, by the code its sharer
/// sent.
class RemoteJoin extends ChangeNotifier {
  RemoteJoin._(this.code, this.name, this.office);

  final String code, name, office;
  RemoteJoinState state = RemoteJoinState.connecting;
  String digits = '';
  String? error;

  /// The document, once shown.
  LiveSession? session;
  _RelayWire? _wire;
  OfficeChannel? _channel;
  bool _cancelled = false;

  /// [code] (as [RemoteCode.read] reads it) joined as [name] of [office].
  static RemoteJoin start(String code, {String name = '', String office = ''}) {
    final join = RemoteJoin._(code, name, office);
    unawaited(join._run());
    return join;
  }

  void _set(RemoteJoinState s, {String? error}) {
    if (_cancelled) return;
    state = s;
    this.error = error;
    notifyListeners();
  }

  Future<void> _run() async {
    try {
      final secret = await _Secret.of(code);
      if (_cancelled) return;
      final wire = _wire = await _RelayWire.connect(secret.room, 'katilan');
      if (_cancelled) return unawaited(wire.close());
      final mine = await X25519().newKeyPair();
      final minePublic = (await mine.extractPublicKey()).bytes;
      wire.send({'t': 'merhaba', 'v': 1, 'eph': base64Encode(minePublic)});
      final hello = await wire.next(const Duration(seconds: 20));
      if (hello == null) {
        return _fail(switch (wire.closeCode) {
          4404 =>
            'Bu kod bulunamadı ya da süresi doldu. Paylaşandan yeni '
                'bir kod isteyin.',
          4410 => 'Bu davet kullanılmış. Paylaşandan yeni bir kod isteyin.',
          _ => 'Paylaşana ulaşılamadı.',
        });
      }
      final theirs = RemoteInvite._key(hello['eph']);
      if (hello['t'] != 'merhaba' || theirs == null) {
        return _fail('Paylaşana ulaşılamadı.');
      }
      final keys = await _Keys.make(
        mine,
        theirs,
        secret,
        joiner: minePublic,
        sharer: theirs,
      );
      if (!await keys.proves('paylasan', hello['onay'])) {
        return _fail('Kod doğrulanamadı.');
      }
      wire.send({'t': 'onay', 'mac': await keys.prove('katilan')});
      final channel = _channel = OfficeChannel.sealed(
        wire: wire,
        peer: _remotePeer(secret.room, ''),
        send: keys.toSharer,
        receive: keys.toJoiner,
      );
      // Listened to before anything is said: the answer is not missed.
      final answer = channel.messages.first.timeout(
        LiveSession.answerWithin + const Duration(minutes: 3),
      );
      await channel.send({'tip': 'tanit', 'ad': name, 'buro': office});
      digits = keys.digits;
      _set(RemoteJoinState.asking);
      final said = await answer;
      if (_cancelled) return;
      switch (said['tip']) {
        case 'davet':
          session = LiveShare.instance.joinRemote(channel, said);
          _set(RemoteJoinState.joined);
        case 'reddedildi':
          await channel.close();
          _set(RemoteJoinState.declined);
        default:
          _fail('Paylaşana ulaşılamadı.');
      }
    } on TimeoutException {
      _fail('Paylaşan yanıt vermedi.');
    } on StateError {
      _fail('Paylaşan bağlantıyı kapattı.');
    } catch (_) {
      _fail(
        state == RemoteJoinState.connecting
            ? 'Canlı paylaşım sunucusuna ulaşılamadı. İnternet bağlantınızı '
                  'denetleyin.'
            : 'Bağlantı koptu.',
      );
    }
  }

  void _fail(String message) {
    unawaited(_channel?.close() ?? _wire?.close() ?? Future.value());
    _set(RemoteJoinState.failed, error: message);
  }

  /// Given up before the document came.
  Future<void> cancel() async {
    if (state == RemoteJoinState.joined) return;
    _cancelled = true;
    await (_channel?.close() ?? _wire?.close() ?? Future.value());
  }
}

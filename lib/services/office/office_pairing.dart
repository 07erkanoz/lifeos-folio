import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter/foundation.dart';

import 'office_identity.dart';
import 'office_known.dart';
import 'office_link.dart';
import 'office_peer.dart';
import '../uyap/uyap_web_service.dart';

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
    this.invite,
    this.guest,
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

  /// The QR this pairing came by: read by the starter, shown by the other.
  final QrInvite? invite;

  /// A guest's: one who is shown a document live once, not a device known
  /// (lib/services/live/live_share.dart). Never the person's own; its
  /// code made apart from a device's, so that one cannot pass for the
  /// other. The guest's name and office, as the guest gave them; empty
  /// on the side that is joined.
  final ({String name, String office})? guest;
  bool get isGuest => guest != null;

  /// What a guest said of itself, on the side it joined.
  String guestName = '', guestOffice = '';

  /// Known by a QR read off this person's own screen: no code to compare,
  /// and the other device is theirs.
  bool get byQr => _byQr;
  bool _byQr = false;

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

  /// "Bu cihaz da benim": the other device is the user's own. Set at first
  /// when both say the same name; the user changes it before confirming.
  bool get mine => _mineValue;
  set mine(bool value) {
    if (isGuest) return;
    _mineValue = value;
    _mineChosen = true;
  }

  bool _mineValue = false, _mineChosen = false;
  bool _theirsMine = false;

  /// How many other devices share this one's person's key, and the other's:
  /// the key already shared more is the one kept.
  int ownCount = 0;
  int theirOwnCount = 0;

  /// Whether this device, and the other, is a member of an office: a
  /// member's person key is the one kept, the office knowing them by it.
  bool member = false;
  bool theirMember = false;

  /// Both users said the other device is their own.
  bool get bothMine => mine && _theirsMine;
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
    // Where it listens, for the other to come back to when it has only
    // met this device here, by a QR, and not on the network.
    'pt': _self.port,
    if (guest case final g?) ...{
      'misafir': true,
      if (g.name.isNotEmpty) 'mad': g.name,
      if (g.office.isNotEmpty) 'mburo': g.office,
    },
  };

  /// Starts knowing [peer], reached at its address.
  static OfficePairing start({
    required OfficeIdentity identity,
    required OfficePeer self,
    required OfficePeer peer,
    required Future<void> Function(KnownDevice device) onKnown,
    QrInvite? invite,
    ({String name, String office})? guest,
  }) {
    final pairing = OfficePairing._(
      null,
      identity,
      self,
      incoming: false,
      onKnown: onKnown,
      invite: invite,
      guest: guest,
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
      final commit = hash.sha256.convert([..._myKey, ..._mineNonce]).bytes;
      link.send({
        't': 'pair',
        ..._about,
        'commit': base64Encode(commit),
        if (invite case final qr?) 'davet': qr.proof(_myKey, commit),
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
    QrInvite? invite,
  }) {
    final pairing = OfficePairing._(
      link,
      identity,
      self,
      incoming: true,
      onKnown: onKnown,
      invite: invite,
      guest: first['misafir'] == true ? (name: '', office: '') : null,
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
    if (isGuest) {
      if (first['davet'] != null) {
        _fail('Karşı cihaz anlaşılamadı.');
        return;
      }
      String said(String k, int most) {
        final v = '${first[k] ?? ''}'.trim();
        return v.length > most ? v.substring(0, most) : v;
      }

      guestName = said('mad', 80);
      guestOffice = said('mburo', 80);
    }
    final proof = first['davet'];
    if (proof != null) {
      // Only who read this screen's QR knows its secret.
      final qr = invite;
      if (qr == null ||
          !qr.valid ||
          proof != qr.proof(base64Decode(_otherKey!), commit)) {
        _fail('QR geçersiz ya da süresi dolmuş.');
        return;
      }
      _byQr = true;
      mine = true;
    }
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
      host: _other?.host ?? _link?.remoteHost,
      port: _other?.port ?? (about['pt'] is int ? about['pt'] as int : 0),
    );
    if (peer == null) return false;
    _other = peer;
    _otherKey = base64Encode(key);
    // The same name ticks it at first; what the user chose stays.
    if (!_mineChosen && !isGuest) {
      _mineValue =
          peer.name.trim().isNotEmpty &&
          UyapWebService.fold(peer.name) == UyapWebService.fold(_self.name);
    }
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
        if (invite case final qr? when qr.deviceId != _other?.deviceId) {
          // Not the device whose QR was read: someone between.
          _fail('QR’daki cihaz bu değil; tanıma durduruldu.');
          return;
        }
        if ((m['misafir'] == true) != isGuest) {
          // One side a guest's and the other not: not to be mixed.
          _fail('Karşı cihaz anlaşılamadı.');
          return;
        }
        if (invite != null) {
          _byQr = true;
          mine = true;
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
        _theirsMine = m['benim'] == true && !isGuest;
        theirOwnCount = m['kendi'] is int ? m['kendi'] as int : 0;
        theirMember = m['uye'] == true;
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
    _code = codeOf(
      starter,
      answerer,
      starterNonce,
      answererNonce,
      guest: isGuest,
    );
    _set(PairingState.code);
    // The QR did what comparing the code would.
    if (_byQr) confirm();
  }

  /// The six digits both screens show.
  @visibleForTesting
  static String codeOf(
    List<int> starterKey,
    List<int> answererKey,
    List<int> starterNonce,
    List<int> answererNonce, {
    bool guest = false,
  }) {
    final d = hash.sha256.convert([
      ...utf8.encode(guest ? 'folio-canli-misafir-1' : 'folio-buro-tanima-1'),
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
    _link?.send({
      't': 'confirm',
      'benim': mine && !isGuest,
      'kendi': ownCount,
      'uye': member,
    });
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
    if (!_mine || !_theirs || finished || _completing) return;
    // Both words may come at once: the device is taken in once.
    _completing = true;
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
        code: _code ?? '',
      ),
    );
    _end(PairingState.done, null);
  }

  bool _completing = false;

  void _ended() {
    if (!finished && !_completing) _fail('Bağlantı kesildi.');
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

/// What a desktop's "Telefonumu ekle" shows as a QR: where it is, which
/// device it is and a secret for five minutes. The phone that reads it
/// proves it saw it; the desktop proves it is the device named in it.
class QrInvite {
  QrInvite({
    required this.hosts,
    required this.port,
    required this.deviceId,
    required this.secret,
    DateTime? until,
  }) : until = until ?? DateTime.now().add(life);

  static const life = Duration(minutes: 5);

  final List<String> hosts;
  final int port;
  final String deviceId;
  final List<int> secret;
  final DateTime until;

  bool get valid => DateTime.now().isBefore(until);

  static QrInvite create({
    required List<String> hosts,
    required int port,
    required String deviceId,
  }) => QrInvite(
    hosts: hosts,
    port: port,
    deviceId: deviceId,
    secret: OfficePairing._random(32),
  );

  /// The secret bound to the reader's key and commitment.
  String proof(List<int> readerKey, List<int> commit) => base64Encode(
    hash.Hmac(
      hash.sha256,
      secret,
    ).convert([...utf8.encode('folio-qr-1'), ...readerKey, ...commit]).bytes,
  );

  String get text => jsonEncode({
    'folio': 1,
    'h': hosts,
    'p': port,
    'd': deviceId,
    's': base64Encode(secret),
  });

  /// A QR's text, if it is one of these.
  static QrInvite? parse(String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map || j['folio'] != 1) return null;
      final hosts = j['h'], port = j['p'], id = j['d'];
      final secret = base64Decode('${j['s']}');
      if (hosts is! List || port is! int || id is! String) return null;
      if (secret.length != 32 || hosts.isEmpty) return null;
      return QrInvite(
        hosts: [for (final h in hosts) '$h'],
        port: port,
        deviceId: id,
        secret: secret,
      );
    } catch (_) {
      return null;
    }
  }
}

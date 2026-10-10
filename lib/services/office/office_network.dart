import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../editor/lawyer_profile.dart';
import '../platform/app_directories.dart';
import 'office_channel.dart';
import 'office_chat.dart';
import 'office_identity.dart';
import 'office_known.dart';
import 'office_ledger.dart';
import 'office_link.dart';
import 'office_pairing.dart';
import 'office_peer.dart';
import 'office_task.dart';
import 'task_package.dart';
import 'office_transfer.dart';

/// The office's network (docs/buro.md): this Folio announced on the local
/// network, and the other Folios found there, under their people.
///
/// Nothing is announced until the user joins: an announcement carries the
/// lawyer's name, and a café's network is not an office's. Once joined,
/// Folio joins again at each start until the user leaves.
class OfficeNetwork extends ChangeNotifier {
  OfficeNetwork({
    Future<File> Function()? settings,
    KnownDevices? known,
    OfficeLedger? ledger,
    OfficeTasks? tasks,
    OfficeChats? chats,
    TaskPackages? packages,
    this.platformName,
  }) : _settingsFile = settings ?? _defaultSettings,
       _known = known ?? KnownDevices(),
       ledger = ledger ?? OfficeLedger(),
       tasks = tasks ?? OfficeTasks(),
       chats = chats ?? OfficeChats(),
       packages = packages ?? TaskPackages();

  /// Task cases on their way, and those that came (docs/buro.md, Görev).
  final TaskPackages packages;

  /// The talks this device is in (docs/buro.md, Mesajlaşma).
  final OfficeChats chats;

  /// The tasks this device gives or was given.
  final OfficeTasks tasks;

  /// The office this device belongs to, if it does (docs/buro.md, Büro
  /// yönetimi).
  final OfficeLedger ledger;

  static OfficeNetwork? _instance;
  static OfficeNetwork get instance => _instance ??= OfficeNetwork();

  /// For tests: the platform the device says it is.
  final String? platformName;
  final Future<File> Function() _settingsFile;

  static Future<File> _defaultSettings() async =>
      File(p.join((await folioSupportDirectory()).path, 'buro.json'));

  OfficeIdentity? _identity;
  OfficePeer? _self;
  ServerSocket? _server;
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _events;
  final _peers = <String, OfficePeer>{};
  final KnownDevices _known;
  Map<String, KnownDevice> _knownDevices = const {};

  /// Files a known device offers: the user is asked wherever they are.
  final incomingOffer = ValueNotifier<OfficeTransfer?>(null);

  /// This run's transfers, the newest first.
  final transfers = <OfficeTransfer>[];

  /// Offers taken before, going on from where they stopped when made again.
  final _accepted = <String>{};

  /// Where what comes is put; for tests, a folder of their own.
  Future<Directory> Function() inbox = _defaultInbox;

  static Future<Directory> _defaultInbox() async {
    final base = Platform.isAndroid || Platform.isIOS
        ? await getApplicationDocumentsDirectory()
        : await getDownloadsDirectory() ??
              await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'Folio Gelenler'));
    await dir.create(recursive: true);
    return dir;
  }

  /// Whom a document can go to from its page: the office's members, then
  /// this person's own devices that are not members; empty when there is
  /// no one, and the page shows no "Gönder".
  List<SendTarget> get sendTargets {
    if (_self == null) return const [];
    final out = <SendTarget>[
      for (final m in ledger.people)
        if (m.deviceId != me)
          SendTarget(
            deviceId: m.deviceId,
            name: m.name,
            detail: m.role.label,
            member: true,
            online: _peers[m.deviceId]?.online ?? false,
          ),
    ];
    final taken = {
      _self!.deviceId,
      ...ledger.devicesOf(me),
      for (final t in out) t.deviceId,
    };
    final mine = _identity?.userId;
    final own = <String, String>{
      for (final d in _knownDevices.values)
        if (d.userId == mine) d.deviceId: d.device,
      for (final peer in _peers.values)
        if (peer.online && peer.userId == mine) peer.deviceId: peer.device,
    };
    for (final e in own.entries) {
      if (!taken.add(e.key)) continue;
      out.add(
        SendTarget(
          deviceId: e.key,
          name: 'Kendi cihazım',
          detail: e.value,
          member: false,
          online: _peers[e.key]?.online ?? false,
        ),
      );
    }
    return out;
  }

  /// Sends a document from its page: to a member in their private talk,
  /// so it waits for them when they are away; to an own device directly,
  /// which must be on the network. Why not, when it cannot be.
  Future<String?> sendTo(
    SendTarget to,
    List<String> paths, {
    String text = '',
  }) async {
    if (to.member) {
      final chat = await privateChat(to.deviceId);
      if (chat == null) return 'Bu kişiyle konuşma açılamadı.';
      return post(chat, text: text, files: paths);
    }
    final peer = _peers[to.deviceId];
    if (peer == null || !peer.online) {
      return 'Bu cihaz şu an ağda değil. Açık olduğunda yeniden deneyin.';
    }
    final t = await send(peer, paths, note: text);
    return t == null ? 'Cihaza ulaşılamadı.' : null;
  }

  /// Sends [paths] to a known device on the network; null when it is not
  /// both known and on the network now.
  Future<OfficeTransfer?> send(
    OfficePeer to,
    List<String> paths, {
    String note = '',
    String? id,
    Map<String, Object?> meta = const {},
  }) async {
    final identity = _identity;
    final known = await _trustedFor(_peers[to.deviceId] ?? to);
    final seen = _peers[to.deviceId] ?? to;
    final host = seen.host;
    if (identity == null || known == null || host == null || seen.port == 0) {
      return null;
    }
    final t = await OfficeTransfer.send(
      identity: identity,
      peer: known,
      host: host,
      port: seen.port,
      paths: paths,
      note: note,
      id: id,
      meta: meta,
      onEnd: _ended,
    );
    _added(t);
    return t;
  }

  /// Sends a cut-off transfer again: what came of it is not sent twice.
  Future<OfficeTransfer?> retry(OfficeTransfer t) async {
    final to = _peers[t.peer.deviceId];
    if (!t.outgoing || to == null) return null;
    transfers.remove(t);
    // With what it was for: a message's file is still that message's.
    return send(to, t.paths, note: t.note, id: t.id, meta: t.meta);
  }

  void _added(OfficeTransfer t) {
    transfers.insert(0, t);
    t.addListener(notifyListeners);
    notifyListeners();
  }

  /// A folder's files another own device sent came whole (see FolderSync).
  void Function(OfficeTransfer t)? onOwnFiles;

  /// Files that came whole on their own, not with a message, a task or a
  /// folder kept alike: in the inbox, for the user to be told where.
  final arrived = ValueNotifier<OfficeTransfer?>(null);

  void _ended(OfficeTransfer t) {
    unawaited(_log(t));
    if (!t.outgoing &&
        t.state == TransferState.done &&
        t.meta['senkron'] is String) {
      onOwnFiles?.call(t);
    }
    if (t.state == TransferState.done) unawaited(_metOwnDevice(t.talkedTo));
    if (!t.outgoing &&
        t.state == TransferState.done &&
        t.saved.isNotEmpty &&
        !t.meta.containsKey('sohbet') &&
        !t.meta.containsKey('gorev') &&
        !t.meta.containsKey('senkron')) {
      arrived.value = t;
    }
    final taskId = t.meta['gorev'], caseKey = t.meta['dosya'];
    if (taskId is String &&
        caseKey is String &&
        t.state == TransferState.done) {
      if (t.outgoing) {
        packages.pending.remove('$taskId|$caseKey|${t.peer.deviceId}');
        packages.delivered.add('$taskId|$caseKey|${t.peer.deviceId}');
        unawaited(packages.save());
      } else {
        unawaited(
          packages
              .came(taskId, caseKey, t.saved)
              .then((_) => notifyListeners()),
        );
      }
    }
    final message = t.meta['mesaj'];
    if (message is String && t.state == TransferState.done) {
      if (t.outgoing) {
        unawaited(chats.delivered(message, t.peer.deviceId));
      } else {
        for (var i = 0; i < t.saved.length && i < t.files.length; i++) {
          unawaited(chats.fileCame(message, t.files[i].name, t.saved[i]));
        }
      }
    }
    notifyListeners();
  }

  Future<File> _logFile() async =>
      File(p.join((await _settingsFile()).parent.path, 'buro_aktarimlar.json'));

  /// The transfers' record: who sent what to whom, when, and how it ended.
  // One write at a time, and whole: Gelenler reads it as it is written.
  Future<void> _logging = Future.value();

  Future<void> _log(OfficeTransfer t) => _logging = _logging.then((_) async {
    try {
      final file = await _logFile();
      var list = <Object?>[];
      if (await file.exists()) {
        final old = jsonDecode(await file.readAsString());
        if (old is List) list = old;
      }
      list.insert(0, recordOf(t));
      if (list.length > 500) list = list.sublist(0, 500);
      final part = File('${file.path}.part');
      await part.writeAsString(jsonEncode(list), flush: true);
      await part.rename(file.path);
    } catch (_) {}
  });

  /// [t] as the transfers' record keeps it; a file with a message has the
  /// message's words for its note.
  Map<String, Object?> recordOf(OfficeTransfer t) {
    final j = t.toJson();
    final chat = chats.of('${t.meta['sohbet'] ?? ''}');
    if (t.note.isEmpty && chat != null) {
      final m = chat.messages.where((m) => m.id == t.meta['mesaj']).firstOrNull;
      if (m != null && m.text.isNotEmpty) j['not'] = m.text;
    }
    // A task's case: by the task's title.
    final task = tasks.of('${t.meta['gorev'] ?? ''}');
    if (task != null) j['gorevAdi'] = task.title;
    return j;
  }

  /// The transfers' record, the newest first (see [recordOf]).
  Future<List<Map<String, Object?>>> transferLog() async {
    try {
      final file = await _logFile();
      if (!await file.exists()) return const [];
      final list = jsonDecode(await file.readAsString());
      return [
        if (list is List)
          for (final e in list)
            if (e is Map) e.cast<String, Object?>(),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// A device that asked to know this one: shown wherever the user is.
  final incoming = ValueNotifier<OfficePairing?>(null);
  OfficePairing? _pairing;

  bool _joined = false, _starting = false;
  String? _error;

  /// Whether this Folio is announced and looking.
  bool get joined => _joined;
  bool get starting => _starting;

  /// What went wrong the last time it tried to join; null when nothing.
  String? get error => _error;

  /// This device, as the others see it; null before it has joined.
  OfficePeer? get self => _self;

  /// Whether the keys outlive this run (see [OfficeIdentity.kept]).
  bool get kept => _identity?.kept ?? true;

  /// The people on the network with their devices, this user's first; a
  /// known device that is not on it now is there too, as closed.
  List<OfficePerson> get people {
    final self = _self;
    if (self == null) return const [];
    return groupPeople([
      // Another's device that keeps only its own alike says no name: it is
      // on no one's list but its owner's.
      for (final p in _peers.values)
        if (p.name.isNotEmpty ||
            p.userId == _identity?.userId ||
            _knownDevices.containsKey(p.deviceId))
          p,
      for (final d in _knownDevices.values)
        if (!_peers.containsKey(d.deviceId)) d.asAbsent(null),
    ], self: self);
  }

  /// The devices this one knows, the newest first.
  List<KnownDevice> get known =>
      _knownDevices.values.toList()
        ..sort((a, b) => b.knownAt.compareTo(a.knownAt));

  bool isKnown(String deviceId) => _knownDevices.containsKey(deviceId);

  QrInvite? _invite;

  /// The pairing a phone began by reading this screen's QR.
  final qrPairing = ValueNotifier<OfficePairing?>(null);

  /// "Telefonumu ekle": a new QR for this device, the last one void.
  Future<QrInvite?> inviteByQr({@visibleForTesting List<String>? at}) async {
    final self = _self, server = _server;
    if (self == null || server == null) return null;
    final hosts = at ?? await _addresses();
    if (hosts.isEmpty) return null;
    qrPairing.value = null;
    return _invite = QrInvite.create(
      hosts: hosts,
      port: server.port,
      deviceId: self.deviceId,
    );
  }

  static Future<List<String>> _addresses() async {
    try {
      return [
        for (final i in await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        ))
          for (final a in i.addresses)
            if (!a.isLoopback && !a.isLinkLocal) a.address,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// "QR okut": knows the computer whose QR the phone read, at the first of
  /// its addresses that answers; null when none does.
  Future<OfficePairing?> pairByQr(QrInvite invite) async {
    final identity = _identity, self = _self;
    if (identity == null || self == null) return null;
    if (_pairing != null && !_pairing!.finished) return null;
    String? host;
    for (final h in invite.hosts) {
      try {
        final probe = await Socket.connect(
          h,
          invite.port,
          timeout: const Duration(seconds: 3),
        );
        probe.destroy();
        host = h;
        break;
      } catch (_) {}
    }
    if (host == null) return null;
    final pairing = _pairing = OfficePairing.start(
      identity: identity,
      self: self,
      peer: OfficePeer(
        deviceId: invite.deviceId,
        userId: '',
        name: '',
        device: '',
        platform: OfficePlatform.other,
        host: host,
        port: invite.port,
      ),
      onKnown: _knownNow,
      invite: invite,
    );
    _watchPairing(pairing);
    return pairing;
  }

  /// What one person's own devices keep alike (docs/buro.md, Senkron), by
  /// name: the agenda, the sessions. Given only over a channel the
  /// person's key vouched for.
  final ownParts = <String, OwnPart>{};

  /// What the office's members keep alike, by name, each part on only
  /// where its user turned it on (the clients). What goes is made for the
  /// member it goes to; what comes is told who sent it.
  final officeParts = <String, OfficePart>{};

  /// Whether this device's person sees the clients' money: alone, with no
  /// office, always; in one, a manager or one a manager let.
  bool get seesMoney => ledger.officeId == null || ledger.seesMoney(me);

  /// Whether [deviceId]'s person sees it.
  bool seesMoneyOf(String deviceId) => ledger.seesMoney(deviceId);

  /// The office parts made alike with [peer], both ways.
  Future<void> _syncOfficeParts(OfficePeer peer) async {
    if (officeParts.isEmpty || ledger.member(peer.deviceId) == null) return;
    final identity = _identity, host = peer.host;
    final trusted = await _trustedFor(peer);
    if (identity == null || host == null || trusted == null) return;
    for (final e in officeParts.entries.toList()) {
      try {
        final ch = await OfficeChannel.open(
          identity: identity,
          peer: trusted,
          host: host,
          port: peer.port,
        );
        unawaited(_metOwn(ch));
        final reply = ch.messages.first.timeout(const Duration(seconds: 20));
        await ch.send({
          't': 'buro-parca',
          'ad': e.key,
          'veri': await e.value.export(peer.deviceId),
        });
        final m = await reply;
        await ch.close();
        if (m['veri'] != null &&
            await e.value.merge(m['veri'], peer.deviceId)) {
          notifyListeners();
        }
      } catch (_) {}
    }
  }

  /// Channels kept open for a kind ("canli": a document shared live): the
  /// first word names the kind, and the channel is the handler's until
  /// either side closes it. [own] whether the asker proved itself one of
  /// this person's devices, [member] whether it is the office's.
  final streams =
      <
        String,
        Future<void> Function(
          OfficeChannel channel,
          Map<String, Object?> first, {
          required bool own,
          required bool member,
          required bool guest,
        })
      >{};

  /// A channel to [deviceId] kept open for [kind], [body] its first word:
  /// to one of the person's own devices, or with [office] to a member of
  /// the office. Null when it cannot be reached or is not who it must be.
  Future<OfficeChannel?> openStream(
    String deviceId,
    String kind, {
    Map<String, Object?> body = const {},
    bool office = false,
    bool guest = false,
  }) async {
    final identity = _identity, peer = _peers[deviceId];
    final host = peer?.host;
    if (identity == null || peer == null || host == null || !peer.online) {
      return null;
    }
    // A guest only as a guest: the channel it may have and no other.
    final trusted = guest
        ? (isGuestOnly(deviceId) ? _guests[deviceId] : null)
        : office
        ? await _trusted(deviceId)
        : await _trustedFor(peer);
    if (trusted == null) return null;
    if (office && ledger.member(deviceId) == null) return null;
    try {
      final ch = await OfficeChannel.open(
        identity: identity,
        peer: trusted,
        host: host,
        port: peer.port,
      );
      if (!office && !guest && !ch.vouched) {
        await ch.close();
        return null;
      }
      if (guest) _guestChannel(deviceId, ch);
      await ch.send({...body, 't': 'akis', 'tur': kind});
      return ch;
    } catch (_) {
      return null;
    }
  }

  /// What this device answers one of the person's own devices asking, by
  /// kind: its answer, and what to do with the asker's last word, null when
  /// it says none.
  final ownAnswers =
      <
        String,
        Future<
          (
            Map<String, Object?>,
            Future<void> Function(Map<String, Object?>? word)?,
          )
        >
        Function(Map<String, Object?> asked)
      >{};

  /// Another own device takes this one into its office as its person's:
  /// signed only while this one is of no other office.
  Future<(Map<String, Object?>, Future<void> Function(Map<String, Object?>?)?)>
  _consent(Map<String, Object?> asked) async {
    final identity = _identity, office = asked['buro'], person = asked['kisi'];
    if (identity == null ||
        office is! String ||
        person is! String ||
        (ledger.exists && ledger.officeId != office) ||
        ledger.member(identity.deviceId) != null) {
      return (<String, Object?>{'ret': true}, null);
    }
    return (
      <String, Object?>{
        'onay': await identity.signAsDevice(
          OfficeLedger.consentOf(office, person, identity.deviceId),
        ),
        'uc': await identity.userCertificate(),
      },
      null,
    );
  }

  /// Asks one of the person's own devices [kind]; [then] says the last
  /// word from its answer. Null when it is not on the network, not proved
  /// the person's own, or did not answer.
  /// What this device answers an office member asking, by kind: the
  /// answer for the member whose device is given; null for none.
  final officeAnswers =
      <
        String,
        Future<Map<String, Object?>?> Function(
          Map<String, Object?> asked,
          String fromDevice,
        )
      >{};

  /// Asks [deviceId], an office member's, a question of [kind]; its
  /// answer, null when it has none or cannot be reached.
  Future<Map<String, Object?>?> askOffice(
    String deviceId,
    String kind, {
    Map<String, Object?> body = const {},
  }) async {
    final identity = _identity, peer = _peers[deviceId];
    final host = peer?.host;
    if (identity == null || peer == null || host == null) return null;
    if (ledger.member(deviceId) == null) return null;
    final trusted = await _trustedFor(peer);
    if (trusted == null) return null;
    try {
      final ch = await OfficeChannel.open(
        identity: identity,
        peer: trusted,
        host: host,
        port: peer.port,
      );
      final reply = ch.messages.first.timeout(const Duration(seconds: 30));
      await ch.send({...body, 't': 'buro-sor', 'tur': kind});
      final answer = await reply;
      await ch.close();
      return answer['yok'] == true ? null : answer;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Object?>?> askOwn(
    String deviceId,
    String kind, {
    Map<String, Object?> body = const {},
    Future<Map<String, Object?>?> Function(Map<String, Object?> answer)? then,
  }) async {
    final identity = _identity, peer = _peers[deviceId];
    final host = peer?.host;
    if (identity == null || peer == null || host == null || !peer.online) {
      return null;
    }
    final trusted = await _trustedFor(peer);
    if (trusted == null) return null;
    try {
      final ch = await OfficeChannel.open(
        identity: identity,
        peer: trusted,
        host: host,
        port: peer.port,
      );
      if (!ch.vouched) {
        await ch.close();
        return null;
      }
      final reply = ch.messages.first.timeout(const Duration(seconds: 30));
      await ch.send({...body, 't': 'kendi', 'tur': kind});
      final answer = await reply;
      if (answer['yok'] == true) {
        await ch.close();
        return null;
      }
      final word = then == null ? null : await then(answer);
      if (word != null) {
        await ch.send(word);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      await ch.close();
      return answer;
    } catch (_) {
      return null;
    }
  }

  /// When each of the person's own devices was last made alike with this.
  final synced = <String, DateTime>{};

  final _ownLast = <String, DateTime>{};
  Timer? _ownSoon;

  /// This person's other devices this one knows as theirs, the newest
  /// first.
  List<KnownDevice> get ownKnown => [
    for (final d in known)
      if (d.userId == _identity?.userId && d.deviceId != _self?.deviceId) d,
  ];

  bool isOnline(String deviceId) => _peers[deviceId]?.online ?? false;

  /// The person's own devices on the network now, as they say.
  List<OfficePeer> get ownOnline => [
    for (final p in _peers.values)
      if (p.online &&
          p.host != null &&
          p.userId == _identity?.userId &&
          p.deviceId != _self?.deviceId)
        p,
  ];

  /// Something kept alike changed here: told to the person's other devices
  /// within a few seconds, a burst of changes once.
  void ownChanged() {
    _ownSoon?.cancel();
    _ownSoon = Timer(const Duration(seconds: 3), () => unawaited(syncOwn()));
  }

  Timer? _officeSoon;

  /// Something an office part holds changed here: sent to the office's
  /// members on the network a moment later.
  void officeChanged() {
    if (officeParts.isEmpty) return;
    _officeSoon?.cancel();
    _officeSoon = Timer(
      const Duration(seconds: 3),
      () => unawaited(syncOffice()),
    );
  }

  /// The office parts made alike with each member on the network.
  Future<void> syncOffice() async {
    for (final peer in _peers.values.toList()) {
      if (peer.host == null || !isTrusted(peer.deviceId)) continue;
      await _syncOfficeParts(peer);
    }
  }

  /// "Şimdi eşitle": with each of the person's own devices on the network.
  Future<void> syncOwn() async {
    for (final peer in ownOnline) {
      await _syncOwnWith(peer, now: true);
    }
  }

  /// What is kept alike, packed: an agenda's JSON is mostly the same words.
  static String _pack(Map<String, Object?> parts) =>
      base64Encode(gzip.encode(utf8.encode(jsonEncode(parts))));

  static Object? _unpack(Object? packed) {
    if (packed is! String) return null;
    try {
      // Only ever from the person's own devices, by proof (see vouched).
      return jsonDecode(utf8.decode(gzip.decode(base64Decode(packed))));
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Object?>> _ownParts() async => {
    for (final e in ownParts.entries)
      e.key: await e.value.export().catchError((Object _) => null),
  };

  Future<void> _ownCame(Object? theirs) async {
    if (theirs is! Map) return;
    for (final e in ownParts.entries) {
      if (!theirs.containsKey(e.key)) continue;
      try {
        await e.value.merge(theirs[e.key]);
      } catch (_) {}
    }
  }

  Future<void> _syncOwnWith(OfficePeer peer, {bool now = false}) async {
    final identity = _identity, host = peer.host;
    if (identity == null || host == null || ownParts.isEmpty) return;
    // Seen again and again on the network: not every time.
    final last = _ownLast[peer.deviceId];
    if (!now &&
        last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _ownLast[peer.deviceId] = DateTime.now();
    final trusted = await _trustedFor(peer);
    if (trusted == null) return;
    try {
      final ch = await OfficeChannel.open(
        identity: identity,
        peer: trusted,
        host: host,
        port: peer.port,
      );
      unawaited(_metOwn(ch));
      if (!ch.vouched) {
        await ch.close();
        return;
      }
      final reply = ch.messages.first.timeout(const Duration(seconds: 20));
      await ch.send({'t': 'senkron', 'parcalar': _pack(await _ownParts())});
      final m = await reply;
      await ch.close();
      await _ownCame(_unpack(m['parcalar']));
      synced[peer.deviceId] = DateTime.now();
      notifyListeners();
    } catch (_) {}
  }

  /// Starts knowing [peer] by a code; null while another is being known.
  OfficePairing? pair(OfficePeer peer) {
    final identity = _identity, self = _self;
    if (identity == null || self == null) return null;
    if (_pairing != null && !_pairing!.finished) return null;
    final pairing = _pairing = OfficePairing.start(
      identity: identity,
      self: self,
      peer: peer,
      onKnown: _knownNow,
    );
    _watchPairing(pairing);
    return pairing;
  }

  /// Forgets a known device: it must be known by its code again before
  /// anything goes to it or comes from it.
  Future<void> forget(String deviceId) async {
    await _known.forget(deviceId);
    await _loadKnown();
    notifyListeners();
  }

  /// A known device's encrypted talk: an offer of files, for now.
  Future<void> _talk(
    OfficeLink link,
    Map<String, Object?> hello,
    OfficeIdentity identity,
  ) async {
    // The grant a guest is let in under, taken as it is let in.
    KnownDevice? grant;
    final ch = await OfficeChannel.accept(
      link: link,
      hello: hello,
      identity: identity,
      known: (id) async {
        final trusted = await _trusted(id);
        if (trusted != null) return trusted;
        return grant = _guests[id];
      },
    );
    if (ch == null) return;
    final id = ch.peer.deviceId;
    // Let in as a guest, or not, fixed now: by the grant it came under,
    // not by what it later says of itself.
    final viaGuest = grant != null && !ch.vouched;
    if (viaGuest) {
      // Its grant gone while it was let in, or too many channels open:
      // shut, never taken another way.
      if (!identical(_guests[id], grant) ||
          (_guestChannels[id]?.length ?? 0) >= _guestChannelLimit) {
        await ch.close();
        return;
      }
      _guestChannel(id, ch);
    } else {
      unawaited(_metOwn(ch));
    }
    late final StreamSubscription<Map<String, Object?>> first;
    // A guest's first word is waited for a while, not for ever.
    final waited = viaGuest
        ? Timer(const Duration(seconds: 20), () => unawaited(ch.close()))
        : null;
    first = ch.messages.listen((m) async {
      waited?.cancel();
      await first.cancel();
      // A guest may ask for the live document's channel and nothing else,
      // and only while its grant stands.
      if (viaGuest && (m['t'] != 'akis' || !identical(_guests[id], grant))) {
        await ch.close();
        return;
      }
      if (m['t'] == 'kullanici') {
        await _adopt(ch, m['tohum']);
        await ch.close();
        return;
      }
      if (m['t'] == 'sohbet') {
        final theirs = Chat.fromJson(m['sohbet']);
        final from = ch.peer.deviceId;
        if (theirs != null &&
            ledger.member(from) != null &&
            await chats.merge(
              theirs,
              from: ledger.personOf(from),
              mayBroadcast: ledger.isManager,
              added: (msg) => _messageCame(theirs.id, msg),
              authentic: _messageAuthentic,
              me: me,
            )) {
          notifyListeners();
        }
        final mine = theirs == null ? null : chats.of(theirs.id);
        // A talk's words only to who is in it: its id is no secret.
        await ch.send({
          't': 'sohbet',
          'sohbet': mine != null && _mayHear(mine, from) ? mine.toJson() : null,
        });
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await ch.close();
        return;
      }
      if (m['t'] == 'gorev') {
        final theirs = OfficeTask.fromJson(m['gorev']);
        final from = ch.peer.deviceId;
        if (theirs != null &&
            ledger.member(from) != null &&
            await tasks.merge(
              theirs,
              from: ledger.personOf(from),
              added: (e) => _taskMoved(theirs.id, e),
              authentic: _taskAuthentic,
              mayCreate: _mayCreate,
              own: ch.vouched && ledger.personOf(from) == me,
            )) {
          notifyListeners();
        }
        final mine = theirs == null ? null : tasks.of(theirs.id);
        await ch.send({
          't': 'gorev',
          'gorev': mine != null && _maySee(mine, from) ? mine.toJson() : null,
        });
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await ch.close();
        return;
      }
      if (m['t'] == 'buro-sor') {
        final from = ch.peer.deviceId;
        final answer = officeAnswers['${m['tur']}'];
        final said = answer == null || ledger.member(from) == null
            ? null
            : await answer(m, from);
        await ch.send({
          ...?said,
          't': 'buro-sor',
          if (said == null) 'yok': true,
        });
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await ch.close();
        return;
      }
      if (m['t'] == 'buro-parca') {
        // An office part another member sends: taken where it is on here,
        // and this one's sent back, made for them.
        final from = ch.peer.deviceId;
        final part = officeParts['${m['ad']}'];
        Object? mine;
        if (part != null && ledger.member(from) != null) {
          if (m['veri'] != null && await part.merge(m['veri'], from)) {
            notifyListeners();
          }
          mine = await part.export(from);
        }
        await ch.send({'t': 'buro-parca', 'veri': mine});
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await ch.close();
        return;
      }
      if (m['t'] == 'kendi') {
        // A question only one of the person's own devices may ask.
        final answer = m['tur'] == 'buro-katil'
            ? _consent
            : ownAnswers['${m['tur']}'];
        if (!ch.vouched || answer == null) {
          await ch.send({'t': 'kendi', 'yok': true});
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await ch.close();
          return;
        }
        final (said, after) = await answer(m);
        final next = after == null
            ? null
            : ch.messages.first
                  .timeout(const Duration(seconds: 40))
                  .then<Map<String, Object?>?>((w) => w)
                  .catchError((Object _) => null);
        await ch.send({...said, 't': 'kendi'});
        if (after != null) await after(await next);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await ch.close();
        return;
      }
      if (m['t'] == 'akis') {
        final handler = streams['${m['tur']}'];
        final own = ch.vouched;
        final member = !viaGuest && ledger.member(id) != null;
        final guest = viaGuest;
        if (handler == null || (!own && !member && !guest)) {
          await ch.close();
          return;
        }
        await handler(ch, m, own: own, member: member, guest: guest);
        return;
      }
      if (m['t'] == 'senkron') {
        // Only to one of this person's own devices, by its key's proof.
        if (!ch.vouched) {
          await ch.close();
          return;
        }
        await _ownCame(_unpack(m['parcalar']));
        await ch.send({'t': 'senkron', 'parcalar': _pack(await _ownParts())});
        synced[ch.peer.deviceId] = DateTime.now();
        notifyListeners();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await ch.close();
        return;
      }
      if (m['t'] == 'defter') {
        await _ledgerCame(m['kayit']);
        await ch.send({'t': 'defter', 'kayit': ledger.records});
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await ch.close();
        return;
      }
      final meta = m['meta'] is Map ? m['meta'] as Map : const {};
      final forChat = meta['sohbet'] is String;
      // A folder's files from another own device (see FolderSync): only by
      // the person's key's proof, put aside until they are put in place.
      final forSync = meta['senkron'] is String;
      if (forSync && !ch.vouched) {
        await ch.close();
        return;
      }
      final forTask = meta['gorev'] is String && meta['dosya'] is String;
      final folder = await inbox();
      final taskFolder = forTask
          // Each case to a folder of its own.
          ? p.join(
              folder.path,
              'Görevler',
              // Only letters and digits: the sender's words name no
              // folder outside the inbox.
              '${'${meta['gorev']}'.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')}-'
                  '${'${meta['dosya']}'.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')}',
            )
          : null;
      final t = m['t'] == 'offer'
          ? OfficeTransfer.receive(
              channel: ch,
              offer: m,
              folder: forSync
                  ? (await Directory(p.join(folder.path, '.folio-senkron'))
                        .create(recursive: true))
                  : forChat
                  ? (await Directory(p.join(folder.path, 'Mesajlar'))
                        .create(recursive: true))
                  : taskFolder != null
                  ? await Directory(taskFolder).create(recursive: true)
                  : folder,
              onEnd: _ended,
            )
          : null;
      if (t == null) {
        await ch.close();
        return;
      }
      transfers.removeWhere((old) => old.id == t.id && old.finished);
      _added(t);
      final chat = chats.of('${t.meta['sohbet'] ?? ''}');
      final writer = ch.peer.deviceId;
      if (chat != null &&
          _mayHear(chat, writer) &&
          (chat.kind != ChatKind.broadcast || ledger.isManager(writer))) {
        // A member's file with a message: taken unasked.
        await t.accept();
        return;
      }
      final task = tasks.of('${t.meta['gorev'] ?? ''}');
      if (task != null &&
          task.by == ledger.personOf(ch.peer.deviceId) &&
          ledger.member(ch.peer.deviceId) != null) {
        // A case of a task given to this device, from its giver.
        await t.accept();
        return;
      }
      if (ch.vouched || forSync) {
        // From one of this person's own devices, by its key's proof:
        // theirs already.
        await t.accept();
        return;
      }
      if (_accepted.contains(t.id)) {
        await t.accept();
      } else {
        incomingOffer.value = t;
      }
    });
  }

  /// A device this one talks to: one it knows, or a member of its office.
  /// Never a guest: a guest is let in by its grant alone, on a channel it
  /// opens ([_talk]), and asked for by [openStream] with `guest`.
  Future<KnownDevice?> _trusted(String deviceId) async =>
      await _known.of(deviceId) ?? ledger.member(deviceId)?.asKnown;

  /// Who is a guest only (lib/services/live/live_share.dart): known for
  /// one live document, in memory, by a code both screens showed; not
  /// the person's, not the office's, not a device known. What a device
  /// says of itself on the network does not change it.
  bool isGuestOnly(String deviceId) =>
      _guests.containsKey(deviceId) &&
      !_knownDevices.containsKey(deviceId) &&
      ledger.member(deviceId) == null;

  /// Guests, by the grant each pairing made: a grant is the very object,
  /// so that one let go is not mistaken for one made since. Their person
  /// is no one's ([_guestGrant]): never taken for this person's own.
  final _guests = <String, KnownDevice>{};

  /// The channels a guest has, closed when it is forgotten.
  final _guestChannels = <String, Set<OfficeChannel>>{};

  /// How many channels a guest may have open at once.
  static const _guestChannelLimit = 4;

  /// The grant [deviceId] has as a guest now, if any.
  KnownDevice? guestGrant(String deviceId) => _guests[deviceId];

  static KnownDevice _guestGrant(KnownDevice d) => KnownDevice(
    deviceId: d.deviceId,
    userId: '',
    publicKey: d.publicKey,
    name: d.name,
    device: d.device,
    platform: d.platform,
    knownAt: d.knownAt,
    code: d.code,
  );

  void _guestChannel(String deviceId, OfficeChannel ch) {
    _guestChannels.putIfAbsent(deviceId, () => {}).add(ch);
    unawaited(
      ch.done.whenComplete(() {
        final set = _guestChannels[deviceId];
        set?.remove(ch);
        if (set != null && set.isEmpty) _guestChannels.remove(deviceId);
      }),
    );
  }

  /// The guests' hosts this Folio joined: only from them is a document
  /// taken, not from a guest that joined this one.
  final _joinedAsGuest = <String>{};
  bool joinedAsGuest(String deviceId) => _joinedAsGuest.contains(deviceId);

  /// The name [deviceId] gave: its announcement's, else a guest's own.
  String? peerNamed(String deviceId) {
    final n = _peers[deviceId]?.name ?? _guests[deviceId]?.name;
    return n == null || n.isEmpty ? null : n;
  }

  /// Taking guests: announced so, by the lawyer's name.
  bool get guestsOpen => _guestsOpen;
  bool _guestsOpen = false;

  /// On the network for a live document alone, not by the user's choice:
  /// gone from it, nothing remembered, when that ends.
  bool _quiet = false;

  /// Asked to remember being on the network while a join was under way.
  bool _rememberWhenJoined = false;

  /// A guest asking to be shown the document, its code on both screens.
  final guestPairing = ValueNotifier<OfficePairing?>(null);

  /// The document [guestPairing] asks for, by its title.
  String get guestPairingFor => _guestPairingFor;
  String _guestPairingFor = '';

  /// The one sharing to guests now: one document at a time, the last to
  /// ask; a guest accepted is told to it alone.
  Object? get guestOwner => _guestOwner;
  Object? _guestOwner;
  String _guestTitle = '';
  void Function(KnownDevice grant, String name, String office)? _onGuest;

  void _turnAwayAsking() {
    final asking = guestPairing.value;
    guestPairing.value = null;
    asking?.reject();
  }

  /// Takes guests for [owner], the document titled [title]: this Folio on
  /// the network, by name, saying it shares a document; joined for it
  /// alone if it was not. A guest the lawyer accepts is told to
  /// [onGuest], by its grant. Another document taking guests before is
  /// taken them from, its guest asking now turned away.
  Future<void> openToGuests(
    Object owner, {
    required String title,
    required void Function(KnownDevice grant, String name, String office)
    onGuest,
  }) async {
    if (!identical(_guestOwner, owner)) _turnAwayAsking();
    _guestOwner = owner;
    _guestTitle = title;
    _onGuest = onGuest;
    _guestsOpen = true;
    if (!_joined && !_starting) {
      _quiet = true;
      await join(remember: false);
    } else {
      await _serial(_announceAgain);
    }
    notifyListeners();
  }

  /// Takes guests no more, if [owner] is the one taking them.
  Future<void> closeToGuests(Object owner) async {
    if (!identical(_guestOwner, owner)) return;
    _guestOwner = null;
    _onGuest = null;
    _guestsOpen = false;
    _turnAwayAsking();
    await _serial(_announceAgain);
    await _maybeQuiet();
    notifyListeners();
  }

  /// The Folios on the network taking guests now.
  List<OfficePeer> get liveHosts => [
    for (final p in _peers.values)
      if (p.live && p.online && p.host != null && p.deviceId != _self?.deviceId)
        p,
  ];

  /// Looked for as one who would join another's live document: on the
  /// network for it alone if not already.
  Future<void> lookForLive(bool look) async {
    _lookingForLive = look;
    if (look && !_joined && !_starting) {
      _quiet = true;
      await join(remember: false);
    }
    await _maybeQuiet();
  }

  bool _lookingForLive = false;

  /// Asks [host] to be shown its document, as a guest named [name] of
  /// [office]: both screens show a code, both users confirm it.
  OfficePairing? joinAsGuest(
    OfficePeer host, {
    required String name,
    String office = '',
  }) {
    final identity = _identity, self = _self;
    if (identity == null || self == null) return null;
    if (_pairing != null && !_pairing!.finished) return null;
    final pairing = _pairing = OfficePairing.start(
      identity: identity,
      self: self,
      peer: host,
      onKnown: (d) async {
        _guests[d.deviceId] = _guestGrant(d);
        _joinedAsGuest.add(d.deviceId);
      },
      guest: (name: name, office: office),
    );
    _letGo(pairing);
    return pairing;
  }

  /// A guest's pairing let go once it ended: what it holds (the sharing
  /// it was for, and through it the document) is not kept by it.
  void _letGo(OfficePairing pairing) {
    void ended() {
      if (!pairing.finished) return;
      pairing.removeListener(ended);
      if (identical(_pairing, pairing)) _pairing = null;
    }

    pairing.addListener(ended);
    ended();
  }

  /// [deviceId] a guest no more: forgotten, its channels closed, and this
  /// Folio off the network again if it was on it for guests alone. With
  /// [grant], only that grant: not one a later pairing made.
  Future<void> forgetGuest(String deviceId, [KnownDevice? grant]) async {
    final now = _guests[deviceId];
    if (grant != null && !identical(now, grant)) return;
    _guests.remove(deviceId);
    _joinedAsGuest.remove(deviceId);
    final channels = _guestChannels.remove(deviceId)?.toList() ?? const [];
    for (final ch in channels) {
      unawaited(ch.close().catchError((Object _) {}));
    }
    await _maybeQuiet();
  }

  /// Joining, leaving and announcing again, one after another: none
  /// finding the network half made by another.
  Future<void> _serial(Future<void> Function() step) {
    final next = _steps.then((_) => step());
    _steps = next.catchError((Object _) {});
    return next;
  }

  Future<void> _steps = Future<void>.value();

  Future<void> _maybeQuiet() => _serial(() async {
    if (!_quiet ||
        !_joined ||
        _guestsOpen ||
        _lookingForLive ||
        _guests.isNotEmpty) {
      return;
    }
    _quiet = false;
    await _close();
    _joined = false;
    _peers.clear();
    notifyListeners();
  });

  Future<void> _announceAgain() async {
    final identity = _identity, server = _server;
    if (!_joined || identity == null || server == null) return;
    // Where it is reached stays what it was.
    final next = (await _describe(identity, server.port)).keepingPlaceOf(_self);
    if (_broadcast == null) {
      _self = next;
      return;
    }
    await _broadcast?.stop();
    _self = next;
    await _announce(next);
  }

  bool isTrusted(String deviceId) =>
      _knownDevices.containsKey(deviceId) ||
      ledger.member(deviceId) != null ||
      _ownOnNetwork(deviceId);

  /// A device on the network under this person's key: believed only when
  /// its certificate holds, in the channel's handshake.
  bool _ownOnNetwork(String deviceId) {
    final me = _identity?.userId;
    return me != null && _peers[deviceId]?.userId == me;
  }

  /// What a channel to [peer] is opened against: the device as known, or
  /// one of the person's own with its key to be shown and vouched for.
  Future<KnownDevice?> _trustedFor(OfficePeer peer) async {
    final known = await _trusted(peer.deviceId);
    if (known != null || !_ownOnNetwork(peer.deviceId)) return known;
    return KnownDevice(
      deviceId: peer.deviceId,
      userId: peer.userId,
      publicKey: '',
      name: peer.name,
      device: peer.device,
      platform: peer.platform,
      knownAt: DateTime.now(),
    );
  }

  /// Devices that, knowing this one, both said are the same person's:
  /// from them alone is a person's key taken.
  final _ownConsent = <String>{};

  int get _ownCount =>
      _knownDevices.values.where((d) => d.userId == _identity?.userId).length;

  void _watchPairing(OfficePairing pairing) {
    pairing.ownCount = _ownCount;
    pairing.member = ledger.member(_self?.deviceId ?? '') != null;
    void done() {
      if (pairing.state != PairingState.done || !pairing.bothMine) return;
      pairing.removeListener(done);
      final other = pairing.other;
      if (other == null) return;
      _ownConsent.add(other.deviceId);
      unawaited(
        _unify(
          other,
          mine: pairing.ownCount,
          theirs: pairing.theirOwnCount,
          memberHere: pairing.member,
          memberThere: pairing.theirMember,
        ),
      );
    }

    pairing.addListener(done);
  }

  /// Two devices of one person, each with a key of its own: the smaller
  /// key's id is kept, and given to the other over a sealed channel.
  Future<void> _unify(
    OfficePeer other, {
    required int mine,
    required int theirs,
    bool memberHere = false,
    bool memberThere = false,
  }) async {
    final identity = _identity;
    if (identity == null || other.userId == identity.userId) return;
    // An office member's key is kept, the office knowing them by it; else
    // the key shared by more devices; else the smaller id's. Both devices
    // say what they know of it, so both decide alike.
    final keep = memberHere != memberThere
        ? memberHere
        : mine != theirs
        ? mine > theirs
        : identity.userId.compareTo(other.userId) < 0;
    if (!keep) return;
    final seen = _peers[other.deviceId] ?? other;
    final host = seen.host;
    final trusted = await _trusted(other.deviceId);
    if (host == null || seen.port == 0 || trusted == null) return;
    try {
      final ch = await OfficeChannel.open(
        identity: identity,
        peer: trusted,
        host: host,
        port: seen.port,
      );
      // Counted as one of this person's devices before the key is sent,
      // so that a next pairing finds it so.
      await _knownNow(
        KnownDevice(
          deviceId: trusted.deviceId,
          userId: identity.userId,
          publicKey: trusted.publicKey,
          name: trusted.name,
          device: trusted.device,
          platform: trusted.platform,
          knownAt: trusted.knownAt,
          code: trusted.code,
        ),
      );
      await ch.send({
        't': 'kullanici',
        'tohum': base64Encode(await identity.userSeed()),
      });
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await ch.close();
    } catch (_) {}
  }

  /// A person's key from their own device that both said is theirs.
  Future<void> _adopt(OfficeChannel ch, Object? seed) async {
    final identity = _identity, self = _self;
    if (identity == null || self == null || seed is! String) return;
    if (!_ownConsent.remove(ch.peer.deviceId)) return;
    final bytes = base64Decode(seed);
    if (bytes.length != 32) return;
    final next = await identity.adoptUser(bytes);
    _identity = next;
    _self = OfficePeer(
      deviceId: self.deviceId,
      userId: next.userId,
      name: self.name,
      device: self.device,
      platform: self.platform,
      host: self.host,
      port: self.port,
    );
    // The known record of the giver is under the person's key now too.
    final giver = _knownDevices[ch.peer.deviceId];
    if (giver != null) {
      await _knownNow(
        KnownDevice(
          deviceId: giver.deviceId,
          userId: next.userId,
          publicKey: giver.publicKey,
          name: giver.name,
          device: giver.device,
          platform: giver.platform,
          knownAt: giver.knownAt,
          code: giver.code,
        ),
      );
    }
    if (_broadcast != null) {
      await _broadcast?.stop();
      await _announce(_self!);
    }
    notifyListeners();
  }

  /// One of the person's own devices, met over a vouched channel: known
  /// from now on, with no code asked.
  Future<void> _metOwn(OfficeChannel ch) async {
    await _metOwnDevice(ch.peer);
    if (ch.vouched) await _takeInOwn(ch.peer);
  }

  /// One of this person's own devices, by its key's proof, not yet of the
  /// office this device is in: added as theirs, so that their tasks and
  /// talks are on it too (docs/buro.md, Senkron).
  Future<void> _takeInOwn(KnownDevice d) async {
    final identity = _identity;
    if (identity == null || d.publicKey.isEmpty || !ledger.exists) return;
    if (ledger.member(identity.deviceId) == null) return;
    if (ledger.member(d.deviceId) != null) return;
    final office = ledger.officeId!;
    final answer = await askOwn(
      d.deviceId,
      'buro-katil',
      body: {'buro': office, 'kisi': me},
    );
    final consent = answer?['onay'], certificate = answer?['uc'];
    if (consent is! String || certificate is! String) return;
    if (await ledger.addOwnDevice(
          identity,
          d,
          consent: consent,
          certificate: certificate,
        ) ==
        null) {
      notifyListeners();
      unawaited(_shareLedger());
      await _queueForNewDevices();
    }
  }

  Future<void> _metOwnDevice(KnownDevice p) async {
    if (p.userId != _identity?.userId || p.publicKey.isEmpty) return;
    if (_knownDevices.containsKey(p.deviceId)) return;
    await _knownNow(p);
  }

  Future<void> _ledgerCame(Object? records) async {
    if (records is List && await ledger.merge(records)) {
      notifyListeners();
      unawaited(_shareLedger());
      await _queueForNewDevices();
    }
  }

  /// A device added to a person a task here was given to gets its cases
  /// too: queued as for the others, not again where they came.
  Future<void> _queueForNewDevices() async {
    var queued = false;
    for (final MapEntry(key: key, value: paths) in packages.sources.entries) {
      final parts = key.split('|');
      if (parts.length != 2) continue;
      final task = tasks.of(parts[0]);
      if (task == null || task.by != me || !task.open) continue;
      for (final id in _devicesOf(task.assignees.keys)) {
        final each = '$key|$id';
        if (packages.pending.containsKey(each) ||
            packages.delivered.contains(each)) {
          continue;
        }
        packages.pending[each] = paths;
        queued = true;
      }
    }
    if (queued) await packages.save();
  }

  /// The ledger said to a trusted device on the network, and theirs heard.
  Future<void> _syncLedger(OfficePeer peer) async {
    final identity = _identity;
    final host = peer.host;
    if (identity == null || host == null || peer.port == 0) return;
    final trusted = await _trustedFor(peer);
    if (trusted == null || (!ledger.exists && !isTrusted(peer.deviceId))) {
      return;
    }
    try {
      final ch = await OfficeChannel.open(
        identity: identity,
        peer: trusted,
        host: host,
        port: peer.port,
      );
      unawaited(_metOwn(ch));
      final reply = ch.messages.first.timeout(const Duration(seconds: 10));
      await ch.send({'t': 'defter', 'kayit': ledger.records});
      final m = await reply;
      await ch.close();
      if (m['t'] == 'defter' && m['kayit'] is List) {
        if (await ledger.merge(m['kayit'] as List)) notifyListeners();
      }
    } catch (_) {}
  }

  /// After a change: to every trusted device on the network.
  Future<void> _shareLedger() async {
    for (final peer in _peers.values.toList()) {
      if (peer.online && isTrusted(peer.deviceId)) {
        await _syncLedger(peer);
      }
    }
  }

  final _ledgerSynced = <String>{};

  /// Whether this device may give a task to [to]: a manager to anyone, a
  /// lawyer to themself, a trainee or a secretary; no one else.
  bool mayGive(String to) => _mayGiveFrom(me, to);

  /// This device's person in the office (see [OfficeMember.person]): whom
  /// its tasks are given to and its talks are had with.
  String get me => ledger.personOf(_self?.deviceId ?? '');

  /// Every device of [people] in the office, but this one.
  Set<String> _devicesOf(Iterable<String> people) =>
      {for (final p in people) ...ledger.devicesOf(p)}..remove(_self?.deviceId);

  /// The same rule for any member: what a task that came is checked by.
  bool _mayGiveFrom(String giver, String to) {
    final me = ledger.member(giver);
    final them = ledger.member(to);
    if (me == null || them == null) return false;
    return switch (me.role) {
      OfficeRole.manager => true,
      OfficeRole.lawyer =>
        them.person == me.person ||
            them.role == OfficeRole.trainee ||
            them.role == OfficeRole.secretary,
      _ => false,
    };
  }

  /// Gives a task; why not, in the user's words, when it cannot be.
  Future<String?> giveTask({
    required String title,
    required List<String> to,
    String note = '',
    DateTime? due,
    TaskPriority priority = TaskPriority.normal,
    List<TaskCase> cases = const [],
    Map<String, TaskPackage> packed = const {},
    TaskHearing? hearing,
  }) async {
    final self = _self;
    if (self == null) return 'Önce büro ağına katılın.';
    if (title.trim().isEmpty) return 'Görevin ne olduğunu yazın.';
    if (to.isEmpty) return 'Görevin kime verileceğini seçin.';
    for (final id in to) {
      if (!mayGive(id)) {
        final who = ledger.member(id)?.name ?? 'bu kişi';
        return '$who için görev verme yetkiniz yok.';
      }
    }
    // A trainee's work is under a lawyer: the giver, unless a trainee.
    final trainee = to.any(
      (id) => ledger.member(id)?.role == OfficeRole.trainee,
    );
    final task = OfficeTask(
      id: OfficeTask.newId(),
      title: title.trim(),
      by: me,
      byName: self.name,
      assignees: {for (final id in to) id: ledger.member(id)?.name ?? ''},
      createdAt: DateTime.now(),
      note: note.trim(),
      due: due,
      priority: priority,
      cases: cases,
      supervisor: trainee ? self.name : '',
      hearing: hearing,
    );
    task.events.add(
      await _sign(
        task,
        TaskEvent.create(
          TaskEventKind.given,
          me,
          self.name,
          device: self.deviceId,
        ),
      ),
    );
    await tasks.put(task);
    for (final c in cases) {
      final pack = packed[c.caseKey];
      if (pack == null || pack.paths.isEmpty) continue;
      packages.sources['${task.id}|${c.caseKey}'] = pack.paths;
      // To each device of each it is given to, this person's others too.
      for (final id in _devicesOf(to)) {
        packages.pending['${task.id}|${c.caseKey}|$id'] = pack.paths;
      }
    }
    await packages.save();
    notifyListeners();
    unawaited(_shareTask(task).then((_) => _sendPackages(task)));
    return null;
  }

  /// A task's cases to those it is given to who are on the network now.
  Future<void> _sendPackages(OfficeTask task, {String? only}) async {
    for (final key in packages.pending.keys.toList()) {
      final parts = key.split('|');
      if (parts.length != 3) continue;
      if (parts[0] != task.id || (only != null && parts[2] != only)) continue;
      // A case only to one it is still given to, still of the office.
      if (!task.assignees.containsKey(ledger.personOf(parts[2])) ||
          ledger.member(parts[2]) == null) {
        packages.pending.remove(key);
        await packages.save();
        continue;
      }
      final peer = _peers[parts[2]];
      if (peer == null || !peer.online) continue;
      await send(
        peer,
        packages.pending[key]!,
        meta: {'gorev': task.id, 'dosya': parts[1]},
      );
    }
  }

  /// What came of a task's case here.
  ReceivedCase? receivedCase(OfficeTask task, String caseKey) =>
      packages.received(task.id, caseKey);

  /// Something done in a task by this device: said to the others in it.
  Future<String?> act(
    OfficeTask task,
    TaskEventKind kind, {
    String text = '',
    int? percent,
    String? itemId,
    List<String> files = const [],
  }) async {
    final self = _self;
    if (self == null) return 'Önce büro ağına katılın.';
    if ((kind == TaskEventKind.returned || kind == TaskEventKind.cancelled) &&
        text.trim().isEmpty) {
      return 'Nedenini yazın.';
    }
    final ok = await tasks.add(
      task,
      await _sign(
        task,
        TaskEvent.create(
          kind,
          me,
          self.name,
          device: self.deviceId,
          text: text.trim(),
          percent: percent,
          itemId: itemId,
          files: files,
        ),
      ),
    );
    if (!ok) return 'Bunu bu görevde yapamazsınız.';
    notifyListeners();
    unawaited(_shareTask(task));
    return null;
  }

  Future<TaskEvent> _sign(OfficeTask task, TaskEvent e) async =>
      e.signed(await _identity!.signAsDevice(_signed(task, e)));

  static List<int> _signed(OfficeTask task, TaskEvent e) =>
      e.signedOf(task.id, e.kind == TaskEventKind.given ? task.terms : '');

  /// The member's device key, from the office's ledger: what a step or a
  /// message is checked against.
  /// [device] wrote it, a device of the person [by], by its signature.
  Future<bool> _byMember(
    String by,
    String device,
    List<int> data,
    String signature,
  ) async {
    final writer = ledger.member(device);
    if (writer == null || writer.person != by) return false;
    return OfficeIdentity.signedBy(writer.publicKey, data, signature);
  }

  bool _mayCreate(OfficeTask t) =>
      t.assignees.keys.every((to) => _mayGiveFrom(t.by, to));

  Future<bool> _taskAuthentic(OfficeTask task, TaskEvent e) =>
      _byMember(e.by, e.device, _signed(task, e), e.signature);

  Future<bool> _messageAuthentic(String chatId, ChatMessage m) =>
      _byMember(m.by, m.device, m.signedOf(chatId), m.signature);

  /// Who may see [task]: those in it and the managers, while members.
  bool _maySee(OfficeTask task, String deviceId) =>
      ledger.member(deviceId) != null &&
      (task.people.contains(ledger.personOf(deviceId)) ||
          ledger.isManager(deviceId));

  /// Who may read [chat]: its members, or all for a broadcast, while
  /// members of the office; one taken off it hears no more.
  bool _mayHear(Chat chat, String deviceId) =>
      ledger.member(deviceId) != null &&
      (chat.kind == ChatKind.broadcast ||
          chat.members.containsKey(ledger.personOf(deviceId)));

  Future<void> _shareTask(OfficeTask task) async {
    // Those in it, and the office's managers, who see all of its work.
    final to = {
      for (final id in _devicesOf(task.people))
        if (_maySee(task, id)) id,
      for (final m in ledger.members)
        if (m.role == OfficeRole.manager) m.deviceId,
    }..remove(_self?.deviceId);
    for (final id in to) {
      final peer = _peers[id];
      if (peer != null && peer.online) {
        await _syncTask(peer, task);
      }
    }
  }

  Future<void> _syncTask(OfficePeer peer, OfficeTask task) async {
    final identity = _identity, host = peer.host;
    final trusted = await _trustedFor(peer);
    if (identity == null || host == null || trusted == null) return;
    try {
      final ch = await OfficeChannel.open(
        identity: identity,
        peer: trusted,
        host: host,
        port: peer.port,
      );
      unawaited(_metOwn(ch));
      final reply = ch.messages.first.timeout(const Duration(seconds: 10));
      await ch.send({'t': 'gorev', 'gorev': task.toJson()});
      final m = await reply;
      await ch.close();
      final theirs = OfficeTask.fromJson(m['gorev']);
      if (theirs != null &&
          await tasks.merge(
            theirs,
            from: ledger.personOf(peer.deviceId),
            added: (e) => _taskMoved(theirs.id, e),
            authentic: _taskAuthentic,
            mayCreate: _mayCreate,
            own: ch.vouched && ledger.personOf(peer.deviceId) == me,
          )) {
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Something another member wrote, for the notifications to tell.
  void Function(Chat chat, ChatMessage message)? onMessage;

  /// Something another member did in a task.
  void Function(OfficeTask task, TaskEvent event)? onTaskEvent;

  void _messageCame(String chatId, ChatMessage m) {
    final c = chats.of(chatId);
    // A correction is no new message: nothing is told of it.
    if (c != null && m.by != me && !m.isCorrection) onMessage?.call(c, m);
  }

  void _taskMoved(String taskId, TaskEvent e) {
    // Read after it is kept: the callback comes while it is being added.
    scheduleMicrotask(() {
      final t = tasks.of(taskId);
      if (t != null && e.by != me) onTaskEvent?.call(t, e);
    });
  }

  /// A talk was opened and read: its count in the menus goes.
  Future<void> markRead(Chat chat) async {
    await chats.markRead(chat);
    notifyListeners();
  }

  /// This device's person, as the device they were taken in with.
  OfficeMember? get _me => ledger.member(me);

  /// The private talk with [deviceId]'s person, made if there is none yet.
  Future<Chat?> privateChat(String deviceId) async {
    final me = _me, them = ledger.member(ledger.personOf(deviceId));
    if (me == null || them == null) return null;
    final id = Chat.privateId(me.deviceId, them.deviceId);
    final kept = chats.of(id);
    if (kept != null) {
      // Only the very talk of the two, never one set up under its id.
      final pair = kept.members.keys.toSet();
      return kept.kind == ChatKind.private &&
              pair.length == 2 &&
              pair.containsAll([me.deviceId, them.deviceId])
          ? kept
          : null;
    }
    final chat = Chat(
      id: id,
      kind: ChatKind.private,
      by: me.deviceId,
      members: {me.deviceId: me.name, them.deviceId: them.name},
    );
    await chats.put(chat);
    notifyListeners();
    return chat;
  }

  Future<Chat?> groupChat(String name, List<String> deviceIds) async {
    final me = _me;
    if (me == null) return null;
    final chat = Chat(
      id: Chat.newId(),
      kind: ChatKind.group,
      by: me.deviceId,
      name: name.trim(),
      members: {
        me.deviceId: me.name,
        for (final id in deviceIds) id: ledger.member(id)?.name ?? '',
      },
    );
    await chats.put(chat);
    notifyListeners();
    unawaited(_shareChat(chat));
    return chat;
  }

  /// The office's announcements: only managers write in it.
  Future<Chat?> broadcastChat() async {
    final me = _me, office = ledger.officeId;
    if (me == null || office == null) return null;
    final id = 'duyuru-${office.substring(0, 16)}';
    final kept = chats.of(id);
    if (kept != null) return kept;
    if (me.role != OfficeRole.manager) return null;
    final chat = Chat(
      id: id,
      kind: ChatKind.broadcast,
      by: me.deviceId,
      name: '${ledger.officeName} · duyurular',
      members: {for (final m in ledger.people) m.deviceId: m.name},
    );
    await chats.put(chat);
    notifyListeners();
    return chat;
  }

  bool mayWrite(Chat chat) => chat.kind == ChatKind.broadcast
      ? ledger.isManager(_self?.deviceId ?? '')
      : chat.members.containsKey(me);

  /// Sends words and files in a talk; the files go to each member on the
  /// network now, and to the others when they come on it.
  Future<String?> post(
    Chat chat, {
    String text = '',
    List<String> files = const [],
    int? voiceSeconds,
  }) async {
    final self = _self;
    if (self == null) return 'Önce büro ağına katılın.';
    if (!mayWrite(chat)) return 'Bu konuşmaya yalnız yöneticiler yazabilir.';
    if (text.trim().isEmpty && files.isEmpty) return null;
    final attachments = <ChatAttachment>[
      for (final f in files)
        ChatAttachment(
          name: p.basename(f),
          size: await File(f).length(),
          kind: voiceSeconds != null
              ? AttachmentKind.voice
              : ChatAttachment.kindOf(f),
          seconds: voiceSeconds,
        ),
    ];
    final unsigned = ChatMessage(
      id: Chat.newId(),
      by: me,
      device: self.deviceId,
      byName: self.name,
      at: DateTime.now(),
      text: text.trim(),
      attachments: attachments,
    );
    final m = unsigned.signed(
      await _identity!.signAsDevice(unsigned.signedOf(chat.id)),
    );
    final to = _audience(chat);
    await chats.add(chat, m, waiting: files.isEmpty ? const {} : to);
    for (var i = 0; i < files.length; i++) {
      await chats.fileCame(m.id, attachments[i].name, files[i]);
    }
    notifyListeners();
    unawaited(_shareChat(chat));
    return null;
  }

  /// [original], one of this person's own messages, corrected to [text],
  /// or [delete]d: a signed message of its own that every device in the
  /// talk applies (see [Chat.ordered]). Files already sent stay where they
  /// came; the talk no longer shows them.
  Future<String?> correct(
    Chat chat,
    ChatMessage original, {
    String text = '',
    bool delete = false,
  }) async {
    final self = _self;
    if (self == null) return 'Önce büro ağına katılın.';
    if (original.by != me) {
      return 'Yalnız kendi mesajınızı değiştirebilirsiniz.';
    }
    if (!delete && text.trim().isEmpty) return 'Mesajı boş bırakmayın; silin.';
    final unsigned = ChatMessage(
      id: Chat.newId(),
      by: me,
      device: self.deviceId,
      byName: self.name,
      at: DateTime.now(),
      text: delete ? '' : text.trim(),
      replaces: original.id,
      deleted: delete,
    );
    final m = unsigned.signed(
      await _identity!.signAsDevice(unsigned.signedOf(chat.id)),
    );
    await chats.add(chat, m);
    notifyListeners();
    unawaited(_shareChat(chat));
    return null;
  }

  /// The devices a talk goes to: every device of its people, this
  /// person's others too, while they are of the office.
  Set<String> _audience(Chat chat) => {
    ...(chat.kind == ChatKind.broadcast
        ? {for (final m in ledger.members) m.deviceId}
        : _devicesOf(chat.members.keys).where((id) => _mayHear(chat, id))),
  }..remove(_self?.deviceId);

  Future<void> _shareChat(Chat chat) async {
    for (final id in _audience(chat)) {
      final peer = _peers[id];
      if (peer != null && peer.online) await _syncChat(peer, chat);
    }
  }

  Future<void> _syncChat(OfficePeer peer, Chat chat) async {
    final identity = _identity, host = peer.host;
    final trusted = await _trustedFor(peer);
    if (identity == null || host == null || trusted == null) return;
    try {
      final ch = await OfficeChannel.open(
        identity: identity,
        peer: trusted,
        host: host,
        port: peer.port,
      );
      unawaited(_metOwn(ch));
      final reply = ch.messages.first.timeout(const Duration(seconds: 10));
      await ch.send({'t': 'sohbet', 'sohbet': chat.toJson()});
      final m = await reply;
      await ch.close();
      final theirs = Chat.fromJson(m['sohbet']);
      if (theirs != null &&
          await chats.merge(
            theirs,
            from: ledger.personOf(peer.deviceId),
            mayBroadcast: ledger.isManager,
            added: (msg) => _messageCame(theirs.id, msg),
            authentic: _messageAuthentic,
            me: me,
          )) {
        notifyListeners();
      }
    } catch (_) {
      // Not reached, though it seemed there: tried again when next heard.
      _ledgerSynced.remove(peer.deviceId);
    }
    // This device's files that have not yet reached it. A copy is gone
    // through: a message written while a file is on its way joins the
    // talk meanwhile.
    for (final msg in [...chat.messages]) {
      final left = chats.pending[msg.id];
      if (msg.device != _self?.deviceId ||
          left == null ||
          !left.contains(peer.deviceId)) {
        continue;
      }
      final paths = [
        for (final a in msg.attachments) ?chats.fileOf(msg.id, a.name),
      ];
      if (paths.isEmpty) continue;
      await send(peer, paths, meta: {'sohbet': chat.id, 'mesaj': msg.id});
    }
  }

  /// Every talk shared with [peer], when it comes on the network.
  Future<void> _syncChats(OfficePeer peer) async {
    for (final c in chats.all) {
      if (_audience(c).contains(peer.deviceId)) await _syncChat(peer, c);
    }
  }

  /// Every task shared with [peer], when it comes on the network.
  Future<void> _syncTasks(OfficePeer peer) async {
    for (final t in tasks.all) {
      if (_maySee(t, peer.deviceId)) {
        await _syncTask(peer, t);
      }
      if (t.by == me) await _sendPackages(t, only: peer.deviceId);
    }
  }

  Future<String?> foundOffice(String name) async {
    final identity = _identity, self = _self;
    if (identity == null || self == null) return 'Önce büro ağına katılın.';
    if (name.trim().isEmpty) return 'Büronun adını yazın.';
    // An office is seen by its name: open to it before it is founded.
    if (!officeOpen) await openToOffice(true);
    await ledger.found(identity, _self ?? self, name);
    notifyListeners();
    return null;
  }

  Future<String?> admit(String deviceId, OfficeRole role) async {
    final identity = _identity;
    final known = _knownDevices[deviceId];
    if (identity == null || known == null) {
      return 'Önce cihazı kodla tanıyın.';
    }
    return _after(await ledger.admit(identity, known, role));
  }

  Future<String?> setRole(String deviceId, OfficeRole role) async {
    final identity = _identity;
    if (identity == null) return 'Önce büro ağına katılın.';
    return _after(await ledger.setRole(identity, deviceId, role));
  }

  /// Lets [deviceId]'s person see the clients' money, or no longer.
  Future<String?> setMoney(String deviceId, bool open) async {
    final identity = _identity;
    if (identity == null) return 'Önce büro ağına katılın.';
    return _after(await ledger.setMoney(identity, deviceId, open));
  }

  /// The founder's recovery code, new; null when this is not the founder.
  Future<String?> makeRecovery() async {
    final identity = _identity;
    if (identity == null) return null;
    final code = await ledger.makeRecovery(identity);
    if (code != null) {
      notifyListeners();
      unawaited(_shareLedger());
    }
    return code;
  }

  /// Comes into the office as its founder, by the recovery code.
  Future<String?> recoverFounder(String code) async {
    final identity = _identity, self = _self;
    if (identity == null || self == null) return 'Önce büro ağına katılın.';
    final error = await ledger.recover(identity, self, code);
    if (error == null) {
      notifyListeners();
      unawaited(_shareLedger());
    }
    return error;
  }

  Future<String?> removeMember(String deviceId) async {
    final identity = _identity;
    if (identity == null) return 'Önce büro ağına katılın.';
    final error = await ledger.remove(identity, deviceId);
    if (error == null) {
      // What was still to go to them does not.
      packages.pending.removeWhere((key, _) => key.endsWith('|$deviceId'));
      await packages.save();
    }
    return _after(error);
  }

  Future<String?> _after(String? error) async {
    notifyListeners();
    if (error == null) unawaited(_shareLedger());
    return error;
  }

  /// The user took an offer: if it is cut off, it goes on unasked.
  Future<void> acceptOffer(OfficeTransfer t) async {
    _accepted.add(t.id);
    await t.accept();
  }

  Future<void> _knownNow(KnownDevice device) async {
    await _known.remember(device);
    await _loadKnown();
    notifyListeners();
  }

  Future<void> _loadKnown() async {
    _knownDevices = {for (final d in await _known.all()) d.deviceId: d};
  }

  /// The one port Folio listens on, so that a firewall needs one rule
  /// for it (`sudo ufw allow 47900/tcp`); another when it is taken.
  static const port = 47900;

  static Future<ServerSocket> _bindServer() async {
    try {
      return await ServerSocket.bind(
        InternetAddress.anyIPv6,
        port,
        v6Only: false,
      );
    } on SocketException {
      return ServerSocket.bind(InternetAddress.anyIPv6, 0, v6Only: false);
    }
  }

  /// Whether this computer's firewall keeps others out: ufw on Linux,
  /// which lets nothing in until told to. Windows asks by itself.
  /// The port this Folio listens on now: [port], or another when that
  /// was taken.
  int get listeningPort => _server?.port ?? port;

  /// The local networks only: the office's and the home's, never all of
  /// the internet.
  static const _local = ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'];

  /// The rules that let the person's phone and the office in on [at].
  static List<String> firewallRules(int at) => [
    for (final net in _local) ...[
      'ufw allow from $net to any port $at proto tcp',
      'ufw allow from $net to any port 5353 proto udp',
    ],
  ];

  static Future<bool> firewallBlocks({int at = port}) async {
    if (!Platform.isLinux) return false;
    try {
      final mark = await _firewallMark();
      if (await mark.exists()) {
        final kept = jsonDecode(await mark.readAsString());
        if (kept is Map && kept['kapi'] == at) return false;
      }
      final r = await Process.run('systemctl', ['is-active', 'ufw']);
      return '${r.stdout}'.trim() == 'active';
    } catch (_) {
      return false;
    }
  }

  /// Kept once the firewall was opened from Folio, with the port it was
  /// opened for: ufw's rules cannot be read without the administrator. A
  /// hint only, for Folio to say no more; it opens nothing.
  static Future<File> _firewallMark() async => File(
    p.join((await folioSupportDirectory()).path, 'guvenlik_duvari.json'),
  );

  /// "İzin ver": the system's own password window (pkexec), the same one
  /// that asks when software is installed, then the rules for [at], from
  /// the local networks only. True when they were added.
  static Future<bool> openFirewall({int at = port}) async {
    if (!Platform.isLinux) return false;
    try {
      // Fixed words only: nothing the user or the network says is in it.
      final r = await Process.run('pkexec', [
        'sh',
        '-c',
        firewallRules(at).join(' && '),
      ]);
      if (r.exitCode != 0) return false;
      final mark = await _firewallMark();
      await mark.parent.create(recursive: true);
      await mark.writeAsString(jsonEncode({'kapi': at}));
      return true;
    } catch (_) {
      return false;
    }
  }

  int _silent = 0;

  /// A talk another Folio opened: knowing by a code, for now; what is
  /// sent to a known device comes in the next step (docs/buro.md, Aktarım).
  void _opened(Socket socket) {
    // Talks not yet begun are few and short: one that says nothing is let
    // go, and a crowd of them is not let in.
    if (_silent >= 32) {
      socket.destroy();
      return;
    }
    _silent++;
    final link = OfficeLink(socket);
    late final StreamSubscription<Map<String, Object?>> first;
    var heard = false;
    final quiet = Timer(const Duration(seconds: 20), () {
      if (heard) return;
      heard = true;
      _silent--;
      unawaited(first.cancel());
      unawaited(link.close());
    });
    first = link.messages.listen(
      (m) {
        if (heard) return;
        heard = true;
        _silent--;
        quiet.cancel();
        unawaited(first.cancel());
        final identity = _identity, self = _self;
        if (m['t'] == 'hello' && identity != null) {
          unawaited(_talk(link, m, identity));
          return;
        }
        if (m['t'] != 'pair' || identity == null || self == null) {
          unawaited(link.close());
          return;
        }
        if (_pairing != null && !_pairing!.finished) {
          link.send({'t': 'busy'});
          unawaited(link.close());
          return;
        }
        if (m['misafir'] == true) {
          // A guest: only while taking guests, and known in memory alone.
          if (!_guestsOpen) {
            link.send({'t': 'reject'});
            unawaited(link.close());
            return;
          }
          // Asked of the document taking guests now, and told to it
          // alone: if another takes them meanwhile, this one is not let in.
          final owner = _guestOwner, told = _onGuest;
          late final OfficePairing asking;
          asking = OfficePairing.answer(
            link: link,
            first: m,
            identity: identity,
            self: self,
            onKnown: (d) async {
              if (!_guestsOpen || !identical(_guestOwner, owner)) {
                asking.reject();
                return;
              }
              final grant = _guestGrant(d);
              _guests[d.deviceId] = grant;
              // Reached where it paired from, if not yet seen announced.
              final at = asking.other;
              if (_peers[d.deviceId]?.host == null &&
                  at?.host != null &&
                  (at?.port ?? 0) > 0) {
                _peers[d.deviceId] = at!;
              }
              told?.call(grant, asking.guestName, asking.guestOffice);
            },
          );
          _pairing = asking;
          _letGo(asking);
          if (!asking.finished) {
            _guestPairingFor = _guestTitle;
            guestPairing.value = asking;
            asking.addListener(() {
              if (asking.finished && identical(guestPairing.value, asking)) {
                guestPairing.value = null;
              }
            });
          }
          return;
        }
        final invite = m['davet'] != null ? _invite : null;
        final pairing = OfficePairing.answer(
          link: link,
          first: m,
          identity: identity,
          self: self,
          onKnown: _knownNow,
          invite: invite,
        );
        _pairing = pairing;
        _watchPairing(pairing);
        if (pairing.finished) return;
        if (pairing.byQr) {
          // A QR is good for one phone.
          _invite = null;
          qrPairing.value = pairing;
        } else {
          incoming.value = pairing;
        }
      },
      onDone: () {
        if (heard) return;
        heard = true;
        _silent--;
        quiet.cancel();
      },
    );
  }

  /// Joins again if the user had joined before; at Folio's start.
  Future<void> resume() async {
    if (await _wanted()) await join();
  }

  /// Seen by the office (by name, on its list), not only by this person's
  /// own devices: chosen on the office's page, or a member of one. Keeping
  /// one's own devices alike is no office: a lawyer alone with two devices
  /// is announced with no name, on no one else's list.
  bool get officeOpen => _officeOpen || ledger.exists;
  bool _officeOpen = false;

  Future<bool> _wanted() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) return false;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return false;
      _officeOpen = json['buro'] == true;
      return json['gorun'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _remember(bool joined) async {
    try {
      final file = await _settingsFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'gorun': joined, 'buro': _officeOpen}),
      );
    } catch (_) {}
  }

  /// The office's page: seen by the office, by name; or, [open] false,
  /// by this person's own devices alone, with no name.
  Future<void> openToOffice(bool open) async {
    _officeOpen = open;
    // The user's own choice: not let go when a live document's guests go.
    _quiet = false;
    if (!_joined) {
      await join();
    } else {
      await _remember(true);
      await rename();
    }
    notifyListeners();
  }

  /// Announces this Folio and starts looking for the others.
  Future<void> join({bool remember = true}) {
    if (remember) _quiet = false;
    // After a leaving or a quiet closing under way, not beside it.
    return _serial(() => _join(remember));
  }

  Future<void> _join(bool remember) async {
    if (_joined || _starting) {
      // Joined, or joining, for a live document alone: kept from now on.
      if (remember && _joined) await _remember(true);
      if (remember && _starting) _rememberWhenJoined = true;
      return;
    }
    _starting = true;
    _error = null;
    if (kDebugMode) debugPrint('Büro ağı: katılıyor');
    notifyListeners();
    try {
      _identity ??= await OfficeIdentity.load();
      await _loadKnown();
      await ledger.load();
      await tasks.load();
      await chats.load();
      await packages.load();
      // Where the others will reach this Folio; what is said there comes in
      // the next step (docs/buro.md, Aktarım), till then it hangs up.
      // Both families: the others may find this one by either address.
      _server = await _bindServer();
      _server!.listen(_opened);
      _self = await _describe(_identity!, _server!.port);
      OfficeChannel.me = _about(_self!);
      await _announce(_self!);
      await _look();
      _joined = true;
      if (remember || _rememberWhenJoined) {
        _quiet = false;
        await _remember(true);
      }
      if (kDebugMode) {
        debugPrint('Büro ağı: katıldı, ${_self!.device}:${_self!.port}');
      }
    } catch (e) {
      _error = '$e';
      if (kDebugMode) debugPrint('Büro ağı: katılınamadı: $e');
      await _close();
    } finally {
      _starting = false;
      _rememberWhenJoined = false;
      notifyListeners();
    }
  }

  /// Stops announcing and looking; Folio will not join at its next start.
  Future<void> leave() {
    _ownSoon?.cancel();
    _quiet = false;
    return _serial(() async {
      await _close();
      _joined = false;
      _peers.clear();
      await _remember(false);
      notifyListeners();
    });
  }

  /// Announces again with the profile's name, after it was changed.
  Future<void> rename() => _serial(_rename);

  Future<void> _rename() async {
    final identity = _identity, server = _server;
    if (!_joined || identity == null || server == null) return;
    // Nothing was announced (a test's listening): nothing to say again.
    if (_broadcast == null) return;
    final next = await _describe(identity, server.port);
    if (next.name == _self?.name && next.device == _self?.device) return;
    await _broadcast?.stop();
    _self = next;
    await _announce(next);
    notifyListeners();
  }

  Future<OfficePeer> _describe(OfficeIdentity identity, int port) async {
    var name = '';
    try {
      name = (await LawyerProfile.load()).lawyer?.titled ?? '';
    } catch (_) {}
    final platform = OfficePlatform.of(
      platformName ?? Platform.operatingSystem,
    );
    var device = '';
    try {
      device = Platform.localHostname;
    } catch (_) {}
    if (device.isEmpty || device == 'localhost') {
      device = platform.phone ? '${platform.label} telefon' : platform.label;
    }
    // Not open to the office: nothing of the person said to the network,
    // only what lets this person's own devices know it.
    // Taking guests: named, that the guest knows whom it asks.
    final open = officeOpen || _guestsOpen;
    return OfficePeer(
      deviceId: identity.deviceId,
      userId: identity.userId,
      name: open ? name : '',
      device: open ? device : '',
      platform: platform,
      port: port,
      live: _guestsOpen,
    );
  }

  Future<void> _announce(OfficePeer self) async {
    final broadcast = BonsoirBroadcast(
      printLogs: false,
      service: BonsoirService(
        // The device's id: unique on the network, and nothing of the person.
        name: 'folio-${self.deviceId}',
        type: OfficePeer.type,
        port: self.port,
        attributes: self.attributes,
      ),
    );
    await broadcast.initialize();
    await broadcast.start();
    _broadcast = broadcast;
  }

  Future<void> _look() async {
    final discovery = BonsoirDiscovery(printLogs: false, type: OfficePeer.type);
    await discovery.initialize();
    _events = discovery.eventStream?.listen((event) => _seen(discovery, event));
    await discovery.start();
    _discovery = discovery;
  }

  void _seen(BonsoirDiscovery discovery, BonsoirDiscoveryEvent event) {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent(:final service):
        // Found is only its name; what it says comes when it is resolved.
        try {
          discovery.serviceResolver.resolveService(service);
        } catch (_) {}
      case BonsoirDiscoveryServiceResolvedEvent(:final service) ||
          BonsoirDiscoveryServiceUpdatedEvent(:final service):
        final heard = OfficePeer.fromAnnouncement(
          service.attributes,
          host: service.hostAddresses.firstOrNull ?? service.hostname,
          port: service.port,
        );
        if (heard != null) _found(heard);
      case BonsoirDiscoveryServiceLostEvent(:final service):
        _lost(
          service.attributes['id'] ?? service.name.replaceFirst('folio-', ''),
        );
      default:
    }
  }

  /// A device heard on the network. One heard for the first time, or back
  /// after it was gone or at another address, is brought up to date: the
  /// ledger, the tasks and the talks, with the files that wait for it. A
  /// phone leaves the network whenever it sleeps; what was said meanwhile
  /// reaches it when it comes back, not only once it answers.
  void _found(OfficePeer heard) {
    if (heard.deviceId == _self?.deviceId) return;
    final before = _peers[heard.deviceId];
    final peer = heard.keepingPlaceOf(before);
    if (kDebugMode && peer.host != null && before?.host == null) {
      debugPrint(
        'Büro ağı: ${peer.name} · ${peer.device} '
        '(${peer.host}:${peer.port}) bulundu',
      );
    }
    _peers[peer.deviceId] = peer;
    notifyListeners();
    if (before == null ||
        !before.online ||
        before.host != peer.host ||
        before.port != peer.port) {
      _ledgerSynced.remove(peer.deviceId);
    }
    if (peer.host != null &&
        isTrusted(peer.deviceId) &&
        _ledgerSynced.add(peer.deviceId)) {
      unawaited(
        _syncLedger(peer)
            .then((_) => _syncTasks(peer))
            .then((_) => _syncChats(peer))
            .then((_) => _syncOfficeParts(peer)),
      );
    }
    if (peer.host != null && peer.userId == _identity?.userId) {
      unawaited(_syncOwnWith(peer));
    }
  }

  /// A device gone from the network: brought up to date again when back.
  void _lost(String id) {
    final peer = _peers[id];
    if (peer == null) return;
    _peers[id] = peer.gone(DateTime.now());
    _ledgerSynced.remove(id);
    notifyListeners();
  }

  Future<void> _close() async {
    await _events?.cancel();
    _events = null;
    try {
      await _discovery?.stop();
    } catch (_) {}
    try {
      await _broadcast?.stop();
    } catch (_) {}
    _discovery = null;
    _broadcast = null;
    await _server?.close();
    _server = null;
  }

  /// For tests: listening as [join] does, without the announcement.
  @visibleForTesting
  Future<void> listenForTesting(
    OfficeIdentity identity,
    OfficePeer self,
  ) async {
    _identity = identity;
    await _loadKnown();
    await ledger.load();
    await tasks.load();
    await chats.load();
    await packages.load();
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_opened);
    _self = OfficePeer(
      deviceId: identity.deviceId,
      userId: identity.userId,
      name: self.name,
      device: self.device,
      platform: self.platform,
      host: '127.0.0.1',
      port: _server!.port,
    );
    OfficeChannel.me = _about(_self!);
    _joined = true;
    // A test of the office: seen by it.
    _officeOpen = true;
  }

  static Map<String, String> _about(OfficePeer self) => {
    'n': self.name,
    'c': self.device,
    'p': self.platform.name,
  };

  /// For tests: a peer as if it had been found.
  /// For tests: [peer] heard on the network, as discovery hears it.
  @visibleForTesting
  void foundForTesting(OfficePeer peer) => _found(peer);

  /// For tests: the device [id] gone from the network.
  @visibleForTesting
  void lostForTesting(String id) => _lost(id);

  @visibleForTesting
  void seenForTesting(OfficePeer peer, {OfficePeer? self, bool office = true}) {
    if (self != null) _self = self;
    _joined = true;
    _officeOpen = office;
    _peers[peer.deviceId] = peer;
    notifyListeners();
  }
}

/// One whom a document can be sent to (see [OfficeNetwork.sendTargets]).
class SendTarget {
  const SendTarget({
    required this.deviceId,
    required this.name,
    required this.detail,
    required this.member,
    required this.online,
  });
  final String deviceId, name, detail;

  /// A member of the office, whose files wait for them; else an own device.
  final bool member;
  final bool online;
}

/// One thing a person's own devices keep alike: what this device has of
/// it, and taking what another has.
class OfficePart {
  const OfficePart({required this.export, required this.merge});

  /// What goes to the member whose device is given.
  final Future<Object?> Function(String toDevice) export;

  /// What came from the member whose device is given; true when anything
  /// here changed.
  final Future<bool> Function(Object? theirs, String fromDevice) merge;
}

class OwnPart {
  const OwnPart({required this.export, required this.merge});
  final Future<Object?> Function() export;

  /// True when anything here changed.
  final Future<bool> Function(Object? theirs) merge;
}

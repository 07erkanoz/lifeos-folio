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
    final me = _self?.deviceId;
    if (me == null) return const [];
    final out = <SendTarget>[
      for (final m in ledger.members)
        if (m.deviceId != me)
          SendTarget(
            deviceId: m.deviceId,
            name: m.name,
            detail: m.role.label,
            member: true,
            online: _peers[m.deviceId]?.online ?? false,
          ),
    ];
    final taken = {me, for (final t in out) t.deviceId};
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
    return send(to, t.paths, note: t.note, id: t.id);
  }

  void _added(OfficeTransfer t) {
    transfers.insert(0, t);
    t.addListener(notifyListeners);
    notifyListeners();
  }

  void _ended(OfficeTransfer t) {
    unawaited(_log(t));
    if (t.state == TransferState.done) unawaited(_metOwnDevice(t.talkedTo));
    final taskId = t.meta['gorev'], caseKey = t.meta['dosya'];
    if (taskId is String &&
        caseKey is String &&
        t.state == TransferState.done) {
      if (t.outgoing) {
        packages.pending.remove('$taskId|$caseKey|${t.peer.deviceId}');
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
  Future<void> _log(OfficeTransfer t) async {
    try {
      final file = await _logFile();
      var list = <Object?>[];
      if (await file.exists()) {
        final old = jsonDecode(await file.readAsString());
        if (old is List) list = old;
      }
      list.insert(0, t.toJson());
      if (list.length > 500) list = list.sublist(0, 500);
      await file.writeAsString(jsonEncode(list));
    } catch (_) {}
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
      ..._peers.values,
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
    final ch = await OfficeChannel.accept(
      link: link,
      hello: hello,
      identity: identity,
      known: _trusted,
    );
    if (ch == null) return;
    unawaited(_metOwn(ch));
    late final StreamSubscription<Map<String, Object?>> first;
    first = ch.messages.listen((m) async {
      await first.cancel();
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
              from: ch.peer.deviceId,
              mayBroadcast: ledger.isManager,
              added: (msg) => _messageCame(theirs.id, msg),
              authentic: _messageAuthentic,
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
              from: ch.peer.deviceId,
              added: (e) => _taskMoved(theirs.id, e),
              authentic: _taskAuthentic,
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
      if (m['t'] == 'defter') {
        await _ledgerCame(m['kayit']);
        await ch.send({'t': 'defter', 'kayit': ledger.records});
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await ch.close();
        return;
      }
      final meta = m['meta'] is Map ? m['meta'] as Map : const {};
      final forChat = meta['sohbet'] is String;
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
              folder: forChat
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
      if (chat != null &&
          (chat.members.containsKey(ch.peer.deviceId) ||
              (chat.kind == ChatKind.broadcast &&
                  ledger.isManager(ch.peer.deviceId)))) {
        // A member's file with a message: taken unasked.
        await t.accept();
        return;
      }
      final task = tasks.of('${t.meta['gorev'] ?? ''}');
      if (task != null && task.by == ch.peer.deviceId) {
        // A case of a task given to this device, from its giver.
        await t.accept();
        return;
      }
      if (ch.peer.userId == _identity?.userId) {
        // From one of this person's own devices: theirs already.
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
  Future<KnownDevice?> _trusted(String deviceId) async =>
      await _known.of(deviceId) ?? ledger.member(deviceId)?.asKnown;

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
    void done() {
      if (pairing.state != PairingState.done || !pairing.bothMine) return;
      pairing.removeListener(done);
      final other = pairing.other;
      if (other == null) return;
      _ownConsent.add(other.deviceId);
      unawaited(
        _unify(other, mine: pairing.ownCount, theirs: pairing.theirOwnCount),
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
  }) async {
    final identity = _identity;
    if (identity == null || other.userId == identity.userId) return;
    // The key shared by more devices is kept; else the smaller id's.
    final keep = mine != theirs
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
  Future<void> _metOwn(OfficeChannel ch) => _metOwnDevice(ch.peer);

  Future<void> _metOwnDevice(KnownDevice p) async {
    if (p.userId != _identity?.userId || p.publicKey.isEmpty) return;
    if (_knownDevices.containsKey(p.deviceId)) return;
    await _knownNow(p);
  }

  Future<void> _ledgerCame(Object? records) async {
    if (records is List && await ledger.merge(records)) {
      notifyListeners();
      unawaited(_shareLedger());
    }
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
  bool mayGive(String to) {
    final me = ledger.member(_self?.deviceId ?? '');
    final them = ledger.member(to);
    if (me == null || them == null) return false;
    return switch (me.role) {
      OfficeRole.manager => true,
      OfficeRole.lawyer =>
        them.deviceId == me.deviceId ||
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
      by: self.deviceId,
      byName: self.name,
      assignees: {for (final id in to) id: ledger.member(id)?.name ?? ''},
      createdAt: DateTime.now(),
      note: note.trim(),
      due: due,
      priority: priority,
      cases: cases,
      supervisor: trainee ? self.name : '',
    );
    task.events.add(
      await _sign(
        task.id,
        TaskEvent.create(TaskEventKind.given, self.deviceId, self.name),
      ),
    );
    await tasks.put(task);
    for (final c in cases) {
      final pack = packed[c.caseKey];
      if (pack == null || pack.paths.isEmpty) continue;
      for (final id in to) {
        if (id == self.deviceId) continue;
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
        task.id,
        TaskEvent.create(
          kind,
          self.deviceId,
          self.name,
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

  Future<TaskEvent> _sign(String taskId, TaskEvent e) async =>
      e.signed(await _identity!.signAsDevice(e.signedOf(taskId)));

  /// The member's device key, from the office's ledger: what a step or a
  /// message is checked against.
  Future<bool> _byMember(String by, List<int> data, String signature) async {
    final key = ledger.member(by)?.publicKey;
    if (key == null) return false;
    return OfficeIdentity.signedBy(key, data, signature);
  }

  Future<bool> _taskAuthentic(String taskId, TaskEvent e) =>
      _byMember(e.by, e.signedOf(taskId), e.signature);

  Future<bool> _messageAuthentic(String chatId, ChatMessage m) =>
      _byMember(m.by, m.signedOf(chatId), m.signature);

  /// Who may see [task]: those in it and the managers, while members.
  bool _maySee(OfficeTask task, String deviceId) =>
      ledger.member(deviceId) != null &&
      (task.people.contains(deviceId) || ledger.isManager(deviceId));

  /// Who may read [chat]: its members, or all for a broadcast, while
  /// members of the office; one taken off it hears no more.
  bool _mayHear(Chat chat, String deviceId) =>
      ledger.member(deviceId) != null &&
      (chat.kind == ChatKind.broadcast || chat.members.containsKey(deviceId));

  Future<void> _shareTask(OfficeTask task) async {
    // Those in it, and the office's managers, who see all of its work.
    final to = {
      for (final id in task.people)
        if (_maySee(task, id)) id,
      for (final m in ledger.members)
        if (m.role == OfficeRole.manager) m.deviceId,
    };
    for (final id in to) {
      final peer = _peers[id];
      if (id != _self?.deviceId && peer != null && peer.online) {
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
            from: peer.deviceId,
            added: (e) => _taskMoved(theirs.id, e),
            authentic: _taskAuthentic,
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
    if (c != null && m.by != _self?.deviceId) onMessage?.call(c, m);
  }

  void _taskMoved(String taskId, TaskEvent e) {
    // Read after it is kept: the callback comes while it is being added.
    scheduleMicrotask(() {
      final t = tasks.of(taskId);
      if (t != null && e.by != _self?.deviceId) onTaskEvent?.call(t, e);
    });
  }

  /// A talk was opened and read: its count in the menus goes.
  Future<void> markRead(Chat chat) async {
    await chats.markRead(chat);
    notifyListeners();
  }

  OfficeMember? get _me => ledger.member(_self?.deviceId ?? '');

  /// The private talk with [deviceId], made if there is none yet.
  Future<Chat?> privateChat(String deviceId) async {
    final me = _me, them = ledger.member(deviceId);
    if (me == null || them == null) return null;
    final id = Chat.privateId(me.deviceId, them.deviceId);
    final kept = chats.of(id);
    if (kept != null) return kept;
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
      members: {for (final m in ledger.members) m.deviceId: m.name},
    );
    await chats.put(chat);
    notifyListeners();
    return chat;
  }

  bool mayWrite(Chat chat) {
    final me = _self?.deviceId ?? '';
    return chat.kind == ChatKind.broadcast
        ? ledger.isManager(me)
        : chat.members.containsKey(me);
  }

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
      by: self.deviceId,
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

  Set<String> _audience(Chat chat) => {
    ...(chat.kind == ChatKind.broadcast
        ? {for (final m in ledger.members) m.deviceId}
        : chat.members.keys.where((id) => _mayHear(chat, id))),
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
            from: peer.deviceId,
            mayBroadcast: ledger.isManager,
            added: (msg) => _messageCame(theirs.id, msg),
            authentic: _messageAuthentic,
          )) {
        notifyListeners();
      }
    } catch (_) {}
    // This device's files that have not yet reached it.
    for (final msg in chat.messages) {
      final left = chats.pending[msg.id];
      if (msg.by != _self?.deviceId ||
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
      if (t.by == _self?.deviceId) await _sendPackages(t, only: peer.deviceId);
    }
  }

  Future<String?> foundOffice(String name) async {
    final identity = _identity, self = _self;
    if (identity == null || self == null) return 'Önce büro ağına katılın.';
    if (name.trim().isEmpty) return 'Büronun adını yazın.';
    await ledger.found(identity, self, name);
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

  Future<String?> removeMember(String deviceId) async {
    final identity = _identity;
    if (identity == null) return 'Önce büro ağına katılın.';
    return _after(await ledger.remove(identity, deviceId));
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

  Future<bool> _wanted() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) return false;
      final json = jsonDecode(await file.readAsString());
      return json is Map && json['gorun'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _remember(bool joined) async {
    try {
      final file = await _settingsFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'gorun': joined}));
    } catch (_) {}
  }

  /// Announces this Folio and starts looking for the others.
  Future<void> join() async {
    if (_joined || _starting) return;
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
      _server = await ServerSocket.bind(
        InternetAddress.anyIPv6,
        0,
        v6Only: false,
      );
      _server!.listen(_opened);
      _self = await _describe(_identity!, _server!.port);
      OfficeChannel.me = _about(_self!);
      await _announce(_self!);
      await _look();
      _joined = true;
      await _remember(true);
      if (kDebugMode) {
        debugPrint('Büro ağı: katıldı, ${_self!.device}:${_self!.port}');
      }
    } catch (e) {
      _error = '$e';
      if (kDebugMode) debugPrint('Büro ağı: katılınamadı: $e');
      await _close();
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  /// Stops announcing and looking; Folio will not join at its next start.
  Future<void> leave() async {
    await _close();
    _joined = false;
    _peers.clear();
    await _remember(false);
    notifyListeners();
  }

  /// Announces again with the profile's name, after it was changed.
  Future<void> rename() async {
    final identity = _identity, server = _server;
    if (!_joined || identity == null || server == null) return;
    // Nothing was announced (a test's listening): nothing to say again.
    if (_broadcast == null) return;
    final next = await _describe(identity, server.port);
    if (next.name == _self?.name) return;
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
    return OfficePeer(
      deviceId: identity.deviceId,
      userId: identity.userId,
      name: name,
      device: device,
      platform: platform,
      port: port,
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
        if (heard == null || heard.deviceId == _self?.deviceId) return;
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
        if (peer.host != null &&
            isTrusted(peer.deviceId) &&
            _ledgerSynced.add(peer.deviceId)) {
          unawaited(
            _syncLedger(peer)
                .then((_) => _syncTasks(peer))
                .then((_) => _syncChats(peer)),
          );
        }
      case BonsoirDiscoveryServiceLostEvent(:final service):
        final id =
            service.attributes['id'] ?? service.name.replaceFirst('folio-', '');
        final peer = _peers[id];
        if (peer == null) return;
        _peers[id] = peer.gone(DateTime.now());
        notifyListeners();
      default:
    }
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
  }

  static Map<String, String> _about(OfficePeer self) => {
    'n': self.name,
    'c': self.device,
    'p': self.platform.name,
  };

  /// For tests: a peer as if it had been found.
  @visibleForTesting
  void seenForTesting(OfficePeer peer, {OfficePeer? self}) {
    if (self != null) _self = self;
    _joined = true;
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

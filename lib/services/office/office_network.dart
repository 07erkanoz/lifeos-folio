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
    final known =
        _knownDevices[to.deviceId] ?? ledger.member(to.deviceId)?.asKnown;
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

  /// Starts knowing [peer] by a code; null while another is being known.
  OfficePairing? pair(OfficePeer peer) {
    final identity = _identity, self = _self;
    if (identity == null || self == null) return null;
    if (_pairing != null && !_pairing!.finished) return null;
    return _pairing = OfficePairing.start(
      identity: identity,
      self: self,
      peer: peer,
      onKnown: _knownNow,
    );
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
    late final StreamSubscription<Map<String, Object?>> first;
    first = ch.messages.listen((m) async {
      await first.cancel();
      if (m['t'] == 'sohbet') {
        final theirs = Chat.fromJson(m['sohbet']);
        if (theirs != null &&
            await chats.merge(
              theirs,
              from: ch.peer.deviceId,
              mayBroadcast: ledger.isManager,
              added: (msg) => _messageCame(theirs.id, msg),
            )) {
          notifyListeners();
        }
        final mine = theirs == null ? null : chats.of(theirs.id);
        await ch.send({'t': 'sohbet', 'sohbet': mine?.toJson()});
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await ch.close();
        return;
      }
      if (m['t'] == 'gorev') {
        final theirs = OfficeTask.fromJson(m['gorev']);
        if (theirs != null &&
            await tasks.merge(
              theirs,
              from: ch.peer.deviceId,
              added: (e) => _taskMoved(theirs.id, e),
            )) {
          notifyListeners();
        }
        final mine = theirs == null ? null : tasks.of(theirs.id);
        await ch.send({'t': 'gorev', 'gorev': mine?.toJson()});
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
              '${meta['gorev']}-${'${meta['dosya']}'.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')}',
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
      _knownDevices.containsKey(deviceId) || ledger.member(deviceId) != null;

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
    final trusted = await _trusted(peer.deviceId);
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
      TaskEvent.create(TaskEventKind.given, self.deviceId, self.name),
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
      TaskEvent.create(
        kind,
        self.deviceId,
        self.name,
        text: text.trim(),
        percent: percent,
        itemId: itemId,
        files: files,
      ),
    );
    if (!ok) return 'Bunu bu görevde yapamazsınız.';
    notifyListeners();
    unawaited(_shareTask(task));
    return null;
  }

  Future<void> _shareTask(OfficeTask task) async {
    // Those in it, and the office's managers, who see all of its work.
    final to = {
      ...task.people,
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
    final trusted = await _trusted(peer.deviceId);
    if (identity == null || host == null || trusted == null) return;
    try {
      final ch = await OfficeChannel.open(
        identity: identity,
        peer: trusted,
        host: host,
        port: peer.port,
      );
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
    final m = ChatMessage(
      id: Chat.newId(),
      by: self.deviceId,
      byName: self.name,
      at: DateTime.now(),
      text: text.trim(),
      attachments: attachments,
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
        : chat.members.keys),
  }..remove(_self?.deviceId);

  Future<void> _shareChat(Chat chat) async {
    for (final id in _audience(chat)) {
      final peer = _peers[id];
      if (peer != null && peer.online) await _syncChat(peer, chat);
    }
  }

  Future<void> _syncChat(OfficePeer peer, Chat chat) async {
    final identity = _identity, host = peer.host;
    final trusted = await _trusted(peer.deviceId);
    if (identity == null || host == null || trusted == null) return;
    try {
      final ch = await OfficeChannel.open(
        identity: identity,
        peer: trusted,
        host: host,
        port: peer.port,
      );
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
    final manager = ledger.isManager(peer.deviceId);
    for (final t in tasks.all) {
      if (manager || t.people.contains(peer.deviceId)) {
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

  /// A talk another Folio opened: knowing by a code, for now; what is
  /// sent to a known device comes in the next step (docs/buro.md, Aktarım).
  void _opened(Socket socket) {
    final link = OfficeLink(socket);
    late final StreamSubscription<Map<String, Object?>> first;
    first = link.messages.listen((m) {
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
      final pairing = OfficePairing.answer(
        link: link,
        first: m,
        identity: identity,
        self: self,
        onKnown: _knownNow,
      );
      _pairing = pairing;
      if (!pairing.finished) incoming.value = pairing;
    });
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
    _joined = true;
  }

  /// For tests: a peer as if it had been found.
  @visibleForTesting
  void seenForTesting(OfficePeer peer, {OfficePeer? self}) {
    if (self != null) _self = self;
    _joined = true;
    _peers[peer.deviceId] = peer;
    notifyListeners();
  }
}

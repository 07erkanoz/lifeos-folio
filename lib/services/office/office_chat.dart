import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';

/// What a talk is: between two, among some, or the managers' word to all.
enum ChatKind { private, group, broadcast }

enum AttachmentKind { file, image, voice }

String _newId() {
  final r = Random.secure();
  return [
    for (var i = 0; i < 8; i++)
      r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// A file with a message: its name, size and kind; [path] once it is here.
class ChatAttachment {
  const ChatAttachment({
    required this.name,
    required this.size,
    required this.kind,
    this.seconds,
  });
  final String name;
  final int size;
  final AttachmentKind kind;

  /// A voice message's length.
  final int? seconds;

  Map<String, Object?> toJson() => {
    'n': name,
    's': size,
    'k': kind.name,
    'sn': ?seconds,
  };
  static ChatAttachment? fromJson(Object? j) {
    if (j is! Map) return null;
    final n = j['n'], s = j['s'];
    if (n is! String || s is! int) return null;
    return ChatAttachment(
      name: p.basename(n.replaceAll('\\', '/')),
      size: s,
      kind: AttachmentKind.values.firstWhere(
        (k) => k.name == j['k'],
        orElse: () => AttachmentKind.file,
      ),
      seconds: j['sn'] is int ? j['sn'] as int : null,
    );
  }

  static AttachmentKind kindOf(String path) {
    final ext = p.extension(path).toLowerCase();
    if (const [
      '.png',
      '.jpg',
      '.jpeg',
      '.webp',
      '.gif',
      '.heic',
    ].contains(ext)) {
      return AttachmentKind.image;
    }
    return AttachmentKind.file;
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.by,
    required this.byName,
    required this.at,
    this.text = '',
    this.attachments = const [],
    this.signature = '',
  });
  final String id, by, byName, text;
  final DateTime at;
  final List<ChatAttachment> attachments;

  /// Its writer's device's signature on [signedOf].
  final String signature;

  /// What its writer signs: the words, the files and the talk they are in.
  List<int> signedOf(String chatId) => utf8.encode(
    [
      'folio-mesaj-1',
      chatId,
      id,
      by,
      byName,
      '${at.millisecondsSinceEpoch}',
      text,
      for (final a in attachments)
        '${a.name}/${a.size}/${a.kind.name}/${a.seconds ?? ''}',
    ].join('\u0000'),
  );

  ChatMessage signed(String signature) => ChatMessage(
    id: id,
    by: by,
    byName: byName,
    at: at,
    text: text,
    attachments: attachments,
    signature: signature,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kim': by,
    'ad': byName,
    'at': at.toUtc().toIso8601String(),
    if (text.isNotEmpty) 'metin': text,
    if (attachments.isNotEmpty)
      'ekler': [for (final a in attachments) a.toJson()],
    if (signature.isNotEmpty) 'imza': signature,
  };
  static ChatMessage? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || j['kim'] is! String) return null;
    final at = DateTime.tryParse('${j['at']}');
    if (at == null) return null;
    return ChatMessage(
      id: j['id'] as String,
      by: j['kim'] as String,
      byName: '${j['ad'] ?? ''}',
      at: at.toLocal(),
      text: '${j['metin'] ?? ''}',
      attachments: [
        for (final a in (j['ekler'] as List? ?? const []))
          ?ChatAttachment.fromJson(a),
      ],
      signature: j['imza'] is String ? j['imza'] as String : '',
    );
  }
}

/// A talk among members of the office (docs/buro.md, Mesajlaşma).
class Chat {
  Chat({
    required this.id,
    required this.kind,
    required this.by,
    required this.members,
    this.name = '',
    List<ChatMessage>? messages,
  }) : messages = messages ?? [];

  final String id, by, name;
  final ChatKind kind;

  /// Device id → name; for a broadcast, the office as it was told it.
  final Map<String, String> members;
  final List<ChatMessage> messages;

  List<ChatMessage> get ordered =>
      [...messages]..sort((a, b) => a.at.compareTo(b.at));
  ChatMessage? get last => messages.isEmpty ? null : ordered.last;

  /// The other person's name for a private talk, else its own name.
  String titleFor(String me) => switch (kind) {
    ChatKind.private =>
      members.entries
          .firstWhere((e) => e.key != me, orElse: () => members.entries.first)
          .value,
    ChatKind.group => name.isEmpty ? members.values.join(', ') : name,
    ChatKind.broadcast => name.isEmpty ? 'Büro duyuruları' : name,
  };

  Map<String, Object?> toJson() => {
    'id': id,
    'tur': kind.name,
    'kim': by,
    'ad': name,
    'uyeler': members,
    'mesajlar': [for (final m in messages) m.toJson()],
  };

  static Chat? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || j['kim'] is! String) return null;
    final members = j['uyeler'];
    return Chat(
      id: j['id'] as String,
      kind: ChatKind.values.firstWhere(
        (k) => k.name == j['tur'],
        orElse: () => ChatKind.group,
      ),
      by: j['kim'] as String,
      name: '${j['ad'] ?? ''}',
      members: {
        if (members is Map)
          for (final e in members.entries) '${e.key}': '${e.value}',
      },
      messages: [
        for (final m in (j['mesajlar'] as List? ?? const []))
          ?ChatMessage.fromJson(m),
      ],
    );
  }

  /// A private talk's id is the same on both sides, whoever starts it.
  static String privateId(String a, String b) =>
      'ozel-${([a, b]..sort()).join('-')}';

  static String newId() => _newId();
}

/// The talks this device is in, and where their files came to.
class OfficeChats {
  OfficeChats({Future<File> Function()? file}) : _file = file ?? _default;

  static Future<File> _default() async =>
      File(p.join((await folioSupportDirectory()).path, 'buro_mesajlar.json'));

  final Future<File> Function() _file;
  final _chats = <String, Chat>{};

  /// "message id/file name" → the file here.
  final _files = <String, String>{};

  /// Messages of this device's whose files have not yet reached a member:
  /// message id → device ids.
  final _pending = <String, Set<String>>{};

  /// Last read message time per talk, for the unread counts.
  final _read = <String, DateTime>{};
  bool _loaded = false;

  List<Chat> get all => _chats.values.toList()
    ..sort(
      (a, b) => (b.last?.at ?? DateTime(2000)).compareTo(
        a.last?.at ?? DateTime(2000),
      ),
    );
  Chat? of(String id) => _chats[id];
  String? fileOf(String messageId, String name) => _files['$messageId/$name'];
  Map<String, Set<String>> get pending => _pending;

  int unread(Chat c, String me) {
    final seen = _read[c.id];
    return c.messages
        .where((m) => m.by != me && (seen == null || m.at.isAfter(seen)))
        .length;
  }

  int unreadAll(String me) =>
      _chats.values.fold(0, (n, c) => n + unread(c, me));

  Future<void> markRead(Chat c) async {
    final last = c.last;
    if (last == null) return;
    _read[c.id] = last.at;
    await _save();
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final j = jsonDecode(await file.readAsString());
      if (j is! Map) return;
      for (final c in (j['sohbetler'] as List? ?? const [])) {
        final chat = Chat.fromJson(c);
        if (chat != null) _chats[chat.id] = chat;
      }
      (j['dosyalar'] as Map? ?? const {}).forEach(
        (k, v) => _files['$k'] = '$v',
      );
      (j['bekleyen'] as Map? ?? const {}).forEach(
        (k, v) => _pending['$k'] = {for (final d in (v as List)) '$d'},
      );
      (j['okundu'] as Map? ?? const {}).forEach((k, v) {
        final at = DateTime.tryParse('$v');
        if (at != null) _read['$k'] = at;
      });
    } catch (_) {}
  }

  Future<void> _saving = Future.value();
  Future<void> _save() =>
      _saving = _saving.then((_) => _write()).catchError((Object _) {});

  Future<void> _write() async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final part = File('${file.path}.part');
    await part.writeAsString(
      jsonEncode({
        'sohbetler': [for (final c in _chats.values) c.toJson()],
        'dosyalar': _files,
        'bekleyen': {for (final e in _pending.entries) e.key: e.value.toList()},
        'okundu': {
          for (final e in _read.entries) e.key: e.value.toIso8601String(),
        },
      }),
      flush: true,
    );
    await part.rename(file.path);
  }

  Future<void> put(Chat chat) async {
    _chats[chat.id] = chat;
    await _save();
  }

  Future<void> add(
    Chat chat,
    ChatMessage m, {
    Set<String> waiting = const {},
  }) async {
    chat.messages.add(m);
    if (waiting.isNotEmpty) _pending[m.id] = {...waiting};
    await put(chat);
  }

  Future<void> fileCame(String messageId, String name, String path) async {
    _files['$messageId/$name'] = path;
    await _save();
  }

  Future<void> delivered(String messageId, String deviceId) async {
    final left = _pending[messageId];
    if (left == null) return;
    left.remove(deviceId);
    if (left.isEmpty) _pending.remove(messageId);
    await _save();
  }

  /// Takes a talk as another member has it: its messages that its members
  /// wrote, from [from] who must be one of them; a broadcast's only from
  /// those [mayBroadcast] allows. True when anything was new.
  Future<bool> merge(
    Chat theirs, {
    required String from,
    required bool Function(String deviceId) mayBroadcast,
    void Function(ChatMessage message)? added,
    Future<bool> Function(String chatId, ChatMessage message)? authentic,
  }) async {
    Future<bool> real(ChatMessage m) async =>
        authentic == null || await authentic(theirs.id, m);
    final mine = _chats[theirs.id];
    final members = mine?.members ?? theirs.members;
    if (theirs.kind != ChatKind.broadcast && !members.containsKey(from)) {
      return false;
    }
    bool allowed(ChatMessage m) => theirs.kind == ChatKind.broadcast
        ? mayBroadcast(m.by)
        : members.containsKey(m.by);
    if (mine == null) {
      if (theirs.kind == ChatKind.broadcast && !mayBroadcast(theirs.by)) {
        return false;
      }
      final kept = Chat.fromJson(theirs.toJson())!..messages.clear();
      for (final m in theirs.messages.where(allowed)) {
        if (await real(m)) kept.messages.add(m);
      }
      await put(kept);
      kept.messages.forEach(added ?? (_) {});
      return true;
    }
    final seen = {for (final m in mine.messages) m.id};
    var changed = false;
    for (final m in theirs.messages) {
      if (seen.contains(m.id) || !allowed(m) || !await real(m)) continue;
      mine.messages.add(m);
      added?.call(m);
      changed = true;
    }
    if (changed) await put(mine);
    return changed;
  }
}

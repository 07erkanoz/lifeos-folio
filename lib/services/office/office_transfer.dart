import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'office_channel.dart';
import 'office_identity.dart';
import 'office_known.dart';

enum TransferState { connecting, offered, sending, done, declined, failed }

class TransferFile {
  const TransferFile(this.name, this.size, this.sha256);
  final String name;
  final int size;
  final String sha256;

  Map<String, Object?> toJson() => {'n': name, 's': size, 'h': sha256};
  static TransferFile? fromJson(Object? j) {
    if (j is! Map) return null;
    final n = j['n'], s = j['s'], h = j['h'];
    if (n is! String || s is! int || h is! String || s < 0) return null;
    // Only the name: no folder of the sender's is ever written to.
    final name = p.basename(n.replaceAll('\\', '/')).trim();
    if (name.isEmpty || name == '.' || name == '..') return null;
    return TransferFile(name, s, h);
  }
}

/// Files going to a known device, or coming from one (docs/buro.md,
/// Aktarım): an offer, the other's yes, the files in pieces, each checked
/// by its SHA-256 at its end. A talk cut off goes on from where it was the
/// next time the same offer is made.
class OfficeTransfer extends ChangeNotifier {
  OfficeTransfer._({
    required this.id,
    required this.outgoing,
    required this.peer,
    required this.files,
    required this.note,
    required this.at,
    this.meta = const {},
  });

  /// What the files belong to, such as a message (`sohbet`, `mesaj`).
  final Map<String, Object?> meta;

  /// Pieces of a file in one message, and how many may be on the way
  /// before the other says it has them.
  static const piece = 48 * 1024, window = 8;

  final String id;
  final bool outgoing;
  final KnownDevice peer;
  final List<TransferFile> files;
  final String note;
  final DateTime at;

  TransferState _state = TransferState.connecting;
  TransferState get state => _state;
  String? _reason;
  String? get reason => _reason;
  int _moved = 0;
  int get moved => _moved;
  int get total => files.fold(0, (n, f) => n + f.size);

  /// The device as the channel proved it: for one of the person's own
  /// devices met first here, with the key it showed.
  KnownDevice get talkedTo => _channel?.peer ?? peer;

  /// Where the files came to, once each is whole and checked.
  final saved = <String>[];

  OfficeChannel? _channel;
  StreamSubscription<Map<String, Object?>>? _listen;
  void Function(OfficeTransfer)? _onEnd;

  bool get finished =>
      _state == TransferState.done ||
      _state == TransferState.declined ||
      _state == TransferState.failed;

  static String newId() {
    final r = Random.secure();
    return [
      for (var i = 0; i < 12; i++)
        r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  static Future<String> sha256Of(File file) async =>
      (await hash.sha256.bind(file.openRead()).first).toString();

  // Sending.

  final _paths = <String>[];

  /// What is being sent, for sending it again from where it stopped.
  List<String> get paths => List.unmodifiable(_paths);
  final _acked = <int, int>{};
  Completer<void>? _ackWait;

  static Future<OfficeTransfer> send({
    required OfficeIdentity identity,
    required KnownDevice peer,
    required String host,
    required int port,
    required List<String> paths,
    String note = '',
    String? id,
    Map<String, Object?> meta = const {},
    void Function(OfficeTransfer)? onEnd,
  }) async {
    final files = <TransferFile>[];
    for (final path in paths) {
      final f = File(path);
      files.add(
        TransferFile(p.basename(path), await f.length(), await sha256Of(f)),
      );
    }
    final t = OfficeTransfer._(
      id: id ?? newId(),
      outgoing: true,
      peer: peer,
      files: files,
      note: note,
      at: DateTime.now(),
      meta: meta,
    ).._onEnd = onEnd;
    t._paths.addAll(paths);
    unawaited(t._offer(identity, host, port));
    return t;
  }

  Future<void> _offer(OfficeIdentity identity, String host, int port) async {
    try {
      final ch = await OfficeChannel.open(
        identity: identity,
        peer: peer,
        host: host,
        port: port,
      );
      _channel = ch;
      final answer = Completer<Map<String, Object?>>();
      _listen = ch.messages.listen((m) {
        if (!answer.isCompleted) {
          answer.complete(m);
        } else {
          _heardBySender(m);
        }
      }, onDone: () => _fail('Bağlantı kesildi.'));
      await ch.send({
        't': 'offer',
        'id': id,
        'files': [for (final f in files) f.toJson()],
        'note': note,
        if (meta.isNotEmpty) 'meta': meta,
      });
      _set(TransferState.offered);
      final m = await answer.future.timeout(const Duration(minutes: 3));
      if (m['t'] == 'decline') return _end(TransferState.declined, null);
      final have = m['have'];
      if (m['t'] != 'accept' || have is! List || have.length != files.length) {
        return _fail('Karşı cihaz anlaşılamadı.');
      }
      _set(TransferState.sending);
      for (var i = 0; i < files.length; i++) {
        final from = have[i] is int ? have[i] as int : 0;
        await _sendFile(i, from.clamp(0, files[i].size));
        if (finished) return;
      }
    } on TimeoutException {
      _fail('Karşı taraf yanıt vermedi.');
    } catch (e) {
      _fail('$e');
    }
  }

  Future<void> _sendFile(int i, int from) async {
    final ch = _channel!;
    _moved += from;
    final raf = await File(_paths[i]).open();
    try {
      await raf.setPosition(from);
      var at = from, sent = 0;
      while (at < files[i].size && !finished) {
        final bytes = await raf.read(piece);
        if (bytes.isEmpty) break;
        await ch.send({
          't': 'chunk',
          'f': i,
          'at': at,
          'd': base64Encode(bytes),
        });
        at += bytes.length;
        sent++;
        _moved += bytes.length;
        notifyListeners();
        // No more than [window] pieces on the way.
        while (!finished && sent - (_acked[i] ?? 0) >= window) {
          _ackWait = Completer<void>();
          await _ackWait!.future.timeout(const Duration(minutes: 1));
        }
      }
    } finally {
      await raf.close();
    }
    if (!finished) await ch.send({'t': 'end', 'f': i});
  }

  void _heardBySender(Map<String, Object?> m) {
    switch (m['t']) {
      case 'ack':
        final f = m['f'];
        if (f is int) _acked[f] = (_acked[f] ?? 0) + 1;
        _ackWait?.complete();
        _ackWait = null;
      case 'got':
        if (m['ok'] != true) {
          _fail('${files[m['f'] as int].name} bozuk ulaştı; yeniden gönderin.');
        } else if (m['f'] == files.length - 1) {
          _end(TransferState.done, null);
        }
      default:
        _fail('Karşı cihaz anlaşılamadı.');
    }
  }

  // Receiving.

  Directory? _folder;
  int _file = 0;
  IOSink? _part;
  int _partLength = 0;

  /// An offer a known device made over [channel]; the user is asked unless
  /// [accepted] says it was taken before and is going on.
  static OfficeTransfer? receive({
    required OfficeChannel channel,
    required Map<String, Object?> offer,
    required Directory folder,
    void Function(OfficeTransfer)? onEnd,
  }) {
    final id = offer['id'];
    final list = offer['files'];
    if (id is! String || !RegExp(r'^[0-9a-f]{8,64}$').hasMatch(id)) return null;
    if (list is! List || list.isEmpty || list.length > 500) return null;
    final files = <TransferFile>[];
    for (final j in list) {
      final f = TransferFile.fromJson(j);
      if (f == null) return null;
      files.add(f);
    }
    final note = offer['note'];
    final t = OfficeTransfer._(
      id: id,
      outgoing: false,
      peer: channel.peer,
      files: files,
      note: note is String ? note : '',
      at: DateTime.now(),
      meta: {
        if (offer['meta'] case final Map m)
          for (final e in m.entries)
            if (e.value is String) '${e.key}': e.value,
      },
    );
    t._channel = channel;
    t._folder = folder;
    t._onEnd = onEnd;
    t._state = TransferState.offered;
    t._listen = channel.messages.listen(
      t._heardByReceiver,
      onDone: () => t._fail('Bağlantı kesildi.'),
    );
    return t;
  }

  Directory get _parts => Directory(p.join(_folder!.path, '.folio-parca'));
  File _partOf(int i) => File(p.join(_parts.path, '$id-$i.part'));

  /// Where a file that came whole was put: so that, offered again after a
  /// cut, it is neither asked for nor written twice.
  File _doneOf(int i) => File(p.join(_parts.path, '$id-$i.done'));

  Future<String?> _cameTo(int i) async {
    try {
      final path = await _doneOf(i).readAsString();
      return await File(path).exists() ? path : null;
    } catch (_) {
      return null;
    }
  }

  /// The user takes the files: what came of them before is not asked again.
  Future<void> accept() async {
    if (_state != TransferState.offered || outgoing) return;
    await _parts.create(recursive: true);
    final have = <int>[];
    for (var i = 0; i < files.length; i++) {
      final came = await _cameTo(i);
      if (came != null) {
        have.add(files[i].size);
        if (!saved.contains(came)) saved.add(came);
        continue;
      }
      final part = _partOf(i);
      have.add(await part.exists() ? await part.length() : 0);
    }
    _file = -1;
    _moved = have.fold(0, (a, b) => a + b);
    _set(TransferState.sending);
    await _channel?.send({'t': 'accept', 'have': have});
  }

  Future<void> decline() async {
    if (finished) return;
    await _channel?.send({'t': 'decline'});
    _end(TransferState.declined, null);
  }

  // Written one message at a time, in order.
  Future<void> _writing = Future.value();

  void _heardByReceiver(Map<String, Object?> m) => _writing = _writing.then((
    _,
  ) async {
    if (finished || _state != TransferState.sending) return;
    final f = m['f'];
    if (f is! int || f < 0 || f >= files.length) {
      return _fail('Karşı cihaz anlaşılamadı.');
    }
    switch (m['t']) {
      case 'chunk':
        final at = m['at'], d = m['d'];
        if (_part == null || _file != f) {
          await _part?.close();
          final part = _partOf(f);
          _partLength = await part.exists() ? await part.length() : 0;
          _part = part.openWrite(mode: FileMode.append);
          _file = f;
        }
        if (at != _partLength || d is! String) {
          return _fail('Parçalar sırasız geldi.');
        }
        final bytes = base64Decode(d);
        if (_partLength + bytes.length > files[f].size) {
          return _fail('Dosya söylenenden büyük geldi.');
        }
        _part!.add(bytes);
        _partLength += bytes.length;
        _moved += bytes.length;
        notifyListeners();
        await _channel?.send({'t': 'ack', 'f': f});
      case 'end':
        await _part?.close();
        _part = null;
        if (await _cameTo(f) != null) {
          await _channel?.send({'t': 'got', 'f': f, 'ok': true});
          if (f == files.length - 1 && saved.length == files.length) _done();
          return;
        }
        final part = _partOf(f);
        // An empty file has no pieces, and so no part yet.
        if (!await part.exists()) await part.create(recursive: true);
        final ok =
            await part.length() == files[f].size &&
            await sha256Of(part) == files[f].sha256;
        if (!ok) {
          if (await part.exists()) await part.delete();
          await _channel?.send({'t': 'got', 'f': f, 'ok': false});
          return _fail('${files[f].name} bozuk geldi ve silindi.');
        }
        final target = _unique(files[f].name);
        await part.rename(target.path);
        await _doneOf(f).writeAsString(target.path, flush: true);
        saved.add(target.path);
        await _channel?.send({'t': 'got', 'f': f, 'ok': true});
        if (f == files.length - 1 && saved.length == files.length) _done();
      default:
        _fail('Karşı cihaz anlaşılamadı.');
    }
  });

  File _unique(String name) {
    final base = p.basenameWithoutExtension(name), ext = p.extension(name);
    var file = File(p.join(_folder!.path, name));
    for (var n = 2; file.existsSync(); n++) {
      file = File(p.join(_folder!.path, '$base ($n)$ext'));
    }
    return file;
  }

  void _fail(String reason) => _end(TransferState.failed, reason);

  /// All came: the marks of what came are no longer needed.
  void _done() {
    for (var i = 0; i < files.length; i++) {
      try {
        _doneOf(i).deleteSync();
      } catch (_) {}
    }
    _end(TransferState.done, null);
  }

  void _end(TransferState state, String? reason) {
    if (finished) return;
    _reason = reason;
    _set(state);
    _ackWait?.completeError(StateError('ended'));
    _ackWait = null;
    unawaited(_listen?.cancel());
    unawaited(_part?.close());
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 300))
          .then((_) => _channel?.close()),
    );
    _onEnd?.call(this);
  }

  void _set(TransferState s) {
    _state = s;
    notifyListeners();
  }

  /// For the transfers' record.
  Map<String, Object?> toJson() => {
    'id': id,
    'yon': outgoing ? 'giden' : 'gelen',
    'kisi': peer.name,
    'cihaz': peer.device,
    'dosyalar': [for (final f in files) f.name],
    'boyut': total,
    'not': note,
    'at': at.toUtc().toIso8601String(),
    'durum': _state.name,
    'yollar': saved,
    if (_reason != null) 'neden': _reason,
  };
}

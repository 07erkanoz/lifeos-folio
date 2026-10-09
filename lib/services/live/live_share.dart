import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show ChangeSource, Document, Embed;
import 'package:flutter_quill/quill_delta.dart';

import '../../models/document_model.dart';
import '../editor/doc_model_json.dart';
import '../office/office_channel.dart';
import '../office/office_network.dart';
import '../office/office_known.dart';

/// A document shared live (the editor's live sharing): the device it is
/// open on streams it to the devices it chose, which see it change as it
/// is written, read-only. The document stays where it is open; the others
/// are shown it, and nothing of it stays with them when it ends.
///
/// The words on the channel (`tip`), each in order on its channel:
/// - from the sharer: `tam` the whole of it at a revision (the body's
///   delta and the blocks its embeds point at), `d` a change of the body
///   taking it to the next revision, `t` a table changed, `s` the writer's
///   selection, `nabiz` still there, `son` the end; `hak` what the viewer
///   may do now, `kalem` who holds the pen (`sende` the viewer itself),
///   `onay` its written change went in at a revision, `red` it did not
///   (the whole follows);
/// - from a viewer: `hazir` ready, `tamiste` the whole again (a change it
///   could not apply), `nabiz`, `ayrildi` gone; with the right to write in
///   turn, `kalemiste` asking for the pen, `kalembirak` giving it back,
///   and holding it `yaz` a change made on the revision `taban`, `s` its
///   selection.
///
/// Written in turn: one holds the pen at a time, the sharer when no one
/// else does. The document stays the sharer's: a change written elsewhere
/// is checked and put in there, then goes to the others as the sharer's
/// own would. The sharer touching it takes the pen back.
/// A word too long for one line goes in `parca`s, its bytes in base64.
const liveKind = 'canli';

/// What a viewer may do: see it, or also write in it in turn.
enum LiveRight { view, edit }

enum LivePeerState { joining, watching, gone, unreachable }

/// One the document is shared with, and how far it has come.
class LivePeer {
  const LivePeer({
    required this.deviceId,
    required this.name,
    this.right = LiveRight.view,
    this.state = LivePeerState.joining,
  });

  final String deviceId, name;
  final LiveRight right;
  final LivePeerState state;

  LivePeer copyWith({LivePeerState? state, LiveRight? right}) => LivePeer(
    deviceId: deviceId,
    name: name,
    right: right ?? this.right,
    state: state ?? this.state,
  );
}

/// A word's bytes at most in one line: sealed, written in base64 twice and
/// wrapped, it stays well within the channel's megabyte a line.
const _piece = 256 * 1024;

/// The most a word may be put together from: a document with its pictures.
const _maxWord = 64 * 1024 * 1024;

/// A word larger than a viewer would put together.
class _TooLarge implements Exception {
  const _TooLarge();
}

/// The words of one word, itself or its pieces, and their bytes.
({List<Map<String, Object?>> words, int bytes}) _words(
  Map<String, Object?> word,
  int id,
) {
  final bytes = utf8.encode(jsonEncode(word));
  if (bytes.length > _maxWord) throw const _TooLarge();
  if (bytes.length <= _piece) return (words: [word], bytes: bytes.length);
  final n = (bytes.length / _piece).ceil();
  final words = [
    for (var i = 0; i < n; i++)
      {
        'tip': 'parca',
        'id': id,
        'i': i,
        'n': n,
        'veri': base64Encode(
          bytes.sublist(
            i * _piece,
            (i + 1) * _piece > bytes.length ? bytes.length : (i + 1) * _piece,
          ),
        ),
      },
  ];
  return (words: words, bytes: (bytes.length * 4 / 3).ceil() + n * 64);
}

/// Words put together again from their pieces; a broken word is said so.
class _Assembler {
  Object? _id;
  int _n = 0, _bytes = 0;
  final _parts = <int, List<int>>{};

  /// When the word being put together began; null while none is.
  DateTime? begun;

  void clear() {
    begun = null;
    _id = null;
    _n = 0;
    _bytes = 0;
    _parts.clear();
  }

  /// The word [m] is or completes; null while pieces are to come. Throws
  /// [FormatException] for pieces that cannot make a word.
  Map<String, Object?>? take(Map<String, Object?> m) {
    if (m['tip'] != 'parca') return m;
    final id = m['id'], i = m['i'], n = m['n'], data = m['veri'];
    if (i is! int || n is! int || data is! String || n < 1) {
      throw const FormatException('parça');
    }
    if (id != _id) {
      // A word begun anew: the one before was not finished, and is gone.
      clear();
      _id = id;
      _n = n;
      begun = DateTime.now();
    }
    if (n != _n || i < 0 || i >= n || _parts.containsKey(i)) {
      clear();
      throw const FormatException('parça sırası');
    }
    final bytes = base64Decode(data);
    _bytes += bytes.length;
    if (_bytes > _maxWord || n * _piece > _maxWord + _piece) {
      clear();
      throw const FormatException('parça boyu');
    }
    _parts[i] = bytes;
    if (_parts.length < n) return null;
    final all = <int>[for (var k = 0; k < n; k++) ..._parts[k]!];
    clear();
    final word = jsonDecode(utf8.decode(all));
    if (word is! Map) throw const FormatException('söz');
    return word.cast<String, Object?>();
  }
}

/// The document as it stands, to be shown whole: its body as the editor
/// holds it, and the blocks its embeds point at.
typedef LiveSnapshot = ({List<Object?> delta, List<DocBlock> blocks});

/// One viewer of the sharer's: its channel, and what is still to go on it,
/// sent one word (all its pieces) after another.
class _Viewer {
  _Viewer(this.channel, [this.grant]);

  final OfficeChannel channel;

  /// The guest's grant it was shown under, if a guest.
  final KnownDevice? grant;
  Future<void> queue = Future.value();
  bool ready = false;

  /// Bytes waiting to go: a viewer too far behind is given the whole
  /// again, once it has caught up, rather than every change.
  int waiting = 0;
  bool behind = false;

  /// The whole is to go, taken once the editor has told every change it
  /// made: the changes until then are in it, and do not go on their own.
  bool wholePending = false;

  /// A whole on its way, and another asked for meanwhile: that one is
  /// taken when this one has gone, one at a time, the changes waiting.
  bool wholeOnWay = false, wholeAgain = false;
  DateTime heard = DateTime.now();
}

/// The side the document is open on.
class LiveShareHost {
  LiveShareHost({
    required this.title,
    required this.snapshot,
    required this.blockCount,
    OfficeNetwork? network,
    this.heartbeat = const Duration(seconds: 10),
    this.apply,
  }) : _net = network ?? OfficeNetwork.instance;

  /// Puts a change written by the one holding the pen in the document
  /// where it is open; false when it may not go in (see [acceptable]).
  /// No one is given the pen without it.
  bool Function(Delta change)? apply;

  /// Who holds the pen: null, the sharer.
  final pen = ValueNotifier<String?>(null);

  /// Who asked for the pen, the first first.
  final asking = ValueNotifier<List<String>>(const []);

  /// How long the pen stays with one who writes nothing.
  Duration penIdle = const Duration(minutes: 2);
  Timer? _idle;
  final _rights = <String, LiveRight>{};

  /// The most a change written elsewhere may be, put in one go.
  static const _maxWrite = 2 * 1024 * 1024;

  /// Whether [change], written by another, may go in [doc]: words and
  /// their marks put in, kept or taken out; nothing but words put in (no
  /// picture, no table), no table or picture taken out, nothing past the
  /// end.
  static bool acceptable(Delta change, Document doc) {
    var index = 0;
    final length = doc.length;
    for (final op in change.operations) {
      final n = op.length ?? 0;
      if (!_plain(op.attributes)) return false;
      if (op.isInsert) {
        if (op.data is! String) return false;
      } else if (op.isDelete) {
        if (index + n > length) return false;
        var at = index;
        while (at < index + n) {
          final leaf = doc.querySegmentLeafNode(at).leaf;
          if (leaf == null) return false;
          if (leaf is Embed) return false;
          final next = leaf.documentOffset + leaf.length;
          if (next <= at) return false;
          at = next;
        }
        index += n;
      } else {
        index += n;
        if (index > length) return false;
      }
    }
    return true;
  }

  static bool _plain(Map<String, dynamic>? attributes) {
    if (attributes == null) return true;
    if (attributes.length > 24) return false;
    for (final e in attributes.entries) {
      if (e.key.length > 64) return false;
      final v = e.value;
      if (v != null && v is! String && v is! num && v is! bool) return false;
      if (v is String && v.length > 512) return false;
    }
    return true;
  }

  /// [deviceId] by the name it is shown it under.
  String nameOf(String deviceId) => _nameOf(deviceId);

  String _nameOf(String deviceId) =>
      peers.value.where((p) => p.deviceId == deviceId).firstOrNull?.name ??
      'Biri';

  /// The name of who holds the pen; null while the sharer does.
  String? get penName => pen.value == null ? null : _nameOf(pen.value!);

  /// What [deviceId] may do: see it, or write in it in turn.
  LiveRight rightOf(String deviceId) => _rights[deviceId] ?? LiveRight.view;

  /// [deviceId] may now do [right]; told at once if it watches. One that
  /// may only see it no more holds the pen or asks for it.
  void setRight(String deviceId, LiveRight right) {
    if (_closed) return;
    _rights[deviceId] = right;
    peers.value = [
      for (final p in peers.value)
        if (p.deviceId == deviceId) p.copyWith(right: right) else p,
    ];
    if (right == LiveRight.view) {
      _unask(deviceId);
      if (pen.value == deviceId) takeBack();
    }
    final v = _viewers[deviceId];
    if (v != null && v.ready) _enqueue(v, {'tip': 'hak', 'hak': right.name});
  }

  void _unask(String deviceId) {
    if (!asking.value.contains(deviceId)) return;
    asking.value = [
      for (final a in asking.value)
        if (a != deviceId) a,
    ];
  }

  /// The pen to [deviceId], if it may write and watches: the sharer's
  /// document is only read here meanwhile.
  bool give(String deviceId) {
    final v = _viewers[deviceId];
    if (_closed || apply == null || v == null || !v.ready) return false;
    if (rightOf(deviceId) != LiveRight.edit) return false;
    _unask(deviceId);
    pen.value = deviceId;
    _penTold();
    _stillWriting();
    return true;
  }

  /// [deviceId]'s asking for the pen turned down.
  void turnDown(String deviceId) => _unask(deviceId);

  /// The pen back with the sharer; a change still on its way from the one
  /// who held it is not put in.
  void takeBack() {
    if (pen.value == null) return;
    _idle?.cancel();
    _idle = null;
    pen.value = null;
    if (!_closed) _penTold();
  }

  void _stillWriting() {
    _idle?.cancel();
    _idle = Timer(penIdle, takeBack);
  }

  Map<String, Object?> _penWord(String? deviceId) => {
    'tip': 'kalem',
    'sende': deviceId != null && pen.value == deviceId,
    'kimde': penName ?? '',
  };

  void _penTold() {
    for (final e in _viewers.entries) {
      if (e.value.ready) _enqueue(e.value, _penWord(e.key));
    }
  }

  /// A change [deviceId] wrote: put in if it holds the pen and wrote it on
  /// the document as it stands here; else turned down, the whole sent.
  void _written(String deviceId, _Viewer v, Map<String, Object?> m) {
    final base = m['taban'], d = m['delta'];
    void refuse() {
      _enqueue(v, const {'tip': 'red'});
      _sendWhole(v);
    }

    if (_closed ||
        pen.value != deviceId ||
        rightOf(deviceId) != LiveRight.edit ||
        base is! int ||
        d is! List ||
        base != _rev) {
      return refuse();
    }
    final Delta change;
    try {
      if (utf8.encode(jsonEncode(d)).length > _maxWrite) return refuse();
      change = Delta.fromJson(d);
    } catch (_) {
      return refuse();
    }
    final put = apply;
    var went = false;
    try {
      went = put != null && put(change);
    } catch (_) {
      went = false;
    }
    if (!went) return refuse();
    _stillWriting();
    _rev++;
    for (final e in _viewers.entries) {
      final o = e.value;
      if (!o.ready) continue;
      _enqueue(
        o,
        identical(o, v)
            ? {'tip': 'onay', 'rev': _rev}
            : {'tip': 'd', 'rev': _rev, 'delta': d},
        change: true,
      );
    }
  }

  /// Where the one holding the pen is, to the others.
  void _theirSelection(String deviceId, Object? s) {
    if (pen.value != deviceId) return;
    if (s is! List || s.length != 2 || s[0] is! int || s[1] is! int) return;
    _selection = (base: s[0] as int, extent: s[1] as int);
    final word = {'tip': 's', 's': s};
    for (final e in _viewers.entries) {
      if (e.key != deviceId && e.value.ready) {
        _enqueue(e.value, word, change: true);
      }
    }
  }

  final String title;
  final LiveSnapshot Function() snapshot;

  /// How many blocks the body's embeds point at now: one more, a table
  /// put in, and the whole goes, the table with it.
  final int Function() blockCount;
  final OfficeNetwork _net;
  final Duration heartbeat;

  /// Who it is shared with, as they come and go.
  final peers = ValueNotifier<List<LivePeer>>(const []);
  final _viewers = <String, _Viewer>{};

  /// Each device's invitation, counted: one withdrawn or made again while
  /// it was being made is not let through when its channel comes.
  final _invitations = <String, int>{};
  int _rev = 0, _blocksSent = -1, _wordId = 0;
  Timer? _selectionTimer, _tableTimer, _pulse;
  ({int base, int extent})? _selection;
  final _tables = <int, DocBlock>{};
  bool _closed = false;

  bool get closed => _closed;

  /// Guests shown it, by the grant each came with: that grant forgotten
  /// by the network when they go, not one made since.
  final _guestIds = <String, KnownDevice>{};

  /// Every guest it was shown to, gone or not: listed as a guest still.
  final _wereGuests = <String>{};

  /// Whether [deviceId] is, or was, a guest shown it.
  bool isGuest(String deviceId) => _wereGuests.contains(deviceId);

  /// Whether guests may ask to be shown it now (Misafir): only one
  /// document takes them at a time, the last to be set to.
  bool get takingGuests => !_closed && identical(_net.guestOwner, this);

  /// Guests taken (or no longer): one the lawyer accepts, its code seen
  /// on both screens, is shown the document at once.
  Future<void> takeGuests(bool take) async {
    if (take && !_closed) {
      await _net.openToGuests(
        this,
        title: title,
        onGuest: (grant, name, office) {
          final named = [
            if (name.isNotEmpty) name else 'Misafir',
            if (office.isNotEmpty) '($office)',
          ].join(' ');
          unawaited(invite(grant.deviceId, named, guest: grant));
        },
      );
    } else {
      await _net.closeToGuests(this);
    }
  }

  bool get sharing =>
      !_closed &&
      peers.value.any(
        (p) =>
            p.state == LivePeerState.joining ||
            p.state == LivePeerState.watching,
      );

  void _set(String deviceId, LivePeerState state) {
    peers.value = [
      for (final p in peers.value)
        if (p.deviceId == deviceId) p.copyWith(state: state) else p,
    ];
  }

  /// [deviceId] shown the document: one of the person's own, or with
  /// [office] a member of the office's (KVKK: only the one chosen).
  Future<bool> invite(
    String deviceId,
    String name, {
    bool office = false,
    KnownDevice? guest,
  }) async {
    if (_closed || _viewers.containsKey(deviceId)) {
      // Not shown it: the guest's grant not kept for nothing.
      if (guest != null) await _net.forgetGuest(deviceId, guest);
      return false;
    }
    final mine = (_invitations[deviceId] ?? 0) + 1;
    _invitations[deviceId] = mine;
    if (guest != null) {
      final before = _guestIds[deviceId];
      if (before != null && !identical(before, guest)) {
        await _net.forgetGuest(deviceId, before);
      }
      _guestIds[deviceId] = guest;
      _wereGuests.add(deviceId);
    }
    peers.value = [
      for (final p in peers.value)
        if (p.deviceId != deviceId) p,
      LivePeer(deviceId: deviceId, name: name, right: rightOf(deviceId)),
    ];
    var tried = await _net.openStream(
      deviceId,
      liveKind,
      body: {'baslik': title, 'izin': rightOf(deviceId).name},
      office: office,
      guest: guest != null,
    );
    // A guest may not yet have taken this Folio in when it is reached
    // (its pairing's last word and this channel go apart): tried again a
    // few times.
    for (final wait in const [200, 600, 1500]) {
      if (tried != null || guest == null || _closed) break;
      if (_invitations[deviceId] != mine) break;
      await Future<void>.delayed(Duration(milliseconds: wait));
      tried = await _net.openStream(
        deviceId,
        liveKind,
        body: {'baslik': title, 'izin': rightOf(deviceId).name},
        guest: true,
      );
    }
    final ch = tried;
    if (_closed || _invitations[deviceId] != mine) {
      // Withdrawn, or made again, while it was being made.
      if (ch != null) unawaited(_shut(ch));
      if (guest != null) await _forgetGuest(deviceId, guest);
      return false;
    }
    if (ch == null) {
      _set(deviceId, LivePeerState.unreachable);
      if (guest != null) await _forgetGuest(deviceId, guest);
      return false;
    }
    final v = _Viewer(ch, guest);
    _viewers[deviceId] = v;
    _pulse ??= Timer.periodic(heartbeat, (_) => _beat());
    final assembler = _Assembler();
    ch.messages.listen(
      (raw) {
        v.heard = DateTime.now();
        try {
          final m = assembler.take(raw);
          switch (m?['tip']) {
            case 'hazir':
              v.ready = true;
              _set(deviceId, LivePeerState.watching);
              _sendWhole(v);
            case 'tamiste':
              _sendWhole(v);
            case 'ayrildi':
              unawaited(_drop(deviceId, ch));
            case 'kalemiste':
              if (rightOf(deviceId) == LiveRight.edit &&
                  apply != null &&
                  pen.value != deviceId &&
                  !asking.value.contains(deviceId)) {
                asking.value = [...asking.value, deviceId];
              }
            case 'kalembirak':
              if (pen.value == deviceId) takeBack();
            case 'yaz':
              if (identical(_viewers[deviceId], v)) _written(deviceId, v, m!);
            case 's':
              _theirSelection(deviceId, m!['s']);
          }
        } catch (_) {
          unawaited(_drop(deviceId, ch));
        }
      },
      onDone: () => _drop(deviceId, ch),
      onError: (Object _) => _drop(deviceId, ch),
    );
    // Not ready in a while: not there.
    Timer(const Duration(seconds: 20), () {
      if (identical(_viewers[deviceId], v) && !v.ready) {
        unawaited(_drop(deviceId, ch, LivePeerState.unreachable));
      }
    });
    return true;
  }

  /// [ch] of [deviceId] dropped: only that channel, not one made since.
  Future<void> _drop(
    String deviceId,
    OfficeChannel ch, [
    LivePeerState state = LivePeerState.gone,
  ]) async {
    final v = _viewers[deviceId];
    if (v == null || !identical(v.channel, ch)) return;
    _viewers.remove(deviceId);
    _set(deviceId, state);
    _unask(deviceId);
    if (pen.value == deviceId) takeBack();
    await _shut(ch);
    if (v.grant != null) await _forgetGuest(deviceId, v.grant);
  }

  static Future<void> _shut(OfficeChannel ch) async {
    if (ch.closed) return;
    try {
      await ch.close().timeout(const Duration(seconds: 3), onTimeout: () {});
    } catch (_) {}
  }

  String? _idOf(_Viewer v) => _viewers.entries
      .where((e) => identical(e.value, v))
      .map((e) => e.key)
      .firstOrNull;

  /// [word] put after what is still to go to [v], all its pieces at once,
  /// and waited on until it has gone out: a slow viewer holds the next
  /// word back, not memory.
  void _enqueue(_Viewer v, Map<String, Object?> word, {bool change = false}) {
    if (_closed || v.channel.closed) return;
    if (change && (v.behind || v.wholePending || v.wholeAgain)) return;
    final ({List<Map<String, Object?>> words, int bytes}) out;
    try {
      out = _words(word, ++_wordId);
    } catch (_) {
      // Larger than a viewer takes: not shown at all.
      final id = _idOf(v);
      if (id != null) {
        unawaited(_drop(id, v.channel, LivePeerState.unreachable));
      }
      return;
    }
    v.waiting += out.bytes;
    if (change && v.waiting > 8 * 1024 * 1024) {
      // Too far behind: the changes stop, and the whole goes once what is
      // on its way has gone.
      v.behind = true;
    }
    v.queue = v.queue.then((_) async {
      try {
        for (final w in out.words) {
          if (_closed || v.channel.closed) return;
          await v.channel.send(w);
        }
        await v.channel.drain().timeout(const Duration(seconds: 30));
      } catch (_) {
        final id = _idOf(v);
        if (id != null) unawaited(_drop(id, v.channel));
      } finally {
        v.waiting -= out.bytes;
        if (v.behind && v.waiting <= 0) {
          v.behind = false;
          _sendWhole(v);
        }
      }
    });
  }

  /// The whole of it to [v], taken in a moment: once the editor has told
  /// every change it made, so that the whole is the document at the
  /// revision it says and the changes after it are the ones put after it.
  /// Asked again before it is taken: the one taking does.
  void _sendWhole(_Viewer v) {
    if (v.wholePending || _closed) return;
    if (v.wholeOnWay) {
      v.wholeAgain = true;
      return;
    }
    v.wholePending = true;
    Timer.run(() {
      v.wholePending = false;
      if (_closed || v.channel.closed || _idOf(v) == null) return;
      try {
        final s = snapshot();
        _blocksSent = s.blocks.length;
        v.wholeOnWay = true;
        _enqueue(v, {
          'tip': 'tam',
          'rev': _rev,
          'baslik': title,
          'delta': s.delta,
          'bloklar': DocModelJson.encode(DocModel(blocks: s.blocks)),
          if (_selection case final sel?) 's': [sel.base, sel.extent],
          'hak': rightOf(_idOf(v) ?? '').name,
          'kalem': _penWord(_idOf(v)),
        });
        v.queue = v.queue.then((_) {
          v.wholeOnWay = false;
          if (v.wholeAgain) {
            v.wholeAgain = false;
            _sendWhole(v);
          }
        });
      } catch (_) {
        final id = _idOf(v);
        if (id != null) unawaited(_drop(id, v.channel));
      }
    });
  }

  Iterable<_Viewer> get _ready => _viewers.values.where((v) => v.ready);

  /// A change of the body, as the editor made it.
  void body(Delta change) {
    if (_closed || _viewers.isEmpty) return;
    // The sharer wrote: the pen is theirs again.
    takeBack();
    _rev++;
    if (blockCount() != _blocksSent) {
      // A table put in or taken out: its block goes with the whole.
      _wholeForAll();
      return;
    }
    final word = {'tip': 'd', 'rev': _rev, 'delta': change.toJson()};
    // A viewer whose whole is still to be taken has this change in it.
    for (final v in _ready) {
      _enqueue(v, word, change: true);
    }
  }

  /// Table [index] (an embed's block) changed: sent within a moment, the
  /// last of a burst of keystrokes in a cell.
  void table(int index, DocBlock block) {
    if (_closed || _viewers.isEmpty) return;
    _tables[index] = block;
    _tableTimer ??= Timer(const Duration(milliseconds: 150), () {
      _tableTimer = null;
      final changed = Map.of(_tables);
      _tables.clear();
      for (final e in changed.entries) {
        final word = {
          'tip': 't',
          'i': e.key,
          'blok': DocModelJson.encode(DocModel(blocks: [e.value])),
        };
        for (final v in _ready) {
          _enqueue(v, word, change: true);
        }
      }
    });
  }

  /// Something the body's changes do not carry: the whole again.
  void whole() {
    if (_closed || _viewers.isEmpty) return;
    takeBack();
    _rev++;
    _wholeForAll();
  }

  /// The whole to every viewer; a table's change waiting to go is in it,
  /// and does not go after it over what may be another table by then.
  void _wholeForAll() {
    _tableTimer?.cancel();
    _tableTimer = null;
    _tables.clear();
    for (final v in _ready) {
      _sendWhole(v);
    }
  }

  /// Where the writer is; sent at most a few times a second.
  void selection(int base, int extent) {
    // The one writing's selection is shown meanwhile, not the sharer's.
    if (pen.value != null) return;
    _selection = (base: base, extent: extent);
    if (_closed || _viewers.isEmpty || _selectionTimer != null) return;
    _selectionTimer = Timer(const Duration(milliseconds: 120), () {
      _selectionTimer = null;
      final sel = _selection;
      if (sel == null) return;
      final word = {
        'tip': 's',
        's': [sel.base, sel.extent],
      };
      for (final v in _ready) {
        _enqueue(v, word, change: true);
      }
    });
  }

  /// Still there, both ways: a viewer not heard from in over three beats
  /// is taken as gone.
  void _beat() {
    final now = DateTime.now();
    for (final e in _viewers.entries.toList()) {
      if (now.difference(e.value.heard) > heartbeat * 3.5) {
        unawaited(_drop(e.key, e.value.channel));
        continue;
      }
      _enqueue(e.value, const {'tip': 'nabiz'});
    }
  }

  /// The guest's grant let go: [only] that one, if given.
  Future<void> _forgetGuest(String deviceId, [KnownDevice? only]) async {
    final grant = _guestIds[deviceId];
    if (grant == null || (only != null && !identical(grant, only))) return;
    _guestIds.remove(deviceId);
    await _net.forgetGuest(deviceId, grant);
  }

  /// [deviceId] shown it no more.
  Future<void> remove(String deviceId) async {
    _invitations[deviceId] = (_invitations[deviceId] ?? 0) + 1;
    final v = _viewers.remove(deviceId);
    peers.value = [
      for (final p in peers.value)
        if (p.deviceId != deviceId) p,
    ];
    _unask(deviceId);
    if (pen.value == deviceId) takeBack();
    // The grant it was shown under, taken now: one made while saying
    // goodbye is not this one.
    final grant = _guestIds[deviceId];
    if (v != null) await _farewell(v.channel);
    if (grant != null) await _forgetGuest(deviceId, grant);
  }

  static Future<void> _farewell(OfficeChannel ch) async {
    try {
      await ch
          .send({'tip': 'son'})
          .timeout(const Duration(seconds: 2), onTimeout: () {});
    } catch (_) {}
    await _shut(ch);
  }

  /// The sharing ended for all: nothing more goes from the moment it is
  /// asked; the channels are closed together, none waiting on another.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // No guest taken from here on, before anything is waited for.
    unawaited(_net.closeToGuests(this));
    _selectionTimer?.cancel();
    _tableTimer?.cancel();
    _pulse?.cancel();
    _idle?.cancel();
    pen.value = null;
    asking.value = const [];
    for (final id in _invitations.keys.toList()) {
      _invitations[id] = _invitations[id]! + 1;
    }
    final viewers = _viewers.values.toList();
    _viewers.clear();
    peers.value = const [];
    await Future.wait([for (final v in viewers) _farewell(v.channel)]);
    for (final id in _guestIds.keys.toList()) {
      await _forgetGuest(id);
    }
  }
}

/// The side a shared document is shown on: the document as it stands,
/// kept up as its words come whether or not a page shows it, and let go
/// the moment the sharing ends.
class LiveSession extends ChangeNotifier {
  LiveSession._(
    this._channel,
    this.title,
    this.from,
    this.right, {
    this.asGuest = false,
  });

  final OfficeChannel _channel;
  final String title;

  /// The device it comes from.
  String get fromDevice => _channel.peer.deviceId;

  /// Shown to this Folio as a guest, which asked for it by a code: opened
  /// by the asking, not told of.
  final bool asGuest;

  /// The device or person it comes from, as they are named here.
  final String from;

  /// What this side may do: the sharer may change it while it is shown.
  LiveRight right;

  /// Whether this side holds the pen: what is written here goes in the
  /// sharer's document.
  bool holding = false;

  /// Who else holds the pen, by name; null while the sharer does.
  String? penWith;

  /// Asked for the pen and not yet given it, nor turned down.
  bool askedPen = false;

  /// Changes written here and sent, not yet said to have gone in.
  int _pending = 0;
  Timer? _selectionSoon;
  ({int base, int extent})? _mySelection;

  /// The document as it stands here; null until shown whole, and after
  /// the end.
  Document? document;
  List<DocBlock> blocks = const [];

  /// Counted up each time [document] is the whole anew: a page shows it
  /// afresh then, and applies [changes] otherwise.
  int whole = 0;
  int _rev = -1;
  bool _waitingWhole = false;

  /// The writer's selection, offsets into the body.
  ({int base, int extent})? selection;

  final _changes = StreamController<Delta>.broadcast();

  /// The body's changes as they are applied to [document], for a page
  /// showing a copy of it.
  Stream<Delta> get changes => _changes.stream;
  bool ended = false;
  bool get ready => document != null;

  final _assembler = _Assembler();
  StreamSubscription<Map<String, Object?>>? _listen;
  Timer? _pulse;
  DateTime _heard = DateTime.now();

  DateTime _begun = DateTime.now();
  DateTime? _askedAt;

  void _start(Duration heartbeat) {
    _begun = DateTime.now();
    _listen = _channel.messages.listen(
      (raw) {
        _heard = DateTime.now();
        Map<String, Object?>? m;
        try {
          m = _assembler.take(raw);
        } catch (_) {
          _askWhole();
          return;
        }
        try {
          if (m != null) _take(m);
        } catch (_) {
          // A word that cannot be read: the sharing ends, nothing kept.
          _end();
        }
      },
      onDone: _end,
      onError: (Object _) => _end(),
    );
    _say({'tip': 'hazir'});
    _pulse = Timer.periodic(heartbeat, (_) {
      final now = DateTime.now();
      final late = heartbeat * 6;
      final begun = _assembler.begun;
      if (now.difference(_heard) > heartbeat * 3.5 ||
          // Never shown whole, a whole asked for and not come, a word
          // begun and not finished: not to be waited on for ever.
          (document == null && now.difference(_begun) > late) ||
          (_waitingWhole &&
              _askedAt != null &&
              now.difference(_askedAt!) > late) ||
          (begun != null && now.difference(begun) > late)) {
        _end();
      } else {
        _say({'tip': 'nabiz'});
      }
    });
  }

  void _say(Map<String, Object?> word) {
    if (ended || _channel.closed) return;
    unawaited(_channel.send(word).catchError((Object _) => _end()));
  }

  /// A change that could not be applied: the whole asked for once, and the
  /// changes until it comes let go.
  void _askWhole() {
    if (_waitingWhole) return;
    _waitingWhole = true;
    _askedAt = DateTime.now();
    _say({'tip': 'tamiste'});
  }

  void _take(Map<String, Object?> m) {
    if (ended) return;
    switch (m['tip']) {
      case 'tam':
        final d = m['delta'], rev = m['rev'];
        if (d is! List || rev is! int) return;
        // An older whole than what is here, overtaken: let go. Not while
        // changes written here wait: the whole is what they went into.
        if (rev < _rev && !_waitingWhole && _pending == 0) return;
        try {
          document = Document.fromDelta(Delta.fromJson(d));
        } catch (_) {
          _end();
          return;
        }
        blocks = DocModelJson.decode(m['bloklar'])?.blocks ?? const [];
        _rev = rev;
        _pending = 0;
        _waitingWhole = false;
        _selectionFrom(m['s']);
        _rightFrom(m['hak']);
        if (m['kalem'] case final Map<String, Object?> pen) _penFrom(pen);
        whole++;
        notifyListeners();
      case 'd':
        final rev = m['rev'], d = m['delta'], doc = document;
        if (rev is! int || d is! List || doc == null || _waitingWhole) return;
        if (rev <= _rev) return;
        // Another's change while this side's are on their way: out of
        // step, taken whole again.
        if (rev != _rev + 1 || _pending > 0) {
          _askWhole();
          return;
        }
        try {
          final change = Delta.fromJson(d);
          doc.compose(change, ChangeSource.remote);
          _rev = rev;
          _changes.add(change);
        } catch (_) {
          _askWhole();
        }
      case 't':
        final i = m['i'];
        final block = DocModelJson.decode(m['blok'])?.blocks.firstOrNull;
        if (i is! int || block == null || i < 0 || i >= blocks.length) return;
        blocks = [...blocks]..[i] = block;
        notifyListeners();
      case 's':
        if (holding) return;
        _selectionFrom(m['s']);
        notifyListeners();
      case 'hak':
        _rightFrom(m['hak']);
        notifyListeners();
      case 'kalem':
        _penFrom(m);
        notifyListeners();
      case 'onay':
        final rev = m['rev'];
        if (rev is! int || _pending == 0) return;
        _pending--;
        _rev = rev;
      case 'red':
        // Not put in: the whole that follows is the document as it is.
        _pending = 0;
        _waitingWhole = true;
        _askedAt = DateTime.now();
      case 'son':
        _end();
    }
  }

  void _rightFrom(Object? r) {
    final right = LiveRight.values.where((x) => x.name == r).firstOrNull;
    if (right == null) return;
    this.right = right;
    if (right == LiveRight.view) askedPen = false;
  }

  void _penFrom(Map<String, Object?> m) {
    final mine = m['sende'] == true;
    final who = m['kimde'];
    holding = mine;
    penWith = mine || who is! String || who.isEmpty ? null : who;
    if (mine || penWith != null) askedPen = false;
  }

  /// The pen asked for, if this side may write in turn.
  void askPen() {
    if (ended || right != LiveRight.edit || holding || askedPen) return;
    askedPen = true;
    _say({'tip': 'kalemiste'});
    notifyListeners();
  }

  /// The pen given back to the sharer.
  void releasePen() {
    if (ended || !holding) return;
    holding = false;
    _say({'tip': 'kalembirak'});
    notifyListeners();
  }

  /// [change], written here on [document] while holding the pen: put in
  /// it and sent to the sharer, on the revision it was written on. Not
  /// told on [changes]: the page that wrote it has it.
  void write(Delta change) {
    final doc = document;
    if (ended || !holding || doc == null || _waitingWhole) return;
    try {
      doc.compose(change, ChangeSource.local);
    } catch (_) {
      _askWhole();
      return;
    }
    final base = _rev + _pending;
    _pending++;
    _say({'tip': 'yaz', 'taban': base, 'delta': change.toJson()});
  }

  /// Where this side is while it holds the pen, for the others to see;
  /// sent at most a few times a second.
  void selectionMoved(int base, int extent) {
    if (!holding) return;
    _mySelection = (base: base, extent: extent);
    _selectionSoon ??= Timer(const Duration(milliseconds: 120), () {
      _selectionSoon = null;
      final sel = _mySelection;
      if (sel == null || !holding) return;
      _say({
        'tip': 's',
        's': [sel.base, sel.extent],
      });
    });
  }

  void _selectionFrom(Object? s) {
    if (s is List && s.length == 2 && s[0] is int && s[1] is int) {
      selection = (base: s[0] as int, extent: s[1] as int);
    }
  }

  /// The end: the document let go here, nothing of it kept.
  void _end() {
    if (ended) return;
    ended = true;
    holding = false;
    _selectionSoon?.cancel();
    _pulse?.cancel();
    unawaited(_listen?.cancel());
    if (!_channel.closed) unawaited(_channel.close());
    document = null;
    blocks = const [];
    selection = null;
    _assembler.clear();
    unawaited(_changes.close());
    LiveShare.instance._gone(this);
    notifyListeners();
  }

  /// Seen no more here.
  Future<void> leave() async {
    if (!ended && !_channel.closed) {
      try {
        await _channel
            .send({'tip': 'ayrildi'})
            .timeout(const Duration(seconds: 2), onTimeout: () {});
      } catch (_) {}
    }
    _end();
  }
}

/// The documents shared with this device now.
class LiveShare {
  LiveShare._();
  static final instance = LiveShare._();

  final incoming = ValueNotifier<List<LiveSession>>(const []);

  /// Whether [listen] was called: in Folio's main window alone, where the
  /// network is.
  bool listening = false;

  /// How often a viewer and the sharer tell each other they are there.
  Duration heartbeat = const Duration(seconds: 10);

  /// Listened for on [network]: from the person's own devices, and from
  /// the office's members; from no one else (the network lets no one
  /// else open a channel at all).
  void listen(OfficeNetwork network) {
    listening = true;
    network.streams[liveKind] =
        (ch, first, {required own, required member, required guest}) async {
          final from = ch.peer.deviceId;
          // A guest's host only when this Folio joined it, as a guest.
          if (!own && !member && !(guest && network.joinedAsGuest(from))) {
            await ch.close();
            return;
          }
          final name = own
              ? network.ownOnline
                    .where((p) => p.deviceId == from)
                    .map((p) => p.device)
                    .firstOrNull
              : member
              ? network.ledger.member(from)?.name
              : network.peerNamed(from);
          final session = LiveSession._(
            ch,
            '${first['baslik'] ?? 'Belge'}',
            (name ?? '').isEmpty
                ? (own ? 'Öbür cihazınız' : 'Bir meslektaşınız')
                : name!,
            LiveRight.values
                    .where((r) => r.name == first['izin'])
                    .firstOrNull ??
                LiveRight.view,
            asGuest: guest && !own && !member,
          );
          incoming.value = [...incoming.value, session];
          if (guest && !own && !member) {
            // Its host forgotten with it: nothing of the guest stays. Only
            // the grant it came under, not one a later joining made.
            final grant = network.guestGrant(from);
            session.addListener(() {
              if (session.ended && grant != null) {
                unawaited(network.forgetGuest(from, grant));
              }
            });
          }
          session._start(heartbeat);
        };
  }

  void _gone(LiveSession s) {
    incoming.value = [
      for (final x in incoming.value)
        if (!identical(x, s)) x,
    ];
  }
}

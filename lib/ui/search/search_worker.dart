import 'dart:async';
import 'dart:isolate';

import '../../services/uyap/uyap_web_service.dart';

/// What a search found, by places in what was loaded: the first
/// [SearchWorker.limit] of each group, and how many there are in all.
class SearchHits {
  const SearchHits({
    required this.cases,
    required this.casesTotal,
    required this.allCases,
    required this.parties,
    required this.partiesTotal,
    required this.documents,
    required this.documentsTotal,
  });

  /// Cases, the latest changed first.
  final List<int> cases;
  final int casesTotal;

  /// Every case found, the [cases] shown and those past them: their
  /// hearings are found too.
  final List<int> allCases;

  /// Parties by their folded name, the one in most cases first: a name,
  /// a role and the cases it is in.
  final List<({String name, String role, List<int> cases})> parties;
  final int partiesTotal;

  /// Documents, the newest first.
  final List<int> documents;
  final int documentsTotal;
}

/// The home page's search off the window's isolate (Codex, for a slow
/// 4 GB laptop): folding tens of thousands of documents' words, and going
/// through them at each letter, held the window. One worker, kept while
/// Folio runs; what it searches loaded again when the portfolio changes.
class SearchWorker {
  SearchWorker._(this._send, this._stop);

  final Future<Object?> Function(List<Object?>) _send;
  final void Function() _stop;
  bool _stopped = false;

  Future<Object?> _ask(List<Object?> message) {
    if (_stopped) return Future.error(StateError('arama durdu'));
    return _send(message);
  }

  /// At most this many of each group come back: the list shows five, and
  /// "tümünü göster" no more than these.
  static const limit = 100;

  /// Documents sent at a time: the copying of one message is the window's
  /// work, and a box's tens of thousands at once held it.
  static const _chunk = 2000;

  /// A worker on an isolate of its own. Stopped, or gone of itself (an
  /// error, the memory), what was asked of it fails, not waits for ever.
  static Future<SearchWorker> start() async {
    final ready = ReceivePort();
    final gone = RawReceivePort();
    final isolate = await Isolate.spawn(
      _main,
      ready.sendPort,
      onExit: gone.sendPort,
      onError: gone.sendPort,
      errorsAreFatal: true,
    );
    final port = await ready.first as SendPort;
    final waiting = <Completer<Object?>>{};
    late final SearchWorker worker;
    void end() {
      worker._stopped = true;
      gone.close();
      for (final c in [...waiting]) {
        if (!c.isCompleted) c.completeError(StateError('arama durdu'));
      }
      waiting.clear();
    }

    gone.handler = (_) => end();
    worker = SearchWorker._(
      (message) async {
        final reply = RawReceivePort();
        final answer = Completer<Object?>();
        waiting.add(answer);
        reply.handler = (Object? r) {
          if (!answer.isCompleted) answer.complete(r);
        };
        try {
          port.send([reply.sendPort, ...message]);
          return await answer.future;
        } finally {
          waiting.remove(answer);
          reply.close();
        }
      },
      () {
        isolate.kill(priority: Isolate.immediate);
        end();
      },
    );
    return worker;
  }

  /// The same, on this isolate: where no other can be awaited (a widget
  /// test's clock).
  factory SearchWorker.inline() {
    final core = _Core();
    late final SearchWorker worker;
    return worker = SearchWorker._(
      (message) async => core.handle(message),
      () => worker._stopped = true,
    );
  }

  int _loads = 0;

  /// What is searched from now on, in place of what was before; the load's
  /// number, for [find] to name.
  Future<int> load({
    required List<String> caseWords,
    required List<int> caseLasts,
    required List<int> partyCases,
    required List<String> partyNames,
    required List<String> partyRoles,
    required List<int> documentCases,
    required List<String> documentWords,
    required List<String> documentApproved,
    required List<String> documentSent,
  }) async {
    final id = ++_loads;
    await _ask([
      'bas',
      id,
      caseWords,
      caseLasts,
      partyCases,
      partyNames,
      partyRoles,
    ]);
    for (var at = 0; at < documentWords.length; at += _chunk) {
      final end = (at + _chunk).clamp(0, documentWords.length);
      await _ask([
        'evrak',
        id,
        documentWords.sublist(at, end),
        documentApproved.sublist(at, end),
        documentSent.sublist(at, end),
      ]);
    }
    await _ask(['bitir', id]);
    return id;
  }

  /// What the folded [words] are all found in, in load [id]; null when the
  /// worker holds another load by now.
  Future<SearchHits?> find(int id, List<String> words) async {
    final r = await _ask(['ara', id, words]);
    if (r is! List) return null;
    return SearchHits(
      cases: (r[0] as List).cast<int>(),
      casesTotal: r[1] as int,
      allCases: (r[6] as List).cast<int>(),
      parties: [
        for (final p in r[2] as List)
          (
            name: (p as List)[0] as String,
            role: p[1] as String,
            cases: (p[2] as List).cast<int>(),
          ),
      ],
      partiesTotal: r[3] as int,
      documents: (r[4] as List).cast<int>(),
      documentsTotal: r[5] as int,
    );
  }

  void stop() => _stop();
}

void _main(SendPort ready) {
  final inbox = ReceivePort();
  ready.send(inbox.sendPort);
  final core = _Core();
  inbox.listen((message) {
    final m = message as List;
    (m[0] as SendPort).send(core.handle(m.sublist(1)));
  });
}

/// The worker's work: what is loaded folded once, each search one pass.
class _Core {
  int _id = 0;
  bool _ready = false;
  var _cases = const <String>[];
  var _lasts = const <int>[];

  /// Parties by folded name: the name, as written and folded, its role
  /// and its cases.
  var _parties = <(String, String, String, Set<int>)>[];

  /// Documents: (place, folded words, date); in date order, newest first,
  /// once loaded.
  var _documents = <(int, String, int)>[];

  Object? handle(List<Object?> m) {
    final id = m[1] as int;
    switch (m[0]) {
      case 'bas':
        _id = id;
        _ready = false;
        _cases = [for (final w in m[2] as List) UyapWebService.fold('$w')];
        _lasts = (m[3] as List).cast<int>();
        final partyCases = (m[4] as List).cast<int>();
        final names = (m[5] as List).cast<String>();
        final roles = (m[6] as List).cast<String>();
        final byName = <String, (String, String, String, Set<int>)>{};
        for (var i = 0; i < names.length; i++) {
          final folded = UyapWebService.fold(names[i]);
          if (folded.isEmpty) continue;
          byName
              .putIfAbsent(folded, () => (names[i], folded, roles[i], <int>{}))
              .$4
              .add(partyCases[i]);
        }
        _parties = byName.values.toList();
        _documents = [];
        return true;
      case 'evrak':
        if (id != _id) return false;
        final words = (m[2] as List).cast<String>();
        final approved = (m[3] as List).cast<String>();
        final sent = (m[4] as List).cast<String>();
        for (var i = 0; i < words.length; i++) {
          final day = approved[i].isNotEmpty ? approved[i] : sent[i];
          _documents.add((
            _documents.length,
            UyapWebService.fold(words[i]),
            parseUyapDate(day)?.millisecondsSinceEpoch ?? 0,
          ));
        }
        return true;
      case 'bitir':
        if (id != _id) return false;
        _documents.sort((a, b) => b.$3.compareTo(a.$3));
        _ready = true;
        return true;
      case 'ara':
        if (id != _id || !_ready) return null;
        return _find((m[2] as List).cast<String>());
    }
    return null;
  }

  List<Object?> _find(List<String> words) {
    bool has(String folded) => words.every(folded.contains);
    final cases = [
      for (var i = 0; i < _cases.length; i++)
        if (has(_cases[i])) i,
    ]..sort((a, b) => _lasts[b].compareTo(_lasts[a]));
    final parties = [
      for (final p in _parties)
        if (has(p.$2)) p,
    ]..sort((a, b) => b.$4.length.compareTo(a.$4.length));
    // In date order already: the first found are the newest, the rest
    // only counted.
    final documents = <int>[];
    var documentsTotal = 0;
    for (final (at, folded, _) in _documents) {
      if (!has(folded)) continue;
      if (documents.length < SearchWorker.limit) documents.add(at);
      documentsTotal++;
    }
    return [
      cases.take(SearchWorker.limit).toList(),
      cases.length,
      [
        for (final p in parties.take(SearchWorker.limit))
          [p.$1, p.$3, p.$4.toList()],
      ],
      parties.length,
      documents,
      documentsTotal,
      cases,
    ];
  }
}

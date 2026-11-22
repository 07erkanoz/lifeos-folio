import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../platform/app_directories.dart';
import '../uyap/uyap_case_store.dart';
import 'ai_case.dart';
import 'ai_external.dart';
import 'ai_groq.dart';

/// Folio's tools in an isolate of their own: what [FolioToolsHere] runs,
/// off the isolate that draws Folio. Reading the database and hundreds of
/// cases' lists held the window up to seconds at a time, and Folio Ajan's
/// animation stood still whenever a tool ran (22 Kasım 2026).
///
/// What only the window's isolate knows goes with the isolate or with
/// every call: Folio's folder (path_provider cannot be asked there; the
/// first try waited on it forever), whether this person may see money and
/// who they are in the office. An isolate that dies answers every call
/// waiting on it with the error, and the next call runs here.
class FolioToolsApart implements FolioToolHost {
  FolioToolsApart._(
    this._session,
    this._external,
    this._isolate,
    this._to,
    this._from,
    Stream<Object?> heard,
  ) {
    heard.listen(_heard);
  }

  final AiCaseSession _session;
  final bool _external;
  final Isolate _isolate;
  final SendPort _to;
  final ReceivePort _from;
  final _waiting = <int, Completer<Object?>>{};
  var _next = 0;
  FolioToolsHere? _fallback;

  /// [session]'s tools, with those of the programs on this computer when
  /// [external]; [FolioToolsHere] where an isolate cannot be started.
  static Future<FolioToolHost> start(
    AiCaseSession session, {
    bool external = false,
  }) async {
    final from = ReceivePort();
    try {
      final folder = (await folioSupportDirectory()).path;
      final isolate = await Isolate.spawn(
        _main,
        (from.sendPort, folder, session.folder.path, external),
        debugName: 'Folio araçları',
        onError: from.sendPort,
        onExit: from.sendPort,
      );
      final ports = from.asBroadcastStream();
      final to =
          await ports
                  .firstWhere((m) => m is SendPort)
                  .timeout(const Duration(seconds: 10))
              as SendPort;
      return FolioToolsApart._(session, external, isolate, to, from, ports);
    } catch (_) {
      from.close();
      return FolioToolsHere(session, external: external);
    }
  }

  bool get _dead => _fallback != null;

  void _heard(Object? message) {
    if (message case (final int id, final Object? answer)) {
      _waiting.remove(id)?.complete(answer);
      return;
    }
    // onError ([error, stack]) or onExit (null): the isolate is gone.
    if (message is SendPort) return;
    _fallback ??= FolioToolsHere(_session, external: _external);
    final why = message is List && message.isNotEmpty ? '${message.first}' : '';
    for (final w in _waiting.values) {
      w.completeError(StateError('Folio’nun araçları durdu. $why'.trim()));
    }
    _waiting.clear();
  }

  Future<Object?> _ask(String what, [Object? a, Object? b]) {
    final id = ++_next;
    final answer = Completer<Object?>();
    _waiting[id] = answer;
    _to.send((id, what, a, b, ExternalHost.seesMoney(), ExternalHost.person()));
    return answer.future;
  }

  @override
  Future<List<Map<String, Object?>>> tools() async {
    if (_fallback case final here?) return here.tools();
    try {
      final got = await _ask('tools');
      if (got is String) throw StateError(got);
      return [
        for (final t in got as List)
          if (t is Map) t.cast<String, Object?>(),
      ];
    } on StateError {
      if (_dead) return _fallback!.tools();
      rethrow;
    }
  }

  @override
  Future<String> call(String name, Map<String, Object?> args) async {
    if (_fallback case final here?) return here.call(name, args);
    try {
      return await _ask('call', name, args) as String;
    } on StateError catch (e) {
      if (_fallback case final here?) return here.call(name, args);
      return '{"hata":"${e.message.replaceAll('"', "'")}"}';
    }
  }

  @override
  Future<void> close() async {
    if (!_dead) {
      try {
        await _ask('close').timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    _isolate.kill(priority: Isolate.immediate);
    _from.close();
    for (final w in _waiting.values) {
      w.complete('{"hata":"Folio’nun araçları kapandı."}');
    }
    _waiting.clear();
  }

  static Future<void> _main((SendPort, String, String, bool) start) async {
    final (out, support, folder, external) = start;
    folioSupportGiven = Directory(support);
    var money = false;
    var person = '';
    ExternalHost.seesMoney = () => money;
    ExternalHost.person = () => person;
    final here = FolioToolsHere(
      AiCaseSession.at(Directory(folder)),
      external: external,
    );
    final inbox = ReceivePort();
    out.send(inbox.sendPort);
    // The cases' lists read now, while the lawyer is still speaking: the
    // first read of hundreds of them takes seconds, later ones are kept.
    unawaited(
      UyapCaseStore.instance
          .cases(counted: false)
          .then((_) {}, onError: (_) {}),
    );
    await for (final m in inbox) {
      if (m is! (int, String, Object?, Object?, bool, String)) continue;
      final (id, what, a, b, seesMoney, who) = m;
      money = seesMoney;
      person = who;
      // Each on its own: a slow one (UYAP) does not hold the next.
      unawaited(() async {
        Object? answer;
        try {
          answer = switch (what) {
            'tools' => await here.tools(),
            'call' => await here.call(
              a! as String,
              (b! as Map).cast<String, Object?>(),
            ),
            'close' => await here.close().then((_) => null),
            _ => null,
          };
        } catch (e) {
          answer = what == 'call' ? '{"hata":"$e"}' : '$e';
        }
        out.send((id, answer));
      }());
    }
  }
}

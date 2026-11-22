import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// `codex app-server` over stdio: JSON-RPC, one message per line.
///
/// The official binary, the user's own `codex login`; no token is read,
/// stored or forwarded here.
class CodexAppServer {
  CodexAppServer._(this._process);

  final Process _process;
  final _waiting = <int, Completer<Map<String, Object?>>>{};
  final _notifications = StreamController<Map<String, Object?>>.broadcast();
  int _next = 0;

  /// Requests the server makes of this client (`item/tool/call`): answer
  /// with the result, or throw for an error.
  Future<Map<String, Object?>> Function(
    String method,
    Map<String, Object?> params,
  )?
  onRequest;

  Stream<Map<String, Object?>> get notifications => _notifications.stream;

  /// [log]: where Codex's own log goes (no conversation text in it).
  static Future<CodexAppServer> start({String? cwd, String? log}) async {
    final process = await Process.start(
      'codex',
      ['app-server'],
      workingDirectory: cwd,
      environment: {if (log != null) 'RUST_LOG': 'info,codex_core=debug'},
    );
    final server = CodexAppServer._(process);
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(server._take);
    final sink = log == null ? null : File(log).openWrite();
    process.stderr.listen((b) => sink?.add(b));
    await server.request('initialize', {
      'clientInfo': {'name': 'lifeos-folio', 'version': '0'},
      'capabilities': {'experimentalApi': true},
    });
    server._send({'method': 'initialized'});
    return server;
  }

  void _send(Map<String, Object?> message) =>
      _process.stdin.writeln(jsonEncode(message));

  Future<Map<String, Object?>> request(
    String method,
    Map<String, Object?> params, {
    Duration timeout = const Duration(seconds: 60),
  }) {
    final id = ++_next;
    final done = Completer<Map<String, Object?>>();
    _waiting[id] = done;
    _send({'id': id, 'method': method, 'params': params});
    return done.future.timeout(
      timeout,
      onTimeout: () {
        _waiting.remove(id);
        throw TimeoutException('$method cevap vermedi', timeout);
      },
    );
  }

  Future<void> _take(String line) async {
    final Map<String, Object?> m;
    try {
      m = (jsonDecode(line) as Map).cast<String, Object?>();
    } catch (_) {
      return;
    }
    final id = m['id'];
    final method = m['method'] as String?;
    if (method == null && id is int) {
      final done = _waiting.remove(id);
      if (done == null) return;
      if (m['error'] case final Map error) {
        done.completeError(CodexError('${error['message'] ?? error}'));
      } else {
        done.complete(((m['result'] as Map?) ?? {}).cast<String, Object?>());
      }
      return;
    }
    if (method == null) return;
    final params = ((m['params'] as Map?) ?? {}).cast<String, Object?>();
    if (id != null) {
      // A request of the server's.
      try {
        final handler = onRequest;
        if (handler == null) throw CodexError('desteklenmiyor: $method');
        _send({'id': id, 'result': await handler(method, params)});
      } catch (e) {
        _send({
          'id': id,
          'error': {'code': -32603, 'message': '$e'},
        });
      }
      return;
    }
    _notifications.add({'method': method, 'params': params});
  }

  Future<void> close() async {
    _process.kill();
    await _notifications.close();
  }
}

class CodexError implements Exception {
  CodexError(this.message);
  final String message;
  @override
  String toString() => message;
}

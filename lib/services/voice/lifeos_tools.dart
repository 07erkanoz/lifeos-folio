import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// LifeOS Linux's own tools (`lifeos mcp sun`) for Folio Ajan, when the
/// lawyer turned them on (Ayarlar › Yapay zekâ, 22 Kasım 2026): "e-imzam
/// neden çalışmıyor", "yazıcı neden yazmıyor", "bilgisayarda sorun var mı".
///
/// Only what reads this computer is given: no tool that changes anything,
/// none of the support team's, none that reaches a server.
class LifeosTools {
  LifeosTools({this.executable = 'lifeos'});

  final String executable;

  /// What Folio Ajan sees them as, apart from Folio's own.
  static const prefix = 'lifeos_';

  /// The tools given, by LifeOS's names.
  static const allowed = {
    'doctor',
    'processes',
    'services',
    'service_logs',
    'printers',
    'esign',
    'store_check',
    'settings',
    'lifeos_versions',
    'first_boot',
  };

  /// Whether this is LifeOS Linux: its `lifeos` program is here.
  static bool get installed {
    if (!Platform.isLinux) return false;
    for (final dir in (Platform.environment['PATH'] ?? '/usr/bin').split(':')) {
      if (dir.isNotEmpty && File('$dir/lifeos').existsSync()) return true;
    }
    return false;
  }

  Process? _process;
  StreamSubscription<String>? _lines;
  final _waiting = <int, Completer<Map<String, Object?>>>{};
  var _next = 0;
  List<Map<String, Object?>>? _tools;

  Future<Map<String, Object?>> _rpc(
    String method,
    Map<String, Object?> params, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final process = await _started();
    final id = ++_next;
    final done = _waiting[id] = Completer<Map<String, Object?>>();
    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    try {
      return await done.future.timeout(timeout);
    } finally {
      _waiting.remove(id);
    }
  }

  Future<Process> _started() async {
    if (_process case final p?) return p;
    final p = await Process.start(executable, const ['mcp', 'sun']);
    _process = p;
    p.stderr.drain<void>();
    _lines = p.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          try {
            final m = jsonDecode(line);
            if (m is Map && m['id'] is int) {
              _waiting[m['id']]?.complete(m.cast<String, Object?>());
            }
          } catch (_) {}
        });
    unawaited(
      p.exitCode.then((_) {
        if (identical(_process, p)) _reset();
      }),
    );
    final hello = _rpc('initialize', {
      'protocolVersion': '2025-06-18',
      'capabilities': {},
      'clientInfo': {'name': 'folio-ajan', 'version': '1'},
    });
    await hello;
    p.stdin.writeln(
      jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
    );
    return p;
  }

  void _reset() {
    _lines?.cancel();
    _lines = null;
    _process = null;
    for (final w in _waiting.values) {
      if (!w.isCompleted) w.completeError(StateError('lifeos ended'));
    }
    _waiting.clear();
  }

  /// The tools given, as Folio Ajan declares them; none when LifeOS's
  /// program does not answer.
  Future<List<Map<String, Object?>>> declarations() async {
    if (_tools case final t?) return t;
    try {
      final r = await _rpc(
        'tools/list',
        {},
        timeout: const Duration(seconds: 15),
      );
      final listed = (r['result'] as Map?)?['tools'];
      return _tools = [
        if (listed is List)
          for (final t in listed)
            if (t is Map &&
                allowed.contains(t['name']) &&
                (t['annotations'] as Map?)?['readOnlyHint'] == true)
              {
                'name': '$prefix${t['name']}',
                'title': t['title'] ?? t['name'],
                'description':
                    'LifeOS Linux: ${t['description'] ?? ''} Yalnız okur; '
                    'bir düzeltme önerirse avukata söyle, kendin yapma.',
                'inputSchema':
                    t['inputSchema'] ?? {'type': 'object', 'properties': {}},
                'annotations': const {
                  'readOnlyHint': true,
                  'destructiveHint': false,
                  'idempotentHint': true,
                  'openWorldHint': false,
                },
              },
      ];
    } catch (_) {
      return const [];
    }
  }

  /// [name] (with [prefix]) asked of LifeOS with [args]: its answer's text.
  Future<String> call(String name, Map<String, Object?> args) async {
    final bare = name.startsWith(prefix) ? name.substring(prefix.length) : name;
    if (!allowed.contains(bare)) {
      return jsonEncode({
        'durum': 'izin_yok',
        'aciklama': 'Bu araç verilmedi.',
      });
    }
    try {
      final r = await _rpc('tools/call', {'name': bare, 'arguments': args});
      if (r['error'] case final Map e) {
        return jsonEncode({'durum': 'hata', 'aciklama': '${e['message']}'});
      }
      final result = (r['result'] as Map?) ?? const {};
      final text = [
        for (final c in (result['content'] as List?) ?? const [])
          if (c is Map && c['type'] == 'text') '${c['text']}',
      ].join('\n');
      return result['isError'] == true
          ? jsonEncode({'durum': 'hata', 'aciklama': text})
          : text;
    } catch (e) {
      return jsonEncode({
        'durum': 'hata',
        'aciklama': 'LifeOS araçları yanıt vermedi.',
      });
    }
  }

  void close() {
    _process?.kill();
    _reset();
  }
}

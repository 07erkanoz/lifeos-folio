import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// LifeOS Linux's own tools (`lifeos mcp sun`) for Folio Ajan, when the
/// lawyer turned them on (Ayarlar › Yapay zekâ, 22 Kasım 2026): "e-imzam
/// neden çalışmıyor", "yazıcı neden yazmıyor", "sunucularım ayakta mı".
///
/// Every tool is given (23 Kasım 2026: reading only, the servers in
/// ~/.ssh/config were out of reach). One that changes anything runs only
/// after the lawyer's yes ([approve]).
class LifeosTools {
  LifeosTools({this.executable = 'lifeos', this.approve});

  final String executable;

  /// The lawyer's yes to [title] with [detail]; null when it cannot be
  /// asked. Without it nothing that changes anything runs.
  final Future<bool?> Function(String title, String detail)? approve;

  /// What Folio Ajan sees them as, apart from Folio's own.
  static const prefix = 'lifeos_';

  /// Whether [tool] (as LifeOS lists it) can change anything: not marked
  /// read-only, or marked destructive, or one that runs any command it is
  /// given (`server_exec`, `support_exec`: LifeOS marks them read-only).
  static bool changes(Map tool) {
    final a = tool['annotations'];
    final name = '${tool['name']}';
    if (name.endsWith('_exec')) return true;
    if (a is! Map) return true;
    return a['readOnlyHint'] != true || a['destructiveHint'] == true;
  }

  /// LifeOS's tools that change anything, as listed.
  final _changing = <String>{};
  final _titles = <String, String>{};

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
      _changing.clear();
      _titles.clear();
      final tools = <Map<String, Object?>>[];
      for (final t in listed is List ? listed : const []) {
        if (t is! Map || t['name'] is! String) continue;
        final name = t['name'] as String;
        final changing = changes(t);
        if (changing) _changing.add(name);
        _titles[name] = '${t['title'] ?? name}';
        tools.add({
          'name': '$prefix$name',
          'title': t['title'] ?? name,
          'description': changing
              ? 'LifeOS Linux: ${t['description'] ?? ''} Değişiklik yapar: '
                    'önce avukata ne yapacağını söyle; çalışmadan önce Folio '
                    'Ajan ekranında avukatın onayı istenir. Onaylanmazsa '
                    'yeniden deneme.'
              : 'LifeOS Linux: ${t['description'] ?? ''} Yalnız okur.',
          'inputSchema':
              t['inputSchema'] ?? {'type': 'object', 'properties': {}},
          'annotations': {
            'readOnlyHint': !changing,
            'destructiveHint':
                (t['annotations'] as Map?)?['destructiveHint'] == true,
            'idempotentHint': !changing,
            'openWorldHint':
                name.startsWith('server_') || name.startsWith('support_'),
          },
        });
      }
      return _tools = tools;
    } catch (_) {
      return const [];
    }
  }

  /// [name] (with [prefix]) asked of LifeOS with [args]: its answer's text.
  Future<String> call(String name, Map<String, Object?> args) async {
    final bare = name.startsWith(prefix) ? name.substring(prefix.length) : name;
    if (_tools == null) await declarations();
    if (!_titles.containsKey(bare)) {
      return jsonEncode({
        'durum': 'yok',
        'aciklama': 'LifeOS’ta bu adla bir araç yok.',
      });
    }
    if (_changing.contains(bare)) {
      final yes = await approve?.call(_titles[bare]!, detail(args));
      if (yes == null) {
        return jsonEncode({
          'durum': 'onay_sorulamadi',
          'aciklama':
              'Bu araç değişiklik yapar ve avukatın onayı Folio Ajan '
              'ekranında istenir; ekran açık değil. Avukattan Folio Ajan’ı '
              'tam ekran açmasını iste.',
        });
      }
      if (!yes) {
        return jsonEncode({
          'durum': 'onaylanmadi',
          'aciklama': 'Avukat onaylamadı; hiçbir şey yapılmadı.',
        });
      }
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

  /// [args] as the lawyer reads them: one "key: value" a line.
  static String detail(Map<String, Object?> args) {
    final lines = [
      for (final MapEntry(:key, :value) in args.entries)
        if (value != null && '$value'.isNotEmpty)
          '$key: ${value is String ? value : jsonEncode(value)}',
    ];
    return lines.isEmpty ? 'Ek bilgi yok.' : lines.join('\n');
  }

  void close() {
    _process?.kill();
    _reset();
  }
}

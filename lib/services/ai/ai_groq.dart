import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../security/secret_store.dart';
import 'ai_assistant.dart';
import 'ai_case.dart';
import 'folio_mcp.dart';

/// A model on Groq (GPT OSS), asked by Folio itself over Groq's API with
/// the lawyer's own key: no program between. Folio's rules are its
/// instructions, Folio's tools (the same `--mcp` server the programs run)
/// its functions. Folio holds it to them more tightly than a program it
/// only runs: a tool named wrongly is put right, an empty answer is asked
/// for again, a search done twice is not done again, and near the end of
/// its steps it is given no more tools and must write.
abstract final class GroqChat {
  static const endpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const keysPage = 'https://console.groq.com/keys';

  /// The models offered; the first is the default.
  static const models = ['openai/gpt-oss-120b', 'openai/gpt-oss-20b'];

  /// The most requests one answer makes: tool rounds and the writing.
  static const mostSteps = 16;

  /// The last steps given no tools: it writes with what it has.
  static const lastSteps = 2;

  /// A tool's answer is cut to this many characters.
  static const toolText = 30000;

  /// The conversation's earlier tool answers are shortened past this many
  /// characters all told (about 3.3 a token: well inside 131k tokens).
  static const mostCharacters = 280000;

  // The key, in the system's keyring (SecretStore), never in a file.

  static const _secret = 'groq';
  static String? _key;
  static bool _keyRead = false;

  static Future<String?> key() async {
    if (!_keyRead) {
      final kept = await SecretStore().read(_secret);
      _key = '${kept?['anahtar'] ?? ''}'.trim();
      if (_key!.isEmpty) _key = null;
      _keyRead = true;
    }
    return keyForTest ?? _key;
  }

  @visibleForTesting
  static String? keyForTest;

  /// The Folio whose tools a test runs (a build's); none otherwise.
  @visibleForTesting
  static String? folioForTest;

  /// A test's own server in place of Groq's.
  @visibleForTesting
  static String? endpointForTest;

  /// Keeps [value]; false when this computer cannot keep it safely.
  static Future<bool> saveKey(String value) async {
    final ok = await SecretStore().write(_secret, {'anahtar': value.trim()});
    _keyRead = false;
    return ok;
  }

  static Future<void> removeKey() async {
    await SecretStore().remove(_secret);
    _key = null;
    _keyRead = true;
  }

  /// Whether [value] is taken by Groq: a request that lists the models.
  static Future<String?> checkKey(String value) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(
        Uri.parse('https://api.groq.com/openai/v1/models'),
      );
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer ${value.trim()}')
        ..set(HttpHeaders.userAgentHeader, 'LifeOS-Folio');
      final res = await req.close().timeout(const Duration(seconds: 20));
      await res.drain<void>();
      if (res.statusCode == 200) return null;
      if (res.statusCode == 401 || res.statusCode == 403) {
        return 'Groq bu anahtarı kabul etmedi.';
      }
      return 'Groq yanıt vermedi (${res.statusCode}).';
    } catch (_) {
      return 'Groq’a ulaşılamadı. İnternet bağlantısını denetleyin.';
    } finally {
      client.close(force: true);
    }
  }

  // Conversations, by the id kept in the chat's [AiThread]: in memory only,
  // for as long as Folio is open. One whose id is not here is asked anew
  // with all that was said ([has] false).

  static final _held = <String, List<Map<String, Object?>>>{};

  static bool has(String id) => _held.containsKey(id);

  static String _newId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// [prompt] answered; [thread] goes on with what was said before in it.
  static Future<String> ask(
    String prompt, {
    String? model,
    AiTier? tier,
    bool tools = true,
    AiCaseSession? caseSession,
    void Function(AiEvent event)? onEvent,
    Future<void>? cancel,
    AiThread? thread,
  }) async {
    final key = await GroqChat.key();
    if (key == null) {
      throw const AiFailure(
        'Groq anahtarı girilmemiş. Ayarlar › Yapay zekâ’dan anahtarınızı girin.',
      );
    }
    final id = thread?.ids[AiProvider.groq];
    final kept = id != null ? _held[id] : null;
    final messages = <Map<String, Object?>>[
      if (kept != null)
        ...kept
      else
        {'role': 'system', 'content': AiPrompts.core},
      {'role': 'user', 'content': prompt},
    ];
    final folio = tools ? folioForTest ?? AiAssistant.folioProgram : null;
    final mcp = folio == null
        ? null
        : await McpClient.start(folio, caseSession);
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    var stopped = false;
    unawaited(
      cancel?.then((_) {
        stopped = true;
        http.close(force: true);
      }),
    );
    try {
      final functions = [
        for (final t in await mcp?.tools() ?? const <Map<String, Object?>>[])
          {
            'type': 'function',
            'function': {
              'name': t['name'],
              'description': t['description'] ?? '',
              'parameters':
                  t['inputSchema'] ??
                  {'type': 'object', 'properties': <String, Object?>{}},
            },
          },
      ];
      final known = {
        for (final f in functions) '${(f['function'] as Map)['name']}',
      };
      final done = <String>{};
      var empty = 0, budget = false, calls = 0;
      _shorten(messages);
      for (var step = 0; step < mostSteps; step++) {
        if (stopped) throw const AiFailure('Durduruldu.');
        final last = functions.isEmpty || step >= mostSteps - lastSteps;
        if (last && functions.isNotEmpty && !budget) {
          budget = true;
          messages.add({
            'role': 'user',
            'content':
                'Araç bütçen bitti. Elindekiyle cevabını şimdi yaz; '
                'bulamadığın şeyi "bulamadım" diye açıkça söyle, tahmin etme.',
          });
        }
        final body = {
          'model': (model == null || model.isEmpty) ? models.first : model,
          'messages': last && functions.isNotEmpty
              ? writingOnly(messages)
              : messages,
          'reasoning_effort': (tier ?? AiTier.normal).effort,
          'temperature': 1,
          'max_completion_tokens': 16000,
          if (!last) ...{'tools': functions, 'disable_tool_validation': true},
        };
        final reply = await _request(http, key, body, () => stopped);
        final message = Map<String, Object?>.from(
          ((reply['choices'] as List).first as Map)['message'] as Map,
        );
        final asked = [
          for (final c in message['tool_calls'] as List? ?? const [])
            if (c is Map) c,
        ];
        final content = '${message['content'] ?? ''}';
        if (asked.isEmpty) {
          // Its thinking spent, an empty answer now and then: asked again.
          if (content.trim().isEmpty && empty < 2) {
            empty++;
            continue;
          }
          messages.add({'role': 'assistant', 'content': content});
          onEvent?.call(AiWriting(content, restart: true));
          final nextId = id ?? _newId();
          _held[nextId] = messages;
          if (thread != null) thread.ids[AiProvider.groq] = nextId;
          if (content.trim().isEmpty) {
            throw const AiFailure('Groq yanıt vermedi.');
          }
          return content.trim();
        }
        messages.add({
          'role': 'assistant',
          'content': message['content'],
          'tool_calls': asked,
        });
        if (content.trim().isNotEmpty) onEvent?.call(AiThought(content.trim()));
        for (final c in asked) {
          final fn = Map<String, Object?>.from(c['function'] as Map? ?? {});
          final callId = '${c['id'] ?? 'c${calls++}'}';
          final name = toolName('${fn['name'] ?? ''}', known);
          Map<String, Object?> args;
          try {
            final a = jsonDecode('${fn['arguments'] ?? '{}'}');
            args = a is Map ? a.cast<String, Object?>() : {};
          } on FormatException {
            args = {};
          }
          final String text;
          final sign = '$name${jsonEncode(args)}';
          if (!known.contains(name)) {
            text = jsonEncode({
              'hata':
                  '${fn['name']} diye bir araç yok. Araçlar: '
                  '${(known.toList()..sort()).join(', ')}',
            });
          } else if (!done.add(sign)) {
            text = jsonEncode({
              'not':
                  'Bu çağrıyı bu soruda zaten yaptın; sonucu yukarıda. Farklı '
                  'bir şey ara ya da cevabını yaz.',
            });
          } else {
            onEvent?.call(AiStep(callId, name, args: args));
            final got = await mcp!.call(name, args);
            onEvent?.call(AiStep(callId, name, args: args, done: true));
            text = got.length > toolText
                ? '${got.substring(0, toolText)}…'
                : got;
          }
          messages.add({
            'role': 'tool',
            'tool_call_id': callId,
            'content': text,
          });
        }
      }
      throw const AiFailure('Groq adım sınırında cevabını bitiremedi.');
    } on AiFailure {
      rethrow;
    } catch (e) {
      if (stopped) throw const AiFailure('Durduruldu.');
      throw AiFailure('Groq’a ulaşılamadı: $e');
    } finally {
      http.close(force: true);
      await mcp?.close();
    }
  }

  /// The request, asked again where Groq says to: its limit for the minute
  /// reached, or a tool's name the model wrote wrongly ("functions/x").
  static Future<Map<String, Object?>> _request(
    HttpClient http,
    String key,
    Map<String, Object?> body,
    bool Function() stopped,
  ) async {
    for (var attempt = 0; ; attempt++) {
      final req = await http.postUrl(Uri.parse(endpointForTest ?? endpoint));
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $key')
        ..set(HttpHeaders.userAgentHeader, 'LifeOS-Folio')
        ..contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close().timeout(const Duration(minutes: 5));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode == 200) {
        return (jsonDecode(text) as Map).cast<String, Object?>();
      }
      if (stopped()) throw const AiFailure('Durduruldu.');
      if (res.statusCode == 429 && attempt < 3) {
        await Future<void>.delayed(Duration(seconds: 10 * (attempt + 1)));
        continue;
      }
      if (res.statusCode == 400 &&
          text.contains('tool_use_failed') &&
          attempt < 3) {
        continue;
      }
      throw AiFailure(failure(res.statusCode, text));
    }
  }

  /// Groq's refusal, said in Turkish.
  @visibleForTesting
  static String failure(int status, String text) {
    String said = '';
    try {
      said = '${((jsonDecode(text) as Map)['error'] as Map)['message'] ?? ''}';
    } catch (_) {}
    return switch (status) {
      401 ||
      403 => 'Groq anahtarı geçersiz. Ayarlar › Yapay zekâ’dan yeniden girin.',
      429 => 'Groq kullanım sınırınız doldu. Biraz sonra yeniden deneyin.',
      413 => 'Soru Groq için çok uzun. Daha az evrakla sorun.',
      _ when said.contains('context_length') || said.contains('too long') =>
        'Soru Groq için çok uzun. Daha az evrakla sorun.',
      _ =>
        said.isEmpty
            ? 'Groq yanıt veremedi ($status).'
            : 'Groq yanıt veremedi: $said',
    };
  }

  /// A tool's name as the model meant it: "functions/karar_ara",
  /// "functions.karar_ara" → karar_ara; "ara" → the one tool it names.
  @visibleForTesting
  static String toolName(String name, Set<String> known) {
    if (known.contains(name)) return name;
    final short = name
        .split('/')
        .last
        .split('.')
        .last
        .replaceFirst(RegExp(r'^functions[_\\]*'), '');
    if (known.contains(short)) return short;
    final like = [
      for (final k in known)
        if (k.endsWith('_$short') || k.startsWith('${short}_')) k,
    ];
    return like.length == 1 ? like.single : name;
  }

  /// [messages] for a request given no tools: what the tools said is kept,
  /// as text, the calls themselves left out.
  @visibleForTesting
  static List<Map<String, Object?>> writingOnly(
    List<Map<String, Object?>> messages,
  ) {
    final out = <Map<String, Object?>>[];
    for (final m in messages) {
      if (m['role'] == 'tool') {
        out.add({'role': 'user', 'content': 'Araç sonucu:\n${m['content']}'});
      } else if (m['tool_calls'] != null) {
        if ('${m['content'] ?? ''}'.trim().isNotEmpty) {
          out.add({'role': 'assistant', 'content': m['content']});
        }
      } else {
        out.add(m);
      }
    }
    return out;
  }

  /// A long conversation's earlier tool answers cut short, the oldest first,
  /// until it fits.
  @visibleForTesting
  static void shorten(List<Map<String, Object?>> messages) =>
      _shorten(messages);

  static void _shorten(List<Map<String, Object?>> messages) {
    int size() =>
        messages.fold(0, (n, m) => n + '${m['content'] ?? ''}'.length);
    for (final m in messages) {
      if (size() <= mostCharacters) return;
      final c = '${m['content'] ?? ''}';
      if (m['role'] == 'tool' && c.length > 1500) {
        m['content'] = '${c.substring(0, 1500)}… [kısaltıldı]';
      }
    }
  }
}

/// Folio's tools as a program reaches them: this Folio run with
/// [FolioMcp.flag], spoken to over its standard input and output.
class McpClient {
  McpClient._(this._process) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_heard, onDone: _ended);
    _process.stderr.drain<void>();
  }

  final Process _process;
  final _waiting = <int, Completer<Map<String, Object?>>>{};
  var _next = 0;

  static Future<McpClient> start(
    String folio,
    AiCaseSession? caseSession,
  ) async {
    final process = await Process.start(
      folio,
      [FolioMcp.flag],
      environment: {
        ...AiAssistant.environment(),
        AiCaseSession.variable: ?caseSession?.folder.path,
      },
    );
    final client = McpClient._(process);
    await client._ask('initialize', {
      'protocolVersion': FolioMcp.protocol,
      'capabilities': <String, Object?>{},
      'clientInfo': {'name': 'folio-groq', 'version': '1'},
    });
    process.stdin.writeln(
      jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
    );
    return client;
  }

  void _heard(String line) {
    if (!line.startsWith('{')) return;
    try {
      final m = jsonDecode(line);
      if (m is! Map || m['id'] is! int) return;
      _waiting.remove(m['id'])?.complete(m.cast<String, Object?>());
    } on FormatException {
      return;
    }
  }

  void _ended() {
    for (final w in _waiting.values) {
      w.completeError(const AiFailure('Folio’nun araçları kapandı.'));
    }
    _waiting.clear();
  }

  Future<Map<String, Object?>> _ask(
    String method,
    Map<String, Object?> params,
  ) {
    final id = ++_next;
    final answer = Completer<Map<String, Object?>>();
    _waiting[id] = answer;
    _process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    return answer.future.timeout(const Duration(minutes: 4));
  }

  Future<List<Map<String, Object?>>> tools() async {
    final got = await _ask('tools/list', {});
    return [
      for (final t in (got['result'] as Map?)?['tools'] as List? ?? const [])
        if (t is Map) t.cast<String, Object?>(),
    ];
  }

  /// The tool's answer as text, as the model reads it.
  Future<String> call(String name, Map<String, Object?> args) async {
    try {
      final got = await _ask('tools/call', {'name': name, 'arguments': args});
      final result = got['result'];
      if (result is! Map) return jsonEncode({'hata': got['error']});
      return [
        for (final c in result['content'] as List? ?? const [])
          if (c is Map) '${c['text'] ?? ''}',
      ].join();
    } on TimeoutException {
      return jsonEncode({
        'durum': 'ulasilamadi',
        'aciklama': 'Araç yanıt vermedi.',
      });
    }
  }

  Future<void> close() async {
    try {
      await _process.stdin.close();
    } catch (_) {}
    _process.kill();
  }
}

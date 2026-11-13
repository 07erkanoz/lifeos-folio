import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';
import '../platform/atomic_file.dart';
import '../security/secret_store.dart';
import 'ai_assistant.dart';
import 'ai_attachment.dart';
import 'ai_case.dart';
import 'ai_office.dart';
import 'ai_claude_api.dart';
import 'folio_mcp.dart';

/// The services Folio asks itself over their OpenAI-like API, with the
/// lawyer's own key: no program to install, so on every computer.
enum ApiService {
  groq(
    'Groq',
    'groq',
    'https://api.groq.com/openai/v1/chat/completions',
    'https://api.groq.com/openai/v1/models',
    'https://console.groq.com/keys',
    ['openai/gpt-oss-120b', 'openai/gpt-oss-20b'],
  ),

  /// Gemini 3.8 Flash takes reasoning_effort low, medium or high (not
  /// minimal); thinking is on by itself.
  gemini(
    'Gemini',
    'gemini',
    'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
    'https://generativelanguage.googleapis.com/v1beta/openai/models',
    'https://aistudio.google.com/apikey',
    ['gemini-3.8-flash'],
  ),
  openai(
    'OpenAI',
    'openai',
    'https://api.openai.com/v1/chat/completions',
    'https://api.openai.com/v1/models',
    'https://platform.openai.com/api-keys',
    ['gpt-6.1-sol', 'gpt-6-luna', 'gpt-6.1-terra'],
  ),

  /// Anthropic's own Messages API, not an OpenAI-like one: thinking is
  /// adaptive on the current models and its depth is the effort.
  anthropic(
    'Claude',
    'anthropic',
    'https://api.anthropic.com/v1/messages',
    'https://api.anthropic.com/v1/models',
    'https://platform.claude.com/settings/keys',
    ['claude-opus-5-5', 'claude-sonnet-5-5', 'claude-haiku-5-5'],
  );

  const ApiService(
    this.label,
    this.secret,
    this.endpoint,
    this.modelsUrl,
    this.keysPage,
    this.models,
  );

  final String label, secret, endpoint, modelsUrl, keysPage;

  /// The models offered; the first is the default.
  final List<String> models;

  AiProvider get provider => switch (this) {
    ApiService.groq => AiProvider.groq,
    ApiService.gemini => AiProvider.gemini,
    ApiService.openai => AiProvider.openai,
    ApiService.anthropic => AiProvider.anthropic,
  };

  static ApiService? of(AiProvider provider) => switch (provider) {
    AiProvider.groq => ApiService.groq,
    AiProvider.gemini => ApiService.gemini,
    AiProvider.openai => ApiService.openai,
    AiProvider.anthropic => ApiService.anthropic,
    _ => null,
  };

  /// The headers a request to it carries the key in.
  Map<String, String> headers(String key) => this == ApiService.anthropic
      ? {'x-api-key': key, 'anthropic-version': '2023-06-01'}
      : {'authorization': 'Bearer $key'};
}

/// A model on Groq (GPT OSS), asked by Folio itself over Groq's API with
/// the lawyer's own key: no program between. Folio's rules are its
/// instructions, Folio's tools (the same `--mcp` server the programs run)
/// its functions. Folio holds it to them more tightly than a program it
/// only runs: a tool named wrongly is put right, an empty answer is asked
/// for again, a search done twice is not done again, and near the end of
/// its steps it is given no more tools and must write.
abstract final class GroqChat {
  static final endpoint = ApiService.groq.endpoint;
  static final keysPage = ApiService.groq.keysPage;

  /// Groq's models; the first is the default.
  static final models = ApiService.groq.models;

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

  static final _keys = <ApiService, String?>{};

  static Future<String?> key([ApiService service = ApiService.groq]) async {
    if (keyForTest != null) return keyForTest;
    if (!_keys.containsKey(service)) {
      final kept = await SecretStore().read(service.secret);
      final k = '${kept?['anahtar'] ?? ''}'.trim();
      _keys[service] = k.isEmpty ? null : k;
    }
    return _keys[service];
  }

  @visibleForTesting
  static String? keyForTest;

  /// The Folio whose tools a test runs (a build's); none otherwise.
  @visibleForTesting
  static String? folioForTest;

  /// The Folio whose `--mcp` server the tools are; null where there is none
  /// to start.
  static String? get toolsProgram => folioForTest ?? AiAssistant.folioProgram;

  /// Whether the tools are started as a server rather than run here.
  static bool get toolsAsServer =>
      toolsProgram != null && (Platform.isLinux || folioForTest != null);

  /// A test's own server in place of Groq's.
  @visibleForTesting
  static String? endpointForTest;

  /// Keeps [value]; false when this computer cannot keep it safely.
  static Future<bool> saveKey(
    String value, [
    ApiService service = ApiService.groq,
  ]) async {
    final ok = await SecretStore().write(service.secret, {
      'anahtar': value.trim(),
    });
    _keys.remove(service);
    return ok;
  }

  static Future<void> removeKey([ApiService service = ApiService.groq]) async {
    await SecretStore().remove(service.secret);
    _keys[service] = null;
  }

  /// Whether [value] is taken by [service]: a request that lists the
  /// models.
  static Future<String?> checkKey(
    String value, [
    ApiService service = ApiService.groq,
  ]) async {
    final who = service.label;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(service.modelsUrl));
      service.headers(value.trim()).forEach(req.headers.set);
      req.headers.set(HttpHeaders.userAgentHeader, 'LifeOS-Folio');
      final res = await req.close().timeout(const Duration(seconds: 20));
      await res.drain<void>();
      if (res.statusCode == 200) return null;
      if (res.statusCode == 401 || res.statusCode == 403) {
        return '$who bu anahtarı kabul etmedi.';
      }
      return '$who yanıt vermedi (${res.statusCode}).';
    } catch (_) {
      return '$who’a ulaşılamadı. İnternet bağlantısını denetleyin.';
    } finally {
      client.close(force: true);
    }
  }

  static final _listed = <ApiService, List<String>>{};

  /// The models [service] offers this key, for the lawyer to choose from;
  /// its defaults when it cannot be asked.
  static Future<List<String>> listModels(ApiService service) async {
    if (_listed[service] case final got?) return got;
    final key = await GroqChat.key(service);
    if (key == null) return service.models;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(service.modelsUrl));
      service.headers(key).forEach(req.headers.set);
      final res = await req.close().timeout(const Duration(seconds: 20));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return service.models;
      final ids = [
        for (final m in (jsonDecode(text) as Map)['data'] as List? ?? const [])
          if (m is Map && m['id'] is String)
            '${m['id']}'.replaceFirst('models/', ''),
      ];
      // Chat models only, the defaults first.
      final chat = ids.where(
        (id) => switch (service) {
          ApiService.gemini =>
            id.startsWith('gemini-') &&
                !id.contains('tts') &&
                !id.contains('embedding') &&
                !id.contains('image'),
          ApiService.openai => id.startsWith('gpt-') || id.startsWith('o'),
          _ => true,
        },
      );
      return _listed[service] = {
        ...service.models.where(ids.contains),
        ...chat,
      }.toList();
    } catch (_) {
      return service.models;
    } finally {
      client.close(force: true);
    }
  }

  // Conversations, by the id kept in the chat's [AiThread]: kept on this
  // computer, in Folio's folder (yapay-zeka/api-sohbet), so that a chat goes
  // on after Folio was closed without the service reading it all again as
  // text; as the programs keep their own records in theirs. A chat removed
  // takes its records with it ([forget]); one untouched for [keepFor] goes.

  static final _held = <String, List<Map<String, Object?>>>{};

  static const keepFor = Duration(days: 60);

  /// Where the conversations are kept; a test's own folder.
  @visibleForTesting
  static Directory? folderForTest;

  static Future<Directory> _folder() async {
    final dir =
        folderForTest ??
        Directory(
          p.join(
            (await folioSupportDirectory()).path,
            'yapay-zeka',
            'api-sohbet',
          ),
        );
    if (!_pruned) {
      _pruned = true;
      try {
        final old = DateTime.now().subtract(keepFor);
        await for (final f in dir.list()) {
          if (f is File && (await f.lastModified()).isBefore(old)) {
            await f.delete();
          }
        }
      } catch (_) {}
    }
    return dir;
  }

  static var _pruned = false;

  /// As a Folio opened anew: nothing held in memory.
  @visibleForTesting
  static void dropMemoryForTest() => _held.clear();

  static String _safe(String id) => id.replaceAll(RegExp(r'[^\w.-]'), '_');

  /// The conversation kept under [id]: in memory, else from its file.
  static Future<List<Map<String, Object?>>?> load(String? id) async {
    if (id == null) return null;
    if (_held[id] case final got?) return got;
    try {
      final file = File(p.join((await _folder()).path, '${_safe(id)}.json'));
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      final list = [
        for (final m in (json as Map)['mesajlar'] as List? ?? const [])
          if (m is Map) m.cast<String, Object?>(),
      ];
      return list.isEmpty ? null : _held[id] = list;
    } catch (_) {
      return null;
    }
  }

  /// [messages] kept under [id] (a new one when null, or the chat's own
  /// [place] for [service]); the id they are kept under.
  static Future<String> hold(
    String? id,
    List<Map<String, Object?>> messages, {
    String? place,
    ApiService service = ApiService.groq,
  }) async {
    final next = id ?? (place == null ? _newId() : '${service.name}-$place');
    _held[next] = messages;
    // A single question (a notice read, a summary) is not a chat to go on.
    if (place == null) return next;
    try {
      final dir = await _folder();
      await dir.create(recursive: true);
      await replaceFileIfChanged(
        File(p.join(dir.path, '${_safe(next)}.json')),
        utf8.encode(
          jsonEncode({
            'hizmet': service.name,
            'sohbet': place,
            'guncel': DateTime.now().toIso8601String(),
            'mesajlar': messages,
          }),
        ),
      );
    } catch (_) {}
    return next;
  }

  /// Whether the conversation [id] is kept, here or on disk.
  static Future<bool> has(String id) async => await load(id) != null;

  /// A chat's records with every service, when the chat is removed.
  static Future<void> forget(String place) async {
    _held.removeWhere((k, _) => k.endsWith('-$place'));
    try {
      for (final s in ApiService.values) {
        final f = File(
          p.join((await _folder()).path, '${_safe('${s.name}-$place')}.json'),
        );
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
  }

  static String _newId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// [prompt] answered; [thread] goes on with what was said before in it.
  /// The question as [service] takes it: its text alone, or with the pages
  /// and pictures of [attachments] after it.
  @visibleForTesting
  static Object userContent(
    String prompt,
    List<AiAttachment> attachments,
    ApiService service,
  ) {
    final images = [for (final a in attachments) ...a.images];
    if (images.isEmpty) return prompt;
    return [
      {'type': 'text', 'text': prompt},
      for (final i in images)
        {
          'type': 'image_url',
          'image_url': {
            'url': 'data:${i.mime};base64,${base64Encode(i.bytes)}',
            // A page of a scan is read at its full size, not a thumbnail.
            if (service == ApiService.openai) 'detail': 'high',
          },
        },
    ];
  }

  static Future<String> ask(
    String prompt, {
    String? model,
    AiTier? tier,
    bool tools = true,
    AiCaseSession? caseSession,
    void Function(AiEvent event)? onEvent,
    Future<void>? cancel,
    AiThread? thread,
    ApiService service = ApiService.groq,
    List<AiAttachment> attachments = const [],
  }) async {
    final who = service.label;
    final key = await GroqChat.key(service);
    if (key == null) {
      throw AiFailure(
        '$who anahtarı girilmemiş. Ayarlar › Yapay zekâ’dan anahtarınızı girin.',
      );
    }
    if (service == ApiService.anthropic) {
      return ClaudeApiChat.ask(
        prompt,
        key: key,
        model: model,
        tier: tier,
        tools: tools,
        caseSession: caseSession,
        onEvent: onEvent,
        cancel: cancel,
        thread: thread,
        attachments: attachments,
      );
    }
    final id = thread?.ids[service.provider];
    final kept = await load(id);
    final messages = <Map<String, Object?>>[
      if (kept != null)
        ...kept
      else
        {'role': 'system', 'content': AiPrompts.core},
      {'role': 'user', 'content': userContent(prompt, attachments, service)},
    ];
    // Folio's tools: on Linux the same `--mcp` server the programs run;
    // elsewhere, where there is no such server, run here.
    final FolioToolHost? mcp = !tools
        ? null
        : toolsAsServer
        ? await McpClient.start(toolsProgram!, caseSession)
        : FolioToolsHere(caseSession);
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
          'model': (model == null || model.isEmpty)
              ? service.provider.defaultModel(tier ?? AiTier.normal)
              : model,
          'messages': last && functions.isNotEmpty
              ? writingOnly(messages)
              : messages,
          'reasoning_effort': (tier ?? AiTier.normal).effort,
          // OpenAI's reasoning models take no temperature but their own.
          if (service != ApiService.openai) 'temperature': 1,
          // The same chat's requests share a prefix (rules, tools, what was
          // said): OpenAI routes them to its cache by this key. Gemini and
          // Groq cache a repeated prefix of themselves.
          if (service == ApiService.openai && thread != null)
            'prompt_cache_key': 'folio-${thread.place}',
          if (service == ApiService.gemini)
            'max_tokens': 16000
          else
            'max_completion_tokens': 16000,
          if (!last) ...{
            'tools': functions,
            // Groq's own: a tool's name the model writes wrongly is let
            // through, and Folio puts it right.
            if (service == ApiService.groq) 'disable_tool_validation': true,
          },
        };
        final reply = await _request(http, key, body, () => stopped, service);
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
          final nextId = await hold(
            id,
            messages,
            place: thread?.place,
            service: service,
          );
          if (thread != null) thread.ids[service.provider] = nextId;
          if (content.trim().isEmpty) {
            throw AiFailure('$who yanıt vermedi.');
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
      throw AiFailure('$who adım sınırında cevabını bitiremedi.');
    } on AiFailure {
      rethrow;
    } catch (e) {
      if (stopped) throw const AiFailure('Durduruldu.');
      throw AiFailure('$who’a ulaşılamadı: $e');
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
    ApiService service,
  ) async {
    for (var attempt = 0; ; attempt++) {
      final req = await http.postUrl(
        Uri.parse(endpointForTest ?? service.endpoint),
      );
      service.headers(key).forEach(req.headers.set);
      req.headers
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
      throw AiFailure(failure(res.statusCode, text, service));
    }
  }

  /// The service's refusal, said in Turkish. Gemini answers in a list
  /// ([{"error": …}]) and says a wrong key with 400.
  static String failure(
    int status,
    String text, [
    ApiService service = ApiService.groq,
  ]) {
    final who = service.label;
    String said = '';
    try {
      var json = jsonDecode(text);
      if (json is List && json.isNotEmpty) json = json.first;
      said = '${((json as Map)['error'] as Map)['message'] ?? ''}';
    } catch (_) {}
    final badKey =
        status == 401 ||
        status == 403 ||
        said.contains('API key not valid') ||
        said.contains('API_KEY_INVALID');
    return switch (status) {
      _ when badKey =>
        '$who anahtarı geçersiz. Ayarlar › Yapay zekâ’dan yeniden girin.',
      429 => '$who kullanım sınırınız doldu. Biraz sonra yeniden deneyin.',
      413 => 'Soru $who için çok uzun. Daha az evrakla sorun.',
      _ when said.contains('context_length') || said.contains('too long') =>
        'Soru $who için çok uzun. Daha az evrakla sorun.',
      _ =>
        said.isEmpty
            ? '$who yanıt veremedi ($status).'
            : '$who yanıt veremedi: $said',
    };
  }

  /// A tool's name as the model meant it: "functions/karar_ara",
  /// "functions.karar_ara" → karar_ara; "ara" → the one tool it names.
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
    // A page sent as a picture is not text to cut: its words are counted,
    // not its bytes.
    int length(Object? c) => c is List
        ? c.fold(0, (n, part) {
            final text = part is Map ? part['text'] : null;
            return n + (text is String ? text.length : 0);
          })
        : '${c ?? ''}'.length;
    int size() => messages.fold(0, (n, m) => n + length(m['content']));
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
/// Where an API service's model calls Folio's tools.
abstract class FolioToolHost {
  Future<List<Map<String, Object?>>> tools();

  /// The tool's answer as text, as the model reads it.
  Future<String> call(String name, Map<String, Object?> args);
  Future<void> close();
}

/// Folio's tools run in Folio itself: where no `--mcp` server can be
/// started for them (Windows, macOS). The case's and the office's tools
/// are those of [caseSession], as the server would have them.
class FolioToolsHere implements FolioToolHost {
  FolioToolsHere(AiCaseSession? caseSession)
    : _mcp = FolioMcp(
        caseTools: caseSession == null
            ? null
            : FolioCaseTools.fromEnvironment({
                AiCaseSession.variable: caseSession.folder.path,
              }),
        officeTools: caseSession == null
            ? null
            : FolioOfficeTools.fromEnvironment({
                AiCaseSession.variable: caseSession.folder.path,
              }),
      );

  final FolioMcp _mcp;
  var _next = 0;

  Future<Map<String, Object?>> _ask(
    String method,
    Map<String, Object?> p,
  ) async =>
      await _mcp.handle({
        'jsonrpc': '2.0',
        'id': ++_next,
        'method': method,
        'params': p,
      }) ??
      const {};

  @override
  Future<List<Map<String, Object?>>> tools() async {
    final got = await _ask('tools/list', {});
    return [
      for (final t in (got['result'] as Map?)?['tools'] as List? ?? const [])
        if (t is Map) t.cast<String, Object?>(),
    ];
  }

  @override
  Future<String> call(String name, Map<String, Object?> args) async {
    final got = await _ask('tools/call', {'name': name, 'arguments': args});
    final result = got['result'];
    if (result is! Map) return jsonEncode({'hata': got['error']});
    return [
      for (final c in result['content'] as List? ?? const [])
        if (c is Map) '${c['text'] ?? ''}',
    ].join();
  }

  @override
  Future<void> close() async {}
}

class McpClient implements FolioToolHost {
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

  @override
  Future<List<Map<String, Object?>>> tools() async {
    final got = await _ask('tools/list', {});
    return [
      for (final t in (got['result'] as Map?)?['tools'] as List? ?? const [])
        if (t is Map) t.cast<String, Object?>(),
    ];
  }

  /// The tool's answer as text, as the model reads it.
  @override
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

  @override
  Future<void> close() async {
    try {
      await _process.stdin.close();
    } catch (_) {}
    _process.kill();
  }
}

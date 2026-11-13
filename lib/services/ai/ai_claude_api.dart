import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'ai_assistant.dart';
import 'ai_attachment.dart';
import 'ai_case.dart';
import 'ai_groq.dart';
import 'ai_usage.dart';

/// Claude asked by Folio itself over Anthropic's Messages API with the
/// lawyer's own key (raw HTTP: there is no Anthropic SDK for Dart). The same
/// hold on the model as [GroqChat]'s: Folio's rules as the system prompt,
/// Folio's tools, a tool's name put right, a call done twice not done again,
/// no tools in the last steps, an empty answer asked for again.
///
/// Thinking is adaptive on the current models (it cannot be turned off on
/// Opus 5.5); its depth is the tier's effort. Each assistant turn is kept
/// as it came, thinking blocks and all, and sent back unchanged. A request
/// the safety classifiers decline ends with stop_reason "refusal"; Opus and
/// Sonnet 5.5 are let fall back to another model on the server
/// ("fallbacks": "default"); Haiku has no server-side fallback.
abstract final class ClaudeApiChat {
  static const mostSteps = 16;
  static const lastSteps = 2;
  static const toolText = 30000;

  /// A test's own server in place of Anthropic's.
  @visibleForTesting
  static String? endpointForTest;

  static bool _fallsBack(String model) =>
      model == 'claude-opus-5-5' || model == 'claude-sonnet-5-5';

  static Future<String> ask(
    String prompt, {
    required String key,
    String? model,
    AiTier? tier,
    bool tools = true,
    AiCaseSession? caseSession,
    void Function(AiEvent event)? onEvent,
    Future<void>? cancel,
    AiThread? thread,
    List<AiAttachment> attachments = const [],
  }) async {
    final name = (model == null || model.isEmpty)
        ? AiProvider.anthropic.defaultModel(tier ?? AiTier.normal)
        : model;
    final id = thread?.ids[AiProvider.anthropic];
    final messages = <Map<String, Object?>>[
      ...?await GroqChat.load(id),
      {'role': 'user', 'content': userContent(prompt, attachments)},
    ];
    final FolioToolHost? host = !tools
        ? null
        : GroqChat.toolsAsServer
        ? await McpClient.start(GroqChat.toolsProgram!, caseSession)
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
      final declared = [
        for (final t in await host?.tools() ?? const <Map<String, Object?>>[])
          {
            'name': t['name'],
            'description': t['description'] ?? '',
            'input_schema':
                t['inputSchema'] ??
                {'type': 'object', 'properties': <String, Object?>{}},
          },
      ];
      final known = {for (final t in declared) '${t['name']}'};
      final done = <String>{};
      var empty = 0, budget = false;
      for (var step = 0; step < mostSteps; step++) {
        if (stopped) throw const AiFailure('Durduruldu.');
        final last = declared.isEmpty || step >= mostSteps - lastSteps;
        if (last && declared.isNotEmpty && !budget) {
          budget = true;
          messages.add({
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text':
                    'Araç bütçen bitti. Elindekiyle cevabını şimdi yaz; '
                    'bulamadığın şeyi "bulamadım" diye açıkça söyle, tahmin etme.',
              },
            ],
          });
        }
        final body = <String, Object?>{
          'model': name,
          'max_tokens': 16000,
          'system': AiPrompts.core,
          'messages': _merged(messages),
          'output_config': {'effort': (tier ?? AiTier.normal).effort},
          if (declared.isNotEmpty) 'tools': declared,
          // The tools stay declared (the history holds their calls); in the
          // last steps none may be called.
          if (last && declared.isNotEmpty) 'tool_choice': {'type': 'none'},
          if (_fallsBack(name)) 'fallbacks': 'default',
          // The rules, the tools and what was said are the same prefix every
          // step and every question of the chat: cached, read again at a
          // tenth of the price.
          'cache_control': {'type': 'ephemeral'},
        };
        final reply = await _request(http, key, body, () => stopped, name);
        if (reply['usage'] case final Map usage) {
          int n(Object? v) => v is num ? v.toInt() : 0;
          unawaited(
            AiUsage.add(
              ApiService.anthropic,
              input:
                  n(usage['input_tokens']) +
                  n(usage['cache_read_input_tokens']) +
                  n(usage['cache_creation_input_tokens']),
              output: n(usage['output_tokens']),
            ),
          );
        }
        if (reply['stop_reason'] == 'refusal') {
          throw const AiFailure(
            'Claude bu soruyu güvenlik denetimi yüzünden yanıtlamadı. '
            'Soruyu başka bir programla deneyin.',
          );
        }
        final content = [
          for (final b in reply['content'] as List? ?? const [])
            if (b is Map) b.cast<String, Object?>(),
        ];
        final text = [
          for (final b in content)
            if (b['type'] == 'text') '${b['text'] ?? ''}',
        ].join();
        final calls = [
          for (final b in content)
            if (b['type'] == 'tool_use') b,
        ];
        if (calls.isEmpty) {
          if (text.trim().isEmpty && empty < 2) {
            empty++;
            continue;
          }
          messages.add({'role': 'assistant', 'content': content});
          onEvent?.call(AiWriting(text, restart: true));
          final kept = await GroqChat.hold(
            id,
            messages,
            place: thread?.place,
            service: ApiService.anthropic,
          );
          if (thread != null) thread.ids[AiProvider.anthropic] = kept;
          if (text.trim().isEmpty) {
            throw const AiFailure('Claude yanıt vermedi.');
          }
          return text.trim();
        }
        // The turn as it came, thinking blocks and all.
        messages.add({'role': 'assistant', 'content': content});
        if (text.trim().isNotEmpty) onEvent?.call(AiThought(text.trim()));
        final results = <Map<String, Object?>>[];
        for (final c in calls) {
          final callId = '${c['id']}';
          final tool = GroqChat.toolName('${c['name'] ?? ''}', known);
          final input = c['input'];
          final args = input is Map
              ? input.cast<String, Object?>()
              : <String, Object?>{};
          final sign = '$tool${jsonEncode(args)}';
          String said;
          var error = false;
          if (!known.contains(tool)) {
            error = true;
            said =
                '${c['name']} diye bir araç yok. Araçlar: '
                '${(known.toList()..sort()).join(', ')}';
          } else if (!done.add(sign)) {
            said =
                'Bu çağrıyı bu soruda zaten yaptın; sonucu yukarıda. Farklı '
                'bir şey ara ya da cevabını yaz.';
          } else {
            onEvent?.call(AiStep(callId, tool, args: args));
            final got = await host!.call(tool, args);
            onEvent?.call(AiStep(callId, tool, args: args, done: true));
            said = got.length > toolText
                ? '${got.substring(0, toolText)}…'
                : got;
          }
          results.add({
            'type': 'tool_result',
            'tool_use_id': callId,
            'content': said,
            if (error) 'is_error': true,
          });
        }
        // Every result of the turn in one message.
        messages.add({'role': 'user', 'content': results});
      }
      throw const AiFailure('Claude adım sınırında cevabını bitiremedi.');
    } on AiFailure {
      rethrow;
    } catch (e) {
      if (stopped) throw const AiFailure('Durduruldu.');
      throw AiFailure('Claude’a ulaşılamadı: $e');
    } finally {
      http.close(force: true);
      await host?.close();
    }
  }

  /// The question with the documents before it: a PDF whole, a picture
  /// as it is.
  @visibleForTesting
  static List<Map<String, Object?>> userContent(
    String prompt,
    List<AiAttachment> attachments,
  ) => [
    for (final a in attachments) ...[
      if (a.pdf case final pdf?)
        {
          'type': 'document',
          'title': a.name,
          'source': {
            'type': 'base64',
            'media_type': 'application/pdf',
            'data': base64Encode(pdf),
          },
        },
      for (final i in a.images)
        {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': i.mime,
            'data': base64Encode(i.bytes),
          },
        },
    ],
    {'type': 'text', 'text': prompt},
  ];

  /// [messages] with two user turns in a row made one: the budget note
  /// after the tools' results, a question after a kept answer's results.
  @visibleForTesting
  static List<Map<String, Object?>> merged(List<Map<String, Object?>> m) =>
      _merged(m);

  static List<Map<String, Object?>> _merged(List<Map<String, Object?>> m) {
    final out = <Map<String, Object?>>[];
    for (final one in m) {
      if (out.isNotEmpty &&
          out.last['role'] == 'user' &&
          one['role'] == 'user') {
        out.last = {
          'role': 'user',
          'content': [
            ...out.last['content'] as List,
            ...one['content'] as List,
          ],
        };
      } else {
        out.add(one);
      }
    }
    return out;
  }

  static Future<Map<String, Object?>> _request(
    HttpClient http,
    String key,
    Map<String, Object?> body,
    bool Function() stopped,
    String model,
  ) async {
    for (var attempt = 0; ; attempt++) {
      final req = await http.postUrl(
        Uri.parse(endpointForTest ?? ApiService.anthropic.endpoint),
      );
      ApiService.anthropic.headers(key).forEach(req.headers.set);
      if (_fallsBack(model)) {
        req.headers.set('anthropic-beta', 'server-side-fallback-2026-07-01');
      }
      req.headers
        ..set(HttpHeaders.userAgentHeader, 'LifeOS-Folio')
        ..contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close().timeout(const Duration(minutes: 8));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode == 200) {
        return (jsonDecode(text) as Map).cast<String, Object?>();
      }
      if (stopped()) throw const AiFailure('Durduruldu.');
      // Rate limit and overload: a little later, a few times.
      if ((res.statusCode == 429 || res.statusCode == 529) && attempt < 3) {
        await Future<void>.delayed(Duration(seconds: 10 * (attempt + 1)));
        continue;
      }
      throw AiFailure(
        GroqChat.failure(res.statusCode, text, ApiService.anthropic),
      );
    }
  }
}

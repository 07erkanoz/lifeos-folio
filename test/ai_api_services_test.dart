import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/ai/ai_assistant.dart';
import 'package:evrak_convert/services/ai/ai_claude_api.dart';
import 'package:evrak_convert/services/ai/ai_groq.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  final bodies = <Map<String, Object?>>[];
  final heads = <HttpHeaders>[];
  final replies = <(int, Object)>[];
  setUp(() async {
    bodies.clear();
    heads.clear();
    replies.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      heads.add(req.headers);
      bodies.add(
        (jsonDecode(await utf8.decodeStream(req)) as Map)
            .cast<String, Object?>(),
      );
      final (status, body) = replies.removeAt(0);
      req.response
        ..statusCode = status
        ..write(jsonEncode(body));
      await req.response.close();
    });
    final url = 'http://127.0.0.1:${server.port}/v1';
    GroqChat.folderForTest = Directory.systemTemp.createTempSync(
      'folio-api-sohbet-',
    );
    GroqChat.keyForTest = 'anahtar';
    GroqChat.endpointForTest = '$url/chat/completions';
    ClaudeApiChat.endpointForTest = '$url/messages';
  });
  tearDown(() async {
    GroqChat.keyForTest = null;
    GroqChat.folderForTest = null;
    GroqChat.endpointForTest = null;
    ClaudeApiChat.endpointForTest = null;
    await server.close(force: true);
  });

  Map<String, Object?> said(String text) => {
    'choices': [
      {
        'message': {'role': 'assistant', 'content': text},
      },
    ],
  };

  test('every API service is offered on every computer, the programs on '
      'Linux only', () {
    expect(AiProvider.gemini.viaApi, isTrue);
    expect(AiProvider.openai.viaApi, isTrue);
    expect(AiProvider.anthropic.viaApi, isTrue);
    expect(AiProvider.claude.viaApi, isFalse);
    expect(
      AiProvider.offered,
      containsAll([AiProvider.gemini, AiProvider.groq]),
    );
  });

  test('Gemini: 3.8 Flash by default, its effort by tier, no Groq-only '
      'field', () async {
    replies.add((200, said('Cevap.')));
    expect(
      await AiAssistant.ask(AiProvider.gemini, 'Soru', tier: AiTier.strong),
      'Cevap.',
    );
    final b = bodies.single;
    expect(b['model'], 'gemini-3.8-flash');
    expect(b['reasoning_effort'], 'high');
    expect(b.containsKey('disable_tool_validation'), isFalse);
    expect(heads.single.value('authorization'), 'Bearer anahtar');
  });

  test('ChatGPT: no temperature for its reasoning models', () async {
    replies.add((200, said('Tamam.')));
    await AiAssistant.ask(AiProvider.openai, 'Soru', tier: AiTier.normal);
    expect(bodies.single.containsKey('temperature'), isFalse);
    expect(bodies.single['model'], 'gpt-6-luna');
    expect(bodies.single['max_completion_tokens'], 16000);
  });

  test('a wrong Gemini key, said in a list with 400, is said so', () {
    expect(
      GroqChat.failure(
        400,
        jsonEncode([
          {
            'error': {
              'message': 'API key not valid. Please pass a valid API key.',
            },
          },
        ]),
        ApiService.gemini,
      ),
      contains('Gemini anahtarı geçersiz'),
    );
  });

  group('Claude API', () {
    Map<String, Object?> turn(
      List<Map<String, Object?>> content,
      String stop,
    ) => {'content': content, 'stop_reason': stop};

    test('Messages API with the effort, Opus falls back on the server, the '
        'thinking kept as it came', () async {
      replies.add((
        200,
        turn([
          {'type': 'thinking', 'thinking': '', 'signature': 'imza'},
          {'type': 'text', 'text': 'İİK m.62 uyarınca 7 gün.'},
        ], 'end_turn'),
      ));
      final thread = AiThread('c1');
      final answer = await AiAssistant.ask(
        AiProvider.anthropic,
        'İtiraz süresi?',
        tier: AiTier.strong,
        thread: thread,
      );
      expect(answer, 'İİK m.62 uyarınca 7 gün.');
      final b = bodies.single;
      expect(b['model'], 'claude-opus-5-5');
      expect(b['output_config'], {'effort': 'high'});
      expect(b['fallbacks'], 'default');
      expect(b['system'], AiPrompts.core);
      expect(heads.single.value('x-api-key'), 'anahtar');
      expect(heads.single.value('anthropic-version'), '2023-06-01');
      expect(
        heads.single.value('anthropic-beta'),
        'server-side-fallback-2026-07-01',
      );
      // Going on: the thinking block goes back unchanged.
      replies.add((
        200,
        turn([
          {'type': 'text', 'text': 'Evet.'},
        ], 'end_turn'),
      ));
      expect(await AiAssistant.goesOn(AiProvider.anthropic, thread), isTrue);
      await AiAssistant.ask(
        AiProvider.anthropic,
        'Emin misin?',
        thread: thread,
      );
      final history = bodies.last['messages']! as List;
      expect(history, hasLength(3));
      expect(((history[1] as Map)['content'] as List).first, {
        'type': 'thinking',
        'thinking': '',
        'signature': 'imza',
      });
    });

    test('Haiku on the light tier, with no server-side fallback', () async {
      replies.add((
        200,
        turn([
          {'type': 'text', 'text': 'Tamam.'},
        ], 'end_turn'),
      ));
      await AiAssistant.ask(AiProvider.anthropic, 'Soru', tier: AiTier.light);
      expect(bodies.single['model'], 'claude-haiku-5-5');
      expect(bodies.single.containsKey('fallbacks'), isFalse);
      expect(heads.single.value('anthropic-beta'), isNull);
    });

    test('a declined request is said so', () {
      replies.add((200, turn(const [], 'refusal')));
      expect(
        () => AiAssistant.ask(AiProvider.anthropic, 'Soru'),
        throwsA(
          isA<AiFailure>().having(
            (f) => f.message,
            'message',
            contains('güvenlik'),
          ),
        ),
      );
    });

    test('two user turns in a row are made one', () {
      final m = ClaudeApiChat.merged([
        {
          'role': 'user',
          'content': [
            {'type': 'tool_result', 'tool_use_id': 'a', 'content': 'x'},
          ],
        },
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'Araç bütçen bitti.'},
          ],
        },
      ]);
      expect(m, hasLength(1));
      expect((m.single['content'] as List), hasLength(2));
    });
  });

  test(
    'a chat goes on after Folio was closed; removed, it is forgotten',
    () async {
      replies.add((200, said('Birinci.')));
      final thread = AiThread('sohbet-9');
      await AiAssistant.ask(AiProvider.gemini, 'Soru 1', thread: thread);
      final file = File('${GroqChat.folderForTest!.path}/gemini-sohbet-9.json');
      expect(file.existsSync(), isTrue);
      // As read again from disk by a Folio opened anew.
      GroqChat.dropMemoryForTest();
      expect(await AiAssistant.goesOn(AiProvider.gemini, thread), isTrue);
      replies.add((200, said('İkinci.')));
      await AiAssistant.ask(AiProvider.gemini, 'Soru 2', thread: thread);
      expect((bodies.last['messages']! as List).length, 4);
      await GroqChat.forget('sohbet-9');
      expect(file.existsSync(), isFalse);
    },
  );

  test(
    'Claude caches the prefix; ChatGPT is given the chat\'s cache key',
    () async {
      replies.add((
        200,
        {
          'content': [
            {'type': 'text', 'text': 'A'},
          ],
          'stop_reason': 'end_turn',
        },
      ));
      await AiAssistant.ask(AiProvider.anthropic, 'Soru');
      expect(bodies.last['cache_control'], {'type': 'ephemeral'});
      replies.add((200, said('B')));
      await AiAssistant.ask(AiProvider.openai, 'Soru', thread: AiThread('s1'));
      expect(bodies.last['prompt_cache_key'], 'folio-s1');
    },
  );

  test(
    'Folio\'s tools run in Folio itself where no server is started',
    () async {
      final here = FolioToolsHere(null);
      final tools = await here.tools();
      expect(
        tools.map((t) => t['name']),
        containsAll(['mevzuat_madde', 'sure_hesapla']),
      );
      final got = await here.call('sure_hesapla', {
        'baslangic': '2026-11-02',
        'miktar': 7,
        'birim': 'gun',
        'yargi': 'icra',
        'madde': 'İİK m.62',
      });
      expect(jsonDecode(got)['son_gun'], '2026-11-09');
    },
  );
}

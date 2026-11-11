import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/ai/ai_assistant.dart';
import 'package:evrak_convert/services/ai/ai_groq.dart';

void main() {
  group('tool names', () {
    const known = {'karar_ara', 'mevzuat_madde', 'mevzuat_icindekiler'};
    test('as the model meant them', () {
      expect(GroqChat.toolName('karar_ara', known), 'karar_ara');
      expect(GroqChat.toolName('functions/karar_ara', known), 'karar_ara');
      expect(
        GroqChat.toolName('functions.mevzuat_madde', known),
        'mevzuat_madde',
      );
      expect(GroqChat.toolName('ara', known), 'karar_ara');
      // Two tools start with "mevzuat_": not guessed.
      expect(GroqChat.toolName('mevzuat', known), 'mevzuat');
    });
  });

  test('a request with no tools keeps what the tools said, as text', () {
    final out = GroqChat.writingOnly([
      {'role': 'system', 'content': 'kurallar'},
      {'role': 'user', 'content': 'soru'},
      {
        'role': 'assistant',
        'content': null,
        'tool_calls': [
          {'id': 'a'},
        ],
      },
      {'role': 'tool', 'tool_call_id': 'a', 'content': 'madde metni'},
    ]);
    expect(out.map((m) => m['role']), ['system', 'user', 'user']);
    expect(out.last['content'], contains('madde metni'));
  });

  test('a long conversation is shortened from its oldest tool answer', () {
    final messages = [
      {'role': 'tool', 'content': 'a' * 200000},
      {'role': 'tool', 'content': 'b' * 200000},
      {'role': 'user', 'content': 'soru'},
    ];
    GroqChat.shorten(messages);
    expect('${messages[0]['content']}'.length, lessThan(2000));
    expect('${messages[1]['content']}'.length, 200000);
  });

  test('Groq refusals in Turkish', () {
    expect(GroqChat.failure(401, '{}'), contains('anahtarı geçersiz'));
    expect(GroqChat.failure(429, '{}'), contains('sınırınız'));
    expect(
      GroqChat.failure(
        400,
        jsonEncode({
          'error': {'message': 'context_length_exceeded'},
        }),
      ),
      contains('çok uzun'),
    );
  });

  group('asking', () {
    late HttpServer server;
    final bodies = <Map<String, Object?>>[];
    final replies = <(int, Object)>[];
    setUp(() async {
      bodies.clear();
      replies.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
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
      GroqChat.keyForTest = 'gsk_test';
      GroqChat.endpointForTest =
          'http://127.0.0.1:${server.port}/openai/v1/chat/completions';
    });
    tearDown(() async {
      GroqChat.keyForTest = null;
      GroqChat.endpointForTest = null;
      await server.close(force: true);
    });

    Map<String, Object?> said(String text) => {
      'choices': [
        {
          'message': {'role': 'assistant', 'content': text},
        },
      ],
    };

    test(
      'an empty answer is asked for again; the conversation goes on',
      () async {
        replies
          ..add((200, said('')))
          ..add((200, said('İİK m.62 uyarınca 7 gün.')));
        final thread = AiThread('t1');
        final events = <AiEvent>[];
        final answer = await AiAssistant.ask(
          AiProvider.groq,
          'İtiraz süresi?',
          tier: AiTier.strong,
          thread: thread,
          onEvent: events.add,
        );
        expect(answer, 'İİK m.62 uyarınca 7 gün.');
        expect(bodies, hasLength(2));
        expect(bodies.first['reasoning_effort'], 'high');
        expect(bodies.first['model'], 'openai/gpt-oss-120b');
        expect((bodies.first['messages'] as List).first, {
          'role': 'system',
          'content': AiPrompts.core,
        });
        expect(events.whereType<AiWriting>(), isNotEmpty);
        expect(await AiAssistant.goesOn(AiProvider.groq, thread), isTrue);

        replies.add((200, said('Evet.')));
        await AiAssistant.ask(AiProvider.groq, 'Emin misin?', thread: thread);
        final roles = [
          for (final m in bodies.last['messages'] as List) (m as Map)['role'],
        ];
        expect(roles, ['system', 'user', 'assistant', 'user']);
      },
    );

    test('a tool named wrongly is asked again; a held id unknown is not '
        'gone on with', () async {
      replies
        ..add((
          400,
          {
            'error': {'code': 'tool_use_failed'},
          },
        ))
        ..add((200, said('Tamam.')));
      expect(await AiAssistant.ask(AiProvider.groq, 'Soru'), 'Tamam.');
      final thread = AiThread('t2', {AiProvider.groq: 'eski'});
      expect(await AiAssistant.goesOn(AiProvider.groq, thread), isFalse);
      expect(thread.ids, isEmpty);
    });

    test('a refused key is said so', () async {
      replies.add((
        401,
        {
          'error': {'message': 'Invalid API Key'},
        },
      ));
      expect(
        () => AiAssistant.ask(AiProvider.groq, 'Soru'),
        throwsA(
          isA<AiFailure>().having(
            (f) => f.message,
            'message',
            contains('anahtarı geçersiz'),
          ),
        ),
      );
    });
  });
}

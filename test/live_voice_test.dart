import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/ai/ai_groq.dart';
import 'package:evrak_convert/services/voice/live_audio.dart';
import 'package:evrak_convert/services/voice/live_conversation.dart';
import 'package:evrak_convert/services/voice/live_session.dart';
import 'package:evrak_convert/services/voice/live_tools.dart';
import 'package:evrak_convert/services/voice/live_usage.dart';
import 'package:evrak_convert/services/voice/speech_gate.dart';
import 'package:evrak_convert/services/voice/voice_settings.dart';

class FakeSession extends LiveSession {
  FakeSession(super.events, {this.fails = false});
  final bool fails;
  final sentAudio = <Uint8List>[];
  final answers = <Map<String, Object?>>[];
  String? instruction;
  bool isOpen = false;

  @override
  bool get open => isOpen;

  @override
  Future<void> connect({
    required String key,
    required String instruction,
    List<Map<String, Object?>> tools = const [],
    bool webSearch = false,
    String voice = '',
  }) async {
    if (fails) throw const LiveFailure('yok');
    this.instruction = instruction;
    isOpen = true;
  }

  @override
  void sendAudio(Uint8List pcm) => sentAudio.add(pcm);

  @override
  void answerTools(List<Map<String, Object?>> answers) =>
      this.answers.addAll(answers);

  @override
  Future<void> close() async => isOpen = false;
}

class FakeMicrophone extends LiveMicrophone {
  void Function(Uint8List)? take;
  @override
  Future<void> open(void Function(Uint8List pcm) take) async =>
      this.take = take;
  @override
  Future<void> close() async => take = null;
}

class FakeSpeaker extends LiveSpeaker {
  final written = <Uint8List>[];
  @override
  bool get playing => false;
  @override
  void write(Uint8List pcm) => written.add(pcm);
  @override
  void finish() {}
  @override
  Future<void> clear() async {}
}

class FakeDetector implements SpeechDetector {
  bool speech = false;
  @override
  bool hears(Float32List samples) => speech;
  @override
  void reset() {}
  @override
  void dispose() {}
}

Uint8List piece([int bytes = 640]) => Uint8List(bytes);

void main() {
  group('Live session', () {
    test(
      'setup asks for audio, tools and both transcripts; no language code',
      () {
        final s =
            LiveSession.setup(
                  instruction: 'talimat',
                  tools: [
                    {'name': FolioLiveTools.brainTool},
                  ],
                  voice: 'Leda',
                )['setup']
                as Map;
        expect(s['model'], 'models/${LiveSession.model}');
        final gen = s['generationConfig'] as Map;
        expect(gen['responseModalities'], ['AUDIO']);
        expect(jsonEncode(gen), isNot(contains('languageCode')));
        expect(jsonEncode(gen), contains('Leda'));
        expect(jsonEncode(s['tools']), contains(FolioLiveTools.brainTool));
        expect(jsonEncode(s['tools']), isNot(contains('googleSearch')));
        expect(s.containsKey('inputAudioTranscription'), isTrue);
        expect(s.containsKey('outputAudioTranscription'), isTrue);
      },
    );

    test('messages from Live reach their events', () {
      final got = <String>[];
      final e = LiveEvents()
        ..audio = ((p) => got.add('ses ${p.length}'))
        ..tools = ((c) =>
            got.add('araç ${c.single.name} ${c.single.args['soru']}'))
        ..heard = ((t) => got.add('duydu $t'))
        ..said = ((t) => got.add('dedi $t'))
        ..interrupted = (() => got.add('kesildi'))
        ..turnComplete = (() => got.add('bitti'))
        ..usage = ((u) => got.add('kullanım ${u['promptTokenCount']}'));
      final s = LiveSession(e);
      s.take(
        jsonEncode({
          'serverContent': {
            'modelTurn': {
              'parts': [
                {
                  'inlineData': {
                    'data': base64Encode([1, 2, 3]),
                  },
                },
              ],
            },
            'inputTranscription': {'text': 'yarın ne var'},
            'outputTranscription': {'text': 'bakıyorum'},
            'interrupted': true,
            'turnComplete': true,
          },
        }),
      );
      s.take(
        utf8.encode(
          jsonEncode({
            'toolCall': {
              'functionCalls': [
                {
                  'id': '1',
                  'name': 'folio_ajan_sor',
                  'args': {'soru': 'süreler'},
                },
              ],
            },
            'usageMetadata': {'promptTokenCount': 42},
          }),
        ),
      );
      s.take('bozuk');
      expect(got, [
        'ses 3',
        'duydu yarın ne var',
        'dedi bakıyorum',
        'kesildi',
        'bitti',
        'araç folio_ajan_sor süreler',
        'kullanım 42',
      ]);
    });
  });

  test('a turn costs its tokens at each modality’s price', () {
    final c = LiveCost.of({
      'promptTokenCount': 1000,
      'responseTokenCount': 600,
      'thoughtsTokenCount': 50,
      'promptTokensDetails': [
        {'modality': 'AUDIO', 'tokenCount': 400},
        {'modality': 'TEXT', 'tokenCount': 600},
      ],
      'responseTokensDetails': [
        {'modality': 'AUDIO', 'tokenCount': 500},
      ],
    });
    expect([c.textIn, c.audioIn, c.textOut, c.audioOut], [600, 400, 150, 500]);
    expect(
      c.dollars,
      closeTo((600 * .75 + 400 * 3 + 150 * 4.5 + 500 * 12) / 1e6, 1e-12),
    );
    // No details: the answer was sound.
    expect(LiveCost.of({'responseTokenCount': 10}).audioOut, 10);
  });

  test('the gate gives the sound from just before speech, once', () {
    final d = FakeDetector();
    final g = SpeechGate(d, keep: const Duration(milliseconds: 60));
    for (var i = 0; i < 5; i++) {
      expect(g.take(piece()), isNull); // 20 ms each
    }
    d.speech = true;
    final kept = g.take(piece());
    // 60 ms kept: three pieces, the last one the one that began.
    expect(kept, hasLength(3));
    expect(g.take(piece()), isNull);
  });

  test('a new session is told only the last lines, shortened', () {
    final lines = [
      for (var i = 0; i < 12; i++)
        LiveLine(i.isEven ? 'avukat' : 'ajan', 'satır $i'),
      LiveLine('bilgi', 'gösterilmez'),
      LiveLine('avukat', 'x' * 400),
    ];
    final c = LiveConversation.context(lines);
    expect(c, isNot(contains('satır 4\n')));
    expect(c, contains('Sen: satır 11'));
    expect(c, isNot(contains('gösterilmez')));
    expect(c, contains('${'x' * 300}…'));
    expect(LiveConversation.context(const []), isEmpty);
  });

  group('conversation', () {
    late List<FakeSession> sessions;
    late FakeMicrophone mic;
    late FakeSpeaker speaker;
    late FakeDetector detector;
    var failNext = false;
    late List<String> asked;

    LiveConversation make({String? key = 'anahtar'}) {
      sessions = [];
      mic = FakeMicrophone();
      speaker = FakeSpeaker();
      detector = FakeDetector();
      asked = [];
      return LiveConversation(
        tools: BrainOnlyTools((q) async {
          asked.add(q);
          return 'Bugün iki duruşma var.';
        }),
        key: () async => key,
        session: (e) {
          final s = FakeSession(e, fails: failNext);
          sessions.add(s);
          return s;
        },
        microphone: mic,
        speaker: speaker,
        detector: () async => detector,
        prepare: () async {},
      );
    }

    setUp(() => failNext = false);

    test('hands free, nothing goes out until someone speaks', () async {
      final c = make();
      await c.start(handsFree: true);
      expect(c.state, LiveState.waiting);
      mic.take!(piece());
      mic.take!(piece());
      expect(sessions, isEmpty);
      detector.speech = true;
      mic.take!(piece());
      await pumpEventQueue();
      expect(sessions, hasLength(1));
      expect(c.state, LiveState.listening);
      // The kept sound went with it.
      expect(sessions.single.sentAudio, hasLength(3));
      mic.take!(piece());
      expect(sessions.single.sentAudio, hasLength(4));
      await c.stop();
    });

    test('no key: a plain message, nothing opened', () async {
      final c = make(key: null);
      await c.start();
      expect(c.state, LiveState.off);
      expect(c.error, contains('Gemini anahtarı'));
    });

    test(
      'each answer opens the next question’s session with the lines so far',
      () async {
        final c = make();
        await c.start();
        final first = sessions.single;
        first.events.heard!('yarın ne var');
        first.events.said!('iki duruşma');
        first.events.usage!({
          'promptTokenCount': 100,
          'responseTokenCount': 50,
        });
        first.events.turnComplete!();
        await pumpEventQueue();
        expect(sessions, hasLength(2));
        expect(first.isOpen, isFalse);
        expect(sessions.last.instruction, contains('Avukat: yarın ne var'));
        expect(c.spent.output, 50);
        await c.stop();
      },
    );

    test('a session that cannot be renewed ends the conversation after three turns', () async {
      final c = make();
      await c.start();
      failNext = true;
      final s = sessions.single;
      for (var i = 0; i < 3; i++) {
        s.events.turnComplete!();
        await pumpEventQueue();
      }
      expect(c.state, LiveState.off);
      expect(c.lines.last.text, contains('maliyet artmasın'));
    });

    test('a tool call goes to the brain and its answer back to Live', () async {
      final c = make();
      await c.start();
      final s = sessions.single;
      s.events.tools!([
        const LiveToolCall('7', FolioLiveTools.brainTool, {'soru': 'bugün'}),
      ]);
      expect(c.state, LiveState.working);
      await pumpEventQueue();
      expect(asked, ['bugün']);
      expect(s.answers.single['id'], '7');
      expect(
        (s.answers.single['response'] as Map)['sonuc'],
        'Bugün iki duruşma var.',
      );
      await c.stop();
    });

    test('without headphones, nothing is sent while Live speaks', () async {
      final c = make();
      await c.start();
      final s = sessions.single;
      s.events.audio!(piece());
      mic.take!(piece());
      expect(s.sentAudio, isEmpty);
      c.headphones = true;
      mic.take!(piece());
      expect(s.sentAudio, hasLength(1));
      await c.stop();
    });

    test('hands free, a session Live closes goes back to waiting', () async {
      final c = make();
      await c.start(handsFree: true);
      detector.speech = true;
      mic.take!(piece());
      await pumpEventQueue();
      sessions.single.events.closed!('1011');
      expect(c.state, LiveState.waiting);
      await c.stop();
    });
  });

  group('Folio tools for Live', () {
    late FakeHost host;
    late List<String> prompts;
    FolioLiveTools make() {
      host = FakeHost();
      prompts = [];
      return FolioLiveTools(
        brain: (q) async => 'beyin: $q',
        host: () async => host,
        flash: (prompt, _) async {
          prompts.add(prompt);
          return 'kısa özet';
        },
      );
    }

    test('only the core tools are declared, with the finding ones', () async {
      final names = [for (final d in await make().declarations()) d['name']];
      expect(names, contains('ajanda'));
      expect(names, isNot(contains('kasa')));
      expect(names, isNot(contains('taslak_oner')));
      expect(
        names,
        containsAll([
          FolioLiveTools.findTool,
          FolioLiveTools.runTool,
          FolioLiveTools.askText,
          FolioLiveTools.brainTool,
        ]),
      );
    });

    test('a tool is found by its Turkish words and then declared', () async {
      final t = make();
      final found = await t.call(FolioLiveTools.findTool, {
        'ihtiyac': 'müvekkilin kasasındaki bakiye',
      });
      expect(((found['araclar'] as List).first as Map)['ad'], 'kasa');
      final missing = await t.call(FolioLiveTools.runTool, {'ad': 'kasa'});
      expect(missing['hata'], contains('muvekkil'));
      final ran = await t.call(FolioLiveTools.runTool, {
        'ad': 'kasa',
        'argumanlar': '{"muvekkil": "Ayşe"}',
      });
      expect(ran['sonuc'], '{"bakiye": 5}');
      expect(host.calls.last, 'kasa {"muvekkil":"Ayşe"}');
      final names = [for (final d in await t.declarations()) d['name']];
      expect(names, contains('kasa'));
    });

    test(
      'a long answer is summarized for the question and kept whole',
      () async {
        final t = make();
        final r = await t.call('ajanda', {}, question: 'yarın ne var');
        expect(r['ozet'], 'kısa özet');
        expect(prompts.single, contains('yarın ne var'));
        expect(t.remembered, contains('kısa özet'));
        final asked = await t.call(FolioLiveTools.askText, {
          'metin_id': r['metin_id'],
          'soru': 'saat kaçta',
        });
        expect(asked['cevap'], 'kısa özet');
        expect(prompts.last, contains('x' * 3000));
      },
    );

    test('heavy work goes to the AI program', () async {
      final r = await make().call(FolioLiveTools.brainTool, {
        'soru': 'dilekçe',
      });
      expect(r['sonuc'], 'beyin: dilekçe');
    });
  });

  test('voice settings are off until turned on', () {
    expect(VoiceSettings.fromJson(null).on, isFalse);
    final s = VoiceSettings.fromJson(
      const VoiceSettings(on: true, headphones: true, voice: 'Leda').toJson(),
    );
    expect([s.on, s.headphones, s.voice], [true, true, 'Leda']);
  });
}

class FakeHost implements FolioToolHost {
  final calls = <String>[];
  @override
  Future<List<Map<String, Object?>>> tools() async => [
    {
      'name': 'ajanda',
      'description': 'Duruşmalar ve süreler',
      'inputSchema': {'type': 'object', 'properties': {}},
    },
    {
      'name': 'kasa',
      'description': 'Müvekkilin kasa hareketleri ve bakiyesi',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'muvekkil': {'type': 'string'},
        },
        'required': ['muvekkil'],
      },
    },
    {'name': 'taslak_oner', 'description': 'panel'},
  ];
  @override
  Future<String> call(String name, Map<String, Object?> args) async {
    calls.add('$name ${jsonEncode(args)}');
    return name == 'ajanda' ? 'x' * 3000 : '{"bakiye": 5}';
  }

  @override
  Future<void> close() async {}
}

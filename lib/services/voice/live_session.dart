import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One Gemini Live conversation over its WebSocket: Folio Ajan's voice.
///
/// Taken from AvukatOS Asistan (`canli.dart`), where it has been used in the
/// field. The lawyer's own Gemini key is sent in a header, never in the
/// address. Live re-bills the whole context every turn and has no cache, so
/// the conversation keeps each session short ([LiveConversation] opens a
/// new one for each question).
class LiveSession {
  LiveSession(
    this.events, {
    Future<WebSocket> Function(String, Map<String, String>)? connect,
  }) : _connect = connect ?? _socket;

  static const model = String.fromEnvironment(
    'FOLIO_LIVE_MODEL',
    defaultValue: 'gemini-3.8-live',
  );

  static const address =
      'wss://generativelanguage.googleapis.com/ws/'
      'google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

  /// The microphone's rate, the only one Live takes.
  static const inputRate = 16000;

  /// The rate of the sound Live sends back.
  static const outputRate = 24000;

  static Future<WebSocket> _socket(String url, Map<String, String> headers) =>
      WebSocket.connect(url, headers: headers);

  final LiveEvents events;
  final Future<WebSocket> Function(String, Map<String, String>) _connect;
  WebSocket? _ws;
  final _ready = Completer<void>();
  bool _closed = false;

  bool get open => _ws != null && !_closed;

  /// The setup message, apart for the tests.
  static Map<String, Object?> setup({
    required String instruction,
    required List<Map<String, Object?>> tools,
    bool webSearch = false,
    String voice = '',
  }) => {
    'setup': {
      'model': 'models/$model',
      'generationConfig': {
        'responseModalities': ['AUDIO'],
        // Native audio chooses the language itself; a language code is not
        // taken.
        if (voice.isNotEmpty)
          'speechConfig': {
            'voiceConfig': {
              'prebuiltVoiceConfig': {'voiceName': voice},
            },
          },
      },
      'systemInstruction': {
        'parts': [
          {'text': instruction},
        ],
      },
      'tools': [
        if (webSearch) {'googleSearch': <String, Object?>{}},
        if (tools.isNotEmpty) {'functionDeclarations': tools},
      ],
      // A television or a talk across the room is not a question.
      'realtimeInputConfig': {
        'automaticActivityDetection': {
          'startOfSpeechSensitivity': 'START_SENSITIVITY_LOW',
        },
      },
      'inputAudioTranscription': <String, Object?>{},
      'outputAudioTranscription': <String, Object?>{},
    },
  };

  Future<void> connect({
    required String key,
    required String instruction,
    List<Map<String, Object?>> tools = const [],
    bool webSearch = false,
    String voice = '',
  }) async {
    final ws = _ws = await _connect(address, {
      'x-goog-api-key': key,
    }).timeout(const Duration(seconds: 20));
    ws.listen(
      _take,
      onDone: () => _end(
        'bağlantı kapandı (${ws.closeCode ?? ''} ${ws.closeReason ?? ''})'
            .trim(),
      ),
      onError: (Object e) => _end('bağlantı hatası: $e'),
      cancelOnError: true,
    );
    _send(
      setup(
        instruction: instruction,
        tools: tools,
        webSearch: webSearch,
        voice: voice,
      ),
    );
    await _ready.future.timeout(const Duration(seconds: 20));
  }

  void _send(Map<String, Object?> message) {
    if (!open) return;
    _ws!.add(jsonEncode(message));
  }

  /// 16-bit little-endian mono PCM at [inputRate].
  void sendAudio(Uint8List pcm) => _send({
    'realtimeInput': {
      'audio': {
        'data': base64Encode(pcm),
        'mimeType': 'audio/pcm;rate=$inputRate',
      },
    },
  });

  void sendText(String text) => _send({
    'realtimeInput': {'text': text},
  });

  void answerTools(List<Map<String, Object?>> answers) => _send({
    'toolResponse': {'functionResponses': answers},
  });

  /// One message from Live, apart for the tests.
  void take(Object? raw) => _take(raw);

  void _take(Object? raw) {
    final Map m;
    try {
      final text = raw is String ? raw : utf8.decode(raw as List<int>);
      m = jsonDecode(text) as Map;
    } catch (_) {
      return;
    }
    if (m.containsKey('setupComplete')) {
      if (!_ready.isCompleted) _ready.complete();
      return;
    }
    final call = m['toolCall'];
    if (call is Map) {
      final calls = [
        for (final f
            in (call['functionCalls'] as List? ?? const []).whereType<Map>())
          LiveToolCall(
            '${f['id'] ?? ''}',
            '${f['name']}',
            ((f['args'] as Map?) ?? const {}).cast<String, Object?>(),
          ),
      ];
      if (calls.isNotEmpty) events.tools?.call(calls);
    }
    final cancelled = m['toolCallCancellation'];
    if (cancelled is Map) {
      events.toolsCancelled?.call([
        for (final id in (cancelled['ids'] as List? ?? const [])) '$id',
      ]);
    }
    if (m['goAway'] != null) events.goingAway?.call();
    final usage = m['usageMetadata'];
    if (usage is Map) events.usage?.call(usage);
    final content = m['serverContent'];
    if (content is! Map) return;
    final turn = content['modelTurn'];
    if (turn is Map) {
      for (final p in (turn['parts'] as List? ?? const []).whereType<Map>()) {
        final data = p['inlineData'];
        if (data is Map && data['data'] is String) {
          events.audio?.call(base64Decode(data['data'] as String));
        }
      }
    }
    final heard = content['inputTranscription'];
    if (heard is Map && '${heard['text'] ?? ''}'.isNotEmpty) {
      events.heard?.call('${heard['text']}');
    }
    final said = content['outputTranscription'];
    if (said is Map && '${said['text'] ?? ''}'.isNotEmpty) {
      events.said?.call('${said['text']}');
    }
    if (content['interrupted'] == true) events.interrupted?.call();
    if (content['turnComplete'] == true) events.turnComplete?.call();
  }

  void _end(String why) {
    if (_closed) return;
    _closed = true;
    if (!_ready.isCompleted) _ready.completeError(LiveFailure(why));
    events.closed?.call(why);
  }

  Future<void> close() async {
    _closed = true;
    try {
      await _ws?.close();
    } catch (_) {}
    _ws = null;
  }
}

class LiveToolCall {
  const LiveToolCall(this.id, this.name, this.args);
  final String id, name;
  final Map<String, Object?> args;
}

class LiveFailure implements Exception {
  const LiveFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What a [LiveSession] hears from Live.
class LiveEvents {
  void Function(Uint8List pcm)? audio;
  void Function(List<LiveToolCall> calls)? tools;
  void Function(List<String> ids)? toolsCancelled;

  /// The lawyer's words, written down as they come.
  void Function(String text)? heard;

  /// Live's words, written down as they come.
  void Function(String text)? said;
  void Function()? interrupted;
  void Function()? turnComplete;
  void Function()? goingAway;
  void Function(Map usage)? usage;
  void Function(String why)? closed;
}

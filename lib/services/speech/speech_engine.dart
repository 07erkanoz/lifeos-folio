import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// The voice, in an isolate of its own: making a sentence's sound takes a
/// good part of a second of the processor, which the page is not to wait on.
class VoiceWorker {
  VoiceWorker._(this._isolate, this._send, this._replies);

  /// Supertonic's second voice, a woman's, the one chosen by ear.
  static const defaultVoice = 1;

  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _replies;
  final _waiting = <int, Completer<SpokenAudio>>{};
  var _next = 0;

  /// [library] is the folder sherpa-onnx's own library is in, where the
  /// system would not find it by name — only ever under test.
  static Future<VoiceWorker> start(String modelDir, {String? library}) async {
    final replies = ReceivePort();
    final ready = Completer<SendPort>();
    late VoiceWorker worker;
    replies.listen((message) {
      switch (message) {
        case SendPort port:
          ready.complete(port);
        case String error when !ready.isCompleted:
          ready.completeError(StateError(error));
        case (int id, TransferableTypedData data, int rate):
          worker._waiting
              .remove(id)
              ?.complete(SpokenAudio(data.materialize().asFloat32List(), rate));
        case (int id, String error):
          worker._waiting.remove(id)?.completeError(StateError(error));
      }
    });
    final isolate = await Isolate.spawn(_voiceMain, (
      replies.sendPort,
      modelDir,
      library,
    ), debugName: 'folio-ses-okuma');
    try {
      worker = VoiceWorker._(isolate, await ready.future, replies);
    } catch (_) {
      isolate.kill();
      replies.close();
      rethrow;
    }
    return worker;
  }

  /// The sound of [text], as the voice says it.
  Future<SpokenAudio> say(
    String text, {
    int voice = defaultVoice,
    double speed = 1.0,
  }) {
    final id = _next++;
    final done = Completer<SpokenAudio>();
    _waiting[id] = done;
    _send.send((id, text, voice, speed));
    return done.future;
  }

  void dispose() {
    for (final w in _waiting.values) {
      w.completeError(StateError('Okuma durduruldu.'));
    }
    _waiting.clear();
    _isolate.kill(priority: Isolate.immediate);
    _replies.close();
  }
}

class SpokenAudio {
  const SpokenAudio(this.samples, this.sampleRate);
  final Float32List samples;
  final int sampleRate;
}

void _voiceMain((SendPort, String, String?) args) {
  final (reply, dir, library) = args;
  final sherpa.OfflineTts tts;
  try {
    sherpa.initBindings(library);
    String at(String name) => p.join(dir, name);
    tts = sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          supertonic: sherpa.OfflineTtsSupertonicModelConfig(
            durationPredictor: at('duration_predictor.int8.onnx'),
            textEncoder: at('text_encoder.int8.onnx'),
            vectorEstimator: at('vector_estimator.int8.onnx'),
            vocoder: at('vocoder.int8.onnx'),
            ttsJson: at('tts.json'),
            unicodeIndexer: at('unicode_indexer.bin'),
            voiceStyle: at('voice.bin'),
          ),
          numThreads: 2,
          debug: false,
        ),
      ),
    );
  } catch (e) {
    reply.send('Ses modeli açılamadı: $e');
    return;
  }
  final requests = ReceivePort();
  reply.send(requests.sendPort);
  requests.listen((message) {
    final (id, text, voice, speed) = message as (int, String, int, double);
    try {
      final audio = tts.generateWithConfig(
        text: text,
        config: sherpa.OfflineTtsGenerationConfig(
          sid: voice,
          speed: speed,
          numSteps: 8,
          extra: const {'lang': 'tr'},
        ),
      );
      reply.send((
        id,
        TransferableTypedData.fromList([audio.samples]),
        audio.sampleRate,
      ));
    } catch (e) {
      reply.send((id, '$e'));
    }
  });
}

/// Hearing and writing down, in an isolate of its own: Silero finds where
/// each stretch of speech starts and stops, and Whisper turbo writes each
/// one down as it ends. What comes back is a sentence or so at a time.
class ListenWorker {
  ListenWorker._(this._isolate, this._send, this._replies);

  /// What the recogniser is given: 16 kHz, one channel.
  static const sampleRate = 16000;

  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _replies;
  final _texts = StreamController<String>.broadcast();
  final _busy = StreamController<bool>.broadcast();
  Completer<void>? _flushed;

  /// Each stretch of speech, written down.
  Stream<String> get texts => _texts.stream;

  /// True while a stretch is being written down.
  Stream<bool> get busy => _busy.stream;

  static Future<ListenWorker> start(String modelDir, {String? library}) async {
    final replies = ReceivePort();
    final ready = Completer<SendPort>();
    late ListenWorker worker;
    replies.listen((message) {
      switch (message) {
        case SendPort port:
          ready.complete(port);
        case String error when !ready.isCompleted:
          ready.completeError(StateError(error));
        case ('text', String text):
          worker._texts.add(text);
        case ('busy', bool busy):
          worker._busy.add(busy);
        case 'flushed':
          worker._flushed?.complete();
          worker._flushed = null;
        case ('error', String error):
          worker._texts.addError(StateError(error));
      }
    });
    final isolate = await Isolate.spawn(_listenMain, (
      replies.sendPort,
      modelDir,
      library,
    ), debugName: 'folio-ses-yazma');
    try {
      worker = ListenWorker._(isolate, await ready.future, replies);
    } catch (_) {
      isolate.kill();
      replies.close();
      rethrow;
    }
    return worker;
  }

  /// More of what the microphone heard, at [sampleRate].
  void feed(Float32List samples) =>
      _send.send(TransferableTypedData.fromList([samples]));

  /// Writes down whatever was still being said when the microphone stopped.
  Future<void> flush() {
    final done = _flushed ??= Completer<void>();
    _send.send('flush');
    return done.future;
  }

  void dispose() {
    _flushed?.complete();
    _isolate.kill(priority: Isolate.immediate);
    _replies.close();
    _texts.close();
    _busy.close();
  }
}

void _listenMain((SendPort, String, String?) args) {
  final (reply, dir, library) = args;
  final sherpa.VoiceActivityDetector vad;
  final sherpa.OfflineRecognizer recognizer;
  const window = 512;
  try {
    sherpa.initBindings(library);
    String at(String name) => p.join(dir, name);
    vad = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: at('silero_vad.onnx'),
          // A pause for thought is not the end of what is being said.
          minSilenceDuration: 0.8,
          minSpeechDuration: 0.25,
          windowSize: window,
          // Whisper hears thirty seconds at a time.
          maxSpeechDuration: 25,
        ),
        sampleRate: ListenWorker.sampleRate,
        debug: false,
      ),
      bufferSizeInSeconds: 60,
    );
    recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: at('turbo-encoder.int8.onnx'),
            decoder: at('turbo-decoder.int8.onnx'),
            language: 'tr',
            task: 'transcribe',
          ),
          tokens: at('turbo-tokens.txt'),
          // Measured on eight cores: six threads write a sentence down in
          // half the time it took to say, eight in seven tenths. Two are
          // left for the page and the microphone.
          numThreads: (Platform.numberOfProcessors - 2).clamp(2, 6),
          debug: false,
        ),
      ),
    );
  } catch (e) {
    reply.send('Yazma modeli açılamadı: $e');
    return;
  }

  // FOLIO_SES_KAYIT=<klasör>: what the microphone gave, each stretch the
  // detector cut out and what was written for it are kept there, to tell a
  // mishearing from a bad cut or a bad recording. Off unless asked for.
  final keep = Platform.environment['FOLIO_SES_KAYIT'];
  final heard = <double>[];
  var kept = 0;
  final session = DateTime.now().toIso8601String().replaceAll(
    RegExp(r'[:.]'),
    '-',
  );
  void keepSegment(Float32List samples, String text) {
    if (keep == null) return;
    final dir = Directory(p.join(keep, session))..createSync(recursive: true);
    final name = (++kept).toString().padLeft(3, '0');
    sherpa.writeWave(
      filename: p.join(dir.path, '$name.wav'),
      samples: samples,
      sampleRate: ListenWorker.sampleRate,
    );
    File(p.join(dir.path, 'metin.txt')).writeAsStringSync(
      '$name\t${samples.length / ListenWorker.sampleRate}\t$text\n',
      mode: FileMode.append,
    );
  }

  final pending = <double>[];
  void writeDown() {
    while (!vad.isEmpty()) {
      final segment = vad.front();
      vad.pop();
      reply.send(('busy', true));
      try {
        final stream = recognizer.createStream();
        stream.acceptWaveform(
          samples: segment.samples,
          sampleRate: ListenWorker.sampleRate,
        );
        recognizer.decode(stream);
        final text = recognizer.getResult(stream).text.trim();
        stream.free();
        keepSegment(segment.samples, text);
        if (text.isNotEmpty) reply.send(('text', text));
      } catch (e) {
        reply.send(('error', '$e'));
      } finally {
        reply.send(('busy', false));
      }
    }
  }

  final requests = ReceivePort();
  reply.send(requests.sendPort);
  requests.listen((message) {
    if (message == 'flush') {
      if (keep != null && heard.isNotEmpty) {
        final dir = Directory(p.join(keep, session))
          ..createSync(recursive: true);
        sherpa.writeWave(
          filename: p.join(dir.path, 'tamami.wav'),
          samples: Float32List.fromList(heard),
          sampleRate: ListenWorker.sampleRate,
        );
      }
      if (pending.isNotEmpty) {
        vad.acceptWaveform(Float32List.fromList(pending));
        pending.clear();
      }
      vad.flush();
      writeDown();
      vad.reset();
      reply.send('flushed');
      return;
    }
    final samples = (message as TransferableTypedData)
        .materialize()
        .asFloat32List();
    pending.addAll(samples);
    if (keep != null) heard.addAll(samples);
    var at = 0;
    while (pending.length - at >= window) {
      vad.acceptWaveform(
        Float32List.fromList(pending.sublist(at, at + window)),
      );
      at += window;
    }
    pending.removeRange(0, at);
    writeDown();
  });
}

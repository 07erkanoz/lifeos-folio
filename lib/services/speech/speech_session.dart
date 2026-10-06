import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_recorder/flutter_recorder.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'reading_text.dart';
import 'speech_engine.dart';

/// Reading aloud and dictation are for the desktop: the models are large
/// and a phone has its own of both.
bool get speechAvailable =>
    !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

/// How long a model stays loaded after it was last used. Whisper holds well
/// over a gigabyte, which is not to be kept for nothing.
const _keepLoaded = Duration(minutes: 3);

/// Something that says a sentence.
abstract class Voice {
  Future<SpokenAudio> say(String text, {double speed});
  void dispose();
}

/// Something that hears and writes down.
abstract class Ear {
  Stream<String> get texts;
  Stream<bool> get busy;
  void feed(Float32List samples);
  Future<void> flush();
  void dispose();
}

/// Plays one sentence's sound.
abstract class SpeechPlayer {
  /// Completes when the sound has played out, or was stopped.
  Future<void> play(SpokenAudio audio);
  void pause(bool paused);
  Future<void> stop();
}

/// The microphone, at the rate the ear wants.
abstract class Microphone {
  Future<Stream<Float32List>> open(int sampleRate);
  Future<void> close();
}

enum ReadState { idle, loading, reading, paused }

/// Reading a document aloud, a sentence at a time, the next one made while
/// the last is being heard so that there is no gap between them.
class ReadAloud extends ChangeNotifier {
  ReadAloud({
    Future<Voice> Function(String modelDir)? openVoice,
    SpeechPlayer? player,
  }) : _openVoice = openVoice ?? _workerVoice,
       _player = player ?? SoLoudPlayer();

  static ReadAloud instance = ReadAloud();

  final Future<Voice> Function(String modelDir) _openVoice;
  final SpeechPlayer _player;

  ReadState _state = ReadState.idle;
  ReadState get state => _state;

  /// Who is being read: the page or the preview that asked, so that only it
  /// shows the controls.
  Object? get owner => _owner;
  Object? _owner;

  List<ReadingSentence> _sentences = const [];
  int _index = 0;
  int get index => _index;
  int get count => _sentences.length;
  ReadingSentence? get current =>
      _index < _sentences.length ? _sentences[_index] : null;

  double _speed = 1.0;
  double get speed => _speed;
  set speed(double value) {
    _speed = value;
    notifyListeners();
  }

  String? _error;
  String? get error => _error;

  Future<Voice>? _voice;
  String? _voiceDir;
  Timer? _unload;
  int _run = 0;
  Completer<void>? _resumed;

  /// Reads [sentences] from the first, telling [onSentence] as each one
  /// begins. Whatever was being read before stops.
  Future<void> read(
    List<ReadingSentence> sentences, {
    required String modelDir,
    Object? owner,
    ValueChanged<ReadingSentence>? onSentence,
  }) async {
    await stop();
    if (sentences.isEmpty) return;
    final run = ++_run;
    _unload?.cancel();
    _owner = owner;
    _sentences = sentences;
    _index = 0;
    _error = null;
    _state = ReadState.loading;
    notifyListeners();
    try {
      if (_voiceDir != modelDir) {
        (await _voice?.catchError((_) => _NoVoice()))?.dispose();
        _voice = null;
      }
      _voiceDir = modelDir;
      final voice = await (_voice ??= _openVoice(modelDir));
      if (run != _run) return;
      var next = voice.say(sentences[0].spoken, speed: _speed);
      for (var i = 0; i < sentences.length; i++) {
        final audio = await next;
        if (run != _run) return;
        if (i + 1 < sentences.length) {
          next = voice.say(sentences[i + 1].spoken, speed: _speed);
        }
        _index = i;
        if (_state != ReadState.paused) _state = ReadState.reading;
        onSentence?.call(sentences[i]);
        notifyListeners();
        while (_resumed != null) {
          await _resumed!.future;
          if (run != _run) return;
        }
        await _player.play(audio);
        if (run != _run) return;
      }
    } catch (e) {
      if (run != _run) return;
      _error = '$e';
      _voice = null;
    }
    if (run != _run) return;
    _finish();
  }

  void pause() {
    if (_state != ReadState.reading && _state != ReadState.loading) return;
    _resumed ??= Completer<void>();
    _player.pause(true);
    _state = ReadState.paused;
    notifyListeners();
  }

  void resume() {
    if (_state != ReadState.paused) return;
    _player.pause(false);
    _resumed?.complete();
    _resumed = null;
    _state = ReadState.reading;
    notifyListeners();
  }

  Future<void> stop() async {
    if (_state == ReadState.idle) return;
    _run++;
    _resumed?.complete();
    _resumed = null;
    await _player.stop();
    _finish();
  }

  void _finish() {
    _state = ReadState.idle;
    _owner = null;
    _sentences = const [];
    _index = 0;
    notifyListeners();
    _unload?.cancel();
    _unload = Timer(_keepLoaded, () async {
      final voice = _voice;
      _voice = null;
      _voiceDir = null;
      (await voice?.catchError((_) => _NoVoice()))?.dispose();
    });
  }

  static Future<Voice> _workerVoice(String dir) async =>
      _WorkerVoice(await VoiceWorker.start(dir));
}

enum ListenState { idle, loading, listening }

/// Writing down what is said, into wherever the caret is.
class Dictation extends ChangeNotifier {
  Dictation({
    Future<Ear> Function(String modelDir)? openEar,
    Microphone? microphone,
  }) : _openEar = openEar ?? _workerEar,
       _microphone = microphone ?? RecorderMicrophone();

  static Dictation instance = Dictation();

  final Future<Ear> Function(String modelDir) _openEar;
  final Microphone _microphone;

  ListenState _state = ListenState.idle;
  ListenState get state => _state;

  Object? get owner => _owner;
  Object? _owner;

  /// True while something heard is being written down.
  bool get writing => _writing;
  bool _writing = false;

  String? _error;
  String? get error => _error;

  Future<Ear>? _ear;
  String? _earDir;
  Timer? _unload;
  StreamSubscription<Float32List>? _heard;
  StreamSubscription<String>? _texts;
  StreamSubscription<bool>? _busy;

  Future<void> start({
    required String modelDir,
    required ValueChanged<String> onText,
    Object? owner,
  }) async {
    await stop();
    _unload?.cancel();
    _owner = owner;
    _error = null;
    _state = ListenState.loading;
    notifyListeners();
    try {
      if (_earDir != modelDir) {
        (await _ear?.catchError((_) => _NoEar()))?.dispose();
        _ear = null;
      }
      _earDir = modelDir;
      final ear = await (_ear ??= _openEar(modelDir));
      if (_state != ListenState.loading) return;
      _texts = ear.texts.listen(
        onText,
        onError: (Object e) {
          _error = '$e';
          notifyListeners();
        },
      );
      _busy = ear.busy.listen((busy) {
        _writing = busy;
        notifyListeners();
      });
      final samples = await _microphone.open(ListenWorker.sampleRate);
      if (_state != ListenState.loading) {
        await _microphone.close();
        return;
      }
      _heard = samples.listen(ear.feed);
      _state = ListenState.listening;
      notifyListeners();
    } catch (e) {
      _error = 'Mikrofon açılamadı: $e';
      _ear = null;
      await _close();
    }
  }

  Future<void> stop() async {
    if (_state == ListenState.idle) return;
    final wasListening = _state == ListenState.listening;
    _state = ListenState.idle;
    notifyListeners();
    await _heard?.cancel();
    _heard = null;
    await _microphone.close();
    // What was being said as the button was pressed is still written down.
    if (wasListening) {
      _writing = true;
      notifyListeners();
      await (await _ear)?.flush();
    }
    await _close();
  }

  Future<void> _close() async {
    await _texts?.cancel();
    await _busy?.cancel();
    _texts = null;
    _busy = null;
    _state = ListenState.idle;
    _writing = false;
    _owner = null;
    notifyListeners();
    _unload?.cancel();
    _unload = Timer(_keepLoaded, () async {
      final ear = _ear;
      _ear = null;
      _earDir = null;
      (await ear?.catchError((_) => _NoEar()))?.dispose();
    });
  }

  static Future<Ear> _workerEar(String dir) async =>
      _WorkerEar(await ListenWorker.start(dir));
}

class _WorkerVoice implements Voice {
  _WorkerVoice(this._worker);
  final VoiceWorker _worker;
  @override
  Future<SpokenAudio> say(String text, {double speed = 1.0}) =>
      _worker.say(text, speed: speed);
  @override
  void dispose() => _worker.dispose();
}

class _NoVoice implements Voice {
  @override
  Future<SpokenAudio> say(String text, {double speed = 1.0}) =>
      throw UnimplementedError();
  @override
  void dispose() {}
}

class _WorkerEar implements Ear {
  _WorkerEar(this._worker);
  final ListenWorker _worker;
  @override
  Stream<String> get texts => _worker.texts;
  @override
  Stream<bool> get busy => _worker.busy;
  @override
  void feed(Float32List samples) => _worker.feed(samples);
  @override
  Future<void> flush() => _worker.flush();
  @override
  void dispose() => _worker.dispose();
}

class _NoEar implements Ear {
  @override
  Stream<String> get texts => const Stream.empty();
  @override
  Stream<bool> get busy => const Stream.empty();
  @override
  void feed(Float32List samples) {}
  @override
  Future<void> flush() async {}
  @override
  void dispose() {}
}

/// Plays through SoLoud, each sentence a sound of its own.
class SoLoudPlayer implements SpeechPlayer {
  SoundHandle? _handle;
  bool _stopped = false;
  bool _paused = false;

  @override
  Future<void> play(SpokenAudio audio) async {
    final soloud = SoLoud.instance;
    if (!soloud.isInitialized) await soloud.init(channels: Channels.mono);
    _stopped = false;
    final source = await soloud.loadMem(
      'okuma.wav',
      wav(audio.samples, audio.sampleRate),
    );
    try {
      final handle = _handle = soloud.play(source, paused: _paused);
      // Watched rather than waited on: a machine whose sound device is gone
      // never says the sound has ended, and the reading must not hang on
      // it. Time spent paused does not count.
      final length = Duration(
        microseconds:
            audio.samples.length *
            Duration.microsecondsPerSecond ~/
            audio.sampleRate,
      );
      var heard = Duration.zero;
      const step = Duration(milliseconds: 100);
      while (!_stopped &&
          soloud.getIsValidVoiceHandle(handle) &&
          heard < length + const Duration(seconds: 2)) {
        await Future<void>.delayed(step);
        if (!_paused) heard += step;
      }
    } finally {
      _handle = null;
      await soloud.disposeSource(source);
    }
  }

  @override
  void pause(bool paused) {
    _paused = paused;
    final handle = _handle;
    if (handle != null) SoLoud.instance.setPause(handle, paused);
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    _paused = false;
    final handle = _handle;
    _handle = null;
    if (handle != null) await SoLoud.instance.stop(handle);
  }
}

/// 16-bit PCM WAV of [samples], which SoLoud reads from memory.
Uint8List wav(Float32List samples, int sampleRate) {
  final data = ByteData(44 + samples.length * 2);
  void text(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(
      44 + i * 2,
      (samples[i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}

/// The system's default microphone, through flutter_recorder.
class RecorderMicrophone implements Microphone {
  StreamController<Float32List>? _out;
  StreamSubscription<AudioDataContainer>? _in;

  @override
  Future<Stream<Float32List>> open(int sampleRate) async {
    final recorder = Recorder.instance;
    await recorder.init(
      format: PCMFormat.f32le,
      sampleRate: sampleRate,
      channels: RecorderChannels.mono,
    );
    recorder.start();
    final out = _out = StreamController<Float32List>();
    _in = recorder.uint8ListStream.listen((data) {
      // Read a float at a time: the bytes need not be aligned for a view.
      final bytes = ByteData.sublistView(data.rawData);
      final samples = Float32List(bytes.lengthInBytes ~/ 4);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = bytes.getFloat32(i * 4, Endian.little);
      }
      out.add(samples);
    });
    recorder.startStreamingData();
    return out.stream;
  }

  @override
  Future<void> close() async {
    final recorder = Recorder.instance;
    if (recorder.isDeviceInitialized()) {
      recorder.stopStreamingData();
      recorder.deinit();
    }
    await _in?.cancel();
    _in = null;
    await _out?.close();
    _out = null;
  }
}

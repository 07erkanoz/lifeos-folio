import 'dart:async';
import 'dart:ffi' show Pointer, Void;
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_recorder/flutter_recorder.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path_provider/path_provider.dart';

import 'live_audio.dart';
import 'vosk.dart';

const _model = 'vosk-model-small-tr-0.3';
const _modelUrl = 'https://alphacephei.com/vosk/models/$_model.zip';

/// The model's zip as it was checked (21 Kasım 2026): a different file is
/// not opened.
const _modelSha256 =
    '8c8d07cec1bce31add14967c16891c84152cdf76d391e33c08278119b9ea96e5';
const _rate = 16000;

enum WakeState { off, preparing, listening, paused, unsupported, failed }

/// "Ajan açıl": heard on this computer by Vosk, nothing leaves it. The
/// small Turkish model (~37 MB) comes down once, the first time it is
/// turned on. While Folio Ajan talks the conversation has the microphone:
/// [pause] / [resume]. AvukatOS Asistan's way, which worked well.
class WakeWord {
  WakeWord._();
  static final WakeWord instance = WakeWord._();

  final state = ValueNotifier<WakeState>(WakeState.off);
  final message = ValueNotifier<String>('');

  /// The last thing heard, its words' confidences and length (Settings).
  final lastHeard = ValueNotifier<String>('');

  /// The phrases that wake it; "merhaba ajan" for a voice whose "ajan
  /// açıl" the model hears badly.
  List<String> phrases = const ['ajan açıl', 'merhaba ajan'];
  double threshold = voskThresholds['orta']!;
  VoidCallback? onWake;

  Pointer<Void>? _modelPtr;
  VoskRecognizer? _recognizer;
  StreamSubscription<AudioDataContainer>? _in;
  DateTime _lastWake = DateTime.fromMillisecondsSinceEpoch(0);
  bool _wanted = false;
  double _voiced = 0;
  AudioSource? _chime;

  bool get on => _wanted;

  Future<Directory> _dir() async {
    final d = Directory(
      '${(await getApplicationSupportDirectory()).path}'
      '${Platform.pathSeparator}vosk',
    );
    await d.create(recursive: true);
    return d;
  }

  Future<String> _modelPath() async {
    final d = await _dir();
    final sep = Platform.pathSeparator;
    final path = '${d.path}$sep$_model';
    // The small Turkish model keeps its files at its root (final.mdl).
    if (await File('$path${sep}final.mdl').exists() ||
        await File('$path${sep}am${sep}final.mdl').exists()) {
      return path;
    }
    message.value = 'Türkçe ses modeli indiriliyor…';
    final zip = File('${d.path}$sep$_model.zip');
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_modelUrl));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('model indirilemedi (HTTP ${response.statusCode})');
      }
      final total = response.contentLength;
      var got = 0;
      final sink = zip.openWrite();
      await for (final part in response) {
        sink.add(part);
        got += part.length;
        if (total > 0) {
          message.value =
              'Türkçe ses modeli indiriliyor… %${(got * 100 / total).floor()}';
        }
      }
      await sink.close();
    } finally {
      client.close();
    }
    message.value = 'Model denetleniyor…';
    final digest = await sha256.bind(zip.openRead()).first;
    if ('$digest' != _modelSha256) {
      await zip.delete();
      throw Exception('İnen ses modeli beklenen dosya değil; açılmadı.');
    }
    message.value = 'Model açılıyor…';
    await extractFileToDisk(zip.path, d.path);
    await zip.delete();
    return path;
  }

  /// Starts listening (the model downloaded if it is not here yet).
  Future<void> start() async {
    _wanted = true;
    if (_recognizer != null) return resume();
    if (state.value == WakeState.preparing) return;
    final v = Vosk.load();
    if (v == null) {
      state.value = WakeState.unsupported;
      message.value = 'Bu derlemede sesle açma yok (Vosk kitaplığı bulunamadı)';
      return;
    }
    state.value = WakeState.preparing;
    try {
      final path = await _modelPath();
      if (!_wanted) return;
      final m = v.model(path);
      _modelPtr = m;
      final own = {for (final f in phrases) ...f.split(' ')};
      _recognizer = v.recognizer(m, [
        ...phrases,
        ...voskDecoys.where((k) => !own.contains(k)),
      ]);
      message.value = '';
      await resume();
    } catch (e) {
      state.value = WakeState.failed;
      message.value = '$e';
    }
  }

  Future<void> stop() async {
    _wanted = false;
    await _closeMicrophone();
    _recognizer?.close();
    _recognizer = null;
    if (_modelPtr != null) Vosk.load()?.freeModel(_modelPtr!);
    _modelPtr = null;
    state.value = WakeState.off;
  }

  /// A conversation takes the microphone: listening stops.
  Future<void> pause() async {
    if (_in == null) return;
    await _closeMicrophone();
    state.value = WakeState.paused;
  }

  /// The conversation is over: back to listening.
  Future<void> resume() async {
    if (!_wanted || _recognizer == null || _in != null) return;
    _recognizer!.reset();
    _voiced = 0;
    try {
      final recorder = Recorder.instance;
      await recorder.init(
        format: PCMFormat.s16le,
        sampleRate: _rate,
        channels: RecorderChannels.mono,
      );
      recorder.start();
      _in = recorder.uint8ListStream.listen(
        (data) => _piece(Uint8List.fromList(data.rawData)),
      );
      recorder.startStreamingData();
      state.value = WakeState.listening;
    } catch (e) {
      state.value = WakeState.failed;
      message.value = 'Mikrofon açılamadı: $e';
    }
  }

  Future<void> _closeMicrophone() async {
    final sub = _in;
    _in = null;
    try {
      final recorder = Recorder.instance;
      if (recorder.isDeviceInitialized()) {
        recorder.stopStreamingData();
        recorder.deinit();
      }
    } catch (_) {}
    await sub?.cancel();
  }

  void _piece(Uint8List pcm) {
    final r = _recognizer;
    if (r == null) return;
    if (pcmLevel(pcm) > .04) _voiced += pcm.length / (_rate * 2);
    final (heard, ended, confidence) = r.feed(pcm);
    final wake = phrases.any(
      (f) => isWakePhrase(
        heard,
        ended,
        f,
        voiced: _voiced,
        confidence: confidence,
        threshold: threshold,
      ),
    );
    if (ended && heard.trim().isNotEmpty) {
      final c = confidence
          .map((k) => '${k.$1} ${k.$2.toStringAsFixed(2)}')
          .join(', ');
      lastHeard.value =
          '"${heard.trim()}" · $c · ${_voiced.toStringAsFixed(1)} sn'
          '${wake ? ' → AÇILDI' : ''}';
    }
    if (ended) _voiced = 0;
    if (!wake) return;
    r.reset();
    final now = DateTime.now();
    if (now.difference(_lastWake).inMilliseconds < 2000) return;
    _lastWake = now;
    unawaited(_woken());
  }

  Future<void> _woken() async {
    await pause();
    await chime();
    onWake?.call();
  }

  /// A short two-tone "dıt-dıt": it heard and is listening.
  Future<void> chime() async {
    try {
      await LiveSpeaker.prepare();
      if (_chime == null) {
        const rate = 16000;
        final n = (rate * .09).round(), gap = (rate * .04).round();
        final b = ByteData((2 * n + gap) * 2);
        void tone(int start, double f) {
          for (var i = 0; i < n; i++) {
            final env = math.min(1.0, math.min(i, n - i) / rate * 60);
            b.setInt16(
              (start + i) * 2,
              (math.sin(2 * math.pi * f * i / rate) * env * .25 * 32767)
                  .round(),
              Endian.little,
            );
          }
        }

        tone(0, 880);
        tone(n + gap, 1320);
        _chime = await SoLoud.instance.loadMem(
          'folio-chime.wav',
          wav(b.buffer.asUint8List(), rate),
        );
      }
      SoLoud.instance.play(_chime!);
      await Future<void>.delayed(const Duration(milliseconds: 260));
    } catch (_) {}
  }
}

/// 16-bit mono PCM in a WAV file.
Uint8List wav(Uint8List pcm, int rate) {
  final h = ByteData(44);
  void text(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      h.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  h.setUint32(4, 36 + pcm.length, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little);
  h.setUint16(22, 1, Endian.little);
  h.setUint32(24, rate, Endian.little);
  h.setUint32(28, rate * 2, Endian.little);
  h.setUint16(32, 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  text(36, 'data');
  h.setUint32(40, pcm.length, Endian.little);
  return Uint8List.fromList([...h.buffer.asUint8List(), ...pcm]);
}

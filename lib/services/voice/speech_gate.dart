import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'live_audio.dart';
import 'live_session.dart';

/// Whether someone is speaking in a stretch of sound.
abstract class SpeechDetector {
  /// Takes [samples] (floats at [LiveSession.inputRate]); true while speech
  /// is heard.
  bool hears(Float32List samples);
  void reset();
  void dispose();
}

/// Jarvis mode's ear without a button: while no Live session is open, the
/// microphone's sound stays on the computer and Silero (a 0.6 MB model, on
/// the processor) only says whether someone has begun to speak. Then the
/// sound kept from just before, and all that follows, goes to Live. Nothing
/// is written down here; that stays Live's.
class SpeechGate {
  SpeechGate(this._detector, {this.keep = const Duration(milliseconds: 1500)});

  final SpeechDetector _detector;

  /// How much sound from before speech was noticed goes with it: the first
  /// syllables come before the detector is sure.
  final Duration keep;

  final _kept = Queue<Uint8List>();
  int _keptBytes = 0;
  bool _hearing = false;

  int get _keepBytes => keep.inMilliseconds * LiveSession.inputRate * 2 ~/ 1000;

  /// Takes one piece of the microphone; returns what was kept, oldest
  /// first, the moment speech begins, and null otherwise.
  List<Uint8List>? take(Uint8List pcm) {
    _kept.add(pcm);
    _keptBytes += pcm.length;
    while (_keptBytes - _kept.first.length >= _keepBytes && _kept.length > 1) {
      _keptBytes -= _kept.removeFirst().length;
    }
    final hearing = _detector.hears(pcmFloats(pcm));
    final began = hearing && !_hearing;
    _hearing = hearing;
    if (!began) return null;
    final out = _kept.toList();
    _kept.clear();
    _keptBytes = 0;
    return out;
  }

  void reset() {
    _kept.clear();
    _keptBytes = 0;
    _hearing = false;
    _detector.reset();
  }

  void dispose() => _detector.dispose();
}

/// Silero through sherpa-onnx, which Folio's dictation already carries.
class SileroDetector implements SpeechDetector {
  SileroDetector._(this._vad);

  static const _asset = 'assets/ses/silero_vad.onnx';
  static const _window = 512;

  /// The model, out of Folio's own files into its folder once: sherpa
  /// reads a path.
  static Future<SileroDetector> open() async {
    final dir = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'ses'),
    );
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'silero_vad.onnx'));
    if (!await file.exists()) {
      final data = await rootBundle.load(_asset);
      final part = File('${file.path}.yarim');
      await part.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await part.rename(file.path);
    }
    return SileroDetector.at(file.path);
  }

  /// Silero from [model], a path; [library] is the folder sherpa-onnx's
  /// own library is in, where the app's bundle is not.
  static SileroDetector at(String model, {String? library}) {
    sherpa.initBindings(library);
    return SileroDetector._(
      sherpa.VoiceActivityDetector(
        config: sherpa.VadModelConfig(
          sileroVad: sherpa.SileroVadModelConfig(
            model: model,
            // A cough or a door is not a question.
            minSpeechDuration: 0.25,
            minSilenceDuration: 0.5,
            threshold: 0.5,
            windowSize: _window,
          ),
          sampleRate: LiveSession.inputRate,
          debug: false,
        ),
        bufferSizeInSeconds: 10,
      ),
    );
  }

  final sherpa.VoiceActivityDetector _vad;
  final _pending = <double>[];

  @override
  bool hears(Float32List samples) {
    _pending.addAll(samples);
    while (_pending.length >= _window) {
      _vad.acceptWaveform(Float32List.fromList(_pending.sublist(0, _window)));
      _pending.removeRange(0, _window);
    }
    // Only whether speech is heard matters: what it was is Live's.
    while (!_vad.isEmpty()) {
      _vad.pop();
    }
    return _vad.isDetected();
  }

  @override
  void reset() {
    _pending.clear();
    _vad.reset();
  }

  @override
  void dispose() => _vad.free();
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_recorder/flutter_recorder.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'live_session.dart';

/// The microphone for Live: 16-bit mono PCM at [LiveSession.inputRate], in
/// the pieces the recorder gives (Live wants 20–40 ms each).
///
/// On Linux the recorder cancels no echo: while Live speaks through the
/// loudspeaker, [LiveConversation] sends nothing unless the lawyer said they
/// wear headphones (or PipeWire's echo-cancel source is the default one).
class LiveMicrophone {
  StreamSubscription<AudioDataContainer>? _in;
  final level = ValueNotifier<double>(0);

  bool get on => _in != null;

  Future<void> open(void Function(Uint8List pcm) take) async {
    if (_in != null) return;
    final recorder = Recorder.instance;
    await recorder.init(
      format: PCMFormat.s16le,
      sampleRate: LiveSession.inputRate,
      channels: RecorderChannels.mono,
    );
    recorder.start();
    _in = recorder.uint8ListStream.listen((data) {
      final pcm = Uint8List.fromList(data.rawData);
      level.value = pcmLevel(pcm);
      take(pcm);
    });
    recorder.startStreamingData();
  }

  Future<void> close() async {
    final recorder = Recorder.instance;
    if (recorder.isDeviceInitialized()) {
      recorder.stopStreamingData();
      recorder.deinit();
    }
    await _in?.cancel();
    _in = null;
    level.value = 0;
  }
}

/// Live's voice: one buffered stream a turn, fed as the pieces come, cut at
/// once when the lawyer speaks over it.
class LiveSpeaker {
  AudioSource? _source;
  SoundHandle? _handle;
  bool _ended = false;
  final level = ValueNotifier<double>(0);

  static Future<void> prepare() async {
    final soloud = SoLoud.instance;
    if (!soloud.isInitialized) await soloud.init(channels: Channels.mono);
  }

  bool get playing {
    final h = _handle;
    return h != null && SoLoud.instance.getIsValidVoiceHandle(h);
  }

  void write(Uint8List pcm) {
    final soloud = SoLoud.instance;
    if (!soloud.isInitialized) return;
    if (_source == null || _ended) {
      _source = soloud.setBufferStream(
        maxBufferSizeDuration: const Duration(minutes: 5),
        bufferingType: BufferingType.released,
        bufferingTimeNeeds: 0.3,
        sampleRate: LiveSession.outputRate,
        channels: Channels.mono,
        format: BufferType.s16le,
        autoDispose: true,
      );
      _ended = false;
      _handle = soloud.play(_source!);
    }
    soloud.addAudioDataStream(_source!, pcm);
    level.value = pcmLevel(pcm);
  }

  /// The turn is over: what is left plays out, then the stream closes.
  void finish() {
    final s = _source;
    if (s != null && !_ended) {
      try {
        SoLoud.instance.setDataIsEnded(s);
      } catch (_) {}
      _ended = true;
    }
    level.value = 0;
  }

  /// Spoken over: quiet at once.
  Future<void> clear() async {
    final h = _handle, s = _source;
    _handle = null;
    _source = null;
    _ended = false;
    level.value = 0;
    try {
      if (h != null) await SoLoud.instance.stop(h);
      if (s != null) await SoLoud.instance.disposeSource(s);
    } catch (_) {}
  }
}

/// How loud 16-bit PCM is, 0–1 (root mean square, lifted for the eye).
double pcmLevel(Uint8List pcm) {
  final n = pcm.length ~/ 2;
  if (n == 0) return 0;
  final data = ByteData.sublistView(pcm);
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    final s = data.getInt16(i * 2, Endian.little) / 32768;
    sum += s * s;
  }
  return math.min(1, math.sqrt(sum / n) * 4);
}

/// 16-bit PCM as the floats a voice detector reads.
Float32List pcmFloats(Uint8List pcm) {
  final n = pcm.length ~/ 2;
  final data = ByteData.sublistView(pcm);
  return Float32List(n)..setAll(0, [
    for (var i = 0; i < n; i++) data.getInt16(i * 2, Endian.little) / 32768,
  ]);
}

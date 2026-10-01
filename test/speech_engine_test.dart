import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/speech/speech_engine.dart';

/// The voice and the ear together, on the real models: what is said is
/// written back down. The models are hundreds of megabytes and are not in
/// the repository; point FOLIO_SES_MODELLERI at a folder holding
/// okuma-supertonic3-1 and yazma-whisper-turbo-1 to run this.
void main() {
  final root = Platform.environment['FOLIO_SES_MODELLERI'];
  final skip = root == null ? 'FOLIO_SES_MODELLERI yok' : null;

  test(
    'a sentence said aloud is written back down',
    () async {
      final library = _sherpaLibrary();
      final voice = await VoiceWorker.start(
        '$root/okuma-supertonic3-1',
        library: library,
      );
      addTearDown(voice.dispose);
      final audio = await voice.say(
        "Sayın Mahkemeden, davanın kabulüne karar verilmesini saygılarımızla "
        'arz ederiz.',
      );
      expect(audio.sampleRate, 44100);
      expect(audio.samples.length / audio.sampleRate, greaterThan(2));

      final ear = await ListenWorker.start(
        '$root/yazma-whisper-turbo-1',
        library: library,
      );
      addTearDown(ear.dispose);
      final heard = <String>[];
      ear.texts.listen(heard.add);
      // The microphone gives a little at a time; so does this.
      final samples = _resample(audio.samples, audio.sampleRate, 16000);
      for (var at = 0; at < samples.length; at += 1600) {
        ear.feed(
          Float32List.sublistView(
            samples,
            at,
            (at + 1600).clamp(0, samples.length),
          ),
        );
      }
      await ear.flush();
      final text = heard.join(' ').toLowerCase();
      expect(text, contains('mahkeme'));
      expect(text, contains('kabulüne karar'));
      expect(text, contains('arz ederiz'));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Where pub put sherpa-onnx's library for this machine.
String _sherpaLibrary() {
  final config = jsonDecode(
    File('.dart_tool/package_config.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final package = (config['packages'] as List).cast<Map>().firstWhere(
    (p) => p['name'] == 'sherpa_onnx_linux',
  );
  final root = Uri.parse(package['rootUri'] as String).toFilePath();
  return '$root/linux/x64';
}

Float32List _resample(Float32List from, int rate, int to) {
  final out = Float32List((from.length * to / rate).floor());
  for (var i = 0; i < out.length; i++) {
    final x = i * rate / to;
    final j = x.floor();
    final k = (j + 1).clamp(0, from.length - 1);
    out[i] = from[j] + (from[k] - from[j]) * (x - j);
  }
  return out;
}

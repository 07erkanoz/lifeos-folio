import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/voice/voice_settings.dart';
import 'package:evrak_convert/services/voice/vosk.dart';
import 'package:evrak_convert/services/voice/wake_word.dart';

void main() {
  test('only the phrase, alone, short and sure, wakes', () {
    const sure = [('ajan', .95), ('açıl', .9)];
    expect(
      isWakePhrase('ajan açıl', true, 'ajan açıl', confidence: sure),
      isTrue,
    );
    // Not until the utterance has ended.
    expect(
      isWakePhrase('ajan açıl', false, 'ajan açıl', confidence: sure),
      isFalse,
    );
    // A word before or after: a sentence, not the call.
    expect(
      isWakePhrase(
        'bu ajan açıl',
        true,
        'ajan açıl',
        confidence: const [('bu', .9), ...sure],
      ),
      isFalse,
    );
    // Unsure, or long (the TV talking).
    expect(
      isWakePhrase(
        'ajan açıl',
        true,
        'ajan açıl',
        confidence: const [('ajan', .5), ('açıl', .9)],
      ),
      isFalse,
    );
    expect(
      isWakePhrase('ajan açıl', true, 'ajan açıl', voiced: 3, confidence: sure),
      isFalse,
    );
  });

  test('a Turkish locale’s decimal comma does not break the result', () {
    final m = VoskRecognizer.decode(
      '{"result":[{"conf":1,000000,"word":"ajan"}],"text":"ajan"}',
    );
    expect(((m['result'] as List).first as Map)['conf'], 1.0);
  });

  test('the wake switch is kept with the voice settings', () {
    final s = VoiceSettings.fromJson(
      const VoiceSettings(on: true, wake: true).toJson(),
    );
    expect(s.wake, isTrue);
    expect(VoiceSettings.fromJson(const {'acik': true}).wake, isFalse);
  });

  test('the chime is a proper WAV', () {
    final w = wav(Uint8List(100), 16000);
    expect(String.fromCharCodes(w.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(w.sublist(8, 12)), 'WAVE');
    expect(w.length, 144);
  });
}

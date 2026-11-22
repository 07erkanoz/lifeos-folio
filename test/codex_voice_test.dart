import 'dart:convert';

import 'package:evrak_convert/services/ai/ai_groq.dart';
import 'package:evrak_convert/services/voice/ajan_voice.dart';
import 'package:evrak_convert/services/voice/codex_conversation.dart';
import 'package:evrak_convert/services/voice/live_conversation.dart';
import 'package:evrak_convert/services/voice/voice_settings.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host implements FolioToolHost {
  @override
  Future<List<Map<String, Object?>>> tools() async => [
    for (final n in [
      'ajanda',
      'mevzuat_madde',
      'ajanda_ekle',
      'not_ekle',
      'dosya_notu_ekle',
      'tebligat_oku',
      'evrak_indir',
      'uyap_guncelle',
      'bulgu_oner',
      'taslak_oner',
    ])
      {'name': n, 'description': n},
  ];

  @override
  Future<String> call(String name, Map<String, Object?> args) async => name;

  @override
  Future<void> close() async {}
}

void main() {
  test('the voice settings are kept and read back', () {
    const s = VoiceSettings(
      on: true,
      codexVoice: 'maple',
      codexModel: 'gpt-6.1-terra',
      codexEffort: 'high',
      handOn: false,
    );
    final back = VoiceSettings.fromJson(jsonDecode(jsonEncode(s.toJson())));
    expect(back.on, isTrue);
    expect(back.codexVoice, 'maple');
    expect(back.codexModel, 'gpt-6.1-terra');
    expect(back.codexEffort, 'high');
    expect(back.handOn, isFalse);
    // A file from before these settings: Codex's own, low, handing on.
    final old = VoiceSettings.fromJson({'acik': true});
    expect(old.codexEffort, 'low');
    expect(old.handOn, isTrue);
    expect(old.codexVoice, isEmpty);
  });

  test('Codex is given read-only tools, and the AI program only when '
      'allowed', () async {
    final c = CodexConversation(
      brain: (q) async => q,
      host: () async => _Host(),
    );
    var names = [for (final t in await c.declarationsForTest()) t['name']];
    expect(names, ['ajanda', 'mevzuat_madde', CodexConversation.brainTool]);
    c.handOn = false;
    names = [for (final t in await c.declarationsForTest()) t['name']];
    expect(names, ['ajanda', 'mevzuat_madde']);
  });

  test('the instructions carry today, and say what has passed', () {
    final i = CodexConversation.instructions(DateTime(2026, 11, 21));
    expect(i, contains('21 Kasım 2026 Cumartesi'));
    expect(i, contains('geçti'));
    // "Bu hafta" on a Saturday: the next seven days, not the past week.
    expect(i, contains('bugünden itibaren yedi gün'));
    expect(ajanDates(DateTime(2026, 11, 21)), contains('21 Kasım 2026'));
    final v = CodexConversation.voiceIdentity(DateTime(2026, 11, 21, 9, 5));
    expect(v, contains('Folio Ajan'));
    expect(v, contains('21 Kasım 2026 Cumartesi, saat 09:05'));
    expect(v, contains('ChatGPT'));
  });

  test('a short "kapan" ends the conversation; a question does not', () {
    for (final said in [
      'Kapan.',
      'sus artık',
      'Tamam yeter.',
      'Konuşmayı bitir',
      'kapat',
      'Tamam, görüşürüz!',
      'Gerek, kapatabilirsin',
      'Gerek yok, kapatabilirsin',
      'Kapatır mısın',
      'Teşekkürler',
      'Gerek yok',
    ]) {
      expect(isStopCommand(said), isTrue, reason: said);
    }
    for (final said in [
      'Bu hafta duruşmam var mı?',
      'Türk Medeni Kanunu birinci madde ne diyor, kısaca anlat bana',
      '',
      'Tebligatları oku',
      'Bu dosyada keşif gerek mi, yok mu, bana ayrıntılı anlat',
      'Susurluk Asliye Hukuk dosyasını aç',
    ]) {
      expect(isStopCommand(said), isFalse, reason: said);
    }
  });
}

import 'dart:convert';

import 'package:evrak_convert/services/ai/ai_groq.dart';
import 'package:evrak_convert/services/voice/ajan_voice.dart';
import 'package:evrak_convert/services/voice/codex_conversation.dart';
import 'package:evrak_convert/services/voice/live_conversation.dart';
import 'package:evrak_convert/services/voice/folio_ajan.dart';
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
      brain: (q, _) async => q,
      host: () async => _Host(),
    );
    var names = [for (final t in await c.declarationsForTest()) t['name']];
    expect(names, [
      'ajanda',
      'mevzuat_madde',
      'ajanda_ekle',
      'not_ekle',
      'dosya_notu_ekle',
      'tebligat_oku',
      'evrak_indir',
      'uyap_guncelle',
      CodexConversation.brainTool,
    ]);
    c.handOn = false;
    names = [for (final t in await c.declarationsForTest()) t['name']];
    expect(names, [
      'ajanda',
      'mevzuat_madde',
      'ajanda_ekle',
      'not_ekle',
      'dosya_notu_ekle',
      'tebligat_oku',
      'evrak_indir',
      'uyap_guncelle',
    ]);
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

  test('the program is asked the lawyer\'s own words, and its answer is '
      'read by the voice as it is', () async {
    final asked = <(String, String)>[];
    final spoken = <String>[];
    final c = CodexConversation(
      brain: (q, conversation) async {
        asked.add((q, conversation));
        return 'Salı değil, 27 Kasım Cuma saat 10.10.';
      },
      host: () async => _Host(),
    )..conversationForTest = 'th-1';
    c.speakForTest = (t) async => spoken.add(t);
    await c.declarationsForTest();
    c.heardForTest('Manavgat duruşması salı mı çarşamba mı?');
    c.heardForTest('En son ne olmuş?');
    final out = await c.toolCallForTest(CodexConversation.brainTool, {
      'soru': 'Bu hafta Manavgat duruşması var mı',
    });
    expect(asked.single.$2, 'th-1');
    expect(
      asked.single.$1,
      startsWith(
        'Avukat (sesli, aynen): «Manavgat duruşması salı mı çarşamba mı? / '
        'En son ne olmuş?»',
      ),
    );
    expect(asked.single.$1, contains('avukatın sözü esastır'));
    expect(spoken, ['Salı değil, 27 Kasım Cuma saat 10.10.']);
    // The agent is told only that it was read: nothing of its own to add.
    final text = ((out['contentItems'] as List).single as Map)['text'];
    expect(text, CodexConversation.spokenMark);
    expect(c.lines.last.text, startsWith('Claude cevapladı ('));

    // The words go once: the next hand-on has only what was said after.
    c.heardForTest('İlkinin mahkemesi neresiydi?');
    await c.toolCallForTest(CodexConversation.brainTool, {'soru': 'mahkeme'});
    expect(asked.last.$1, contains('«İlkinin mahkemesi neresiydi?»'));
    expect(asked.last.$1, isNot(contains('Manavgat')));
  });

  test(
    'a voice that cannot be handed the answer reads it from the tool',
    () async {
      final c = CodexConversation(
        brain: (q, _) async => 'Cevap budur.',
        host: () async => _Host(),
      );
      c.speakForTest = (_) async => throw Exception('appendSpeech yok');
      await c.declarationsForTest();
      final out = await c.toolCallForTest(CodexConversation.brainTool, {
        'soru': 'Soru',
      });
      final text = ((out['contentItems'] as List).single as Map)['text'];
      expect(text, startsWith('AVUKATA AYNEN OKU'));
      expect(text, endsWith('Cevap budur.'));
      // Nothing was heard: the agent's request is all there is.
      expect(CodexConversation.handOnQuestion(const [], ' Soru '), 'Soru');
    },
  );

  test('the handed-on question names two weeks from today', () {
    final p = spokenPrompt('Bu hafta duruşmam var mı?', DateTime(2026, 11, 24));
    expect(p, contains('24 Kasım 2026 Salı'));
    expect(p, contains('2026-11-24 – 2026-12-07'));
    expect(p, contains('Salı değil, 27 Kasım Cuma'));
    expect(p, endsWith('Bu hafta duruşmam var mı?'));
  });

  test('one Claude conversation for each voice session', () {
    final a = FolioAjan();
    final first = a.voiceThread('th-1');
    expect(a.voiceThread('th-1'), same(first));
    final second = a.voiceThread('th-2');
    expect(second, isNot(same(first)));
    expect(second.place, 'ses-th-2');
  });
}

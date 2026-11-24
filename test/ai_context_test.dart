import 'dart:convert';

import 'package:evrak_convert/services/ai/ai_assistant.dart';
import 'package:evrak_convert/services/ai/ai_context.dart';
import 'package:flutter_test/flutter_test.dart';

/// Claude Code's result line, as 2.1.330 wrote it (24 Kasım 2026): the
/// turn's sums above, each call in `iterations`.
String _result({required List<int> calls}) => jsonEncode({
  'type': 'result',
  'is_error': false,
  'result': 'Tamam.',
  'session_id': 's-1',
  'usage': {
    'input_tokens': 2 * calls.length,
    'cache_read_input_tokens': calls.fold(0, (a, b) => a + b),
    'output_tokens': 57,
    'iterations': [
      for (final c in calls)
        {
          'input_tokens': 2,
          'output_tokens': 57,
          'cache_read_input_tokens': c - 1000,
          'cache_creation_input_tokens': 941,
          'type': 'message',
        },
    ],
  },
});

void main() {
  test('the size is the last call\'s, not the turn\'s sum', () {
    // Twelve calls of a turn: millions summed, the conversation 360 bin.
    final out = _result(calls: [for (var i = 0; i < 11; i++) 250000, 360000]);
    expect(AiContext.fromClaudeOutput(out), 360000);
    // A line an event, the result last (with pictures).
    final lines = '{"type":"system","session_id":"s-1"}\n$out\n';
    expect(AiContext.fromClaudeOutput(lines), 360000);
    // Not told: no size, no decision.
    expect(AiContext.fromClaudeOutput('{"type":"result","result":"x"}'), null);
    expect(AiContext.fromClaudeOutput('okunamadı'), null);
    expect(AiContext.endOfTurn({'iterations': []}), null);
  });

  test('a new session past the ceiling, not twice in a row', () {
    expect(AiContext.needed(399999, 400000), isFalse);
    expect(AiContext.needed(400000, 400000), isTrue);
    expect(AiContext.needed(900000, 0), isFalse, reason: 'kapalı');
    expect(AiContext.needed(null, 400000), isFalse);
    // Just started again: the documents read stay for three answers…
    expect(AiContext.needed(500000, 400000, since: 1), isFalse);
    expect(AiContext.needed(500000, 400000, since: 3), isTrue);
    // …unless twice the ceiling.
    expect(AiContext.needed(800000, 400000, since: 1), isTrue);
  });

  test('the thread starts again at the next question only', () {
    final thread = AiThread('c1', {AiProvider.claude: 's-1'});
    thread.size[AiProvider.claude] = 412000;
    AiContext.afterAnswer(thread, AiProvider.claude, 400000, restarted: false);
    // Decided at the end of the answer; the session is still the same.
    expect(thread.restart, {AiProvider.claude});
    expect(thread.ids[AiProvider.claude], 's-1');
    // The next question lets go of it, once.
    expect(AiContext.beforeQuestion(thread, AiProvider.claude), isTrue);
    expect(thread.ids, isEmpty);
    expect(AiContext.beforeQuestion(thread, AiProvider.claude), isFalse);
    // The first answer of the new session: small, and counted.
    thread.size[AiProvider.claude] = 60000;
    AiContext.afterAnswer(thread, AiProvider.claude, 400000, restarted: true);
    expect(thread.sinceRestart, 1);
    expect(thread.restart, isEmpty);
    // Grown again at once: waits for three answers.
    thread.size[AiProvider.claude] = 450000;
    AiContext.afterAnswer(thread, AiProvider.claude, 400000, restarted: false);
    expect(thread.restart, isEmpty);
    AiContext.afterAnswer(thread, AiProvider.claude, 400000, restarted: false);
    expect(thread.sinceRestart, 3);
    expect(thread.restart, {AiProvider.claude});
  });

  test('the index lists what was read, the cases and the documents added', () {
    final steps = [
      const AiStep(
        '1',
        'mcp__folio__dosya_sec',
        args: {'anahtar': 'k|2026/255'},
      ),
      const AiStep('2', 'evrak_oku', args: {'anahtar': 'e-17'}),
      const AiStep('3', 'evrak_oku', args: {'anahtar': 'e-17', 'parca': 2}),
      const AiStep('4', 'evrak_oku', args: {'anahtar': 'e-17'}),
      const AiStep(
        '5',
        'mevzuat_madde',
        args: {'kanun': 'HMK', 'madde': '119'},
      ),
      const AiStep(
        '6',
        'mevzuat_toplu',
        args: {
          'maddeler': [
            {'kanun': 'TBK', 'madde': '49'},
            {'kanun': 'HMK', 'madde': '119'},
          ],
        },
      ),
      const AiStep(
        '7',
        'karar_getir',
        args: {'kunye': 'Yargıtay 3. HD E.2023/1 K.2023/2', 'kimlik': 'y-9'},
      ),
      const AiStep(
        '8',
        'kunye_dogrula',
        args: {'daire': '3. HD', 'esas': '2023/1', 'karar': '2023/2'},
      ),
      const AiStep(
        '9',
        'sure_hesapla',
        args: {
          'madde': 'HMK 345',
          'miktar': 2,
          'birim': 'hafta',
          'baslangic': '2026-11-20',
        },
      ),
      const AiStep('10', 'taslak_oner', args: {'baslik': 'İstinaf dilekçesi'}),
      const AiStep('11', 'ajanda'),
    ];
    final index = AiContext.index(
      steps,
      attached: ['bilirkisi-raporu.pdf', 'bilirkisi-raporu.pdf'],
      cases: ['Manavgat 5. Asliye Hukuk 2026/255'],
    );
    expect(index, startsWith('[KESİN DİZİN'));
    expect(index, contains('- Manavgat 5. Asliye Hukuk 2026/255'));
    expect(index, contains('- anahtar: k|2026/255'));
    expect('- bilirkisi-raporu.pdf'.allMatches(index).length, 1);
    expect('- anahtar: e-17\n'.allMatches(index).length, 1);
    expect(index, contains('- anahtar: e-17 (parça 2)'));
    expect('- HMK m.119'.allMatches(index).length, 1);
    expect(index, contains('- TBK m.49'));
    expect(index, contains('Yargıtay 3. HD E.2023/1 K.2023/2 · kimlik: y-9'));
    expect(index, contains('denetlendi: 3. HD E.2023/1 K.2023/2'));
    expect(index, contains('HMK 345 · 2 hafta · 2026-11-20'));
    expect(index, contains('«İstinaf dilekçesi»'));
    expect(index, isNot(contains('ajanda')));
    // The order: cases and the documents added first.
    expect(
      index.indexOf('ÜZERİNDE ÇALIŞILAN'),
      lessThan(index.indexOf('AVUKATIN EKLEDİĞİ')),
    );
    expect(AiContext.index(const []), isEmpty);
  });

  test('a long index is cut and says so', () {
    final steps = [
      for (var i = 0; i < 500; i++)
        AiStep('$i', 'evrak_oku', args: {'anahtar': 'evrak-${'x' * 100}-$i'}),
    ];
    final index = AiContext.index(steps);
    expect(index, contains('satır daha (gösterilmedi)'));
    final wide = AiContext.index([
      for (final kind in ['evrak_oku', 'emsal_getir', 'doktrin_getir'])
        for (var i = 0; i < 60; i++)
          AiStep(
            '$kind$i',
            kind,
            args: {'anahtar': 'a' * 110 + '$i', 'kimlik': 'k' * 110 + '$i'},
          ),
    ]);
    expect(wide.length, lessThanOrEqualTo(12100));
    expect(wide, endsWith('listeyi tam sayma.'));
  });

  test('the ceiling is kept with the settings, 400 bin when not set', () {
    expect(const AiSettings().contextCeiling, 400000);
    expect(const AiSettings().toJson().containsKey('baglamTavani'), isFalse);
    for (final c in [0, 300000, 600000]) {
      final back = AiSettings.fromJson(
        jsonDecode(
          jsonEncode(const AiSettings().copyWith(contextCeiling: c).toJson()),
        ),
      );
      expect(back.contextCeiling, c);
    }
    // A value not offered falls back.
    expect(AiSettings.fromJson({'baglamTavani': 12345}).contextCeiling, 400000);
  });

  test('the note says the texts are gone and are to be read again', () {
    expect(AiContext.note, contains('aynen'));
    expect(AiContext.note, contains('yeniden çağırıp metni oku'));
    expect(AiContext.shown(412345), '412 bin');
  });
}

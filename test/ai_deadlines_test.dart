import 'package:evrak_convert/services/ai/ai_deadlines.dart';
import 'package:evrak_convert/services/legal/deadlines/mahkeme_kategori.dart';
import 'package:evrak_convert/services/legal/deadlines/sure_katalogu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const notice =
      'Dava dilekçesi ekte gönderilmiştir. Tebliğden itibaren iki hafta '
      'içinde cevap vermeniz gerekmektedir. Davacı vekiline bir hafta '
      'içinde 4.000 TL bilirkişi ücretini yatırması için süre verildi. '
      'Tanık listesi verilecek.';
  const answer = '''Tebligatı okudum.
```json
{"oneriler": [
 {"ne": "Cevap dilekçesi verilecek", "miktar": 2, "birim": "hafta",
  "madde": "HMK m.127", "nitelik": "kanuni", "baslangic": "teblig",
  "alinti": "Tebliğden itibaren iki hafta içinde cevap vermeniz gerekmektedir."},
 {"ne": "Bilirkişi ücreti yatırılacak", "miktar": 1, "birim": "hafta",
  "madde": "hâkim süresi", "nitelik": "hakim", "baslangic": "teblig",
  "alinti": "bir hafta içinde 4.000 TL bilirkişi ücretini yatırması"},
 {"ne": "Tanık listesi verilecek", "miktar": 0, "birim": "",
  "alinti": "Tanık listesi verilecek."},
 {"ne": "Uydurma", "miktar": 7, "birim": "gun", "madde": "İİK m.62",
  "alinti": "yedi gün içinde itiraz edebilirsiniz"}
]}
```''';

  test('the suggestions are read; one whose sentence is not in the notice '
      'is left out', () {
    final got = AiDeadlines.parse(answer, text: notice);
    expect(got.map((s) => s.what), [
      'Cevap dilekçesi verilecek',
      'Bilirkişi ücreti yatırılacak',
      'Tanık listesi verilecek',
    ]);
    expect(got[0].unit, SureBirimi.hafta);
    expect(got[2].isTask, isTrue);
  });

  test('a time the catalogue holds is kept as the catalogue\'s rule', () {
    final got = AiDeadlines.parse(answer, text: notice);
    expect(got[0].catalogueRule, isNotNull);
    expect(got[1].catalogueRule, isNull);
    final c = got[1].choice(id: 'x', noticeId: 'n1', model: 'Claude · haiku');
    expect(c.ruleId, 'ozel');
    expect(c.byAi, isTrue);
    expect(c.rule!.nitelik, SureNiteligi.hakim);
    expect(c.rule!.kanunMaddesi, 'hâkim süresi');
    // Kept and read back as it was.
    final back = c.toJson();
    expect(back['kaynak'], 'yapay_zeka');
    expect(back['alinti'], contains('bilirkişi'));
  });

  test('the last day is the engine\'s, not the program\'s', () {
    final got = AiDeadlines.parse(answer, text: notice);
    final day = got[0].lastDay(
      DateTime(2026, 11, 10),
      MahkemeKategorisi.hukuk,
      now: DateTime(2026, 11, 13),
    );
    expect(day!.etkiliSonGun, DateTime(2026, 11, 24));
    expect(
      got[2].lastDay(DateTime(2026, 11, 10), MahkemeKategorisi.hukuk),
      isNull,
    );
  });

  test('an answer with no block or broken JSON gives nothing', () {
    expect(AiDeadlines.parse('Süre bulamadım.'), isEmpty);
    expect(AiDeadlines.parse('```json\n{"oneriler": [\n```'), isEmpty);
  });

  test('the prompt says the engine reckons the day and asks for quotes', () {
    final p = AiDeadlines.prompt(text: notice, served: DateTime(2026, 11, 10));
    expect(p, contains('10.11.2026'));
    expect(p, contains('Son günü hesaplama'));
    expect(p, contains('alıntıla'));
  });
}

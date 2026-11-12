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
  "kimde": "karsi",
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
    // Given to the other side: shown, not the lawyer's to do.
    expect(got[1].others, isTrue);
    expect(got[0].whose, 'belirsiz');
  });

  test('a time up to a day stays that day; an article of another code is '
      'said', () {
    final got = AiDeadlines.parse('''```json
{"oneriler": [
 {"ne": "Belge sunulacak", "miktar": 93, "birim": "gun", "nitelik": "hakim",
  "son_tarih": "2027-01-15",
  "alinti": "ilk duruşma günü olan 15/01/2027 tarihine kadar"},
 {"ne": "Cevap", "miktar": 2, "birim": "hafta", "madde": "HMK m.127",
  "nitelik": "kanuni", "alinti": "cevap"}
]}
```''', court: MahkemeKategorisi.ceza);
    expect(got[0].isTask, isTrue);
    expect(got[0].until, DateTime(2027, 1, 15));
    expect(got[1].warning, contains('HMK'));
  });

  test('a time from a document\'s name alone is not kept; one the rules '
      'found is not said twice', () {
    const zarf =
        'BU ZARFTA Istinaf Cevap Dilekçesi VARDIR. Tebliğden itibaren '
        'iki hafta içinde cevap vermeniz gerekmektedir.';
    final got = AiDeadlines.parse(
      '''```json
{"oneriler": [
 {"ne": "İstinaf cevap dilekçesi verilecek", "miktar": 2, "birim": "hafta",
  "madde": "CMK m.273", "alinti": "BU ZARFTA Istinaf Cevap Dilekçesi VARDIR"},
 {"ne": "Cevap dilekçesi verilecek", "miktar": 2, "birim": "hafta",
  "madde": "HMK m.127",
  "alinti": "Tebliğden itibaren iki hafta içinde cevap vermeniz gerekmektedir."}
]}
```''',
      text: zarf,
      knownRules: {'hmk127'},
    );
    expect(got, hasLength(1));
    expect(got.single.isTask, isTrue);
    expect(got.single.warning, contains('süre yazmıyor'));
  });

  test('a last day the program reckoned itself is not taken', () {
    final got = AiDeadlines.parse('''```json
{"oneriler": [{"ne": "Gider yatırılacak", "miktar": 2, "birim": "hafta",
  "nitelik": "hakim", "son_tarih": "2026-10-25",
  "alinti": "iki haftalık kesin süre verilmesine"}]}
```''');
    expect(got.single.until, isNull);
    expect(
      got.single
          .lastDay(DateTime(2026, 10, 11), MahkemeKategorisi.hukuk)!
          .etkiliSonGun,
      DateTime(2026, 10, 26),
    );
  });

  test('a time the catalogue holds is kept as the catalogue\'s rule', () {
    final got = AiDeadlines.parse(answer, text: notice);
    expect(got[0].catalogueRule, isNotNull);
    expect(got[1].catalogueRule, isNull);
    final c = got[1].choice(id: 'x', noticeId: 'n1', model: 'Claude · haiku');
    expect(c.ruleId, 'ozel');
    expect(c.byAi, isTrue);
    expect(c.rule!.nitelik, SureNiteligi.hakim);
    expect(c.rule!.kanunMaddesi, 'Hâkimin verdiği süre');
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
    expect(p, contains('taraf varsayma'));
    expect(
      AiDeadlines.prompt(
        text: notice,
        served: DateTime(2026, 11, 10),
        side: 'Ali (davalı)',
      ),
      contains('müvekkili: Ali (davalı)'),
    );
  });
}

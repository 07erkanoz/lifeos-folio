import 'package:evrak_convert/services/voice/folio_ajan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the brief keeps the week\'s hearings, with their hour and day', () {
    final today = DateTime(2026, 11, 21, 9);
    final brief = AjanBrief.from(
      {
        'durusmalar': [
          {'tarih': '2026-11-24T10:30', 'tur': 'Duruşma', 'esas': '2026/1'},
          {'tarih': '2026-11-27T14:00', 'tur': 'Karar', 'esas': '2025/2'},
        ],
        'sureler': [
          {'son_gun': '2026-11-21', 'baslik': 'İstinaf'},
          {'son_gun': '2026-11-23', 'baslik': 'Rapora itiraz'},
        ],
        'gorev_ve_notlar': [
          {'tur': 'görev', 'baslik': 'Tanık listesi', 'bitti': false},
          {'tur': 'görev', 'baslik': 'Bitmiş', 'bitti': true},
        ],
      },
      const {},
      const {},
      today,
    );
    expect(brief.hearings.map((h) => h.clock), ['10:30', '14:00']);
    expect(brief.hearings.map((h) => h.days), [3, 6]);
    expect(brief.hearings.any((h) => h.urgent), isFalse);
    expect(brief.deadlines.map((d) => d.days), [0, 2]);
    expect(brief.deadlines.every((d) => d.urgent), isTrue);
    expect(brief.tasks.map((t) => t.title), ['Tanık listesi']);
    expect(brief.summary, contains('2 duruşma'));
  });
}

import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/uets/notice_matcher.dart';
import 'package:evrak_convert/services/uets/uets_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PortalCase kase(String number, String court) =>
      PortalCase.create(number: number, court: court);

  test('the number and the unit exactly', () {
    final a = kase('2025/412', 'Antalya 3. Asliye Hukuk Mahkemesi');
    final b = kase('2025/412', 'Antalya 4. Asliye Hukuk Mahkemesi');
    expect(
      matchSubject(
        'ANTALYA 3. ASLİYE HUKUK MAHKEMESİ [2025/412] [Gerekçeli Karar]',
        [a, b],
      ),
      a.key,
    );
  });

  test('the Court of Cassation’s notification bureau', () {
    final y = kase('2024/9001', 'Yargıtay 3. Hukuk Dairesi');
    expect(
      matchSubject('Yargıtay 3. Hukuk Dairesi Tebligat Bölümü [2024/9001]', [
        y,
      ]),
      y.key,
    );
  });

  test('a prosecutor’s bureau to its Başsavcılık, by the place', () {
    final c = kase('2026/1500', 'Antalya Cumhuriyet Başsavcılığı');
    expect(matchSubject('Antalya Soruşturma Bürosu [2026/1500]', [c]), c.key);
  });

  test('two candidates, a wrong city or no number tie nothing', () {
    final a = kase('2026/77', 'Antalya 1. İcra Dairesi');
    final b = kase('2026/77', 'Antalya 2. İcra Dairesi');
    expect(matchSubject('Antalya İcra Bürosu [2026/77]', [a, b]), isNull);
    expect(matchSubject('İzmir 1. İcra Dairesi [2026/77]', [a]), isNull);
    expect(matchSubject('Duyuru', [a]), isNull);
  });

  test('a manual tie stays; a certain kind of document brings its deadlines '
      'once', () {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    final c = kase('2025/412', 'Antalya 3. Asliye Hukuk Mahkemesi');
    db.mergeCases([c]);
    db.mergeNotices([
      UetsMessage(
        id: 'm1',
        subject:
            'Antalya 3. Asliye Hukuk Mahkemesi [2025/412] [Gerekçeli Karar]',
        sent: DateTime(2026, 10, 1, 10),
      ),
      UetsMessage(
        id: 'm2',
        subject: 'Antalya 3. Asliye Hukuk Mahkemesi [2025/412] [Ara Karar]',
        sent: DateTime(2026, 10, 2, 10),
      ),
    ]);
    db.linkNotice('m2', 'baska-dosya', 'manual');
    matchNotices(db, now: DateTime(2026, 10, 6));
    final kept = {for (final n in db.notices()) n.message.id: n};
    expect(kept['m1']!.caseKey, c.key);
    expect(kept['m1']!.link, 'auto');
    expect(kept['m2']!.caseKey, 'baska-dosya');
    final deadlines = db.agenda().where((i) => i.id.startsWith('uets:m1:'));
    expect(deadlines, isNotEmpty);
    // Served 6 October (five days later); two weeks to appeal: 20 October.
    expect(deadlines.map((d) => d.at), contains(DateTime(2026, 10, 20)));
    final count = db.agenda().length;
    matchNotices(db, now: DateTime(2026, 10, 6));
    expect(db.agenda().length, count);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/uets/notice_deadlines.dart';
import 'package:evrak_convert/services/uets/uets_api.dart';

/// A criminal court's reasoned decision served by UETS: which side of 7499
/// (1 June 2024) its appeal is on, from what the notice itself tells.
List<String> appeals(String number, DateTime sent) => [
  for (final d in noticeDeadlines(
    KeptNotice(
      UetsMessage(
        id: 'n',
        subject: 'Manavgat 6. Asliye Ceza Mahkemesi [$number]',
        sent: sent,
      ),
    ),
    manifest: (
      state: 'alindi',
      fetchedAt: null,
      parts: [(id: 'p', name: 'Gerekceli_Karar.pdf')],
    ),
    now: sent.add(const Duration(days: 1)),
  ))
    if (d.title.startsWith('İstinaf')) d.title,
];

void main() {
  test('a decision states its day and its number', () {
    expect(
      decisionDayIn('ESAS NO : 2025/739\nKARAR TARİHİ\t: 12/11/2026\n'),
      DateTime(2026, 11, 12),
    );
    expect(decisionDayIn('Karar Tarihi: 3.6.2024'), DateTime(2024, 6, 3));
    expect(decisionDayIn('KARAR TARİHİ : 31/02/2025'), isNull);
    expect(decisionDayIn('karar verildi'), isNull);
    expect(decisionYearIn('KARAR NO : 2025 / 45'), 2025);
    expect(decisionYearIn('ESAS NO : 2023/12'), isNull);
  });

  test('a 2025 case was not decided before 1 June 2024: two weeks only', () {
    expect(appeals('2025/739', DateTime.utc(2026, 11, 17)), [
      'İstinaf süresi',
    ]);
  });

  test('a notice sent before 1 June 2024 brings the old rule only', () {
    final titles = appeals('2023/12', DateTime.utc(2024, 3, 1));
    expect(titles, isNotEmpty);
    expect(titles.every((t) => t.contains('eski hüküm')), isTrue);
  });

  test('an older case served after it may be either: both, said why', () {
    final titles = appeals('2023/12', DateTime.utc(2026, 10, 1));
    expect(titles, containsAll(['İstinaf süresi', 'İstinaf süresi (eski hüküm)']));
  });
}

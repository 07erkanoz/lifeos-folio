import 'package:evrak_convert/services/legal/deadlines/deadline_service.dart';
import 'package:evrak_convert/services/legal/deadlines/legal_day.dart';
import 'package:evrak_convert/services/legal/deadlines/mahkeme_kategori.dart';
import 'package:evrak_convert/services/legal/deadlines/turkish_legal_calendar.dart';
import 'package:evrak_convert/services/legal/deadlines/yasal_sure.dart';
import 'package:flutter_test/flutter_test.dart';

// The days a deadline is counted in (the report's T24–T33, T76, T78): the
// Turkish day of an instant, whatever this computer's zone; months to the
// corresponding day; the tax recess's late start; half holidays.
void main() {
  group('the Turkish day of an instant', () {
    test('just after midnight in Turkey is the next day, not UTC’s', () {
      // 21.30 UTC on 7 October is 00.30 on 8 October in Turkey (T26).
      expect(turkeyDay(DateTime.utc(2026, 10, 7, 21, 30)).key, '2026-10-08');
      expect(turkeyDay(DateTime.utc(2026, 10, 7, 20, 59)).key, '2026-10-07');
    });

    test('the same instant gives the same day, from any zone (T25)', () {
      final instant = DateTime.utc(2026, 10, 7, 21, 30);
      expect(turkeyDay(instant), turkeyDay(instant.toLocal()));
    });

    test('a notice in the box on 8 October is served on 13 October; two '
        'weeks from then is 27 October (T24)', () {
      final served = turkeyDay(DateTime.utc(2026, 10, 7, 21, 30)).addDays(5);
      expect(served.key, '2026-10-13');
      final c = DeadlineService.computeFromUsuliTebligTarihi(
        usuliTebligTarihi: served.toLocal(),
        kategori: MahkemeKategorisi.hukuk,
        kurallar: const [sIstinafHukuk],
        now: DateTime(2026, 10, 8),
      );
      expect(LegalDay.of(c.items.single.hamSonGun).key, '2026-10-27');
    });

    test('a fifth day on a Sunday is not moved: only a last day is (T27)', () {
      // In the box on Tuesday 6 October 2026: served Sunday 11 October.
      expect(
        turkeyDay(DateTime.utc(2026, 10, 6, 9)).addDays(5).weekday,
        DateTime.sunday,
      );
    });

    test('before September 2016 the offset is not known to be +3', () {
      expect(turkeyOffsetKnown(DateTime.utc(2016, 3, 1)), isFalse);
      expect(turkeyOffsetKnown(DateTime.utc(2017, 3, 1)), isTrue);
    });
  });

  group('months and years', () {
    test('31 January and a month is 28 February (T30)', () {
      expect(LegalDay(2026, 1, 31).addMonths(1).key, '2026-02-28');
      // HMK m.93: 28 February 2026 is a Saturday, the last day 2 March.
      final adj = TurkishLegalCalendar.adjustDeadline(
        LegalDay(2026, 1, 31).addMonths(1).toLocal(),
        kategori: MahkemeKategorisi.hukuk,
      );
      expect(adj.effectiveDate, DateTime(2026, 3, 2));
    });

    test('29 February and a year is 28 February (T31)', () {
      expect(LegalDay(2024, 2, 29).addYears(1).key, '2025-02-28');
    });

    test('31 December and two months is the end of February (T32)', () {
      expect(LegalDay(2025, 12, 31).addMonths(2).key, '2026-02-28');
    });

    test('days are counted on dates, never on hours (T33)', () {
      expect(LegalDay(2026, 3, 28).addDays(2).key, '2026-03-30');
      expect(LegalDay(2026, 10, 27).daysSince(LegalDay(2026, 10, 13)), 14);
    });
  });

  group('the calendar', () {
    test('the tax recess starts the day after July’s first working day when '
        '30 June is not one (T76)', () {
      // 30 June 2024 was a Sunday; 1 July a Monday: the recess began 2 July.
      expect(
        TurkishLegalCalendar.maliTatilBaslangici(2024),
        DateTime(2024, 7, 2),
      );
      expect(TurkishLegalCalendar.inMaliTatil(DateTime(2024, 7, 1)), isFalse);
      expect(TurkishLegalCalendar.inMaliTatil(DateTime(2024, 7, 2)), isTrue);
      expect(TurkishLegalCalendar.maliTatilBaslangiciKaydi(2024), isTrue);
      // 30 June 2026 is a Tuesday: 1 July, as the law's first sentence says.
      expect(
        TurkishLegalCalendar.maliTatilBaslangici(2026),
        DateTime(2026, 7, 1),
      );
      expect(TurkishLegalCalendar.maliTatilBaslangiciKaydi(2026), isFalse);
    });

    test('a last day on a half holiday is not moved, but said (T78)', () {
      expect(TurkishLegalCalendar.isYarimGun(DateTime(2026, 10, 28)), isTrue);
      // The eve of the Ramazan Bayramı of 2026 (20–22 March).
      expect(TurkishLegalCalendar.isYarimGun(DateTime(2026, 3, 19)), isTrue);
      expect(TurkishLegalCalendar.isYarimGun(DateTime(2026, 3, 20)), isFalse);
      final adj = TurkishLegalCalendar.adjustDeadline(
        DateTime(2026, 10, 28),
        kategori: MahkemeKategorisi.hukuk,
      );
      expect(adj.effectiveDate, DateTime(2026, 10, 28));
      expect(adj.notes.join(' '), contains('yarım gün'));
    });
  });
}

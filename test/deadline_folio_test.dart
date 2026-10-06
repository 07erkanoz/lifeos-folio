import 'package:evrak_convert/services/legal/deadlines/belge_turu.dart';
import 'package:evrak_convert/services/legal/deadlines/deadline_service.dart';
import 'package:evrak_convert/services/legal/deadlines/mahkeme_kategori.dart';
import 'package:evrak_convert/services/legal/deadlines/turkish_legal_calendar.dart';
import 'package:evrak_convert/services/legal/deadlines/yasal_sure.dart';
import 'package:flutter_test/flutter_test.dart';

/// What Folio changed in Banaozel's deadline engine, and what Banaozel left
/// untested (UYGULAMAPLANI §11).
void main() {
  YasalSure rule(int amount, SureBirimi unit) => YasalSure(
    ad: 'deneme',
    miktar: amount,
    birim: unit,
    baslangic: SureBaslangici.teblig,
    kanunMaddesi: 'HMK m.92',
  );

  test('a month from the 31st ends on the shorter month’s last day', () {
    expect(
      rule(1, SureBirimi.ay).hamSonTarih(DateTime(2026, 1, 31)),
      DateTime(2026, 2, 28),
    );
    expect(
      rule(1, SureBirimi.ay).hamSonTarih(DateTime(2027, 12, 31)),
      DateTime(2028, 1, 31),
    );
    expect(
      rule(1, SureBirimi.yil).hamSonTarih(DateTime(2028, 2, 29)),
      DateTime(2029, 2, 28),
    );
  });

  test(
    'a last day on a holiday or a weekend moves to the next working day',
    () {
      // 29 Ekim 2026 Perşembe, Cumhuriyet Bayramı.
      expect(
        TurkishLegalCalendar.isOfficialHoliday(DateTime(2026, 10, 29)),
        isTrue,
      );
      final adj = TurkishLegalCalendar.adjustDeadline(
        DateTime(2026, 10, 29),
        kategori: MahkemeKategorisi.hukuk,
        adliTatileTabi: true,
      );
      expect(adj.effectiveDate, DateTime(2026, 10, 30));
      // 10 Ekim 2026 Cumartesi.
      expect(
        TurkishLegalCalendar.adjustDeadline(
          DateTime(2026, 10, 10),
          kategori: MahkemeKategorisi.hukuk,
          adliTatileTabi: true,
        ).effectiveDate,
        DateTime(2026, 10, 12),
      );
    },
  );

  test('working days skip the weekend', () {
    expect(
      rule(2, SureBirimi.isGunu).hamSonTarih(DateTime(2026, 10, 9)),
      DateTime(2026, 10, 13),
    );
  });

  test('a last day in a projected or unknown holiday year is flagged', () {
    DeadlineItem first(DateTime served) =>
        DeadlineService.computeFromUsuliTebligTarihi(
          usuliTebligTarihi: served,
          belgeTuru: BelgeTuru.gerekceliKarar,
          kategori: MahkemeKategorisi.hukuk,
          adliTatileTabi: true,
          now: served,
        ).items.first;
    final projected = first(DateTime(2028, 3, 1));
    expect(projected.guven, isNot(SureGuveni.yuksek));
    expect(projected.dayanakNotlari.join(' '), contains('tahmini'));
    final unknown = first(DateTime(2031, 3, 1));
    expect(unknown.guven, SureGuveni.dusuk);
    expect(unknown.dayanakNotlari.join(' '), contains('doğrulanamadı'));
  });
}

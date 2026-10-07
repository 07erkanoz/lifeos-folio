// Türk hukuku yasal süre takvimi — resmî tatil + hafta sonu + adli tatil.
//
// KURAL KAYNAKLARI:
//  • HMK m.93 / CMK m.39 / İYUK m.8: Sürenin son günü resmî tatile rastlarsa
//    süre, tatili takip eden ilk İŞ GÜNÜ mesai bitiminde sona erer. (EVRENSEL)
//  • HMK m.104: Adli tatile (20 Temmuz – 31 Ağustos) denk gelen süreler,
//    tatilin bittiği günden itibaren BİR HAFTA uzamış sayılır (hukuk).
//  • İYUK m.61: İdare/vergi yargısında adli tatilde biten süreler 7 gün uzar.
//  • CMK m.331/4: Ceza yargısında adli tatile rastlayan süreler tatilin
//    bittiği günden itibaren ÜÇ GÜN uzamış sayılır.
//  • İİK: İcra takip süreleri adli tatilde İŞLEMEYE DEVAM EDER (uzama YOK).
//
// GÜVENLİK İLKESİ: Bu modül süreyi ASLA KISALTMAZ — yalnızca uzatır ve her
// uzatmayı hukuki dayanağıyla nota döker. Kategori bilinmiyorsa adli tatil
// uzatması UYGULANMAZ (yanlış uzatma avukatı geç bırakabilir); yalnız uyarı
// notu eklenir. Hafta sonu/tatil kaydırması her durumda uygulanır (evrensel).
//
// (AvukatOS Hukuk projesinden taşınmıştır.)

import 'mahkeme_kategori.dart';
import 'legal_day.dart';

/// Süre düzeltme sonucu — ham tarih + nihai tarih + hukuki dayanak notları.
class DeadlineAdjustment {
  /// Ham hesap (tebliğ tarihi + N gün) — düzeltme öncesi.
  final DateTime rawDate;

  /// Nihai son gün (adli tatil + iş günü kaydırması uygulanmış).
  final DateTime effectiveDate;

  /// Uygulanan kuralların hukuki dayanak notları (kullanıcıya gösterilir).
  final List<String> notes;

  const DeadlineAdjustment({
    required this.rawDate,
    required this.effectiveDate,
    this.notes = const [],
  });

  bool get extended =>
      effectiveDate.year != rawDate.year ||
      effectiveDate.month != rawDate.month ||
      effectiveDate.day != rawDate.day;

  /// Notları tek satırda birleştir (takvim açıklaması için).
  String get notesText => notes.join(' ');
}

class TurkishLegalCalendar {
  TurkishLegalCalendar._();

  /// Dini bayram tarihlerinin RESMÎ olarak doğrulandığı son yıl. Bu yıla kadar
  /// (dahil) Diyanet takvimiyle teyitli; SONRASI projeksiyondur (dış denetim
  /// 2026-07-05). Yeni yıl doğrulanınca bu sabit + _diniBayramlar güncellenir.
  static const int kDiniBayramSonResmiYil = 2026;

  /// The last year the religious holidays are written down at all; after
  /// it a holiday would silently count as a working day (Folio).
  static const int kDiniBayramTabloSonYil = 2030;

  /// The calendar's version, raised whenever a holiday or a rule of it
  /// changes: a deadline reckoned on another is reckoned again.
  ///   1 — 2026-10-07: tax recess start (5604 m.1/1), half holidays.
  static const int takvimSurumu = 1;

  /// The first year whose holidays are written down; before it a holiday
  /// would count as a working day.
  static const int kDiniBayramTabloIlkYil = 2024;

  /// Takvim verisinin son elle doğrulanma tarihi (kullanıcıya/asistanı bilgi).
  static const String kTakvimSonGuncelleme = '2026-07';

  /// [yil] için dini bayram tarihleri PROJEKSİYON mu (resmî değil)?
  static bool diniBayramProjeksiyonYili(int yil) =>
      yil > kDiniBayramSonResmiYil;

  // ── Dini bayramlar (Diyanet) — yalnız TAM tatil günleri (arife yarım gün
  //    resmi tatil sayılmaz, süre hesabında iş günüdür).
  //    2027+ tarihleri Diyanet projeksiyonudur; yıl yaklaşınca doğrulanmalı.
  static final Set<String> _diniBayramlar = {
    // 2024
    '2024-04-10', '2024-04-11', '2024-04-12', // Ramazan
    '2024-06-16', '2024-06-17', '2024-06-18', '2024-06-19', // Kurban
    // 2025
    '2025-03-30', '2025-03-31', '2025-04-01', // Ramazan
    '2025-06-06', '2025-06-07', '2025-06-08', '2025-06-09', // Kurban
    // 2026
    '2026-03-20', '2026-03-21', '2026-03-22', // Ramazan
    '2026-05-27', '2026-05-28', '2026-05-29', '2026-05-30', // Kurban
    // 2027 (projeksiyon)
    '2027-03-09', '2027-03-10', '2027-03-11', // Ramazan
    '2027-05-16', '2027-05-17', '2027-05-18', '2027-05-19', // Kurban
    // 2028 (projeksiyon)
    '2028-02-26', '2028-02-27', '2028-02-28', // Ramazan
    '2028-05-05', '2028-05-06', '2028-05-07', '2028-05-08', // Kurban
    // 2029 (projeksiyon)
    '2029-02-14', '2029-02-15', '2029-02-16', // Ramazan
    '2029-04-24', '2029-04-25', '2029-04-26', '2029-04-27', // Kurban
    // 2030 (projeksiyon)
    '2030-02-05', '2030-02-06', '2030-02-07', // Ramazan
    '2030-04-14', '2030-04-15', '2030-04-16', '2030-04-17', // Kurban
  };

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Resmî tatil mi? (sabit ulusal günler + dini bayramlar; hafta sonu HARİÇ)
  static bool isOfficialHoliday(DateTime d) {
    if (d.month == 1 && d.day == 1) return true; // Yılbaşı
    if (d.month == 4 && d.day == 23) return true; // Ulusal Egemenlik
    if (d.month == 5 && d.day == 1) return true; // Emek ve Dayanışma
    if (d.month == 5 && d.day == 19) return true; // Gençlik ve Spor
    if (d.month == 7 && d.day == 15) return true; // Demokrasi ve Milli Birlik
    if (d.month == 8 && d.day == 30) return true; // Zafer Bayramı
    if (d.month == 10 && d.day == 29) return true; // Cumhuriyet Bayramı
    return _diniBayramlar.contains(_key(d));
  }

  /// İş günü mü? (hafta içi VE resmî tatil değil)
  static bool isBusinessDay(DateTime d) =>
      d.weekday != DateTime.saturday &&
      d.weekday != DateTime.sunday &&
      !isOfficialHoliday(d);

  /// Verilen günden itibaren (kendisi dahil) ilk iş günü.
  static DateTime firstBusinessDayOnOrAfter(DateTime d) {
    var x = DateTime(d.year, d.month, d.day);
    while (!isBusinessDay(x)) {
      x = DateTime(x.year, x.month, x.day + 1);
    }
    return x;
  }

  /// Adli tatil içinde mi? (20 Temmuz – 31 Ağustos, HMK m.102)
  static bool inAdliTatil(DateTime d) {
    if (d.month == 7 && d.day >= 20) return true;
    if (d.month == 8) return true;
    return false;
  }

  /// The first day of the tax recess (5604 m.1/1): 1 July; but when the
  /// last day of June is not a working day, the day after July's first
  /// working day (30 June 2024 a Sunday: 2 July).
  static DateTime maliTatilBaslangici(int yil) {
    if (isBusinessDay(DateTime(yil, 6, 30))) return DateTime(yil, 7, 1);
    final ilk = firstBusinessDayOnOrAfter(DateTime(yil, 7, 1));
    return DateTime(ilk.year, ilk.month, ilk.day + 1);
  }

  /// Whether [yil]'s recess starts late (see [maliTatilBaslangici]): the
  /// law moves the start but says nothing of the end, which is kept on 20
  /// July here, the earlier end and so the safe one, and said so.
  static bool maliTatilBaslangiciKaydi(int yil) =>
      maliTatilBaslangici(yil) != DateTime(yil, 7, 1);

  /// Mali tatil içinde mi? (5604 s.K. m.1: [maliTatilBaslangici] – 20 Temmuz)
  static bool inMaliTatil(DateTime d) {
    if (d.month != 7 || d.day > 20) return false;
    return !DateTime(
      d.year,
      d.month,
      d.day,
    ).isBefore(maliTatilBaslangici(d.year));
  }

  /// A half holiday (2429 m.2): the eve of each religious holiday and 28
  /// October, a holiday from 13.00. A last day on one is not moved, since
  /// the morning is a working day, but it is said, since a filing in person
  /// and one through UYAP may not end at the same hour.
  static bool isYarimGun(DateTime d) {
    if (d.month == 10 && d.day == 28) return true;
    final next = DateTime(d.year, d.month, d.day + 1);
    return _diniBayramlar.contains(_key(next)) &&
        !_diniBayramlar.contains(_key(d));
  }

  /// Mali tatil DURMASI (5604 s.K. m.1/3): vergiyle ilgili dava açma süreleri
  /// mali tatil süresince İŞLEMEZ. [baslangic]→[ham] aralığında mali tatile
  /// düşen günler sayılmaz; son gün o kadar İLERİ gider.
  ///
  /// YALNIZ `maliTatildeDurur=true` işaretli süre olgularıyla çağrılmalıdır —
  /// Danıştay içtihadına göre kanun yolu (istinaf/temyiz) süreleri mali
  /// tatilden etkilenmez; yanlış uygulamak avukatı geç bırakır.
  static ({DateTime tarih, int durmaGunu}) maliTatilDurmasiUygula(
    DateTime baslangic,
    DateTime ham,
  ) {
    final b = DateTime(baslangic.year, baslangic.month, baslangic.day);
    final h = DateTime(ham.year, ham.month, ham.day);
    final toplamGun = LegalDay.of(h).daysSince(LegalDay.of(b));
    if (toplamGun <= 0) return (tarih: h, durmaGunu: 0);
    // Süreyi gün gün yürüt; mali tatile düşen gün SAYILMAZ (işlemez).
    var sayilan = 0;
    var d = b;
    while (sayilan < toplamGun) {
      d = DateTime(d.year, d.month, d.day + 1);
      if (!inMaliTatil(d)) sayilan++;
    }
    return (tarih: d, durmaGunu: LegalDay.of(d).daysSince(LegalDay.of(h)));
  }

  /// Mahkeme adından kategori türet (kategori elde yoksa).
  /// Yalnız NET sinyallerde döner; emin değilse null (yanlış uzatma önlenir).
  static MahkemeKategorisi? kategoriFromMahkemeAdi(String? mahkemeAdi) {
    if (mahkemeAdi == null || mahkemeAdi.trim().isEmpty) return null;
    // TÜRKÇE KATLAMA ÖNCE: Dart'ın `toLowerCase()`'i İ'yi birleşik i̇ (i +
    // combining dot) yapıyor, bu da düz 'iş mahkemesi' ile EŞLEŞMİYOR. Yani
    // "İş Mahkemesi" hiçbir dala girmiyor ve kategori null kalıyordu.
    final m = mahkemeAdi
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .toLowerCase();
    if (m.contains('icra')) return MahkemeKategorisi.icra;
    if (m.contains('vergi')) return MahkemeKategorisi.vergi;
    if (m.contains('idare') ||
        m.contains('danıştay') ||
        m.contains('danistay')) {
      return MahkemeKategorisi.idare;
    }
    if (m.contains('ceza') || m.contains('savcılı') || m.contains('savcili')) {
      return MahkemeKategorisi.ceza;
    }
    if (m.contains('hukuk') ||
        m.contains('aile') ||
        m.contains('ticaret') ||
        m.contains('tüketici') ||
        m.contains('tuketici') ||
        m.contains('kadastro') ||
        m.contains('iş mahkemesi') ||
        m.contains('is mahkemesi')) {
      return MahkemeKategorisi.hukuk;
    }
    return null;
  }

  /// Adli tatil uzatmasının düştüğü gün.
  ///
  /// HMK m.104 ve İYUK m.8/3 FARKLI LAFIZLA AYNI GÜNE varır — 7 Eylül:
  /// - HMK: "adli tatilin BİTTİĞİ günden itibaren bir hafta" → 31 Ağustos + 7.
  /// - İYUK: "ara vermenin sona erdiği günü İZLEYEN tarihten itibaren yedi
  ///   gün" → çapa 1 Eylül ve o gün BİRİNCİ gündür; yedinci gün 7 Eylül.
  ///
  /// DİKKAT: İYUK'ta çapa bir gün ileri diye ayrıca +1 EKLENMEZ; kaydırma
  /// sayımın içinde. Bir kez o hataya düşüldü ve 8 Eylül üretildi — üretimde
  /// hak kaybettiren yön. Danıştay İDDK somut olayda son günü 7 Eylül kabul
  /// ediyor. CMK m.331/4 ise üç gün uzatır.
  static DateTime? _tatilUzatmasi(DateTime tatilSonu, MahkemeKategorisi? k) {
    switch (k) {
      case MahkemeKategorisi.hukuk:
        return DateTime(tatilSonu.year, tatilSonu.month, tatilSonu.day + 7);
      case MahkemeKategorisi.idare:
      case MahkemeKategorisi.vergi:
        return DateTime(tatilSonu.year, tatilSonu.month, tatilSonu.day + 7);
      case MahkemeKategorisi.ceza:
        return DateTime(tatilSonu.year, tatilSonu.month, tatilSonu.day + 3);
      case MahkemeKategorisi.icra:
      case MahkemeKategorisi.bilinmeyen:
      case null:
        return null;
    }
  }

  static String _gun(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// Ham son tarihi hukuki kurallara göre düzelt.
  ///
  /// Sıra: (0) mali tatil durması (yalnız [maliTatildeDurur] + [baslangic]
  /// verildiyse; 5604 m.1/3) → (1) adli tatil uzatması (kategoriye göre) →
  /// (2) son gün iş günü değilse ilk iş gününe kaydır (evrensel).
  /// Süre ASLA kısalmaz.
  static DeadlineAdjustment adjustDeadline(
    DateTime rawDate, {
    MahkemeKategorisi? kategori,
    DateTime? baslangic,
    bool maliTatildeDurur = false,
    bool? adliTatileTabi,
  }) {
    final notes = <String>[];
    var effective = DateTime(rawDate.year, rawDate.month, rawDate.day);

    // ── 0) Mali tatil durması (yalnız vergi dava açma gibi işaretli süreler) ──
    if (maliTatildeDurur && baslangic != null) {
      final m = maliTatilDurmasiUygula(baslangic, effective);
      if (m.durmaGunu > 0) {
        effective = m.tarih;
        notes.add(
          'Mali tatil (${_gun(maliTatilBaslangici(effective.year))}–20 Temmuz) süresince vergiyle ilgili dava '
          'açma süresi işlemez; süre ${m.durmaGunu} gün ileri gitti '
          '(5604 s.K. m.1/3).',
        );
      }
    }

    // ── 1) Adli tatil uzatması ──
    if (inAdliTatil(effective)) {
      final tatilSonu = DateTime(effective.year, 8, 31);
      final uzatilmis = _tatilUzatmasi(tatilSonu, kategori);
      // HMK m.104 uzatmayı YALNIZ "adli tatile tabi olan dava ve işlerde"
      // verir. m.103 tatilde GÖRÜLEN işleri sayar ve onlarda uzatma YOKTUR:
      // işçilerin açtığı iş davaları, nafaka/soybağı/velayet/vesayet, nüfus
      // kaydı düzeltme, iflas-konkordato, çekişmesiz yargı, ivedi işler,
      // ihtiyati tedbir/haciz... İdari yargıda aynı ayrım İYUK m.61/1 c.2'de:
      // BİM il merkezi dışında tek idare ya da vergi mahkemesi bulunan yerler
      // ara vermeden yararlanamaz.
      //
      // BİLİNMİYORSA UZATMA UYGULANMAZ. Uzatmak son günü İLERİ atar; yanlış
      // ileri tarih hak kaybettirir, yanlış erken tarih yalnız erken
      // çalıştırır. Belirsizlik güvenli yöne düşer.
      final kapiliKategori =
          kategori == MahkemeKategorisi.hukuk ||
          kategori == MahkemeKategorisi.idare ||
          kategori == MahkemeKategorisi.vergi;
      if (kapiliKategori && adliTatileTabi == false) {
        notes.add(
          'Bu dava/iş adli tatile tabi olmadığından süre UZAMAZ '
          '(HMK m.103 / İYUK m.61). Son gün tatil içinde kalır.',
        );
      } else if (kapiliKategori && adliTatileTabi == null) {
        notes.add(
          '⚠ Son gün adli tatile denk geliyor, fakat davanın tatile '
          'tabi olup olmadığı belirlenemedi (HMK m.103 / İYUK m.61). '
          'Güvenli tarafta kalmak için uzatma UYGULANMADI'
          '${uzatilmis == null ? '' : '; dava tatile tabiyse son gün '
                    '${_gun(uzatilmis)} olur'}.',
        );
      } else {
        switch (kategori) {
          case MahkemeKategorisi.hukuk:
            // HMK m.104: "adli tatilin bittiği günden itibaren bir hafta".
            effective = uzatilmis!;
            notes.add(
              'Son gün adli tatile denk geldiğinden süre '
              '${_gun(effective)} tarihine uzar (HMK m.104).',
            );
            break;
          case MahkemeKategorisi.idare:
          case MahkemeKategorisi.vergi:
            // Uzatmanın dayanağı m.61 DEĞİL m.8/3'tür; m.61 çalışmaya ara
            // vermenin kendisini düzenler, uzatmayı m.8/3 verir. Tarih HMK
            // ile aynı (7 Eylül) — bkz. _tatilUzatmasi.
            effective = uzatilmis!;
            notes.add(
              'Son gün çalışmaya ara verme zamanına denk geldiğinden '
              'süre ${_gun(effective)} tarihine uzar (İYUK m.8/3).',
            );
            break;
          case MahkemeKategorisi.ceza:
            effective = uzatilmis!;
            notes.add(
              'Son gün adli tatile denk geldiğinden süre 3 gün uzar '
              '(CMK m.331/4).',
            );
            break;
          case MahkemeKategorisi.icra:
            notes.add(
              'İcra süreleri adli tatilde işlemeye devam eder — '
              'uzama uygulanmaz.',
            );
            break;
          case MahkemeKategorisi.bilinmeyen:
          case null:
            notes.add(
              '⚠ Son gün adli tatile (20 Tem–31 Ağu) denk geliyor — '
              'mahkeme türüne göre süre uzayabilir (HMK m.104 / CMK m.331 / '
              'İYUK m.8/3). Kontrol edin.',
            );
            break;
        }
      }
    }

    // ── 2) Son gün iş günü değilse ilk iş gününe kaydır (evrensel) ──
    final shifted = firstBusinessDayOnOrAfter(effective);
    if (shifted != effective) {
      final neden =
          (effective.weekday == DateTime.saturday ||
              effective.weekday == DateTime.sunday)
          ? 'hafta sonuna'
          : 'resmî tatile';
      notes.add(
        'Son gün $neden rastladığından süre ilk iş günü mesai '
        'bitiminde sona erer (HMK m.93 / CMK m.39 / İYUK m.8).',
      );
      effective = shifted;
    }

    if (isYarimGun(effective)) {
      notes.add(
        'Son gün yarım gün (saat 13.00\'te tatil başlar; 2429 s.K. m.2); '
        'fizikî başvuru ve UYAP işlem saatini kontrol edin.',
      );
    }

    return DeadlineAdjustment(
      rawDate: rawDate,
      effectiveDate: effective,
      notes: notes,
    );
  }
}

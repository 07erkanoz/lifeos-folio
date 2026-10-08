import 'belge_turu.dart';
import 'mahkeme_kategori.dart';
import 'tebligat_parser.dart';
import 'turkish_legal_calendar.dart';
import 'yasal_sure.dart';
import 'legal_day.dart';

/// Tebliğ tarihinin nasıl belirlendiği. (Geriye dönük uyum için korunur.)
enum TebligKaynagi {
  /// Usulî tebliğ tarihi doğrudan kullanıcı/kayıt tarafından verildi.
  dogrudan,

  /// Muhatap tebligatı 5 günden önce açtı (fiilî öğrenme).
  okunma,

  /// 5 gün kuralı (Tebligat Kanunu 7/a) — gönderimi izleyen 5. günün sonu.
  besGunKurali,
}

/// Tek bir yasal süre için hesaplanmış son gün + dayanak + güven.
class DeadlineItem {
  const DeadlineItem({
    required this.sureAdi,
    required this.gun,
    required this.sureMetni,
    required this.kanun,
    required this.baslangicTarihi,
    required this.baslangicTuru,
    required this.hamSonGun,
    required this.etkiliSonGun,
    required this.kalanGun,
    required this.dayanakNotlari,
    required this.uzadi,
    required this.guven,
    this.tatilBelirsiz = false,
    this.onayDurumu = 'dogrulanmadi', // dogrulanmadi | onaylandi | degistirildi
  });

  final String sureAdi; // "İstinaf süresi"
  final int gun; // yaklaşık gün (gösterim/uyum)
  final String sureMetni; // "2 hafta", "1 yıl" (insan-okunur)
  final String kanun; // "HMK m.345"
  final DateTime baslangicTarihi; // sürenin başladığı gün
  final String
  baslangicTuru; // "usulî tebliğ" | "fiilî öğrenme" | "karar tarihi"
  final DateTime hamSonGun; // başlangıç + süre (düzeltme öncesi)
  final DateTime etkiliSonGun; // adli tatil + iş günü düzeltmesi sonrası
  final int kalanGun; // bugünden etkili son güne (negatif = geçti)
  final List<String> dayanakNotlari; // uzatma/kaydırma + güven notları
  final bool uzadi; // ham ≠ etkili mi
  final SureGuveni guven;

  /// Son gün adli tatile denk geliyor, uzayıp uzamadığı bilinmiyor
  /// (bkz. [DeadlineAdjustment.tatilBelirsiz]).
  final bool tatilBelirsiz;
  final String onayDurumu;
}

/// Bir tebligat için başlangıç tarihleri + tüm yasal sürelerin hesabı.
class DeadlineComputation {
  const DeadlineComputation({
    required this.tebligTarihi,
    required this.tebligKaynagi,
    required this.usuliTebligTarihi,
    this.ogrenmeTarihi,
    required this.kategori,
    required this.items,
    this.olayBekleyenler = const [],
  });

  /// Geriye dönük uyum: usulî tebliğ tarihi (5. gün).
  final DateTime tebligTarihi;
  final TebligKaynagi tebligKaynagi;

  /// Usulî tebliğ tarihi — kanun yolu sürelerinin olağan başlangıcı.
  final DateTime usuliTebligTarihi;

  /// Fiilî öğrenme (okunma) tarihi — biliniyorsa; öğrenmeye bağlı süreler için.
  final DateTime? ogrenmeTarihi;

  final MahkemeKategorisi kategori;

  /// Kalan güne göre artan sıralı (en acil önce).
  final List<DeadlineItem> items;

  /// Başlangıç olayının (tefhim, karar, ilan, öğrenme) tarihi verilmediği
  /// için hesaplanamayan kurallar. Tebliğ tarihi bunların yerine konmaz;
  /// görev kaybolmasın diye ayrı döner, çağıran "olay bekleniyor" gösterir.
  final List<({YasalSure sure, String eksikOlay})> olayBekleyenler;

  DeadlineItem? get enAcil => items.isEmpty ? null : items.first;
}

/// Tebligat → başlangıç tarihleri → yasal süre → etkili son gün hesaplayan
/// DETERMİNİSTİK servis. Yapay zeka GEREKTİRMEZ (AI yalnızca belge sınıflandırma
/// için ayrıca kullanılabilir; nihai son günü bu motor hesaplar).
class DeadlineService {
  const DeadlineService._();

  /// Yalnız arka planın kaydettiği süre alanları için karar gerekli mi?
  /// Üç olası yanıt aynı satırları üretiyorsa uzak sınıflandırma sonucu
  /// değiştiremez. Takvim kuralı kopyalanmaz; gerçek motor karşılaştırılır.
  /// Açıklama/güven gösteren detay ekranı bu optimizasyonu kullanmaz.
  static bool adliTatilKarariGerekli({
    required DateTime gonderimTarihi,
    DateTime? okunmaTarihi,
    required MahkemeKategorisi kategori,
    required BelgeTuru belgeTuru,
  }) {
    final now = DateTime.now();
    List<(String, String, String, int)> sonuc(bool? tabi) => [
      for (final item in compute(
        gonderimTarihi: gonderimTarihi,
        okunmaTarihi: okunmaTarihi,
        kategori: kategori,
        belgeTuru: belgeTuru,
        adliTatileTabi: tabi,
        now: now,
      ).items)
        (
          item.sureAdi,
          item.kanun,
          item.sureMetni,
          item.etkiliSonGun.millisecondsSinceEpoch,
        ),
    ];
    final bilinmeyen = sonuc(null);
    for (final tabi in [false, true]) {
      final diger = sonuc(tabi);
      if (diger.length != bilinmeyen.length) return true;
      for (var i = 0; i < diger.length; i++) {
        if (diger[i] != bilinmeyen[i]) return true;
      }
    }
    return false;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  // Days are counted on the date's own fields, never as 24 hours added to
  // a local clock, which a summer-time change would shift by a day.
  static DateTime _plusDays(DateTime d, int n) =>
      DateTime(d.year, d.month, d.day + n);

  /// Usulî tebliğ tarihi: elektronik tebligat, gönderimi izleyen 5. günün
  /// sonunda yapılmış sayılır (Tebligat Kanunu 7/a). **Erken okuma bu tarihi
  /// DEĞİŞTİRMEZ** — kanun yolu süreleri buradan başlar (LEG-01).
  static DateTime usuliTebligTarihiHesapla(DateTime gonderimTarihi) =>
      _plusDays(_dateOnly(gonderimTarihi), 5);

  /// Geriye dönük uyum: usulî tebliğ tarihini döndürür. (Eski "erken okunmayı
  /// tebliğ say" davranışı KALDIRILDI; okunma artık ayrı "öğrenme" tarihidir.)
  static ({DateTime tarih, TebligKaynagi kaynak}) tebligTarihi({
    required DateTime gonderimTarihi,
    DateTime? okunmaTarihi,
  }) => (
    tarih: usuliTebligTarihiHesapla(gonderimTarihi),
    kaynak: TebligKaynagi.besGunKurali,
  );

  static String _baslangicEtiket(SureBaslangici b) => switch (b) {
    SureBaslangici.teblig => 'usulî tebliğ',
    SureBaslangici.ogrenme => 'fiilî öğrenme',
    SureBaslangici.tefhim => 'tefhim',
    SureBaslangici.ilan => 'ilan',
    SureBaslangici.kararTarihi => 'karar tarihi',
  };

  /// Verilen tebligat verisinden tüm uygulanabilir süreleri hesaplar.
  ///
  /// - Süreler BELGE TÜRÜNE göre seçilir (kategoriye göre körlemesine değil).
  /// - Her sürenin BAŞLANGICI tetikleyicisine göre belirlenir (usulî tebliğ /
  ///   fiilî öğrenme / karar tarihi).
  /// - Tarih-etkin kurallar (ör. CMK m.273) [kararTarihi] ile seçilir; karar
  ///   tarihi yoksa eski/yeni senaryolar birlikte gösterilir ve güven düşürülür.
  static DeadlineComputation compute({
    required DateTime gonderimTarihi,
    DateTime? okunmaTarihi,
    required MahkemeKategorisi kategori,
    BelgeTuru belgeTuru = BelgeTuru.diger,
    DateTime? kararTarihi,
    DateTime? tefhimTarihi,
    DateTime? ilanTarihi,
    DateTime? now,
    bool? adliTatileTabi,
  }) {
    final usuli = usuliTebligTarihiHesapla(gonderimTarihi);
    return _compute(
      usuliTebligTarihi: usuli,
      okunmaTarihi: okunmaTarihi,
      kategori: kategori,
      belgeTuru: belgeTuru,
      kararTarihi: kararTarihi,
      tefhimTarihi: tefhimTarihi,
      ilanTarihi: ilanTarihi,
      now: now,
      tebligKaynagi: TebligKaynagi.besGunKurali,
      adliTatileTabi: adliTatileTabi,
    );
  }

  /// Usulî tebliğ tarihi zaten kesin olarak biliniyorsa doğrudan hesaplar.
  /// Kâtip `sure_hesapla` aracı ve elle tarih girişi bu yolu kullanır; UETS'nin
  /// beş gün kuralı ikinci kez uygulanmaz.
  ///
  /// [kurallar] reckons only those rules instead of the catalogue's for
  /// [belgeTuru] (a notice's deadlines are made rule by rule).
  static DeadlineComputation computeFromUsuliTebligTarihi({
    required DateTime usuliTebligTarihi,
    DateTime? okunmaTarihi,
    required MahkemeKategorisi kategori,
    BelgeTuru belgeTuru = BelgeTuru.diger,
    DateTime? kararTarihi,
    DateTime? tefhimTarihi,
    DateTime? ilanTarihi,
    DateTime? now,
    bool? adliTatileTabi,
    List<YasalSure>? kurallar,
  }) => _compute(
    usuliTebligTarihi: _dateOnly(usuliTebligTarihi),
    okunmaTarihi: okunmaTarihi,
    kategori: kategori,
    belgeTuru: belgeTuru,
    kararTarihi: kararTarihi,
    tefhimTarihi: tefhimTarihi,
    ilanTarihi: ilanTarihi,
    now: now,
    tebligKaynagi: TebligKaynagi.dogrudan,
    adliTatileTabi: adliTatileTabi,
    ozelKurallar: kurallar,
  );

  /// DURUŞMADA VERİLEN SÜRE — kaynağı katalog değil, zabıt metnidir.
  ///
  /// NEDEN AYRI YOL: katalog "bu belge türünde şu süre işler" der; duruşmada
  /// verilen süre ise hâkimin o dosyaya özgü kararıdır ("tanık listesi için iki
  /// hafta kesin süre"). Miktarı katalogdan çıkarılamaz, zabıttan okunur.
  /// UETS bunu ASLA göremez — yüze karşı tefhim edilir, zarf yoktur.
  ///
  /// TAKVİM HESABI YİNE BURADA: adli tatil, HMK m.103 kapısı, hafta sonu
  /// kaydırması ve tatil uzatması olağan yolla aynı kodu kullanır. Süreyi
  /// okuyan (model) ile tarihi hesaplayan (bu motor) ayrı kalır; modele
  /// aritmetik sorulmaz.
  ///
  /// [baslangic] tefhim tarihidir (duruşma günü). Yoklukta verilen kesin süre
  /// TEBLİĞ edilmek zorundadır (HMK m.91); o durumda çağıran bu yolu
  /// kullanmamalı, tebligatı beklemelidir.
  static DeadlineComputation computeFromOzelSure({
    required DateTime baslangic,
    required YasalSure sure,
    required MahkemeKategorisi kategori,
    DateTime? now,
    bool? adliTatileTabi,
  }) => _compute(
    usuliTebligTarihi: _dateOnly(baslangic),
    kategori: kategori,
    belgeTuru: BelgeTuru.diger,
    kararTarihi: _dateOnly(baslangic),
    tefhimTarihi: _dateOnly(baslangic),
    now: now,
    tebligKaynagi: TebligKaynagi.dogrudan,
    adliTatileTabi: adliTatileTabi,
    ozelKurallar: [sure],
  );

  static DeadlineComputation _compute({
    required DateTime usuliTebligTarihi,
    DateTime? okunmaTarihi,
    required MahkemeKategorisi kategori,
    required BelgeTuru belgeTuru,
    DateTime? kararTarihi,
    DateTime? tefhimTarihi,
    DateTime? ilanTarihi,
    DateTime? now,
    required TebligKaynagi tebligKaynagi,
    bool? adliTatileTabi,
    List<YasalSure>? ozelKurallar,
  }) {
    final bugun = _dateOnly(now ?? DateTime.now());
    final usuli = _dateOnly(usuliTebligTarihi);
    final ogrenme = okunmaTarihi != null ? _dateOnly(okunmaTarihi) : null;
    final karar = kararTarihi != null ? _dateOnly(kararTarihi) : null;
    final tefhim = tefhimTarihi != null ? _dateOnly(tefhimTarihi) : null;
    final ilan = ilanTarihi != null ? _dateOnly(ilanTarihi) : null;
    final bekleyenler = <({YasalSure sure, String eksikOlay})>[];

    // Tarih-etkin kuralları karar tarihine göre filtrele/dedupla.
    // `ozelKurallar` verilmişse katalog HİÇ sorgulanmaz: duruşmada verilen süre
    // dosyaya özgüdür, katalogda karşılığı yoktur ve olmamalıdır.
    final kurallar = _uygulanabilirKurallar(
      ozelKurallar ?? surelerForBelgeTuru(belgeTuru, kategori),
      karar,
    );

    final items = <DeadlineItem>[];
    for (final sure in kurallar) {
      // Başlangıç, kuralın kendi olayının tarihidir. O tarih yoksa tebliğ
      // tarihi yerine KONMAZ: tefhim, karar ve ilan tebliğden önce olabilir,
      // ikame son günü geç gösterir. Kural "olay bekleniyor" olarak döner.
      final olay = switch (sure.baslangic) {
        SureBaslangici.teblig => usuli,
        SureBaslangici.ogrenme => ogrenme,
        SureBaslangici.tefhim => tefhim,
        SureBaslangici.kararTarihi => karar,
        SureBaslangici.ilan => ilan,
      };
      if (olay == null) {
        bekleyenler.add((
          sure: sure,
          eksikOlay: _baslangicEtiket(sure.baslangic),
        ));
        continue;
      }
      var baslangic = olay;
      var baslangicAdliTatilNedeniyleDegisti = false;
      var guven = sure.guven;
      final notlar = <String>[];

      // Ceza işinde başlangıç olayı adli tatil içindeyse tebligat/tefhim
      // geçerlidir fakat süre 1 Eylül'de işlemeye başlar. Bu, tatilden ÖNCE
      // başlayıp son günü tatile rastlayan sürenin doğrudan 3 Eylül'e uzaması
      // kuralından farklı senaryodur; ikisi üst üste eklenmez.
      if (kategori == MahkemeKategorisi.ceza &&
          TurkishLegalCalendar.inAdliTatil(baslangic)) {
        baslangic = DateTime(baslangic.year, 9, 1);
        baslangicAdliTatilNedeniyleDegisti = true;
        notlar.add(
          'Başlangıç olayı adli tatil içinde olduğundan süre 1 Eylül\'de '
          'işlemeye başlar (CMK m.331/4; 14.02.1934 t. 47/1 İBK).',
        );
      }

      // Karar tarihine bağlı kuralda karar tarihi yoksa güveni düşür.
      if (sure.tariheBagli && karar == null && guven == SureGuveni.yuksek) {
        guven = SureGuveni.orta;
      }
      if (sure.guvenNotu != null) notlar.add(sure.guvenNotu!);

      final ham = sure.hamSonTarih(baslangic);
      final adj = TurkishLegalCalendar.adjustDeadline(
        ham,
        kategori: kategori,
        // Mali tatil durması (5604 m.1/3) yalnız işaretli olgularda (vergi dava
        // açma); kanun yolu sürelerine uygulanmaz (Danıştay içtihadı).
        baslangic: baslangic,
        maliTatildeDurur: sure.maliTatildeDurur,
        // HMK m.103 / İYUK m.61: tatile tabi OLMAYAN işlerde uzatma yok.
        // Bilinmiyorsa (null) uzatma uygulanmaz — bkz. adjustDeadline.
        adliTatileTabi: adliTatileTabi,
        // HMK m.104 yalnız kanunda belirtilen süreleri uzatır.
        tatilUzatmaz: switch (sure.nitelik) {
          SureNiteligi.kanuni => null,
          SureNiteligi.hakim =>
            '⚠ Son gün adli tatile denk geliyor; bu süreyi hâkim verdi. '
                'HMK m.104 yalnız kanunda belirtilen süreleri uzattığından '
                'uzatma uygulanmadı. Kararda başka bir şey yazıyorsa ona '
                'göre düzeltin.',
          SureNiteligi.maddi =>
            'Bu süre maddi hukuka ait; adli tatil onu uzatmaz.',
        },
      );
      notlar.addAll(adj.notes);
      // Whether the recess extends it is not known, or a judge's time ends
      // in it: not certain.
      if ((adj.tatilBelirsiz ||
              (sure.nitelik == SureNiteligi.hakim &&
                  TurkishLegalCalendar.inAdliTatil(ham))) &&
          guven == SureGuveni.yuksek) {
        guven = SureGuveni.orta;
      }

      // Folio: every year the reckoning runs through is checked, not the
      // last day's alone (a count of working days crosses holidays on the
      // way): a year outside the holiday table is not given as certain,
      // since a holiday there would count as a working day; a year whose
      // religious holidays are projected is flagged.
      for (var yil = baslangic.year; yil <= adj.effectiveDate.year; yil++) {
        if (yil > TurkishLegalCalendar.kDiniBayramTabloSonYil ||
            yil < TurkishLegalCalendar.kDiniBayramTabloIlkYil) {
          guven = SureGuveni.dusuk;
          notlar.add(
            '$yil yılının dini bayramları takvimde yok; son gün '
            'doğrulanamadı.',
          );
        } else if (TurkishLegalCalendar.diniBayramProjeksiyonYili(yil)) {
          if (guven == SureGuveni.yuksek) guven = SureGuveni.orta;
          notlar.add(
            '$yil dini bayram tarihleri tahminidir; Diyanet takvimiyle '
            'doğrulayın.',
          );
        }
      }

      items.add(
        DeadlineItem(
          sureAdi: sure.ad,
          gun: sure.gun,
          sureMetni: sure.sureMetni,
          kanun: sure.kanunMaddesi,
          baslangicTarihi: baslangic,
          baslangicTuru: _baslangicEtiket(sure.baslangic),
          hamSonGun: ham,
          etkiliSonGun: adj.effectiveDate,
          kalanGun: LegalDay.of(adj.effectiveDate)
              .daysSince(LegalDay.of(bugun)),
          dayanakNotlari: notlar,
          uzadi: adj.extended || baslangicAdliTatilNedeniyleDegisti,
          guven: guven,
          tatilBelirsiz: adj.tatilBelirsiz,
        ),
      );
    }
    items.sort((a, b) => a.kalanGun.compareTo(b.kalanGun));

    return DeadlineComputation(
      tebligTarihi: usuli,
      tebligKaynagi: tebligKaynagi,
      usuliTebligTarihi: usuli,
      ogrenmeTarihi: ogrenme,
      kategori: kategori,
      items: items,
      olayBekleyenler: bekleyenler,
    );
  }

  /// Tarih-etkin kuralları karar tarihine göre seçer:
  /// - Karar tarihi VARSA: yalnız o tarihte geçerli kurallar.
  /// - Karar tarihi YOKSA: eski/yeni iki senaryoyu da görünür tut. Güncel
  ///   kuralı sessizce varsaymak 1 Haziran 2024 öncesi kararları yanlış hesaplar.
  static List<YasalSure> _uygulanabilirKurallar(
    List<YasalSure> tumu,
    DateTime? kararTarihi,
  ) {
    if (kararTarihi != null) {
      return tumu.where((s) => s.gecerliMi(kararTarihi)).toList();
    }
    return List<YasalSure>.of(tumu);
  }

  /// UETS konu metninden kategoriyi çıkarıp süreleri hesaplar.
  static DeadlineComputation computeFromKonu({
    required String konu,
    required DateTime gonderimTarihi,
    DateTime? okunmaTarihi,
    BelgeTuru belgeTuru = BelgeTuru.diger,
    DateTime? kararTarihi,
    DateTime? now,
  }) {
    final parsed = TebligatParser.parse(konu);
    return compute(
      gonderimTarihi: gonderimTarihi,
      okunmaTarihi: okunmaTarihi,
      kategori: parsed.kategori,
      belgeTuru: belgeTuru,
      kararTarihi: kararTarihi,
      now: now,
    );
  }
}

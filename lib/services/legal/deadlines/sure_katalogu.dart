/// NÖTR süre kataloğu — UI/UYAP/services'ten BAĞIMSIZ çekirdek hukukî süre olgusu.
///
/// İLKE (mimari.md): tek kaynak. Hem A1 sabit-veri cevabı (`LegalKurallarService`)
/// hem tarih hesabı (`DeadlineService`) AYNI olgudan beslenir; süre değerleri TEK
/// yerde tanımlanır → drift olmaz.
///
/// Bu dosya NÖTRdür: yalnız saf veri + saf yardımcılar. UYAP'a özgü iki şey BURADA
/// DEĞİL, `lib/uyap/legal/yasal_sure.dart` ADAPTÖRÜNDEdir:
///   • Takvim hesabı (`hamSonTarih`) — `TurkishLegalCalendar`'a bağlı (extension).
///   • Belge türü / mahkeme kategorisi → olgu eşlemesi (`surelerForBelgeTuru` vb.).
library;

/// Süre birimi. Yıl/ay TAKVİM bazlı hesaplanır (artık yıl/ay uzunluğu doğru);
/// "iş günü" tatilleri atlayarak sayar.
enum SureBirimi { gun, isGunu, hafta, ay, yil }

/// Sürenin BAŞLANGIÇ olayı. Aynı dosyada farklı başvuruların başlangıcı farklı
/// olabilir (usulî tebliğ vs fiilî öğrenme vs tefhim/karar tarihi).
enum SureBaslangici {
  /// Usulî tebliğ tarihi (elektronikte 5. günün sonu) — kanun yolu sürelerinin
  /// olağan başlangıcı; erken okuma bunu DEĞİŞTİRMEZ.
  teblig,

  /// Fiilî öğrenme (belgenin açıldığı/öğrenildiği tarih) — öğrenmeye bağlı
  /// süreler (ör. AYM bireysel başvuru) ve koruyucu erken uyarı için.
  ogrenme,

  /// Yüze karşı tefhim (duruşmada açıklanma) tarihi.
  tefhim,

  /// İlan tarihi.
  ilan,

  /// Karar/işlem tarihi.
  kararTarihi,
}

/// Bir hukuki sürenin değerlendirme güveni.
enum SureGuveni {
  /// Kural net, başlangıç ve süre kesin.
  yuksek,

  /// Kural seçimi bir bilgiye bağlı (ör. karar tarihi bilinmiyor) veya belge
  /// alt türü doğrulanmalı — kullanıcı kontrol etmeli.
  orta,

  /// Yalnızca uyarı; otomatik kesin son gün verilemez.
  dusuk,
}

/// Yasal süre tanımı: miktar + birim + başlangıç olayı + (varsa) karar tarihine
/// bağlı geçerlilik aralığı. Tarihler ISO string ('YYYY-MM-DD') tutulur ki
/// katalog `const` kalabilsin.
///
/// SAF veri modeli — takvim hesabı İÇERMEZ. Gerçek (takvim-doğru) son gün için
/// `yasal_sure.dart`'taki `hamSonTarih` extension'ı kullanılır.
/// What a time limit is, for the judicial recess: HMK m.104 extends the
/// times "kanunda belirtilen" alone.
enum SureNiteligi {
  /// A procedural time the law sets: the recess extends it where the case
  /// is subject to the recess.
  kanuni,

  /// A time the judge set: never extended as of course (HMK m.104 speaks
  /// of the law's times); the lawyer is told to check.
  hakim,

  /// A time of substantive law (İİK m.67's year): the recess does not
  /// touch it (Yargıtay 11. HD, 2022/617 E., 2023/3521 K.).
  maddi,
}

class YasalSure {
  const YasalSure({
    required this.ad,
    required this.miktar,
    required this.kanunMaddesi,
    this.birim = SureBirimi.gun,
    this.baslangic = SureBaslangici.teblig,
    this.gecerliBaslangicIso, // bu KARAR tarihinden itibaren (dahil)
    this.gecerliBitisIso, // bu KARAR tarihine kadar (hariç)
    this.guven = SureGuveni.yuksek,
    this.guvenNotu, // alt tür/belirsizlik uyarısı
    this.maliTatildeDurur = false,
    this.nitelik = SureNiteligi.kanuni,
  });

  final String ad;

  /// Whether the judicial recess may extend it (see [SureNiteligi]).
  final SureNiteligi nitelik;
  final int miktar;
  final String kanunMaddesi;
  final SureBirimi birim;
  final SureBaslangici baslangic;
  final String? gecerliBaslangicIso;
  final String? gecerliBitisIso;
  final SureGuveni guven;
  final String? guvenNotu;

  /// Mali tatilde (1–20 Temmuz, 5604 s.K. m.1/3) süre İŞLEMEZ mi?
  /// YALNIZ vergiyle ilgili DAVA AÇMA süreleri için true — Danıştay içtihadına
  /// göre kanun yolu (istinaf/temyiz) süreleri mali tatilden ETKİLENMEZ; yanlış
  /// uygulamak son günü İLERİ gösterip avukatı geç bırakır (o yüzden varsayılan
  /// false ve bilinçli olarak yalnız ilgili olguda açılır).
  final bool maliTatildeDurur;

  /// Geriye dönük uyumluluk + kaba gösterim (gün cinsinden yaklaşık). Gerçek
  /// son gün için DAİMA takvim-hesaplı `hamSonTarih` (yasal_sure.dart) kullanılır.
  int get gun => switch (birim) {
    SureBirimi.gun || SureBirimi.isGunu => miktar,
    SureBirimi.hafta => miktar * 7,
    SureBirimi.ay => miktar * 30,
    SureBirimi.yil => miktar * 365,
  };

  /// İnsan-okunur süre metni (ör. "2 hafta", "1 yıl").
  String get sureMetni => switch (birim) {
    SureBirimi.gun => '$miktar gün',
    SureBirimi.isGunu => '$miktar iş günü',
    SureBirimi.hafta => '$miktar hafta',
    SureBirimi.ay => '$miktar ay',
    SureBirimi.yil => '$miktar yıl',
  };

  /// Bu kural verilen KARAR tarihinde geçerli mi? (tarih-etkin kurallar için.)
  /// Karar tarihi bilinmiyorsa kuralı ELEME (true döner); engine güveni düşürür.
  bool gecerliMi(DateTime? kararTarihi) {
    if (gecerliBaslangicIso == null && gecerliBitisIso == null) return true;
    if (kararTarihi == null) return true;
    final k = DateTime(kararTarihi.year, kararTarihi.month, kararTarihi.day);
    final from = _parse(gecerliBaslangicIso);
    final to = _parse(gecerliBitisIso);
    if (from != null && k.isBefore(from)) return false;
    if (to != null && !k.isBefore(to)) return false; // [from, to)
    return true;
  }

  /// Bu kural karar tarihine bağlı mı (tarih bilinmezse güven düşer)?
  bool get tariheBagli =>
      gecerliBaslangicIso != null || gecerliBitisIso != null;

  static DateTime? _parse(String? iso) {
    if (iso == null) return null;
    final p = iso.split('-');
    if (p.length != 3) return null;
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }
}

/// 7499 sayılı Kanun'un yürürlük tarihi (1 Haziran 2024) — CMK kanun yolu
/// sürelerindeki "tebliğden 2 hafta" değişikliğinin başlangıcı.
const k7499 = '2024-06-01';

// ───────────────────────────────────────────────────────────────────────────
// KANONİK SÜRE OLGULARI — TEK KAYNAK.
// Hem DeadlineService (belge türü / mahkeme kategorisi indeksi, yasal_sure.dart)
// hem A1 LegalKurallarService (soru terimi indeksi) BU olgulara referans verir →
// değer/dayanak/güven tek yerde; drift olmaz. Değer değişirse yalnız burası güncellenir.
// ───────────────────────────────────────────────────────────────────────────

// ── Kanun yolları — hukuk (HMK) ──
const sIstinafHukuk = YasalSure(
  ad: 'İstinaf süresi',
  miktar: 2,
  birim: SureBirimi.hafta,
  kanunMaddesi: 'HMK m.345',
);
const sTemyizHukuk = YasalSure(
  ad: 'Temyiz süresi',
  miktar: 2,
  birim: SureBirimi.hafta,
  kanunMaddesi: 'HMK m.361',
  // SÜRE 7589 s.K. ile DEĞİŞMEDİ (2 hafta). Değişen, temyizin AÇIK olup
  // olmadığıdır: HMK m.362/3 (7589/25, 31/7/2026) BAM'ın istinafı kabul edip
  // YENİDEN ESAS hakkında verdiği kararlar için temyiz yolunu açtı.
  guvenNotu:
      'Süre tebliğden 2 haftadır. Kararın temyiz edilebilir olup '
      'olmadığını ayrıca kontrol edin: 31/7/2026 sonrası BİM istinafı kabul '
      'edip yeniden esas hakkında karar verdiyse, kabul/ret kısmı HMK m.341/2 '
      'parasal sınırının üzerindeyse temyiz açıktır (m.362/3) — fark sınırı '
      'geçmiyorsa veya karar sadece yargılama gideri/vekalet ücretine '
      'ilişkinse kapalıdır.',
);
const sCevapHmk127 = YasalSure(
  ad: 'Cevap süresi',
  miktar: 2,
  birim: SureBirimi.hafta,
  kanunMaddesi: 'HMK m.127',
);

/// HMK m.136/1: the plaintiff's reply to the answer, in two weeks from
/// its service; the defendant's second answer, in two weeks from the
/// reply's. Not in the simple procedure (HMK m.317/3), which a case's
/// court alone does not tell: the lawyer is to look.
const sCevabaCevap = YasalSure(
  ad: 'Cevaba cevap süresi',
  miktar: 2,
  birim: SureBirimi.hafta,
  kanunMaddesi: 'HMK m.136',
  guven: SureGuveni.orta,
  guvenNotu:
      'Basit yargılama usulünde cevaba cevap verilmez (HMK m.317/3); '
      'dosyanın usulüne bakın.',
);
const sIkinciCevap = YasalSure(
  ad: 'İkinci cevap süresi',
  miktar: 2,
  birim: SureBirimi.hafta,
  kanunMaddesi: 'HMK m.136',
  guven: SureGuveni.orta,
  guvenNotu:
      'Basit yargılama usulünde ikinci cevap verilmez (HMK m.317/3); '
      'dosyanın usulüne bakın.',
);

/// CMK m.297/3: the chief prosecutor's opinion, served to the one it goes
/// against, answered in two weeks.
const sTeblignameCevap = YasalSure(
  ad: 'Tebliğnameye cevap',
  miktar: 2,
  birim: SureBirimi.hafta,
  kanunMaddesi: 'CMK m.297/3',
);

/// The answer to the other side's appeal, in two weeks from its service:
/// HMK m.347/2, in an appeal on points of law through m.366; CMK m.277/1
/// and m.297/1 (two weeks since Law 7499).
const sKanunYoluCevapHukuk = YasalSure(
  ad: 'Kanun yolu dilekçesine cevap',
  miktar: 2,
  birim: SureBirimi.hafta,
  kanunMaddesi: 'HMK m.347, m.366',
);
const sKanunYoluCevapCeza = YasalSure(
  ad: 'Kanun yolu dilekçesine cevap',
  miktar: 2,
  birim: SureBirimi.hafta,
  kanunMaddesi: 'CMK m.277, m.297',
);

/// HMK m.394/1: the other side's objection to an interim injunction given
/// without hearing it, in a week from its enforcement, or from its service
/// when not present then. Not chosen from a document's kind: the lawyer
/// picks it for a notice (an interim decision is no kind with a time).
const sTedbirItiraz = YasalSure(
  ad: 'İhtiyati tedbire itiraz',
  miktar: 1,
  birim: SureBirimi.hafta,
  kanunMaddesi: 'HMK m.394',
  guvenNotu: 'Tedbir uygulanırken hazır bulunduysanız süre uygulamadan başlar.',
);
const sBilirkisiRaporu = YasalSure(
  ad: 'Bilirkişi raporuna itiraz',
  miktar: 2,
  birim: SureBirimi.hafta,
  kanunMaddesi: 'HMK m.281',
  guven: SureGuveni.orta,
  guvenNotu:
      'Hukuk yargılamasında rapora itiraz/beyan süresi tebliğden '
      'itibaren 2 haftadır (HMK m.281/1). Ceza/idari yargıda farklı olabilir; '
      'mahkeme türünü ve raporun ek-süre içerip içermediğini doğrulayın.',
);

// ── İcra (İİK) ──
const sIcraSikayet = YasalSure(
  ad: 'İcra mahkemesine şikâyet/itiraz',
  miktar: 7,
  birim: SureBirimi.gun,
  kanunMaddesi: 'İİK m.16',
  guven: SureGuveni.orta,
  guvenNotu:
      'İcra dosyasının türüne göre süre/dayanak değişir; belgeden '
      'doğrulayın.',
);
const sItirazinIptali = YasalSure(
  ad: 'İtirazın iptali davası',
  miktar: 1,
  birim: SureBirimi.yil,
  kanunMaddesi: 'İİK m.67',
  nitelik: SureNiteligi.maddi,
);
const sOdemeEmriIik62 = YasalSure(
  ad: 'Ödeme emrine itiraz (genel haciz)',
  miktar: 7,
  birim: SureBirimi.gun,
  kanunMaddesi: 'İİK m.62',
  guvenNotu:
      'Genel haciz yolunda itiraz 7 gündür (İİK m.62). Kambiyo takibinin '
      'kendi türü vardır (odemeEmriKambiyo, 5 gün) — bu süre ona uygulanmaz.',
);

// ── Kambiyo senetlerine mahsus haciz yolu (Örnek 10, İİK m.168) ──
//
// TEK SÜRE DEĞİL: madde ödeme emrine yazılacak dört ayrı ihtarı sayıyor ve
// üçü BEŞ günlük. Genel haciz yolunun 7 günü buraya uygulanırsa avukat iki
// gün GEÇ uyarılır — hak kaybettiren yön. Süreler maddenin bent sırasıyla.
const sKambiyoBorcaItiraz = YasalSure(
  ad: 'Kambiyo — borca itiraz',
  miktar: 5,
  birim: SureBirimi.gun,
  kanunMaddesi: 'İİK m.168/5',
  guvenNotu:
      'Borçlu olmadığı, borcun itfa edildiği, mehil verildiği, alacağın '
      'zamanaşımına uğradığı veya yetki itirazı; icra mahkemesine dilekçeyle.',
);
const sKambiyoImzayaItiraz = YasalSure(
  ad: 'Kambiyo — imzaya itiraz',
  miktar: 5,
  birim: SureBirimi.gun,
  kanunMaddesi: 'İİK m.168/4',
  guvenNotu:
      'İmza kendisine ait değilse AÇIKÇA dilekçeyle bildirilmeli; aksi hâlde '
      'imza kendisinden sadır sayılır. Haksız inkârda alacağın %10\'u para cezası.',
);
const sKambiyoVasifSikayeti = YasalSure(
  ad: 'Kambiyo — senedin vasfına şikâyet',
  miktar: 5,
  birim: SureBirimi.gun,
  kanunMaddesi: 'İİK m.168/3',
  guvenNotu:
      'Takibin dayanağı senet kambiyo senedi vasfını taşımıyorsa icra '
      'mahkemesine şikâyet.',
);
const sKambiyoOdeme = YasalSure(
  ad: 'Kambiyo — borcun ödenmesi',
  miktar: 10,
  birim: SureBirimi.gun,
  kanunMaddesi: 'İİK m.168/2',
  guvenNotu:
      'Borç ve takip masraflarının ödenmesi için tanınan süre; itiraz süresi '
      'DEĞİLDİR (o beş gündür).',
);

// ── İlamlı icra (icra emri) ──
//
// İcra emrine "itiraz" edilmez; ödeme süresi ile icranın geri bırakılması
// talebi ayrı ayrı işler. Eski tek kayıt (İİK m.16 şikâyet) yanıltıcıydı:
// şikâyetin başlangıcı tebliğ değil ŞİKÂYET KONUSU İŞLEMDİR, o yüzden
// tebliğe bağlı bir süre olarak gösterilmesi yanlıştı.
const sIcraEmriOdeme = YasalSure(
  ad: 'İcra emri — ödeme süresi',
  miktar: 7,
  birim: SureBirimi.gun,
  kanunMaddesi: 'İİK m.32',
  guvenNotu:
      'Hükmolunanın ödenmesi veya teminatın verilmesi; aynı süre içinde mal '
      'beyanı da gerekir (İİK m.74).',
);
const sIcraEmriGeriBirakma = YasalSure(
  ad: 'İcra emri — icranın geri bırakılması',
  miktar: 7,
  birim: SureBirimi.gun,
  kanunMaddesi: 'İİK m.33',
  guvenNotu:
      'Zamanaşımı, itfa veya imhal iddiasıyla icra mahkemesine başvuru. '
      'Tebliğden SONRA doğan itfa/imhal/zamanaşımı istekleri her zaman '
      'yapılabilir; bu süre tebliğ anındaki iddialar içindir.',
);
const sHacizIhbarnamesi = YasalSure(
  ad: 'Haciz ihbarnamesine itiraz',
  miktar: 7,
  birim: SureBirimi.gun,
  kanunMaddesi: 'İİK m.89',
  guven: SureGuveni.orta,
  guvenNotu:
      'İhbarnamenin birinci, ikinci ya da üçüncü olduğu belgeden '
      'anlaşılamadı. Birinci ve ikincisine itiraz 7 gündür; üçüncüsünde '
      '15 gün içinde ödeme/teslim ya da menfi tespit davası gerekir.',
);

/// İİK m.89/1: the first garnishment notice, objected to in seven days.
const sHaciz891 = YasalSure(
  ad: 'Birinci haciz ihbarnamesine itiraz',
  miktar: 7,
  birim: SureBirimi.gun,
  kanunMaddesi: 'İİK m.89/1',
);

/// İİK m.89/2: the second, sent when the first was not objected to.
const sHaciz892 = YasalSure(
  ad: 'İkinci haciz ihbarnamesine itiraz',
  miktar: 7,
  birim: SureBirimi.gun,
  kanunMaddesi: 'İİK m.89/2',
);

/// İİK m.89/3: the third. Fifteen days to pay or deliver, or to bring the
/// suit that the debt is not owed.
const sHaciz893Dava = YasalSure(
  ad: 'Üçüncü haciz ihbarnamesi — ödeme/teslim ya da menfi tespit davası',
  miktar: 15,
  birim: SureBirimi.gun,
  kanunMaddesi: 'İİK m.89/3',
);

/// İİK m.89/3: and when the suit is brought, the paper that says so is
/// given to the enforcement office within twenty days of the notice.
const sHaciz893Belge = YasalSure(
  ad: 'Üçüncü haciz ihbarnamesi — dava açıldığı belgesini icra dairesine verme',
  miktar: 20,
  birim: SureBirimi.gun,
  kanunMaddesi: 'İİK m.89/3',
  guvenNotu: 'Yalnız menfi tespit davası açtıysanız.',
);

/// İİK m.363 as 7499 wrote it: an enforcement court's decision given on
/// or after 1 June 2024 is appealed in two weeks from its service. Not
/// every such decision is open to appeal, and the sum matters.
const sIcraMahkemesiIstinaf = YasalSure(
  ad: 'İstinaf süresi (icra mahkemesi kararı)',
  miktar: 2,
  birim: SureBirimi.hafta,
  kanunMaddesi: 'İİK m.363',
  gecerliBaslangicIso: k7499,
  guven: SureGuveni.orta,
  guvenNotu:
      'Kararın istinafa açık bir karar türü olup olmadığı ve parasal sınır '
      'denetlenmedi (İİK m.363).',
);

// ── Ceza (CMK) — 7499 tarih-etkin geçişi ──
// Eski rejimde süre hükmün açıklanmasından başlar; hüküm yokluğunda
// açıklandıysa tebliğden. Hangisi olduğu tebligattan anlaşılmaz: iki
// başlangıç ayrı satırdır, eski kural topluca tefhime ya da tebliğe
// çevrilmez. Yüze karşı satırı tefhim günü bilinene dek beklemede kalır.
const sCezaIstinafEski = YasalSure(
  ad: 'İstinaf süresi (eski hüküm)',
  miktar: 7,
  birim: SureBirimi.gun,
  kanunMaddesi: 'CMK m.273',
  gecerliBitisIso: k7499,
  guven: SureGuveni.orta,
  guvenNotu:
      'Karar 1 Haziran 2024 ÖNCESİ ve hüküm yokluğunuzda açıklandıysa '
      'tebliğden 7 gün. Yüzünüze karşı açıklandıysa süre açıklamadan '
      'başlar (ayrı satır). Karar tarihi belirsizse kontrol edin.',
);
const sCezaIstinafEskiTefhim = YasalSure(
  ad: 'İstinaf süresi (eski hüküm, yüze karşı)',
  miktar: 7,
  birim: SureBirimi.gun,
  kanunMaddesi: 'CMK m.273/1',
  baslangic: SureBaslangici.tefhim,
  gecerliBitisIso: k7499,
  guven: SureGuveni.orta,
  guvenNotu:
      'Karar 1 Haziran 2024 ÖNCESİ ve hüküm yüzünüze karşı açıklandıysa '
      'süre açıklamadan başlar; tebligat bu süreyi yeniden başlatmaz.',
);
const sCezaIstinafYeni = YasalSure(
  ad: 'İstinaf süresi',
  miktar: 2,
  birim: SureBirimi.hafta,
  kanunMaddesi: 'CMK m.273',
  gecerliBaslangicIso: k7499,
  guven: SureGuveni.orta,
  guvenNotu:
      '1 Haziran 2024 ve sonrası kararlarda gerekçeli kararın '
      'tebliğinden 2 hafta. Karar tarihi belirsizse kontrol edin.',
);
const sCezaTemyizEski = YasalSure(
  ad: 'Temyiz süresi (eski hüküm)',
  miktar: 15,
  birim: SureBirimi.gun,
  kanunMaddesi: 'CMK m.291',
  gecerliBitisIso: k7499,
  guven: SureGuveni.orta,
  guvenNotu:
      'Karar 1 Haziran 2024 ÖNCESİ ve hüküm yokluğunuzda açıklandıysa '
      'tebliğden 15 gün. Yüzünüze karşı açıklandıysa süre açıklamadan '
      'başlar (ayrı satır). Karar tarihi belirsizse kontrol edin.',
);
const sCezaTemyizEskiTefhim = YasalSure(
  ad: 'Temyiz süresi (eski hüküm, yüze karşı)',
  miktar: 15,
  birim: SureBirimi.gun,
  kanunMaddesi: 'CMK m.291/1',
  baslangic: SureBaslangici.tefhim,
  gecerliBitisIso: k7499,
  guven: SureGuveni.orta,
  guvenNotu:
      'Karar 1 Haziran 2024 ÖNCESİ ve hüküm yüzünüze karşı açıklandıysa '
      'süre açıklamadan başlar; tebligat bu süreyi yeniden başlatmaz.',
);
const sCezaTemyizYeni = YasalSure(
  ad: 'Temyiz süresi',
  miktar: 2,
  birim: SureBirimi.hafta,
  kanunMaddesi: 'CMK m.291',
  gecerliBaslangicIso: k7499,
  guven: SureGuveni.orta,
  guvenNotu:
      '1 Haziran 2024 ve sonrası kararlarda gerekçeli kararın '
      'tebliğinden itibaren 2 hafta (CMK Geçici m.6/1-c).',
);

// ── İdari / vergi (İYUK) ──
const sIdariDava = YasalSure(
  ad: 'İdari dava açma süresi',
  miktar: 60,
  birim: SureBirimi.gun,
  kanunMaddesi: 'İYUK m.7',
);
const sVergiDava = YasalSure(
  ad: 'Vergi dava açma süresi',
  miktar: 30,
  birim: SureBirimi.gun,
  kanunMaddesi: 'İYUK m.7',
  // 5604 s.K. m.1/3: vergiyle ilgili dava açma süresi mali tatilde (1–20 Tem)
  // İŞLEMEZ. Yalnız bu olguda açık — kanun yolu sürelerine UYGULANMAZ.
  maliTatildeDurur: true,
);

/// İdari yargıda GEREKÇELİ KARARA karşı kanun yolu süresi. İstinaf (İYUK m.45)
/// da temyiz (İYUK m.46) de tebliğden itibaren 30 GÜNDÜR. NOT: Önceden bu
/// bağlamda yanlışlıkla 60 günlük DAVA AÇMA süresi (sIdariDava) gösteriliyordu —
/// avukatı 30 gün GEÇ bırakırdı. Dava açma olguları (sIdariDava/sVergiDava)
/// yalnız dava-öncesi bağlam (A1 soru-cevap, ihbarname) içindir.
/// İYUK m.16/3: the defence to an administrative suit, thirty days from
/// the petition's service; the court may extend it, and the special
/// procedures (m.20/A, 20/B) are shorter.
const sIyukSavunma = YasalSure(
  ad: 'Savunma süresi',
  miktar: 30,
  birim: SureBirimi.gun,
  kanunMaddesi: 'İYUK m.16',
  guven: SureGuveni.orta,
  guvenNotu:
      'İvedi yargılama (İYUK m.20/A) ve özel usuller (m.20/B) daha kısa '
      'süre öngörür; mahkemenin ek süre kararı da süreyi değiştirir.',
);

const sIdariKanunYolu = YasalSure(
  ad: 'İstinaf/temyiz süresi (idari yargı)',
  miktar: 30,
  birim: SureBirimi.gun,
  kanunMaddesi: 'İYUK m.45/46',
  guven: SureGuveni.orta,
  // SÜRE 7589 s.K. ile DEĞİŞMEDİ (30 gün); yeni İYUK m.46/2 de "otuz gün"
  // diyor. Değişen, temyizin hangi kararlara karşı AÇIK olduğudur.
  guvenNotu:
      'İdari yargıda istinaf ve temyiz süresi tebliğden 30 gündür '
      '(İYUK m.45/46). Kararın kesin olup olmadığını ve başvuru merciini '
      '(BİM/Danıştay) kontrol edin. 31/7/2026 sonrası BİM kararlarında: BİM '
      'ilk derece kararını kaldırıp yeniden karar verdiyse temyiz yolu 30 gün '
      'ile açıktır (İYUK m.46/2, 7589 s.K.) — tek hâkimli davalar, 4081/3091/'
      '6458 uygulamasından doğanlar, farkı parasal sınırı geçmeyenler ve '
      'sadece vekalet ücreti/yargılama giderine ilişkin kararlar hariç.',
);

// ── Yargı kolu belirsiz fallback (güven düşürülür) ──
const sIstinafBilinmeyen = YasalSure(
  ad: 'İstinaf süresi',
  miktar: 2,
  birim: SureBirimi.hafta,
  kanunMaddesi: 'HMK m.345',
  guven: SureGuveni.orta,
  guvenNotu: 'Yargı kolu belirsiz; süre hukuk yargısı varsayımıyla verildi.',
);
const sTemyizBilinmeyen = YasalSure(
  ad: 'Temyiz süresi',
  miktar: 2,
  birim: SureBirimi.hafta,
  kanunMaddesi: 'HMK m.361',
  guven: SureGuveni.orta,
  guvenNotu: 'Yargı kolu belirsiz; süre hukuk yargısı varsayımıyla verildi.',
);

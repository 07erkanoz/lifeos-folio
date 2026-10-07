import 'belge_turu.dart';
import 'mahkeme_kategori.dart';
import 'turkish_legal_calendar.dart';
import 'sure_katalogu.dart';

// Nötr süre olgusu (YasalSure) + enumlar + KANONİK olgular TEK kaynakta:
// lib/legal/sure_katalogu.dart. Geriye dönük uyum için RE-EXPORT → mevcut importlar
// 'yasal_sure.dart'tan YasalSure/SureBirimi/... + kanonik olguları kullanmaya devam eder.
export 'sure_katalogu.dart';

/// Süre olgusunun TAKVİM-doğru HAM son tarih hesabı — UYAP adaptörü
/// (`TurkishLegalCalendar`'a bağlı). Nötr katalog modeli takvim İÇERMEZ; bu hesap
/// burada extension olarak tutulur ki katalog UI/services'ten bağımsız kalsın.
extension YasalSureTakvim on YasalSure {
  /// Başlangıç tarihinden HAM son tarih (hukuki düzeltme öncesi), birime göre
  /// TAKVİM-doğru: yıl=takvim yılı (artık yıl doğru), ay=takvim ayı.
  DateTime hamSonTarih(DateTime baslangicTarihi) {
    final d = DateTime(
      baslangicTarihi.year,
      baslangicTarihi.month,
      baslangicTarihi.day,
    );
    switch (birim) {
      case SureBirimi.gun:
        return DateTime(d.year, d.month, d.day + miktar);
      case SureBirimi.hafta:
        return DateTime(d.year, d.month, d.day + miktar * 7);
      // HMK m.92: the corresponding day, or the month's last when the
      // month has none. DateTime(y, m + n, d) rolled over instead: 31
      // January plus a month was 3 March, a deadline given too late.
      case SureBirimi.ay:
        return _correspondingDay(d.year, d.month + miktar, d.day);
      case SureBirimi.yil:
        return _correspondingDay(d.year + miktar, d.month, d.day);
      case SureBirimi.isGunu:
        var x = d;
        var kalan = miktar;
        while (kalan > 0) {
          x = DateTime(x.year, x.month, x.day + 1);
          if (TurkishLegalCalendar.isBusinessDay(x)) kalan--;
        }
        return x;
    }
  }
}

/// SÜRE HESABI SÜRÜMÜ — hesap mantığı her değiştiğinde ARTIRILIR.
///
/// Neden var: hesaplanan süreler `uets_tebligat.sure_hesaplandi` ile "bitti"
/// işaretleniyordu ve bir daha ASLA hesaplanmıyordu. 2026-07-27'de iki hukuki
/// hata düzeltildi (adli tıp raporu → gerekçeli karar sanılıyordu; ilk derece
/// kararına temyiz süresi üretiliyordu) ama SUPABASE'DEKİ ESKİ HESAPLAR OLDUĞU
/// GİBİ KALDI — web'e yanlış süre düşmeye devam etti.
///
/// Elle silmek tek seferlik bir yama olurdu. Bunun yerine sürüm: istemci
/// `sure_hesaplandi < surum` olan tebligatı yeniden hesaplar, sonuç Supabase'e
/// yazılırken eski satırlar silinip yenisi konur. Yani hesap mantığındaki her
/// düzeltme, mevcut yanlış veriyi KENDİLİĞİNDEN onarır.
///
/// SÜRÜM GEÇMİŞİ:
///   1 — ilk hesap (2026 öncesi)
///   2 — 2026-07-27: rapor ailesi tanındı (HMK m.281); ilk derece kararında
///       temyiz üretimi kaldırıldı (temyiz BAM kararına karşıdır)
///   3 — 2026-08-03: CMK 7499 geçişi temyize eklendi; cezada adli tatil içinde
///       doğan sürenin 1 Eylül'de başlaması ve kategoriye göre BAM yolu düzeltildi
///   4 — 2026-08-27: HMK m.103 kapısı — adli tatile TABİ OLMAYAN işlerde
///       (işçinin açtığı iş davaları, nafaka/velayet/soybağı/vesayet, nüfus,
///       iflas-konkordato, çekişmesiz yargı, ivedi işler) m.104 uzatması
///       uygulanmaz; tabi olup olmadığı bilinmiyorsa da uzatılmaz (güvenli
///       yön). İdari uzatmanın dayanağı m.61 yerine İYUK m.8/3 olarak
///       düzeltildi (tarih değişmedi: 7 Eylül).
///   5 — 2026-10-07 (Folio): a notice's deadlines are candidates the
///       lawyer confirms, made rule by rule from its documents; kambiyo,
///       the garnishment notice's stages, İİK m.363 for enforcement
///       courts, İYUK m.16, reports by jurisdiction; days counted on dates,
///       not hours.
const sureHesapSurumu = 5;

/// Kategori bazlı yasal süreler (belge türü kanun yolu kararıysa kullanılır).
/// Değerler kanonik olgulardan (sure_katalogu.dart) gelir — TEK kaynak.
const kategoriYasalSureleri = <MahkemeKategorisi, List<YasalSure>>{
  // HUKUKI DUZELTME: ilk derece gerekceli kararina karsi yol ISTINAF'tir.
  // TEMYIZ (HMK m.361) BAM kararina karsidir ve suresi BAM kararinin
  // tebliginden isler. Ikisini birlikte gostermek avukata var olmayan bir
  // kanun yolu suresi bildiriyordu. Temyiz zaten `istinafKarari` turunde var.
  MahkemeKategorisi.hukuk: [sIstinafHukuk],
  // An enforcement court's decision: appeal under İİK m.363, and only the
  // regime 7499 wrote (decisions from 1 June 2024). The complaint (m.16)
  // and the suit against an objection (m.67) start from other events, not
  // from a decision's service; they stay in the catalogue for the lawyer's
  // own reckoning.
  MahkemeKategorisi.icra: [sIcraMahkemesiIstinaf],
  MahkemeKategorisi.ceza: [sCezaIstinafEski, sCezaIstinafYeni],
  // DÜZELTME (hukuki): gerekçeli karara karşı süre İSTİNAF/TEMYİZ'dir (İYUK
  // m.45/46 → 30 gün). Önceki eşleme dava açma sürelerini (60/30 gün, İYUK m.7)
  // gösteriyordu — idari yargıda 60 gün göstermek avukatı 30 gün GEÇ bırakırdı.
  // Dava açma olguları A1 soru-cevap için katalogda DURUYOR.
  MahkemeKategorisi.idare: [sIdariKanunYolu],
  MahkemeKategorisi.vergi: [sIdariKanunYolu],
};

/// Bilinmeyen kategori için genel süreler (en yaygın hukuk kanun yolları).
const bilinmeyenYasalSureleri = <YasalSure>[sIstinafBilinmeyen];

List<YasalSure> yasalSurelerForKategori(MahkemeKategorisi kategori) =>
    kategoriYasalSureleri[kategori] ?? bilinmeyenYasalSureleri;

/// BELGE TÜRÜNE göre uygulanabilir yasal süre(ler). Standart kanun yolu süresi
/// olmayan türler (tensip, ara karar, davetiye, müzekkere, ihtarname, vekâletname,
/// zarf, belirsiz) için BOŞ döner. Değerler kanonik olgulardan (sure_katalogu.dart).
List<YasalSure> surelerForBelgeTuru(
  BelgeTuru turu,
  MahkemeKategorisi kategori,
) {
  switch (turu) {
    case BelgeTuru.gerekceliKarar:
    case BelgeTuru.kararIlami:
      return kategoriYasalSureleri[kategori] ?? bilinmeyenYasalSureleri;
    case BelgeTuru.istinafKarari:
      return switch (kategori) {
        MahkemeKategorisi.hukuk => const [sTemyizHukuk],
        MahkemeKategorisi.ceza => const [sCezaTemyizEski, sCezaTemyizYeni],
        MahkemeKategorisi.idare ||
        MahkemeKategorisi.vergi => const [sIdariKanunYolu],
        MahkemeKategorisi.icra ||
        MahkemeKategorisi.bilinmeyen => const [sTemyizBilinmeyen],
      };
    case BelgeTuru.odemeEmri:
      return const [sOdemeEmriIik62];
    case BelgeTuru.odemeEmriKambiyo:
      // Dördü de gösterilir: hangisinin işleyeceği somut savunmaya bağlı ve
      // avukat ilgisizi eler; eksik göstermek ise kaçırtır.
      return const [
        sKambiyoBorcaItiraz,
        sKambiyoImzayaItiraz,
        sKambiyoVasifSikayeti,
        sKambiyoOdeme,
      ];
    case BelgeTuru.icraEmri:
      return const [sIcraEmriOdeme, sIcraEmriGeriBirakma];
    case BelgeTuru.hacizIhbarnamesi:
      return const [sHacizIhbarnamesi];
    case BelgeTuru.hacizIhbarnamesiBirinci:
      return const [sHaciz891];
    case BelgeTuru.hacizIhbarnamesiIkinci:
      return const [sHaciz892];
    case BelgeTuru.hacizIhbarnamesiUcuncu:
      return const [sHaciz893Dava, sHaciz893Belge];
    // A statement of claim is answered by the court's own procedure: HMK
    // m.127 in civil courts, İYUK m.16 in administrative ones; a criminal
    // or enforcement court has no such answer.
    case BelgeTuru.davaDilekcesi:
      return switch (kategori) {
        MahkemeKategorisi.hukuk ||
        MahkemeKategorisi.bilinmeyen => const [sCevapHmk127],
        MahkemeKategorisi.idare ||
        MahkemeKategorisi.vergi => const [sIyukSavunma],
        MahkemeKategorisi.ceza || MahkemeKategorisi.icra => const [],
      };
    // HMK m.281 in civil courts, through İYUK m.31 in administrative ones
    // and İİK m.18 in enforcement courts. A criminal court gives its own
    // time for a report (CMK m.67/5), written in its decision, not in a
    // catalogue.
    case BelgeTuru.bilirkisiRaporu:
      return kategori == MahkemeKategorisi.ceza
          ? const []
          : const [sBilirkisiRaporu];
    case BelgeTuru.temyizKarari:
    case BelgeTuru.cevapDilekcesi:
    case BelgeTuru.tensipZapti:
    case BelgeTuru.araKarar:
    case BelgeTuru.durusmaDavetiyesi:
    case BelgeTuru.durusmaTutanagi:
    case BelgeTuru.iddianame:
    case BelgeTuru.muzekkere:
    case BelgeTuru.ihtarname:
    case BelgeTuru.vekaletname:
    case BelgeTuru.tebligatZarfi:
    case BelgeTuru.diger:
      return const [];
  }
}

/// [day] of [month] of [year], or that month's last day when it is shorter.
DateTime _correspondingDay(int year, int month, int day) {
  final last = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > last ? last : day);
}

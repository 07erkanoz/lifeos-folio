# UYAP senkron haritası (14 Ekim 2026, `1fc52fd` sonrası kod)

Bu belge **bugünkü kodun gerçekte ne yaptığını** anlatır; tasarım değildir. Her satırın kaynağı
koddadır (dosya:satır). Kısaltmalar: PS = `lib/services/portal/portal_sync.dart`,
PC = `lib/services/uyap/uyap_case_panel_controller.dart`, ST = `lib/services/uyap/uyap_case_store.dart`,
DB = `lib/services/portal/portal_database.dart`. "Otomatik okuma" = Ayarlar'daki `uyap_auto`
(varsayılan kapalı). Gece = 21:00–07:00.

## 1. Kilit bulgu: "her şey her şeyi tetikliyor"

`syncWeb()` ve `syncMobile()` yalnız portföy okumaz. İkisi de sonunda **dosyaları tek tek okur**
(`_fill`, PS:1575, PS:1950); `syncMobile` bitince web bağlıysa ayrıca web ile tek tek okumayı
başlatır (`_fillOnly`, PS:1958). `_fill`, web'in (ya da mobilin) hiç okumadığı her açık dosyayı
okur: künye, taraflar, evrak listesi (sayfa sayfa), para, icra hesabı, borçlular — dosya başına
6–9 istek.

Dolayısıyla `syncWeb`/`syncMobile` çağıran **her yer** dosya dosya okumayı başlatabilir:
ajanda sayfasını açmak, giriş pencereleri, ilk bağlantı, yeni dosya bildiren bir UYAP bildirimi,
5 dakikalık zamanlayıcı.

## 2. Tetikleyiciler ve zincirleri

| # | Tetikleyici | Koşul | Ne çalışır / UYAP'a ne sorulur | Sonra ne tetiklenir |
|---|---|---|---|---|
| 1 | Uygulama açılışı | — | Kayıtlı mobil, web, UETS oturumları geri alınır (mobil: ağ yoksa 8 kez artan aralıkla) | Oturum gelince 3/4/5 |
| 2 | Editör penceresi | `quiet` | Oturumlar alınır; hiçbir senkron, zamanlayıcı yok | — |
| 3 | Web oturumu geldi (giriş, geri alma, diğer cihaz) | `_connected` PS:463 | Otomatik açık: `syncWeb` + bildirimler. Kapalı: yalnız portföy hiç okunmadıysa `syncWeb` | 13 |
| 4 | Mobil oturumu geldi | aynı | `syncMobile` | 14 |
| 5 | UETS oturumu geldi | giriş ise ya da otomatik açık | `syncUets` | 17 |
| 6 | **Ekranlardaki giriş sonrası çağrılar** | **ayar denetimi yok** | Web girişi → `syncWeb()`: channel_bar.dart:84, desktop_home.dart:844, home_page.dart:2844, portfolio_page.dart:228, settings_page.dart:678. Mobil girişi → `syncMobile()`: channel_bar.dart:321, desktop_home.dart:872, home_page.dart:2834, settings_page.dart:645, uyap_case_picker.dart:350 | 13/14 (**her girişte**) |
| 7 | Diğer cihazdan oturum devri | | 3/4 gibi | |
| 8 | 5 dk zamanlayıcı | otomatik açık, gece değil | Bildirimler (saatte 1), `_readDue`: duruşma (günde 1), portföy (haftada 1) ya da okunmamış dosya varsa `syncMobile`/`syncWeb`; web bağlıysa `enrichOnWeb` | 13/14/24 |
| 9 | Otomatik okumayı açmak | gece değil | Bildirimler + `_readDue` | 8 |
| 10 | Telefon öne gelince | otomatik açık | Bildirimler | 16 |
| 11 | Telefon arka plan görevi (15 dk) | otomatik, bildirim açık | Bildirimler; yeni "Vekil Kaydı" varsa **tam portföy okuması** başlayabilir (koddan çıkarım, gözlenmedi) | 16 |
| 12 | **Ajanda sayfasını açmak** | **ayar denetimi yok** | `syncWeb()` + `syncMobile()` (agenda_page.dart:287) | 13/14 → **dosya dosya okuma** |
| 13 | `syncWeb` | duruşma/portföy vadesi ya da okunmamış dosya | Duruşmalar (5 pencere); portföy: birim türü × sayfa (500'lük, en çok 40 sayfa), Yargıtay/Danıştay daireleri, savcılıklar (bilinenler; 30 günde bir ya da yeni dosyada 81 il); **her sayfadaki tarafı bilinmeyen açık dosya için ayrı taraf isteği**; sonra `_fill(web)` | Portföy satırları, taraflar, duruşmalar; ardından süre ve tebligat eşleşmesi, diğer cihazlara bildirim |
| 14 | `syncMobile` | | Duruşmalar; portföy: birim × mahkeme × sayfa (100'lük, **en çok 20 sayfa**); web yoksa önce taraflar sonra `_fill(mobil)`; bitince web bağlıysa `_fillOnly` (web ile tek tek okuma) | 13 gibi |
| 15 | Senkronize et / Portföyü yenile | elle | Duruşmalar her zaman; portföy son 3 saatte okunmadıysa; sonra `_fill` | |
| 16 | Bildirimler (sayfa açılışı, Yenile) | sayfa açılışında 30 dk tazelik, **ayar denetimi yok** | Mobil bildirim listesi (2 sayfa; ilkinde 10) + metinsiz 25 bildirimin metni; web son 30 gün. **Portföyde olmayan dosyayı bildiren "Vekil Kaydı" → tam portföy okuması (81 il dahil) → `_fill`** | 13/14 |
| 17 | UETS (sayfa açılışı, Yenile, giriş) | **ayar denetimi yok** | Tebligatlar, paketler; **tarafı bilinmeyen en çok 30 dosya için UYAP'a taraf sorgusu** (`_fetchMissingParties`, web'de dosya arama 81 ile kadar uzayabilir) | Süreler, kâğıttan duruşmalar |
| 18 | **Dosya sayfasını açmak** | bağlıysa ve kayıt yoksa / 30 dk'dan eskiyse / yalnız mobilden okunmuşsa | O dosya okunur (20) — **pratikte neredeyse her açılışta** | 20 |
| 19 | UYAP'tan tazele, editör UYAP paneli, dosya seçici | elle | 20 | |
| 20 | Tek dosya okuma (`PC.refresh`) | | Web: dosyayı bul, izinler, künye, taraflar, evrak (sayfa sayfa), para, hesap, borçlular (~6–9 istek). Mobil: kimlik arama + taraflar + evrak | Dosya kaydı, taraflar, "okundu" işareti, diğer cihazlara bildirim |
| 21 | Ajandada duruşmanın senkron simgesi | elle | Künye + evrak; **yalnız portföy satırına yazar, dosya kaydına değil** | |
| 22 | Mazeret | elle | Mobil duruşma + mazeret talebi | |
| 23 | Tümünü tazele | elle | **Her açık dosya** tek tek (20) | |
| 24 | `enrichOnWeb` | otomatik açık, web, gece değil, günde 1 | **Duruşması 31 gün içindeki her dosya** + en eski okunmamışlar; tam başarı olmazsa 2 saatte bir tekrar (yakın duruşmalılar her seferinde yeniden okunur) | |
| 25 | Portföyden/seçiciden içe alma | elle | Dosyayı bul + 20; **portföy tablosuna yazmaz** | |
| 26–27 | Paylaşılan dosyada / görevde evrak istenmesi | meslektaş ister | Sahibin cihazında evrak indirme; eski kimlikle tam okuma (20) | |
| 28 | Diğer cihazdan gelen senkron | | UYAP'a istek yok; portföy, kayıtlar, işaretler alınır | Yerel okumayı azaltabilir ya da tetikleyebilir |

**Hiç istek atmayan sayfalar:** müvekkiller, portföy listesi (açılışta), masaüstü ana sayfa, ayarlar
(yalnız düğmeler).

### Sorulan dört soru

1. **Bildirim evrak listesini yeniler mi?** Doğrudan değil. Ama (a) portföyde olmayan dosyayı bildiren
   "Vekil Kaydı" tam portföy okuması başlatır, o da o dosyayı ve **okunmamış bütün dosyaları** okur;
   (b) bildirimden dosyayı açmak 18'i çalıştırır.
2. **Duruşma listesi yakın duruşmalı dosyaların evrakını tetikler mi?** Evet, üç yoldan: duruşma
   satırından oluşan dosya "okunmamış" sayılıp tam okunur; `_fill` duruşması 31 gün içindekileri önce
   okur; `enrichOnWeb` bunları her gün (hata olursa 2 saatte bir) yeniden okur. Ayrıca ajandayı açmak
   doğrudan `_fill` başlatır.
3. **Müvekkil isimleri portföyle mi geliyor?** Evet: web portföyünde her sayfada tarafı bilinmeyen her
   açık dosya için ayrı taraf isteği; mobilde oturum kimlikleriyle taraf isteği. Müvekkil listesi,
   avukatın kendi seçtiği temsil ya da taraf kayıtlarındaki vekil adı ile kurulur.
4. **Portföye dosya nereden eklenir?** Web listesi, mobil listesi, iki kanalın duruşma listesi,
   paylaşılan dosyalar, görevler, diğer cihazlar. Bildirimler ve UETS dosya eklemez. Seçiciden içe alma
   **portföy tablosuna yazmaz** (müvekkillerde görünür, portföyde görünmez).

## 3. Kim neyi yazar

| Veri | Yazanlar | Kural |
|---|---|---|
| Portföy: durum | web/mobil listeleri, `syncCase`, diğer cihaz | Boş cevap yok sayılır; eksik cevap tam olanı değiştirmez; yeni olan kazanır |
| Portföy: künye (`details`) | listeler, duruşmalar, `syncCase`, diğer cihaz | **Anahtar anahtar birleşir** (1fc52fd); `birimId` artık silinmez |
| Portföy: kimlikler | listeler, duruşmalar | Birleşir; "değişti" sayılmaz |
| Dosya kaydı — web okuması | 20 | Künye ve **taraflar tamamen değişir** (UYAP tarafları gizlerse boş liste yazılır); evrak değişir (gizlenmediyse); para/hesap gelmezse eskisi kalır |
| Dosya kaydı — mobil okuması | 20 | Web künyesi korunur; taraflar ve evrak **yalnız eklenir** (1fc52fd); para korunur |
| Dosya kaydı — diğer cihaz | 28 | Daha yeni okuma bütün olarak kazanır; para/icra/taraf/künye karşıda boşsa buradaki kalır |
| Taraf tablosu (`case_party`) | portföy, okumalar, tebligat paketleri | Bütün liste değişir; kaynak sırası uyap > taraflar > paket; **aynı sıradakiler birbirini ezer** (web ve mobil ikisi de "uyap") |
| Duruşmalar | web, mobil, diğer cihaz, UETS | Alan alan; yalnız tam web cevabı penceresinde olmayanı siler; mobil hiç silmez |
| Bildirimler | okumalar, diğer cihaz | Eklenir, boş alan doldurulur |

## 4. Portföyün sessizce eksik kalabileceği yerler

- **Mobil, mahkeme başına en çok 20 × 100 dosya** okur ve eksik olduğunu bildirmez.
- Mobil Yargıtay ve savcılık listelemez; yalnız mobil bağlıyken portföy yine "tam" sayılır.
- Mobil bağlıyken web mahkeme dosyalarını okumaz; mahkeme dosyaları tamamen mobil listeye kalır.
- Web: liste başına 40 × 500 (aşılırsa "eksik" sayılır). Yargıtay daire listesi tek istek.
- Savcılık: 30 günlük tam taramalar arasında yalnız bilinen savcılıklar sorulur.
- **Kapanan dosya fark edilmez** ("kapalıları da indir" kapalıyken): açık listeden düşer, "Açık" kalır,
  her okumada yeniden "okunmamış" sayılır. Hiçbir şey dosya silmez.
- **İlk okuma yarım kalırsa** "hiç okunmadı" sayılır; her bağlantıda (2 saat sonra) tam okuma + dosya
  dosya okuma yeniden başlar.
- Bildirimler: mobilde çalışma başına 2 sayfa (eskiler kaçabilir); web son 30 gün.
- Hatalar çoğu yerde yutulur (taraf istekleri ilk 3 hatadan sonra kaydedilmez).

## 5. Bu bilgisayardaki gerçek durum (14 Ekim, veritabanı ve günlükten)

- Web portföyü 12 Ekim 19:24'te **eksiksiz** okundu: 563 dosya (543 mahkeme, 15 Yargıtay, 3 savcılık,
  2 Danıştay). Hepsinin web kimliği var; **yalnız mobilin bulduğu dosya: 0**.
- 553 dosyanın tarafları var (portföy okumasından).
- Web ile tek tek okunan: 115 dosya (para/hesap bunlarda). Toplam okunan: 154.
- Tek tek web okuması 12 Ekim'de 98. dosyada, 13 Ekim'de iki kez 2. dosyada "bağlantı kapandı" diye
  durdu. `banaozel` ölçümüne göre web oturumu ~2 sa 55 dk yaşar; **durma sebebi oturum süresi değil**,
  araştırılmalı (paralel istek, eski `dosyaId`, `.ajx` katmanının düşmesi).
- 13 Ekim 22:52'de mobil bağlanınca, otomatik okuma kapalıyken, okunmamış dosyalar mobil ile (parasız)
  tek tek okunmaya başladı.
- Para silinmedi: yeniden okunan kayıtların hepsinde para ve hesap duruyor.

## 6. Doğrulanamayanlar

- Editör penceresinde diğer cihaz senkronunun çalışıp çalışmadığı.
- Telefon arka plan görevinin başlattığı portföy okumasının gerçekten sürüp sürmediği.
- UYAP'ın Yargıtay daire, web duruşma ve bildirim listelerini sayfalayıp sayfalamadığı.

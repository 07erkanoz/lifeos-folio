# Otomatik UYAP okuması: kendi cihazlardan yalnız biri okusun (16 Ekim 2026)

**Durum:** uygulandı (dal `claude/kind-lehmann-7487c9`, `main`'e henüz alınmadı). Kararlar §6'da,
ne yapıldığı §7'de.

Kapsam: "UYAP verilerini kendiliğinden al" (`PortalSync.autoFetch`, Ayarlar › Bağlantılar,
`lib/ui/settings/uyap_auto.dart`) iki bilgisayarda da açıkken UYAP'a iki kez gidilmesi. Uzun işler
(kurulum, web tamamlaması, eksik bilgiler) bunun dışında; onlar için
[uyap-is-sahipligi.md](uyap-is-sahipligi.md) yapıldı.

Kısıtlar:
- **UYAP'tan nasıl okunduğu değişmez.** Değişen yalnız, kendiliğinden okumanın *hangi cihazda*
  başladığı.
- Avukatın bastığı düğmeler (Portföyü yenile, Yenile, dosya açmak) her cihazda bugünkü gibi
  çalışır.
- Ayrı ağlarda tam koruma yok; kullanıcı bunu kabul etti (iş sahipliği, karar 1).

Satır numaraları bu dalın (`claude/kind-lehmann-7487c9`, `64f9519`) `portal_sync.dart`'ına
göredir.

## 1. Bugün kendiliğinden ne okunuyor

Hepsi `autoFetch` açıkken. Kapalıyken hiçbiri çalışmaz.

| Tetik | Yer | Okunan |
|---|---|---|
| 5 dk'lık zamanlayıcı (gece değil) | `portal_sync.dart:179-187` | bildirimler (saatte bir) + `_readDue` |
| Ayarı açmak | `setAutoFetch`, `:322-331` | bildirimler + `_readDue` |
| `_readDue` | `:335-366` | mobil: duruşmalar (günde bir), portföy (haftada bir) (`syncMobile()`); web: aynısı (`syncWeb()`); web: günlük zenginleştirme partisi (`enrichOnWeb`, `:2249`) |
| Kanal bağlanınca | `_connected`, `:494-497` | o kanalın `syncWeb()`/`syncMobile()`'ı + bildirimler |
| Telefon öne gelince | `home_page.dart:955` | bildirimler |
| Vekil Kaydı bildirimi | `:1867-1878` | portföy, yalnız o cihaz bildirimi okuduysa |

Telefonun arka plan bildirim denetimi (`background_notices.dart:153`) telefona özgüdür; kapsam
dışı.

## 2. Bugün iki cihaz arasında zaten olan

1. **Son okuma zamanları gidiyor.** `uyap` parçası okunan veriyle birlikte zamanları da taşır
   (`uyap_own_sync.dart:44-54`):
   - `portfolio_at`, `portfolio_web_only_at`;
   - `hearings_at:<kanal>`, `notices_at`;
   - `web_enriched_at`, …

   Aynı ağdaki ikinci cihaz bu yüzden çoğu zaman "vakti gelmedi" der ve okumaz. Bildirimler ayrıca
   `_askedLately` ile bakar (`:1752-1760`).
2. **Telefon bilgisayara bırakır.**
   - `deferToComputer` (`own_sync.dart:131-139`): ağda UYAP Mobil oturumu olan, kendiliğinden
     okuyan bir bilgisayar varsa telefon kendiliğinden okumaz.
   - Bunu bilmek için `oturumlar` parçası her cihazdan şunları taşır (`own_sync.dart:153-181`):
     - açık oturumlar (`acik`);
     - telefon mu (`telefon`);
     - "kendiliğinden okuyup okuduğunu veriyor mu" (`oto` = `autoFetch` ve `uyap` parçası açık).
   - Bilgisayarlar arasında böyle bir bırakma yok. Hatta `enrichOnWeb` açıkça bırakmıyor
     (`:2252-2253`: "öbürünün yalnız UYAP Mobil'i olabilir").

## 3. Açık kalan çift okuma

1. **İkisi aynı anda vakitliyse.** Zaman, okuma *bittikten* sonra gider. Okuma sürerken
   öbürünün 5 dakikalık zamanlayıcısı gelirse ikisi de okur. Bunun olasılığı okumanın süresiyle
   artar:
   - pazartesi sabahı ikisi de açılınca haftalık portföy (mobil 150–400 istek, 5–10 dk);
   - günlük web zenginleştirme partisi (10–14 dk; `web_enriched_at` parti bitince yazılır).
2. **Bağlanınca.** `_connected`'daki `sync()` vakit denetimiyle aynıdır; 1'deki gibi çakışabilir.
3. **Uzun iş sürerken.** A uzun işi UYAP Mobil'de çalıştırırken B o kanalda günlük okumaları
   yapar. Aynı ağdalarsa jeton da paylaşılmış olabilir (`keepMobileAlike`).
4. **Ayrı ağlar:** önlenemez (kabul).

## 4. Öneri: kanal başına tek "otomatik okuyan" bilgisayar

Yeni kayıt yok. Bilgiler zaten `oturumlar` parçasında; ağda kimin olduğu mDNS ile anlık biliniyor
(`ownOnline`).

**Kural** (her cihaz kendisi için, kanal kanal):
- Aday: ağda görünen (`ownOnline`), telefon olmayan, `oto` diyen ve o kanalın oturumu açık olan
  kendi cihazlar, artı bu cihaz (o kanal burada bağlıysa).
- Sıra:
  1. O kanalda **uzun işi şu an çalıştıran** önce gelir. Bunun için `oturumlar`'a bir alan
     eklenir: süren işin kanalı (`surenIs`). İş başlayınca ve bitince `ownChanged` çağrılır.
  2. Sonra sabit bir sıra: büro cihaz kimliği küçük olan. Keyfi ama her cihazda aynı ve değişmez.
- İlk gelen bu cihaz değilse, bu cihaz o kanalda **kendiliğinden** okumaz. Öbürünün okudukları
  `uyap` parçasıyla gelir.
- Bu cihazda `uyap` parçası kapalıysa hiç bırakmaz: öbürünün okuduğunu alamaz.

**Nerede uygulanır** (yalnız kendiliğinden yollar; okuma kodu değişmez):
- `_readDue` (`:335-366`):
  - mobil kanal öbüründeyse `syncMobile()` atlanır;
  - web öbüründeyse `syncWeb()` ve `enrichOnWeb()` atlanır.
- `_connected`'ın `autoFetch` dalı (`:494-497`): bağlanan kanal öbüründeyse `sync()` atlanır.
- Bildirimler (zamanlayıcı, ayarı açmak, bağlanmak, telefon öne gelince):
  - burada bağlı **her** kanal öbüründe okunuyorsa atlanır;
  - biri burada kalıyorsa bugünkü gibi okunur.
  - Bildirimler hafif ve zaten zamana bakıyor: kanal kanal bölmek okuma kodunu değiştirirdi.
- Vekil Kaydı'nın portföy okuması bildirimi okuyan cihazda kalır; bildirim okunmayınca o da yok.
- Avukatın düğmeleri ve telefonun `deferToComputer`'ı aynen kalır.

**Kanca:** `PortalSync.autoElsewhere` (statik, `deferToComputer` gibi; Senkron koyar):
`bool Function(PortalChannel)`.

**Ekran:** Ayarlar › Bağlantılar'daki "UYAP verilerini kendiliğinden al" satırının altına,
yalnız bırakılmış bir kanal varken bir satır:

> *Şu an kendiliğinden okumayı Ofis bilgisayarı yapıyor (UYAP Mobil); bu bilgisayar onun
> okuduklarını alır.*

UYAP durumu'na da aynı satır (soru 4).

**Sınırlar (dürüstçe):**
- Karar, ağda görünmeye ve `oturumlar`'ın son haberine dayanır.
- Öbürü uykuya geçip ağdan düşünce, bu cihaz bir sonraki 5 dakikada okumaya başlar.
- Ayar değişince ya da iş başlayınca birkaç saniyelik bir arada iki cihaz farklı düşünebilir;
  en kötü sonuç bir okumanın iki kez yapılması, yani bugünkü durum.

## 5. Testler (onaydan sonra)

- `PortalSync`: `autoElsewhere` kancasıyla:
  - `_readDue` ve `_connected` bırakılan kanalda okumaz, öbür kanalda okur;
  - bildirimler yalnız bütün kanallar bırakılınca atlanır;
  - avukatın düğmeleri bırakılmaz.
- `OwnSync`'in kuralı, saf bir işlev olarak (adaylar → kazanan):
  - telefon aday olmaz;
  - `oto` demeyen aday olmaz;
  - o kanalın oturumu olmayan aday olmaz;
  - uzun işi çalıştıran önce gelir;
  - eşitlikte her iki cihazda aynı kazanan çıkar;
  - `uyap` parçası kapalıyken bırakılmaz.
- Ayarlar satırının metni (ekran testi).

## 6. Kararlar (kullanıcı, 16 Ekim 2026)

1. **Kim okusun:** kendiliğinden seçilsin. Önce o kanalda uzun işi çalıştıran, yoksa sabit sıra.
   Yeni ayar yok.
2. **Kanal başına.**
3. **Bildirimler:** yalnız buradaki bütün kanallar öbüründe okunuyorsa bırakılır.
4. **Ekranda:** yalnız Ayarlar satırında, bırakılmışken.
5. **UETS:** şimdilik dışarıda.

Kullanıcının sorusu: "Bu kadar karışık işlemleri bir avukat nasıl yapacak?" Cevap: hiçbirini
yapmaz. Seçim kendiliğinden yapılır. Ekranda görünen tek şey Ayarlar'daki bir satırdır; uzun işte
de tek bir "Bu bilgisayarda devral" düğmesi vardır.

## 7. Uygulama (16 Ekim 2026)

- **Kural:** `autoReaderElsewhere` (`lib/services/sync/auto_reader.dart`): adaylar → kazanan;
  saf işlev, ağdan bağımsız.
- **`PortalSync`** (`portal_sync.dart`):
  - kanca `autoReader` (statik; yapıcıda testler için verilebilir), `autoReaderOf(kanal)`;
  - `_readDue` mobil ve web dalları ile `enrichOnWeb`;
  - `_connected`'ın `autoFetch` dalı (`sync()` ve bildirimler);
  - `syncNotices(auto: true)` (`_noticesElsewhere`): zamanlayıcı, ayarı açmak, telefon öne gelince;
  - süren iş kanalı `jobRunningHere`; iş başlayınca ve bitince `jobRunsChanged`;
  - ekranlar için `autoReadersChanged`;
  - yalnız test için `readDueForTesting`.
  - Okuma kodu değişmedi; avukatın düğmeleri (`full`/`force` yolları) bırakılmaz.
- **Senkron** (`own_sync.dart`):
  - `oturumlar` parçası süren işin kanalını taşır (`is`);
  - `PortalSync.autoReader` ağdaki kendi cihazlardan kuralı kurar: cihaz adı `OfficePeer.device`;
    telefon, `oto` ve oturum bilgisi parçadan;
  - iş başlayınca ya da bitince `ownChanged`;
  - cihaz gelip gidince ekran yeniden sorar.
- **Ekran:** Ayarlar › Bağlantılar (`uyap_auto.dart`): bırakılmış kanal varken
  *"Şu an kendiliğinden okumayı … yapıyor (UYAP Mobil); bu bilgisayar onun okuduklarını alır."*
- **Testler:**
  - `test/auto_reader_test.dart`: 4 kural testi ve Ayarlar satırı.
  - `test/first_fill_test.dart`, "reading of itself, left to another own computer" (4):
    - vakti gelen okuma bırakılan kanalda yapılmaz, bırakılmayınca yapılır;
    - bağlanınca bırakılan kanal okunmaz, burada tek kanal oysa bildirimler de okunmaz (ve
      bırakılmayınca ikisi de okunur);
    - burada bırakılmayan bir kanal varken bildirimler okunur;
    - avukatın istediği bırakılmaz.
- **Bütün takım:** 1767 geçti, 27 başarısız. Hepsi önceden bilinen kırık ya da zamana bağlı
  testler. Bu turda ilk kez düşen `uyap_budget_test` yük altında 30 sn sınırına takıldı; tek
  başına geçiyor.
- **Yapılmayanlar:** iki gerçek bilgisayarla ve canlı UYAP ile denenmedi. Kuralı uçtan uca
  (`oturumlar` iki gerçek `OfficeNetwork` arasında) sınayan test yok; parça statik
  `PortalSync.started`'a bağlı.

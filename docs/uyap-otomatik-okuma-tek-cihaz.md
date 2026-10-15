# Otomatik UYAP okuması: kendi cihazlardan yalnız biri okusun (öneri, 16 Ekim 2026)

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

## 6. Kullanıcıya sorular

1. **Kim okusun?** Öneri: kendiliğinden seçilsin. Önce o kanalda uzun işi çalıştıran, yoksa sabit
   bir sıra. İsterseniz bunun yerine Ayarlar'da "Kendiliğinden okumayı bu bilgisayar yapsın"
   seçeneği olur. Daha açık, ama bir ayar daha.
2. **Kanal başına mı, cihaz başına mı?** Öneri: kanal başına. Ofiste yalnız UYAP Mobil, evde
   UYAP Web bağlıysa ikisi de kendi kanalını okur, hiçbir şey eksik kalmaz. Cihaz başına olursa
   daha basit olur, ama bir kanal hiç okunmayabilir.
3. **Bildirimler:** öneri, yalnız buradaki bütün kanallar öbüründe okunuyorsa atlansın. Bir
   kanal burada kalıyorsa bildirimler burada da okunur: hafif, ve zaten saatte bir.
4. **Ekranda gösterilsin mi?** Öneri: yalnız Ayarlar satırında, bırakılmışken. UYAP durumu'nda
   da isterseniz eklenir.
5. **UETS (tebligat):** oturum geri gelince her cihaz UETS'yi de okuyor (`_uetsChanged`,
   `:1293-1298`). Bu UYAP değil. Aynı kurala bağlansın mı, yoksa şimdilik dışarıda mı kalsın?

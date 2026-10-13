# UYAP hedef haritası (öneri, 14 Ekim 2026)

Bu belge **olması gerekeni** anlatır. Bugünkü durum: [uyap-senkron-haritasi.md](uyap-senkron-haritasi.md).
Kanal bilgileri `banaozel`in ölçümlü belgelerinden (`MobilUYAP.md`, `uyapweb.md`,
`output/celse-denetimi-2026-09-13/RAPOR.md`) ve Folio'nun kanal tablosundan
(`lib/services/portal/portal_channel.dart`) alındı. Onaylanınca kod bu belgeye göre değişir; belgede
olmayan hiçbir tetikleme kalmaz.

## 1. İki kanal neyi verir

| Bilgi | UYAP Web portalı | UYAP Mobil API |
|---|---|---|
| Portföy: mahkeme dosyaları (istinaf dahil) | ✅ birim türü başına liste, 500'lük sayfa, **toplam sayı verir** | ✅ birim → mahkeme → dosya, 100'lük sayfa; mahkeme şart |
| Portföy: **Yargıtay** | ✅ daire daire | ❌ **14 Ekim 2026 denendi**: `yargibirimleri/{3,4,5,7,8,9,10,14}` boş; Yargıtay birimi hiçbir kodda yok; uygulama paketinde Yargıtay yolu yok |
| Portföy: istinaf (BAM) daireleri | ✅ | ✅ zaten kapsamda: BAM ceza (7702) tür **0**'da, BAM hukuk (7703, 7710) tür **1**'de (14 Ekim 2026 ölçüldü) |
| Portföy: **Tazminat Komisyonu** | ❓ web hiç sormuyor (kodu bulunmalı) | ✅ **tür 26** (7100). 14 Ekim 2026: 1 dosya (2025/5984) — **portföyde yoktu, ne web getirmişti ne mobil soruyordu** |
| Portföy: satış memurluğu, arabuluculuk | ✅ (11, 13) | ✅ tür 11 (9791), tür 25 (6701, 6702); bu avukatta dosya yok |
| Tür 12 ve 13 (mobil) | — | **Sorulmaz**: 13, 1'in alt kümesi (Manavgat 1. Asliye Hukuk: tür 1 → 20 dosya, tür 13 → aynı 20'nin 3'ü); 12, 0'daki BAM ceza dairelerini verir. Sormak aynı dosyaları ikinci kez sormaktır |
| Portföy: **Cumhuriyet Başsavcılığı** | ✅ il → savcılık → dosya | ✅ **14 Ekim 2026 canlı denendi**: `POST mobile/avukat/illerigetir {}` (81 il, `illerList`), `POST mobile/avukat/cbsbirimler {ilKodu}` (`birimListesi`: `birimAdi`, `birimId`), `POST mobile/avukat/cbsdosya` gövde `RequestFileList` + `mahkeme` = `birimTuru2` = savcılık `birimId`, `birimTuru3` = `"3"` → Manavgat'ta web'le aynı 3 dosya. `birimTuru*` boşken 0 dosya döner |
| Portföy: Danıştay | ✅ | ✅ |
| Kapalı dosyalar | ✅ ayrı tarama | ✅ ayrı tarama |
| Künye (dava türü, açılış, ilgili dosyalar, keşif/ön inceleme, karar) | ✅ ayrıntılı | ⚠ yalnız tür, durum, açılış/kapanış |
| Taraflar | ✅ tam ad, rol, **vekil** | ⚠ ad, rol; **vekil %17 dolu**, soyadı/TC yok |
| Evrak listesi | ✅ | ✅ (bağlı dosyaların evrakı da gelir; `son20Evrak` yedeği) |
| Evrak içeriği (indirme) | ✅ | ✅ |
| **Tahsilat / reddiyat / harç (para)** | ✅ | ❌ **14 Ekim 2026 denendi**: icra dosyasının `dosya/{id}/1` cevabında yalnız `son20Evrak`, `tumEvraklar`; para/tahsilat/harç/hesap/borç adlı alan yok |
| **İcra hesabı (alacak kalemleri)** | ✅ | ❌ |
| **İcra borçluları** | ✅ | ❌ |
| Safahat (işlem geçmişi) | ✅ dosya başına ücretli/sayılı; ücretsiz yol birim+tarih, hesap başına süre sınırlı | ❌ |
| Borçlu mal varlığı sorguları | ✅ dosya başına günde 5 ücretsiz + 60 dk sınırı | ❌ |
| Duruşmalar | ✅ geniş pencere | ✅ en çok 31 günlük pencere; satırda taraf listesi de var |
| Bildirimler | ✅ son 30 gün | ✅ sayfalı |
| Mazeret, e-duruşma talebi | ❌ | ✅ (yazar) |
| Evrak gönderme | ✅ (yazar) | ❌ |
| Oturum | **~2 sa 55 dk, uzatılamaz** (yoklama uzatmaz); paralel istek oturumu düşürür | erişim kodu **~55 dk** (`expires_in` 3300 sn), yenileme koduyla yenilenir; yenileme kodunun süresi uzamaz (giriş ~7 gün geçerli) |
| Dosya kimliği (`dosyaId`) | her cevapta değişir, saklanmaz | oturumluk, saklanmaz |

Sonuç: **Mobil hızlı ve uzun ömürlü ama eksik; web eksiksiz ama oturumu kısa ve tek tek.** Mobil
portföyün (mahkeme, Danıştay ve savcılık dosyaları) ve günlük takibin (duruşma, bildirim, evrak
listesi) omurgasıdır; web zenginleştirir (para, icra hesabı, borçlular, vekiller, ayrıntılı künye) ve
mobilin göremediği **Yargıtay** dosyalarını ekler.

## 2. Beş kural

1. **Bağlanmak hiçbir şey okumaz.** Okumayı yalnız şunlar başlatır: (a) ilk kurulumun portföy listesi
   (bir kez), (b) kullanıcının açtığı tek dosya, (c) kullanıcının bastığı bir düğme, (d) otomatik okuma
   açıksa zamanlayıcı. Ekranlar (ajanda, tebligat, bildirim, portföy) yalnız kayıtlı veriyi gösterir.
2. **İki kanal birbirini ezmez.** Her bilginin bir sahibi vardır (§3). Sahip olmayan kanal yalnız boş
   alanı doldurur ya da yeni kayıt ekler; hiçbir şeyi silmez, azaltmaz.
3. **Liste ile dosya okuma ayrıdır.** Portföy listesi okumak hiçbir dosyanın ayrıntısını okumaz
   (taraf, evrak, para dahil). Dosya ayrıntısı ayrı bir işin, kuyruğun işidir.
4. **Her iş kendi kanalında kalır.** Web için ayrılan iş (para, hesap, borçlu, Yargıtay) web yoksa
   bekler; mobile geçip "tamamlandı" sayılmaz. Kullanıcının başlattığı bir iş seçtiği kanalda kalır:
   mobil kurulum web bağlansa da mobilde sürer; web tamamlaması web düşerse durur.
5. **Her okuma ölçülür ve kaldığı yerden devam eder.** Bölüm bölüm işaretlenir; başarılı bölüm tekrar
   okunmaz; eksik kalan liste "eksik" olarak görünür.

## 3. Bilgi sahipliği

| Bilgi | Sahibi (yazar, günceller) | Diğer kanal |
|---|---|---|
| Dosya kimliği (mahkeme + esas, folded) | ikisi de; eşleşme anahtarı | — |
| Durum (açık/kapalı) | listede gören kanal; **yalnız açık↔kapalı değişince** güncellenir; web'in ayrıntılı durum metni korunur | aynı kural |
| Web adresi (`birimId`, web birim kodları) | web | mobil kendi kodlarını ayrı alanlarda tutar |
| Ayrıntılı künye | web | mobil boş alanı doldurur |
| Taraflar ve vekiller | web | mobil yeni taraf ekler, boş alan doldurur; vekili/tam adı silemez |
| Evrak listesi | ikisi (anahtar: `birimEvrakNo`, yoksa ya da "0" ise `evrakId`) | yalnız ekler; listede görünmeyeni silmez |
| Para, icra hesabı, borçlular | **yalnız web**; üçü ayrı bölüm, biri hata verirse diğerleri silinmez | **dokunamaz** |
| Duruşmalar | ikisi; eşleşme dosya + birim + dakika | yalnız tam web penceresi kendi penceresindekini silebilir |
| Bildirimler | ikisi | eklenir, boş alan doldurulur |
| Yerel: indirilen dosyalar, okundu, notlar, temsil seçimi | kullanıcı/cihaz | UYAP cevabı dokunamaz |

"Boş" üçe ayrılır ve ayrı saklanır: **okundu ve boş**, **bu dosya türünde yok/izin yok**, **alınamadı**.
Yalnız ilk ikisi "tamamlandı" sayılır.

## 4. İşler

| İş | Kanal | Ne okur | Kaç istek |
|---|---|---|---|
| **L1 Mahkeme, Danıştay ve savcılık portföy listesi** | mobil; mobil yoksa web | mahkeme dosyaları (mobilde yargı türleri **1, 0, 2, 6, 26, 11, 25**; 12 ve 13 tekrar olduğu için sorulmaz) + Danıştay + savcılık dosyaları (bilinen savcılıklar; 30 günde bir 81 il) (yalnız açık; kapalılar yalnız kullanıcı Dava Dosyalarım'da isteyince ayrı tarama). Taraf yok (ilk kurulum hariç, §6). | mobil ~150–400 (birim/mahkeme/sayfa) + savcılıklar, web ~60 + sayfalar |
| **L2 Web'e özgü liste** | web | **yalnız** Yargıtay daireleri (mobil yokken mahkemeler ve savcılıklar L1'in web yoludur; L2 bunları ikinci kez taramaz) | onlarca |
| **D Duruşmalar** | ikisi | −30/+90 gün | web 5, mobil 4–5 |
| **B Bildirimler** | ikisi | yeni bildirimler; metni olmayanların metni | birkaç + en çok 25 |
| **Z Dosya zenginleştirme** (bölüm bölüm) | bölümün sahibi | künye, taraflar, evrak listesi (ikisi) / para, hesap, borçlular (web) | dosya başına web 6–9, mobil 2–3 |
| **E Evrak indirme** | ikisi | seçilen evrak | evrak başına 1 |
| **T Tebligat (UETS)** | UETS | tebligat ve paketler; **UYAP'a taraf sormaz** (taraf yoksa Z kuyruğuna ekler) | — |

## 5. Tetikleyici → izin verilen iş

`O` = otomatik okuma. "Kuyruğa ekler" = Z kuyruğuna öncelikli iş koyar, okumaz.

| Tetikleyici | O kapalı | O açık |
|---|---|---|
| Uygulama açılışı, oturum geri alma, başka cihazdan oturum | **hiçbir şey**; yalnız kullanıcının daha önce başlattığı ve kullanıcının durdurmadığı iş (kurulum, web tamamlaması) kendi kanalı bağlıysa kaldığı yerden sürer | aynı + süresi gelen D (günde 1), B (saatte 1), L1/L2 (haftada 1) |
| Elle giriş (web ya da mobil) | portföy **hiç okunmadıysa** ilk kurulum (§6); yoksa **hiçbir şey** | aynı + süresi gelenler |
| Ajanda / tebligat / bildirim / portföy sayfasını açmak | **hiçbir şey** (kayıtlı veri gösterilir) | hiçbir şey (zamanlayıcı zaten çalışır) |
| Dosya sayfasını açmak | **yalnız o dosya**, eksik ya da 24 saatten eski bölümleri, sahibi bağlıysa; en çok 3 dk'da bir | aynı |
| "UYAP'tan tazele" (dosya) | o dosyanın bütün bölümleri | aynı |
| "Portföyü yenile" | L1 + L2 (en çok 3 saatte bir); **dosya okumaz** | aynı |
| "Duruşmaları / bildirimleri yenile" | D / B | aynı |
| "Eksik bilgileri tamamla" (yeni düğme) | Z kuyruğundan **bir parti** | aynı |
| Yeni dosya bildiren "Vekil Kaydı" bildirimi | portföy listesine eklenmesi için **uyarı** gösterir; okumaz | L1/L2 yalnız ilgili birim için; dosya Z kuyruğuna |
| Duruşma listesinde yeni dosya | dosya portföye "duruşmadan gelen" olarak eklenir; **okunmaz** | Z kuyruğuna |
| Zamanlayıcı (5 dk) | **çalışmaz** | B saatte 1; D günde 1; L haftada 1; Z: günde en çok bir parti, gece yok |
| Telefon arka plan görevi | çalışmaz | yalnız B; **asla L/Z** |
| Diğer cihazdan veri | UYAP'a sormaz; yalnız gelen kayıtta **açıkça işaretli** bölüm sonuçlarını alır (verinin varlığından kanal tahmini yapılmaz) | aynı |
| Paylaşılan dosya / görev evrakı | yalnız istenen evrak (E); kimlik bilinmiyorsa yalnız dosyayı bulma + evrak listesi, **tam okuma değil** | aynı |
| Editör penceresi | hiçbir şey; yalnız kullanıcının istediği tek dosya/evrak | aynı |

## 6. İlk kurulum

Kararlar (14 Ekim 2026): mobil **önerilir** (zorunlu değil); evrak listeleri kurulumda gelir; web
tamamlamasını **kullanıcı başlatır**.

0. Karşılama: *"Dosyalarınızı UYAP'tan getirelim. UYAP Mobil ile başlamanızı öneririz: dosya listeniz
   ve müvekkilleriniz birkaç dakikada gelir. UYAP Web daha sonra Yargıtay dosyalarını ekler; tahsilat,
   reddiyat, icra hesabı ve borçlu bilgilerini tamamlar."* Seçenekler: **UYAP Mobil ile başla**
   (önerilen) · UYAP Web ile başla · Şimdilik geç.
1. **Portföy listesi** (mobil L1, 150–400 istek, ~5–10 dk): tür 1, 0, 2, 6, 26, 11, 25 + Danıştay +
   savcılıklar; yalnız açık dosyalar. İlerleme: "Mahkemeler 34/145 · 412 dosya bulundu". Ardından **D**.
2. **Taraflar / müvekkiller** (mobil `taraflar`, dosya başına 1 istek, listedeki `dosyaId` ile).
3. **Evrak listeleri** (mobil `dosya/{id}/1`, dosya başına 1 istek); sıra: duruşması yakın → açık icra →
   diğerleri. Taraf bölümü tamamlanan dosyada taraflar **tekrar okunmaz**.
   Süre (istekler arası ort. 1,5 sn + ağ): **563 dosya ~35–40 dk, 1000 dosya ~1 sa.**
   1–3 tek bir **Kurulum işi**dir (§11.3): kullanıcı başlattığı için O kapalıyken de çalışır; uygulama
   bu sırada kullanılabilir, liste geldikçe görünür; kesilirse kaldığı yerden sürer. Kurulum, dosya
   okumak için bugünkü tam `refresh()`i **kullanmaz**; kanalı sabit, bölüm seçen okuyucuyu kullanır.
4. Kurulum bitince: *"563 dosya ve 210 müvekkil geldi. Para, icra hesabı, borçlular ve Yargıtay
   dosyaları için UYAP Web ile tamamlayın."* **[UYAP Web ile tamamla]**: L2 (Yargıtay) + web Z
   (para, hesap, borçlular, vekiller, künye; evrak listesi mobilden **tam** geldiyse atlanır);
   ~10 sn/dosya (563 → ~1,5 sa, 1000 → ~3 sa). Web oturumu ~2 sa 55 dk olduğundan **oturumlar arası
   devam normal yoldur**: oturum kapanınca durur, sonraki web girişinde kaldığı yerden sürer.
5. Yalnız web ile başlayan: web 1–3'ü yapar (L1'in web yolu + L2 Yargıtay), sonra aynı tamamlama.
   Tazminat komisyonunun web kodu bulunana kadar bu birim "web'de taranmadı" diye **görünür** kalır.

**Müvekkil isimleri:** ilk kurulumda açık dosyaların tarafları listeyle birlikte okunur (yukarıda 2).
Kurulumdaki taraf ve evrak okumaları ilgili bölümleri Z'de "tamamlandı (mobil)" işaretler; web
tamamlaması yalnız web'in sahip olduğu bölümleri ve vekil bilgisini ekler.
Mobil taraflarda vekil alanı yalnız vekili olan tarafta doludur (ölçüm: 486 tarafın 83'ü); avukatın
müvekkillerinde vekil avukatın kendisidir, tespit bununla yapılır. Bulunamayanlar web
zenginleştirmesinde (vekilli tam taraf listesi) düzelir. Sonradan portföye giren dosyanın tarafları
da Z'nin ilk bölümü olarak okunur.

## 7. Zenginleştirme kuyruğu (Z)

- İş anahtarı: **dosya + bölüm + kanal** (künye, taraflar, evrak listesi, para, hesap, borçlular;
  "mobil taraflar alındı" ile "web vekilleri tamamlandı" ayrı satırdır). Her satırda sonuç türü
  (§11.2), kapsam (tam / kısmi, ör. yalnız `son20Evrak`), son başarı, son deneme, sonraki deneme,
  deneme sayısı. Bölüm verisi ile başarı işareti **aynı yazmada** kalıcılaşır.
- Bölüm kanalı sabittir: para/hesap/borçlular web; diğerleri web varsa web, yoksa mobil (mobil sonucu
  web bölümünü "tamamlandı" saymaz).
- Sıra: kullanıcının açtığı dosya → duruşması 31 gün içinde olanlar → açık icra dosyaları → diğer açık
  dosyalar → eski bilgilerin yenilenmesi (yaşlanan iş öne geçer). Kapalı dosyalar kuyruğa yalnız
  kullanıcı isteyince girer.
- **Sınır dosya sayısında değil, hızdadır.** Tek istek, toplu işte istekler arası 1–2 sn (mevcut
  `UyapPace` arka plan hızı; kullanıcı başlatsa da toplu iş bu hızda), hata olunca artan bekleme. İlk
  web zenginleştirmesinde dosya başına ~7 istek (dosyayı bulma, izinler, künye, taraflar, para, hesap,
  borçlular; evrak listesi mobilden tam geldiyse atlanır) → dosya başına ~10 sn; 1000 dosya ~3 saat
  yalnız bekleme, yani **iki web oturumu**.
- **Kullanıcının başlattığı "Eksik bilgileri tamamla":** dosya ya da gün sınırı yok; oturum kapanana,
  hata sınırına ya da kullanıcı durdurana kadar sürer; sonra kaldığı yerden devam eder.
- **Otomatik mod (O açık):** yalnız eskiyen bilgileri tazeler; günde en çok 200 dosya, gece yok. İlk
  doldurmayı otomatik mod yapmaz.
- Elle tek dosya (dosyayı açmak, "UYAP'tan tazele") hiçbir sınıra sayılmaz.
- Oturum kapanınca kuyruk **duraklar**; tamamlanan bölümler kayıtlıdır; mobile geçilmez.
- Hata: oturum bitti → dur, giriş iste. 429 → bekle. Ağ/5xx → artan bekleme, partide en çok 1 tekrar.
  Dosyaya özgü hata → 7/30/90 gün sonra tekrar. "İzin yok/desteklenmiyor" → açıklamalı sonuç, tekrar yok.
- İlerleme: *"Web bilgileri 153/563 dosyada tamamlandı · bu partide 24/50 · 7 dosya kısmen."*

## 8. Portföyün eksiksiz olduğuna güvenmek

- Her liste sonunda **beklenen toplam ile gelen sayı** karşılaştırılır (web `[kayıtlar, TOPLAM]`).
  Sayfa sınırına takılan liste (mobil 20 sayfa, web 40 sayfa) **"eksik"** işaretlenir ve ekranda görünür.
- Liste "tam" sayılması için bütün birimlerin hatasız gelmesi gerekir; hata veren birim adıyla gösterilir.
- **Çapraz kontrol:** iki kanal bağlıyken haftada bir, mobil listedeki mahkeme dosyaları ile web
  listesindekiler sayıca karşılaştırılır (web yalnız toplam sayıyı sorar, ayrıntı okumaz); fark varsa
  kullanıcıya gösterilir.
- **Kapanan dosya:** yalnız **aynı kapsamın eksiksiz** açık taraması (aynı kanal, aynı birim, hatasız,
  sayfa sınırına takılmamış) dosyayı göstermezse "kapandı olabilir" işaretlenir; kısmi liste,
  Yargıtay kapsamı ya da duruşmadan eklenmiş kayıt için yokluk kapanma sayılmaz. Doğrulama: dosya
  açılınca ya da kullanıcının Dava Dosyalarım'da başlattığı kapalı taramasında. "Kapandı olabilir"
  dosyalar Z'ye otomatik girmez. Dosyalar asla sessizce silinmez. Kanal/birim başına `lastSeen` ve
  son tam tarama tutulur.
- Portföy kaynağı her dosyada görünür: web listesi / mobil listesi / duruşmadan / paylaşılan / görev.

## 9. Bugünkü tetikleyicilerin yeni karşılığı

Numaralar [uyap-senkron-haritasi.md](uyap-senkron-haritasi.md) §2'deki satırlar.

| Bugün | Yeni |
|---|---|
| 3/4 bağlantı → `syncWeb`/`syncMobile` | §5 ilk satırlar; O kapalıysa hiçbir şey |
| 6 ekranlardaki giriş çağrıları | **kaldırılır**; ilk kurulum dışında bir şey çağırmaz |
| 12 ajanda açılışı → senkron | **kaldırılır** |
| 13/14 `syncWeb`/`syncMobile` sonundaki `_fill`, `_fillOnly` | **kaldırılır**; dosya okuma yalnız Z kuyruğu ve tek dosya |
| 13 portföy sırasında sayfa başına taraf isteği (`_partiesOf`) | **kaldırılır**; taraflar Z'de |
| 16 bildirimdeki "Vekil Kaydı" → tam portföy | O kapalı: uyarı; açık: ilgili birim |
| 17 UETS'nin UYAP'a taraf sorması | **kaldırılır**; Z kuyruğuna eklenir |
| 18 dosya açılışında 30 dk kuralı | eksik/24 saatten eski bölümler, 3 dk bekleme |
| 21 ajandadaki duruşma senkronu | o dosyanın tek dosya okuması (kayda da yazar) |
| 23 "Tümünü tazele" | "Eksik bilgileri tamamla" partisi |
| 24 `enrichOnWeb` | O açıksa günde bir Z partisi |
| 25 seçiciden içe alma | portföy tablosuna da yazar |
| bildirim sayfası açılışı (`uyap_notices_page.dart:73`) | açılış çağrısı kaldırılır; "Yenile" → B |
| tebligat sayfası açılışı (`uets_page.dart:184`) | açılış çağrısı kaldırılır; "Yenile" → T |
| ajandada duruşma yenileme (`agenda_page.dart:1580`) | yalnız D |
| kanal çubuğunun ortak senkron düğmesi (`channel_bar.dart:345`) | "Portföyü yenile" (L1+L2) + D + B; dosya okumaz |
| portföy yenileme / boş portföyden içe alma (`portfolio_page.dart:204`, `uyap_cases_page.dart:149`) | L1/L2; ayrıntı yalnız seçilen dosyalara |
| ana sayfa, masaüstü, ayarlardaki elle çağrılar (`home_page.dart:2832`, `desktop_home.dart:840`, `settings_page.dart:633`) | düğmenin adındaki iş; giriş sonrası çağrı değildir |
| otomatik ayarı açma, zamanlayıcı, öne gelme (`portal_sync.dart:308`, `:169`, `home_page.dart:944`) | §5 vade ve kapsam kuralları |
| telefon arka plan bildirimi (`background_notices.dart:153`) | yalnız B; L/Z asla |
| başka cihazın kayıt aktarımı (`uyap_own_sync.dart:168`) | yalnız açık bölüm sonuçları (§11.4) |
| paylaşılan / görev evrakı indirme (`shared_cases.dart:343`, `task_package.dart:103`, `uyap_case_panel_controller.dart:828`) | E: kimlik çözme + evrak listesi; tam `refresh()` değil |
| kalıcı `portfolio_closed` ayarı (`portal_sync.dart:2011`, `:1548`, `:1930`) | **kaldırılır**; kapalı tarama yalnız kullanıcının başlattığı ayrı iş |

## 10. Karar bekleyenler

1. ~~Mobil savcılık uç noktaları denensin mi?~~ Denendi, çalışıyor (§1). Savcılık listesi mobilde;
   web'e yalnız Yargıtay ve zenginleştirme kalır.
2. ~~Taraflar ilk kurulumda mı?~~ **Evet**, açık dosyaların tarafları listeyle birlikte (§6).
3. ~~Parti sınırları?~~ **Dosya sınırı yok, hız sınırı var**; kullanıcının başlattığı tamamlama
   sınırsız ve devam ettirilebilir; otomatik mod günde en çok 200 dosya (§7).
4. ~~Kapalı dosyalar?~~ **Yalnız kullanıcı Dava Dosyalarım'da isterse**; otomatik hiçbir yerde yok.
5. ~~Kurulum ekranı?~~ Maket onaylandı (14 Ekim 2026).

## 11. Codex denetimi (14 Ekim 2026) — uygulamaya geçmeden kesinleşenler

Codex (gpt-6.1-sol) planı koda karşı denetledi; aşağıdakiler planın parçasıdır.

**11.1 Tek birleştirme sözleşmesi.** §3'teki sahiplik bütün yazma yollarında uygulanır: portföy satırı
(`PortalCase.merge`), taraf tablosu (`case_party`), dosya kaydı (`UyapCaseStore`), cihazlar arası
aktarım. Bugünkü açıklar:
- `case_party` web ve mobil için aynı `source: 'uyap'` ile yazılıyor, eşit önceliktekiler silinip
  yeniden yazılıyor → mobil taraf okuması web vekilini siler. Kaynak `uyap_web` / `uyap_mobil` ayrılır;
  mobil web satırını silemez, yalnız ekler ve boş alanı doldurur.
- `UyapCaseStore` web okumasında taraf ve evrak listesini bütünüyle değiştiriyor → birleşir (§3).
- İcra: hesap ve borçlular ayrı bölümdür; biri alınamazsa eskisi korunur (bugün boş borçlu listesi
  eski hesabın yerine geçebiliyor).
- Mobil ve web'in ortak `yargiTuru/yargiBirimi` alanları: web adresi web'indir; mobil kendi kodunu
  ayrı anahtarda tutar.

**11.2 Sonuç türleri.** Her bölüm okuması dört sonuçtan birini üretir: `okundu` (tam ya da kısmi
kapsamla), `boş` (okundu ve gerçekten boş), `yok` (izin yok / bu türde desteklenmiyor),
`alınamadı`. Beklenen alanı olmayan cevap (bugün mobil `_list` boş liste, `caseDocuments` `{}` dönüyor)
`alınamadı`dır, `boş` değil. Yalnız `son20Evrak` gelen evrak listesi **kısmi**dir; tam sayılmaz, web
evrak bölümü atlanmaz. Geçici izin kaybı süresiz "yok" sayılmaz.

**11.3 Kullanıcı işi.** Kurulum ve web tamamlaması kalıcı bir iş kaydıdır: kanal, aşama, kapsam,
ilerleme, durma nedeni (`oturum düştü`, `kullanıcı durdurdu`, `kullanıcı bağlantıyı kesti`,
`uygulama kapandı`). Yeniden bağlanmak **yeni okuma başlatmaz**; yalnız durma nedeni "kullanıcı
durdurdu" olmayan işi kendi kanalında sürdürür. Devam işareti dosya sıra numarası değil, liste için
birim/sayfa kapsamı, dosyalar için bölüm sonuçlarıdır; yeni oturumda kimlikler yeniden çözülür.
Kullanıcı durdurunca bekleyen istek iptal edilir; eski oturumdan dönen cevap işi ilerletmez. Web'in
bütün oturum kayıpları (GET hata yolu dahil) tek ortak hata türüne çevrilir.

**11.4 Cihazlar arası.** Aktarılan kayıt bölüm sonuçlarını (kanal + tarih + kapsam) taşır; alan cihaz
yalnız bunları kabul eder, para/icra varlığından "web'de okundu" çıkarmaz. Aynı kullanıcının iki
cihazı aynı uzun işi aynı anda çalıştırmaz: işi başlatan cihaz iş kaydına kendini yazar, diğeri
yalnız ilerlemeyi gösterir.
*Uygulandı (14 Ekim 2026):* bölüm sonuçları dosya kaydıyla birlikte `bolumler` olarak gider; kayıt
içeriği değişmeden yalnız bölüm sonucu değişirse henüz gitmez (özet, kayıt zamanına bakıyor).

**11.5 Kimlik.** Dosya eşleşmesi `caseKey` (folded mahkeme + esas) üzerindedir; kanalların mahkeme
adı farklıysa alias tablosu tutulur, kayıt dosyası anahtarı aynı normalizasyonu kullanır. Evrak
anahtarı: kaynak dosya + `birimEvrakNo`; numarasızsa içerik alanları (bugünkü kod gibi);
oturumluk `evrakId` anahtar olmaz.

**11.6 Savcılık.** Mobil savcılık yalnız listeleme değildir: kimlik çözme (`MobileCaseFinder`),
kanal tablosundaki taraf/evrak/indirme yetenekleri ayrı doğrulanır; doğrulanana kadar savcılık
dosyasının ayrıntısı web bölümüdür.

**11.7 Mobil oturum.** `auth/refresh` hız kuyruğundan geçer; 429 alınca token silinmez, beklenir.

**11.8 Uygulama sırası.**
1. Bölüm + kanal sonuç kaydı ve ezmeyen birleştirme (11.1, 11.2).
2. Kanalı sabit, bölüm seçen okuyucu; kurulum ve E yollarını tam `refresh()`ten ayırmak (11.3).
3. Tetikleyicileri §5/§9'a göre ayrıştırmak; `_fill` ve ekran çağrılarını kaldırmak.
4. Kullanıcı işi (kurulum, web tamamlaması) ve kurulum ekranı.
5. Mobil türler 26/11/25, mobil savcılık (11.6), kapalı tarama ayrı iş.
6. Kesinti, iki kanal, iki cihaz, kısmi evrak, hesap/borçlu hata senaryolarının testleri.

# UYAP işinin sahipliği: iki kendi cihaz aynı uzun işi aynı anda çalıştırmasın (öneri, 16 Ekim 2026)

Kapsam: [uyap-hedef-harita.md](uyap-hedef-harita.md) §11.4 ("işi başlatan cihaz iş kaydına kendini
yazar, diğeri yalnız ilerlemeyi gösterir") ve §12'de ertelenen "sahiplik ve paylaşılan ilerleme".
Senkron tarafı: [senkron-plan.md](senkron-plan.md). **UYAP'tan nasıl okunduğu değişmez**: aynı
`_jobSteps`, aynı `_jobCases`, aynı istekler ve aynı hız. Değişen yalnız *hangi cihazın* işi
çalıştırdığı.

Satır numaraları:
- `portal_sync.dart`, `uyap_job.dart`, `uyap_setup_dialog.dart` ve `uyap_status_dialog.dart` için
  numaralar, ana çalışma kopyasındaki **henüz commit edilmemiş** "Eksik bilgileri tamamla" işine
  (`UyapJobKind.fill`, hedef harita §13) göredir.
- Diğer dosyalar `main` `2b17c69`'a göredir.

## 1. İncelemede çıkan, tasarımı belirleyen bulgular

1. **Kendi cihaz eşitlemesi yalnız aynı yerel ağda çalışır.**
   - Bulma mDNS ile (`office_network.dart:3186-3192`).
   - Sunucu yok, internet yok (`docs/buro.md:9`, `:144`).
   - Ofis ile ev bilgisayarı ayrı ağlardayken birbirinden **hiç haber alamaz**: ne iş kaydı ne
     nabız.
   - Haber yalnız iki yoldan gider:
     - iki cihaz aynı ağda (ör. dizüstü ofise getirilince);
     - ikisini de gören üçüncü bir cihaz (telefon) kaydı taşır (A→B→C yayılımı, senkron-plan §0
       adım 3).
   - **Sonuç: ayrı ağlardaki iki cihazın aynı anda okumasını hiçbir tasarım kesin olarak
     önleyemez.**
   - Tasarımın verebileceği:
     - aynı ağdayken kesin önlemek;
     - ayrıyken, bilinen son durumu dürüstçe göstermek;
     - kendiliğinden hiçbir şey başlatmamak;
     - karşılaşınca hemen tek sahibe düşmek.
2. **Bugün iş kaydı cihazdan çıkmıyor.**
   - `uyap_job` yalnız yerel meta (`portal_sync.dart:506`, `:513-523`).
   - Ev bilgisayarı ofisteki işi bilmez.
   - İki kopya yalnız iki yoldan olur:
     - avukat her iki cihazda ayrı ayrı başlatırsa;
     - eski yerel kayıt, bağlanınca kendiliğinden sürerse (`_connected`, `:470-481`).
3. **Okunan dosyalar zaten gidiyor.**
   - Bölüm sonuçları kayıtla birlikte gider (`uyap_own_sync.dart:386`).
   - Yalnız "tamam" olanlar gider (`portal_database.dart:1785-1796`).
   - Alan cihaz daha yenisini alır (`adoptSections`, `:1801`).
   - `_jobWants` her dosyadan hemen önce bölümleri yeniden sayar (`portal_sync.dart:899`, `:919`).
   - Sonuç: devralan cihaz, eşitleme gelmişse okunmuşu tekrar okumaz.
   - Başarısız denemeler gitmez: devralan cihaz onları kendi 3 denemesiyle yeniden dener.
   - **Ama:** `uyap` parçası kapatılabilir (`own_sync.dart:335`). Kapalıysa devralan cihaz okunmuşu
     bilmez ve yeniden okur.
4. **İş sürerken eşitleme pek tetiklenmiyor.**
   - `_keepRead` `uyapChanged`'i çağırmıyor (`portal_sync.dart:2338-2393`).
   - Bu yüzden iş sürerken okunanlar diğer cihaza ancak bir sonraki eşitleme turunda gider. Turlar:
     - keşif, en çok 30 sn'de bir (`office_network.dart:1069-1073`);
     - başka bir değişiklik.
   - `ownChanged` 3 sn'lik geciktirmeyle her değişiklikte yeniden kurulur (`:864-867`).
   - Her tur bütün parçaları gönderir; ajanda bütün dökümüyle gider (senkron-plan §1). **Nabız bu
     tura bağlanmamalı.**
5. **Hafif soru kanalı var.**
   - `askOwn(deviceId, kind, body)` (`office_network.dart:796-834`) tek mesaj gönderir, tek cevap
     alır.
   - Karşı tarafta `ownAnswers[kind]` karşılar (örnek: `oturum-ver`, `own_sync.dart:175`).
   - Nabız ve devir bununla gider; bütün eşitleme turu gerekmez.
6. **Her zaman açık parça kalıbı var.**
   - Örnekler: `not-takibi`, `oneriler`, `paylasimlar` (`own_sync.dart:76-85`, `:519`, `:580`).
   - Yetenek tablosu: `SyncCaps.matrix` (`sync_caps.dart:65-92`).
   - Karar cihazı (senkron-plan R6) aynı sorunun benzerini çözmüş:
     - nesil;
     - eşit nesilde cihaz kimliği;
     - kayıp cihazda devir.
   - Burada da aynı kalıp kullanılır, daha basit hâliyle.
7. **Telefon uzun işi zaten çalıştırmaz.**
   - Telefon UYAP'ı bilgisayara bırakır (`deferToComputer`, `own_sync.dart:126-134`).
   - Arka planda L/Z yapmaz (hedef harita §5).
   - Ama kaydı taşıyabilir (bulgu 1).

## 2. Öneri

### 2.1 İş kaydı paylaşılır, sahibiyle

`UyapJob` (`uyap_job.dart`) şu alanları kazanır. Hepsi `encode`/`decode` içinde; eski kayıt
okunabilir.

| Alan | JSON | Anlamı |
|---|---|---|
| `id` | `kimlik` | işin kimliği: başlatan cihaz + başlama anı |
| `owner`, `ownerName` | `sahip`, `sahipAdi` | çalıştıran cihazın kimliği (`OfficeIdentity.deviceId`) ve görünen adı ("Ofis bilgisayarı") |
| `generation` | `nesil` | her devirde bir artar |
| `beat` | `nabiz` | sahibin son "çalışıyorum" anı (UTC); yalnız iş koşarken ilerler |
| `progress` | `ilerleme` | `{asama, bitti, toplam}`; bugün yalnız bellekte (`jobProgress`, `:500`), artık kayıtta da |
| `version` | `surum` | HLC (`lib/services/sync/hlc.dart`); birleştirmede sıra |

Kurallar:
- **Kişi başına tek iş yuvası**, bugün cihaz başına olduğu gibi (soru 2).
- Kayıt yine `uyap_job` metasında durur. Diğer cihazın işi de buraya yazılır, sahibi başka cihaz
  olarak.
- **Göç:** sahibi olmayan eski kayıt, ilk açılışta bu cihazın, 1. nesil sayılır (`_loadJob`, `:513`).
  İki cihazda ayrı eski kayıt varsa karşılaşınca 2.3'teki kural uygulanır.

### 2.2 Nabız ve gidişi

- İş bu cihazda koşarken (`_jobRun != null`, `:668`), 60 sn'de bir yalnız kayıt güncellenir:
  - `nabiz` ve `ilerleme` yazılır;
  - UYAP'a hiçbir şey sorulmaz.
- Kayıt, ağdaki her kendi cihaza `askOwn(…, 'uyap-is', body: kayıt)` ile gider (hafif, bulgu 5).
- Aşama değişince, durunca, bitince ya da devredilince de hemen gider.
- Cevap karşı tarafın kaydıdır. Böylece sahip, kendisinden sonra devralındığını hemen öğrenir.
- Ayrıca **`uyap-is` kendi cihaz parçası** (her zaman açık, `not-takibi` gibi): kayıt her eşitleme
  turunda da gider.
  - Telefonla taşınma (bulgu 1) ve sonradan açılan cihaz bu yoldan öğrenir.
  - Yetenek: `isSahipligi` (`hlc` ister).
- Alan cihaz kaydı birleştirir ve **duyduğu anı kendi saatiyle** ayrıca tutar (yerel, gönderilmez).
  "Son haber" bu ikisinden yenisidir; sahibin saati ileri ya da geri olsa da doğru görünür.

### 2.3 Birleştirme (iki kayıt karşılaşınca)

1. Daha yüksek `nesil` kazanır.
2. Eşit nesilde iki farklı iş varsa (ikisi de ayrı başlatılmış), **sonra başlatılan** kazanır: o,
   avukatın son isteğidir. Eşitlikte cihaz kimliği kazanır: her cihazda aynı sonuç.
3. Aynı iş, aynı nesil: `surum` (HLC) yenisi kazanır. Bunu yalnız sahip yazar: ilerleme, aşama,
   durma, bitme.
4. "Bırakıldı" (`dropJob`) bir kayıt olarak kalır, silinmez. Sürümüyle gider; eski kayıt onu
   diriltmez.

### 2.4 Sahip olmayan cihaz ne yapar

- **Hiçbir şeyi kendiliğinden başlatmaz ya da sürdürmez.**
  - Bağlanınca sürdürme (`_connected`, `:473-481`) yalnız `owner == ben` ise çalışır.
  - Uygulama açılışı da aynı.
- `_jobSteps` (`:674`) en başta ve `current()` (`:680`) her adımda sahipliği de denetler.
  - Gelen kayıt sahipliği aldıysa birleştirme `_jobGen++` yapar (duraklatmadaki gibi, `:617`).
  - Koşan okuma bir sonraki adımında durur ve bir şey yazmaz. O an okunan dosyanın sonucu bugünkü
    duraklatma kuralıyla aynı: yazılmaz.
- `startSetup`/`startWebCompletion`/`startFill` (`:528-592`) ve `resumeJob` (`:623`): başka
  cihazın işi biliniyor ve bitmemişse çalışmaz, nedenini döner. Ekran bunu gösterir (2.5).
- **Devralma** (`takeOverJob`):
  - yalnız avukatın açık isteğiyle;
  - `nesil + 1`, sahip ben;
  - kayıt hemen eski sahibe gider (ağdaysa); eski sahip ilk adımında durur.
  - Sonra iş, `_jobCases`'in bugünkü kuralıyla kalan bölümlerden sürer.
  - Fill işinin sabit dosya listesi (`cases`, `dosyalar`) kayıtla gittiği için aynı dosyalar
    okunur.
- **Duraklat** ve **Bırak** (soru 4): sahip ağdaysa ona istek olarak gider; değilse yalnız
  "Devral" ve "Bu cihazda bırak" (yerel kopyayı unut).

### 2.5 "Uzun süre ses yok"

- **Taze:** son haber 3 dk'dan yeni. Sahip büyük olasılıkla şimdi okuyor.
- **Sessiz:** daha eski. Sahip kapalı, uykuda ya da **başka ağda çalışıyor** olabilir. Bulgu 1
  yüzünden bu ikisi ayırt edilemez.
- Öneri: sessizlik **kendiliğinden devir değildir**. Sessizlik yalnız devralmayı kolaylaştırır:
  - Taze iken "Bu cihazda sürdür": uyarılı onay. *"Ofis bilgisayarı bu işi şu an okuyor. İki
    cihaz aynı anda okursa UYAP oturumu düşebilir. Bu cihaza alınırsa ofis bilgisayarı durur."*
  - Sessizken tek tık, bilgi satırıyla: *"Ofis bilgisayarından 3 saattir haber yok; kapalı ya da
    başka bir ağda olabilir. Başka bir ağda çalışıyorsa iki cihaz aynı anda okur; aynı ağa
    gelince biri durur."*
- Kendiliğinden devrin bir istisnası düşünülebilir (soru 3): sahip **aynı ağda görünüyor**
  (`isOnline`) ve "oturumum yok, bekliyorum" diyor (`stopped: session`). Bu cihazın o kanalı
  bağlıysa iş burada sürer. Bu, kesin bilgiye dayanan tek durumdur.

### 2.6 Ekranlar

- **Kurulum penceresi**, `_running` (`uyap_setup_dialog.dart:306`):
  - Sahip başka cihazsa üstte bir satır: *"Ofis bilgisayarında sürüyor · son haber 1 dk önce"*.
  - Aşama satırları kaydın `ilerleme`'sinden: "212 / 333".
  - Kalan süre gösterilmez.
  - Düğmeler: Duraklat/Sürdür yerine "Bu cihazda sürdür" (2.5'teki onayla); sahip ağdaysa
    "Duraklat".
  - Bitmiş iş (`:139-172`): *"Ofis bilgisayarında tamamlandı"*; "Tamam" bu cihazdaki kopyayı
    kapatır.
- **UYAP durumu**:
  - "Süren iş" başlığı ve `_jobLine` (`uyap_status_dialog.dart:302-316`, `:364-386`): cihaz adı ve
    son haber eklenir. Örnek: *"Ofis bilgisayarı · UYAP Mobil · evrak listeleri 212/333 · son
    haber 1 dk önce"*.
  - Tamamlama düğmeleri (`fillRuns`, `:168`, `:240-262`): başka cihazın işi tazeyken gizlenir.
    Sessizken görünür; basınca 2.5'teki onay sorulur.
  - Sayılar bu cihazın verisidir. Eşitleme gecikmişse ofisin okuduklarını henüz göstermez; bir
    satır bunu söyler.
- **Maket:** metinler yukarıda. Görsel maket ya da ekran görüntüsü turu, onay verilirse
  uygulamadan önce yapılır.

### 2.7 Bu tasarımın kapsamadıkları (ayrı iş)

- **Otomatik okuma (O) iki cihazda da açıksa** ikisi de günlük işleri yapar:
  - `_readDue` (`portal_sync.dart:329-360`): duruşma, haftalık liste, günlük `enrichOnWeb`
    partisi.
  - Bu "uzun iş" değildir, ama aynı çift istek riskini taşır.
  - Aynı sahiplikle tek cihaza bağlanabilir. Telefon için zaten var (`deferToComputer`).
- **UYAP Mobil jetonu ağda paylaşılıyor** (`oturumlar` parçası, `keepMobileAlike`,
  `portal_sync.dart:262-272`). İki cihaz aynı ağda aynı oturumla okuyabilir. Sahiplik uzun işi
  önler; tek dosya açmayı önlemez.
- **İki ayrı UYAP Web girişinin** birbirini düşürüp düşürmediği ölçülmedi (soru 5).

## 3. Uygulama sırası (onaydan sonra)

Ön koşul: ana çalışma kopyasındaki fill işi ve UYAP durumu commit edilmiş olmalı. Bu iş onların
üstüne kurulur.

1. **Saf kurallar.**
   - `UyapJob` alanları; `UyapJobOwnership`: birleştirme, taze/sessiz, kim çalıştırabilir.
   - Hepsi `uyap_job.dart` içinde, ağdan bağımsız.
   - Test: `test/uyap_job_owner_test.dart`.
2. **`PortalSync`.**
   - Sahiplik denetimleri: `_connected`, `_startJob`, `resumeJob`, `_jobSteps.current()`.
   - Nabız zamanlayıcı, `takeOverJob`, `mergeJob`.
   - Ağa dokunmaz; kancalar bugünkü gibi statik: `deferToComputer`/`uyapChanged` gibi
     `jobSelf`/`jobChanged`.
3. **`OwnSync`.**
   - `uyap-is` parçası ve `ownAnswers['uyap-is']`; `SyncCaps.isSahipligi`.
   - Sahibin ağa girip çıkması: `_net` dinleyicisi.
4. **Ekranlar:** 2.6.
5. **Testler.**
   - `test/first_fill_test.dart`'ın iş grubuna (`:520`) iki `PortalSync` ile senaryolar:
     - B, A'nın işini bağlanınca sürdürmez;
     - B başlatamaz, nedenini görür;
     - devir A'yı ilk adımında durdurur, yazdırmaz;
     - ayrıyken iki nesil karşılaşınca tek sahip;
     - eşit nesilde sonra başlatan kazanır, her iki sırada aynı;
     - bırakılan diriltilmez;
     - göç;
     - eski sürüm eşe gitmez.
   - Ağ katmanıyla A–B: `test/sync_step9_test.dart`'taki kurulum gibi.
   - Ekran testleri: kurulum penceresi ve UYAP durumu, başka cihazın işi taze ve sessizken.
6. `docs/uyap-hedef-harita.md` §11.4 ve §12'ye "uygulandı" notu.

## 4. Kullanıcıya sorular

1. **Ayrı ağlar** (bulgu 1). Ofis ile ev ayrı ağdayken çift okumayı kesin önlemenin yolu yok. Öneri:
   - aynı ağdayken kesin önle;
   - ayrıyken son bilinen durumu göster, kendiliğinden başlatma;
   - karşılaşınca tek sahibe düş.

   Bu yeterli mi? Ofis ile ev bilgisayarı arada hiç aynı ağa geliyor mu, ya da telefonunuz Folio'yla
   ikisini de görüyor mu?
2. **Yuva.** Kişi başına tek iş mi (önerilen; bugün cihaz başına tek), kanal başına tek iş mi? Kanal
   başına olursa ofiste UYAP Mobil, evde UYAP Web tamamlaması aynı anda sürebilir.
3. **Sessiz sahip.** Öneri: sessizlik kendiliğinden devir değil, yalnız devralmayı tek tık yapar.
   - Taze sınırı 3 dk, nabız 60 sn.
   - İstisna seçeneği: sahip aynı ağda görünüyor ve oturumu yok diye bekliyorsa, bağlı cihaz işi
     kendiliğinden sürdürsün mü?
4. **Uzaktan duraklat/bırak.** Sahip aynı ağdayken diğer cihazdan "Duraklat" ve "Bırak" ona
   gitsin mi, yoksa yalnız "Bu cihazda sürdür" (devir) mi olsun?
5. **UYAP Web'de iki giriş.** Aynı hesapla iki cihazdan UYAP Web'e girilince ilki düşüyor mu?
   Düşüyorsa web işinde çift okuma kendiliğinden kısalır. Ölçülmedi.
6. **Otomatik okuma** (2.7). İki cihazda açıksa günlük okumalar da çift gidiyor. Bu da aynı
   sahipliğe bağlansın mı? Ayrı iş olarak önerilir.

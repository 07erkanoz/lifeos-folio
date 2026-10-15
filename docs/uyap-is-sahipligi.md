# UYAP işinin sahipliği: iki kendi cihaz aynı uzun işi aynı anda çalıştırmasın (16 Ekim 2026)

**Durum:** uygulandı (dal `claude/kind-lehmann-7487c9`, `main`'e henüz alınmadı; kullanıcı gözden
geçirecek). Ne yapıldığı ve neyin kalmadığı §3'te.

Kapsam: [uyap-hedef-harita.md](uyap-hedef-harita.md) §11.4 ("işi başlatan cihaz iş kaydına kendini
yazar, diğeri yalnız ilerlemeyi gösterir") ve §12'de ertelenen "sahiplik ve paylaşılan ilerleme".
Senkron tarafı: [senkron-plan.md](senkron-plan.md). **UYAP'tan nasıl okunduğu değişmez**: aynı
`_jobSteps`, aynı `_jobCases`, aynı istekler ve aynı hız. Değişen yalnız *hangi cihazın* işi
çalıştırdığı.

Satır numaraları (§1–§2) öneri yazılırken bakılan sürüme göredir: `portal_sync.dart`,
`uyap_job.dart` ve iki pencere için "Eksik bilgileri tamamla" işinin (hedef harita §13) o günkü
çalışma kopyası, şimdi `main` `71351ed`; diğerleri `main` `2b17c69`. Uygulamadan sonra kaymış
olabilirler; §3 yeni yerleri adıyla verir.

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

`UyapJob` (`uyap_job.dart`) değişmez. Onu saran `UyapJobClaim`
(`lib/services/portal/uyap_job_owner.dart`, **yapıldı**) şu alanları taşır; işin kendisi `is`
altında, `UyapJob.encode` biçimiyle. Sahibi olmayan eski kayıt `UyapJob.decode` ile okunmaya devam
eder (göç, aşağıda).

| Alan | JSON | Anlamı |
|---|---|---|
| `id` | `kimlik` | işin kimliği: başlatan cihaz + başlama anı |
| `owner`, `ownerName` | `sahip`, `sahipAdi` | çalıştıran cihazın kimliği ve görünen adı ("Ofis bilgisayarı"). Kimlik `SyncClock.localDeviceId` (`sync_generation.dart:208`): veritabanına bağlı, büro ağına katılmadan da var ve değişmez. Büro kimliği kullanılmaz: ağa sonradan katılan cihaz kendi kaydını başkasınınki sanırdı |
| `generation` | `nesil` | her devirde bir artar |
| `beat` | `nabiz` | sahibin son "çalışıyorum" anı (UTC); yalnız iş koşarken ilerler |
| `progress` | `ilerleme` | `{asama, bitti, toplam}`; bugün yalnız bellekte (`jobProgress`, `:500`), artık kayıtta da |
| `version` | `surum` | HLC (`lib/services/sync/hlc.dart`); birleştirmede sıra |

Kurallar:
- **Kişi başına tek iş yuvası**, bugün cihaz başına olduğu gibi (karar 2).
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
3. Aynı iş, aynı nesil, iki ayrı sahip (iki cihaz ayrıyken aynı işi devraldı): cihaz kimliği büyük
   olan kazanır, sonradan kim ne derse desin. Sürüme bakılsaydı kaybedenin sonraki nabzı, onun
   için durmuş olanı yeniden sahip yapabilirdi; ikisi de dururdu.
4. Aynı iş, aynı nesil, aynı sahip: `surum` (HLC) yenisi kazanır. Bunu yalnız sahip yazar:
   ilerleme, aşama, durma, bitme.
5. "Bırakıldı" (`dropJob`) bir kayıt olarak kalır, silinmez. Sürümüyle gider; eski kayıt onu
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
- **Uzaktan Duraklat ya da Bırak yok** (karar 4). Sahip olmayan cihazda tek düğme "Bu
  bilgisayarda devral".
- **Meslektaşlar etkilenmez.** Kayıt yalnız aynı kişinin cihazlarına gider:
  - nabız `ownOnline`'a gider (aynı kullanıcı kimliği, `office_network.dart:853-860`);
  - soru `askOwn` ile, yalnız kanıtlanmış kendi cihaz kanalında (`ch.vouched`, `:812`);
  - parça yalnız `ownParts`'ta.
  - Aynı büro ağında her avukat kendi UYAP'ıyla bağımsız çalışır: birinin işi ötekinin işini
    ne görür ne durdurur.

### 2.5 "Uzun süre ses yok"

- **Taze:** son haber 3 dk'dan yeni. Sahip büyük olasılıkla şimdi okuyor.
- **Sessiz:** daha eski. Sahip kapalı, uykuda ya da **başka ağda çalışıyor** olabilir. Bulgu 1
  yüzünden bu ikisi ayırt edilemez.
- Öneri: sessizlik **kendiliğinden devir değildir**. Sessizlik yalnız devralmayı kolaylaştırır:
  - Taze iken "Bu bilgisayarda devral": uyarılı onay. *"Ofis bilgisayarı bu işi şu an okuyor. İki
    cihaz aynı anda okursa UYAP oturumu düşebilir. Bu cihaza alınırsa ofis bilgisayarı durur."*
  - Sessizken tek tık, bilgi satırıyla: *"Ofis bilgisayarından 3 saattir haber yok; kapalı ya da
    başka bir ağda olabilir. Başka bir ağda çalışıyorsa iki cihaz aynı anda okur; aynı ağa
    gelince biri durur."*
- Kendiliğinden devir hiçbir durumda yok. Sahip aynı ağda oturumunu bekliyor olsa da devir avukatın
  düğmesiyle olur: daha basit ve öngörülebilir.

### 2.6 Ekranlar

- **Kurulum penceresi**, `_running` (`uyap_setup_dialog.dart:306`):
  - Sahip başka cihazsa üstte bir satır: *"Ofis bilgisayarında sürüyor · son haber 1 dk önce"*.
  - Aşama satırları kaydın `ilerleme`'sinden: "212 / 333".
  - Kalan süre gösterilmez.
  - Düğmeler: Duraklat/Sürdür yerine yalnız "Bu bilgisayarda devral" (2.5'teki onayla).
  - Bitmiş iş (`:139-172`): *"Ofis bilgisayarında tamamlandı"*; "Tamam" bu cihazdaki kopyayı
    kapatır.
- **UYAP durumu**:
  - "Süren iş" başlığı ve `_jobLine` (`uyap_status_dialog.dart:302-316`, `:364-386`): cihaz adı ve
    son haber eklenir. Örnek: *"Ofis bilgisayarı · UYAP Mobil · evrak listeleri 212/333 · son
    haber 1 dk önce"*.
  - Tamamlama düğmeleri (`fillRuns`): bugünkü kuralla, iş durmamışsa gizli. Bu, başka cihazın
    işi için de geçerli; sessizken de. O zaman yol "Süren iş" altındaki "Ayrıntı ya da bu
    bilgisayarda devral"dır. Yeni bir iş başlatmak yerine işi devralmak, aynı dosya listesini
    sürdürür.
  - Sayılar bu cihazın verisidir. Eşitleme gecikmişse ofisin okuduklarını henüz göstermez; bir
    satır bunu söyler.
- **Maket:** yapılmadı; metinler yukarıda ve testlerde.

### 2.7 Bu tasarımın kapsamadıkları (ayrı iş)

- **Otomatik okuma (O) iki cihazda da açıksa** ikisi de günlük işleri yapar:
  - `_readDue` (`portal_sync.dart:329-360`): duruşma, haftalık liste, günlük `enrichOnWeb`
    partisi.
  - Bu "uzun iş" değildir, ama aynı çift istek riskini taşır.
  - Aynı sahiplikle tek cihaza bağlanabilir. Telefon için zaten var (`deferToComputer`).
- **UYAP Mobil jetonu ağda paylaşılıyor** (`oturumlar` parçası, `keepMobileAlike`,
  `portal_sync.dart:262-272`). İki cihaz aynı ağda aynı oturumla okuyabilir. Sahiplik uzun işi
  önler; tek dosya açmayı önlemez.
- **İki ayrı UYAP Web girişinin** birbirini düşürüp düşürmediği ölçülmedi (karar 5).

## 3. Uygulama (16 Ekim 2026)

`main` `71351ed` (tamamlama işi ve UYAP durumu) bu dala alındıktan sonra yapıldı. UYAP'tan okuma
yolları (`_jobCases`, `readSections`, liste okumaları) değişmedi.

1. **Kurallar:** `UyapJobClaim` (`lib/services/portal/uyap_job_owner.dart`).
   - İçerik: başlatma (`start`), devir (`takenOver`), sahibin sözü (`said`), birleştirme
     (`pick`), taze/sessiz (`running`, 3 dk), kim çalıştırabilir (`runsOn`).
   - Ağdan ve `PortalSync`'ten bağımsız; `UyapJob`'a dokunmaz.
2. **`PortalSync`** (`portal_sync.dart`):
   - Kayıt `uyap_job` metasında, sarılı biçimde durur. Sahipsiz eski kayıt açılışta bu cihazın
     sayılır, 1. nesil, "çalışıyor" denmeden (`_loadJob`).
   - Sahibin her sözü tek yoldan geçer (`_sayJob` → `_holdJob`): kayıt yazılır, ekrana verilir,
     ağdaki kendi cihazlara söylenir. `_keepJob`, `_jobSteps.keep`, `dropJob` bunu kullanır.
   - Denetimler (`_jobHere`):
     - `_connected`: yalnız sahibin işi bağlanınca sürer;
     - `pauseJob`, `resumeJob`: sahip olmayanda bir şey yapmaz;
     - `_jobSteps`: başta ve her `current()`'ta denetler;
     - `_startJob`: başka cihazın işi tazeyken başlatmaz, günlüğe yazar;
     - `dropJob`: başka cihazın işini yalnız bitmişse kapatır.
   - `mergeJob(theirs, direct:)`: gelen kaydı `pick` ile alır.
     - Burada koşan iş başkasına geçtiyse `_jobGen++` olur: bir sonraki adımında durur ve yazmaz.
     - `direct` ise sahibin duyulduğu an yerel saatle tutulur (`_heard`).
   - `takeOverJob()`: yalnız avukatın düğmesiyle; kanal bağlı değilse `session` durumunda bekler.
   - Nabız: iş koşarken 60 sn'de bir `_sayJob`; UYAP'a istek yok (`_beatJob`).
   - Ekranlar için: `jobClaim`, `jobElsewhere`, `jobRunningElsewhere()`, `jobLastWord`,
     `jobProgressShown`.
   - Kancalar:
     - `tellJob` ve `deviceName` statik (Senkron koyar); yapıcıda testler için verilebilir.
     - `connectedForTesting` yalnız test için.
3. **Senkron** (`own_sync.dart`, `sync_caps.dart`):
   - `uyap-is` kendi cihaz parçası, her zaman açık.
   - `ownAnswers['uyap-is']` gelen kaydı alır, buradakini döner.
   - `PortalSync.tellJob` kaydı `askOwn` ile ağdaki her kendi cihaza söyler, yalnız
     `isSahipligi` diyene.
   - Cihaz adı `OfficePeer.device`.
   - Yetenek `isSahipligi` (`known`, `active`; parça `{isSahipligi, hlc}` ister): eski sürüm
     Folio'ya gitmez, ondan alınmaz.
4. **Ekranlar:**
   - Kurulum penceresi, başka cihazın işi:
     - ilerleme kayıttan;
     - not: "Bu iş başka bilgisayarınızda sürüyor: … · son haber …" ya da sessizken "kapalı ya da
       başka bir ağda olabilir…";
     - tek düğme "Bu bilgisayarda devral"; tazeyken onay sorulur.
   - UYAP durumu, "Süren iş": cihaz adı ve son haber; düğme "Ayrıntı ya da bu bilgisayarda
     devral"; sayıların bu bilgisayarın bildikleri olduğunu söyleyen satır.
   - "Son haber" iki pencerede 30 sn'de bir yenilenir.
5. **Testler:**
   - `test/uyap_job_owner_test.dart` (9): kurallar.
   - `test/first_fill_test.dart`, "two of the lawyer's own devices" (6):
     - öbürü bağlanınca da Sürdür'de de çalıştırmaz;
     - tazeyken başlatılamaz, devralınınca 2. nesille burada koşar;
     - sessizken kendiliğinden bir şey yok, avukatın başlattığı sonra gelir;
     - koşarken öbüründe devralınan iş bir sonraki adımında durur, gelen tarafları yazmaz;
     - bırakılan öbüründe de bırakılır, eski söz diriltmez;
     - sahipsiz eski kayıt bu cihazın.
   - `test/uyap_job_owner_screens_test.dart` (4): kurulum penceresi taze ve sessiz, UYAP durumu,
     "son haber" metni.
   - Ekran testi ayrı dosyada. Nedeni: `first_fill_test`'teki önceki ekran testi `SyncLog`'un
     yazma zincirini sahte saatinde bırakıyor; sonraki bir UYAP durumu okuması orada hiç bitmiyor.
     Bu, bu işten önce de vardı.
   - Bütün takım (16 Ekim 2026): 26 test başarısız.
     - Hepsi senkron-plan §0'daki "bu işten önce de kırık olan testler" listesinde.
     - Tek istisna `sync_protocol_test`'in A→B→C testi: zamana bağlı; `main`'de de üç denemenin
       birinde düştü.

Yapılmayanlar:
- **Ağ katmanıyla uçtan uca test** (`uyap-is` parçası ve `askOwn` iki gerçek `OfficeNetwork`
  arasında) yok. Parça `PortalSync.started`'ı kullanıyor; bir süreçte iki cihazın iki ayrı
  `PortalSync`'i olamıyor. `PortalSync` tarafı yukarıdaki testlerde kanca yerine doğrudan
  bağlanarak sınandı.
- Bitmiş başka cihaz işinde "Ofis bilgisayarında tamamlandı" yazısı yok; bugünkü bitti metni
  görünür, "Tamam" iki cihazda da kapatır.
- Canlı UYAP ve iki gerçek bilgisayarla denenmedi.

## 4. Kararlar (kullanıcı, 16 Ekim 2026)

1. **Ayrı ağlarda tam koruma yok: kabul.** Ofis ile ev bilgisayarının aynı ağa gelip gelmeyeceği
   bilinemez. Örnek: avukat dizüstüsünü ofise getirir. Ya da aynı büro ağında herkes kendi UYAP'ıyla
   bağlıdır. Aynı ağdayken kesin önlenir; ayrıyken son bilinen durum gösterilir, hiçbir şey
   kendiliğinden başlamaz; karşılaşınca tek sahibe düşülür. Meslektaşların cihazları bu kayda
   karışmaz (2.4).
2. **Kişi başına tek iş:** daha basit ve güvenli.
3. **3 dakikadır haber yoksa çalışmıyor sayılır.** Nabız 60 sn. Kendiliğinden devir yok (2.5).
4. **Uzaktan Duraklat/Bırak yok:** yalnız "Bu bilgisayarda devral".
5. **İki UYAP Web girişi:** kullanıcı emin değil, "düşmesi gerek, UYAP denetliyor olabilir"
   diyor. Ölçülmedi. Tasarım buna dayanmaz: düşerse sahip işi `session` ile durur ve yeniden
   bağlandığında yalnız hâlâ sahipse sürer. İki cihazın birbirini sırayla düşürmesi de böylece
   önlenir.
6. **Otomatik okuma** (2.7): bu işin dışında, ayrı iş olarak önerildi.

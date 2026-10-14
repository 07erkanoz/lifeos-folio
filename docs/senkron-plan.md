# Senkron planı: kendi cihazlar ve büro ağı, birbirini ezmeden (14 Ekim 2026)

Bu belge, kullanıcının kendi cihazları arasındaki eşitlemenin (Senkron) ve büro ağı eşitlemesinin
bugünkü hâlini, ezme risklerini, verilen kararları ve uygulama planını tutar. Başka bir bilgisayardan
(ofisten) bu belgeyle devam edilir. UYAP okuma tarafı ayrı belgededir:
[uyap-hedef-harita.md](uyap-hedef-harita.md).

## 0. Nereden devam edilecek

- UYAP okuma işi (hedef harita §1–§12) bitti ve `main`'de: son commit `9ca3f97`. Ertelenen UYAP
  maddeleri hedef harita §12'de.
- Bu belgedeki senkron işi **henüz başlamadı**.
  - Codex'in ilk denetimi yapıldı (gpt-6.1-sol, salt okunur, 14 Ekim): **REVISE**, 17 bulgu (§7).
  - İkinci denetim (aynı gün): **REVISE**, 14 bulgu (§7).
  - Üçüncü denetim (aynı gün): **REVISE**, 10 bulgu (§7).
  - Dördüncü denetim (aynı gün): **REVISE**, 2 kritik bulgu (§7).
  - Beşinci denetim (aynı gün): **REVISE**, 1 kritik bulgu (§7).
  - Altıncı denetim (aynı gün): **APPROVED** (§7).
  - **§5 adım 1 bitti (14 Ekim):** `lib/services/sync/hlc.dart`, `sync_generation.dart`,
    `sync_caps.dart`, `sync_migration.dart`; testleri `test/sync_protocol_test.dart`.
    - Uygulamada plana eklenenler:
      - **İki adımlı alışveriş:** Senkron (`senkron` → `senkron-ek`) ve büro (`buro-parca` →
        `buro-parca-ek`). Yetenek gerektiren parça, karşı taraf yeteneğini **aynı alışverişte**
        söyledikten sonra gider; eski bilgiye güvenilmez.
      - **Saatin yüksek su işareti:** veritabanı dışındaki dosyada (`senkron-nesil.json`) tutulur.
        Uygulama açıkken alınmış bir yedeğe dönüş de böyle fark edilir.
    - Ertelenenler:
      - Ekranda duran parçanın gösterilmesi (`OfficeNetwork.stoppedParts` hazır) ilk kez bir
        parçanın durabildiği adıma, maketle.
      - Görev paketi, dosya isteği ve soru kanalının biçim sürümleri, o biçimleri değiştiren
        adımlara.
    - Bu adımda hiçbir parçanın biçimi değişmedi (`SyncCaps.active` boş). Yalnız `hlc` ilan ediliyor.
    - Codex denetimi (11 bulgu, REVISE) düzeltildi (`b54eadc`):
      - açılış hataları yutulmuyor, tek açılış;
      - dış dosya atomik yazılıyor, kaybolunca rastgele dönem kimliği;
      - saat için bir dakikalık sınır;
      - yetenek kararı alışverişin kendi mesajından;
      - zaman aşımı, tür doğrulaması ve başarı kaydı;
      - sayaç taşması;
      - eski sürüm Folio'nun iki yönlü testi.
  - **§5 adım 2 (ekran dışı kısmı) bitti:**
    - R11: `ClientRecordKind.financial`. Para yetkisi gönderme, kabul ve dosya isteğinde icra
      defterini de kapsıyor. Yetki kaybında bütün finansal türler temizleniyor.
    - R6 denetimi: büro üyesinin `ters`, `kaynak: mahsup:…` ve `kaynak: icra:…` hareketi yalnız kendi
      kaydına ve aynı müvekkile. Hedefi gelmemiş olan `client_record_pending`'de bekliyor, toplamlara
      girmiyor.
    - R4: UYAP eşleşmesi kaydedilmiyor, her açılışta hesaplanıyor (`ledgerOf(collections:)`).
      Avukatın sözü `resmiKarar`'da. Eski `resmi: elle` okunuyor, eski otomatik anahtar okunmuyor.
    - Ekran (`1cbf25a`): meslektaşın icra kaydında "Yazan: …" rozeti; Düzenle, Sil, Bildirildi,
      İşlendi say ve Geri al yok; "Bu kaydı yalnız … değiştirebilir.".
  - Ara iş (`65516df`): UYAP Mobil oturumu açılışta yalnız UYAP reddederse düşer. Gövdedeki
    `status: 401` yenilenir. Oturum olayları `uyap-senkron.log`'a yazılır.
  - **§5 adım 3 bitti:**
    - **Parçalı aktarım:** `OfficeNetwork._sendPacked` / `_receivePacked`. Yük `pieceSize`'ı
      (512 KB) aşarsa parçalar, alıcı her birini istedikçe (`bolum-iste` → `bolum`) gider; hiçbir
      parça dinlenmeden gelmez.
      - Bölme yalnız karşı taraf `paketBolme`'yi aynı alışverişte söylediyse yapılır.
      - İlk mesaja sığmayan yük ikinci adıma ertelenir (`ertelendi`).
      - Büro parçalarında `veriPaket`.
      - Alıcı bütün parçalar gelince tek seferde uygular; eksik parçada hiçbir şey alınmaz.
      - Onay gelmezse eşitleme başarılı sayılmaz, sonraki turda yeniden denenir.
    - **Yayılım (A→B→C):** `_ownCame` bir şey değiştirdiyse `ownChanged()` tetiklenir; değişiklik
      yoksa tetiklenmez, döngü olmaz.
    - İlan edilenler: `hlc`, `paketBolme`.
    - Test edilmeyen: büro parçalarının parçalı aktarımı (büro üyeliği kurulumu uçtan uca testte,
      adım 8).
  - **§5 adım 4 bitti:**
    - `lib/services/enforcement/ledger_book.dart`:
      - alan grupları (`finans`, `bilgi`, `bildirildi`, `resmiKarar`, `yasam`) ve HLC sürümleri
        (`surumler`);
      - kayda bağlı mahsup listesi (`mahsuplar`);
      - her cihazda aynı **etkin durum** ve "askıda" mahsup;
      - türetilen hareketler (`icra:<id>:emanet`, `icra:<id>:mahsup:<mahsupId>`).
    - Projeksiyon `ledger_projection` tablosunda. `allClientRecords()`, `clientRecords()` ve
      `clientRecord()` onu da döndürür. Elle yazılamaz, gönderilmez, alınmaz. Yalnız yeni biçimdeki
      (sürümlü) kayıt için kurulur.
    - `lib/services/enforcement/ledger_service.dart` (R12): ekleme, düzeltme, bildirildi, işlendi,
      kaldırma/geri koyma, mahsup ekleme/geri alma; her biri tek işlemde, gösterilen sürüm
      denetlenerek (`LedgerConflict`). Mahsup kalandan fazla olamaz (`LedgerOverdrawn`).
    - Düzeltme penceresinde "para nereye gitti" yalnız seçim değiştiyse mahsuplara dokunur;
      karttan yapılmış kısmi mahsup kalır.
    - Kart ve Kasa: icradan doğan emanete "Ters kayıtla düzelt" yok. "Mahsup et" defterin
      mahsup listesine yazar; mahsubun tersi mahsubu geri alır. Ters kayıt artık `kaynak`'ı
      kopyalamaz.
    - Kasa her satırı bir kez tersler: hedefin ilk tersi sayılır, fazlası ve tersin tersi
      sıfır sayılır.
    - Göç (şema 2, `migrateLedgers`): eski hareketlerin net etkisi uyuşuyorsa geçmişe
      (`ledger_history`, `ledger_legacy`) taşınır, uyuşmuyorsa `ledger_repair` raporuna gider.
      `resolveLedgerRepair` rapor özetiyle onaylı onarım yapar.
    - İlan ve etkinleştirme: `defterIslemi`. Eski sürüm cihazla `ajanda` ve `muvekkil-buro`
      parçaları durur.
    - Codex kod denetimi (15 bulgu, §7) işlendi:
      - gelen sürümler yerel saati ilerletir (`SyncClock.observe`);
      - meslektaşın defteri kart ve Kasa'dan değişmez (`LedgerNotYours`), gelen ters ve mahsup
        türetilmiş harekete yazılamaz;
      - göç yeniden çalışınca yeni biçimdeki kaydı atlar; net etki bileşen bileşen karşılaştırılır;
      - onarım onayı rapor özetini (kayıt + eski hareketler + öneri) yeniden hesaplar, değiştiyse
        raporu yeniler ve onarmaz;
      - eski biçimdeki kayıt gelirse projeksiyon kurulmaz, tartılır; eski kimlik eşlemesi
        (`defterEski`) kendi cihazlara ve büroya gider;
      - sürüm denetimi içerik özetiyle (`defterSurum`), mahsup komutları da gösterileni denetler;
      - elle "UYAP'ta var" sözü finansal sürüme bağlı; para değişince düşer;
      - her değişiklik `ledger_history`'ye yazılır; para yetkisi gidince temizlenir;
      - yazım başarısızsa hata; `changed` bildirimi commit'ten sonra;
      - projeksiyonda `client_id` indeksi, göçte eski hareketler önceden indekslenir.
    - Ekranlar (maket onaylı):
      - icra ödeme kartında askıdaki mahsup ve "Mahsubu geri al";
      - Kasa'da onarım raporu şeridi: şimdiki ve onarınca durum, "Onar" düğmesi;
      - Senkron sayfasında eski sürüm cihazla duran parçaların satırı.
  - **§5 adım 5 bitti:**
    - `lib/services/sync/field_versions.dart`: bir satırın alan grupları, her grubun HLC sürümü,
      yalnız değişen gruba yeni sürüm, grup grup birleştirme.
    - Ajanda satırı (`lib/services/portal/portal_agenda_versions.dart`):
      - gruplar `tur`, `baslik`, `govde`, `zaman` (`at`, `all_day`), `tamam`, `bag`
        (`case_key`, `hearing_key`) ve yaşam sürümü `yasam`;
      - silinen satır `agenda_removed`'da son içeriği ve yaşam sürümüyle durur (`silinenler`);
      - başka cihazdaki düzenleme silineni geri getirmez; yalnız `restoreAgenda` ("Geri al")
        daha yeni yaşam sürümüyle getirir, aradaki düzenlemeyle birlikte;
      - silinmiş satır ekranda gösterildiği hâliyle kaydedilince geri gelmez;
      - eşit yaşam sürümünde silme kazanır (eski kural); eski `silinen` işaretleri hâlâ okunur.
    - Süre kararı (`deadline_user`): `tamam`, `gun`, `baslik`, `govde`, `onay`
      (`confirmed_inputs`, `confirmed_at`; gün onunla gider), `kaldir`. İlk kez yazılan karar boş
      karara göre sürümlenir: değiştirmediği alan başka cihazın sözünü ezmez.
    - Temsil (`case_representation.surum`): sonraki sürüm; eşitte her cihazda aynı seçim.
    - Müvekkil kartı:
      - alan sürümleri `alanSurumu`; sürümsüz alan damgasından (`alanZamani`) türetilir, göç
        gerekmez;
      - `saveClient` yalnız avukatın bu kartta değiştirdiğini (`copyWith` damgası kartın zamanı)
        sürümler; ekranda eski kalmış alan, başka cihazdan geleni ezmez;
      - yeni kartın sürümleri kendi zamanından türetilir;
      - `CaseNote` ve `CaseLink` kendi `surum`'unu taşır.
    - Gelen her sürüm saate işlenir (R2).
    - İlan ve etkinleştirme: `alanSurumu`, `silmeOmru`. Eski sürüm cihazla ajanda parçası durur.
    - Testler: `test/sync_step5_test.dart` (A, B, C üç cihaz).
    - Ekran değişikliği yok.
  - **§5 adım 6 bitti (gizli not ve geri çekme, R7):**
    - Gizlilik metinle aynı sürümde: ajanda `gizli_not` (`govde` grubu), süre gövdesi
      `govde_gizli`, `CaseNote.secret`, kart `noteSecret` (`not` ile tek alan), icra
      `aciklamaGizli` (`bilgi` grubu). Gizli ajanda satırı başlığıyla birlikte gizlidir.
    - `lib/services/notes/secret_notes.dart`: bütün dışa çıkış kararları burada. Gizli olan görev
      paketine, paylaşılan dosyaya, takvim dosyasına, icra belgesine girmez; kart büroya boş metin
      ve kendi sürümüyle gider. Kendi cihazlara tam gider.
    - **Görev paketi not taşımaz** (`notBicimi: 2`). Notlar `gorev-notlari` büro parçasıyla
      (`lib/services/notes/task_notes.dart`) not not, grup sürümleriyle gider; alıcı not not
      birleştirir, gizlenen ve silineni açık işaretle bırakır, gizleneni kalıcı tutar (eski liste
      diriltmez). Kapanan görevin notları alıcıda düşer.
    - Gizleme kaydı (`note_hide`) yerel yazımla aynı anda, metinsiz ve kalıcı; ajanda parçası kapalı
      cihaz da bu kayda bakar. Kimde ne var (`note_hold`): gönderimde "olası", alıcının
      bildirimiyle "tutuyor"/"uyguladı". Bu ikisi ve alıcının aldığı gizlemeler `not-takibi`
      (her zaman açık kendi cihaz parçası) ile eşitlenir. "Geri çekildi: n/m kişide" kişinin bütün
      cihazları uygulayınca sayılır.
    - Kart notu, dosya notu ve icra açıklamasının geri çekilmesi para yetkisinden ve paylaşım
      ayarından bağımsız, metinsiz işaretle (`kartGizli`); alıcı her kart birleşiminden sonra
      yeniden uygular.
    - Eski paketler: veren tarafta bekleyen/kaynak dosyalar notsuz yeniden yazılır, teslimler
      "eski" tutan olarak kaydedilir; alıcıda verenin ilk listesi gelince ve sonra gelen her eski
      pakette notlar ve süreler ayrıntı dosyasından silinir (evraklara dokunulmaz).
    - Meslektaşın kart ve dosya notu servis katmanında değiştirilemez (R6).
    - İlan ve etkinleştirme: `notGizli`, `geriCekme`; `gorev-notlari` ve `not-takibi` bunları ister.
    - Ekranlar (onaylı maketler): ekleme penceresinde anahtar; ajanda satırında kilit; notu basılı
      tutunca ya da sağ tıklayınca gizlilik ve geri çekme durumu; dosya notu ve kart notu anahtarı
      ve etiketi; icra açıklaması anahtarı; paylaşılmış notu gizlerken onay penceresi.
    - Testler: `test/sync_step6_test.dart`, `test/sync_step6_screens_test.dart`.
  - **§5 adım 7 bitti (öneri, karar ve karar cihazı, R6):**
    - `lib/services/portal/portal_proposals.dart`: değişmez öneri (`proposal`), ayrı karar
      (`proposal_decision`, çıktılarıyla), karar cihazı seçimi (`decision_device`, nesilli).
    - `lib/services/office/proposals.dart` (`ProposalService`):
      - öneri: icra ödemesinin tutar, tarih, borçlu, ödeme, açıklama, tamamı ya da silinmesi;
        kart notu; dosya notu. Gördüğü grup sürümlerini taşır;
      - karar yalnız karar cihazında ve tek işlemde: sürüm denetimi, uygulama (sahibin kendi
        yazımı olarak, `LedgerService`/`saveClient`), karar ve çıktıları (önce/sonra);
      - kayıt öneriden sonra değiştiyse öneri eskidir, uygulanmaz ("Kapat");
      - karar cihazı: varsayılan kişinin ilk cihazı (büro kimliği); devir yalnız karar cihazından
        açık bir diğer cihaza; "kayboldu" yeni nesil seçer, o an bilinen kararlar geçerli kalır;
      - eski nesilden sonradan gelen karar geçersizdir: çıktısı, o arada değişmediyse geri alınır
        (değiştiyse çatışma işareti), öneri yeniden karara açılır;
      - büroya: öneriler sahibine, kararlar önerene (çıktısız); finansal olan yalnız ikisi de parayı
        görebiliyorsa; kart notu önerisi yalnız paylaşılan kartta. Kendi cihazlara: öneriler,
        kararlar (çıktılarıyla) ve karar cihazı (`oneriler`).
    - İlan: `oneri`; `oneri` ve `oneriler` bunu ister.
    - Ekranlar (onaylı maketler): meslektaşın ödemesinde "Değişiklik öner" / "Silinmesini öner",
      öneri kipinde ödeme penceresi (neden alanı); önerenin durumu (bekliyor / onaylandı /
      reddedildi / kayıt değişti); Kasa ve müvekkil kartında "Bekleyen öneriler" şeridi ve listesi
      (şimdi → önerilen, Onayla / Reddet, eskiyse Kapat; karar cihazı dışında yalnız görünür);
      meslektaşın kartında "Not öner"; Senkron sayfasında karar cihazı kutusu.
    - Testler: `test/sync_step7_test.dart`, `test/sync_step7_screens_test.dart`.
  - Sıradaki adım: adım 7'nin Codex kod denetimi, sonra §5 adım 8 (paylaşılan dosyada defter;
    önce maket).
- Bilinen, bu işten önce de kırık olan testler:
  - codex_recheck, dropped_files, ocr_test, office_transfer (zamana bağlı), shared_directory,
    task_package, uets_connect, uyap_case_test, uyap_connect, uyap_door, uyap_library,
    uyap_web_service "send gate", viewer_registration, editor_drafts (Windows geçici klasör kilidi).
  - Tek başına geçen zamana bağlı olanlar: secret_store, live_share, folder_sync, swipe_pages,
    petition_format.

## 1. Bugün nasıl çalışıyor

### Genel mekanizma

- **Kendi cihazlar (Senkron):** Senkron zarfı (`{'t':'senkron','parcalar':…}`) kayıtlı her parçayı
  taşır (`own_sync.dart:309-319`; `office_network.dart:812-847`, `:1049-1061`).
  - Ajanda/müvekkil parçası her turda **bütün dökümünü** gönderir, fark değil.
  - UYAP parçası özet gönderir; karşı taraf eksik kayıtları ayrıca ister (`uyap_own_sync.dart:70-91`).
  - Ne zaman çalışır: kendi cihaz keşifte görülünce, ve yerel bir değişiklikten 3 sn sonra
    (`ownChanged`, `:736-739`; `PortalDatabase.changed`, `own_sync.dart:431-436`).
  - `office_network.dart:815-820` keşif kaynaklı çağrıları en çok 30 sn'de bire sınırlar. Bu bir hız
    sınırıdır, düzenli çalışma garantisi değildir.
  - Gelen veriyi birleştirmek `changed` tetiklemez: A→B→C yayılımı B'nin bir sonraki tetiğini bekler.
    `_ownCame` birleşimin dönüş değerini kullanmaz (`:794-803`).
- **Büro ağı:** her `officeParts` parçası alıcı üye için dışa aktarılır, gönderen cihaz kimliğiyle
  birleştirilir (`office_network.dart:487-522`, `:996-1012`).
  - İki parça var:
    - `paylasilan-dosya` (SharedCases): her zaman açık (`own_sync.dart:291-295`).
    - `muvekkil-buro`: isteğe bağlı, varsayılan kapalı (`own_sync.dart:64-65`, `:363-417`).
- **Değişiklik sürümü yok:** kayıtlarda sahip (`person`) var. Değişikliği yapan kaynak cihaz, sayaç
  ya da vektör saat yok. Her şey duvar saatine bağlı ve **saat dilimsiz yerel saat**
  (`DateTime.now().toIso8601String()`). Bu biçimdeki alanlar:
  - `agenda.updated`, `agenda_removed.at`, `deadline_user.updated`, `case_representation.updated`
  - `client.updated` ve alan başına `stamps`/`alanZamani` (`lib/services/clients/client.dart:45-48`,
    `:292-295`)
  - `client_record.updated` (`client.dart:503`, `:525`)
- `cases_revision`, `clients_revision` yalnız yerel önbellek sayaçlarıdır.
- **Protokol sürümü:** keşifte bir sürüm var, ama yalnız `version < 1` reddediliyor
  (`office_peer.dart:45`, `:80-83`). Özellik ya da yetenek anlaşması yok.
- **Paket boyutu:** büro bağlantısında satır başına 1 MiB sınırı var (`office_link.dart:15-16`,
  `:31`). Bütün döküm büyüdükçe aktarım bu sınıra dayanır.

### A. İcra haricen tahsilat / feragat (`EnforcementLedger`)

- **Saklama:** `client_record`, `kind='icra'` (`client.dart:447`).
  - Alanlar `data` içinde: `dosya, tur, tutar, zaman, borclu, odeme, aciklama, tamami, uyapBakiye,
    bildirildi, resmi`.
  - `clientId` dosyanın müvekkil kartıdır. Kart yoksa `officeCashId='buro'` kullanılır
    (`enforcement_view.dart:257-279`).
- **Para:**
  - İcra kaydı hesap toplamına katılmaz (`client.dart:462-468`). Ama aynı yüzden **para görme
    yetkisinin kapsamına da girmez** (bkz. §2 risk 13).
  - Defter kaydı ayrıca **kilitli** `hareket` kayıtları yazar, `'kaynak':'icra:<entryId>'`
    (`enforcement_view.dart:316-338`). Kilitli kayıtlar hiç ezilmez (`portal_clients.dart:67-71`,
    `:500`).
- **Düzenle / sil / bildirildi:**
  - Değişiklik `saveClientRecord(copyWith(...))` ile yazılır, `updated=now`
    (`enforcement_view.dart:454`, `:904-922`, `:953`).
  - Silme `silindi:true` işaretidir (`:953`).
  - Para hiç silinmez; geri alma `'ters'` işaretli yeni kayıttır (`:391-415`).
  - Düzenleme, eski hareketlerin terslenmesi ve yenilerinin yazılması **ayrı ayrı** yazılır
    (`:439-459`). Defter kaydı başarısız dönse bile para işlemleri sürebilir.
- **Kendi cihazlar:** ajanda parçasının içinde gider (`_agendaExport` → `clientsExport()`,
  `portal_database.dart:1264`; `agendaMerge` → `clientsMerge`, `:1466-1474`).
  - Kural: kayıt kimliği başına **bütün kayıt, son yazan kazanır** (`portal_clients.dart:499-503`).
    Gelen kayıt yalnız `updated` daha yeniyse ve yerel kayıt kilitli değilse yerine geçer.
  - Alan birleştirme yok. Eşitlikte yerel kalır.
- **Büro:** yalnız `muvekkil-buro` açıksa ve kart paylaşılmışsa (`c.office`). `officeCashId` kayıtları
  yalnız parayı görebilenlere gider (`portal_clients.dart:365-374`).
  - Herkes yalnız `rec.person == me` kayıtlarını gönderir.
  - Alırken yalnız `r.person == author` ve yerel kopya aynı kişi/müvekkil/türdeyse kabul edilir
    (`:487-498`); sonra aynı son-yazan-kazanır kuralı.
  - Gelen bir `ters` hareketin **hedef hareketinin sahibi doğrulanmaz**.
  - **Dosya paylaşmak (SharedCases) defter kayıtlarını göndermez**: yalnız UYAP kaydı, duruşmalar ve
    ekler gider (`shared_cases.dart:161-194`). Meslektaş UYAP'ın borcunu görür, Folio'daki kalanı
    (`folioLeft`) görmez.
- **Kasa ve müvekkil hesabı tersleri farklı sayar:**
  - Müvekkil hesabı aynı hareketin terslerini `taken` kümesiyle tek etkili sayar
    (`client_accounts.dart:149-154`).
  - Kasa her ters kaydı ayrı negatif tutar olarak toplar; `struck` toplamdan dışlanmaz
    (`office_cash.dart:94-104`, `:139-173`, `:198-215`).

### B. Ajanda

- **Saklama:** `agenda` tablosu (`portal_database.dart:148-152`). Silinenler `agenda_removed(id, at)`
  (`:238`).
  - Tebligat süreleri ajanda satırı değildir: tamamlandı/gün/başlık `deadline_user`'da tutulur
    (`:1120-1140`, `:1210-1216`, `:2160-2179`).
  - `saveAgenda` bütün satırı yazar (`INSERT OR REPLACE`, `:1190-1206`). Tamamlandı işareti
    `copyWith(done:…)` ile `updated=now` (`agenda_page.dart:461`; `portal_database.dart:84-101`).
- **Kendi cihazlar:** `ajanda` parçası, varsayılan açık (`own_sync.dart:335-362`).
  - Gönderilenler (`portal_database.dart:1236-1265`):
    - `satirlar`
    - `silinen`
    - `kararlar` (deadline_user)
    - `secimler` (deadline_choice)
    - `temsil` (case_representation)
    - müvekkil verisi
  - **Silme işaretleri:** gelen silme, yerel satırı yalnız yerel `updated <= silme zamanı` ise siler
    (`:1330-1347`).
  - **Satırlar:**
    - Gelen satır yerel silme işaretinden yeni değilse atlanır (`:1352`); daha yeniyse uygulanır.
    - Eşit zamanda sütunların JSON'u büyük olan kazanır (`:1290-1326`, `:1353`).
    - **Bütün satır yerine geçer** (`:1356-1372`).
  - Diğerleri:
    - `deadline_user`: aynı kural (`:1375-1415`).
    - `deadline_choice`: yalnız eklenir (`:1417-1432`).
    - `case_representation`: kesin daha yeni kazanır, eşitlikte karar yok (`:1433-1456`).
  - Silme işaretleri hiç budanmaz.
- **Büro:** ajanda parçası yok.
  - Ama `TaskPackage.caseExtras` dosyanın ajandasının düz kopyasını taşır (`task_package.dart:165-207`):
    - `sureler`
    - `notlar`: süre olmayan her satırın türü, başlığı, gövdesi, tarihi, tamamlandısı.
  - Bu kopya görev paketleriyle gider (`:137`; görev sayfasında salt okunur,
    `tasks_page.dart:1150-1161`). Dosyanın paylaşıldığı **her üyeye** de gönderilir
    (`shared_cases.dart:182`).
  - Paylaşılan dosyada alıcı bu kopyayı atar (`adoptChecked` yalnız `UyapCaseRecord`'u okur,
    `uyap_case_store.dart:323-342`). Ama veri yine de gönderilmiş olur.
  - Geri hiçbir şey gelmez. Büro görevleri ajandada sanal `gorev-*` olarak görünür, saklanmaz
    (`agenda_page.dart:427-450`).

### C. Notlar

| Not | Saklama | Kendi cihazlar | Büro |
|---|---|---|---|
| Ajanda notu/işi `body` | `agenda.body` | evet, bütün satır son yazan kazanır | paylaşılan dosya ve görevle `caseExtras.notlar` kopyası |
| Süre başlık/gövde değişikliği | `deadline_user.title_override/body_override` | evet, bütün satır | `sureler` (yalnız başlık) |
| Müvekkil kartı `not` | `client.json` (`client.dart:92`, `:202`) | **alan alan** birleşir: her alanın zamanı, eşitlikte büyük değer (`client.dart:217-270`; `portal_clients.dart:471-478`) | kart paylaşılınca bütün `c.toJson()` (`portal_clients.dart:355`) |
| Dosya notu `CaseNote(text, at, by)`, `dosyaNotlari` | `client.json` (`client.dart:386-409`; yazılış `clients_page.dart:3570-3580`) | dosya anahtarı başına, `at` daha geç olan kazanır (`client.dart:239-243`) | kartla birlikte |
| Görüşme tutanağı, vekalet, mesaj | `client_record` | bütün kayıt son yazan kazanır; kilitliler donuk | paylaşılan kart için, yalnız kendi yazdığı |
| Defter `aciklama` | icra kaydının içinde | A gibi | A gibi |
| PDF üzerindeki notlar | `index_database.dart:93-105`, `:366-395` | **eşitlenmiyor** | hayır |

- **`uets_document.note` bir kullanıcı notu değildir.** Tebligat okuyucusunun yazdığı durum ve hata
  açıklamasıdır ("dosya bulunamadı", "XML tanınmadı"). Yeniden okumada satırlar yeniden oluşur
  (`notice_documents.dart:44-45`, `:234-251`, `:289-294`). Eşitlenmez, eşitlenmemelidir.
- **PDF notları** mutlak dosya yolundan türeyen belge anahtarı ve yerel artan tamsayı kimlikle
  tutulur. Güncelleme sürümleri yoktur, silme sert silmedir. Cihazlar arasında taşınabilir değildir.
- **Müvekkil kartı notu üretilen belgeye de kopyalanır** (`enforcement_papers.dart:174`).
- **Büroda kart birleştirme:** kartı yalnız sahibinin değişikliği değiştirir
  (`c.person == from && kept.person == from`), alan alan (`portal_clients.dart:394-433`).
- **Paylaşımı kaldırmak:** yalnız kimlik işareti gider.
  - Alıcı başkalarının kayıtlarını **sert siler** (işaret bırakmadan), kendisininkileri tutar
    (`portal_clients.dart:401-426`, `:505-513`).
  - Para görme yetkisini kaybetmek de başkalarının para kayıtlarını siler, ama yalnız `ucret` ve
    `hareket` türlerini (`own_sync.dart:480-498`; `portal_clients.dart:125-134`). Başkalarının
    `kasa`, `kasaTekrar`, `banka`, `belge` kayıtları kalır.
- **Hiçbir not "büroya gitmesin" diye işaretlenemiyor.** Kodda var olan `Client.hidden` (JSON
  `gizli`) yalnız listede gizlemektir; paylaşım anlamı yoktur.

## 2. Ezme ve tutarsızlık riskleri

1. **Haricen tahsilatta alan kaybı:** A cihazında `aciklama`, B'de `bildirildi` değişirse daha geç
   `updated` kazanır, öteki kaybolur.
2. **Ekran açılınca yazma:** `_loadBooked`, icra görünümünü açan cihazda `resmi` alanını yazıp
   `updated`'ı tazeliyor (`enforcement_view.dart:164-171`). Başka cihazdaki, henüz gelmemiş eski
   tarihli elle düzenlemeyi sessizce ezebilir.
3. **Çift para hareketi ve çift ters:** aynı kaydı iki cihazda düzenlemek iki `_unbook`/`_bookLedger`
   çalıştırır.
   - **İki yeni `icra:<id>` hareketi** birlikte kalır: müvekkil hesabı ve kasa iki kez düşer, defter
     satırı tek tutarı gösterir.
   - Eski hareketin iki ters kaydı müvekkil hesabında zararsızdır (`taken`), **kasada değildir**: kasa
     her tersi ayrı toplar. Ücrete mahsup edilmiş 100 TL, iki tersle kasada −200 TL olabilir.
4. **Farklı eşzamanlı tutarlar:** A tutarı 100→120, B 100→130 yaparsa iki ayrı hareket kalır, defter
   bir tutarı gösterir. Tarih ve mahsup hedefi değişikliği de yeniden hareket yazar.
5. **Atomik olmayan yerel yazım:**
   - Defter düzenlemesi, terslemeler ve yeni hareketler ayrı yazılır. Arada kapanma ya da hata,
     defterle kasayı ayırır.
   - Diyalog açıkken gelen güncelleme, eski `e.record` üzerinden yapılan kayıtla kaybolur.
6. **Büroda sahiplik yok:** `enforcement_view.dart`'ta `person` denetimi yok.
   - Meslektaş sahibin kaydını düzenler, siler ya da bildirildi/resmi işaretlerse değişiklik yerelde
     kalır (`person` sahip olduğu için hiç gönderilmez).
   - Ama yeni yerel `updated` sahibin daha eski zamanlı düzenlemelerini engeller.
   - Meslektaşın ters ve yeniden yazma hareketleri (`person` = meslektaş) gönderilip kabul edilir.
     Gelen tersin hedefinin sahibi doğrulanmadığından meslektaş sahibin kilitli hareketinin etkisini
     kaldırabilir.
7. **Ajandada alan kaybı:** A'da tamamlandı, B'de başlık değişirse biri kaybolur. Silmeden sonra başka
   cihazda yapılan düzenleme satırı geri getirir.
8. **Kart notunda ayrışma:** meslektaş paylaşılan bir kartın notunu ya da dosya notunu değiştirirse
   yerelde yazılır, hiç gönderilmez (`mine(c.person)` yanlış, `portal_clients.dart:344`, `:353`).
   Yerel alan zamanı daha yeni olduğu için sahibin eski zamanlı güncellemeleri reddedilir. İki taraf
   sahip yeniden yazana kadar ayrışık kalır.
9. **`case_representation` eşitliği:** eşit zamanda yerel kalır; cihazlar ayrışabilir.
10. **Saat:** saat dilimsiz yerel zaman; saati ileri olan cihaz her çakışmayı kazanır. Aynı metin
    farklı saat dilimindeki alıcılarda farklı ana dönüşür.
11. **Gizlilik:** paylaşılan dosya ve görevle dosyanın bütün ajanda notları gider; "gizli" işareti yok.
12. **Eski ve yeni sürüm birlikte:**
    - Eski uygulama yeni alanları düşürebilir, bütün satırı yazabilir.
    - Yeni kayıt türlerini (öneri) tanımaz.
    - Yeni gizlilik kurallarını uygulamaz.
13. **İcra kaydı para yetkisinin dışında:**
    - `enforcement` türü para kapsamına girmediği için paylaşılan kartın icra tutarı, borçlusu ve
      açıklaması para görmeyen üyeye gidebilir (`client.dart:462`; `portal_clients.dart:365-373`,
      `:480-483`).
    - Yetki kaybında temizlik de eksiktir (§1 C).
14. **Paket büyümesi:** silme işaretleri budanmadığı ve her tur bütün döküm gittiği için paket 1 MiB
    satır sınırına dayanabilir. Başarısız aktarım başarılı senkron gibi görünebilir.

## 3. Kararlar (kullanıcı, 14 Ekim 2026)

1. **Notların varsayılanı senkron durumuna bağlıdır:**
   - Senkron açıksa notlar kendi cihazlara gider.
   - Büro paylaşımı açıksa (paylaşılan dosya/kart, görev) büroya da gider.
   - Gizli kalması gereken not **"gizli not"** olarak eklenir.
   - **Gizli not kullanıcının kendi diğer cihazlarına gider** (Senkronun ilgili parçası açıksa).
     Büroya, görev paketine, paylaşılan dosyaya ve üretilen belgeye hiç gitmez. "Gizli" ekranda bu
     anlamla anlatılır: "büroyla paylaşılmaz".
2. **Başkasının tahsilatı:** büroda meslektaş sahibin defter kaydını doğrudan değiştiremez.
   - Yaptığı değişiklik (düzenleme, silme, bildirildi/resmi işareti) sahibe **öneri** olarak gider.
   - Sahip onaylarsa uygulanır, reddederse düşer.
   - Öneriyi yapan, sonucunu görür.
3. Plan uygulanmadan önce Codex'e denetletilir.
4. **Kart paylaşılmadan defter:** dosya paylaşılınca defter kendiliğinden gitmez. Paylaşırken ayrı bir
   tercih olur: **"Folio hesabını da paylaş"**.
   - Seçilirse yalnız o dosyanın alıcılarından para görme yetkisi olanlara gider.
   - Yalnız kalan borç için gereken defter verisi gider: kayıtlar, tutarlar, tarihler, açıklama.
   - Kartın kimlik/iletişim bilgileri ve müvekkilin genel hesabı eklenmez.

## 4. Hedef kurallar

- **R0 Sürüm ve yetenek anlaşması:**
  - Keşif, senkron zarfı ve **her paket biçimi** (görev paketi, paylaşılan dosya, dosya isteği, soru
    kanalı, `muvekkil-buro`) bir biçim sürümü taşır.
  - Bağlantı kurulunca, doğrulanmış kanalda yetenek listesi alışverişi yapılır: `hlc`, `alanSurumu`,
    `defterIslemi`, `silmeOmru`, `oneri`, `notGizli`, `geriCekme`, `defterPaylasimi`, `paketBolme`.
  - Her parça ve kanal için gereken yetenekler bir **matriste** yazılır (§4.1).
  - Gereken yeteneği ilan etmeyen ya da sürüm göndermeyen eşe o parça/kanal **gönderilmez, ondan
    alınmaz** (güvenli varsayılan ret). Eski biçimde gelen istekler de reddedilir.
  - Ekranda bütün eşitleme değil, **hangi parçanın neden durduğu** gösterilir: "Ajanda bu cihazla
    eşitlenmiyor: diğer cihazı güncelleyin".
  - Bir yetenek ancak onu kullanan özellik bütünüyle hazır olunca ilan edilir. Yarım bir özellik
    yetenek olarak ilan edilmez.
  - Göç bir kez, deterministik ve tekrar çalıştırılabilir yapılır. Şema sürümü tutulur, göçten önce
    veritabanının yedeği alınır.
- **R1 Alan alan birleştirme, alan grupları:**
  - Defter kayıtları (`client_record` icra), ajanda satırları, `deadline_user`, müvekkil kartı,
    `CaseNote`, `CaseLink` ve `case_representation` için her alanın ya da **alan grubunun** kendi
    HLC sürümü olur. Gelen kayıt yalnız kendi daha yeni alanlarını/gruplarını değiştirir.
  - Birlikte değişmesi gereken alanlar tek grup olarak sürümlenir:
    - süre onayı: `confirmed_inputs`, `confirmed_at`, `confirmed_day`;
    - defterin finansal grubu (R3'teki kanonik finansal veri).
  - Alan sürümü yalnız gerçekten değişen alana verilir.
- **R2 Mantıksal saat (HLC) ve eşitlik:**
  - Sürüm `(l, c, kaynak)`: `l` milisaniye UTC, `c` sayaç, `kaynak` değişikliği yapan cihazın
    kalıcı kimliği ve **yazım nesli** (`cihaz:nesil`).
  - **Yerel yazım:** `l' = max(l, şimdi)`. `l' == l` ise `c' = c + 1`, değilse `c' = 0`.
  - **Uzak sürüm alma:** `l' = max(l, l_uzak, şimdi)`. Sayaç büyük olan `l`'nin sayacından
    sürer: `l'` hem yerel hem uzak `l`'ye eşitse `max(c, c_uzak) + 1`, yalnız birine eşitse onun
    sayacı + 1, ikisine de eşit değilse 0.
  - **Karşılaştırma:** önce `l`, sonra `c`, sonra `kaynak` (sözlük sırası).
  - Saat durumu (`l`, `c`) veritabanında kalıcıdır. Yeniden başlatmada `l = max(saklı l, şimdi)`
    ile başlanır.
  - **Yedekten dönüş:**
    - Veritabanı bir açılış sayacı tutar. Aynı sayaç veritabanının dışında, yedeğe girmeyen bir
      dosyada da tutulur.
    - Açılışta veritabanındaki sayaç dışarıdakinden küçükse yedekten dönülmüş demektir. Cihazın
      yazım nesli bir artar.
    - Yeni nesil `kaynak`'ın parçası olduğu için, yedekten önce kullanılmış bir `(l, c)` tekrar
      üretilse bile sürüm aynı olamaz.
    - Dışarıdaki sayaç ve nesil yalnız ileri gider. Yazımı önce dışarıya, sonra veritabanına
      yapılır; arada kesinti olursa sonraki açılış yine yedekten dönüş sayar (fazladan nesil
      zararsızdır).
    - Yedekten dönen cihaz, ilk eşitlemesi bitene kadar yazdıklarını yine yazar. Yeni nesil, eski
      nesildeki daha geç sürümlerle R1 kurallarına göre karşılaşır. Ekranda "yedekten dönüldü,
      eşitleniyor" denir.
  - **Garanti sınırı:** HLC, bir cihazın gördüğü değişikliklerden sonra yazdığını onlardan sonraya
    koyar (nedensel sıra). Birbirini görmeden aynı alanı değiştiren iki cihazda kazananı yine
    fiziksel saat belirler; saati çok ileri bir cihaz bu durumda kazanır. Bu, alan grubu
    birleştirmeyle sınırlanır ve ekranda gösterilmez.
  - Kaynak cihaz, değişikliği **yapan** cihazdır; aktaran cihaz sürümü yeniden üretmez.
- **R2.1 Göç (deterministik):**
  - Yalnız **ofsetsiz eski sürüm damgaları** dönüştürülür. Ofseti ya da `Z`'si olan zamanların anı
    korunur. Finansal işlem tarihi (`zaman`) bir sürüm damgası değildir, göçte değişmez.
  - Bozuk ya da eksik damga `l = 0` sayılır: her gerçek sürümden eskidir, içerik özetiyle karar
    verilir.
  - Saat dilimsiz eski zamanlar, cihazın saat diliminden bağımsız olarak **sabit +03:00 (Türkiye
    saati)** sayılır. Türkiye 2016'dan beri sabit +03:00'tür; aynı veritabanı her cihazda aynı
    sürümleri üretir.
  - Göçte sürümün `kaynak`'ı sabit `goc` değeridir; `c = 0`.
  - Müvekkil kartındaki mevcut alan damgaları (`stamps`) **korunur**. Yalnız damgası olmayan alanlar
    kaydın `updated` zamanını alır.
  - Aynı eski zamanlı, farklı içerikli iki göç sürümü karşılaşırsa içeriğin kanonik JSON'unun özeti
    büyük olan kazanır; her cihaz aynı sonucu bulur.
  - Testlerden biri: aynı veritabanı farklı saat dilimlerinde göç edilince bütün sürümler aynı.
- **R3 Finansal işlem modeli:**
  - **Kanonik finansal veri** defter kaydının finansal grubudur: müvekkil/hesap (`clientId`), dosya,
    tür, tutar, tarih (`zaman`), ödeme yöntemi (`odeme`), mahsup hedefi, `tamami`, `uyapBakiye`
    (kayıt anındaki UYAP bakiye görüntüsü) ve yaşam döngüsü (R5).
  - Mahsup bugün ayrı hareketlerle yapılıyor ve **kısmi** olabiliyor (100 TL emanetin 40 TL'si).
    Artık defter kaydı bir **mahsup listesi** taşır:
    - her mahsup: kimlik, hedef (ücret/masraf), tutar, tarih, kendi yaşam döngüsü;
    - mahsuplar kayda (`entryId`) bağlıdır, finansal sürüme değil: tutar değişse de mahsup aynı
      mahsuptur;
    - mahsup toplamı emaneti aşamaz. Yerel komutta aşan mahsup reddedilir. Birleşimde aşım
      aşağıdaki **etkin durum** kuralıyla çözülür.
  - **Etkin durum (her cihazda aynı):** birleşmiş veriden, teslim sırasından bağımsız, saf bir
    hesapla bulunur:
    1. emanet = kazanan finansal içeriğin tutarı (kayıt silinmişse 0);
    2. mahsuplar, yaşam döngüsü `etkin` olanlar, `(mahsup HLC sürümü, mahsupId)` sırasına dizilir;
    3. sırayla, birikmiş toplam emaneti aşmadıkça her mahsup **etkin** sayılır;
    4. aşan mahsup ve ondan sonrakilerden sığmayanlar **askıda** sayılır:
       - silinmez, ayak üretmez;
       - ekranda "emaneti aşan mahsup, askıda" diye görünür;
       - emanet artar ya da önceki bir mahsup silinirse kendiliğinden etkinleşir.

    Örnekler:
    - 100 TL emanete iki cihazda 60'ar TL mahsup: sürümü önce olan etkin, öteki askıda.
    - Tutar 100'den 50'ye inerken öteki cihazda 80 TL mahsup: emanet 50, 80 TL'lik mahsup askıda.
    - Askıdaki mahsup kullanıcıya bildirilir; kullanıcı tutarını düzeltir ya da siler.
  - **Üç sürüm ayrıdır:**
    - finansal içerik sürümü: tutar, tarih, hesap, ödeme, `tamami`, `uyapBakiye`;
    - yaşam döngüsü sürümü: `etkin` / `silindi`, R5;
    - her mahsubun kendi içerik ve yaşam döngüsü sürümü.
  - **İcradan doğan para hareketleri senkronla gönderilmez ve kalıcı olay değildir.** Bunlar
    defterin **projeksiyonudur**:
    - Her cihaz, kanonik verinin **güncel etkin durumundan** emanet ve etkin mahsup ayaklarını
      hesaplar. Müvekkil hesabı ve kasa bu ayakları projeksiyon tablosundan okur.
    - Projeksiyon, kaydın kanonik verisi değişince (yerel düzenleme, gelen birleşim, silme, geri
      alma, askıya düşme ya da askıdan çıkma) **o kayıt için baştan yeniden kurulur**. Bu, kanonik
      veriyle aynı veritabanı işleminde yapılır (R12).
    - Yeniden kurma tekrar çalıştırılabilir (idempotent): aynı kanonik veri her cihazda, hangi
      sırayla gelmiş olursa olsun, aynı ayakları verir.
    - İcradan doğan ayaklar için **ters kayıt yazılmaz**. Ayağın etkisi, projeksiyondan çıkınca
      kalkar. Böylece askıdan çıkan ya da geri alınan bir mahsubun önünde terslenmiş kimlik engeli
      olmaz.
    - Ayak kimlikleri (`icra:<entryId>:emanet`, `icra:<entryId>:mahsup:<mahsupId>`) yalnız
      projeksiyon içinde satır kimliğidir ve kalıcı bir olaya bağlanmaz. Bu yüzden nesil ya da
      sürüm taşıması gerekmez.
    - Değişikliklerin izi, para etkisi olmayan ayrı bir **defter geçmişinde** tutulur: kim, hangi
      cihazda, ne zaman, hangi alanın eski ve yeni değeri. "Para hiç silinmez" kuralının amacı (iz)
      böylece korunur. Ekranda kaydın geçmişi buradan gösterilir.
    - Defter geçmişinin eski ve yeni değerleri R11 (finansal yetki) ve R7 (gizli metin)
      kurallarına tabidir. Geçmiş büroya ancak bu kurallarla süzülerek gider.
    - Örnekler:
      - 100 TL, 40 TL mahsup → sil → geri al: silmede projeksiyon boşalır, geri almada emanet ve
        40 TL mahsup döner.
      - M1 ve M2 60'ar TL, cihazlar farklı sırayla görür; M1 silinir: her cihazda projeksiyon M2'yi
        etkin gösterir.
  - Elle girilen hareketlerin tersleri (icraya bağlı olmayanlar) bugünkü gibi kalıcı kayıttır.
    Bunlarda kasa da müvekkil hesabı gibi hedef başına **tek ters** sayar (`taken`).
  - **Eski hareketlerle uyum:**
    - Göçte, bir kaydın mevcut `kaynak:'icra:<entryId>'` kilitli hareketleri ve onların tersleri
      okunur. Bunların bıraktığı **net etki** kanonik veriyle karşılaştırılır: tek bir toplam değil,
      hesap ve dosya, para birimi, emanet ve gelir bileşenleri ayrı ayrı, mahsup bağlantılarıyla
      birlikte.
      - Uyuşuyorsa eski hareketler projeksiyona devredilir: hesaptan çıkarılıp yerini projeksiyon
        alır ve defter geçmişine yazılır. Toplam değişmez.
      - Uyuşmuyorsa aşağıdaki onarım raporuna gider.
    - Mevcut mahsup hareketleri, tutarlarıyla birlikte kaydın mahsup listesine alınır (kısmi
      mahsup korunur).
    - Eski rastgele kimlikler cihazlar arasında farklı olduğu için eşleme tablosu (eski kimlik →
      kayıt) da kanonik kayıtla birlikte eşitlenir. Bir cihaz eski bir kimliğe bağlı bir elle işlem
      görürse tabloya bakar; tabloda yoksa işlem raporlanır.
    - Bir kayda karşılık hareketler kanonik veriyle tek anlamlı eşleşmiyorsa (çift emanet, tutar
      uyuşmazlığı) o kayıt otomatik düzeltilmez. **Onarım raporuna** alınır ve türetme o kayıt
      için durur.
    - Rapor, incelediği kayıt ve hareket kümesinin özetini taşır. Onayda küme yeniden okunur; özet
      değiştiyse rapor yeniden üretilir.
    - Onarım tek işlemdir ve tekrar uygulamaya dayanıklıdır.
  - **İcradan doğan ayaklara doğrudan elle işlem yapılmaz.** Bu ayaklara yönelik mahsup ve ters
    komutları kapatılır; ekrandaki "Mahsup et" ve "Geri al" defter servisinden geçer ve kanonik
    kaydı (mahsup listesini ya da yaşam döngüsünü) değiştirir.
    - Bir ayağın hangi sürüm ya da nesilden olduğu önemsizleşir. A'nın `v1`'ine bağlı bir işlem B'de
      `v1` hiç görülmeden de doğru sonuç verir, çünkü işlem kayda bağlıdır.
  - Elle girilen öteki hareketler (`ucret`, icraya bağlı olmayan elle `hareket`) bugünkü gibi
    eşitlenir.
  - Bir elle tersin hedefi henüz gelmediyse ters "bekleyen" alana alınır, toplamlara katılmaz. Hedef
    gelince yeniden doğrulanır. "Yetkisiz" ile "bağımlılığı gelmemiş" ayrı durumlardır.
  - Aynı kimlikli bir elle hareket farklı içerikle gelirse sessizce atlanmaz; bütünlük çatışması
    olarak kaydedilir ve gösterilir.
- **R4 `resmi` için üç ayrı veri:**
  1. Otomatik UYAP eşleşmesi türetilmiş veridir. Her açılışta hesaplanır, kaydedilmez.
  2. Kullanıcının elle kararı (`resmiKarar`) sürümlü bir alandır ve **hangi finansal sürüme ait
     olduğunu** taşır. Finansal sürüm değişince karar geçersizleşir, ekranda "yeniden onaylayın"
     denir.
  3. `uyapBakiye` kayıt anındaki görüntüdür ve finansal grubun içindedir.
  - Göçte eski otomatik `resmi` değerleri atılır, eski `elle` değerleri `resmiKarar` olur.
  - Görüntülemek hiçbir şey yazmaz.
- **R5 Silme yaşam döngüsü:**
  - Silme ve geri alma ayrı işlemlerdir: kaydın bir **yaşam döngüsü sürümü** vardır (`etkin` /
    `silindi`).
  - Sıradan bir düzenleme silmeyi kaldıramaz. Silmeden sonra başka cihazda yapılan düzenleme satırı
    geri getirmez; yalnız açık "Geri al" (daha yeni bir yaşam döngüsü sürümü) getirir.
  - Defterde silme, kaydın projeksiyonunu boşaltır (R3); geri alma (daha yeni yaşam döngüsü
    sürümü) projeksiyonu yeniden kurar. İkisi de defter geçmişine yazılır.
  - Silme–düzenleme–geri alma yarışında sonucu, kazanan yaşam döngüsü ve kazanan finansal içerik
    belirler; projeksiyon ondan kurulur.
  - Silme işaretleri ilk sürümde budanmaz. Budama ileride ancak bütün kendi cihazların ve ilgili
    büro üyelerinin işareti gördüğü kanıtlanınca yapılır; süreye bağlı temizlik yapılmaz.
- **R6 Sahiplik ve öneri:**
  - Defter kaydının sahibi `person`. Sahiplik denetimi **bütün yazma yollarında ve gelen veride**
    uygulanır: düzenle, sil, bildirildi, resmi, ters, mahsup.
  - Gelen bir elle ters ya da mahsup hareketin hedefinin sahibi, dosyası ve para yetkisi doğrulanır.
    Sahibi başkasıysa kabul edilmez. Hedef henüz yoksa R3'teki bekleyen alana alınır.
  - Sahip olmayanın defter ya da not etkileyen işlemi bir **öneri** yazar (`kind='oneri'`):
    - benzersiz öneri kimliği;
    - hedef kayıt ve **hedef alanların sürümleri**;
    - önerilen alanlar ya da silme;
    - öneren, sahip, paylaşım kapsamı.
  - Öneri değişmezdir. Karar, sahibin ayrı bir `oneri-karar` kaydıdır (onay/red, öneri kimliği).
  - **Karar cihazı:**
    - İlk sürümde sahibin tek ve sabit bir karar cihazı vardır: büro kimliğini kalıcı anahtarla ilk
      oluşturan cihaz.
    - Anahtarını kalıcı saklayamayan cihaz (oturumluk kimlik, `office_identity.dart`) karar cihazı
      olamaz.
    - Devir yalnız eski karar cihazı da çevrimiçiyken, ikisinin katıldığı bir işlemle yapılır.
    - Kayıp cihaz: sahip yeni karar cihazını seçer. Seçim bir sürüm taşır; eski cihazdan bu
      sürümden sonra gelen kararlar reddedilir. O anda bekleyen öneriler yeniden karara açılır.
      Kayıptan önce verilip henüz ulaşmamış kararların kaybolabileceği ekranda söylenir.
  - **Kararın çıktıları seçim neslini taşır:** karar cihazı seçiminin bir nesli vardır. Bir kararla
    üretilen bütün alan değişiklikleri, kararın kimliğini ve bu nesli taşır.
    - Alıcı karar kaydını ve çıktılarını **birlikte** doğrular. Geçersiz bir neslin kararının
      çıktıları normal alan güncellemesi olarak kabul edilmez.
    - Alıcı, kabul ettiği bir çıktının neslinin geçersiz olduğunu sonradan öğrenirse:
      - alan bu çıktıdan sonra başka bir yazımla değişmediyse çıktıyı geri alır;
      - değiştiyse alanı bırakır, bir çatışma kaydı yazar ve sahibin yeni karar cihazına
        gösterir.
    - Yeniden karara açılan öneri bir kez daha uygulanırsa önceki çıktısı geri alınmış olur; aynı
      öneri iki kez etkili olmaz.
    - Çıktının geri alınması önceki alan değerini geri koyar ve finansal türetmeyi (R3) **aynı
      işlemde** yeniler.
  - **Karar ve uygulama tek işlemdir:** karar cihazında hedef sürüm denetimi, karar kaydı,
    "uygulandı" işareti ve ortaya çıkan değişiklikler (yeni alan sürümleri) tek veritabanı işleminde
    yazılır.
  - Diğer cihazlar karar kaydıyla gelen değişiklikleri birleştirir, öneriyi **yeniden çalıştırmaz**.
  - "Eski öneri" denetimi karar cihazının **o an bildiği** sürümlere göre yapılır. Sahibin başka bir
    çevrimdışı cihazındaki henüz gelmemiş düzenleme, sonra gelince R1 kurallarıyla birleşir.
  - Aynı öneri kimliği bir kez uygulanır. Sonuç öneriyi yapana karar kaydıyla gider.
  - Öneri ve kararın gizlilik sınıfı hedef kayıttan ve taşınan alanlardan türetilir:
    - finansal kaydın önerisi finansaldır (R11);
    - açık bir kart notu önerisi o kartın paylaşım kapsamındadır;
    - gizli metin hiçbir büro önerisine girmez.
- **R7 Gizli not (`notGizli`):**
  - Kapsam: ajanda notu, süre gövdesi, dosya notu (`CaseNote`), müvekkil kartı notu, defter
    açıklaması. Ad `notGizli`: mevcut `Client.hidden`/`gizli` (listede gizleme) ile karışmaz.
  - Metin ve gizlilik durumu **birlikte** sürümlenir. Gizli yeni metin, eski "açık" işaretiyle
    birleşip gönderilemez.
  - Gizli olan şunlara girmez: `caseExtras.notlar`, görev paketi, paylaşılan dosya, `muvekkil-buro`
    dışa aktarımı, öneri ve karar kayıtları, üretilen belgeler (`enforcement_papers.dart:174`), ek
    indirme.
  - **Yönetilen kopyalar:** büroya giden her not kopyası (görev paketindeki `caseExtras.notlar`,
    paylaşılan dosya, kart) kaynak not kimliğini ve sürümünü taşır. Gönderen, hangi üyeye hangi
    notun hangi sürümünü verdiğini tutar.
  - Gönderim takibi ("hangi üyeye hangi sürüm") ve geri çekme yükümlülükleri kendi cihazlar
    arasında eşitlenir. A'nın gönderdiği not B'de gizlenirse B de alıcıları bilir.
  - Göçten önceki kopyalar (kaynak kimliği taşımayan eski görev paketleri) için bir eşleme ve
    temizlik raporu üretilir. Kullanıcı hangi eski paketlerde metin kaldığını görür.
  - Not metni taşıyan eski öneri ve karar kayıtlarında, not gizlenince metin silinir; yalnız
    kimlik ve karar kalır.
  - Önceden paylaşılmış not sonradan gizli yapılırsa o üyelere bir **geri çekme işareti** gider:
    not kimliği ve sürüm, içerik yok.
    - Alıcı işareti **kalıcı saklar** ve metni siler. Daha eski sürümle yeniden gelen bir paket
      metni diriltmez.
    - Alıcı uyguladığını bildirir. Gönderen ekranında not "geri çekildi: 2/3 kişide" diye görünür.
  - Ekranda dürüst söylenir: geri çekme, alıcının cihazıyla bağlantı kurulup uygulanınca
    tamamlanır; dışarı aktarılmış belgeler ve ekran görüntüleri geri alınamaz.
  - Kendi cihazlara gider (karar 1).
- **R8 Paylaşılan dosyada defter:**
  - Yalnız "Folio hesabını da paylaş" seçildiyse gider (karar 4).
  - Alıcılar: dosyanın paylaşıldığı kişiler **ve** para görme yetkisi olanların kesişimi.
  - Alıcıda **ayrı, salt okunur bir görünüm** olarak saklanır (`paylasilan_defter`): alıcının
    müvekkil hesabına, kasasına ve genel toplamlarına **katılmaz**. Kaynak üye, dosya ve paylaşım
    kapsamını taşır.
  - Kalan borcu hesaplamak için gerekenler gider: kanonik finansal veri, yaşam döngüsü, `resmiKarar`.
    Otomatik UYAP eşleşmesini alıcı kendi UYAP kaydıyla yeniden hesaplar.
  - Değişiklik R6 önerisiyle yapılır.
  - **Kanonik veri ile erişim ayrıdır:**
    - Aynı kayıt hem R8'den hem kart paylaşımından gelirse kanonik veri bir kez tutulur.
    - Kaydın **erişim kaynakları** (kart, R8) ayrı ayrı, kendi sürümleriyle izlenir.
    - **Muhasebe projeksiyonu** (alıcının kasasına ve hesabına etkisi) yalnız kart erişimi ve para
      yetkisi varken vardır.
    - Kart erişimi kalkınca projeksiyon temizlenir. R8 erişimi sürüyorsa salt okunur görünüm
      kalır.
    - İki erişim de kalkınca kayıt silinir.
  - Dosya paylaşım sürümü tutulur. Paylaşım ya da tercih kaldırılınca alıcı o kaynaktan gelen
    defter verisini siler; eski sürümlü paketler reddedilir.
  - Kaynak bilgisi taşınır: alınan defter, alıcının büro kanalından yeniden başkasına aktarılmaz.
- **R9 PDF notları:** ayrı bir iş olarak, sonra. Gerekenler:
  - taşınabilir belge kimliği (içerik özeti + sürüm);
  - evrensel not kimliği, alan sürümleri, silme işareti;
  - dosya taşınması, aynı içeriğin iki kopyası, PDF içeriğinin değişmesi için eşleme kuralı.

  Bu planın kapsamında değil. `uets_document.note` hiç eşitlenmez (§1 C).
- **R10 Taşıma bütünlüğü ve yayılım:**
  - Paketler boyut sınırına göre bölünür; her paket parça kimliği, sıra ve toplam taşır.
  - Alıcı bütün parçalar gelince **tek işlemde** uygular ve uyguladığını bildirir. Eksik parça
    uygulanmaz; gönderen yeniden dener.
  - Başarısız aktarım başarılı sayılmaz.
  - Gelen veri birleştirildikten sonra içerik **ya da birleştirme metadatası** (sürümler, silme ve
    geri çekme işaretleri) gerçekten değiştiyse `changed` tetiklenir. Böylece A→B→C beklemez.
  - Karşılaştırma deterministiktir: sırasız küme ve listeler sıralanarak karşılaştırılır. Aktarım
    sürümleri yeniden üretmez.
- **R11 Finansal gizlilik sınıfı:**
  - Muhasebe toplamına katılmak ile para görme yetkisine tabi olmak ayrı kavramlardır.
  - Finansal sınıftakiler yetkiye tabidir: icra defteri, finansal öneri ve kararlar, kasa,
    kasaTekrar, banka, belge, ücret, hareket, `paylasilan_defter`.
  - Aynı politika gönderme, kabul, dosya indirme ve yetki kaybındaki temizlik için kullanılır.
- **R12 Atomik defter yazımı:**
  - Defter düzenlemesi ve türetilen hareketler (R3) tek servis komutudur.
  - Komut son kaydı yeniden okur, beklenen sürümü doğrular ve bütün yerel değişiklikleri tek
    veritabanı işleminde yapar.
  - Defter kaydı yazılamazsa hiçbir hareket yazılmaz. Diyalogdaki eski kopya yeni gelen değişikliği
    ezmez: sürüm uyuşmazsa "kayıt bu arada değişti" denir.

### 4.1 Yetenek matrisi

| Parça / kanal | Taşıdığı | Gereken yetenekler |
|---|---|---|
| Senkron `ajanda` | ajanda, süre kararları, temsil, müvekkil kartları, defter (kanonik), `CaseNote`, `CaseLink` | `hlc`, `alanSurumu`, `silmeOmru`, `defterIslemi`, `notGizli` |
| Senkron UYAP | UYAP kayıtları ve damgaları | bugünkü (değişmiyor) |
| Büro `muvekkil-buro` | paylaşılan kart, kart notu, kendi kayıtları, icra defteri | `hlc`, `alanSurumu`, `silmeOmru`, `defterIslemi`, `notGizli`, `geriCekme`, `oneri` |
| Büro `paylasilan-dosya` (defter yok) | UYAP kaydı, duruşmalar, ekler | `geriCekme` |
| Büro `paylasilan-dosya` + R8 defteri | yukarıdakiler ve kanonik defter | `geriCekme`, `defterPaylasimi`, `hlc`, `alanSurumu`, `silmeOmru`, `defterIslemi` |
| Görev paketi | görev, `caseExtras` (süreler, notlar) | `notGizli`, `geriCekme` |
| Öneri / karar | öneri ve karar kayıtları | `oneri`, `hlc` |
| Dosya isteği, soru kanalı | istenen kayıtlar | isteğin taşıdığı parçanın yetenekleri |

- Bölünmüş her aktarım ayrıca `paketBolme` ister. Bölünmesi gerekecek kadar büyük bir yük,
  `paketBolme` ilan etmeyen eşe gönderilmez.
- Öneri ve karar kanalındaki finansal yük, hedef kaydın kanalının yetenek şartlarını da devralır:
  finansal bir öneri `defterIslemi` ilan etmeyen eşe gönderilmez.
- Bir parçanın finansal alt yükü ayrı durdurulabilir. Örneğin `defterIslemi` ilan etmeyen eşe
  `muvekkil-buro`'nun kart ve not kısmı gider, icra defteri gitmez; ekranda nedeni yazar.
- Matristeki yetenekleri ilan etmeyen eşle ilgili satır durur; diğer satırlar sürer.
- Test: gereken yeteneklerden **yalnız biri eksik** olan eşe gönderme ve ondan kabul reddedilir.

## 5. Uygulama sırası (her adım ayrı test edilir, ayrı commit)

Her senaryo şunları yazar:
- cihazların rolünü (kendi cihaz, karar cihazı, meslektaş, R8 alıcısı) ve başlangıç verisini;
- beklenen **etkin ayakları** (kimlikleriyle), her cihazın hesap ve kasa tutarını;
- her cihazda izin verilen görünürlüğü.

Her senaryo ayrıca şunları doğrular:
- Kendi cihazlarda defter, kasa ve hesap aynıdır. R8 alıcısının kasası bilerek farklıdır ve öyle
  doğrulanır.
- Yalnız son toplam değil, mahsup bağlantıları ve **gerçekten dışa aktarılan yük** de denetlenir:
  gizli metin hiçbir ara pakette olmamalıdır.
- Küçük senaryolarda bütün teslim sıraları denenir. Büyüklerde rastgele sıra, tekrar ve kesinti
  kullanılır.

Kendi cihaz testleri en az üç cihazla (A, B, C: A→B→C yayılımı), büro testleri ayrıca bir meslektaş
cihazıyla (D) yapılır.

1. **Protokol, yetenek matrisi, HLC ve göç (R0, R2, R2.1):**
   - Biçim sürümleri, yetenek alışverişi, matris, parça başına durma ve ekrandaki neden.
   - HLC yardımcısı, kalıcı saat durumu, kaynak cihaz kimliği.
   - Deterministik göç, şema sürümü ve yedek.
   - Bu adım yeni yetenek ilan etmez; yalnız `hlc` hazır olunca onu ilan eder.
   - Testler:
     - eski sürüm eşle ilgili parça durur, diğerleri sürer;
     - ileri saat, saat geri alma, aynı milisaniyede çoklu yazım, yeniden başlatma;
     - **başka cihaza ulaşmış bir yazımdan önceki yedeğe dönüş**: yeni nesil, sürüm tekrarı yok;
     - aynı eski yedeğe iki kez dönüş; sayaç yazımı sırasında kesinti;
     - ofsetli zaman korunur, bozuk damga en eski sayılır, işlem tarihi değişmez;
     - aynı veritabanının farklı saat dilimlerinde göçü aynı sürümleri üretir;
     - göç tekrar çalıştırılınca bir şey değişmez.
2. **Bugünkü açıkları kapatmak (R11, R6'nın denetim kısmı, R4):**
   - İcra ve bütün finansal türler para yetkisine tabi; yetki kaybında tam temizlik.
   - Gelen elle ters/mahsup hedefinin sahiplik denetimi; hedefsiz ters bekleyen alanda.
   - Sahip olmayanın yazma yolları kapalı (öneri gelene kadar salt okunur).
   - `resmi` üçe ayrılır; görüntülemek yazmaz.
   - Testler:
     - para görmeyen üyeye icra gitmez;
     - yetki kaybında kasa, banka, belge de silinir;
     - meslektaşın tersi reddedilir;
     - hedefsiz ters toplamı etkilemez, hedef gelince doğrulanır;
     - ekranı açmak sürüm değiştirmez.
3. **Taşıma bütünlüğü ve yayılım (R10):**
   - Paket bölme, alıcının tek işlemde uygulaması ve onayı, yeniden deneme.
   - İçerik ve metadata karşılaştırmasıyla `changed`.
   - İlan: `paketBolme`.
   - Testler: 1 MiB üstü döküm; ortada kesilen aktarım; sırasız ve tekrarlanan parçalar;
     A→B→C yayılımı beklemeden.
4. **Finansal işlem modeli (R12, R3, R1'in defter kısmı, R5'in defter kısmı):**
   - Kanonik finansal veri, mahsup hedefinin kayıtta saklanması.
   - Türetilen hareketler, kasada tek ters.
   - Atomik yerel ve gelen uygulama, yaşam döngüsü, geri al.
   - Eski hareketlerin eşlenmesi; onarım raporu ve onaylı onarım.
   - İlan: `defterIslemi`, `silmeOmru` (defter için).
   - Testler:
     - iki cihaz farklı alan;
     - iki cihaz farklı tutar → tek etkin işlem;
     - çift ters → kasa bir kez;
     - her kesilme noktasında defter–kasa–hesap tutarlı;
     - silme + geri al → bir etkin işlem;
     - eski veriyle göç;
     - belirsiz çift → raporda, otomatik düzeltilmez;
     - aynı eski zaman, farklı tutar, iki teslim sırası → tek kazanan tutar, tek etkin işlem;
     - 100/40 kısmi mahsup göçü; birden çok mahsup; mahsuptan sonra tutar değişikliği ve silme;
     - 100 TL, 40 TL mahsup → sil → geri al: emanet ve mahsup aynı projeksiyon kimlikleriyle
       yeniden oluşur;
     - 100 TL emanete iki cihazda 60'ar TL mahsup, iki teslim sırası: aynı mahsup etkin, öteki
       askıda, toplamlar her cihazda aynı;
     - tutar 100→50 ile 80 TL mahsup yarışı: 80 askıda; tutar yeniden 100 olunca etkinleşir;
     - `v1` hiç alınmadan `v2` ve `v1`'e bağlı bir işlem alınması;
     - icradan doğan ayağa doğrudan elle ters reddedilir;
     - M1, M2 60'ar TL, iki farklı teslim geçmişi, ardından M1 silinir: yalnız toplamlar değil,
       her cihazda M2'nin etkin ayağı da aynı;
     - projeksiyon yeniden kurma iki kez çalıştırılınca bir şey değişmez;
     - göçte eski hareketlerin net etkisi uyuşan kayıtta toplam değişmez, uyuşmayan rapora gider;
     - rapordan sonra değişen küme → rapor yenilenir.
5. **Ajanda ve diğer kayıtlar (R1, R5):**
   - `agenda`, `deadline_user` (onay tek grup), müvekkil kartı, `CaseNote`, `CaseLink`,
     `case_representation` sürümleri.
   - İlan: `alanSurumu`, `silmeOmru` (ajanda için).
   - Testler: tamamlandı + başlık; silme + düzenleme; onay grubunun bütünlüğü; temsil eşitliği;
     kart damgalarının göçte korunması.
6. **Gizli not ve geri çekme (R7):**
   - Veri alanı, ekranda "Gizli not · büroyla paylaşılmaz" (önce maket, kullanıcı onayı).
   - Bütün kopyalama yollarında süzme, yönetilen kopyalar, kalıcı geri çekme, alıcı onayı.
   - İlan: `notGizli`, `geriCekme`.
   - Testler:
     - gizli not büroya, göreve, belgeye gitmez, kendi cihaza gider;
     - sonradan gizlenen not alıcıda silinir;
     - eski paket notu diriltmez;
     - gönderen "geri çekildi: n/m" görür;
     - A'nın gönderdiği not B'de gizlenir, alıcılar yine geri çekilir;
     - gizlenen notun metni eski öneri ve karar kayıtlarından silinir.
7. **Öneri, karar ve karar cihazı (R6):**
   - Değişmez öneri, ayrı karar, sabit karar cihazı, devir ve kayıp cihaz.
   - Atomik karar ve uygulama; gizlilik sınıfı.
   - Sahibin "Bekleyen öneriler" ekranı (önce maket, kullanıcı onayı).
   - Kart notu ve dosya notu da bu yoldan.
   - İlan: `oneri`.
   - Testler:
     - meslektaş düzenler → sahipte öneri;
     - onay → iki tarafta aynı;
     - red → değişmez;
     - eski öneri uygulanmaz;
     - karar cihazı dışından karar verilemez;
     - kayıp cihazdan sonra eski kararlar ve **çıktıları** reddedilir;
     - kabul edilmiş bir çıktının sonradan geri alınması finansal türetmeyi de yeniler; arada
       başka yazım varsa çatışma kaydı yazılır;
     - eski cihazda uygulanmış ama ulaşmamış onay, yeni cihazda red ya da onay; seçim, karar ve
       çıktıların bütün teslim sıraları;
     - para yetkisi olmayan üye açık kart notu önerebilir, finansal öneri yapamaz.
8. **Paylaşılan dosyada defter (R8):**
   - "Folio hesabını da paylaş" tercihi (maket), alıcı kesişimi, ayrı salt okunur görünüm.
   - Paylaşım sürümü, geri çekme, yeniden aktarma engeli, tekilleştirme.
   - İlan: `defterPaylasimi`.
   - Testler:
     - alıcının genel hesabı ve kasası etkilenmez;
     - para yetkisi olmayan alıcıya gitmez;
     - yetki kaybı ve tercih kapatma veriyi siler;
     - eski paket veriyi geri getiremez;
     - kart paylaşımıyla birlikte gelince tek kayıt;
     - yalnız R8 → ikisi birlikte → yalnız R8 → hiçbiri: her geçişte görünürlük ve genel toplamlar
       ayrı doğrulanır.
9. **Uçtan uca denetim:** A, B, C kendi cihazlar ve D meslektaşla bütün senaryolar; sonuç bugünkü
   test tabanıyla karşılaştırılır. Codex denetimi, düzeltmeler, tam test, push.

PDF notlarının eşitlenmesi (R9) bu sıranın dışında, ayrı bir iştir.

## 6. Dikkat

- `dart format` yalnız değişen dosyalara verilmeli. `lib/services` gibi klasöre verilince ilgisiz
  dosyaları da biçimlendiriyor: `system_font_catalog.dart`, `uyap_pace.dart`, `clients_page.dart`,
  `portfolio_rows.dart`, `editor_widget.dart`.
- Üretilen eklenti dosyaları commitlenmez:
  - `macos/Flutter/GeneratedPluginRegistrant.swift`
  - `windows/flutter/generated_plugin_registrant.cc`
  - `windows/flutter/generated_plugins.cmake`
- Codex: `codex exec -m gpt-6.1-sol -s read-only -C <repo> -o <çıktı> "<talimat>"`. Talimat dosyası
  repo dışındaysa okuyamayabiliyor; talimatı komutun içine koy.
- UI değişikliklerinde önce maket gösterilir, onaydan sonra uygulanır.

## 7. Codex denetimleri

- **1. denetim (14 Ekim, REVISE, 17 bulgu):** Bu sürümde işlenenler:
  - §1 düzeltmeleri: bütün döküm yalnız ajanda/müvekkil parçasında; 30 sn bir hız sınırı;
    `client.dart` yolu; `uets_document.note` kullanıcı notu değil; kasada çift ters.
  - Yeni riskler 3–6 ve 12–14.
  - Yeni kurallar R0, R11, R12; HLC (R2); finansal işlem modeli (R3); alan grupları (R1); silme
    yaşam döngüsü (R5); değişmez öneri, ayrı karar ve karar cihazı (R6); `notGizli` ve geri çekme
    (R7); R8 kapsamı; R9'un ayrı iş olması.
  - Güvenli sıra (§5).
  - Açık soruların ikisi kullanıcı kararıyla kapandı (§3 karar 1 ve 4).
- **2. denetim (14 Ekim, REVISE, 14 bulgu):** Kapanmış saydıkları:
  - `uets_document.note` ayrımı;
  - kasa hatasının tespiti;
  - görüntülemenin yazmaması;
  - PDF notlarının ayrılması;
  - R8 kapsamı.

  Bu sürümde işlenenler:
  - Deterministik göç (sabit +03:00, `goc` kaynağı, kart damgalarının korunması), R2.1.
  - HLC algoritması, kalıcılığı ve garanti sınırı (R2).
  - İşlem ve ayak kimlikleri; kanonik finansal veri.
  - **İcradan doğan hareketlerin senkronla gitmeyip türetilmesi** (R3).
  - Gelen birleşimde atomik türetme; silme ve geri alın para etkisi (R5).
  - Eski hareketlerin eşlenmesi, sürümlü onarım raporu.
  - Sabit karar cihazı, devir ve kayıp cihaz; atomik karar ve uygulama; öneri gizlilik sınıfı (R6).
  - Yönetilen kopyalar ve kalıcı geri çekme (R7).
  - Yetenek matrisi ve bütün kanallar (R0, §4.1).
  - R8'in ayrı salt okunur görünüm olması.
  - Bekleyen ters alanı.
  - `resmi`'nin üçe ayrılması (R4).
  - Taşıma bütünlüğünün öne alınması ve son durum testleri (§5).
- **3. denetim (14 Ekim, REVISE, 10 bulgu):** R3'ün temel yönünü (finansal etkiyi kanonik veriden
  türetmek) doğru buldu.

  Bu sürümde işlenenler:
  - İşlem kimliğine içerik özeti ve nesil.
  - Kısmi ve çoklu mahsup için kayda bağlı mahsup listesi. İcradan doğan ayaklara doğrudan elle
    işlem yasağı. Eski kimlik eşleme tablosu.
  - Karar çıktılarının seçim neslini taşıması; geçersiz kararın çıktılarının reddi ya da geri
    alınması.
  - Matriste finansal yetenekler ve `paketBolme`; finansal alt yükün ayrı durması.
  - R8'de erişim kaynakları ve muhasebe projeksiyonunun ayrılması.
  - Yedekten dönüşte yazım nesli (R2).
  - Göçün kapsamı (yalnız ofsetsiz damga, bozuk damga, işlem tarihi korunur).
  - Üç ayrı sürüm (finansal, yaşam döngüsü, mahsup).
  - Geri çekme takibinin kendi cihazlarda eşitlenmesi, eski kopyalar ve öneri metinleri.
  - Kesin senaryo beklentileri (§5).
- **4. denetim (14 Ekim, REVISE, 2 kritik):**
  - Kapanmış saydıkları: içerik özetli kimlik, karar çıktılarının seçim nesli, matristeki
    finansal yetenekler, R8'de erişim ve muhasebe ayrımı, yedekten dönüşte nesil.
  - Kalan iki açık mahsuptaydı. Bu sürümde işlenenler:
    - muhasebe bağlamı ve mahsubun kalıcı kimliği ile ayağının kimliğinin ayrılması (silme ve
      geri almada mahsup geri döner);
    - emaneti aşan mahsuplar için her cihazda aynı sonucu veren **etkin durum** kuralı ("askıda"
      mahsup).
  - Öneriler de işlendi: dış sayacın tek yönlü ilerlemesi, çıktı geri almada finansal yenileme,
    öneri kanalında yetenek devri.
- **5. denetim (14 Ekim, REVISE, 1 kritik):**
  - Önceki iki bulguyu kapanmış saydı. Bunun dışında engelleyen açık bulmadı.
  - Kalan açık: askıdan çıkan bir mahsup, bir cihazda daha önce terslenmiş aynı ayak kimliğine
    dönüyor ve geri gelemiyordu.
  - Bu sürümde: icradan doğan hareketler **kalıcı olay değil, yeniden kurulabilen
    projeksiyon**. Ters kayıt yazılmıyor, iz ayrı defter geçmişinde. Göçte eski hareketlerin net
    etkisi projeksiyona devrediliyor.
- **6. denetim (14 Ekim, APPROVED):**
  - Projeksiyon modeli önceki bulguyu kapattı. R1, R5, R6, R8, R11, R12 ve mevcut hesap ve kasa
    hesaplamalarıyla tutarlı bulundu.
  - Üç önerisi işlendi: göçte net etkinin bileşen bileşen karşılaştırılması; defter geçmişine
    R11 ve R7 kurallarının uygulanması; geri almada projeksiyon kimlikleri.
- **Adım 4 kod denetimi (14 Ekim, REVISE, 9 kritik, 5 uyarı, 1 öneri):**
  - Kritikler: gelen HLC'nin saati ilerletmemesi; meslektaşın defterine karttan yazılabilmesi;
    göçün yeniden çalışınca başarılı kaydı onarıma düşürmesi; onarım onayının veri kümesini
    kanıtlamaması; bileşen bazlı karşılaştırmanın eksikliği; sürümsüz kayıtta çift sayım; eski
    kimlik eşlemesinin taşınmaması; projeksiyona ters yazma yasağının depoda ve birleşimde
    uygulanmaması; sürüm denetiminin eşit sürümlü içerik değişikliğini kaçırması.
  - Uyarılar: finansal grup eksikliği; elle UYAP onayının finansal sürüme bağlı olmaması; defter
    izinin tutulmaması; başarısız yazımın başarılı görünmesi ve erken bildirim; eski sürümle
    sessiz durma ve askı/onarım için kullanıcı yolu olmaması.
  - Öneri: büyük veri kümesinde projeksiyon okuma ve göç maliyeti.
  - Hepsi işlendi (§0 adım 4); her biri `test/sync_step4_test.dart` "Codex's review of step 4"
    grubunda, ekranlar `test/sync_step4_screens_test.dart`'ta denenir.
- **Adım 4 kod denetimi, 2. tur (14 Ekim, REVISE):** 15 bulgudan 5'i kapandı, 10'u kısmen; 6 yeni
  bulgu. Bu sürümde işlenenler:
  - İki eski biçimli kopya birleşince yeni biçime çevrilmez; sonraki kazanır ve tartılır (çift
    sayım kapandı). Burada eski, gelen yeni biçimdeyse eski hareketler kenara alınır.
  - Gelen eşleme (`defterEski`), defteri burada yeni biçimde olan eski hareketi de hesaptan
    çıkarır (`_retireMapped`). Bürodan gelen eşleme, yalnız yazanın defterleri için alınır.
  - Onarım bekleyen defterin eski hareketine mahsup ve ters yazılamaz; geç gelen parça oluşmaz.
  - Onarımı yalnız yazan yapar; şerit yalnız kişinin kendi raporlarını gösterir; onarım geçmişe
    yazılır.
  - `resmiKararSurum` `resmiKarar` grubunda birleşir; eski elle söz göçte o anki finansal sürüme
    bağlanır.
  - Ters kayıtlar zincir boyunca rapora girer; türü düzelttiğinden farklı ters rapora gider.
  - Bekleyen ters başka dosyanın hareketine bağlanamaz.
  - Paylaşım geri çekilince bekleyen kayıtlar, defter geçmişi ve raporu da silinir.
  - Rapor tutarları vekâlet ve karşı vekâlet ayrı; başka müvekkil, dosya ya da para birimi
    karışınca tutar gösterilmez. Askı yazısı emanette kalanı gösterir.
  - Açık bırakılanlar: icra ekranında kayıtların her ödeme için yeniden okunması (performans);
    büro cihazlarının duran parçasının Senkron sayfasında gösterilmesi; adım 4'ün ara
    sürümünde kabul edilmiş ileri saatli kayıtlar (bu sürüm yayımlanmadı).
- **Adım 5 kod denetimi (14 Ekim, REVISE, 3 kritik, 5 uyarı, 1 öneri):** Bu sürümde işlenenler:
  - Ekranda eski kalmış kopya: `AgendaItem`, `DeadlineUser` ve `Client` okundukları hâli (`base`)
    taşır; kaydederken yalnız o hâle göre değişen gruplar şimdiki kayda uygulanır. Arada başka
    cihazdan gelen başlık, kaldırma ya da telefon ezilmez; kaldırılmış süre sıradan düzenlemeyle
    dönmez. `base` olmadan yapılan yeni kararlar boş karara göre tartılır.
  - Saat: kayıtlı satırın, kartın, notun ve bağın sürümleri (damgadan türetilenler de) yerel
    yazımdan önce saate işlenir; ileri saatli eski satır silinince geri dönmez.
  - `confirmed_day` onay grubunda; aynı sürümde gün yalnız birinde varsa ikisine de o gider, iki
    farklı gün her cihazda aynı seçilir; doldurma yeni sürüm üretmez, döngü yok.
  - Dosya notu ve bağı: niyet okunan kopyadan anlaşılır, fiziksel saat yazımı reddetmez.
  - Yeni kartın alanları, notları ve bağları bu cihazın kaynağıyla, kendi zamanlarından sürüm alır.
  - Ad ve katılan kart kümeleri, okunan kopyaya göre eklenen ve çıkarılanla şimdiki kayda
    uygulanır; `sharedOnce` birleşir, sahip korunur.
  - Temsil değişikliği tebligatsız dosyada da "değişti" sayılır (yayılım).
  - Şema adımı 3 (`alan-surumleri`): yedek, yeni biçimde ilk yazımdan önce alınır; boş sütunlar
    açılışta eklenir, eski Folio onları okumaz.
  - Testler silinen satırların içeriğini ve sürümünü de karşılaştırır.
  - Bilinen sınır: aynı ekran nesnesinden üst üste iki kayıtta, aradaki uzak değişiklik ilk
    kaydın değiştirdiği alanda ezilebilir; ekranlar her kayıttan sonra yeniden okur.
- **Adım 6 plan denetimleri (14 Ekim, üç tur, REVISE):**
  - 1. tur (15 bulgu): gizli başlığın takvime ve süreye sızması, paketlemeden sonra gizlenen not,
    teslim geçmişi, kendi cihaz yayılımı, cihaz başına onay, kimliksiz eski paketler, yetki, R6.
  - 2. tur (12 bulgu): donmuş not kopyasının yol açtığı yarım aktarım, yeniden deneme, aktarım
    başına yetenek, tombstone, fiziksel kopya sahipliği.
  - 3. tur (9 bulgu): canlı durum yönü doğru bulundu; liste sürümünün en büyük sürümle
    sıralanamaması, gizlemenin `govde` grubuyla karşılaştırılması, kapanan görev, kapsam başına
    onay, olası alıcı, eski kuyruk, kalıcı temizlik, yetkiden bağımsız kart geri çekmesi.
    Kullanıcının isteğiyle bunlar uygulamada karşılandı (not not birleşim, açık işaretler,
    `govde` karşılaştırması, kapsamlı `note_hold`, kalıcı temizlik durumu, metinsiz `kartGizli`).
- **Adım 6 kod denetimi (14 Ekim, REVISE, 7 kritik, 2 uyarı):** Bu sürümde işlenenler:
  - İcra belgesi açıklamanın gizliliğini kalıcı gizleme kaydıyla da belirler
    (`SecretNotes.descriptionHidden`, `LedgerEntry.noteHidden`).
  - Alıcıda gizleme (`gizlenen`) ve silme (`silindi`) ayrı ve bağımsız tutulur; boş kayıtta da en
    yeni silme sürümü saklanır; habersiz cihazın eski listesi diriltemez.
  - Eski paket temizliği üç durumlu (`bekliyor`, `temizlenecek`, `tamam`); yalnız `tamam` ya da hiç
    eski paket yoksa "temiz" bildirilir; açılışta yarım kalanlar yeniden denenir.
  - Kapanan ya da geri alınan görevlere de metinsiz gizleme ve silme işareti gider; eski paketleri
    temizlenir.
  - Görev dosyası gönderim sınırında notsuz biçime getirilir; getirilemezse o paket bekler. Göç bir
    dosyada hata alırsa bitmiş sayılmaz.
  - Gizlilik yazımı ile gizleme kaydı aynı işlemde; iç içe işlem güvenli.
  - Takip değişiklikleri kendi cihazlara (`ownChanged`), kendi cihazdan gelen gizleme büroya
    (`officeChanged`) hemen yayılır; değişiklik yoksa tetik yok.
  - Alınan görev notları `not-takibi` ile kişinin diğer cihazlarına gider.
  - Meslektaşın kartında not alanı salt okunur; kayıttan sonra kart veritabanından yeniden okunur.
- **Adım 6 kod denetimi, 2. tur (14 Ekim, REVISE: 4 kapandı, 5 kısmen, 2 yeni kritik):** işlenenler:
  - Belge, açık ekranın eski nesnesiyle değil, kayıt yeniden okunarak üretilir.
  - Eski paket temizliği sürümlü bildirilir (`task_note_clean.surum`, `eskiSurum`); veren en son
    bildirimi tutar, sonradan gelip temizlenemeyen paket eski "temiz" onayını geçersiz kılar.
    Temizlik yalnız gerçekten yazılacak dosya varsa durum değiştirir (döngü yok).
  - Kapanan görevin işareti alıcıda o kapsamın notlarını hemen düşürür.
  - Kart notu alıcıları ve alınan görev notları değişince kendi cihazlara hemen yayılır.
  - Kendi cihazdan gelen görev notları, oradaki eski paketin temizliğini başlatır (`cleanKnown`).
  - Bir kişiye gönderilen not, o kişinin büro defterindeki bütün cihazlarında "olası" sayılır;
    kişi ancak bütün cihazları uygulayınca tamamlanır.
- **Adım 7 kod denetimi (14 Ekim, REVISE, 9 kritik, 1 uyarı):** Bu sürümde işlenenler:
  - Normal devir ile kayıp cihaz ayrı: devirde bütün önceki kararlar geçerli kalır (`known`
    birikir); yalnız kayıp seçimden (`lostAt`) önceki, o an bilinmeyen kararlar geçersizdir.
  - Eşit nesilli iki seçimde her cihazda aynı kazanan (cihaz kimliği); kazanandan başka cihazın o
    nesildeki kararı geçersiz.
  - Kararlar arasında `supersedes`: aynı kararın geçersiz/çatışmalı hâli, yoksa daha yeni nesil ve
    zaman kazanır; eski geçersizlik yenisini ezmez. Büroda ve kendi cihazlarda aynı kural.
  - Geçersiz kararın çıktısı grup grup, sürümüyle geri alınır; ilgisiz grup değişikliği engellemez;
    henüz gelmemiş çıktı ve sonradan gelen çıktı `blocked_output` ile hiç alınmaz (kart notu, dosya
    notu, defter grupları). Not geri alınırken gizliliği ve yazanı korunur.
  - Çatışma kalıcı (`catisma`), eşitlenir ve "Bekleyen öneriler"de "kayda elle bakın" olarak
    görünür.
  - Not gizlenince ilgili önerilerin metni silinir (sahipte ve önerende); sonradan gelen öneri de.
  - Öneri, ekranın gösterdiği sürümlerle yapılır.
  - Kalıcı kimliği olmayan cihaz karar veremez, seçilemez.
- **Adım 7 kod denetimi, 2. tur (14 Ekim, REVISE: 6 kapandı, 4 kısmen, 4 yeni kritik):** işlenenler:
  - Geçerli olmayan kararın değişikliği, hangi karar duruyor olursa olsun bir kez geri alınır ve
    engellenir (`_karar` işareti); duran geçerli karar silinmez.
  - Her neslin seçilen cihazı (`kazananlar`) saklanır ve birleşir; o nesilde başka cihazın kararı,
    sonraki devirden sonra da geçerli değildir.
  - Not gizlenince yalnız gizlenen sürümü görerek yapılmış önerilerin metni silinir; silinen öneri
    uygulanamaz (`temizlendi`); yeniden açılan notun yeni önerisi korunur.
  - Geri alma kararın değiştirdiği mahsupları da sürümleriyle geri alır ve engeller; "UYAP'ta var"
    bağı geri dönen finansal sürüme taşınır.
  - Çatışmanın "Tamam"ı cihazda yerel; gelen kayıt onu yeniden açmaz.
  - Açık kalan uyarılar: devrin hedefte alındığının onayı ve devir hedefinin kalıcı kimliği.

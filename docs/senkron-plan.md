# Senkron planı: kendi cihazlar ve büro ağı, birbirini ezmeden (14 Ekim 2026)

Bu belge, kullanıcının kendi cihazları arasındaki eşitlemenin (Senkron) ve büro ağı eşitlemesinin
bugünkü hâlini, ezme risklerini, verilen kararları ve uygulama planını tutar. Başka bir bilgisayardan
(ofisten) bu belgeyle devam edilir. UYAP okuma tarafı ayrı belgededir:
[uyap-hedef-harita.md](uyap-hedef-harita.md).

## 0. Nereden devam edilecek

- UYAP okuma işi (hedef harita §1–§12) bitti ve `main`'de: son commit `9ca3f97`. Ertelenen UYAP
  maddeleri hedef harita §12'de.
- Bu belgedeki senkron işi **henüz başlamadı**. Sıradaki adım: §5'teki planı Codex'e denetletmek
  (gpt-6.1-sol, salt okunur), sonra §5 sırasıyla uygulamak.
- Bilinen, bu işten önce de kırık olan testler: codex_recheck, dropped_files, ocr_test,
  office_transfer (zamana bağlı), shared_directory, task_package, uets_connect, uyap_case_test,
  uyap_connect, uyap_door, uyap_library, uyap_web_service "send gate", viewer_registration,
  editor_drafts (Windows geçici klasör kilidi). Tek başına geçen zamana bağlı olanlar: secret_store,
  live_share, folder_sync, swipe_pages, petition_format.

## 1. Bugün nasıl çalışıyor

### Genel mekanizma

- **Kendi cihazlar (Senkron):** Her turda her parçanın **bütün dökümü** gönderilir, fark değil
  (`office_network.dart:812-847`, `:1049-1061`; `{'t':'senkron','parcalar':…}`).
  - Ne zaman çalışır: kendi cihaz görülünce (en çok 30 sn'de bir, `:2805-2807`) ve yerel bir
    değişiklikten 3 sn sonra (`ownChanged`, `:736-739`; `PortalDatabase.changed`,
    `own_sync.dart:431-436`).
  - Gelen veriyi birleştirmek `changed` tetiklemez: A→B→C yayılımı B'nin bir sonraki tetiğini bekler.
- **Büro ağı:** her `officeParts` parçası alıcı üye için dışa aktarılır, gönderen cihaz kimliğiyle
  birleştirilir (`office_network.dart:487-522`, `:996-1012`).
  - İki parça var: `paylasilan-dosya` (SharedCases, her zaman açık; `own_sync.dart:291-295`) ve
    `muvekkil-buro` (isteğe bağlı, varsayılan kapalı; `own_sync.dart:64-65`, `:363-417`).
- **Sürüm bilgisi yok:** kayıtlarda sayaç, vektör saat ya da cihaz kimliği yok. Her şey duvar
  saatine bağlı ve **saat dilimsiz yerel saat** (`DateTime.now().toIso8601String()`):
  - `agenda.updated`, `agenda_removed.at`, `deadline_user.updated`, `case_representation.updated`
  - `client.updated` ve alan başına `stamps`/`alanZamani` (`client.dart:45-48`, `:292-295`)
  - `client_record.updated` (`client.dart:503`, `:525`)
- `cases_revision`, `clients_revision` yalnız yerel önbellek sayaçlarıdır.

### A. İcra haricen tahsilat / feragat (`EnforcementLedger`)

- **Saklama:** `client_record`, `kind='icra'` (`client.dart:447`). Alanlar `data` içinde: `dosya, tur,
  tutar, zaman, borclu, odeme, aciklama, tamami, uyapBakiye, bildirildi, resmi`. `clientId` dosyanın
  müvekkil kartı, kart yoksa `officeCashId='buro'` (`enforcement_view.dart:257-279`).
- Para sayılmaz (`client.dart:462-468`). Defter kaydı ayrıca **kilitli** `hareket` kayıtları yazar,
  `'kaynak':'icra:<entryId>'` (`enforcement_view.dart:316-338`); kilitli kayıtlar hiç ezilmez
  (`portal_clients.dart:67-71`, `:500`).
- **Düzenle / sil / bildirildi:** `saveClientRecord(copyWith(...))`, `updated=now`
  (`enforcement_view.dart:454`, `:904-922`, `:953`). **Silme:** `silindi:true` işareti (`:953`).
  Para hiç silinmez; geri alma `'ters'` işaretli yeni kayıttır (`:391-415`).
- **Kendi cihazlar:** ajanda parçasının içinde gider (`_agendaExport` → `clientsExport()`,
  `portal_database.dart:1264`; `agendaMerge` → `clientsMerge`, `:1466-1474`).
  - Kural: kayıt kimliği başına **bütün kayıt, son yazan kazanır** (`portal_clients.dart:499-503`).
    Gelen kayıt yalnız `updated` daha yeniyse ve yerel kayıt kilitli değilse yerine geçer.
  - Alan birleştirme yok. Eşitlikte yerel kalır.
- **Büro:** yalnız `muvekkil-buro` açıksa ve kart paylaşılmışsa (`c.office`). `officeCashId`
  kayıtları yalnız parayı görebilenlere gider (`portal_clients.dart:365-374`).
  - Herkes yalnız `rec.person == me` kayıtlarını gönderir.
  - Alırken yalnız `r.person == author` ve yerel kopya aynı kişi/müvekkil/türdeyse kabul edilir
    (`:487-498`); sonra aynı son-yazan-kazanır kuralı.
  - **Dosya paylaşmak (SharedCases) defter kayıtlarını göndermez**: yalnız UYAP kaydı, duruşmalar ve
    ekler gider (`shared_cases.dart:161-194`). Meslektaş UYAP'ın borcunu görür, Folio'daki kalanı
    (`folioLeft`) görmez.

### B. Ajanda

- **Saklama:** `agenda` tablosu (`portal_database.dart:148-152`), silinenler `agenda_removed(id, at)`
  (`:238`). Tebligat süreleri ajanda satırı değil: tamamlandı/gün/başlık `deadline_user`
  (`:1120-1140`, `:1210-1216`, `:2160-2179`).
  - `saveAgenda` bütün satırı yazar (`INSERT OR REPLACE`, `:1190-1206`). Tamamlandı işareti
    `copyWith(done:…)` ile `updated=now` (`agenda_page.dart:461`; `portal_database.dart:84-101`).
- **Kendi cihazlar:** `ajanda` parçası, varsayılan açık (`own_sync.dart:335-362`). Gönderilenler:
  `satirlar`, `silinen`, `kararlar` (deadline_user), `secimler` (deadline_choice), `temsil`
  (case_representation), müvekkil verisi (`portal_database.dart:1236-1265`).
  - **Silme işaretleri:** gelen silme, yerel satırı yalnız yerel `updated <= silme zamanı` ise siler
    (`:1330-1347`).
  - **Satırlar:** gelen satır yerel silme işaretinden yeni değilse atlanır (`:1352`); daha yeniyse
    uygulanır; eşit zamanda sütunların JSON'u büyük olan kazanır (`:1290-1326`, `:1353`).
    **Bütün satır yerine geçer** (`:1356-1372`).
  - `deadline_user`: aynı kural (`:1375-1415`). `deadline_choice`: yalnız eklenir (`:1417-1432`).
    `case_representation`: kesin daha yeni kazanır, eşitlikte karar yok (`:1433-1456`).
  - Silme işaretleri hiç budanmaz.
- **Büro:** ajanda parçası yok. Ama `TaskPackage.caseExtras` dosyanın ajandasının düz kopyasını
  taşır: `sureler`, ve `notlar` = süre olmayan her satırın türü, başlığı, gövdesi, tarihi, tamamlandısı
  (`task_package.dart:165-207`).
  - Bu kopya görev paketleriyle gider (`:137`; görev sayfasında salt okunur,
    `tasks_page.dart:1150-1161`) ve dosyanın paylaşıldığı **her üyeye** gönderilir
    (`shared_cases.dart:182`). Paylaşılan dosyada alıcı onu atar (`adoptChecked` yalnız
    `UyapCaseRecord`'u okur, `uyap_case_store.dart:323-342`), ama veri yine de gönderilmiş olur.
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
| Tebligat evrak notu `uets_document.note` | `portal_database.dart:187`, `:1598-1616` | **eşitlenmiyor** | hayır |
| PDF üzerindeki notlar | `index_database.dart:99-103`, `:369` | **eşitlenmiyor** | hayır |

- **Büroda kart birleştirme:** kartı yalnız sahibinin değişikliği değiştirir
  (`c.person == from && kept.person == from`), alan alan (`portal_clients.dart:394-433`).
- **Paylaşımı kaldırmak:** yalnız kimlik işareti gider; alıcı başkalarının kayıtlarını **sert siler**
  (işaret bırakmadan), kendisininkileri tutar (`portal_clients.dart:401-426`, `:505-513`). Para görme
  yetkisini kaybetmek de başkalarının para kayıtlarını sert siler (`own_sync.dart:480-498`;
  `portal_clients.dart:125-134`).
- **Hiçbir not "özel" diye işaretlenemiyor.**

## 2. Ezme ve tutarsızlık riskleri

1. **Haricen tahsilatta alan kaybı:** A cihazında `aciklama`, B'de `bildirildi` değişirse daha geç
   `updated` kazanır, öteki kaybolur.
2. **Ekran açılınca yazma:** `_loadBooked`, icra görünümünü açan cihazda `resmi` alanını yazıp
   `updated`'ı tazeliyor (`enforcement_view.dart:164-171`). Başka cihazdaki, henüz gelmemiş eski
   tarihli elle düzenlemeyi sessizce ezebilir.
3. **Çift para hareketi:** aynı kaydı iki cihazda düzenlemek iki `_unbook`/`_bookLedger` çalıştırır.
   Eski hareketin iki ters kaydı zararsız (`client_accounts.dart:149-154`'teki `taken` kümesi), ama
   **iki yeni `icra:<id>` hareketi** birlikte kalır: müvekkil hesabı ve kasa iki kez düşer, defter
   satırı tek tutarı gösterir.
4. **Büroda sahiplik yok:** `enforcement_view.dart`'ta `person` denetimi yok. Meslektaş sahibin
   kaydını düzenler ya da silerse değişiklik yerelde kalır (`person` sahip olduğu için hiç
   gönderilmez), ama yeni yerel `updated` sahibin daha eski zamanlı düzenlemelerini engeller.
   Meslektaşın ters ve yeniden yazma hareketleri (`person` = meslektaş) ise gönderilip kabul edilir ve
   sahibin hesaplarını bozar.
5. **Ajandada alan kaybı:** A'da tamamlandı, B'de başlık değişirse biri kaybolur. Silmeden sonra başka
   cihazda yapılan düzenleme satırı geri getirir.
6. **Kart notunda ayrışma:** meslektaş paylaşılan bir kartın notunu ya da dosya notunu değiştirirse
   yerelde yazılır, hiç gönderilmez (`mine(c.person)` yanlış, `portal_clients.dart:344`, `:353`);
   yerel alan zamanı daha yeni olduğu için sahibin eski zamanlı güncellemeleri reddedilir. İki taraf
   sahip yeniden yazana kadar ayrışık kalır.
7. **`case_representation` eşitliği:** eşit zamanda yerel kalır; cihazlar ayrışabilir.
8. **Saat:** saat dilimsiz yerel zaman; saati ileri olan cihaz her çakışmayı kazanır.
9. **Gizlilik:** paylaşılan dosya ve görevle dosyanın bütün ajanda notları gider; "gizli" işareti yok.

## 3. Kararlar (kullanıcı, 14 Ekim 2026)

1. **Notların varsayılanı senkron durumuna bağlıdır:** Senkron açıksa notlar kendi cihazlara; büro
   paylaşımı açıksa (paylaşılan dosya/kart, görev) büroya da gider. Gizli kalması gereken not
   **"gizli not"** olarak eklenir; gizli not büroya hiç gitmez.
   - *Açık soru:* Gizli not kullanıcının kendi diğer cihazlarına gitsin mi? Öneri: evet (aynı kişi),
     yalnız büroya ve görev paketine gitmez. Uygulamadan önce kullanıcıya teyit ettir.
2. **Başkasının tahsilatı:** büroda meslektaş sahibin defter kaydını doğrudan değiştiremez; yaptığı
   değişiklik (düzenleme ya da silme) sahibe **öneri** olarak gider, sahip onaylarsa uygulanır,
   reddederse düşer. Öneriyi yapan, sonucunu görür.
3. Plan uygulanmadan önce Codex'e denetletilir.

## 4. Hedef kurallar

- **R1 Alan alan birleştirme:** defter kayıtları (`client_record` icra) ve ajanda satırları için her
  alanın kendi değişiklik zamanı (müvekkil kartındaki `stamps` gibi). Gelen kayıt yalnız kendi daha
  yeni alanlarını değiştirir.
- **R2 Zaman ve eşitlik:** yeni zamanlar UTC (`toUtc().toIso8601String()`), eşitlikte cihaz kimliği
  kesin karar verir. Eski saat dilimsiz zamanlar yerel saat sayılıp okunur.
- **R3 Tek para hareketi:** bir defter kaydının kasaya/müvekkil hesabına düşen hareketi, kayıt
  kimliğinden türetilen kimliği taşır (`icra:<entryId>:<tutar sürümü>`); iki cihazın aynı anda yazdığı
  hareketler aynı kimlikte birleşir. Mevcut çiftler onarılır (aynı `kaynak` ile iki ayakta hareket →
  biri ters kayıtla kapatılır).
- **R4 Görüntülemek yazmaz:** `resmi` her açılışta hesaplanır, kaydedilmez; ya da kaydedilirse
  `updated` ve alan zamanı değişmez.
- **R5 Silme:** silme bir alan gibi zamanlıdır (`silindi` + zamanı); silmeden sonra başka cihazda
  yapılan düzenleme satırı geri getirmez, "Geri al" açık bir işlemdir.
- **R6 Sahiplik ve öneri:** defter kaydının sahibi `person`. Sahip olmayanın Düzenle/Sil'i bir
  `oneri` kaydı yazar (`kind='oneri'`, hedef kayıt, önerilen alanlar ya da silme, öneren, zaman); öneri
  büro ağıyla sahibine gider. Sahibin ekranında "Bekleyen öneriler": Onayla (sahibin düzenlemesi
  olarak uygulanır) / Reddet. Sonuç öneriyi yapana geri gider. Kart notu ve dosya notu için aynı yol
  (bugünkü ayrışma, risk 6).
- **R7 Gizli not:** ajanda notu, süre gövdesi, dosya notu (`CaseNote`), müvekkil kartı notu ve defter
  açıklaması için `gizli` işareti. Gizli olan `caseExtras.notlar`'a, görev paketine, paylaşılan
  dosyaya ve `muvekkil-buro` dışa aktarımına girmez. Senkron açıksa gizli olmayan notlar R1 kurallarıyla
  gider.
- **R8 Paylaşılan dosyada defter:** dosya paylaşılınca defter kayıtları da (salt okunur, R6 önerisiyle)
  gider, böylece meslektaş Folio'daki kalan borcu görür. *Teyit ettir:* müvekkil kartı paylaşılmadan da
  gitsin mi? (Para görme yetkisi kuralları geçerli kalır.)
- **R9 Eşitlenmeyen notlar:** `uets_document.note` ve PDF notları kendi cihazlar arasında eşitlenir
  (büroya gitmez), R1 kuralıyla.
- **R10 Yayılım:** gelen veri birleştirildikten sonra, gerçekten bir şey değiştiyse `changed`
  tetiklenir (A→B→C beklemesin); döngüye girmemesi için yalnız içerik değiştiğinde.

## 5. Uygulama sırası (her adım ayrı test edilir, ayrı commit)

1. **Altyapı (R2):** UTC zaman yardımcısı, cihaz kimliğiyle eşitlik kararı; eski zamanları okuma.
   Test: saat farkı ve eşitlik senaryoları.
2. **Defter alan alan (R1, R4, R5):** `client_record` icra için alan zamanları (`alanZamani`), göç
   (eski kayıtta bütün alanlar `updated` zamanını alır), `clientsMerge` alan birleşimi, `_loadBooked`
   yazmasının kaldırılması, silme zamanı. Test: iki cihaz farklı alan; düzenleme-silme yarışı.
3. **Tek para hareketi (R3):** kimlik türetme, birleşimde aynı kimlik, mevcut çiftlerin onarımı.
   Test: iki cihaz aynı anda düzenler → kasa bir kez düşer.
4. **Ajanda alan alan (R1, R5):** `agenda` ve `deadline_user` için alan zamanları, göç, birleşim;
   `case_representation` eşitliğinde kesin karar. Test: tamamlandı + başlık; silme + düzenleme.
5. **Gizli not (R7):** veri alanı, ekranda "Gizli not" işareti, dışa aktarımlarda süzme
   (`caseExtras`, görev paketi, `muvekkil-buro`, paylaşılan dosya). Test: gizli not büroya gitmez,
   kendi cihaza gider (karar 1'in açık sorusuna göre).
6. **Sahiplik ve öneri (R6):** `oneri` kaydı, büro ağıyla gönderim, sahibin onay/red ekranı (önce
   maket, kullanıcı onayı), sonuç bildirimi; kart notu ve dosya notu da bu yoldan. Test: meslektaş
   düzenler → sahipte öneri; onay → iki tarafta aynı; red → değişmez.
7. **Paylaşılan dosyada defter (R8)** ve **eşitlenmeyen notlar (R9)**.
8. **Yayılım (R10)** ve uçtan uca üç cihaz testi (A, B kendi; C meslektaş).
9. Codex denetimi, düzeltmeler, tam test, push.

## 6. Dikkat

- `dart format` yalnız değişen dosyalara verilmeli; `lib/services` gibi klasöre verilince ilgisiz
  dosyaları da biçimlendiriyor (`system_font_catalog.dart`, `uyap_pace.dart`, `clients_page.dart`,
  `portfolio_rows.dart`, `editor_widget.dart`).
- Üretilen eklenti dosyaları commitlenmez: `macos/Flutter/GeneratedPluginRegistrant.swift`,
  `windows/flutter/generated_plugin_registrant.cc`, `windows/flutter/generated_plugins.cmake`.
- Codex: `codex exec -m gpt-6.1-sol -s read-only -C <repo> -o <çıktı> "<talimat>"`; talimat dosyası
  repo dışındaysa okuyamayabiliyor, talimatı komutun içine koy.
- UI değişikliklerinde önce maket gösterilir, onaydan sonra uygulanır.

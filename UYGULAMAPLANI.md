# LifeOS Folio — Uygulama Planı

Tarih: 6 Ekim 2026

Durum: Kaynak incelemesi ve plan hazırlandı. Uygulama geliştirmesi başlatılmadı.

Ek inceleme (6 Ekim 2026): Banaozel'in senkron, portföy, evrak, duruşma ve UETS eşleştirme mantığı incelendi; Folio kuralları §9'a, paket maddeleri ilgili paketlere işlendi. Ekran yerleşimi §10'da karara bağlandı; süre motoru kararı §11'de, uygulama sırası §12'de.

Hedef proje: `/home/erkanoz/projeler/evrak convert`

Referans proje: `/home/erkanoz/projeler/banaozel`

## 1. Geçerli kullanıcı kararları

1. Folio ücretsiz kullanılacak. Folio hesabı, uygulamaya giriş/kayıt, ödeme, Pro paketi, lisans aktivasyonu, abonelik ve lisansa bağlı cihaz sınırı bu geliştirmede yok.
2. Yapay zekâ özellikleri sonraki bir çalışmaya bırakıldı. Gemini/BYOK, analiz, otomatik dilekçe üretimi, embedding, semantik araştırma ve AI ile süre çıkarımı bu iş listesinin parçası değil.
3. Telefon testleri geliştirme sonrasında yapılacak. Geliştirme; kaynak incelemesi, anonim örnekler, sahte HTTP/oturum servisleri, widget testleri ve mevcut platformlarda derleme ile ilerleyecek.
4. **Toplu portal bağlantısı olmayacak.** Bir giriş işlemi başka bir portalda giriş başlatmayacak. PIN, OAuth kodu, çerez ve token bir başka giriş işlemi için tekrar kullanılmayacak.
5. Üç bağımsız bağlantı bulunacak: **UETS**, **UYAP Web Portal**, **UYAP Mobil API**.
6. Belgeler, ajanda ve portal oturumları cihazda tutulacak. Banaozel'in uygulama hesabı, merkezi token paylaşımı, sunucu belge arşivi ve analiz/bot sistemi Folio'ya taşınmayacak.
7. Mobil/masaüstü cihaz eşleştirmesi ayrıca kullanıcı işlemiyle yapılacak. QR eşleştirmesi portal girişini başlatmayacak; eş cihazın portal tokenını otomatik almayacak.
8. Mevcut belge motoru, masaüstü iş akışları, geçmiş/kurtarma ve imzalı asılların korunması geliştirme boyunca sürdürülecek.

Bu kararlar, `Folio_AI_Mobil_UYAP_Gelistirme_Plani.md` içindeki eski fiyat, lisans, ilk sprintte telefon testi ve ek giriş yöntemi önerilerinin yerine geçer. Kaynak belgedeki “güncel kullanıcı kararı” ifadeleri, bu sohbetin son talimatlarıyla birlikte değerlendirilmiştir.

## 2. İnceleme kapsamı ve bulunan durum

- Folio HEAD: `95445d4d2914e6e4b18139b407a097595c14dbdb`; sürüm `1.4.0+6`.
- Banaozel HEAD: `be1324865ef22cb53ed4cdf26808a888f26a5b90`. Çalışma ağacında kullanıcı değişiklikleri var; inceleme yerel dosyalar üzerinden yapıldı. Özellikle `server/katip_service.py` için HEAD tek başına incelenen içeriği temsil etmiyor. Kaynak hash'leri Ek A'da.
- Planın son kontrolü sırasında Banaozel HEAD'i başka bir çalışma ile `e15bd73abdfb4598940b42914f3557c44d632e24` oldu; `server/uets_web.py` ve `server/katip_service.py` içerikleri değişti. UETS farkı ağırlıkla bu sürüme alınmayan e-Devlet girişinin bekleme/tamamlama yönetiminde. Ek A ilk incelenen içeriği kaydeder; uygulama öncesinde bu iki dosyanın güncel farkı tekrar değerlendirilecek.
- Kaynak fonksiyonları ve seçili testlerin kodu okundu. Bu inceleme sırasında Banaozel/Folio testleri, canlı portal girişi, gerçek kart/SIM işlemi ve telefon testleri çalıştırılmadı.
- Bu sohbetin önceki adımında aynı Folio HEAD'i Linux release olarak derlendi ve çalıştırıldı. Bu, yeni planın henüz uygulanmamış özelliklerinin doğrulaması değildir.

| Alan | Kaynakta görülen yapı | Folio'da uygulanacak yaklaşım |
|---|---|---|
| Toplu bağlantı | Banaozel `BaglanAkisi.baglan()` varsayılanı `BaglanHedef.ikisi`; bir PIN ile tray ve PKCS#11 yollarını sıralıyor | Bu üst akış taşınmayacak; üç bağımsız giriş denetleyicisi kurulacak |
| UETS'e ayrı e-imza | `UetsAuthService.loginWithEimza`, challenge ve CAdES-BES; Python'da da başlat/imza/yokla fonksiyonları var | Sertifikadan kimlik, kullanıcı sertifika seçimi ve Folio kart altyapısıyla doğrudan UETS girişi |
| UETS'e mobil imza | Python `mobil_baslat` / `mobil_yokla` / `_oturum_ac` | Protokol yerel Dart servisine uyarlanacak; Folio sunucusu gerekmeyecek |
| UYAP web e-imza | Folio `UyapWebService.connect`, Adalet tray; Banaozel `SigningService.loginToUyap` | Folio'nun mevcut tray girişi korunacak; UETS PKCS#11 ön taraması çağrılmayacak |
| UYAP web mobil imza | Folio `beginEdevlet` / `finishEdevlet`; Banaozel `uyap_web.baslat/tamamla` | Aynı web oturumunun çerez/state ilişkisi korunacak; mobil giriş görünümü eklenecek |
| UYAP Mobil API | `UyapMobileApiService`, e-Devlet kod takası, access/refresh, avukat kimliği ve veri uçları | Hesapsız, cihaz içi adaptör; web çerezlerinden bağımsız token yönetimi |
| Mobil API'nin dış bağımlılığı | `MobilUyap` uygulama hesabı ve `/uyap/token` sunucu paylaşımına bağlı | Bu sınıf olduğu gibi alınmayacak; protokol/yenileme kuralları ayrılacak |
| Giriş tarayıcısı | Banaozel OAuth motor seçimi Windows WebView2; Linux ayrı yardımcı süreç | Masaüstü desenleri kullanılabilir; Android/iOS giriş görünümü ayrıca geliştirilecek |
| OAuth korumaları | Banaozel Dart örneğinde sabit `state=1179` ve URL öneki kontrolü; Python mobil akışında üretilen state ve tek kullanım var | Mobil API için yerel akışa özgü state, tam URI kontrolü, tek kullanım ve giriş nesli; web için UYAP'ın verdiği state korunacak |
| Kart yaşam döngüsü | Banaozel'de kart/tray çakışması için ayrı kart süreci; Folio UDF imzasında kısa ömürlü isolate var | UETS kart girişinde ayrı süreç ve ortak kart kaynağı koruması; kaynak serbest bırakma sınanacak |
| UETS sayfalama | Dart `start` ofseti / `starttime` tarih filtresi; `strict=false` yollarında hata boş liste olabiliyor | Folio'da hatalar tipli olacak; hata ile başarılı boş liste ayrılacak |
| İstek tekrarı | Mobil API genel `_post` yolunda 401/403 sonrası tekrar var | Tekrar politikası işlem türüne göre ayrılacak; gönderim/talep otomatik tekrar edilmeyecek |
| UETS yan etkileri | Banaozel servis ve arka plan katmanlarında analiz ve süre işleri var | Liste/indirme/görüntüleme ayrı kurulacak; analiz/süre çağrıları alınmayacak |
| Ajanda | Banaozel birleştirme kodu sunucu kaynaklı süre/duruşma verileri içeriyor | Tekilleştirme fikri kullanılacak; yerel not/iş ve kaynak duruşması ayrı sahiplikle saklanacak |
| Mobil sayfa | Folio `PageZoom.opening` ve viewport `%50` alt sınırı; ilk açılışa bağlı sığdırma | Dar ekran hesabı ve otomatik/manuel zoom ayrımı düzeltilecek; akış editörü ayrıca yapılacak |

## 3. Kesin bağlantı ve giriş matrisi

| Bağlantı | Kullanıcının seçtiği yöntem | Giriş yolu | Üretilen oturum |
|---|---|---|---|
| UETS | Mobil imza | UETS mobil imza başlat → doğrulama dizesi → onay yoklama → UETS authentication | Yalnız UETS tokenı/oturumu |
| UETS | E-imza | Kart/sertifika seç → UETS challenge → yerel CAdES imza → UETS authentication | Yalnız UETS tokenı/oturumu |
| UYAP Web Portal | E-imza | Mevcut Adalet E-İmza tray girişi | Yalnız UYAP web çerezleri |
| UYAP Web Portal | Mobil imza | Web oturumu başlat → e-Devlet mobil imza → web dönüş kodu → aynı çerezlerle tamamla | Yalnız UYAP web çerezleri |
| UYAP Mobil API | E-imza | Mobil API'ye ait e-Devlet akışı; e-imza yöntemi resmi girişte seçilir | Yalnız mobil access/refresh tokenı |
| UYAP Mobil API | Mobil imza | Mobil API'ye ait e-Devlet akışı; mobil imza yöntemi resmi girişte seçilir | Yalnız mobil access/refresh tokenı |

### Bağlantıların bağımsızlık kuralları

- Her kartın kendi **Bağlan, Yeniden bağlan, İptal, Senkronize et, Bağlantıyı kaldır** işlemi ve kendi durum göstergesi olacak.
- “Hepsine bağlan”, birleşik PIN penceresi, toplu giriş denemesi veya başarısız girişten sonra başka portalı otomatik deneme olmayacak.
- UETS girişi UYAP'a; web girişi mobil API'ye; mobil API girişi web/UETS'e dönüşmeyecek.
- Bir portalın iptali, zaman aşımı, çıkışı veya oturum kaybı diğer portalın oturumunu kapatmayacak.
- Başarılı giriş veya doğrulanmış restore yalnız ilgili kanalın senkron işini başlatacak. Tokenın sıradan yenilenmesi bütün portföyü yeniden başlatmayacak.
- Gerekli kanal bağlı değilse ilgili bağlantı kartı gösterilecek; giriş ancak kullanıcı o kartta başlattığında yapılacak.
- Kullanıcı farklı zamanlarda birden fazla portalı bağlayabilir. Aynı doğrulanmış portal sahibi kapsamındaki kayıtlar yerelde birleştirilebilir; bu, ortak giriş anlamına gelmez.
- Aynı fiziksel kart için eşzamanlı işlemleri önleyen kaynak kilidi kullanılabilir. Kilit girişleri birleştirmeyecek; ikinci işlem “kart meşgul” durumunda bekletilecek veya kullanıcıya gösterilecek.
- UETS kart girişi kimlik okumak için Adalet tray'e bağımlı olmayacak. Banaozel üst akışındaki UETS-only tray ön kontrolü taşınmayacak.
- UETS e-Devlet/şifre+SMS ve UYAP web e-Devlet e-imza seçeneği bu sürümde ayrı Folio giriş yöntemi olarak eklenmeyecek; kullanıcı tarafından belirtilen altı yol uygulanacak.

### İki UYAP e-Devlet akışının ayrımı

- **Web dönüşü:** `https://avukat.uyap.gov.tr/login.uyap`; `beginEdevlet` tarafından açılan web çerezleri ve UYAP'ın verdiği state ile `finishEdevlet` kullanılır. State `0` ise geçerli değer olarak korunur.
- **Mobil API dönüşü:** `https://mobilws.uyap.gov.tr/portaldmz/avukat.html`; code mobil `auth/edevlet` yolunda tokenla değiştirilir. Yerel akışa özgü state ve tek kullanımlı tamamlayıcı tasarlanır.
- Banaozel Dart istemcisindeki gerçek istek tabanı `/portaldmz/services`; eski belgenin kısaltılmış tabanı ve yorumlar yerine çalıştırılan URI üretimi envantere alınacak. Uç uyumluluğu gerçek kabul aşamasında doğrulanacak.
- Scheme/host/path tam eşleşmesi yapılacak; `startsWith` tek başına yeterli sayılmayacak. Yanlış hedefe ait kod hiçbir token/çerez takasına gönderilmeyecek.
- Kaynaktaki `loginTypeIndex=1` iki yöntemin de doğrulandığı anlamına gelmiyor. Mobil API e-imza/mobil imza seçimi resmi ekran üzerinden sunulacak; doğrulanmamış indeks eşlemeleri uydurulmayacak.
- Android/iOS resmi giriş ekranı ve e-imza bileşenlerinin gerçek cihaz desteği P16'da doğrulanacak. Geliştirme sırasında bu yollar “telefon üzerinde doğrulandı” olarak işaretlenmeyecek; telefon için UETS kart/tray sürücüsü varmış gibi davranılmayacak.

## 4. Hedef yapı ve veri kuralları

### Servis sınırları

```text
Bağlantılar ekranı
  ├─ UetsConnectionController       → UETS mobil imza / yerel kart girişi
  ├─ UyapWebConnectionController    → Adalet tray / web e-Devlet mobil imza
  └─ UyapMobileConnectionController → mobil API e-Devlet e-imza / mobil imza

Bağımsız kanal durumları → PortalRegistry
Kanalın connectionReady olayı → ilgili kanalın SyncCoordinator işi
UYAP okuma/yazma → UyapRepository + işlem/yetenek çözümleyicisi
UETS okuma/indirme → UetsRepository
Yerel kayıtlar/asıl evrak → dosya ekranları + görüntüleyici + ajanda
Kullanıcının eşleştirdiği cihazlar → ayrı DeviceSyncService
```

`PortalRegistry` durumları izler; toplu giriş yapan bir orkestratör değildir. UI doğrudan kaynak uç ve kimlik seçmez. `SyncCoordinator` da giriş veya imza başlatmaz.

### Önerilen hedef dosyalar

Bu adlar uygulama sırasında mevcut yapıya göre uyarlanabilir; aşağıdaki yeni dosyaların şu anda var olduğu iddia edilmiyor.

| Hedef | Görev |
|---|---|
| `lib/services/portal/portal_channel.dart`, `portal_registry.dart` | Kanal ve bağımsız durumlar |
| `lib/services/portal/connection_state.dart`, `login_flow.dart` | Akış kimliği, iptal, oturum nesli, kimlik ve durum geçişleri |
| `lib/services/security/secret_store.dart` | Cihazda token/çerez/cihaz anahtarı saklama |
| `lib/services/portal/portal_database.dart`, `archive_repository.dart` | Yerel metadata, kayıt göçü ve asıl evrak |
| `lib/services/uyap/uyap_repository.dart`, `channel_resolver.dart`, `case_ref.dart` | Normalize dosya/evrak ve işlem bazlı kanal çözümü |
| `lib/services/uyap/uyap_mobile_api.dart`, `uyap_mobile_connection.dart` | Mobil API protokolü ve ayrı bağlantı |
| Mevcut `uyap_web_service.dart` + `uyap_web_connection.dart` | Mevcut web protokolünü koruyan adaptör |
| `lib/ui/widgets/portal_login_view.dart` + platform adaptörleri | Hedefi parametreli resmi giriş görünümü; her akışın oturumu ayrı |
| `lib/services/uets/uets_auth_service.dart`, `uets_client.dart`, `uets_repository.dart` | Bağımsız UETS giriş/liste/indirme |
| `lib/services/signing/card_process.dart`, `card_operation_guard.dart` | Kart yardımcı süreci ve fiziksel kaynak koruması |
| `lib/services/portal/sync_coordinator.dart`, `job_repository.dart` | Kanal başına kalıcı senkron/indirme işleri |
| `lib/services/uets/case_matcher.dart` | Kanıta dayalı tebligat–dosya ilişkisi |
| `lib/services/agenda/agenda_repository.dart`, `reminder_scheduler.dart` | Duruşma, manuel not/iş ve yerel bildirim |
| `lib/services/sync/device_pairing.dart`, `device_sync_service.dart` | QR, yerel ağ ve artımlı aktarım |
| `lib/services/backup/encrypted_backup.dart` | Kullanıcının seçtiği konuma şifreli yedek/geri yükleme |

### Yerel modelin zorunlu alanları

| Kayıt | Kimlik ve korunacak alanlar |
|---|---|
| Portal oturumu | Kanal, doğrulanmış yerel portal sahibi, yöntem, `sessionGeneration`, erişim/yenileme bitişi, son doğrulama; sırlar güvenli depoda |
| Giriş akışı | Kanal, `flowId`, beklenen dönüş, state, oluşturulma/bitiş, iptal/tek kullanım durumu; PIN/code loglanmaz |
| Dosya | Yerel UUID, portal sahibi, yargı türü, kanonik birim/numara; ayrı mobil/web ID ve ID'nin oturum nesli |
| Evrak | Dosya/alt dosya + kaynak kanal + kaynak ID; asıl/önizleme ayrımı, hash, boyut, MIME, sürüm ve indirme durumu |
| UETS | Portal sahibi ve seçilen UETS client hesabı, message/part ID, gönderim/kaynak durumları, envanter, asıl/paket, Folio'da görüldü bilgisi |
| Ajanda | UUID veya kalıcı kaynak kimliği, kaynak, dosya bağı, tarih/saat/tüm gün, zaman dilimi, not/görev/hatırlatma ve revizyon |
| İş kuyruğu | Job ID, kanal/sahip/oturum nesli, kapsam/tarih penceresi, cursor, başarılı/eksik parçalar, tekrar bütçesi, hata ve checkpoint |
| Cihaz aktarımı | Cihaz kimliği, güvenilen eş, kapsam, kayıt revizyonu/hash, outbox/cursor ve silme tombstone'u |

- Folio hesabı yerine **yerel portal sahibi ayrımı** kullanılır. Kimlik portalın korumalı kullanıcı yanıtından doğrulanır; JWT payload veya isim benzerliği sahiplik kanıtı değildir.
- Mobil/web/UETS farklı kimlik döndürürse veriler otomatik birleştirilmez. UETS'te birden fazla client hesabı varsa açık seçim yapılır.
- Sahibi belirlenemeyen eski kayıtlar “eski yerel arşiv” kapsamında korunur; yanlış kullanıcıya sessizce atanmaz.
- Kaynak tarih/yer/durum alanı ile kullanıcının not/tamamlama/hatırlatma alanı ayrı sahipliktedir.
- Başarısız/kısmi snapshot son sağlam veriyi silmez. Tarih penceresi dışındaki ajanda kayıtları korunur.
- İmzalı/asıl baytlar değişmezdir. Düzenleme yeni sürüm üretir; kaynak imza değiştirilmez.
- Cache/önizleme temizliği kalıcı asıl arşivi silmez. Dışa aktarma kullanıcı seçimiyle yapılır.
- Güvenli kasa yazma-okuma doğrulaması yapılır. Kasa yoksa Banaozel'in düz token JSON fallback'i alınmaz; bellekte oturum veya güvenli saklamanın kurulması seçeneği gösterilir.
- UYAP mobil token yenilemesi tek işlemle yürür; yeni girişi eski yenileme yanıtının ezmesi oturum nesli kontrolüyle engellenir. Yenileme ömrü her refresh'te uzatılmaz.
- Web/UETS oturum süresi mobil API'nin yenileme süresinden türetilmez. Kesin bitiş bilinmiyorsa son doğrulama ve yeniden kontrol durumu gösterilir.

## 5. İş paketleri ve uygulanma sırası

Her paket için çıktı ve yerel kabul koşulu tamamlanmadan bağlı paket bitmiş sayılmaz. P16'ya kadar telefon testi zorunlu geçiş koşulu değildir. Listedeki bütün uygulama kutuları henüz yapılacak durumdadır.

| Paket | İş | Ön koşul |
|---|---|---|
| P01 | Temel test düzeni, kanal/işlem sözleşmeleri | Kaynak incelemesi |
| P02 | Yerel veritabanı, arşiv, güvenli kasa ve kayıt göçü | P01 |
| P03 | Ayrı UYAP Web Portal girişi | P01–P02 |
| P04 | Ayrı UYAP Mobil API girişi ve token yönetimi | P01–P02 |
| P05 | Ayrı UETS mobil imza/e-imza girişi | P01–P02 |
| P06 | Kalıcı senkron ve indirme kuyruğu | P02; ilgili P03/P04/P05 adaptörü |
| P07 | UYAP dosya portföyü, evrak ve çevrimdışı kullanım | P03–P04–P06 |
| P08 | UETS kutusu, asıl/ek/paket arşivi | P05–P06 |
| P09 | UETS–UYAP eşleştirmesi | P07–P08 |
| P10 | Yerel ajanda, not/iş ve bildirimler | P04–P06–P07; web duruşma adaptörü P03 |
| P11 | Mobil gezinme ve ekrana sığan önizleme | P01; portal ekran bağları P07/P08/P10 |
| P12 | Mobil akış editörü ve A4 geçişi | P11 |
| P13 | İmza, mobil gönderim ve mazeret/e-duruşma | P03–P04–P07–P12 |
| P14 | QR cihaz eşleştirme, LAN aktarımı ve yedek | P02–P09–P10–P12 |
| P15 | Ücretsiz dağıtım ve bütünleşik yerel doğrulama | P03–P14 |
| P16 | Sonradan gerçek telefon/kart/SIM kabulü | P15 |

Önerilen yürütme: P01 → P02 → P03 → P04 → P05 → P06 → P07 → P08 → P09 → P10 → P11 → P12 → P13 → P14 → P15 → P16. Önizleme teşhisi P01 sırasında yapılabilir; temel sığdırma düzeltmesi portal işlerini beklemeden hazırlanabilir. P03–P05 birbirinin girişini veya canlı başarısını ön koşul yapmaz.

### P01 — Temel sözleşmeler ve yerel test düzeni

- [ ] Mevcut analiz/test sonuçlarını başlangıç kaydı olarak al; mevcut başarısızlıkları yeni değişikliklerden ayır.
- [ ] Banaozel'in inceleme sonrasında değişen kaynaklarını Ek A ile karşılaştır; taşınacak fonksiyon ve bağımlılık envanterini güncel içerikle kesinleştir.
- [ ] `PortalChannel`, kanal bağlantı durumu ve iptal edilebilir giriş akışı sözleşmelerini tanımla.
- [ ] `UyapOp` benzeri işlem tablosu ve normalize sonuç modeli oluştur: başarılı, boş, kısmi, bağlantı gerekli, yetki, ağ, format, belirsiz yazma sonucu.
- [ ] HTTP GET/POST ayrımı yerine **işlemin etkisine** göre politika tanımla; salt okunur POST sorguları ile yazan POST taleplerini ayır.
- [ ] §9.2 işlem → kanal tablosunu tek bir çözümleyici olarak kur. Senkron, indirme, UI ve gönderim katmanları kendi kanal kuralını içermesin; tablo testlerle sabitlensin.
- [ ] Sahte saat, HTTP sunucusu, güvenli kasa, kart worker ve giriş tarayıcısı adaptörlerini testlerde kullanılabilir yap.
- [ ] Anonim örnek setini hazırla: UDF/DOCX tablo/antet/görsel/listeler, imzalı/bozuk belge, PDF, çok sayfalı TIFF, EYP ve iki hesap/dosya çakışması.

**Çıktı:** Telefon/kart gerektirmeyen geliştirme test düzeni ve servis sözleşmeleri.

**Kabul:** Üç kanalın durum nesneleri ayrıdır; bir kanala gelen olay diğerinin giriş/çıkışını tetiklemez. Yazma işlemi için otomatik retry kapalıdır.

### P02 — Yerel veri, güvenli kasa ve göç

- [ ] Portal verileri için sürümlü SQLite şemasını ve repository'leri oluştur; mevcut arama indeksini bu iş için yeniden yazma.
- [ ] `UyapCaseStore`, `baglar.json`, `fresh`, `previousFetchedAt`, `files/previews`, dilekçe/dosya bağları ve orijinal evrak yollarını göç envanterine al.
- [ ] Yedeklenmiş kaynaklarla idempotent göç yap; yarıda kesilme/yeniden başlama/bozuk kayıt davranışını kur. Doğrulanmadan eski JSON'u kaldırma.
- [ ] Android/iOS için kalıcı özel arşiv dizini; masaüstü için mevcut seçili arşiv düzeni ve atomik yazma kullan.
- [ ] Token/çerez/cihaz anahtarı için kanal+sahip ayrımlı güvenli kasa uygula; sır içeren log/hata metinlerini maskele.
- [ ] Portal bağlantısını kaldırma, yerel arşivi silme ve bütün cihaz verisini silme işlemlerini ayrı tasarla.
- [ ] Evrak hash/MIME/boyut ve bütünlüğünü kaydet; dosya yolu değişmiş eski belgeye yeniden konum gösterme akışı ekle.

**Çıktı:** Eski arşivi koruyan yerel repository ve güvenli oturum deposu.

**Kabul:** İkinci göç kopya kayıt üretmez; kesinti kaynakları bozmaz; kasa hatasında düz token dosyası oluşturulmaz; sahipler arası veri karışmaz.

### P03 — UYAP Web Portal'a bağımsız giriş

- [ ] Mevcut Folio tray girişini ayrı web denetleyicisine bağla. E-imza seçilince yalnız Adalet tray yolu çalışsın.
- [ ] Web mobil imza seçilince mevcut `beginEdevlet(EdevletMethod.mobile)` ve `finishEdevlet` kullanılsın; aynı web çerezleri/state korunsun.
- [ ] Masaüstü giriş görünümünü koru; Android/iOS için hedefi web olan resmi giriş adaptörünü geliştir. Mobil engeli adaptör yeteneğine bağla.
- [ ] Yeni giriş/iptal/timeout nesliyle eski pencerenin yeni oturumu tamamlamasını önle; redirect ve code tek kez işlensin.
- [ ] Web kimliğini ve gerekli yetki seviyesini ayrı doğrula; yalnız görünen ad veya giriş ekranının kapanmasını başarı sayma.
- [ ] Her adımda yalnız web kanalının durumunu güncelle. UETS veya mobil API otomatik giriş/restore çağrısı üretme.

**Çıktı:** Web kartı: e-imza/tray ve mobil imza/e-Devlet, bağımsız durum ve iptal.

**Kabul:** Sahte tray/web/e-Devlet yanıtlarında doğru çerez/state kullanılır; yanlış dönüş reddedilir; iptal UETS/mobil tokena dokunmaz; PKCS#11 ön taraması yoktur.

### P04 — UYAP Mobil API'ye bağımsız giriş

- [ ] Banaozel mobil veri/token protokolünü Folio DTO ve yerel kasasına uyarla; `KimlikServisi`, `ProfileService`, sunucu `/uyap/token` ve merkezi refresh bağımlılıklarını ayır.
- [ ] Mobil API hedefli e-Devlet girişini iki yöntemle sun: e-imza ve mobil imza. Yöntem seçimi resmi giriş ekranında tamamlanır.
- [ ] Yerel akış state/timeout/tek kullanım ve tam dönüş URI kontrolü uygula; web kodunu mobil `auth/edevlet`e gönderme.
- [ ] Token takasındaki platform/cihaz alanlarını kaynak protokol envanterine al; Banaozel marka/donanım etiketlerini körlemesine kopyalama.
- [ ] Korumalı avukat kimliği ve işlem yetkilerini doğrula; Folio hesabı veya uygulama parolası isteme.
- [ ] Restore, access yenileme kilidi, oturum nesli, refresh bitişini koruma ve erken yetki kaybını uygula.
- [ ] GET/POST yanıtlarının bozuk/HTML/401/403/hata durumlarını sınırlandırılmış kuralla işle; okuma için sınırlı tekrar, talep/gönderim için belirsiz sonuç üret.

**Çıktı:** Cihaz içi mobil API girişi ve uygulama açılışında geri yüklenen yerel token.

**Kabul:** Eski refresh yeni login'i ezmez; paralel yenileme tek çağrıdır; web/UETS bağlılığına gerek duymaz; Folio sunucusuna token gönderilmez.

### P05 — UETS'e bağımsız mobil imza ve e-imza

- [ ] UETS mobil imzayı yerel Dart'a taşı: TCKN/GSM/operatör doğrulama → başlat → doğrulama dizesi → sınırlı yoklama → UETS authentication.
- [ ] Pending, iptal, timeout ve sonradan gelen onayı aynı flow kaydıyla yönet; timeout yeni bir SIM isteğini otomatik başlatmasın.
- [ ] UETS e-imza için kart/sertifika seç, kimliği sertifikadan oku, challenge/onay metnini göster, CAdES imza gönder ve oturumu doğrula.
- [ ] Kaynak `UetsAuthService`in “geçerli sertifika yoksa ilk sertifikaya düş” davranışını alma; geçersiz sertifikada açık hata ver.
- [ ] Kart yardımcı sürecini Folio giriş noktalarına/native paketlere uyarla; timeout ve iptalde süreç/kart serbest kalsın. PIN sadece özel IPC'de taşınsın; dosya/argüman/env/loga yazılmasın.
- [ ] Kart kaynağı korumasını tray, UETS ve Folio belge imzasında uygula; bu, ortak PIN veya ortak login üretmesin.
- [ ] UETS kimliğini ve birden fazla client varsa seçili hesabı doğrula; tokenı yalnız UETS kasasına yaz.
- [ ] UETS ekranında yalnız kullanıcının istediği mobil imza/e-imza yöntemleri bulunsun; diğer portal denetleyicilerini çağırma.

**Çıktı:** UYAP/tray kurulumu gerektirmeden çalışan ayrı UETS bağlantı servisi ve ekranı.

**Kabul:** Sahte mobil imza/kart testinde yalnız UETS çağrıları görülür; yanlış PIN ikinci portala gönderilmez; süreç her sonuçta kapanır; stale onay yeni girişe bağlanmaz.

### P06 — Kalıcı senkron ve indirme işleri

- [ ] `connectionReady(channel, owner, generation)` olayını tanımla; ilk giriş/doğrulanmış restore için ilgili kanala tek iş oluştur.
- [ ] Kanal+sahip+iş kapsamı başına tek aktif iş; yinelenen UI olaylarında tekilleştirme uygula.
- [ ] Liste/cursor/pencere sonuçlarını checkpoint ile kaydet; işlerin “bekliyor, çalışıyor, kısmi, tamam, hata, oturum bekliyor, iptal” durumlarını oluştur.
- [ ] Önce metadata, sonra takip edilen UYAP dosyalarının ve seçili UETS kapsamının yeni/eksik asıllarını kuyruğa al.
- [ ] Ağ ve depolama bütçesi, kontrollü istek sırası, sınırlı okuma tekrarı ve kullanıcı durdur/devam et işlemlerini ekle.
- [ ] Oturum kaybı yalnız ilgili kanalın işlerini bekletsin. Yeni oturumda kimlikler taze çözülsün.
- [ ] UI'da kanal bazlı son kontrol, kalan kapsam, indirme/hata sayıları ve depolama durumunu göster.

- [ ] Mobil ve web turları aynı dosyaya yazabilir. Birleşme §9.4'teki alan bazlı gözlem damgasıyla ve tek transaction'da yapılsın; eski gözlem yeniyi, boş değer veya boş liste dolu veriyi ezmesin.
- [ ] Yeni evrak eşiğini kanal geneli değil **dosya başına** tut (§9.6). Bir belgenin indirilememesi yalnız o belgeyi işaretlesin; dosyanın kalanını ve turu kesmesin.
- [ ] Açık dosyaların evrak listesi tazeliği, eksik dosya dilimleri ve dosya açılışındaki canlı tazeleme ayrı bütçelerle planlansın; turlar kaldığı yerden devam etsin.

**Çıktı:** Kapanma/kesintiden devam edebilen senkron ve indirme kuyruğu.

**Kabul:** Yarım iş tam sayılmaz; hata güncellik zamanını ilerletmez; başka kanalın kuyruğu iptal edilmez; bağlantı hiçbir gönderim/talep üretmez.

### P07 — UYAP portföyü ve evrak akışı

- [ ] `UyapCasePanelController` ve dosya ekranlarını web servisi yerine repository/facade üzerinden okut.
- [ ] Dosya arama, mahkeme/esas/taraf filtreleri, son kullanılanlar, açık/kapalı dosya ve takip seçimini mobil/masaüstünde sun.
- [ ] Mobil/web çift ID ve oturum nesli çözümünü uygula. Yargıtay için mevcut web yolunu; Danıştay mobil/web kapsamını ayrı değerlendir.
- [ ] Web'in zengin taraf/künye/safahat/para bilgisi mobilin eksik snapshot'ıyla ezilmesin; kaynak ve eksik alan görünür olsun.
- [ ] Evrak envanteri, alt dosya/ek ilişkisi, tekli/toplu indirme ve çevrimdışı açmayı ortak modele bağla.
- [ ] Dilekçeler ve yerel belge–dosya ilişkilerini koru; indirilen evrakları mevcut arama/görüntüleyiciye bağla.

- [ ] Portföyü iki kanaldan doldur (§9.4): mobil açık/kapalı yargı dosyaları ve taraflar; web Yargıtay, Cumhuriyet Başsavcılığı (il → birim → dosya), safahat, para/işlem bilgisi ve mobilde gelmeyenler. Danıştay ve istinaf için §9.2 tablosu esas.
- [ ] Mobil ve web kayıtları `dosya_key` (sadeleştirilmiş dosya no | birim adı; icra yenileme eki kırpılmış) üzerinde birleşsin. Oturumluk `dosyaId`/birim kimlikleri kalıcı anahtar yapılmasın; web kimliği yalnız ipucu olarak tutulup bayatlayınca taze çözülsün.
- [ ] Evrakı bağlı kanaldan indir; seçilen kanal başarısızsa diğer bağlı kanala düş (§9.5). Yargıtay ve Cumhuriyet Başsavcılığı evrakı yalnız web'den. Evrak kaydında indiği kanal tutulsun.
- [ ] Evrak kimliği `stabil_no` (birim evrak no, yoksa evrak id; ekler `<ana>:ek:<n>`). Asıl içerik özetiyle adlandırılıp benzersiz geçici dosyadan yeniden adlandırma ile yazılsın; HTML/giriş sayfası yanıtı oturum hatası sayılsın. UDF/DOCX/ZIP/EYP içerikten ayrılsın; her ZIP UDF sayılmasın.

**Çıktı:** Aynı veri modelini kullanan mobil/masaüstü UYAP dosya ekranları.

**Kabul:** Mobil ID web ucuna gitmez; yanlış sahip/alt dosya evrakı açılmaz; web gereken işlem yalnız bağlantı kartına yönlendirir; arşiv çevrimdışı açılır.

### P08 — UETS kutusu ve evrak arşivi

- [ ] Liste/detay/parts/evidence/folder normalizasyonunu oluştur; sayfalama `start`, tarih filtresi `starttime` olarak ayrı kullanılsın.
- [ ] Başarılı boş liste ile 401, bozuk yanıt, sonraki sayfa hatası ve geçici ağ hatasını ayrı kaydet.
- [ ] Üst yazı metadata'sı, ek envanteri, asıl dosyalar, tam EYP/paket ve paketteki zarfı ayrı takip et.
- [ ] Asılları atomik/hash kontrollü kaydet; PDF/UDF/DOCX/TIFF ve paket içeriğini mevcut görüntüleyiciye yönlendir.
- [ ] UETS'in kaynak gönderim/ulaşma/okunma alanları ile Folio'da görüldü bilgisi ayrı gösterilsin. Eksik tebliğ tarihi üretilmesin.
- [ ] Yeni/eksik içeriği otomatik indir; kapsam/byte bütçesi kullanıcı ayarı olsun. Kaynak projedeki 40 günlük veya tur tavanları sessiz veri kaybı yaratmasın.
- [ ] Banaozel'in AI/süre/korpus upload bağımlılıklarını çıkar; indirme servisinde bile analiz/model çağrısı bulunmasın.

**Çıktı:** Liste, üst yazı/ek/paket ve çevrimdışı içeriği bulunan UETS ekranı.

**Kabul:** 100+ mesaj, ilk sayfa başarı/ikinci sayfa hata, eksik asıl, bozuk hash, yeni ek, EYP zarfı ve çok sayfalı TIFF örnekleri doğru işlenir. Eşleşmeyen tebligat açılır.

### P09 — UETS–UYAP eşleştirmesi

- [ ] Konu künyesi ve Türkçe normalizasyonu saf yerel eşleyiciye taşı.
- [ ] Doğrulanmış portal sahibi kapsamında numara + tam/alias birim eşleşmesinde tekil otomatik bağ kur.
- [ ] Yalnız şehir/önek benzerliğiyle kesin bağ kurma; zayıf veya çoklu adayda öneri/seçim göster.
- [ ] Manuel bağ/düzelt/ayır ve gerektiğinde çoklu ilişki ekle; yöntemi/kanıtı/observedAt bilgisini sakla.
- [ ] Portföy sonradan gelirse bekleyenleri yeniden değerlendir; manuel bağı geçici/kısmi portföy yüzünden silme.

- [ ] §9.8'deki üç kademeli ve her kademede tek aday şartlı kuralı uygula: tam birim + no → birim öneki (Yargıtay tebligat bölümü) → yer adı (savcılık bürosu → Cumhuriyet Başsavcılığı). Banaozel masaüstündeki "o numarada tek dosya varsa bağla" gevşek kuralı alınmasın.
- [ ] Portföy değişince bağsız ve belirsiz tebligatların tamamı yeniden değerlendirilsin; yalnız en yeni N kayıtla sınırlanmasın.

**Çıktı:** Açıklanabilir ve düzeltilebilir tebligat–dosya ilişkisi.

**Kabul:** Aynı esas farklı mahkemede, yanlış şehir, Yargıtay tebligat bölümü, iki aday ve manuel bağ senaryoları yanlış otomatik ilişki üretmez.

### P10 — Ajanda, not/iş ve bildirimler

- [ ] Mobil API duruşmalarını ve mevcut web kanalından tamamlanabilecek duruşma pencerelerini normalize et. Yalnız web bağlıyken de desteklenen duruşma işleri kullanılabilsin.
- [ ] Kaynak duruşmasını kalıcı kimlikle tut; tarih değişikliğini yeni olay sayma. Saat eksikse saat uydurma; Europe/Istanbul bağlamını sakla.
- [ ] Tarihsiz/tarihli not, tarih/saat/tüm gün, öncelik, dosya/tebligat bağı, tamamlandı/ertelendi ve hatırlatma özellikli manuel iş ekle.
- [ ] Gün/hafta/liste görünümü ve duruşma hazırlık kartında kullanıcının not/görevleri ile seçtiği evrak bağlantılarını göster.
- [ ] Kaynak alanlarını güncellerken kullanıcı açıklama/not/tamamlama/hatırlatmasını koru; başarılı boş pencere, kısmi pencere ve doğrulanmış iptali ayır.
- [ ] Yerel hatırlatma planla; değişiklikte eskisini kaldır; olay kimliğiyle yeni evrak/duruşma bildirimi tekilleştir.
- [ ] İzin durumu, bildirimden ilgili kayda geçiş, kilit ekranında genel metin ve masaüstü/mobil zaman davranışını uygula.

- [ ] Duruşmaları iki kanaldan al (§9.7): mobil `durusmalarim` 30 günlük, web `avukat_durusma_sorgula_brd.ajx` 29 günlük dilimlerle. `olay_key` (kırpılmış dosya no | birim | dakika) ile birleştir; alan bazlı gözlem damgası kullan; hâkim notu ve e-duruşma alanları yalnız mobilden gelir.
- [ ] Duruşmayı dosyaya `dosya_key` ile bağla; birimi dosyayla çelişen duruşmayı o dosyaya yazma.
- [ ] Silmeyi yalnız hatasız ve dolu bir tarama penceresinde, pencere içinde artık görünmeyen kayıt için yap. Yalnız mobil bağlıyken eski kayıt "doğrulanamadı" durumunda kalsın; yerel duruşmalar aynı gün aynı türde birbirini ezmesin.

**Çıktı:** Portal yeniden açılmadan çalışan yerel ajanda ve manuel işler.

**Kabul:** Yeniden açılışta çevrimdışı kayıt görünür; not kaybolmaz; aynı kontrol mükerrer bildirim üretmez; eksik pencere kayıt silmez. İlk arşiv geçmişinin tamamı yeni evrak diye bildirilmez.

### P11 — Mobil gezinme ve önizleme

- [ ] Mobil alt gezinme: Dosyalar, UETS, Ajanda, Belgeler, Ayarlar. Bağlantı kartları Ayarlar/Bağlantılar ve ilgili işlemden erişilebilir olsun.
- [ ] Ana görünümde bugünkü duruşmalar, yaklaşan işler, yeni evraklar ve ilgili kanalın senkron durumunu sun.
- [ ] Safe area, panel/araç alanı ve gerçek viewport genişliğiyle önizleme sığdırmasını hesapla; `%50` sabit alt sınırını otomatik sığdırmadan ayır.
- [ ] Otomatik genişliğe sığdırma ile manuel zoom durumlarını ayır; döndürme/panel değişiminde otomatik mod güncellensin, normal rebuild manuel zoom'u sıfırlamasın.
- [ ] Telefon/tablet/yatay/dikey ve 360–430 mantıksal piksel genişliklerde widget testleriyle taşmayı kontrol et.
- [ ] PDF/imzalı belge gerçek sayfa görünümünü korusun; taranmış içerik metin görünümü şartı olmadan açılabilsin.

**Çıktı:** Kullanılabilir mobil gezinme ve ekrana doğru oturan sayfa önizlemesi.

**Kabul:** Dar ekranda araç/panel taşması yoktur; yalnız görünüm değiştirmek belgeyi değiştirilmiş saymaz; masaüstü zoom davranışı korunur.

### P12 — Mobil akış editörü ve A4 çıktı kontrolü

- [ ] Aynı DocModel/Delta üzerinde ekran genişliğinde akan mobil editör görünümü geliştir; masaüstü A4 düzenini koru.
- [ ] Mobil düzenleme ve A4 kontrolünü tek dokunuşla değiştir; paragraf/metin konumuyla imleç/seçim korunmalı.
- [ ] Kısa alt araç çubuğu ve ayrıntılı biçim paneli; klavye alanı, imleç görünürlüğü, seçim, bileşik metin girişi, yapıştırma ve geri al davranışını düzenle.
- [ ] Tablo kaydırmasını tabloyla sınırla; karmaşık/uyumsuz bölümü sessizce düz metne dönüştürme.
- [ ] Punto, kenar boşluğu, sekme, girinti, liste, antet, üst/alt bilgi, görsel ve sayfa sonlarını görünümden bağımsız koru.
- [ ] Uzun belgede kaydırma/yazma ölçümü yap; mobil kayıt ve dışa aktarma ile belge geçmişini bağla.

**Çıktı:** Telefona uygun düzenleme ve aynı belgenin gerçek A4 kontrolü.

**Kabul:** Örnek UDF/DOCX aç–kaydet biçimi korur; görünüm değişimi içerik değiştirmez; düzenleme sonrası A4 ve dışa aktarılan belge tutarlıdır. Fiziksel klavye/IME kabulü P16'dadır.

### P13 — Belge imzası, mobil gönderim ve talepler

- [ ] Folio mevcut `MobileUdfSigner`, içerik–imza doğrulaması, hash/snapshot ve imzalı kaynak korumasını yeniden kullan.
- [ ] İmzalama işlemini kalıcı iş kaydına bağla; bekleyen SIM işlemi, iptal ve yeniden açılışta belirsiz sonucu göster. Operatör işlemi iptal edilmeden yeni istek varsayma.
- [ ] `EditorWidget._sendToUyap` ve menü platform kontrollerini gerçek yeteneklere taşı; mobil gönderim arayüzünü ayrı son kontrol ekranıyla sun.
- [ ] Genel evrak sunmada web kanalını iste; mobil API tokenını web gönderim yetkisi yerine kullanma. Web girişini otomatik başlatma.
- [ ] Taze hedef dosya ID, ana/ek evrak türü/açıklaması, izin/boyut/format ve gönderim öncesi imzalı byte hash kontrolünü koru.
- [ ] Gönderim/işlem kaydını kalıcı tut; timeout sonrası işlem/evrak sorgusuyla araştır, belirsizse kullanıcıya göster, otomatik tekrar gönderme.
- [ ] Mazeret/e-duruşma için mobil kanalda taze duruşma/kayıt ID/hak kontrolü ve açık kullanıcı son onayı ekle. Genel `_post` retry bu yazma yollarında çalışmasın.
- [ ] iOS mobil imza yeteneğini adaptör ve testleri tamamlanınca etkinleştir; telefonlarda yerel kart/tray yeteneğini varsayma.

**Çıktı:** Mobilde belge hazırlama/imzalama/web gönderimi ve mobil API özel talepleri.

**Kabul:** Değişmiş belge, eski kimlik, bozuk imza, yanlış hedef ve belirsiz sonuç testleri istenmeyen tekrar/yazma üretmez; imzalı asıl korunur.

### P14 — Hesapsız cihaz eşleştirme ve yedekleme

- [ ] Güvenli kasada cihaz anahtar çifti oluştur; kısa ömürlü/tek kullanımlı QR daveti ve karşılıklı cihaz doğrulaması uygula.
- [ ] Cihazları kullanıcının onayıyla eşleştir; abonelik/aktivasyon hesabı veya beş cihaz limiti ekleme.
- [ ] Aynı Wi-Fi/LAN'da standart, bakımı yapılan ve platformlarda desteklenen şifreli taşıma seç; özel kripto protokolü tasarlama.
- [ ] Ajanda/not/iş, seçili takipli dosya ve evrak kapsamını kullanıcı seçsin; mantıksal kayıt ve değişmez belge blob'larını aktar, SQLite dosyasını eşitleme.
- [ ] Cursor/revizyon/hash/outbox/tombstone, yarım aktarım checkpoint ve çatışmada iki sürümü koruma ekle.
- [ ] Portal tokenları/çerezler/PIN aktarım kapsamına girmesin. Cihaz eşleştirme üç portal girişinden bağımsız olsun.
- [ ] Eş cihaz kaldırma, çevrimdışı eş/son aktarım/bekleyen değişiklik göstergeleri oluştur.
- [ ] Kullanıcının seçtiği dosyaya şifreli yedek ve geri yükleme ekle; yedek anahtar kurtarma ve bozuk/yanlış parola davranışını açık tasarla.

**Çıktı:** Hesap gerektirmeyen LAN devam akışı ve ayrı yedek/geri yükleme.

**Kabul:** Yerel iki süreç testinde expired/replay QR, yanlış anahtar, yarım aktarım, aynı notun eşzamanlı düzenlenmesi, silme ve güven kaldırma doğru işlenir. Yedek doğrulanıp geri yüklenir.

İnternet relay'i, NAS/SFTP üzerinden asenkron devam ve portal oturumu aktarımı bu sürümün parçası değildir. Eş cihazın erişilebilir olması gerekir; sürekli kapalı mobil uygulamada aktarım vaadi yoktur.

### P15 — Ücretsiz dağıtım ve bütünleşik yerel kabul

- [ ] Uygulama doğrudan açılışını koru; Folio giriş/kayıt, Pro/ödeme/aktivasyon ekranı eklenmediğini doğrula.
- [ ] Linux/Windows release ve Android üretim paketlerini hazırlayan mevcut akışları güncelle; üretim Android imzasında debug fallback'i hata olarak ele al, geliştirme paketini açık ayır.
- [ ] Android/iOS dosya açma/kaydetme/paylaşma adaptörleri ve iOS belge yaşam döngüsü/izinleri için uygulama işlerini tamamla; mevcut Android taramasını koru, iOS tarama yeteneğini uygun adaptörle ele al.
- [ ] iOS derleme/paketleme işini macOS/Xcode ortamında doğrula; Linux makinede iOS release çıktısı üretildiğini varsayma. Cihaz kabulü P16'da kalır.
- [ ] Güncelleme, önceki sürümden veri göçü, uygulama yeniden açılışı ve Folio/Editör çoklu pencere kaynak kilidini dene.
- [ ] README/platform belgelerini üç bağımsız giriş, yerel veri, ücretsiz kullanım, otomatik indirme ve doğrulanan platform kapsamına göre güncelle.
- [ ] Kullanıcıya gösterilen hata/güncellik/indirme durumlarını tamamla; sırları çıkarmayan destek kaydı sun.
- [ ] Aşağıdaki yerel kabul ve mevcut regresyon paketini çalıştır; test çıktısını “telefon doğrulaması” olarak adlandırma.

**Çıktı:** Yerel testleri geçen, gerçek cihaz kabulüne hazır ücretsiz test paketleri.

**Kabul:** Hesap/lisans gerekmiyor; eski arşiv açılıyor; mevcut masaüstü iş akışları çalışıyor; hazırlanmış paket ve test sonucu ayrı kaydediliyor. Yayımlama bu plan dosyasının yazılmasıyla yapılmış sayılmaz.

### P16 — Sonradan telefon, gerçek kart/SIM ve portal kabulü

- [ ] Android ve iPhone'da giriş matrisindeki her uygulanmış yöntemi ayrı ayrı dene; başarısız/desteksiz yöntemi platform bazında açık kaydet.
- [ ] UETS mobil imza ve masaüstü UETS kart; web tray ve web e-Devlet mobil imza; mobil API e-Devlet e-imza/mobil imza yollarını gerçek kaynaklarla doğrula.
- [ ] SIM onayı sırasında arka plan, ekran kilidi, ağ kesintisi, iptal, gecikmiş cevap ve uygulama yeniden açılışını dene.
- [ ] Mobil token access/refresh/restore davranışını zaman içinde ölç; kesin süreyi source fallback'inden ilan etme.
- [ ] UETS otomatik indirmesinin kaynak okunma durumuna etkisini doğrula; kaynak ve Folio'da görülme alanları doğru gösterilsin.
- [ ] Yetkili pilotta dosya seç → evrak indir → çevrimdışı aç → düzenle → imzala → doğru web dosyasına gönder → işlem sonucunu doğrula.
- [ ] Mazeret/e-duruşmayı yalnız uygun yetkili pilotta, son kullanıcı işlemiyle dene; belirsiz sonucu tekrar gönderme.
- [ ] Telefon önizlemesi, klavye/IME/seçim, tablo, A4 geçişi, depolama, bildirim izinleri ve gerçek bildirim teslimini kontrol et.
- [ ] Telefon–masaüstü QR/LAN aktarımı, iki cihazda çatışma ve şifreli yedekten geri yükleme dene.
- [ ] Kart/tray sırayla kullanıldığında süreçlerin kaynakları bıraktığını ve yeni girişin yeniden başlayabildiğini doğrula.
- [ ] Sonuçlara göre hata düzeltme turunu tamamla; üretim destek matrisi ve paketleri yalnız doğrulanan kapsamla kesinleştir.

**Çıktı:** Platform/yöntem/operatör bazında gerçek kabul kaydı ve üretim sürümü kapsamı.

**Kabul:** Telefon testleri kullanıcıya ertelenmiş iş olarak görünür; tamamlanmadan başarılı telefon desteği veya gerçek gönderim uyumluluğu iddia edilmez.

## 6. Yerel kabul senaryoları

| Kod | Senaryo | Beklenen sonuç |
|---|---|---|
| K01 | Yalnız UETS girişini başlat | UYAP web/mobil giriş, PIN veya token çağrısı yok |
| K02 | Yalnız web tray girişini başlat | UETS PKCS#11 taraması ve mobil API login yok |
| K03 | Yalnız mobil API e-Devlet girişini başlat | Web oturumu/çerez başlangıcı ve UETS isteği yok |
| K04 | Bir kanalı iptal et/çıkar/expire yap | Diğer kanalın oturumu ve işi korunur |
| K05 | Yanlış host/path/state veya eski giriş yanıtı | Code/token takası yapılmaz; yeni oturum etkilenmez |
| K06 | Çoklu access yenileme + aynı anda yeni login | Tek refresh; eski cevap yeni tokenı ezmez |
| K07 | Kasa yazımı başarısız | Düz token dosyası yok; kalıcılık durumu açık |
| K08 | Göç/indirme ortasında uygulama kesilir | Son sağlam kayıt/asıl korunur; devam kopya üretmez |
| K09 | Web/mobile ID ve sahip uyuşmazlığı | Yanlış kanala/dosyaya çağrı yapılmaz |
| K10 | UETS 100+ mesaj; sonraki sayfa 401/hata | Kısmi durum, devam bilgisi; liste boş/silinmiş sayılmaz |
| K11 | Önizleme var, asıl veya bir ek eksik | İndirme tamam sayılmaz; eksik kapsam görünür |
| K12 | Aynı esas farklı birim, yanlış şehir, manuel bağ | Yanlış kesin eşleşme yok; manuel bağ korunur |
| K13 | Duruşma tarihi değişir; pencere eksik/boş döner | Kullanıcı notu korunur; eski hatırlatma uygun şekilde yenilenir; sahte iptal üretilmez |
| K14 | Dar ekran/klavye/A4 geçişi/aç–kaydet | Taşma yok; imleç ve belge biçimi korunur |
| K15 | İmza sonrası belge değişir; gönderim timeout | Gönderim engellenir veya belirsiz sonuç gösterilir; otomatik tekrar yok |
| K16 | Mazeret hakkı kapalı/eski kayıt/yanıt kayıp | Talep gönderilmez veya belirsiz kaydedilir; otomatik tekrar yok |
| K17 | İki cihazda aynı kayıt değişir/QR tekrarlanır | Çatışma korunur; davet tekrar kullanılamaz; portal tokenı aktarılmaz |
| K18 | UETS/ajanda/senkron akışları izlenir | Model/analiz/süre üretimi veya merkezi kullanıcı kasası çağrısı yok |
| K19 | Mobil ve web aynı dosyayı yazar; biri boş liste döner | Eski gözlem yeniyi ezmez; boş liste dolu evrak/taraf listesini silmez |
| K20 | Yalnız mobil bağlı; Yargıtay veya Başsavcılık dosyası istenir | Mobilde denenmez; web bağlantı kartı gösterilir |
| K21 | Yalnız mobil bağlıyken evrak indirilir; sonra web bağlanır | Mobilden iner, kaynak kanal kaydedilir; web kimliği taze çözülür, evrak kopyalanmaz |
| K22 | Bir dosyanın sırası 3 gün sonra gelir; arada yeni evrak eklenmiş | Yeni evrak kaçırılmaz; ilk toplu arşiv "yeni" bildirilmez |
| K23 | Aynı gün aynı türde iki duruşma; icra numarasında yenileme eki | İki ayrı kayıt kalır; aynı olay tek kayıttır |
| K24 | Tebligat için iki aday dosya var; portföy sonradan tamamlanır | Otomatik bağ yok, öneri gösterilir; portföy gelince yeniden değerlendirilir |

### Mevcut regresyon temelinden kullanılacak testler

- UYAP: `test/uyap_connect_test.dart`, `uyap_edevlet_test.dart`, `uyap_web_service_test.dart`, `uyap_case_test.dart`, `uyap_library_test.dart`, `uyap_panel_test.dart`, `editor_uyap_test.dart`.
- İmza: `test/mobile_signature_test.dart`, `signing_dialog_mobile_test.dart`, `signing_test.dart`, `signed_file_save_test.dart`, `editor_signature_test.dart`.
- Belge/mobil: `test/mobile_layout_test.dart`, `mobile_document_workflow_test.dart`, `android_document_save_test.dart`, `page_scale_test.dart`, `editor_zoom_test.dart`, `format_fidelity_test.dart`, `editor_recovery_test.dart`, `document_versions_test.dart`.
- Banaozel testlerinden aktarılacak **senaryolar**: `uets_metadata_paging_test.dart`, `uets_package_gate_test.dart`, `uets_http_deadline_test.dart`, `uets_asil_kaynagi_test.dart`, `uets_ek_sayfalama_test.dart`, `uyap_yetenek_akisi_test.dart`, `uyap_snapshot_transaction_test.dart`, `mazeret_akisi_test.dart`, `mazeret_talebi_test.dart`, `ajanda_birlesim_test.dart`.
- Test dosyaları birebir taşınmaz; sunucu ve profil varsayımları Folio'nun yerel modeline uyarlanır. Test isimlerinin varlığı testlerin geçtiği anlamına gelmez.

Paket başına ilgili testler ve statik analiz; P15'te mevcut CI'nin tam regresyonu ve platform derlemeleri çalıştırılacak. Mevcut native/OCR gereksinimleri CI'daki gibi sağlanacak; eksik araç nedeniyle sessiz atlama kabul kaydında belirtilecek.

```sh
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build linux --release --no-pub
./packaging/linux/make-release.sh
```

Android/Windows derlemeleri uygun mevcut geliştirme/CI ortamında; iOS derlemesi macOS/Xcode ortamında yapılacak. Bu komutlar planın ilerideki kabul adımlarıdır; bu incelemede çalıştırılmadı.

## 7. Teslim sırası ve kapsam yönetimi

1. **Temel servis teslimi — P01–P05:** Yerel kayıt ve altı giriş yolunun bağımsız servis/UI adaptörleri; sahte servis kabulü.
2. **Portal/evrak teslimi — P06–P09:** Kesintiden devam, portföy, UETS ve dosya ilişkileri; çevrimdışı asıl evrak.
3. **Ajanda ve mobil kullanım — P10–P13:** Not/iş, hatırlatma, önizleme, akış editörü, imza/gönderim ve talepler.
4. **Cihazlar arasında devam ve test paketi — P14–P15:** QR/LAN, yedek, ücretsiz dağıtım ve yerel regresyon.
5. **Sonradan gerçek kabul — P16:** Telefon/kart/SIM ve yetkili portal işlemleri; ardından gereken düzeltmeler.

İlk uygulama turu P01–P02 ile başlamalı; bütün paketler tek büyük değişiklikte yapılmamalı. Her pakette tamamlanan iş, test sonucu ve açık kabul maddesi bu dosyada güncellenebilir. İlk iki haftaya bütün giriş, ajanda, cihaz aktarımı ve gönderim kapsamını bitirme sözü verilmiyor. Kaynak incelemesi geliştirme tahminini tek başına kesinleştirmediği için sabit teslim tarihi yazılmadı.

### Sonraya bırakılanlar

- AI/BYOK/analiz/dilekçe üretimi, embedding ve semantik araştırma.
- Folio hesap sistemi, ücretli paket, ödeme, lisans/aktivasyon ve cihaz limiti.
- İnternet relay'i, merkezi evrak barındırma, otomatik portal token paylaşımı ve eşleştirilmiş masaüstü üzerinden portal köprüsü.
- Ofis ekip yetkileri, gelişmiş hesap araçları, otomatik hukuki süre hesabı ve yeni mobil ses/AI özellikleri.

Mevcut araştırma, belge dönüştürme ve masaüstü ses işlevlerini korumak regresyon kapsamındadır; bu özelliklerin genişletilmesi yeni iş olarak eklenmedi.

## 8. Kaynak dosyalar ve taşıma rehberi

| Yerel kaynak | Alınacak bölüm / sınır |
|---|---|
| [Banaozel bağlantı akışı](/home/erkanoz/projeler/banaozel/app/lib/uyap/baglan_akisi.dart:125) | Toplu akışın ve kart çakışmasının inceleme kaynağı; `ikisi` akışı taşınmayacak |
| [Mobil e-Devlet görünümü](/home/erkanoz/projeler/banaozel/app/lib/uyap/edevlet_webview.dart:20) | Mobil API dönüş adresi ve masaüstü pencere deseni; sabit state/önek kontrolü aynen alınmayacak |
| [OAuth motor seçimi](/home/erkanoz/projeler/banaozel/app/lib/uyap/webview/oauth_webview_platform.dart:1) | Windows motorunun mobil adaptör yerine geçmediğinin kaynağı |
| [Mobil token adaptörü](/home/erkanoz/projeler/banaozel/app/lib/uyap/mobil_uyap.dart:27) | Restore/yenileme düşüncesi; uygulama hesabı ve sunucu paylaşımı alınmayacak |
| [Mobil API](/home/erkanoz/projeler/banaozel/app/lib/uyap/core/uyap/uyap_mobile_api.dart:673) | Token/DTO/uçlar; platform ve kasa bağımlılıkları ayrılacak, retry politikası değişecek |
| [İşlem/kanal sözleşmesi](/home/erkanoz/projeler/banaozel/app/lib/uyap/core/uyap/uyap_sonuc.dart:52) | İşlem bazlı yetenek ve normalize sonuç deseni |
| [Python mobil e-Devlet](/home/erkanoz/projeler/banaozel/server/uyap_mobil.py:1410) | Flow/state/tek kullanım/kimlik denetimi; sunucu DB saklama alınmayacak |
| [UETS kart girişi](/home/erkanoz/projeler/banaozel/app/lib/uyap/core/uets/uets_auth_service.dart:43) | Challenge/CAdES/authentication; geçersiz sertifika fallback'i alınmayacak |
| [Kart yardımcı süreci](/home/erkanoz/projeler/banaozel/app/lib/uyap/core/pkcs11/kart_surec.dart:30) | İşlem/PIN IPC ve süreç sonlandırma yaklaşımı; Folio runner'a uyarlanacak |
| [UETS mobil imza](/home/erkanoz/projeler/banaozel/server/uets_web.py) | Başlat/yokla/authentication; yerel Dart'a uyarlanacak |
| [UETS liste/indirme](/home/erkanoz/projeler/banaozel/app/lib/uyap/core/uets/uets_service.dart:134) | `start` ofseti, binary/paket ve timeout; SessionStore/runtime bağımlılıkları ayrılacak |
| [UETS konu eşleştirmesi](/home/erkanoz/projeler/banaozel/server/uets_web.py) | Konu/normalizasyon/aday kuralları; zayıf şehir eşleşmesi öneri olacak |
| [Web portal protokolü](/home/erkanoz/projeler/banaozel/server/uyap_web.py:236) | Çerez/state, web portföy/duruşma ve taze kimlik; sunucu kasa/korpus alınmayacak |
| [UETS analiz kancaları](/home/erkanoz/projeler/banaozel/server/katip_service.py) | Folio'ya taşınmayacak yan etkilerin kontrol kaynağı |
| [Ajanda birleştirme](/home/erkanoz/projeler/banaozel/app/lib/ajanda_birlesim.dart:1) | Tekilleştirme/sıralama fikri; sunucu kazanır ve otomatik süre alanları alınmayacak |
| [Mazeret canlı kontrolü](/home/erkanoz/projeler/banaozel/app/lib/uyap/mazeret_talebi.dart:22) | Taze duruşma/izin/gövde ve belirsiz sonuç kuralları |
| [Folio web servisi](</home/erkanoz/projeler/evrak convert/lib/services/uyap/uyap_web_service.dart:219>) | Tray/web protokolü korunacak; bağımsız adaptör ve mobil giriş görünümü eklenecek |
| [Folio giriş görünümü](</home/erkanoz/projeler/evrak convert/lib/ui/widgets/uyap_connect_view.dart:19>) | Web yöntemleri yeni üç kartlı bağlantı yüzeyine bağlanacak |
| [Folio yerel dosya deposu](</home/erkanoz/projeler/evrak convert/lib/services/uyap/uyap_case_store.dart:80>) | JSON/arşiv göçü, asıl/önizleme ve eski ilişkilerin korunması |
| [Folio dosya paneli](</home/erkanoz/projeler/evrak convert/lib/services/uyap/uyap_case_panel_controller.dart:14>) | Doğrudan web bağımlılığının repository'ye taşınması |
| [Folio mobil imza](</home/erkanoz/projeler/evrak convert/lib/services/signing/mobile_signature.dart:60>) | Belge mobil imzası korunacak; portal mobil imza girişiyle karıştırılmayacak |
| [Folio gönderim](</home/erkanoz/projeler/evrak convert/lib/ui/widgets/editor_widget.dart:2556>) | Snapshot/hash/imza ve son kontrol korunacak; masaüstü engeli yetenekle değişecek |
| [Folio zoom](</home/erkanoz/projeler/evrak convert/lib/ui/widgets/page_zoom.dart:25>) | Dar ekran ve otomatik/manuel sığdırma düzeltmesinin kaynağı |
| [Folio platform yetenekleri](</home/erkanoz/projeler/evrak convert/lib/services/platform/platform_capabilities.dart:1>) | iOS mobil imza ve platforma göre giriş adaptörü çalışması |

## 9. Portal verisi kuralları — Banaozel senkron incelemesi

Bu bölüm 6 Ekim 2026'da Banaozel'in Windows çalışma kopyası (`C:\Projeler\banaozel`) üzerinde yapılan incelemeye dayanır; kaynak atıfları §9.10'dadır. Banaozel'in sunucu, yapay zekâ ve korpus kısımları Folio'ya taşınmaz; yalnız protokol ve kural bilgisi alınır.

### 9.1 İncelemede bulunan durum

- Kanal seçimi Banaozel'de dört yerde ve birbiriyle çelişen kurallarla yapılıyor: `uyapKanalCoz` üretimde hiç çağrılmıyor (yalnız testte); masaüstü her işlemde önce web'i, sunucu önce mobili deniyor; sunucunun evrak tazelemesi Danıştay'ı mobilde desteklendiği hâlde web'e zorluyor. Folio'da kanal kuralı tek yerde olacak (§9.2).
- Mobil ve web turları arasında kilit yok; çakışmayı alan bazlı gözlem damgası önlüyor. Folio da bu modeli kullanacak (§9.4).

### 9.2 İşlem → kanal tablosu

| İşlem | Birincil | Yedek | Not |
|---|---|---|---|
| Yargı dosyası listesi (hukuk, ceza, icra, idari, istinaf) | Web + mobil | — | İkisi de sorulur ve birleştirilir; web toplu döküm verir, mobil web'in kapalı olduğu sürede tamamlar |
| Yargıtay dosyaları | Web | — | Mobil adaptörde bağlı değil |
| Cumhuriyet Başsavcılığı (soruşturma) dosyaları | Web | — | İl → birim → dosya; mobilde yok |
| Danıştay dosyaları | Web + mobil | — | İki kanalda da var; birleştirilir |
| Taraflar | Web | Mobil | Web duruşma kaydında da taraf gelir |
| Safahat, para/hesap, işlemler | Web | — | Safahat sorgusu kotalı ve kısmen ücretli |
| Künye | Web | Mobil | Web'de ayrı uç; mobilde dosya detayıyla gelir |
| Evrak listesi | Web | Mobil | Yargıtay ve Başsavcılık yalnız web |
| Evrak indirme | Web | Mobil | Yargıtay ve Başsavcılık yalnız web |
| Duruşma listesi | Web + mobil | — | İkisi de alınır ve birleştirilir (§9.7) |
| Evrak gönderme | Web | — | Mobil token web yetkisi yerine geçmez |
| Mazeret, e-duruşma | Mobil | — | Yazma işlemi; otomatik tekrar yok |

Web daha çok veri verir, mobil daha az ama daha uzun oturumludur: ikisi de bağlıysa okumada web önce sorulur, mobil web'in ulaşamadığını veya kapalı olduğu süreyi tamamlar; "Web + mobil" satırlarında iki kanalın sonucu §9.4 kuralıyla birleştirilir. Birincil bağlı değil ya da başarısızsa yalnız **okuma** yedeğe düşer; yazma düşmez. Kod: `lib/services/portal/portal_channel.dart`.

### 9.3 Web Portal ile Mobil API farkları

| | Web Portal (`avukat.uyap.gov.tr`) | Mobil API (`mobilws.uyap.gov.tr/portaldmz/services`) |
|---|---|---|
| Giriş | Adalet E-İmza ya da e-Devlet (e-imza/mobil imza); `code`/`state` aynı çerezlerle tamamlanır | e-Devlet → access + refresh token (Bearer) |
| Oturum | Yaklaşık 2 sa 55 dk; yenilemek yeniden imza ister | Yaklaşık 7 gün; gözetimsiz yenilenir |
| Yalnız bu kanalda | Yargıtay, Cumhuriyet Başsavcılığı, safahat, para, işlemler, evrak gönderme, harç/faiz | Mazeret, e-duruşma, hâkim notu, baro/TBB bilgisi |
| Dosya listesi | Yargı türleri 1/0/2/6/11/13; `search_phrase_detayli.ajx`, 500'lük sayfa | `yargibirimleri` → `mahkeme` → `dosya`; 100'lük sayfa |
| Evrak | `list_dosya_evraklar.ajx` (sayfalı), `view_document_brd.uyap` | `dosya/{id}/1` (`son20Evrak`, `tumEvraklar`), `evrakV2/{evrakId}/{dosyaId}` (base64) |
| Duruşma | `avukat_durusma_sorgula_brd.ajx`, en çok ~30 günlük pencere | `durusmalarim/{başlangıç}/{bitiş}`, 30 günlük dilim |
| Sınırlar | Aynı anda tek istek; safahat kotası | Arama mahkeme ya da yıl/sıra ister; `evrakV2` ara sıra 500 döner |
| Kimlikler | `dosyaId` oturuma bağlı; bayatlayınca `PRTL_GNL_10001-4` | `dosyaId` ve birim kimliği oturumluk; birim kimliği şifreli |
| Hata biçimi | 200 içinde `errorCode`; HTML/giriş sayfası oturum kaybıdır | Gövdedeki `status` ≠ 200 hatadır |

Web oturumu kısa olduğu için web turunda önce yalnız web'den gelen aileler (Yargıtay, Başsavcılık) ve web'e özgü alanlar alınır.

### 9.4 Portföy doldurma ve birleştirme

- Portföy iki kanaldan dolar: mobil yargı dosyalarını (açık/kapalı) ve tarafları; web §9.2'deki yalnız-web aileleri ve alanları ekler. Hangi kanal bağlıysa o doldurur; ikisi de bağlıysa her kanal kendi payını alır.
- Ortak anahtar `dosya_key` = sadeleştirilmiş (Türkçe harf katlama, küçük harf, boşluk sıkıştırma) dosya no | birim adı; icra yenileme eki kırpılır. Kanallar arası ayrı bir kimlik eşleme tablosu tutulmaz.
- Oturumluk kimlikler (`dosyaId`, mobil birim kimliği) kalıcı anahtar değildir. Web dosya kimliği yalnız ipucu olarak saklanır; bayatlarsa taze çözülüp güncellenir.
- Her bileşenin (künye, taraflar, safahat, para, evrak listesi) kendi gözlem anı vardır. Daha eski gözlem yeniyi ezmez; damgasız yazıcı en eski sayılır; boş değer dolu alanı, boş "tam" liste dolu listeyi silmez. Liste yazımı tek transaction'dır; iptalde eski hâl kalır.
- Kısmi veya hatalı tur "tamam" damgası almaz; yeniden deneme bekleme süresi artarak uzar. Bir aile (ör. Yargıtay) düşerse diğerleri devam eder.
- Yargıtay kaydının yerel mahkeme dosyasıyla bağı ve Başsavcılık tebliğnamesi ayrı dosya değil, ilgili dosyanın ilişkisi olarak tutulur.

### 9.5 Evrak indirme ve saklama

- Evrak §9.2'ye göre bağlı kanaldan iner; okuma olduğu için birincil başarısızsa diğer bağlı kanala düşülür. Mobilde 5xx için kısa aralıklarla sınırlı tekrar yapılır; her denemede dosya ve evrak kimliği taze çözülür.
- Evrak kimliği `stabil_no`: birim evrak numarası, yoksa evrak id; ekler `<ana>:ek:<n>`.
- Asıl ham baytıyla saklanır: içerik özetiyle adlandırılır, benzersiz geçici dosyaya yazılıp yeniden adlandırılır; kayıt tablosunda kaynak kanal, hash, MIME, boyut, tarih ve durum tutulur. Aynı içerik ikinci kez saklanmaz; okurken özet doğrulanır.
- Gösterim kopyası (TIFF → PDF vb.) asılın yerine yazılmaz. İmzalı asıl değiştirilmez; aynı evrak için farklı içerik gelirse yeni sürüm olarak kaydedilir.
- Biçim içerikten anlaşılır: ZIP içinde `content.xml` UDF, `word/` DOCX, EYP ayrıca tanınır; diğer ZIP'ler ZIP kalır.
- Boş yanıt, HTML veya giriş sayfası indirme başarısı sayılmaz.

### 9.6 Yeni evrak denetimi ve zamanlama

- "Yeni evrak" kararı dosya başına tutulan eşikle verilir. Dosya ilk kez incelendiğinde mevcut evraklar taban kabul edilir; ilk toplu arşiv yeni diye bildirilmez.
- Banaozel masaüstündeki hata alınmayacak: tur yalnız birkaç dosyaya bakarken eşik bütün kanal için ilerletiliyor, sırası seyrek gelen dosyadaki evrak kaçırılabiliyordu.
- Zamanlama: bağlantı anında ilgili kanalın turu; açık dosyaların evrak listesi tazelik süresi dolunca (Banaozel: 20 saat); hiç doldurulmamış dosyalar sınırlı dilimlerle, imleçle sırayla; dosya açılınca kısa soğuma süreli canlı tazeleme. Kesin süreler kullanıcı ayarı ve ölçümle belirlenir.
- Bir belgenin hatası yalnız o belgeyi işaretler; dosyanın kalanı ve tur devam eder. Sürekli düşen belgeler adıyla gösterilir.

### 9.7 Duruşma listesi ve dosya ilişkisi

- Mobil: `durusmalarim/{dd.MM.yyyy}/{dd.MM.yyyy}`, 30 günlük dilimler; hâkim notu ve e-duruşma alanları yalnız burada. Web: `avukat_durusma_sorgula_brd.ajx`, `d.M.yyyy`, 29 günlük dilimler. Düşen pencere eksik olarak işaretlenir.
- Tekil kimlik `olay_key` = sadeleştirilmiş, kırpılmış dosya no | birim adı | dakika. Web ve mobil kayıt kimlikleri ayrı alanlarda tutulur; alan bazlı gözlem damgası uygulanır; mobilin genel "Duruşma" türü web'in özel türünü ezmez.
- Duruşma dosyaya `dosya_key` ile bağlanır (yanıt başına değişen `dosyaId` kullanılmaz). Birimi dosyayla çelişen duruşma o dosyaya yazılmaz.
- Tarih değişirse yeni olay oluşur; eski kayıt yalnız hatasız ve dolu bir tarama penceresinde artık görünmüyorsa kaldırılır. Yalnız mobil bağlıyken eski kayıt silinmez, "doğrulanamadı" olarak kalır. Kullanıcının notu ve görevi kaynaktan ayrı sahiplikle korunur.

### 9.8 UETS tebligatının dosyayla ilişkisi

- Konu satırından `Birim adı [YYYY/N]` okunur; ilk köşeli parantez esas no, öncesi birim adıdır. Türkçe harfler katlanır, noktalama boşluğa çevrilir.
- Üç kademe; her kademede yalnız tek aday varsa bağ kurulur: (1) esas no + birim tam eşleşir; (2) dosya birimi tebligat biriminin önekidir (Yargıtay "… Tebligat Bölümü"); (3) ilk sözcük (yer adı) aynıdır (savcılık bürosu → Cumhuriyet Başsavcılığı). İki ve üstü aday belirsizdir, öneri olarak gösterilir.
- Elle bağ, düzeltme ve ayırma vardır; elle bağ otomatik değerlendirmeyle bozulmaz. Bağın yöntemi ve kanıtı saklanır.
- Portföy değiştiğinde bağsız ve belirsiz tebligatların tamamı yeniden değerlendirilir.

### 9.9 Banaozel'de bulunan, Folio'ya taşınmayacak hatalar

1. Çelişen kanal kuralları (§9.1).
2. Web yedeğinden indirilen evrakın arşivlenmemesi. Folio'da evrak hangi kanaldan inerse insin aynı saklama yolunu kullanır.
3. Kanal geneli yeni evrak eşiği (§9.6) ve tek belge hatasının turu kesmesi.
4. İndirmede paylaşılan sabit `.part` adı. Her yazım benzersiz geçici ad kullanır.
5. Her ZIP'in UDF sayılması ve EYP'nin tanınmaması.
6. Yerel duruşmaların aynı gün aynı türde birbirini ezmesi; kırpılmamış icra numarasıyla aynı olayın iki satıra bölünmesi.
7. Tebligatta "o numarada tek dosya varsa bağla" gevşek kuralı; yeniden değerlendirmenin en yeni 60 kayıtla sınırlı olması.

### 9.10 Kaynak atıflar (banaozel kökünden)

| Konu | Kaynak |
|---|---|
| Web portföy, Yargıtay, Danıştay, Başsavcılık, safahat, evrak, duruşma | `server/uyap_web.py` (dosya listesi 842-890, döküm 962-1156, duruşma 1187-1333, CBS 1503-1549, safahat 1840/1974, Yargıtay 2016-2303, evrak 2345-2459, kimlik 2490-2606, Danıştay 2688) |
| Mobil portföy, evrak, duruşma, kimlikler | `server/uyap_mobil.py` (84-99, 555-743, 1093-1108, 1769-1873, 3067-3145, 4029-4170) |
| Turlar, zamanlama, kanal düşmesi | `server/katip_service.py` (5622-6092, 12044-12341, 12785-13014, 13714-13963) |
| Gözlem damgası, anahtarlar | `server/katip_db.py` (229-261, 2806-2997, 5503-5507), `server/db/migrations/2026-10-31_denetim_kaynak_korumasi.sql` |
| UETS eşleştirme | `server/uets_web.py` (1937-2074), `app/lib/uyap/legal/tebligat_parser.dart` |
| Masaüstü kanal ve tazeleme | `app/lib/uyap/uyap_canli.dart`, `app/lib/uyap/core/uyap/uyap_sonuc.dart`, `app/lib/uyap/akilli_senkron.dart` |
| Yerel saklama ve kuyruk | `app/lib/uyap/uyap_db.dart`, `app/lib/arsiv/arsiv_kuyrugu.dart`, `app/lib/yardimci/runtime/work_coordinator.dart` |

## 10. Ekran kararı: Büro bölümü ve Ajanda (karar verildi, 6 Ekim 2026)

Kullanıcı `docs/design/ajanda-taslak.png` taslağını onayladı; uygulama bu görselin aynısı olacak (renk, yazı, kart, boşluklar). Kaynak HTML: `docs/design/ajanda-taslak.html`.

- **Kenar çubuğu:** Tüm Evraklar, Belgeler, Galeri'nin altında **BÜRO** bölümü: `UYAP Dosyalarım` (dosya sayısı) → `Ajanda` (bugünkü duruşma rozeti) → `UETS Tebligatlarım` (okunmamış sayısı). Klasörler altta kalır.
- **Ajanda üst satırı:** başlık, tarih gezinmesi (‹ Bugün ›), Gün/Hafta/Ay/Liste, `Not / iş ekle`; altında kanal durumu çipleri (UYAP Mobil, UYAP Web, UETS: güncellik veya yeniden bağlan).
- **Özet kartları:** bugünkü duruşma, bu hafta duruşma, süresi yaklaşan, açık iş/not.
- **Haftalık takvim:** duruşma mavi, e-duruşma yeşil, süre kırmızı, not/iş turuncu; şimdiki saat çizgisi; "Duruşmalar UYAP Mobil ve Web'den birleştirildi" notu.
- **Sağ panel:** seçili duruşmanın hazırlık kartı (mahkeme, esas, taraflar, işlem, salon, kaynak kanal, son evraklar, notlarım ve işlerim, Dosyayı aç / Dilekçe başlat / Mazeret) ve yaklaşan süreler.
- Bağlantı kartları, ilgili ekranın kanal çipine tıklanınca açılır; Ayarlar'da da bulunur. UETS Tebligatlarım ve mobil yerleşimi aynı görsel dille ayrıca tasarlanır.

## 11. Süre motoru kararı

Banaozel'in süre motoru (`app/lib/uyap/legal/` ve `app/lib/legal/sure_katalogu.dart`) saf Dart'tır: ağ, yapay zekâ, veritabanı ve Flutter bağımlılığı yoktur; `now` parametreyle verilir. Folio'ya `lib/services/legal/deadlines/` altına taşınacak (T8).

- Taşınacak dosyalar: `sure_katalogu.dart`, `mahkeme_kategori.dart`, `belge_turu.dart`, `turkish_legal_calendar.dart`, `tebligat_parser.dart`, `yasal_sure.dart`, `deadline_service.dart`; isteğe bağlı `icra_sure.dart`. `yasal_sure.dart` içindeki göreli katalog yolu yeni dizine göre düzeltilecek.
- Kapsam: HMK istinaf/temyiz/cevap/bilirkişi itirazı, İİK m.16/62/67/168/32-33/89, CMK m.273/291 (7499 geçişiyle), İYUK m.45/46; e-tebligatta gönderim +5 gün; adli tatil (hukuk/idare/vergi 7 Eylül, ceza +3 gün ve 1 Eylül başlangıcı, icra uzamaz, HMK m.103 kapısı); mali tatil; hafta sonu/resmî tatil/bayram kaydırması (dini bayramlar 2026'ya kadar resmî, sonrası projeksiyon).
- Taşırken düzeltilecekler: (1) ay/yıl eklemesi `DateTime(y, m+n, d)` taşması (31 Ocak + 1 ay = 3 Mart) ayın son gününe kıstırılacak (HMK m.92), `icra_sure.dart` ile aynı kural; (2) projeksiyon yılı (2027+) ve tanımsız yıl (2031+) bütün yollarda uyarı/güven düşürme üretecek; bayram tanımsızsa süre "doğrulanamadı" olur, sessizce iş günü sayılmaz.
- Alınmayacaklar: LLM ile belge türü, m.103 tabiiyeti ve zabıttan süre çıkarımı (`server/tebligat_tur.py`, `adli_tatil_kapsami.py`, `zabit_sure.py`, `uets_belge_suresi.py`). Folio'da belge türü ve m.103 bilgisi kullanıcı seçimi veya kurallı ayrıştırmayla gelir; bilinmiyorsa motorun güvenli (erken) yönü kullanılır ve not gösterilir.
- Testler taşınır (`deadline_service_test`, `icra_sure_test`, `karar_tarihi_sure_baslangici_degil_test`); eksik olanlar eklenir: bayram/resmî tatil kaydırması, iş günü birimi, mali tatil, ay/yıl sonu kıstırma, projeksiyon uyarısı.

## 12. Uygulama sırası ve durum

Her madde bitince commit edilip GitHub'a gönderilir; durum burada güncellenir.

| # | İş | Paket | Durum |
|---|---|---|---|
| T1 | Ekran kararı ve iş sırası plana işlendi | §10 | Tamam |
| T2 | Banaozel süre motoru incelemesi; kullanılabilirse taşıma kararı | P10 | Tamam: taşınacak (§11) |
| T3 | Kanal ve işlem → kanal tablosu (§9.2), testleriyle | P01 | Tamam |
| T4 | Gözlem damgalı birleştirme: web ve mobil birbirini ezmez, eksiklerini tamamlar (§9.4) | P06/P07 | Tamam |
| T5 | Yerel portal veritabanı: dosya, duruşma, not/iş | P02 | Tamam |
| T6 | Web duruşma listesi (29 günlük pencereler), normalize ve birleştirme | P10 | Tamam |
| T7 | Kenar çubuğu BÜRO bölümü ve Ajanda ekranı (taslağın aynısı) | P10/P11 | Tamam (önizleme: `tool/agenda_preview.dart`) |
| T8 | Süre motoru ve yaklaşan süreler | P10 | Tamam (`lib/services/legal/deadlines`, Ajanda'da "Süreyi hesapla") |
| T9 | UYAP Mobil API girişi, portföy ve duruşma; web ile birleştirme | P04/P07 | Tamam (gerçek hesapla kabul P16'da) |
| T10 | UETS girişi, Tebligatlarım ekranı ve dosya eşleştirme | P05/P08/P09 | Sırada |

## Ek A — İncelenen Banaozel dosyalarının içerik hash'leri

Hash'ler inceleme anındaki yerel dosyalara aittir; bu kaynaklar ileride değişirse taşıma öncesi fark yeniden incelenmelidir.

```text
c30598ffa146fbb8d47e9da3f1217b822486c7ce7f84eb80684e801c47347e7e  app/lib/uyap/baglan_akisi.dart
df7c184eb1baf60ab1857d4dbd6c74661ef86131cf467fa465ac677840968b1e  app/lib/uyap/edevlet_webview.dart
caac14400c98985c250908c2cd8d5c15da4b90fd227fc7275bdd670369c5fad5  app/lib/uyap/mobil_uyap.dart
e0c711ab0d8f4bf04ce57f0dda5ff5e909da46d5fca9220c87249f1579409d1e  app/lib/uyap/core/uyap/uyap_mobile_api.dart
b0d3c9f1a55833d8d5fbad4bc26646bcd9a929c42987763523bd9fc1c0fbbb39  app/lib/uyap/core/uyap/uyap_sonuc.dart
370f8aa543bde8b319a2307ec9f80256ee680dc78ffb066699f3b6382ab406c2  app/lib/uyap/core/uets/uets_auth_service.dart
49c1d8dd7657a857a07fe224f16d5c9f612eedceb8cd9e9b535e45b1a854b523  app/lib/uyap/core/uets/uets_service.dart
28b9d710b19c65db0667c70bc8415423baf47ed605775ebf9de096a5838ab5a9  app/lib/uyap/core/pkcs11/kart_surec.dart
c350b2483bf6788a14e1e91021a46a657c7acd762fc4ae3fa0e8501a18cf3965  server/uets_web.py
ca60a26b896ad8647dac827571be15cde8333622a4ad5a6130b4c7fe90d63885  server/uyap_web.py
cf3ed7b9ced0f86d7d27f8871ba4fdbc81482958038039b702829d542541a990  server/uyap_mobil.py
3918f029d1445eb649ea2d49e9d6717a536ae3e5064c6f9aad018db96892126a  server/katip_service.py
```

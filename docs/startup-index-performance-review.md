# LifeOS Folio — Windows ve Linux açılış ve indeks performansı incelemesi

Tarih: 14 Eylül 2026  
İncelenen uygulama sürümü: `36c70cb`  
Kapsam: masaüstü başlangıcı, kalıcı indeks, değişiklik izleme ve tekrar kontrol. Bu rapordaki öneriler henüz uygulanmış değişiklikler değildir.

## 14 Eylül 2026 — Uygulama durumu

Aşağıdaki inceleme başlangıçtaki durumu anlatır. Bu rapordan sonra şu iyileştirmeler uygulandı:

- Dosya olayları yol bazında, 180 ms'lik küçük gruplarla kalıcı SQLite kuyruğuna aktarılır. Tek dosya değişikliği/silmesi tam kaynak taraması başlatmaz; yeni alt klasör doğrudan kendi kapsamıyla taranır.
- Kuyrukta daha eski bir iş tamamlandığında aynı yolun daha yeni bildirimi silinmez. İşlenmemiş bildirimler yeniden başlatmada sürdürülür. Olay kaybı/izleyici hatasında izleme yeniden kurulur ve uzlaştırma istenir.
- Klasör yürüyüşü metadata kayıtlarını doğrudan üretir; indeksleme için alfabetik yol sıralaması kaldırıldı. Aynı tarama grubundaki iç içe kaynaklar ortak metadata listesini ve tek izleyici kökünü kullanır; kaynak üyelikleri korunur.
- Değişmeyen belgeler ve mevcut kaynak üyelikleri yeniden yazılmaz. Eksik dosya tespiti için geçici, bellekteki `scan_seen` tablosu kullanılır. Kaynak tarama zamanı gibi küçük yönetim kayıtları yazılmaya devam eder.
- İçerik çıkaran isolate bir indeksleme grubu boyunca tekrar kullanılır; zaman aşımında/iptalde sonlandırılır ve sonraki iş için yeniden oluşturulur. Grup bittiğinde bırakılır.
- Flutter arayüzü native pencerenin gösterilmesi beklenmeden kurulmaya başlar. `FOLIO_STARTUP_TRACE=1` ile ilk Flutter karesi ve indeks/ilk sonuç hazırlığı ayrı ölçülebilir. Süreler Flutter motorundan önceki native süreç başlangıcını kapsamaz.
- Pencerenin normal boyutu, büyütülmüş ve tam ekran durumu kalıcı saklanır. Tray arama penceresinin geçici boyutu bu ayarı değiştirmez.
- Önizlemenin sol listesindeki Yukarı/Aşağı, Home/End gezinmesi Enter gerektirmeden seçili belgeyi açar. 110 ms bekleme, basılı tutulan tuşla geçilen her ara belgenin çözülmesini önler. Arşiv listesinde oklarla seçim, Enter ile açma sürer.
- UDF imzası aynı kaynak yoluna atomik dosya değişimiyle kaydedilir; imza öncesi sürüm belge geçmişinde tutulur. İmzalama sırasında kaynak baytları değişmişse yeni içerik ezilmez. Kalıcı bir `_imzali_…` klasörü oluşturulmaz.

Doğrulama: tam test paketinde 148 test geçti. 1.000 değişmeyen kayıtta karşılaştırma 43 ms ölçüldü; belge/kaynak üyeliği tablolarında tekrar yazma sayısı sıfırdı. Bu ölçüm sentetik veritabanı testi olup dosya sistemi veya uygulamanın toplam açılış süresi değildir. Son kuyruk sorgusu düzenlemesinden sonra ilgili 7 test tekrar geçti; statik analiz temiz. Linux release derlemesi başarılı oldu ve sanal X11 ekranında geçici profille gerçek TXT önizlemesi açılarak görsel kontrol yapıldı. Bu sanal ekran kontrolü donanımlı GNOME/Windows performans ölçümü değildir.

**Açık kalan platform aşaması:** Windows USN günlük entegrasyonu uygulanmadı. Standart kullanıcı izinleri, dosya kimliği/yol eşlemesi ve günlük sürekliliği gerçek Windows üzerinde doğrulanmalıdır. İlgili API sınırları için [Microsoft USN belgesi](https://learn.microsoft.com/en-us/windows/win32/api/winioctl/ni-winioctl-fsctl_read_usn_journal) referans alınır. Windows ve Linux'ta tamamen kapalı geçirilen süredeki değişiklikleri kaçırmamak için soğuk açılışta arka plan metadata uzlaştırması devam eder. Windows native pencere davranışı ve fiziksel e-imza kartı bu Linux ortamında canlı doğrulanmadı.

## Sonuç

Uygulama her açılışta belgelerin metnini yeniden çıkarmıyor. Kalıcı SQLite/FTS5 indeksi kullanılıyor. Ancak her yeni süreç başlangıcında kayıtlı kaynaklar yeniden dolaşılıyor ve desteklenen dosyaların boyut, değiştirilme ve metadata değişiklik zamanları karşılaştırılıyor. Yeni, değişmiş veya yarım kalmış belgelerin içeriği yeniden indeksleniyor.

En önemli iyileştirme, tek dosya değiştiğinde bütün kaynak klasörü taramak yerine doğrudan o dosyayı güncellemek. Soğuk açılış için de ilk ekran, aramanın hazır olması ve arka plan kontrolünün bitmesi ayrı performans hedefleri olarak ele alınmalı.

## Mevcut başlangıç akışı

1. Windows/Linux üzerinde tek süreç kilidi ve yerel iletişim soketi hazırlanır. Mevcut süreç varsa açma isteği ona iletilir.
2. Native pencere yöneticisi başlatılır; pencerenin gösterilmesi ve odaklanması beklenir.
3. `runApp` çağrılır ve Flutter arayüzü kurulur.
4. Kütüphane, SQLite indeksini ayrı bir isolate içinde açar.
5. Katalog ve kayıtlı arama sonuçları alınır. Kaynakların izleyicileri katalog yüklenirken kurulur.
6. Kaynaklar tam metadata karşılaştırması için kuyruğa eklenir.
7. Değişen belgelerin metni arka planda çıkarılır.

Ana sayfa kütüphane başlangıcını beklemeden oluşturulur. `refresh` isteği de taramanın tamamlanmasını değil, kuyruğa alınmasını bekler. Dolayısıyla mevcut yapı zaten tarama tamamlanmadan kayıtlı indeksten aramaya izin verir. Yine de tarama disk, işlemci ve indeks worker'ı için ek yük oluşturabilir.

Kod kaynakları: [başlangıç](../lib/main.dart), [ana sayfa](../lib/ui/home_page.dart), [kütüphane denetleyicisi](../lib/services/search/library_controller.dart), [tek süreç yönetimi](../lib/services/desktop/desktop_instance.dart).

## Hangi işlem ne zaman tekrarlanıyor?

| Durum | Mevcut davranış |
|---|---|
| Uygulama tamamen kapalıyken açılması | Kaynakların tamamı dolaşılır ve dosya metadata'sı karşılaştırılır |
| Tray'deki çalışan pencerenin yeniden açılması | Aynı süreç ve mevcut indeks kullanılır; pencere açılması tek başına kütüphaneyi yeniden başlatmaz |
| Değişmeyen belge | Metin yeniden çıkarılmaz; tarama sırasında metadata ve kaynak üyeliği işlenir |
| Yeni veya değişmiş belge | İçerik okunur ve FTS kaydı güncellenir |
| Yarım kalmış (`pending`) belge | İçerik çıkarma tekrar denenir |
| Hatalı (`error`) belge | Dosya değişirse veya zorunlu yeniden tarama istenirse tekrar denenir |
| Çalışırken tek dosyanın değişmesi | 700 ms olay birleştirme süresinden sonra ilgili kaynağın tamamı yeniden taranır |
| Kullanıcının zorunlu yeniden taraması | İlgili belgelerin içerikleri yeniden çıkarılır |

Değişiklik kararı dosya boyutu ve zaman damgalarına dayanır; her kontrolde içerik özeti hesaplanmaz. Bu hız sağlar ancak boyut ve zaman damgalarının korunduğu bazı dış müdahaleleri yakalama garantisi vermez.

Kod kaynakları: [tarama ve iş kuyruğu](../lib/services/search/index_service.dart), [metadata karşılaştırması](../lib/services/search/index_database.dart).

## Ölçümler ve sınırları

### Yerel Linux incelemesi

| Ölçüm | Sonuç |
|---|---:|
| İncelenen kaynak klasördeki normal dosya | 2.761 |
| Desteklenen ve indekslenen belge | 2.210 |
| Metin içeriği hazır belge | 1.736 |
| Metinsiz belge | 288 |
| Görsel | 175 |
| Hatalı belge | 11 |
| Bekleyen belge | 0 |
| SQLite dosyası | 42.209.280 bayt, yaklaşık 40,3 MiB |
| WAL dosyası | Yaklaşık 5,2 MiB |
| Kayıtlı çıkarılmış metin | Yaklaşık 11,1 MiB |
| Duruma göre belge sayımı | Yaklaşık 0,67 ms |
| `karar*` için 1.192 eşleşmeli doğrudan FTS sorgusu | Yaklaşık 5 ms |
| Sıcak dosya sistemi önbelleğiyle klasör yürüyüşü | Üç koşuda yaklaşık 3 ms |
| Klasör yürüyüşü ve tüm normal dosyalara metadata erişimi | Üç koşuda yaklaşık 7–10 ms |

Dosya sistemi süreleri `find` ve `stat` ile alınmış kabuk ölçümleridir; Dart'ın tarama, sıralama, isolate iletişimi ve SQLite kayıt güncelleme maliyetlerini kapsamaz. FTS ölçümü uygulamadaki sıralama, alıntı üretimi ve ekran çiziminin uçtan uca süresi değildir. Linux release uygulamasının soğuk açılış süresi bu incelemede ölçülmedi. Bu sonuçlar mevcut yerel klasörün sıcak önbellekle hızlı erişilebilir olduğunu gösterir; ağ, bulut, harici disk veya çok daha büyük arşivler için genellenemez.

İndekste aynı kaynak klasörün içinde bulunan üç belge ayrıca tekil kaynak olarak kayıtlı. Belge satırları tekilleşse de bu kaynakların tarama ve izleme işi tekrarlanabilir.

### Daha önce kaydedilmiş Windows ölçümleri

11 Eylül 2026 tarihli [inceleme notlarında](../INCELEME_NOTLARI.md) şu sonuçlar bulunuyor:

- Klasör ağacında 34.606 giriş; bunların 4.587'si indekslenebilir.
- Eski sürümde 764 hatalı belge tekrar tekrar ayrıştırılıyordu; bulut üzerinde olup yerelde okunamayan dosyalar önemli bir kaynaktı.
- Dosya başına SQLite işlemleri ve her başlangıçta tam tablo işlemleri ek yük oluşturuyordu.
- Düzeltmelerden sonra ölçülen yazma miktarı 132,9 MB'den 0,4–0,5 MB'ye indi; ölçülen boşta CPU tüketimi giderildi.
- Açılış 5–6,5 saniye aralığında kaldı.
- Başlangıç taramasını yalnız geciktirme denemesi 6.069 ms ortalamadan 5.513 ms'ye düştü; yüksek varyans nedeniyle anlamlı kazanç olduğu gösterilemedi ve değişiklik geri alındı.

Bu Windows sayıları önceki rapordan alınmıştır; bu turda Windows üzerinde yeniden ölçülmedi. Motor/pencere başlangıcı ve klasör yürüyüşü ayrı ayrı zamanlanmadığından toplam gecikmenin ne kadarının her bileşene ait olduğu henüz kanıtlanmış değildir.

## Darboğazlar

### 1. Dosya olayının bütün kaynağı taratması

İzleyici bir dosyanın değiştiği yolu zaten bildiriyor. Buna rağmen denetleyici `refresh(ids: [source.id])` çağırıyor. Büyük arşivde tek DOCX kaydı, bütün kaynak için metadata karşılaştırmasına dönüşüyor. Olayları 700 ms birleştirmek kısa patlamaları azaltır fakat bu maliyeti kaldırmaz.

### 2. Listeleme, sıralama ve ikinci geçiş

`FileLibrary.collect` desteklenen yolları topluyor ve alfabetik sıralıyor. Sonra indeks servisi bu yolların her biri için `stat()` çağırıyor. Tarama metadata taşıyan kayıtları doğrudan üretmeli; yalnız indeks kontrolü için kullanılan global sıralama kaldırılmalı. Bu, bütün metadata sistem çağrılarını ortadan kaldırmaz fakat ikinci geçişi ve ara liste maliyetini azaltır.

### 3. İlk Flutter ekranından önce beklemeler

Tek süreç yönetimi ve native pencere hazırlığı `runApp` öncesinde bekleniyor. Bu aşamalar zamanlanmalı ve güvenle bağımsız yürütülebilen işler birlikte başlatılmalı. Tek indeks sahibi garantisi korunmalı; yalnız pencereyi erken göstermek aramanın da erken hazır olduğu anlamına gelmez.

### 4. Değişmeyen dosyalar için de veritabanı işi

500 kayıtlık işlemler önceki dosya başına commit sorununu azaltmış durumda. Ancak her dosya için mevcut satırı okuma, upsert ve kaynak üyeliği yazımı sürüyor. Parça bazlı mevcut kayıt okuma ve yalnız gerekli metadata yazımları değerlendirilmeli. Silinen dosyaların tespitini sağlayan tarama işaretleri korunmalı.

### 5. Her içerik çıkarımı için ayrı isolate

Yeni/yeniden indekslenen her belge için yeni isolate oluşturuluyor. Başlangıçta değişiklik yoksa etkisi sınırlı; ilk klasör ekleme ve toplu güncellemede kalıcı, sınırlı sayıda worker daha verimli olabilir. Zaman aşımı yaşayan ayrıştırıcıyı sonlandırma ve worker'ı yeniden oluşturma davranışı korunmalı.

### 6. Örtüşen kaynaklar ve izleyiciler

Altındaki tekil dosyaların ayrıca eklendiği klasörlerde veya iç içe kaynaklarda iş tekrarlanabilir. Kaynak üyeliği korunarak tarama kökleri ve izleyiciler tekilleştirilmeli.

## Önerilen mimari

### Önce kayıtlı indeks, ardından güncellik kontrolü

İlk ekran, aramanın hazır olması ve tam uzlaştırmanın bitmesi ayrı aşamalar olarak yönetilmeli. Mevcut indeks hemen kullanılmalı; güncellik kontrolü sürerken sonuçlar açık kalmalı. Disk erişimi ve sorgu gecikmeleri ölçülerek arka plan işleri küçük, kesilebilir parçalara ayrılmalı.

### Dosya bazında güncelleme

| Olay | Hedef işlem |
|---|---|
| Dosya ekleme | Yalnız ilgili dosyayı kontrol et ve indeksle |
| Dosya değiştirme | Yalnız ilgili dosyanın metadata'sını karşılaştır; gerekiyorsa içeriği çıkar |
| Dosya silme | İlgili kaydı/kaynak üyeliğini kaldır |
| Yeni alt klasör | Yalnız yeni alt ağacı tara |
| Yeniden adlandırma | İzleyicinin bildirimine göre eski/yeni yolları uzlaştır |
| Olay kaybı veya izleyici hatası | Kaynağı tam uzlaştırma için işaretle |

Olaylar yol bazında birleştirilmeli, kalıcı bekleyen iş kuyruğuna yazılmalı ve başarılı indeks güncellemesiyle tamamlandı olarak işaretlenmeli. Okuma sırasında tekrar değişen belgeler yeniden kuyruğa alınmalı. Başlangıçta izleyici kurulumu ile tarama arasındaki olaylar da kaybolmamalı.

### Windows yaklaşımı

Çalışan süreçte mevcut yerel izleyici kullanılmalı. Tamamen kapalıyken gerçekleşen değişiklikler için NTFS USN Change Journal olası bir ikinci aşamadır. Bu destek uygulanmadan önce normal kullanıcı izinleri, hacme erişim, günlük sıfırlanması/taşması ve dosya kimliğinden yola eşleme ayrı bir prototiple doğrulanmalı. Yönetici yetkisi gerektiren bir tasarım varsayılan masaüstü akışı kabul edilmemeli.

USN kullanılamayan disklerde, ağ/bulut kaynaklarında veya günlük sürekliliği kaybolduğunda arka plan tam uzlaştırması sürmeli. Yerelde bulunmayan bulut dosyaları gereksiz içerik okumasına zorlanmamalı. Uygulama paketleme ve güvenlik yazılımının başlangıca etkisi ancak ayrı soğuk açılış ölçümleriyle değerlendirilmelidir.

### Linux yaklaşımı

Çalışan süreçte mevcut native klasör izleyicisi kullanılmalı. Uygulama tamamen kapalıyken oluşan olaylar bu izleyici tarafından kaydedilemez. Tray'de çalışma ve kalıcı olay kuyruğu, süreç açık kaldığı sürece güncelliği korur. Tam çıkıştan sonraki başlangıçta arka plan uzlaştırması gerekir.

Temiz kapanış işareti tek başına bu kontrolü kaldırmaya yeterli değildir; kapanıştan sonra dosyalar değişebilir. Yalnız üst klasörün tarihine bakarak içerik değişikliklerinin tamamının yakalandığı varsayılmamalı. İzleyici kurulamadığında veya olay sürekliliği kaybolduğunda tam kontrol geri dönüş yolu bulunmalı.

## Kullanıcıya gösterilecek kontrol düzeyleri

| İşlem | Açıklama |
|---|---|
| Arama hazır | Kalıcı indeks kullanılabilir |
| Değişiklikler kontrol ediliyor | Diskteki dosyalar indeksle karşılaştırılıyor |
| Yeni/değişen belgeler indeksleniyor | Yalnız gerekli belgelerin metni çıkarılıyor |
| Tüm içerikleri yeniden indeksle | Kullanıcının açık isteğiyle kapsamlı içerik çıkarımı |

Bu ayrım, her başlangıçtaki metadata kontrolünün kullanıcıya baştan indeksleme gibi görünmesini önler.

## Uygulama öncelikleri

1. İlk ekran, indeks açılışı, ilk sonuç, tarama ve içerik çıkarma aşamalarını ayrı ölçmek.
2. İzleyici olaylarını dosya bazında işlemek; olay kaybında tam taramaya dönmek.
3. Kalıcı iş kuyruğu, olay birleştirme ve tray'de süreklilik sağlamak.
4. Tarama köklerini tekilleştirmek; listeleme ve metadata karşılaştırmasını parçalara ayırmak; gereksiz sıralamayı kaldırmak.
5. Arama gecikmesini koruyarak SQLite okuma/yazma işini azaltmak.
6. Native başlangıç beklemelerini ölçümlere göre düzenlemek.
7. Toplu indeksleme için sınırlı, tekrar kullanılan çıkarım worker'larını değerlendirmek.
8. Windows USN desteğini izinler ve geri dönüş davranışıyla prototiplemek.

## Doğrulama planı

Windows ve Linux release paketlerinde soğuk süreç başlangıcı ile tray'den pencere açılışı ayrı ölçülmeli. Soğuk süreç başlangıcı ile işletim sistemi disk önbelleğinin soğuk olması da birbirinden ayrılmalı.

- Değişmeyen 2 bin, 10 bin ve 100 bin belgeli arşivlerde ilk ekran/ilk arama/tam kontrol süreleri.
- Tek dosya ekleme, düzenleme ve silmede yalnız ilgili dosyanın işlenmesi.
- Yeni alt klasör, toplu taşıma ve örtüşen kaynaklarda doğru üyelikler.
- Uygulama tamamen kapalıyken değişen dosyaların sonraki açılışta bulunması.
- İzleyici hatası, olay kaybı, çıkarım sırasında dosya değişmesi ve beklenmeyen süreç kapanışından toparlanma.
- OneDrive çevrimdışı belge, erişilemeyen ağ klasörü ve çıkarılan harici diskte mevcut indeksin korunması.
- İndeksleme devam ederken ana pencere ve tray aramasının gecikmesi; CPU, disk yazma ve bellek tüketimi.

Kesin saniye veya yüzdesel hızlanma taahhüdü için uçtan uca release ölçümü gerekir. Beklenen mimari kazanç, tek dosya değişikliğinin tüm arşivi dolaştırmaması ve kullanıcının mevcut indeksle hemen çalışabilmesidir.

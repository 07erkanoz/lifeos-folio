# LifeOS Folio teknik inceleme — 21 Eylül 2026

## Kapsam ve sonuç

Bu inceleme Flutter/Dart uygulama katmanını, Windows ve Linux çalıştırıcılarını, Android belge köprüsünü, kalıcı arama indeksini, OCR akışını, PDF önizleme/düzenleme sınırlarını ve telefon yerleşimlerini kapsar. Proje yaklaşık 36 bin satır Dart kodu ile geniş bir otomatik test paketine sahiptir. Genel mimari sağlıklıdır: önizleme varsayılandır, kaynak dosya korunur, ağır indeks ve belge ayrıştırma işleri UI isolate'ından ayrıdır.

Bu turda bulunan ve giderilen somut sorunlar:

- OCR klasör kapsamı SQL `LIKE` ile kuruluyordu. Yol adındaki `%` ve `_` karakterleri joker olarak yorumlanıp yanlış klasörlerin OCR'a girmesine neden olabiliyordu. Kapsam artık ayıraçlı, birebir önek karşılaştırması kullanıyor; Unicode/emoji içeren yollar da SQLite'ın kendi karakter uzunluğuyla hesaplanıyor.
- OCR açıkken kapsam değiştirildiğinde yeni kapsama giren belgeler ayarı kapatıp açmadan kuyruğa alınmıyordu. Kapsam değişikliği artık uygun belgeleri hemen kuyruğa alıyor.
- OCR aday sayısı boş TXT/Office belgeleri ve SVG gibi Tesseract'ın iyileştiremeyeceği dosyaları da sayıyordu. Adaylar gerçekten OCR uygulanabilen PDF/raster biçimleriyle sınırlandırıldı.
- 64 MB sınırını aşan belge, bilinçli bir kaynak sınırı olmasına rağmen "hata" sayılıyordu. Artık "yalnız dosya adı aranabilir" grubunda raporlanıyor.
- Yirmi sayfadan uzun taranmış PDF'lerde yalnızca ilk 20 sayfanın OCR ile okunduğu sonuç durumuna yansımıyordu. Bu belgeler artık `partial` olarak ve açık notla kaydediliyor.
- PDF metin katmanı zaten ara belge modeline çevrilebildiği halde PDF için editör girişi kapalıydı. PDF'ye **Düzenle** eklendi. Kullanıcıya kayıpsız nesne düzenleme olmadığı açıkça anlatılıyor; kaynak PDF değiştirilmiyor ve sonuç yeni UDF/DOCX/RTF/PDF olarak kaydediliyor. Windows ve Linux sağ tık "düzenle" kayıtları da PDF'yi kapsıyor.
- Android'de içerik sağlayıcısı bildirimlerine ve uygulamanın öne dönüş taramasına ek olarak her 30 saniyede tam SAF ağacı dolaşılıyordu. Bildirim vermeyen sağlayıcılar için geri dönüş kontrolü beş dakikaya indirildi ve yalnız bağlı klasör varsa çalışıyor.
- Metin PDF'sini düzenlemeye açarken dosya ikinci kez tamamen ayrıştırılıyor, satırlar tahmini olarak birleştiriliyor ve uzun metin yazım/mevzuat taramasına gönderiliyordu. Editör metni ve karakter biçimini PDFium üzerinden birlikte alıyor; font, punto, kalın/italik ve renk karakter konumlarıyla eşleştiriliyor. Arama indeksindeki düzleştirilmiş metin editör içeriği olarak kullanılmıyor. Ayrıştırma worker isolate'ında yapılıyor ve PDF aktarımında yardımcı tam-belge taramaları kapalı tutuluyor. OCR yalnız metin katmanı olmayan taramalarda devreye giriyor.
- Word/LibreOffice panosundaki `text/html` daha önce düz metne düşüyor, fontlar ve tablolar kayboluyordu. Windows Win32 ve Linux GTK pano köprüleri HTML, RTF ve UYAP EditorDataFlavor verisini ortak belge modeline bağlıyor. Font, punto, renk, kalın/italik/altı çizili, liste/paragraf özellikleri ve tablolar düzenlenebilir Quill/UDF yapısına çevriliyor; bir biçim çözülemezse panodaki diğer biçimli sürümler deneniyor; biçimli veri bulunamazsa normal Quill yapıştırma yolu kullanılıyor.

## Mimari değerlendirme

### Arama ve indeks

SQLite FTS5 + WAL doğru seçimdir. Veritabanı tek arka plan isolate'ına ait; arama, katalog ve yazma sıralı olduğu için kilit karmaşası düşüktür. Dosya olayları kalıcı kuyruğa yazılıyor, tek dosya değişikliği tam klasör taramasına dönüşmüyor, değişmeyen kayıtlar yeniden yazılmıyor. 10.000 sentetik kayıtlı mevcut test FTS sorgusunu milisaniyeler düzeyinde tutuyor.

Soğuk açılışta uygulama kapalıyken olan değişiklikleri yakalamak için kaynak ağacı yine metadata seviyesinde dolaşılıyor. Yerel SSD'de kabul edilebilir olan bu maliyet ağ diski, OneDrive veya 100 bin dosyalı arşivde baskın hale gelebilir. Windows için USN Journal prototipi ancak normal kullanıcı izinleri ve journal sürekliliği doğrulandıktan sonra eklenmelidir. Linux'ta uygulama kapalıyken inotify olayı tutulmadığı için başlangıç uzlaştırması doğruluk açısından kalmalıdır.

### OCR

Arşiv OCR'ı ile kullanıcının ekranda istediği dikkatli OCR modelinin ayrılması doğrudur. PDF sayfaları 200 DPI gri PGM olarak Tesseract'a boru üzerinden veriliyor; geçici sayfa görseli yazılmıyor. Hızlı model, sayfa başına zaman aşımı, dosya/sayfa/metin sınırları ve iptal edilebilir ayrıştırıcı isolate arşiv kullanımı için uygun korumalardır.

Kalan sınır: çok sayfalı TIFF tek Tesseract sürecine veriliyor. Zaman bütçesi 20 sayfada sınırlı olsa da girdi fiziksel olarak ilk 20 sayfaya kesilmiyor. Çok uzun TIFF'lerde ilk N sayfayı kayıpsız ayıran, iptal edilebilir bir akış ayrı performans çalışması olarak ele alınmalıdır.

### PDF düzenleme

Uygulamada iki farklı kavram ayrı tutulmalıdır:

1. Mevcut PDF üzerine yerel vurgu/not eklemek: kaynak baytları ve elektronik imza korunur, fakat işaretler Folio veritabanındadır ve başka PDF okuyucuda görünmez.
2. PDF metnini yeni bir düzenlenebilir belgeye aktarmak: metin değiştirilebilir, ancak PDF'nin kesin geometrisi, font nesneleri, form alanları, imzalar ve ek açıklamalar yeniden kurulmaz.

Bu turda ikinci akış arayüze açıldı. Gerçek PDF nesne düzenleme veya vurguları kaynak/kopya PDF'ye gömme ayrı ve daha büyük bir özelliktir. İmzayı geçersiz kılacağı için varsayılan davranış mutlaka "yeni kopya" olmalıdır. Taranmış PDF'nin indekslenmiş OCR metnini doğrudan editöre aktarma henüz bağlı değildir.

### Windows ve Linux

Native araçlar uygulamayla paketleniyor ve kullanıcının PATH durumuna bağlı değil. Windows tek süreç yönetimi, kapanış sırasında Flutter motoruna mesaj iletmeme koruması ve kullanıcı kapsamında dosya ilişkilendirmeleri iyi tasarlanmış. Linux'ta RPATH paket içi `lib` dizinine sınırlı; masaüstü kaydı ve dosya yöneticisi eylemleri sistem geneline yazmıyor.

Zengin pano için Windows'ta mevcut yerel Quill köprüsü, Linux'ta GTK `text/html` hedefi kullanılıyor. Böylece DOCX uygulamasından kopyalama hem DOCX hem UDF açıkken aynı biçim koruma yolundan geçiyor.

Kalan platform riski: paketlenmiş Tesseract/qpdf/TIFF/JPEG araç setleri yalnız `x64` için bulunuyor. ARM64 Windows/Linux dağıtımı bu haliyle desteklenmez. Windows performansı ve kapanışı bu Linux ortamında canlı olarak yeniden ölçülemez; gerçek Windows release kabul testi gereklidir.

### Mobil

Telefon yerleşimi ayrı ana sayfa, dar ekran araç menüsü, tam ekran okuyucu, kenardan geri hareketi, Android SAF ile klasör/kaydetme ve yerel paylaşım akışlarına sahiptir. Genel depolama izni istenmemesi ve dış belgenin uygulama özel alanına atomik kopyalanması doğru yaklaşımdır.

Yayın öncesi kritik konu: Android `release` yapılandırması halen debug anahtarıyla imzalanıyor. Gerçek keystore/CI secret yapılandırılıp debug anahtarı release yolundan kaldırılmadan mağaza veya son kullanıcı dağıtımı yapılmamalıdır.

Android debug derlemesi başarılıdır. Derleme zinciri ayrıca iki ileriye dönük bakım uyarısı veriyor: uygulama ile `desktop_drop`/`file_picker` eklentileri Kotlin Gradle Plugin uyguluyor ve gelecek Flutter sürümleri Built-in Kotlin geçişi isteyecek; kurulu Android command-line tools da SDK XML sürümünden geridedir. Bunlar bugünkü debug derlemesini engellemiyor, ancak Flutter/Android araç yükseltmesinden önce giderilmelidir.

iOS klasör senkronizasyonu, dış uygulamadan belge alma, yerel paylaşım ve kaydetme köprüleri Android'deki kapsamda uygulanmış değildir. iOS klasörleri projede bulunsa da iOS'u desteklenen ürün gibi duyurmadan önce ayrı iPhone/iPad kabul çalışması gerekir.

## Doğrulama

- `flutter analyze --no-pub`: temiz.
- Tam Flutter paketi: 420 test geçti.
- PDF metninin satır/sıra koruması ile Word HTML font/tablo → UDF dönüşü için yeni regresyon testleri eklendi.
- Linux release: `build/linux/x64/release/bundle/lifeos_folio` üretildi.
- Android debug: `build/app/outputs/flutter-apk/app-debug.apk` üretildi.
- Linux/Windows bağlam menüsü testi geçti; paketlenmiş native araçların kayıtlı checksum'ları doğrulandı (Windows x64: 9, Linux x64: 6 dosya).

## Önerilen sonraki sıra

1. Android release imzalama ve CI secret yönetimini tamamla; AAB/APK'yı fiziksel cihazda yükseltme senaryosuyla doğrula.
2. Windows x64 release paketinde soğuk açılış, tray'den dönüş, 10 bin/100 bin dosya uzlaştırması, OneDrive placeholder ve kapanış testlerini ölç.
3. Taranmış PDF için "OCR metnini düzenlenebilir belgeye aktar" akışını, sayfa sınırı ve tanıma uyarılarıyla ekle.
4. PDF vurgularını isteğe bağlı yeni PDF kopyasına gömme ve form doldurma kapsamını ayrı tasarla; imzalı kaynağa asla yerinde yazma.
5. Çok sayfalı TIFF OCR'ı için gerçek sayfa kesme ve ilerleme/iptal davranışı ekle.
6. Destek hedefiyse iOS belge alma, kaydetme, paylaşma ve klasör erişimini native olarak tamamla.
7. ARM64 hedeflenecekse native araç zincirini ayrı paketle ve checksum/lisans doğrulamasını mimariye göre genişlet.

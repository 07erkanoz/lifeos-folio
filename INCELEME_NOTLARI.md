## 11.09.2026 — Windows yavaşlığı ve hızlı bakışın yeniden tasarımı

### Ölçülen sorun

Açılıp boşta bırakılan uygulama 25 saniyede 32,5 sn CPU harcadı, 404,5 MB okudu ve **132,9 MB yazdı** (65.194 yazma işlemi). Kök neden: taramada `state='error'` olan belgeler her seferinde yeniden ayrıştırılıyordu. Kullanıcının indeksinde bu durumda 764 belge vardı; baskın hata, OneDrive'ın cihaza indirmediği dosyalardan gelen `ERROR_CLOUD_FILE_PROVIDER_NOT_RUNNING` (errno 362). Dosya okunamıyor → yine `error` → sonraki açılışta yine deneniyor; kapanmayan bir döngü. Aynı kural 30 saniyede zaman aşımına uğrayan belgeler için de geçerliydi.

Yanında iki maliyet daha ölçüldü: `registerFile` dosya başına ayrı SQLite işlemi açıyordu (tarama başına 4587 WAL commit'i) ve `stats()` içindeki `GROUP BY state`, `state` sütununda indeks olmadığı için 84 MB'lık `documents` tablosunu baştan sona okuyordu — açılışta 3 kez. Ayrıca `IndexDatabase` yapıcısı her açılışta koşulsuz bir tam tablo `UPDATE`'i çalıştırıyordu.

### Değişiklikler

- Okunamayan belge yalnızca dosya değişince veya **Yeniden tara** ile yeniden ayrıştırılır; yarım kalan (`pending`) işler eskisi gibi sürer.
- Tarama 500'lük parçalar halinde tek işlemle yazılır. Tek büyük işlem WAL commit'lerini bitiriyor ama isolate'ı bloke ediyordu; parçalama ikisini de çözer.
- `documents_state` indeksi eklendi: `GROUP BY state` 40 ms/tam tarama yerine 2,5 ms/kapsayıcı indeks.
- Tek seferlik temizlik `user_version` 3 migration'ına taşındı.
- Windows bulut dosyaları "çevrimdışı saklanıyor" notuyla gösterilir.
- `recent_queries` sıralamasına `rowid` eşitlik bozucusu eklendi; Windows saat çözünürlüğü aynı damgayı verdiğinde son arama başa gelmiyordu.

### Hızlı bakış yeniden tasarlandı

Kart sayfanın küçük resmini gösteriyordu: A4 sayfa 255×330 px'e sığdırıldığında 10 punto yazı ~4 piksele düşüyor ve okunmuyordu. Kullanım amacı "aradığım metin bu mu?" sorusunu yanıtlamak olduğu için kart metin odaklı hale getirildi: `IndexDatabase.passages` eşleşmelerin çevresinden en çok üç bölüm döndürür, sözcükler kartta vurgulanır, altta toplam eşleşme sayısı yazar. Sayfa çizilmez; metin indeksten okunur, bu yüzden çevrimdışı ve büyük dosyalarda da çalışır. Görsellerde küçük resim korunur.

Bu iş sırasında gerçek bir hata bulundu: `passages` isteği `'id'` anahtarını kullanıyordu, ama `IndexService` protokolünde `'id'` istek numarasıdır. Argüman spread'i istek numarasını eziyor, yanıt çağırana eşleşmiyor ve kart sonsuza kadar "yükleniyor" kalıyordu. Anahtar `documentId` olarak değiştirildi ve istek numarası artık argümanlardan sonra yazılıyor, böylece bir argüman onu ezemez.

### Doğrulama

`flutter analyze` temiz. `flutter test` iki tam koşumda aynı 8 hatayı verdi; bunlar değişiklik öncesinde de başarısızdı ve tamamı ortam kaynaklıdır (`openssl`/`tiffcp` PATH'te yok, Linux portal testleri, Windows geçici dosya kilidi, Linux varyantını Windows'ta süren widget testi). Dört yeni test eklendi: hatalı belgenin yeniden ayrıştırılmaması, `passages` bağlam pencereleri, isolate üzerinden uçtan uca `passages` isteği (eski hatada zaman aşımıyla düşer) ve şema sürümü.

Windows release paketiyle ölçülen sonuç: boştaki yazma 132,9 MB → 0,4-0,5 MB, boştaki CPU (30-45 sn aralığı) 6,6 sn/15 sn → 0 sn. Hızlı bakış kartı indeksleme sürerken bile yanıt veriyor. Açılış süresi 5-6,5 sn aralığında kaldı. Açılış taramasını geciktirmek denendi ve geri alındı: ortalamayı 6069 ms'den 5513 ms'ye çekti ama varyans yüksek, bu fark gürültüden ayırt edilemez ve işi ortadan kaldırmıyor, geriye kaydırıyor. Kalan açılış maliyeti motor başlatma ve 34.606 dosyalık klasör ağacının yürünmesidir (indekslenebilir olan 4587'si).

**Doğrulanmayanlar:** Değişikliklerin tamamı platformdan bağımsız Dart'tır (tek istisna bulut dosyası notu, `Platform.isWindows`), ancak yalnızca Windows'ta ölçüldü; Linux'ta ölçüm yapılmadı.

### Kapanış çökmesi

`flutter_windows.dll` içinde iki kez NULL erişim ihlali (0xc0000005, ardından pencere yordamı içinde olduğu için 0xc000041d) kaydedildi. Dump'lardaki register değerleri iki kayıtta da aynı: `rcx=0` (motor işaretçisi), `rdi=0x210` (`WM_PARENTNOTIFY`), `rsi=2` (`WM_DESTROY`). Yığın `lifeos_folio` → `FlutterDesktopViewControllerHandleTopLevelWindowProc` zinciri. Yani Flutter'ın alt penceresi yok edilirken üst pencereye gelen bildirim, serbest bırakılmış motora iletiliyordu.

`std::unique_ptr` yıkıcısı sakladığı işaretçiyi temizlemez; `~FlutterWindow()` üzerinden yıkım olduğunda `flutter_controller_` silme sırasında hâlâ dolu görünür ve `MessageHandler`'daki null denetimi geçer. Denetleyici bırakılmadan önce `shutting_down_` bayrağı kaldırılıyor ve `MessageHandler` bu durumda mesaj iletmiyor. Ayrıca `WM_FONTCHANGE` işlenirken `flutter_controller_` null denetimi olmadan kullanılıyordu; bu da ikinci bir çökme yoluydu ve denetim eklendi.

Çökme isteğe bağlı olarak yeniden üretilemedi (bugün ~25 açılış/kapanışta bir kez bile oluşmadı), bu yüzden düzeltmenin *o* çökmeyi bitirdiği kanıtlanamaz. Gösterilebilen: yıkım başladıktan sonra artık serbest bırakılmış motora mesaj iletilmiyor ve 8 ardışık açılış/kapanış temiz çıktı (çıkış kodu 0, yeni dump yok).

## 11.09.2026 — İmza bilgileri ve sağ tıklama düzeltmesi

- Önizleme bandı yalnızca elektronik imza ve imzacı bilgilerini gösterir. Geçerlilik hakkında sonuç bildirmez. Editörden kaydedilen kopyanın imzasız olması uyarısı korunur.
- PDF/UDF önizlemesinde sağ tıklamadaki gri katman, `pdfrx` varsayılan menüsünün ayrı `material_ui` yerelleştirmesini ararken hata vermesinden kaynaklanıyordu. Uygulamanın Flutter Material menüsü kullanıldı; metin seçme, kopyalama ve kopyalama izinleri korundu.
- 7 ilgili regresyon testi geçti; beyaz/siyah tema, kopyalama ve imza bilgileri kontrol edildi. Linux release üzerinde hata önce yeniden üretildi; ardından sağ tıklama, tümünü seçme ve kopyalama görsel olarak doğrulandı. `docs/screenshots/lifeos-imzali-udf.png` güncel örnek görüntüdür; gerçek kişi veya dosya verisi içermez.

# Son güncelleme — 10 Eylül 2026

Kalıcı FTS5 indeksi, Ayarlar üzerinden kaynak klasör yönetimi, otomatik değişiklik izleme, arama alıntıları, son aramalar ve ilk indeksleme tarihine göre yeni eklenenler eklendi. Arama/çözümleme UI isolate'ından ayrıldı. Beyaz/siyah tema ve 170 ms durum koruyan geçişler, telefon menüsü ve küçük ekran uyarlamaları yapıldı.

Karararama'nın PKCS#11 bağları, oturum/sürücü keşfi, X.509 ve CAdES çekirdeği incelenerek yalnız belge imzalama için uyarlandı; portal/UYAP oturum kodu taşınmadı. DER SET sıralaması eklendi, eşleşmeyen ilk özel anahtara düşme kaldırıldı, seçili sertifikayla RSA bütünlük kontrolü eklendi. Önceden imzalı UDF'nin üzerine imza yazılmaz. Gerçek kartla kabul testi ayrıca gerekir; Android kart imzalaması desteklenmez.

Linux kullanıcıya özel MIME/desktop kaydı, Windows kullanıcıya özel dosya ilişkilendirme kaydı ve Android soğuk/sıcak intent açılışları eklendi. Android izinli klasör kopyaları değişiklik bildirimi/30 saniyelik öndeki tarama ile yenilenir. Linux gerçek release penceresi görsel kontrolden geçti; Windows ve Android cihaz davranışı ancak ilgili ortamda doğrulanabilir.

Metin katmanı olmayan PDF/görsellerde OCR yoktur. ODT temel düzenlemeden sonra UDF/DOCX/PDF/TXT çıktısı verir; ODT'ye geri yazmaz. Markdown/HTML/veri metinleri kaynak metin editöründe UTF-8 kopya olarak kaydedilir. Güncel davranış ve kullanım için README esas alınır.

---

# Proje incelemesi — 10 Eylül 2026

## LifeOS Evrakçı genişletmesi

- Uygulama adı ve platform ikonları LifeOS Evrakçı olarak güncellendi. Yeni ikonun üretim kaydı `assets/branding/README.md` içinde.
- ODT, HTML, Markdown temel içerik önizlemesi; SVG vektör önizlemesi; CSV/TSV/JSON/XML/LOG metin önizlemesi eklendi. Kesin hedefler README biçim tablosunda.
- Klasörden yalnız desteklenen uzantılar alınır; alt klasör seçeneği, sürükle-bırak, tekrar eklememe ve dosya yolu argümanları desteklenir.
- Toplu dönüşüm belgeler/görseller olarak ayrıldı. Görsel → PNG/TIFF/PDF uygun olduğunda sunulur; çok kareli dosya tek PNG/TIFF'e sessizce indirgenmez.
- TIFF → PDF'de boyut düşürme ve JPEG yeniden kodlama kaldırıldı; tam çözünürlüklü PNG aktarımı kullanılır.
- PDF/qpdf, TIFF/tiffcp, JPEG/jpegtran ve PNG/IDAT için kayıpsız optimizasyon eklendi. Sonuç yalnız daha küçükse ayrı kopyadır. İmza alanlı PDF işlenmez.
- Karararama `signature_parser.dart`, `x509_parser.dart`, `editor_imza.dart` ve `editor_page.dart` tekrar incelendi. İmzacı ayrıntıları artık UDF okuma → önizleme/editör bandı → ayrıntılar ekranına bağlıdır. CMS imza kaydı sertifikayla issuer+serial veya subjectKeyIdentifier üzerinden eşleşir. İlk sertifika varsayımı kullanılmaz; çoklu ve karşı imzalar listelenir.
- İmzalı editörde açılış uyarısı ve sürekli bilgi bandı vardır: kaydedilen kopya imzasızdır, salt açma kaynak imzayı silmez. Kaynak üzerine yazma koruması sürer.

## UDF ve önizlemede önceki düzeltmeler

- UDF/DOCX/TXT varsayılan olarak salt okunur, sayfalı önizlemeye açılır. Ayrı **Düzenle** / **Önizlemeye Dön** düğmeleri vardır. Önizleme, kaynak dosyayı okur; editördeki kaydedilmemiş taslağı kaynak dosya olarak göstermez. Taslak, önizlemeye veya başka dosyaya geçildiğinde bellekte tutulur.
- PDF/UDF/DOCX önizlemelerinde, TIFF'te ve görsellerde sağa/sola 90° döndürme vardır. Bu işlem görünümü değiştirir, kaynak dosyayı yazmaz ve belgeyi yeniden dönüştürmez. PDF sayfa kontrolleri döndürmenin dışında kalır.
- UDF çözümleme ve PDF üretimi isolate üzerinde çalışır. Yerel font verisi tekrar kullanılır. Kaynak önizleme önbelleği 5 kayıt ve yaklaşık 32 MiB maliyetle sınırlandırılır; aynı dosyanın eşzamanlı istekleri tek üretimi paylaşır. Dosya boyutu/değiştirilme zamanı değişince yeni önizleme üretilir. TIFF komşu sayfaları önden çözer ve uzak sayfaları önbellekten çıkarır.
- UDF stil/resolver mirası ve açık `bold="false"` gibi değerler uygulanır. Serif, sans ve mono fontlar Türkçe destekli Liberation ailelerine eşlenir; özgün font adı modelde korunur. PDF için internetten font indirilmez.
- UTF-8, Windows-1254, UTF-16 BOM ve RTF hex kaçışları ele alınır. UTF-16 metin aralıkları, satır içi kırılmalar, CDATA parçaları ve boş paragraflar korunur; sınırı aşan metin aralığı boş başarılı belgeye çevrilmez.
- UDF yazımı XML kütüphanesiyle yapılır. XML özel karakterleri, `]]>` içeren metinler, kesirli punto, çakışan/belgeyi aşan biçim aralıkları ve tablo hücresi biçimleri ele alınır. Üst/alt bilgilerin paylaşılan metindeki konumları yeniden hesaplanır. Yeni üretilen UDF imzasızdır.
- PDF çıktısında gerçek görseller, metin rengi, kalın/italik aileler, sayfa yönü ve üst/alt bilgiler çizilir. Uzun paragraf birden fazla sayfaya bölünebilir.
- İmza verisi varsa önizleme/editörde bilgi bandı görünür. Varlık tespiti, doğrulanmış imza olarak sunulmaz. Düzenleme kaydında imzalı kaynak dosyanın üzerine yazılması engellenir; yeni dosya adı önerilir.
- Toplu dönüşüm yalnız ortak desteklenen hedefleri sunar, dosya adındaki noktaları korur, mevcut çıktıları ezmek yerine sıra numarası ekler. Çalışırken pencere kapatılmaz; sonuçlarda başarı/hata sayıları ayrılır.
- Görsel → PDF bağlandı. OCR gerektiren taranmış PDF metne çevrilirken açık hata verir. DOC/RTF desteklenmediği halde DOCX/TXT gibi tanıtılmaz; HTML kendi okuyucusunu kullanır. TIFF → PNG desteklenmediği için seçeneklerden çıkarıldı. TIFF → PDF bir sayfa çözülemezse kısmi dosyayı başarılı diye kaydetmez.
- DOCX dışa aktarımında görsel, metin rengi, paragraf girintisi, A4/yatay sayfa ve hücre birleşim alanları korunur. DOCX okuması resimleri ve satır içi tab/kırılmaları modele alır. Aynı hedefi kullanan farklı ilişki kimliklerini silen işlem kaldırıldı.

## Karararama karşılaştırması

Referans proje değiştirilmedi. İncelenen başlıca kaynaklar:

- `lib/services/udf/udf_model_reader.dart`, `udf_writer.dart`, `document_model.dart`: paylaşılan metin havuzu, paragraflar, tablolar, üst/alt bilgiler, eski ZIP/karakter kodlaması.
- `lib/widgets/pdf_font_setup.dart`: özellikle Windows'ta gömülmemiş PDF fontlarının Türkçe karakter sorunu ve font yüzü eşleme yaklaşımı. Bu uygulamanın ürettiği PDF'lere fontlar gömülür; referanstaki Windows PDFium eşleyicisi bütünüyle kopyalanmadı.
- `lib/uyap/uyap_service.dart`: web kanalında UYAP'ın ürettiği PDF; mobil kanalda ham UDF'den metin/PDF yedeği. Yerel dosyalar için sunucu önizlemesi kullanılamaz; evrak kimliği ve oturum gerekir.
- `lib/uyap/ui/editor_imza.dart`: kart algılama → PIN → geçerli sertifika → UDF imzalama. UYAP bağlantısı önkoşul değildir.
- `lib/uyap/core/signing/{signing_service,cades_builder,signature_parser,x509_parser}.dart`: content.xml üzerinden imza özeti, CAdES zarfı, sign.sgn ve sertifika bilgileri.
- `lib/uyap/core/pkcs11/{pkcs11_discovery,pkcs11_session,pkcs11_bindings}.dart`: işletim sistemine göre kart sürücüsü arama ve kart oturumu. AKİS, SafeSign, GemSafe, SafeNet ve OpenSC yolları tanımlı; ek modül yolu desteği var.

## Açık sınırlar / sonraki işler

1. **Birebir UYAP çizimi:** Buradaki önizleme, kaynak UDF'yi yerel model üzerinden PDF'e çizer. UYAP'ın resmî çizicisi değildir. Gerçek örnek dosyalarda piksel/sayfa eşleşmesi henüz doğrulanmadı. Birleşik hücrelerin PDF geometrisi, özel TabSet hizaları, ilk satır girintisinin PDF çizimi, satır içi görsel konumu ve bilinmeyen UDF öğeleri için kapsam genişletilmeli. UDF'de hücre birleşim verisi korunması, PDF'de aynı geometrinin çizildiği anlamına gelmez.
2. **Elektronik imzalama:** Bu uygulamada kart sürücüsü seçimi, PIN/sertifika ekranı ve PKCS#11/CAdES imzalama henüz entegre değildir. İmzacı/sertifika ayrıntıları gösterilir; kriptografik bütünlük, güven zinciri ve iptal kontrolü yapılmaz. Bozuk veya desteklenmeyen imza zarfında varlık uyarısı korunur. Referansın ilk sertifikayı imzacı sayan ayrıştırıcısı doğrudan kopyalanmadı.
3. **Editör kapsamı:** Tablo/görsel blokları korunan öğe olarak taşınır; gelişmiş tablo düzenleyicisi yoktur. Taslaklar uygulama belleğindedir; dosyayı listeden kaldırma veya uygulamayı kapatma için kalıcı taslak/çıkış koruması eklenmeli. Kaynak dosyaya ait dönüştür/yazdır düğmeleri diskteki dosyayı işler; taslak çıktısı editörün kaydet menüsündedir.
4. **Diğer biçimler:** PDF → metin/DOCX/UDF metin katmanını kullanır; özgün PDF sayfa yerleşimini yeniden kurmaz. OCR, eski DOC, RTF, ofis hesap tabloları/sunumlar ve çok sayfalı TIFF → ayrı resimler yoktur. ODT/HTML/Markdown temel içerik önizlemesidir; gelişmiş yerleşim ve gömülü kaynakların tamamı desteklenmez. DOCX'in bölüm/üst-alt bilgi ve karmaşık liste özelliklerinin tamamı ara modele taşınmaz.
5. **Platform doğrulaması:** Linux debug derlemesi ve otomatik testler yapıldı. Fiziksel e-imza kartı, Windows/macOS ve gerçek kullanıcı UDF örnekleriyle canlı doğrulama yapılmadı.

## Doğrulama

`flutter analyze --no-pub`, `flutter test --no-pub`, `flutter build linux --debug --no-pub`.

Güncel kontrolde statik analiz temiz, 45 test başarılı ve Linux debug derlemesi başarılı. Derlenen uygulama sanal Linux ekranında örnek klasörle açıldı: yalnız desteklenen iki dosya listelendi, UDF sayfası ve iki imzacı adı görüntülendi. Görüntü: `docs/screenshots/lifeos-imzali-udf.png`. Sanal ekranda donanım hızlandırması bulunmadığından bu kontrol performans ölçümü değildir.

Testler UDF okuma/yazma, kodlama/fontlar, imza varlığı, CDATA/aralık bozulmaları, tablo/üst-alt bilgi, uzun paragraf sayfalaması, çıktı çakışması, OCR gereksinimi, önbellek, ayrı editör geçişi ve iki yönde döndürmeyi kapsar.

100 paragraflık sentetik örnekte önizleme verisinin ilk üretimi yaklaşık 81–102 ms; önbellekten erişim 1 ms altında ölçüldü. Bu değer ekranın PDFium çizimini, soğuk uygulama başlangıcını veya büyük gerçek evrakları temsil etmez.

İlave testler: klasör filtreleme/alt klasörler/bağlantılar; yeni biçimlerin içeriği; SVG harici kaynak reddi; PNG/JPEG piksel eşitliği; iki sayfalı TIFF piksel/sayfa eşitliği; PDF metin, sayfa boyutu ve raster eşitliği; PDF imza alanı koruması; gerçek CMS örneklerinde çoklu imzacı ve SKI eşleştirmesi; karşı imza; Türkçe BMPString; eksik/bozuk sertifika; imzalı editörün açılış uyarısı ve kaynak baytlarının korunması.

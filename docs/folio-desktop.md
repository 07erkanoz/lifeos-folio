# Folio ilk açılış ve masaüstü davranışı

- Görünen uygulama adı **LifeOS Folio**. Çalıştırılabilir dosya `lifeos_folio` / `lifeos_folio.exe` olarak adlandırılır; uygulama kimliği ve veri dizini kimlikleri korunur. Windows path_provider ürün adıyla dizin oluşturduğu için indeks, tema ve imza ayarları önceki `LifeOS Evrakçı` dizininden okunmaya devam eder.
- Linux/Windows başlığı Flutter tarafından çizilir: sürükleme, çift tıklayarak büyütme, küçültme, geri boyutlandırma, kapatma, kenarlardan boyutlandırma, F11 tam ekran ve tam ekrandan Esc ile çıkış. Pencere kontrolleri diyaloglar ve lisans sayfası açıkken de kalır. macOS yerel başlığını korur.
- İlk açılış: tanıtım ve Beyaz/Siyah/Sistem seçimi → sürümlenmiş ücretsiz kullanım lisansı → isteğe bağlı klasör seçimi. Onay ve kurulum durumu yerel `onboarding.json` dosyasında tutulur. Lisans onayı sonrasında dışarıdan açılan bir belge için klasör kurulumu ertelenebilir. Tema `appearance.json` içinde saklanır.
- Hakkında: Kullanım Koşulları, Gizlilik ve KVKK Aydınlatma Metni, üçüncü taraf lisansları ve lifeos.com.tr bağlantıları. Uygulamanın ücretsiz kullanım izni üçüncü taraf bileşenlerin lisanslarının yerine geçmez.
- Tepsiden normal açılış ana sayfaya döner: sol panelle birlikte belge alanı da temizlenir, okunan evrak ekranda kalmaz. Kaydedilmemiş değişiklik taşıyan bir editör bunun istisnasıdır; ekranda bırakılır, çünkü kapatmak taslağı hiçbir şey sorulmadan düşürürdü.
- İşletim sisteminden gelen dosya açılışı doğrudan sol panel kapalı önizlemeye gider; dosyayı açmak onu otomatik olarak indeks kaynağına eklemez. Sonuçlar üst düğmeden açılabilir. Uygulama içi arama sonuçlarından önizleme önceki düzeni korur.
- PDF/UDF/DOCX önizlemesinde motorun `0.2` fare katsayısı `1.0` oldu. Tekerlek ve trackpad hareketleri gecikmeli animasyon kuyruğu olmadan uygulanır; yakınlaştırma ve sayfa geçişi ayrıdır.

## Varsayılan dosya türleri ve GNOME olayı

11 Eylül 2026 12:32:13 kaydında GNOME Shell SIGSEGV ile çökmüştür. Ana yığın `g_desktop_app_info_get_is_hidden → libgnome-menu → gmenu_tree_load_sync` zincirindedir. Bu, uygulama menüsü yeniden yüklenirken çökmeyi doğrular; çökme kaydı tek başına tam kök nedeni kanıtlamaz.

Eski kayıt akışı `.desktop` dosyasını ve ikonu doğrudan açıp kısaltarak yazıyordu. Yeni akış:

1. İçerik aynıysa dosyaya dokunmaz.
2. Tam dosyayı aynı dosya sistemindeki geçici dizinde hazırlayıp tek rename ile yayınlar; menü gözlemcileri yarım dosya okuyamaz.
3. MIME/desktop veritabanını yalnız kayıt değiştiğinde günceller; zorunlu ikon önbelleği yenilemesi yapmaz.
4. Aynı anda yinelenen kayıt çağrılarını birleştirir; arayüz işlem sürerken devre dışıdır.
5. Linux'ta yalnız kullanıcının seçtiği MIME türlerini `xdg-mime` ile atar ve ardından sorgulayarak kontrol eder. Zaten atanmış türler tekrar yazılmaz. TXT/LOG gibi aynı MIME türünü kullanan uzantılar birlikte sunulur.
6. Windows'ta seçilen türleri kullanıcı capabilities kaydına hazırlar; son seçimi Windows Ayarları yapar. UserChoice hashleri değiştirilmez.

Testler geçici veri dizinleri ve sahte komut çalıştırıcısıyla yapıldı; canlı GNOME oturumunda kayıt işlemi yeniden tetiklenmedi. Bu değişiklikler sistemdeki GNOME/libgnome-menu bileşenini değiştirmez.

Windows pencere davranışları ve kayıt betiği bu Linux ortamında gerçek Windows üzerinde doğrulanmadı. Windows ve Android test paketleri yalnız elle başlatılan GitHub Actions iş akışıyla derlenir; Linux yerel olarak derlenir.

## UYAP Editör ile UDF ilişkilendirmesi

Folio'nun eski `application/x-uyap-udf` tanımı `*.udf` için 80 öncelik
kullanıyordu. UYAP'ın Linux paketi ise `application/udf` ve normal glob önceliği
kaydeder. Folio'nun kuralı baskın gelince GNOME, UYAP Editör'ü UDF için önerilen
uygulamalar arasında göstermiyordu; UYAP'ın masaüstü dosyası silinmemişti.

Folio artık UYAP ile aynı `application/udf` tanımını ve normal önceliği kullanır.
`application/x-uyap-udf` ve `application/x-udf` aynı türün alias adlarıdır.
Bu yaklaşım [Shared MIME-info tanımına](https://specifications.freedesktop.org/shared-mime-info/latest/ar01s02.html)
uygundur. Eski kurulumlarda Folio'nun `mime/packages/lifeos-evrakci.xml`
dosyasının güncellenmesi ve `update-mime-database` çalışması gerekir; varsayılan
seçim dosyaları ve UYAP'ın uygulama kaydı değiştirilmez.

Linux entegrasyon testi eski hatayı izole XDG dizinlerinde yeniden üretir;
düzeltme sonrası GIO'nun üç MIME adı için de UYAP ve Folio'yu listelediğini,
UYAP varsayılan seçiminin ve masaüstü kaydının korunduğunu doğrular.

UYAP paketinin bazı masaüstü kısayollarında `Exec=.../dokuman.sh` satırında
`%f` eksiktir. Bu ayrı durumda GIO uygulamayı dosya açabilen bir uygulama olarak
işaretlemez. Kullanıcıya özel `applications/dokuman.desktop` kopyasına `%f`
eklenerek giderilebilir; Folio'nun kayıt işlemi diğer uygulamaların kısayollarını
otomatik değiştirmez.

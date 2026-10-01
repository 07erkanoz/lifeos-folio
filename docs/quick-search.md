# LifeOS Folio hızlı arama

Ayarlar → **Masaüstünde hızlı arama** açıldığında ana pencere kapatma düğmesiyle
sistem tepsisine gizlenir. Aynı işlem ve aynı kalıcı SQLite FTS5 indeksi yaşamaya
devam eder. Klasör izleyicisi yeni/değişen desteklenen belgeleri indeksler; kaynak
belgeler her aramada yeniden okunmaz. **Tamamen çık**, arka plan çalışmasını da
sonlandırır. Bu sürüm işletim sistemi açılışına kendiliğinden kayıt eklemez.

Önerilen kısayol **Ctrl + Alt + Space**; Windows/X11 üzerinde ayarlardan seçilir. Wayland’da masaüstünün izin ekranında atanır ve Folio masaüstünün bildirdiği gerçek tuş birleşimini gösterir. Kısayol veya
tepsi menüsü, 740 × 580 boyutunda arama penceresini açar. Yukarı/aşağı ile seçim,
Enter ile gerçek önizleme, Esc ile kapatma kullanılır. Dosya açılınca editöre
geçilmez. Ana pencerenin boyutu ve düzenleyici durumu gizlenirken korunur.

Tepsideki **LifeOS Folio’yu aç** veya dosya belirtmeden uygulamayı yeniden
başlatma, ana sayfayı gösterir ve arama kutusuna odaklanır. Açık belgeler ve
taslaklar bellekte korunur. Bir dosya veya hızlı arama sonucu açıldığında ilgili
önizleme gösterilir. Açık ana pencere üzerinden çağrılan hızlı aramadan Esc ile
dönüş ve işletim sisteminin küçült/geri yükle işlemi mevcut ekranı korur.

Ana ekran ve hızlı arama aynı `LibraryController`, `SearchControls` ve
`IndexService` kullanır. Sorgu, dosya türü, kaynak klasör, ad/içerik seçimi,
eşleşme biçimi ve sıralama iki arayüz arasında korunur. Sonuçlar yalnız görünür
satırlarda 150–262 ms süren hafif saydamlık/kayma geçişiyle sunulur; erişilebilirlik
ayarındaki animasyon azaltma tercihi desteklenir.

## İçerik araması

- Türkçe harfleri toleranslı eşleştirme; özgün metinle kısa sonuç önizlemesi.
- Tüm sözcükler, tam ifade veya herhangi bir sözcük seçimi. Tırnak içindeki ifade
  sözcük sırası korunarak aranır. Serbest sözcük araması önek eşleşmesini destekler.
- 16.384 karaktere kadar sorgu; aşılırsa açık hata, sessiz kırpma yok.
- 64 MB kaynak dosya / 32 milyon metin karakteri işleme sınırı. Kısmi indeksleme
  veya metin katmanı olmayan taranmış belgeler sonuç durumunda belirtilir. OCR yok.
- Eski 2 milyon karakter sınırı yüzünden kısmi kalan kayıtlar bir kez yeniden
  işlenir; diğer belgelerin indeksi korunur.
- FTS5, uzun belgenin sonundaki eşleşmeler dahil ilgili metin bölümünü seçer.

## Masaüstü desteği

Windows: yerel `RegisterHotKey`, Windows sistem tepsisi. Linux X11: XGrabKey;
Wayland: masaüstünün GlobalShortcuts portalı. Portal desteklenmiyorsa ayarlarda
sistem klavye kısayoluna atanabilecek `lifeos_folio --quick-search` komutu gösterilir.
Folio, bağımsız çalıştırılan Linux uygulamasını kısayol bağlantısında kurulu
`com.erkanoz.evrak_convert.desktop` kimliğiyle Registry portalına tanıtır; izin
penceresine ana pencere tanıtıcısını iletir. Portal v2'de kısayol değiştirme
`ConfigureShortcuts` ile yapılır. GNOME portal v1'de mevcut atamayı değiştirmek
sistem klavye ayarlarını açar. Terminalden/klasörden çalıştırırken de uygulama
menüsü kaydı kurulu olmalıdır (`packaging/linux/install_local.py`).

GNOME sistem tepsisinin görünmesi için AppIndicator desteği gerekir. Tepsi ve
kısayolun ikisi de kullanılamıyorsa uygulama kapatma düğmesinde gizlenmez.

İkinci başlatma, kullanıcı veri dizinindeki işletim sistemi kilidiyle tespit edilir.
Dosya/kısayol isteği yalnız loopback arayüzündeki geçici sokete, her çalıştırmada
üretilen rastgele anahtarla iletilir. İndeksin ikinci bir sahibi oluşturulmaz.

GlobalShortcuts protokolü:
https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html

## Derleme

`.github/workflows/platform-builds.yml` yalnız **workflow_dispatch** ile çalışır.
Push/PR tetikleyicisi ve Linux derleme işi yoktur. Windows Setup.exe ve Android ABI APK
paketleri manuel derleme sonunda GitHub Releases bölümünde test sürümü (prerelease)
olarak yayımlanır; bağlantısı çalışma özetindedir. Paketler Actions artefakt
kotasını kullanmaz ve kararlı sürümün Latest işaretini değiştirmez. Windows kurulumu ve kaldırması CI üzerinde
kontrol edilir; ayrıntılar [Windows kurulumu](../packaging/windows/README.md) belgesindedir.
Android mevcut debug imzasını kullanır;
mağaza dağıtımı için özel yayın anahtarı gerekir. Linux yerel olarak derlenir.

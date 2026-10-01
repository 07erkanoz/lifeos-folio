# Editör

Önizleme varsayılandır. Düzenle düğmesiyle tek satırlık, gruplandırılmış araç çubuğuna ve beyaz sayfa çalışma alanına geçilir. Ek biçimlendirme araçları üç nokta menüsündedir. Editör tam genişlikte açılır; üstteki panel simgesiyle sol arama alanı açılıp kapatılır. Önizlemeye dönüş önceki arama düzenini geri getirir.

- **Paragraf stili:** araç çubuğunun başındaki liste Normal metin, Başlık 1, Başlık 2 ve Başlık 3 arasında seçim yapar. Stil UDF'e kendi `resolver` mekanizmasıyla yazılır — uydurma öznitelik kullanılmaz — ve dosya kendi stil tanımını taşır, başka bir editörde de aynı görünür. PDF çıktısında da başlık boyutu ve kalınlığı korunur.
- Ctrl+S: mevcut düzenlenebilir UDF, DOCX veya metin belgesini kaydeder. Yeni belgede dosya adı seçilir.
- Ctrl+Shift+S: farklı kaydetme / PDF dışa aktarma menüsü.
- Ctrl+F: belge içinde bul; Ctrl+P: mevcut editör içeriğini yazdır.
- Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z: geri al / yinele.
- Ctrl+B / I / U: kalın / italik / altı çizili.
- Ctrl+L / E / R / J: sola / ortaya / sağa / iki yana hizala.
- Ctrl+Shift+L veya Ctrl+Shift+8: madde işaretleri; Ctrl+Shift+7: numaralı liste.
- Ctrl+M / Ctrl+Shift+M: girintiyi artır / azalt.
- Ctrl+A / C / X / V: seç / kopyala / kes / yapıştır.

macOS üzerinde karşılık gelen komut tuşu ⌘'dir. İmzalı kaynak üzerine yazılmaz: ilk kaydetmede uyarı gösterilir ve imzasız kopya oluşturulur. Sonraki Ctrl+S aynı kopyaya yazar. PDF dışa aktarma düzenlenebilir kaydetme hedefini değiştirmez.

Üst ve sol cetvel santimetre cinsindendir. Mavi işaretleri sürüklemek sol/sağ ve üst/alt sayfa boşluklarını değiştirir. En az 72 pt içerik alanı korunur. Cetvel menüden gizlenebilir. Ölçüler UDF, DOCX ve PDF çıktısında kullanılır; düz metin biçimi sayfa düzeni taşımaz.

Editör içeriği henüz Word gibi fiziksel sayfalara bölünmez; düşey cetvel ilk A4 sayfasının ölçüsünü gösterir. Basılacak sayfalar PDF önizleme/çıktısında oluşur.

Ctrl + fare tekerleği sayfa, metin ve cetvelleri birlikte %50–%300 aralığında yakınlaştırır. Alt çubukta oran, +/− ve sıfırlama bulunur. Yakınlaştırma kaydedilen belgeyi veya yazı puntosunu değiştirmez. Normal tekerlek kaydırmaya devam eder.

PDF düzenlemede metin ve karakter biçimi aynı PDFium motorundan birlikte alınır. Türkçe karakter kodlaması yüzünden başka bir motorla satır eşleştirmesine gerek kalmaz. Font ailesi, punto, kalın/italik ve metin rengi korunur; karakter konumlarından başlık hizası, girintiler ve sütun sekmeleri çıkarılır. PDF bir kelime işlemci belgesi olmadığından karmaşık sayfa yerleşimi birebir yeniden kurulmaz. Sistemde bulunmayan fontlar mevcut yedek fontla gösterilir.

Ctrl+V ve sağ tık → Yapıştır panodaki biçimli sürümleri şu sırayla dener (`RichClipboard.decode`): Folio'nun kendi kopyası (HTML'deki `folio-clipboard` meta öğesinde, belge modeli JSON olarak), UYAP'ın `EditorDataFlavor` verisi, RTF, HTML; hiçbiri yoksa düz metin. Bir biçim çözülemezse sıradaki denenir. Aynı yol gövde, üst/alt bilgi ve tablo hücrelerinde çalışır (`EditorClipboard`); tablo üst/alt bilgiye ve hücreye sekmeli satırlar olarak girer, görsel hücreye girmez.

- **UYAP:** Java serileştirme akışı yalnız veri olarak çözülür; Java çalıştırılmaz. Akıştaki öğe ağacı (paragraf, tablo, satır, hücre, görsel, alan) UDF'in `<elements>` yapısına çevrilip `UdfReader` ile okunur; yani UYAP'tan yapıştırmak dosyayı açmakla aynı sonucu verir. UYAP'ın seçim tablo içinde bittiğinde sona eklediği birleştirme boşluğu (JoinPrevious) atılır.
- **RTF (Word, LibreOffice):** sekme durakları (`\tx`, `\tqr`, `\tqc`), negatif ilk satır girintisi → asılı girinti, `\slmult` satır aralığı, `\listtext`/`\pntext` işaretinden numaralı/madde işaretli liste ayrımı, hücre kenarlığı ve gölgesi, LibreOffice'in yedek yazı tipi yerine belgenin istediği yazı tipi (`\falt`).
- **HTML:** CSS kalıtımı ve boşluk kuralları tarayıcıdaki gibi uygulanır. Word'ün yorum içindeki stil sayfası, `mso-list` listeleri, `mso-tab-count` sekmeleri ve `tab-stops` durakları; Google Docs'un liste içi paragrafları ve `white-space` ile korunan sekmeleri; Chrome'un satır içi hesaplanmış stilleri; LibreOffice'in `align` ve `font` öznitelikleri ve metindeki sekmeleri okunur. Negatif `text-indent` asılı girintidir. Yalnız HTML'in içinde taşınan (`data:`) görseller alınır; hiçbir adres açılmaz, diskten dosya okunmaz.

Kopyalanan son paragrafın sonu seçildiyse (Word'ün CF_HTML seçim sınırı, RTF'de son `\par`, UYAP'ta son satır sonu) paragraf kendi düzeniyle gelir; seçilmediyse yapıştırılan metin imlecin bulunduğu paragrafa katılır. Kaynak bunu söylemiyorsa (tarayıcı HTML'i) son paragraf imlecin paragrafına katılır; o satır boşsa yapıştırılan paragrafın hizası ve girintisi uygulanır. Yapıştırma tek değişikliktir, tek Ctrl+Z ile geri alınır.

Ctrl+C / Ctrl+X ve sağ tık → Kopyala/Kes panoya HTML (CF_HTML), RTF ve düz metin yazar. Düz metinde tablo, Word'deki gibi sekmeyle ayrılmış satırlardır (nesne yer tutucusu yazılmaz). Linux'ta GTK panosuna `text/html`, `text/rtf`, `application/rtf` ve metin hedefleri; Windows'ta `HTML Format`, `Rich Text Format` ve `CF_UNICODETEXT`; Android'de HTML'li `ClipData` yazılır.

Gerçek programların pano çıktısı `test/fixtures/clipboard` altındadır ve müvekkil verisi içermez: `uyap-document.udf` sentetik bir UYAP belgesidir (`make_uyap_document.py`); `uyap-*.bin` bu belgenin UYAP editöründen gerçek kopyalarıdır (`xvfb-run -a test/fixtures/clipboard/capture_uyap.sh belge.udf cikti.bin [başlangıç:bitiş]`), `chrome-copy.html` ve `libreoffice-document.*` aynı belgenin Chrome ve LibreOffice'ten kopyalarıdır.

Linux pano köprüsü değiştiğinde uygulamayı tamamen kapatıp yeniden derlenen `build/linux/x64/release/bundle/lifeos_folio` çalıştırılmalıdır; hot reload yerel köprüyü yenilemez.

Gerçek Linux pano testleri (Xvfb, Python GTK/UNO ve LibreOffice gerektirir; kullanıcının panosuna dokunmaz). Wayland oturumunda `WAYLAND_DISPLAY` kaldırılmazsa LibreOffice pencereleri sanal ekran yerine masaüstünde açılır:

```sh
env -u WAYLAND_DISPLAY GDK_BACKEND=x11 FOLIO_TEST_ROOT="$PWD" xvfb-run -a -s '-screen 0 1400x1000x24' dbus-run-session -- flutter drive --driver=test_driver/integration_test.dart --target=integration_test/rich_clipboard_test.dart -d linux
```

`integration_test/rich_copy_test.dart` ters yönü sınar: Folio'da belge açılıp gerçek Ctrl+A, Ctrl+C basılır; panoda `text/html` (Folio'nun kendi kopyasıyla), `text/rtf` ve metin hedefleri olduğu, düz metinde tablonun sekmeli satır olduğu `xclip` ile okunur.

Windows pano testi CI'da Win32 üzerinden HTML/RTF/UYAP baytlarını ve seçim önceliğini doğrular. Yerelde: `cmake -S test/native/windows -B build/clipboard-test`, `cmake --build build/clipboard-test --config Debug`, `ctest --test-dir build/clipboard-test -C Debug --output-on-failure`. Bu test Word uygulamasının kendisini başlatmaz.

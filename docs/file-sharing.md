# Belge açma ve paylaşma

Önizlemenin sağ üstündeki **Belge işlemleri** menüsü:

- **Varsayılan uygulamayla aç:** işletim sisteminin belge türü için seçtiği uygulama. Varsayılan LifeOS ise uygulama seçicisi gösterilir.
- **Birlikte aç:** farklı uygulama seçimi; varsayılan ilişkilendirme zorla değiştirilmez.
- **Paylaş / Gönder:** Windows paylaşım paneli, gerçek dosya kopyalama ve klasöre kopyalama. Linux’ta ayrıca varsayılan e-posta uygulamasında dosya ekli ileti açılır. Android’de sistem paylaşım paneli kullanılır.
- **Klasörde göster:** Windows’ta Explorer içinde dosyayı seçer; Linux’ta bulunduğu klasörü açar.

İşlemler diskteki özgün dosyayı kullanır. Editörde henüz kaydedilmemiş değişiklikler gönderilmez. Format değiştirilmez ve imzalı dosyanın baytları yeniden oluşturulmaz. Klasöre kopyalamada aynı adlı dosya varsa yeni bir numaralı isim kullanılır. LifeOS alıcı seçmez veya otomatik ileti göndermez.

## Platform uygulaması

Windows, `IDataTransferManagerInterop::ShowShareUIForWindow` ve `StorageFile` ile yerel paylaşım paneline dosya aktarır. İşlem dosyanın tamamını Dart belleğine yüklemez. Pano `CF_HDROP` ve `DROPEFFECT_COPY` kullanır; Türkçe dosya adları UTF-16 olarak korunur. `SHOpenWithDialog` uygulama seçicisini, `SHOpenFolderAndSelectItems` Explorer seçimini açar. Derleme C++20 ve Windows SDK’nın C++/WinRT başlıklarını kullanır.

Linux, GTK/GIO uygulama seçicisi ve dosya panosunun GNOME/KDE URI biçimlerini kullanır. E-posta işlemi `xdg-email --attach` ile yalnızca ileti hazırlama ekranını açar; e-posta uygulamasının kurulu olması gerekir.

Android, dosyayı arka planda uygulamanın dar kapsamlı `outgoing/` önbelleğine kopyalar. `FileProvider` yalnızca bu klasörü sunar; `ACTION_SEND` veya `ACTION_VIEW` alıcısına geçici okuma izni verilir. Uygulamanın diğer özel dosyaları paylaşılmaz.

## Windows cihazında doğrulama

Windows kodu Linux üzerinde çalıştırılamaz. Windows sürümünü yayımlamadan önce yerel Windows 10/11 cihazında:

1. Boşluk, Türkçe karakter ve uzun isim içeren PDF, DOCX, UDF ve görsel dosyalarıyla varsayılan açma ve uygulama seçimini deneyin.
2. LifeOS varsayılan olduğunda yeni LifeOS penceresi döngüsü oluşmadığını kontrol edin.
3. Windows paylaşım panelinde kurulu bir dosya kabul eden uygulamayı seçin; iptal ve hedef uygulama bulunamaması durumlarını deneyin.
4. Dosyayı kopyalayıp Explorer’a ve dosya kabul eden e-posta/sohbet uygulamasına yapıştırın. Kaynak dosyanın durduğunu ve kopyanın SHA-256 değerinin aynı olduğunu kontrol edin.
5. İmzalı UDF paylaşımında dosya baytlarının ve imza verisinin değişmediğini doğrulayın.

Bu kontroller GitHub Actions gerektirmez.

## Fontlar ve yerel test sürümü

Editör ve UDF/DOCX PDF üretimi, sistem/kullanıcı klasörlerindeki TrueType fontlarını bir kez arka planda tarar. İstenen kurulu font önceliklidir; bulunamazsa Türkçe destekli Liberation ailesi kullanılır. Yedek asset bulunamadığında uygun kurulu sistem fontu denenir. Başarısız font yüklemeleri kalıcı olarak önbelleğe alınmaz. TTC koleksiyonları ve CFF tabanlı OTF dosyaları bu editör/PDF yazıcı kataloğuna dahil değildir; mevcut PDF görüntüleyicinin platform font çözümleyicisi ayrıdır.

Açık test uygulamasının asset klasörünü derleme sırasında değiştirmemek için bu çalışmanın son Linux derlemesi `build-local/linux/x64/release/bundle/` altında tutulur. Dağıtımda yalnızca çalıştırılabilir dosya değil, `data/` ve `lib/` ile birlikte tüm bundle kullanılmalıdır.

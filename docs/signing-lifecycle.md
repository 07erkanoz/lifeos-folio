# E-imza kartının serbest bırakılması

Kart tarama, sertifika okuma ve imzalama ayrı, kısa ömürlü işçi isolate'larında çalışır. Isolate'lar aynı süreçteki yerel sürücüyü paylaşabildiğinden uygulama bu işleri sıraya alır; sürücü başlatma ve kapatma işlemleri çakışmaz.

Her işlem sonunda, hata durumları dahil:

1. Uygulamanın açtığı PIN oturumundan çıkılır.
2. Kart oturumu kapatılır.
3. Uygulamanın başlattığı PKCS#11 modülünde `C_Finalize` çağrılır.
4. `.so` / `.dll` / `.dylib` kütüphanesinin OS referansı `DynamicLibrary.close()` ile bırakılır.

İmza üretildiğinde kart, RSA bütünlük kontrolü ve dosya yazımı başlamadan bırakılır. Sembol bulma veya modül başlatma hataları da kütüphane referansı sızdırmaz. Kart/PIN işlemi sürerken pencerenin kapatılması engellenir; işlem bitince pencereyi açık tutmak kartı tutmaz. PIN otomatik tekrar denenmez.

`test/pkcs11_lifecycle_test.dart` gerçek karta erişmeden küçük bir C test sürücüsü derler; başarı, başlatma/giriş hatası, zaten başlatılmış modül, kapatma hatası ve eksik giriş noktası durumlarında native unload sırasını doğrular.

2026-09-11 yerel teşhis: `pcscd` çalışıyordu. `pcsc_scan -n -c -t 3` ACS ACR39U okuyucuyu ve takılı kartı gördü. Gerçek PIN ile imzalama yapılmadı. Servisi yeniden başlatmak açık uygulamaların eski PC/SC bağlantılarını yenilemez; uygulamanın da yeniden açılması gerekebilir. Uygulama sistem servisini kendiliğinden yeniden başlatmaz ve diğer uygulamaları kapatmaz.

Ek donanım kontrolü: Yeni uygulamada kart taraması yapılıp pencere kapatıldıktan sonra, LifeOS süreci çalışmaya devam ederken bağımsız `opensc-tool --reader 0 --atr` komutu başarıyla karta erişti. Bu kontrol PIN veya imzalama içermedi.

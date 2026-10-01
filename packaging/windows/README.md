# Windows kurulumu

Manuel Windows GitHub Actions işi `LifeOS-Folio-<sürüm>-Windows-x64-Setup.exe`
ve SHA-256 sağlama dosyasını üretir. Kurulum dili Türkçe veya İngilizce seçilebilir.

- Kullanıcı hesabına kurulur: `%LOCALAPPDATA%\Programs\LifeOS Folio`.
- Başlat menüsü kısayolu oluşturulur; masaüstü kısayolu isteğe bağlıdır.
- “Birlikte aç” kaydı ve sağ tuş “Folio ile önizle / düzenle” komutları seçilebilir.
  Windows'un mevcut varsayılan uygulama seçimi değiştirilmez.
- Flutter dosyaları, fontlar, e-imza yardımcıları, qpdf, tiffcp ve bağımlı DLL'ler
  release klasöründen birlikte paketlenir. Visual C++ çalışma zamanı uygulama
  klasörüne eklenir; kullanıcıdan ayrıca indirmesi istenmez.
- Aynı uygulama kimliği ve klasör kullanılarak mevcut kurulum güncellenir.
  Kaldırma Windows uygulama ayarlarından yapılabilir; kullanıcı belgeleri,
  indeks, geçmiş ve ayarlar silinmez.

Windows üzerinde Flutter release klasörü hazırlandıktan sonra:

```powershell
flutter build windows --release
./packaging/windows/build-installer.ps1
```

Derleme makinesinde Visual Studio C++ araçları ve Inno Setup 6.3 veya üzeri
bulunmalıdır. GitHub Windows runner bu araçları sağlar. Paketleme betiği release
dosyalarını doğrular, Visual C++ DLL'lerini ekler ve kurulum dosyasını derler.
`test-installer.ps1` yalnızca geçici GitHub runner üzerinde sessiz kurulum,
üzerine kurulum, kısayol, belge komutları ve kaldırmayı kontrol eder.

Kurulum çıktısı `build/windows/installer/` altında oluşur. Başarılı Windows test
paketleri `windows-test-<run>-<attempt>` adlı **GitHub ön sürümü (prerelease)**
olarak Releases bölümünde yayımlanır. İndirme bağlantısı Actions çalışmasının
özetinde de bulunur. Manuel derleme başarıyla tamamlanınca paket yayımlanır;
kararlı sürümün Latest işareti değiştirilmez. Paketler Actions artefakt kotasını
kullanmaz. Eski test sürümleri Releases üzerinden
silinebilir. Hata günlüklerinin Actions saklama süresi üç gündür.
Kod imzalama sertifikası yapılandırılmadığı için Setup.exe Authenticode imzası içermez.

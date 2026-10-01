# Gezginde UDF önizlemesi ve küçük resim (Quick Look) — plan

Durum: **planlandı, başlanmadı** (28 Eylül 2026). Sonra yapılacak.

macOS'taki [udf-quicklook-extension](https://github.com/saidsurucu/udf-quicklook-extension)
gibi, UDF dosyası gezginde seçilince içinin görünmesi ve simgesinin yerine ilk
sayfanın küçük resminin çıkması; Windows ve Linux'ta **aynı şekilde**.

O depo Swift ile yazılmış ve lisansı yok; kodu alınamaz, yalnız fikir alınır.
Zaten gerekmiyor: UDF'yi PDF'e çizen motor Folio'da var.

## Kararlar

- **Dış bağımlılık yok.** LibreOffice, Office ya da başka bir dönüştürücü
  kullanılmaz. UDF'yi Folio'nun kendi motoru çizer; gezginde görünen, Folio'nun
  önizlemesiyle aynıdır.
- **Windows ve Linux aynı çalışır:** tek ortak çekirdek (`folio-render`), her
  sistemde ona bağlanan ince bir ek.
- **Sessizce kurulmaz.** Mevcut "Sağ tuşa önizle ve düzenle ekle" gibi bir kez
  sorulur ya da Ayarlar'dan açılır. Açıldıktan sonra Folio her açılışta kaydı
  denetler (program taşındıysa yolu günceller); kapatılınca her şey geri alınır.
- Kayıt kullanıcı başına yapılır; yönetici izni istenmez. Tek istisna GNOME'da
  küçük resim (aşağıda).

## Yapı

```
                 ┌──────────────────────────────┐
                 │  folio-render (ortak çekirdek)│
                 │  UDF → PDF / PNG, ekransız     │
                 └──────────────┬───────────────┘
          ┌─────────────────────┼──────────────────────┐
   Windows │                     │ Linux                │
  ┌────────┴─────────┐   ┌───────┴────────┐   ┌─────────┴─────────┐
  │ folio_shell.dll  │   │ Sushi modülü    │   │ .thumbnailer      │
  │ IPreviewHandler  │   │ (Boşluk tuşu)   │   │ (küçük resim)     │
  │ IThumbnailProvider│  │ ~/.local/share/ │   │ /usr/share/       │
  │ HKCU kaydı        │  │ sushi/viewers/  │   │ thumbnailers/     │
  └──────────────────┘   └────────────────┘   └───────────────────┘
```

| | Windows | Linux (GNOME) |
|---|---|---|
| Önizleme | Gezgin önizleme bölmesi (Alt+P) — önizleme işleyicisi | Nautilus'ta Boşluk tuşu — Sushi görüntüleyici modülü |
| Küçük resim | Gezgin küçük resim sağlayıcısı | freedesktop `.thumbnailer` |
| Kurulum | Kullanıcı başına, `HKCU` | Önizleme kullanıcı başına; küçük resim sistem paketiyle |

## Ölçülenler (28 Eylül 2026, bu makine: Arch, GNOME 50 Wayland, Nautilus 50.3.1, Sushi 50.0, gnome-desktop 44.5, bubblewrap 0.13)

1. **Sushi kullanıcı klasöründen görüntüleyici yüklüyor — ölçüldü, çalışıyor.**
   `~/.local/share/sushi/viewers/folio_udf_deneme.js` konuldu
   (`var mimeTypes = ['application/udf']`, `Renderer.Renderer` arayüzünü uygulayan
   bir `Gtk.Label`). `sushi deneme.udf` xvfb altında açıldı; pencerede modülün
   yazdığı "FOLIO UDF DENEME / deneme.udf / application/udf" göründü. Yani
   Boşluk tuşu önizlemesi root izni olmadan kurulabilir.
   - Sushi bunu `mimeHandler.js` içinde yapıyor:
     `GLib.build_filenamev([GLib.get_user_data_dir(), 'sushi'])` arama yoluna
     ekleniyor, `imports.viewers` altındaki `mimeTypes` taşıyan her modül yükleniyor.
   - Arayüz (`ui/renderer.js`): `GObject.registerClass({Implements:
     [Renderer.Renderer], Properties: {fullscreen, ready}})`, bir Gtk widget'ı,
     hazır olunca `this.isReady()`.
   - Sushi'nin kendi PDF görüntüleyicisi `EvinceView.View` kullanıyor. Bizim
     modül `folio-render` ile UDF'yi geçici bir PDF'e çevirip aynı görüntüleyiciye
     verebilir (Evince kütüphanesi Sushi'nin kendi bağımlılığı; bize yeni bağımlılık
     getirmez). Ya da doğrudan PNG sayfaları gösterir.
   - Modül olmadan Sushi UDF için yalnız MIME simgesini gösteriyor (küçük resmi değil).
2. **GNOME küçük resmi ev klasöründen çalışmıyor — ölçüldü.** GNOME küçük resim
   programlarını bubblewrap kutusunda çalıştırıyor; kutuda `$HOME` yok, ekran yok.
   - Ev klasöründeki bir programla: çıkış kodu 1, elle bwrap denemesinde
     `execvp …/folio-kucukresim-deneme/uret.sh: No such file or directory`.
   - Yalnız `/usr` yollarını kullanan aynı deneme: küçük resim üretildi (48 px).
   - Sonuç: GNOME'da küçük resim için `folio-render` ve `.thumbnailer` dosyası
     `/usr` altına kurulmalı → .deb / .rpm / AUR paketi, bir kez root ile.
     Folio'nun kendisi bunu kuramaz; Ayarlar'da "küçük resim için sistem paketi
     gerekir" diye söylenir.
   - Ölçerken çıkan tuzaklar: `.thumbnailer` dosyasında `Exec` satırı `%i`
     içermezse "Input file could not be set"; ters bölü içeren `Exec`
     "missing Exec key" veriyor (tek tırnak kullanılmalı).
3. **Ölçülmedi:** KDE/Dolphin (KIO ThumbCreator eklentisi gerekebilir), Nemo,
   Thunar/tumbler (sandbox yok; kullanıcı başına çalışması beklenir). Windows'ta
   hiçbir şey henüz ölçülmedi (bu makinede Windows yok).

## Mevcut kod — nereye oturur

- UDF okuma: `lib/services/udf/udf_reader.dart` (archive + xml; yalnız
  `flutter/foundation` alıyor).
- PDF çizimi: `lib/services/pdf/pdf_service.dart` →
  `PdfService.modelToPdfBytes(model, title:)`; `package:pdf` ile saf Dart.
- PNG'ye çevirme: pdfium (`libpdfium.so` / `pdfium.dll` zaten pakette;
  `lib/services/pdf/pdfium_setup.dart`). Şu an `pdfrx` üzerinden, Flutter'lı.
- Yazı tipleri: `lib/services/fonts/document_fonts.dart` — `rootBundle`'dan
  okuyor, olmazsa sistem fontlarına ve `data/flutter_assets/fonts/pdf/`'e düşüyor.
- Gezgin kaydı: `lib/services/platform/context_menu_registration.dart`
  (Linux: `packaging/linux/context_menu.py`, Windows:
  `packaging/windows/register-viewer.ps1 -ContextMenuOnly`). Aynı kalıp
  kullanılacak.
- UDF MIME türü `application/udf` zaten kayıtlı (`context_menu.py` içindeki
  `MIMES`).

### Çekirdeği Flutter'sız derlemenin önündekiler

`dart compile exe` Flutter'a bağlı paketi derleyemez. UDF → PDF yolunda
ayrılması gerekenler:

| Dosya | Flutter'a bağı | Yapılacak |
|---|---|---|
| `pdf_service.dart` | `flutter/foundation` (`compute`), `flutter/rendering` (`Matrix4`) | `compute` yerine düz çağrı / `Isolate.run`; `Matrix4` yerine `vector_math` |
| `document_fonts.dart` | `flutter/services` (`rootBundle`, `FontLoader`) | PDF için font okuma kısmı ayrı dosyaya; dosya yolundan okunur |
| `doc_delta_map.dart` | `flutter_quill/quill_delta` | **En büyük risk.** `flutter_quill` paketi Flutter'a bağlı; ya `dart_quill_delta` gibi saf Dart pakete geçilir ya da PDF yolu delta'ya ihtiyaç duymayacak şekilde ayrılır. Önce ölçülecek. |
| `udf_reader.dart`, `signature_parser.dart` | `flutter/foundation` (`@immutable`, `debugPrint`) | `package:meta` ve `print`/sessiz |
| PNG | `pdfrx` (Flutter eklentisi) | pdfium'a doğrudan `dart:ffi` ile (yalnız `FPDF_LoadMemDocument`, `FPDF_RenderPageBitmap`, `FPDFBitmap_*`) ya da PNG'yi Windows'ta DLL, Linux'ta Sushi tarafında çiz |

Hedef: Folio uygulaması ve `folio-render` **aynı** Dart kodunu çağırır; iki ayrı
çizim yolu olmaz. Aksi hâlde gezgindeki görüntü Folio'dakinden ayrışır.

## Parçalar

### 1. `folio-render` (ortak çekirdek)

```
folio-render pdf   <girdi.udf> <çıktı.pdf>
folio-render png   <girdi.udf> <çıktı.png> [--size 256] [--page 1]
```

- `dart compile exe tool/folio_render.dart` → Linux ve Windows için ayrı ikili;
  paketin içinde `tools/` altına (`lifeos_folio` ile yan yana).
- Ekran, D-Bus, `$HOME` gerektirmez (GNOME kutusunda çalışmalı).
- Fontlar paketin içinden, göreli yolla bulunur.
- Hızlı olmalı: küçük resim için hedef < 1 sn (1024 gerçek UDF arşivinde ölçülür;
  bkz. gerçek arşive karşı doğrulama). Bellek sınırlı çalıştırılarak denenir.
- Bozuk / imzalı / çok büyük UDF'de çökmeden hata koduyla çıkar; gezgin o zaman
  kendi simgesini gösterir.
- Testler: `test/` altında aynı UDF'den Folio ve `folio-render` çıktısının aynı
  PDF'i vermesi.

Not: Dart, Windows programını Linux'tan çapraz derleyemiyor. Windows ikilisi
GitHub'daki Windows makinesinde (`platform-builds.yml`, `windows-latest`) derlenir.

### 2. Linux

**a) Boşluk tuşu önizlemesi (kullanıcı başına, root gerekmez)**

- `packaging/linux/sushi/folio_udf.js` →
  `~/.local/share/sushi/viewers/folio_udf.js` olarak kopyalanır.
- Modül `folio-render pdf` ile geçici PDF üretir (`GLib.get_user_cache_dir()`
  altında, dosya yolu + mtime ile önbellek) ve Sushi'nin Evince görüntüleyicisiyle
  gösterir. Folio'nun yolu modüle kurulum sırasında yazılır.
- `mimeTypes`: `application/udf`, `application/x-udf`, `application/x-uyap-udf`.
- Başarısız olursa hata metni gösterir, Sushi çökmez.
- Sushi yoksa (GNOME dışı) bu adım atlanır.

**b) Küçük resim (sistem paketi gerekir)**

- `/usr/share/thumbnailers/folio-udf.thumbnailer`:
  ```
  [Thumbnailer Entry]
  TryExec=/usr/lib/lifeos-folio/tools/folio-render
  Exec=/usr/lib/lifeos-folio/tools/folio-render png %i %o --size %s
  MimeType=application/udf;application/x-udf;application/x-uyap-udf;
  ```
- Yalnız paketle kurulur (.deb / .rpm / AUR `PKGBUILD`). Kurulumdan sonra eski
  başarısız küçük resimler için `~/.cache/thumbnails/fail/` temizlenmesi gerekebilir.
- KDE ve tumbler için ayrıca ölçülecek.

**c) Kayıt**

- `packaging/linux/context_menu.py` yanına `quicklook.py`; `install_local.py` ve
  Ayarlar'daki anahtar bunu çağırır. Kaldırma da aynı betikte.

### 3. Windows

**a) `folio_shell.dll` (C++, COM)**

- `IPreviewHandler` + `IInitializeWithStream` (ya da `IInitializeWithFile`) +
  `IObjectWithSite` + `IOleWindow`: önizleme bölmesinde sayfaları çizer.
- `IThumbnailProvider` + `IInitializeWithStream`: `HBITMAP` döner.
- Çizim: `folio-render png` çağrılır (akıştan geçici dosyaya yazıp) ya da DLL
  pdfium'u doğrudan yükleyip `folio-render`'ın ürettiği PDF'i çizer. Hangisinin
  daha hızlı ve güvenli olduğu ölçülerek seçilir.
- Önizleme işleyicisi `prevhost.exe` içinde, küçük resim sağlayıcısı yalıtılmış
  süreçte çalışır; Explorer'ı çökertmemeli.
- `windows/` altında CMake hedefi; Folio paketiyle birlikte gelir.

**b) Kayıt (HKCU, yönetici izni yok)**

```
HKCU\Software\Classes\CLSID\{önizleme-CLSID}\InprocServer32 = …\folio_shell.dll
HKCU\Software\Classes\CLSID\{küçükresim-CLSID}\InprocServer32 = …\folio_shell.dll
HKCU\Software\Classes\.udf\ShellEx\{8895b1c6-b41f-4c1c-a562-0d564250836f} = {önizleme-CLSID}
HKCU\Software\Classes\.udf\ShellEx\{e357fccd-a995-4576-b01f-234630154e96} = {küçükresim-CLSID}
HKCU\Software\Microsoft\Windows\CurrentVersion\PreviewHandlers  {önizleme-CLSID} = "LifeOS Folio UDF"
```

- `register-viewer.ps1`'e `-QuickLook` / `-RemoveQuickLook` eklenir.
- Kayıttan sonra `SHChangeNotify(SHCNE_ASSOCCHANGED)`; eski küçük resimler için
  küçük resim önbelleği temizliği gerekebilir.
- Inno Setup paketi (`folio.iss`) kaldırırken kayıtları siler.

**c) Windows'ta deneme (bu makinede Windows yok)**

- GitHub Actions `windows-latest` üzerinde: DLL ve `folio-render` derlenir,
  HKCU'ya kaydedilir, küçük bir test programı gerçek bir UDF için
  `IThumbnailProvider::GetThumbnail` ve önizleme işleyicisini çağırır, çıkan PNG
  iş çıktısı olarak yüklenir → indirilip bakılır.
- Her deneme turu yaklaşık 10–15 dakika.
- Son göz kontrolü (Explorer önizleme bölmesinin gerçek görünümü) bir kez gerçek
  bir Windows makinede, Releases'teki test kurulumuyla. Releases'e yayımlayan iş
  kullanıcı onayıyla çalıştırılır.

### 4. Folio içinde anahtar

- Ayarlar → **Gezginde UDF önizlemesi ve küçük resim** (açık/kapalı).
- İlk açılışta bir kez soran küçük bir bilgi kartı (reddedilirse bir daha sormaz).
- Açıkken her açılışta: kayıt yerinde mi, DLL/modül yolu bu programı mı
  gösteriyor → değilse sessizce düzeltir.
- Linux'ta küçük resim sistem paketi yoksa: "Küçük resim için sistem paketi
  gerekir" notu; önizleme yine çalışır.
- Kapatınca: HKCU kayıtları / Sushi modülü silinir.

## Sıra ve tahmini süre (ölçülmemiş tahmin)

| # | Parça | Süre | Not |
|---|---|---|---|
| 1 | `folio-render` çekirdeği | kısa–orta | `flutter_quill` delta bağı ilk ölçülecek risk |
| 2 | Linux Boşluk tuşu önizlemesi | kısa | Yol ölçüldü, çalışıyor |
| 3 | Linux küçük resim + paket | kısa | Sistem paketi gerekir |
| 4 | Windows DLL | en uzun | C++/COM; GitHub'da birkaç deneme turu |
| 5 | Ayarlar anahtarı, açılışta denetim, kaldırma | kısa | Sağ tuş kaydının aynı kalıbı |

Önerilen başlangıç: 1 + 2 → bu Linux makinede Boşluk tuşuyla UDF önizlemesi
gösterilir; sonra 4.

## Kabul ölçütleri

- Gerçek UDF arşivinden rastgele seçilen belgelerde gezgindeki önizleme,
  Folio'daki önizlemeyle aynı (sayfa sayısı, satır kırılımları).
- Küçük resim < 1 sn; bozuk dosyada çökme yok, gezgin kendi simgesine döner.
- Yönetici izni istenmeden açılır ve kapanır (GNOME küçük resmi hariç).
- Kaldırınca geride kayıt, modül ya da önbellek kalmaz.
- İnternet bağlantısı gerektirmez; belge içeriği hiçbir yere gönderilmez.

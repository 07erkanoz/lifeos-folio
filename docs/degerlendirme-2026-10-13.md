# Değerlendirme — bağlantı, kurulum, dosya ilişkilendirme ve görev (13 Ekim 2026)

Beş konu, kodun bugünkü hâline (`68aba6c`) bakılarak değerlendirildi. Her bölümde önce bugün ne olduğu, sonra önerilen yol, en sonda yapılacak işler var. Sıra ve durum `UYGULAMAPLANI.md` §12'de (T14–T19).

---

## 1. UYAP'a tek bağlantı sistemi

### Bugün

Bağlanmak için üç ayrı araç var. Her ekran bunlardan birini kendi seçiyor:

| Araç | Ne açıyor |
|---|---|
| `connectUyapMobile` | Doğrudan e-Devlet sayfası (UYAP Mobil API). Folio'da yöntem seçimi yok. |
| `connectUyapWeb` / `UyapConnectView` | Web Portal. Seçenekler: Adalet E-İmza (kart + PIN), mobil imza, e-Devlet üzerinden e-imza. |
| `connectUets` | UETS: mobil imza ya da kart. |

Ekranların seçtikleri:

| Ekran | Hangi bağlantıyı istiyor |
|---|---|
| Dosya detay: UYAP'tan tazele, evrak aç, yeni evrakları indir (`case_detail_page.dart:299-332`, `:924-936`) | **Yalnız UYAP Mobil**, platforma bakmadan. Masaüstünde e-Devlet penceresi açılıyor; Web Portal ve e-imza hiç sorulmuyor. |
| Portföyü yenile (`portfolio_page.dart:183-197`) | Telefonda Mobil, masaüstünde Web. Platforma bakan tek yer burası. |
| Editör UYAP paneli ve dosya seçici | İkisi birden, alt alta. |
| UYAP'a gönder ve İşlemlerim | Yalnız Web (doğru). |
| İlk kurulumda profil doldurma | Yalnız UYAP Mobil. |

Sorunun kökü: hangi işi hangi kanalın yapacağını söyleyen ortak tablo (`ChannelTable`, `portal_channel.dart`) var, ama arayüzden hiçbir yer ona sormuyor. Ayrıca `PortalSync.portfolioChannel` her platformda Mobil'i öne alıyor; bu, tablonun "dosya listesi: birincil Web" kuralıyla çelişiyor.

Telefonda iki kural ihlali var:

- Web Portal penceresinde **"E-imza ile, e-Devlet üzerinden"** seçeneği telefonda da çıkıyor (`uyap_connect_view.dart:341-346`). Telefonda e-imza hiç görünmemeli.
- UYAP Mobil girişindeki ipucu telefonda da "e-imza ya da mobil imzayı seçin" diyor (`mobile_connect.dart:55, 84`).

### Önerilen yol: tek kapı, platforma göre sıralı yöntemler

1. **Tek giriş noktası.** Ekranlar artık kanal seçmez; `ensureUyap(context, işlem)` der. Bu fonksiyon işi `ChannelTable`'a sorar:
   - İşi yapabilen bir kanal bağlıysa hiçbir şey sormadan devam eder.
   - Bağlı kanal yoksa tek bir **"UYAP'a bağlan"** penceresi açılır (FolioDialog). Pencere yalnız o işi yapabilen yöntemleri gösterir.
2. **Yöntemlerin sırası platforma göre.**

   | | Masaüstü | Telefon |
   |---|---|---|
   | 1 (önerilen) | **E-imza kartı + PIN → UYAP Web Portal.** En zengin veri; gönderim ve İşlemlerim de bununla. | **Mobil imza → UYAP Mobil** (e-Devlet). |
   | 2 | Mobil imza → UYAP Web Portal (e-Devlet). | Mobil imza → UYAP Web Portal (e-Devlet). |
   | 3 | UYAP Mobil (e-Devlet). İsteğe bağlı, ek kanal. | — |
   | Hiç yok | — | **E-imza (kart/PIN ya da e-Devlet üzerinden).** |

3. **Son kullanılan yöntemi hatırla.** Bugünkü `UyapConnectView._last` yalnız bellekte duruyor. Bunun yerine her cihaz kendi tercihini saklar (UETS'nin `uets-login` kaydı gibi). Pencere hatırlanan yöntemle açılır; Ayarlar › Bağlantılar'dan değiştirilebilir.
4. **İşe göre açıklama.** Örnek: yalnız Mobil bağlıyken "UYAP'a gönder" denirse pencere "Gönderim için Web Portal gerekir" der ve yalnız Web yöntemlerini gösterir.
5. **Kanal çubuğu ve Ayarlar aynı pencereyi açar.** Kanal çubuğundaki "UYAP Web" çipi doğrudan o kanalın yöntemlerine gider. Farklı görünüşlü üç ayrı pencere kalmaz.

**Kararınız gereken nokta.** Planın 4. kararı "toplu portal bağlantısı olmayacak, bir PIN başka girişte kullanılmayacak" diyor. Önerim bunu bozmuyor: tek kapı tek pencere demek, tek PIN ile hepsi demek değil. Kolaylık için şu eklenebilir: Web Portal'a e-imzayla girildikten sonra pencerenin sonunda **"UETS'ye de bu kartla bağlan"** düğmesi çıkar. PIN yeniden sorulur. İsterseniz bunu ekleriz, istemezseniz yalnız tek kapı yapılır.

### Yapılacaklar (T14)

- [ ] `ensureUyap(context, UyapOp)` ve tek bağlantı penceresi; yöntem sırası `ChannelTable` + platformdan.
- [ ] Çağrıları bu fonksiyona taşı:
  - `case_detail_page` (tazele, aç, indir, `_fetchShown`)
  - `portfolio_page._refresh`
  - `uyap_case_panel` ve `uyap_case_picker`
  - `TaskPackage.pack`
  - kanal çubuğu, masaüstü anasayfa kartları, telefon çekmecesi, Ayarlar
- [ ] Telefonda e-imza seçeneğini kaldır (`_Route.eSignature`) ve telefondaki ipucu metnini düzelt.
- [ ] `PortalSync.portfolioChannel`: masaüstünde Web birincil.
- [ ] Tercih edilen yöntemi cihaz başına sakla; Ayarlar › Bağlantılar'da göster.
- [ ] Testler:
  - Dosya detay masaüstünde Web/e-imza önerir, telefonda Mobil önerir.
  - Telefonda e-imza hiçbir pencerede görünmez.
- [ ] `UYGULAMAPLANI.md` §3 ve §13'ü güncelle. Telefonda Web Portal (mobil imza) artık var; "telefonda Web yok" yazan satır eskidi.

---

## 2. Telefonun ilk kurulumunda masaüstüne eşleşip her şeyi almak

### Bugün

- İlk kurulum telefon ve masaüstünde aynı: Hoş geldiniz → Lisans → Avukat profili → Belge kütüphanesi. Eşleştirme adımı yok.
- Eşleştirme altyapısı hazır ve çalışıyor: Senkron sayfası ve büro ağında QR ile "Telefonumu ekle" / "QR okut", şifreli kanal. Eşitlenenler:
  - ajanda
  - UYAP dosyaları, evrak listeleri, duruşmalar
  - müvekkiller, tutanaklar, vekâletnameler
  - portal oturumları (isteğe bağlı paylaşım)
  - klasörler
- **Eşitlenmeyenler:**
  - profil (`profil.json`)
  - kalıp metinler ve antetler
  - editör, hukuk ve görünüm ayarları
  - UETS kutusu
- İlerleme yalnız bir dönen çarktan ibaret. Hangi bölümün ne kadarının geldiği görünmüyor.
- Profilde bir hata var. Dört yer, profili kaydederken büro adını (`officeName`) siliyor:
  - `profile_autofill.dart:63-70`
  - `profile_from_uyap.dart:56-67`
  - `onboarding_gate.dart:177-184`
  - `lawyer_profile_dialog.dart:85-92`

  Profil eşitlenmeye başlamadan önce düzeltilmeli; yoksa silinen alan öbür cihaza da gider.

### Önerilen yol

1. **Telefonun ilk ekranında iki seçenek:**
   - **"Masaüstümdeki Folio'ya bağlan"** (önerilen, büyük kart)
   - **"Yeni başla"**

   Lisans adımı yine telefonda kabul edilir; bu cihaz başına bir onaydır.
2. **Eşleştirme.**
   - Telefon QR okutur. Masaüstünde Ayarlar › Senkron › "Telefonumu ekle" QR'ı açar. İlk kurulum ekranı da bu adımı tarif eder.
   - Kod, mevcut `QrInvite` / `scanAndPair` akışı. Telefonun önce "Senkronu aç" demesi gerekmez; kurulum bunu kendisi açar.
3. **İlk eşitleme, bölüm bölüm ilerlemeyle.** Her satır kendi sayacını ve tikini gösterir:

   | Bölüm | Örnek gösterim |
   |---|---|
   | Profil | ✓ |
   | Ayarlar | Görünüm, editör, hukuk, kalıp metinler, antetler |
   | Ajanda | 214 kayıt |
   | UYAP dosyaları | 38 dosya |
   | Müvekkiller | 52 kart |
   | Bağlantılar | UYAP Mobil oturumu (kullanıcı onayıyla) |
   | Evraklar | İsteğe bağlı; boyutu önceden yazılır, "sonra" denebilir |

   Bittiğinde "Hazır" ekranı çıkar ve profil adımı atlanır.
4. **Yeni eşitleme bölümleri:** `profil` ve `ayarlar`. Kilit (şifre) ayarları ve cihaza özgü yollar (kütüphane klasörleri) taşınmaz.
5. **Tekrar kullanılabilirlik.** Aynı ilerleme ekranı daha sonra Senkron sayfasındaki "Şimdi eşitle" için de kullanılır.

### Yapılacaklar (T15)

- [ ] `officeName` silinmesini düzelt (4 yer), test ekle.
- [ ] `profil` ve `ayarlar` eşitleme bölümleri: kayıt, birleştirme kuralı (yeni olan kazanır, çakışma notu), testler.
- [ ] İlk eşitleme yürütücüsü: bölüm bazında ilerleme olayları, hata olursa bölümü yeniden dene.
- [ ] Telefon kurulumuna "Masaüstüme bağlan" yolu: QR okut → eşleş → ilerleme ekranı → Hazır.
- [ ] Masaüstünde "Telefonumu ekle" ekranına kurulumdaki telefonu tanıyan kısa açıklama.

---

## 3. Masaüstü ilk kurulumda profili e-imzayla doldurmak

### Bugün

Profil adımında tek seçenek **"UYAP Mobil ile doldur"** var. Bu e-Devlet penceresi açar ve tam bir UYAP Mobil girişi yapar. Kodun yapabildikleri:

- **E-imza sertifikasından ad soyad ve TC okunabiliyor.** X.509 ayrıştırıcı hazır (`x509_parser.dart`), PKCS#11 ile kart okuma da hazır (`UdfSigningService`). PKCS#11 sertifika listesini PIN'siz verebiliyor; bu her sürücüde denenmeli.
- **Web Portal girişi** zaten ad soyad ve TC'yi profile yazıyor (`portal_sync.dart:441-447`).
- **Baro, baro sicil ve TBB sicil no** yalnız UYAP Mobil'den geliyor (`mobile/avukat/user`). Ne e-imza sertifikasında ne Web Portal'da bu alanlar yok.

### Önerilen yol

Masaüstünde profil adımı üç kartla gelir:

1. **"E-imza kartımdan doldur"** (önerilen). Kart takılıysa ad soyad ve TC hemen gelir; PIN gerekmez, olmazsa sorulur. Baro ve sicil alanları boş kalır, yanında "UYAP'tan tamamla" bağlantısı olur.
2. **"UYAP Web Portal ile (e-imza)"**. Ad soyad ve TC gelir; aynı zamanda Web Portal bağlanmış olur, yani kurulum biter bitmez portföy dolmaya başlar.
3. **"UYAP Mobil ile (e-Devlet)"**. Baro ve sicil dahil her şey gelir.

Telefonda yalnız 3. seçenek kalır. E-imza seçeneği telefonda gösterilmez.

### Yapılacaklar (T16)

- [ ] Sertifikadan profil: kart seç → sertifika oku → ad soyad (CN) ve TC (serialNumber).
- [ ] Profil adımında platforma göre seçenek kartları; Web Portal seçeneği T14'teki tek bağlantı penceresini kullanır.
- [ ] Ayarlar › Avukat profili sayfasına da "E-imza kartımdan güncelle".
- [ ] Testler: sertifika ayrıştırma ile profil alanları eşleşiyor; telefonda e-imza seçeneği görünmüyor.

---

## 4. İşletim sisteminde dosya ilişkilendirme (UDF, PDF, TIFF)

### Windows'ta neden çalışmıyor

Kurulum programı (`folio.iss`) ilişkilendirmeyi doğru yazıyor. Ama **Ayarlar › Varsayılan uygulama** düğmesi (`register-viewer.ps1`) bu kaydı bozuyor:

1. Açma komutunu `"exe" "%1"` yapıyor ve `--preview --` kısmını siliyor. Sonuç: çift tıklama önizleme yerine tam pencereyi açıyor.
2. `Capabilities\FileAssociations` anahtarını silip yalnız seçilen türleri geri yazıyor. Pencerede yalnız UDF seçili geliyor. Düğmeye bir kez basınca Windows'un Varsayılan uygulamalar sayfasında Folio için **yalnız .udf** kalıyor; PDF ve TIFF artık atanamıyor. Şikâyet edilen durum bu.
3. `New-Item -Force` var olan `OpenWithProgids` ve `RegisteredApplications` anahtarlarını yeniden yaratıyor. Bu, başka uygulamaların kayıtlarını silebilir; Windows'ta doğrulanmalı.
4. İşlemden sonra Explorer'a haber verilmiyor (`SHChangeNotify`), bu yüzden "Birlikte aç" listesi yenilenmiyor.
5. Açılan ayar sayfası genel `ms-settings:defaultapps`. Folio'nun kendi sayfası doğrudan açılabilir: `?registeredAppUser=LifeOSEvrak`.
6. Windows 11'de "Önizle" ve "Düzenle" komutları yalnız "Diğer seçenekleri göster" altında görünüyor. ProgID'de `edit` fiili yok.

### Linux'ta neden çalışmıyor

1. Normal kurulum (`kur.sh` → `install_local.py`) **UDF için MIME tanımı kurmuyor**. Sistem `*.udf` dosyasını tanımadığı için ZIP (`application/zip`) sanıyor. Masaüstü dosyasındaki `application/udf` hiç eşleşmiyor, bu yüzden Folio "Birlikte aç" listesinde çıkmıyor.
2. Ayarlar'dan kayıt yapılırken `update-mime-database`, `update-desktop-database` ve `xdg-mime` var mı diye bakılmıyor. Biri eksikse işlemin tamamı yarıda kalıyor.
3. Takma ad türlerinde (`application/x-udf` gibi) doğrulama yanlış hata ("Bazı türler atanamadı") verebilir.
4. Masaüstü dosyasında `--preview` yok ve `[Desktop Action]` tanımları yok. "Önizle" ve "Düzenle" yalnız Nautilus/Nemo betik menüsünde var.
5. Kurulum, Editör'ün masaüstü dosyasını `update-desktop-database` çalıştıktan sonra yazıyor; bu yüzden Editör'ün türleri dizine girmeyebilir.

### Yapılacaklar (T17)

**Windows**

- [ ] `register-viewer.ps1` kurulumla aynı kaydı yazsın:
  - açma komutu `--preview --` ile;
  - Capabilities'te bütün desteklenen türler (seçim yalnız "varsayılan yap" listesini etkilesin);
  - var olan anahtarlar silinmeden düzenlensin.
- [ ] ProgID'e `edit` ve `preview` fiilleri, `Applications\lifeos_folio.exe` (FriendlyAppName, SupportedTypes) ve ApplicationIcon.
- [ ] Kayıttan sonra `SHChangeNotify(SHCNE_ASSOCCHANGED)`; Folio'nun kendi ayar sayfasını aç.
- [ ] `test-installer.ps1`'e Ayarlar düğmesinden sonra da açma komutunu ve türleri doğrulayan adım ekle.

**Linux**

- [ ] `install_local.py` MIME XML'ini kursun ve `update-mime-database` çalıştırsın.
- [ ] Masaüstü dosyasına `Actions=Preview;Edit;` ekle; varsayılan açılış `--preview`.
- [ ] Eksik araç varsa adım adım devam etsin ve hangisinin eksik olduğunu söylesin; takma ad türlerinde doğrulama kanonik türe baksın.
- [ ] Editör'ün masaüstü dosyası `update-desktop-database`'den önce yazılsın.

**İkisi için**

- [ ] Önizleme penceresine görünür bir "Düzenle" düğmesi.

---

## 5. Büro ağı üzerinden dosya ve evrakla görev verme

### Bugün: temel çalışıyor

Dosyayı evraklarıyla birlikte görev olarak göndermek **zaten var** (`docs/buro.md` "Büro yönetimi ve görev", 8 Ekim'de yapıldı):

1. **Nereden verilir:** Dosya detay › Görevler sekmesi › **"Bu dosya için görev ver"**, ya da bir evrakın önizlemesinden **"Bu evrakla görev ver"**.
2. **Paketleme:** `TaskPackage.pack`, seçilen evraklardan inmemiş olanları önce UYAP'tan indirir, sonra dosya künyesi, taraflar ve evrak listesiyle birlikte paketler.
3. **Gönderme:** Paket imzalı görev olayıyla gider. Görevli çevrimdışıysa ağa gelince alır.
4. **Teslim:** Görevli paketi Görevler sayfasında ve portföydeki "Görevle gelen dosyalar" listesinde görür.

### Eksikler: görevin "kaliteli" çalışması için

| # | Eksik | Neden önemli |
|---|---|---|
| 1 | Dosya detay Evraklar sekmesinde **çoklu seçim yok**; yalnız tek evrak ya da hiçbiri önceden seçilebiliyor. | "Seçtiğim evraklarla görev ver" doğrudan yapılamıyor. |
| 2 | Görev penceresi **ilk 40 evrakı** gösteriyor, **ekleri** göstermiyor, **inmiş/inmemiş** işareti yok. | Hangi evrakın indirilmesi gerektiği görülmüyor; büyük dosyada evrak kayboluyor. |
| 3 | UYAP bağlı değilse paketleme **bağlanmayı önermiyor**; evrakları "indirilemedi" diye bildiriyor. | Görevli evraksız kalıyor. |
| 4 | İndirme **ilk hatada duruyor**; kalanların hepsi "eksik" sayılıyor. Evrak başına ilerleme ve yeniden deneme yok. | Tek bozuk evrak bütün paketi bozuyor. |
| 5 | Pakette **duruşmalar, süreler, UETS tebligatları ve notlar yok**; yalnız künyedeki "sonraki duruşma" yazısı var. `buro.md` bunların gideceğini yazıyor. | Görevli süreyi ve duruşmayı göremiyor. |
| 6 | Gelen dosya görevlinin **dosya listesine eklenmiyor**; yalnız görev sayfasından açılıyor. | Görevli dosya detay ekranında çalışamıyor. |
| 7 | **Müvekkil sayfasından ve Ajanda'dan görev verilemiyor.** | İstediğiniz akışlardan biri bu. |

### Önerilen akış

1. Dosya detay › Evraklar: satırlarda onay kutusu, üstte **"Seçilenlerle görev ver (3)"**.
2. Görev penceresi:
   - bütün evraklar ve ekleri görünür; her satırda "inmiş" ya da "indirilecek" etiketi;
   - "Dosya verisi" bölümünde künye, taraflar, duruşmalar, süreler ve tebligatlar varsayılan olarak seçili.
3. **"Görevi ver"** basılınca:
   - eksik evrak varsa ve UYAP bağlı değilse T14'teki tek bağlantı penceresi açılır;
   - evraklar tek tek inerken satır satır ilerleme gösterilir;
   - inemeyenler için "yeniden dene" ve "bunlarsız gönder" seçenekleri sunulur.
4. Görevli tarafı: dosya "Görevle gelen" işaretiyle dosya listesine eklenir ve dosya detay ekranında açılır. UYAP'tan tazeleme, görevli kendi bağlantısını kurarsa çalışır.
5. Müvekkil sayfası: müvekkilin dosyaları arasından seçip **"Görev ver"**.
6. Ajanda: duruşma ya da süre satırından **"Görev ver"**. Dosya ve ilgili duruşma ya da süre önceden seçili gelir.

### Yapılacaklar (T18)

- [ ] Evraklar sekmesinde çoklu seçim; `TaskGiveDialog`'a `initialDocKeys`.
- [ ] Görev penceresinde tam evrak listesi: ekler, 40 sınırı kalkar, inmiş/indirilecek etiketi.
- [ ] Paketlemeden önce `ensureUyap` (T14).
- [ ] Evrak başına indirme: hata yakalama, ilerleme, yeniden deneme.
- [ ] `dosya.json`'a duruşmalar, süreler, UETS tebligatları ve notlar; alıcıda birleştirme.
- [ ] Alıcıda dosyayı "görevle gelen" olarak dosya listesine ekle; dosya detay ekranında aç.
- [ ] Müvekkil sayfasından ve Ajanda'dan görev ver.
- [ ] Testler: seçilen ve inmemiş evrak indirilip gidiyor; biri inmezse kalanlar yine gidiyor; alıcıda dosya detay ekranı açılıyor.

---

## Önerilen sıra

| Sıra | İş | Neden önce |
|---|---|---|
| 1 | **T14 Tek bağlantı** | Her gün karşılaşılan sorun; T16 ve T18 de buna dayanıyor. |
| 2 | **T17 Dosya ilişkilendirme** | Kesin hatalar; kısa sürer. Windows'ta ve Linux'ta denemeniz gerekecek. |
| 3 | **T18 Görev iyileştirmeleri** | |
| 4 | **T16 Masaüstü profil e-imzayla** | |
| 5 | **T15 Telefon kurulumunda eşleştirme ve ilk eşitleme** | En büyük iş; profil hatası ilk adım olarak önce düzeltilir. |

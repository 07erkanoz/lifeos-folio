# Büro ağı: paylaşım ve görev

Taslak: [docs/design/buro-paylasim-taslak.html](design/buro-paylasim-taslak.html) (görüntüsü `buro-paylasim-taslak.png`). Taslak 7 Ekim 2026'da onaylandı.

## Amaç

Büro içinde işi hızlandırmak. Aynı ağdaki Folio'lar birbirini bulur. Bir avukat bir başkasına evrak, bir UYAP dosyasının evrakını ya da dilekçe gönderir; kendi cihazları arasında klasör ve oturum taşır. İkinci aşamada bir dosyayı ya da bir işi bir avukata görev olarak verir, görevin dönüşünü izler.

Her şey büronun ağı içinde, cihazdan cihaza gider. Sunucu yok, internet gerekmez, hiçbir şey büronun dışına çıkmaz.

## Aşamalar

1. **Paylaşım ve kendi cihazlar** (bu belgenin ana konusu)
   - Aynı ağdaki cihazları kullanıcıya göre görmek.
   - Cihaz tanıma (eşleme) ve şifreli aktarım.
   - Dosya, klasör, UYAP dosyasından evrak, UETS evrakı, dilekçe göndermek.
   - Bir kişiye, bir cihaza ya da herkesin varsayılan cihazına göndermek.
   - Kendi cihazlar arasında klasör eşitleme.
   - Kendi cihazlar arasında oturum aktarımı (UYAP Mobil, UETS, UYAP Web).
   - Telefondan hızlı gönderme (paylaşma ekranından "Folio ile gönder").
2. **Görev** (1. aşama kullanılmaya başlandıktan sonra)
   - Bir dosyayı seçili ya da bütün evrakıyla, ya da bir dilekçeyi bir avukata görev olarak vermek.
   - Görevin kabulü, yapılması, düzenlenen evrakın geri gönderilmesi, tamamlanması.
   - Açık görevlerin takibi ve her adımda bildirim.

## 1. aşama: ekranlar

Taslaktaki beş görünüm:

1. **Büro ağı sayfası** (sol menüde BÜRO altında "Büro ağı"; gelen aktarım sayısı rozet olarak görünür). Sekmeler: Gönder, Kendi cihazlarım, Görevler (2. aşamada). Sayfanın üç sütunu var:
   - **Kişiler ve cihazlar:**
     - Kişiler gruplanır: "Av. Erkan Öz (siz)" altında masaüstü, telefon, dizüstü; diğer avukatlar ve büro çalışanları kendi cihazlarıyla.
     - Her cihazın türü (Linux, Windows, macOS, Android, iOS) ve durumu görünür: çevrimiçi yeşil, kapalı gri ve son görülme saatiyle.
     - Varsayılan cihaz yıldızla işaretlenir.
     - Alıcı, kişinin ya da tek bir cihazın yanındaki kutuyla seçilir. "Herkesin varsayılan cihazına gönder" de seçilebilir.
   - **Ne gönderilecek:**
     - Dosya ya da klasör bırakma alanı; "UYAP dosyasından evrak", "UETS evrakı", "Dilekçe" ve "Klasör" seçicileri.
     - Seçilenler kart olarak listelenir. Bir UYAP dosyası seçildiyse kartta seçili evrakın adları ve "dosyanın künyesi ve tarafları da gider" yazar.
   - **Kime ve not:** alıcı çipleri, "+ kişi ya da cihaz", isteğe bağlı bir not ve "Gönder".
   - **Aktarımlar:**
     - Bugünün gelen ve giden aktarımları: GELEN, GİDİYOR (ilerleme çubuğuyla), ALINDI.
     - Gelen aktarımda "Aç" ve "Klasörde göster".
2. **Kendi cihazlarım:**
   - **Klasör eşitleme:** Seçilen klasör, seçilen cihazlarda aynı kalır.
     - Silinen dosya kalıcı silinmez, çöp klasörüne alınır.
     - Türe göre süzgeç kurulabilir, örneğin yalnız UDF ve PDF.
   - **Oturum aktarımı:** UYAP Mobil, UETS ve UYAP Web oturumu kendi başka cihazınıza geçirilir; orada yeniden e-imzayla girmek gerekmez. Oturum başka bir kullanıcıya gönderilemez; uyarısı ekranda yazar.
3. **Yeni cihaz tanıma:**
   - Ağda tanınmamış bir Folio göründüğünde iki ekranda aynı altı haneli kod çıkar.
   - "Kodlar aynı, tanı" denince cihaz tanınır. Ondan sonra her aktarım şifrelidir ve kod bir daha sorulmaz.
4. **Telefon:**
   - Telefonun paylaşma ekranında "Folio ile gönder" çıkar.
   - Gönder ekranında gönderilecek dosya, ardından kişiler: önce "Kendi cihazlarım", sonra diğerleri.
5. **Dosya sayfasından paylaşma:**
   - Evrak listesinde seçip "Paylaş": seçili evrak, bütün evrak ya da yalnız künye ve taraflar.
   - Alan kişi dosyayı kendi "UYAP Dosyalarım"ında, gönderilen evrakla birlikte görür; UYAP'a bağlı olmasa da.

## 1. aşama: nasıl çalışır

### Bulma

- **Duyuru:** Her Folio aynı ağda DNS-SD (mDNS) ile `_folio._tcp` hizmeti olarak kendini duyurur. Duyurunun içeriği:
  - cihaz kimliği (açık anahtarın kısa özeti);
  - görünen ad, yani avukat profilindeki ad, örneğin "Av. Deniz Kaya";
  - cihaz türü ve adı (Masaüstü · Windows);
  - dinlediği kapı (port);
  - protokol sürümü.
- Duyuruda dosya, dosya adı ya da müvekkil bilgisi yer almaz.
- **Kişiye göre gruplama:** Görünen ad ve kullanıcı kimliğine göre. Kullanıcı kimliği, kişinin cihazlarını birbirine bağlayan anahtardır; "Kimlik" bölümüne bakın.
- **Çoklu yayın engelliyse:** Bazı kurumsal ağlar mDNS'i engeller. O durumda "Cihaz ekle" ekranında karşı cihazın IP adresi elle girilebilir, ya da karşı cihazdaki QR kod okutulur.

### Kimlik

- **Cihaz anahtarı:** İlk açılışta bir Ed25519 anahtar çifti oluşturulur ve işletim sisteminin güvenli deposunda (SecretStore) saklanır. Açık anahtarın özeti cihaz kimliğidir.
- **Kullanıcı anahtarı:** Ayrıca kişiye ait bir anahtar daha vardır.
  - Kişinin ilk cihazında oluşturulur.
  - Kendi cihazlarını tanıtırken diğer cihazlara güvenli olarak geçirilir.
  - "Bu cihazlar aynı kişinin" bilgisi bu anahtarın imzasıyla kurulur.
  - Kişinin kendi cihazları arasında klasör eşitleme ve oturum aktarımı yalnız bu imza doğrulanınca yapılır.
- **Kullanıcı hesabı yok:** Ayrı bir hesap ya da şifre kurulmaz. Görünen ad avukat profilinden gelir (bkz. açık karar 1).

### Tanıma (eşleme)

- **Kod:** İki cihaz ilk kez konuşurken ECDH (X25519) ile ortak bir anahtar kurulur. İki tarafın açık anahtarlarından ve oturum verisinden altı haneli bir doğrulama kodu üretilir; iki ekranda aynı kod görünür.
- **Onay:** İki taraf da "Kodlar aynı, tanı" der. Bundan sonra karşı cihazın açık anahtarı "tanınan cihazlar" listesine yazılır.
- **Kaldırma:** Tanınan bir cihaz Kendi cihazlarım ya da kişiler listesinden kaldırılabilir. Kaldırılan cihaz yeniden tanınana kadar hiçbir şey gönderemez, alamaz.
- **Kendi cihazınızı tanıtma:** Kod ekranında "Bu cihaz da benim" işaretlenirse kullanıcı anahtarı karşı cihaza geçer. İki cihazda aynı profil adı görünüyorsa kutu işaretli gelir. Anahtarı paylaşan cihazlar birbirini, aralarında kod olmadan da tanır; her cihaz bağlantıda kişi anahtarıyla imzalı sertifikasını gösterir.
- **QR ile tanıma (telefon):** Bilgisayarda Büro ağı'nda "Telefonumu ekle" bir QR gösterir: bilgisayarın adresleri, kapısı, cihaz kimliği ve beş dakikalık, tek kullanımlık bir sır. Telefon "QR okut" ile okur; sırrı bildiğini HMAC ile kanıtlar, bilgisayar da QR'daki cihaz olduğunu anahtarıyla kanıtlar. Kod karşılaştırılmaz ve telefon kişinin kendi cihazı sayılır.
- **Kendi cihaz denetimi:** Bir cihazın "kendi cihazım" sayılması yalnız kanaldaki sertifikaya dayanır (`OfficeChannel.vouched`). Cihazın duyurduğu kullanıcı kimliği kanıt sayılmaz.

### Aktarım

- **Bağlantı:** Tanınan cihazlar arasında her konuşma şifrelidir (3. adım: X25519, HKDF, ChaCha20-Poly1305). Taraflar birbirini tanıma sırasında saklanan açık anahtarlarla doğrular; sertifika otoritesi gerekmez. Söz almayan bağlantı 20 saniyede kapanır; aynı anda en çok 32 bağlantı bekleyebilir.
- **Teklif ve kabul:**
  1. Gönderen bir "teklif" yollar: ne gönderildiği, dosya adları, boyutları, SHA-256 özetleri, not ve bağlı olduğu UYAP dosyası.
  2. Alan taraf kabul eder.
  3. Dosyalar parça parça gider. Kesilen aktarım kaldığı yerden sürer; her dosya inince özeti denetlenir.
- **Kabul kuralı:**
  - Kişinin kendi cihazlarından gelen kendiliğinden kabul edilir.
  - Başka kişiden gelende alan tarafa sorulur. İsterse "bu kişiden gelenleri hep kabul et" denebilir.
- **Nereye düşer:**
  - UYAP evrakı, alanın UYAP klasöründe o dosyanın klasörüne düşer ve dosyasına bağlanır.
  - Dosya alanda yoksa "UYAP Dosyalarım"da, gönderilen künye ve taraflarla yeni bir dosya olarak görünür ve "paylaşılan" diye işaretlenir.
  - UETS evrakı, alanın UETS klasörüne tebligatın bilgisiyle düşer.
  - Diğer dosyalar "Gelenler" klasörüne düşer.
- **Kayıt:** Her aktarım gönderende ve alanda bir aktarım kaydına yazılır: kim, kime, ne, ne zaman, sonuç. Aktarımlar listesi bu kayıttan gelir.

### UYAP dosyası paketi

Bir UYAP dosyası gönderildiğinde paket şunları taşır:

- dosyanın künyesi: mahkeme, esas numarası, türü, durumu;
- taraflar ve vekilleri;
- seçilen evrak, UYAP'taki özgün dosyaları ve evrak bilgileriyle;
- isteğe bağlı olarak dosyanın UETS tebligatları ve süreleri;
- gönderenin notu.

UYAP oturum kimlikleri (dosyaId gibi) pakete girmez. Bunlar oturumluktur ve karşı tarafta işe yaramaz. Dosya, alanda esas numarası ve mahkemeyle eşleşir.

### Klasör eşitleme (kendi cihazlar)

- **Kim ve ne:** Yalnız aynı kişinin cihazları arasında, seçilen klasörler eşitlenir.
- **Nasıl:** Her cihaz klasörün bir dizinini tutar: göreli yol, boyut, değişiklik zamanı, SHA-256. Ayrıca her dosyanın son eşit hâlinin özetini saklar. Cihazlar karşılaştığında dizinleri karşılaştırır; her cihaz öbüründe olmayanı ve kendisinde değişeni gönderir. Alan, dosyayı yerine koyunca "yerleştirdim" der; gönderen ancak o zaman eşit sayar.
- **Katılma:** Bir cihazda seçilen ya da Senkron sayfasına bırakılan klasör, öbür cihazlarda "paylaşılıyor" diye görünür. Bilgisayarda mevcut dosyaların hepsi gelir; telefonda mevcut dosyaların da gelip gelmeyeceği sorulur. Katılınan klasör Senkron klasörüne (UYAP klasörünün yanına) açılır ve arşive eklenir.
- **Silme:** Bir cihazda silinen dosya, öbüründe kalıcı silinmez; Senkron çöpüne alınır ve 30 gün sonra temizlenir. Karar saatlere değil, dosyanın son eşit hâlinden beri değişip değişmediğine göre verilir.
- **Çakışma:** Aynı dosya iki tarafta da değiştiyse ikisi de saklanır. Cihaz kimliği küçük olanın hâli adını korur; öbürü "ad (cihaz adı).uzantı" olarak durur; hiçbiri ezilmez.
- **Süzgeç:** Yalnız Folio'nun açtığı türler eşitlenir; nokta ile başlayan dosya ve klasörler alınmaz. Klasör dışına çıkan yollar ve sembolik bağlantılar reddedilir; iç içe klasörler eşitlenmez.

### Oturum aktarımı (kendi cihazlar)

- **Ne aktarılır:** UYAP Mobil'in jetonları, UETS oturumu ve UYAP Web oturumu, saklandıkları biçimde, şifreli bağlantıyla kendi başka cihaza geçer ve oranın güvenli deposuna yazılır.
- **Kime:** Yalnız kullanıcı anahtarıyla doğrulanmış kendi cihazlarınıza. Başka bir kullanıcıya oturum gönderilemez.
  - Gerekçe: Oturum e-imzayla açılmış kişisel bir giriştir. Başkası o oturumla sizin adınıza evrak gönderebilirdi.
- **Oturum taşınır, kopyalanmaz:** UYAP Mobil'in yenileme jetonu her yenilemede değişir; iki cihaz aynı oturumu kullanırsa birbirini düşürür. Bu yüzden "Bu cihaza al" ve "Öbür cihaza ver" oturumu taşır. Alan cihaz oturumu güvenli deposuna yazıp "aldım" der; veren cihaz oturumu yalnız o zaman, yalnız kendinde kapatır. UETS ve UYAP Web için de aynı kural geçerlidir.

### Telefon

- **Android:** Paylaşma hedefi ("Folio ile gönder") olur. Büyük aktarımlar sürerken ekran kapansa da kesilmesin diye aktarım boyunca bir ön plan bildirimiyle çalışılır.
- **iOS:** Paylaşma eklentisi (Share Extension) gerekir. Aktarım Folio açıkken yapılır; iOS arka planda yerel ağ bağlantısına izin vermez.
- **İzinler:** İki platformda da "yerel ağ" izni istenir.

## Güvenlik ve gizlilik

- **İnternet yok:** Hiçbir veri büronun ağı dışına çıkmaz; aracı sunucu yok.
- **Duyuru:** Dosya ya da müvekkil bilgisi taşımaz, yalnız cihazın görünen adını taşır.
- **Şifreleme:** Tanınmamış bir cihazla hiçbir şey alınıp verilmez. Tanınan cihazla her aktarım uçtan uca şifrelidir ve karşı taraf açık anahtarıyla doğrulanır.
- **Anahtarlar:** Cihaz ve kullanıcı anahtarları güvenli depoda tutulur; hiçbir yere yazılmaz.
- **Oturumlar:** Yalnız kişinin kendi cihazları arasında taşınır.
- **İz:** Her aktarım kayda geçer; kim neyi kime gönderdi görülebilir.
- **İptal:** Bir cihaz kaybolursa yönetici onu bürodan çıkarır; kişinin ilk cihazı çıkarılırsa kişi bütün cihazlarıyla çıkar. Çıkarılan cihaz görev, sohbet ve paket alamaz; gönderdiği dosyalar sorulmadan kabul edilmez. Büronun ortak bir anahtarı olmadığı için yenilenecek anahtar yoktur.
- **İmzalı kayıtlar:** Defterin her kaydı, her görev adımı ve her mesaj yazan cihazın anahtarıyla imzalıdır ve defterdeki üye anahtarıyla doğrulanır. "Görev verildi" adımının imzası görevin başlığını, son gününü, dosyalarını ve kime verildiğini de kapsar.
- **Disk:** Folio dosyaları diskte şifrelemez; uygulama kilidi yalnız Folio'nun açılmasını önler. Disk şifrelemesi (BitLocker, FileVault) önerilir.

## Platform notları

| Platform | Bulma ve aktarım | Not |
|---|---|---|
| Linux | Avahi ile mDNS, arka planda da çalışır | Tepside çalışmayla açık kalır |
| Windows | mDNS ve TCP dinleme | İlk açılışta Windows Güvenlik Duvarı izni ister |
| macOS | Bonjour | Info.plist'e `NSLocalNetworkUsageDescription` ve `NSBonjourServices` (`_folio._tcp`) gerekir; yerel ağ izni sorulur |
| Android | NSD | Yerel ağ izni; büyük aktarımda ön plan hizmeti |
| iOS | Bonjour | Yalnız Folio açıkken; paylaşma eklentisi gerekir; Info.plist girdileri macOS'takiyle aynı |

Dart tarafında mDNS için `bonsoir` ya da `nsd` gibi bir paket, şifreli bağlantı için `cryptography` (zaten kullanılıyor) ile Noise ya da `dart:io` SecureSocket düşünülür. Seçim, beş platformda çalıştığı ölçülerek yapılır.

## 2. aşama: görev

- **Görev nedir:** Bir kişiye verilen, bir dosyaya bağlı iş: "2024/318 · bilirkişi raporuna itiraz dilekçesini hazırla, son gün 16.10.2026".
  - Göreve evrak eklenebilir: seçili evrak, dosyanın bütün evrakı ya da bir taslak dilekçe.
- **Akış:** Verildi → Kabul edildi → Sürüyor → Tamamlandı. Görevi alan "İade" de diyebilir.
  - Tamamlarken düzenlediği evrakı (örneğin dilekçenin son hâlini) ve bir not ekler. Evrak görevi verenin cihazına, dosyanın klasörüne düşer.
- **Takip:**
  - Görevler sekmesinde "Verdiğim" ve "Bana verilen" açık görevler.
  - Ajandada son günüyle görünür; dosyanın sayfasında "Görevler" bölümü olur.
  - Her adımda karşı tarafa bildirim gider.
- **Eşitleme:**
  - Görev kayıtları aynı şifreli kanalla, kişiler arasında eşitlenir.
  - Her alan için son yazan kazanır; ama durum geçişleri yalnız ileri gider, eski bir kayıt yeni bir durumu geri almaz.
  - Karşı cihaz kapalıysa kayıt sıraya alınır, cihaz görünce gider.
- **Dosya görevlendirme:** "Bu dosyayı Av. Mert Yıldız'a görevlendir" dendiğinde dosyanın paketi gider. Dosya karşı tarafta "görevlendirilen" olarak işaretlenir.

## Büro yönetimi ve görev (onaylandı 8 Ekim 2026)

Taslak: [docs/design/buro-yonetim-taslak.html](design/buro-yonetim-taslak.html). Bu bölüm 2. erişim kararının yerini alır: büroya üyeyi yönetici kabul eder.

- **Büro ve roller:** Büroyu kuran yöneticidir. Yönetici üye kabul eder, çıkarır, rol verir, başka yönetici atar. Roller: Yönetici, Avukat, Stajyer, Sekreter.
  - Yönetici herkese görev verir ve bütün görevleri görür.
  - Avukat kendine, stajyere ve sekretere görev verir; kendi verdiği ve aldığı görevleri görür.
  - Stajyer ve sekreter kendilerine verilen görevleri yürütür ve teslim eder.
- **Kayıt defteri (sunucusuz):** Büro, imzalı kayıtlardan oluşan bir defterdir. İlk kayıt kurucunun cihaz anahtarıyla imzalanır; büronun kimliği bu kaydın özetidir. Üye ekleme, rol ve çıkarma kayıtlarını o an yönetici olan bir cihaz imzalar. Defter üyeler arasında şifreli kanalla dolaşır; geçerli imzası olmayan kayıt hiçbir cihazda kabul edilmez.
- **Katılma:** Yeni cihaz bir yöneticiyle kodla tanışır, yönetici "Kabul et" der, üyelik kaydı deftere girer. Defterdeki üyeler birbirini ayrıca tanımadan şifreli konuşur.
- **Görev:** Bir ya da birkaç kişiye, bir ya da birkaç UYAP dosyası. Her dosyanın kendi yapılacak işleri vardır (her biri bir kişiye); işi veren her dosya için seçili evrak, bütün evrak ya da yalnız künye ve taraflar gönderir.
  - Alan kişi o dosyada UYAP yetkisi olmasa da dosyayı UYAP Dosyalarım'da "görevle gelen" olarak görür ve gelen evrakı inceler; o dosyada UYAP'tan tazeleme kapalıdır.
  - Görevli o dosyayı kendi UYAP'ıyla açamadığı için her şey işi verenden gider: seçilen evrakın bilgisayarda olmayanları, görev verilmeden önce işi verenin Folio'su tarafından UYAP'tan indirilir; evrakla birlikte dosyanın detayı da gider (künye, taraflar ve vekilleri, evrak listesi, duruşmalar, süreler). İndirilemeyen evrak varsa (UYAP bağlantısı yoksa) görev verilmeden önce söylenir.
  - Akış: Verildi → Sürüyor → Teslim edildi → Tamamlandı (veren onaylar) ya da geri gönderilir. İşi alan not, ilerleme ve evrak ekler; teslimde yapılan işi yazar ve evrakı ekler. Evrak verenin cihazında dosyanın klasörüne düşer.
  - Görev kayıtları imzalı olaylardır; ilgili kişilerin cihazlarına gider, kapalı cihaz için sıraya alınır. Son gün ajandaya düşer; dosya sayfasında "Görevler" sekmesi olur.
- **Benzer ürünlerden alınanlar** (Clio, Filevine, Smokeball, Mühlet, Dosya360, Asana, Linear, Keybase, Matrix, Syncthing; araştırma 8 Ekim 2026):
  - Durumlar: Verildi → Sürüyor → İncelemede (teslim edildi) → Tamamlandı; ayrıca İptal. Geri gönderilen iş "Sürüyor"a döner, tamamlanmış sayılmaz (Asana'nın bilinen hatası); geri gönderme ve iptal gerekçe ister.
  - Son gün duruşmaya ya da süreye göreli verilebilir ("duruşmadan 7 gün önce"); duruşma kayarsa görev sessizce kaymaz, sorulur. Hatırlatma kademelidir (7, 3, 1 gün) ve "Gördüm" ile durdurulur.
  - Dava türüne göre hazır iş şablonları; iş yükü görünümü (kişi başına açık işler, durumlarına göre).
  - Stajyere verilen işte gözetimden sorumlu avukat kayda geçer (Av. K. m. 26).
  - KVKK: asgari paylaşım; varsayılan seçili evraktır, bütün evrak bilerek seçilir.
  - **Yazışma:** Her görevin kendi yazışma alanı vardır; mesajlar ve ekleri, durum değişiklikleriyle aynı akışta ama ayrı görünür.
  - Defter: kurucu kalıcı üst yetkilidir, onu yalnız kendisi değiştirir; kayıtların sırası cihaz saatinden değil, her kaydın bağlandığı önceki kayıttan gelir (Matrix'in saat sorunu). Silinen üye kayıtla silinir, başka bir cihaz onu geri getiremez (Syncthing'in sorunu). Ortak bir büro anahtarı yoktur: her görev ve mesaj iki cihaz arasındaki kendi kanalından gider ve alan cihaz göndereni defterde üye olarak görmezse kabul etmez; bu yüzden üye çıkınca yenilenecek bir anahtar da yoktur. Çıkan üyenin elindeki eski görev ve mesajlar geri alınamaz.
- **Mesajlaşma (görevden bağımsız):** Özel mesaj (iki üye), grup mesajı (seçilen üyeler) ve toplu duyuru (yalnız yöneticiler, bütün büroya). Hepsi üyelerin şifreli kanalından gider; ek evrak gönderilebilir. Görevden bağımsız evrak gönderme Büro ağı sayfasındaki "Gönder" ile sürer.
- **Bildirimler:** Gelen mesaj, görev, teslim, onay, geri gönderme ve dosya teklifi sistem bildirimi olarak (masaüstünde tepsiden de) çıkar. Folio kilitliyken bildirimde içerik yazmaz, yalnız "Yeni mesaj" gibi genel bir söz çıkar.
- **Giriş şifresi (Ayarlar › Güvenlik, yapıldı 8 Ekim 2026):** Açılışta ve seçilen süre kullanılmayınca ekran koruyucu gibi bir kilit; büro varsa adı yazar. Şifre ve kurtarma kodu yalnız PBKDF2 özetiyle saklanır; yanlış denemeler bekletilir; kurtarma koduyla yeni şifre konur ve kod yenilenir. Şifre dosyaları şifrelemez (disk şifrelemesi önerilir). Sonra: UYAP/UETS oturumlarını şifreye bağlamak, LifeOS Editör penceresini de kilitlemek, telefonda parmak izi.
- **Yapıldı (8 Ekim 2026):** büro ve roller (imzalı defter), Görevler sayfası (pano, görev ver, görevin sayfası, teslim, onay, geri gönderme, iptal, görev yazışması), Mesajlar sayfası (özel, grup, duyuru; dosya, resim, sesli mesaj), sistem bildirimleri (kilitliyken içeriksiz), görevle giden dosya paketi (eksik evrak UYAP'tan indirilir, indirilemeyen söylenir; künye, taraflar ve evrak alanın görev sayfasında incelenir).
  - Ardından yapılanlar: görevle gelen dosyalar UYAP Dosyalarım'ın üstünde, son günler ajandada, dosya sayfasında "Görevler" sekmesi ("Bu dosya için görev ver"), kademeli hatırlatmalar (7, 3, 1 gün, son gün, gecikince her gün; "Gördüm"), dava türüne göre iş şablonları (`assets/buro/gorev_sablonlari.json`, veri olarak), iş yükü görünümü (yöneticiler), menüde okunmamış mesaj ve açık görev sayıları.
  - Sonra yapılanlar: görev ve mesaj olaylarının tek tek imzalanması, kurucu kurtarma kodu, telefonda QR ile kendi cihazını tanıtma, Senkron sayfası, Gelenler; son günü duruşmaya göre verilen görev (duruşmadan 1, 3, 7 ya da 14 gün önce): duruşma UYAP Web'in listesinden kalkınca işi verene sorulur ("Kaydır" ya da "Eski günde kalsın"), kendiliğinden kaymaz; UYAP Mobil eski duruşmayı silmediği için yalnız UYAP Mobil bağlıyken soru Web eşitlemesinden sonra gelir.
  - Açık kalanlar: mesajı silme ve düzeltme; iOS paylaşma eklentisi; cihaz bulmanın Windows, macOS, iOS ve Android'de ölçülmesi.
- **Yapım sırası:** (1) büro, üyelik ve roller; (2) görev verme ve pano; (3) gidişat, teslim ve onay; (4) görevle gelen dosya, ajanda ve dosya sayfası bağlantıları.

## Kararlar (8 Ekim 2026)

1. **Kişi kavramı:** Bir cihaz, oradaki Folio'nun avukat profilindeki adla görünür. Ayrı bir kullanıcı hesabı ya da şifre kurulmaz.
2. **Erişim:** Ağdaki her iki Folio, iki ekranda aynı altı haneli kodu görüp ikisi de onaylayınca birbirini tanır. Ayrı bir büro yöneticisi yoktur.
3. **Kendi cihazlar:** TC numarasıyla onaysız eşleşme yapılmaz; TC gizli değildir (dilekçede, vekâletnamede, UYAP evrakında yazar) ve onu bilen biri kendini kişinin cihazı gibi tanıtıp oturumlarını alabilirdi. Bunun yerine:
   - Her yeni cihaz hayatında bir kez onaylanır. İkinci cihaz tanınınca kişi anahtarı ona geçer; üçüncü cihaz kişinin herhangi bir cihazına tanıtılınca öbürleri onu kendiliğinden tanır.
   - Telefonu tanıtırken bilgisayarda QR kodu çıkar, telefonla okutulur; kod karşılaştırmak gerekmez. Bilgisayarlar arasında altı haneli kod bir kez karşılaştırılır.
   - TC yalnız ipucudur: bağlantı kurulduktan sonra ağa açılmadan karşılaştırılır; aynıysa pencere "Bu sizin cihazınız" diye açılır.
4. **Senkron sayfası:** Büro ağından ayrı bir sayfa; yalnız kişinin kendi cihazları arasında klasör ve dosya, ajandadaki işler ve notlar, UYAP Mobil, UETS ve UYAP Web oturumları eşitlenir.
5. **Katılma:** Folio, kullanıcı Büro ağı sayfasında "Bu ağa katıl" demedikçe ağda duyurulmaz; duyuruda avukatın adı bulunduğu için ortak ağlarda (kafe, otel) kendiliğinden görünmesi istenmez. Katıldıktan sonra her açılışta yeniden katılır, "Ağdan ayrıl" diyene kadar.

## Kişi, cihazları ve kurtarma (yapıldı, 8 Ekim 2026)

- **Kişi:** Büroda görev ve sohbet cihaza değil kişiye verilir. Kişinin büroya alındığı ilk cihaz kişinin kimliğidir.
- **Kendi cihazını ekleme:** Kişinin kanıtlı kendi cihazı büronun bir cihazıyla karşılaşınca deftere kendiliğinden eklenir ("kendi" kaydı). Yönetici onayı gerekmez, ama kayıt üç kanıt ister: yeni cihazın kendi anahtarıyla verdiği katılma onayı, iki cihazın aynı kişi anahtarına bağlı olduğunu gösteren sertifikalar ve kişi anahtarı. Yeni cihaz kişinin adını ve rolünü alır.
- **Kurallar:** Rol kişinin bütün cihazlarına uygulanır. "En az bir yönetici" kuralı cihazları değil kişileri sayar. Kişinin sonradan eklenen cihazına verilmiş görevlerin dava paketleri de gider.
- **Kurucu kurtarma kodu:** Kurucu, Büro ağı'nda 32 harf ve rakamlık bir kod oluşturup kâğıda yazar. Defter yalnız kodun açık anahtarını tutar; yeni kod eskisini geçersiz kılar. Kurucu bütün cihazlarını kaybederse yeni cihaz önce bir meslektaşının cihazıyla tanışır, sonra kodu girer ve kurucu olarak, aynı kişi olarak devam eder. Kod hiçbir veriyi çözmez; görevler ve mesajlar meslektaşların cihazlarından yeniden gelir.
- **İmza sürümü:** Görev ve mesaj imzaları bu sürümde değişti. Yayından önceki deneme cihazlarındaki eski görev ve mesajlar yeni cihazlara eşitlenmez.

## Yapım sırası (1. aşama)

Durum:

- **1. adım yapıldı** (8 Ekim 2026): `lib/services/office/` (kimlik, duyuru ve bulma `bonsoir` ile), `lib/ui/office/office_network_page.dart` (kişiler ve cihazlar).
  - Linux'ta ölçüldü: aynı makinede iki ayrı Folio birbirini adıyla ve adresiyle buldu; kapıya IPv4 ve IPv6 ile bağlanılabildi; kapanınca duyurular kalktı.
  - Linux eklentisi önce TXT kaydını, adresi sonra bildiriyor; adres ve kapı korunur, IPv4 adresi IPv6'ya tercih edilir.
  - Henüz ölçülmedi: Windows (güvenlik duvarı izni), macOS ve iOS (yerel ağ izni; Info.plist girdileri eklendi), Android (NSD).
  - Kişiler, kullanıcı anahtarları paylaşılana kadar (2. adım) profil adına göre gruplanır.
- **2. adım yapıldı** (8 Ekim 2026): `office_pairing.dart` (kodla tanıma), `office_known.dart` (tanınan cihazlar, `buro_cihazlar.json`'da yalnız açık anahtarlar ve adlar), `office_link.dart` (satır başına bir JSON; uzun satır bayt bayt sayılıp kesilir), `office_pairing_dialog.dart`.
  - Tanıyan taraf önce rastgele sayısının özetine bağlanır, karşının sayısını duyduktan sonra kendininkini açıklar; altı hane iki cihazın açık anahtarlarından ve iki sayıdan üretilir. Açıklanan sayı özetle tutmazsa tanıma durur.
  - İki taraf da onaylamadan hiçbiri tanınmaz; reddedilen ya da süresi (3 dakika) dolan tanıma kayda geçmez; bir tanıma sürerken gelen ikinci istek "meşgul" yanıtı alır.
  - Uçtan uca testler aynı makinede iki Folio'yu gerçek soketlerle konuşturur (`test/office_pairing_test.dart`).
  - Başka odadaki cihazda istek kullanıcı hangi sayfadaysa orada açılır; kod isteyen telefonla okuyup karşılaştırır. Kod tanınan cihazlar listesinde saklanır, sonradan da karşılaştırılabilir.
- **3. adım yapıldı** (8 Ekim 2026): `office_channel.dart` (şifreli kanal), `office_transfer.dart` (teklif, kabul, parça, sürme, özet).
  - El sıkışma: iki taraf bu konuşmaya özel X25519 anahtarı üretir, tanımada saklanan Ed25519 cihaz anahtarıyla imzalar; anahtarlar HKDF ile iki yöne ayrı türetilir, her mesaj ChaCha20-Poly1305 ile ve yalnız artan sayaçla mühürlenir. Tanınmayan cihaz konuşma bile açamaz.
  - 48 KB'lık parçalar, yolda en çok 8 parça; alan her dosyanın sonunda SHA-256'yı denetler, tutmazsa siler. Kesilen aktarım "Sürdür" ile aynı kimlikle yeniden teklif edilir ve alan elindekini söyler; yalnız kalanı gider. Dosya adından klasör kısmı atılır.
  - Gelenler "Folio Gelenler" klasörüne (masaüstünde İndirilenler altında) düşer; aktarım kaydı `buro_aktarimlar.json`.

1. Cihaz ve kullanıcı anahtarları; mDNS ile duyurma ve bulma; kişiler ve cihazlar listesi. Beş platformda bulmanın ölçülmesi.
2. Tanıma (kodla eşleme), tanınan cihazlar listesi, cihaz kaldırma.
3. Şifreli bağlantı; teklif, kabul ve parça parça dosya aktarımı; kaldığı yerden sürme; özet denetimi; aktarım kaydı.
4. Büro ağı sayfası: kişiler ve cihazlar, gönderme, aktarımlar (taslaktaki 1. görünüm).
5. UYAP dosyası paketi; dosya sayfasından "Paylaş"; alanda dosyaya bağlama (taslaktaki 5. görünüm). UETS evrakı gönderme.
6. Telefon: Android paylaşma hedefi ve iOS paylaşma eklentisi (taslaktaki 4. görünüm).
7. Kendi cihazlar: kişi anahtarının aktarımı ve yayılması, QR ile tanıma, TC ipucu. Ardından ayrı **Senkron sayfası**: klasör ve dosya eşitleme, ajanda işleri ve notları, oturum (jeton) aktarımı (taslaktaki 2. görünüm bu sayfaya taşınır).
8. Her adımda testler: iki Folio'yu aynı makinede sahte ağla konuşturan uçtan uca testler; tanınmamış cihazın reddedilmesi; yarım kalan aktarımın sürmesi; özeti tutmayan dosyanın atılması; başka kullanıcıya oturum gönderilememesi.

2. aşama, 1. aşama bürolarda kullanılmaya başladıktan sonra aynı belgeye ayrıntılandırılarak eklenir.

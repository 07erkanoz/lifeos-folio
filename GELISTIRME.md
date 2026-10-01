# Geliştirme planı — editör

26 Eylül 2026'da lifeOS Hukuk editörüyle yapılan karşılaştırmadan çıkan işler. Sıra, işin faydasına ve birbirine bağımlılığına göre konuldu. Her madde bitince işaretlenir, testleri geçince main'e gönderilir.

Durum: `[ ]` yapılacak · `[~]` sürüyor · `[x]` bitti

## İlerleme

| Madde | Durum | Commit |
|---|---|---|
| 1. Dayanaklar durum çubuğunda | bitti | `d632f64` |
| 2. Avukat profili ve kalıp boşlukları | bitti | `d540593` |
| 3. Kalıplar: anahtar kelime + Tab, Alt+F, yönetim | bitti | `2c8b1e9` |
| Ek: LifeOS Editör (ayrı program) | Windows'ta denendi; Linux GitHub'da derlendi, makinede denenecek | `9285513`, `8a710f7` |
| 4. Yazarken öneri ve akıllı öğrenme | bitti | bu commit |
| 5. Emsal kararı dilekçeye atıf olarak ekleme | bekliyor | — |
| 6. Cetvel: sekme durakları ve girintiler | bekliyor | — |
| 7. Otomatik biçimlendirme | bekliyor | — |

### Kalan işler

Sırayla yapılacak; her biri bitince testleri geçer, main'e gider ve burada işaretlenir.

1. **Akıllı öğrenme ve yazarken öneri** (madde 4) — bitti, 29 Eylül 2026.
   - 1. tur: öneri listesi (Enter ya da Tab ile kabul, Esc kapatır), Türkçe harf eşleşmesi, çok kelimeli eşleşme; kaynaklar: kalıp anahtar kelimeleri, avukat profili, yerleşik hukuk ifadeleri.
   - 2. tur: kaydedilen belgelerden ve arşiv indeksinden öğrenme (`oneriler.sqlite`), kişisel veri süzgeci, Ayarlar'daki üç anahtar ve "Öğrenilenler" yönetim ekranı.
2. **Emsal kararı dilekçeye atıf olarak ekleme** (madde 5, 1 tur).
3. **Cetvel: sekme durakları ve ilk satır girintisi** (madde 6, 1 tur).
4. **Otomatik biçimlendirme** (madde 7, 1–2 tur): başlık ortalı, metin iki yana yaslı, "DAVACI :" gibi satırlarda eşit sekme.
5. **LifeOS Editör'ün kalanları:** Linux makinede denenmesi (GitHub'daki Linux derlemesi geçti); Windows kurulum paketinin (Başlat menüsü, masaüstü, Birlikte aç) GitHub'daki paket işinde denenmesi — bu iş GitHub Releases'e sürüm yayımladığı için kullanıcı onayıyla çalıştırılır.
6. **Gezginde UDF önizlemesi ve küçük resim (Quick Look), Windows ve Linux:** plan ve ölçümler [docs/quicklook.md](docs/quicklook.md)'de; sonra yapılacak.
7. **Tarama araçlarının kalitesi** (29 Eylül 2026 ölçümüne göre; sürüyor):
   - [x] TIFF→PDF kayıpsız ve küçük: UYAP'ın 1 bit G4 sayfaları PNG'ye çevrilip 2 kat şişiyordu (22 MB → 43 MB). Artık 1 bit Flate: 20,1 MB, 274 gerçek sayfada pikseller libtiff'le bit bit aynı.
   - [x] PDF küçültme: taramalardaki JPEG'ler kayıpsız yeniden kodlanıyor (jpegtran -optimize -progressive). 25 gerçek taramada 41,6 MB → 36,4 MB (%12,6); PDFium, poppler ve Ghostscript render'ları aynı. Eskiden qpdf taramalarda %0,2 kazandırıyordu.
   - [x] OCR (PDF sayfaları): Tesseract'a `--dpi` veriliyor; güveni 85'in altında ya da harfi küçük sayfa, harfleri ~30 px olacak çözünürlükte (150–400 dpi) yeniden çizilip Sauvola ile okunuyor, iyisi tutuluyor. Ölçüm: 30 sayfada +%3,1, kötüleşen yok; küçük puntolu tutanakta "Kanun" 5 → 11 kez okunuyor.
   - [x] OCR (tek sayfalık resimler: JPG, PNG, tek sayfa TIFF): kötü okunan resim harfleri ~30 px olacak şekilde büyütülüp (Pillow'un bicubic'iyle aynı, Dart'ta 0,2 sn) Sauvola ile yeniden okunuyor. 30 gerçek resimde (20 belge fotoğrafı/tarama, 10 ekran görüntüsü) metindeki kelime 2784 → 3426 (+%23), süre 19 → 58 sn. Çok sayfalı TIFF'ler (UYAP) henüz eski yoldan okunuyor.
   - İsteğe bağlı kayıplı küçültme ("e-posta/UYAP için"), ne kaybedileceği yazılarak. Siyah-beyaz G4 taramaları ~7 kat küçültüyor (93 sayfada 41,4 MB → 5,7 MB) ama sayfaların yarısındaki mühür/ıslak imza rengini siliyor: yalnız renksiz sayfalarda ya da açık onayla.
8. **Android: kameradan PDF** `[~]` (CamScanner gibi): telefonun ana ekranında "Kameradan PDF tara". Google ML Kit belge tarayıcısı kenarları bulur, perspektifi düzeltir, 100 sayfaya kadar alır ve tek PDF verir; PDF sistemin kaydet penceresiyle seçilen yere yazılır, Folio'da açılır ve son açılanlara girer. Derlendi; telefonda denenecek.
   - **Kamera izni:** ML Kit kamerayı Google Play Hizmetleri'nin kendi ekranında açtığı için Folio izin istemiyor (29 Eylül 2026'da izinsiz yol seçildi). Play Hizmetleri olmayan telefonda tarayıcı açılmaz, bunu söyleyen bir uyarı çıkar.

### Biten maddeleri deneme

1. **Dayanaklar:** Kanun maddesi ya da karar atfı olan bir dilekçeyi editörde açın. Sayfanın altındaki çubuğun solunda "N dayanak" görünür; üstüne gelince kaç madde ve kaç karar olduğu yazar. Tıklayınca liste sayfa ile çubuk arasında açılır, yeniden tıklayınca kapanır. Atıfsız belgede hiçbir şey görünmez.
2. **Avukat profili:** Ayarlar → **Avukat profili**. Avukatları (biri varsayılan) ve büro bilgilerini girip kaydedin. Sonra metninde `[VEKİLLER]`, `[BARO]`, `[BUGÜN]` geçen bir kalıp oluşturup ekleyin: pencere açılmadan dolmalı. Bir de `[MÜVEKKİL]` ekleyin: yalnızca o sorulmalı, profildekiler "Avukat profilinden" notuyla hazır gelmeli.
3. **Kalıplar:** Ctrl+Space → **Kalıplarımı yönet** (ya da Ayarlar → **Kalıplarım**).
   - Bir kalıba anahtar kelime (ör. `dil1`) ve kısayol (ör. Alt+F2) verin.
   - Belgede `dil1` yazıp Tab'a basın: kalıbın gövdesi biçimiyle gelmeli. Ctrl+Z tek adımda geri almalı.
   - Alt+F2 kalıbı imlecin olduğu yere yazmalı; atanmamış bir Alt+F tuşu uyarı vermeli.
   - Aynı anahtar kelimeyi iki kalıba vermeye çalışınca hata çıkmalı.
   - Silme ve dışa/içe aktarmayı da deneyin.

---

## Ek: LifeOS Editör `[~]`

Aynı derlemeden ikinci bir program: `lifeos_editor` (Windows'ta `.exe`). Runner `FOLIO_EDITOR` ile derlenir, Dart'a `--editor` verir; `lib/editor_app.dart` yalnızca editörü, boş bir UDF ile açar. Kendi başlığı, kalemli simgesi ve görev çubuğu kimliği (`com.erkanoz.lifeos.editor`, Linux'ta `com.erkanoz.lifeos_editor`) vardır. Yeni (Ctrl+N) ve Aç (Ctrl+O) başlık çubuğunda, yazısız ikon düğmeler olarak (üzerine gelince ne yaptıkları ve kısayolları yazar). Folio'nun içinde editör eskisi gibi uygulama içinde kalır.

- Windows: derlendi, açıldı, Yeni/Aç denendi. Kurulum betiği (Başlat menüsü, masaüstü, Birlikte aç) Inno Setup bu makinede olmadığı için GitHub'daki Windows paket işinde doğrulanacak.
- Linux: runner ve `.desktop` yazıldı; "Testler" iş akışındaki Linux derlemesi geçti ve `lifeos_editor` pakette (45b340d). Kullanıcının Linux makinesinde denenecek.

---

## 1. Dayanaklar durum çubuğunda `[x]` — 1 tur

Araç çubuğunda "Dayanaklar" düğmesini bulmak zor. Belgede atıf varsa bu, editörün altındaki durum çubuğunda görünmeli.

- Araç çubuğundaki Dayanaklar düğmesi (geniş ve dar görünüm) kaldırılır.
- Editörün altındaki durum çubuğunun (yakınlaştırma düğmelerinin olduğu çubuk) sol ucunda, atıf varsa "⚖ 7 dayanak" gibi bir düğme görünür. İpucu metni ayrıntıyı verir: "5 kanun maddesi, 2 karar".
- Atıf yoksa düğme hiç görünmez.
- Tıklayınca dayanaklar paneli editörün altında açılır; yeniden tıklayınca ya da panelin kapatma düğmesiyle kapanır. Panel açıkken düğme seçili görünür.
- Sayı yazarken güncellenir (atıf taraması yazma durduktan yarım saniye sonra zaten çalışıyor).

Kabul: Atıfsız belgede çubukta dayanak düğmesi yok; atıf eklenince yarım saniye içinde belirir; tıklayınca panel açılır/kapanır.

---

## 2. Avukat profili ve kalıp boşluklarının kendiliğinden dolması `[x]` — 1 tur

Dilekçelerde tekrar tekrar yazılan büro ve avukat bilgileri bir kez girilir.

**Profil ekranı** (Ayarlar → Avukat profili):
- Büro: adres, telefon, e-posta, KEP adresi.
- Avukatlar (birden çok olabilir, biri varsayılan): ad soyad, baro, baro sicil no, TBB sicil no, TC kimlik no.
- Bilgiler yalnızca bu bilgisayarda, uygulamanın veri klasöründe (`profil.json`) tutulur; hiçbir yere gönderilmez.

**Kalıp boşlukları:** Kalıp eklenirken aşağıdaki boşluklar profilden kendiliğinden dolar. Bilinmeyen boşluklar için doldurma penceresi eskisi gibi açılır; profilden dolanlar orada hazır gelir ve değiştirilebilir.

| Boşluk | Dolacak değer |
|---|---|
| `[AVUKAT]` | Av. Varsayılan Avukat |
| `[VEKİLLER]` | Av. A - Av. B (bütün avukatlar) |
| `[BARO]` | Antalya Barosu |
| `[BARO SİCİL NO]`, `[TBB SİCİL NO]` | varsayılan avukatınki |
| `[AVUKAT TC]` | varsayılan avukatın TC'si (`[TC]` müvekkil içindir, karışmasın diye ayrı) |
| `[BÜRO ADRESİ]`, `[BÜRO TELEFONU]`, `[EPOSTA]`, `[KEP]` | büro bilgileri |
| `[BUGÜN]` | bugünün tarihi, 26.09.2026 biçiminde |

Kabul: Profil doluyken `[VEKİLLER]` ve `[BUGÜN]` içeren bir kalıp, pencere açılmadan doğru değerlerle eklenir; profil boşken pencere eskisi gibi sorar.

**Kullanıcı denemesinden sonra eklendi (26.09.2026):** Profil yalnızca kalıplarda işe yarıyordu; belgeye `[AVUKAT]` yazınca hiçbir şey olmuyordu. Şimdi:
- **Yazınca dolma:** Belgeye bir profil boşluğu yazılıp köşeli parantez kapanınca değer gelir; Ctrl+Z boşluğu geri getirir. Profilde olmayan bilgi için "Avukat profilinde … yok" denir. Yapıştırılan ya da açılan belgedeki boşluklara dokunulmaz.
- **Parantezsiz ekleme:** Ctrl+Space paletinin üstünde "Profilden" düğmeleri (Av. ad, baro, sicil, adres, telefon, e-posta, bugünün tarihi). Aramada eşleşen profil bilgileri kalıpların üstünde çıkar, Enter ile eklenir. Profil boşsa palet "Avukat profilini doldurun" der.
- En rahat yol, yazarken öneri (4. madde) ile gelecek: "Av" yazınca "Av. ADINIZ" önerilecek.

---

## 3. Kalıplar: anahtar kelime + Tab, Alt+F kısayolları, yönetim ekranı `[x]` — 1 tur

- Her kalıba isteğe bağlı bir **anahtar kelime** (örn. `dil1`, `vek`) ve bir **kısayol** (Alt+F1–F12) verilebilir. İkisi de kalıplar arasında tekildir; çakışma kaydederken söylenir.
- **Anahtar kelime + Tab:** İmlecin hemen önündeki kelime bir kalıbın anahtar kelimesiyse Tab o kelimeyi kalıbın **gövdesiyle** (biçimiyle birlikte) değiştirir, ardından boşluk doldurma akışı çalışır. Eşleşme yoksa Tab eskisi gibi sekme koyar.
- **Alt+F1–F12:** Atanan kalıbı imlecin olduğu yere ekler: gövde, üst/alt bilgi ya da tablo hücresi. Alt+F4 yok: Windows onunla pencereyi kapatıyor.
- **Kalıplarım ekranı** (kalıp paletinden ve Ayarlar'dan açılır):
  - Arama; her satırda ad, anahtar kelime, kısayol, kullanım sayısı.
  - Ad, anahtar kelime ve kısayolu düzenleme.
  - Gövdeyi biçimiyle düzenleme (küçük bir editörde).
  - Silme (onayla).
  - Dışa/içe aktarma (JSON), bilgisayar değiştirirken kalıplar kaybolmasın diye.
- Her ekleme tek adımda geri alınır.

Kabul: `dil1` + Tab kalıbın gövdesini biçimiyle ekler; Alt+F3 atanmış kalıbı ekler; silinen kalıp paletten de kalkar.

---

## 4. Yazarken öneri ve akıllı öğrenme `[x]`

Yapılan (29 Eylül 2026): `lib/services/editor/suggestions/` (ifade bölme, kişisel veri süzgeci, motor, `oneriler.sqlite`), `lib/ui/widgets/suggestion_list.dart`, Ayarlar'da üç anahtar ve "Öğrenilen ifadeler" ekranı. Gerçek arşivde (≈2.500 metinli belge) ölçüldü: 5.000 ifade ~15 sn'de, arka planda; adres, telefon, e-posta, kimlik, sicil ve dosya numarası içerenler süzülüyor. Bilinen sınır: yalnız büyük harfle yazılmış ad soyad ("AHMET YILMAZ") her zaman ayırt edilemez; "Bir daha önerme" ile engellenir.

Plan:

### Öneri
- Yazma durduktan ~200 ms sonra, imleç bir kelimenin sonundayken ve en az 2 harf yazılmışken çalışır.
- **Çok kelimeli eşleşme:** Yalnızca son kelimeye değil, cümlenin başından (son `.` `:` `;` `(` ya da satır başından) imlece kadar yazılan son 1–6 kelimeye bakılır; en uzun eşleşme önce gelir. "gereğini say" yazınca "gereğini saygılarımla arz ederim" önerilir.
- **Türkçe harf eşleşmesi:** Karşılaştırma katlanmış metinle yapılır: İ/I/ı/i, Ş/ş, Ğ/ğ, Ü/ü, Ö/ö, Ç/ç ve â/î/û kendi eşleriyle eşleşir. "icra" yazınca "İcra ve İflas Kanunu" bulunur.
- **Kaynaklar ve sıra:**
  1. Kalıpların anahtar kelimeleri ("Kalıp: Vekâletname girişi").
  2. Avukat profili (ad, baro, sicil, adres…).
  3. Yerleşik hukuk ifadeleri: hitaplar, bölüm başlıkları, kapanışlar, kanun ve mahkeme adları (yaklaşık 100 ifade).
  4. Öğrenilmiş ifadeler: kaç ayrı belgede geçtiği ve kaç kez kabul edildiğiyle sıralanır.
- **Görünüm:** İmlecin altında en fazla 6 öneri; yazılan kısım soluk, tamamlanacak kısım belirgin; her satırda kaynak simgesi ve öğrenilmişlerde "12 belgede".
- **Tuşlar:**
  - **Enter** ya da **Tab** öneriyi kabul eder; tıklamak da kabul eder.
  - ↑/↓ yalnızca liste açıkken önerilerde gezinir.
  - **Esc** listeyi kapatır; bir sonraki kelimeye kadar yeniden açılmaz.
  - Liste kapalıyken (ya da Esc ile kapatıldıktan sonra) Enter yeni satır açar. İlk turda Enter hiç kabul etmiyordu; kullanıcı Windows'ta denerken Enter'ın öneriyi getirmesini bekledi (2026-09-30).
- **Kabul:** Yazılan kısım tam ifadeyle değiştirilir; o anki yazı biçimi (kalın vb.) korunur; tek adımda geri alınır.

### Öğrenme
- **Kaydedilen belgelerden:** Kayıtta belge cümle/yan cümle düzeyinde ifadelere ayrılır (10–120 karakter, en az 2 kelime). Aynı belge kaç kez kaydedilirse kaydedilsin **bir belge bir kez sayılır**; belge değiştiyse onun katkısı güncellenir.
- **Arşiv indeksinden:** Folio'nun tuttuğu indeksteki belgelerde **en az 3 ayrı belgede** geçen ifadeler öğrenilir. Arka planda, indeks işçisinde çalışır; ilk kez açılışta ve yönetim ekranındaki "Arşivden yeniden öğren" ile. En çok 5.000 ifade tutulur.
- Bir ifade **en az 2 ayrı belgede** görülünce ya da bir kez kabul edilince öneri olur.
- Kişisel veri öğrenilmez: TC kimlik no, IBAN, telefon, e-posta içeren ifadeler atlanır.
- Uzun süre görülmeyen/kullanılmayan ifadeler sıralamada geriler.
- Depolama: uygulamanın veri klasöründe ayrı bir SQLite veritabanı (`oneriler.sqlite`); yalnızca bu bilgisayarda.

### Ayarlar ve yönetim
- Ayarlar → Editör: "Yazarken öneri" aç/kapa, "Kaydettiğim belgelerden öğren" aç/kapa, "Arşivden öğren" aç/kapa.
- **Öğrenilenler ekranı:** arama; ifade, kaynak, belge sayısı, kabul sayısı; silme; "bir daha önerme" (engel listesi); "hepsini sil"; "Arşivden yeniden öğren".

Kabul: "icra" → "İcra ve İflas Kanunu"; öneri açıkken Enter öneriyi alır, Esc'ten sonra yeni satır açar; aynı belgeyi 5 kez kaydetmek sayacı 1 artırır; kapatınca hiç öneri çıkmaz; engellenen ifade bir daha çıkmaz.

---

## 5. Emsal kararı dilekçeye atıf olarak ekleme `[ ]` — 1 tur

Yapay zekâ gerekmez; kararın bilgileri resmî bankadan zaten geliyor.

- **Nereden:** Karar önizleme kartı (atıftan açılan) ve İçtihat ara sonuçları: "Dilekçeye ekle" düğmesi.
- **Biçim:**
  - Karardan metin seçiliyse alıntıyla: **Yargıtay 9. Hukuk Dairesi'nin 12.03.2024 tarihli, 2023/1234 E. ve 2024/567 K. sayılı kararında;** "…seçilen bölüm…" şeklinde hüküm kurulmuştur.
  - Seçim yoksa künyeyle: Yargıtay 9. Hukuk Dairesi'nin 12.03.2024 tarihli, 2023/1234 E. ve 2024/567 K. sayılı kararı da bu yöndedir.
  - İlgi eki kuralla yazılır: Dairesi'nin, Kurulu'nun, Mahkemesi'nin, Danıştay 10. Dairesi'nin.
- **Yerleştirme:** Varsayılan imlecin olduğu yer. "Sonuç bölümünden önce" seçilirse SONUÇ VE İSTEM / NETİCE VE TALEP / SONUÇ VE TALEP / TALEP SONUCU başlığının hemen önüne yeni paragraf olarak girer.
- Aynı yere art arda eklenen kararlarda ikinciden itibaren "Aynı yönde, " ile bağlanır.
- Künye kalın, alıntı tırnak içinde italik; tek adımda geri alınır.

Kabul: Seçimli ve seçimsiz iki biçim doğru; ilgi eki doğru; SONUÇ başlığı varsa önüne, yoksa imlece eklenir.

---

## 6. Cetvel: sekme durakları ve girintiler `[ ]` — 1 tur

- Yatay cetvel imlecin bulunduğu paragrafın sekme duraklarını ve girintilerini gösterir (dosyadan okunanlar zaten çiziliyor).
- **Sekme durağı:**
  - Cetvele tıklamak durak ekler. Cetvelin solundaki seçici türü değiştirir: sol, orta, sağ, ondalık.
  - Sürüklemek taşır; cetvelden aşağı sürükleyip bırakmak ya da çift tıklamak siler.
  - 0,25 cm'ye yapışır; Alt basılıyken serbest.
- **Girinti işaretleri:** ilk satır girintisi (üst üçgen), asılı/sol girinti (alt üçgen), sağ girinti. Sürüklerken sayfada dikey kılavuz çizgisi görünür.
- Seçili paragraflara (yoksa imlecin paragrafına) uygulanır; tek adımda geri alınır.
- **UDF ve DOCX'e kaydedilir** (lifeOS'ta sekme durakları dosyaya yazılmıyordu).

Kabul: Eklenen/taşınan durak ve girinti kaydedip yeniden açınca yerinde; UYAP'ta açılan UDF'de aynı hizada.

---

## 7. Otomatik biçimlendirme `[ ]` — 1–2 tur

"Biçimlendir" komutu (araç çubuğu ve kısayol) belgeyi ya da seçimi dilekçe kurallarına göre düzenler:

- **Mahkeme başlığı:** Büyük harfle yazılmış, …MAHKEMESİ'NE / …MÜDÜRLÜĞÜ'NE / …BAŞKANLIĞI'NA ile biten ilk satırlar ortalı ve kalın olur.
- **Bölüm başlıkları:** AÇIKLAMALAR, HUKUKİ NEDENLER, DELİLLER, SONUÇ VE İSTEM gibi kısa büyük harfli satırlar kalın olur.
- **Etiketli satırlar:** DAVACI :, DAVALI :, VEKİLİ :, KONU :, DOSYA NO : gibi satırlar tek bir sekme durağına hizalanır.
  - Durak, en uzun etikete göre yazı tipinin gerçek genişliğiyle hesaplanır.
  - Aradaki boşluk dizileri sekmeye çevrilir.
  - Asılı girinti verilir; değer iki satıra taşarsa alt satır değerin hizasından devam eder.
- **Gövde paragrafları:** İki yana yaslanır; ilk satır girintisi ayarlanabilir, varsayılan 1,25 cm.
- **Numaralı maddeler** ("1-", "2)"): tutarlı asılı girinti.
- **İmza bloğu** (sondaki "Davacı Vekili", "Av. …"): sağa yaslanır.
- Tek adımda geri alınır; sonunda "Biçimlendirildi — Ctrl+Z ile geri alabilirsiniz" bildirimi çıkar.
- Kurallar sonra ayarlanabilir hâle getirilebilir.

Kabul: Örnek dilekçelerde başlık ortalı, gövde iki yana yaslı, taraf etiketleri tek hizada; Ctrl+Z her şeyi tek seferde geri alır.

---

## lifeOS Hukuk'taki hatalar ve burada nasıl önlenecek

| lifeOS Hukuk'ta | Burada |
|---|---|
| Türkçe büyük/küçük harf eşleşmesi bozuk ("icra" → "İcra…" bulunmuyor; SQLite NOCASE yalnız ASCII katlıyor) | Katlanmış Türkçe metinle eşleşme, testle güvence |
| Öneri açıkken Enter yeni satır açmıyor, öneriyi kabul ediyor | Yalnızca Tab kabul eder, Enter hep yeni satır |
| Anahtar kelime + Tab kalıbın gövdesi yerine başlığını yazıyor | Gövde biçimiyle eklenir, testle güvence |
| Aynı belgeyi iki kez kaydetmek "iki belgede görüldü" sayılıyor | Belge başına bir kez sayılır |
| Öneri kapatılamıyor, öğrenilenler yönetilemiyor | Aç/kapa ayarları ve öğrenilenler ekranı |
| Yalnızca tek kelimenin başıyla eşleşiyor | Son 1–6 kelimeyle çok kelimeli eşleşme |
| Kalıplar biçimsiz (düz metin) kaydediliyor, Alt+F ile satır sonları kayboluyor | Kalıplar biçimiyle (Delta) saklanıyor ve öyle ekleniyor |
| Yazım denetimi yalnızca ilk 150 kelimeye bakıyor | (Folio zaten bütün belgeyi denetliyor) |
| Cetvelde eklenen sekme durakları dosyaya yazılmıyor | UDF ve DOCX'e yazılır |
| Kişisel veriler de öğrenilebiliyor | TC, IBAN, telefon, e-posta içeren ifadeler öğrenilmez |

---

## Test yaklaşımı

- **Birim testleri:** Türkçe katlama ve çok kelimeli eşleşme; ifade çıkarma ve kişisel veri eleme; belge başına sayım; ilgi eki; SONUÇ başlığı bulma; otomatik biçim kuralları; profil boşlukları.
- **Widget testleri:**
  - Öneri listesi: Tab kabul eder, Enter yeni satır açar, Esc kapatır.
  - Anahtar kelime + Tab ve Alt+F kısayolu.
  - Durum çubuğundaki dayanak düğmesi.
  - Cetvelde durak ekleme ve taşıma.
- **Gidiş-dönüş testleri:** Sekme durakları ve girintiler UDF ve DOCX'e yazılıp geri okunduğunda aynı.

---

## Sonraki adaylar (karşılaştırmadan)

- Yazım denetimi için hukuk terimleri beyaz listesi (HMK, müvekkil…) ve "sonraki hata" düğmesi.
- Markdown kısayolları (`# ` başlık, `- ` liste) ve Markdown biçimli metni yapıştırma.
- Tabloda hücre birleştirme/bölme ve başlık satırı (daha önce ertelenmişti).
- Üst/alt bilgide sayfa numarası (`{sayfa}/{toplam}`), gerçek sayfalama.
- Yapay zekâ özellikleri (asistan paneli, Güçlendir/Özetle/Düzelt, seçili metinde yapay zekâ, belgeden anlamsal emsal arama). Sunucu bağlantısı, maliyet ve KVKK ayrıca konuşulacak.
- UYAP'a doğrudan evrak gönderme; UDF dışı dosyalar için ayrık `.p7s` imza.
- PTT tebligat takibi (PTT'nin resmî web servisi için kullanıcı adı/şifre alınırsa).

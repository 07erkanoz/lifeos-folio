/// What each page's "?" tells, in plain words: what the page is for, then
/// how to do its work step by step, then a tip. The buttons are named as
/// they are on the screen, so that what is read is found.
library;

/// A page's help.
class HelpTopic {
  const HelpTopic(this.title, this.intro, this.parts, [this.tip]);

  final String title;

  /// What the page is for, in a sentence or two.
  final String intro;

  final List<HelpPart> parts;
  final String? tip;
}

/// A heading, and its steps (numbered) or lines (bulleted).
class HelpPart {
  const HelpPart(this.heading, this.lines, {this.numbered = true});

  final String heading;
  final List<String> lines;
  final bool numbered;
}

abstract final class Help {
  static const _liveShare = HelpPart('Canlı paylaşım', [
    'Hukuk sekmesinde Canlı paylaş’a ya da Dosya › Canlı paylaş’a basın. '
        'Açık belgeniz başkalarının ekranında canlı görünür; belge sizde '
        'kalır, paylaşım bitince karşı tarafta hiçbir şey kalmaz.',
    'Açılan listede aynı ağdaki cihazlar görünür: kendi cihazlarınız, '
        'büronuzdaki kişiler ve yakındaki Folio’lar (büronuzda olmayan, '
        'örneğin karşı tarafın vekili). Kişinin yanındaki Davet et’e '
        'basın.',
    'Her kişi için seçin: Yalnız görebilir (okur, kopyalayamaz) ya da '
        'Sırayla düzenleyebilir.',
    'Yakındaki bir Folio’yu davet edince satırında altı haneli bir kod '
        'görünür; karşı tarafın davet penceresinde de aynı kod çıkar.',
    'Başka bir büroyla, aynı ağda olmadan paylaşmak için Uzaktan’a basın; '
        'ya da ana sayfada Canlı belge’den bir belge seçin, kod hemen çıkar. '
        'Çıkan kodu WhatsApp ya da e-postayla gönderin. Kişi kodu yazınca '
        'size sorulur; iki ekranda da aynı dört rakam görünür. Yalnız '
        'görsün ya da Sırayla düzenlesin’e basın. Her kod bir kişi içindir '
        've 15 dakika geçerlidir.',
    'Sırayla düzenleyebilen birine Kalemi ver dediğinizde onun '
        'yazdıkları sizin belgenize anında işlenir; o sırada siz yalnız '
        'okursunuz.',
    'Kalemi geri al ile istediğiniz an geri alırsınız. Kalem iki dakika '
        'kullanılmazsa kendiliğinden size döner.',
    'Bitirmek için Paylaşımı bitir’e basın.',
  ]);

  static const _liveJoin = HelpPart('Canlı paylaşıma katılmak', [
    'Biri sizi davet edince Folio’da bir pencere açılır. Katıl’a basın; '
        'belge kendiliğinden açılır. İstemiyorsanız Reddet’e basın.',
    'Başka bir büronun sizi davet edebilmesi için Ayarlar › Editör’de '
        'Canlı paylaşıma davet edilebilirim açık olmalı.',
    'Size bir davet bağlantısı geldiyse ona dokunun; Folio açılır ve kod '
        'hazır gelir. Ya da ana sayfada Canlı belge’ye basıp kodu yazın. '
        'Paylaşan onaylayınca belge açılır.',
    'Düzenleme izniniz varsa Düzenlemek iste’ye basın; paylaşan kalemi '
        'verince yazdıklarınız onun belgesine işlenir.',
    'İş bitince Kalemi bırak’a, ayrılmak için İzlemeyi bırak’a basın.',
  ]);

  static const live = HelpTopic(
    'Canlı paylaşım',
    'Açık belgenizi başkalarının ekranında canlı gösterirsiniz; isterseniz '
        'sırayla birlikte yazarsınız. Örneğin bir sözleşmeyi karşı tarafın '
        'vekiliyle aynı anda düzenlersiniz. Belge sizde kalır; paylaşım '
        'bitince karşı tarafta hiçbir şey kalmaz.',
    [_liveShare, _liveJoin],
    'Aynı ağda belge cihazdan cihaza, şifreli gider; hiçbir sunucuya '
        'uğramaz. Uzaktan paylaşımda belge şifreli olarak '
        'canli.lifeos.com.tr üzerinden geçer; şifreyi yalnız iki Folio bilir, '
        'sunucu içeriği göremez ve hiçbir şey saklamaz.',
  );
  static const home = HelpTopic(
    'Ana sayfa',
    'Günün işleri bir bakışta burada: UYAP ve UETS bağlantılarınız, bugünün '
        'duruşmaları, yaklaşan süreler, yeni bildirimler ve tebligatlar, '
        'yarım bıraktığınız belgeler.',
    [
      HelpPart('UYAP’a bağlanmak', [
        'UYAP Web kartında Bağlan’a basın ve e-imzanız ya da mobil '
            'imzanızla girin.',
        'İsterseniz UYAP Mobil kartından e-Devlet ile de bağlanın. Biri '
            'yeter; ikisi de bağlıysa Folio her işi en uygun olanla yapar.',
        'İlk bağlantıda kurulum ekranı açılır. UYAP Mobil ile başlamanız '
            'önerilir: dosya listeniz, müvekkilleriniz ve evrak listeleri '
            'gelir. Ardından UYAP Web ile tamamla, para, icra hesabı ve '
            'Yargıtay dosyalarını getirir.',
      ]),
      HelpPart('Güncel tutmak', [
        'Senkronize et, UYAP’taki son durumu hemen getirir.',
        'Folio’nun UYAP’ı kendiliğinden okumasını isterseniz Ayarlar › '
            'Bağlantılar’dan açın.',
      ]),
    ],
    'Kaldığınız yerden devam edin kartı, son çalıştığınız belgeyi tek '
        'tıkla açar.',
  );

  static const portfolio = HelpTopic(
    'Dava Dosyalarım',
    'UYAP’taki bütün dosyalarınız burada: mahkeme dosyaları, icra '
        'dosyaları, Cumhuriyet savcılığı ve Yargıtay dosyaları. Dosyalar '
        'bağlı olan UYAP bağlantısından gelir.',
    [
      HelpPart('Dosyaları getirmek', [
        'UYAP Web’e ya da UYAP Mobil’e bağlanın; kurulum ekranından '
            'başlatınca portföyünüz birim birim gelir. Ekran sonradan '
            'sağ üstteki ⋯ menüsünden de açılır.',
        'Yeni açılan bir davada Vekil Kaydı bildirimi gelince Folio sizi '
            'uyarır; Portföyü yenile ile dosya eklenir. UYAP’ın kendiliğinden '
            'okunması açıksa dosya kendiliğinden eklenir.',
        'Senkronize et ile listeyi elle yenileyebilirsiniz. UYAP’ı yormamak '
            'için üç saatte bir defadan sık yenilenmez.',
      ]),
      HelpPart('Bir dosyayı açmak', [
        'Listeden dosyaya dokunun. Evraklar, taraflar, duruşmalar, süreler '
            've para bilgileri dosyanın sayfasında görünür.',
        'Kapalı dosyaları da görmek için sağ üstteki ⋯ menüsünden Kapalı '
            'dosyaları getir’i seçin; liste bir kez okunur.',
      ]),
    ],
    'Arama kutusuna dosya numarası, taraf adı ya da mahkeme yazarak '
        'dosyayı hemen bulursunuz.',
  );

  static const caseDetail = HelpTopic(
    'Dosyanın sayfası',
    'Bir dosyanın UYAP’ta olan her şeyi: evrakları, tarafları, duruşmaları, '
        'süreleri ve tebligatları, icra dosyasında para girişleri ve '
        'hesabı.',
    [
      HelpPart('Güncel bilgiyi almak', [
        'Sayfa açılınca bir günden eski bilgiler kendiliğinden tazelenir.',
        'UYAP’tan tazele ile hemen yeniletebilirsiniz. Para girişleri, '
            'tahsilat ve icra hesabı UYAP Web’den gelir; bu yüzden UYAP '
            'Web bağlıyken tazelemek en eksiksiz bilgiyi verir.',
        'Üstteki renkli kutulara dokununca ilgili sekme açılır: duruşma, '
            'süre, evraklar ya da harç.',
        'Harç & Tahsilat sekmesinde dosyaya yatırılan harçlar, gider '
            'avansı ve reddiyatlar makbuzlarıyla görünür. İcra dosyasında '
            'bunlar İcra sekmesindedir.',
      ]),
      HelpPart('Evrakla çalışmak', [
        'Bir evraka dokununca açılır ve bilgisayarınıza kaydedilir.',
        'Dilekçe yaz, bu dosya için yeni bir dilekçe açar; dosyanın '
            'bilgileri dilekçeye hazır gelir.',
        'Evrakı seçip Paylaş ile büronuzdaki birine gönderebilir, Görevler '
            'sekmesinden bu dosya için görev verebilirsiniz.',
      ]),
      HelpPart('Yapay zekâ sekmesi', [
        'Yapay zekâ özellikleri açıksa görünür. Sohbetler’de bu dosyayla '
            'yapılan bütün sohbetler listelenir; birine dokununca Yapay '
            'zekâ sayfasında açılır.',
        'Bu dosyayla yeni sohbet, Yapay zekâ sayfasını bu dosyaya bağlı '
            'olarak açar.',
        'Bulgular’da yapay zekânın önerip sizin kaydettiğiniz tespitler '
            'türlerine göre durur. Yanlış olanı Yanlış işaretle ile '
            'gerekçesini yazarak işaretlersiniz; silinmez, üstü çizili kalır.',
        'Taslaklar’da yapay zekânın yazıp kaydettiğiniz dilekçe ve raporlar '
            'durur; dokununca editörde açılır.',
      ], numbered: false),
    ],
  );

  static const ai = HelpTopic(
    'Yapay zekâ',
    'Kendi API anahtarınızla Gemini, ChatGPT ya da Claude’la soru '
        'sorarsınız; bilgisayarda Groq da seçilebilir. Linux’ta ayrıca '
        'bilgisayarınızda kurulu Claude, Codex ya da Antigravity ile kendi '
        'aboneliğinizle çalışırsınız. Folio araya sunucu koymaz; kanun '
        'maddesini, yönetmeliği ve kararı resmî kaynaklardan okutur, '
        'yanıttaki atıfları denetler.',
    [
      HelpPart('Soru sormak', [
        'Yeni sohbet’e basın ve sorunuzu yazın.',
        'Soru bir dosyayla ilgiliyse dosyayı esas numarasıyla, mahkemesiyle '
            'ya da bir tarafın adıyla anın. Yapay zekâ dosyayı bulur ve '
            'sohbetin üstünde dosyanın adı görünür. Yanlış dosyayı seçtiyse '
            'Kaldır’a basın.',
        'Birden fazla dosya uyuyorsa yapay zekâ hangisi olduğunu size sorar.',
        'Sohbet seçilen dosyaya kaydedilir ve dosyanın Yapay zekâ '
            'sekmesinde de görünür. Bir dahaki sohbette yapay zekâ dosyada '
            'daha önce yapılanları hatırlar.',
      ]),
      HelpPart('Belge eklemek', [
        'Soru kutusunun yanındaki artı düğmesiyle belge ekleyin: UDF, Word, '
            'PDF, TIFF ya da resim.',
        'Metni olan belgeler metniyle gider. Taranmış belge ve resim, Gemini, '
            'ChatGPT ve Claude’a sayfa görüntüsü olarak gider; tablo, kaşe ve '
            'silik yazıyı yapay zekâ kendisi okur.',
        'Groq ve Antigravity görüntü almaz; onlara taramanın Folio’nun '
            'okuduğu metni gider. Yan taranmış sayfaları Folio döndürüp okur.',
        'Göndermeden önce geçerli TC kimlik numaraları gizlenir. Sayfa '
            'görüntüsündeki numaralar gizlenemez.',
      ]),
      HelpPart('Bulgular, taslaklar ve evrak', [
        'Yapay zekâ bir tespiti dosyaya kaydetmeyi önerirse yanıtın altında '
            'bir kart çıkar. Kaydet’e basarsanız dosyanın bulgularına girer.',
        'Bir taslak yazarsa Dosyaya kaydet ve aç ile dosyanın klasörüne '
            'UDF olarak kaydedilir ve editörde açılır.',
        'İnmemiş bir evrakı okuması gerekirse Folio UYAP’a bağlıysa '
            'evrakı kendiliğinden indirir. İnmiş evrak yeniden '
            'indirilmez.',
        'Yönetmelik ve tebliğlerin ayrı ek dosyaları da okunur; örneğin '
            'Avukatlık Asgari Ücret Tarifesi’nin tutar tabloları.',
      ]),
      HelpPart('Programı seçmek', [
        'Sohbetin üstündeki listeden programı seçin. Seçiminiz kaydedilir; '
            'tebligattan süre çıkarmak gibi diğer işler de aynı programla '
            'yapılır.',
        'Programı ve her düzeyin modelini Ayarlar › Yapay zekâ’dan da '
            'değiştirebilirsiniz.',
      ]),
      HelpPart('Telefondan sormak', [
        'Telefonda Yapay zekâ sayfasında ya da bir dosyanın Yapay zekâ '
            'sekmesinde sorunuzu yazın.',
        'Telefona Ayarlar › Yapay zekâ’dan Gemini, ChatGPT ya da Claude '
            'API anahtarı girdiyseniz soru telefondan doğrudan o hizmete '
            'gider. Anahtar her cihazda ayrı girilir; cihazlar arasında '
            'eşitlenmez.',
        'Anahtar girmediyseniz soru Senkron ile bilgisayarınıza gider; '
            'bilgisayarınızdaki Folio cevaplar. Bilgisayar kapalıysa '
            'açılınca cevaplanır. Bu yolda gereken evrak bilgisayarınızdaki '
            'UYAP bağlantısıyla indirilir.',
      ]),
    ],
    'Yanıtlar yanlış ya da eksik olabilir. Yanıtın altındaki Dayanakları '
        'bölümünde yanıtın dayandığı kanun maddeleri ve kararlar görünür; '
        'birine tıklarsanız tam metni resmî kaynaktan açılır. Folio her '
        'birinin resmî kaynakta olup olmadığını işaretler; kararı siz '
        'verirsiniz.',
  );

  static const uyapNotices = HelpTopic(
    'UYAP bildirimleri',
    'UYAP’ın size gönderdiği bildirimler: yeni evrak, duruşma, vekil '
        'kaydı ve diğerleri. Her bildirim ilgili dosyaya bağlanır.',
    [
      HelpPart('Kullanmak', [
        'Bildirime dokunun; ilgili dosyanın sayfası açılır.',
        'Okundu yap ya da Okunmadı yap ile listeyi düzenleyin.',
        'Yenile, UYAP’taki son bildirimleri hemen getirir.',
      ]),
    ],
    'Bir bildirimin dosyası henüz portföyünüzde yoksa portföy '
        'yenilendiğinde bağlanır.',
  );

  static const uets = HelpTopic(
    'Tebligatlarım',
    'e-Tebligat (UETS) ile gelen tebligatlarınız. Folio her tebligatın '
        'süresini kanuna göre hesaplar.',
    [
      HelpPart('Kullanmak', [
        'UETS’ye bağlan’a basın ve kendi girişinizle girin.',
        'Tebligata dokunun; içindeki belgeleri okursunuz ve Folio süreyi '
            'kanuna göre hesaplayıp gösterir.',
        'Süreyi onaylarsanız ajandaya yazılır ve yaklaşınca hatırlatılır.',
      ]),
      HelpPart('Kimi temsil ettiğiniz', [
        'Sürenin size mi karşı tarafa mı ait olduğunu Folio, dosyada kimin '
            'vekili olduğunuza göre belirler.',
        'Bunu UYAP’taki taraf listesinden ya da tebligattaki belgenin '
            'başlığından (“DAVALILAR … VEKİLİ: Av. …”) kendisi okur. '
            'Okuyamazsa bir kez sorar; cevabınız o dosyanın bütün '
            'tebligatlarında geçerlidir. Değiştir ile düzeltebilirsiniz.',
      ]),
      HelpPart('Yapay zekâyla çıkar', [
        'Yapay zekâ özellikleri açıksa tebligatın altındaki Yapay zekâyla '
            'çıkar düğmesi, belgedeki süreleri ve yapılacak işleri '
            'dayanak maddesiyle ve belgedeki cümlesiyle önerir.',
        'Son günü yapay zekâ değil, Folio’nun süre motoru hesaplar. '
            'Önerilen hiçbir şey siz onaylamadan ajandaya girmez.',
      ]),
    ],
    'Folio süreyi önerir; son kararı siz verirsiniz. Kesin olduğu yazılan '
        'bir karar için kanun yolu süresi önerilmez; bölge adliye '
        'mahkemesinin kararı için istinaf süresi gösterilmez.',
  );

  static const agenda = HelpTopic(
    'Ajanda',
    'Duruşmalarınız, süreleriniz ve görevleriniz tek takvimde.',
    [
      HelpPart('Kullanmak', [
        'Duruşmalar UYAP’tan, süreler tebligatlardan ve görevler büro '
            'ağından kendiliğinden gelir.',
        'Yeni ile kendiniz de duruşma, süre ya da hatırlatma ekleyebilirsiniz.',
        'Bir kayda dokununca ayrıntısı ve dosyası açılır.',
        'Yapay zekâ özellikleri açıksa bir kayda uzun basıp Süre ve iş '
            'çıkar’ı seçin: kaydın metnindeki süreler ve yapılacak işler '
            'önerilir, onayladıklarınız ajandaya eklenir.',
      ]),
    ],
    'Ajandanız kendi telefonunuz ve bilgisayarınız arasında Senkron ile '
        'aynı kalır.',
  );

  static const clients = HelpTopic(
    'Müvekkiller',
    'Her müvekkilin dosyaları, duruşmaları, görüşme tutanakları, ücret '
        'sözleşmeleri ve hesabı tek kartta.',
    [
      HelpPart('Müvekkil eklemek', [
        'Yeni’ye basın, müvekkilin bilgilerini yazın.',
        'Dava dosyalarındaki taraflardan da müvekkil oluşturabilirsiniz.',
      ]),
      HelpPart('Ücret ve hesap', [
        'Her dosya için ücreti, avansı ve masrafları girin.',
        'Tahsilat girdiğinizde kasaya kendiliğinden düşer.',
        'Ücret sözleşmesi, makbuz ve ibranameyi buradan hazırlarsınız.',
      ]),
    ],
    'Ücret ve hesap bilgilerini büroda yalnız yöneticiler ve yöneticinin '
        'izin verdiği kişiler görür.',
  );

  static const cash = HelpTopic(
    'Kasa',
    'Büronuzun gelir ve giderleri. Müvekkillerden yapılan tahsilatlar buraya '
        'kendiliğinden düşer.',
    [
      HelpPart('Kullanmak', [
        'Gider eklemek için Gider’e basın, tutarı ve açıklamayı yazın.',
        'Aylık ve yıllık raporu seçip görüntüleyin ya da yazdırın.',
      ]),
      HelpPart('TL, Euro ve Dolar', [
        'Tutarın yanındaki TL, € ve \$ düğmesiyle para birimini seçin.',
        'Her para birimi kendi kasasında toplanır; birbirine çevrilmez. '
            'Üstteki kasa kartına basınca sayfa o para birimini gösterir.',
      ]),
      HelpPart('Müvekkil masrafları', [
        'Müvekkil için sizin ödediğiniz masraflar Müvekkil masrafı kutusunda '
            'toplanır; geri alındıkça düşer. Kutuya basınca yalnız bunlar '
            'listelenir.',
      ]),
      HelpPart('Banka (isteğe bağlı)', [
        'İsterseniz Banka bakiyesi ekle ile hesabın adını ve bakiyesini '
            'yazın. Bankaya bağlanılmaz, IBAN istenmez; bakiyeyi karta basıp '
            'istediğiniz zaman güncellersiniz.',
      ]),
    ],
    'Kasayı yalnız yöneticiler ve yöneticinin izin verdiği kişiler görür.',
  );

  static const office = HelpTopic(
    'Büro ağı',
    'Büro ağı, aynı bürodaki avukatların, stajyerlerin ve sekreterlerin '
        'Folio’larını birbirine bağlar. Evrak gönderir, görev verir, '
        'mesajlaşırsınız. Her şey büronuzun kendi ağı (Wi-Fi ya da kablo) '
        'içinde, bir bilgisayardan ötekine şifreli gider. Arada sunucu '
        'yoktur; hiçbir bilgi büronun dışına çıkmaz.',
    [
      HelpPart('Kim neyi görür?', [
        'Herkes yalnız kendisine gönderileni görür. Dava dosyalarınız '
            'kimseye kendiliğinden gitmez.',
        'Müvekkil kartları ve görüşme tutanakları bürodaki avukatlara '
            'gider.',
        'Ücret, avans ve kasa bilgilerini yalnız yöneticiler ve yöneticinin '
            '“Ücret ve hesapları görebilir” izni verdiği kişiler görür.',
      ], numbered: false),
      HelpPart('Büroyu kurmak (yönetici)', [
        'Büro ağı sayfasında Büro kur’a basın ve büronun adını yazın.',
        'Ekranda bir kurtarma kodu çıkar. Kâğıda yazıp saklayın: '
            'bilgisayarınız değişirse büroyu bu kodla geri alırsınız.',
      ]),
      HelpPart('Büroya katılmak', [
        'Büro ile aynı ağa bağlıyken Büro ağı sayfasını açın; büro '
            'kendiliğinden görünür. Bu ağa katıl’a basın.',
        'Sizin ekranınızda ve yöneticinin ekranında aynı kod çıkar. Kodlar '
            'aynıysa yönetici Kodlar aynı, tanı’ya ve ardından Kabul et’e '
            'basar.',
        'Bundan sonra kod bir daha sorulmaz.',
      ]),
      HelpPart('Yetki vermek (yönetici)', [
        'Büro ağı sayfasında üyenin yanındaki Rol’den görevini seçin: '
            'Yönetici, Avukat, Stajyer ya da Sekreter.',
        'Para bilgilerini görmesi gereken birine “Ücret ve hesapları '
            'görebilir” iznini verin.',
        'Bürodan ayrılan birini Bürodan çıkar ile çıkarın; o kişi bundan '
            'sonra büronuzdan hiçbir şey alamaz.',
      ]),
      HelpPart('Roller ne yapabilir?', [
        'Yönetici: herkese görev verir, bütün görevleri görür, üye ekler, '
            'çıkarır ve rol verir.',
        'Avukat: kendine, stajyere ve sekretere görev verir; verdiği ve '
            'aldığı görevleri görür.',
        'Stajyer ve sekreter: kendilerine verilen görevleri yürütür ve '
            'teslim eder.',
      ], numbered: false),
      HelpPart('Dosya göndermek', [
        'Gönder bölümüne dosyayı bırakın ya da seçin: bir UYAP dosyasından '
            'evrak, bir dilekçe ya da bir klasör.',
        'Kime gönderileceğini seçin, isterseniz bir not yazın ve Gönder’e '
            'basın.',
        'Karşı taraf kabul edince dosya onun bilgisayarındaki Folio '
            'Gelenler klasörüne iner.',
        'Bir dava dosyasının evrakını dosyanın sayfasından da '
            'gönderebilirsiniz: seçili evrak, bütün evrak ya da yalnız künye '
            've taraflar.',
      ]),
    ],
    'Karşıdaki bilgisayar kapalıysa gönderdiğiniz şey sırada bekler; '
        'bilgisayar açılınca kendiliğinden gider.',
  );

  static const tasks = HelpTopic(
    'Görevler',
    'Bir işi büronuzdaki birine, dosyası ve evrakıyla birlikte verirsiniz; '
        'işin ne durumda olduğunu buradan izlersiniz.',
    [
      HelpPart('Görev vermek', [
        'Görev ver’e basın. Bir dava dosyasının sayfasından da “Bu dosya '
            'için görev ver” diyebilirsiniz.',
        'Görevi alacak kişiyi ya da kişileri seçin.',
        'Dosyayı seçin ve Ne yapılacak? alanına işi yazın. İş ekle ile bir '
            'dosyaya birden fazla iş, her birini başka birine verebilirsiniz.',
        'Son günü seçin. Son gün bir tarih ya da “duruşmadan 7 gün önce” '
            'gibi duruşmaya göre olabilir; duruşma değişirse size sorulur.',
        'Gidecek evrakı işaretleyin: seçili evrak, bütün evrak ya da yalnız '
            'künye ve taraflar. Bilgisayarınızda olmayan evrak, görev '
            'verilmeden önce UYAP’tan indirilir.',
        'Göreve bir not yazın ve gönderin.',
      ]),
      HelpPart('Görevi yürütmek (görevi alan)', [
        'Gelen görevi açın; dosyanın evrakını, tarafları ve duruşmaları '
            'görev sayfasında incelersiniz. O dosyada UYAP yetkiniz olmasa da '
            'gelen evrak sizde açılır.',
        'İlerleme yaz ile ne yaptığınızı, ne kaldığını bildirin.',
        'İş bitince hazırladığınız evrakı ekleyip Teslim et’e basın.',
      ]),
      HelpPart('Teslimi almak (görevi veren)', [
        'Teslim gelince evrakı inceleyin.',
        'Uygunsa Onayla’ya, düzeltilmesi gerekiyorsa notunuzla birlikte Geri '
            'gönder’e basın.',
      ]),
    ],
    'Son günler ajandada görünür. Folio son günden 7, 3 ve 1 gün önce '
        'hatırlatır; Gördüm’e basana kadar her gün yineler.',
  );

  static const messages = HelpTopic(
    'Mesajlar',
    'Büronuzdaki kişilerle yazışırsınız. Mesajlar da büronun ağı içinde, '
        'şifreli gider.',
    [
      HelpPart('Kullanmak', [
        'Özel mesaj ile bir kişiye, Grup ile seçtiğiniz kişilere yazın.',
        'Dosya, fotoğraf ya da sesli mesaj ekleyebilirsiniz.',
        'Yöneticiler Büroya duyuru ile herkese birden yazabilir.',
      ]),
    ],
    'Folio kilitliyken bildirimde mesajın içeriği görünmez, yalnız “Yeni '
        'mesaj” yazar.',
  );

  static const sync = HelpTopic(
    'Senkron',
    'Senkron, sizin kendi cihazlarınızı, örneğin büro bilgisayarınızı, ev '
        'bilgisayarınızı ve telefonunuzu, birbirine bağlar. Bilgileriniz '
        'hepsinde aynı olur. Yalnız aynı ağdaki kendi cihazlarınız arasında, '
        'şifreli çalışır; başka kimse sizin cihazınızı göremez. Büro kurmanız '
        'gerekmez.',
    [
      HelpPart('Cihaz eklemek', [
        'Bilgisayarda Senkron’u açın ve Senkronu aç’a basın.',
        'Telefonu eklemek için bilgisayardaki QR kodunu telefondaki Folio '
            'ile okutun.',
        'Başka bir bilgisayarı eklemek için Bilgisayarımı ekle’ye basıp '
            'ağda onu seçin; iki ekranda da aynı kodu onaylayın.',
      ]),
      HelpPart('Ne eşitlenir?', [
        'Ajanda ve notlar: görevler, notlar ve süre işaretleri. Birinde '
            'silinen ötekinde de silinir.',
        'UYAP verileri: dava dosyaları, evrak listeleri, duruşmalar ve '
            'bildirimler. Bir cihazınızın UYAP’tan aldığını öbürü de alır; '
            'UYAP’a iki kez sorulmaz. Evrakın kendisi açıldığı cihaza iner.',
        'Müvekkiller: kartlar ve görüşme tutanakları. Ücret ve hesaplar '
            'yalnız yetkisi olan cihazlara gider.',
        'Klasörler: seçtiğiniz klasörler iki yönde eşitlenir. İki cihazda '
            'birden değişen dosyanın iki hâli de kalır; silinen dosya 30 gün '
            'Senkron çöpünde durur.',
        'Oturumlar: UYAP ve UETS girişinizi öbür cihazınıza geçirip orada '
            'yeniden e-imza atmadan devam edersiniz.',
      ], numbered: false),
    ],
    'UYAP Web aynı anda tek işlem kabul eder; iki cihazdan birlikte '
        'kullanılırsa oturum düşebilir. Bir cihazda çalışın, öbüründe '
        'yalnız bakın.',
  );

  static const editor = HelpTopic(
    'Belge editörü',
    'UDF dilekçenizi yazar, imzalar ve dava dosyanıza gönderirsiniz. Word '
        've metin belgeleri de burada açılır ve düzenlenir.',
    [
      HelpPart('Dilekçe yazmak', [
        'Yeni belge ile boş bir dilekçe ya da bir şablon açın.',
        'Yazarken kanun maddelerine yaptığınız atıflar yandaki Dayanaklar '
            'listesinde görünür; her biri resmî kaynağından açılır.',
        'Kaydet ile UDF olarak, Farklı kaydet ile Word ya da PDF olarak '
            'saklayın.',
      ]),
      HelpPart('İmzalamak ve göndermek', [
        'İmzala’ya basın; e-imza kartınızla ya da mobil imzanızla imzalayın.',
        'UYAP’a gönder ile dilekçeyi dava dosyasına gönderin. Göndermeden '
            'önce dosya ve evrak türü size gösterilir.',
      ]),
      _liveShare,
      _liveJoin,
    ],
    'Aynı ağda belge cihazdan cihaza, şifreli gider; hiçbir sunucuya '
        'uğramaz. Uzaktan paylaşımda belge şifreli olarak '
        'canli.lifeos.com.tr üzerinden geçer; şifreyi yalnız iki Folio bilir, '
        'sunucu içeriği göremez ve hiçbir şey saklamaz.',
  );

  static const library = HelpTopic(
    'Belgeler',
    'Bilgisayarınızdaki belgeler: UDF, Word, Excel, PDF ve taramalar. '
        'Folio seçtiğiniz klasörleri tarar; bir belgeyi adıyla ya da içinde '
        'geçen bir kelimeyle bulursunuz.',
    [
      HelpPart('Kullanmak', [
        'Aranacak klasörleri Ayarlar › Arşiv klasörleri’nden ekleyin.',
        'Arama kutusuna belgenin adını ya da içinde geçen bir kelimeyi yazın.',
        'Bir belgeye dokununca önizlemesi açılır; düzenlemek için '
            'Düzenle’ye basın.',
      ]),
    ],
    'Belgeleriniz kendi yerinde kalır; Folio onları taşımaz, kopyalamaz.',
  );

  static const settings = HelpTopic(
    'Ayarlar',
    'Profiliniz, bağlantılarınız, arşiv klasörleriniz, görünüm ve '
        'güvenlik ayarları.',
    [
      HelpPart('Önemli ayarlar', [
        'Profil: adınız, baronuz ve sicil numaranız dilekçelere hazır gelir.',
        'Bağlantılar: UYAP, UETS ve UYAP’ın kendiliğinden okunması.',
        'Arşiv klasörleri: Folio’nun arayacağı klasörler.',
        'Yapay zekâ: özellikleri açıp kapatırsınız, programı ve modelleri '
            'seçersiniz, API anahtarlarınızı girersiniz; kullanım onayınız '
            'burada görünür. Telefonda da aynı bölümden anahtar girilir.',
        'Tüm verileri temizle: Folio’yu ilk kurulduğu hâline döndürür. '
            'Kendi klasörlerinizdeki belgeler silinmez.',
      ], numbered: false),
    ],
    'Aradığınız ayarı üstteki arama kutusuna yazarak bulun.',
  );

  static const inbox = HelpTopic(
    'Gelenler',
    'Büronuzdaki kişilerin size gönderdiği dosyalar.',
    [
      HelpPart('Kullanmak', [
        'Bir dosya geldiğinde kabul ederseniz bilgisayarınızdaki Folio '
            'Gelenler klasörüne iner.',
        'Aç ile dosyayı açın, Klasörde göster ile yerini görün.',
      ]),
    ],
  );
}

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
    'Canlı paylaş, açık belgenizi başkalarının ekranında canlı gösterir. '
        'Belge sizde kalır; paylaşım bitince karşı tarafta hiçbir şey '
        'kalmaz.',
    'Kiminle paylaşacağınızı seçin: Cihazlarım (kendi cihazlarınız), '
        'büronuzdaki kişiler ya da Misafir (büronuzda olmayan, aynı '
        'ağda Folio kullanan biri, örneğin karşı tarafın vekili).',
    'Her kişi için seçin: Yalnız görebilir (okur, kopyalayamaz) ya da '
        'Sırayla düzenleyebilir.',
    'Sırayla düzenleyebilen birine Kalemi ver dediğinizde onun '
        'yazdıkları sizin belgenize anında işlenir; o sırada siz yalnız '
        'okursunuz.',
    'Kalemi geri al ile istediğiniz an geri alırsınız. Kalem iki dakika '
        'kullanılmazsa kendiliğinden size döner.',
    'Misafir için Misafirleri kabul et’i açın. Misafir kendi Folio’sunda '
        'Dosya › Canlı belgeye katıl’ı seçer; iki ekranda çıkan kod '
        'aynıysa onaylarsınız.',
    'Bitirmek için Paylaşımı kapat’a basın.',
  ]);

  static const _liveJoin = HelpPart('Canlı belgeye katılmak', [
    'Paylaşan size belgeyi açınca ekranınızda görünür. Misafirseniz '
        'Dosya › Canlı belgeye katıl ile katılın.',
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
    'Canlı paylaşım yalnız aynı ağdaki cihazlar arasında, şifreli çalışır. '
        'Belge hiçbir sunucuya gitmez.',
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
        'Bağlandıktan sonra dava dosyalarınız, duruşmalarınız ve '
            'bildirimleriniz kendiliğinden gelir.',
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
        'UYAP Web’e ya da UYAP Mobil’e bağlanın; portföyünüz birim birim '
            'gelir.',
        'Yeni açılan bir dava için ayrıca bir şey yapmanız gerekmez: '
            'Vekil Kaydı bildirimi gelince dosya hemen eklenir.',
        'Senkronize et ile listeyi elle yenileyebilirsiniz. UYAP’ı yormamak '
            'için üç saatte bir defadan sık yenilenmez.',
      ]),
      HelpPart('Bir dosyayı açmak', [
        'Listeden dosyaya dokunun. Evraklar, taraflar, duruşmalar, süreler '
            've para bilgileri dosyanın sayfasında görünür.',
        'Kapalı dosyaları da görmek için sağ üstteki ⋯ menüsünden Kapalı '
            'dosyaları da indir’i seçin.',
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
        'Sayfa açılınca bilgiler kendiliğinden tazelenir.',
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
    ],
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
        'Tebligata dokunun; içeriğini okursunuz ve Folio süreyi gösterir.',
        'Süreyi onaylarsanız ajandaya yazılır ve yaklaşınca hatırlatılır.',
      ]),
    ],
    'Folio süreyi önerir; son kararı siz verirsiniz. Ajandaya ancak sizin '
        'onayınızla yazılır.',
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
        'Gider eklemek için Yeni’ye basın, tutarı ve açıklamayı yazın.',
        'Aylık ve yıllık raporu seçip görüntüleyin ya da yazdırın.',
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
    'Canlı paylaşım yalnız aynı ağdaki cihazlar arasında, şifreli çalışır. '
        'Belge hiçbir sunucuya gitmez.',
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

/// Belge türü — süre, dosya adı (UETS belge adları açıklayıcıdır) ve metin
/// anahtar kelimelerinden YEREL olarak (yapay zeka GEREKMEDEN) belirlenir.
///
/// Kritik: süreler kategoriye göre KÖRLEMESİNE değil, belgenin türüne göre
/// verilir. Örn. "Tensip Zaptı" bir karar değildir; istinaf/temyiz süresi
/// İÇERMEZ — onun süresi (tanık/delil listesi vb.) belgeye özeldir.
enum BelgeTuru {
  gerekceliKarar,
  kararIlami,
  istinafKarari,
  temyizKarari,
  odemeEmri,
  // Kambiyo senetlerine mahsus haciz yolu (Örnek 10). AYRI TÜR,
  // çünkü süreleri genel haciz yolundan (Örnek 7) tamamen farklı:
  // itiraz 7 değil BEŞ gün ve tek değil dört ayrı süre var.
  odemeEmriKambiyo,
  icraEmri,
  // Its stage unknown: the first, second or third (İİK m.89).
  hacizIhbarnamesi,
  hacizIhbarnamesiBirinci,
  hacizIhbarnamesiIkinci,
  hacizIhbarnamesiUcuncu,
  davaDilekcesi,
  cevapDilekcesi,
  // The plaintiff's reply to an answer: the defendant's second answer
  // follows it (HMK m.136).
  cevabaCevapDilekcesi,
  // The other side's appeal (istinaf or temyiz), served to be answered.
  kanunYoluDilekcesi,
  // A sale's notice served to the parties (İİK m.127): complained of in
  // seven days (m.16).
  satisIlani,
  // The Court of Cassation's chief prosecutor's opinion served (CMK
  // m.297/3): answered in two weeks.
  tebligname,
  tensipZapti,
  araKarar,
  bilirkisiRaporu,
  durusmaDavetiyesi,
  durusmaTutanagi,
  iddianame,
  muzekkere,
  ihtarname,
  vekaletname,
  tebligatZarfi,
  diger,
}

const belgeTuruEtiket = <BelgeTuru, String>{
  BelgeTuru.gerekceliKarar: 'Gerekçeli Karar',
  BelgeTuru.kararIlami: 'Karar / İlam',
  BelgeTuru.istinafKarari: 'İstinaf Kararı',
  BelgeTuru.temyizKarari: 'Temyiz Kararı',
  BelgeTuru.odemeEmri: 'Ödeme Emri (genel haciz)',
  BelgeTuru.odemeEmriKambiyo: 'Ödeme Emri (kambiyo)',
  BelgeTuru.icraEmri: 'İcra Emri',
  BelgeTuru.hacizIhbarnamesi: 'Haciz İhbarnamesi',
  BelgeTuru.hacizIhbarnamesiBirinci: 'Birinci Haciz İhbarnamesi (89/1)',
  BelgeTuru.hacizIhbarnamesiIkinci: 'İkinci Haciz İhbarnamesi (89/2)',
  BelgeTuru.hacizIhbarnamesiUcuncu: 'Üçüncü Haciz İhbarnamesi (89/3)',
  BelgeTuru.davaDilekcesi: 'Dava Dilekçesi',
  BelgeTuru.cevapDilekcesi: 'Cevap Dilekçesi',
  BelgeTuru.cevabaCevapDilekcesi: 'Cevaba Cevap Dilekçesi',
  BelgeTuru.kanunYoluDilekcesi: 'İstinaf / Temyiz Dilekçesi',
  BelgeTuru.satisIlani: 'Satış İlanı',
  BelgeTuru.tebligname: 'Tebliğname',
  BelgeTuru.tensipZapti: 'Tensip Zaptı',
  BelgeTuru.araKarar: 'Ara Karar',
  BelgeTuru.bilirkisiRaporu: 'Bilirkişi Raporu',
  BelgeTuru.durusmaDavetiyesi: 'Duruşma Davetiyesi',
  BelgeTuru.durusmaTutanagi: 'Duruşma Tutanağı',
  BelgeTuru.iddianame: 'İddianame',
  BelgeTuru.muzekkere: 'Müzekkere',
  BelgeTuru.ihtarname: 'İhtarname',
  BelgeTuru.vekaletname: 'Vekâletname',
  BelgeTuru.tebligatZarfi: 'Tebligat Zarfı / Üstveri',
  BelgeTuru.diger: 'Belirlenemedi',
};

/// Saklanan Türkçe etiketten (uets_tebligat.belge_turu) BelgeTuru'na geri çözüm.
BelgeTuru belgeTuruFromEtiket(String? etiket) {
  if (etiket == null || etiket.trim().isEmpty) return BelgeTuru.diger;
  for (final e in belgeTuruEtiket.entries) {
    if (e.value == etiket) return e.key;
  }
  return BelgeTuru.diger;
}

/// Asistana gönderilecek bir eylem: buton etiketi + talimat + öne çıkan mı +
/// NİYET ('analyze' | 'draft'). Niyet send()'e açıkça verilir; böylece belge
/// metnindeki kelimeler ("istinaf/çıkar") niyeti EZEMEZ ("Analiz et" dilekçeye
/// gitmez). Varsayılan 'draft' (çoğu eylem bir belge/dilekçe üretir).
class BelgeEylem {
  const BelgeEylem(
    this.etiket,
    this.talimat, {
    this.birincil = false,
    this.intent = 'draft',
  });
  final String etiket;
  final String talimat;
  final bool birincil;
  final String intent;
}

const _analizEylem = BelgeEylem(
  'Analiz et',
  'Bu tebligatı hukuki yönden analiz et: belgede TAM OLARAK ne istendiğini, hangi '
      'işlemlerin hangi yasal süre içinde yapılması gerektiğini ve müvekkil lehine '
      'atılacak adımları madde madde açıkla. Ham kanun metni DÖKME; bu belgeye özgü konuş.',
  intent: 'analyze',
);

/// Belge türüne uygun asistan eylemleri. İlk eylem her zaman genel analizdir;
/// sonrasında türe özgü dilekçe/işlem(ler). Böylece tensip zaptında "cevap
/// dilekçesi" yerine tanık/delil listesi gibi DOĞRU butonlar gelir.
List<BelgeEylem> belgeTuruEylemleri(BelgeTuru t) {
  switch (t) {
    case BelgeTuru.tensipZapti:
    case BelgeTuru.araKarar:
      return const [
        _analizEylem,
        BelgeEylem(
          'Tanık listesi hazırla',
          'Bu tensip/ara kararına göre, dilekçede dayanılan tanıkların listesini ve her '
              'tanığın hangi vakıayı ispat edeceğini içeren bir TANIK LİSTESİ dilekçesi hazırla.',
          birincil: true,
        ),
        BelgeEylem(
          'Delil/belge listesi',
          'Bu belgede kesin süre içinde sunulması istenen delil ve belgelerin listesini; '
              'hangi vakıa için olduğunu ve başka yerden getirtilecekse gereken açıklamayı '
              'içerecek biçimde hazırla.',
        ),
        BelgeEylem(
          'Ön incelemeye hazırlık',
          'Bu belgeye göre ön inceleme duruşmasına kadar yapılması gerekenleri (kesin '
              'süreler, tanık bildirimi, delil/belge sunumu, sulh/arabuluculuk) tarih ve '
              'dayanağıyla madde madde çıkar.',
        ),
      ];
    case BelgeTuru.davaDilekcesi:
      return const [
        _analizEylem,
        BelgeEylem(
          'Cevap dilekçesi hazırla',
          'Bu dava dilekçesine karşı; usule ve esasa ilişkin itirazları, delilleri ve '
              'talep sonucunu içeren bir CEVAP DİLEKÇESİ hazırla.',
          birincil: true,
        ),
      ];
    case BelgeTuru.gerekceliKarar:
    case BelgeTuru.kararIlami:
      return const [
        _analizEylem,
        BelgeEylem(
          'İstinaf dilekçesi hazırla',
          'Bu karara karşı istinaf kanun yoluna başvuru dilekçesi hazırla; istinaf '
              'sebeplerini gerekçeli olarak yaz.',
          birincil: true,
        ),
      ];
    case BelgeTuru.istinafKarari:
      return const [
        _analizEylem,
        BelgeEylem(
          'Temyiz dilekçesi hazırla',
          'Bu istinaf kararına karşı temyiz dilekçesi hazırla; temyiz sebeplerini '
              'gerekçeli olarak yaz.',
          birincil: true,
        ),
      ];
    case BelgeTuru.odemeEmri:
    case BelgeTuru.icraEmri:
      return const [
        _analizEylem,
        BelgeEylem(
          'İtiraz dilekçesi hazırla',
          'Bu ödeme/icra emrine karşı (borca/imzaya/yetkiye) itiraz dilekçesi hazırla.',
          birincil: true,
        ),
      ];
    case BelgeTuru.hacizIhbarnamesi:
    case BelgeTuru.hacizIhbarnamesiBirinci:
    case BelgeTuru.hacizIhbarnamesiIkinci:
    case BelgeTuru.hacizIhbarnamesiUcuncu:
      return const [
        _analizEylem,
        BelgeEylem(
          'İtiraz/beyan hazırla',
          'Bu haciz ihbarnamesine karşı süresi içinde itiraz/beyan dilekçesi hazırla.',
          birincil: true,
        ),
      ];
    case BelgeTuru.bilirkisiRaporu:
      return const [
        _analizEylem,
        BelgeEylem(
          'Rapora itiraz hazırla',
          'Bu bilirkişi raporuna karşı itiraz/beyan dilekçesi hazırla; rapordaki hatalı '
              'tespitleri gerekçeleriyle belirt.',
          birincil: true,
        ),
      ];
    case BelgeTuru.ihtarname:
      return const [
        _analizEylem,
        BelgeEylem(
          'İhtara cevap hazırla',
          'Bu ihtarnameye karşı cevabi ihtarname/dilekçe hazırla.',
          birincil: true,
        ),
      ];
    case BelgeTuru.durusmaDavetiyesi:
      return const [
        _analizEylem,
        BelgeEylem(
          'Duruşmaya hazırlık',
          'Bu duruşma davetiyesine göre duruşma hazırlık notu çıkar (gündem, sunulacak '
              'belge/tanık, mazeret seçeneği, dikkat edilecek hususlar).',
          birincil: true,
        ),
      ];
    default:
      return const [
        _analizEylem,
        BelgeEylem(
          'Dilekçe hazırla',
          'Bu tebligata uygun dilekçeyi hazırla; tür belirsizse önce belgede ne '
              'istendiğini özetle, sonra uygun dilekçeyi yaz.',
          birincil: true,
        ),
      ];
  }
}

class BelgeTuruTespit {
  BelgeTuruTespit._();

  /// Tebligattaki belgelerden en SÜRE-BELİRLEYİCİ türü seçer.
  static BelgeTuru tebligatTuru(List<String> dosyaAdlari, {String? metin}) {
    var en = BelgeTuru.diger;
    for (final ad in dosyaAdlari) {
      final t = _tekil(ad, null);
      if (_oncelik(t) > _oncelik(en)) en = t;
    }
    // Dosya adlarindan belirlenemediyse metinden dene — ama TUM METINDE cıplak
    // alt-dize ARAMAYARAK. Bir adli tip raporu 'gerekceli' kelimesini,
    // bir gerekceli karar 'bilirkisi' kelimesini gecerken kullanir; uzun metinde
    // alt-dize eslesmesi kaçınılmaz olarak yanlis tur uretir. Yalniz belgenin
    // BASLIK bolgesine (ilk 600 karakter) ve TAM IFADE kaliplarina bakilir.
    if (_oncelik(en) <= _oncelik(BelgeTuru.tebligatZarfi) &&
        metin != null &&
        metin.trim().isNotEmpty) {
      final t = _baslikBolgesinden(metin);
      if (_oncelik(t) > _oncelik(en)) en = t;
    }
    return en;
  }

  /// Belgenin BASLIK bolgesinden tur — tam ifade capalari, gevsek eslesme yok.
  static BelgeTuru _baslikBolgesinden(String metin) {
    final n = _norm(metin);
    final bas = n.length > 600 ? n.substring(0, 600) : n;
    bool h(String k) => bas.contains(k);
    if (h('adli tip') || h('bilirkisi rapor')) {
      return BelgeTuru.bilirkisiRaporu;
    }
    if (h('gerekceli karar')) return BelgeTuru.gerekceliKarar;
    if (h('odeme emri')) return _odemeEmri(bas);
    if (h('icra emri')) return BelgeTuru.icraEmri;
    if (h('haciz ihbarname')) return _hacizAsamasi(bas);
    if (h('tensip zapti') || h('tensip tutanag')) return BelgeTuru.tensipZapti;
    if (h('durusma davetiye')) return BelgeTuru.durusmaDavetiyesi;
    if (h('ihtarname')) return BelgeTuru.ihtarname;
    // Belirsiz: TUR UYDURMA. Yanlis sure gostermek, sure gostermemekten kotudur.
    return BelgeTuru.diger;
  }

  static BelgeTuru _tekil(String ad, String? metin) {
    final adL = ad.toLowerCase();
    if (adL.endsWith('.xml')) return BelgeTuru.tebligatZarfi;
    // UETS writes its documents' names run together ("CevapDilekcesi"):
    // apart, "cevap dilekce" is found, and the name does not fall through
    // to the bare "dilekce" of a statement of claim.
    final words = ad.replaceAllMapped(
      RegExp(r'([a-zçğıöşü])([A-ZÇĞİÖŞÜ])'),
      (m) => '${m[1]} ${m[2]}',
    );
    final s = _norm('$words ${metin ?? ''}');
    bool h(String k) => s.contains(k);

    if (h('dosyabilgileri') || h('ustveri') || h('ust yazi')) {
      return BelgeTuru.tebligatZarfi;
    }
    if (h('tensip')) return BelgeTuru.tensipZapti;
    if (h('satis ilan')) return BelgeTuru.satisIlani;
    if (h('tebligname')) return BelgeTuru.tebligname;
    if (h('odeme emri') || h('odemeemri')) return _odemeEmri(s);
    if (h('icra emri')) return BelgeTuru.icraEmri;
    if (h('haciz ihbar')) return _hacizAsamasi(s);
    // RAPOR AILESI (HMK m.281 -> 2 hafta itiraz). 'adli tip raporu' kurali YOKTU:
    // gelen Adli Tip Raporu tanınmayip metne dusuyor, metinde gecen 'gerekceli'
    // kelimesi yuzunden GEREKCELI KARAR sayilip istinaf/temyiz suresi
    // uretiliyordu. Yanlis kanun yolu = hak kaybi.
    //
    // A party's expert opinion and a health board's report are not the
    // court's expert report: HMK m.281's two weeks is not theirs, and they
    // are left to the lawyer (Folio).
    if (h('uzman gorus') || h('saglik kurulu rapor')) return BelgeTuru.diger;
    if (h('bilirkisi') || h('adli tip') || h('adlitip') || h('hesap rapor')) {
      return BelgeTuru.bilirkisiRaporu;
    }
    if (h('istinaf') && (h('karar') || h('ilam'))) {
      return BelgeTuru.istinafKarari;
    }
    if (h('temyiz') && (h('karar') || h('ilam'))) {
      return BelgeTuru.temyizKarari;
    }
    if (h('gerekceli karar') || h('gerekceli')) return BelgeTuru.gerekceliKarar;
    // An appeal's own petition: the other side's to answer. Its answer, a
    // second answer and a reply to an appeal are answered by no one.
    if ((h('istinaf') || h('temyiz')) && h('cevap')) return BelgeTuru.diger;
    if ((h('istinaf') || h('temyiz')) &&
        (h('dilekce') || h('basvuru') || h('talep') || h('talebi'))) {
      return BelgeTuru.kanunYoluDilekcesi;
    }
    if (h('ikinci cevap')) return BelgeTuru.diger;
    if (h('cevaba cevap')) return BelgeTuru.cevabaCevapDilekcesi;
    if (h('cevap dilekce')) return BelgeTuru.cevapDilekcesi;
    if (h('dava dilekce')) return BelgeTuru.davaDilekcesi;
    if (h('durusma') && h('davet')) return BelgeTuru.durusmaDavetiyesi;
    if (h('durusma') && (h('tutanak') || h('zapti'))) {
      return BelgeTuru.durusmaTutanagi;
    }
    if (h('muzekkere')) return BelgeTuru.muzekkere;
    if (h('ihtar')) return BelgeTuru.ihtarname;
    if (h('vekalet')) return BelgeTuru.vekaletname;
    if (h('iddianame')) return BelgeTuru.iddianame;
    if (h('ara karar') || h('arakarar')) return BelgeTuru.araKarar;
    if (h('karar') || h('ilam')) return BelgeTuru.kararIlami;
    if (h('dilekce')) return BelgeTuru.davaDilekcesi;
    return BelgeTuru.diger;
  }

  /// A payment order's kind of proceedings from its own words (folded):
  /// the bills' form (Örnek 10, "kambiyo") or the general one (Örnek 7,
  /// "genel haciz"); null when it says neither, and then the lawyer is to
  /// tell, since the deadlines differ (İİK m.62: 7 days; m.168: 5).
  static BelgeTuru? odemeEmriTakipTuru(String text) {
    final s = _norm(text);
    if (s.contains('kambiyo') || _ornek(s, 10)) {
      return BelgeTuru.odemeEmriKambiyo;
    }
    if (s.contains('genel haciz') || _ornek(s, 7)) return BelgeTuru.odemeEmri;
    return null;
  }

  static bool _ornek(String folded, int n) => RegExp(
    r'ornek\s*(no\s*)?[:.]?\s*'
    '$n'
    r'(?!\d)',
  ).hasMatch(folded);

  static BelgeTuru _odemeEmri(String folded) =>
      odemeEmriTakipTuru(folded) ?? BelgeTuru.odemeEmri;

  /// A garnishment notice's stage (İİK m.89) from its words; the bare kind
  /// when it says none.
  static BelgeTuru _hacizAsamasi(String folded) {
    bool any(List<String> ks) => ks.any(folded.contains);
    if (any(['ucuncu haciz', '3 haciz', '3. haciz', '89/3', '89 3'])) {
      return BelgeTuru.hacizIhbarnamesiUcuncu;
    }
    if (any(['ikinci haciz', '2 haciz', '2. haciz', '89/2', '89 2'])) {
      return BelgeTuru.hacizIhbarnamesiIkinci;
    }
    if (any(['birinci haciz', '1 haciz', '1. haciz', '89/1', '89 1'])) {
      return BelgeTuru.hacizIhbarnamesiBirinci;
    }
    return BelgeTuru.hacizIhbarnamesi;
  }

  /// Every document of a notice with the kind its own name gives, in its
  /// order: a package of a report and an interim decision is two kinds,
  /// never only the one ranked higher (Folio). The envelope and what tells
  /// nothing are left out.
  static List<({BelgeTuru tur, String ad})> ekTurleri(List<String> adlar) => [
    for (final ad in adlar)
      if (_tekil(ad, null) case final t when !belirsiz(t)) (tur: t, ad: ad),
  ];

  /// Sunucudan gelen enum ADINI BelgeTuru'ne cevirir. Taninmayan ad -> null
  /// (uydurma yok; cagiran kural sonucunu korur).
  static BelgeTuru? adaGore(String ad) {
    for (final t in BelgeTuru.values) {
      if (t.name == ad) return t;
    }
    return null;
  }

  /// Kural tabanli sonuc BELIRSIZ mi (model sorulmali mi)?
  static bool belirsiz(BelgeTuru t) =>
      t == BelgeTuru.diger || t == BelgeTuru.tebligatZarfi;

  /// Türkçe karakterleri ascii'ye katlar, alt çizgi/boşluğu normalize eder.
  static String _norm(String s) {
    var x = s.replaceAll('İ', 'i').replaceAll('I', 'i').toLowerCase();
    x = x
        .replaceAll('ş', 's')
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll('_', ' ')
        .replaceAll('-', ' ');
    return x.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Süre belirleme önceliği (yüksek = daha belirleyici).
  static int _oncelik(BelgeTuru t) => switch (t) {
    BelgeTuru.gerekceliKarar || BelgeTuru.kararIlami => 100,
    BelgeTuru.istinafKarari || BelgeTuru.temyizKarari => 95,
    // Kambiyo GENEL odeme emrinden ONCE gelir: ikisi de eslesirse daha
    // OZEL olan kazanmali. Suresi de daha kisa (5 gun), yani guvenli yon.
    BelgeTuru.odemeEmriKambiyo => 92,
    BelgeTuru.odemeEmri ||
    BelgeTuru.icraEmri ||
    BelgeTuru.hacizIhbarnamesi ||
    BelgeTuru.hacizIhbarnamesiBirinci ||
    BelgeTuru.hacizIhbarnamesiIkinci ||
    BelgeTuru.hacizIhbarnamesiUcuncu => 90,
    BelgeTuru.kanunYoluDilekcesi => 75,
    BelgeTuru.satisIlani || BelgeTuru.tebligname => 72,
    BelgeTuru.davaDilekcesi ||
    BelgeTuru.cevapDilekcesi ||
    BelgeTuru.cevabaCevapDilekcesi => 70,
    BelgeTuru.iddianame => 60,
    BelgeTuru.tensipZapti || BelgeTuru.araKarar => 40,
    BelgeTuru.bilirkisiRaporu ||
    BelgeTuru.durusmaDavetiyesi ||
    BelgeTuru.durusmaTutanagi => 35,
    BelgeTuru.muzekkere || BelgeTuru.ihtarname || BelgeTuru.vekaletname => 30,
    BelgeTuru.tebligatZarfi => 5,
    BelgeTuru.diger => 0,
  };
}

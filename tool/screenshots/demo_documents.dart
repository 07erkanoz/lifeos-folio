// The documents the screenshots show. Every person, address and file number
// here is invented; the laws cited are real, and so is the decision, which
// the Court of Cassation publishes without the parties' names.

/// One paragraph of a demo document: its text, how it is aligned, and how
/// many of its first characters are bold (a heading, or "DAVACI :").
class DemoParagraph {
  const DemoParagraph(
    this.text, {
    this.center = false,
    this.bold = 0,
    this.justify = false,
  });

  /// A paragraph set in bold throughout.
  const DemoParagraph.heading(this.text, {this.center = false})
    : bold = -1,
      justify = false;

  final String text;
  final bool center, justify;

  /// Bold characters from the start; -1 for all of them.
  final int bold;
}

DemoParagraph _label(String label, String rest) =>
    DemoParagraph('$label\t: $rest', bold: label.length);

/// A divorce petition citing [decision] (a label such as
/// "2. Hukuk Dairesi E.2016/24019 K.2017/6511").
List<DemoParagraph> demoPetition(String decision) => [
  const DemoParagraph.heading(
    'İSTANBUL ANADOLU NÖBETÇİ AİLE MAHKEMESİ HÂKİMLİĞİ’NE',
    center: true,
  ),
  const DemoParagraph(''),
  _label(
    'DAVACI',
    'Zeynep KAYA, Örnek Mah. Deneme Sok. No: 1 Kadıköy / İSTANBUL',
  ),
  _label('VEKİLİ', 'Av. Deniz YILMAZ'),
  _label(
    'DAVALI',
    'Emre KAYA, Örnek Mah. Deneme Sok. No: 1 Kadıköy / İSTANBUL',
  ),
  _label(
    'KONU',
    'Evlilik birliğinin temelinden sarsılması nedeniyle boşanma, maddi ve '
        'manevi tazminat talebimizden ibarettir.',
  ),
  const DemoParagraph(''),
  const DemoParagraph.heading('AÇIKLAMALAR', center: true),
  const DemoParagraph(
    '1. Taraflar 2015 yılında evlenmiş olup bu evlilikten müşterek bir '
    'çocukları bulunmaktadır. Davalının ekonomik şiddet uygulaması, ortak '
    'konutu uzun süre terk etmesi ve davacıya yönelik küçük düşürücü '
    'davranışları nedeniyle evlilik birliği, ortak hayatı sürdürmeleri '
    'taraflardan beklenemeyecek derecede temelinden sarsılmıştır.',
    justify: true,
  ),
  const DemoParagraph(
    '2. TMK m. 166/1 uyarınca evlilik birliği, ortak hayatı sürdürmeleri '
    'kendilerinden beklenemeyecek derecede temelinden sarsılmış olursa '
    'eşlerden her biri boşanma davası açabilir. Somut olayda boşanma şartları '
    'gerçekleşmiştir.',
    justify: true,
  ),
  const DemoParagraph(
    '3. Boşanmaya sebep olan olaylarda kusuru daha ağır olan davalı, TMK m. 174 '
    'uyarınca davacının maddi ve manevi zararlarını karşılamakla yükümlüdür. '
    'Boşanma yüzünden yoksulluğa düşecek olan davacı lehine TMK m. 175 '
    'uyarınca yoksulluk nafakasına hükmedilmesi gerekmektedir.',
    justify: true,
  ),
  DemoParagraph(
    '4. Yerleşik içtihada göre kusur belirlemesi, tarafların ispatlanan '
    'davranışlarına göre yapılır (Yargıtay $decision). Dava dilekçesi '
    'HMK m. 119 uyarınca gerekli unsurları taşımaktadır.',
    justify: true,
  ),
  const DemoParagraph(''),
  _label(
    'HUKUKİ SEBEPLER',
    'TMK m. 166, 174, 175; HMK m. 119 ve ilgili mevzuat.',
  ),
  _label(
    'DELİLLER',
    'Nüfus kaydı, tanık beyanları, banka kayıtları, bilirkişi incelemesi ve '
        'her türlü yasal delil.',
  ),
  _label(
    'SONUÇ VE İSTEM',
    'Tarafların boşanmalarına, davacı lehine maddi ve manevi tazminata, '
        'yoksulluk nafakasına, yargılama giderleri ile vekâlet ücretinin '
        'davalıya yükletilmesine karar verilmesini saygılarımızla arz ve talep '
        'ederiz.',
  ),
  const DemoParagraph(''),
  const DemoParagraph('Davacı Vekili\nAv. Deniz YILMAZ', center: true),
];

/// A document in the demo archive: its file name and its paragraphs.
class DemoFile {
  const DemoFile(this.name, this.paragraphs, {this.daysAgo = 0});
  final String name;
  final List<DemoParagraph> paragraphs;

  /// How long ago it was last changed, for the archive's order and dates.
  final int daysAgo;
}

DemoParagraph _body(String text) => DemoParagraph(text, justify: true);

/// The archive the library screens show: a small office's recent work.
List<DemoFile> demoArchive(String decision) => [
  DemoFile('Boşanma Dava Dilekçesi.udf', demoPetition(decision), daysAgo: 1),
  DemoFile('Kira Tahliye İhtarnamesi.udf', [
    const DemoParagraph.heading('İHTARNAME', center: true),
    _label('KEŞİDECİ', 'Selin AKTAŞ, Vekili Av. Deniz YILMAZ'),
    _label('MUHATAP', 'Burak ŞAHİN, Deneme Cad. No: 12/4 Üsküdar / İSTANBUL'),
    _label('KONU', 'Kira bedelinin ödenmemesi nedeniyle tahliye ihtarıdır.'),
    _body(
      'Müvekkilimize ait taşınmazda kiracı olarak bulunduğunuz halde Temmuz ve '
      'Ağustos 2026 aylarına ait kira bedellerini ödemediniz. TBK m. 315 '
      'uyarınca işbu ihtarnamenin tebliğinden itibaren otuz gün içinde '
      'birikmiş kira bedellerini ödemediğiniz takdirde kira sözleşmesinin '
      'feshedileceğini ve tahliye davası açılacağını ihtar ederiz.',
    ),
  ], daysAgo: 2),
  DemoFile('Cevap Dilekçesi - İşçilik Alacağı.udf', [
    const DemoParagraph.heading('İSTANBUL 12. İŞ MAHKEMESİ’NE', center: true),
    _label('DOSYA NO', '2026/4815 Esas'),
    _label('DAVALI', 'Örnek Lojistik Ltd. Şti.'),
    _label('DAVACI', 'Can ÖZTÜRK'),
    _label('KONU', 'Davaya karşı cevaplarımızın sunulmasıdır.'),
    _body(
      'Davacı, iş sözleşmesinin haklı neden olmaksızın feshedildiğini ileri '
      'sürerek kıdem ve ihbar tazminatı talep etmektedir. Oysa fesih, '
      'davacının devamsızlığı nedeniyle 4857 sayılı İş Kanunu m. 25/II-g '
      'uyarınca haklı nedenle yapılmıştır. Fazla çalışma iddiası ise puantaj '
      'kayıtlarıyla çelişmektedir.',
    ),
  ], daysAgo: 4),
  DemoFile('Bilirkişi Raporuna İtiraz.udf', [
    const DemoParagraph.heading(
      'ANKARA 4. ASLİYE TİCARET MAHKEMESİ’NE',
      center: true,
    ),
    _label('DOSYA NO', '2025/912 Esas'),
    _label('KONU', 'Bilirkişi raporuna itirazlarımızın sunulmasıdır.'),
    _body(
      'Dosyaya sunulan bilirkişi raporunda faturaların tamamı değerlendirmeye '
      'alınmamış, ticari defterlerdeki mutabakat kayıtları gözden kaçırılmıştır. '
      'HMK m. 281 uyarınca raporun eksikliklerinin giderilmesi için ek rapor '
      'alınmasını talep ederiz.',
    ),
  ], daysAgo: 6),
  DemoFile('İcra Takip Talebi.udf', [
    const DemoParagraph.heading('İCRA TAKİP TALEBİ', center: true),
    _label('ALACAKLI', 'Deneme Yapı A.Ş.'),
    _label('BORÇLU', 'Mert KOÇ'),
    _label('ALACAK', '185.000,00 TL asıl alacak ve işlemiş faiz'),
    _body(
      'Borçlu hakkında 2004 sayılı İcra ve İflas Kanunu hükümlerine göre ilamsız '
      'icra yoluyla genel haciz takibi başlatılmasını, takip tarihinden '
      'itibaren işleyecek yasal faiziyle birlikte tahsilini talep ederiz.',
    ),
  ], daysAgo: 9),
  DemoFile('Arabuluculuk Son Tutanağı.pdf', [
    const DemoParagraph.heading('ARABULUCULUK SON TUTANAĞI', center: true),
    _label('BÜRO NO', '2026/3301'),
    _label('TARAFLAR', 'Elif ARSLAN ile Örnek Gıda San. A.Ş.'),
    _body(
      'Taraflar, arabulucu huzurunda yapılan görüşmeler sonunda işçilik '
      'alacakları konusunda anlaşmaya varmıştır. Anlaşma uyarınca ödeme iki '
      'eşit taksitte yapılacak ve taraflar birbirlerini başkaca talepten ibra '
      'edecektir.',
    ),
  ], daysAgo: 12),
  DemoFile('Kira Sözleşmesi - Deneme Cad. No 12.pdf', [
    const DemoParagraph.heading('KİRA SÖZLEŞMESİ', center: true),
    _label('KİRAYA VEREN', 'Selin AKTAŞ'),
    _label('KİRACI', 'Burak ŞAHİN'),
    _label('KİRALANAN', 'Deneme Cad. No: 12/4 Üsküdar / İSTANBUL'),
    _body(
      'Aylık kira bedeli her ayın beşinci gününe kadar kiraya verenin banka '
      'hesabına ödenecektir. Kiracı, kiralananı özenle kullanmak ve komşulara '
      'saygı göstermekle yükümlüdür (TBK m. 316).',
    ),
  ], daysAgo: 30),
  DemoFile('Tanık Listesi.udf', [
    const DemoParagraph.heading('TANIK LİSTESİ', center: true),
    _label('DOSYA NO', '2026/1204 Esas'),
    _body(
      '1. Ayşe DEMİR – Taraflar arasındaki tartışmalara ve davalının ortak '
      'konutu terk ettiği tarihe ilişkin. 2. Kemal YILDIZ – Davalının ekonomik '
      'baskısına ve aile içi ilişkilere ilişkin.',
    ),
  ], daysAgo: 1),
];

/// What the documents of the demo UYAP case say: enough to show one.
List<DemoParagraph> demoUyapDocument(String type) => switch (type) {
  'Bilirkişi Raporu' => [
    _label(
      'KONU',
      'Tarafların ve müşterek çocuğun sosyal durumunun incelenmesi',
    ),
    const DemoParagraph(''),
    _body(
      'Mahkemenin 16.09.2026 tarihli ara kararı uyarınca taraflarla ayrı '
      'ayrı görüşülmüş, müşterek konut ve davacının hâlen oturduğu konut '
      'yerinde incelenmiştir. Müşterek çocuğun okul öğretmeni ile de '
      'görüşülmüştür.',
    ),
    _body(
      'Davacının çocuğun okuluna yakın bir konutta düzenli bir yaşam '
      'sürdürdüğü, çocuğun bakım ve eğitim ihtiyaçlarının karşılandığı '
      'gözlemlenmiştir. Davalının iş nedeniyle sık sık şehir dışında '
      'bulunduğu ve çocukla görüşmelerinin düzensiz olduğu anlaşılmıştır.',
    ),
    _body(
      'Bu tespitler ışığında, müşterek çocuğun velayetinin davacı anneye '
      'verilmesinin, babayla kişisel ilişkinin ise hafta sonları ve yarıyıl '
      'tatillerinde kurulmasının çocuğun üstün yararına uygun olacağı '
      'kanaatine varılmıştır.',
    ),
    const DemoParagraph(''),
    _label('SONUÇ', 'Velayetin davacıya verilmesi uygun görülmüştür.'),
    const DemoParagraph('Sosyal Çalışmacı Ayşe DEMİR', center: true),
  ],
  _ => [
    _body(
      'Dosya kapsamındaki belgeler ve tarafların beyanları birlikte '
      'değerlendirilmiş, işbu evrak düzenlenmiştir.',
    ),
  ],
};

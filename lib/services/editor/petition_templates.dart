import '../../models/document_model.dart';

/// The petitions the editor's Hukuk tab begins: a lawyer's own skeletons,
/// laid out as UYAP lays out a filing (Times New Roman 12, the court
/// centred and bold, the labels in a column with their colons on one tab
/// stop, the body justified), and filled from the case the document is
/// tied to: its court, its number, its parties and its next hearing.
///
/// Brackets mark what is left to the lawyer.

/// What a template takes from the case the document belongs to.
class PetitionCase {
  const PetitionCase({
    required this.court,
    required this.number,
    this.lawyer,
    this.parties = const [],
    this.hearing,
  });

  /// "Antalya 3. Asliye Hukuk Mahkemesi", "2024/318 Esas".
  final String court, number;

  /// "Av. Deniz Kaya", from the lawyer's profile.
  final String? lawyer;

  /// The case's parties as UYAP lists them: (role, name).
  final List<(String, String)> parties;

  /// The case's next hearing.
  final DateTime? hearing;

  bool get criminal => isCriminalCourt(court);

  /// The names of the parties whose role contains one of [roles].
  String? of(List<String> roles) {
    final names = [
      for (final (role, name) in parties)
        if (name.isNotEmpty &&
            roles.any((r) => trLower(role).contains(trLower(r))))
          name,
    ];
    return names.isEmpty ? null : names.join(', ');
  }
}

/// A court whose files are criminal.
bool isCriminalCourt(String court) {
  final c = trLower(court);
  return c.contains('ceza') || c.contains('cumhuriyet başsavcılığı');
}

class PetitionTemplate {
  const PetitionTemplate(this.group, this.name, this.build);

  /// The heading it is listed under: Hukuk, Ceza, Duruşma, Karar, İcra.
  final String group;
  final String name;
  final DocModel Function(PetitionCase? from, DateTime today) build;
}

/// Turkish capitals and small letters: i is İ, ı is I.
String trUpper(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
String trLower(String s) =>
    s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

String _two(int v) => v.toString().padLeft(2, '0');

/// "07.10.2026".
String dotted(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';

/// "07.10.2026 günü saat 09:35".
String _hearingAt(DateTime? at) => at == null
    ? '…/…/20… günü saat …:…'
    : '${dotted(at)} günü saat ${_two(at.hour)}:${_two(at.minute)}';

/// The heading's court, in the dative: "ANTALYA 3. ASLİYE HUKUK
/// MAHKEMESİ’NE", "ANTALYA 5. İCRA DAİRESİ MÜDÜRLÜĞÜ’NE".
String courtTo(String court) {
  final upper = trUpper(court.trim());
  if (upper.endsWith('DAİRESİ') && upper.contains('İCRA')) {
    return '$upper MÜDÜRLÜĞÜ’NE';
  }
  if (upper.endsWith('MÜDÜRLÜĞÜ')) return '$upper’NE';
  return '$upper’NE';
}

/// "2024/318 Esas": a bare number is an Esas number.
String _esas(String number) =>
    RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]').hasMatch(number) ? number : '$number Esas';

// The page's parts.

const _font = 'Times New Roman';
const _size = 12.0;

/// The labels' column: a tab stop here, and the value's second row under
/// its first.
const _labelStop = 150.0;
const _valueStart = 158.0;

DocSpan _span(int start, int length, {bool bold = false}) => DocSpan(
  startOffset: start,
  length: length,
  bold: bold,
  fontFamily: _font,
  fontSize: _size,
);

DocBlock _text(
  String text, {
  DocAlignment align = DocAlignment.left,
  bool bold = false,
  double first = 0,
  double before = 0,
}) => DocBlock(
  plainText: text,
  alignment: align,
  firstLineIndent: first,
  spacingBefore: before,
  spans: text.isEmpty ? const [] : [_span(0, text.length, bold: bold)],
  endFontSize: _size,
  endFontFamily: _font,
);

DocBlock _blank() => _text('');

/// The court, centred and bold.
DocBlock _court(String text) =>
    _text(text, align: DocAlignment.center, bold: true);

/// "DAVACI`<TAB`>: Ayşe K.": the label bold, its colon on the column's stop,
/// a long value wrapping under itself.
DocBlock _field(String label, String value) {
  final head = '${trUpper(label)}\t';
  final text = '$head: $value';
  return DocBlock(
    plainText: text,
    tabSet: '${_labelStop.toStringAsFixed(1)}:0',
    hanging: _valueStart,
    spans: [
      _span(0, head.length, bold: true),
      _span(head.length, text.length - head.length),
    ],
    endFontSize: _size,
    endFontFamily: _font,
  );
}

/// A section's heading: bold, with room above it.
DocBlock _head(String text) => _text(trUpper(text), bold: true, before: 6);

/// The body: justified, its first row indented.
DocBlock _body(String text) =>
    _text(text, align: DocAlignment.justify, first: 36);

/// A numbered point: justified, not indented.
DocBlock _point(String text) => _text(text, align: DocAlignment.justify);

List<DocBlock> _signature(
  PetitionCase? c,
  DateTime today,
  String role, {
  List<String> attachments = const [],
}) => [
  _blank(),
  _text(dotted(today), align: DocAlignment.right),
  _text(role, align: DocAlignment.right),
  _text(c?.lawyer ?? 'Av. [Ad Soyad]', align: DocAlignment.right, bold: true),
  _text('(e-imzalıdır)', align: DocAlignment.right),
  if (attachments.isNotEmpty) ...[
    _blank(),
    _text('EKLER', bold: true),
    for (final (i, a) in attachments.indexed) _text('${i + 1}- $a'),
  ],
];

DocModel _page(List<DocBlock> blocks) => DocModel(blocks: blocks);

// The same parts for the ribbon's single tools.

DocBlock petitionField(String label, String value) => _field(label, value);
DocBlock petitionHeading(String text) => _head(text);
DocBlock petitionLine(
  String text, {
  DocAlignment align = DocAlignment.left,
  bool bold = false,
}) => _text(text, align: align, bold: bold);
List<DocBlock> petitionSignature(String? lawyer, DateTime today, String role) =>
    _signature(
      lawyer == null
          ? null
          : PetitionCase(court: '', number: '', lawyer: lawyer),
      today,
      role,
    );

// The parts that follow the case.

String _courtLine(PetitionCase? c, String fallback) =>
    c == null ? fallback : courtTo(c.court);

String _number(PetitionCase? c) => c == null ? '20…/… Esas' : _esas(c.number);

String _lawyerOf(PetitionCase? c) =>
    '${c?.lawyer ?? 'Av. [Ad Soyad]'} ([…] Barosu)';

/// The side the lawyer stands for, in a criminal or a civil file.
({String client, String counsel, String clientWord}) _side(PetitionCase? c) =>
    c != null && c.criminal
    ? (client: 'SANIK', counsel: 'MÜDAFİİ', clientWord: 'Sanık Müdafii')
    : (client: 'MÜVEKKİL', counsel: 'VEKİLİ', clientWord: 'Vekili');

final petitionTemplates = <PetitionTemplate>[
  // Civil.
  PetitionTemplate(
    'Hukuk',
    'Dava dilekçesi',
    (c, today) => _page([
      _court(_courtLine(c, 'NÖBETÇİ […] ASLİYE HUKUK MAHKEMESİ’NE')),
      _blank(),
      _field('Davacı', '${c?.of(['davacı']) ?? '[Ad Soyad]'} (TCKN: […])'),
      _field('Vekili', _lawyerOf(c)),
      _field('Davalı', '${c?.of(['davalı']) ?? '[Ad Soyad / Unvan]'} […]'),
      _field('Dava Değeri', '[…] TL'),
      _field('Konu', '[…] istemine ilişkindir.'),
      _blank(),
      _head('Açıklamalar'),
      _point(
        '1- Müvekkil ile davalı arasında […] tarihinde […] '
        'ilişkisi kurulmuştur.',
      ),
      _point(
        '2- Davalı, […] yükümlülüğünü yerine getirmemiş; müvekkil bu '
        'nedenle […] zarara uğramıştır.',
      ),
      _point(
        '3- Uyuşmazlığın sulh yoluyla çözümü için yapılan girişimler '
        'sonuçsuz kalmış, işbu davayı açma zorunluluğu doğmuştur.',
      ),
      _head('Hukuki Sebepler'),
      _point('HMK, TBK, TMK ve ilgili sair mevzuat.'),
      _head('Hukuki Deliller'),
      _point(
        'Sözleşme ve yazışmalar, banka kayıtları, tanık beyanları, '
        'bilirkişi incelemesi, keşif, yemin ve her türlü yasal delil.',
      ),
      _head('Sonuç ve İstem'),
      _body(
        'Yukarıda açıklanan ve re’sen gözetilecek nedenlerle; davamızın '
        'KABULÜ ile […]’a, yargılama giderleri ile vekâlet ücretinin '
        'davalıya yükletilmesine karar verilmesini saygılarımızla vekâleten '
        'arz ve talep ederiz.',
      ),
      ..._signature(
        c,
        today,
        'Davacı Vekili',
        attachments: ['Vekâletname örneği', 'Delil listesi ve belgeler'],
      ),
    ]),
  ),
  PetitionTemplate(
    'Hukuk',
    'Cevap dilekçesi',
    (c, today) => _page([
      _court(_courtLine(c, '[…] ASLİYE HUKUK MAHKEMESİ’NE')),
      _blank(),
      _field('Dosya No', _number(c)),
      _field('Cevap Veren', '${c?.of(['davalı']) ?? '[Ad Soyad]'} (Davalı)'),
      _field('Vekili', _lawyerOf(c)),
      _field('Davacı', c?.of(['davacı']) ?? '[Ad Soyad]'),
      _field('Tebliğ Tarihi', '…/…/20…'),
      _field('Konu', 'Dava dilekçesine karşı cevaplarımızın sunulmasıdır.'),
      _blank(),
      _head('Ön İtirazlarımız'),
      _point(
        '1- [Görev / yetki / zamanaşımı / dava şartı] yönünden itirazımız '
        'bulunmaktadır: […]',
      ),
      _head('Esasa İlişkin Cevaplarımız'),
      _point(
        '1- Davacının iddiaları gerçeği yansıtmamaktadır. Kabul anlamına '
        'gelmemek kaydıyla belirtmek gerekir ki […]',
      ),
      _point(
        '2- Davacı, iddiasını ispat yükünü (TMK m.6, HMK m.190) yerine '
        'getirememiştir. […]',
      ),
      _point('3- Dava dilekçesinde ileri sürülen talepler fahiştir. […]'),
      _head('Hukuki Sebepler'),
      _point('HMK m.127 vd., TBK, TMK ve ilgili sair mevzuat.'),
      _head('Hukuki Deliller'),
      _point(
        'Dosya kapsamı, […] kayıtları, tanık beyanları, bilirkişi '
        'incelemesi, yemin ve her türlü yasal delil.',
      ),
      _head('Sonuç ve İstem'),
      _body(
        'Yukarıda açıklanan ve re’sen gözetilecek nedenlerle; ön '
        'itirazlarımızın kabulüne, kabul görmemesi hâlinde haksız ve '
        'mesnetsiz davanın ESASTAN REDDİNE, yargılama giderleri ile vekâlet '
        'ücretinin davacıya yükletilmesine karar verilmesini saygılarımızla '
        'vekâleten arz ve talep ederiz.',
      ),
      ..._signature(c, today, 'Davalı Vekili'),
    ]),
  ),
  PetitionTemplate(
    'Hukuk',
    'İstinaf dilekçesi (Hukuk)',
    (c, today) => _page([
      _court('[…] BÖLGE ADLİYE MAHKEMESİ İLGİLİ HUKUK DAİRESİ’NE'),
      _text('Gönderilmek Üzere', align: DocAlignment.center),
      _court(_courtLine(c, '[…] ASLİYE HUKUK MAHKEMESİ’NE')),
      _blank(),
      _field('Dosya No', _number(c)),
      _field('Karar No', '20…/… Karar'),
      _field('İstinaf Eden', '[Davacı / Davalı] […]'),
      _field('Vekili', _lawyerOf(c)),
      _field('Karşı Taraf', '[Ad Soyad / Unvan]'),
      _field('Karar Tarihi', '…/…/20…'),
      _field('Tebliğ Tarihi', '…/…/20…'),
      _field(
        'Konu',
        'İlk derece mahkemesi kararının HMK m.341 vd. uyarınca KALDIRILMASI '
            'istemidir.',
      ),
      _blank(),
      _head('Açıklamalar'),
      _body(
        'Yerel mahkemece verilen karar, aşağıda açıklanan nedenlerle usul '
        've yasaya aykırı olup kaldırılması gerekmektedir. Kararın tarafımıza '
        'tebliğinden itibaren iki haftalık yasal süre (HMK m.345) içinde '
        'istinaf yoluna başvuruyoruz.',
      ),
      _head('İstinaf Sebeplerimiz'),
      _point(
        '1- Usule aykırılık: Mahkemece […] hususunda HMK’nın emredici '
        'hükümlerine uyulmamış, hukuki dinlenilme hakkı ihlal edilmiştir.',
      ),
      _point(
        '2- Delillerin değerlendirilmesi: Dosyaya sunulan […] delili hiç '
        'değerlendirilmemiş, eksik inceleme ile hüküm kurulmuştur.',
      ),
      _point(
        '3- Esasa ilişkin: Kararın gerekçesi dosya kapsamıyla '
        'örtüşmemektedir. […]',
      ),
      _head('Hukuki Sebepler'),
      _point('HMK m.341–366 ve ilgili sair mevzuat.'),
      _head('Sonuç ve İstem'),
      _body(
        'Yukarıda açıklanan ve re’sen gözetilecek nedenlerle; istinaf '
        'başvurumuzun KABULÜ ile ilk derece mahkemesi kararının '
        'KALDIRILMASINA, HMK m.353/1-b uyarınca davanın esası hakkında '
        'yeniden hüküm kurularak […] karar verilmesine, yargılama giderleri '
        'ile vekâlet ücretinin karşı tarafa yükletilmesine karar verilmesini '
        'saygılarımızla vekâleten arz ve talep ederiz.',
      ),
      ..._signature(c, today, 'İstinaf Eden Vekili'),
    ]),
  ),
  PetitionTemplate(
    'Hukuk',
    'Bilirkişi raporuna itiraz',
    (c, today) => _page([
      _court(_courtLine(c, '[…] ASLİYE HUKUK MAHKEMESİ’NE')),
      _blank(),
      _field('Dosya No', _number(c)),
      _field('İtiraz Eden', '[Davacı / Davalı] […]'),
      _field('Vekili', _lawyerOf(c)),
      _field('Rapor Tebliğ', '…/…/20…'),
      _field(
        'Konu',
        '…/…/20… tarihli bilirkişi raporuna itirazlarımızın sunulmasıdır.',
      ),
      _blank(),
      _head('Açıklamalar'),
      _body(
        'Dosyaya sunulan bilirkişi raporu tarafımıza …/…/20… tarihinde tebliğ '
        'edilmiş olup HMK m.281 uyarınca iki haftalık süre içinde aşağıdaki '
        'itirazlarımızı sunuyoruz.',
      ),
      _point(
        '1- Bilirkişi, mahkemece belirlenen görev kapsamını aşarak hukuki '
        'nitelendirme yapmıştır (HMK m.279/4). […]',
      ),
      _point(
        '2- Raporda dosyadaki […] belgesi dikkate alınmamış; hesaplama '
        'eksik ve hatalı yapılmıştır. […]',
      ),
      _point('3- Rapor, denetime elverişli gerekçe içermemektedir. […]'),
      _head('Sonuç ve İstem'),
      _body(
        'Yukarıda açıklanan nedenlerle itirazlarımızın kabulü ile raporun '
        'hükme esas alınmamasına, itirazlarımız doğrultusunda ek rapor '
        'alınmasına, olmadığı takdirde HMK m.281/2 uyarınca yeni bir '
        'bilirkişi (heyeti) tarafından inceleme yaptırılmasına karar '
        'verilmesini saygılarımızla vekâleten arz ve talep ederiz.',
      ),
      ..._signature(c, today, 'Vekili'),
    ]),
  ),
  // Criminal.
  PetitionTemplate(
    'Ceza',
    'İstinaf dilekçesi (Ceza)',
    (c, today) => _page([
      _court('[…] BÖLGE ADLİYE MAHKEMESİ İLGİLİ CEZA DAİRESİ’NE'),
      _text('Gönderilmek Üzere', align: DocAlignment.center),
      _court(_courtLine(c, '[…] ASLİYE CEZA MAHKEMESİ’NE')),
      _blank(),
      _field('Dosya No', _number(c)),
      _field('Karar No', '20…/… Karar'),
      _field('İstinaf Eden', '${c?.of(['sanık']) ?? '[Ad Soyad]'} (Sanık)'),
      _field('Müdafii', _lawyerOf(c)),
      _field('Katılan', c?.of(['katılan', 'müşteki']) ?? '[…]'),
      _field('Suç', '[…]'),
      _field('Hüküm Tarihi', '…/…/20…'),
      _field('Tebliğ Tarihi', '…/…/20… (gerekçeli karar)'),
      _field(
        'Konu',
        'Yerel mahkeme hükmüne karşı CMK m.272 vd. uyarınca istinaf '
            'sebeplerimizin sunulmasıdır.',
      ),
      _blank(),
      _head('Açıklamalar'),
      _body(
        'Müvekkil sanık hakkında yerel mahkemece kurulan mahkûmiyet hükmüne '
        'karşı yasal süresi içinde istinaf yoluna başvurulmuş olup gerekçeli '
        'istinaf sebeplerimiz aşağıda sunulmuştur.',
      ),
      _head('İstinaf Sebeplerimiz'),
      _point(
        '1- Suçun sübutu: Müvekkilin atılı suçu işlediğine dair her türlü '
        'şüpheden uzak, kesin ve inandırıcı delil bulunmamaktadır. '
        '“Şüpheden sanık yararlanır” ilkesi gözetilmemiştir.',
      ),
      _point(
        '2- Delillerin hukuka uygunluğu: Hükme esas alınan […] delili '
        'hukuka aykırı yöntemle elde edilmiş olup CMK m.206/2-a ve m.217/2 '
        'uyarınca hükme esas alınamaz.',
      ),
      _point(
        '3- Suç vasfı ve ceza: Eylemin nitelendirilmesi hatalıdır; temel '
        'cezanın belirlenmesinde TCK m.61 ölçütlerine uyulmamış, TCK m.62 '
        'takdiri indirim ve CMK m.231 (HAGB) hükümleri gerekçesiz olarak '
        'uygulanmamıştır.',
      ),
      _head('Hukuki Sebepler'),
      _point('CMK m.272–285, TCK ve ilgili sair mevzuat.'),
      _head('Sonuç ve İstem'),
      _body(
        'Yukarıda açıklanan ve re’sen gözetilecek nedenlerle; istinaf '
        'başvurumuzun KABULÜ ile CMK m.280 uyarınca hükmün '
        'KALDIRILMASINA, müvekkil sanığın atılı suçtan BERAATİNE, aksi '
        'kanaatte duruşma açılarak yeniden yargılama yapılmasına karar '
        'verilmesini saygılarımızla arz ve talep ederiz.',
      ),
      ..._signature(c, today, 'Sanık Müdafii'),
    ]),
  ),
  // The hearing.
  PetitionTemplate('Duruşma', 'E-duruşma talebi', (c, today) {
    final side = _side(c);
    final criminal = c != null && c.criminal;
    return _page([
      _court(_courtLine(c, '[…] MAHKEMESİ’NE')),
      _blank(),
      _field('Dosya No', _number(c)),
      _field(
        'Talep Eden',
        side.counsel == 'MÜDAFİİ'
            ? '${c?.of(['sanık']) ?? '[Ad Soyad]'} (Sanık)'
            : '[Müvekkil Ad Soyad]',
      ),
      _field(side.counsel, _lawyerOf(c)),
      _field(
        'Konu',
        '${_hearingAt(c?.hearing)} yapılacak duruşmaya e-duruşma '
            'yoluyla katılım talebimizdir.',
      ),
      _blank(),
      _head('Açıklamalar'),
      _body(
        'Yukarıda numarası yazılı dosyanın ${_hearingAt(c?.hearing)} '
        'yapılacak duruşmasına, büromuzdan UYAP Avukat Portal e-Duruşma '
        'uygulaması (SEGBİS) aracılığıyla, ses ve görüntü nakli yoluyla '
        'katılmak istiyoruz. Bağlantı için gerekli teknik altyapı '
        'büromuzda mevcuttur.',
      ),
      _head('Hukuki Sebepler'),
      _point(
        criminal
            ? 'CMK m.196, Ceza Muhakemesinde Sesli ve Görüntülü Bilişim '
                  'Sisteminin Kullanılması Hakkında Yönetmelik ve ilgili '
                  'mevzuat.'
            : 'HMK m.149 ve ilgili mevzuat.',
      ),
      _head('Sonuç ve İstem'),
      _body(
        'Yukarıda açıklanan nedenlerle ${_hearingAt(c?.hearing)} yapılacak '
        'duruşmaya e-duruşma yoluyla katılım talebimizin kabulüne karar '
        'verilmesini saygılarımızla arz ve talep ederiz.',
      ),
      ..._signature(c, today, criminal ? 'Sanık Müdafii' : 'Vekili'),
    ]);
  }),
  PetitionTemplate('Duruşma', 'Mazeret dilekçesi (mesleki)', (c, today) {
    final side = _side(c);
    return _page([
      _court(_courtLine(c, '[…] MAHKEMESİ’NE')),
      _blank(),
      _field('Dosya No', _number(c)),
      _field(
        'Mazeret Bildiren',
        '${c?.lawyer ?? 'Av. [Ad Soyad]'} '
            '(${side.clientWord})',
      ),
      _field('Duruşma', _hearingAt(c?.hearing)),
      _field(
        'Konu',
        'Mesleki mazeret bildirimi ve duruşmanın ertelenmesi '
            'talebimizdir.',
      ),
      _blank(),
      _head('Açıklamalar'),
      _body(
        'Yukarıda numarası yazılı dosyanın ${_hearingAt(c?.hearing)} '
        'yapılacak duruşmasında ${side.clientWord.toLowerCase()} olarak '
        'bulunmam gerekmektedir. Ancak aynı gün ve saatte […] Mahkemesi’nin '
        '20…/… Esas sayılı dosyasında, ondan önce tayin edilmiş duruşmam '
        'bulunmaktadır. Bu nedenle duruşmaya katılamayacağım.',
      ),
      _body(
        'Mazeretimi gösteren diğer dosyaya ait duruşma gün ve saatini '
        'gösterir UYAP çıktısı ekte sunulmuştur. Müvekkilin hukuki '
        'yararlarının korunması ve savunma hakkının kısıtlanmaması için '
        'duruşmanın ertelenmesi zorunludur.',
      ),
      _head('Sonuç ve İstem'),
      _body(
        'Yukarıda açıklanan nedenlerle mesleki mazeretimin KABULÜ ile '
        'duruşmanın ertelenmesine, yeni duruşma gün ve saatinin tarafıma '
        'bildirilmesine karar verilmesini saygılarımla arz ve talep ederim.',
      ),
      ..._signature(
        c,
        today,
        side.clientWord,
        attachments: ['Diğer dosyanın duruşma gün ve saatini gösterir belge'],
      ),
    ]);
  }),
  // The judgment.
  PetitionTemplate('Karar', 'Kararın tebliği talebi', (c, today) {
    final side = _side(c);
    return _page([
      _court(_courtLine(c, '[…] MAHKEMESİ’NE')),
      _blank(),
      _field('Dosya No', _number(c)),
      _field('Karar No', '20…/… Karar'),
      _field('Talep Eden', '[Müvekkil Ad Soyad]'),
      _field(side.counsel, _lawyerOf(c)),
      _field(
        'Konu',
        'Gerekçeli kararın taraflara tebliğe çıkarılması '
            'talebimizdir.',
      ),
      _blank(),
      _head('Açıklamalar'),
      _body(
        'Yukarıda numarası yazılı dosyada …/…/20… tarihinde karar verilmiş '
        've gerekçeli karar yazılmıştır. Kararın kesinleşme sürecinin '
        'başlayabilmesi için gerekçeli kararın taraflara tebliğe '
        'çıkarılması gerekmektedir.',
      ),
      _head('Sonuç ve İstem'),
      _body(
        'Yukarıda açıklanan nedenlerle gerekçeli kararın taraflara tebliğe '
        'çıkarılmasına, tebliğ giderlerinin yatırılmış gider avansından '
        'karşılanmasına, avansın yetersiz olması hâlinde tarafımıza '
        'bildirilmesine karar verilmesini saygılarımızla arz ve talep '
        'ederiz.',
      ),
      ..._signature(c, today, side.clientWord),
    ]);
  }),
  PetitionTemplate('Karar', 'Kesinleşme şerhi talebi', (c, today) {
    final side = _side(c);
    return _page([
      _court(_courtLine(c, '[…] MAHKEMESİ’NE')),
      _blank(),
      _field('Dosya No', _number(c)),
      _field('Karar No', '20…/… Karar'),
      _field('Talep Eden', '[Müvekkil Ad Soyad]'),
      _field(side.counsel, _lawyerOf(c)),
      _field(
        'Konu',
        'Kararın kesinleştiğine dair şerh verilmesi '
            'talebimizdir.',
      ),
      _blank(),
      _head('Açıklamalar'),
      _body(
        'Yukarıda numarası yazılı dosyada verilen …/…/20… tarihli karar '
        'taraflara usulüne uygun olarak tebliğ edilmiş, yasal süresi içinde '
        'kanun yoluna başvurulmamış ve karar kesinleşmiştir.',
      ),
      _head('Sonuç ve İstem'),
      _body(
        'Yukarıda açıklanan nedenlerle karara kesinleşme şerhi verilmesine '
        've şerhli bir örneğinin tarafımıza UYAP üzerinden gönderilmesine '
        'karar verilmesini saygılarımızla arz ve talep ederiz.',
      ),
      ..._signature(c, today, side.clientWord),
    ]);
  }),
  // Enforcement.
  PetitionTemplate(
    'İcra',
    'Ödeme emrine itiraz',
    (c, today) => _page([
      _court(
        c == null || !trLower(c.court).contains('icra')
            ? '[…] İCRA DAİRESİ MÜDÜRLÜĞÜ’NE'
            : courtTo(c.court),
      ),
      _blank(),
      _field('Dosya No', _number(c)),
      _field('İtiraz Eden', '${c?.of(['borçlu']) ?? '[Ad Soyad]'} (Borçlu)'),
      _field('Vekili', _lawyerOf(c)),
      _field('Alacaklı', c?.of(['alacaklı']) ?? '[Ad Soyad / Unvan]'),
      _field('Tebliğ Tarihi', '…/…/20…'),
      _field('Konu', 'Ödeme emrine itirazlarımızın sunulmasıdır.'),
      _blank(),
      _head('Açıklamalar'),
      _body(
        'Müvekkile …/…/20… tarihinde tebliğ edilen ödeme emrine, İİK m.62 '
        'uyarınca yedi günlük yasal süresi içinde itiraz ediyoruz.',
      ),
      _point(
        '1- Müvekkilin alacaklıya herhangi bir borcu bulunmamaktadır. '
        'Borcun tamamına itiraz ediyoruz.',
      ),
      _point(
        '2- Talep edilen faize, faiz oranına, faizin başlangıç tarihine, '
        'işlemiş faize ve tüm ferilere ayrıca itiraz ediyoruz.',
      ),
      _point('3- Takibe dayanak belgedeki imzaya itiraz […]'),
      _head('Sonuç ve İstem'),
      _body(
        'Yukarıda açıklanan nedenlerle borca, faize ve tüm ferilerine '
        'itirazımızın kabulü ile takibin DURDURULMASINA karar verilmesini '
        'saygılarımızla vekâleten arz ve talep ederiz.',
      ),
      ..._signature(
        c,
        today,
        'Borçlu Vekili',
        attachments: ['Vekâletname örneği'],
      ),
    ]),
  ),
  // Any file.
  PetitionTemplate('Genel', 'Vekâletname sunma ve dosyaya katılma', (c, today) {
    final side = _side(c);
    return _page([
      _court(_courtLine(c, '[…] MAHKEMESİ’NE')),
      _blank(),
      _field('Dosya No', _number(c)),
      _field(
        side.counsel == 'MÜDAFİİ' ? 'Sanık' : 'Müvekkil',
        '[Ad Soyad] (TCKN: […])',
      ),
      _field(side.counsel, _lawyerOf(c)),
      _field(
        'Konu',
        'Vekâletnamenin sunulması ve dosyaya katılma '
            'talebimizdir.',
      ),
      _blank(),
      _head('Açıklamalar'),
      _body(
        'Yukarıda numarası yazılı dosyada ${side.counsel == 'MÜDAFİİ' ? 'sanık müdafii' : 'vekil'} '
        'olarak görev üstlenmiş bulunmaktayız. Vekâletnamemiz ekte '
        'sunulmuştur.',
      ),
      _head('Sonuç ve İstem'),
      _body(
        'Vekâletnamemizin kabulü ile dosyanın UYAP üzerinden tarafımıza '
        'erişime açılmasına, bundan sonraki tebligatların büromuza '
        'yapılmasına karar verilmesini saygılarımızla arz ve talep ederiz.',
      ),
      ..._signature(
        c,
        today,
        side.clientWord,
        attachments: ['Vekâletname örneği'],
      ),
    ]);
  }),
];

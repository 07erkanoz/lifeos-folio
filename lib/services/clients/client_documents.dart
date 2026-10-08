import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/document_model.dart';
import '../editor/lawyer_profile.dart';
import '../udf/udf_writer.dart';
import 'client.dart';
import 'client_accounts.dart';

/// The papers made for a client, filled from what Folio keeps, written as
/// UDF and opened in the editor to be read over and changed before they
/// are printed and signed: the fee agreement (on the bar's form the lawyer
/// gave), a payment's receipt, a case's release.

String _two(int v) => v.toString().padLeft(2, '0');
String _day(DateTime t) => '${_two(t.day)}.${_two(t.month)}.${t.year}';
String _time(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';
const _blank = '………………………';

/// A paragraph from text with **bold** parts.
DocBlock _p(
  String text, {
  DocAlignment align = DocAlignment.justify,
  bool indent = false,
  double after = 6,
  double? size,
}) {
  final plain = StringBuffer();
  final spans = <DocSpan>[];
  final parts = text.split('**');
  for (var i = 0; i < parts.length; i++) {
    if (i.isOdd && parts[i].isNotEmpty) {
      spans.add(
        DocSpan(
          startOffset: plain.length,
          length: parts[i].length,
          bold: true,
          fontSize: size,
        ),
      );
    } else if (size != null && parts[i].isNotEmpty) {
      spans.add(
        DocSpan(
          startOffset: plain.length,
          length: parts[i].length,
          fontSize: size,
        ),
      );
    }
    plain.write(parts[i]);
  }
  return DocBlock(
    plainText: plain.toString(),
    spans: spans,
    alignment: align,
    firstLineIndent: indent ? 35 : 0,
    spacingAfter: after,
  );
}

DocBlock _title(String text) =>
    _p('**$text**', align: DocAlignment.center, after: 14, size: 14);

DocBlock _gap() => DocBlock(plainText: '');

/// The two who sign, side by side: a table with no lines.
DocBlock _signatures(
  String left,
  String leftName,
  String right,
  String rightName,
) {
  DocTableCell cell(String who, String name) => DocTableCell(
    blocks: [
      _p('**$who**', align: DocAlignment.center, after: 2),
      _p(name, align: DocAlignment.center, after: 40),
      _p('İmza', align: DocAlignment.center),
    ],
  );
  return DocBlock(
    type: DocBlockType.table,
    plainText: '',
    table: DocTable(
      bordered: false,
      rows: [
        DocTableRow(cells: [cell(left, leftName), cell(right, rightName)]),
      ],
    ),
  );
}

DocModel _model(List<DocBlock> blocks) => DocModel(
  pageProperties: const DocPageProperties(
    marginTop: 56,
    marginBottom: 56,
    marginLeft: 70,
    marginRight: 56,
  ),
  blocks: blocks,
);

/// "onbeş bin" — an amount in words, as a receipt writes it beside the
/// figure: "15.000 TL (on beş bin Türk lirası)".
String inWords(int kurus) {
  const ones = [
    '',
    'bir',
    'iki',
    'üç',
    'dört',
    'beş',
    'altı',
    'yedi',
    'sekiz',
    'dokuz',
  ];
  const tens = [
    '',
    'on',
    'yirmi',
    'otuz',
    'kırk',
    'elli',
    'altmış',
    'yetmiş',
    'seksen',
    'doksan',
  ];
  String hundreds(int n) {
    final h = n ~/ 100, t = (n % 100) ~/ 10, o = n % 10;
    return [
      if (h > 0) h == 1 ? 'yüz' : '${ones[h]} yüz',
      if (t > 0) tens[t],
      if (o > 0) ones[o],
    ].join(' ');
  }

  String whole(int n) {
    if (n == 0) return 'sıfır';
    const groups = ['', 'bin', 'milyon', 'milyar'];
    final words = <String>[];
    var g = 0;
    while (n > 0 && g < groups.length) {
      final part = n % 1000;
      if (part > 0) {
        // "bin", not "bir bin".
        final said = g == 1 && part == 1 ? '' : hundreds(part);
        words.insert(0, [said, groups[g]].where((w) => w.isNotEmpty).join(' '));
      }
      n ~/= 1000;
      g++;
    }
    return words.join(' ');
  }

  final lira = kurus.abs() ~/ 100, cents = kurus.abs() % 100;
  return '${whole(lira)} Türk lirası'
      '${cents == 0 ? '' : ' ${whole(cents)} kuruş'}';
}

/// The fee agreement, on the form of the bar the lawyer gave (Avukatlık
/// Kanunu m.163–164): the parties, the work, the fee and its payment from
/// what was agreed in Folio; what Folio does not know left to be filled.
DocModel feeAgreementDocument({
  required Client client,
  required LawyerProfile profile,
  required String lawyer,
  required String work,
  ClientRecord? fee,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final account = fee == null ? null : CaseAccount('', fee, const []);
  final fixed = account?.feeAgreed ?? 0;
  final share = account?.feeShare ?? 0;
  final price = [
    if (fixed > 0) '${lira(fixed)} (${inWords(fixed)})',
    if (share > 0) 'elde edilecek sonucun %$share oranında',
  ].join(' ve ');
  final plan = account?.instalments(at) ?? const [];
  final office = profile.officeName.trim();
  final lawyerName = [
    if (lawyer.isNotEmpty) lawyer,
    if (office.isNotEmpty) office,
  ].join(' — ');
  return _model([
    _title('AVUKATLIK ÜCRET SÖZLEŞMESİ'),
    _p('**İŞ SAHİBİ**', after: 2),
    _p('**Adı/soyadı (Unvanı) :** ${client.name}', after: 2),
    _p(
      '**Adres :** ${client.address.isEmpty ? _blank : client.address}',
      after: 10,
    ),
    _p('**AVUKAT/AVUKATLIK ORTAKLIĞI**', after: 2),
    _p(
      '**Adı/soyadı (Unvanı) :** ${lawyerName.isEmpty ? _blank : lawyerName}',
      after: 2,
    ),
    _p(
      '**Adres :** ${profile.address.isEmpty ? _blank : profile.address}',
      after: 12,
    ),
    _p(
      'Yukarıda adı, soyadı, (tüzel kişilerde unvanı) ile tebligata uygun '
      'adresleri belirtilen taraflar arasında bir avukatlık ücret '
      'sözleşmesi yapılmıştır.',
      indent: true,
    ),
    _p(
      'Bu sözleşmede iş sahibi (Müvekkil) ve işi üzerine alan (Avukat) '
      'olarak adlandırılmıştır.',
      indent: true,
    ),
    _p('**MADDE – 1** (Avukatın) üzerine aldığı iş, $work', indent: true),
    _p(
      '**MADDE – 2** Sözleşme konusu ${work.isEmpty ? _blank : work} '
      'dolayı avukata ${price.isEmpty ? _blank : price} ücret ödenecektir.',
      indent: true,
    ),
    _p(
      'Ücretin ödenme şekli sözleşmenin 10 nolu maddesinde '
      'düzenlenmiştir.',
      indent: true,
    ),
    _p(
      '**MADDE – 3** Tespit olunan ücret yalnız bu sözleşmede yazılı işin '
      'veya işlerin karşılığı olup, bunlar dışında kalacak takipler ve bu '
      'işle ilgi ve bağlantısı bulunsa dahi karşı taraf veya üçüncü şahıs '
      'tarafından karşılıklı dava veya ayrı dava şeklinde açılacak davalar '
      'bu sözleşme ve ücretin dışındadır.',
      indent: true,
    ),
    _p(
      'Avukatın, bu sözleşmeye göre peşin verilmesi gerekli ücret ve '
      'aşağıda yazılı gider avansını kendisine ödenmediği sürece işe '
      'başlamak zorunluluğunda değildir.',
      indent: true,
    ),
    _p(
      '**MADDE – 4** Avukat üzerine aldığı işi kanun ve bu sözleşme '
      'hükümleri uyarınca sonuna kadar takip edecektir. Avukat, verilen '
      'vekaletname ile başkasını tevkile yetkili kılınmışsa üzerine aldığı '
      'işi uygun göreceği diğer avukatları tevkil ile yetkilendirerek veya '
      'yetki belgesi düzenleyerek birlikte takip edebileceği gibi takibi '
      'tamamen onlara da bırakabilecektir.',
      indent: true,
    ),
    _p(
      'Müvekkil de avukatın yazılı iznini almak şartı ile başka avukatları '
      'işe teşrik edebilir. Bu hallerde 1136 sayılı Kanunun 171 ve 172 nci '
      'maddeleri hükmü uygulanır.',
      indent: true,
    ),
    _p(
      '**MADDE – 5** İşin yapılması için gerekli bütün vergi, resim, harç, '
      'gider avansı gibi giderler müvekkile ait olup, avukatın ilk isteminde '
      'müvekkil tarafından avukata veya merciine ödenmesi gerekir.',
      indent: true,
    ),
    _p(
      'Yukarıda sayılan giderlerin avukat tarafından yapılabilmesini '
      'sağlamak için müvekkil, giderleri karşılayacak avansı avukata '
      'zamanında vermek zorunluluğundadır. Müvekkil bu iş için avukata '
      '$_blank TL gider avansını peşin olarak verecektir.',
      indent: true,
    ),
    _p(
      'Verilen iş için yapılan tüm yolculuk giderleri, uçak, tren veya '
      'vapur birinci mevkii yataklı tarifesine göre (gidiş-dönüş), taksi ile '
      'ulaşım, iaşe gibi giderler müvekkil tarafından avukata ücretten ayrı '
      'olarak ödenecektir. Bu giderler verilmeksizin avukat seyahati yapmak '
      'zorunluluğunda değildir.',
      indent: true,
    ),
    _p(
      'Müvekkil, yolculuk giderlerinden başka avukatın yazıhanesinden ayrı '
      'kaldığı her gün için $_blank TL ödemeyi kabul etmiştir.',
      indent: true,
    ),
    _p(
      'Yargıtay, Danıştay ve Vergi Temyiz komisyonları ve Bölge Adliye '
      'Mahkemelerindeki duruşmalar ayrı ücrete tabidir. Bu takdirde '
      'yukarıda sayılan yolculuk giderlerinden başka avukata $_blank TL '
      'verilecektir. Bu paralar peşin ödenmedikçe avukat duruşmada '
      'bulunmaya zorunlu değildir.',
      indent: true,
    ),
    _p(
      '**MADDE – 6** Avukat üzerine aldığı işi haklı bir sebep olmaksızın '
      'takipten vazgeçtiği ve haklı bir sebep olmaksızın vekaletten istifa '
      'ettiği takdirde ücret isteminde bulunamaz. Peşin aldığı ücret ve sarf '
      'etmediği gider avansını ve müvekkilin verdiği belgeleri geri vermeye '
      'mecburdur.',
      indent: true,
    ),
    _p(
      'Müvekkilin bu sözleşmenin akdinden sonra vekalet vermemesi, '
      'dosyasını geri alması, avukatın yazılı iznini almadan başka '
      'avukatları teşrik etmesi veya bir başka avukata işini vermesi, '
      'istenen giderleri ödememesi, iddia veya savunma için gerekli bilgi, '
      'belge ve delilleri vermemesi, adresini değiştirdiği halde yeni '
      'adresini bildirmeyip işin takibini bu suretle imkansız hale '
      'getirmesi, dava veya alacağın takibinden kısmen veya tamamen '
      'vazgeçmesi, karşı taraf ile sulh olması veya karşı tarafı ibra '
      'etmesi veya haklı bir sebep olmaksızın avukatı azletmesi gibi işin '
      'takip ve sonuçlandırmasını her ne suretle olursa olsun engellediği '
      'durumlarda avukat sözleşmeyi haklı sebebe dayanarak bozabilir. Bu '
      'durumda müvekkilin sözleşmede belirtilen ücreti avukatın ilk '
      'isteminde derhal ve bir defada ödemesi gerekir.',
      indent: true,
    ),
    _p(
      '**MADDE – 7** Müvekkil yukarıda yazılı adresi kanuni ikametgah '
      'olarak beyan ve kabul etmiştir. Avukat tarafından bu adrese veya '
      'müvekkilin (${client.email.isEmpty ? _blank : client.email} e-mail '
      'adresine veya ${client.phone.isEmpty ? _blank : client.phone} '
      'numaralı telefon numarasına) göndereceği her türlü teknolojik '
      'yazışma usulü çerçevesindeki bütün ihbar ve tebliğleri müvekkil, '
      'şahsına yapılmış olduğunu kabul eder.',
      indent: true,
    ),
    _p(
      'Müvekkilin bu bilgilerini değiştirdiği takdirde yeni bilgilerini '
      'avukata derhal yazılı olarak bildirmek zorundadır. Yukarıdaki adres, '
      'e-mail ve telefon numarasına gönderilecek yazı, mail ve mesajların '
      'tebliğ edilmemesinden/ulaşmamasından doğacak sonuçlar sözleşmenin 6. '
      'maddesinin 2. fıkrasında yazılı olup, müvekkil bunları şimdiden '
      'kabul eder.',
      indent: true,
    ),
    _p(
      '**MADDE – 8** Bu sözleşmede açıklık bulunmayan hallerde 1136 sayılı '
      'Avukatlık Kanununun hükümleri uygulanır.',
      indent: true,
    ),
    _p(
      '**MADDE – 9** Bu sözleşmeden doğacak uyuşmazlıklarda (sözleşmenin '
      'ihlali, feshi veya geçersizliğine ilişkin uyuşmazlıklar dahil olmak '
      'üzere) Türkiye Barolar Birliği Tahkim Yönergesi yoluyla '
      'çözümlenecektir. 6100 sayılı Hukuk Muhakemeleri Kanunu ve TBB Tahkim '
      'Yönergesi uyarınca tahkim kararları kesin ve bağlayıcıdır.',
      indent: true,
    ),
    _p('**AVUKATLIK ÜCRETİNİN ÖDENME ŞEKLİ**', indent: true),
    _p(
      '**MADDE 10 –** İş bu sözleşmeye konu olan işten dolayı avukata, '
      '${plan.isEmpty ? (price.isEmpty ? _blank : '$price ödenecektir.') : '${lira(fixed)} aşağıdaki taksitlerle ödenecektir:'}',
      indent: true,
    ),
    for (final t in plan)
      _p(
        '– ${_day(t.due)} tarihinde ${lira(t.amount)}',
        indent: true,
        after: 2,
      ),
    if (share > 0 && plan.isNotEmpty)
      _p(
        'Ayrıca elde edilecek sonucun %$share oranındaki ücret, tahsil '
        'edildiğinde ödenecektir.',
        indent: true,
      ),
    if ((fee?.text('not') ?? '').isNotEmpty) _p(fee!.text('not'), indent: true),
    _gap(),
    _p('**Tarih:** ${_day(at)}', align: DocAlignment.center, after: 18),
    _signatures('MÜVEKKİL', client.name, 'AVUKAT', lawyer),
  ]);
}

/// A payment taken, the receipt to give: who paid whom, when to the
/// minute, how much in figures and words, how, for which case.
DocModel receiptDocument({
  required Client client,
  required ClientRecord movement,
  required String lawyer,
  required String caseTitle,
}) {
  final kind = movement.movement;
  final what = switch (kind) {
    MovementKind.feePaid => 'avukatlık ücreti',
    MovementKind.advanceIn => 'masraf (gider) avansı',
    MovementKind.costRepaid => 'avukatın yaptığı masrafların karşılığı',
    _ => kind?.label.toLowerCase() ?? 'ödeme',
  };
  final way = movement.text('odeme');
  return _model([
    _title('TAHSİLAT BELGESİ'),
    _p('**Ödeyen:** ${client.name}', after: 2),
    _p('**Tahsil eden:** $lawyer', after: 2),
    if (caseTitle.isNotEmpty) _p('**Dosya:** $caseTitle', after: 2),
    _p(
      '**Tarih ve saat:** ${_day(movement.at)} ${_time(movement.at)}',
      after: 2,
    ),
    _p(
      '**Tutar:** ${lira(movement.amount)} (${inWords(movement.amount)})',
      after: 2,
    ),
    _p('**Karşılığı:** $what', after: 2),
    if (way.isNotEmpty) _p('**Ödeme şekli:** $way', after: 10),
    _p(
      'Yukarıda yazılı tutar, belirtilen tarih ve saatte, yazılı karşılık '
      'olarak müvekkil tarafından ödenmiş ve tahsil edilmiştir.',
      indent: true,
    ),
    if (movement.text('aciklama').isNotEmpty)
      _p('Açıklama: ${movement.text('aciklama')}', indent: true),
    if (movement.text('makbuz').isNotEmpty)
      _p('Makbuz no: ${movement.text('makbuz')}', indent: true),
    _p(
      'İşbu belge, ödemeyi yapan ile tahsil eden arasında iki nüsha '
      'olarak düzenlenmiştir.',
      indent: true,
    ),
    _gap(),
    _signatures('ÖDEYEN', client.name, 'TAHSİL EDEN', lawyer),
  ]);
}

/// A case's release: the client tells what was paid and taken in it, and
/// releases the lawyer of it; the lawyer, of the fee. To be read over: a
/// release says what the two agree it says.
DocModel releaseDocument({
  required Client client,
  required CaseAccount account,
  required String lawyer,
  required String caseTitle,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  return _model([
    _title('İBRANAME'),
    _p(
      '**${caseTitle.isEmpty ? _blank : caseTitle}** dosyasında avukat '
      '$lawyer tarafından yürütülen iş nedeniyle müvekkil ile avukat '
      'arasındaki ücret ve masraf hesabı görülmüştür.',
      indent: true,
    ),
    _p(
      'Bu dosya için avukata ${lira(account.feeIn)} avukatlık ücreti ve '
      '${lira(account.advanceIn)} masraf avansı ödenmiş; avanstan '
      '${lira(account.advanceSpent)} masraf yapılmış, '
      '${lira(account.advanceLeft)} avans bakiyesi '
      '${account.advanceLeft > 0 ? 'tarafıma iade edilmiştir' : 'kalmamıştır'}.',
      indent: true,
    ),
    _p(
      'Dosyada karşı taraftan tahsil edilip tarafıma ödenen tutar: '
      '$_blank TL.',
      indent: true,
    ),
    _p(
      'Bu dosya nedeniyle avukatımdan herhangi bir alacağım kalmadığını, '
      'avukatımı ibra ettiğimi beyan ederim.',
      indent: true,
    ),
    _p(
      'Avukat da bu dosya nedeniyle müvekkilden ücret ve masraf alacağı '
      '${account.feeOwed > 0 || account.lawyerOwed > 0 ? 'olarak ${lira((account.feeOwed > 0 ? account.feeOwed : 0) + account.lawyerOwed)} dışında' : ''} '
      'bir alacağı kalmadığını kabul eder.',
      indent: true,
    ),
    _gap(),
    _p('**Tarih:** ${_day(at)}', align: DocAlignment.center, after: 18),
    _signatures('MÜVEKKİL', client.name, 'AVUKAT', lawyer),
  ]);
}

/// [model] written as [name].udf among the client's papers; its path, for
/// the editor to open.
Future<String> writeClientDocument(
  Directory clientsRoot,
  String clientId,
  String name,
  DocModel model,
) async {
  // A client's id from another device names no path.
  if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(clientId)) {
    throw ArgumentError('müvekkil kimliği: $clientId');
  }
  final folder = Directory(p.join(clientsRoot.path, clientId, 'belgeler'));
  await folder.create(recursive: true);
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
  var file = File(p.join(folder.path, '$safe.udf'));
  for (var i = 2; await file.exists(); i++) {
    file = File(p.join(folder.path, '$safe ($i).udf'));
  }
  await file.writeAsBytes(UdfWriter.writeBytes(model), flush: true);
  return file.path;
}

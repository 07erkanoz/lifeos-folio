import '../../models/document_model.dart';
import '../clients/client_accounts.dart';
import '../clients/client_documents.dart';
import '../editor/petition_templates.dart' show trUpper;
import '../legal/decision_insert.dart';
import 'enforcement_ledger.dart';

/// The papers an enforcement file's own account in Folio makes: the
/// request telling the office of a payment made outside it or of a claim
/// waived, and the debtor's receipt and release. Filled from UYAP's
/// particulars and the lawyer's profile, written as UDF and opened in the
/// editor to be read over, signed and sent.

String _two(int v) => v.toString().padLeft(2, '0');
String _day(DateTime t) => '${_two(t.day)}.${_two(t.month)}.${t.year}';

/// Who and what a file's papers name.
class EnforcementParties {
  const EnforcementParties({
    required this.office,
    required this.number,
    required this.creditor,
    required this.lawyer,
    this.lawyerAddress = '',
    this.debtors = const [],
  });

  /// "Manavgat İcra Dairesi"; "2026/1234".
  final String office, number;
  final String creditor, lawyer, lawyerAddress;
  final List<String> debtors;
}

/// "MANAVGAT İCRA DAİRESİ MÜDÜRLÜĞÜ'NE": the office as a request is
/// addressed to it.
String officeHeading(String office) {
  final name = office.trim();
  final folded = trUpper(name);
  final whole = folded.contains('MÜDÜRLÜĞÜ') ? folded : '$folded MÜDÜRLÜĞÜ';
  return "$whole'NE";
}

/// "DAVACI\t: …": a label and its value, the colons in one column.
DocBlock _label(String label, String value) => DocBlock(
  plainText: '$label\t: $value',
  spans: [DocSpan(startOffset: 0, length: label.length, bold: true)],
  alignment: DocAlignment.left,
  tabSet: '120.0:0',
  hanging: 128,
  spacingAfter: 4,
);

DocBlock _heading(String text) =>
    paperParagraph('**$text**', align: DocAlignment.left, after: 6);

List<DocBlock> _signature(String lawyer, DateTime at) => [
  for (final line in [
    _day(at),
    'Alacaklı Vekili',
    '**$lawyer**',
    'e-imzalıdır',
  ])
    paperParagraph(line, align: DocAlignment.right, after: 0),
];

List<DocBlock> _head(EnforcementParties p, String debtor, String subject) => [
  paperParagraph(
    '**${officeHeading(p.office)}**',
    align: DocAlignment.center,
    after: 18,
  ),
  _label('DOSYA NO', '${p.number} Esas'),
  _label('ALACAKLI', p.creditor),
  _label(
    'VEKİLİ',
    [p.lawyer, if (p.lawyerAddress.isNotEmpty) p.lawyerAddress].join(' — '),
  ),
  _label('BORÇLU', debtor.isEmpty ? p.debtors.join(', ') : debtor),
  _label('KONU', subject),
  paperGap(),
];

/// The request telling the office of a payment the debtor made outside
/// it: its sum taken off the debt and the rest followed, or, when it was
/// the whole, the file closed once the collection fee is paid.
DocModel externalPaymentRequest(
  EnforcementParties p,
  LedgerEntry e, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final sum = '${money(e.amount, Currency.tl)} (${inWords(e.amount)})';
  final debtor = e.debtor.isEmpty ? 'borçlu' : 'borçlu ${e.debtor}';
  final subject = e.whole
      ? 'Dosya borcunun tamamının haricen ödendiğinin bildirilmesi ve '
            'dosyanın kapatılması talebidir.'
      : 'Borçlunun haricen yaptığı ödemenin bildirilmesi ve dosya borcundan '
            'düşülmesi talebidir.';
  return paperModel([
    ..._head(p, e.debtor, subject),
    _heading('AÇIKLAMALAR'),
    paperParagraph(
      '1- Müdürlüğünüzün yukarıda esas numarası yazılı dosyası ile '
      '$debtor aleyhine icra takibi yapılmaktadır.',
      indent: true,
    ),
    paperParagraph(
      '2- ${debtor[0].toUpperCase()}${debtor.substring(1)}, '
      '${_day(e.at)} tarihinde dosya borcuna mahsuben tarafımıza haricen '
      '$sum ödeme yapmıştır.',
      indent: true,
    ),
    paperParagraph(
      e.whole
          ? '3- Bu ödemeyle dosya borcunun tamamı ödenmiş, müvekkilin '
                'alacağı haricen tahsil edilmiştir.'
          : '3- Haricen tahsil edilen bu tutarın ödeme tarihi itibarıyla '
                'dosya borcundan düşülmesi, bakiye alacak için takibe devam '
                'olunması gerekmektedir.',
      indent: true,
    ),
    paperGap(),
    _heading('SONUÇ VE İSTEM'),
    paperParagraph(
      e.whole
          ? 'Yukarıda açıklanan nedenlerle; dosya borcunun tamamının '
                '${_day(e.at)} tarihinde haricen ödendiğinin kabulü ile '
                'haricen tahsil harcının hesaplanarak tarafımıza '
                'bildirilmesine, harcın ödenmesinin ardından dosyanın '
                'haricen tahsil nedeniyle kapatılmasına karar verilmesini '
                'saygılarımla arz ve talep ederim.'
          : 'Yukarıda açıklanan nedenlerle; $debtor tarafından '
                '${_day(e.at)} tarihinde haricen ödenen $sum tutarın ödeme '
                'tarihi itibarıyla dosya borcundan mahsup edilerek '
                'düşülmesine, bakiye alacak için takibe devam olunmasına '
                'karar verilmesini saygılarımla arz ve talep ederim.',
      indent: true,
      after: 24,
    ),
    ..._signature(p.lawyer, at),
  ]);
}

/// The request waiving part or all of the claim, on the power to waive
/// the power of attorney gives.
DocModel waiverRequest(EnforcementParties p, LedgerEntry e, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final sum = '${money(e.amount, Currency.tl)} (${inWords(e.amount)})';
  final debtor = e.debtor.isEmpty ? 'borçlu' : 'borçlu ${e.debtor}';
  return paperModel([
    ..._head(
      p,
      e.debtor,
      e.whole
          ? 'Alacağın tamamından feragat ve dosyanın kapatılması talebidir.'
          : 'Alacağın bir kısmından feragat talebidir.',
    ),
    _heading('AÇIKLAMALAR'),
    paperParagraph(
      '1- Müdürlüğünüzün yukarıda esas numarası yazılı dosyası ile '
      '$debtor aleyhine icra takibi yapılmaktadır.',
      indent: true,
    ),
    paperParagraph(
      e.whole
          ? '2- Müvekkil adına, vekâletnamemizdeki feragat yetkisine '
                'dayanarak dosyadaki alacağımızın tamamından feragat '
                'ediyoruz.'
          : '2- Müvekkil adına, vekâletnamemizdeki feragat yetkisine '
                'dayanarak dosyadaki alacağımızın $sum tutarındaki '
                'kısmından feragat ediyoruz.',
      indent: true,
    ),
    if (e.note.isNotEmpty) paperParagraph('3- ${e.note}', indent: true),
    paperGap(),
    _heading('SONUÇ VE İSTEM'),
    paperParagraph(
      e.whole
          ? 'Yukarıda açıklanan nedenlerle; alacağın tamamından '
                'feragatimizin kabulü ile feragat nedeniyle doğan harcın '
                'hesaplanmasına ve dosyanın feragat nedeniyle kapatılmasına '
                'karar verilmesini saygılarımla arz ve talep ederim.'
          : 'Yukarıda açıklanan nedenlerle; $sum tutarındaki feragatimizin '
                'kabulü ile bu tutarın dosya alacağından düşülmesine, '
                'bakiye alacak için takibe devam olunmasına karar '
                'verilmesini saygılarımla arz ve talep ederim.',
      indent: true,
      after: 24,
    ),
    ..._signature(p.lawyer, at),
  ]);
}

/// The debtor's receipt for a payment made outside the office, releasing
/// them of as much as they paid, or of the whole debt when it was all.
DocModel debtorReceipt(EnforcementParties p, LedgerEntry e, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final sum = '${money(e.amount, Currency.tl)} (${inWords(e.amount)})';
  final debtor = e.debtor.isEmpty ? '………………………' : e.debtor;
  final how = switch (e.way) {
    'Nakit' => ' nakden',
    '' => '',
    final w => ' ($w ile)',
  };
  return paperModel([
    paperTitle(
      e.whole
          ? 'TAHSİLAT MAKBUZU VE İBRANAME'
          : 'TAHSİLAT MAKBUZU VE KISMİ İBRANAME',
    ),
    paperParagraph(
      '**Dosya:** ${p.office} ${p.number} Esas',
      after: 2,
      align: DocAlignment.left,
    ),
    paperParagraph(
      '**Alacaklı:** ${p.creditor}',
      after: 2,
      align: DocAlignment.left,
    ),
    paperParagraph('**Borçlu:** $debtor', after: 2, align: DocAlignment.left),
    paperParagraph(
      '**Ödeme tarihi:** ${_day(e.at)}',
      after: 2,
      align: DocAlignment.left,
    ),
    paperParagraph('**Tutar:** $sum', after: 12, align: DocAlignment.left),
    paperParagraph(
      "${DecisionInsert.genitive(p.office)} ${p.number} Esas sayılı "
      'dosyasında alacaklı ${p.creditor} vekili olarak, borçlu $debtor '
      'tarafından ${_day(e.at)} tarihinde dosya borcuna mahsuben$how '
      'ödenen $sum tarafımca tahsil edilmiştir.',
      indent: true,
    ),
    paperParagraph(
      e.whole
          ? 'Bu ödemeyle dosya borcunun tamamı ödenmiş olup borçlu, dosya '
                'borcundan tamamen ibra edilmiştir. Ödeme icra dairesine '
                'haricen tahsil olarak bildirilerek dosyanın kapatılması '
                'istenecektir.'
          : 'Borçlu, ödediği $sum tutar kadar dosya borcundan ibra '
                'edilmiştir. Bakiye borç için takibe devam olunacak; ödeme '
                'icra dairesine haricen tahsil olarak bildirilecektir.',
      indent: true,
    ),
    paperGap(),
    paperParagraph(
      '**Tarih:** ${_day(at)}',
      align: DocAlignment.center,
      after: 18,
    ),
    paperSignatures('ÖDEYEN (BORÇLU)', debtor, 'TAHSİL EDEN', p.lawyer),
  ]);
}

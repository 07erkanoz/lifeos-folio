import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../fonts/document_fonts.dart';
import 'client.dart';
import 'client_accounts.dart';

/// A client's statement, to give them (docs/design/muvekkil-taslak): each
/// case's fee agreed and instalments, every movement with the minute the
/// money changed hands, a corrected one marked so, and what is owed and
/// held. [cases] gives each case's title; one case alone when [only].
Future<Uint8List> clientStatementPdf({
  required Client client,
  required List<ClientRecord> records,
  required Map<String, String> cases,
  required String lawyer,
  String? only,
  DateTime? now,
  ByteData? regular,
  ByteData? bold,
}) async {
  final at = now ?? DateTime.now();
  final font = pw.Font.ttf(
    regular ?? await DocumentFonts.loadFace('Times New Roman', 'Regular'),
  );
  final strong = pw.Font.ttf(
    bold ?? await DocumentFonts.loadFace('Times New Roman', 'Bold'),
  );
  String two(int v) => v.toString().padLeft(2, '0');
  String day(DateTime t) => '${two(t.day)}.${two(t.month)}.${t.year}';
  String time(DateTime t) => '${two(t.hour)}:${two(t.minute)}';
  final base = pw.TextStyle(font: font, fontSize: 10);
  final head = pw.TextStyle(font: strong, fontSize: 10);
  final accounts = caseAccounts(records);
  final keys = [
    for (final k in [...cases.keys, if (accounts.containsKey('')) ''])
      if (only == null || k == only)
        if (accounts.containsKey(k)) k,
  ];

  pw.Widget line(String label, String value, {bool strongValue = false}) =>
      pw.Row(
        children: [
          pw.Expanded(child: pw.Text(label, style: base)),
          pw.Text(value, style: strongValue ? head : base),
        ],
      );

  List<pw.Widget> account(String key) {
    final a = accounts[key]!;
    final plan = a.instalments(at);
    final agreed = [
      if (a.feeAgreed > 0) 'Sabit ${lira(a.feeAgreed)}',
      if (a.feeShare > 0) 'sonuçtan %${a.feeShare}',
    ].join(' + ');
    return [
      pw.SizedBox(height: 14),
      pw.Text(
        key.isEmpty ? 'Dosyasız' : cases[key] ?? key,
        style: head.copyWith(fontSize: 11.5),
      ),
      pw.SizedBox(height: 4),
      line('Ücret anlaşması', agreed.isEmpty ? 'yok' : agreed),
      for (final t in plan)
        line(
          '   Taksit ${day(t.due)}',
          '${lira(t.amount)} · ${t.paid
              ? 'ödendi'
              : t.late
              ? 'gecikti'
              : 'bekleniyor'}',
        ),
      pw.SizedBox(height: 6),
      pw.TableHelper.fromTextArray(
        border: const pw.TableBorder(
          horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: .5),
          bottom: pw.BorderSide(color: PdfColors.grey500, width: .5),
          top: pw.BorderSide(color: PdfColors.grey500, width: .5),
        ),
        headerStyle: head,
        cellStyle: base,
        headerAlignment: pw.Alignment.centerLeft,
        cellAlignments: {3: pw.Alignment.centerRight},
        columnWidths: {
          0: const pw.FixedColumnWidth(96),
          1: const pw.FlexColumnWidth(3),
          2: const pw.FlexColumnWidth(2),
          3: const pw.FixedColumnWidth(80),
        },
        headers: ['Tarih ve saat', 'Açıklama', 'Hesap', 'Tutar'],
        data: [
          for (final m in a.movements.reversed)
            [
              '${day(m.at)} ${time(m.at)}',
              [
                if (m.reverses.isNotEmpty) 'Düzeltme:',
                if (m.text('aciklama').isNotEmpty) m.text('aciklama'),
                if (m.text('makbuz').isNotEmpty) '(makbuz ${m.text('makbuz')})',
                if (a.reversed.contains(m.id)) '(düzeltildi)',
              ].join(' '),
              m.movement?.label ?? '',
              '${(m.movement?.sign ?? 1) * (m.reverses.isEmpty ? 1 : -1) > 0 ? '+' : '−'}'
                  '${lira(m.amount)}',
            ],
        ],
      ),
      pw.SizedBox(height: 6),
      line('Ödenen ücret', lira(a.feeIn)),
      if (a.feeAgreed > 0)
        line('Kalan ücret', lira(a.feeOwed), strongValue: true),
      line('Avans bakiyesi', lira(a.advanceLeft), strongValue: true),
      if (a.lawyerOwed != 0)
        line(
          'Avukatın yaptığı, ödenmemiş masraf',
          lira(a.lawyerOwed),
          strongValue: true,
        ),
    ];
  }

  final doc = pw.Document(title: 'Müvekkil hesap dökümü');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 48, 48, 40),
      footer: (context) => pw.Text(
        '${day(at)} ${time(at)} tarihinde alınmıştır · '
        'sayfa ${context.pageNumber}/${context.pagesCount}',
        style: base.copyWith(fontSize: 8, color: PdfColors.grey700),
      ),
      build: (context) => [
        pw.Center(
          child: pw.Text(
            'MÜVEKKİL HESAP DÖKÜMÜ',
            style: head.copyWith(fontSize: 14),
          ),
        ),
        pw.SizedBox(height: 12),
        line('Müvekkil', client.name),
        line('Avukat', lawyer),
        line('Tarih', day(at)),
        if (keys.isEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Text('Hesap hareketi yok.', style: base),
        ],
        for (final k in keys) ...account(k),
      ],
    ),
  );
  return doc.save();
}

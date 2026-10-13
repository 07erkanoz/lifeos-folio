import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart' as xl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../fonts/document_fonts.dart';
import 'client_accounts.dart';
import 'office_cash.dart';

String _two(int v) => v.toString().padLeft(2, '0');
String _day(DateTime t) => '${_two(t.day)}.${_two(t.month)}.${t.year}';
String _time(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

const monthNames = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

/// [lines] as a workbook, for the accountant: one row a line, the amounts
/// as numbers in the line's own currency, named beside them. [caseTitle] names a case by its key.
Future<Uint8List> cashWorkbook(
  List<CashLine> lines,
  String Function(String caseKey) caseTitle,
) async {
  final book = xl.Excel.createExcel();
  final first = book.getDefaultSheet() ?? 'Sheet1';
  book.rename(first, 'Kasa');
  final sheet = book['Kasa'];
  xl.CellValue text(String v) => xl.TextCellValue(v);
  xl.CellValue? money(int kurus) =>
      kurus == 0 ? null : xl.DoubleCellValue(kurus / 100);
  sheet.appendRow([
    for (final h in [
      'Tarih',
      'Saat',
      'Tür',
      'Kategori',
      'Açıklama',
      'Müvekkil',
      'Dosya',
      'Ödeme',
      'Para birimi',
      'Giriş',
      'Çıkış',
      'Düzeltme',
    ])
      text(h),
  ]);
  for (final l in lines) {
    sheet.appendRow([
      text(_day(l.at)),
      text(_time(l.at)),
      text(l.side.label),
      text(l.category),
      text(l.title),
      text(l.client),
      text(l.caseKey.isEmpty ? '' : caseTitle(l.caseKey)),
      text(l.way),
      text(l.currency.code),
      money(l.amount > 0 ? l.amount : 0),
      money(l.amount < 0 ? -l.amount : 0),
      text(l.struck ? 'ters kayıtla düzeltildi' : ''),
    ]);
  }
  return Uint8List.fromList(await book.encodeAsync() ?? const []);
}

/// The year's report: each month's income and expense, the expenses by
/// kind, what the clients owe and what is held for them; each currency
/// apart.
Future<Uint8List> cashReportPdf({
  required int year,
  required List<CashLine> lines,
  required List<ClientBalance> balances,
  required String lawyer,
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  final font = pw.Font.ttf(
    await DocumentFonts.loadFace('Times New Roman', 'Regular'),
  );
  final strong = pw.Font.ttf(
    await DocumentFonts.loadFace('Times New Roman', 'Bold'),
  );
  final base = pw.TextStyle(font: font, fontSize: 10);
  final head = pw.TextStyle(font: strong, fontSize: 10);
  final title = pw.TextStyle(font: strong, fontSize: 14);
  final ofYear = [
    for (final l in lines)
      if (l.at.year == year) l,
  ];
  pw.Widget row(List<String> cells, {bool bold = false}) => pw.Row(
    children: [
      for (var i = 0; i < cells.length; i++)
        pw.Expanded(
          flex: i == 0 ? 3 : 2,
          child: pw.Text(
            cells[i],
            textAlign: i == 0 ? pw.TextAlign.left : pw.TextAlign.right,
            style: bold ? head : base,
          ),
        ),
    ],
  );
  List<pw.Widget> part(Currency c) {
    final mine = [
      for (final l in ofYear)
        if (l.currency == c) l,
    ];
    final total = cashTotals(mine);
    final categories = <String, int>{};
    for (final l in mine) {
      if (l.side == CashSide.expense) {
        final k = l.category.isEmpty ? 'Diğer' : l.category;
        categories[k] = (categories[k] ?? 0) - l.amount;
      }
    }
    String m(int v) => money(v, c);
    return [
      pw.Text(c == Currency.tl ? 'TL' : c.label, style: head),
      pw.SizedBox(height: 4),
      row(['', 'Gelir', 'Gider', 'Net'], bold: true),
      pw.Divider(thickness: .5),
      for (var n = 1; n <= 12; n++)
        if (cashTotals([
              for (final l in mine)
                if (l.at.month == n) l,
            ])
            case final t)
          row([monthNames[n - 1], m(t.income), m(t.expense), m(t.net)]),
      pw.Divider(thickness: .5),
      row(['Yıl', m(total.income), m(total.expense), m(total.net)], bold: true),
      if (categories.isNotEmpty) ...[
        pw.SizedBox(height: 10),
        pw.Text('Giderler', style: head),
        pw.SizedBox(height: 4),
        for (final e
            in categories.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
          row([e.key, m(e.value)]),
      ],
      pw.SizedBox(height: 18),
    ];
  }

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => [
        pw.Text('Kasa raporu · $year', style: title),
        pw.SizedBox(height: 4),
        pw.Text('$lawyer · ${_day(at)} ${_time(at)}', style: base),
        pw.SizedBox(height: 14),
        for (final c in cashCurrencies(ofYear)) ...part(c),
        pw.Text('Müvekkil alacakları, masrafları ve emanet', style: head),
        pw.SizedBox(height: 4),
        row(['Müvekkil', 'Ücret alacağı', 'Masraf', 'Emanet'], bold: true),
        for (final b in balances)
          row([b.name, b.owed.text, b.costs.text, b.held.text]),
        pw.SizedBox(height: 12),
        pw.Text(
          'Emanet, müvekkil adına tutulan paradır; büronun geliri sayılmaz. '
          'Her para birimi ayrı toplanır, birbirine çevrilmez.',
          style: base,
        ),
      ],
    ),
  );
  return doc.save();
}

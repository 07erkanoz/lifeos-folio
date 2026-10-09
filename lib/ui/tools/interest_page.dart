import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/document_model.dart';
import '../../services/clients/client_accounts.dart' show kurusOf, lira;
import '../../services/fonts/document_fonts.dart';
import '../../services/legal/interest.dart';
import '../../services/platform/rich_clipboard.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../clients/attachment_preview.dart';
import '../widgets/notice.dart';

String _two(int v) => v.toString().padLeft(2, '0');
String _day(DateTime t) => '${_two(t.day)}.${_two(t.month)}.${t.year}';

/// "%24" or "%39,75".
String _rate(double r) =>
    '%${r == r.roundToDouble() ? r.toInt() : r.toStringAsFixed(2).replaceAll('.', ',')}';

/// "250.000,00": the reckoning's own figures, to the kuruş.
String _money(int kurus) {
  final s = lira(kurus.abs()).replaceAll(' TL', '');
  final whole = s.contains(',') ? s : '$s,00';
  return '${kurus < 0 ? '−' : ''}$whole';
}

/// Interest reckoned (3095; TBK m.100): a kind, a principal, its days and
/// the payments made; each stretch at its own rate, ready to copy into a
/// petition or to print.
class InterestPage extends StatefulWidget {
  const InterestPage({
    super.key,
    this.rates,
    this.title,
    this.principal,
    this.from,
    this.to,
  });

  /// What to begin with: the principal (kuruş) and the days.
  final int? principal;
  final DateTime? from, to;

  /// The rates; read from the app's data when not given.
  final InterestRates? rates;

  /// What the reckoning is for ("2024/318 · Ayşe Karaca"), written above it.
  final String? title;

  /// The page on its own, with its bar.
  static Future<void> open(
    BuildContext context, {
    String? title,
    int? principal,
    DateTime? from,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Faiz hesabı')),
        body: InterestPage(title: title, principal: principal, from: from),
      ),
    ),
  );

  @override
  State<InterestPage> createState() => _InterestPageState();
}

class _InterestPageState extends State<InterestPage> {
  InterestRates? _rates;
  InterestKind _kind = InterestKind.legal;
  late final _principal = TextEditingController(
    text: widget.principal == null
        ? ''
        : _money(widget.principal!).replaceAll(RegExp(r',00$'), ''),
  );
  final _fixed = TextEditingController();
  late final _for = TextEditingController(text: widget.title ?? '');
  late DateTime? _from = widget.from;
  late DateTime _to = widget.to ?? DateTime.now();
  final _payments = <({DateTime day, int amount})>[];

  @override
  void initState() {
    super.initState();
    _rates = widget.rates;
    if (_rates == null) {
      unawaited(
        InterestRates.load().then((r) {
          if (mounted) setState(() => _rates = r);
        }),
      );
    }
  }

  @override
  void dispose() {
    _principal.dispose();
    _fixed.dispose();
    _for.dispose();
    super.dispose();
  }

  InterestResult? get _result {
    final rates = _rates, from = _from;
    final principal = kurusOf(_principal.text);
    if (rates == null || from == null || principal == null || principal <= 0) {
      return null;
    }
    if (!_to.isAfter(from)) return null;
    final fixed = double.tryParse(_fixed.text.replaceAll(',', '.')) ?? 0;
    if (_kind == InterestKind.fixed && fixed <= 0) return null;
    return reckon(
      rates: rates,
      kind: _kind,
      principal: principal,
      from: from,
      to: _to,
      fixedRate: fixed,
      payments: _payments,
    );
  }

  Future<DateTime?> _pick(DateTime? at) => showDatePicker(
    context: context,
    initialDate: at ?? DateTime.now(),
    firstDate: DateTime(1985),
    lastDate: DateTime(DateTime.now().year + 5),
  );

  Future<void> _addPayment() async {
    final day = await _pick(_from);
    if (day == null || !mounted) return;
    final amount = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Ödeme · ${_day(day)}'),
        content: TextField(
          key: const ValueKey('interest-payment-amount'),
          controller: amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Tutar',
            suffixText: 'TL',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
    final kurus = kurusOf(amount.text);
    // Disposed after the dialog's closing frame has used it.
    WidgetsBinding.instance.addPostFrameCallback((_) => amount.dispose());
    if (ok != true || kurus == null || kurus <= 0) return;
    setState(() {
      _payments.add((day: day, amount: kurus));
      _payments.sort((a, b) => a.day.compareTo(b.day));
    });
  }

  String get _heading => [
    'Faiz hesabı',
    if (_for.text.trim().isNotEmpty) _for.text.trim(),
  ].join(' · ');

  List<List<String>> _table(InterestResult r) => [
    ['Dönem', 'Gün', 'Oran', 'Anapara', 'Faiz', 'Açıklama'],
    for (final row in r.rows)
      row.isPayment
          ? [
              _day(row.from),
              '',
              '',
              '',
              '',
              'Ödeme ${_money(row.payment)} TL: ${_money(row.toInterest)} faize, '
                  '${_money(row.toPrincipal)} anaparaya',
            ]
          : [
              '${_day(row.from)} – ${_day(row.to!)}',
              '${row.days}',
              _rate(row.rate),
              _money(row.principal),
              _money(row.interest),
              row.basis,
            ],
  ];

  String _summary(InterestResult r) => [
    _heading,
    '${_kind.label}; asıl alacak ${_money(kurusOf(_principal.text) ?? 0)} TL; '
        '${_day(_from!)} – ${_day(_to)}',
    'İşlemiş faiz: ${_money(r.accrued)} TL',
    if (r.accrued != r.interestLeft) 'Kalan faiz: ${_money(r.interestLeft)} TL',
    'Kalan anapara: ${_money(r.principalLeft)} TL',
    'Toplam alacak: ${_money(r.total)} TL',
  ].join('\n');

  Future<void> _copy(InterestResult r) async {
    DocBlock p(String text, {bool bold = false}) => DocBlock(
      plainText: text,
      spans: [
        if (bold && text.isNotEmpty)
          DocSpan(startOffset: 0, length: text.length, bold: true),
      ],
    );
    final table = _table(r);
    final model = DocModel(
      blocks: [
        for (final line in _summary(r).split('\n')) p(line),
        DocBlock(
          type: DocBlockType.table,
          plainText: '',
          table: DocTable(
            rows: [
              for (final (i, cells) in table.indexed)
                DocTableRow(
                  isHeader: i == 0,
                  cells: [
                    for (final c in cells)
                      DocTableCell(blocks: [p(c, bold: i == 0)]),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
    final text = [
      _summary(r),
      '',
      for (final cells in table) cells.join('\t'),
    ].join('\n');
    await RichClipboard.write(model, text);
    if (mounted) {
      showNotice(
        context,
        'Hesap kopyalandı.',
        detail:
            'Dilekçeye ya da Word\'e yapıştırabilirsiniz; tablo olarak gelir.',
      );
    }
  }

  Future<Uint8List> _pdf(InterestResult r) async {
    final font = pw.Font.ttf(
      await DocumentFonts.loadFace('Times New Roman', 'Regular'),
    );
    final bold = pw.Font.ttf(
      await DocumentFonts.loadFace('Times New Roman', 'Bold'),
    );
    final table = _table(r);
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => [
          for (final (i, line) in _summary(r).split('\n').indexed)
            pw.Text(
              line,
              style: pw.TextStyle(
                font: i == 0 ? bold : font,
                fontSize: i == 0 ? 13 : 10.5,
              ),
            ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: table.first,
            data: table.sublist(1),
            headerStyle: pw.TextStyle(font: bold, fontSize: 9.5),
            cellStyle: pw.TextStyle(font: font, fontSize: 9.5),
            cellAlignments: {
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Faiz her gün o gün geçerli oranla, yıl 365 gün sayılarak '
            'hesaplanmıştır. Ödemeler önce işlemiş faize, sonra anaparaya '
            'mahsup edilmiştir (TBK m.100); faize faiz yürütülmemiştir.',
            style: pw.TextStyle(font: font, fontSize: 9),
          ),
        ],
      ),
    );
    return doc.save();
  }

  @override
  Widget build(BuildContext context) {
    final rates = _rates;
    if (rates == null) return const Center(child: CircularProgressIndicator());
    final r = _result;
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 860;
        final form = _form();
        final out = _out(r, rates);
        return SingleChildScrollView(
          padding: EdgeInsets.all(wide ? 16 : 10),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 380, child: form),
                    const SizedBox(width: 12),
                    Expanded(child: out),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [form, const SizedBox(height: 10), out],
                ),
        );
      },
    );
  }

  Widget _frame(Widget child) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AgendaColors.line),
    ),
    child: child,
  );

  Widget _form() {
    Widget dateField(
      String label,
      DateTime? value,
      ValueChanged<DateTime> on,
    ) => Expanded(
      child: InkWell(
        onTap: () async {
          final d = await _pick(value);
          if (d != null) setState(() => on(d));
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, isDense: true),
          child: Text(value == null ? 'seçin' : _day(value)),
        ),
      ),
    );
    return _frame(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in InterestKind.values)
                ChoiceChip(
                  key: ValueKey('interest-kind-${k.code}'),
                  label: Text(switch (k) {
                    InterestKind.legal => 'Kanuni',
                    InterestKind.commercial => 'Ticari (avans)',
                    InterestKind.fixed => 'Sözleşme',
                  }),
                  selected: _kind == k,
                  onSelected: (_) => setState(() => _kind = k),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(switch (_kind) {
            InterestKind.legal =>
              '3095 s.K. m.1 · 31.07.2026\'dan beri TCMB '
                  'reeskont oranının %80\'i',
            InterestKind.commercial =>
              '3095 s.K. m.2/2 · TCMB avans oranı; '
                  'kanuni faizden az olamaz',
            InterestKind.fixed => 'Taraflarca kararlaştırılan yıllık oran',
          }, style: const TextStyle(fontSize: 12, color: AgendaColors.muted)),
          if (_kind == InterestKind.fixed) ...[
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('interest-fixed'),
              controller: _fixed,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Yıllık oran',
                prefixText: '% ',
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('interest-principal'),
            controller: _principal,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Asıl alacak',
              suffixText: 'TL',
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              dateField('Başlangıç (temerrüt)', _from, (d) => _from = d),
              const SizedBox(width: 8),
              dateField('Bitiş (o güne kadar)', _to, (d) => _to = d),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Kısmi ödemeler · önce faize, sonra anaparaya (TBK m.100)',
            style: TextStyle(fontSize: 12, color: AgendaColors.muted),
          ),
          for (final (i, pay) in _payments.indexed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${_day(pay.day)} · ${_money(pay.amount)} TL'),
              trailing: IconButton(
                tooltip: 'Kaldır',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() => _payments.removeAt(i)),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('interest-add-payment'),
              onPressed: _addPayment,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Ödeme ekle'),
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _for,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Ne için (dosya, müvekkil; çıktıda yazılır)',
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _out(InterestResult? r, InterestRates rates) {
    if (r == null) {
      return _frame(
        const Text(
          'Asıl alacağı ve başlangıç gününü yazın; hesap kendiliğinden '
          'yapılır.',
          style: TextStyle(color: AgendaColors.muted),
        ),
      );
    }
    Widget big(String label, int v, {Color? color}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
        ),
        Text(
          '${_money(v)} TL',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
    const head = TextStyle(fontSize: 11, color: AgendaColors.muted);
    const cell = TextStyle(fontSize: 12.5);
    final verified = rates.verified;
    return _frame(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 28,
            runSpacing: 10,
            children: [
              big('İşlemiş faiz', r.accrued, color: AgendaColors.deadlineText),
              if (r.interestLeft != r.accrued)
                big('Kalan faiz', r.interestLeft),
              big('Kalan anapara', r.principalLeft),
              big('Toplam alacak', r.total),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('interest-copy'),
                onPressed: () => _copy(r),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Kopyala'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('interest-pdf'),
                onPressed: () => showClientAttachment(
                  context,
                  title: 'Faiz hesabı',
                  fileName: 'Faiz hesabı.pdf',
                  pdf: () => _pdf(r),
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 32,
              dataRowMinHeight: 30,
              dataRowMaxHeight: 44,
              columnSpacing: 18,
              horizontalMargin: 4,
              columns: const [
                DataColumn(label: Text('Dönem', style: head)),
                DataColumn(label: Text('Gün', style: head), numeric: true),
                DataColumn(label: Text('Oran', style: head), numeric: true),
                DataColumn(label: Text('Anapara', style: head), numeric: true),
                DataColumn(label: Text('Faiz', style: head), numeric: true),
                DataColumn(label: Text('Açıklama', style: head)),
              ],
              rows: [
                for (final row in r.rows)
                  row.isPayment
                      ? DataRow(
                          color: const WidgetStatePropertyAll(
                            Color(0xFFF2F7F3),
                          ),
                          cells: [
                            DataCell(Text(_day(row.from), style: cell)),
                            const DataCell(Text('')),
                            const DataCell(Text('')),
                            const DataCell(Text('')),
                            const DataCell(Text('')),
                            DataCell(
                              Text(
                                'Ödeme ${_money(row.payment)}: '
                                '${_money(row.toInterest)} faize, '
                                '${_money(row.toPrincipal)} anaparaya',
                                style: cell.copyWith(
                                  color: const Color(0xFF1B6B3A),
                                ),
                              ),
                            ),
                          ],
                        )
                      : DataRow(
                          cells: [
                            DataCell(
                              Text(
                                '${_day(row.from)} – ${_day(row.to!)}',
                                style: cell,
                              ),
                            ),
                            DataCell(Text('${row.days}', style: cell)),
                            DataCell(Text(_rate(row.rate), style: cell)),
                            DataCell(Text(_money(row.principal), style: cell)),
                            DataCell(Text(_money(row.interest), style: cell)),
                            DataCell(
                              Text(
                                row.basis,
                                style: cell.copyWith(color: AgendaColors.muted),
                              ),
                            ),
                          ],
                        ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (r.missing)
            _warn(
              'Başlangıç günü, bu faiz türü için oran bilinen ilk günden '
              'önce; o günler hesaba katılmadı.',
            ),
          if (r.beyondData && verified != null)
            _warn(
              'Oranlar en son ${_day(verified)} günü resmî kaynaklarla '
              'karşılaştırıldı; sonrasında değişen bir oran varsa yansımamış '
              'olabilir.',
            ),
          const Text(
            'Faiz her gün o gün geçerli oranla, yıl 365 gün sayılarak '
            'hesaplanır; faize faiz yürütülmez. Sonuç bilgi amaçlıdır.',
            style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _warn(String text) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: AgendaColors.taskFill,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: AgendaColors.taskText),
    ),
  );
}

import 'dart:async';

import '../help/help_button.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../tools/interest_page.dart';
import '../../services/clients/cash_report.dart';
import '../../services/clients/client.dart';
import '../../services/clients/client_accounts.dart';
import '../../services/clients/client_files.dart';
import '../../services/clients/office_cash.dart';
import '../../services/platform/phone_document_save.dart';
import '../../services/portal/portal_database.dart';
import '../../services/uyap/uyap_web_service.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../clients/attachment_preview.dart';
import '../clients/client_accounts_view.dart'
    show CurrencyChoice, MovementDialog, askApplyHeld, ledgerApply;
import '../clients/clients_page.dart' show pickScan;
import '../portfolio/portfolio_rows.dart' show titleName;
import '../widgets/proposals_view.dart';
import '../widgets/notice.dart';
import '../theme/folio_palette.dart';

String _two(int v) => v.toString().padLeft(2, '0');
String _day(DateTime t) => '${_two(t.day)}.${_two(t.month)}.${t.year}';
String _time(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// "15.000" from kuruş: TL is the column's; another currency with its
/// sign.
String _plain(int kurus, [Currency c = Currency.tl]) => plainMoney(kurus, c);

// Getters, not finals: a final would keep the theme it was first read in.
Color get _green => tone(const Color(0xFF1B6B3A));
Color get _purple => tone(const Color(0xFF5B3B9A));
Color get _trustFill => tone(const Color(0xFFF6F3FC));
Color get _trustLine => tone(const Color(0xFFE2DAF3));

Color _sideColor(CashSide s) => switch (s) {
  CashSide.income => _green,
  CashSide.expense => AgendaColors.deadlineText,
  CashSide.trust => _purple,
  CashSide.onBehalf => AgendaColors.taskText,
};

Color _sideFill(CashSide s) => switch (s) {
  CashSide.income => tone(const Color(0xFFE6F4EC)),
  CashSide.expense => tone(const Color(0xFFFCEBEA)),
  CashSide.trust => tone(const Color(0xFFEFE9FA)),
  CashSide.onBehalf => AgendaColors.taskFill,
};

/// The lawyer's book (Kasa): what the clients paid and were paid for,
/// read from their cards, and the office's own income and expenses; its
/// reports by the year. Alone, on one's own devices, and in an office
/// among those who see the money alike.
class CashPage extends StatefulWidget {
  const CashPage({
    super.key,
    required this.lawyer,
    this.person = '',
    this.database,
    this.files,
    this.onOpenClient,
  });

  final String lawyer, person;
  final PortalDatabase? database;
  final ClientFiles? files;

  /// A client opened on their page, by their key in the list.
  final ValueChanged<String>? onOpenClient;

  @override
  State<CashPage> createState() => _CashPageState();
}

class _CashPageState extends State<CashPage> {
  PortalDatabase? _db;
  late final ClientFiles _files = widget.files ?? ClientFiles();
  List<ClientEntry> _entries = const [];
  List<CashLine> _lines = const [];
  List<ClientBalance> _balances = const [];
  List<BankAccount> _banks = const [];

  /// The currency the page shows: each is its own book.
  Currency _currency = Currency.tl;
  bool _reports = false;
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late int _year = DateTime.now().year;
  CashSide? _side;
  String? _way;
  String _query = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final db = _db ??= widget.database ?? await PortalDatabase.shared();
    final now = DateTime.now();
    writeRepeats(db, now, person: widget.person);
    final entries = db.clientEntries(lawyer: widget.lawyer);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _lines = cashLines(db, entries: entries);
      _balances = clientBalances(db, now, entries: entries);
      _banks = bankAccounts(db);
      if (!cashCurrencies(_lines).contains(_currency)) {
        _currency = Currency.tl;
      }
    });
  }

  String _caseTitle(String key) {
    final c = _db?.caseOf(key);
    return c == null ? key : '${c.number} · ${c.court}';
  }

  /// Each case's number read once for each reading of the book: asked for
  /// every line on every build, and every line on each keystroke of the
  /// search, each was a query and a decoding.
  ///
  /// Read afresh when the book is read again or any case is written (a
  /// number may change with no line of the book changing); that is looked
  /// at once a build ([_freshNumbers]), not once a line.
  String _caseNumber(String key) =>
      _numbers[key] ??= _db?.caseOf(key)?.number ?? key;

  void _freshNumbers() {
    final cases = _db?.casesRevision;
    if (identical(_numbersOf, _lines) && cases == _numbersCases) return;
    _numbersOf = _lines;
    _numbersCases = cases;
    _numbers.clear();
  }

  List<CashLine>? _numbersOf;
  int? _numbersCases;
  final _numbers = <String, String>{};

  /// The month's lines in the currency shown.
  List<CashLine> _ofMonth(DateTime m) => [
    for (final l in _lines)
      if (l.at.year == m.year &&
          l.at.month == m.month &&
          l.currency == _currency)
        l,
  ];

  // Writing

  void _keep(ClientRecord r) {
    _db!.saveClientRecord(
      r.person.isEmpty && widget.person.isNotEmpty
          ? r.copyWith(person: widget.person)
          : r,
    );
  }

  Future<void> _expense({bool income = false}) async {
    final saved = await showDialog<List<ClientRecord>>(
      context: context,
      builder: (_) => _CashDialog(
        income: income,
        currency: _currency,
        lawyer: widget.lawyer,
        person: widget.person,
        files: _files,
      ),
    );
    if (saved == null) return;
    saved.forEach(_keep);
    await _load();
  }

  /// A client's payment written from here: the client and the case asked,
  /// then the movement as on the client's card.
  Future<void> _collection() async {
    final picked = await showDialog<({ClientEntry entry, String caseKey})>(
      context: context,
      builder: (_) => _ClientPick(entries: _entries, caseTitle: _caseTitle),
    );
    if (picked == null || !mounted) return;
    var card = picked.entry.client;
    if (card == null) {
      card = Client(
        id: Client.newId(),
        name: picked.entry.name,
        updated: DateTime.now(),
        person: widget.person,
      );
      _db!.saveClient(card);
    }
    final saved = await showDialog<ClientRecord>(
      context: context,
      builder: (_) => MovementDialog(
        client: card!,
        caseKey: picked.caseKey,
        currency: _currency,
        lawyer: widget.lawyer,
        person: widget.person,
        files: _files,
      ),
    );
    if (saved == null) return;
    _keep(saved);
    await _load();
  }

  /// A bank account added, its balance told again, or taken off.
  Future<void> _bank([BankAccount? kept]) async {
    final saved = await showDialog<ClientRecord>(
      context: context,
      builder: (_) => _BankDialog(
        kept: kept,
        currency: _currency,
        lawyer: widget.lawyer,
        person: widget.person,
      ),
    );
    if (saved == null) return;
    _keep(saved);
    await _load();
  }

  /// One of the office's own lines taken back by another naming it.
  Future<void> _reverse(CashLine l) async {
    final why = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(),
    );
    if (why == null) return;
    final now = DateTime.now();
    final m = l.record;
    _keep(
      ClientRecord(
        id: Client.newId(),
        clientId: officeCashId,
        kind: ClientRecordKind.cash,
        data: {
          ...m.data,
          'ters': m.id,
          'zaman': now.toIso8601String(),
          'aciklama': why.trim().isEmpty ? m.text('aciklama') : why.trim(),
          'ekler': const [],
        }..remove('tekrar'),
        created: now,
        by: widget.lawyer,
        updated: now,
        locked: true,
      ),
    );
    await _load();
  }

  Future<void> _receipt(CashLine l) async {
    final f = clientFilesOf(l.record).firstOrNull;
    if (f == null) return;
    final file = await _files.locate(l.record.clientId, f);
    if (!mounted) return;
    if (file == null) {
      showNotice(
        context,
        'Bu belge bu cihazda yok.',
        detail: 'Eklendiği cihaz ağdayken eşitlemeyle gelir.',
      );
      return;
    }
    await showClientAttachment(
      context,
      title: 'Belge',
      fileName: '${f.name.replaceAll(RegExp(r'\.[^.]+$'), '')}.pdf',
      pdf: () => attachmentPdf(file),
    );
  }

  Future<void> _repeats() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _RepeatsDialog(database: _db!),
    );
    await _load();
  }

  Future<void> _saveBytes(String name, String ext, Uint8List data) async {
    try {
      final path = PhoneDocumentSave.here
          ? await PhoneDocumentSave.save(fileName: name, bytes: data)
          : await FilePicker.saveFile(
              fileName: name,
              type: FileType.custom,
              allowedExtensions: [ext],
              bytes: data,
            );
      if (path == null) return;
      if (!PhoneDocumentSave.here) {
        await File(path).writeAsBytes(data, flush: true);
      }
      if (mounted) showNotice(context, '$name kaydedildi.', detail: path);
    } catch (e) {
      if (mounted) {
        showNotice(context, 'Kaydedilemedi: $e', kind: NoticeKind.error);
      }
    }
  }

  Future<void> _excel() async {
    // Every currency: the workbook names each line's.
    final lines = [
      for (final l in _lines)
        if (_reports
            ? l.at.year == _year
            : l.at.year == _month.year && l.at.month == _month.month)
          l,
    ];
    final name = _reports
        ? 'Kasa $_year.xlsx'
        : 'Kasa ${monthNames[_month.month - 1]} ${_month.year}.xlsx';
    await _saveBytes(name, 'xlsx', await cashWorkbook(lines, _caseTitle));
  }

  Future<void> _pdf() => showClientAttachment(
    context,
    title: 'Kasa raporu $_year',
    fileName: 'Kasa raporu $_year.pdf',
    pdf: () => cashReportPdf(
      year: _year,
      lines: _lines,
      balances: _balances,
      lawyer: widget.lawyer,
    ),
  );

  // Showing

  @override
  Widget build(BuildContext context) {
    if (_db == null) return const Center(child: CircularProgressIndicator());
    _freshNumbers();
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 720;
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: wide || _reports
              ? null
              : FloatingActionButton.extended(
                  key: const ValueKey('cash-expense-fab'),
                  onPressed: _expense,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Gider'),
                ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              wide ? 16 : 10,
              12,
              wide ? 16 : 10,
              wide ? 24 : 88,
            ),
            children: [
              _top(wide),
              const SizedBox(height: 10),
              ..._repairs(),
              // What colleagues proposed of this person's records (R6).
              if (_db case final db?)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ProposalsStrip(
                    db: db,
                    onChanged: () => unawaited(_load()),
                  ),
                ),
              if (_reports) ..._report(wide) else ..._book(wide),
            ],
          ),
        );
      },
    );
  }

  /// The enforcement payments whose old movements wait for the lawyer's
  /// word (docs/senkron-plan.md R3), each with why, what the account holds
  /// now and what it will once mended; none, nothing shown.
  List<Widget> _repairs() {
    final db = _db!;
    // Only this person's own: a colleague's is mended on their devices.
    final ids = [
      for (final id in db.ledgerRepairs)
        if (db.clientRecord(id) case final e? when db.isMineToMend(e)) id,
    ];
    if (ids.isEmpty) return const [];
    String sums(Object? m) {
      final map = m is Map ? m : const {};
      final parts = [
        for (final e in map.entries)
          if (e.value is num && e.value != 0)
            '${lira((e.value as num).toInt())} '
                '${switch (MovementKind.of(e.key)) {
                  MovementKind.toFee => 'vekâlet ücreti',
                  MovementKind.toCounterFee => 'karşı vekâlet ücreti',
                  _ => 'emanet',
                }}',
      ];
      return parts.isEmpty ? 'hesapta yok' : parts.join(', ');
    }

    Widget row(String id) {
      final e = db.clientRecord(id);
      final report = db.ledgerRepairOf(id);
      if (e == null || report == null) return const SizedBox.shrink();
      final after = sums(report['onarinca']);
      return Container(
        key: ValueKey('ledger-repair-$id'),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AgendaColors.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${lira(e.amount)} · ${_caseTitle(e.text('dosya'))}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${report['neden'] ?? ''}',
                    style: TextStyle(fontSize: 13, color: AgendaColors.muted),
                  ),
                  Text(
                    report['karsilastirilir'] == false
                        ? 'Eski kayıtlar ${(report['kimlikler'] as List?)?.length ?? 0} '
                              'hareket; başka bir müvekkil, dosya ya da para birimi '
                              'karıştığı için tutarlar yan yana konamıyor. '
                              'Müvekkil hesabından bakın.'
                        : 'Şimdi: ${sums(report['simdi'])} → Onarınca: '
                              '${after == 'hesapta yok' ? 'hesaptan çıkar' : after}',
                    style: TextStyle(fontSize: 12, color: AgendaColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              key: ValueKey('ledger-repair-ok-$id'),
              onPressed: () async {
                final ok = db.resolveLedgerRepair(id, '${report['ozet']}');
                await _load();
                if (!mounted) return;
                showNotice(
                  context,
                  ok
                      ? 'Onarıldı.'
                      : 'Kayıt bu arada değişti; rapor yenilendi, '
                            'yeniden bakın.',
                );
              },
              child: const Text('Onar'),
            ),
          ],
        ),
      );
    }

    return [
      Container(
        key: const ValueKey('ledger-repairs'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AgendaColors.task),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: AgendaColors.taskText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${ids.length} icra ödemesinin eski kayıtları onarım '
                    'bekliyor',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Folio\'nun önceki sürümü bu ödemeleri hesaba farklı işlemiş. '
              'Siz onaylayana kadar hesap olduğu gibi kalır.',
              style: TextStyle(fontSize: 13, color: AgendaColors.muted),
            ),
            const SizedBox(height: 8),
            for (final id in ids) row(id),
          ],
        ),
      ),
      const SizedBox(height: 10),
    ];
  }

  Widget _top(bool wide) {
    final now = DateTime.now();
    final months = <DateTime>{
      for (var i = 0; i < 24; i++) DateTime(now.year, now.month - i),
      for (final l in _lines) DateTime(l.at.year, l.at.month),
    }.toList()..sort((a, b) => b.compareTo(a));
    final years = <int>{now.year, for (final l in _lines) l.at.year}.toList()
      ..sort((a, b) => b.compareTo(a));
    final period = _reports
        ? DropdownButton<int>(
            key: const ValueKey('cash-year'),
            value: _year,
            underline: const SizedBox(),
            items: [
              for (final y in years)
                DropdownMenuItem(value: y, child: Text('$y')),
            ],
            onChanged: (v) => setState(() => _year = v ?? _year),
          )
        : DropdownButton<DateTime>(
            key: const ValueKey('cash-month'),
            value: _month,
            underline: const SizedBox(),
            items: [
              for (final m in months)
                DropdownMenuItem(
                  value: m,
                  child: Text('${monthNames[m.month - 1]} ${m.year}'),
                ),
            ],
            onChanged: (v) => setState(() => _month = v ?? _month),
          );
    final currencies = cashCurrencies(_lines);
    final currency = currencies.length < 2 || !_reports
        ? null
        : DropdownButton<Currency>(
            key: const ValueKey('cash-report-currency'),
            value: _currency,
            underline: const SizedBox(),
            items: [
              for (final c in currencies)
                DropdownMenuItem(value: c, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() => _currency = v ?? _currency),
          );
    final mode = SegmentedButton<bool>(
      key: const ValueKey('cash-mode'),
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: false, label: Text('Defter')),
        ButtonSegment(value: true, label: Text('Raporlar')),
      ],
      selected: {_reports},
      onSelectionChanged: (v) => setState(() => _reports = v.first),
    );
    final more = PopupMenuButton<String>(
      key: const ValueKey('cash-more'),
      onSelected: (v) => switch (v) {
        'gelir' => _expense(income: true),
        'tekrar' => _repeats(),
        'banka' => _bank(),
        'faiz' => InterestPage.open(context),
        'pdf' => _pdf(),
        _ => _excel(),
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'gelir', child: Text('Başka gelir ekle')),
        const PopupMenuItem(
          value: 'tekrar',
          child: Text('Her ay tekrarlanan giderler'),
        ),
        const PopupMenuItem(value: 'banka', child: Text('Banka hesabı ekle')),
        const PopupMenuItem(value: 'faiz', child: Text('Faiz hesabı')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'excel', child: Text('Excel\'e aktar')),
        if (_reports)
          const PopupMenuItem(value: 'pdf', child: Text('Raporu PDF yap')),
      ],
    );
    final actions = [
      if (_reports) ...[
        OutlinedButton(
          key: const ValueKey('cash-pdf'),
          onPressed: _pdf,
          child: const Text('PDF'),
        ),
        OutlinedButton(
          key: const ValueKey('cash-excel'),
          onPressed: _excel,
          child: const Text('Excel'),
        ),
      ] else ...[
        OutlinedButton.icon(
          key: const ValueKey('cash-collection'),
          onPressed: _collection,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Tahsilat'),
        ),
        if (wide)
          FilledButton.icon(
            key: const ValueKey('cash-expense'),
            onPressed: _expense,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Gider'),
          ),
      ],
      more,
    ];
    const title = Text(
      'Kasa',
      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
    );
    if (wide) {
      return Row(
        children: [
          title,
          const SizedBox(width: 14),
          mode,
          const SizedBox(width: 10),
          period,
          if (currency != null) ...[const SizedBox(width: 10), currency],
          const Spacer(),
          const HelpButton(Help.cash),
          const SizedBox(width: 6),
          for (final a in actions) ...[a, const SizedBox(width: 6)],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            title,
            const Spacer(),
            const HelpButton(Help.cash),
            ...actions,
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: mode),
            const SizedBox(width: 8),
            period,
            ?currency,
          ],
        ),
      ],
    );
  }

  Widget _kpi(
    String label,
    String value,
    Color? color, {
    String? sub,
    bool trust = false,
  }) => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
    decoration: BoxDecoration(
      color: trust ? _trustFill : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: trust ? _trustLine : AgendaColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: AgendaColors.muted)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        if (sub != null)
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
          ),
      ],
    ),
  );

  /// One card a currency the book is in: what the office has in it, this
  /// month's in and out; the one chosen is the page's. TL's always.
  Widget _tills(bool wide) {
    final balance = cashBalance(_lines);
    final currencies = cashCurrencies(_lines);
    Widget till(Currency c) {
      final month = cashTotals([
        for (final l in _lines)
          if (l.currency == c &&
              l.at.year == _month.year &&
              l.at.month == _month.month)
            l,
      ]);
      final chosen = c == _currency;
      final value = balance[c];
      return InkWell(
        key: ValueKey('cash-till-${c.code}'),
        borderRadius: BorderRadius.circular(12),
        onTap: currencies.length < 2
            ? null
            : () => setState(() {
                _currency = c;
                _side = null;
              }),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: chosen && currencies.length > 1
                  ? Theme.of(context).colorScheme.primary
                  : AgendaColors.line,
              width: chosen && currencies.length > 1 ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c == Currency.tl ? 'TL kasası' : '${c.label} kasası',
                style: TextStyle(fontSize: 12, color: AgendaColors.muted),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  money(value, c),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: value < 0 ? AgendaColors.deadlineText : null,
                  ),
                ),
              ),
              Text(
                '${monthNames[_month.month - 1]}: '
                '+${_plain(month.income, c)}  −${_plain(month.expense, c)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
              ),
            ],
          ),
        ),
      );
    }

    Widget bank(BankAccount b) => InkWell(
      key: ValueKey('cash-bank-${b.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => _bank(b),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AgendaColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_outlined,
                  size: 14,
                  color: AgendaColors.muted,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    b.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AgendaColors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                money(b.balance, b.currency),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${_day(b.told)} itibarıyla',
              style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
            ),
          ],
        ),
      ),
    );

    final cards = [
      for (final c in currencies) till(c),
      for (final b in _banks) bank(b),
    ];
    final addBank = _banks.isEmpty
        ? Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('cash-bank-add'),
              onPressed: _bank,
              icon: const Icon(Icons.account_balance_outlined, size: 16),
              label: const Text('Banka bakiyesi ekle (isteğe bağlı)'),
            ),
          )
        : null;
    final across = wide ? 4 : 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            const gap = 8.0;
            final w = (box.maxWidth - gap * (across - 1)) / across;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [for (final c in cards) SizedBox(width: w, child: c)],
            );
          },
        ),
        ?addBank,
      ],
    );
  }

  List<Widget> _book(bool wide) {
    final c = _currency;
    final month = _ofMonth(_month);
    final total = cashTotals(month);
    final before = cashTotals(
      _ofMonth(DateTime(_month.year, _month.month - 1)),
    );
    final owed = _balances.fold(0, (n, b) => n + b.owed[c]);
    final costs = _balances.fold(0, (n, b) => n + b.costs[c]);
    final held = _balances.fold(0, (n, b) => n + b.held[c]);
    final late = _balances.where((b) => b.late).length;
    final holding = _balances.where((b) => b.held[c] > 0).length;
    final spending = _balances.where((b) => b.costs[c] > 0).length;
    String m(int v) => money(v, c);
    final kpis = [
      _kpi('Gelir', m(total.income), _green, sub: 'ücret ve diğer gelirler'),
      _kpi(
        'Gider',
        m(total.expense),
        AgendaColors.deadlineText,
        sub: 'büronun giderleri',
      ),
      _kpi('Net', m(total.net), null, sub: 'önceki ay ${m(before.net)}'),
      InkWell(
        key: const ValueKey('cash-client-costs'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _side = CashSide.onBehalf),
        child: _kpi(
          'Müvekkil masrafı',
          m(costs),
          costs > 0 ? AgendaColors.taskText : null,
          sub: spending > 0
              ? '$spending müvekkilden geri alınacak'
              : 'sizin ödediğiniz masraflar',
        ),
      ),
      _kpi(
        'Ücret alacağı',
        m(owed),
        owed > 0 ? AgendaColors.deadlineText : null,
        sub: late > 0 ? '$late müvekkilin taksiti gecikmiş' : 'kalan ücretler',
      ),
      _kpi(
        'Emanet',
        m(held),
        _purple,
        sub: 'gelir değil · $holding müvekkil',
        trust: true,
      ),
    ];
    final q = UyapWebService.fold(_query.trim());
    final ways = {for (final l in month) l.way}..remove('');
    final shown = [
      for (final l in month)
        if ((_side == null || l.side == _side) &&
            (_way == null || l.way == _way) &&
            (q.isEmpty ||
                UyapWebService.fold(
                  '${l.title} ${l.client} ${_caseNumber(l.caseKey)} '
                  '${l.category}',
                ).contains(q)))
          l,
    ];
    int count(CashSide? s) =>
        s == null ? month.length : month.where((l) => l.side == s).length;
    final filters = Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final s in [null, ...CashSide.values])
          ChoiceChip(
            key: ValueKey('cash-side-${s?.name ?? 'all'}'),
            visualDensity: VisualDensity.compact,
            label: Text('${s?.label ?? 'Tümü'} ${count(s)}'),
            selected: _side == s,
            onSelected: (_) => setState(() => _side = s),
          ),
        if (ways.length > 1)
          DropdownButton<String?>(
            value: _way,
            underline: const SizedBox(),
            hint: const Text('Ödeme'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Tüm ödemeler')),
              for (final w in ways.toList()..sort())
                DropdownMenuItem(value: w, child: Text(w)),
            ],
            onChanged: (v) => setState(() => _way = v),
          ),
        SizedBox(
          width: wide ? 240 : double.infinity,
          child: TextField(
            key: const ValueKey('cash-search'),
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded, size: 20),
              hintText: 'Açıklama, müvekkil, dosya…',
            ),
          ),
        ),
      ],
    );
    return [
      _tills(wide),
      const SizedBox(height: 10),
      if (wide)
        Row(
          children: [
            for (final (i, k) in kpis.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: k),
            ],
          ],
        )
      else
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 2.2,
          children: kpis,
        ),
      const SizedBox(height: 10),
      _frame(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            filters,
            const SizedBox(height: 6),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'Bu ayda kayıt yok. Müvekkil kartında yazılan tahsilat, '
                  'avans ve masraflar buraya kendiliğinden gelir; büronun '
                  'giderlerini "Gider" ile yazın.',
                  style: TextStyle(color: AgendaColors.muted),
                ),
              )
            else ...[
              if (wide) _head(),
              for (final l in shown) wide ? _row(l) : _tile(l),
            ],
            const SizedBox(height: 6),
            Text(
              'Müvekkil kartında yazılan kayıtlar buraya kendiliğinden gelir; '
              'düzeltmesi kartta ters kayıtla yapılır. Emanet, müvekkil adına '
              'tutulan paradır; büronun geliri sayılmaz.',
              style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _frame(Widget child, {Color? fill, Color? line}) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: fill ?? Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: line ?? AgendaColors.line),
    ),
    child: child,
  );

  Widget _tag(CashSide s) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: _sideFill(s),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      s.label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: _sideColor(s),
      ),
    ),
  );

  static const _wDate = 96.0, _wSide = 116.0, _wWay = 110.0, _wSum = 92.0;

  Widget _head() {
    Widget h(String t, {double? w, bool right = false}) {
      final text = Text(
        t,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: TextStyle(fontSize: 11, color: AgendaColors.muted),
      );
      return w == null
          ? Expanded(child: text)
          : SizedBox(width: w, child: text);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          h('Tarih', w: _wDate),
          h('Tür', w: _wSide),
          h('Açıklama'),
          h('Müvekkil · dosya'),
          h('Ödeme', w: _wWay),
          h('Giriş', w: _wSum, right: true),
          h('Çıkış', w: _wSum, right: true),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  /// Whether [l] is money held for a client that may be taken as a fee.
  static bool _held(CashLine l) =>
      l.fromClient &&
      !l.struck &&
      l.side == CashSide.trust &&
      l.amount > 0 &&
      (l.record.movement == MovementKind.collected ||
          l.record.movement == MovementKind.advanceIn);

  List<PopupMenuEntry<String>> _items(CashLine l) => [
    if (l.fromClient && l.clientKey != null && widget.onOpenClient != null)
      const PopupMenuItem(value: 'muvekkil', child: Text('Müvekkili aç')),
    if (clientFilesOf(l.record).isNotEmpty)
      const PopupMenuItem(value: 'belge', child: Text('Belgeyi göster')),
    if (_held(l)) ...[
      const PopupMenuItem(
        value: 'ucret',
        child: Text('Vekâlet ücretine mahsup et'),
      ),
      const PopupMenuItem(
        value: 'karsi',
        child: Text('Karşı vekâlet ücretine mahsup et'),
      ),
    ],
    if (!l.fromClient && !l.struck)
      const PopupMenuItem(value: 'ters', child: Text('Ters kayıtla düzelt')),
  ];

  void _act(CashLine l, String v) => switch (v) {
    'muvekkil' => widget.onOpenClient!(l.clientKey!),
    'belge' => _receipt(l),
    'ucret' => _apply(l, MovementKind.toFee),
    'karsi' => _apply(l, MovementKind.toCounterFee),
    _ => _reverse(l),
  };

  /// [l]'s line menu where it was right-clicked.
  Future<void> _menuAt(CashLine l, Offset at) async {
    final items = _items(l);
    if (items.isEmpty) return;
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: items,
    );
    if (v != null && mounted) _act(l, v);
  }

  /// Money held for a client taken as a fee: up to what is held for the
  /// case in that currency.
  Future<void> _apply(CashLine l, MovementKind kind) async {
    final db = _db!;
    final held = l.record;
    final records = [
      for (final r in db.allClientRecords())
        if (!r.removed && r.kind.money && r.clientId == held.clientId) r,
    ];
    final account = caseAccounts(records)[held.text('dosya')]?.all
        .where((a) => a.currency == held.currency)
        .firstOrNull;
    final most = account?.advanceLeft ?? held.amount;
    if (most <= 0) {
      showNotice(context, 'Bu dosyada emanette para kalmamış.');
      return;
    }
    final made = await askApplyHeld(
      context,
      held,
      kind,
      lawyer: widget.lawyer,
      person: widget.person,
      most: most,
    );
    if (made == null) return;
    final via = ledgerApply(db, held, made);
    if (!via.ledger) _keep(made);
    if (via.refused != null && mounted) showNotice(context, via.refused!);
    await _load();
  }

  Widget? _menu(CashLine l) {
    final items = _items(l);
    if (items.isEmpty) return null;
    // A fee taken from what was held is two lines of one record.
    final second =
        l.side == CashSide.income && (l.record.movement?.isApplied ?? false);
    return PopupMenuButton<String>(
      key: ValueKey('cash-line-${l.record.id}${second ? '-gelir' : ''}'),
      icon: const Icon(Icons.more_horiz_rounded, size: 20),
      onSelected: (v) => _act(l, v),
      itemBuilder: (_) => items,
    );
  }

  TextStyle _struck(TextStyle s, CashLine l) => l.struck
      ? s.copyWith(
          decoration: TextDecoration.lineThrough,
          color: AgendaColors.muted,
        )
      : s;

  Widget _row(CashLine l) => GestureDetector(
    onSecondaryTapUp: (d) => _menuAt(l, d.globalPosition),
    onLongPressStart: (d) => _menuAt(l, d.globalPosition),
    child: _rowOf(l),
  );

  Widget _rowOf(CashLine l) {
    const base = TextStyle(fontSize: 13);
    final who = [
      if (l.client.isNotEmpty) titleName(l.client),
      if (l.caseKey.isNotEmpty) _caseNumber(l.caseKey),
    ].join(' · ');
    Text sum(int v) => Text(
      v == 0 ? '' : _plain(v, l.currency),
      textAlign: TextAlign.right,
      style: _struck(base.copyWith(color: _sideColor(l.side)), l),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AgendaColors.line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _wDate,
            child: Text(
              // A line written with no hour shows its day alone.
              l.at.hour == 0 && l.at.minute == 0
                  ? _day(l.at).substring(0, 5)
                  : '${_day(l.at).substring(0, 5)} ${_time(l.at)}',
              style: base,
            ),
          ),
          SizedBox(
            width: _wSide,
            child: Align(alignment: Alignment.centerLeft, child: _tag(l.side)),
          ),
          Expanded(
            child: Text(
              l.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _struck(base, l),
            ),
          ),
          Expanded(
            child: Text(
              who.isEmpty ? '—' : who,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: base.copyWith(
                color: who.isEmpty ? AgendaColors.muted : null,
              ),
            ),
          ),
          SizedBox(
            width: _wWay,
            child: Text(l.way, overflow: TextOverflow.ellipsis, style: base),
          ),
          SizedBox(width: _wSum, child: sum(l.amount > 0 ? l.amount : 0)),
          SizedBox(width: _wSum, child: sum(l.amount < 0 ? -l.amount : 0)),
          SizedBox(
            width: 40,
            child:
                _menu(l) ??
                (l.fromClient
                    ? Tooltip(
                        message: 'Müvekkil kartında yazıldı',
                        child: Icon(
                          Icons.lock_outline_rounded,
                          size: 16,
                          color: AgendaColors.muted,
                        ),
                      )
                    : null),
          ),
        ],
      ),
    );
  }

  Widget _tile(CashLine l) => GestureDetector(
    onLongPressStart: (d) => _menuAt(l, d.globalPosition),
    child: _tileOf(l),
  );

  Widget _tileOf(CashLine l) {
    final sub = [
      _day(l.at).substring(0, 5),
      if (l.client.isNotEmpty) titleName(l.client),
      if (l.caseKey.isNotEmpty) _caseNumber(l.caseKey),
      if (l.client.isEmpty && l.way.isNotEmpty) l.way,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AgendaColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l.title,
                      style: _struck(
                        const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                        l,
                      ),
                    ),
                    if (l.side != CashSide.income && l.side != CashSide.expense)
                      _tag(l.side),
                  ],
                ),
                Text(
                  sub,
                  style: TextStyle(fontSize: 12, color: AgendaColors.muted),
                ),
              ],
            ),
          ),
          Text(
            '${l.amount > 0 ? '+' : '−'}${_plain(l.amount.abs(), l.currency)}',
            style: _struck(
              TextStyle(fontWeight: FontWeight.w700, color: _sideColor(l.side)),
              l,
            ),
          ),
          ?_menu(l),
        ],
      ),
    );
  }

  List<Widget> _report(bool wide) {
    final c = _currency;
    String m(int v) => money(v, c);
    final year = [
      for (final l in _lines)
        if (l.at.year == _year && l.currency == c) l,
    ];
    final total = cashTotals(year);
    final months = [
      for (var m = 1; m <= 12; m++)
        cashTotals([
          for (final l in year)
            if (l.at.month == m) l,
        ]),
    ];
    final top = months.fold(
      1,
      (n, t) => [n, t.income, t.expense].reduce((a, b) => a > b ? a : b),
    );
    final categories = <String, int>{};
    for (final l in year) {
      if (l.side == CashSide.expense) {
        final k = l.category.isEmpty ? 'Diğer' : l.category;
        categories[k] = (categories[k] ?? 0) - l.amount;
      }
    }
    final cats = categories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final paid = <String, int>{};
    for (final l in year) {
      if (l.side == CashSide.income && l.client.isNotEmpty) {
        paid[l.client] = (paid[l.client] ?? 0) + l.amount;
      }
    }
    final payers = paid.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final owing = [
      for (final b in _balances)
        if (b.owed[c] > 0) b,
    ]..sort((a, b) => b.owed[c].compareTo(a.owed[c]));
    final spent = [
      for (final b in _balances)
        if (b.costs[c] > 0) b,
    ]..sort((a, b) => b.costs[c].compareTo(a.costs[c]));
    final holding = [
      for (final b in _balances)
        if (b.held[c] > 0) b,
    ]..sort((a, b) => b.held[c].compareTo(a.held[c]));
    Widget title(String t, {String? right}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          if (right != null)
            Text(
              right,
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            ),
        ],
      ),
    );
    Widget line(String a, String b, {Color? color, Widget? tag}) => Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AgendaColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              children: [
                Text(a, style: const TextStyle(fontSize: 13)),
                ?tag,
              ],
            ),
          ),
          Text(
            b,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
    final bars = _frame(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title('Aylık gelir ve gider', right: 'yeşil gelir · kırmızı gider'),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var n = 0; n < 12; n++)
                  Expanded(
                    child: Tooltip(
                      message:
                          '${monthNames[n]}: gelir ${m(months[n].income)}, '
                          'gider ${m(months[n].expense)}',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (final (v, c) in [
                                (
                                  months[n].income,
                                  tone(const Color(0xFF3E9C6B)),
                                ),
                                (
                                  months[n].expense,
                                  tone(const Color(0xFFC2523F)),
                                ),
                              ])
                                Container(
                                  width: wide ? 11 : 6,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 1,
                                  ),
                                  height: v <= 0 ? 0 : 1 + 124 * v / top,
                                  decoration: BoxDecoration(
                                    color: c,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(3),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            monthNames[n].substring(0, 3),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AgendaColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Yıl: gelir ${m(total.income)} · gider ${m(total.expense)} '
            '· net ${m(total.net)}',
            style: TextStyle(fontSize: 12, color: AgendaColors.muted),
          ),
        ],
      ),
    );
    final most = cats.isEmpty ? 1 : cats.first.value;
    final expenses = _frame(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title('Giderler', right: '$_year'),
          if (cats.isEmpty)
            Text(
              'Bu yıl gider yazılmadı.',
              style: TextStyle(color: AgendaColors.muted),
            ),
          for (final c in cats) ...[
            line(c.key, _plain(c.value, _currency)),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: c.value / most,
                minHeight: 6,
                color: tone(const Color(0xFFC2523F)),
                backgroundColor: tone(const Color(0xFFEEF0F4)),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
    Widget list(
      String t,
      String right,
      List<Widget> rows, {
      bool trust = false,
    }) => _frame(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title(t, right: right),
          if (rows.isEmpty)
            Text('Yok.', style: TextStyle(color: AgendaColors.muted)),
          ...rows.take(8),
        ],
      ),
      fill: trust ? _trustFill : null,
      line: trust ? _trustLine : null,
    );
    final receivable = list(
      'Ücret alacakları',
      _plain(owing.fold(0, (n, b) => n + b.owed[c]), c),
      [
        for (final b in owing)
          line(
            titleName(b.name),
            _plain(b.owed[c], c),
            color: AgendaColors.deadlineText,
            tag: b.late ? _late() : null,
          ),
      ],
    );
    final costs = list(
      'Müvekkil masrafları',
      _plain(spent.fold(0, (n, b) => n + b.costs[c]), c),
      [
        for (final b in spent)
          line(
            titleName(b.name),
            _plain(b.costs[c], c),
            color: AgendaColors.taskText,
          ),
      ],
    );
    final collected = list('En çok tahsilat', '$_year', [
      for (final p in payers) line(titleName(p.key), _plain(p.value, c)),
    ]);
    final trust = list(
      'Emanet bakiyeleri',
      _plain(holding.fold(0, (n, b) => n + b.held[c]), c),
      [
        for (final b in holding)
          line(titleName(b.name), _plain(b.held[c], c), color: _purple),
      ],
      trust: true,
    );
    if (!wide) {
      return [
        for (final w in [
          bars,
          expenses,
          receivable,
          costs,
          collected,
          trust,
        ]) ...[w, const SizedBox(height: 10)],
      ];
    }
    return [
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 13, child: bars),
            const SizedBox(width: 10),
            Expanded(flex: 10, child: expenses),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: receivable),
          const SizedBox(width: 10),
          Expanded(child: costs),
          const SizedBox(width: 10),
          Expanded(child: collected),
          const SizedBox(width: 10),
          Expanded(child: trust),
        ],
      ),
    ];
  }

  Widget _late() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: tone(const Color(0xFFFCEBEA)),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      'gecikti',
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: AgendaColors.deadlineText,
      ),
    ),
  );
}

/// The office's own expense, or an income of no client's: one record,
/// and its monthly repeat when asked.
class _CashDialog extends StatefulWidget {
  const _CashDialog({
    required this.income,
    required this.lawyer,
    required this.person,
    required this.files,
    this.currency = Currency.tl,
  });
  final bool income;

  /// The currency it starts in: the one the page shows.
  final Currency currency;
  final String lawyer, person;
  final ClientFiles files;

  @override
  State<_CashDialog> createState() => _CashDialogState();
}

class _CashDialogState extends State<_CashDialog> {
  final _amount = TextEditingController();
  final _what = TextEditingController();
  late String _category = widget.income
      ? 'Danışmanlık'
      : expenseCategories.first;
  String _way = cashWays[1];
  late Currency _currency = widget.currency;
  DateTime _at = DateTime.now();
  bool _repeat = false;
  ClientFile? _file;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _what.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    setState(
      () => _at = DateTime(
        day.year,
        day.month,
        day.day,
        time?.hour ?? _at.hour,
        time?.minute ?? _at.minute,
      ),
    );
  }

  Future<void> _scan() async {
    final path = await pickScan(context, 'Fiş, fatura ya da dekont');
    if (path == null) return;
    setState(() => _busy = true);
    try {
      final kept = await widget.files.keep(officeCashId, path);
      if (mounted) setState(() => _file = kept);
    } catch (e) {
      if (mounted) setState(() => _error = 'Belge eklenemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _save() {
    final amount = kurusOf(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Tutarı yazın.');
      return;
    }
    final now = DateTime.now();
    final data = <String, Object?>{
      'tur': widget.income ? 'gelir' : 'gider',
      'kategori': _category,
      'tutar': amount,
      'zaman': _at.toIso8601String(),
      'aciklama': _what.text.trim(),
      'odeme': _way,
      if (_currency != Currency.tl) 'para': _currency.code,
      'ekler': [?(_file == null ? null : clientFileJson(_file!))],
    };
    final out = <ClientRecord>[];
    var id = Client.newId();
    if (_repeat && !widget.income) {
      final template = ClientRecord(
        id: Client.newId(),
        clientId: officeCashId,
        kind: ClientRecordKind.cashRepeat,
        data: {
          'kategori': _category,
          'tutar': amount,
          'aciklama': _what.text.trim(),
          'odeme': _way,
          if (_currency != Currency.tl) 'para': _currency.code,
          'baslangic': _at.toIso8601String(),
          'bitis': '',
        },
        created: now,
        by: widget.lawyer,
        updated: now,
        person: widget.person,
      );
      out.add(template);
      // This month's is the repeat's own: it is not written twice.
      id = '${template.id}-${monthKey(_at)}';
      data['tekrar'] = template.id;
    }
    out.add(
      ClientRecord(
        id: id,
        clientId: officeCashId,
        kind: ClientRecordKind.cash,
        data: data,
        created: now,
        by: widget.lawyer,
        updated: now,
        locked: true,
        person: widget.person,
      ),
    );
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.income ? 'Gelir' : 'Gider'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('cash-amount'),
                    controller: _amount,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Tutar',
                      suffixText: _currency.sign,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CurrencyChoice(
                  key: const ValueKey('cash-currency'),
                  value: _currency,
                  onChanged: (c) => setState(() => _currency = c),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c
                    in widget.income
                        ? const ['Danışmanlık', 'Sözleşme', 'Diğer']
                        : expenseCategories)
                  ChoiceChip(
                    label: Text(c),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('cash-what'),
              controller: _what,
              decoration: const InputDecoration(labelText: 'Açıklama'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text('${_day(_at)} ${_time(_at)}'),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _way,
                  items: [
                    for (final w in cashWays)
                      DropdownMenuItem(value: w, child: Text(w)),
                  ],
                  onChanged: (v) => setState(() => _way = v ?? _way),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.document_scanner_outlined, size: 18),
              label: Text(
                _file == null
                    ? 'Fiş, fatura ya da dekont ekle'
                    : 'Eklendi: ${_file!.name}',
              ),
            ),
            if (!widget.income)
              SwitchListTile(
                key: const ValueKey('cash-repeat'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Her ay tekrarla'),
                subtitle: const Text(
                  'Kira gibi giderler her ay bu günde kendiliğinden yazılır.',
                ),
                value: _repeat,
                onChanged: (v) => setState(() => _repeat = v),
              ),
            Text(
              'Yazılan kayıt değiştirilmez; yanlışsa ters kayıtla düzeltilir.',
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _error!,
                  style: TextStyle(color: AgendaColors.deadlineText),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        key: const ValueKey('cash-save'),
        onPressed: _busy ? null : _save,
        child: const Text('Kaydet'),
      ),
    ],
  );
}

/// A bank account kept beside the book: its name, currency and balance as
/// the lawyer last read it. Told again whenever they like; never needed.
class _BankDialog extends StatefulWidget {
  const _BankDialog({
    required this.lawyer,
    required this.person,
    this.kept,
    this.currency = Currency.tl,
  });

  final BankAccount? kept;
  final Currency currency;
  final String lawyer, person;

  @override
  State<_BankDialog> createState() => _BankDialogState();
}

class _BankDialogState extends State<_BankDialog> {
  late final _name = TextEditingController(text: widget.kept?.name ?? '');
  late final _balance = TextEditingController(
    text: widget.kept == null
        ? ''
        : lira(widget.kept!.balance).replaceAll(' TL', ''),
  );
  late Currency _currency = widget.kept?.currency ?? widget.currency;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final balance = kurusOf(_balance.text.replaceAll('−', '-'));
    if (name.isEmpty) {
      setState(() => _error = 'Hesaba bir ad verin (Ziraat TL gibi).');
      return;
    }
    if (balance == null) {
      setState(() => _error = 'Bakiyeyi yazın.');
      return;
    }
    final now = DateTime.now();
    final data = <String, Object?>{
      'ad': name,
      'bakiye': balance,
      'tarih': now.toIso8601String(),
      if (_currency != Currency.tl) 'para': _currency.code,
    };
    final kept = widget.kept?.record;
    Navigator.pop(
      context,
      kept == null
          ? ClientRecord(
              id: Client.newId(),
              clientId: officeCashId,
              kind: ClientRecordKind.bank,
              data: data,
              created: now,
              by: widget.lawyer,
              updated: now,
              person: widget.person,
            )
          : kept.copyWith(data: data),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.kept == null ? 'Banka hesabı' : widget.kept!.name),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('bank-name'),
            controller: _name,
            autofocus: widget.kept == null,
            decoration: const InputDecoration(
              labelText: 'Hesabın adı',
              hintText: 'Ziraat TL, Garanti Euro…',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('bank-balance'),
                  controller: _balance,
                  autofocus: widget.kept != null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Bugünkü bakiye',
                    suffixText: _currency.sign,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CurrencyChoice(
                value: _currency,
                onChanged: (c) => setState(() => _currency = c),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'İsteğe bağlıdır. Bankaya bağlanılmaz; IBAN ya da hesap '
            'numarası istenmez. Bakiyeyi ne zaman isterseniz güncellersiniz.',
            style: TextStyle(fontSize: 12, color: AgendaColors.muted),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _error!,
                style: TextStyle(color: AgendaColors.deadlineText),
              ),
            ),
        ],
      ),
    ),
    actions: [
      if (widget.kept != null)
        TextButton(
          key: const ValueKey('bank-remove'),
          onPressed: () => Navigator.pop(
            context,
            widget.kept!.record.copyWith(removed: true),
          ),
          child: Text(
            'Kaldır',
            style: TextStyle(color: AgendaColors.deadlineText),
          ),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        key: const ValueKey('bank-save'),
        onPressed: _save,
        child: const Text('Kaydet'),
      ),
    ],
  );
}

/// Why a line is taken back; null when backed out.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _why = TextEditingController();

  @override
  void dispose() {
    _why.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ters kayıtla düzelt'),
    content: TextField(
      key: const ValueKey('cash-reason'),
      controller: _why,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Neden'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        key: const ValueKey('cash-reason-ok'),
        onPressed: () => Navigator.pop(context, _why.text),
        child: const Text('Düzelt'),
      ),
    ],
  );
}

/// The client a payment is of, and its case.
class _ClientPick extends StatefulWidget {
  const _ClientPick({required this.entries, required this.caseTitle});
  final List<ClientEntry> entries;
  final String Function(String key) caseTitle;

  @override
  State<_ClientPick> createState() => _ClientPickState();
}

class _ClientPickState extends State<_ClientPick> {
  String _query = '';
  ClientEntry? _client;
  String _case = '';

  @override
  Widget build(BuildContext context) {
    final q = UyapWebService.fold(_query.trim());
    final shown = [
      for (final e in widget.entries)
        if (q.isEmpty || UyapWebService.fold(e.name).contains(q)) e,
    ];
    final c = _client;
    return AlertDialog(
      title: const Text('Tahsilat'),
      content: SizedBox(
        width: 440,
        height: 400,
        child: c == null
            ? Column(
                children: [
                  TextField(
                    key: const ValueKey('cash-client-search'),
                    autofocus: true,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                      hintText: 'Müvekkil ara…',
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final e in shown)
                          ListTile(
                            key: ValueKey('cash-client-${e.key}'),
                            dense: true,
                            title: Text(titleName(e.name)),
                            subtitle: Text('${e.cases.length} dosya'),
                            onTap: () => setState(() {
                              _client = e;
                              _case = e.cases.length == 1
                                  ? e.cases.single.caseKey
                                  : '';
                            }),
                          ),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      titleName(c.name),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: TextButton(
                      onPressed: () => setState(() => _client = null),
                      child: const Text('Değiştir'),
                    ),
                  ),
                  Text(
                    'Hangi dosyanın?',
                    style: TextStyle(color: AgendaColors.muted),
                  ),
                  Expanded(
                    child: RadioGroup<String>(
                      groupValue: _case,
                      onChanged: (v) => setState(() => _case = v ?? ''),
                      child: ListView(
                        children: [
                          for (final x in c.cases)
                            RadioListTile<String>(
                              key: ValueKey('cash-case-${x.caseKey}'),
                              dense: true,
                              value: x.caseKey,
                              title: Text(widget.caseTitle(x.caseKey)),
                            ),
                          const RadioListTile<String>(
                            dense: true,
                            value: '',
                            title: Text('Dosyasız'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          key: const ValueKey('cash-client-ok'),
          onPressed: c == null
              ? null
              : () => Navigator.pop(context, (entry: c, caseKey: _case)),
          child: const Text('Devam'),
        ),
      ],
    );
  }
}

/// The monthly expenses, each stopped from the coming month on.
class _RepeatsDialog extends StatefulWidget {
  const _RepeatsDialog({required this.database});
  final PortalDatabase database;

  @override
  State<_RepeatsDialog> createState() => _RepeatsDialogState();
}

class _RepeatsDialogState extends State<_RepeatsDialog> {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final repeats = [
      for (final r in widget.database.allClientRecords())
        if (!r.removed &&
            r.kind == ClientRecordKind.cashRepeat &&
            r.clientId == officeCashId)
          r,
    ]..sort((a, b) => a.text('kategori').compareTo(b.text('kategori')));
    bool going(ClientRecord r) {
      final stop = DateTime.tryParse(r.text('bitis'));
      return stop == null || stop.isAfter(now);
    }

    return AlertDialog(
      title: const Text('Her ay tekrarlanan giderler'),
      content: SizedBox(
        width: 460,
        child: repeats.isEmpty
            ? Text(
                'Yok. Bir gider yazarken "Her ay tekrarla" seçilirse burada '
                'görünür.',
                style: TextStyle(color: AgendaColors.muted),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final r in repeats)
                    ListTile(
                      key: ValueKey('cash-repeat-${r.id}'),
                      title: Text(
                        [
                          r.text('kategori'),
                          if (r.text('aciklama').isNotEmpty) r.text('aciklama'),
                        ].join(' · '),
                      ),
                      subtitle: Text(
                        '${money(r.amount, r.currency)} · her ayın '
                        '${DateTime.tryParse(r.text('baslangic'))?.day ?? 1}. '
                        'günü · ${r.text('odeme')}'
                        '${going(r) ? '' : ' · durduruldu'}',
                      ),
                      trailing: going(r)
                          ? TextButton(
                              key: ValueKey('cash-repeat-stop-${r.id}'),
                              onPressed: () {
                                widget.database.saveClientRecord(
                                  r.copyWith(
                                    data: {
                                      ...r.data,
                                      'bitis': DateTime.now().toIso8601String(),
                                    },
                                  ),
                                );
                                setState(() {});
                              },
                              child: const Text('Durdur'),
                            )
                          : null,
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
      ],
    );
  }
}

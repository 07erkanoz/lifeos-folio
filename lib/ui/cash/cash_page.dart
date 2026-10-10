import 'dart:async';
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
import '../clients/client_accounts_view.dart' show MovementDialog;
import '../clients/clients_page.dart' show pickScan;
import '../portfolio/portfolio_rows.dart' show titleName;
import '../widgets/notice.dart';

String _two(int v) => v.toString().padLeft(2, '0');
String _day(DateTime t) => '${_two(t.day)}.${_two(t.month)}.${t.year}';
String _time(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// "15.000" from kuruş: TL is the column's.
String _plain(int kurus) => lira(kurus).replaceAll(' TL', '');

const _green = Color(0xFF1B6B3A), _purple = Color(0xFF5B3B9A);
const _trustFill = Color(0xFFF6F3FC), _trustLine = Color(0xFFE2DAF3);

Color _sideColor(CashSide s) => switch (s) {
  CashSide.income => _green,
  CashSide.expense => AgendaColors.deadlineText,
  CashSide.trust => _purple,
  CashSide.onBehalf => AgendaColors.taskText,
};

Color _sideFill(CashSide s) => switch (s) {
  CashSide.income => const Color(0xFFE6F4EC),
  CashSide.expense => const Color(0xFFFCEBEA),
  CashSide.trust => const Color(0xFFEFE9FA),
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
  List<({String key, String name, int owed, int held, bool late})> _balances =
      const [];
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
    });
  }

  String _caseTitle(String key) {
    final c = _db?.caseOf(key);
    return c == null ? key : '${c.number} · ${c.court}';
  }

  String _caseNumber(String key) => _db?.caseOf(key)?.number ?? key;

  List<CashLine> _ofMonth(DateTime m) => [
    for (final l in _lines)
      if (l.at.year == m.year && l.at.month == m.month) l,
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
        lawyer: widget.lawyer,
        person: widget.person,
        files: _files,
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
    final lines = _reports
        ? [
            for (final l in _lines)
              if (l.at.year == _year) l,
          ]
        : _ofMonth(_month);
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
              if (_reports) ..._report(wide) else ..._book(wide),
            ],
          ),
        );
      },
    );
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
          const Spacer(),
          for (final a in actions) ...[a, const SizedBox(width: 6)],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [title, const Spacer(), ...actions]),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: mode),
            const SizedBox(width: 8),
            period,
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
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
        ),
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
            style: const TextStyle(fontSize: 11.5, color: AgendaColors.muted),
          ),
      ],
    ),
  );

  List<Widget> _book(bool wide) {
    final month = _ofMonth(_month);
    final total = cashTotals(month);
    final before = cashTotals(
      _ofMonth(DateTime(_month.year, _month.month - 1)),
    );
    final owed = _balances.fold(0, (n, b) => n + (b.owed > 0 ? b.owed : 0));
    final held = _balances.fold(0, (n, b) => n + b.held);
    final late = _balances.where((b) => b.late).length;
    final holding = _balances.where((b) => b.held > 0).length;
    final kpis = [
      _kpi('Gelir', lira(total.income), _green, sub: 'ücret ve karşı vekâlet'),
      _kpi(
        'Gider',
        lira(total.expense),
        AgendaColors.deadlineText,
        sub: 'büronun giderleri',
      ),
      _kpi('Net', lira(total.net), null, sub: 'önceki ay ${lira(before.net)}'),
      _kpi(
        'Müvekkil alacağı',
        lira(owed),
        owed > 0 ? AgendaColors.deadlineText : null,
        sub: late > 0 ? '$late müvekkilin taksiti gecikmiş' : 'ücret ve masraf',
      ),
      _kpi(
        'Emanet',
        lira(held),
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
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
            const Text(
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
        style: const TextStyle(fontSize: 11, color: AgendaColors.muted),
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

  Widget? _menu(CashLine l) {
    final items = <PopupMenuEntry<String>>[
      if (l.fromClient && l.clientKey != null && widget.onOpenClient != null)
        const PopupMenuItem(value: 'muvekkil', child: Text('Müvekkili aç')),
      if (clientFilesOf(l.record).isNotEmpty)
        const PopupMenuItem(value: 'belge', child: Text('Belgeyi göster')),
      if (!l.fromClient && !l.struck)
        const PopupMenuItem(value: 'ters', child: Text('Ters kayıtla düzelt')),
    ];
    if (items.isEmpty) return null;
    return PopupMenuButton<String>(
      key: ValueKey('cash-line-${l.record.id}'),
      icon: const Icon(Icons.more_horiz_rounded, size: 20),
      onSelected: (v) => switch (v) {
        'muvekkil' => widget.onOpenClient!(l.clientKey!),
        'belge' => _receipt(l),
        _ => _reverse(l),
      },
      itemBuilder: (_) => items,
    );
  }

  TextStyle _struck(TextStyle s, CashLine l) => l.struck
      ? s.copyWith(
          decoration: TextDecoration.lineThrough,
          color: AgendaColors.muted,
        )
      : s;

  Widget _row(CashLine l) {
    const base = TextStyle(fontSize: 13);
    final who = [
      if (l.client.isNotEmpty) titleName(l.client),
      if (l.caseKey.isNotEmpty) _caseNumber(l.caseKey),
    ].join(' · ');
    Text sum(int v) => Text(
      v == 0 ? '' : _plain(v),
      textAlign: TextAlign.right,
      style: _struck(base.copyWith(color: _sideColor(l.side)), l),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AgendaColors.line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _wDate,
            child: Text(
              '${_day(l.at).substring(0, 5)} ${_time(l.at)}',
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
                    ? const Tooltip(
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

  Widget _tile(CashLine l) {
    final sub = [
      _day(l.at).substring(0, 5),
      if (l.client.isNotEmpty) titleName(l.client),
      if (l.caseKey.isNotEmpty) _caseNumber(l.caseKey),
      if (l.client.isEmpty && l.way.isNotEmpty) l.way,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: const BoxDecoration(
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
                  style: const TextStyle(
                    fontSize: 12,
                    color: AgendaColors.muted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${l.amount > 0 ? '+' : '−'}${_plain(l.amount.abs())}',
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
    final year = [
      for (final l in _lines)
        if (l.at.year == _year) l,
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
        if (b.owed > 0) b,
    ]..sort((a, b) => b.owed.compareTo(a.owed));
    final holding = [
      for (final b in _balances)
        if (b.held > 0) b,
    ]..sort((a, b) => b.held.compareTo(a.held));
    Widget title(String t, {String? right}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          if (right != null)
            Text(
              right,
              style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
            ),
        ],
      ),
    );
    Widget line(String a, String b, {Color? color, Widget? tag}) => Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: const BoxDecoration(
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
                for (var m = 0; m < 12; m++)
                  Expanded(
                    child: Tooltip(
                      message:
                          '${monthNames[m]}: gelir ${lira(months[m].income)}, '
                          'gider ${lira(months[m].expense)}',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (final (v, c) in [
                                (months[m].income, const Color(0xFF3E9C6B)),
                                (months[m].expense, const Color(0xFFC2523F)),
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
                            monthNames[m].substring(0, 3),
                            style: const TextStyle(
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
            'Yıl: gelir ${lira(total.income)} · gider ${lira(total.expense)} '
            '· net ${lira(total.net)}',
            style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
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
            const Text(
              'Bu yıl gider yazılmadı.',
              style: TextStyle(color: AgendaColors.muted),
            ),
          for (final c in cats) ...[
            line(c.key, _plain(c.value)),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: c.value / most,
                minHeight: 6,
                color: const Color(0xFFC2523F),
                backgroundColor: const Color(0xFFEEF0F4),
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
            const Text('Yok.', style: TextStyle(color: AgendaColors.muted)),
          ...rows.take(8),
        ],
      ),
      fill: trust ? _trustFill : null,
      line: trust ? _trustLine : null,
    );
    final receivable = list(
      'Müvekkil alacakları',
      _plain(owing.fold(0, (n, b) => n + b.owed)),
      [
        for (final b in owing)
          line(
            titleName(b.name),
            _plain(b.owed),
            color: AgendaColors.deadlineText,
            tag: b.late ? _late() : null,
          ),
      ],
    );
    final collected = list('En çok tahsilat', '$_year', [
      for (final p in payers) line(titleName(p.key), _plain(p.value)),
    ]);
    final trust = list(
      'Emanet bakiyeleri',
      _plain(holding.fold(0, (n, b) => n + b.held)),
      [
        for (final b in holding)
          line(titleName(b.name), _plain(b.held), color: _purple),
      ],
      trust: true,
    );
    if (!wide) {
      return [
        for (final w in [bars, expenses, receivable, collected, trust]) ...[
          w,
          const SizedBox(height: 10),
        ],
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
      color: const Color(0xFFFCEBEA),
      borderRadius: BorderRadius.circular(5),
    ),
    child: const Text(
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
  });
  final bool income;
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
            TextField(
              key: const ValueKey('cash-amount'),
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Tutar',
                suffixText: 'TL',
              ),
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
            const Text(
              'Yazılan kayıt değiştirilmez; yanlışsa ters kayıtla düzeltilir.',
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AgendaColors.deadlineText),
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
                  const Text(
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
            ? const Text(
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
                        '${lira(r.amount)} · her ayın '
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

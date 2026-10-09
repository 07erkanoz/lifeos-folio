import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/clients/client.dart';
import '../../services/clients/client_accounts.dart';
import '../../services/office/office_network.dart';
import '../../services/portal/portal_database.dart';
import '../../services/uyap/uyap_case_data.dart';
import '../../services/uyap/uyap_case_store.dart';
import '../../services/uyap/uyap_enforcement.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../tools/interest_page.dart';
import '../widgets/notice.dart';
import 'portfolio_rows.dart';

const _green = Color(0xFF1B6B3A), _purple = Color(0xFF5B3B9A);

/// "250.000,00" from lira.
String _tl(double v) {
  final kurus = (v * 100).round();
  final s = lira(kurus.abs()).replaceAll(' TL', '');
  return '${kurus < 0 ? '−' : ''}${s.contains(',') ? s : '$s,00'}';
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// A day as UYAP writes one: "21.09.2026", "2026-09-21", or the web's
/// "Sep 21, 2026 10:50:00 PM".
DateTime? uyapDay(String raw) {
  final en = RegExp(r'([A-Za-z]{3})\w* (\d{1,2}), (\d{4})').firstMatch(raw);
  if (en != null) {
    final m = _months[en.group(1)!.toLowerCase()];
    if (m != null) {
      return DateTime(int.parse(en.group(3)!), m, int.parse(en.group(2)!));
    }
  }
  return parseDay(raw);
}

/// An enforcement file (icra) as the lawyer follows it: where the debt
/// stands, its items, the money collected and paid out, its debtors and
/// its course, from what UYAP gave (docs: banaozel uyapweb.md §10).
class EnforcementView extends StatefulWidget {
  const EnforcementView({
    super.key,
    required this.record,
    required this.caseKey,
    required this.title,
    required this.database,
    this.lawyer = '',
    this.wide = true,
  });

  final UyapCaseRecord? record;
  final String caseKey, title, lawyer;
  final Future<PortalDatabase> Function() database;
  final bool wide;

  @override
  State<EnforcementView> createState() => _EnforcementViewState();
}

class _EnforcementViewState extends State<EnforcementView> {
  /// The payments out already written to a client's account, by their key.
  Set<String> _booked = const {};
  bool _allCourse = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBooked());
  }

  Future<void> _loadBooked() async {
    final db = await widget.database();
    final booked = {
      for (final r in db.allClientRecords())
        if (r.kind == ClientRecordKind.movement && !r.removed)
          if (r.text('kaynak').isNotEmpty) r.text('kaynak'),
    };
    if (mounted) setState(() => _booked = booked);
  }

  String _keyOf(UyapMoneyItem p) =>
      'uyap-reddiyat:${widget.caseKey}:${p.receipt.isNotEmpty ? p.receipt : '${p.date}|${p.amount}'}';

  /// A payment out of the file written to its client's account: money
  /// held for the client, or the fee the court gave the lawyer.
  Future<void> _book(UyapMoneyItem p) async {
    final db = await widget.database();
    final entry = db
        .clientEntries(lawyer: widget.lawyer)
        .where((e) => e.cases.any((c) => c.caseKey == widget.caseKey))
        .firstOrNull;
    if (!mounted) return;
    if (entry == null) {
      showNotice(
        context,
        'Bu dosyanın müvekkili bulunamadı.',
        detail: 'Müvekkiller sayfasında dosyayı müvekkile ekleyin.',
      );
      return;
    }
    final kind = await showDialog<MovementKind>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('${_tl(p.amount)} TL · ${titleName(entry.name)}'),
        children: [
          SimpleDialogOption(
            key: const ValueKey('book-trust'),
            onPressed: () => Navigator.pop(context, MovementKind.advanceIn),
            child: const ListTile(
              title: Text('Emanet: müvekkile ait'),
              subtitle: Text('Tahsil edilen alacak; müvekkile ödenecek.'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, MovementKind.counterFee),
            child: const ListTile(
              title: Text('Karşı vekâlet ücreti: avukata ait'),
              subtitle: Text('Büronun geliri olarak yazılır.'),
            ),
          ),
        ],
      ),
    );
    if (kind == null) return;
    var card = entry.client;
    if (card == null) {
      card = Client(
        id: Client.newId(),
        name: entry.name,
        updated: DateTime.now(),
        person: OfficeNetwork.instance.me,
      );
      db.saveClient(card);
    }
    final at = uyapDay(p.date) ?? DateTime.now();
    final now = DateTime.now();
    db.saveClientRecord(
      ClientRecord(
        id: Client.newId(),
        clientId: card.id,
        kind: ClientRecordKind.movement,
        data: {
          'dosya': widget.caseKey,
          'hesap': kind.code,
          'tutar': (p.amount * 100).round(),
          'zaman': at.toIso8601String(),
          'aciklama': [
            'UYAP reddiyatı',
            if (p.kind.isNotEmpty) p.kind,
            if (p.receipt.isNotEmpty) 'makbuz ${p.receipt}',
          ].join(' · '),
          'odeme': 'Havale / EFT',
          'kaynak': _keyOf(p),
        },
        created: now,
        by: widget.lawyer,
        updated: now,
        locked: true,
        person: OfficeNetwork.instance.me,
      ),
    );
    await _loadBooked();
    if (mounted) {
      showNotice(
        context,
        kind == MovementKind.advanceIn
            ? 'Emanet olarak müvekkil hesabına yazıldı.'
            : 'Karşı vekâlet ücreti olarak yazıldı.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    if (record == null) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: Text(
          'Dosya henüz UYAP\'tan çekilmedi. "UYAP\'tan tazele" ile borç '
          'hesabı, tahsilatlar ve borçlular gelir.',
          style: TextStyle(color: AgendaColors.muted),
        ),
      );
    }
    final e = record.enforcement;
    final account = e?.account ?? const UyapAccount();
    final facts = {for (final (k, v) in record.details.enforcement) k: v};
    double? fact(String k) => parseLira(facts[k] ?? '');
    // Without the account page, the particulars' sums.
    final total = account.total ?? fact('Alacak toplamı');
    final paid =
        account.paid ?? record.money?.collected ?? fact('Yapılmış tahsilat');
    final left =
        account.left ?? (total != null && paid != null ? total - paid : null);
    final share =
        account.share ??
        (total != null && total > 0 && paid != null
            ? (paid / total).clamp(0, 1).toDouble()
            : null);
    final debt = _box(
      'BORÇ DURUMU',
      right: e?.lines.isNotEmpty ?? false
          ? 'UYAP hesap bilgileri'
          : 'UYAP künyesi',
      [
        Wrap(
          spacing: 28,
          runSpacing: 8,
          children: [
            _big('Toplam alacak', total),
            _big('Tahsil edilen', paid, color: _green),
            _big('Bakiye borç', left, color: AgendaColors.deadlineText),
          ],
        ),
        if (share != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 9,
              color: const Color(0xFF3E9C6B),
              backgroundColor: const Color(0xFFEEF0F4),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '%${(share * 100).toStringAsFixed(1).replaceAll('.', ',')} '
            'tahsil edildi',
            style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
          ),
        ],
        const SizedBox(height: 8),
        _columns([
          _lines(
            'ALACAK KALEMLERİ',
            account.items.isNotEmpty
                ? [for (final l in account.items) (l.title, l.amount)]
                : [
                    for (final k in const [
                      'Faiz',
                      'Takip sonrası masraf',
                      'Vekâlet ücreti',
                    ])
                      if (fact(k) != null) (k, fact(k)),
                  ],
          ),
          _lines(
            'HARÇ VE VERGİLER',
            account.fees.isNotEmpty
                ? [for (final l in account.fees) (l.title, l.amount)]
                : [
                    if (fact('Tahsil harcı') != null)
                      ('Tahsil harcı', fact('Tahsil harcı')),
                  ],
            total: true,
          ),
        ]),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey('enforcement-interest'),
            onPressed: () {
              final base = [
                for (final l in account.items)
                  if (RegExp(r'asil|kesinles')
                      .hasMatch(l.label.toLowerCase().replaceAll('ı', 'i')))
                    l,
              ].firstOrNull;
              InterestPage.open(
                context,
                title: widget.title,
                principal: base?.amount == null
                    ? null
                    : (base!.amount! * 100).round(),
                from: parseDay(record.details.openedOn),
              );
            },
            icon: const Icon(Icons.percent_rounded, size: 18),
            label: const Text('Güncel borcu hesapla'),
          ),
        ),
      ],
    );
    final money = _money(record.money);
    final debtors = _debtors(e?.debtors ?? const []);
    final course = _course(record);
    if (!widget.wide) {
      return Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            debt,
            const SizedBox(height: 10),
            money,
            const SizedBox(height: 10),
            debtors,
            const SizedBox(height: 10),
            course,
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 27, child: debt),
              const SizedBox(width: 10),
              Expanded(flex: 20, child: money),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 27, child: course),
              const SizedBox(width: 10),
              Expanded(flex: 20, child: debtors),
            ],
          ),
        ],
      ),
    );
  }

  Widget _box(String title, List<Widget> children, {String? right}) =>
      Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AgendaColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5,
                    color: AgendaColors.muted,
                  ),
                ),
                const Spacer(),
                if (right != null)
                  Text(
                    right,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AgendaColors.muted,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      );

  Widget _big(String label, double? v, {Color? color}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
      ),
      Text(
        v == null ? '—' : '${_tl(v)} TL',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: v == null ? AgendaColors.muted : color,
        ),
      ),
    ],
  );

  Widget _columns(List<Widget> parts) => LayoutBuilder(
    builder: (context, box) => box.maxWidth < 460
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, p) in parts.indexed) ...[
                if (i > 0) const SizedBox(height: 8),
                p,
              ],
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, p) in parts.indexed) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(child: p),
              ],
            ],
          ),
  );

  Widget _row(String a, String b, {bool bold = false, Color? color}) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF0F1F5))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                a,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: bold ? FontWeight.w700 : null,
                ),
              ),
            ),
            Text(
              b,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: bold ? FontWeight.w700 : null,
                color: color,
              ),
            ),
          ],
        ),
      );

  Widget _lines(
    String title,
    List<(String, double?)> rows, {
    bool total = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: .5,
          color: AgendaColors.muted,
        ),
      ),
      const SizedBox(height: 2),
      if (rows.isEmpty)
        const Text(
          'UYAP göstermedi.',
          style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
        ),
      for (final (a, v) in rows) _row(a, v == null ? '—' : _tl(v)),
      if (total && rows.length > 1)
        _row(
          'Toplam',
          _tl(rows.fold<double>(0, (n, r) => n + (r.$2 ?? 0))),
          bold: true,
        ),
    ],
  );

  Widget _money(UyapCaseMoney? m) {
    final items =
        <({UyapMoneyItem item, bool out, DateTime? at})>[
          for (final c in m?.collections ?? const <UyapMoneyItem>[])
            (item: c, out: false, at: uyapDay(c.date)),
          for (final p in m?.payments ?? const <UyapMoneyItem>[])
            (item: p, out: true, at: uyapDay(p.date)),
        ]..sort(
          (a, b) => (b.at ?? DateTime(1900)).compareTo(a.at ?? DateTime(1900)),
        );
    final unbooked = [
      for (final i in items)
        if (i.out && !_booked.contains(_keyOf(i.item))) i.item,
    ];
    final collected = m?.collected, out = m?.paidOut;
    return _box('TAHSİLAT VE REDDİYAT', right: '${items.length}', [
      if (items.isEmpty)
        const Text(
          'Tahsilat ya da reddiyat yok.',
          style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
        ),
      for (final i in items.take(8))
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFF0F1F5))),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 82,
                child: Text(
                  i.at == null ? i.item.date : dayText(i.at!),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              Container(
                width: 70,
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: i.out
                        ? const Color(0xFFEFE9FA)
                        : const Color(0xFFE6F4EC),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    i.out ? 'Reddiyat' : 'Tahsilat',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: i.out ? _purple : _green,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  [
                    if (i.item.kind.isNotEmpty) i.item.kind,
                    if (i.item.payer.isNotEmpty) i.item.payer,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              Text(
                _tl(i.item.amount),
                style: TextStyle(
                  fontSize: 12.5,
                  color: i.out ? _purple : _green,
                ),
              ),
            ],
          ),
        ),
      if (items.length > 8)
        Text(
          've ${items.length - 8} kayıt daha',
          style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
        ),
      if (collected != null && out != null)
        _row(
          'Dosyada kalan (tahsilat − reddiyat)',
          _tl(collected - out),
          bold: true,
        ),
      for (final p in unbooked.take(3))
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.fromLTRB(8, 2, 2, 2),
          decoration: BoxDecoration(
            color: const Color(0xFFFCEBEA),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${p.date.split(' ').first} reddiyatı (${_tl(p.amount)} TL) '
                  'müvekkil hesabına işlenmedi.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AgendaColors.deadlineText,
                  ),
                ),
              ),
              TextButton(
                key: ValueKey('book-${_keyOf(p)}'),
                onPressed: () => _book(p),
                child: const Text('Hesaba işle'),
              ),
            ],
          ),
        ),
    ]);
  }

  Widget _debtors(List<UyapDebtor> debtors) => _box(
    'BORÇLULAR',
    right: debtors.isEmpty ? null : '${debtors.length}',
    [
      if (debtors.isEmpty)
        const Text(
          'UYAP borçlu listesi gelmedi; "UYAP\'tan tazele" ile çekilir.',
          style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
        ),
      for (final d in debtors)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFF0F1F5))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: titleName(d.name),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (d.idNo.isNotEmpty)
                      TextSpan(
                        text: '  ${d.body ? 'VKN' : 'TCKN'} ${d.idNo}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AgendaColors.muted,
                        ),
                      ),
                  ],
                ),
                style: const TextStyle(fontSize: 12.5),
              ),
              if (d.dead || d.moved || d.warning)
                Wrap(
                  spacing: 6,
                  children: [
                    if (d.dead)
                      _flag('Ölüm kaydı var', AgendaColors.deadlineText),
                    if (d.moved)
                      _flag(
                        d.movedWhy.isEmpty
                            ? 'Adresi değişmiş'
                            : 'Adresi değişmiş · ${d.movedWhy}',
                        AgendaColors.taskText,
                      ),
                    if (d.warning) _flag('UYAP uyarısı', AgendaColors.taskText),
                  ],
                ),
            ],
          ),
        ),
      const SizedBox(height: 6),
      const Text(
        'Borçlu sorguları (araç, tapu, banka, SGK) UYAP\'ta dosya başına '
        'günde 5 ücretsiz, sonrası ücretlidir; burada kendiliğinden '
        'yapılmaz.',
        style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
      ),
    ],
  );

  Widget _flag(String text, Color color) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );

  /// The file's course from what is kept: its documents and the money in
  /// and out, newest first. UYAP's own course (safahat) is counted and paid
  /// for beyond a number, and is not asked.
  Widget _course(UyapCaseRecord record) {
    final events = <({DateTime at, String text, Color color})>[
      for (final d in record.documents)
        if (uyapDay(d.sentToSystem.isNotEmpty ? d.sentToSystem : d.approved)
            case final at?)
          (at: at, text: d.title, color: AgendaColors.hearing),
      for (final c in record.money?.collections ?? const <UyapMoneyItem>[])
        if (uyapDay(c.date) case final at?)
          (
            at: at,
            text:
                'Tahsilat ${_tl(c.amount)} TL'
                '${c.kind.isEmpty ? '' : ' · ${c.kind}'}',
            color: _green,
          ),
      for (final p in record.money?.payments ?? const <UyapMoneyItem>[])
        if (uyapDay(p.date) case final at?)
          (
            at: at,
            text:
                'Reddiyat ${_tl(p.amount)} TL'
                '${p.kind.isEmpty ? '' : ' · ${p.kind}'}',
            color: _purple,
          ),
    ]..sort((a, b) => b.at.compareTo(a.at));
    final shown = _allCourse ? events : events.take(8).toList();
    return _box('DOSYA SEYRİ', right: 'evraklar ve para hareketleri', [
      if (events.isEmpty)
        const Text(
          'Henüz bir şey yok.',
          style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
        ),
      for (final ev in shown)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5, right: 8),
                child: Icon(Icons.circle, size: 8, color: ev.color),
              ),
              SizedBox(
                width: 78,
                child: Text(
                  dayText(ev.at),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AgendaColors.muted,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  ev.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      if (events.length > 8)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _allCourse = !_allCourse),
            child: Text(_allCourse ? 'Daha az' : 'Tümü ${events.length}'),
          ),
        ),
    ]);
  }
}

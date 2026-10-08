import 'package:flutter/material.dart';

import '../../services/clients/client.dart';
import '../../services/clients/client_accounts.dart';
import '../../services/clients/client_files.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import 'clients_page.dart' show pickScan;

String _two(int v) => v.toString().padLeft(2, '0');
String _day(DateTime t) => '${_two(t.day)}.${_two(t.month)}.${t.year}';
String _time(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// A client's accounts, a case at a time: each case's fee, advance and the
/// costs the lawyer met apart (docs/design/muvekkil-taslak).
class ClientAccountsView extends StatelessWidget {
  const ClientAccountsView({
    super.key,
    required this.client,
    required this.records,
    required this.cases,
    required this.onMovement,
    required this.onFee,
    required this.onReverse,
    this.onOpen,
    this.onStatement,
    this.titleOf,
    this.onPaper,
  });

  /// A paper made for a case and opened in the editor: 'sozlesme' (the
  /// fee agreement), 'ibra' (its release); for a movement, 'tahsilat'.
  final void Function(String paper, String caseKey, ClientRecord? movement)?
  onPaper;

  /// A case's title by its key, for an account of a case no longer listed.
  final String Function(String caseKey)? titleOf;

  /// A case's statement, to give the client.
  final void Function(String caseKey)? onStatement;

  /// A movement's receipt seen, printed or shared.
  final void Function(ClientRecord movement)? onOpen;

  final Client client;
  final List<ClientRecord> records;

  /// The client's cases: key and title.
  final List<({String key, String title})> cases;

  /// A movement to write, for the case given.
  final void Function(String caseKey) onMovement;
  final void Function(String caseKey, ClientRecord? kept) onFee;
  final void Function(ClientRecord movement) onReverse;

  @override
  Widget build(BuildContext context) {
    final accounts = caseAccounts(records);
    final now = DateTime.now();
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final c in [
          ...cases,
          // Accounts of cases no longer the client's, and of none.
          for (final k in accounts.keys)
            if (!cases.any((c) => c.key == k))
              (key: k, title: k.isEmpty ? 'Dosyasız' : (titleOf?.call(k) ?? k)),
        ])
          _account(
            context,
            c.title,
            c.key,
            accounts[c.key] ?? CaseAccount(c.key, null, const []),
            now,
          ),
      ],
    );
  }

  Widget _account(
    BuildContext context,
    String title,
    String key,
    CaseAccount a,
    DateTime now,
  ) {
    final instalments = a.instalments(now);
    final late = instalments.where((t) => t.late).length;
    String agreed() {
      final fixed = a.feeAgreed, share = a.feeShare;
      if (a.fee == null) return 'Ücret anlaşması yok';
      return [
        if (fixed > 0) 'Sabit ${lira(fixed)}',
        if (share > 0) '%$share',
        if (instalments.isNotEmpty) '${instalments.length} taksit',
      ].join(' + ');
    }

    return Card(
      key: ValueKey('account-$key'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AgendaColors.line),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Wrap(
          spacing: 10,
          children: [
            _amount('Ücret kalan', a.feeOwed, owed: true),
            _amount('Avans', a.advanceLeft),
            if (a.lawyerOwed != 0)
              _amount('Avukat masrafı', a.lawyerOwed, owed: true),
            if (late > 0)
              Text(
                '$late taksit gecikti',
                style: const TextStyle(
                  color: AgendaColors.deadline,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
          ],
        ),
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.handshake_outlined, size: 20),
            title: Text(agreed()),
            subtitle: a.fee?.text('not').isNotEmpty ?? false
                ? Text(a.fee!.text('not'))
                : null,
            trailing: Wrap(
              children: [
                if (onPaper != null)
                  PopupMenuButton<String>(
                    key: ValueKey('papers-$key'),
                    tooltip: 'Belge hazırla',
                    icon: const Icon(Icons.description_outlined, size: 20),
                    onSelected: (v) => onPaper!(v, key, null),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'sozlesme',
                        child: Text('Avukatlık ücret sözleşmesi'),
                      ),
                      PopupMenuItem(value: 'ibra', child: Text('İbraname')),
                    ],
                  ),
                if (onStatement != null && a.movements.isNotEmpty)
                  TextButton(
                    key: ValueKey('statement-$key'),
                    onPressed: () => onStatement!(key),
                    child: const Text('Döküm'),
                  ),
                TextButton(
                  key: ValueKey('fee-$key'),
                  onPressed: () => onFee(key, a.fee),
                  child: Text(a.fee == null ? 'Anlaşma ekle' : 'Değiştir'),
                ),
              ],
            ),
          ),
          for (final t in instalments)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(
                t.paid
                    ? Icons.check_circle_rounded
                    : t.late
                    ? Icons.error_outline_rounded
                    : Icons.schedule_rounded,
                size: 18,
                color: t.paid
                    ? AgendaColors.ok
                    : t.late
                    ? AgendaColors.deadline
                    : AgendaColors.muted,
              ),
              title: Text('Taksit · ${_day(t.due)}'),
              trailing: Text(lira(t.amount)),
            ),
          const Divider(height: 1),
          if (a.movements.isEmpty)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Hareket yok.',
                style: TextStyle(color: AgendaColors.muted),
              ),
            ),
          for (final m in a.movements) _movement(m, a.reversed),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: TextButton.icon(
                key: ValueKey('movement-$key'),
                onPressed: () => onMovement(key),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Hareket ekle'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _amount(String label, int value, {bool owed = false}) => Text(
    '$label ${lira(value)}',
    style: TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: value == 0
          ? AgendaColors.muted
          : owed == value > 0
          ? AgendaColors.deadlineText
          : const Color(0xFF1B6B3A),
    ),
  );

  Widget _movement(ClientRecord m, Set<String> reversed) {
    final kind = m.movement;
    final gone = reversed.contains(m.id) || m.reverses.isNotEmpty;
    final sign = (kind?.sign ?? 1) * (m.reverses.isNotEmpty ? -1 : 1);
    final detail = [
      '${_day(m.at)} ${_time(m.at)}',
      if (m.text('odeme').isNotEmpty) m.text('odeme'),
      if (m.text('makbuz').isNotEmpty) 'makbuz ${m.text('makbuz')}',
      if (clientFilesOf(m).isNotEmpty) 'belge ekli',
      if (m.by.isNotEmpty) m.by,
    ].join(' · ');
    return ListTile(
      key: ValueKey('move-${m.id}'),
      dense: true,
      onTap: onOpen == null || clientFilesOf(m).isEmpty
          ? null
          : () => onOpen!(m),
      title: Text(
        [
          if (m.reverses.isNotEmpty) 'Düzeltme ·',
          kind?.label ?? '?',
          if (m.text('aciklama').isNotEmpty) '· ${m.text('aciklama')}',
        ].join(' '),
        style: TextStyle(
          decoration: gone && m.reverses.isEmpty
              ? TextDecoration.lineThrough
              : null,
        ),
      ),
      subtitle: Text(detail, style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${sign > 0 ? '+' : '−'}${lira(m.amount)}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: gone
                  ? AgendaColors.muted
                  : sign > 0
                  ? const Color(0xFF1B6B3A)
                  : AgendaColors.deadlineText,
            ),
          ),
          if (!gone)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'tahsilat'
                  ? onPaper?.call('tahsilat', m.text('dosya'), m)
                  : onReverse(m),
              itemBuilder: (_) => [
                if (onPaper != null && (kind?.sign ?? 0) > 0)
                  const PopupMenuItem(
                    value: 'tahsilat',
                    child: Text('Tahsilat belgesi'),
                  ),
                const PopupMenuItem(
                  value: 'ters',
                  child: Text('Ters kayıtla düzelt'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Money in or out of a case's account, written once and never changed.
class MovementDialog extends StatefulWidget {
  const MovementDialog({
    super.key,
    required this.client,
    required this.caseKey,
    required this.lawyer,
    required this.person,
    required this.files,
  });

  final Client client;
  final String caseKey, lawyer, person;
  final ClientFiles files;

  @override
  State<MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<MovementDialog> {
  static const _ways = ['Nakit', 'Havale / EFT', 'Kredi kartı', 'Çek'];
  var _kind = MovementKind.feePaid;
  String? _way = _ways.first;
  DateTime _at = DateTime.now();
  final _amount = TextEditingController();
  final _what = TextEditingController();
  final _receipt = TextEditingController();
  ClientFile? _file;
  String? _error;

  @override
  void dispose() {
    for (final c in [_amount, _what, _receipt]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAt() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (!mounted) return;
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

  Future<void> _attach() async {
    final path = await pickScan(context, 'Dekont, makbuz ya da fiş');
    if (path == null) return;
    final kept = await widget.files.keep(widget.client.id, path);
    if (mounted) setState(() => _file = kept);
  }

  void _save() {
    final amount = kurusOf(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Tutarı yazın.');
      return;
    }
    final now = DateTime.now();
    Navigator.pop(
      context,
      ClientRecord(
        id: Client.newId(),
        clientId: widget.client.id,
        kind: ClientRecordKind.movement,
        data: {
          'dosya': widget.caseKey,
          'hesap': _kind.code,
          'tutar': amount,
          'zaman': _at.toIso8601String(),
          if (_way != null && _kind.sign > 0) 'odeme': _way,
          if (_kind == MovementKind.costByLawyer) 'odeme': 'Avukat ödedi',
          if (_kind == MovementKind.costFromAdvance) 'odeme': 'Avanstan',
          'aciklama': _what.text.trim(),
          'makbuz': _receipt.text.trim(),
          if (_file != null) 'ekler': [clientFileJson(_file!)],
        },
        created: now,
        by: widget.lawyer,
        updated: now,
        locked: true,
        person: widget.person,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Hareket'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<MovementKind>(
              key: const ValueKey('movement-kind'),
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Ne'),
              items: [
                for (final k in MovementKind.values)
                  DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              onChanged: (v) => setState(() => _kind = v ?? _kind),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('movement-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Tutar (TL)',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pickAt,
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: Text('${_day(_at)} ${_time(_at)}'),
            ),
            if (_kind.sign > 0) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _way,
                decoration: const InputDecoration(labelText: 'Ödeme şekli'),
                items: [
                  for (final w in _ways)
                    DropdownMenuItem(value: w, child: Text(w)),
                ],
                onChanged: (v) => setState(() => _way = v),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _what,
              decoration: const InputDecoration(
                labelText: 'Açıklama (bilirkişi ücreti, 2. taksit…)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _receipt,
              decoration: const InputDecoration(labelText: 'Makbuz no'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _attach,
              icon: const Icon(Icons.attach_file_rounded, size: 18),
              label: Text(_file?.name ?? 'Dekont / makbuz ekle'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Kaydedilen hareket değiştirilemez; yanlışsa ters kayıtla '
              'düzeltilir. Yazıldığı an ve yazan kayda geçer.',
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
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
        key: const ValueKey('movement-save'),
        onPressed: _save,
        child: const Text('Kaydet'),
      ),
    ],
  );
}

/// A case's fee agreed: fixed, a share of what is won, or both; and its
/// instalments, made from a count, a first day and months between.
class FeeDialog extends StatefulWidget {
  const FeeDialog({
    super.key,
    required this.client,
    required this.caseKey,
    required this.lawyer,
    required this.person,
    this.kept,
  });

  final Client client;
  final String caseKey, lawyer, person;
  final ClientRecord? kept;

  @override
  State<FeeDialog> createState() => _FeeDialogState();
}

class _FeeDialogState extends State<FeeDialog> {
  // The kuruş shown too: one saved again unchanged keeps them.
  late final _fixed = TextEditingController(
    text: (widget.kept?.data['tutar'] as int?) == null
        ? ''
        : lira(widget.kept!.data['tutar'] as int).replaceAll(' TL', ''),
  );
  late final _share = TextEditingController(
    text: '${widget.kept?.data['yuzde'] ?? ''}',
  );
  late final _count = TextEditingController(
    text: '${(widget.kept?.data['taksitler'] as List?)?.length ?? 1}',
  );
  late final _note = TextEditingController(
    text: widget.kept?.text('not') ?? '',
  );

  /// The plan's first day as it was; today for a new agreement.
  late DateTime _first = () {
    final plan = widget.kept?.data['taksitler'];
    if (plan is List && plan.isNotEmpty && plan.first is Map) {
      final d = DateTime.tryParse('${(plan.first as Map)['tarih']}');
      if (d != null) return d;
    }
    return DateTime.now();
  }();

  @override
  void dispose() {
    for (final c in [_fixed, _share, _count, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final fixed = kurusOf(_fixed.text) ?? 0;
    final share = num.tryParse(_share.text.replaceAll(',', '.')) ?? 0;
    final count = (int.tryParse(_count.text) ?? 1).clamp(1, 60);
    final each = fixed ~/ count;
    // The same day of each month, or the month's last when it has none
    // (the 31st of January, then the 28th of February).
    DateTime monthOn(int i) {
      final last = DateTime(_first.year, _first.month + i + 1, 0).day;
      return DateTime(
        _first.year,
        _first.month + i,
        _first.day > last ? last : _first.day,
      );
    }

    final kept = widget.kept;
    final keptPlan = kept?.data['taksitler'];
    // The plan unchanged (only the note changed): kept as it was.
    final same =
        kept != null &&
        keptPlan is List &&
        kept.data['tutar'] == fixed &&
        keptPlan.length == (fixed > 0 ? count : 0) &&
        (keptPlan.isEmpty ||
            DateTime.tryParse('${(keptPlan.first as Map)['tarih']}') == _first);
    final plan = same
        ? keptPlan
        : [
            if (fixed > 0)
              for (var i = 0; i < count; i++)
                {
                  'tarih': monthOn(i).toIso8601String(),
                  // The rest of the division on the last.
                  'tutar': i == count - 1 ? fixed - each * (count - 1) : each,
                },
          ];
    final data = {
      'dosya': widget.caseKey,
      'tutar': fixed,
      'yuzde': share,
      'taksitler': plan,
      'not': _note.text.trim(),
    };
    final now = DateTime.now();
    Navigator.pop(
      context,
      kept == null
          ? ClientRecord(
              id: Client.newId(),
              clientId: widget.client.id,
              kind: ClientRecordKind.fee,
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
    title: const Text('Ücret anlaşması'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('fee-fixed'),
              controller: _fixed,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Sabit ücret (TL)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _share,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Sonuçtan pay (%) — yoksa boş',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('fee-count'),
                    controller: _count,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Taksit sayısı',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _first,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (d != null && mounted) setState(() => _first = d);
                    },
                    child: Text('İlk taksit ${_day(_first)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Taksitler birer ay arayla yazılır.',
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Not'),
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
        key: const ValueKey('fee-save'),
        onPressed: _save,
        child: const Text('Kaydet'),
      ),
    ],
  );
}

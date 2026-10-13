import 'package:flutter/material.dart';

import '../../services/clients/client_accounts.dart';
import '../../services/enforcement/enforcement_ledger.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../widgets/folio_dialog.dart';

String _two(int v) => v.toString().padLeft(2, '0');
String _day(DateTime t) => '${_two(t.day)}.${_two(t.month)}.${t.year}';

/// What the lawyer wrote of a payment made outside the office or a claim
/// waived, and where the money goes ([target]: held for the client when
/// null, else taken as that fee).
typedef LedgerInput = ({
  LedgerKind kind,
  int amount,
  DateTime at,
  String debtor,
  String way,
  bool whole,
  String note,
  MovementKind? target,
});

/// A payment made outside the office, or a claim waived, written in the
/// file's own account in Folio.
class LedgerDialog extends StatefulWidget {
  const LedgerDialog({
    super.key,
    required this.kind,
    this.debtors = const [],
    this.left,
    this.editing,
    this.target,
  });

  final LedgerKind kind;
  final List<String> debtors;

  /// The debt as Folio counts it, in kuruş; null while not known.
  final int? left;

  /// The line being corrected, its values filled in; null for a new one.
  /// Corrected, no papers are offered: they are made from its menu.
  final LedgerEntry? editing;

  /// Where [editing]'s money was written: null for held for the client.
  final MovementKind? target;

  @override
  State<LedgerDialog> createState() => _LedgerDialogState();
}

class _LedgerDialogState extends State<LedgerDialog> {
  static const _ways = ['Nakit', 'Havale / EFT', 'Kredi kartı'];
  late final _amount = TextEditingController(
    text: switch (widget.editing) {
      final e? => plainMoney(e.amount, Currency.tl).replaceAll(' ', ''),
      null => '',
    },
  );
  late final _note = TextEditingController(text: widget.editing?.note ?? '');
  late DateTime _at = widget.editing?.at ?? DateTime.now();
  late String _debtor =
      widget.editing?.debtor ??
      (widget.debtors.length == 1 ? widget.debtors.first : '');
  late String _way = switch (widget.editing?.way) {
    final w? when w.isNotEmpty => w,
    _ => _ways.first,
  };
  late bool _whole = widget.editing?.whole ?? false;
  late MovementKind? _target = widget.target;
  String? _error;

  bool get _external => widget.kind == LedgerKind.external;
  bool get _editing => widget.editing != null;

  /// The debtors offered: the file's, and one written before that the file
  /// no longer lists.
  List<String> get _debtors => [
    ...widget.debtors,
    if (_debtor.isNotEmpty && !widget.debtors.contains(_debtor)) _debtor,
  ];

  /// The ways offered, with one written before that is not among them.
  List<String> get _wayChoices => [..._ways, if (!_ways.contains(_way)) _way];

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _typed(String text) {
    final v = kurusOf(text);
    final left = widget.left;
    if (v != null && left != null && left > 0) {
      setState(() => _whole = v >= left);
    }
  }

  Future<void> _pick() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (day != null && mounted) setState(() => _at = day);
  }

  void _save() {
    final amount = kurusOf(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Tutarı yazın.');
      return;
    }
    Navigator.pop<LedgerInput>(context, (
      kind: widget.kind,
      amount: amount,
      at: _at,
      debtor: _debtor,
      way: _external ? _way : '',
      whole: _whole,
      note: _note.text.trim(),
      target: _external ? _target : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.left;
    final muted = TextStyle(fontSize: 12, color: AgendaColors.muted);
    final debtors = _debtors;
    return FolioDialog(
      title: _editing ? '${widget.kind.label} düzelt' : widget.kind.label,
      subtitle: _external
          ? 'Borçlunun büroya doğrudan yaptığı ödeme'
          : 'Alacağın bir kısmından ya da tamamından feragat',
      icon: _external
          ? Icons.payments_outlined
          : Icons.remove_circle_outline_rounded,
      width: 480,
      onClose: () => Navigator.pop(context),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          key: const ValueKey('ledger-save'),
          onPressed: _save,
          child: const Text('Kaydet'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('ledger-amount'),
                  controller: _amount,
                  autofocus: true,
                  onChanged: _typed,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Tutar',
                    suffixText: 'TL',
                    errorText: _error,
                    helperText: left == null
                        ? null
                        : "Folio'ya göre kalan borç ${lira(left)}",
                  ),
                ),
              ),
              if (left != null && left > 0) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton(
                    key: const ValueKey('ledger-all'),
                    onPressed: () => setState(() {
                      _amount.text = plainMoney(
                        left,
                        Currency.tl,
                      ).replaceAll(' ', '');
                      _whole = true;
                    }),
                    child: const Text('Tamamı'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pick,
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(
                    _external
                        ? 'Ödeme tarihi ${_day(_at)}'
                        : 'Feragat tarihi ${_day(_at)}',
                  ),
                ),
              ),
              if (_external) ...[
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _way,
                  items: [
                    for (final w in _wayChoices)
                      DropdownMenuItem(value: w, child: Text(w)),
                  ],
                  onChanged: (v) => setState(() => _way = v ?? _way),
                ),
              ],
            ],
          ),
          if (debtors.isNotEmpty) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: const ValueKey('ledger-debtor'),
              initialValue: _debtor,
              decoration: InputDecoration(
                labelText: _external ? 'Ödeyen borçlu' : 'Borçlu',
              ),
              items: [
                if (debtors.length > 1 || _debtor.isEmpty)
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Bütün borçlular'),
                  ),
                for (final d in debtors)
                  DropdownMenuItem(value: d, child: Text(d)),
              ],
              onChanged: (v) => setState(() => _debtor = v ?? ''),
            ),
          ],
          SwitchListTile(
            key: const ValueKey('ledger-whole'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              _external
                  ? 'Dosya borcunun tamamı ödendi'
                  : 'Alacağın tamamından feragat',
            ),
            subtitle: Text(
              _external
                  ? 'Talep, dosyanın kapatılmasını ister.'
                  : 'Talep, dosyanın feragat nedeniyle kapatılmasını '
                        'ister.',
            ),
            value: _whole,
            onChanged: (v) => setState(() => _whole = v),
          ),
          if (_external) ...[
            Text('Para nereye yazılsın?', style: muted),
            RadioGroup<MovementKind?>(
              groupValue: _target,
              onChanged: (v) => setState(() => _target = v),
              child: const Column(
                children: [
                  RadioListTile<MovementKind?>(
                    key: ValueKey('ledger-target-held'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: null,
                    title: Text('Emanet (müvekkile ait)'),
                  ),
                  RadioListTile<MovementKind?>(
                    key: ValueKey('ledger-target-fee'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: MovementKind.toFee,
                    title: Text('Vekâlet ücretine mahsup'),
                  ),
                  RadioListTile<MovementKind?>(
                    key: ValueKey('ledger-target-counter'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: MovementKind.toCounterFee,
                    title: Text('Karşı vekâlet ücretine mahsup'),
                  ),
                ],
              ),
            ),
            Text(
              'Emanet yazılan para sonra Kasa\'da sağ tıklayarak '
              'ücrete mahsup edilebilir.',
              style: muted,
            ),
          ] else
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Açıklama (isteğe bağlı)',
              ),
            ),
          // The papers are printed from the payment's card ("Yazdır"),
          // when wanted: none is made, nor opened, on saving.
          const SizedBox(height: 10),
          if (_editing && _external)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Tutar, tarih ya da paranın yazıldığı yer değişirse '
                'Kasa\'daki eski kayıt ters kayıtla düzeltilir ve yenisi '
                'yazılır.',
                style: muted,
              ),
            ),
          if (!_editing)
            Text(
              _external
                  ? 'Vekâletnamede ahzu kabz ve ibra yetkisi bulunmalıdır. '
                        'Ödeme, UYAP\'ta tahsilat olarak görününce '
                        'kendiliğinden resmîleşir.'
                  : 'Vekâletnamede feragat yetkisi bulunmalıdır.',
              style: muted,
            ),
        ],
      ),
    );
  }
}

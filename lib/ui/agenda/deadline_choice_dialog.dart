import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/legal/deadlines/deadline_service.dart';
import '../../services/legal/deadlines/kural_bilgisi.dart';
import '../../services/legal/deadlines/mahkeme_kategori.dart';
import '../../services/legal/deadlines/yasal_sure.dart';
import '../../services/uets/deadline_choice.dart';
import 'agenda_page.dart' show AgendaColors;

/// The lawyer's own deadline for a notice: a rule chosen (or a time of
/// their own), its start, and the last day reckoned before it is kept.
/// Kept, it is confirmed: choosing it is the lawyer's word. [replacing] is
/// the deadline Folio made that it is put in place of; [hint], the words
/// of the notice's documents, preselects a way of appeal they name.
Future<DeadlineChoice?> askDeadlineChoice(
  BuildContext context, {
  required String noticeId,
  required DateTime served,
  required MahkemeKategorisi? category,
  String hint = '',
  String? replacing,
  String? replacingRule,
}) => showDialog<DeadlineChoice>(
  context: context,
  builder: (_) => _DeadlineChoiceDialog(
    noticeId: noticeId,
    served: served,
    category: category,
    hint: hint,
    replacing: replacing,
    replacingRule: replacingRule,
  ),
);

class _DeadlineChoiceDialog extends StatefulWidget {
  const _DeadlineChoiceDialog({
    required this.noticeId,
    required this.served,
    required this.category,
    required this.hint,
    this.replacing,
    this.replacingRule,
  });

  final String noticeId;
  final DateTime served;
  final MahkemeKategorisi? category;
  final String hint;
  final String? replacing, replacingRule;

  @override
  State<_DeadlineChoiceDialog> createState() => _DeadlineChoiceDialogState();
}

class _DeadlineChoiceDialogState extends State<_DeadlineChoiceDialog> {
  late final _groups = [
    for (final g in choosableRules)
      if (g.for_.contains(widget.category ?? MahkemeKategorisi.bilinmeyen)) g,
  ];

  /// The rule chosen, by its id; 'ozel' for the lawyer's own time.
  late String _rule;
  String? _hint;
  final _amount = TextEditingController(text: '10');
  final _purpose = TextEditingController();
  SureBirimi _unit = SureBirimi.gun;
  String _event = 'teblig';
  late DateTime _day = widget.served;

  static const _events = {
    'teblig': 'Tebliğ',
    'tefhim': 'Tefhim',
    'karar': 'Karar',
    'ilan': 'İlan',
    'ogrenme': 'Öğrenme',
  };

  /// The rule to begin with: the one being replaced, else a way of appeal
  /// the documents name, else the first.
  String _first() {
    final ids = [
      for (final g in _groups)
        for (final r in g.rules) kuralBilgisi(r)?.id ?? '',
    ];
    if (widget.replacingRule != null && ids.contains(widget.replacingRule)) {
      return widget.replacingRule!;
    }
    final words = widget.hint
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .toLowerCase();
    for (final (word, label) in const [
      ('istinaf', 'istinaf'),
      ('temyiz', 'temyiz'),
    ]) {
      if (!words.contains(word)) continue;
      for (final g in _groups) {
        for (final r in g.rules) {
          if (r.ad.toLowerCase().contains(label)) {
            _hint =
                'Belgede “$label” geçiyor; ${r.ad.toLowerCase()} seçili '
                'geldi.';
            return kuralBilgisi(r)!.id;
          }
        }
      }
    }
    return ids.firstOrNull ?? 'ozel';
  }

  @override
  void initState() {
    super.initState();
    _rule = _first();
  }

  @override
  void dispose() {
    _amount.dispose();
    _purpose.dispose();
    super.dispose();
  }

  DeadlineChoice get _choice => DeadlineChoice(
    id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
    noticeId: widget.noticeId,
    ruleId: _rule,
    amount: int.tryParse(_amount.text.trim()) ?? 0,
    unit: _unit,
    purpose: _purpose.text,
    startEvent: _event,
    startDay: _event == 'teblig' && _sameDay(_day, widget.served)
        ? null
        : _key(_day),
    replaces: widget.replacing,
    created: DateTime.now(),
  );

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _key(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
  static String _text(DateTime d) =>
      '${_two(d.day)}.${_two(d.month)}.${d.year}';
  static const _weekdays = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];

  /// The last day the choice gives, with what moved it; null while the
  /// lawyer's own time is not a number.
  DeadlineItem? get _item {
    final rule = _choice.rule;
    if (rule == null || rule.miktar <= 0) return null;
    final c = DeadlineService.computeFromUsuliTebligTarihi(
      usuliTebligTarihi: _day,
      kategori: widget.category ?? MahkemeKategorisi.bilinmeyen,
      kurallar: [
        YasalSure(
          ad: rule.ad,
          miktar: rule.miktar,
          birim: rule.birim,
          kanunMaddesi: rule.kanunMaddesi,
          maliTatildeDurur: rule.maliTatildeDurur,
          nitelik: rule.nitelik,
        ),
      ],
    );
    return c.items.firstOrNull;
  }

  Widget _option(String id, String title, String trailing) {
    final on = _rule == id;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        key: ValueKey('choice-$id'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _rule = id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: on ? scheme.primary.withValues(alpha: .06) : null,
            border: Border.all(
              color: on ? scheme.primary : scheme.outlineVariant,
              width: on ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                on ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 18,
                color: on ? scheme.primary : AgendaColors.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 13)),
              ),
              if (trailing.isNotEmpty)
                Text(
                  trailing,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AgendaColors.muted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kicker(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: .6,
        color: AgendaColors.muted,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final width = math.min(480.0, MediaQuery.sizeOf(context).width - 48);
    InputDecoration field(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
    );
    return AlertDialog(
      title: Text(widget.replacing == null ? 'Süre ekle' : 'Süreyi değiştir'),
      content: SizedBox(
        width: width,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_hint != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AgendaColors.hearingFill,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _hint!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AgendaColors.hearingText,
                    ),
                  ),
                ),
              for (final g in _groups) ...[
                _kicker(g.title),
                for (final r in g.rules)
                  _option(
                    kuralBilgisi(r)!.id,
                    '${r.ad} · ${r.kanunMaddesi}',
                    r.sureMetni,
                  ),
              ],
              _kicker('BAŞKA BİR SÜRE'),
              _option('ozel', 'Kendim gireyim', ''),
              if (_rule == 'ozel')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: 80,
                        child: TextField(
                          key: const ValueKey('choice-amount'),
                          controller: _amount,
                          keyboardType: TextInputType.number,
                          decoration: field('Süre'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: DropdownButtonFormField<SureBirimi>(
                          initialValue: _unit,
                          isExpanded: true,
                          decoration: field('Birim'),
                          items: const [
                            DropdownMenuItem(
                              value: SureBirimi.gun,
                              child: Text('gün'),
                            ),
                            DropdownMenuItem(
                              value: SureBirimi.isGunu,
                              child: Text('iş günü'),
                            ),
                            DropdownMenuItem(
                              value: SureBirimi.hafta,
                              child: Text('hafta'),
                            ),
                            DropdownMenuItem(
                              value: SureBirimi.ay,
                              child: Text('ay'),
                            ),
                          ],
                          onChanged: (u) => setState(() => _unit = u ?? _unit),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: TextField(
                          key: const ValueKey('choice-purpose'),
                          controller: _purpose,
                          decoration: field('Ne için'),
                        ),
                      ),
                    ],
                  ),
                ),
              _kicker('BAŞLANGIÇ'),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: const ValueKey('choice-event'),
                      initialValue: _event,
                      isExpanded: true,
                      decoration: field('Neden başlıyor'),
                      items: [
                        for (final e in _events.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (e) => setState(() {
                        _event = e ?? _event;
                        if (_event == 'teblig') _day = widget.served;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      key: const ValueKey('choice-day'),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _day,
                          firstDate: DateTime(2015),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (d != null) setState(() => _day = d);
                      },
                      child: InputDecorator(
                        decoration: field('Tarihi'),
                        child: Text(_text(_day)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                key: const ValueKey('choice-result'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: item == null
                      ? AgendaColors.page
                      : const Color(0xFFEAF5EE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: item == null
                    ? const Text(
                        'Süreyi gün, hafta ya da ay olarak girin.',
                        style: TextStyle(fontSize: 12.5),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Son gün: ${_text(item.etkiliSonGun)} '
                            '${_weekdays[item.etkiliSonGun.weekday - 1]}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            [
                              '${_text(_day)} ${_events[_event]!.toLowerCase()} '
                                  '+ ${item.sureMetni}.',
                              ...item.dayanakNotlari,
                            ].join(' '),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF3B5E47),
                            ),
                          ),
                        ],
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
          key: const ValueKey('choice-save'),
          onPressed: item == null
              ? null
              : () => Navigator.pop(context, _choice),
          child: const Text('Ekle ve onayla'),
        ),
      ],
    );
  }
}

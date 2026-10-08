import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/office/office_network.dart';
import '../../services/office/office_task.dart';
import '../../services/office/task_package.dart';
import '../../services/uyap/uyap_web_service.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../portfolio/portfolio_rows.dart';

/// A case being put in a task: its things to do and what goes with it.
class _Draft {
  _Draft(this.row);
  final PortfolioRow row;
  final items = <(TextEditingController, String)>[];
  TaskDocs docs = TaskDocs.chosen;
  final chosen = <String>{};
}

/// Görev ver (docs/design/buro-yonetim-taslak.png, 2): one or more people,
/// one or more cases each with its things to do and the documents that go
/// with it, a due day, a priority and a note.
class TaskGiveDialog extends StatefulWidget {
  const TaskGiveDialog({
    super.key,
    required this.network,
    this.rows,
    this.initialCaseKey,
    this.initialDocKey,
  });

  /// A document of that case to send with it: the one it was given from.
  final String? initialDocKey;

  /// A case to start with: the one whose page it was given from.
  final String? initialCaseKey;

  final OfficeNetwork network;

  /// The portfolio to choose cases from; read when not given.
  final List<PortfolioRow>? rows;

  static Future<void> show(BuildContext context, OfficeNetwork network) =>
      showDialog<void>(
        context: context,
        builder: (_) => TaskGiveDialog(network: network),
      );

  @override
  State<TaskGiveDialog> createState() => _TaskGiveDialogState();
}

class _TaskGiveDialogState extends State<TaskGiveDialog> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _to = <String>{};
  final _cases = <_Draft>[];
  DateTime? _due;

  /// The rest of a task, asked for only when wanted.
  bool _more = false;
  TaskPriority _priority = TaskPriority.normal;
  List<PortfolioRow> _rows = const [];
  String? _error;
  bool _busy = false;

  OfficeNetwork get _net => widget.network;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTemplates());
    // One to give to: already chosen.
    final others = [
      for (final m in _net.ledger.people)
        if (m.deviceId != _net.me && _net.mayGive(m.deviceId)) m.deviceId,
    ];
    if (others.length == 1) _to.add(others.single);
    final given = widget.rows;
    if (given != null) {
      _rows = given;
      _startWith();
    } else {
      unawaited(
        loadPortfolio(lawyer: _net.self?.name ?? '')
            .then((rows) {
              if (!mounted) return;
              setState(() {
                _rows = rows;
                _startWith();
              });
            })
            .catchError((Object _) {}),
      );
    }
  }

  /// The things to do the template file suggests for each kind of case.
  static Map<String, List<String>>? _templateCache;
  Map<String, List<String>> get _templates => _templateCache ?? const {};

  Future<void> _loadTemplates() async {
    if (_templateCache != null) return;
    try {
      final j = jsonDecode(
        await rootBundle.loadString('assets/buro/gorev_sablonlari.json'),
      );
      final all = (j as Map)['sablonlar'] as Map;
      _templateCache = {
        for (final e in all.entries)
          '${e.key}': [for (final t in e.value as List) '$t'],
      };
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _startWith() {
    final key = widget.initialCaseKey;
    final doc = widget.initialDocKey;
    final row = _rows.where((r) => r.key == key).firstOrNull;
    if (row != null && !_cases.any((c) => c.row.key == key)) {
      _cases.add(
        _Draft(row)
          ..items.add((TextEditingController(), ''))
          ..chosen.addAll([?doc]),
      );
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    for (final c in _cases) {
      for (final (field, _) in c.items) {
        field.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _pickCase() async {
    final picked = await showDialog<PortfolioRow>(
      context: context,
      builder: (_) => _CasePicker(
        rows: [
          for (final r in _rows)
            if (!_cases.any((c) => c.row.key == r.key)) r,
        ],
      ),
    );
    if (picked != null) {
      setState(
        () => _cases.add(
          _Draft(picked)..items.add((TextEditingController(), '')),
        ),
      );
    }
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _due ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (day != null) setState(() => _due = day);
  }

  String? _packing;

  Future<void> _give() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final cases = [
      for (final c in _cases)
        TaskCase(
          caseKey: c.row.key,
          number: c.row.kase.number,
          court: c.row.kase.court,
          items: [
            for (final (field, who) in c.items)
              if (field.text.trim().isNotEmpty)
                TaskItem.create(field.text, assignee: who),
          ],
          docs: c.docs,
          docKeys: c.chosen.toList(),
        ),
    ];
    // The cases' details and documents, those not here fetched from UYAP:
    // the assignee cannot open them there.
    final packed = <String, TaskPackage>{};
    final missing = <String>[];
    for (final c in cases) {
      setState(() => _packing = '${c.number} hazırlanıyor…');
      final pack = await TaskPackage.pack(c);
      packed[c.caseKey] = pack;
      missing.addAll([for (final m in pack.missing) '${c.number}: $m']);
    }
    if (!mounted) return;
    setState(() => _packing = null);
    if (missing.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Bazı evrak indirilemedi'),
          content: SizedBox(
            width: 420,
            child: Text(
              'UYAP’a bağlı olmadığınız ya da UYAP vermediği için şu evrak '
              'gönderilemeyecek:\n\n${missing.take(12).join('\n')}'
              '${missing.length > 12 ? '\n+${missing.length - 12} evrak daha' : ''}'
              '\n\nUYAP’a bağlanıp yeniden deneyebilir ya da görevi bunlarsız '
              'verebilirsiniz.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              key: const ValueKey('task-give-anyway'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yine de ver'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) {
        setState(() => _busy = false);
        return;
      }
    }
    final error = await _net.giveTask(
      title: _title.text,
      to: _to.toList(),
      note: _note.text,
      due: _due,
      priority: _priority,
      cases: cases,
      packed: packed,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final people = [
      for (final m in _net.ledger.people)
        if (_net.mayGive(m.deviceId)) m,
    ];
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 5),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: .7,
          color: AgendaColors.muted,
        ),
      ),
    );
    return AlertDialog(
      title: const Text('Yeni görev'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('task-title'),
                controller: _title,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Ne yapılacak?',
                  hintText: 'ör. Ekim duruşmalarına hazırlık',
                ),
              ),
              label('KİME'),
              if (people.isEmpty)
                const Text(
                  'Görev verebileceğiniz bir üye yok. Önce Büro ağı sayfasında '
                  'büroyu kurup üyeleri ekleyin.',
                  style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
                ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in people)
                    FilterChip(
                      key: ValueKey('task-to-${m.deviceId}'),
                      label: Text(
                        m.deviceId == _net.me
                            ? '${m.name} (kendim)'
                            : '${m.name} · ${m.role.label}',
                      ),
                      selected: _to.contains(m.deviceId),
                      onSelected: (on) => setState(
                        () => on ? _to.add(m.deviceId) : _to.remove(m.deviceId),
                      ),
                    ),
                ],
              ),
              label('NE ZAMANA'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (days, text) in _quickDays)
                    ChoiceChip(
                      key: ValueKey('task-due-$days'),
                      label: Text(text),
                      selected: _due == _dayAfter(days),
                      onSelected: (on) =>
                          setState(() => _due = on ? _dayAfter(days) : null),
                    ),
                  ActionChip(
                    key: const ValueKey('task-due'),
                    avatar: const Icon(Icons.event_rounded, size: 16),
                    label: Text(
                      _due == null ||
                              _quickDays.any((q) => _dayAfter(q.$1) == _due)
                          ? 'Tarih seç'
                          : dayText(_due!),
                    ),
                    onPressed: _pickDue,
                  ),
                ],
              ),
              if (_cases.isNotEmpty) ...[
                label('DOSYALAR VE İŞLER'),
                for (final c in _cases) _caseCard(context, c),
              ],
              if (_cases.isNotEmpty || _more) _addCase(),
              if (_more) ...[
                label('ÖNCELİK'),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final p in TaskPriority.values)
                      ChoiceChip(
                        key: ValueKey('task-priority-${p.name}'),
                        label: Text(p.label),
                        selected: _priority == p,
                        onSelected: (_) => setState(() => _priority = p),
                      ),
                  ],
                ),
                label('AÇIKLAMA'),
                TextField(
                  key: const ValueKey('task-note'),
                  controller: _note,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'İşi alanın bilmesi gerekenler',
                  ),
                ),
              ] else
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('task-more'),
                    onPressed: () => setState(() => _more = true),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      _cases.isEmpty
                          ? 'Ayrıntı ekle (dosya, öncelik, açıklama)'
                          : 'Ayrıntı ekle (öncelik, açıklama)',
                    ),
                  ),
                ),
              if (_cases.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Seçilen evrak, dosyanın künyesi ve taraflarıyla şifreli '
                    'gider; alan kişi o dosyada UYAP yetkisi olmasa da dosyayı '
                    '"görevle gelen" olarak görür.',
                    style: TextStyle(fontSize: 12, color: AgendaColors.muted),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: scheme.error)),
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
          key: const ValueKey('task-give'),
          onPressed: _busy ? null : () => unawaited(_give()),
          child: Text(_packing ?? 'Görevi ver'),
        ),
      ],
    );
  }

  Widget _addCase() => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: OutlinedButton.icon(
      key: const ValueKey('task-add-case'),
      onPressed: _rows.isEmpty ? null : _pickCase,
      icon: const Icon(Icons.add_rounded, size: 18),
      label: Text(
        _rows.isEmpty
            ? 'UYAP Dosyalarım’da dosya yok'
            : 'UYAP Dosyalarım’dan dosya ekle',
      ),
    ),
  );

  static const _quickDays = [
    (0, 'Bugün'),
    (1, 'Yarın'),
    (3, '3 gün'),
    (7, '1 hafta'),
  ];

  static DateTime _dayAfter(int days) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + days);
  }

  Widget _caseCard(BuildContext context, _Draft c) {
    final scheme = Theme.of(context).colorScheme;
    final docs = c.row.record?.documents ?? const [];
    final names = {
      for (final id in _to) id: _net.ledger.member(id)?.name ?? '',
    };
    return Container(
      key: ValueKey('task-case-${c.row.key}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 10),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${c.row.kase.number} · ${c.row.kase.court}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Çıkar',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _cases.remove(c)),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          for (final (i, (field, who)) in c.items.indexed)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: field,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Yapılacak iş',
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Bounded, a long name shortened: on a phone the item's
                // words keep their room.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: names.containsKey(who) ? who : '',
                    underline: const SizedBox.shrink(),
                    onChanged: (v) =>
                        setState(() => c.items[i] = (field, v ?? '')),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text(
                          'Herhangi biri',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      for (final e in names.entries)
                        DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          Wrap(
            children: [
              TextButton.icon(
                onPressed: () =>
                    setState(() => c.items.add((TextEditingController(), ''))),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('İş ekle'),
              ),
              PopupMenuButton<String>(
                key: ValueKey('task-template-${c.row.key}'),
                tooltip: 'Bu dava türünün işleri',
                onSelected: (text) => setState(() {
                  // An empty row is filled rather than left.
                  final empty = c.items.indexWhere(
                    (i) => i.$1.text.trim().isEmpty,
                  );
                  if (empty >= 0) {
                    c.items[empty].$1.text = text;
                  } else {
                    c.items.add((TextEditingController(text: text), ''));
                  }
                }),
                itemBuilder: (_) => [
                  for (final t
                      in _templates[c.row.kind.name] ?? const <String>[])
                    PopupMenuItem(value: t, child: Text(t)),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  child: Text(
                    '${c.row.kind.label} şablonundan ekle ▾',
                    style: TextStyle(fontSize: 13, color: scheme.primary),
                  ),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Evrak:', style: TextStyle(fontSize: 12.5)),
              for (final mode in TaskDocs.values)
                ChoiceChip(
                  label: Text(
                    mode == TaskDocs.all
                        ? '${mode.label} (${docs.length})'
                        : mode.label,
                  ),
                  selected: c.docs == mode,
                  onSelected: (_) => setState(() => c.docs = mode),
                ),
            ],
          ),
          if (c.docs == TaskDocs.chosen)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final d in docs.take(40))
                  FilterChip(
                    label: Text(
                      d.type.isNotEmpty ? d.type : d.title,
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: c.chosen.contains(d.key),
                    onSelected: (on) => setState(
                      () => on ? c.chosen.add(d.key) : c.chosen.remove(d.key),
                    ),
                  ),
                if (docs.isEmpty)
                  const Text(
                    'Bu dosyanın evrak listesi henüz UYAP’tan gelmedi.',
                    style: TextStyle(fontSize: 12, color: AgendaColors.muted),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Choosing a case from UYAP Dosyalarım, by its number, court or party.
class _CasePicker extends StatefulWidget {
  const _CasePicker({required this.rows});
  final List<PortfolioRow> rows;
  @override
  State<_CasePicker> createState() => _CasePickerState();
}

class _CasePickerState extends State<_CasePicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final words = UyapWebService.fold(_q).split(' ').where((w) => w.length > 1);
    final shown = [
      for (final r in widget.rows)
        if (words.every(r.haystack.contains)) r,
    ].take(50).toList();
    return AlertDialog(
      title: const Text('Dosya seçin'),
      content: SizedBox(
        width: 520,
        // No taller than the screen leaves over the keyboard.
        height: math.max(
          180.0,
          math.min(
            420.0,
            MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom -
                240,
          ),
        ),
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Dosya no, taraf, mahkeme',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final r in shown)
                    ListTile(
                      dense: true,
                      title: Text('${r.kase.number} · ${r.kase.court}'),
                      subtitle: Text(
                        [
                          for (final p in r.ours.take(1)) titleName(p.name),
                          for (final p in r.others.take(1)) titleName(p.name),
                        ].join(' – '),
                      ),
                      onTap: () => Navigator.pop(context, r),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

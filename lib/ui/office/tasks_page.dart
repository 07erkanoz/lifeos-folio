import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/office/office_network.dart';
import '../../services/office/office_notices.dart' show TaskReminders;
import '../../services/office/office_task.dart';
import '../../services/platform/file_actions.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../portfolio/portfolio_rows.dart' show clockText, dayText;
import 'task_give_dialog.dart';

enum _View { all, given, mine, load }

/// How a task's due day reads, and its colour: late red, near amber.
(String, Color) dueOf(OfficeTask t, DateTime now) {
  final d = t.daysLeft(now);
  if (d == null) return ('son gün yok', AgendaColors.muted);
  if (!t.open) return ('son gün ${dayText(t.due!)}', AgendaColors.muted);
  if (d < 0) return ('${-d} gün gecikti', AgendaColors.deadline);
  if (d == 0) return ('bugün son gün', AgendaColors.task);
  if (d <= 3) return ('$d gün kaldı', AgendaColors.task);
  return ('son gün ${dayText(t.due!)} · $d gün', AgendaColors.muted);
}

Color _stageInk(TaskStage s) => switch (s) {
  TaskStage.given => AgendaColors.hearing,
  TaskStage.running => AgendaColors.taskText,
  TaskStage.review => const Color(0xFF0E7C86),
  TaskStage.done => AgendaColors.ok,
  TaskStage.cancelled => AgendaColors.muted,
};

Widget _tag(String text, Color ink) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
  decoration: BoxDecoration(
    color: ink.withValues(alpha: .12),
    borderRadius: BorderRadius.circular(5),
  ),
  child: Text(
    text.replaceAll('i', 'İ').toUpperCase(),
    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: ink),
  ),
);

/// Görevler (docs/design/buro-yonetim-taslak.png, 3): the office's tasks in
/// columns by their stage, each with its due day, how far along it is and
/// its last word.
class TasksPage extends StatefulWidget {
  const TasksPage({super.key, this.network, this.now});
  final OfficeNetwork? network;
  final DateTime Function()? now;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  OfficeNetwork get _net => widget.network ?? OfficeNetwork.instance;
  _View? _view;
  TaskStage? _stage;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: dark ? scheme.surface : AgendaColors.page,
      child: ListenableBuilder(
        listenable: _net,
        builder: (context, _) {
          final me = _net.me;
          final manager = _net.ledger.isManager(me);
          final view = _view ?? (manager ? _View.all : _View.mine);
          final now = (widget.now ?? DateTime.now)();
          final tasks = [
            for (final t in _net.tasks.all)
              if (switch (view) {
                _View.all => true,
                _View.given => t.by == me,
                _View.mine => t.assignees.containsKey(me),
                _View.load => true,
              })
                t,
          ];
          final canGive = _net.ledger.members.any(
            (m) => _net.mayGive(m.deviceId),
          );
          return LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= 900;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: scheme.surface,
                    padding: EdgeInsets.fromLTRB(wide ? 24 : 8, 12, 16, 10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (!wide &&
                            (Scaffold.maybeOf(context)?.hasDrawer ?? false))
                          IconButton(
                            tooltip: 'Menü',
                            onPressed: () => Scaffold.of(context).openDrawer(),
                            icon: const Icon(Icons.menu_rounded),
                          ),
                        const Text(
                          'Görevler',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 10),
                        for (final (v, label) in [
                          if (manager) (_View.all, 'Bütün büro'),
                          (_View.given, 'Verdiğim'),
                          (_View.mine, 'Bana verilen'),
                          if (manager) (_View.load, 'İş yükü'),
                        ])
                          ChoiceChip(
                            key: ValueKey('tasks-view-${v.name}'),
                            label: Text(label),
                            selected: view == v,
                            onSelected: (_) => setState(() => _view = v),
                          ),
                        if (canGive)
                          FilledButton.icon(
                            key: const ValueKey('tasks-give'),
                            onPressed: () =>
                                unawaited(TaskGiveDialog.show(context, _net)),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Görev ver'),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: !_net.ledger.exists
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Görevler büroyla gelir. Büro ağı sayfasında bir '
                                'büro kurun ya da büronuzun yöneticisinin sizi '
                                'eklemesini bekleyin.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AgendaColors.muted),
                              ),
                            ),
                          )
                        : view == _View.load
                        ? _workload(context, tasks, now)
                        : wide
                        ? _board(context, tasks, now)
                        : _list(context, tasks, now),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _board(BuildContext context, List<OfficeTask> tasks, DateTime now) {
    final columns = [
      (
        TaskStage.given,
        [
          for (final t in tasks)
            if (t.stage == TaskStage.given) t,
        ],
      ),
      (
        TaskStage.running,
        [
          for (final t in tasks)
            if (t.stage == TaskStage.running) t,
        ],
      ),
      (
        TaskStage.review,
        [
          for (final t in tasks)
            if (t.stage == TaskStage.review) t,
        ],
      ),
      (
        TaskStage.done,
        [
          for (final t in tasks)
            if (t.stage == TaskStage.done || t.stage == TaskStage.cancelled) t,
        ],
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (stage, list) in columns)
            Expanded(
              child: Container(
                key: ValueKey('tasks-column-${stage.name}'),
                margin: const EdgeInsets.symmetric(horizontal: 5),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                      child: Text(
                        '${stage.label} · ${list.length}'
                        '${stage == TaskStage.review && list.isNotEmpty ? '  onay bekliyor' : ''}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final t in list) _card(context, t, now),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Each member's open work, by stage, and what is late or due this week.
  Widget _workload(BuildContext context, List<OfficeTask> tasks, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final rows = [
      for (final m in _net.ledger.people)
        () {
          final mine = [
            for (final t in tasks)
              if (t.open && t.assignees.containsKey(m.deviceId)) t,
          ];
          int at(TaskStage s) => mine.where((t) => t.stage == s).length;
          final late = mine.where((t) => t.late(now)).length;
          final week = mine.where((t) {
            final d = t.daysLeft(now);
            return d != null && d >= 0 && d <= 7;
          }).length;
          return (
            m,
            mine.length,
            at(TaskStage.given),
            at(TaskStage.running),
            at(TaskStage.review),
            late,
            week,
          );
        }(),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    Widget cell(String text, {bool head = false, Color? ink}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: head ? FontWeight.w700 : FontWeight.w400,
          color: ink,
        ),
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Table(
          key: const ValueKey('tasks-workload'),
          columnWidths: const {0: FlexColumnWidth(2.4)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
              children: [
                for (final h in [
                  'Üye',
                  'Açık',
                  'Verildi',
                  'Sürüyor',
                  'İncelemede',
                  'Geciken',
                  'Bu hafta',
                ])
                  cell(h, head: true),
              ],
            ),
            for (final (m, open, given, running, review, late, week) in rows)
              TableRow(
                children: [
                  cell('${m.name} · ${m.role.label}'),
                  cell('$open', head: true),
                  cell('$given'),
                  cell('$running'),
                  cell('$review'),
                  cell('$late', ink: late > 0 ? AgendaColors.deadline : null),
                  cell('$week', ink: week > 0 ? AgendaColors.task : null),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<OfficeTask> tasks, DateTime now) {
    final shown = [
      for (final t in tasks)
        if (_stage == null || t.stage == _stage) t,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final s in [null, ...TaskStage.values])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      s == null
                          ? 'Tümü · ${tasks.length}'
                          : '${s.label} · ${tasks.where((t) => t.stage == s).length}',
                    ),
                    selected: _stage == s,
                    onSelected: (_) => setState(() => _stage = s),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final t in shown) _card(context, t, now),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Burada görev yok.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AgendaColors.muted),
            ),
          ),
      ],
    );
  }

  Widget _card(BuildContext context, OfficeTask t, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final (due, dueInk) = dueOf(t, now);
    final last = t.last;
    final review = t.stage == TaskStage.review;
    return Card(
      key: ValueKey('task-card-${t.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: t.late(now)
              ? AgendaColors.deadline.withValues(alpha: .5)
              : review
              ? AgendaColors.ok.withValues(alpha: .5)
              : scheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => unawaited(TaskDetail.show(context, _net, t)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (t.priority != TaskPriority.normal)
                    _tag(
                      t.priority.label,
                      t.priority == TaskPriority.urgent
                          ? AgendaColors.deadline
                          : AgendaColors.task,
                    ),
                  if (t.stage == TaskStage.cancelled)
                    _tag('İptal', AgendaColors.muted),
                  if (t.stage == TaskStage.done)
                    _tag('Onaylandı', AgendaColors.ok),
                  if (review) _tag('Teslim', AgendaColors.ok),
                  Text(due, style: TextStyle(fontSize: 11.5, color: dueInk)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                t.title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (t.cases.isNotEmpty)
                Text(
                  [
                    '${t.cases.first.number} · ${t.cases.first.court}',
                    if (t.cases.length > 1) '+${t.cases.length - 1} dosya',
                  ].join(' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AgendaColors.muted,
                  ),
                ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: t.percent / 100,
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
              const SizedBox(height: 6),
              Text(
                '${t.byName} → ${t.assignees.values.join(', ')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AgendaColors.muted,
                ),
              ),
              if (last != null && last.text.isNotEmpty)
                Text(
                  '“${last.text}”',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A task's page (docs/design/buro-yonetim-taslak.png, 4): where it stands,
/// its things to do, what happened and what was said, and what this user
/// may do next.
class TaskDetail extends StatefulWidget {
  const TaskDetail({
    super.key,
    required this.network,
    required this.task,
    this.now,
  });
  final OfficeNetwork network;
  final OfficeTask task;
  final DateTime Function()? now;

  static Future<void> show(
    BuildContext context,
    OfficeNetwork net,
    OfficeTask t,
  ) => showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
        child: TaskDetail(network: net, task: t),
      ),
    ),
  );

  @override
  State<TaskDetail> createState() => _TaskDetailState();
}

class _TaskDetailState extends State<TaskDetail> {
  final _say = TextEditingController();

  OfficeNetwork get _net => widget.network;

  @override
  void dispose() {
    _say.dispose();
    super.dispose();
  }

  Future<void> _do(
    TaskEventKind kind, {
    String text = '',
    int? percent,
    String? item,
  }) async {
    final error = await _net.act(
      widget.task,
      kind,
      text: text,
      percent: percent,
      itemId: item,
    );
    if (error != null && mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  /// Words for a step that needs them; null when given up.
  Future<String?> _words(String title, String hint, {bool required = false}) {
    final field = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: TextField(
            key: const ValueKey('task-words'),
            controller: field,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(hintText: hint),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            key: const ValueKey('task-words-ok'),
            onPressed: () {
              if (required && field.text.trim().isEmpty) return;
              Navigator.pop(context, field.text);
            },
            child: Text(title),
          ),
        ],
      ),
    );
  }

  Future<void> _progress() async {
    var value = widget.task.percent.toDouble();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('İlerleme yaz'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: value,
                        max: 100,
                        divisions: 20,
                        onChanged: (v) => set(() => value = v),
                      ),
                    ),
                    Text('%${value.round()}'),
                  ],
                ),
                TextField(
                  controller: note,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Ne yapıldı, ne kaldı',
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
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yaz'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _do(
        TaskEventKind.progress,
        text: note.text,
        percent: value.round(),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _net,
    builder: (context, _) {
      final t = _net.tasks.of(widget.task.id) ?? widget.task;
      final me = _net.me;
      final giver = t.by == me;
      final doer = t.assignees.containsKey(me);
      final now = (widget.now ?? DateTime.now)();
      final (due, dueInk) = dueOf(t, now);
      final stage = t.stage;
      final done = t.itemsDone;
      final scheme = Theme.of(context).colorScheme;
      final actions = <Widget>[
        if (doer && stage == TaskStage.given)
          FilledButton(
            key: const ValueKey('task-accept'),
            onPressed: () => unawaited(_do(TaskEventKind.accepted)),
            child: const Text('Kabul et'),
          ),
        if (doer && stage == TaskStage.running) ...[
          OutlinedButton(
            key: const ValueKey('task-progress'),
            onPressed: () => unawaited(_progress()),
            child: const Text('İlerleme yaz'),
          ),
          FilledButton(
            key: const ValueKey('task-deliver'),
            onPressed: () async {
              final w = await _words('Teslim et', 'Yapılan iş', required: true);
              if (w != null) await _do(TaskEventKind.delivered, text: w);
            },
            child: const Text('Teslim et'),
          ),
        ],
        if (giver && stage == TaskStage.review) ...[
          OutlinedButton(
            key: const ValueKey('task-return'),
            onPressed: () async {
              final w = await _words(
                'Geri gönder',
                'Ne eksik, ne değişmeli',
                required: true,
              );
              if (w != null) await _do(TaskEventKind.returned, text: w);
            },
            child: const Text('Geri gönder'),
          ),
          FilledButton(
            key: const ValueKey('task-approve'),
            onPressed: () => unawaited(_do(TaskEventKind.approved)),
            child: const Text('Onayla'),
          ),
        ],
        if (doer &&
            t.open &&
            t.due != null &&
            !TaskReminders.instance.seen(t.id))
          TextButton(
            key: const ValueKey('task-seen'),
            onPressed: () async {
              await TaskReminders.instance.markSeen(t.id);
              if (mounted) setState(() {});
            },
            child: const Text('Gördüm'),
          ),
        if (giver && t.open)
          TextButton(
            key: const ValueKey('task-cancel'),
            onPressed: () async {
              final w = await _words(
                'İptal et',
                'Neden iptal ediliyor',
                required: true,
              );
              if (w != null) await _do(TaskEventKind.cancelled, text: w);
            },
            child: const Text('İptal et'),
          ),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _tag(stage.label, _stageInk(stage)),
                IconButton(
                  tooltip: 'Kapat',
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Aşama '),
                      TextSpan(
                        text: stage.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'İlerleme '),
                      TextSpan(
                        text: '%${t.percent}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Text(
                  due,
                  key: const ValueKey('task-due-text'),
                  style: TextStyle(color: dueInk, fontWeight: FontWeight.w600),
                ),
                Text('Öncelik ${t.priority.label}'),
                Text('${t.byName} → ${t.assignees.values.join(', ')}'),
                if (t.supervisor.isNotEmpty) Text('Gözetim: ${t.supervisor}'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: LinearProgressIndicator(
              value: t.percent / 100,
              minHeight: 5,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
              children: [
                if (t.note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(t.note),
                  ),
                for (final c in t.cases) ...[
                  Text(
                    '${c.number} · ${c.court}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    c.docs == TaskDocs.chosen
                        ? '${c.docKeys.length} evrak seçildi'
                        : c.docs.label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AgendaColors.muted,
                    ),
                  ),
                  _received(context, t, c, doer),
                  for (final item in c.items)
                    CheckboxListTile(
                      key: ValueKey('task-item-${item.id}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: done.contains(item.id),
                      onChanged: doer && t.open
                          ? (v) => unawaited(
                              _do(
                                v == true
                                    ? TaskEventKind.itemDone
                                    : TaskEventKind.itemOpen,
                                item: item.id,
                              ),
                            )
                          : null,
                      title: Text(item.text),
                      subtitle: item.assignee.isEmpty
                          ? null
                          : Text(t.assignees[item.assignee] ?? ''),
                    ),
                  const SizedBox(height: 8),
                ],
                const Text(
                  'GİDİŞAT VE YAZIŞMA',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .7,
                    color: AgendaColors.muted,
                  ),
                ),
                const SizedBox(height: 6),
                for (final e in t.timeline) _event(context, e, me),
              ],
            ),
          ),
          if (t.people.contains(me))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('task-say'),
                      controller: _say,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Yazın…',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('task-say-send'),
                    tooltip: 'Gönder',
                    onPressed: _send,
                    icon: Icon(Icons.send_rounded, color: scheme.primary),
                  ),
                ],
              ),
            ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: actions,
              ),
            ),
        ],
      );
    },
  );

  /// The case as it came with the task: its particulars, its parties and
  /// its documents, here to read without UYAP.
  Widget _received(BuildContext context, OfficeTask t, TaskCase c, bool doer) {
    if (!doer) return const SizedBox.shrink();
    final got = _net.receivedCase(t, c.caseKey);
    if (got == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Dosya ve evrak işi verenden geliyor…',
          style: TextStyle(fontSize: 12, color: AgendaColors.muted),
        ),
      );
    }
    final k = got.particulars;
    String v(String key) => '${k[key] ?? ''}'.trim();
    final facts = [
      if (v('kind').isNotEmpty) 'Dava türü: ${v('kind')}',
      if (v('fileType').isNotEmpty) 'Dosya türü: ${v('fileType')}',
      if ((v('status').isNotEmpty ? v('status') : v('state')).isNotEmpty)
        'Durum: ${v('status').isNotEmpty ? v('status') : v('state')}',
      if (v('openedOn').isNotEmpty) 'Açılış: ${v('openedOn')}',
      if (v('hearing').isNotEmpty) 'Duruşma: ${v('hearing')}',
    ];
    return Container(
      key: ValueKey('task-received-${c.caseKey}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AgendaColors.taskFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'GÖREVLE GELEN DOSYA · UYAP yetkiniz olmasa da inceleyebilirsiniz',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: AgendaColors.taskText,
            ),
          ),
          if (facts.isNotEmpty)
            Text(facts.join(' · '), style: const TextStyle(fontSize: 12.5)),
          for (final party in got.parties.take(6))
            Text(
              '${party['rol'] ?? ''}: ${party['ad'] ?? ''}'
              '${'${party['vekil'] ?? ''}'.isEmpty ? '' : ' · vekil ${party['vekil']}'}',
              style: const TextStyle(fontSize: 12),
            ),
          const SizedBox(height: 4),
          for (final path in got.documents)
            Row(
              children: [
                const Icon(Icons.description_outlined, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    p.basename(path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      unawaited(FileActions.invoke('openDefault', path)),
                  child: const Text('Aç'),
                ),
                TextButton(
                  onPressed: () =>
                      unawaited(FileActions.invoke('showFolder', path)),
                  child: const Text('Klasörde göster'),
                ),
              ],
            ),
          if (got.documents.isEmpty)
            const Text(
              'Yalnız künye ve taraflar gönderildi.',
              style: TextStyle(fontSize: 12),
            ),
        ],
      ),
    );
  }

  void _send() {
    final text = _say.text.trim();
    if (text.isEmpty) return;
    _say.clear();
    unawaited(_do(TaskEventKind.message, text: text));
  }

  Widget _event(BuildContext context, TaskEvent e, String me) {
    final when = '${dayText(e.at)} ${clockText(e.at)}';
    if (e.isTalk) {
      final mine = e.by == me;
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
          decoration: BoxDecoration(
            color: mine
                ? AgendaColors.hearingFill
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${mine ? 'Siz' : e.byName} · $when',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AgendaColors.muted,
                ),
              ),
              Text(e.text),
            ],
          ),
        ),
      );
    }
    final what = switch (e.kind) {
      TaskEventKind.given => 'görevi verdi',
      TaskEventKind.accepted => 'kabul etti',
      TaskEventKind.progress =>
        'ilerleme yazdı${e.percent == null ? '' : ' · %${e.percent}'}',
      TaskEventKind.itemDone => 'bir işi tamamladı',
      TaskEventKind.itemOpen => 'bir işi yeniden açtı',
      TaskEventKind.delivered => 'teslim etti',
      TaskEventKind.approved => 'onayladı',
      TaskEventKind.returned => 'geri gönderdi',
      TaskEventKind.cancelled => 'iptal etti',
      TaskEventKind.message => '',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 4, right: 8),
            child: Icon(Icons.circle, size: 9, color: AgendaColors.hearing),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${e.by == me ? 'Siz' : e.byName} $what',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: '  $when',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AgendaColors.muted,
                    ),
                  ),
                  if (e.text.isNotEmpty) TextSpan(text: '\n${e.text}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';

/// Where a task stands (docs/buro.md, Görev).
enum TaskStage {
  given('Verildi'),
  running('Sürüyor'),
  review('İncelemede'),
  done('Tamamlandı'),
  cancelled('İptal');

  const TaskStage(this.label);
  final String label;
}

enum TaskPriority {
  normal('Normal'),
  high('Yüksek'),
  urgent('Acil');

  const TaskPriority(this.label);
  final String label;
}

/// Which of a case's documents go with the task.
enum TaskDocs {
  chosen('Seçili evrak'),
  all('Bütün evrak'),
  particulars('Yalnız künye ve taraflar');

  const TaskDocs(this.label);
  final String label;
}

String _newId() {
  final r = Random.secure();
  return [
    for (var i = 0; i < 8; i++)
      r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

T? _enum<T extends Enum>(List<T> values, Object? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

/// One thing to do in a case, and who is to do it.
class TaskItem {
  const TaskItem({required this.id, required this.text, this.assignee = ''});
  final String id, text;

  /// A device id among the task's assignees; empty for any of them.
  final String assignee;

  Map<String, Object?> toJson() => {'id': id, 'text': text, 'kim': assignee};
  static TaskItem fromJson(Map j) => TaskItem(
    id: '${j['id']}',
    text: '${j['text'] ?? ''}',
    assignee: '${j['kim'] ?? ''}',
  );
  static TaskItem create(String text, {String assignee = ''}) =>
      TaskItem(id: _newId(), text: text.trim(), assignee: assignee);
}

/// A UYAP case the task is about, its things to do and what goes with it.
class TaskCase {
  const TaskCase({
    required this.caseKey,
    required this.number,
    required this.court,
    this.items = const [],
    this.docs = TaskDocs.chosen,
    this.docKeys = const [],
  });

  final String caseKey, number, court;
  final List<TaskItem> items;
  final TaskDocs docs;

  /// The chosen documents' keys, when [docs] is [TaskDocs.chosen].
  final List<String> docKeys;

  Map<String, Object?> toJson() => {
    'key': caseKey,
    'no': number,
    'mahkeme': court,
    'isler': [for (final i in items) i.toJson()],
    'evrak': docs.name,
    'secili': docKeys,
  };
  static TaskCase fromJson(Map j) => TaskCase(
    caseKey: '${j['key']}',
    number: '${j['no'] ?? ''}',
    court: '${j['mahkeme'] ?? ''}',
    items: [
      for (final i in (j['isler'] as List? ?? const []))
        if (i is Map) TaskItem.fromJson(i),
    ],
    docs: _enum(TaskDocs.values, j['evrak']) ?? TaskDocs.chosen,
    docKeys: [for (final k in (j['secili'] as List? ?? const [])) '$k'],
  );
}

enum TaskEventKind {
  given,
  accepted,
  progress,
  message,
  itemDone,
  itemOpen,
  delivered,
  approved,
  returned,
  cancelled,
}

/// Something that happened in a task: who, what, when, with what words
/// and files. A task's stage is read from these, and they are only ever
/// added to, never changed.
class TaskEvent {
  const TaskEvent({
    required this.id,
    required this.kind,
    required this.by,
    required this.byName,
    required this.at,
    this.text = '',
    this.percent,
    this.itemId,
    this.files = const [],
    this.signature = '',
  });

  final String id;
  final TaskEventKind kind;
  final String by, byName, text;
  final DateTime at;
  final int? percent;
  final String? itemId;

  /// The names of files sent with it.
  final List<String> files;

  /// Its maker's device's signature on [signedOf] (docs/buro.md, Güvenlik).
  final String signature;

  /// What its maker signs: the step and the task it is in, so that it
  /// can be neither changed nor moved to another.
  List<int> signedOf(String taskId) => utf8.encode(
    [
      'folio-gorev-olayi-1',
      taskId,
      id,
      kind.name,
      by,
      byName,
      '${at.millisecondsSinceEpoch}',
      text,
      '${percent ?? ''}',
      itemId ?? '',
      ...files,
    ].join('\u0000'),
  );

  TaskEvent signed(String signature) => TaskEvent(
    id: id,
    kind: kind,
    by: by,
    byName: byName,
    at: at,
    text: text,
    percent: percent,
    itemId: itemId,
    files: files,
    signature: signature,
  );

  /// Words of the talk, not a change of the task's state.
  bool get isTalk => kind == TaskEventKind.message;

  Map<String, Object?> toJson() => {
    'id': id,
    'tur': kind.name,
    'kim': by,
    'ad': byName,
    'at': at.toUtc().toIso8601String(),
    if (text.isNotEmpty) 'metin': text,
    'yuzde': ?percent,
    'is': ?itemId,
    if (files.isNotEmpty) 'dosyalar': files,
    if (signature.isNotEmpty) 'imza': signature,
  };

  static TaskEvent? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = _enum(TaskEventKind.values, j['tur']);
    final at = DateTime.tryParse('${j['at']}');
    if (kind == null || at == null || j['id'] is! String) return null;
    final percent = j['yuzde'];
    return TaskEvent(
      id: j['id'] as String,
      kind: kind,
      by: '${j['kim'] ?? ''}',
      byName: '${j['ad'] ?? ''}',
      at: at.toLocal(),
      text: '${j['metin'] ?? ''}',
      percent: percent is int ? percent.clamp(0, 100) : null,
      itemId: j['is'] is String ? j['is'] as String : null,
      files: [for (final f in (j['dosyalar'] as List? ?? const [])) '$f'],
      signature: j['imza'] is String ? j['imza'] as String : '',
    );
  }

  static TaskEvent create(
    TaskEventKind kind,
    String by,
    String byName, {
    String text = '',
    int? percent,
    String? itemId,
    List<String> files = const [],
  }) => TaskEvent(
    id: _newId(),
    kind: kind,
    by: by,
    byName: byName,
    at: DateTime.now(),
    text: text,
    percent: percent,
    itemId: itemId,
    files: files,
  );
}

/// A piece of work given to one or more people, over one or more cases.
class OfficeTask {
  OfficeTask({
    required this.id,
    required this.title,
    required this.by,
    required this.byName,
    required this.assignees,
    required this.createdAt,
    this.note = '',
    this.due,
    this.priority = TaskPriority.normal,
    this.cases = const [],
    this.supervisor = '',
    List<TaskEvent>? events,
  }) : events = events ?? [];

  final String id, title, by, byName, note;

  /// Device id → name, of those it is given to.
  final Map<String, String> assignees;
  final DateTime createdAt;
  final DateTime? due;
  final TaskPriority priority;
  final List<TaskCase> cases;

  /// The lawyer who supervises a trainee's part (Av. K. m. 26).
  final String supervisor;
  final List<TaskEvent> events;

  /// Whom it concerns: the giver and those it is given to.
  Set<String> get people => {by, ...assignees.keys};

  List<TaskEvent> get timeline =>
      [...events]..sort((a, b) => a.at.compareTo(b.at));

  /// The stage, from what happened last that changes it.
  TaskStage get stage {
    var stage = TaskStage.given;
    for (final e in timeline) {
      stage = switch (e.kind) {
        TaskEventKind.accepted ||
        TaskEventKind.progress ||
        TaskEventKind.returned =>
          stage == TaskStage.done || stage == TaskStage.cancelled
              ? stage
              : TaskStage.running,
        TaskEventKind.delivered =>
          stage == TaskStage.cancelled ? stage : TaskStage.review,
        TaskEventKind.approved => TaskStage.done,
        TaskEventKind.cancelled => TaskStage.cancelled,
        _ => stage,
      };
    }
    return stage;
  }

  List<TaskItem> get items => [for (final c in cases) ...c.items];

  /// The items done, as their last ticking says.
  Set<String> get itemsDone {
    final done = <String>{};
    for (final e in timeline) {
      if (e.kind == TaskEventKind.itemDone && e.itemId != null) {
        done.add(e.itemId!);
      } else if (e.kind == TaskEventKind.itemOpen && e.itemId != null) {
        done.remove(e.itemId!);
      }
    }
    return done;
  }

  /// How far along: done is all of it; else the items ticked, or the last
  /// progress said where there are no items.
  int get percent {
    if (stage == TaskStage.done) return 100;
    final all = items;
    if (all.isNotEmpty) {
      return (itemsDone.length * 100 / all.length).round();
    }
    for (final e in timeline.reversed) {
      if (e.percent != null) return e.percent!;
    }
    return stage == TaskStage.review ? 100 : 0;
  }

  bool get open => stage != TaskStage.done && stage != TaskStage.cancelled;

  /// Days left to the due day: negative when late, null when none is set.
  int? daysLeft(DateTime now) {
    final d = due;
    if (d == null) return null;
    return DateTime(
      d.year,
      d.month,
      d.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  bool late(DateTime now) => open && (daysLeft(now) ?? 1) < 0;

  TaskEvent? get last => timeline.isEmpty ? null : timeline.last;

  Map<String, Object?> toJson() => {
    'id': id,
    'baslik': title,
    'kim': by,
    'ad': byName,
    'alanlar': assignees,
    'olusma': createdAt.toUtc().toIso8601String(),
    if (note.isNotEmpty) 'aciklama': note,
    if (due != null) 'son': due!.toIso8601String().substring(0, 10),
    'oncelik': priority.name,
    'dosyalar': [for (final c in cases) c.toJson()],
    if (supervisor.isNotEmpty) 'gozetim': supervisor,
    'olaylar': [for (final e in events) e.toJson()],
  };

  static OfficeTask? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], title = j['baslik'], by = j['kim'];
    final made = DateTime.tryParse('${j['olusma']}');
    if (id is! String || title is! String || by is! String || made == null) {
      return null;
    }
    final assignees = j['alanlar'];
    return OfficeTask(
      id: id,
      title: title,
      by: by,
      byName: '${j['ad'] ?? ''}',
      assignees: {
        if (assignees is Map)
          for (final e in assignees.entries) '${e.key}': '${e.value}',
      },
      createdAt: made.toLocal(),
      note: '${j['aciklama'] ?? ''}',
      due: DateTime.tryParse('${j['son']}'),
      priority: _enum(TaskPriority.values, j['oncelik']) ?? TaskPriority.normal,
      cases: [
        for (final c in (j['dosyalar'] as List? ?? const []))
          if (c is Map) TaskCase.fromJson(c),
      ],
      supervisor: '${j['gozetim'] ?? ''}',
      events: [
        for (final e in (j['olaylar'] as List? ?? const []))
          ?TaskEvent.fromJson(e),
      ],
    );
  }

  static String newId() => _newId();
}

/// What each kind of event may come from: the giver decides, those it is
/// given to do and say; anyone in it may talk.
bool mayDo(OfficeTask task, TaskEventKind kind, String who) {
  final giver = who == task.by;
  final assignee = task.assignees.containsKey(who);
  return switch (kind) {
    TaskEventKind.given ||
    TaskEventKind.approved ||
    TaskEventKind.returned ||
    TaskEventKind.cancelled => giver,
    TaskEventKind.accepted ||
    TaskEventKind.progress ||
    TaskEventKind.delivered ||
    TaskEventKind.itemDone ||
    TaskEventKind.itemOpen => assignee,
    TaskEventKind.message => giver || assignee,
  };
}

/// The tasks this device takes part in, kept beside Folio's settings.
class OfficeTasks {
  OfficeTasks({Future<File> Function()? file}) : _file = file ?? _default;

  static Future<File> _default() async =>
      File(p.join((await folioSupportDirectory()).path, 'buro_gorevler.json'));

  final Future<File> Function() _file;
  final _tasks = <String, OfficeTask>{};
  bool _loaded = false;

  List<OfficeTask> get all =>
      _tasks.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  OfficeTask? of(String id) => _tasks[id];

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is! List) return;
      for (final j in json) {
        final t = OfficeTask.fromJson(j);
        if (t != null) _tasks[t.id] = t;
      }
    } catch (_) {}
  }

  // One write at a time: two at once raced for the same part file.
  Future<void> _saving = Future.value();

  Future<void> _save() =>
      _saving = _saving.then((_) => _write()).catchError((Object _) {});

  Future<void> _write() async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final part = File('${file.path}.part');
    await part.writeAsString(
      jsonEncode([for (final t in _tasks.values) t.toJson()]),
      flush: true,
    );
    await part.rename(file.path);
  }

  Future<void> put(OfficeTask task) async {
    _tasks[task.id] = task;
    await _save();
  }

  /// Adds an event, if [who] may make it; false when not.
  Future<bool> add(OfficeTask task, TaskEvent event) async {
    if (!mayDo(task, event.kind, event.by)) return false;
    task.events.add(event);
    await put(task);
    return true;
  }

  /// Takes a task as another device has it: what is new in it is added,
  /// what one may not have done is left out; true when anything changed.
  /// The giver's words of what the task is are kept as the giver sent them.
  Future<bool> merge(
    OfficeTask theirs, {
    required String from,
    void Function(TaskEvent event)? added,
    Future<bool> Function(String taskId, TaskEvent event)? authentic,
  }) async {
    // Each step only as its maker signed it: one in the task cannot put
    // words in another's mouth.
    Future<bool> real(TaskEvent e) async =>
        authentic == null || await authentic(theirs.id, e);
    if (!theirs.people.contains(from)) return false;
    final mine = _tasks[theirs.id];
    if (mine == null) {
      // Only its giver brings a task into being here.
      if (from != theirs.by) return false;
      final kept = OfficeTask.fromJson(theirs.toJson())!..events.clear();
      for (final e in theirs.events) {
        if (mayDo(kept, e.kind, e.by) && await real(e)) kept.events.add(e);
      }
      await put(kept);
      kept.events.forEach(added ?? (_) {});
      return true;
    }
    final seen = {for (final e in mine.events) e.id};
    var changed = false;
    for (final e in theirs.events) {
      if (seen.contains(e.id) || !mayDo(mine, e.kind, e.by)) continue;
      if (!await real(e)) continue;
      mine.events.add(e);
      added?.call(e);
      changed = true;
    }
    if (changed) await put(mine);
    return changed;
  }
}

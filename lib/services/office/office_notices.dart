import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';

import '../platform/system_notices.dart';
import '../security/app_lock.dart';
import 'office_chat.dart';
import 'office_network.dart';
import 'office_task.dart';

/// The office's words as the system's notifications (docs/buro.md,
/// Bildirimler): a message, a task's step, a device asking to be known and
/// files offered. While Folio is locked they say only that something
/// came, not what. A tap opens the page it is about.
void tellOffice(OfficeNetwork net, {SystemNotices? notices, AppLock? lock}) {
  final system = notices ?? SystemNotices.instance;
  bool locked() => (lock ?? AppLock.instance).locked;

  void show(
    String key,
    String title,
    String body,
    String payload,
    String hidden,
  ) => unawaited(
    system
        .show(
          id: key.hashCode & 0x7fffffff,
          title: locked() ? 'LifeOS Folio' : title,
          body: locked() ? hidden : body,
          payload: payload,
          ask: false,
        )
        .catchError((Object _) {}),
  );

  net.onMessage = (Chat chat, ChatMessage m) {
    final what = m.text.isNotEmpty
        ? m.text
        : switch (m.attachments.firstOrNull?.kind) {
            AttachmentKind.voice => 'Sesli mesaj',
            AttachmentKind.image => 'Resim gönderdi',
            AttachmentKind.file =>
              'Dosya gönderdi: ${m.attachments.first.name}',
            null => '',
          };
    final where = chat.kind == ChatKind.private
        ? m.byName
        : '${m.byName} · ${chat.titleFor(net.me)}';
    show('m${m.id}', where, what, 'mesaj:${chat.id}', 'Yeni mesaj');
  };

  net.onTaskEvent = (OfficeTask t, TaskEvent e) {
    final (title, body) = switch (e.kind) {
      TaskEventKind.given => ('Yeni görev', '${e.byName}: ${t.title}'),
      TaskEventKind.accepted => (
        'Görev kabul edildi',
        '${e.byName}: ${t.title}',
      ),
      TaskEventKind.delivered => (
        'Görev teslim edildi',
        '${e.byName}: ${t.title}',
      ),
      TaskEventKind.approved => ('Görev onaylandı', t.title),
      TaskEventKind.returned => (
        'Görev geri gönderildi',
        '${t.title}: ${e.text}',
      ),
      TaskEventKind.cancelled => (
        'Görev iptal edildi',
        '${t.title}: ${e.text}',
      ),
      TaskEventKind.message => ('${e.byName} · ${t.title}', e.text),
      TaskEventKind.progress => (
        'Görevde ilerleme',
        '${t.title}: %${e.percent ?? t.percent}',
      ),
      _ => ('', ''),
    };
    if (title.isEmpty) return;
    show('g${e.id}', title, body, 'gorev:${t.id}', 'Görevde yeni bir hareket');
  };

  TaskReminders.instance.start(net, (t, d) {
    final when = d < 0
        ? '${-d} gün gecikti'
        : d == 0
        ? 'bugün son gün'
        : '$d gün kaldı';
    show(
      'h${t.id}$d${DateTime.now().day}',
      'Görev: $when',
      t.title,
      'gorev:${t.id}',
      'Görevin son günü yaklaşıyor',
    );
  });

  net.incoming.addListener(() {
    final p = net.incoming.value;
    if (p == null) return;
    show(
      'p${p.hashCode}',
      'Bir cihaz sizi tanımak istiyor',
      p.other?.name ?? 'Büro ağında yeni bir cihaz',
      'buro:',
      'Büro ağında yeni bir istek',
    );
  });

  net.incomingOffer.addListener(() {
    final t = net.incomingOffer.value;
    if (t == null) return;
    show(
      'o${t.id}',
      '${t.peer.name.isEmpty ? t.peer.device : t.peer.name} dosya gönderiyor',
      t.files.length == 1 ? t.files.single.name : '${t.files.length} dosya',
      'buro:',
      'Size dosya gönderiliyor',
    );
  });
}

/// Staged reminders of tasks' due days (docs/buro.md, from Mühlet and
/// Dosya360): 7, 3 and 1 days before, on the day, and every day late.
/// "Gördüm" on a task stops all but the day's own; kept on this device.
class TaskReminders {
  TaskReminders({Future<File> Function()? file}) : _file = file ?? _default;

  static Future<File> _default() async => File(
    p.join((await folioSupportDirectory()).path, 'buro_hatirlatma.json'),
  );

  final Future<File> Function() _file;
  final _sent = <String>{};
  final _seen = <String>{};
  bool _loaded = false;
  Timer? _timer;

  static const stages = [7, 3, 1];

  bool seen(String taskId) => _seen.contains(taskId);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final j = jsonDecode(await file.readAsString());
      if (j is! Map) return;
      _sent.addAll([
        for (final s in (j['gonderilen'] as List? ?? const [])) '$s',
      ]);
      _seen.addAll([for (final s in (j['goruldu'] as List? ?? const [])) '$s']);
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'gonderilen': _sent.toList(), 'goruldu': _seen.toList()}),
      );
    } catch (_) {}
  }

  Future<void> markSeen(String taskId) async {
    _seen.add(taskId);
    await _save();
  }

  /// What is due to be told now: (task, days left), each told once.
  @visibleForTesting
  List<(OfficeTask, int)> due(
    Iterable<OfficeTask> tasks,
    String me,
    DateTime now,
  ) {
    final out = <(OfficeTask, int)>[];
    final today = '${now.year}-${now.month}-${now.day}';
    for (final t in tasks) {
      final d = t.daysLeft(now);
      if (d == null || !t.open || !t.assignees.containsKey(me)) continue;
      final String key;
      if (d < 0) {
        key = '${t.id}|gec|$today';
      } else if (d == 0) {
        key = '${t.id}|0';
      } else if (stages.contains(d) && !_seen.contains(t.id)) {
        key = '${t.id}|$d';
      } else {
        continue;
      }
      if (d < 0 && _seen.contains(t.id)) continue;
      if (_sent.add(key)) out.add((t, d));
    }
    return out;
  }

  /// Checks now and every hour while Folio runs.
  void start(
    OfficeNetwork net,
    void Function(OfficeTask t, int daysLeft) tell,
  ) {
    _timer?.cancel();
    Future<void> check() async {
      await load();
      final me = net.self == null ? null : net.me;
      if (me == null) return;
      final todo = due(net.tasks.all, me, DateTime.now());
      if (todo.isEmpty) return;
      await _save();
      for (final (t, d) in todo) {
        tell(t, d);
      }
    }

    unawaited(check());
    _timer = Timer.periodic(
      const Duration(hours: 1),
      (_) => unawaited(check()),
    );
  }

  static final instance = TaskReminders();
}

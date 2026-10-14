import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../office/office_task.dart';
import '../portal/portal_database.dart';
import '../sync/hlc.dart';
import '../sync/sync_generation.dart';

/// The notes of the cases of the office's tasks, kept alike as they are
/// now, never as a copy frozen in a task's package (docs/senkron-plan.md
/// R7): the one who gave a task sends its cases' agenda notes, none
/// secret, each with its groups' versions; whoever it is given to takes
/// them note by note, and keeps for good what was taken back. Each says
/// what it holds of the other's, for "geri çekildi: n/m" to be counted.
///
/// An office part (`gorev-notlari`), both ways, as every part needing the
/// secret note's and the taking back's capabilities: to an older Folio it
/// does not go, and the task goes without notes.
class TaskNotes {
  TaskNotes({
    required this.db,
    required this.me,
    required this.tasks,
    required this.personOf,
    required this.received,
  });

  static const part = 'gorev-notlari';

  /// The mark a task's package made by this Folio carries: its notes are
  /// not in it.
  static const format = 'notBicimi';

  final PortalDatabase db;
  final String Function() me;
  final List<OfficeTask> Function() tasks;

  /// The office person of a device, by the office's ledger; empty for none.
  final String Function(String device) personOf;

  /// The files of [task]'s case that came here; null for none.
  final List<String>? Function(String task, String caseKey) received;

  /// What goes to [toDevice]: the notes of the tasks this person gave its
  /// person, and of their cards' notes what was taken back; and what this
  /// one holds of theirs.
  Map<String, Object?> export(String toDevice) {
    final to = personOf(toDevice), self = me();
    if (to.isEmpty || self.isEmpty || to == self) return const {};
    final scopes = <Map<String, Object?>>[];
    for (final t in tasks()) {
      if (t.by != self || !t.open || !t.assignees.containsKey(to)) continue;
      for (final c in t.cases) {
        final n = db.taskNoteRows(c.caseKey);
        final scope = 'gorev:${t.id}|${c.caseKey}';
        // Sent: it may be there from now on, whether it came or not.
        for (final row in n.rows) {
          db.recordHold('ajanda:${row['id']}', toDevice, to, scope);
        }
        scopes.add({
          'gorev': t.id,
          'dosya': c.caseKey,
          'notlar': n.rows,
          'gizlenen': {for (final e in n.hidden.entries) e.key: '${e.value}'},
          'silinen': {for (final e in n.removed.entries) e.key: '${e.value}'},
        });
      }
    }
    // Of a card's notes, only that each was taken back, and when: no text.
    final cardHides = [
      for (final e in db.noteHides.entries)
        if (!e.key.startsWith('ajanda:'))
          {'not': e.key, 'surum': '${e.value.version}'},
    ];
    // What this one holds of [to]'s, for them to count.
    final held = <String, Map<String, Object?>>{};
    for (final h in db.taskNotesHeld(to)) {
      final s = held.putIfAbsent(
        '${h.task}|${h.caseKey}',
        () => {
          'gorev': h.task,
          'dosya': h.caseKey,
          'notlar': <String, String>{},
          'gizlenen': <String, String>{},
          'eskiTemiz': db.taskNotesCleaning(h.task, h.caseKey) != 'bekliyor',
        },
      );
      if (h.hidden != null) {
        (s['gizlenen'] as Map)[h.id] = '${h.hidden}';
      } else if (h.body != null) {
        (s['notlar'] as Map)[h.id] = '${h.body}';
      }
    }
    return {
      'gorevler': scopes,
      'kartGizli': cardHides,
      'rapor': held.values.toList(),
      'uygulanan': [
        for (final h in db.takenNoteHidesOf(to))
          {'not': h.key, 'surum': '${h.version}'},
      ],
    };
  }

  /// What [fromDevice] sent: the notes of the tasks its person gave this
  /// one, only theirs; what they took back of their cards; what they hold
  /// of this one's. True when anything changed here.
  Future<bool> merge(Object? theirs, String fromDevice) async {
    if (theirs is! Map) return false;
    final from = personOf(fromDevice), self = me();
    if (from.isEmpty || self.isEmpty || from == self) return false;
    var changed = false;
    final given = {
      for (final t in tasks())
        if (t.by == from && t.open && t.assignees.containsKey(self))
          for (final c in t.cases) '${t.id}|${c.caseKey}',
    };
    for (final s in theirs['gorevler'] as List? ?? const []) {
      if (s is! Map || s['gorev'] is! String || s['dosya'] is! String) {
        continue;
      }
      final task = s['gorev'] as String, caseKey = s['dosya'] as String;
      if (!given.contains('$task|$caseKey')) continue;
      Map<String, Hlc> versions(Object? m) => {
        if (m is Map)
          for (final e in m.entries) '${e.key}': ?Hlc.tryParse(e.value),
      };
      final rows = [
        for (final r in s['notlar'] as List? ?? const [])
          if (r is Map) r,
      ];
      for (final r in rows) {
        for (final v in [
          ...?(jsonDecodeMap(r['surumler'])?.values.map(Hlc.tryParse)),
        ]) {
          if (v != null) SyncClock.observe(db, v);
        }
      }
      if (db.mergeTaskNotes(
        from,
        task,
        caseKey,
        rows,
        versions(s['gizlenen']),
        removed: versions(s['silinen']),
      )) {
        changed = true;
      }
      // The giver's Folio keeps the notes apart now: those an older one put
      // in the package here go.
      if (await cleanPackage(task, caseKey, now: true)) changed = true;
    }
    if (db.forgetTaskNotes(from, given)) changed = true;
    for (final h in theirs['kartGizli'] as List? ?? const []) {
      if (h is! Map || h['not'] is! String) continue;
      final v = Hlc.tryParse(h['surum']);
      if (v != null) db.takeNoteHide(from, h['not'] as String, v);
    }
    if (db.applyTakenNoteHides()) changed = true;
    // What they hold of this person's: only of tasks this person gave them.
    final mine = {
      for (final t in tasks())
        if (t.by == self && t.assignees.containsKey(from))
          for (final c in t.cases) '${t.id}|${c.caseKey}',
    };
    for (final r in theirs['rapor'] as List? ?? const []) {
      if (r is! Map) continue;
      final key = '${r['gorev']}|${r['dosya']}';
      if (!mine.contains(key)) continue;
      final scope = 'gorev:$key';
      (r['notlar'] as Map? ?? const {}).forEach((id, v) {
        db.recordHold(
          'ajanda:$id',
          fromDevice,
          from,
          scope,
          held: Hlc.tryParse(v),
        );
      });
      (r['gizlenen'] as Map? ?? const {}).forEach((id, v) {
        db.recordHold(
          'ajanda:$id',
          fromDevice,
          from,
          scope,
          applied: Hlc.tryParse(v),
          gone: true,
        );
      });
      if (r['eskiTemiz'] == true && db.knowsHold('eski:$key', fromDevice)) {
        db.recordHold(
          'eski:$key',
          fromDevice,
          from,
          scope,
          applied: oldCleaned,
        );
      }
    }
    for (final h in theirs['uygulanan'] as List? ?? const []) {
      if (h is! Map || h['not'] is! String) continue;
      final key = h['not'] as String;
      final parts = key.split(':');
      if (parts.length < 2 || db.hideOf(key) == null) continue;
      db.recordHold(
        key,
        fromDevice,
        from,
        'kart:${parts[1]}',
        applied: Hlc.tryParse(h['surum']),
      );
    }
    return changed;
  }

  /// What an older Folio's package of [task]'s case [caseKey] carried of
  /// its giver's notes, taken out of it here: its notes and deadlines, the
  /// package's details alone, never its documents. [now] when the giver's
  /// notes came apart: from then on, every package of it is cleaned as it
  /// comes. True when a file was written.
  Future<bool> cleanPackage(
    String task,
    String caseKey, {
    bool now = false,
  }) async {
    final state = db.taskNotesCleaning(task, caseKey);
    if (!now && state == null) return false;
    var wrote = false;
    for (final path in received(task, caseKey) ?? const <String>[]) {
      final name = p.basename(path);
      if (!name.startsWith('dosya') || !name.endsWith('.json')) continue;
      final file = File(path);
      try {
        final j = jsonDecode(await file.readAsString());
        if (j is! Map || !j.containsKey('evrakAdlari') || j[format] != null) {
          continue;
        }
        if (!j.containsKey('notlar') && !j.containsKey('sureler')) continue;
        j
          ..remove('notlar')
          ..remove('sureler');
        final part = File('$path.yeni');
        await part.writeAsString(jsonEncode(j), flush: true);
        await part.rename(path);
        wrote = true;
      } catch (_) {
        // Tried again as the next list comes, or at the next start.
        return wrote;
      }
    }
    db.setTaskNotesCleaning(task, caseKey, 'tamam');
    return wrote;
  }

  /// A package that came: an older Folio's notes taken out of it at once,
  /// once its giver's notes come apart.
  Future<void> came(String task, String caseKey, List<String> saved) async {
    final state = db.taskNotesCleaning(task, caseKey);
    if (state == 'tamam') {
      await cleanPackage(task, caseKey, now: true);
    } else if (state == null) {
      // Kept to be cleaned once its giver's notes come apart.
      for (final path in saved) {
        if (p.basename(path).startsWith('dosya') && path.endsWith('.json')) {
          try {
            final j = jsonDecode(await File(path).readAsString());
            if (j is Map && j[format] == null && j.containsKey('notlar')) {
              db.setTaskNotesCleaning(task, caseKey, 'bekliyor');
            }
          } catch (_) {}
        }
      }
    }
  }

  /// The mark of an older package cleaned: no version of its own.
  static const oldCleaned = Hlc(1, 0, 'eski');

  static Map<String, Object?>? jsonDecodeMap(Object? text) {
    if (text is! String) return null;
    try {
      final j = jsonDecode(text);
      return j is Map ? Map<String, Object?>.from(j) : null;
    } on FormatException {
      return null;
    }
  }
}

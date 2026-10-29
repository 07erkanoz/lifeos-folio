import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'lifeos_agenda.dart';
import 'observed.dart';
import 'portal_database.dart';

/// What LifeOS's Ajanda asks Folio to keep: a task or a deadline added, a
/// task done (lifeOSArch docs/folio-ajanda.md). LifeOS leaves each request
/// as `<uuid>.json` in [folder]; Folio keeps it and moves it to
/// `islendi/<uuid>.json` with what came of it, `{"result": "ok", "uid": …}`
/// or `{"result": "hata", "message": …}`. A request is taken by renaming it
/// first, so two Folios (one open, one `--ajanda-yaz`) never keep it twice.
/// It names a case by its number alone, never a client; Folio ties it to
/// that case and opens none.
abstract final class LifeosInbox {
  /// The contract's version of a request.
  static const schema = 1;

  /// A request taken and not finished for this long is taken again: the
  /// Folio that took it stopped midway.
  static const stale = Duration(minutes: 10);

  /// `$XDG_DATA_HOME/lifeos/folio-istek`, `~/.local/share/…` when it is
  /// not set; null with neither, and off Linux.
  static Directory? folder([Map<String, String>? environment]) {
    if (environment == null && !Platform.isLinux) return null;
    final agenda = LifeosAgenda.file(environment);
    return agenda == null
        ? null
        : Directory(p.join(agenda.parent.path, 'folio-istek'));
  }

  /// Keeps every request waiting in [folder]; how many were finished, kept
  /// or refused.
  static Future<int> process(
    PortalDatabase db,
    Directory folder, {
    DateTime? now,
  }) async {
    if (!await folder.exists()) return 0;
    final done = Directory(p.join(folder.path, 'islendi'));
    var finished = 0;
    final waiting = <File>[];
    await for (final entry in folder.list()) {
      if (entry is! File) continue;
      final name = p.basename(entry.path);
      if (name.endsWith('.json') && !name.startsWith('.')) {
        waiting.add(entry);
      } else if (name.startsWith('.alindi-') &&
          DateTime.now().difference(await entry.lastModified()) > stale) {
        waiting.add(entry);
      }
    }
    for (final file in waiting) {
      final id = _idOf(p.basename(file.path));
      // Taken by renaming: whoever renames it keeps it, the other finds it
      // gone.
      final taken = File(p.join(folder.path, '.alindi-$id.$pid'));
      try {
        await file.rename(taken.path);
      } on FileSystemException {
        continue;
      }
      final result = File(p.join(done.path, '$id.json'));
      Map<String, Object?> outcome;
      if (await result.exists()) {
        // Kept already, and only its leftover here.
        await taken.delete();
        continue;
      }
      try {
        outcome = keep(db, await taken.readAsString(), now: now);
      } catch (e) {
        outcome = _refused('İstek işlenemedi: $e');
      }
      await done.create(recursive: true);
      await LifeosAgenda.write(result, '${jsonEncode(outcome)}\n');
      await taken.delete();
      finished++;
    }
    return finished;
  }

  /// The request's uuid, from its file's name or a taken one's.
  static String _idOf(String name) {
    var id = name;
    if (id.startsWith('.alindi-')) {
      id = id.substring(8);
      final dot = id.lastIndexOf('.');
      if (dot > 0) id = id.substring(0, dot);
    }
    if (id.endsWith('.json')) id = id.substring(0, id.length - 5);
    return id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }

  static Map<String, Object?> _refused(String message) => {
    'result': 'hata',
    'message': message,
  };

  /// One request's [text] kept in [db]; what came of it.
  static Map<String, Object?> keep(
    PortalDatabase db,
    String text, {
    DateTime? now,
  }) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return _refused('İstek okunamadı: biçimi bozuk.');
    }
    if (json is! Map) return _refused('İstek okunamadı: biçimi bozuk.');
    final Map<dynamic, dynamic> request = json;
    if (request['schema'] != schema) {
      return _refused('Bu istek biçimini Folio tanımıyor.');
    }
    String field(String key) {
      final v = request[key];
      return v is String ? v.trim() : '';
    }

    switch (field('action')) {
      case 'ekle':
        return _add(db, request, field, now ?? DateTime.now());
      case 'bitti':
        return _finish(db, field('uid'), now ?? DateTime.now());
      default:
        return _refused('Folio bu isteği tanımıyor.');
    }
  }

  static Map<String, Object?> _add(
    PortalDatabase db,
    Map<dynamic, dynamic> json,
    String Function(String) field,
    DateTime now,
  ) {
    final kind = switch (field('kind')) {
      'gorev' => 'task',
      'sure' => 'deadline',
      'durusma' => null,
      _ => '',
    };
    if (kind == null) {
      return _refused(
        'Duruşmalar UYAP’tan gelir; Folio’ya el ile duruşma eklenmez.',
      );
    }
    if (kind.isEmpty) return _refused('Eklenecek kaydın türü bilinmiyor.');
    final title = field('title');
    if (title.isEmpty) return _refused('Kaydın başlığı yok.');
    final start = field('start');
    final at = DateTime.tryParse(start);
    if (at == null) return _refused('Kaydın tarihi okunamadı.');
    final allDay = json['allDay'] == true || !start.contains('T');
    final number = field('case');
    String? key;
    if (number.isNotEmpty) {
      final found = _case(db, number, field('court'));
      if (found.error case final error?) return _refused(error);
      key = found.key;
    }
    final item = AgendaItem(
      id: AgendaItem.newId(),
      kind: kind,
      title: title,
      body: field('note'),
      at: allDay ? DateTime(at.year, at.month, at.day) : at.toLocal(),
      allDay: allDay,
      caseKey: key,
      updated: now,
    );
    db.saveAgenda(item);
    return {
      'result': 'ok',
      'uid': LifeosAgenda.uidOf(
        kind == 'task' ? 'gorev' : 'sure',
        'folio-ajanda-${item.id}',
      ),
    };
  }

  /// The one case kept with [number] (and [court], when given).
  static ({String? key, String? error}) _case(
    PortalDatabase db,
    String number,
    String court,
  ) {
    if (court.isNotEmpty) {
      final key = caseKey(number, court);
      if (db.caseOf(key) != null) return (key: key, error: null);
    }
    final prefix = caseKey(number, '').split('|').first;
    final matches = [
      for (final key in db.cases().keys)
        if (key.split('|').first == prefix) key,
    ];
    if (matches.length == 1) return (key: matches.single, error: null);
    if (matches.isEmpty) {
      return (key: null, error: 'Folio’da $number numaralı dosya yok.');
    }
    return (
      key: null,
      error:
          'Folio’da $number numaralı birden çok dosya var; mahkemesiyle '
          'birlikte gönderin.',
    );
  }

  static Map<String, Object?> _finish(
    PortalDatabase db,
    String uid,
    DateTime now,
  ) {
    if (!uid.startsWith('gorev-')) {
      return _refused('Yalnız görevler bitti olarak işaretlenir.');
    }
    for (final item in db.agenda()) {
      if (item.kind != 'task' && item.kind != 'note') continue;
      if (LifeosAgenda.uidOf('gorev', 'folio-ajanda-${item.id}') != uid) {
        continue;
      }
      if (!item.done) db.saveAgenda(item.copyWith(done: true, updated: now));
      return {'result': 'ok', 'uid': uid};
    }
    return _refused('Bu görev Folio’da bulunamadı.');
  }
}

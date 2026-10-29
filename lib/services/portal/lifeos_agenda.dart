import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../editor/lawyer_profile.dart';
import '../platform/app_directories.dart';
import 'agenda_ics.dart';
import 'lifeos_inbox.dart';
import 'portal_database.dart';

/// The agenda LifeOS's notification centre and its Ajanda show: the
/// hearings, the deadlines followed and the tasks from [back] days before
/// today to [ahead] days after, written to a small file of its own
/// (lifeOSArch docs/folio-ajanda.md). LifeOS reads that file alone, never
/// Folio's database; clicked, a record starts `lifeos_folio --ajanda <uid>`
/// ([AgendaLaunch]). A record keeps its uid while it lasts (a hearing
/// moved to another hour too, [LifeosAgendaIds]): LifeOS ties the copy it
/// put in Google's calendar to it.
abstract final class LifeosAgenda {
  /// The contract's version; a panel that does not know it shows nothing.
  static const schema = 1;

  /// Days before today written: the week and the month shown whole.
  static const back = 30;

  /// Days after today written; today itself is one more.
  static const ahead = 120;

  /// The first and the last day written at [now].
  static ({DateTime from, DateTime to}) range(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return (
      from: DateTime(today.year, today.month, today.day - back),
      to: DateTime(today.year, today.month, today.day + ahead),
    );
  }

  static const _namesKey = 'lifeos_ajanda_muvekkil';

  /// "Müvekkil adını LifeOS ajandasında göster": off unless turned on, as
  /// the calendar's export (KVKK: the file is read by others than Folio).
  static bool showsNames(PortalDatabase db) => db.meta(_namesKey) == '1';

  static void setShowsNames(PortalDatabase db, bool on) =>
      db.setMeta(_namesKey, on ? '1' : '0');

  /// The record's id on the desktop: its kind and its calendar uid's hash,
  /// the same on every write, letters, digits and `-` only (the panel puts
  /// it on a command line).
  static String uidOf(String kind, String calendarUid) =>
      '$kind-${sha1.convert(utf8.encode(calendarUid)).toString().substring(0, 16)}';

  /// Where the panel looks: `$XDG_DATA_HOME/lifeos/folio-ajanda.json`,
  /// `~/.local/share/…` when it is not set. Null with neither.
  static File? file([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    final data = env['XDG_DATA_HOME'];
    final home = env['HOME'];
    final base = data != null && p.isAbsolute(data)
        ? data
        : home == null || home.isEmpty
        ? null
        : p.join(home, '.local', 'share');
    return base == null
        ? null
        : File(p.join(base, 'lifeos', 'folio-ajanda.json'));
  }

  /// The events LifeOS is given at [now], in the contract's shape. [ids]
  /// keeps hearings' uids and when each record last changed between
  /// writes; without it every record is as new.
  static List<Map<String, Object?>> events(
    PortalDatabase db,
    DateTime now, {
    bool? names,
    String? lawyer,
    LifeosAgendaIds? ids,
  }) {
    final known = ids ?? LifeosAgendaIds();
    final named = names ?? showsNames(db);
    final window = range(now);
    final list = agendaEvents(
      db,
      from: window.from,
      // The last day whole, the day after it not.
      to: DateTime(
        window.to.year,
        window.to.month,
        window.to.day + 1,
      ).subtract(const Duration(milliseconds: 1)),
      tasks: true,
      names: named,
      lawyer: lawyer,
      done: true,
    );
    final used = <String>{};
    final out = <Map<String, Object?>>[];
    for (final e in list) {
      final uid = e.kind == 'durusma'
          ? known.hearing(e, taken: used)
          : uidOf(e.kind, e.uid);
      used.add(uid);
      final record = <String, Object?>{
        'uid': uid,
        'kind': e.kind,
        'title': e.name,
        'start': e.allDay ? dayOf(e.start) : stamp(e.start),
        'allDay': e.allDay,
        if (!e.allDay) 'minutes': e.minutes,
        'court': e.court,
        'case': e.caseNumber,
        if (named && e.clients.isNotEmpty) 'client': e.clients.join(', '),
        if (e.done) 'done': true,
        if (e.cancelled) 'status': 'iptal',
      };
      record['updated'] = stamp(
        known.updated(uid, record, now, own: e.updated),
      );
      out.add(record);
    }
    known.prune(used, now);
    return out;
  }

  /// The file's text: [events], when they were written and the days they
  /// cover; a record in those days and not in the file is no more.
  static String encode(List<Map<String, Object?>> events, DateTime now) {
    final window = range(now);
    return '${const JsonEncoder.withIndent('  ').convert({
      'schema': schema,
      'generated': stamp(now),
      'range': {'from': dayOf(window.from), 'to': dayOf(window.to)},
      'events': events,
    })}\n';
  }

  /// [text] put in [target] whole or not at all: written beside it, its
  /// leave the user's alone, and renamed over it. A panel reading it never
  /// sees half a file.
  static Future<void> write(File target, String text) async {
    await target.parent.create(recursive: true);
    final pending = File(
      p.join(target.parent.path, '.${p.basename(target.path)}.$pid.tmp'),
    );
    try {
      // Made empty, its leave narrowed, and only then written.
      await pending.writeAsString('', flush: true);
      if (!Platform.isWindows) {
        await Process.run('chmod', ['600', pending.path]);
      }
      await pending.writeAsString(text, flush: true);
      await pending.rename(target.path);
    } catch (_) {
      try {
        if (await pending.exists()) await pending.delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// The day and the hearing the agenda opens at for [uid]: a hearing at
  /// its own, a deadline or a task at its day (and at the hearing a task
  /// is about). Null when there is no such record.
  static ({DateTime day, String? hearing})? find(
    PortalDatabase db,
    String uid,
    DateTime now, {
    LifeosAgendaIds? ids,
  }) {
    DateTime day(DateTime t) => DateTime(t.year, t.month, t.day);
    final kind = uid.split('-').first;
    if (kind == 'durusma') {
      // A hearing told of is a year either side of today at most; one
      // moved since its uid was given is found by the keys it had.
      final keys = ids?.keysOf(uid) ?? const <String>{};
      for (final h in db.hearings(
        from: now.subtract(const Duration(days: 366)),
        to: now.add(const Duration(days: 732)),
      )) {
        if (keys.contains(h.key) ||
            uidOf('durusma', 'folio-durusma-${h.key}') == uid) {
          return (day: day(h.at), hearing: h.key);
        }
      }
      return null;
    }
    if (kind == 'sure') {
      for (final d in db.deadlines(decidedOnly: false)) {
        if (uidOf('sure', 'folio-sure-${d.record.id}') != uid) continue;
        final at = DateTime.tryParse(d.day ?? '');
        return at == null ? null : (day: day(at), hearing: null);
      }
    }
    if (kind == 'sure' || kind == 'gorev') {
      for (final i in db.agenda()) {
        final at = i.at;
        if (at == null) continue;
        if (uidOf(kind, 'folio-ajanda-${i.id}') == uid) {
          return (day: day(at), hearing: i.hearingKey);
        }
      }
    }
    return null;
  }

  /// [t] as ISO 8601 with the offset of its zone: `2026-10-29T10:30:00+03:00`.
  static String stamp(DateTime t) {
    final local = t.isUtc ? t.toLocal() : t;
    final offset = local.timeZoneOffset;
    final minutes = offset.inMinutes.abs();
    return '${dayOf(local)}T${_two(local.hour)}:${_two(local.minute)}:'
        '${_two(local.second)}${offset.isNegative ? '-' : '+'}'
        '${_two(minutes ~/ 60)}:${_two(minutes % 60)}';
  }

  /// [t]'s day: `2026-10-30`.
  static String dayOf(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}';

  static String _two(int v) => v.toString().padLeft(2, '0');
}

/// What [LifeosAgenda] keeps between writes: the uid each hearing was
/// given, by its key and by its ids at the portals, so a hearing moved to
/// another day, hour, hall or court (another key) keeps it; and for each
/// record what it was last written as and when that changed. Kept in
/// Folio's own folder ([file]), never in LifeOS's.
class LifeosAgendaIds {
  LifeosAgendaIds();

  /// Hearing key or portal id (`uyapWeb:123`) → uid.
  final _byKey = <String, String>{};
  final _byPortal = <String, String>{};

  /// uid → what it was written as, when that changed, when last written.
  final _records = <String, ({String hash, String updated, String seen})>{};

  bool _changed = false;

  /// Whether something was given or changed since read.
  bool get changed => _changed;

  /// A record not written for this long is forgotten.
  static const forget = Duration(days: 400);

  /// The uid of the hearing [e]: the one it had, under its key or any of
  /// its portal ids; else its own. One already [taken] in this write is
  /// not given twice.
  String hearing(CalendarEvent e, {Set<String> taken = const {}}) {
    final key = e.hearingKey ?? e.uid;
    var uid = _byKey[key];
    if (uid == null) {
      for (final id in e.portalIds) {
        final had = _byPortal[id];
        if (had != null && !taken.contains(had)) {
          uid = had;
          break;
        }
      }
    }
    if (uid == null || taken.contains(uid)) {
      uid = LifeosAgenda.uidOf('durusma', e.uid);
    }
    if (_byKey[key] != uid) {
      _byKey[key] = uid;
      _changed = true;
    }
    for (final id in e.portalIds) {
      if (_byPortal[id] != uid) {
        _byPortal[id] = uid;
        _changed = true;
      }
    }
    return uid;
  }

  /// The keys a hearing's [uid] was given under.
  Set<String> keysOf(String uid) => {
    for (final e in _byKey.entries)
      if (e.value == uid) e.key,
  };

  /// When [record] (its fields but `updated`) last changed: [own], where
  /// Folio keeps that itself; else the write that first saw it this way.
  DateTime updated(
    String uid,
    Map<String, Object?> record,
    DateTime now, {
    DateTime? own,
  }) {
    final hash = sha1.convert(utf8.encode(jsonEncode(record))).toString();
    final was = _records[uid];
    final at =
        own ??
        (was != null && was.hash == hash
            ? DateTime.tryParse(was.updated) ?? now
            : now);
    final kept = (
      hash: hash,
      updated: at.toIso8601String(),
      seen: LifeosAgenda.dayOf(now),
    );
    if (was == null ||
        was.hash != kept.hash ||
        was.updated != kept.updated ||
        was.seen != kept.seen) {
      _records[uid] = kept;
      _changed = true;
    }
    return at;
  }

  /// Forgets what has not been written for [forget], [current] aside.
  void prune(Set<String> current, DateTime now) {
    final gone = <String>{
      for (final e in _records.entries)
        if (!current.contains(e.key) &&
            now.difference(DateTime.tryParse(e.value.seen) ?? now) > forget)
          e.key,
    };
    if (gone.isEmpty) return;
    _records.removeWhere((uid, _) => gone.contains(uid));
    _byKey.removeWhere((_, uid) => gone.contains(uid));
    _byPortal.removeWhere((_, uid) => gone.contains(uid));
    _changed = true;
  }

  Map<String, Object?> toJson() => {
    'keys': _byKey,
    'portal': _byPortal,
    'records': {
      for (final e in _records.entries)
        e.key: {
          'hash': e.value.hash,
          'updated': e.value.updated,
          'seen': e.value.seen,
        },
    },
  };

  static LifeosAgendaIds fromJson(Object? json) {
    final ids = LifeosAgendaIds();
    if (json is! Map) return ids;
    Map<String, String> strings(Object? m) => {
      if (m is Map)
        for (final e in m.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
    };
    ids._byKey.addAll(strings(json['keys']));
    ids._byPortal.addAll(strings(json['portal']));
    final records = json['records'];
    if (records is Map) {
      for (final e in records.entries) {
        final v = e.value;
        if (e.key is! String || v is! Map) continue;
        final hash = v['hash'], updated = v['updated'], seen = v['seen'];
        if (hash is String && updated is String && seen is String) {
          ids._records[e.key as String] = (
            hash: hash,
            updated: updated,
            seen: seen,
          );
        }
      }
    }
    return ids;
  }

  /// Read from [from]; empty when it is not there or cannot be read.
  static Future<LifeosAgendaIds> read(File from) async {
    try {
      if (!await from.exists()) return LifeosAgendaIds();
      return fromJson(jsonDecode(await from.readAsString()));
    } catch (_) {
      return LifeosAgendaIds();
    }
  }

  /// Kept in [to] whole, and marked as such.
  Future<void> save(File to) async {
    await LifeosAgenda.write(to, '${jsonEncode(toJson())}\n');
    _changed = false;
  }

  /// In Folio's own folder.
  static Future<File> file() async => File(
    p.join((await folioSupportDirectory()).path, 'lifeos-ajanda-kimlik.json'),
  );
}

/// Keeps [LifeosAgenda]'s file current while Folio runs on Linux: written
/// at start, again when the agenda's database changes (by Folio or its
/// sync, a write anywhere moves its [PortalDatabase.revision]) and when the
/// day turns. What is the same is not written again.
class LifeosAgendaWriter {
  LifeosAgendaWriter({
    required this.database,
    required this.target,
    this.lawyer,
    this.inbox,
    this.idsFile,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Future<PortalDatabase> Function() database;
  final File target;
  final String? Function()? lawyer;

  /// Where LifeOS's Ajanda leaves what it asks Folio to keep
  /// ([LifeosInbox]); none read without it.
  final Directory? inbox;

  /// Where [LifeosAgendaIds] are kept between writes; in memory without it.
  final File? idsFile;
  final DateTime Function() _now;
  LifeosAgendaIds? _ids;

  (int, int)? _revision;
  DateTime? _day;
  String? _written;
  Timer? _timer;
  bool _busy = false;

  static LifeosAgendaWriter? _running;

  /// Started once, on Linux, outside tests; the panel looks every minute.
  static void start({String? Function()? lawyer}) {
    if (!Platform.isLinux || Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    final target = LifeosAgenda.file();
    if (target == null || _running != null) return;
    unawaited(
      LifeosAgendaIds.file().then((ids) {
        final writer = _running = LifeosAgendaWriter(
          database: PortalDatabase.shared,
          target: target,
          lawyer: lawyer,
          inbox: LifeosInbox.folder(),
          idsFile: ids,
        );
        unawaited(writer.check());
        writer._timer = Timer.periodic(
          const Duration(seconds: 20),
          (_) => unawaited(writer.check()),
        );
      }, onError: (Object _) {}),
    );
  }

  /// `lifeos_folio --ajanda-yaz`: the inbox read and the file written once,
  /// with no window, for LifeOS's timer while Folio is closed (and safely
  /// while it is open: the database waits for the other's writes, and the
  /// file is put in place whole). 0 when done; 1 with a line said.
  static Future<int> runOnce() async {
    try {
      final target = LifeosAgenda.file();
      if (target == null) {
        stderr.writeln('Folio ajandası yazılamadı: ev klasörü bilinmiyor.');
        return 1;
      }
      final db = await PortalDatabase.shared().timeout(
        const Duration(seconds: 20),
      );
      String? name;
      try {
        name = (await LawyerProfile.load()).lawyer?.titled;
      } catch (_) {}
      final writer = LifeosAgendaWriter(
        database: () async => db,
        target: target,
        lawyer: () => name,
        inbox: LifeosInbox.folder(),
        idsFile: await LifeosAgendaIds.file(),
      );
      await writer.check(force: true, quiet: false);
      return 0;
    } catch (e) {
      stderr.writeln('Folio ajandası yazılamadı: $e');
      return 1;
    }
  }

  /// Written again now, whatever has changed: a setting of it did.
  static Future<void> refresh() async => _running?.check(force: true);

  /// Keeps what LifeOS asked first ([inbox]), then writes the file if the
  /// agenda or the day changed since last time, or [force]; true when it
  /// was written. [quiet]: a failure is the next tick's to try again.
  Future<bool> check({bool force = false, bool quiet = true}) async {
    if (_busy) return false;
    _busy = true;
    try {
      final db = await database();
      final now = _now();
      if (inbox case final folder?) {
        if (await LifeosInbox.process(db, folder, now: now) > 0) force = true;
      }
      final today = DateTime(now.year, now.month, now.day);
      final revision = db.revision;
      if (!force && revision == _revision && today == _day) return false;
      final ids = _ids ??= idsFile == null
          ? LifeosAgendaIds()
          : await LifeosAgendaIds.read(idsFile!);
      final events = LifeosAgenda.events(
        db,
        now,
        lawyer: lawyer?.call(),
        ids: ids,
      );
      // The revision read before the events: a write made meanwhile is
      // read at the next tick.
      _revision = revision;
      _day = today;
      if (idsFile case final file? when ids.changed) await ids.save(file);
      final same = jsonEncode(events);
      if (!force && same == _written && await target.exists()) return false;
      await LifeosAgenda.write(target, LifeosAgenda.encode(events, now));
      _written = same;
      return true;
    } catch (_) {
      // No data folder, or the database not open yet: the next tick.
      if (!quiet) rethrow;
      return false;
    } finally {
      _busy = false;
    }
  }

  void dispose() => _timer?.cancel();
}

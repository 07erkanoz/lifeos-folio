import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'agenda_ics.dart';
import 'portal_database.dart';

/// The agenda LifeOS's notification centre shows: the hearings, the
/// deadlines followed and the tasks of today and the next 14 days, written
/// to a small file of its own (lifeOSArch docs/folio-ajanda.md). The panel
/// reads that file alone, never Folio's database; clicked, it starts
/// `lifeos_folio --ajanda <uid>` ([AgendaLaunch]).
abstract final class LifeosAgenda {
  /// The contract's version; a panel that does not know it shows nothing.
  static const schema = 1;

  /// Days after today written: today is the first of 15.
  static const days = 14;

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

  /// The events the panel is given at [now], in the contract's shape.
  static List<Map<String, Object?>> events(
    PortalDatabase db,
    DateTime now, {
    bool? names,
    String? lawyer,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final named = names ?? showsNames(db);
    final list = agendaEvents(
      db,
      from: today,
      // The last day whole, the day after it not.
      to: DateTime(
        today.year,
        today.month,
        today.day + days + 1,
      ).subtract(const Duration(milliseconds: 1)),
      tasks: true,
      names: named,
      lawyer: lawyer,
    );
    return [
      for (final e in list)
        {
          'uid': uidOf(e.kind, e.uid),
          'kind': e.kind,
          'title': e.name,
          'start': e.allDay ? dayOf(e.start) : stamp(e.start),
          'allDay': e.allDay,
          if (!e.allDay) 'minutes': e.minutes,
          'court': e.court,
          'case': e.caseNumber,
          if (named && e.clients.isNotEmpty) 'client': e.clients.join(', '),
        },
    ];
  }

  /// The file's text: [events] and when they were written.
  static String encode(List<Map<String, Object?>> events, DateTime now) =>
      '${const JsonEncoder.withIndent('  ').convert({'schema': schema, 'generated': stamp(now), 'events': events})}\n';

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
    DateTime now,
  ) {
    DateTime day(DateTime t) => DateTime(t.year, t.month, t.day);
    final kind = uid.split('-').first;
    if (kind == 'durusma') {
      // A hearing told of is a year either side of today at most.
      for (final h in db.hearings(
        from: now.subtract(const Duration(days: 366)),
        to: now.add(const Duration(days: 732)),
      )) {
        if (uidOf('durusma', 'folio-durusma-${h.key}') == uid) {
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

/// Keeps [LifeosAgenda]'s file current while Folio runs on Linux: written
/// at start, again when the agenda's database changes (by Folio or its
/// sync, a write anywhere moves its [PortalDatabase.revision]) and when the
/// day turns. What is the same is not written again.
class LifeosAgendaWriter {
  LifeosAgendaWriter({
    required this.database,
    required this.target,
    this.lawyer,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Future<PortalDatabase> Function() database;
  final File target;
  final String? Function()? lawyer;
  final DateTime Function() _now;

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
    final writer = _running = LifeosAgendaWriter(
      database: PortalDatabase.shared,
      target: target,
      lawyer: lawyer,
    );
    unawaited(writer.check());
    writer._timer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(writer.check()),
    );
  }

  /// Written again now, whatever has changed: a setting of it did.
  static Future<void> refresh() async => _running?.check(force: true);

  /// Writes the file if the agenda or the day changed since last time, or
  /// [force]; true when it was written.
  Future<bool> check({bool force = false}) async {
    if (_busy) return false;
    _busy = true;
    try {
      final db = await database();
      final now = _now();
      final today = DateTime(now.year, now.month, now.day);
      final revision = db.revision;
      if (!force && revision == _revision && today == _day) return false;
      final events = LifeosAgenda.events(db, now, lawyer: lawyer?.call());
      // The revision read before the events: a write made meanwhile is
      // read at the next tick.
      _revision = revision;
      _day = today;
      final same = jsonEncode(events);
      if (!force && same == _written && await target.exists()) return false;
      await LifeosAgenda.write(target, LifeosAgenda.encode(events, now));
      _written = same;
      return true;
    } catch (_) {
      // No data folder, or the database not open yet: the next tick.
      return false;
    } finally {
      _busy = false;
    }
  }

  void dispose() => _timer?.cancel();
}

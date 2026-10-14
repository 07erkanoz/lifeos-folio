import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../portal/portal_database.dart';
import 'hlc.dart';

/// What the file beside the database keeps: the openings counted, the
/// write generation and its epoch, and the clock's reserved bound.
typedef _Beside = ({int count, int generation, String epoch, int bound});

/// This device's write generation (docs/senkron-plan.md R2), and what
/// keeps a version from ever being made twice, even by a database put back
/// from a backup.
///
/// - A file beside the database, which no backup of it holds, keeps a
///   **bound** of the clock: a minute ahead of the last version made. A
///   version past the bound moves it on before the version is used. At
///   every opening the clock begins at the bound, so a database put back,
///   whose own clock is behind, writes after every version made before.
/// - The database and the file count the openings. A database whose count
///   is behind the file's came back from a backup: the generation goes up.
/// - The file is written whole or not at all: to a copy beside it, then
///   moved in its place, the one before kept. Lost with its copy (a new
///   install beside an old database), not known what came after: a new
///   generation with an epoch of its own, drawn at random, so that two
///   such returns to the same backup never write as the same source.
abstract final class SyncGeneration {
  static const _countKey = 'senkron_acilis';
  static const _generationKey = 'senkron_nesil';
  static const _epochKey = 'senkron_donem';
  static const _clockKey = 'senkron_saat';

  /// How far ahead of the last version the bound is kept.
  static const reserve = Duration(minutes: 1);

  /// The file beside the shared database, once it was counted.
  static File? outside;

  static File _previous(File f) => File('${f.path}.onceki');
  static File _next(File f) => File('${f.path}.yeni');

  static _Beside? _parse(File file) {
    try {
      if (!file.existsSync()) return null;
      final j = jsonDecode(file.readAsStringSync());
      if (j is! Map) return null;
      int n(String k) => (j[k] as num?)?.toInt() ?? 0;
      return (
        count: n('sayac'),
        generation: n('nesil'),
        epoch: j['donem'] is String ? j['donem'] as String : '',
        bound: n('sinir'),
      );
    } catch (_) {
      return null;
    }
  }

  /// The file, else the copy kept of it before it was last replaced.
  static _Beside? _read(File file) => _parse(file) ?? _parse(_previous(file));

  /// [beside] written whole: to a copy, flushed, then moved in place; the
  /// one before kept.
  static void _write(File file, _Beside beside) {
    file.parent.createSync(recursive: true);
    final next = _next(file);
    final raf = next.openSync(mode: FileMode.write);
    try {
      raf.writeStringSync(
        jsonEncode({
          'sayac': beside.count,
          'nesil': beside.generation,
          'donem': beside.epoch,
          'sinir': beside.bound,
        }),
      );
      raf.flushSync();
    } finally {
      raf.closeSync();
    }
    if (file.existsSync()) {
      try {
        file.copySync(_previous(file).path);
      } catch (_) {}
    }
    next.renameSync(file.path);
  }

  static int _int(PortalDatabase db, String key) =>
      int.tryParse(db.meta(key) ?? '') ?? 0;

  static (int, int) _clockOf(PortalDatabase db) {
    final parts = (db.meta(_clockKey) ?? '').split('.');
    if (parts.length != 2) return (0, 0);
    return (int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0);
  }

  static String _epoch(Random random) =>
      random.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');

  /// This opening counted; the generation written with now. [outside] is
  /// the file beside the database. Throws when the file cannot be written:
  /// nothing is to be written without it.
  static Future<({int generation, bool restored})> count(
    PortalDatabase db,
    File outside, {
    Random? random,
  }) async {
    final beside = _read(outside);
    final dbCount = _int(db, _countKey);
    final dbGeneration = _int(db, _generationKey);
    final dbEpoch = db.meta(_epochKey) ?? '';
    final (dbL, dbC) = _clockOf(db);
    // Behind the file: a backup. No file for a database opened before:
    // not known what came after it.
    final lost = beside == null && dbCount > 0;
    final restored = lost || (beside != null && dbCount < beside.count);
    final besideCount = beside?.count ?? 0;
    final besideGeneration = beside?.generation ?? 0;
    var generation = besideGeneration > dbGeneration
        ? besideGeneration
        : dbGeneration;
    var epoch = beside?.epoch ?? dbEpoch;
    if (restored) generation++;
    // Not known what came after: an epoch no other return can draw.
    if (lost) epoch = _epoch(random ?? Random.secure());
    final count = (dbCount > besideCount ? dbCount : besideCount) + 1;
    // The clock begins at the bound kept beside: after every version made
    // before, the database's own clock behind or not.
    final bound = beside?.bound ?? 0;
    final l = bound > dbL ? bound : dbL;
    final c = bound > dbL ? 0 : dbC;
    _write(outside, (
      count: count,
      generation: generation,
      epoch: epoch,
      bound: l + reserve.inMilliseconds,
    ));
    db.inTransaction(() {
      db
        ..setMeta(_countKey, '$count')
        ..setMeta(_generationKey, '$generation')
        ..setMeta(_epochKey, epoch)
        ..setMeta(_clockKey, '$l.$c');
    });
    SyncGeneration.outside = outside;
    return (generation: generation, restored: restored);
  }

  /// The generation the database last counted.
  static int generationOf(PortalDatabase db) => _int(db, _generationKey);

  /// The source [deviceId]'s versions are written as in [db]: the device,
  /// its generation, and the epoch when one was drawn.
  static String sourceOf(PortalDatabase db, String deviceId) {
    final epoch = db.meta(_epochKey) ?? '';
    final generation = generationOf(db);
    return epoch.isEmpty
        ? '$deviceId:$generation'
        : '$deviceId:$generation.$epoch';
  }

  /// The clock [deviceId] writes with in [db], its state kept in [db] in
  /// one write; the bound beside it moved on, before a version past it is
  /// used, a [reserve] ahead.
  static HlcClock clockFor(
    PortalDatabase db, {
    required String deviceId,
    File? outside,
    DateTime Function()? now,
  }) {
    final beside = outside ?? SyncGeneration.outside;
    final (l, c) = _clockOf(db);
    var bound = beside == null ? 0 : (_read(beside)?.bound ?? 0);
    return HlcClock(
      source: sourceOf(db, deviceId),
      l: l,
      c: c,
      now: now,
      persist: (l, c) {
        if (beside != null && l >= bound) {
          final kept = _read(beside);
          bound = l + reserve.inMilliseconds;
          _write(beside, (
            count: kept?.count ?? _int(db, _countKey),
            generation: kept?.generation ?? generationOf(db),
            epoch: kept?.epoch ?? (db.meta(_epochKey) ?? ''),
            bound: bound,
          ));
        }
        db.setMeta(_clockKey, '$l.$c');
      },
    );
  }
}

/// The one clock of this Folio's database, made the first time a version
/// is wanted, once the device's id is known.
abstract final class SyncClock {
  static HlcClock? _clock;
  static PortalDatabase? _of;

  static HlcClock of(PortalDatabase db, String deviceId) {
    if (_clock == null || !identical(_of, db)) {
      _clock = SyncGeneration.clockFor(db, deviceId: deviceId);
      _of = db;
    }
    return _clock!;
  }
}

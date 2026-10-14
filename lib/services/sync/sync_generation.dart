import 'dart:convert';
import 'dart:io';

import '../portal/portal_database.dart';
import 'hlc.dart';

/// This device's write generation (docs/senkron-plan.md R2): a part of
/// every version it makes, raised when the database is found to have come
/// back from a backup, so that a version made before the backup and sent
/// to another device is never made again for another change.
///
/// The database counts its openings and keeps its clock; a file beside it
/// that no backup of the database holds keeps them too, the clock written
/// there before any version is used. A database whose count or clock is
/// behind the file's came back from a backup, even one taken while Folio
/// ran. The file is written first: an opening cut between the two writes
/// is taken for a return from a backup at the next, which costs a
/// generation and nothing else.
abstract final class SyncGeneration {
  static const _countKey = 'senkron_acilis';
  static const _generationKey = 'senkron_nesil';
  static const _clockL = 'senkron_saat_l';
  static const _clockC = 'senkron_saat_c';

  /// The file beside the shared database, once it was counted.
  static File? outside;

  static ({int count, int generation, int l, int c})? _read(File file) {
    try {
      if (!file.existsSync()) return null;
      final j = jsonDecode(file.readAsStringSync());
      if (j is! Map) return null;
      int n(String k) => (j[k] as num?)?.toInt() ?? 0;
      return (count: n('sayac'), generation: n('nesil'), l: n('l'), c: n('c'));
    } catch (_) {
      return null;
    }
  }

  static void _write(
    File file, {
    required int count,
    required int generation,
    required int l,
    required int c,
  }) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({'sayac': count, 'nesil': generation, 'l': l, 'c': c}),
      flush: true,
    );
  }

  static int _int(PortalDatabase db, String key) =>
      int.tryParse(db.meta(key) ?? '') ?? 0;

  /// This opening counted; the generation written with now. [outside] is
  /// the file beside the database.
  static Future<({int generation, bool restored})> count(
    PortalDatabase db,
    File outside,
  ) async {
    final file = _read(outside);
    final dbCount = _int(db, _countKey);
    final dbGeneration = _int(db, _generationKey);
    final dbL = _int(db, _clockL), dbC = _int(db, _clockC);
    final behind =
        file != null &&
        (dbCount < file.count ||
            dbL < file.l ||
            (dbL == file.l && dbC < file.c));
    // No file for a database that has been opened before: not known what
    // came after it, so a new generation too.
    final restored = behind || (file == null && dbCount > 0);
    final fileCount = file?.count ?? 0, fileGeneration = file?.generation ?? 0;
    var generation = fileGeneration > dbGeneration
        ? fileGeneration
        : dbGeneration;
    if (restored) generation++;
    final count = (dbCount > fileCount ? dbCount : fileCount) + 1;
    // The clock never goes back: the later of the two.
    final later =
        file != null && (file.l > dbL || (file.l == dbL && file.c > dbC));
    final l = later ? file.l : dbL, c = later ? file.c : dbC;
    _write(outside, count: count, generation: generation, l: l, c: c);
    db
      ..setMeta(_countKey, '$count')
      ..setMeta(_generationKey, '$generation')
      ..setMeta(_clockL, '$l')
      ..setMeta(_clockC, '$c');
    SyncGeneration.outside = outside;
    return (generation: generation, restored: restored);
  }

  /// The generation the database last counted.
  static int generationOf(PortalDatabase db) => _int(db, _generationKey);

  /// The clock [deviceId] writes with in [db]'s generation, its state kept
  /// in [db] and, before a version is used, in [outside].
  static HlcClock clockFor(
    PortalDatabase db, {
    required String deviceId,
    File? outside,
    DateTime Function()? now,
  }) {
    final beside = outside ?? SyncGeneration.outside;
    return HlcClock(
      source: '$deviceId:${generationOf(db)}',
      l: _int(db, _clockL),
      c: _int(db, _clockC),
      now: now,
      persist: (l, c) {
        if (beside != null) {
          _write(
            beside,
            count: _int(db, _countKey),
            generation: generationOf(db),
            l: l,
            c: c,
          );
        }
        db
          ..setMeta(_clockL, '$l')
          ..setMeta(_clockC, '$c');
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

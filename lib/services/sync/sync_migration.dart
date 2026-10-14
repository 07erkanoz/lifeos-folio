import 'dart:io';

import 'package:path/path.dart' as p;

import '../portal/portal_database.dart';

/// One step of what the database is made into for the sync's new rules
/// (docs/senkron-plan.md R0): to schema [to], by [run], in a transaction.
class SyncMigrationStep {
  const SyncMigrationStep(this.to, this.name, this.run);

  final int to;
  final String name;
  final void Function(PortalDatabase db) run;
}

/// The database's schema for the sync, made current once at opening:
/// each step not yet run, in order, after a copy of the database is put
/// aside. Run again it does nothing; a step that fails leaves the database
/// as it was before it, and the copy.
abstract final class SyncMigration {
  static const schemaKey = 'senkron_sema';

  /// 1: the clock and the generation (§5 step 1), with nothing to change
  /// in what is kept. The steps after it come with the parts they serve.
  static const base = 1;

  static List<SyncMigrationStep> steps = [
    // The enforcement ledgers' movements made of their records (§5 step 4).
    SyncMigrationStep(2, 'icra-defteri', (db) => db.migrateLedgers()),
  ];

  static int schemaOf(PortalDatabase db) =>
      int.tryParse(db.meta(schemaKey) ?? '') ?? 0;

  /// Makes [db] current; true when a step ran. [backups] is where the copy
  /// goes before the first step; none for a database in memory.
  static bool run(
    PortalDatabase db, {
    Directory? backups,
    List<SyncMigrationStep>? using,
    DateTime Function()? now,
  }) {
    final all = [...(using ?? steps)]..sort((a, b) => a.to.compareTo(b.to));
    final current = schemaOf(db);
    final pending = [
      for (final s in all)
        if (s.to > current) s,
    ];
    if (pending.isEmpty) {
      if (current < base) db.setMeta(schemaKey, '$base');
      return false;
    }
    if (backups != null) {
      backups.createSync(recursive: true);
      final at = (now ?? DateTime.now)().toUtc().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      db.backupTo(p.join(backups.path, 'portal-sema$current-$at.sqlite'));
    }
    for (final s in pending) {
      db.inTransaction(() {
        s.run(db);
        db.setMeta(schemaKey, '${s.to}');
      });
    }
    return true;
  }
}

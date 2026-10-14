part of 'portal_database.dart';

/// A case's own account in Folio shared with it (docs/senkron-plan.md R8,
/// §3 decision 4): the owner's enforcement payments of the case, kept by
/// the one it is shared with apart from their own, read only, in no
/// account nor Kasa of theirs; each with the owner and the share's version,
/// so that one of before brings nothing back, and gone when the share is.
extension PortalSharedLedger on PortalDatabase {
  static const _tables = '''
    CREATE TABLE IF NOT EXISTS shared_ledger_state (
      sahip TEXT NOT NULL, dosya TEXT NOT NULL, surum TEXT NOT NULL,
      acik INTEGER NOT NULL, PRIMARY KEY(sahip, dosya));
    CREATE TABLE IF NOT EXISTS shared_ledger (
      sahip TEXT NOT NULL, dosya TEXT NOT NULL, id TEXT NOT NULL,
      json TEXT NOT NULL, PRIMARY KEY(sahip, dosya, id));
  ''';

  // The owner's word.

  static const _ledgerShares = 'paylasim-defter';

  /// Whether this person's [caseKey]'s account goes with it, and the
  /// version of that word.
  ({bool on, Hlc version})? ledgerShare(String caseKey) {
    final all = PortalAgendaVersions._map(meta(_ledgerShares)) ?? const {};
    final j = all[caseKey];
    if (j is! Map) return null;
    final v = Hlc.tryParse(j['surum']);
    return v == null ? null : (on: j['acik'] == true, version: v);
  }

  /// This person's [caseKey]'s account shared with it, or no longer: a
  /// new version of the word either way.
  void setLedgerShare(String caseKey, bool on) {
    final all = {...?PortalAgendaVersions._map(meta(_ledgerShares))};
    final was = ledgerShare(caseKey);
    if (was != null && was.on == on) return;
    all[caseKey] = {'acik': on, 'surum': '${SyncClock.of(this).tick()}'};
    setMeta(_ledgerShares, jsonEncode(all));
    PortalDatabase.changed?.call();
  }

  // The one it is shared with.

  /// [owner]'s account of [caseKey] as it came, of its share's [version]:
  /// none of before taken; [records] (theirs, of the case) taken record by
  /// record, group by group (R1); [closed], all of it gone, and said so.
  /// True when anything here changed.
  bool takeSharedLedger(
    String owner,
    String caseKey,
    Hlc version, {
    List<ClientRecord> records = const [],
    bool closed = false,
    String ownerName = '',
  }) {
    final kept = _db.select(
      'SELECT surum, acik FROM shared_ledger_state WHERE sahip=? AND dosya=?',
      [owner, caseKey],
    );
    final was = kept.isEmpty ? null : Hlc.tryParse(kept.first['surum']);
    if (was != null && version < was) return false;
    var changed = false;
    _transaction(() {
      if (closed) {
        final had = _db.select(
          'SELECT 1 FROM shared_ledger WHERE sahip=? AND dosya=?',
          [owner, caseKey],
        );
        _db.execute('DELETE FROM shared_ledger WHERE sahip=? AND dosya=?', [
          owner,
          caseKey,
        ]);
        if (had.isNotEmpty) {
          setMeta(
            'paylasilan-defter-kaldirildi|$caseKey',
            ownerName.isEmpty ? owner : ownerName,
          );
          changed = true;
        }
      } else {
        for (final r in records) {
          if (r.kind != ClientRecordKind.enforcement ||
              r.person != owner ||
              r.text('dosya') != caseKey) {
            continue;
          }
          final row = _db.select(
            'SELECT json FROM shared_ledger WHERE sahip=? AND dosya=? AND id=?',
            [owner, caseKey, r.id],
          );
          final mine = row.isEmpty
              ? null
              : ClientRecord.fromJson(
                  PortalAgendaVersions._map(row.first['json']),
                );
          final next = mine == null ? r : LedgerBook.merge(mine, r);
          if (mine != null &&
              LedgerBook.contentOf(mine) == LedgerBook.contentOf(next)) {
            continue;
          }
          _db.execute(
            'INSERT OR REPLACE INTO shared_ledger(sahip, dosya, id, json) '
            'VALUES(?,?,?,?)',
            [owner, caseKey, r.id, jsonEncode(next.toJson())],
          );
          changed = true;
        }
        setMeta('paylasilan-defter-kaldirildi|$caseKey', '');
      }
      final open = closed ? 0 : 1;
      if (was == null || version > was || kept.first['acik'] != open) {
        _db.execute(
          'INSERT OR REPLACE INTO shared_ledger_state(sahip, dosya, surum, '
          'acik) VALUES(?,?,?,?)',
          [owner, caseKey, '$version', open],
        );
      }
    });
    return changed;
  }

  /// The accounts of [caseKey] shared with this person, by their owner:
  /// those records only that are not here through a card shared too (one
  /// record, kept once).
  Map<String, List<ClientRecord>> sharedLedgersOf(String caseKey) {
    final out = <String, List<ClientRecord>>{};
    for (final r in _db.select(
      'SELECT sahip, json FROM shared_ledger WHERE dosya=?',
      [caseKey],
    )) {
      final rec = ClientRecord.fromJson(PortalAgendaVersions._map(r['json']));
      if (rec == null) continue;
      if (_db.select('SELECT 1 FROM client_record WHERE id=?', [
        rec.id,
      ]).isNotEmpty) {
        continue;
      }
      out.putIfAbsent(r['sahip'] as String, () => []).add(rec);
    }
    return out;
  }

  /// A record of an account shared with this person; null for none.
  ClientRecord? sharedLedgerRecord(String id) {
    final r = _db.select('SELECT json FROM shared_ledger WHERE id=?', [id]);
    return r.isEmpty
        ? null
        : ClientRecord.fromJson(PortalAgendaVersions._map(r.first['json']));
  }

  /// Who stopped sharing [caseKey]'s account with this person, its records
  /// gone from here; null while none did.
  String? sharedLedgerRemoved(String caseKey) {
    final v = meta('paylasilan-defter-kaldirildi|$caseKey');
    return v == null || v.isEmpty ? null : v;
  }

  /// Every account shared with this person forgotten: they may no longer
  /// see the money (R11).
  void forgetSharedLedgers() {
    _db.execute('DELETE FROM shared_ledger');
    _db.execute('DELETE FROM shared_ledger_state');
  }
}

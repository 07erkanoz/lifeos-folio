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

  // The owner's side.

  static const _shareVersions = 'paylasim-surum';

  /// The version of the word of whom [caseKey] is shared with: each change
  /// of it a later one, for one of before to bring nothing back.
  Hlc? caseShareVersion(String caseKey) => Hlc.tryParse(
    (PortalAgendaVersions._map(meta(_shareVersions)) ?? const {})[caseKey],
  );

  /// The version of [caseKey]'s account for [person]: a later one each
  /// time it opens or closes for them, at least the share's own.
  Hlc accessVersion(String caseKey, String person, bool open) {
    final all = {...?PortalAgendaVersions._map(meta('paylasim-erisim'))};
    final key = '$caseKey|$person';
    final kept = all[key] is Map ? all[key] as Map : null;
    final share = caseShareVersion(caseKey);
    final was = Hlc.tryParse(kept?['surum']);
    if (kept != null &&
        kept['acik'] == open &&
        was != null &&
        (share == null || was >= share)) {
      return was;
    }
    final now = SyncClock.of(this).tick();
    all[key] = {'acik': open, 'surum': '$now'};
    setMeta('paylasim-erisim', jsonEncode(all));
    return now;
  }

  /// [caseKey]'s share's version, as another own device's word had it.
  void setCaseShareVersion(String caseKey, Hlc version) {
    final all = {...?PortalAgendaVersions._map(meta(_shareVersions))};
    all[caseKey] = '$version';
    setMeta(_shareVersions, jsonEncode(all));
  }

  /// Whom [caseKey] is shared with changed: a new version of that word.
  void tickCaseShare(String caseKey) {
    final all = {...?PortalAgendaVersions._map(meta(_shareVersions))};
    all[caseKey] = '${SyncClock.of(this).tick()}';
    setMeta(_shareVersions, jsonEncode(all));
  }

  /// This person's own enforcement payments of [caseKey], as the ones it
  /// is shared with who may see the money take them: its secret
  /// descriptions empty (R7), never a colleague's that came here.
  List<Map<String, Object?>> caseLedgerForOffice(String caseKey, String me) => [
    for (final r in allClientRecords())
      if (r.kind == ClientRecordKind.enforcement &&
          r.text('dosya') == caseKey &&
          (r.person == me || r.person.isEmpty))
        {...SecretNotes.recordForOffice(this, r), 'kisi': me},
  ];

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
    bool fromOwner = true,
  }) {
    final kept = _db.select(
      'SELECT surum, acik FROM shared_ledger_state WHERE sahip=? AND dosya=?',
      [owner, caseKey],
    );
    final was = kept.isEmpty ? null : Hlc.tryParse(kept.first['surum']);
    if (was != null && version < was) return false;
    // Closed here (the money no longer let, or the share taken off): opened
    // again at the same version only by its owner's word as it is now, not
    // by a copy another own device kept of before.
    if (!closed &&
        !fromOwner &&
        was != null &&
        version == was &&
        kept.first['acik'] != 1) {
      return false;
    }
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
        for (var r in records) {
          if (r.kind != ClientRecordKind.enforcement ||
              r.person != owner ||
              r.text('dosya') != caseKey) {
            continue;
          }
          // Its description taken back by its owner: not kept (R7).
          r = _withoutTakenDescription(owner, r);
          // Here through the card too: one record, kept alike both ways.
          final card = clientRecord(r.id);
          if (card != null &&
              card.person == owner &&
              card.kind == ClientRecordKind.enforcement &&
              !LedgerBook.isProjected(card)) {
            final both = LedgerBook.merge(card, r);
            if (LedgerBook.contentOf(both) != LedgerBook.contentOf(card)) {
              _putRecord(both);
              rebuildLedger(both.id);
              changed = true;
            }
            r = both;
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
  /// see the money (R11). What version each share had is kept: the money
  /// let again, no package of before brings one back.
  void forgetSharedLedgers() {
    _db.execute('DELETE FROM shared_ledger');
    _db.execute('UPDATE shared_ledger_state SET acik=0');
  }

  /// [r] with its description empty when its owner took it back at a
  /// version not older than its own.
  ClientRecord _withoutTakenDescription(String owner, ClientRecord r) {
    final hide = takenNoteHide(owner, 'aciklama:${r.id}');
    if (hide == null ||
        r.text('aciklama').isEmpty ||
        LedgerBook.versionOf(r, 'bilgi') > hide) {
      return r;
    }
    return ClientRecord.fromJson({
          ...r.toJson(),
          'veri': {...r.data, 'aciklama': '', 'aciklamaGizli': true},
        }) ??
        r;
  }

  /// The descriptions taken back, out of the accounts shared with this
  /// person too. True when one was.
  bool applyTakenHidesToShared() {
    var changed = false;
    for (final row in _db.select(
      'SELECT sahip, dosya, id, json FROM shared_ledger',
    )) {
      final r = ClientRecord.fromJson(PortalAgendaVersions._map(row['json']));
      if (r == null) continue;
      final next = _withoutTakenDescription(row['sahip'] as String, r);
      if (identical(next, r)) continue;
      _db.execute(
        'UPDATE shared_ledger SET json=? WHERE sahip=? AND dosya=? AND id=?',
        [jsonEncode(next.toJson()), row['sahip'], row['dosya'], row['id']],
      );
      changed = true;
    }
    return changed;
  }

  /// [r], come through a card, kept alike in the account shared too.
  void _alsoShared(ClientRecord r) {
    final rows = _db.select(
      'SELECT sahip, dosya, json FROM shared_ledger WHERE id=?',
      [r.id],
    );
    for (final row in rows) {
      final kept = ClientRecord.fromJson(
        PortalAgendaVersions._map(row['json']),
      );
      if (kept == null || kept.person != r.person) continue;
      final both = LedgerBook.merge(kept, r);
      _db.execute(
        'UPDATE shared_ledger SET json=? WHERE sahip=? AND dosya=? AND id=?',
        [jsonEncode(both.toJson()), row['sahip'], row['dosya'], r.id],
      );
    }
  }

  /// What the person's other devices take of the accounts shared with
  /// them: each with its share's version.
  Map<String, Object?> sharedLedgersExport() => {
    'durumlar': [
      for (final r in _db.select('SELECT * FROM shared_ledger_state'))
        {for (final c in r.keys) c: r[c]},
    ],
    'kayitlar': [
      for (final r in _db.select('SELECT * FROM shared_ledger'))
        {for (final c in r.keys) c: r[c]},
    ],
  };

  /// Another own device's [sharedLedgersExport], taken by the same rules:
  /// none of before, closed ones gone. True when anything changed.
  bool sharedLedgersMerge(Object? theirs) {
    if (theirs is! Map) return false;
    var changed = false;
    final byShare = <String, List<ClientRecord>>{};
    for (final r in theirs['kayitlar'] as List? ?? const []) {
      if (r is! Map) continue;
      final rec = ClientRecord.fromJson(PortalAgendaVersions._map(r['json']));
      if (rec == null) continue;
      byShare.putIfAbsent('${r['sahip']}|${r['dosya']}', () => []).add(rec);
    }
    for (final s in theirs['durumlar'] as List? ?? const []) {
      if (s is! Map || s['sahip'] is! String || s['dosya'] is! String) {
        continue;
      }
      final v = Hlc.tryParse(s['surum']);
      if (v == null) continue;
      if (takeSharedLedger(
        s['sahip'] as String,
        s['dosya'] as String,
        v,
        closed: s['acik'] != 1,
        fromOwner: false,
        records: byShare['${s['sahip']}|${s['dosya']}'] ?? const [],
      )) {
        changed = true;
      }
    }
    return changed;
  }
}

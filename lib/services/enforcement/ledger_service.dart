import 'dart:math';

import '../clients/client.dart';
import '../clients/client_accounts.dart';
import '../portal/portal_database.dart';
import '../sync/hlc.dart';
import '../sync/sync_generation.dart';
import 'ledger_book.dart';

/// The record changed since it was shown: nothing was written.
class LedgerConflict implements Exception {
  const LedgerConflict();
  @override
  String toString() =>
      'Kayıt bu arada değişti (başka bir cihazda). Yeniden açıp deneyin.';
}

/// The record waits for its repair report to be looked at.
class LedgerNeedsRepair implements Exception {
  const LedgerNeedsRepair();
  @override
  String toString() =>
      'Bu ödemenin eski kayıtları onarım bekliyor; önce onarım raporuna bakın.';
}

/// Another person's record of the office: changed only by them (R6).
class LedgerNotYours implements Exception {
  const LedgerNotYours();
  @override
  String toString() => 'Bu kaydı yalnız yazan değiştirebilir.';
}

/// A set-off past what is held for the client.
class LedgerOverdrawn implements Exception {
  const LedgerOverdrawn(this.left);

  /// Kuruş still held.
  final int left;
  @override
  String toString() => 'Mahsup, emanette kalandan fazla.';
}

/// Every change of an enforcement file's own account, each in one
/// transaction (docs/senkron-plan.md R12): the record read anew, the
/// version shown checked, its changed groups given new versions, and its
/// movements made anew with it; all of it or none.
class LedgerService {
  LedgerService(this.db, {HlcClock? clock, Random? random})
    : _clock = clock ?? SyncClock.of(db);

  final PortalDatabase db;
  final HlcClock _clock;

  /// This database's own id: [SyncClock.localDeviceId].
  static String localDeviceId(PortalDatabase db, {Random? random}) =>
      SyncClock.localDeviceId(db, random: random);

  /// [id]'s record as it is now, to be changed here: refused when it waits
  /// for its repair or is still in an older Folio's form, when it is
  /// another person's, or when it no longer says what [seen] (what was
  /// shown) said.
  ClientRecord _fresh(String id, {required String seen}) {
    if (db.ledgerRepairOf(id) != null) throw const LedgerNeedsRepair();
    final now = db.clientRecord(id);
    if (now == null || now.kind != ClientRecordKind.enforcement) {
      throw const LedgerConflict();
    }
    if (!LedgerBook.isNewForm(now)) throw const LedgerNeedsRepair();
    final me = PortalDatabase.clientPerson?.call() ?? '';
    if (now.person.isNotEmpty && me.isNotEmpty && now.person != me) {
      throw const LedgerNotYours();
    }
    if (LedgerBook.tokenOf(now) != seen) throw const LedgerConflict();
    return now;
  }

  ClientRecord _write(
    ClientRecord r, {
    required String what,
    required Map<String, Hlc> versions,
    required List<LedgerSetOff> setOffs,
    Map<String, Object?>? data,
    String? clientId,
    bool? removed,
    bool made = false,
  }) {
    final next = LedgerBook.write(
      r,
      versions: versions,
      setOffs: setOffs,
      data: data,
      clientId: clientId,
      removed: removed,
      updated: DateTime.now(),
    );
    if (!db.saveClientRecord(next)) {
      throw StateError('Kayıt yazılamadı.');
    }
    // Who changed what, when, from where; no money in it (R3, R5).
    db.addLedgerHistory(next.id, {
      'islem': what,
      'kisi': PortalDatabase.clientPerson?.call() ?? '',
      'kaynak': _clock.source,
      'zaman': DateTime.now().toIso8601String(),
      if (!made) 'eski': LedgerBook.contentOf(r),
      'yeni': LedgerBook.contentOf(next),
    });
    return next;
  }

  /// A new line: a payment made outside, or a waiver. [target], when
  /// given, takes the whole of it as a fee at once.
  ClientRecord add({
    required String clientId,
    required String caseKey,
    required String kind,
    required int amount,
    required DateTime at,
    required String by,
    String person = '',
    String debtor = '',
    String way = '',
    String note = '',
    bool whole = false,
    int? uyapLeft,
    MovementKind? target,
  }) {
    late ClientRecord made;
    db.inTransaction(() {
      final now = DateTime.now();
      final base = ClientRecord(
        id: Client.newId(),
        clientId: clientId,
        kind: ClientRecordKind.enforcement,
        data: {
          'dosya': caseKey,
          'tur': kind,
          'tutar': amount,
          'zaman': at.toIso8601String(),
          'borclu': debtor,
          'odeme': way,
          'aciklama': note,
          'tamami': whole,
          'uyapBakiye': ?uyapLeft,
        },
        created: now,
        by: by,
        updated: now,
        person: person,
      );
      final version = _clock.tick();
      made = _write(
        base,
        what: 'ekle',
        made: true,
        versions: {
          for (final g in [...LedgerBook.groups.keys, LedgerBook.lifecycle])
            g: version,
        },
        setOffs: [
          if (target != null && target.isApplied)
            LedgerSetOff(
              id: Client.newId(),
              target: target,
              amount: amount,
              at: at,
              version: version,
            ),
        ],
      );
    });
    return made;
  }

  /// [seen] corrected. [target] is where the whole of its money went as
  /// the dialog left it (null: held), [shown] as the dialog showed it:
  /// - chosen anew, the set-offs standing are taken off and, for a fee, one
  ///   of the whole sum made;
  /// - left as it was, the set-offs stay as they are (a part taken from the
  ///   client's card among them); only one of the whole sum, as the dialog
  ///   makes it, follows the sum and the day.
  ClientRecord edit(
    ClientRecord seen, {
    required int amount,
    required DateTime at,
    required String debtor,
    required String way,
    required String note,
    required bool whole,
    required MovementKind? target,
    MovementKind? shown,
  }) {
    late ClientRecord made;
    db.inTransaction(() {
      final r = _fresh(seen.id, seen: LedgerBook.tokenOf(seen));
      final versions = LedgerBook.versionsOf(r);
      final data = {
        ...r.data,
        'tutar': amount,
        'zaman': at.toIso8601String(),
        'odeme': way,
        'tamami': whole,
        'borclu': debtor,
        'aciklama': note,
      };
      final money =
          amount != r.amount ||
          at != r.at ||
          way != r.text('odeme') ||
          whole != (r.data['tamami'] == true);
      final words = debtor != r.text('borclu') || note != r.text('aciklama');
      if (money) {
        // The lawyer's word that UYAP has it was for the sum and day it
        // had: not for these (R4).
        final word =
            r.text('resmiKarar') == 'elle' || r.text('resmi') == 'elle';
        if (word) {
          data['resmiKararSurum'] = '${versions['finans']}';
          data['resmi'] = '';
          if (r.text('resmi') == 'elle') data['resmiKarar'] = 'elle';
          versions['resmiKarar'] = _clock.tick();
        }
        versions['finans'] = _clock.tick();
      }
      if (words) versions['bilgi'] = _clock.tick();
      var setOffs = LedgerBook.setOffsOf(r);
      if (target != shown) {
        setOffs = [
          for (final s in setOffs)
            s.removed ? s : s.copyWith(removed: true, version: _clock.tick()),
          if (target != null && target.isApplied)
            LedgerSetOff(
              id: Client.newId(),
              target: target,
              amount: amount,
              at: at,
              version: _clock.tick(),
            ),
        ];
      } else if (money) {
        final standing = [
          for (final s in setOffs)
            if (!s.removed) s,
        ];
        if (standing.length == 1 && standing.single.amount == r.amount) {
          final s = standing.single;
          setOffs = [
            for (final x in setOffs)
              x.id == s.id
                  ? x.copyWith(amount: amount, at: at, version: _clock.tick())
                  : x,
          ];
        }
      }
      made = _write(
        r,
        what: 'duzelt',
        versions: versions,
        setOffs: setOffs,
        data: data,
      );
    });
    return made;
  }

  /// [seen] marked as told to the office ([at]), or not yet (null).
  ClientRecord setReported(ClientRecord seen, DateTime? at) => _group(
    seen,
    'bildirildi',
    (data) => {...data, 'bildirildi': at?.toIso8601String() ?? ''},
  );

  /// [seen] marked by the lawyer as UYAP has it, or not.
  ClientRecord setOfficial(ClientRecord seen, bool official) => _group(
    seen,
    'resmiKarar',
    (data) => {
      ...data,
      'resmiKarar': official ? 'elle' : '',
      'resmi': '',
      // For the sum and day it has now (R4).
      'resmiKararSurum': official
          ? '${LedgerBook.versionOf(seen, 'finans')}'
          : '',
    },
  );

  ClientRecord _group(
    ClientRecord seen,
    String group,
    Map<String, Object?> Function(Map<String, Object?> data) change,
  ) {
    late ClientRecord made;
    db.inTransaction(() {
      final r = _fresh(seen.id, seen: LedgerBook.tokenOf(seen));
      final versions = LedgerBook.versionsOf(r)..[group] = _clock.tick();
      made = _write(
        r,
        what: group,
        versions: versions,
        setOffs: LedgerBook.setOffsOf(r),
        data: change(r.data),
      );
    });
    return made;
  }

  /// [seen] taken off the file's account, or put back ([removed] false):
  /// its money in the client's account and Kasa goes and comes with it.
  ClientRecord setRemoved(ClientRecord seen, bool removed) {
    late ClientRecord made;
    db.inTransaction(() {
      final r = _fresh(seen.id, seen: LedgerBook.tokenOf(seen));
      final versions = LedgerBook.versionsOf(r)
        ..[LedgerBook.lifecycle] = _clock.tick();
      made = _write(
        r,
        what: removed ? 'kaldir' : 'geri-koy',
        versions: versions,
        setOffs: LedgerBook.setOffsOf(r),
        removed: removed,
      );
    });
    return made;
  }

  /// [amount] of what [entryId] holds for the client taken as [target]
  /// ([LedgerOverdrawn] past what is left).
  ///
  /// [seen] is the mark of the record as the movement it was made from
  /// showed it ([LedgerBook.tokenOf], its `defterSurum`).
  ClientRecord addSetOff(
    String entryId,
    MovementKind target,
    int amount, {
    required String seen,
    DateTime? at,
  }) {
    late ClientRecord made;
    db.inTransaction(() {
      final r = _fresh(entryId, seen: seen);
      final state = LedgerBook.stateOf(r);
      final left =
          state.held - state.active.fold<int>(0, (n, s) => n + s.amount);
      if (!target.isApplied || amount <= 0 || amount > left) {
        throw LedgerOverdrawn(left);
      }
      made = _write(
        r,
        what: 'mahsup',
        versions: LedgerBook.versionsOf(r),
        setOffs: [
          ...LedgerBook.setOffsOf(r),
          LedgerSetOff(
            id: Client.newId(),
            target: target,
            amount: amount,
            at: at ?? DateTime.now(),
            version: _clock.tick(),
          ),
        ],
      );
    });
    return made;
  }

  /// [setOffId] of [entryId] taken back: the money held again.
  ClientRecord removeSetOff(
    String entryId,
    String setOffId, {
    required String seen,
  }) {
    late ClientRecord made;
    db.inTransaction(() {
      final r = _fresh(entryId, seen: seen);
      made = _write(
        r,
        what: 'mahsup-geri-al',
        versions: LedgerBook.versionsOf(r),
        setOffs: [
          for (final s in LedgerBook.setOffsOf(r))
            s.id == setOffId && !s.removed
                ? s.copyWith(removed: true, version: _clock.tick())
                : s,
        ],
      );
    });
    return made;
  }

  /// The record and set-off a projected movement [m] stands for: null for
  /// a movement not made of a ledger.
  static ({String entryId, String? setOffId})? sourceOf(ClientRecord m) {
    if (!LedgerBook.isProjected(m)) return null;
    final parts = m.id.split(':');
    if (parts.length < 3 || parts.first != 'icra') return null;
    return (
      entryId: parts[1],
      setOffId: parts.length >= 4 && parts[2] == 'mahsup' ? parts[3] : null,
    );
  }
}

import 'dart:math';

import '../clients/client.dart';
import '../clients/client_accounts.dart';
import '../enforcement/ledger_book.dart';
import '../enforcement/ledger_service.dart';
import '../portal/portal_database.dart';
import '../sync/hlc.dart';
import '../sync/sync_generation.dart';
import '../../models/json_shape.dart';

/// A colleague's proposals of another's records, and the owner's decisions
/// on them (docs/senkron-plan.md R6, §3 decision 2): an enforcement
/// payment's sum, day, debtor, way and description, or that it be taken
/// off; a card's note; a case's note.
///
/// A proposal never changes. Its owner decides on their one device for
/// deciding ([DecisionDevice]): taken, the record is changed there, in the
/// same transaction as the decision, which carries what it changed; the
/// owner's other devices take the change as they take any, never running
/// the proposal again. A decision of a device given up as lost before it
/// came does not hold: what it changed is put back where nothing changed
/// it since, the proposal open again.
class ProposalService {
  ProposalService(
    this.db, {
    required this.me,
    required this.device,
    this.myName = '',
    this.kept = true,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// Whether this device's keys are kept: one whose are this run's only
  /// is seen anew at its next start, and never decides (R6).
  final bool kept;

  final PortalDatabase db;

  /// This person, and this device of theirs.
  final String me, device;
  final String myName;
  final Random _random;

  String _newId() =>
      'o${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_random.nextInt(1 << 32).toRadixString(36)}';

  /// The versions of what [kind] [target] says now: for a proposal to be
  /// made seeing, and to be found old by.
  static Map<String, String> versionsOf(
    PortalDatabase db,
    String kind,
    String target, {
    String caseKey = '',
  }) {
    switch (kind) {
      case 'icra':
        final r = enforcementRecord(db, target);
        if (r == null || r.kind != ClientRecordKind.enforcement) return {};
        return {
          for (final e in LedgerBook.versionsOf(r).entries) e.key: '${e.value}',
        };
      case 'kartNotu':
        final c = db.clientCard(target);
        return c == null ? {} : {'not': '${c.versionOf('not')}'};
      case 'dosyaNotu':
        final n = db.clientCard(target)?.caseNotes[caseKey];
        return {'not': n == null ? '' : '${n.versionOf}'};
    }
    return {};
  }

  /// Enforcement payment [id] as known here: one's own or a card's, else
  /// of a case's account shared with this person (R8).
  static ClientRecord? enforcementRecord(PortalDatabase db, String id) =>
      db.clientRecord(id) ?? db.sharedLedgerRecord(id);

  /// The person whose [kind] [target] is; empty for none known.
  static String ownerOf(PortalDatabase db, String kind, String target) =>
      switch (kind) {
        'icra' => enforcementRecord(db, target)?.person ?? '',
        _ => db.clientCard(target)?.person ?? '',
      };

  /// [fields] proposed of another's [kind] [target] (or that it be taken
  /// off): kept, to go to its owner. Null when it is this person's own, or
  /// no one's.
  Proposal? propose({
    required String kind,
    required String target,
    String caseKey = '',
    Map<String, Object?> fields = const {},
    bool remove = false,
    String reason = '',
    Map<String, String>? seen,
    DateTime? now,
  }) {
    final owner = ownerOf(db, kind, target);
    if (owner.isEmpty || owner == me || me.isEmpty) return null;
    final p = Proposal(
      id: _newId(),
      owner: owner,
      by: me,
      byName: myName,
      kind: kind,
      target: target,
      caseKey: caseKey,
      // What it was made seeing: as the screen showed it, not as it is now.
      seen: seen ?? versionsOf(db, kind, target, caseKey: caseKey),
      fields: fields,
      remove: remove,
      reason: reason,
      at: now ?? DateTime.now(),
    );
    db.putProposal(p);
    PortalDatabase.changed?.call();
    return p;
  }

  /// The device on which [owner]'s proposals are decided: as chosen, else
  /// their first device (the one the office knows them by).
  DecisionDevice deciding(String owner) {
    final kept = db.decisionDevice(owner);
    if (kept == null) {
      return DecisionDevice(device: owner, generation: 0, at: DateTime(2000));
    }
    // The first generation's device, before any was chosen: their first.
    return kept.winners.containsKey(0) || kept.generation == 0
        ? kept
        : DecisionDevice(
            device: kept.device,
            generation: kept.generation,
            at: kept.at,
            lost: kept.lost,
            lostAt: kept.lostAt,
            known: kept.known,
            winners: {0: owner, ...kept.winners},
          );
  }

  /// Whether this device decides this person's proposals.
  bool get decidesHere => kept && deciding(me).device == device;

  /// The proposals made to this person not yet decided, the oldest first.
  List<Proposal> get waiting => [
    for (final p in db.proposals(owner: me).reversed)
      if (db.decisionOf(p.id) case final d when d == null || d.void_) p,
  ];

  /// The decisions of this person's that did not hold and whose change was
  /// changed again since: to be looked at.
  List<ProposalDecision> get conflicts => [
    for (final d in db.decisions)
      if (d.owner == me &&
          (d.conflict ||
              (db.blockedOf(d.proposal)['_catisma']?.isNotEmpty ?? false)) &&
          db.meta('oneri_catisma_goruldu:${d.proposal}') != '1')
        d,
  ];

  /// [proposal]'s conflict looked at, on this device: not shown here again.
  void conflictSeen(String proposal) =>
      db.setMeta('oneri_catisma_goruldu:$proposal', '1');

  /// Whether [p] was made seeing what its record says now.
  bool current(Proposal p) {
    if (p.scrubbed) return false;
    final now = versionsOf(db, p.kind, p.target, caseKey: p.caseKey);
    return now.isNotEmpty &&
        Hlc.canonical(now) == Hlc.canonical(p.seen) &&
        (p.kind != 'icra' || enforcementRecord(db, p.target) != null);
  }

  /// This person's word on [proposalId], on their device for deciding:
  /// taken ([approve]) it changes the record in the same transaction, and
  /// the decision says what it changed; one made on a record changed since
  /// is not taken, said to be old. Null when it may not be decided here.
  ProposalDecision? decide(
    String proposalId, {
    required bool approve,
    String reason = '',
    DateTime? now,
  }) {
    final p = db.proposal(proposalId);
    if (p == null || p.owner != me || !decidesHere) return null;
    final had = db.decisionOf(p.id);
    if (had != null && !had.void_) return null;
    ProposalDecision? made;
    db.inTransaction(() {
      final fresh = current(p);
      var outputs = const <String, Object?>{};
      if (approve && fresh) outputs = _apply(p);
      made = ProposalDecision(
        proposal: p.id,
        owner: me,
        approved: approve && fresh,
        stale: approve && !fresh,
        device: device,
        generation: deciding(me).generation,
        at: now ?? DateTime.now(),
        reason: reason,
        outputs: outputs,
      );
      db.putDecision(made!);
    });
    PortalDatabase.changed?.call();
    return made;
  }

  /// [p]'s fields written, as the owner would write them here; what it
  /// changed, before and after.
  Map<String, Object?> _apply(Proposal p) {
    switch (p.kind) {
      case 'icra':
        final r = db.clientRecord(p.target)!;
        final book = LedgerService(db);
        final f = p.fields;
        final after = p.remove
            ? book.setRemoved(r, true)
            : book.edit(
                r,
                amount: f['tutar'] is int ? f['tutar'] as int : r.amount,
                at: DateTime.tryParse('${f['zaman']}') ?? r.at,
                debtor: '${f['borclu'] ?? r.text('borclu')}',
                way: '${f['odeme'] ?? r.text('odeme')}',
                note: '${f['aciklama'] ?? r.text('aciklama')}',
                whole: f['tamami'] is bool
                    ? f['tamami'] as bool
                    : r.data['tamami'] == true,
                target: null,
                shown: null,
              );
        return {'once': r.toJson(), 'sonra': after.toJson()};
      case 'kartNotu' || 'dosyaNotu':
        final card = db.clientCard(p.target)!;
        final text = '${p.fields['metin'] ?? ''}';
        final made = p.kind == 'kartNotu'
            ? card.copyWith(note: text)
            : card.copyWith(
                caseNotes: {
                  ...card.caseNotes,
                  p.caseKey: CaseNote(text, DateTime.now(), by: p.byName),
                },
              );
        db.saveClient(made);
        return {
          'once': card.toJson(),
          'sonra': db.clientCard(p.target)!.toJson(),
        };
    }
    return const {};
  }

  /// [d], a decision of this person's that came from another of their
  /// devices: kept when it stands over the one here; one that does not
  /// hold by the device for deciding as chosen ([DecisionDevice.holds]) is
  /// kept as not holding, what it changed put back group by group where
  /// nothing changed it since, and kept from coming here after (else a
  /// conflict, to be looked at). True when anything here changed.
  bool takeOwn(ProposalDecision d) {
    final choice = deciding(me);
    final had = db.decisionOf(d.proposal);
    if (choice.holds(d) && !d.void_) {
      if (had != null && !d.supersedes(had)) return false;
      // Never over one that holds by the device chosen, of after it.
      if (had != null &&
          !had.void_ &&
          choice.holds(had) &&
          had.generation > d.generation) {
        return false;
      }
      db.deleteDecision(d.proposal);
      db.putDecision(d);
      return true;
    }
    // One that does not hold: what it changed taken back, once, whatever
    // decision stands now; that one kept as it is.
    var changed = false;
    db.inTransaction(() {
      final mark = '${d.device}|${d.generation}|${d.at.toIso8601String()}';
      final handled =
          db.blockedOf(d.proposal)['_karar']?.contains(mark) ?? false;
      var conflict = false;
      if (!handled) {
        conflict = !_undo(d);
        db.blockOutput(d.proposal, '_karar', mark);
        if (conflict) db.blockOutput(d.proposal, '_catisma', mark);
        changed = true;
      }
      final sameOne =
          had != null &&
          had.device == d.device &&
          had.generation == d.generation &&
          had.at == d.at;
      final stands = had != null && !had.void_ && choice.holds(had) && !sameOne;
      if (!stands && (had == null || d.supersedes(had) || !had.void_)) {
        db.deleteDecision(d.proposal);
        db.putDecision(d.voided(conflict: conflict || d.conflict));
        changed = true;
      }
    });
    return changed;
  }

  /// What [d] changed, group by group, put back where it is as [d] left it
  /// (its version that one), and that version kept from coming here after;
  /// one not come yet only kept from coming. False when one was changed
  /// since (a conflict).
  bool _undo(ProposalDecision d) {
    final before = d.outputs['once'], after = d.outputs['sonra'];
    if (before is! Map || after is! Map) return true;
    final p = db.proposal(d.proposal);
    if (p == null) return true;
    var clean = true;
    switch (p.kind) {
      case 'icra':
        final was = ClientRecord.fromJson(before);
        final left = ClientRecord.fromJson(after);
        if (was == null || left == null) return true;
        final wasV = LedgerBook.versionsOf(was),
            leftV = LedgerBook.versionsOf(left);
        final back = <String>[];
        for (final g in [...LedgerBook.groups.keys, LedgerBook.lifecycle]) {
          if (wasV[g] == leftV[g]) continue;
          db.blockOutput(p.target, g, '${leftV[g]}');
          final now = db.clientRecord(p.target);
          if (now == null) continue;
          final v = LedgerBook.versionOf(now, g);
          if (v == leftV[g]) {
            back.add(g);
          } else if (v > leftV[g]!) {
            clean = false;
          }
        }
        // The set-offs it changed, each by its own version.
        final wasS = {for (final x in LedgerBook.setOffsOf(was)) x.id: x};
        final leftS = {for (final x in LedgerBook.setOffsOf(left)) x.id: x};
        final nowRecord = db.clientRecord(p.target);
        final nowS = {
          for (final x in LedgerBook.setOffsOf(nowRecord ?? left)) x.id: x,
        };
        final backS = <String>[];
        for (final x in leftS.values) {
          if (wasS[x.id]?.version == x.version) continue;
          db.blockOutput(p.target, 'mahsup:${x.id}', '${x.version}');
          final v = nowS[x.id]?.version;
          if (v == x.version) {
            backS.add(x.id);
          } else if (v != null && v > x.version) {
            clean = false;
          }
        }
        final now = db.clientRecord(p.target);
        if ((back.isNotEmpty || backS.isNotEmpty) && now != null) {
          final clock = SyncClock.of(db);
          final versions = LedgerBook.versionsOf(now);
          final data = {...now.data};
          var removed = now.removed;
          var clientId = now.clientId;
          for (final g in back) {
            versions[g] = clock.tick();
            if (g == LedgerBook.lifecycle) {
              removed = was.removed;
              continue;
            }
            for (final f in LedgerBook.groups[g]!) {
              if (was.data.containsKey(f)) {
                data[f] = was.data[f];
              } else {
                data.remove(f);
              }
            }
            if (g == 'finans') clientId = was.clientId;
          }
          // The lawyer's word that UYAP has it, given for the sum it had,
          // given again for that sum as it is back (R4).
          if (back.contains('finans') &&
              '${data['resmiKararSurum'] ?? ''}' == '${wasV['finans']}') {
            data['resmiKararSurum'] = '${versions['finans']}';
          }
          final setOffs = [
            for (final x in LedgerBook.setOffsOf(now))
              if (backS.contains(x.id))
                switch (wasS[x.id]) {
                  final w? => w.copyWith(version: clock.tick()),
                  null => x.copyWith(removed: true, version: clock.tick()),
                }
              else
                x,
          ];
          db.saveClientRecord(
            LedgerBook.write(
              now,
              versions: versions,
              setOffs: setOffs,
              data: data,
              clientId: clientId,
              removed: removed,
              updated: DateTime.now(),
            ),
          );
        }
      case 'kartNotu' || 'dosyaNotu':
        final was = Client.fromJson(before), left = Client.fromJson(after);
        if (was == null || left == null) return true;
        final group = p.kind == 'kartNotu' ? 'not' : 'dosyaNotu:${p.caseKey}';
        Hlc? version(Client c) => p.kind == 'kartNotu'
            ? c.versionOf('not')
            : c.caseNotes[p.caseKey]?.versionOf;
        final leftV = version(left);
        if (leftV == null || leftV == version(was)) return true;
        db.blockOutput(p.target, group, '$leftV');
        final now = db.clientCard(p.target);
        final nowV = now == null ? null : version(now);
        if (now == null || nowV == null || nowV < leftV) return true;
        if (nowV > leftV) return false;
        // As it was, its secrecy and writer too.
        db.saveClient(
          p.kind == 'kartNotu'
              ? now.copyWith(note: was.note, noteSecret: was.noteSecret)
              : now.copyWith(
                  caseNotes: {
                    ...now.caseNotes,
                    p.caseKey: switch (was.caseNotes[p.caseKey]) {
                      final n? => CaseNote(
                        n.text,
                        DateTime.now(),
                        by: n.by,
                        secret: n.secret,
                      ),
                      null => CaseNote('', DateTime.now()),
                    },
                  },
                ),
        );
    }
    return clean;
  }

  /// The proposals this person's decisions known here stand on.
  Set<String> get _decided => {
    for (final x in db.decisions)
      if (x.owner == me && !x.void_) x.proposal,
  };

  /// The device for deciding given from this one to [other], another of
  /// this person's own, both on: the next generation.
  DecisionDevice? giveTo(String other) {
    if (!decidesHere || other == device) return null;
    final was = deciding(me);
    // Given over: every decision made before stands.
    final d = DecisionDevice(
      device: other,
      generation: was.generation + 1,
      at: DateTime.now(),
      lostAt: was.lostAt,
      known: {...was.known, ..._decided},
      winners: was.allWinners,
    );
    db.putDecisionDevice(me, d);
    PortalDatabase.changed?.call();
    return d;
  }

  /// The device for deciding lost: this one chosen anew, the next
  /// generation; the decisions known here now hold, any other of before
  /// does not when it comes, its proposal open again.
  DecisionDevice? lost() {
    if (!kept) return null;
    final was = deciding(me);
    final d = DecisionDevice(
      device: device,
      generation: was.generation + 1,
      at: DateTime.now(),
      lost: true,
      lostAt: was.generation + 1,
      known: {...was.known, ..._decided},
      winners: was.allWinners,
    );
    db.putDecisionDevice(me, d);
    PortalDatabase.changed?.call();
    return d;
  }

  /// What goes to the office member [to] (a person): this person's
  /// proposals of theirs, and this person's decisions on theirs. Of money
  /// only when [money] (both may see it, R11). No text of a secret note
  /// is ever in one: a proposal carries only what its maker wrote.
  Map<String, Object?> officeExport(String to, {required bool money}) => {
    'oneriler': [
      for (final p in db.proposals(by: me))
        if (p.owner == to && (money || !p.financial)) p.toJson(),
    ],
    'kararlar': [
      for (final d in db.decisions)
        if (d.owner == me)
          if (db.proposal(d.proposal) case final p?
              when p.by == to && (money || !p.financial))
            {...d.toJson()}..remove('ciktilar'),
    ],
  };

  /// What [from] (a person, by the office's ledger) sent: their proposals
  /// of this person's records, each of a record that is this person's and
  /// that they may see; their decisions on this person's proposals. True
  /// when anything here changed.
  bool officeMerge(Object? theirs, String from, {required bool money}) {
    if (theirs is! Map || from.isEmpty || from == me) return false;
    var changed = false;
    db.inTransaction(() {
      for (final j in jsonList(theirs['oneriler'])) {
        final p = Proposal.fromJson(j);
        if (p == null || p.owner != me || p.by != from) continue;
        if (p.financial && !money) continue;
        if (ownerOf(db, p.kind, p.target) != me) continue;
        // A card's note only of a card shared with the office.
        if (!p.financial && !(db.clientCard(p.target)?.office ?? false)) {
          continue;
        }
        if (db.putProposal(p)) changed = true;
      }
      for (final j in jsonList(theirs['kararlar'])) {
        final d = ProposalDecision.fromJson(j);
        if (d == null || d.owner != from) continue;
        final p = db.proposal(d.proposal);
        if (p == null || p.by != me || p.owner != from) continue;
        final had = db.decisionOf(d.proposal);
        if (had != null && !d.supersedes(had)) continue;
        db.deleteDecision(d.proposal);
        db.putDecision(d);
        changed = true;
      }
    });
    return changed;
  }

  /// What this person's other devices take: the proposals, the decisions
  /// with what they changed, and the device for deciding.
  Map<String, Object?> ownExport() => {
    'oneriler': [
      for (final p in db.proposals())
        if (_mayKeep(p)) p.toJson(),
    ],
    'kararlar': [
      for (final d in db.decisions)
        if (db.proposal(d.proposal) case final p? when _mayKeep(p)) d.toJson(),
    ],
    'kararCihazi': ?db.decisionDevice(me)?.toJson(),
    'engellenen': db.blockedOutputs,
  };

  /// Another own device's [ownExport]: the device for deciding first, so
  /// that its decisions are weighed by it. True when anything changed.
  bool ownMerge(Object? theirs) {
    if (theirs is! Map) return false;
    var changed = false;
    db.inTransaction(() {
      if (DecisionDevice.fromJson(theirs['kararCihazi']) case final c?) {
        if (db.putDecisionDevice(me, c)) {
          changed = true;
          // Decisions known here that no longer hold by the new choice.
          for (final d in db.decisions) {
            if (d.owner == me && !d.void_ && !deciding(me).holds(d)) {
              if (takeOwn(d)) changed = true;
            }
          }
        }
      }
      for (final j in jsonList(theirs['oneriler'])) {
        final p = Proposal.fromJson(j);
        if (p != null && _mayKeep(p) && db.putProposal(p)) changed = true;
      }
      for (final j in jsonList(theirs['kararlar'])) {
        final d = ProposalDecision.fromJson(j);
        if (d == null) continue;
        // Never one whose proposal is not here to be weighed (its money
        // perhaps not this person's to see).
        final of = db.proposal(d.proposal);
        if (of == null || !_mayKeep(of)) continue;
        if (d.owner == me) {
          if (takeOwn(d)) changed = true;
          continue;
        }
        final had = db.decisionOf(d.proposal);
        if (had != null && !d.supersedes(had)) continue;
        db.deleteDecision(d.proposal);
        db.putDecision(d);
        changed = true;
      }
      for (final b in jsonList(theirs['engellenen'])) {
        if (b is Map && b['kayit'] is String && b['grup'] is String) {
          db.blockOutput(
            b['kayit'] as String,
            b['grup'] as String,
            '${b['surum']}',
          );
        }
      }
    });
    return changed;
  }

  /// Whether [p] may be kept here: one of money only while this person may
  /// see it, but for one of their own records (R11).
  bool _mayKeep(Proposal p) =>
      !p.financial ||
      p.owner == me ||
      (PortalDatabase.clientMoneyAllowed?.call() ?? true);

  /// Whether [d] holds by the device for deciding as chosen now.
  bool takeOwnHolds(ProposalDecision d) => deciding(me).holds(d);
}

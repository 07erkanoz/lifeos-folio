import 'dart:math';

import '../clients/client.dart';
import '../clients/client_accounts.dart';
import '../enforcement/ledger_book.dart';
import '../enforcement/ledger_service.dart';
import '../portal/portal_database.dart';
import '../sync/hlc.dart';

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
    Random? random,
  }) : _random = random ?? Random.secure();

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
        final r = db.clientRecord(target);
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

  /// The person whose [kind] [target] is; empty for none known.
  static String ownerOf(PortalDatabase db, String kind, String target) =>
      switch (kind) {
        'icra' => db.clientRecord(target)?.person ?? '',
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
      seen: versionsOf(db, kind, target, caseKey: caseKey),
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
  DecisionDevice deciding(String owner) =>
      db.decisionDevice(owner) ??
      DecisionDevice(device: owner, generation: 0, at: DateTime(2000));

  /// Whether this device decides this person's proposals.
  bool get decidesHere => deciding(me).device == device;

  /// The proposals made to this person not yet decided, the oldest first.
  List<Proposal> get waiting => [
    for (final p in db.proposals(owner: me).reversed)
      if (db.decisionOf(p.id) case final d when d == null || d.void_) p,
  ];

  /// Whether [p] was made seeing what its record says now.
  bool current(Proposal p) {
    final now = versionsOf(db, p.kind, p.target, caseKey: p.caseKey);
    return now.isNotEmpty &&
        Hlc.canonical(now) == Hlc.canonical(p.seen) &&
        (p.kind != 'icra' || db.clientRecord(p.target) != null);
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
  /// devices: kept; one of a device given up as lost before it came does
  /// not hold, and what it changed is put back where nothing changed it
  /// since (else marked a conflict, to be looked at). True when anything
  /// here changed.
  bool takeOwn(ProposalDecision d) {
    final choice = deciding(me);
    final holds =
        d.generation >= choice.generation || choice.known.contains(d.proposal);
    if (holds) return db.putDecision(d);
    // Its proposal decided anew here meanwhile: that one stands.
    final mine = db.decisionOf(d.proposal);
    if (mine != null && !mine.void_ && mine.generation >= choice.generation) {
      return false;
    }
    final had = db.decisionOf(d.proposal);
    if (had != null && had.void_) return false;
    var changed = false;
    db.inTransaction(() {
      final undone = _undo(d);
      db.deleteDecision(d.proposal);
      db.putDecision(
        ProposalDecision.fromJson({
          ...d.voided().toJson(),
          if (!undone) 'catisma': true,
        })!,
      );
      changed = true;
    });
    return changed;
  }

  /// What [d] changed, put back where it is as [d] left it. False when it
  /// was changed since (a conflict).
  bool _undo(ProposalDecision d) {
    final before = d.outputs['once'], after = d.outputs['sonra'];
    if (before is! Map || after is! Map) return true;
    final p = db.proposal(d.proposal);
    if (p == null) return true;
    switch (p.kind) {
      case 'icra':
        final now = db.clientRecord(p.target);
        final was = ClientRecord.fromJson(before);
        final left = ClientRecord.fromJson(after);
        if (now == null || was == null || left == null) return true;
        if (LedgerBook.contentOf(now) != LedgerBook.contentOf(left)) {
          return false;
        }
        final book = LedgerService(db);
        if (now.removed != was.removed) {
          book.setRemoved(now, was.removed);
        } else {
          book.edit(
            now,
            amount: was.amount,
            at: was.at,
            debtor: was.text('borclu'),
            way: was.text('odeme'),
            note: was.text('aciklama'),
            whole: was.data['tamami'] == true,
            target: null,
            shown: null,
          );
        }
        return true;
      case 'kartNotu' || 'dosyaNotu':
        final now = db.clientCard(p.target);
        final was = Client.fromJson(before), left = Client.fromJson(after);
        if (now == null || was == null || left == null) return true;
        if (p.kind == 'kartNotu') {
          if (now.note != left.note) return false;
          db.saveClient(now.copyWith(note: was.note));
        } else {
          final n = now.caseNotes[p.caseKey];
          if (n?.text != left.caseNotes[p.caseKey]?.text) return false;
          final back = was.caseNotes[p.caseKey];
          db.saveClient(
            now.copyWith(
              caseNotes: {
                ...now.caseNotes,
                p.caseKey: CaseNote(back?.text ?? '', DateTime.now()),
              },
            ),
          );
        }
        return true;
    }
    return true;
  }

  /// The device for deciding given from this one to [other], another of
  /// this person's own, both on: the next generation.
  DecisionDevice? giveTo(String other) {
    if (!decidesHere || other == device) return null;
    final d = DecisionDevice(
      device: other,
      generation: deciding(me).generation + 1,
      at: DateTime.now(),
    );
    db.putDecisionDevice(me, d);
    PortalDatabase.changed?.call();
    return d;
  }

  /// The device for deciding lost: this one chosen anew, the next
  /// generation; the decisions known here now hold, any other of before
  /// does not when it comes, its proposal open again.
  DecisionDevice lost() {
    final d = DecisionDevice(
      device: device,
      generation: deciding(me).generation + 1,
      at: DateTime.now(),
      lost: true,
      known: {
        for (final x in db.decisions)
          if (x.owner == me && !x.void_) x.proposal,
      },
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
      for (final j in theirs['oneriler'] as List? ?? const []) {
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
      for (final j in theirs['kararlar'] as List? ?? const []) {
        final d = ProposalDecision.fromJson(j);
        if (d == null || d.owner != from) continue;
        final p = db.proposal(d.proposal);
        if (p == null || p.by != me || p.owner != from) continue;
        final had = db.decisionOf(d.proposal);
        if (had != null &&
            Hlc.canonical(had.toJson()) == Hlc.canonical(d.toJson())) {
          continue;
        }
        if (had == null || had.void_ || d.void_) {
          db.deleteDecision(d.proposal);
          db.putDecision(d);
          changed = true;
        }
      }
    });
    return changed;
  }

  /// What this person's other devices take: the proposals, the decisions
  /// with what they changed, and the device for deciding.
  Map<String, Object?> ownExport() => {
    'oneriler': [for (final p in db.proposals()) p.toJson()],
    'kararlar': [for (final d in db.decisions) d.toJson()],
    'kararCihazi': ?db.decisionDevice(me)?.toJson(),
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
          // Decisions known here of a generation now given up, that the
          // new choice did not know: they do not hold.
          for (final d in db.decisions) {
            if (d.owner == me && !d.void_ && !takeOwnHolds(d)) {
              if (takeOwn(d)) changed = true;
            }
          }
        }
      }
      for (final j in theirs['oneriler'] as List? ?? const []) {
        final p = Proposal.fromJson(j);
        if (p != null && db.putProposal(p)) changed = true;
      }
      for (final j in theirs['kararlar'] as List? ?? const []) {
        final d = ProposalDecision.fromJson(j);
        if (d == null) continue;
        final had = db.decisionOf(d.proposal);
        if (had != null &&
            Hlc.canonical(had.toJson()) == Hlc.canonical(d.toJson())) {
          continue;
        }
        if (d.owner == me) {
          if (had != null && !had.void_ && !d.void_) continue;
          if (d.void_) {
            db.deleteDecision(d.proposal);
            db.putDecision(d);
            changed = true;
          } else if (takeOwn(d)) {
            changed = true;
          }
        } else if (had == null || had.void_ || d.void_) {
          db.deleteDecision(d.proposal);
          db.putDecision(d);
          changed = true;
        }
      }
    });
    return changed;
  }

  /// Whether [d] holds by the device for deciding as chosen now.
  bool takeOwnHolds(ProposalDecision d) {
    final choice = deciding(me);
    return d.generation >= choice.generation ||
        choice.known.contains(d.proposal);
  }
}

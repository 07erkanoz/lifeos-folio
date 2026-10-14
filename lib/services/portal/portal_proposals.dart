part of 'portal_database.dart';

/// What a colleague proposes of another's record, and the owner's word on
/// it (docs/senkron-plan.md R6, §3 decision 2): a proposal never changes
/// once made; its decision is another record, made on the owner's one
/// device for deciding, carrying what it changed.
extension PortalProposals on PortalDatabase {
  static const _tables = '''
    CREATE TABLE IF NOT EXISTS proposal (
      id TEXT PRIMARY KEY, sahip TEXT NOT NULL, oneren TEXT NOT NULL,
      json TEXT NOT NULL, at TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS proposal_sahip ON proposal(sahip);
    CREATE TABLE IF NOT EXISTS proposal_decision (
      oneri TEXT PRIMARY KEY, sahip TEXT NOT NULL, json TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS decision_device (
      sahip TEXT PRIMARY KEY, json TEXT NOT NULL);
  ''';

  /// [p] kept as it came, once: a proposal is never changed. False when it
  /// was here already.
  bool putProposal(Proposal p) {
    final had = _db.select('SELECT 1 FROM proposal WHERE id=?', [p.id]);
    if (had.isNotEmpty) return false;
    _db.execute(
      'INSERT INTO proposal(id, sahip, oneren, json, at) VALUES(?,?,?,?,?)',
      [p.id, p.owner, p.by, jsonEncode(p.toJson()), p.at.toIso8601String()],
    );
    return true;
  }

  Proposal? proposal(String id) {
    final r = _db.select('SELECT json FROM proposal WHERE id=?', [id]);
    return r.isEmpty
        ? null
        : Proposal.fromJson(PortalAgendaVersions._map(r.first['json']));
  }

  /// The proposals made to [owner], or by [by]; the newest first.
  List<Proposal> proposals({String? owner, String? by}) => [
    for (final r in _db.select(
      'SELECT json FROM proposal'
      '${owner != null
          ? ' WHERE sahip=?'
          : by != null
          ? ' WHERE oneren=?'
          : ''}'
      ' ORDER BY at DESC',
      [?owner, if (owner == null) ?by],
    ))
      ?Proposal.fromJson(PortalAgendaVersions._map(r['json'])),
  ];

  /// [d] kept: one decision a proposal, the first that holds. False when
  /// one was here already.
  bool putDecision(ProposalDecision d) {
    final had = decisionOf(d.proposal);
    if (had != null && !had.void_) return false;
    _db.execute(
      'INSERT OR REPLACE INTO proposal_decision(oneri, sahip, json) '
      'VALUES(?,?,?)',
      [d.proposal, d.owner, jsonEncode(d.toJson())],
    );
    return true;
  }

  void deleteDecision(String proposal) =>
      _db.execute('DELETE FROM proposal_decision WHERE oneri=?', [proposal]);

  ProposalDecision? decisionOf(String proposal) {
    final r = _db.select('SELECT json FROM proposal_decision WHERE oneri=?', [
      proposal,
    ]);
    return r.isEmpty
        ? null
        : ProposalDecision.fromJson(PortalAgendaVersions._map(r.first['json']));
  }

  List<ProposalDecision> get decisions => [
    for (final r in _db.select('SELECT json FROM proposal_decision'))
      ?ProposalDecision.fromJson(PortalAgendaVersions._map(r['json'])),
  ];

  /// [owner]'s one device for deciding on proposals, as chosen last; null
  /// while none was (their first device is then).
  DecisionDevice? decisionDevice(String owner) {
    final r = _db.select('SELECT json FROM decision_device WHERE sahip=?', [
      owner,
    ]);
    return r.isEmpty
        ? null
        : DecisionDevice.fromJson(PortalAgendaVersions._map(r.first['json']));
  }

  /// [d] kept when it is a later choice than the one here. True when it
  /// was.
  bool putDecisionDevice(String owner, DecisionDevice d) {
    final kept = decisionDevice(owner);
    if (kept != null && kept.generation >= d.generation) return false;
    _db.execute(
      'INSERT OR REPLACE INTO decision_device(sahip, json) VALUES(?,?)',
      [owner, jsonEncode(d.toJson())],
    );
    return true;
  }
}

/// What a colleague ([by]) proposes of [owner]'s record: its fields as they
/// would be, or that it be taken off; never changed once made (R6).
class Proposal {
  const Proposal({
    required this.id,
    required this.owner,
    required this.by,
    required this.byName,
    required this.kind,
    required this.target,
    required this.seen,
    required this.fields,
    required this.at,
    this.caseKey = '',
    this.remove = false,
    this.reason = '',
  });

  final String id, owner, by, byName;

  /// What it is of: `icra` (an enforcement payment), `kartNotu` (a
  /// card's note), `dosyaNotu` (a case's note on a card).
  final String kind;

  /// The record or card it is of.
  final String target;

  /// For a case's note: the case.
  final String caseKey;

  /// The versions of the record's groups it was made seeing: one changed
  /// since makes it old.
  final Map<String, String> seen;

  /// The fields as they would be.
  final Map<String, Object?> fields;
  final bool remove;
  final String reason;
  final DateTime at;

  /// Whether it is of money (R11): only between two who may see it.
  bool get financial => kind == 'icra';

  Map<String, Object?> toJson() => {
    'id': id,
    'sahip': owner,
    'oneren': by,
    'onerenAd': byName,
    'tur': kind,
    'hedef': target,
    if (caseKey.isNotEmpty) 'dosya': caseKey,
    'gorulen': seen,
    'alanlar': fields,
    if (remove) 'sil': true,
    if (reason.isNotEmpty) 'neden': reason,
    'zaman': at.toIso8601String(),
  };

  static Proposal? fromJson(Object? j) {
    if (j is! Map ||
        j['id'] is! String ||
        j['sahip'] is! String ||
        j['oneren'] is! String ||
        j['tur'] is! String ||
        j['hedef'] is! String) {
      return null;
    }
    final at = DateTime.tryParse('${j['zaman']}');
    if (at == null) return null;
    return Proposal(
      id: j['id'] as String,
      owner: j['sahip'] as String,
      by: j['oneren'] as String,
      byName: '${j['onerenAd'] ?? ''}',
      kind: j['tur'] as String,
      target: j['hedef'] as String,
      caseKey: '${j['dosya'] ?? ''}',
      seen: {
        if (j['gorulen'] is Map)
          for (final e in (j['gorulen'] as Map).entries)
            '${e.key}': '${e.value}',
      },
      fields: {
        if (j['alanlar'] is Map)
          for (final e in (j['alanlar'] as Map).entries) '${e.key}': e.value,
      },
      remove: j['sil'] == true,
      reason: '${j['neden'] ?? ''}',
      at: at,
    );
  }
}

/// The owner's word on a proposal: taken or not, made on their device for
/// deciding of its [generation]; what it changed ([outputs]: each group of
/// the record, before and after, with their versions), for it to be undone
/// should the decision not hold.
class ProposalDecision {
  const ProposalDecision({
    required this.proposal,
    required this.owner,
    required this.approved,
    required this.device,
    required this.generation,
    required this.at,
    this.reason = '',
    this.outputs = const {},
    this.stale = false,
    this.void_ = false,
  });

  final String proposal, owner, device, reason;
  final bool approved;

  /// Not taken: the record changed since it was made.
  final bool stale;
  final int generation;
  final DateTime at;
  final Map<String, Object?> outputs;

  /// Found not to hold (its device's generation given up before it came):
  /// the proposal open again.
  final bool void_;

  ProposalDecision voided() => ProposalDecision(
    proposal: proposal,
    owner: owner,
    approved: approved,
    device: device,
    generation: generation,
    at: at,
    reason: reason,
    outputs: outputs,
    stale: stale,
    void_: true,
  );

  Map<String, Object?> toJson() => {
    'oneri': proposal,
    'sahip': owner,
    'karar': approved ? 'onay' : 'red',
    'cihaz': device,
    'nesil': generation,
    'zaman': at.toIso8601String(),
    if (reason.isNotEmpty) 'neden': reason,
    if (outputs.isNotEmpty) 'ciktilar': outputs,
    if (stale) 'eski': true,
    if (void_) 'gecersiz': true,
  };

  static ProposalDecision? fromJson(Object? j) {
    if (j is! Map ||
        j['oneri'] is! String ||
        j['sahip'] is! String ||
        j['cihaz'] is! String) {
      return null;
    }
    final at = DateTime.tryParse('${j['zaman']}');
    if (at == null) return null;
    return ProposalDecision(
      proposal: j['oneri'] as String,
      owner: j['sahip'] as String,
      approved: j['karar'] == 'onay',
      device: j['cihaz'] as String,
      generation: j['nesil'] is int ? j['nesil'] as int : 0,
      at: at,
      reason: '${j['neden'] ?? ''}',
      outputs: {
        if (j['ciktilar'] is Map)
          for (final e in (j['ciktilar'] as Map).entries) '${e.key}': e.value,
      },
      stale: j['eski'] == true,
      void_: j['gecersiz'] == true,
    );
  }
}

/// The one device of a person's on which proposals are decided (R6), by
/// its [generation]: given over from it, or chosen anew when it was lost,
/// each a later generation. A decision of an earlier generation that was
/// not [known] when this was chosen does not hold.
class DecisionDevice {
  const DecisionDevice({
    required this.device,
    required this.generation,
    required this.at,
    this.lost = false,
    this.known = const {},
  });

  final String device;
  final int generation;
  final DateTime at;

  /// Chosen anew, the one before lost.
  final bool lost;

  /// The decisions known when it was chosen anew: those of before that
  /// hold.
  final Set<String> known;

  Map<String, Object?> toJson() => {
    'cihaz': device,
    'nesil': generation,
    'zaman': at.toIso8601String(),
    if (lost) 'kayip': true,
    if (known.isNotEmpty) 'bilinen': (known.toList()..sort()),
  };

  static DecisionDevice? fromJson(Object? j) {
    if (j is! Map || j['cihaz'] is! String || j['nesil'] is! int) return null;
    return DecisionDevice(
      device: j['cihaz'] as String,
      generation: j['nesil'] as int,
      at: DateTime.tryParse('${j['zaman']}') ?? DateTime(2000),
      lost: j['kayip'] == true,
      known: {
        if (j['bilinen'] is List)
          for (final x in j['bilinen'] as List)
            if (x is String) x,
      },
    );
  }
}

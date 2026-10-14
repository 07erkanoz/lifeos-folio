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
    CREATE TABLE IF NOT EXISTS blocked_output (
      kayit TEXT NOT NULL, grup TEXT NOT NULL, surum TEXT NOT NULL,
      PRIMARY KEY(kayit, grup, surum));
  ''';

  /// What a decision that did not hold changed: that version of that
  /// group of [record] ("not", `dosyaNotu:` and its case, a ledger's group) is
  /// never taken from another device (R6).
  void blockOutput(String record, String group, String version) => _db.execute(
    'INSERT OR IGNORE INTO blocked_output(kayit, grup, surum) '
    'VALUES(?,?,?)',
    [record, group, version],
  );

  /// The versions of [record]'s groups not to be taken: group → versions.
  Map<String, Set<String>> blockedOf(String record) {
    final out = <String, Set<String>>{};
    for (final r in _db.select(
      'SELECT grup, surum FROM blocked_output WHERE kayit=?',
      [record],
    )) {
      out.putIfAbsent(r['grup'] as String, () => {}).add(r['surum'] as String);
    }
    return out;
  }

  List<Map<String, Object?>> get blockedOutputs => [
    for (final r in _db.select('SELECT * FROM blocked_output'))
      {for (final c in r.keys) c: r[c]},
  ];

  /// The text of the proposals of [kind] [target] (and [caseKey]) taken
  /// out, its note made secret (R7): their ids and decisions stay. True
  /// when one was.
  bool scrubProposals(
    String kind,
    String target, {
    String caseKey = '',
    Hlc? upTo,
  }) {
    var changed = false;
    for (final r in _db.select('SELECT id, json FROM proposal')) {
      final j = PortalAgendaVersions._map(r['json']);
      if (j == null ||
          j['tur'] != kind ||
          j['hedef'] != target ||
          '${j['dosya'] ?? ''}' != caseKey) {
        continue;
      }
      // Only one made seeing a version taken back: not one of after it,
      // its note made open again.
      final seen = j['gorulen'] is Map ? j['gorulen'] as Map : const {};
      final saw = Hlc.tryParse(seen[kind == 'icra' ? 'bilgi' : 'not']);
      if (upTo != null && saw != null && saw > upTo) continue;
      final fields = Map<String, Object?>.from(j['alanlar'] as Map? ?? {});
      var scrubbed = false;
      for (final f in const ['metin', 'aciklama']) {
        if ('${fields[f] ?? ''}'.isNotEmpty) {
          fields[f] = '';
          scrubbed = true;
        }
      }
      if (!scrubbed) continue;
      // Its text gone, it is never taken: it would write the note empty.
      _db.execute('UPDATE proposal SET json=? WHERE id=?', [
        jsonEncode({...j, 'alanlar': fields, 'temizlendi': true}),
        r['id'],
      ]);
      changed = true;
    }
    return changed;
  }

  /// A note's key ("kartNotu:", "dosyaNotu:", "aciklama:") as what its
  /// proposals are of; null for another.
  static ({String kind, String target, String caseKey})? proposalOfNote(
    String key,
  ) {
    final parts = key.split(':');
    if (parts.length < 2) return null;
    return switch (parts.first) {
      'kartNotu' => (kind: 'kartNotu', target: parts[1], caseKey: ''),
      'dosyaNotu' when parts.length >= 3 => (
        kind: 'dosyaNotu',
        target: parts[1],
        caseKey: parts.sublist(2).join(':'),
      ),
      'aciklama' => (kind: 'icra', target: parts[1], caseKey: ''),
      _ => null,
    };
  }

  /// [p] kept as it came, once: a proposal is never changed. False when it
  /// was here already.
  bool putProposal(Proposal p) {
    final had = _db.select('SELECT 1 FROM proposal WHERE id=?', [p.id]);
    if (had.isNotEmpty) return false;
    _db.execute(
      'INSERT INTO proposal(id, sahip, oneren, json, at) VALUES(?,?,?,?,?)',
      [p.id, p.owner, p.by, jsonEncode(p.toJson()), p.at.toIso8601String()],
    );
    // Of a note made secret since: its text not kept (R7).
    final key = switch (p.kind) {
      'kartNotu' => 'kartNotu:${p.target}',
      'dosyaNotu' => 'dosyaNotu:${p.target}:${p.caseKey}',
      _ => 'aciklama:${p.target}',
    };
    final hide = [
      ?hideOf(key),
      ?takenNoteHide(p.owner, key),
    ].fold<Hlc?>(null, (a, b) => a == null || b > a ? b : a);
    if (hide != null) {
      scrubProposals(p.kind, p.target, caseKey: p.caseKey, upTo: hide);
    }
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
    if (had != null && !d.supersedes(had)) return false;
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
    // Each generation's device: of two chosen at once, the same one on
    // every device, by the device's id.
    final winners = <int, String>{...?kept?.allWinners};
    for (final e in d.allWinners.entries) {
      final w = winners[e.key];
      if (w == null || e.value.compareTo(w) > 0) winners[e.key] = e.value;
    }
    // The later generation's choice, with every generation's device.
    final top =
        kept == null ||
            d.generation > kept.generation ||
            (d.generation == kept.generation &&
                d.device.compareTo(kept.device) > 0)
        ? d
        : kept;
    final next = DecisionDevice(
      device: top.device,
      generation: top.generation,
      at: top.at,
      lost: top.lost,
      lostAt: [d.lostAt, ?kept?.lostAt].reduce((a, b) => a > b ? a : b),
      known: {...d.known, ...?kept?.known},
      winners: winners,
    );
    if (kept != null &&
        Hlc.canonical(kept.toJson()) == Hlc.canonical(next.toJson())) {
      return false;
    }
    d = next;
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
    this.scrubbed = false,
  });

  final String id, owner, by, byName;

  /// Its text taken out, its note made secret since (R7): never taken.
  final bool scrubbed;

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
    if (scrubbed) 'temizlendi': true,
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
      scrubbed: j['temizlendi'] == true,
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
    this.conflict = false,
  });

  final String proposal, owner, device, reason;

  /// Not holding, and what it changed changed again since: left as it is,
  /// for the owner to look at.
  final bool conflict;

  /// Whether this one stands over [other], of the same proposal: the same
  /// decision found not to hold, or a later decision (by its device's
  /// generation, then when, then the device); never an older one marked
  /// not holding over a newer one.
  bool supersedes(ProposalDecision other) {
    final same =
        device == other.device &&
        generation == other.generation &&
        at == other.at;
    if (same) {
      return (void_ && !other.void_) || (conflict && !other.conflict);
    }
    if (generation != other.generation) return generation > other.generation;
    if (at != other.at) return at.isAfter(other.at);
    return device.compareTo(other.device) > 0;
  }

  final bool approved;

  /// Not taken: the record changed since it was made.
  final bool stale;
  final int generation;
  final DateTime at;
  final Map<String, Object?> outputs;

  /// Found not to hold (its device's generation given up before it came):
  /// the proposal open again.
  final bool void_;

  ProposalDecision voided({bool conflict = false}) => ProposalDecision(
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
    conflict: conflict,
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
    if (conflict) 'catisma': true,
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
      conflict: j['catisma'] == true,
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
    this.lostAt = 0,
    this.winners = const {},
  });

  final String device;

  /// The device chosen for each generation of before, and this one's: a
  /// decision of a generation by another device does not hold.
  final Map<int, String> winners;

  /// [winners] with this choice in it.
  Map<int, String> get allWinners => {...winners, generation: device};

  /// The generation of the last choice made of a device lost: decisions of
  /// before it hold only when [known] then.
  final int lostAt;
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
    if (lostAt > 0) 'kayipNesil': lostAt,
    if (known.isNotEmpty) 'bilinen': (known.toList()..sort()),
    'kazananlar': {
      for (final e in allWinners.entries) '${e.key}': e.value,
    },
  };

  /// Whether [d] holds by this choice: made by the device chosen for its
  /// generation, and not of before a device lost unless known then.
  bool holds(ProposalDecision d) {
    final winner = allWinners[d.generation];
    if (winner != null && winner != d.device) return false;
    return d.generation >= lostAt || known.contains(d.proposal);
  }

  static DecisionDevice? fromJson(Object? j) {
    if (j is! Map || j['cihaz'] is! String || j['nesil'] is! int) return null;
    return DecisionDevice(
      device: j['cihaz'] as String,
      generation: j['nesil'] as int,
      at: DateTime.tryParse('${j['zaman']}') ?? DateTime(2000),
      lost: j['kayip'] == true,
      lostAt: j['kayipNesil'] is int ? j['kayipNesil'] as int : 0,
      winners: {
        if (j['kazananlar'] is Map)
          for (final e in (j['kazananlar'] as Map).entries)
            if (int.tryParse('${e.key}') case final g? when e.value is String)
              g: e.value as String,
      },
      known: {
        if (j['bilinen'] is List)
          for (final x in j['bilinen'] as List)
            if (x is String) x,
      },
    );
  }
}

import '../clients/client.dart';
import '../clients/client_accounts.dart';
import '../sync/hlc.dart';

/// A set-off of a payment made outside, kept in the payment's own record
/// (docs/senkron-plan.md R3): taken as the lawyer's fee or the counter fee,
/// whole or in part. It belongs to the record, not to a version of it: a
/// sum changed, it is the same set-off.
class LedgerSetOff {
  const LedgerSetOff({
    required this.id,
    required this.target,
    required this.amount,
    required this.at,
    required this.version,
    this.removed = false,
  });

  final String id;
  final MovementKind target;

  /// Kuruş.
  final int amount;
  final DateTime at;
  final bool removed;
  final Hlc version;

  Map<String, Object?> toJson() => {
    'id': id,
    'hedef': target.code,
    'tutar': amount,
    'zaman': at.toIso8601String(),
    'silindi': removed,
    'surum': '$version',
  };

  /// Its value, for choosing between two of the same version.
  Map<String, Object?> get value => {...toJson()}..remove('surum');

  static LedgerSetOff? fromJson(Object? j, {required Hlc fallback}) {
    if (j is! Map || j['id'] is! String) return null;
    final target = MovementKind.of(j['hedef']);
    final at = DateTime.tryParse('${j['zaman']}');
    if (target == null || !target.isApplied || at == null) return null;
    return LedgerSetOff(
      id: j['id'] as String,
      target: target,
      amount: j['tutar'] is int ? j['tutar'] as int : 0,
      at: at,
      removed: j['silindi'] == true,
      version: Hlc.tryParse(j['surum']) ?? fallback,
    );
  }

  LedgerSetOff copyWith({
    int? amount,
    MovementKind? target,
    DateTime? at,
    bool? removed,
    required Hlc version,
  }) => LedgerSetOff(
    id: id,
    target: target ?? this.target,
    amount: amount ?? this.amount,
    at: at ?? this.at,
    removed: removed ?? this.removed,
    version: version,
  );
}

/// What a payment made outside does to the money now, worked out from its
/// record alone, the same on every device: what is held for the client,
/// and of its set-offs which are in effect and which wait (R3's state).
class LedgerState {
  const LedgerState({
    required this.held,
    required this.active,
    required this.waiting,
  });

  /// Kuruş held for the client: the sum, or nothing when taken off.
  final int held;

  /// The set-offs in effect, in their order.
  final List<LedgerSetOff> active;

  /// Those past what is held: kept, in no account, till they fit.
  final List<LedgerSetOff> waiting;
}

/// An enforcement file's own account line (`ClientRecordKind.enforcement`)
/// kept alike field group by field group, its money worked out from it
/// (docs/senkron-plan.md R1, R3, R5). Its movements in the client's
/// account and in Kasa are a projection of it: made on each device from
/// the record, never sent, never changed by hand.
abstract final class LedgerBook {
  /// The record's fields, by the group each is changed with.
  static const groups = <String, List<String>>{
    // What the money is: changed together, chosen together.
    'finans': [
      'dosya',
      'tur',
      'tutar',
      'zaman',
      'odeme',
      'tamami',
      'uyapBakiye',
    ],
    'bilgi': ['borclu', 'aciklama'],
    'bildirildi': ['bildirildi'],
    'resmiKarar': ['resmiKarar', 'resmi'],
  };

  /// The group of whether the record stands or was taken off.
  static const lifecycle = 'yasam';

  static const _versions = 'surumler';
  static const _setOffs = 'mahsuplar';

  /// [r]'s version of [group]: as kept, else made of its last change, the
  /// same on every device (R2.1).
  static Hlc versionOf(ClientRecord r, String group) {
    final kept = r.data[_versions];
    return Hlc.tryParse(kept is Map ? kept[group] : null) ??
        Hlc.fromLegacy(r.updated.toIso8601String());
  }

  static Map<String, Hlc> versionsOf(ClientRecord r) => {
    for (final g in [...groups.keys, lifecycle]) g: versionOf(r, g),
  };

  /// [group]'s value in [r], for choosing between two of the same version.
  static Object? valueOf(ClientRecord r, String group) => group == lifecycle
      ? r.removed
      : {
          for (final f in groups[group]!) f: r.data[f],
          if (group == 'finans') 'muvekkil': r.clientId,
        };

  static List<LedgerSetOff> setOffsOf(ClientRecord r) => [
    for (final j in (r.data[_setOffs] as List? ?? const []))
      ?LedgerSetOff.fromJson(
        j,
        fallback: Hlc.fromLegacy(r.updated.toIso8601String()),
      ),
  ];

  /// [r] with [versions] and [setOffs] written in.
  static ClientRecord write(
    ClientRecord r, {
    required Map<String, Hlc> versions,
    required List<LedgerSetOff> setOffs,
    Map<String, Object?>? data,
    String? clientId,
    bool? removed,
    DateTime? updated,
  }) => ClientRecord(
    id: r.id,
    clientId: clientId ?? r.clientId,
    kind: r.kind,
    data: {
      ...(data ?? r.data),
      _versions: {for (final e in versions.entries) e.key: '${e.value}'},
      _setOffs: [for (final s in setOffs) s.toJson()],
    },
    created: r.created,
    by: r.by,
    updated: updated ?? r.updated,
    locked: r.locked,
    removed: removed ?? r.removed,
    person: r.person,
  );

  /// [mine] and [theirs], two copies of one record, made one: each group
  /// as the later of the two changed it, each set-off likewise; for the
  /// same version, the same value chosen on every device (R1, R2).
  static ClientRecord merge(ClientRecord mine, ClientRecord theirs) {
    final versions = <String, Hlc>{};
    final data = <String, Object?>{...mine.data};
    var clientId = mine.clientId;
    var removed = mine.removed;
    for (final g in [...groups.keys, lifecycle]) {
      final a = versionOf(mine, g), b = versionOf(theirs, g);
      final theirsWins =
          Hlc.decide(b, valueOf(theirs, g), a, valueOf(mine, g)) > 0;
      versions[g] = theirsWins ? b : a;
      if (!theirsWins) continue;
      if (g == lifecycle) {
        removed = theirs.removed;
        continue;
      }
      for (final f in groups[g]!) {
        if (theirs.data.containsKey(f)) {
          data[f] = theirs.data[f];
        } else {
          data.remove(f);
        }
      }
      if (g == 'finans') clientId = theirs.clientId;
    }
    final byId = {for (final s in setOffsOf(mine)) s.id: s};
    for (final s in setOffsOf(theirs)) {
      final kept = byId[s.id];
      if (kept == null ||
          Hlc.decide(s.version, s.value, kept.version, kept.value) > 0) {
        byId[s.id] = s;
      }
    }
    final setOffs = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return write(
      mine,
      versions: versions,
      setOffs: setOffs,
      data: data,
      clientId: clientId,
      removed: removed,
      updated: theirs.updated.isAfter(mine.updated)
          ? theirs.updated
          : mine.updated,
    );
  }

  /// What [r] says, all of it but when it was last written: two copies
  /// that say the same give the same text (R12's check).
  static String contentOf(ClientRecord r) => Hlc.canonical({
    'veri': r.data,
    'muvekkil': r.clientId,
    'silindi': r.removed,
  });

  /// A short mark of [contentOf], carried by [r]'s movements: what a
  /// change made from one of them was made seeing.
  static String tokenOf(ClientRecord r) => Hlc.digest(contentOf(r));

  /// Whether the lawyer's word that UYAP has [r] stands: given for the sum
  /// and day it has now (R4). A word given by an older Folio, with no
  /// version of its own, stands till they change.
  static bool officialByHand(ClientRecord r) {
    final word = r.text('resmiKarar') == 'elle' || r.text('resmi') == 'elle';
    if (!word) return false;
    final given = r.text('resmiKararSurum');
    return given.isEmpty || given == '${versionOf(r, 'finans')}';
  }

  /// Whether [r] is in the form this Folio writes, with its groups'
  /// versions: an older Folio's has its movements still of its own.
  static bool isNewForm(ClientRecord r) => r.data[_versions] is Map;

  /// Whether [r] puts money in a client's account: a payment made outside,
  /// standing, of a client's (not the office's own cash).
  static bool books(ClientRecord r) =>
      !r.removed &&
      r.kind == ClientRecordKind.enforcement &&
      r.data['tur'] == 'haricen' &&
      r.clientId != officeCashId;

  /// [r]'s money now (R3): held is the sum while it stands; its set-offs
  /// standing, in the order of their versions, are in effect while what
  /// they take is within what is held, and wait past it, till they fit.
  static LedgerState stateOf(ClientRecord r) {
    final held = books(r) && r.amount > 0 ? r.amount : 0;
    final standing =
        [
          for (final s in setOffsOf(r))
            if (!s.removed && s.amount > 0) s,
        ]..sort((a, b) {
          final byVersion = a.version.compareTo(b.version);
          return byVersion != 0 ? byVersion : a.id.compareTo(b.id);
        });
    final active = <LedgerSetOff>[], waiting = <LedgerSetOff>[];
    var taken = 0;
    for (final s in standing) {
      if (taken + s.amount <= held) {
        active.add(s);
        taken += s.amount;
      } else {
        waiting.add(s);
      }
    }
    return LedgerState(held: held, active: active, waiting: waiting);
  }

  /// The id of [r]'s money held in the client's account.
  static String heldIdOf(String entryId) => 'icra:$entryId:emanet';

  /// Whether [r] is a movement made of a ledger record: never sent, never
  /// changed by hand.
  static bool isProjected(ClientRecord r) => r.data['turetilmis'] == true;

  /// [r]'s movements in the client's account and Kasa, made of its state:
  /// what is held, and each set-off in effect. The same on every device.
  static List<ClientRecord> projectionOf(ClientRecord r) {
    final state = stateOf(r);
    if (state.held == 0) return const [];
    final heldId = heldIdOf(r.id);
    final debtor = r.text('borclu');
    ClientRecord movement(String id, Map<String, Object?> data) => ClientRecord(
      id: id,
      clientId: r.clientId,
      kind: ClientRecordKind.movement,
      data: {
        'dosya': r.text('dosya'),
        ...data,
        'turetilmis': true,
        // What the record said when this was made of it.
        'defterSurum': tokenOf(r),
      },
      created: r.created,
      by: r.by,
      updated: r.updated,
      locked: true,
      person: r.person,
    );
    return [
      movement(heldId, {
        'hesap': MovementKind.collected.code,
        'tutar': state.held,
        'zaman': r.at.toIso8601String(),
        'aciklama': [
          'Haricen tahsilat',
          if (debtor.isNotEmpty) debtor,
        ].join(' · '),
        'odeme': r.text('odeme'),
        'kaynak': 'icra:${r.id}',
      }),
      for (final s in state.active)
        movement('icra:${r.id}:mahsup:${s.id}', {
          'hesap': s.target.code,
          'tutar': s.amount,
          'zaman': s.at.toIso8601String(),
          'aciklama': MovementKind.collected.label,
          'odeme': 'Mahsup',
          'kaynak': 'mahsup:$heldId',
        }),
    ];
  }
}

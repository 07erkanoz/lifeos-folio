import 'dart:convert';
import 'dart:math';

import '../sync/hlc.dart';
import '../uyap/uyap_web_service.dart';

/// A client of the lawyer's: a person or a body, by the names the cases
/// write it with (docs/design/muvekkil-taslak). Made by the lawyer, or
/// first seen as the party they act for in a case.
class Client {
  const Client({
    required this.id,
    required this.name,
    this.body = false,
    this.idNo = '',
    this.phone = '',
    this.phone2 = '',
    this.email = '',
    this.address = '',
    this.note = '',
    this.noteSecret = false,
    this.messages = false,
    this.names = const [],
    required this.updated,
    this.removed = false,
    this.office = false,
    this.sharedOnce = false,
    this.person = '',
    this.absorbed = const [],
    this.stamps = const {},
    this.versions = const {},
    this.caseLinks = const {},
    this.caseNotes = const {},
    this.group = '',
    this.hidden = false,
    this.base,
  });

  /// The card as it was read, that this one was changed from ([copyWith]):
  /// what the lawyer changed is told apart from what came from another
  /// device since ([written]). Never kept.
  final Client? base;

  /// The lawyer's own group for the client ("Bankalar", "Sigorta"), by
  /// which the list is narrowed; empty for none.
  final String group;

  /// Kept, but not listed unless asked for: a client of once.
  final bool hidden;

  /// The lawyer's note on each of the client's cases, by case key.
  final Map<String, CaseNote> caseNotes;

  /// When each of [fields] was last set: two devices that changed
  /// different fields of a card keep both ([merge]). One not stamped was
  /// set when the card was ([updated]).
  final Map<String, DateTime> stamps;

  /// Each of [fields]' version (docs/senkron-plan.md R1, R2), written by
  /// [written]: one not yet versioned has its [stamps]' made of it, the
  /// same on every device (R2.1).
  final Map<String, Hlc> versions;

  /// The cases the lawyer tied to the client by hand, or took off it, by
  /// case key: these overrule what the names in the cases say.
  final Map<String, CaseLink> caseLinks;

  /// The card's fields that are set one by one, by their names in JSON.
  static const fields = [
    'ad',
    'kurum',
    'kimlik',
    'telefon',
    'telefon2',
    'eposta',
    'adres',
    'not',
    'silindi',
    'buro',
    'mesajIzni',
    'grup',
    'gizli',
  ];

  /// The cards told to be this client's too: their records are its.
  final List<String> absorbed;

  final String id, name;

  /// Shared with the office (KVKK: a client at a time, by the lawyer's
  /// choice): its card and records go to the office's members.
  final bool office;

  /// Shared before: its card still goes, unshared, for the members to
  /// forget what they were given of it.
  final bool sharedOnce;

  /// The office person who made the card; empty where there is no office.
  final String person;

  /// A company or an office, not a person.
  final bool body;

  /// TCKN for a person, VKN for a body; empty while not told.
  final String idNo;
  final String phone, phone2, email, address, note;

  /// [note] a secret note (docs/senkron-plan.md R7): on the lawyer's own
  /// devices only, never sent to the office. Versioned with [note], as one.
  final bool noteSecret;

  /// Wishes to be told by message (WhatsApp, SMS, e-mail) of their
  /// hearings and instalments: the day's list asks for them only then.
  final bool messages;

  /// The other names its cases write it with, folded: "AYŞE KARACA" and
  /// "Ayşe Karaca" are one client, a name told to be the same is too.
  final List<String> names;
  final DateTime updated;

  /// Taken off by the lawyer; kept so that their other devices hear of it.
  final bool removed;

  /// Every name it is found by, folded.
  Set<String> get folded => {UyapWebService.fold(name), ...names};

  static String newId() {
    final r = Random.secure();
    return 'm${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '${r.nextInt(1 << 32).toRadixString(36)}';
  }

  Client copyWith({
    String? name,
    bool? body,
    String? idNo,
    String? phone,
    String? phone2,
    String? email,
    String? address,
    String? note,
    bool? noteSecret,
    bool? messages,
    List<String>? names,
    DateTime? updated,
    bool? removed,
    bool? office,
    List<String>? absorbed,
    Map<String, CaseLink>? caseLinks,
    Map<String, CaseNote>? caseNotes,
    String? group,
    bool? hidden,
  }) {
    final now = updated ?? DateTime.now();
    final made = Client(
      id: id,
      name: name ?? this.name,
      body: body ?? this.body,
      idNo: idNo ?? this.idNo,
      phone: phone ?? this.phone,
      phone2: phone2 ?? this.phone2,
      email: email ?? this.email,
      address: address ?? this.address,
      note: note ?? this.note,
      noteSecret: noteSecret ?? this.noteSecret,
      messages: messages ?? this.messages,
      names: names ?? this.names,
      updated: now,
      removed: removed ?? this.removed,
      office: office ?? this.office,
      sharedOnce: sharedOnce || (office ?? this.office),
      person: person,
      absorbed: absorbed ?? this.absorbed,
      versions: versions,
      caseLinks: caseLinks ?? this.caseLinks,
      caseNotes: caseNotes ?? this.caseNotes,
      group: group ?? this.group,
      hidden: hidden ?? this.hidden,
      base: base ?? this,
    );
    // Only what changed is stamped now; the rest keeps the time it had.
    final was = _values, is_ = made._values;
    return made._stamped({
      for (final k in fields) k: was[k] == is_[k] ? stampOf(k) : now,
    });
  }

  Client _stamped(Map<String, DateTime> stamps) => Client(
    id: id,
    name: name,
    body: body,
    idNo: idNo,
    phone: phone,
    phone2: phone2,
    email: email,
    address: address,
    note: note,
    noteSecret: noteSecret,
    messages: messages,
    names: names,
    updated: updated,
    removed: removed,
    office: office,
    sharedOnce: sharedOnce,
    person: person,
    absorbed: absorbed,
    stamps: stamps,
    versions: versions,
    caseLinks: caseLinks,
    caseNotes: caseNotes,
    group: group,
    hidden: hidden,
    base: base,
  );

  /// When field [k] was last set.
  DateTime stampOf(String k) => stamps[k] ?? updated;

  /// Field [k]'s version: as written, else made of when it was last set.
  Hlc versionOf(String k) =>
      versions[k] ?? Hlc.fromLegacy(stampOf(k).toIso8601String());

  /// Every version the card was written with, its cases' and notes' too.
  /// Those made of when each was set among them (R2.1): seen before one
  /// is written after them.
  Iterable<Hlc> get allVersions => [
    for (final k in fields) versionOf(k),
    for (final l in caseLinks.values) l.versionOf,
    for (final n in caseNotes.values) n.versionOf,
  ];

  /// This card as the lawyer wrote it here, [before] the one kept: what
  /// they changed given a new version of [clock], the rest as kept, so
  /// that what came from another device since stands. What they changed is
  /// what differs from [base], the card as it was read; for one made
  /// without it, a field stamped as this card was ([copyWith] stamps what
  /// it changes), a case's note or link written after the one kept. The
  /// names and the cards it took in, as they were changed of [base]. A new
  /// card's versions are this device's, of when each was set.
  Client written(Client? before, HlcClock clock) {
    // What is kept is seen first: this is written after it (R2).
    void seen(Iterable<Hlc> versions) {
      for (final v in versions) {
        if (v.l > 0 && v.compareTo(clock.last) > 0) clock.receive(v);
      }
    }

    if (before == null) {
      Hlc at(DateTime t) =>
          Hlc(t.toUtc().millisecondsSinceEpoch, 0, clock.source);
      final made = _picked(
        _values,
        stamps: {for (final k in fields) k: stampOf(k)},
        versions: {for (final k in fields) k: at(stampOf(k))},
        names: names,
        updated: updated,
        sharedOnce: sharedOnce,
        person: person,
        absorbed: absorbed,
        caseLinks: {
          for (final e in caseLinks.entries)
            e.key: e.value.withVersion(at(e.value.at)),
        },
        caseNotes: {
          for (final e in caseNotes.entries)
            e.key: e.value.withVersion(at(e.value.at)),
        },
      );
      seen(made.allVersions);
      return made;
    }
    seen(before.allVersions);
    final shown = base;
    final now = _values;
    final was = before._values;
    final from = shown?._values;
    final pick = <String, Object>{};
    final stampsNow = <String, DateTime>{};
    final versionsNow = <String, Hlc>{};
    for (final k in fields) {
      final mine = from != null ? now[k] != from[k] : stampOf(k) == updated;
      if (now[k] != was[k] && mine) {
        pick[k] = now[k]!;
        stampsNow[k] = stampOf(k);
        versionsNow[k] = clock.tick();
      } else {
        pick[k] = was[k]!;
        stampsNow[k] = before.stampOf(k);
        versionsNow[k] = before.versionOf(k);
      }
    }
    final links = <String, CaseLink>{...before.caseLinks};
    caseLinks.forEach((k, l) {
      final kept = links[k];
      if (kept != null && kept.sameAs(l)) return;
      final mine = shown != null
          ? !(shown.caseLinks[k]?.sameAs(l) ?? false)
          : kept == null || l.at.isAfter(kept.at);
      if (mine) links[k] = l.withVersion(clock.tick());
    });
    final notes = <String, CaseNote>{...before.caseNotes};
    caseNotes.forEach((k, n) {
      final kept = notes[k];
      if (kept != null && kept.sameAs(n)) return;
      final mine = shown != null
          ? !(shown.caseNotes[k]?.sameAs(n) ?? false)
          : kept == null || n.at.isAfter(kept.at);
      if (mine) notes[k] = n.withVersion(clock.tick());
    });
    // The names and the cards taken in: as kept, with what this one added
    // to or took off of what it was read with.
    List<String> changedOf(
      List<String> kept,
      List<String> read,
      List<String> made,
    ) => shown == null
        ? {...kept, ...made}.toList()
        : ({
            ...kept,
            ...made.where((x) => !read.contains(x)),
          }..removeAll(read.where((x) => !made.contains(x)))).toList();
    return _picked(
      pick,
      stamps: stampsNow,
      versions: versionsNow,
      names: changedOf(before.names, shown?.names ?? const [], names),
      updated: updated,
      sharedOnce: sharedOnce || before.sharedOnce,
      person: before.person.isNotEmpty ? before.person : person,
      absorbed: changedOf(
        before.absorbed,
        shown?.absorbed ?? const [],
        absorbed,
      ),
      caseLinks: links,
      caseNotes: notes,
    );
  }

  Client _picked(
    Map<String, Object> pick, {
    required Map<String, DateTime> stamps,
    required Map<String, Hlc> versions,
    required List<String> names,
    required DateTime updated,
    required bool sharedOnce,
    required String person,
    required List<String> absorbed,
    required Map<String, CaseLink> caseLinks,
    required Map<String, CaseNote> caseNotes,
  }) => Client(
    id: id,
    name: pick['ad']! as String,
    body: pick['kurum']! as bool,
    idNo: pick['kimlik']! as String,
    phone: pick['telefon']! as String,
    phone2: pick['telefon2']! as String,
    email: pick['eposta']! as String,
    address: pick['adres']! as String,
    note: (pick['not']! as (String, bool)).$1,
    noteSecret: (pick['not']! as (String, bool)).$2,
    messages: pick['mesajIzni']! as bool,
    names: names,
    updated: updated,
    removed: pick['silindi']! as bool,
    office: pick['buro']! as bool,
    sharedOnce: sharedOnce,
    person: person,
    absorbed: absorbed,
    stamps: stamps,
    versions: versions,
    caseLinks: caseLinks,
    caseNotes: caseNotes,
    group: pick['grup']! as String,
    hidden: pick['gizli']! as bool,
  );

  static bool _secretOf(Object? v) => v is (String, bool) && v.$2;

  /// [v] as JSON can write it.
  static Object? _plain(Object? v) => v is (String, bool) ? [v.$1, v.$2] : v;

  Map<String, Object> get _values => {
    'ad': name,
    'kurum': body,
    'kimlik': idNo,
    'telefon': phone,
    'telefon2': phone2,
    'eposta': email,
    'adres': address,
    // The note and whether it is secret: one field, one version (R7).
    'not': (note, noteSecret),
    'silindi': removed,
    'buro': office,
    'mesajIzni': messages,
    'grup': group,
    'gizli': hidden,
  };

  /// The mark a colleague's client unshared leaves: nothing of the person.
  bool get _mark => removed && name.isEmpty;

  /// [mine] and [theirs], two words of one card, made one: each field
  /// the one set later, the names and the cases tied both sides'. A
  /// device that changed the phone and another the address keep both.
  /// The same on every device, whichever comes first.
  static Client merge(Client mine, Client theirs) {
    if (mine.id != theirs.id) return theirs;
    // An unshared client's mark is a whole word: nothing of the person
    // comes back with it, nor goes with a newer one.
    if (mine._mark || theirs._mark) {
      return theirs.updated.isAfter(mine.updated) ? theirs : mine;
    }
    final a = mine._values, b = theirs._values;
    final pick = <String, Object>{};
    final stamps = <String, DateTime>{};
    final versions = <String, Hlc>{};
    for (final k in fields) {
      final va = mine.versionOf(k), vb = theirs.versionOf(k);
      // The later version; for the same, the same value on every device,
      // a secret note before an open one (R7).
      final later = k == 'not' && va == vb && _secretOf(a[k]) != _secretOf(b[k])
          ? _secretOf(b[k])
          : Hlc.decide(vb, _plain(b[k]), va, _plain(a[k])) > 0;
      pick[k] = later ? b[k]! : a[k]!;
      stamps[k] = later ? theirs.stampOf(k) : mine.stampOf(k);
      versions[k] = later ? vb : va;
    }
    final links = {...mine.caseLinks};
    theirs.caseLinks.forEach((k, l) {
      final kept = links[k];
      if (kept == null ||
          Hlc.decide(l.versionOf, l.value, kept.versionOf, kept.value) > 0) {
        links[k] = l;
      }
    });
    final notes = {...mine.caseNotes};
    theirs.caseNotes.forEach((k, n) {
      final kept = notes[k];
      if (kept == null ||
          (n.versionOf == kept.versionOf && n.secret != kept.secret
              ? n.secret
              : Hlc.decide(n.versionOf, n.value, kept.versionOf, kept.value) >
                    0)) {
        notes[k] = n;
      }
    });
    return mine._picked(
      pick,
      stamps: stamps,
      versions: versions,
      names: {...mine.names, ...theirs.names}.toList(),
      updated: theirs.updated.isAfter(mine.updated)
          ? theirs.updated
          : mine.updated,
      sharedOnce: mine.sharedOnce || theirs.sharedOnce,
      person: mine.person.isNotEmpty ? mine.person : theirs.person,
      absorbed: {...mine.absorbed, ...theirs.absorbed}.toList(),
      caseLinks: links,
      caseNotes: notes,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'ad': name,
    'kurum': body,
    'kimlik': idNo,
    'telefon': phone,
    'telefon2': phone2,
    'eposta': email,
    'adres': address,
    'not': note,
    if (noteSecret) 'notGizli': true,
    'mesajIzni': messages,
    'adlar': names,
    'guncelleme': updated.toIso8601String(),
    'silindi': removed,
    'buro': office,
    'paylasildi': sharedOnce,
    'kisi': person,
    'katilan': absorbed,
    if (group.isNotEmpty) 'grup': group,
    if (hidden) 'gizli': true,
    'alanZamani': {
      for (final k in fields)
        if (stamps[k] case final t?) k: t.toIso8601String(),
    },
    if (versions.isNotEmpty)
      'alanSurumu': {
        for (final k in fields)
          if (versions[k] case final v?) k: '$v',
      },
    'dosyalar': {
      for (final k in caseLinks.keys.toList()..sort())
        k: caseLinks[k]!.toJson(),
    },
    'dosyaNotlari': {
      for (final k in caseNotes.keys.toList()..sort())
        k: caseNotes[k]!.toJson(),
    },
  };

  static Client? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || j['ad'] is! String) return null;
    String s(String k) => j[k] is String ? j[k] as String : '';
    return Client(
      id: j['id'] as String,
      name: j['ad'] as String,
      body: j['kurum'] == true,
      idNo: s('kimlik'),
      phone: s('telefon'),
      phone2: s('telefon2'),
      email: s('eposta'),
      address: s('adres'),
      note: s('not'),
      noteSecret: j['notGizli'] == true,
      messages: j['mesajIzni'] == true,
      names: [
        for (final n in j['adlar'] is List ? j['adlar'] as List : const [])
          if (n is String) n,
      ],
      updated: DateTime.tryParse(s('guncelleme')) ?? DateTime(2000),
      removed: j['silindi'] == true,
      office: j['buro'] == true,
      sharedOnce: j['paylasildi'] == true || j['buro'] == true,
      person: s('kisi'),
      group: s('grup').trim(),
      hidden: j['gizli'] == true,
      absorbed: [
        for (final n in j['katilan'] is List ? j['katilan'] as List : const [])
          if (n is String) n,
      ],
      stamps: {
        if (j['alanZamani'] is Map)
          for (final e in (j['alanZamani'] as Map).entries)
            if (fields.contains(e.key))
              '${e.key}': ?DateTime.tryParse('${e.value}'),
      },
      versions: {
        if (j['alanSurumu'] is Map)
          for (final e in (j['alanSurumu'] as Map).entries)
            if (fields.contains(e.key)) '${e.key}': ?Hlc.tryParse(e.value),
      },
      caseLinks: {
        if (j['dosyalar'] is Map)
          for (final e in (j['dosyalar'] as Map).entries)
            '${e.key}': ?CaseLink.fromJson(e.value),
      },
      caseNotes: {
        if (j['dosyaNotlari'] is Map)
          for (final e in (j['dosyaNotlari'] as Map).entries)
            '${e.key}': ?CaseNote.fromJson(e.value),
      },
    );
  }

  String encode() => jsonEncode(toJson());
}

/// A case tied to a client by the lawyer's hand ([added]), or taken off
/// it ([removed]; the cases' names bring it back no more), or neither
/// again; [at] is when this was said, the later word winning.
class CaseLink {
  const CaseLink(this.state, this.at, {this.role = '', this.version});

  static const added = 'ekli', removed = 'cikarildi', none = '';
  final String state, role;
  final DateTime at;

  /// Its version (R1); null for one written before versions.
  final Hlc? version;

  Hlc get versionOf => version ?? Hlc.fromLegacy(at.toIso8601String());

  /// What it says, for choosing between two of the same version.
  Map<String, Object?> get value => {...toJson()}..remove('surum');

  bool sameAs(CaseLink o) => state == o.state && role == o.role && at == o.at;

  CaseLink withVersion(Hlc v) => CaseLink(state, at, role: role, version: v);

  Map<String, Object?> toJson() => {
    'durum': state,
    'rol': role,
    'zaman': at.toIso8601String(),
    if (version != null) 'surum': '$version',
  };

  static CaseLink? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['zaman']}');
    final state = j['durum'];
    if (at == null || state is! String) return null;
    return CaseLink(
      state,
      at,
      role: j['rol'] is String ? j['rol'] as String : '',
      version: Hlc.tryParse(j['surum']),
    );
  }
}

/// The lawyer's note on one of the client's cases: [by] wrote it at [at];
/// the later note wins on every device.
class CaseNote {
  const CaseNote(
    this.text,
    this.at, {
    this.by = '',
    this.version,
    this.secret = false,
  });
  final String text, by;
  final DateTime at;

  /// A secret note (R7): on the lawyer's own devices only. Versioned with
  /// its text, as one.
  final bool secret;

  /// Its version (R1); null for one written before versions.
  final Hlc? version;

  Hlc get versionOf => version ?? Hlc.fromLegacy(at.toIso8601String());

  /// What it says, for choosing between two of the same version.
  Map<String, Object?> get value => {...toJson()}..remove('surum');

  bool sameAs(CaseNote o) =>
      text == o.text && by == o.by && at == o.at && secret == o.secret;

  CaseNote withVersion(Hlc v) =>
      CaseNote(text, at, by: by, version: v, secret: secret);

  Map<String, Object?> toJson() => {
    'metin': text,
    'yazan': by,
    'zaman': at.toIso8601String(),
    if (secret) 'gizliNot': true,
    if (version != null) 'surum': '$version',
  };

  static CaseNote? fromJson(Object? j) {
    if (j is! Map || j['metin'] is! String) return null;
    final at = DateTime.tryParse('${j['zaman']}');
    if (at == null) return null;
    return CaseNote(
      j['metin'] as String,
      at,
      by: j['yazan'] is String ? j['yazan'] as String : '',
      version: Hlc.tryParse(j['surum']),
      secret: j['gizliNot'] == true,
    );
  }
}

/// The lawyer's own income and expenses (the Kasa) are kept beside the
/// clients' records, under this id: alone, on one's own devices through
/// Senkron, and in an office among those who see the money; never changed
/// once written, as a client's movements are not.
const officeCashId = 'buro';

/// What is kept for a client beside its card: a meeting's minutes, a power
/// of attorney; later its accounts' movements.
enum ClientRecordKind {
  meeting('gorusme'),
  attorney('vekalet'),

  /// A case's fee agreed: fixed, a share of what is won, or both, and its
  /// instalments.
  fee('ucret'),

  /// Money in or out of a case's account: a fee paid, an advance taken, a
  /// cost met from it or by the lawyer. Never changed once written; a
  /// wrong one is taken back by another that names it.
  movement('hareket'),

  /// The office's own income or expense (lib/services/clients/
  /// office_cash.dart): never changed once written.
  cash('kasa'),

  /// An expense the office pays every month, written for each month.
  cashRepeat('kasaTekrar'),

  /// A bank account kept beside the book, if the lawyer wants one: its
  /// name, currency and balance as last told (office_cash.dart).
  bank('banka'),

  /// A line of an enforcement file's own account in Folio: a payment the
  /// debtor made outside the office (haricen), or a claim waived; until
  /// UYAP shows it, the debt Folio counts is less by it
  /// (lib/services/enforcement/enforcement_ledger.dart).
  enforcement('icra'),

  /// A message written to the client (WhatsApp, SMS, e-mail) as the
  /// lawyer sent it: kept on their timeline.
  message('mesaj'),

  /// A paper made for the client (a fee agreement, a release, a receipt):
  /// what it is, its case and sum, the draft as made (in `ekler`, named by
  /// `taslak`) and, once signed, its signed copy; locked then.
  paper('belge');

  const ClientRecordKind(this.code);
  final String code;

  /// Seen only by those who see the money (a manager, or one let).
  bool get money =>
      this == fee ||
      this == movement ||
      this == cash ||
      this == cashRepeat ||
      this == bank ||
      this == paper;

  /// Seen and sent only to those who see the money (docs/senkron-plan.md
  /// R11): [money]'s, and an enforcement file's own account, whose sums,
  /// debtors and notes are money though they count in no total. Kept
  /// apart from [money], which the accounts and lists use.
  bool get financial => money || this == enforcement;

  /// The [financial] kinds' codes.
  static final financialCodes = [
    for (final k in values)
      if (k.financial) k.code,
  ];

  static ClientRecordKind? of(Object? code) {
    for (final k in values) {
      if (k.code == code) return k;
    }
    return null;
  }
}

/// One record of a client's. [created] is when it was written, to the
/// second, and never changes; [by] who wrote it. A [locked] record (signed
/// minutes) is not changed again, here or by another device: what was
/// decided in it stands as it was signed.
class ClientRecord {
  const ClientRecord({
    required this.id,
    required this.clientId,
    required this.kind,
    required this.data,
    required this.created,
    required this.by,
    required this.updated,
    this.locked = false,
    this.removed = false,
    this.person = '',
  });

  final String id, clientId;

  /// The office person who wrote it (their first device's id); empty
  /// where there is no office.
  final String person;
  final ClientRecordKind kind;
  final Map<String, Object?> data;
  final DateTime created, updated;
  final String by;
  final bool locked, removed;

  String text(String key) => data[key] is String ? data[key] as String : '';
  List<String> list(String key) => [
    for (final v in data[key] is List ? data[key] as List : const [])
      if (v is String) v,
  ];

  ClientRecord copyWith({
    Map<String, Object?>? data,
    bool? locked,
    bool? removed,
    String? person,
  }) => ClientRecord(
    id: id,
    clientId: clientId,
    kind: kind,
    data: data ?? this.data,
    created: created,
    by: by,
    updated: DateTime.now(),
    locked: locked ?? this.locked,
    removed: removed ?? this.removed,
    person: person ?? this.person,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'muvekkil': clientId,
    'tur': kind.code,
    'veri': data,
    'olusturma': created.toIso8601String(),
    'yazan': by,
    'kisi': person,
    'guncelleme': updated.toIso8601String(),
    'kilitli': locked,
    'silindi': removed,
  };

  static ClientRecord? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || j['muvekkil'] is! String) {
      return null;
    }
    final kind = ClientRecordKind.of(j['tur']);
    final created = DateTime.tryParse('${j['olusturma']}');
    if (kind == null || created == null) return null;
    return ClientRecord(
      id: j['id'] as String,
      clientId: j['muvekkil'] as String,
      kind: kind,
      data: j['veri'] is Map
          ? Map<String, Object?>.from(j['veri'] as Map)
          : const {},
      created: created,
      by: j['yazan'] is String ? j['yazan'] as String : '',
      updated: DateTime.tryParse('${j['guncelleme']}') ?? created,
      locked: j['kilitli'] == true,
      removed: j['silindi'] == true,
      person: j['kisi'] is String ? j['kisi'] as String : '',
    );
  }
}

/// A client as the list shows it: its card (null for one only seen in
/// the cases so far), its name, and the cases it is the lawyer's in.
class ClientEntry {
  const ClientEntry({
    required this.key,
    required this.name,
    this.client,
    this.cases = const [],
    this.ids = const [],
    this.removedCases = const [],
    this.addedCases = const {},
  });

  /// The cases the lawyer took off the client: kept to be given back.
  final List<({String caseKey, String role})> removedCases;

  /// The keys of the cases among [cases] the lawyer tied by hand.
  final Set<String> addedCases;

  /// Every card it is: the same client a colleague made a card for too
  /// (the same TCKN/VKN, else the same name) is one.
  final List<String> ids;

  /// Its card's id, else its folded name.
  final String key;
  final String name;
  final Client? client;

  /// The cases, each with the role the client has in it.
  final List<({String caseKey, String role})> cases;
}

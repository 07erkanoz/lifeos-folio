import 'dart:convert';
import 'dart:math';

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
    this.names = const [],
    required this.updated,
    this.removed = false,
    this.office = false,
    this.sharedOnce = false,
    this.person = '',
    this.absorbed = const [],
    this.stamps = const {},
    this.caseLinks = const {},
    this.caseNotes = const {},
  });

  /// The lawyer's note on each of the client's cases, by case key.
  final Map<String, CaseNote> caseNotes;

  /// When each of [fields] was last set: two devices that changed
  /// different fields of a card keep both ([merge]). One not stamped was
  /// set when the card was ([updated]).
  final Map<String, DateTime> stamps;

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
    List<String>? names,
    DateTime? updated,
    bool? removed,
    bool? office,
    List<String>? absorbed,
    Map<String, CaseLink>? caseLinks,
    Map<String, CaseNote>? caseNotes,
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
      names: names ?? this.names,
      updated: now,
      removed: removed ?? this.removed,
      office: office ?? this.office,
      sharedOnce: sharedOnce || (office ?? this.office),
      person: person,
      absorbed: absorbed ?? this.absorbed,
      caseLinks: caseLinks ?? this.caseLinks,
      caseNotes: caseNotes ?? this.caseNotes,
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
    names: names,
    updated: updated,
    removed: removed,
    office: office,
    sharedOnce: sharedOnce,
    person: person,
    absorbed: absorbed,
    stamps: stamps,
    caseLinks: caseLinks,
    caseNotes: caseNotes,
  );

  /// When field [k] was last set.
  DateTime stampOf(String k) => stamps[k] ?? updated;

  Map<String, Object> get _values => {
    'ad': name,
    'kurum': body,
    'kimlik': idNo,
    'telefon': phone,
    'telefon2': phone2,
    'eposta': email,
    'adres': address,
    'not': note,
    'silindi': removed,
    'buro': office,
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
    for (final k in fields) {
      final ta = mine.stampOf(k), tb = theirs.stampOf(k);
      final later =
          tb.isAfter(ta) || (tb == ta && '${b[k]}'.compareTo('${a[k]}') > 0);
      pick[k] = later ? b[k]! : a[k]!;
      stamps[k] = later ? tb : ta;
    }
    final links = {...mine.caseLinks};
    theirs.caseLinks.forEach((k, l) {
      final kept = links[k];
      if (kept == null || l.at.isAfter(kept.at)) links[k] = l;
    });
    final notes = {...mine.caseNotes};
    theirs.caseNotes.forEach((k, n) {
      final kept = notes[k];
      if (kept == null || n.at.isAfter(kept.at)) notes[k] = n;
    });
    return Client(
      id: mine.id,
      name: pick['ad']! as String,
      body: pick['kurum']! as bool,
      idNo: pick['kimlik']! as String,
      phone: pick['telefon']! as String,
      phone2: pick['telefon2']! as String,
      email: pick['eposta']! as String,
      address: pick['adres']! as String,
      note: pick['not']! as String,
      names: {...mine.names, ...theirs.names}.toList(),
      updated: theirs.updated.isAfter(mine.updated)
          ? theirs.updated
          : mine.updated,
      removed: pick['silindi']! as bool,
      office: pick['buro']! as bool,
      sharedOnce: mine.sharedOnce || theirs.sharedOnce,
      person: mine.person.isNotEmpty ? mine.person : theirs.person,
      absorbed: {...mine.absorbed, ...theirs.absorbed}.toList(),
      stamps: stamps,
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
    'adlar': names,
    'guncelleme': updated.toIso8601String(),
    'silindi': removed,
    'buro': office,
    'paylasildi': sharedOnce,
    'kisi': person,
    'katilan': absorbed,
    'alanZamani': {
      for (final k in fields)
        if (stamps[k] case final t?) k: t.toIso8601String(),
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
      names: [
        for (final n in j['adlar'] is List ? j['adlar'] as List : const [])
          if (n is String) n,
      ],
      updated: DateTime.tryParse(s('guncelleme')) ?? DateTime(2000),
      removed: j['silindi'] == true,
      office: j['buro'] == true,
      sharedOnce: j['paylasildi'] == true || j['buro'] == true,
      person: s('kisi'),
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
  const CaseLink(this.state, this.at, {this.role = ''});

  static const added = 'ekli', removed = 'cikarildi', none = '';
  final String state, role;
  final DateTime at;

  Map<String, Object?> toJson() => {
    'durum': state,
    'rol': role,
    'zaman': at.toIso8601String(),
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
    );
  }
}

/// The lawyer's note on one of the client's cases: [by] wrote it at [at];
/// the later note wins on every device.
class CaseNote {
  const CaseNote(this.text, this.at, {this.by = ''});
  final String text, by;
  final DateTime at;

  Map<String, Object?> toJson() => {
    'metin': text,
    'yazan': by,
    'zaman': at.toIso8601String(),
  };

  static CaseNote? fromJson(Object? j) {
    if (j is! Map || j['metin'] is! String) return null;
    final at = DateTime.tryParse('${j['zaman']}');
    if (at == null) return null;
    return CaseNote(
      j['metin'] as String,
      at,
      by: j['yazan'] is String ? j['yazan'] as String : '',
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
  cashRepeat('kasaTekrar');

  const ClientRecordKind(this.code);
  final String code;

  /// Seen only by those who see the money (a manager, or one let).
  bool get money =>
      this == fee || this == movement || this == cash || this == cashRepeat;

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

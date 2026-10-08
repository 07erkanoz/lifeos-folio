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
    this.email = '',
    this.address = '',
    this.note = '',
    this.names = const [],
    required this.updated,
    this.removed = false,
  });

  final String id, name;

  /// A company or an office, not a person.
  final bool body;

  /// TCKN for a person, VKN for a body; empty while not told.
  final String idNo;
  final String phone, email, address, note;

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
    String? email,
    String? address,
    String? note,
    List<String>? names,
    DateTime? updated,
    bool? removed,
  }) => Client(
    id: id,
    name: name ?? this.name,
    body: body ?? this.body,
    idNo: idNo ?? this.idNo,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    address: address ?? this.address,
    note: note ?? this.note,
    names: names ?? this.names,
    updated: updated ?? DateTime.now(),
    removed: removed ?? this.removed,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'ad': name,
    'kurum': body,
    'kimlik': idNo,
    'telefon': phone,
    'eposta': email,
    'adres': address,
    'not': note,
    'adlar': names,
    'guncelleme': updated.toIso8601String(),
    'silindi': removed,
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
      email: s('eposta'),
      address: s('adres'),
      note: s('not'),
      names: [
        for (final n in j['adlar'] is List ? j['adlar'] as List : const [])
          if (n is String) n,
      ],
      updated: DateTime.tryParse(s('guncelleme')) ?? DateTime(2000),
      removed: j['silindi'] == true,
    );
  }

  String encode() => jsonEncode(toJson());
}

/// What is kept for a client beside its card: a meeting's minutes, a power
/// of attorney; later its accounts' movements.
enum ClientRecordKind {
  meeting('gorusme'),
  attorney('vekalet');

  const ClientRecordKind(this.code);
  final String code;

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
  });

  final String id, clientId;
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
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'muvekkil': clientId,
    'tur': kind.code,
    'veri': data,
    'olusturma': created.toIso8601String(),
    'yazan': by,
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
  });

  /// Its card's id, else its folded name.
  final String key;
  final String name;
  final Client? client;

  /// The cases, each with the role the client has in it.
  final List<({String caseKey, String role})> cases;
}

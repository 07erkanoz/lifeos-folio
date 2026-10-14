import 'dart:convert';

import 'observed.dart';
import 'portal_channel.dart';
import '../../models/json_shape.dart';

/// One case as the portals together know it: the web's richer record and
/// the mobile API's shorter one merged field by field, each field
/// remembering which portal saw it and when (UYGULAMAPLANI §9.4).
class PortalCase {
  /// [caseKey] of [number] and [court].
  final String key;
  final String number;
  final String court;
  final CaseFamily family;

  /// Each portal's own id for the case, as a hint for its next request
  /// only: it lasts a session and is resolved afresh when stale.
  final Map<PortalChannel, String> ids;

  /// "açık"/"kapalı", and the like.
  final Observed<String>? status;
  final Observed<List<Map<String, Object?>>>? parties;

  /// Künye: the case's type, subject, opening date and so on.
  final Observed<Map<String, Object?>>? details;
  final Observed<List<Map<String, Object?>>>? documents;

  const PortalCase({
    required this.key,
    required this.number,
    required this.court,
    this.family = CaseFamily.court,
    this.ids = const {},
    this.status,
    this.parties,
    this.details,
    this.documents,
  });

  factory PortalCase.create({
    required String number,
    required String court,
    CaseFamily family = CaseFamily.court,
  }) => PortalCase(
    key: caseKey(number, court),
    number: number,
    court: court,
    family: family,
  );

  /// This case with [other], the same case from another answer, merged in.
  /// Neither portal's fields overwrite the other's: each fills what the
  /// other left empty, and a field both have goes to the complete or, among
  /// equals, the newer observation.
  PortalCase merge(PortalCase other) {
    assert(other.key == key, 'merging two different cases');
    return PortalCase(
      key: key,
      number: number.length >= other.number.length ? number : other.number,
      court: court.length >= other.court.length ? court : other.court,
      family: family == CaseFamily.court ? other.family : family,
      ids: {...ids, ...other.ids},
      status: mergeObserved(status, other.status),
      parties: mergeObserved(parties, other.parties),
      details: mergeDetails(details, other.details),
      documents: mergeObserved(documents, other.documents),
    );
  }
}

/// A case's particulars from the two portals, merged key by key: each says
/// what it knows (the web the court's id on the web, `birimId`; UYAP Mobil
/// its own codes), and neither wipes out what only the other said. The
/// newer (or the complete) one's value wins a key both give; a key only one
/// gives stays. Taken whole, the mobile API's reading erased the web's
/// `birimId`, and the web could no longer find the case to read its money
/// and account.
Observed<Map<String, Object?>>? mergeDetails(
  Observed<Map<String, Object?>>? current,
  Observed<Map<String, Object?>>? incoming,
) {
  final winner = mergeObserved(current, incoming);
  if (current == null || incoming == null || winner == null) return winner;
  final other = identical(winner, current) ? incoming : current;
  final merged = <String, Object?>{
    ...{
      for (final e in other.value.entries)
        if (!isEmptyValue(e.value)) e.key: e.value,
    },
    for (final e in winner.value.entries)
      if (!isEmptyValue(e.value)) e.key: e.value,
  };
  if (jsonEncode(merged) == jsonEncode(winner.value)) return winner;
  if (identical(winner, current) &&
      jsonEncode(merged) == jsonEncode(current.value)) {
    return current;
  }
  return Observed(merged, winner.source, winner.at, complete: winner.complete);
}

extension PortalCaseJson on PortalCase {
  Map<String, Object?> toJson() => {
    'key': key,
    'number': number,
    'court': court,
    'family': family.name,
    'ids': {for (final e in ids.entries) e.key.name: e.value},
    'status': status?.toJson((v) => v),
    'parties': parties?.toJson((v) => v),
    'details': details?.toJson((v) => v),
    'documents': documents?.toJson((v) => v),
  };

  static PortalCase fromJson(Map<String, Object?> json) {
    List<Map<String, Object?>> list(Object? v) => [
      for (final e in jsonList(v)) Map<String, Object?>.from(e),
    ];
    return PortalCase(
      key: json['key'] as String,
      number: json['number'] as String,
      court: json['court'] as String,
      family: CaseFamily.values.asNameMap()[json['family']] ?? CaseFamily.court,
      ids: {
        for (final e in (json['ids'] as Map? ?? const {}).entries)
          ?PortalChannel.values.asNameMap()[e.key]: '${e.value}',
      },
      status: Observed.fromJson(json['status'], (v) => '$v'),
      parties: Observed.fromJson(json['parties'], list),
      details: Observed.fromJson(
        json['details'],
        (v) => Map<String, Object?>.from(v as Map? ?? const {}),
      ),
      documents: Observed.fromJson(json['documents'], list),
    );
  }
}

/// [current] with every case of [incoming] merged in by key; cases the
/// answer did not mention stay, since an answer that leaves one out does
/// not say it is gone.
Map<String, PortalCase> mergePortfolio(
  Map<String, PortalCase> current,
  Iterable<PortalCase> incoming,
) {
  final out = {...current};
  for (final one in incoming) {
    out[one.key] = out[one.key]?.merge(one) ?? one;
  }
  return out;
}

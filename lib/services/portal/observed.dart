import '../editor/suggestions/phrases.dart' show foldPhrase;
import 'portal_channel.dart';

/// A value as one portal last saw it (UYGULAMAPLANI §9.4).
class Observed<T> {
  final T value;
  final PortalChannel source;

  /// When the portal was asked, not when Folio wrote it down.
  final DateTime at;

  /// The portal gave the whole of it: the web's party list or document
  /// list, say. The mobile API's shorter answers are not complete, and
  /// never replace a complete one, however much newer.
  final bool complete;

  const Observed(this.value, this.source, this.at, {this.complete = true});

  Map<String, Object?> toJson(Object? Function(T value) encode) => {
    'value': encode(value),
    'source': source.name,
    'at': at.toUtc().toIso8601String(),
    'complete': complete,
  };

  static Observed<T>? fromJson<T>(
    Object? json,
    T Function(Object? value) decode,
  ) {
    if (json is! Map) return null;
    final source = PortalChannel.values.asNameMap()[json['source']];
    final at = DateTime.tryParse('${json['at']}');
    if (source == null || at == null) return null;
    return Observed(
      decode(json['value']),
      source,
      at,
      complete: json['complete'] != false,
    );
  }
}

/// Whether [value] says nothing: null, blank, or an empty list or map. An
/// empty answer never wipes out what another portal said.
bool isEmptyValue(Object? value) => switch (value) {
  null => true,
  String s => s.trim().isEmpty,
  Iterable i => i.isEmpty,
  Map m => m.isEmpty,
  _ => false,
};

/// The field after [incoming] arrives, where [current] is what Folio has.
/// The two portals enrich each other and never overwrite each other:
///
/// 1. An empty answer keeps what there is.
/// 2. An empty field takes any answer.
/// 3. A partial answer does not replace a complete one: the mobile API's
///    party list does not cut the web's down.
/// 4. Otherwise the newer observation wins; on a tie, what there is stays.
Observed<T>? mergeObserved<T>(Observed<T>? current, Observed<T>? incoming) {
  if (incoming == null || isEmptyValue(incoming.value)) return current;
  if (current == null || isEmptyValue(current.value)) return incoming;
  if (current.complete && !incoming.complete) return current;
  if (incoming.complete && !current.complete) return incoming;
  return incoming.at.isAfter(current.at) ? incoming : current;
}

/// What the two portals' records of one case meet on: the case number and
/// the court, folded (Turkish letters, case, punctuation, spacing), with an
/// enforcement file's renewal suffix (" - 2" and the like) cut. The
/// portals' own ids last a session and are never the key.
String caseKey(String number, String court) {
  String fold(String text) =>
      foldPhrase(text)
          .replaceAll(RegExp(r'[^\p{L}\p{N}/]+', unicode: true), ' ')
          .trim();
  final base = number.split(' - ').first;
  return '${fold(base).replaceAll(' ', '')}|${fold(court)}';
}

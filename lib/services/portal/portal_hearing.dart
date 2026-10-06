import 'observed.dart';
import 'portal_channel.dart';

/// One hearing as the portals together know it (UYGULAMAPLANI §9.7).
class PortalHearing {
  /// [hearingKey]: the case and the minute. A hearing moved to another
  /// time is another hearing.
  final String key;

  /// [caseKey] of the case it belongs to.
  final String caseKey;
  final String number;
  final String court;

  /// Local Turkish time, as UYAP gives it.
  final DateTime at;

  /// Each portal's own id for the hearing record.
  final Map<PortalChannel, String> ids;

  /// "Ön inceleme duruşması", "Tanık dinlenmesi" and the like.
  final Observed<String>? kind;
  final Observed<String>? result;
  final Observed<List<Map<String, Object?>>>? parties;

  /// The judge's note and the e-hearing link: the mobile API's alone.
  final Observed<String>? judgeNote;
  final Observed<String>? eHearing;

  const PortalHearing({
    required this.key,
    required this.caseKey,
    required this.number,
    required this.court,
    required this.at,
    this.ids = const {},
    this.kind,
    this.result,
    this.parties,
    this.judgeNote,
    this.eHearing,
  });

  factory PortalHearing.create({
    required String number,
    required String court,
    required DateTime at,
    PortalChannel? channel,
    String? id,
    Observed<String>? kind,
    Observed<String>? result,
    Observed<List<Map<String, Object?>>>? parties,
    Observed<String>? judgeNote,
    Observed<String>? eHearing,
  }) => PortalHearing(
    key: hearingKey(number, court, at),
    caseKey: _caseKeyOf(number, court),
    number: number,
    court: court,
    at: at,
    ids: {if (channel != null && id != null) channel: id},
    kind: kind,
    result: result,
    parties: parties,
    judgeNote: judgeNote,
    eHearing: eHearing,
  );

  bool get isEHearing => !isEmptyValue(eHearing?.value);

  /// The channels that have reported this hearing.
  Set<PortalChannel> get seenBy => {
    ...ids.keys,
    for (final f in [kind, result, parties, judgeNote, eHearing]) ?f?.source,
  };

  /// Neither portal's fields overwrite the other's; the mobile API's
  /// generic "Duruşma" does not replace the web's own kind, being partial.
  PortalHearing merge(PortalHearing other) {
    assert(other.key == key, 'merging two different hearings');
    return PortalHearing(
      key: key,
      caseKey: caseKey,
      number: number.length >= other.number.length ? number : other.number,
      court: court.length >= other.court.length ? court : other.court,
      at: at,
      ids: {...ids, ...other.ids},
      kind: mergeObserved(kind, other.kind),
      result: mergeObserved(result, other.result),
      parties: mergeObserved(parties, other.parties),
      judgeNote: mergeObserved(judgeNote, other.judgeNote),
      eHearing: mergeObserved(eHearing, other.eHearing),
    );
  }

  Map<String, Object?> toJson() => {
    'key': key,
    'caseKey': caseKey,
    'number': number,
    'court': court,
    'at': at.toIso8601String(),
    'ids': {for (final e in ids.entries) e.key.name: e.value},
    'kind': kind?.toJson((v) => v),
    'result': result?.toJson((v) => v),
    'parties': parties?.toJson((v) => v),
    'judgeNote': judgeNote?.toJson((v) => v),
    'eHearing': eHearing?.toJson((v) => v),
  };

  static PortalHearing fromJson(Map<String, Object?> json) {
    String str(Object? v) => '$v';
    List<Map<String, Object?>> list(Object? v) => [
      for (final e in v as List? ?? const []) Map<String, Object?>.from(e),
    ];
    return PortalHearing(
      key: json['key'] as String,
      caseKey: json['caseKey'] as String,
      number: json['number'] as String,
      court: json['court'] as String,
      at: DateTime.parse(json['at'] as String),
      ids: {
        for (final e in (json['ids'] as Map? ?? const {}).entries)
          ?PortalChannel.values.asNameMap()[e.key]: '${e.value}',
      },
      kind: Observed.fromJson(json['kind'], str),
      result: Observed.fromJson(json['result'], str),
      parties: Observed.fromJson(json['parties'], list),
      judgeNote: Observed.fromJson(json['judgeNote'], str),
      eHearing: Observed.fromJson(json['eHearing'], str),
    );
  }
}

/// [caseKey], under a name the class's own field does not hide.
String _caseKeyOf(String number, String court) => caseKey(number, court);

/// The case and the minute, the way the two portals' records of one
/// hearing meet.
String hearingKey(String number, String court, DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${caseKey(number, court)}|${at.year}${two(at.month)}${two(at.day)}'
      '${two(at.hour)}${two(at.minute)}';
}

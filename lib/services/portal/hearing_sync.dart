import 'observed.dart';
import 'portal_case.dart';
import 'portal_channel.dart';
import 'portal_database.dart';
import 'portal_hearing.dart';

/// One portal's hearing row as a [PortalHearing]. The web and the mobile
/// API name the fields alike (`tarihSaat`, `kayitId`, `dosyaNo`,
/// `yerelBirimAd`, `islemTuruAciklama`, `dosyaTaraflari`), so one reader
/// serves both; two readers is how Banaozel came to split one hearing into
/// two rows. Null for a row without a time, a case number or a court.
PortalHearing? parseHearing(
  Map<String, Object?> row,
  PortalChannel channel,
  DateTime asked,
) {
  final at = _time('${row['tarihSaat'] ?? ''}'.trim());
  final number = '${row['dosyaNo'] ?? ''}'.split(' - ').first.trim();
  final court = '${row['yerelBirimAd'] ?? row['birimAdi'] ?? ''}'.trim();
  if (at == null || number.isEmpty || court.isEmpty) return null;
  final web = channel == PortalChannel.uyapWeb;
  Observed<String>? text(Object? value, {bool complete = true}) {
    final s = '${value ?? ''}'.trim();
    return s.isEmpty ? null : Observed(s, channel, asked, complete: complete);
  }

  final parties = [
    for (final p in row['dosyaTaraflari'] as List? ?? const [])
      if (p is Map) {for (final e in p.entries) '${e.key}': e.value},
  ];
  final link = '${row['token'] ?? ''}'.trim();
  final id = '${row['kayitId'] ?? ''}'.trim();
  return PortalHearing.create(
    number: number,
    court: court,
    at: at,
    channel: channel,
    id: id.isEmpty ? null : id,
    // The mobile API's kind is often a bare "Duruşma": partial, so that it
    // never replaces the web's own.
    kind: text(row['islemTuruAciklama'], complete: web),
    result: text(
      row['islemSonucuAciklama'] ?? row['talepDurumu'],
      complete: web,
    ),
    parties: parties.isEmpty
        ? null
        : Observed(parties, channel, asked, complete: web),
    eHearing: text(link),
  );
}

/// The case a hearing row belongs to, as far as the row tells: its number
/// and court, this session's id for it, and the kind of file (a partial
/// answer, which the case's own details replace). A hearing's case is in
/// the portfolio even before the portfolio is fetched.
PortalCase? caseOfHearing(
  Map<String, Object?> row,
  PortalChannel channel,
  DateTime asked,
) {
  final number = '${row['dosyaNo'] ?? ''}'.split(' - ').first.trim();
  final court = '${row['yerelBirimAd'] ?? row['birimAdi'] ?? ''}'.trim();
  if (number.isEmpty || court.isEmpty) return null;
  String text(String key) => '${row[key] ?? ''}'.trim();
  final details = {
    if (text('dosyaTurKodAciklama').isNotEmpty)
      'dosyaTuru': text('dosyaTurKodAciklama'),
    if (text('dosyaTurKod').isNotEmpty) 'dosyaTurKod': text('dosyaTurKod'),
    // The web's court id is a number the web asks with; the mobile API's
    // is its own, useless to the web.
    if (channel == PortalChannel.uyapWeb && text('birimId').isNotEmpty)
      'birimId': text('birimId'),
  };
  return PortalCase(
    key: caseKey(number, court),
    number: number,
    court: court,
    ids: {if (text('dosyaId').isNotEmpty) channel: text('dosyaId')},
    details: details.isEmpty
        ? null
        : Observed(details, channel, asked, complete: false),
  );
}

/// "06.10.2026 09:20:00", with or without seconds or fractions, or ISO.
DateTime? _time(String raw) {
  final tr = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})[ T](\d{1,2}):(\d{2})')
      .firstMatch(raw);
  if (tr != null) {
    int g(int i) => int.parse(tr.group(i)!);
    return DateTime(g(3), g(2), g(1), g(4), g(5));
  }
  final iso = DateTime.tryParse(raw);
  return iso == null
      ? null
      : DateTime(iso.year, iso.month, iso.day, iso.hour, iso.minute);
}

/// [from]–[to] in windows of at most [days] days each, both ends included:
/// the portals refuse a longer range.
Iterable<(DateTime, DateTime)> hearingWindows(
  DateTime from,
  DateTime to, {
  int days = 29,
}) sync* {
  var start = DateTime(from.year, from.month, from.day);
  final last = DateTime(to.year, to.month, to.day);
  while (!start.isAfter(last)) {
    var end = DateTime(start.year, start.month, start.day + days - 1);
    if (end.isAfter(last)) end = last;
    yield (start, end);
    start = DateTime(end.year, end.month, end.day + 1);
  }
}

class HearingSyncResult {
  final int hearings;

  /// Every window answered. Only a complete answer may remove a hearing.
  final bool complete;
  final List<String> errors;
  const HearingSyncResult(this.hearings, this.complete, this.errors);
}

/// Asks one portal for the hearings from [daysBefore] days ago to
/// [daysAfter] days ahead, window by window, and merges the answer into
/// [db] (UYGULAMAPLANI §9.7). A window that fails makes the answer
/// incomplete, and the next windows are still asked; a lost session stops
/// it.
Future<HearingSyncResult> syncHearings(
  PortalChannel channel,
  PortalDatabase db,
  Future<List<Map<String, Object?>>> Function(DateTime from, DateTime to)
  query, {
  DateTime? now,
  int daysBefore = 30,
  int daysAfter = 90,
  int windowDays = 29,
}) async {
  final today = now ?? DateTime.now();
  final from = DateTime(today.year, today.month, today.day - daysBefore);
  final to = DateTime(today.year, today.month, today.day + daysAfter);
  final asked = DateTime.now().toUtc();
  final found = <String, PortalHearing>{};
  final cases = <String, PortalCase>{};
  final errors = <String>[];
  for (final (start, end) in hearingWindows(from, to, days: windowDays)) {
    try {
      for (final row in await query(start, end)) {
        final one = parseHearing(row, channel, asked);
        if (one != null) found[one.key] = found[one.key]?.merge(one) ?? one;
        final kase = caseOfHearing(row, channel, asked);
        if (kase != null) {
          cases[kase.key] = cases[kase.key]?.merge(kase) ?? kase;
        }
      }
    } catch (e) {
      errors.add('${start.day}.${start.month}.${start.year}: $e');
      if ('$e'.toLowerCase().contains('oturum')) break;
    }
  }
  final complete = errors.isEmpty;
  db.mergeCases(cases.values);
  db.mergeHearings(
    channel,
    from,
    DateTime(to.year, to.month, to.day + 1),
    found.values.toList(),
    complete: complete,
  );
  return HearingSyncResult(found.length, complete, errors);
}

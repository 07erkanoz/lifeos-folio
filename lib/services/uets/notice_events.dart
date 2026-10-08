import '../portal/observed.dart';
import '../portal/portal_channel.dart';
import '../portal/portal_database.dart';
import '../portal/portal_hearing.dart';
import '../uyap/uyap_web_service.dart' show UyapWebService;

/// A day a notice's papers set: a hearing, an on-site inspection (keşif),
/// a hearing on an objection (mürafaa); its kind and its minute.
typedef NoticeEvent = ({String kind, DateTime at});

final _when = RegExp(
  r'(\d{1,2})[./](\d{1,2})[./](\d{4})\s*(?:günü|tarihinde|tarihli)?\s*'
  r'(?:saat\s*)?(?:[:\s]*)(\d{1,2})[.:](\d{2})',
);

/// The days [text] sets, by the word near each date: "keşfin 04/05/2026
/// günü saat 10.00'da yapılmasına", "duruşmasının 15/12/2025 günü saat
/// 11:15'a bırakılmasına", a summons's "Duruşma Günü … 15/10/2026 13:45".
/// A date that only names a decision or a filing sets nothing.
List<NoticeEvent> noticeEvents(String text) {
  final folded = UyapWebService.fold(text);
  final out = <NoticeEvent>[];
  for (final m in _when.allMatches(text)) {
    final d = int.parse(m[1]!), mo = int.parse(m[2]!), y = int.parse(m[3]!);
    final h = int.parse(m[4]!), mi = int.parse(m[5]!);
    if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59) continue;
    // The words around it, folded alike (fold keeps the length).
    final from = (m.start - 90).clamp(0, folded.length);
    final to = (m.end + 60).clamp(0, folded.length);
    final near = folded.substring(from, to);
    final String kind;
    if (near.contains('kesif') || near.contains('kesf')) {
      kind = 'Keşif';
    } else if (near.contains('murafaa')) {
      kind = 'Mürafaa';
    } else if (near.contains('durusma')) {
      kind = 'Duruşma';
    } else {
      continue;
    }
    final at = DateTime(y, mo, d, h, mi);
    if (!out.any((e) => e.at == at)) out.add((kind: kind, at: at));
  }
  return out;
}

/// The days the notices' papers set, kept as hearings of their cases when
/// UYAP has not listed them (an inspection is not on its hearing list; a
/// case outside the portfolio has none): to come only, from the newest
/// notice of each case, and of a kind the notice's papers name. A day
/// UYAP lists is left to UYAP; one a later paper moved is no longer kept.
int refreshNoticeEvents(PortalDatabase db, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final envelopes = db.envelopes();
  final seen = <String>{};
  final found = <PortalHearing>[];
  final cases = <String>{};
  // Newest first: a case's latest papers say where it stands.
  for (final kept in db.notices()) {
    final id = kept.message.id;
    final texts = [
      if (envelopes[id]?.envelopeText case final t? when t.isNotEmpty) t,
      for (final d in db.noticeDocuments(id))
        if (d.hasText) d.text,
    ];
    if (texts.isEmpty) continue;
    final file = [for (final d in db.noticeDocuments(id)) ?d.caseFile]
        .firstOrNull;
    final number = file?.number ?? '';
    final court = file?.unitName ?? '';
    final key =
        kept.caseKey ??
        (number.isEmpty || court.isEmpty ? null : caseKey(number, court));
    if (key == null || !seen.add(key)) continue;
    final events = [for (final t in texts) ...noticeEvents(t)];
    if (events.isEmpty) continue;
    cases.add(key);
    final known = db.caseOf(key);
    for (final e in events) {
      if (e.at.isBefore(today)) continue;
      final n = known?.number ?? number, c = known?.court ?? court;
      found.add(
        PortalHearing(
          key: hearingKey(n, c, e.at),
          caseKey: key,
          number: n,
          court: c,
          at: e.at,
          ids: {PortalChannel.uets: id},
          kind: Observed(e.kind, PortalChannel.uets, today),
        ),
      );
    }
  }
  // What the papers set before and set no longer goes; UYAP's stay.
  db.replacePaperHearings(cases, found);
  return found.length;
}

import '../editor/suggestions/phrases.dart' show foldPhrase;
import '../legal/deadlines/belge_turu.dart';
import '../legal/deadlines/deadline_service.dart';
import '../legal/deadlines/mahkeme_kategori.dart';
import '../legal/deadlines/sure_katalogu.dart' show SureGuveni;
import '../legal/deadlines/turkish_legal_calendar.dart';
import '../portal/portal_case.dart';
import '../portal/portal_database.dart';
import 'uets_api.dart';

/// A notification's subject read: "Antalya 3. Asliye Hukuk Mahkemesi
/// [2025/412] [Gerekçeli Karar]": the unit, then the first bracket's case
/// number.
class NoticeSubject {
  final String unit;
  final String number;
  const NoticeSubject(this.unit, this.number);

  static final _pattern = RegExp(r'^([^\[]{3,120}?)\s*\[(\d{4}/\d+)\]');

  static NoticeSubject? parse(String subject) {
    final m = _pattern.firstMatch(subject.trim());
    return m == null ? null : NoticeSubject(m.group(1)!.trim(), m.group(2)!);
  }
}

/// Turkish letters folded, case dropped, everything but letters and digits
/// made a space: "ANTALYA 3. ASLİYE HUKUK" and "Antalya 3 Asliye Hukuk" meet.
String _plain(String text) =>
    foldPhrase(text)
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .trim();

/// The case [subject] belongs to, among [cases], by the three steps of
/// UYGULAMAPLANI §9.8, each taken only when it leaves a single case:
/// the number and the unit exactly; the case's unit at the start of the
/// notice's (the Court of Cassation's "… Tebligat Bölümü"); the first word,
/// the place, alike (a prosecutor's bureau to its Başsavcılık). Two cases
/// or more, or none, tie nothing: no guess is made.
String? matchSubject(String subject, Iterable<PortalCase> cases) {
  final parsed = NoticeSubject.parse(subject);
  if (parsed == null) return null;
  final unit = _plain(parsed.unit);
  final sameNumber = [
    for (final c in cases)
      if (c.number.split(' - ').first.replaceAll(' ', '') == parsed.number) c,
  ];
  if (sameNumber.isEmpty) return null;
  final firstWord = unit.split(' ').first;
  for (final test in <bool Function(String court)>[
    (court) => court == unit,
    (court) => court.isNotEmpty && unit.startsWith(court),
    (court) => court.split(' ').first == firstWord,
  ]) {
    final found = [
      for (final c in sameNumber)
        if (test(_plain(c.court))) c,
    ];
    if (found.length == 1) return found.single.key;
    if (found.length > 1) return null;
  }
  return null;
}

/// Ties every untied notification in [db] to its case where the subject
/// leaves a single one; a tie the lawyer made is never touched. Then each
/// notification whose kind of document is certain from its subject gets
/// its deadlines in the agenda, once.
void matchNotices(PortalDatabase db, {DateTime? now}) {
  final cases = db.cases().values.toList();
  final kept = db.notices();
  for (final n in kept) {
    if (n.link != null) continue;
    final key = matchSubject(n.message.subject, cases);
    if (key != null) db.linkNotice(n.message.id, key, 'auto');
  }
  addNoticeDeadlines(db, now: now);
}

/// The deadlines a notification starts, as agenda deadlines whose ids name
/// the notification, so that they are added once and never overwrite what
/// the lawyer marked. Only where the kind of document is certain from the
/// subject; otherwise the lawyer calculates it in the agenda.
void addNoticeDeadlines(PortalDatabase db, {DateTime? now}) {
  final have = {for (final i in db.agenda()) i.id};
  for (final n in db.notices()) {
    final m = n.message;
    final sent = m.sent;
    final parsed = NoticeSubject.parse(m.subject);
    if (sent == null || parsed == null) continue;
    final kind = BelgeTuruTespit.tebligatTuru(const [], metin: m.subject);
    if (BelgeTuruTespit.belirsiz(kind)) continue;
    final category =
        TurkishLegalCalendar.kategoriFromMahkemeAdi(parsed.unit) ??
        MahkemeKategorisi.hukuk;
    final items = DeadlineService.compute(
      gonderimTarihi: sent,
      kategori: category,
      belgeTuru: kind,
      now: now,
    ).items;
    for (final item in items) {
      final id = 'uets:${m.id}:${item.sureAdi}';
      if (have.contains(id)) continue;
      db.saveAgenda(
        AgendaItem(
          id: id,
          kind: 'deadline',
          title: item.sureAdi,
          body: [
            'UETS · ${parsed.unit} · ${parsed.number}',
            item.kanun,
            if (item.guven != SureGuveni.yuksek) 'kontrol edin',
          ].join(' · '),
          at: item.etkiliSonGun,
          allDay: true,
          caseKey: n.caseKey,
          updated: DateTime.now(),
        ),
      );
    }
  }
}

/// Exposed for the screens: the subject's unit and number, or the subject.
String noticeTitle(UetsMessage m) {
  final p = NoticeSubject.parse(m.subject);
  return p == null ? m.subject : '${p.unit} · ${p.number}';
}

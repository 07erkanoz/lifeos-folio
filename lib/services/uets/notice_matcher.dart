import '../editor/suggestions/phrases.dart' show foldPhrase;
import '../portal/portal_case.dart';
import '../portal/portal_database.dart';
import 'notice_deadlines.dart';
import 'notice_documents.dart';
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
/// the place, alike, but only for a notice from a bureau or a prosecutor's
/// office (a prosecutor's bureau to its Başsavcılık): a court's notice
/// never ties to another court of the same place, "Ankara 1. Asliye Hukuk"
/// to "Ankara 8. İş" by the same number. Two cases or more, or none, tie
/// nothing: no guess is made.
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
  final office = RegExp(r'\b(buro\w*|\w*savcilig\w*)\b').hasMatch(unit);
  for (final test in <bool Function(String court)>[
    (court) => court == unit,
    (court) => court.isNotEmpty && unit.startsWith(court),
    if (office) (court) => court.split(' ').first == firstWord,
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
/// leaves a single one; a tie the lawyer made is never touched. Then the
/// notices' deadlines are made again (see [refreshNoticeDeadlines]), with
/// the parties and the lawyer's name [NoticeDeadlineContext] holds.
void matchNotices(PortalDatabase db, {DateTime? now}) {
  _tie(db);
  refreshNoticeDeadlines(
    db,
    parties: NoticeDeadlineContext.parties,
    lawyer: NoticeDeadlineContext.lawyer,
    now: now,
  );
}

/// What the subject's later brackets say the document is: "Gerekçeli
/// Karar"; empty when they say nothing.
String noticeKind(UetsMessage m) => [
  for (final b in RegExp(r'\[([^\]]*)\]').allMatches(m.subject).skip(1))
    b.group(1)!.trim(),
].where((s) => s.isNotEmpty).join(' · ');

/// [matchNotices] for the syncs: the deadlines made a few notices at a
/// time, the window let breathe between them.
Future<void> matchNoticesGently(PortalDatabase db, {DateTime? now}) async {
  _tie(db);
  await Future<void>.delayed(Duration.zero);
  await refreshNoticeDeadlinesGently(
    db,
    parties: NoticeDeadlineContext.parties,
    lawyer: NoticeDeadlineContext.lawyer,
    now: now,
  );
}

/// Ties notice [id], if untied, to the case its package's own description
/// (dosyaBilgileri) names: the same number and UYAP's name of the same
/// unit, word for word. The subject's words are a guess beside it.
void tieByCaseFile(PortalDatabase db, String id) {
  final n = db.notice(id);
  if (n == null || n.link != null) return;
  final file = db
      .noticeDocuments(id)
      .map((d) => d.caseFile)
      .whereType<NoticeCaseFile>()
      .firstOrNull;
  if (file == null || file.number.isEmpty || file.unitName.isEmpty) return;
  final unit = _plain(file.unitName);
  final found = [
    for (final c in db.cases().values)
      if (c.number.split(' - ').first.replaceAll(' ', '') ==
              file.number.replaceAll(' ', '') &&
          _plain(c.court) == unit)
        c,
  ];
  if (found.length == 1) db.linkNotice(id, found.single.key, 'auto');
}

/// Ties every untied notification to its case where its subject leaves
/// one; the untied ones alone are read.
void _tie(PortalDatabase db) {
  final untied = [
    for (final n in db.notices())
      if (n.link == null) n,
  ];
  if (untied.isEmpty) return;
  final cases = db.cases().values.toList();
  for (final n in untied) {
    final key = matchSubject(n.message.subject, cases);
    if (key != null) db.linkNotice(n.message.id, key, 'auto');
  }
}

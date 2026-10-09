import 'dart:convert';

import 'portal_database.dart';
import 'portal_hearing.dart';

/// One thing for the lawyer's calendar: a hearing at its hour, a deadline
/// or a task on its day.
class CalendarEvent {
  const CalendarEvent({
    required this.uid,
    required this.title,
    required this.start,
    this.allDay = false,
    this.minutes = 60,
    this.place = '',
    this.detail = '',
  });

  /// The same for the same thing on every export: a calendar given the
  /// file again updates what it took, adds nothing twice.
  final String uid;
  final String title, place, detail;
  final DateTime start;
  final bool allDay;
  final int minutes;
}

/// What the agenda keeps between [from] and [to], for a calendar: the
/// hearings, the deadlines followed and not done, and with [tasks] the
/// tasks and notes with a day. With [names] the clients' names are
/// written beside the case; without, only its number and court (KVKK:
/// the calendar is another's server).
List<CalendarEvent> agendaEvents(
  PortalDatabase db, {
  required DateTime from,
  required DateTime to,
  bool hearings = true,
  bool deadlines = true,
  bool tasks = false,
  bool names = false,
  String? lawyer,
}) {
  final whose = <String, List<String>>{};
  if (names) {
    for (final e in db.clientEntries(lawyer: lawyer)) {
      for (final c in e.cases) {
        (whose[c.caseKey] ??= []).add(e.name);
      }
    }
  }
  String named(String key, String number, String court) => [
    number,
    court,
    if (whose[key] case final n? when n.isNotEmpty) n.join(', '),
  ].where((s) => s.isNotEmpty).join(' · ');
  final out = <CalendarEvent>[
    if (hearings)
      for (final h in db.hearings(from: from, to: to))
        hearingEvent(
          h,
          client: names ? (whose[h.caseKey] ?? const []) : const [],
        ),
  ];
  if (deadlines) {
    for (final d in db.deadlines(decidedOnly: true)) {
      if (!d.onAgenda || (d.user?.done ?? false)) continue;
      final day = DateTime.tryParse(d.day ?? '');
      if (day == null || day.isBefore(from) || day.isAfter(to)) continue;
      final key = d.record.caseKey ?? '';
      final kase = key.isEmpty ? null : db.caseOf(key);
      out.add(
        CalendarEvent(
          uid: 'folio-sure-${d.record.id}',
          title:
              'Süre: ${d.user?.titleOverride ?? d.record.title}'
              '${kase == null ? '' : ' · ${named(key, kase.number, kase.court)}'}',
          start: day,
          allDay: true,
          detail: d.record.law,
        ),
      );
    }
  }
  for (final i in db.agenda(from: from, to: to)) {
    final at = i.at;
    if (at == null || i.done) continue;
    if (i.kind == 'deadline' ? !deadlines : !tasks) continue;
    final kase = i.caseKey == null ? null : db.caseOf(i.caseKey!);
    out.add(
      CalendarEvent(
        uid: 'folio-ajanda-${i.id}',
        title: [
          if (i.kind == 'deadline') 'Süre: ${i.title}' else i.title,
          if (kase != null) named(i.caseKey!, kase.number, kase.court),
        ].join(' · '),
        start: at,
        allDay: i.allDay,
        minutes: 30,
        detail: i.body,
      ),
    );
  }
  return out..sort((a, b) => a.start.compareTo(b.start));
}

/// A hearing as the calendar shows it; [client] the names of whom the
/// lawyer acts for, when they are to be written.
CalendarEvent hearingEvent(PortalHearing h, {List<String> client = const []}) =>
    CalendarEvent(
      uid: 'folio-durusma-${h.key}',
      title: [
        'Duruşma',
        h.number,
        h.court,
        if (client.isNotEmpty) client.join(', '),
      ].join(' · '),
      start: h.at,
      place: h.court,
      detail: h.kind?.value ?? '',
    );

/// [events] as an iCalendar file (RFC 5545) that Google, Outlook and
/// Apple's calendars take; each with an alarm [alarms] minutes before.
String calendarFile(
  List<CalendarEvent> events, {
  List<int> alarms = const [],
  DateTime? now,
}) {
  final stamp = _utc(now ?? DateTime.now());
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//LifeOS//Folio//TR',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:Folio ajanda',
    for (final e in events) ...[
      'BEGIN:VEVENT',
      'UID:${e.uid}@lifeos.com.tr',
      'DTSTAMP:$stamp',
      if (e.allDay) ...[
        'DTSTART;VALUE=DATE:${_date(e.start)}',
        'DTEND;VALUE=DATE:${_date(e.start.add(const Duration(days: 1)))}',
      ] else ...[
        'DTSTART:${_utc(e.start)}',
        'DTEND:${_utc(e.start.add(Duration(minutes: e.minutes)))}',
      ],
      'SUMMARY:${_text(e.title)}',
      if (e.place.isNotEmpty) 'LOCATION:${_text(e.place)}',
      if (e.detail.isNotEmpty) 'DESCRIPTION:${_text(e.detail)}',
      for (final m in alarms) ...[
        'BEGIN:VALARM',
        'ACTION:DISPLAY',
        'DESCRIPTION:${_text(e.title)}',
        'TRIGGER:-PT${m}M',
        'END:VALARM',
      ],
      'END:VEVENT',
    ],
    'END:VCALENDAR',
  ];
  return '${lines.map(_fold).join('\r\n')}\r\n';
}

String _two(int v) => v.toString().padLeft(2, '0');

String _date(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}'
    '${_two(t.month)}${_two(t.day)}';

String _utc(DateTime t) {
  final u = t.toUtc();
  return '${_date(u)}T${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
}

String _text(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,')
    .replaceAll(RegExp(r'\r?\n'), r'\n');

/// A line broken at 75 bytes, the rest on lines begun with a space; a
/// letter's bytes never split.
String _fold(String line) {
  final out = StringBuffer();
  var used = 0;
  for (final rune in line.runes) {
    final ch = String.fromCharCode(rune);
    final size = utf8.encode(ch).length;
    if (used + size > 75) {
      out.write('\r\n ');
      used = 1;
    }
    out.write(ch);
    used += size;
  }
  return out.toString();
}

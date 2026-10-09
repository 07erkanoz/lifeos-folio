import 'dart:convert';

import 'package:evrak_convert/services/portal/agenda_ics.dart';
import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_hearing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a calendar file a calendar takes: lines of 75 bytes at most, '
      'Turkish letters whole, its text escaped, an alarm before', () {
    final ics = calendarFile(
      [
        CalendarEvent(
          uid: 'folio-durusma-x',
          title:
              'Duruşma · 2024/318 · Antalya 3. Asliye Hukuk Mahkemesi; '
              'tanıklar, bilirkişi ve keşif için çağrılacak',
          start: DateTime.utc(2026, 10, 22, 7, 30),
          place: 'Antalya Adliyesi',
        ),
        CalendarEvent(
          uid: 'folio-sure-y',
          title: 'Süre: cevaba cevap',
          start: DateTime(2026, 10, 14),
          allDay: true,
        ),
      ],
      alarms: const [1440],
      now: DateTime.utc(2026, 10, 9),
    );
    final lines = ics.split('\r\n');
    for (final l in lines) {
      expect(utf8.encode(l).length, lessThanOrEqualTo(75), reason: l);
    }
    // Unfolded, the words are as written.
    final whole = ics.replaceAll('\r\n ', '');
    expect(whole, contains(r'Mahkemesi\; tanıklar\, bilirkişi'));
    expect(whole, contains('UID:folio-durusma-x@lifeos.com.tr'));
    expect(whole, contains('DTSTART:20261022T073000Z'));
    expect(whole, contains('DTEND:20261022T083000Z'));
    expect(whole, contains('DTSTART;VALUE=DATE:20261014'));
    expect(whole, contains('DTEND;VALUE=DATE:20261015'));
    expect('TRIGGER:-PT1440M'.allMatches(whole).length, 2);
    expect(lines.first, 'BEGIN:VCALENDAR');
    expect(ics.endsWith('END:VCALENDAR\r\n'), isTrue);
  });

  test('the agenda\'s hearings go by number and court, the client named '
      'only when asked; the same hearing has the same id each time', () {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    const number = '2024/318', court = 'Antalya 3. Asliye Hukuk Mahkemesi';
    final key = caseKey(number, court);
    db.mergeCases(
      [PortalCase(key: key, number: number, court: court)],
      portfolio: true,
      baseline: true,
    );
    db.setRepresentation(key, const [(ad: 'AYŞE KARACA', rol: 'Davacı')]);
    final at = DateTime(2026, 10, 22, 10, 30);
    db.mergeHearings(PortalChannel.uyapWeb, DateTime(2026), DateTime(2027), [
      PortalHearing(
        key: hearingKey(number, court, at),
        caseKey: key,
        number: number,
        court: court,
        at: at,
      ),
    ], complete: true);
    List<CalendarEvent> events({bool names = false}) => agendaEvents(
      db,
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 12, 31),
      names: names,
    );
    final hidden = events().single;
    expect(hidden.title, 'Duruşma · 2024/318 · $court');
    expect(events(names: true).single.title, contains('AYŞE KARACA'));
    expect(events().single.uid, hidden.uid);
  });
}

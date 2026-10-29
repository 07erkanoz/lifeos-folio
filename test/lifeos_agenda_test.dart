import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/platform/agenda_launch.dart';
import 'package:evrak_convert/services/portal/agenda_reminders.dart';
import 'package:evrak_convert/services/portal/lifeos_agenda.dart';
import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_hearing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const number = '2026/1182';
  const court = 'Ankara 4. Asliye Hukuk Mahkemesi';
  final key = caseKey(number, court);
  final now = DateTime(2026, 10, 27, 14, 20);

  PortalHearing hearing(DateTime at) => PortalHearing(
    key: hearingKey(number, court, at),
    caseKey: key,
    number: number,
    court: court,
    at: at,
  );

  /// A case for AYŞE KARACA, its hearings at [hearings], and a task on
  /// each of [tasks].
  PortalDatabase agenda({
    List<DateTime> hearings = const [],
    List<DateTime> tasks = const [],
  }) {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    db.mergeCases(
      [PortalCase(key: key, number: number, court: court)],
      portfolio: true,
      baseline: true,
    );
    db.setRepresentation(key, const [(ad: 'AYŞE KARACA', rol: 'Davacı')]);
    db.mergeHearings(PortalChannel.uyapWeb, DateTime(2026), DateTime(2028), [
      for (final at in hearings) hearing(at),
    ], complete: true);
    for (final (i, at) in tasks.indexed) {
      db.saveAgenda(
        AgendaItem(
          id: 'gorev$i',
          kind: 'task',
          title: 'Dilekçe hazırla',
          at: at,
          allDay: true,
          caseKey: key,
          updated: now,
        ),
      );
    }
    return db;
  }

  group('the file LifeOS reads', () {
    test('schema 1: a hearing with its time and offset, a task on its day, '
        'court and case apart, a uid fit for a command line', () {
      final db = agenda(
        hearings: [DateTime(2026, 10, 29, 10, 30)],
        tasks: [DateTime(2026, 10, 30)],
      );
      final events = LifeosAgenda.events(db, now);
      final doc = jsonDecode(LifeosAgenda.encode(events, now)) as Map;
      expect(doc['schema'], 1);
      expect(
        doc['generated'],
        matches(RegExp(r'^2026-10-27T14:20:00[+-]\d\d:\d\d$')),
      );
      final list = (doc['events'] as List).cast<Map>();
      expect(list, hasLength(2));
      final h = list.first;
      expect(h['kind'], 'durusma');
      expect(h['title'], 'Duruşma');
      expect(
        h['start'],
        matches(RegExp(r'^2026-10-29T10:30:00[+-]\d\d:\d\d$')),
      );
      expect(
        DateTime.parse(h['start'] as String)
            .isAtSameMomentAs(DateTime(2026, 10, 29, 10, 30)),
        isTrue,
      );
      expect(h['allDay'], isFalse);
      expect(h['minutes'], 60);
      expect(h['court'], court);
      expect(h['case'], number);
      final t = list.last;
      expect(t['kind'], 'gorev');
      expect(t['title'], 'Dilekçe hazırla');
      expect(t['start'], '2026-10-30');
      expect(t['allDay'], isTrue);
      expect(t.containsKey('minutes'), isFalse);
      for (final e in list) {
        expect(e['uid'], matches(RegExp(r'^[A-Za-z0-9._-]+$')));
      }
      // The same record has the same uid on every write.
      expect(LifeosAgenda.events(db, now).first['uid'], h['uid']);
    });

    test('no client is named unless the lawyer turned it on', () {
      final db = agenda(
        hearings: [DateTime(2026, 10, 29, 10, 30)],
        tasks: [DateTime(2026, 10, 30)],
      );
      expect(LifeosAgenda.showsNames(db), isFalse);
      final hidden = LifeosAgenda.encode(LifeosAgenda.events(db, now), now);
      expect(hidden, isNot(contains('KARACA')));
      expect(hidden, isNot(contains('"client"')));
      LifeosAgenda.setShowsNames(db, true);
      final named = LifeosAgenda.events(db, now);
      expect(named.first['client'], 'AYŞE KARACA');
      LifeosAgenda.setShowsNames(db, false);
      expect(
        LifeosAgenda.encode(LifeosAgenda.events(db, now), now),
        isNot(contains('KARACA')),
      );
    });

    test('today and the next 14 days: not yesterday, not the 15th day', () {
      final db = agenda(
        hearings: [
          DateTime(2026, 10, 26, 10), // yesterday
          DateTime(2026, 10, 27, 9), // today, already begun
          DateTime(2026, 11, 10, 16), // the 14th day
          DateTime(2026, 11, 11, 9), // the 15th
        ],
        tasks: [DateTime(2026, 11, 10), DateTime(2026, 11, 11)],
      );
      final starts = [
        for (final e in LifeosAgenda.events(db, now)) e['start'] as String,
      ];
      expect(starts, hasLength(3));
      expect(starts[0], startsWith('2026-10-27T09:00'));
      expect(starts[1], '2026-11-10');
      expect(starts[2], startsWith('2026-11-10T16:00'));
    });

    test('written whole: renamed over the old file, only its owner may read '
        'it, nothing left beside it', () async {
      final dir = await Directory.systemTemp.createTemp('lifeos-ajanda-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'lifeos', 'folio-ajanda.json'));
      await LifeosAgenda.write(file, 'eski\n');
      // A reader that opened the old file goes on reading the old one.
      final reader = await file.open();
      await LifeosAgenda.write(file, 'yeni\n');
      expect(utf8.decode(await reader.read(16)), 'eski\n');
      await reader.close();
      expect(await file.readAsString(), 'yeni\n');
      expect(file.parent.listSync().map((e) => p.basename(e.path)), [
        'folio-ajanda.json',
      ]);
      if (!Platform.isWindows) {
        expect((await file.stat()).mode & 0x1ff, 0x180); // 0600
      }
    });

    test('the file is under XDG_DATA_HOME, or ~/.local/share', () {
      expect(
        LifeosAgenda.file({'XDG_DATA_HOME': '/x/data', 'HOME': '/home/a'})!
            .path,
        '/x/data/lifeos/folio-ajanda.json',
      );
      expect(
        LifeosAgenda.file({'HOME': '/home/a'})!.path,
        '/home/a/.local/share/lifeos/folio-ajanda.json',
      );
      // A relative XDG_DATA_HOME is to be ignored (XDG Base Directory).
      expect(
        LifeosAgenda.file({'XDG_DATA_HOME': 'rel', 'HOME': '/home/a'})!.path,
        '/home/a/.local/share/lifeos/folio-ajanda.json',
      );
      expect(LifeosAgenda.file({}), isNull);
    });

    test('kept current: written at start, again when the agenda changes and '
        'when the day turns, not when nothing did', () async {
      final dir = await Directory.systemTemp.createTemp('lifeos-ajanda-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'lifeos', 'folio-ajanda.json'));
      final db = agenda(hearings: [DateTime(2026, 10, 29, 10, 30)]);
      var clock = now;
      final writer = LifeosAgendaWriter(
        database: () async => db,
        target: file,
        now: () => clock,
      );
      addTearDown(writer.dispose);
      List<Map> events() =>
          ((jsonDecode(file.readAsStringSync()) as Map)['events'] as List)
              .cast<Map>();

      expect(await writer.check(), isTrue);
      expect(events(), hasLength(1));
      expect(await writer.check(), isFalse);

      // A hearing added: there at the next check.
      db.mergeHearings(PortalChannel.uyapWeb, DateTime(2026), DateTime(2028), [
        hearing(DateTime(2026, 10, 29, 10, 30)),
        hearing(DateTime(2026, 11, 2, 9)),
      ], complete: true);
      expect(await writer.check(), isTrue);
      expect(events(), hasLength(2));

      // Gone from Folio: gone from the file.
      db.mergeHearings(PortalChannel.uyapWeb, DateTime(2026), DateTime(2028), [
        hearing(DateTime(2026, 11, 2, 9)),
      ], complete: true);
      expect(await writer.check(), isTrue);
      expect(events().single['start'], startsWith('2026-11-02T09:00'));

      // The day turns, the hearing's day passes: written without it.
      clock = DateTime(2026, 11, 3, 0, 0, 20);
      expect(await writer.check(), isTrue);
      expect(events(), isEmpty);
    });

    test('a uid leads back to its record: a hearing chosen, a task at its '
        'day; one not kept to nothing', () {
      final db = agenda(
        hearings: [DateTime(2026, 10, 29, 10, 30)],
        tasks: [DateTime(2026, 10, 30)],
      );
      final events = LifeosAgenda.events(db, now);
      final h = LifeosAgenda.find(db, events.first['uid'] as String, now)!;
      expect(h.day, DateTime(2026, 10, 29));
      expect(
        h.hearing,
        hearingKey(number, court, DateTime(2026, 10, 29, 10, 30)),
      );
      final t = LifeosAgenda.find(db, events.last['uid'] as String, now)!;
      expect(t.day, DateTime(2026, 10, 30));
      expect(t.hearing, isNull);
      expect(LifeosAgenda.find(db, 'durusma-0000000000000000', now), isNull);
      expect(LifeosAgenda.find(db, 'baska', now), isNull);
    });
  });

  group('--ajanda', () {
    test('with a uid, without one, and not at all', () {
      expect(
        AgendaLaunch.parse(['--ajanda', 'durusma-1a2b'])!.uid,
        'durusma-1a2b',
      );
      expect(AgendaLaunch.parse(['--ajanda=sure-9f'])!.uid, 'sure-9f');
      final bare = AgendaLaunch.parse(['--ajanda']);
      expect(bare, isNotNull);
      expect(bare!.uid, isNull);
      expect(AgendaLaunch.parse(['belge.pdf']), isNull);
      expect(AgendaLaunch.parse([]), isNull);
      // Past `--` it is a document's name.
      expect(AgendaLaunch.parse(['--', '--ajanda']), isNull);
    });

    test('what is not a uid is not taken for one', () {
      expect(AgendaLaunch.parse(['--ajanda', '--quick-search'])!.uid, isNull);
      expect(AgendaLaunch.parse(['--ajanda', '/ev/a b.pdf'])!.uid, isNull);
      expect(AgendaLaunch.parse(['--ajanda', 'a;rm -rf'])!.uid, isNull);
    });

    test('forwarded to the open Folio as it came; the documents beside it '
        'are left for the documents', () {
      expect(AgendaLaunch.parse(['--ajanda', 'gorev-1'])!.arguments, [
        '--ajanda',
        'gorev-1',
      ]);
      expect(const AgendaLaunch().arguments, ['--ajanda']);
      expect(AgendaLaunch.without(['--ajanda', 'gorev-1', 'a.pdf']), ['a.pdf']);
      expect(AgendaLaunch.without(['a.pdf', '--ajanda']), ['a.pdf']);
      expect(AgendaLaunch.without(['--ajanda', '/ev/a.pdf']), ['/ev/a.pdf']);
      expect(AgendaLaunch.without(['--', '--ajanda']), ['--', '--ajanda']);
    });
  });

  group('a hearing told of', () {
    test('a day before and an hour before, each once; clicked, it opens as '
        '--ajanda does', () {
      final at = DateTime(2026, 10, 28, 10, 30);
      final db = agenda(hearings: [at]);
      final uid = LifeosAgenda.events(db, now).single['uid'];
      // More than a day before: nothing yet.
      expect(AgendaReminders.due(db, DateTime(2026, 10, 27, 10)), isEmpty);
      final day = AgendaReminders.due(db, DateTime(2026, 10, 27, 10, 30));
      expect(day.single.title, 'Yarın duruşma 10:30');
      expect(day.single.payload, 'ajanda:$uid');
      expect(AgendaReminders.due(db, DateTime(2026, 10, 28, 8)), isEmpty);
      final hour = AgendaReminders.due(db, DateTime(2026, 10, 28, 9, 30));
      expect(hour.single.title, '1 saat sonra duruşma 10:30');
      expect(hour.single.payload, 'ajanda:$uid');
      expect(AgendaReminders.due(db, DateTime(2026, 10, 28, 9, 45)), isEmpty);
      // Begun: not told of.
      expect(AgendaReminders.due(db, DateTime(2026, 10, 28, 10, 31)), isEmpty);
    });

    test('one added within the hour is told once, with the minutes left', () {
      final db = agenda(hearings: [DateTime(2026, 10, 27, 15)]);
      final told = AgendaReminders.due(db, now);
      expect(told.single.title, '40 dakika sonra duruşma 15:00');
      expect(AgendaReminders.due(db, now), isEmpty);
    });

    test('the next moment to tell is a day or an hour before', () {
      final db = agenda(hearings: [DateTime(2026, 10, 28, 10, 30)]);
      expect(
        AgendaReminders.nextHearing(db, now),
        DateTime(2026, 10, 28, 9, 30),
      );
      expect(
        AgendaReminders.nextHearing(db, DateTime(2026, 10, 27, 9)),
        DateTime(2026, 10, 27, 10, 30),
      );
      expect(
        AgendaReminders.nextHearing(db, DateTime(2026, 10, 28, 9, 31)),
        isNull,
      );
    });
  });
}

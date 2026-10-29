import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/portal/lifeos_agenda.dart';
import 'package:evrak_convert/services/portal/lifeos_inbox.dart';
import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// What LifeOS's Ajanda asks Folio to keep, left as files in a folder:
// kept once, tied to the case its number names, never a new case.
void main() {
  const number = '2026/470';
  const court = 'Manavgat 3. İş Mahkemesi';
  final now = DateTime(2026, 11, 3, 10, 41);
  late Directory dir;
  late Directory inbox;
  late PortalDatabase db;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lifeos-istek-');
    inbox = Directory(p.join(dir.path, 'folio-istek'))..createSync();
    db = PortalDatabase.memory();
    db.mergeCases(
      [PortalCase(key: caseKey(number, court), number: number, court: court)],
      portfolio: true,
      baseline: true,
    );
  });
  tearDown(() async {
    db.dispose();
    await dir.delete(recursive: true);
  });

  void ask(String id, Map<String, Object?> request) =>
      File(p.join(inbox.path, '$id.json')).writeAsStringSync(
        jsonEncode({'schema': 1, 'id': id, 'created': '…', ...request}),
      );

  Map<String, Object?> result(String id) => jsonDecode(
    File(p.join(inbox.path, 'islendi', '$id.json')).readAsStringSync(),
  ) as Map<String, Object?>;

  test('a task for a case: kept on that case, its uid told, the request '
      'moved with what came of it', () async {
    ask('a1', {
      'action': 'ekle',
      'kind': 'gorev',
      'title': 'Bilirkişi raporuna itiraz dilekçesi',
      'start': '2026-11-05',
      'allDay': true,
      'case': number,
      'court': court,
      'note': 'Süre 2 hafta',
    });
    expect(await LifeosInbox.process(db, inbox, now: now), 1);
    expect(File(p.join(inbox.path, 'a1.json')).existsSync(), isFalse);
    final kept = db.agenda().single;
    expect(kept.kind, 'task');
    expect(kept.title, 'Bilirkişi raporuna itiraz dilekçesi');
    expect(kept.body, 'Süre 2 hafta');
    expect(kept.at, DateTime(2026, 11, 5));
    expect(kept.allDay, isTrue);
    expect(kept.caseKey, caseKey(number, court));
    final told = result('a1');
    expect(told['result'], 'ok');
    // The uid it has in the agenda file.
    final events = LifeosAgenda.events(db, now);
    expect(told['uid'], events.single['uid']);
    expect(
      File(p.join(inbox.path, 'islendi', 'a1.json')).statSync().modeString(),
      'rw-------',
    );
  });

  test(
    'a deadline by the case number alone, when only one case has it',
    () async {
      ask('s1', {
        'action': 'ekle',
        'kind': 'sure',
        'title': 'İstinaf süresi',
        'start': '2026-11-12',
        'case': number,
      });
      await LifeosInbox.process(db, inbox, now: now);
      expect(result('s1')['result'], 'ok');
      expect(db.agenda().single.kind, 'deadline');
    },
  );

  test('an unknown case number, two cases with it, a hearing or a broken '
      'file: refused in Turkish, nothing kept, no case opened', () async {
    db.mergeCases(
      [
        PortalCase(
          key: caseKey('2026/9', 'A Mahkemesi'),
          number: '2026/9',
          court: 'A Mahkemesi',
        ),
        PortalCase(
          key: caseKey('2026/9', 'B Mahkemesi'),
          number: '2026/9',
          court: 'B Mahkemesi',
        ),
      ],
      portfolio: true,
      baseline: true,
    );
    ask('x1', {
      'action': 'ekle',
      'kind': 'gorev',
      'title': 'Dilekçe',
      'start': '2026-11-05',
      'case': '2025/1',
    });
    ask('x2', {
      'action': 'ekle',
      'kind': 'gorev',
      'title': 'Dilekçe',
      'start': '2026-11-05',
      'case': '2026/9',
    });
    ask('x3', {
      'action': 'ekle',
      'kind': 'durusma',
      'title': 'Duruşma',
      'start': '2026-11-05T10:00:00+03:00',
    });
    File(p.join(inbox.path, 'x4.json')).writeAsStringSync('{"schema": 1, ');
    final cases = db.cases().length;
    expect(await LifeosInbox.process(db, inbox, now: now), 4);
    for (final id in ['x1', 'x2', 'x3', 'x4']) {
      final told = result(id);
      expect(told['result'], 'hata', reason: id);
      expect(told['message'], isA<String>(), reason: id);
    }
    expect(result('x1')['message'], contains('2025/1'));
    expect(result('x2')['message'], contains('birden çok'));
    expect(db.agenda(), isEmpty);
    expect(db.cases().length, cases);
  });

  test(
    'kept once: a second Folio, or the same again, keeps nothing more',
    () async {
      ask('d1', {
        'action': 'ekle',
        'kind': 'gorev',
        'title': 'Tebligat',
        'start': '2026-11-05',
      });
      // Two at once, as an open Folio and `--ajanda-yaz` would.
      final both = await Future.wait([
        LifeosInbox.process(db, inbox, now: now),
        LifeosInbox.process(db, inbox, now: now),
      ]);
      expect(both.reduce((a, b) => a + b), 1);
      expect(await LifeosInbox.process(db, inbox, now: now), 0);
      // The same request left again after it was kept.
      ask('d1', {
        'action': 'ekle',
        'kind': 'gorev',
        'title': 'Tebligat',
        'start': '2026-11-05',
      });
      await LifeosInbox.process(db, inbox, now: now);
      expect(db.agenda(), hasLength(1));
      expect(File(p.join(inbox.path, 'd1.json')).existsSync(), isFalse);
    },
  );

  test('a task marked done from the agenda is done in Folio', () async {
    ask('e1', {
      'action': 'ekle',
      'kind': 'gorev',
      'title': 'Vekaletname',
      'start': '2026-11-05',
    });
    await LifeosInbox.process(db, inbox, now: now);
    final uid = result('e1')['uid'];
    ask('b1', {'action': 'bitti', 'uid': uid});
    ask('b2', {'action': 'bitti', 'uid': 'gorev-0000000000000000'});
    await LifeosInbox.process(db, inbox, now: now);
    expect(result('b1')['result'], 'ok');
    expect(db.agenda().single.done, isTrue);
    expect(result('b2')['result'], 'hata');
    expect(LifeosAgenda.events(db, now).single['done'], isTrue);
  });

  test(
    'the writer keeps what was asked first and writes the file at once',
    () async {
      final file = File(p.join(dir.path, 'folio-ajanda.json'));
      final writer = LifeosAgendaWriter(
        database: () async => db,
        target: file,
        inbox: inbox,
        idsFile: File(p.join(dir.path, 'kimlik.json')),
        now: () => now,
      );
      addTearDown(writer.dispose);
      expect(await writer.check(), isTrue);
      expect(await writer.check(), isFalse);
      ask('w1', {
        'action': 'ekle',
        'kind': 'gorev',
        'title': 'Keşif',
        'start': '2026-11-06',
        'case': number,
      });
      expect(await writer.check(), isTrue);
      final doc = jsonDecode(file.readAsStringSync()) as Map;
      final events = (doc['events'] as List).cast<Map>();
      expect(events.single['title'], 'Keşif');
      expect(events.single['uid'], result('w1')['uid']);
      expect(File(p.join(dir.path, 'kimlik.json')).existsSync(), isTrue);
    },
  );

  test('the folder: beside the agenda file, under XDG_DATA_HOME', () {
    expect(
      LifeosInbox.folder({'HOME': '/home/a'})!.path,
      '/home/a/.local/share/lifeos/folio-istek',
    );
    expect(
      LifeosInbox.folder({'XDG_DATA_HOME': '/v', 'HOME': '/home/a'})!.path,
      '/v/lifeos/folio-istek',
    );
  });
}

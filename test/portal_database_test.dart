import 'dart:io';

import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_hearing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const web = PortalChannel.uyapWeb;
  const mobile = PortalChannel.uyapMobile;
  const court = 'Antalya 3. Asliye Hukuk Mahkemesi';
  final asked = DateTime.utc(2026, 10, 6, 8);
  final from = DateTime(2026, 10, 5);
  final to = DateTime(2026, 11, 3);

  late PortalDatabase db;
  setUp(() => db = PortalDatabase.memory());
  tearDown(() => db.dispose());

  PortalHearing hearing(
    DateTime at,
    PortalChannel channel, {
    String? kind,
    bool complete = true,
  }) => PortalHearing.create(
    number: '2025/412',
    court: court,
    at: at,
    channel: channel,
    id: '${channel.name}-${at.day}',
    kind: kind == null
        ? null
        : Observed(kind, channel, asked, complete: complete),
  );

  test('the two portals’ cases merge in the database', () {
    db.mergeCases([
      PortalCase(
        key: caseKey('2025/412', court),
        number: '2025/412',
        court: court,
        parties: Observed(
          [
            {'ad': 'Ayşe K.'},
            {'ad': 'B. Ltd.'},
          ],
          web,
          asked,
        ),
      ),
    ]);
    db.mergeCases([
      PortalCase(
        key: caseKey('2025/412', court),
        number: '2025/412',
        court: court,
        status: Observed('açık', mobile, asked),
        parties: Observed(
          [
            {'ad': 'Ayşe K.'},
          ],
          mobile,
          asked.add(const Duration(hours: 1)),
          complete: false,
        ),
      ),
    ]);
    final one = db.cases().values.single;
    expect(one.parties!.value, hasLength(2));
    expect(one.status!.value, 'açık');
  });

  test('the mobile API’s generic kind does not replace the web’s own', () {
    final at = DateTime(2026, 10, 6, 9, 20);
    db.mergeHearings(web, from, to, [
      hearing(at, web, kind: 'Ön inceleme duruşması'),
    ], complete: true);
    db.mergeHearings(mobile, from, to, [
      hearing(at, mobile, kind: 'Duruşma', complete: false),
    ], complete: true);
    final one = db.hearings().single;
    expect(one.kind!.value, 'Ön inceleme duruşması');
    expect(one.ids.keys, containsAll([web, mobile]));
  });

  test('only a complete web answer removes a hearing it no longer lists', () {
    final old = DateTime(2026, 10, 6, 9, 20);
    final moved = DateTime(2026, 10, 20, 10);
    db.mergeHearings(web, from, to, [hearing(old, web)], complete: true);

    // The mobile API reports the new time: the old one stays.
    db.mergeHearings(mobile, from, to, [
      hearing(moved, mobile),
    ], complete: true);
    expect(db.hearings(), hasLength(2));

    // A web answer with a window missing does not remove it either.
    db.mergeHearings(web, from, to, [hearing(moved, web)], complete: false);
    expect(db.hearings(), hasLength(2));

    // A complete web answer does.
    db.mergeHearings(web, from, to, [hearing(moved, web)], complete: true);
    expect(db.hearings().single.at, moved);
  });

  test('an empty web answer removes nothing', () {
    db.mergeHearings(web, from, to, [
      hearing(DateTime(2026, 10, 6, 9), web),
    ], complete: true);
    db.mergeHearings(web, from, to, [], complete: true);
    expect(db.hearings(), hasLength(1));
  });

  test('the agenda’s notes are the lawyer’s, apart from the portals', () {
    final note = AgendaItem(
      id: AgendaItem.newId(),
      kind: 'task',
      title: 'Bilirkişi raporuna itiraz taslağı',
      at: DateTime(2026, 10, 6, 11, 30),
      caseKey: caseKey('2025/412', court),
      updated: DateTime(2026, 10, 6),
    );
    db.saveAgenda(note);
    db.mergeHearings(web, from, to, [
      hearing(DateTime(2026, 10, 6, 9), web),
    ], complete: true);
    db.saveAgenda(note.copyWith(done: true));
    final kept = db.agenda(from: from, to: to).single;
    expect(kept.title, note.title);
    expect(kept.done, isTrue);
    db.removeAgenda(note.id);
    expect(db.agenda(), isEmpty);
  });

  test('what is kept survives closing the file', () {
    final dir = Directory.systemTemp.createTempSync('folio-portal-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/portal.sqlite';
    final first = PortalDatabase.open(path);
    first.mergeHearings(web, from, to, [
      hearing(DateTime(2026, 10, 6, 9), web, kind: 'Duruşma'),
    ], complete: true);
    first.dispose();
    final again = PortalDatabase.open(path);
    addTearDown(again.dispose);
    expect(again.hearings().single.kind!.value, 'Duruşma');
  });
}

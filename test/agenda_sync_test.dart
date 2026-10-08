import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_deadline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AgendaItem note(String id, String title, DateTime updated) =>
      AgendaItem(id: id, kind: 'note', title: title, updated: updated);

  test('one person’s agendas: the newer of each, and what was taken off', () {
    final pc = PortalDatabase.memory(), phone = PortalDatabase.memory();
    addTearDown(pc.dispose);
    addTearDown(phone.dispose);
    final t0 = DateTime(2026, 10, 1, 9);
    pc.saveAgenda(note('a', 'Bilirkişi raporu', t0));
    pc.saveAgenda(note('b', 'Müvekkili ara', t0));
    phone.saveAgenda(note('c', 'Harç yatır', t0));
    expect(phone.agendaMerge(pc.agendaExport()), isTrue);
    expect(pc.agendaMerge(phone.agendaExport()), isTrue);
    List<String> titles(PortalDatabase db) =>
        [for (final i in db.agenda()) i.title]..sort();
    expect(titles(pc), ['Bilirkişi raporu', 'Harç yatır', 'Müvekkili ara']);
    expect(titles(phone), titles(pc));
    // Changed on the phone later, taken off on the computer: the newer wins.
    phone.saveAgenda(
      note('a', 'Bilirkişi raporuna itiraz', t0.add(const Duration(hours: 1))),
    );
    pc.removeAgenda('b');
    expect(pc.agendaMerge(phone.agendaExport()), isTrue);
    expect(phone.agendaMerge(pc.agendaExport()), isTrue);
    expect(titles(pc), ['Bilirkişi raporuna itiraz', 'Harç yatır']);
    expect(titles(phone), titles(pc));
    // Nothing new: nothing changes.
    expect(pc.agendaMerge(phone.agendaExport()), isFalse);
    // A deadline marked done on one is marked on the other.
    pc.saveDeadlineUser(const DeadlineUser(deadlineId: 'd1', done: true));
    expect(phone.agendaMerge(pc.agendaExport()), isTrue);
    final kept = (phone.agendaExport()['kararlar'] as List).single as Map;
    expect((kept['deadline_id'], kept['done']), ('d1', 1));
  });

  test('the agenda tells of the lawyer’s changes, not of what came', () {
    final db = PortalDatabase.memory(), other = PortalDatabase.memory();
    addTearDown(db.dispose);
    addTearDown(other.dispose);
    var told = 0;
    PortalDatabase.changed = () => told++;
    addTearDown(() => PortalDatabase.changed = null);
    db.saveAgenda(note('a', 'Not', DateTime(2026)));
    db.removeAgenda('a');
    expect(told, 2);
    other.agendaMerge(db.agendaExport());
    expect(told, 2);
  });
}

import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PortalDatabase db;
  setUp(() => db = PortalDatabase.memory());
  tearDown(() => db.dispose());

  ClientRecord meeting(String id, String client, {bool locked = false}) =>
      ClientRecord(
        id: id,
        clientId: client,
        kind: ClientRecordKind.meeting,
        data: const {'kararlar': 'İki tanık bildirilecek.'},
        created: DateTime(2026, 10, 6, 14, 10, 5),
        by: 'Av. Deniz Kaya',
        updated: DateTime(2026, 10, 6, 14, 40),
        locked: locked,
      );

  test('the parties the lawyer acts for are clients, one for every way '
      'their name is written; a card takes in the names it is told', () {
    db.setRepresentation('a', const [(ad: 'AYŞE KARACA', rol: 'Davacı')]);
    db.setRepresentation('b', const [(ad: 'Ayşe Karaca', rol: 'Davacı')]);
    db.saveCaseParties('c', const [
      UyapParty('A. KARACA', 'Davalı', 'Av. Deniz Kaya', 'Kişi'),
      UyapParty('B. LTD.', 'Davacı', 'Av. Murat Er', 'Kurum'),
    ], source: 'uyap');
    final seen = db.clientEntries(lawyer: 'Av. Deniz Kaya');
    expect(seen.map((e) => e.name), ['A. KARACA', 'AYŞE KARACA']);
    expect(seen.last.cases.map((c) => c.caseKey), ['a', 'b']);
    expect(seen.last.client, isNull);

    final card = Client(
      id: 'k1',
      name: 'Ayşe Karaca',
      names: [UyapWebService.fold('A. KARACA')],
      phone: '0532',
      updated: DateTime(2026, 10, 8),
    );
    db.saveClient(card);
    final one = db.clientEntries(lawyer: 'Av. Deniz Kaya').single;
    expect(one.client!.phone, '0532');
    expect(one.cases.map((c) => (c.caseKey, c.role)), [
      ('a', 'Davacı'),
      ('b', 'Davacı'),
      ('c', 'Davalı'),
    ]);
  });

  test('signed minutes are not written over, here or from another device; '
      'the newer of the rest wins', () {
    db.saveClientRecord(meeting('g1', 'k1', locked: true));
    expect(
      db.saveClientRecord(
        meeting('g1', 'k1').copyWith(data: {'kararlar': 'x'}),
      ),
      isFalse,
    );
    final phone = PortalDatabase.memory();
    addTearDown(phone.dispose);
    phone.saveClient(
      Client(id: 'k1', name: 'Ayşe Karaca', updated: DateTime(2026, 10, 8)),
    );
    phone.saveClientRecord(meeting('g2', 'k1'));
    expect(phone.agendaMerge(db.agendaExport()), isTrue);
    expect(phone.clientRecord('g1')!.locked, isTrue);
    // Written over on the phone, a locked one comes back as it was signed.
    final forged = db.agendaExport();
    (forged['muvekkilKayitlari'] as List).cast<Map>().single['veri'] = {
      'kararlar': 'değişti',
    };
    expect(phone.clientsMerge(forged), isFalse);
    expect(
      phone.clientRecord('g1')!.text('kararlar'),
      'İki tanık bildirilecek.',
    );

    expect(db.agendaMerge(phone.agendaExport()), isTrue);
    expect(db.clientCard('k1')!.name, 'Ayşe Karaca');
    expect(
      db.clientRecords('k1', kind: ClientRecordKind.meeting).map((r) => r.id),
      containsAll(['g1', 'g2']),
    );
    // Its time of writing, to the second, kept.
    expect(db.clientRecord('g2')!.created, DateTime(2026, 10, 6, 14, 10, 5));
  });

  test('a name written another way is offered, not merged; merged, its '
      'cases and records are the card\'s', () {
    db.setRepresentation('a', const [(ad: 'AYŞE KARACA', rol: 'Davacı')]);
    db.setRepresentation('b', const [(ad: 'A. KARACA', rol: 'Davalı')]);
    db.setRepresentation('c', const [(ad: 'MEHMET KARACA', rol: 'Davacı')]);
    db.setRepresentation('d', const [(ad: 'KARACA LTD. ŞTİ.', rol: 'Davacı')]);
    final all = db.clientEntries();
    ClientEntry named(String n) => all.firstWhere((e) => e.name == n);
    expect(db.clientLookalikes(named('AYŞE KARACA'), all).map((e) => e.name), [
      'A. KARACA',
    ]);
    expect(db.clientLookalikes(named('KARACA LTD. ŞTİ.'), all), isEmpty);
    final card = Client(id: 'k1', name: 'AYŞE KARACA', updated: DateTime(2026));
    db.saveClient(card);
    db.mergeClients(card, named('A. KARACA'));
    final after = db.clientEntries();
    expect(after.map((e) => e.name), isNot(contains('A. KARACA')));
    expect(after.firstWhere((e) => e.key == 'k1').cases.map((c) => c.caseKey), [
      'a',
      'b',
    ]);
  });

  test('a name UYAP shortened names no client, nor takes a whole one\'s '
      'place; a whole one takes its place from any source', () {
    expect(isShortenedName('A** E**'), isTrue);
    expect(isShortenedName('A.. E..'), isTrue);
    expect(isShortenedName('Ayşe Karaca'), isFalse);
    db.saveCaseParties('c', const [
      UyapParty('A** K**', 'Davacı', 'Av. Deniz Kaya', 'Kişi'),
    ], source: 'taraflar');
    expect(db.clientEntries(lawyer: 'Av. Deniz Kaya'), isEmpty);
    db.saveCaseParties('c', const [
      UyapParty('AYŞE KARACA', 'Davacı', 'Av. Deniz Kaya', 'Kişi'),
    ], source: 'paket');
    expect(
      db.clientEntries(lawyer: 'Av. Deniz Kaya').single.name,
      'AYŞE KARACA',
    );
    db.saveCaseParties('c', const [
      UyapParty('A** K**', 'Davacı', 'Av. Deniz Kaya', 'Kişi'),
    ], source: 'uyap');
    expect(
      db.clientEntries(lawyer: 'Av. Deniz Kaya').single.name,
      'AYŞE KARACA',
    );
  });
}

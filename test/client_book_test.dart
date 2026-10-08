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
}

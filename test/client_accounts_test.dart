import 'package:evrak_convert/services/clients/client.dart';

import 'dart:io';

import 'package:evrak_convert/services/clients/client_accounts.dart';
import 'package:evrak_convert/services/clients/client_file_sync.dart';
import 'package:evrak_convert/services/clients/client_files.dart';
import 'package:evrak_convert/ui/clients/attachment_preview.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:flutter_test/flutter_test.dart';

ClientRecord move(
  String id,
  String caseKey,
  MovementKind kind,
  int lira, {
  String reverses = '',
  String client = 'k1',
  String person = '',
}) => ClientRecord(
  id: id,
  clientId: client,
  kind: ClientRecordKind.movement,
  data: {
    'dosya': caseKey,
    'hesap': kind.code,
    'tutar': lira * 100,
    'zaman': DateTime(2026, 6, 14, 14, 22).toIso8601String(),
    if (reverses.isNotEmpty) 'ters': reverses,
  },
  created: DateTime(2026, 6, 14, 14, 23, 5),
  by: 'Av. Deniz Kaya',
  updated: DateTime(2026, 6, 14, 14, 23, 5),
  person: person,
);

ClientRecord fee(String caseKey, int lira, List<(DateTime, int)> plan) =>
    ClientRecord(
      id: 'f-$caseKey',
      clientId: 'k1',
      kind: ClientRecordKind.fee,
      data: {
        'dosya': caseKey,
        'tutar': lira * 100,
        'taksitler': [
          for (final (d, t) in plan)
            {'tarih': d.toIso8601String(), 'tutar': t * 100},
        ],
      },
      created: DateTime(2026, 3, 12),
      by: 'Av. Deniz Kaya',
      updated: DateTime(2026, 3, 12),
    );

void main() {
  test('each case keeps its own fee, advance and the lawyer\'s costs; one '
      'taken back by another counts for nothing', () {
    final a = caseAccounts([
      fee('a', 45000, [
        (DateTime(2026, 3, 12), 15000),
        (DateTime(2026, 6, 12), 15000),
        (DateTime(2026, 10, 3), 15000),
      ]),
      move('1', 'a', MovementKind.feePaid, 15000),
      move('2', 'a', MovementKind.feePaid, 15000),
      move('3', 'a', MovementKind.advanceIn, 5000),
      move('4', 'a', MovementKind.costFromAdvance, 2500),
      move('5', 'b', MovementKind.advanceIn, 1600),
      move('6', 'b', MovementKind.costFromAdvance, 980),
      move('7', 'b', MovementKind.costByLawyer, 1250),
      move('8', 'b', MovementKind.feePaid, 999),
      move('9', 'b', MovementKind.feePaid, 999, reverses: '8'),
    ]);
    expect(a['a']!.feeOwed, 1500000);
    expect(a['a']!.advanceLeft, 250000);
    expect(a['b']!.advanceLeft, 62000);
    expect(a['b']!.lawyerOwed, 125000);
    expect(a['b']!.feeIn, 0);
    expect(a['b']!.reversed, {'8'});
    final plan = a['a']!.instalments(DateTime(2026, 10, 8));
    expect(plan.map((t) => (t.paid, t.late)), [
      (true, false),
      (true, false),
      (false, true),
    ]);
    expect(lira(1250050), '12.500,50 TL');
    expect(kurusOf('12.500 TL'), 1250000);
    expect(kurusOf('12.500'), 1250000);
    expect(kurusOf('980,5'), 98050);
  });

  test('a movement written is never changed, here or from another device', () {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    db.saveClientRecord(move('1', 'a', MovementKind.feePaid, 100));
    expect(db.clientRecord('1')!.locked, isTrue);
    expect(
      db.saveClientRecord(
        move('1', 'a', MovementKind.feePaid, 1).copyWith(locked: false),
      ),
      isFalse,
    );
    expect(db.clientRecord('1')!.amount, 10000);
  });

  group('the office, a client at a time', () {
    late PortalDatabase mine, theirs;
    setUp(() {
      mine = PortalDatabase.memory();
      theirs = PortalDatabase.memory();
    });
    tearDown(() {
      mine.dispose();
      theirs.dispose();
    });

    Client card(String id, {bool office = false}) => Client(
      id: id,
      name: 'Ayşe Karaca $id',
      updated: DateTime.now(),
      person: 'deniz',
    ).copyWith(office: office);

    test('only a client shared goes, its money only to one who may see it; '
        'unshared, the others forget it but what they wrote', () {
      mine.saveClient(card('k1', office: true));
      mine.saveClient(card('k2'));
      mine.saveClientRecord(
        ClientRecord(
          id: 'g1',
          clientId: 'k1',
          kind: ClientRecordKind.meeting,
          data: const {'kararlar': 'x'},
          created: DateTime(2026),
          by: 'Av. Deniz Kaya',
          updated: DateTime(2026),
          person: 'deniz',
        ),
      );
      mine.saveClientRecord(
        move('m1', 'a', MovementKind.feePaid, 100, person: 'deniz'),
      );
      mine.saveClientRecord(
        move('m2', 'a', MovementKind.feePaid, 100, client: 'k2'),
      );

      final none = mine.clientsOfficeExport(money: false);
      expect((none['muvekkiller'] as List).length, 1);
      expect(
        [for (final r in none['muvekkilKayitlari'] as List) (r as Map)['id']],
        ['g1'],
      );
      // A forged money record, from one who may not see it, is not taken.
      theirs.clientsOfficeMerge(
        mine.clientsOfficeExport(money: true),
        money: false,
        me: 'selin',
      );
      expect(theirs.clientRecord('g1'), isNotNull);
      expect(theirs.clientRecord('m1'), isNull);
      expect(theirs.clientCard('k2'), isNull);

      theirs.clientsOfficeMerge(
        mine.clientsOfficeExport(money: true),
        money: true,
        me: 'selin',
      );
      expect(theirs.clientRecord('m1'), isNotNull);
      theirs.saveClientRecord(
        ClientRecord(
          id: 'g2',
          clientId: 'k1',
          kind: ClientRecordKind.meeting,
          data: const {'kararlar': 'Selin yazdı'},
          created: DateTime(2026, 2),
          by: 'Av. Selin Aksoy',
          updated: DateTime(2026, 2),
          person: 'selin',
        ),
      );

      // Unshared: gone from there, but for Selin's own minutes.
      mine.saveClient(mine.clientCard('k1')!.copyWith(office: false));
      expect(
        theirs.clientsOfficeMerge(
          mine.clientsOfficeExport(money: true),
          money: true,
          me: 'selin',
        ),
        isTrue,
      );
      expect(theirs.clientCard('k1'), isNull);
      expect(theirs.clientRecord('g1'), isNull);
      expect(theirs.clientRecord('m1'), isNull);
      expect(theirs.clientRecord('g2'), isNotNull);
    });
  });

  test('a scan comes to the device that has not got it, in pieces, and is '
      'kept only when its digest is its own; a PDF scan is shown as it is, '
      'a picture as a page', () async {
    final root = Directory.systemTemp.createTempSync('folio_ek_');
    addTearDown(() => root.deleteSync(recursive: true));
    final a = PortalDatabase.memory(), b = PortalDatabase.memory();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final filesA = ClientFiles(root: () async => Directory('${root.path}/a'));
    final filesB = ClientFiles(root: () async => Directory('${root.path}/b'));
    final source = File('${root.path}/vekalet.pdf')
      ..writeAsBytesSync([
        ...'%PDF-1.4'.codeUnits,
        for (var i = 0; i < 1300000; i++) i % 251,
      ]);
    final kept = await filesA.keep('k1', source.path);
    final record = ClientRecord(
      id: 'v1',
      clientId: 'k1',
      kind: ClientRecordKind.attorney,
      data: {
        'ekler': [clientFileJson(kept)],
      },
      created: DateTime(2026),
      by: 'Av. Deniz Kaya',
      updated: DateTime(2026),
    );
    a.saveClientRecord(record);
    b.saveClientRecord(record);
    final sender = ClientFileSync(db: a, files: filesA);
    var asks = 0;
    final brought = await ClientFileSync(db: b, files: filesB).fetchMissing((
      body,
    ) {
      asks++;
      return sender.answer(body, may: (_) => true);
    });
    expect(brought, 1);
    expect(asks, 3);
    final there = await filesB.locate('k1', kept);
    expect(there!.lengthSync(), source.lengthSync());
    // One that may not have it is given nothing.
    expect(
      await sender.answer({'sha256': kept.sha256}, may: (_) => false),
      isNull,
    );
    expect(await attachmentPdf(there), there.readAsBytesSync());
  });
}

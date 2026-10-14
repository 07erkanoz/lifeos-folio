// How long the enforcement tab's reading takes on a large database: a
// measurement, not part of the test suite.
//
//   systemd-run --user --scope -p MemoryMax=4G \
//     flutter test tool/measure_enforcement_test.dart
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/clients/client_accounts.dart';
import 'package:evrak_convert/services/enforcement/enforcement_ledger.dart';
import 'package:evrak_convert/services/enforcement/ledger_service.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/ui/portfolio/enforcement_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// The tab's reading as it was before: every record read again for each
/// payment.
({Set<String> booked, int ledger, Map<String, Object?> bookings}) before(
  PortalDatabase db,
  String caseKey,
) {
  ({List<ClientRecord> held, List<ClientRecord> applied}) movementsOf(
    LedgerEntry e,
  ) {
    final records = db.allClientRecords().toList();
    final reversed = {
      for (final r in records)
        if (r.text('ters').isNotEmpty) r.text('ters'),
    };
    bool standing(ClientRecord r) =>
        !r.removed &&
        r.kind == ClientRecordKind.movement &&
        !reversed.contains(r.id);
    final held = [
      for (final r in records)
        if (standing(r) && r.text('kaynak') == 'icra:${e.id}') r,
    ];
    final applied = [
      for (final r in records)
        if (standing(r) &&
            held.any((m) => r.text('kaynak') == 'mahsup:${m.id}'))
          r,
    ];
    return (held: held, applied: applied);
  }

  final booked = {
    for (final r in db.allClientRecords())
      if (r.kind == ClientRecordKind.movement && !r.removed)
        if (r.text('kaynak').isNotEmpty) r.text('kaynak'),
  };
  final ledger = [
    for (final r in db.allClientRecords())
      if (!r.removed &&
          r.kind == ClientRecordKind.enforcement &&
          r.text('dosya') == caseKey)
        LedgerEntry(r),
  ];
  final bookings = {
    for (final e in ledger)
      if (movementsOf(e) case (:final held, :final applied))
        e.id: (
          booked: held.isNotEmpty,
          target: applied.isEmpty
              ? null
              : MovementKind.of(applied.first.data['hesap']),
        ),
  };
  return (booked: booked, ledger: ledger.length, bookings: bookings);
}

void main() {
  test('the enforcement tab on 5,000 records, 20 payments in the case', () {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    final person = PortalDatabase.clientPerson;
    addTearDown(() => PortalDatabase.clientPerson = person);
    PortalDatabase.clientPerson = () => 'deniz';
    final day = DateTime(2026, 10, 1);
    // Other clients' records: meetings, movements, enforcement payments.
    for (var i = 0; i < 4700; i++) {
      final client = 'k${i % 200}';
      db.putRecordForTesting(
        ClientRecord(
          id: 'r$i',
          clientId: client,
          kind: switch (i % 3) {
            0 => ClientRecordKind.meeting,
            1 => ClientRecordKind.movement,
            _ => ClientRecordKind.fee,
          },
          data: {
            'dosya': 'dosya${i % 400}',
            'hesap': MovementKind.feePaid.code,
            'tutar': 10000 + i,
            'zaman': day.toIso8601String(),
            'konusulanlar': 'Görüşme notu ' * 20,
          },
          created: day,
          by: 'Av. Deniz Kaya',
          updated: day,
          person: 'deniz',
          locked: true,
        ),
      );
    }
    final book = LedgerService(db);
    for (var i = 0; i < 280; i++) {
      book.add(
        clientId: 'k${i % 200}',
        caseKey: i < 20 ? 'dava' : 'icra$i',
        kind: 'haricen',
        amount: 100000 + i,
        at: day,
        by: 'Av. Deniz Kaya',
        person: 'deniz',
        target: i.isEven ? MovementKind.toFee : null,
      );
    }
    final total = db.allClientRecords().length;

    Duration time(void Function() f, {int runs = 5}) {
      f();
      final watch = Stopwatch()..start();
      for (var i = 0; i < runs; i++) {
        f();
      }
      return watch.elapsed ~/ runs;
    }

    final old = before(db, 'dava');
    final now = readEnforcementBooks(db, 'dava', const []);
    // The same answer.
    expect(now.ledger.length, old.ledger);
    expect(now.bookings, old.bookings);
    expect(now.booked, old.booked);
    final was = time(() => before(db, 'dava'));
    final is_ = time(() => readEnforcementBooks(db, 'dava', const []));
    // ignore: avoid_print
    print(
      'Kayıt: $total · dosyada ödeme: ${old.ledger} · '
      'önce: ${was.inMilliseconds} ms · sonra: ${is_.inMilliseconds} ms',
    );
  });
}

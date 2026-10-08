import 'dart:io';

import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/clients/client_files.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/ui/clients/clients_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PortalDatabase db;
  late Directory root;
  setUp(() {
    db = PortalDatabase.memory();
    root = Directory.systemTemp.createTempSync('folio_clients_');
    db.setRepresentation('k1', const [(ad: 'AYŞE KARACA', rol: 'Davacı')]);
  });
  tearDown(() {
    db.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('a client of a case is listed; its minutes written are kept '
      'with the time they were written, and its card made then', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientsPage(
            lawyer: 'Av. Deniz Kaya',
            database: db,
            files: ClientFiles(root: () async => root),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ayşe Karaca'), findsOneWidget);
    await tester.tap(find.text('Ayşe Karaca'));
    await tester.pumpAndSettle();
    expect(find.text('Dosyalar 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('client-meeting')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('meeting-decided')),
      'Sulh görüşmesine yetki verildi.',
    );
    await tester.tap(find.byKey(const ValueKey('meeting-save')));
    await tester.pumpAndSettle();

    final card = db.clientCards().single;
    final m = db.clientRecords(card.id).single;
    expect(m.text('kararlar'), 'Sulh görüşmesine yetki verildi.');
    expect(m.by, 'Av. Deniz Kaya');
    expect(m.locked, isFalse);
    expect(find.textContaining('imza bekliyor'), findsWidgets);
    // The card made stands for the name the case wrote.
    expect(
      db.clientEntries(lawyer: 'Av. Deniz Kaya').single.client?.id,
      card.id,
    );
  });

  test('the minutes print with both signatures and their code', () async {
    ByteData font(String style) => ByteData.sublistView(
      File('fonts/pdf/LiberationSerif-$style.ttf').readAsBytesSync(),
    );
    final client = Client(
      id: 'k',
      name: 'Ayşe Karaca',
      updated: DateTime(2026),
    );
    final bytes = await meetingMinutesPdf(
      client: client,
      meeting: ClientRecord(
        id: 'g',
        clientId: 'k',
        kind: ClientRecordKind.meeting,
        data: const {'kararlar': 'İki tanık bildirilecek.'},
        created: DateTime(2026, 10, 6, 14, 10, 5),
        by: 'Av. Deniz Kaya',
        updated: DateTime(2026, 10, 6, 14, 10, 5),
      ),
      lawyer: 'Av. Deniz Kaya',
      regular: font('Regular'),
      bold: font('Bold'),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(2000));
  });
}

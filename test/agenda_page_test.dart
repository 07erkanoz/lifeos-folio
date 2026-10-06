import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_hearing.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/agenda/agenda_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const court = 'Antalya 3. Asliye Hukuk Mahkemesi';
  final now = DateTime(2026, 10, 6, 7, 20);

  Future<PortalDatabase> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    final asked = DateTime.utc(2026, 10, 6);
    db.mergeHearings(
      PortalChannel.uyapWeb,
      DateTime(2026, 9, 6),
      DateTime(2026, 12, 5),
      [
        PortalHearing.create(
          number: '2025/412',
          court: court,
          at: DateTime(2026, 10, 6, 9, 20),
          channel: PortalChannel.uyapWeb,
          id: '1',
          kind: Observed('Ön inceleme duruşması', PortalChannel.uyapWeb, asked),
          parties: Observed(
            [
              {'adi': 'Ayşe K.'},
              {'adi': 'B. İnşaat Ltd.'},
            ],
            PortalChannel.uyapWeb,
            asked,
          ),
        ),
      ],
      complete: true,
    );
    db.saveAgenda(
      AgendaItem(
        id: 'd1',
        kind: 'deadline',
        title: 'İstinaf süresi son gün',
        at: DateTime(2026, 10, 7),
        allDay: true,
        updated: now,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaPage(
            database: db,
            web: UyapWebService.forTesting(),
            now: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  testWidgets('the week shows the hearing and its preparation card', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Ajanda'), findsOneWidget);
    expect(find.text('09:20 Duruşma'), findsOneWidget);
    expect(find.text('⏱ İstinaf süresi son gün'), findsOneWidget);
    final prep = find.byKey(const ValueKey('agenda-prep'));
    expect(
      find.descendant(of: prep, matching: find.text(court)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: prep,
        matching: find.text('Ayşe K. — B. İnşaat Ltd.'),
      ),
      findsOneWidget,
    );
    expect(find.text('BUGÜN 09:20 · DURUŞMA · 2 SA SONRA'), findsOneWidget);
    // The deadline in the card of what is coming.
    expect(find.text('İstinaf süresi son gün'), findsOneWidget);
    expect(find.text('UYAP Web · bağlı değil'), findsOneWidget);
  });

  testWidgets('a task added to the hearing is kept and shown in its card', (
    tester,
  ) async {
    final db = await pump(tester);
    await tester.tap(find.text('İş ekle'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('agenda-title')),
      'Tanık listesini hazırla',
    );
    await tester.tap(find.byKey(const ValueKey('agenda-save')));
    await tester.pumpAndSettle();
    final saved = db.agenda().where((i) => i.kind == 'task').single;
    expect(saved.hearingKey, isNotNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('agenda-prep')),
        matching: find.text('Tanık listesini hazırla'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the list shows what is coming, day by day', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('agenda-view-list')));
    await tester.pumpAndSettle();
    expect(find.text('6 Ekim Salı'), findsOneWidget);
    expect(find.text('7 Ekim Çarşamba'), findsOneWidget);
  });
}

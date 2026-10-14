import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_hearing.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/agenda/agenda_page.dart';
import 'package:evrak_convert/ui/widgets/secret_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// docs/senkron-plan.md §5 step 6, the screens approved: the secret note's
/// switch, its mark, the asking before one shared is made secret, and how
/// far it was taken back.
void main() {
  const court = 'Antalya 3. Asliye Hukuk Mahkemesi';
  final now = DateTime(2026, 10, 6, 7, 20);

  Future<PortalDatabase> pump(
    WidgetTester tester, {
    void Function(PortalDatabase db)? before,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
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
          kind: Observed(
            'Ön inceleme duruşması',
            PortalChannel.uyapWeb,
            DateTime.utc(2026, 10, 6),
          ),
        ),
      ],
      complete: true,
    );
    before?.call(db);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaPage(
            database: db,
            sync: PortalSync(
              web: UyapWebService.forTesting(),
              mobile: UyapMobileApi.forTesting(
                Uri.parse('http://127.0.0.1:9/'),
              ),
              database: () async => db,
            ),
            now: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  testWidgets('a task added secret is kept secret and marked; held by a '
      'colleague, made secret again asks first and says how far it was '
      'taken back', (tester) async {
    final db = await pump(tester);
    await tester.tap(find.text('İş ekle'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('agenda-title')),
      'Uzlaşma sınırını konuş',
    );
    // Off at first.
    final toggle = find.byKey(const ValueKey('secret-note-switch'));
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(find.text('Gizli not · büroyla paylaşılmaz'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-save')));
    await tester.pumpAndSettle();
    final saved = db.agenda().where((i) => i.kind == 'task').single;
    expect(saved.secret, isTrue);
    expect(find.byType(SecretNoteMark), findsOneWidget);
  });

  testWidgets('a note a colleague holds, made secret: asked first, then how '
      'far it was taken back', (tester) async {
    final db = await pump(
      tester,
      before: (db) {
        final hearing = db.hearings().single;
        db.saveAgenda(
          AgendaItem(
            id: 'n1',
            kind: 'task',
            title: 'Uzlaşma sınırını konuş',
            caseKey: hearing.caseKey,
            hearingKey: hearing.key,
            updated: now,
          ),
        );
        db.recordHold('ajanda:n1', 'b1', 'selin', 'gorev:t1|k');
      },
    );
    await tester.longPress(find.text('Uzlaşma sınırını konuş').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('secret-note-switch')).last);
    await tester.pumpAndSettle();
    expect(find.text('Not büroyla paylaşılmıştı'), findsOneWidget);
    expect(find.textContaining('Dışarı aktarılmış belge'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('secret-note-confirm')));
    await tester.pumpAndSettle();
    expect(db.agenda().where((i) => i.id == 'n1').single.secret, isTrue);
    expect(
      find.textContaining('Geri çekildi: 0/1 kişide · Bekleyen: selin'),
      findsOneWidget,
    );
  });
}

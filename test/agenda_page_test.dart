import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_hearing.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/uets/notice_deadlines.dart';
import 'package:evrak_convert/services/uets/uets_api.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/agenda/agenda_page.dart';
import 'package:flutter/material.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const court = 'Antalya 3. Asliye Hukuk Mahkemesi';
  final now = DateTime(2026, 10, 6, 7, 20);

  Future<PortalDatabase> pump(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    void Function(PortalCase kase)? onPetition,
    void Function(PortalDatabase db)? before,
    void Function(String noticeId)? onOpenNotice,
  }) async {
    tester.view.physicalSize = size;
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
            onPetition: onPetition,
            onOpenNotice: onOpenNotice,
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
    expect(find.text('UYAP Web · bağlan'), findsOneWidget);
    expect(find.text('UYAP Mobil · bağlan'), findsOneWidget);
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

  testWidgets('a deadline is calculated from the day it was served', (
    tester,
  ) async {
    final db = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('agenda-add')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<String>),
        matching: find.text('Süre'),
      ),
    );
    await tester.pumpAndSettle();
    // Served today, 6 October 2026: a judgment with its reasons.
    await tester.tap(find.byKey(const ValueKey('agenda-served')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-calculate')));
    await tester.pumpAndSettle();
    final results = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('agenda-result-'),
    );
    expect(results, findsWidgets);
    await tester.tap(results.first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-save')));
    await tester.pumpAndSettle();
    final saved = db
        .agenda()
        .where((i) => i.kind == 'deadline' && i.id != 'd1')
        .single;
    // Two weeks, and 20 October is a working day.
    expect(saved.at, DateTime(2026, 10, 20));
    expect(saved.body, contains('tebliğ 6.10.2026'));
  });

  testWidgets('hearings at overlapping times are drawn side by side', (
    tester,
  ) async {
    final db = await pump(tester);
    final asked = DateTime.utc(2026, 10, 6);
    db.mergeHearings(
      PortalChannel.uyapWeb,
      DateTime(2026, 9, 6),
      DateTime(2026, 12, 5),
      [
        for (final (m, c) in [
          (25, 'Konya 1. Asliye Ceza'),
          (35, 'Kepez 2. Sulh Hukuk'),
        ])
          PortalHearing.create(
            number: '2026/$m',
            court: c,
            at: DateTime(2026, 10, 6, 9, m),
            channel: PortalChannel.uyapWeb,
            id: '$m',
            kind: Observed('Duruşma', PortalChannel.uyapWeb, asked),
          ),
      ],
      complete: false,
    );
    // Back a week and forward again, to read what is kept anew.
    await tester.tap(find.byTooltip('Önceki'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sonraki'));
    await tester.pumpAndSettle();
    final blocks = [
      for (final t in ['09:20 Duruşma', '09:25 Duruşma', '09:35 Duruşma'])
        tester.getRect(find.text(t)),
    ];
    for (var i = 0; i < blocks.length; i++) {
      for (var j = i + 1; j < blocks.length; j++) {
        expect(blocks[i].overlaps(blocks[j]), isFalse, reason: '$i ve $j');
      }
    }
  });

  testWidgets('the list shows what is coming, day by day', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('agenda-view-list')));
    await tester.pumpAndSettle();
    expect(find.text('6 Ekim Salı'), findsOneWidget);
    expect(find.text('7 Ekim Çarşamba'), findsOneWidget);
  });

  testWidgets('on a phone the agenda lists, and a hearing opens its card '
      'from below', (tester) async {
    for (final size in const [Size(360, 760), Size(390, 844)]) {
      await pump(tester, size: size);
      expect(find.text('Liste'), findsOneWidget);
      expect(find.text('Hafta'), findsNothing);
      final hearing = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('agenda-hearing-'),
      );
      expect(hearing, findsOneWidget);
      await tester.tap(hearing);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('agenda-prep')), findsOneWidget);
      expect(find.text('Dilekçe başlat'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a petition begun from the card closes the sheet first', (
    tester,
  ) async {
    final begun = <String>[];
    await pump(
      tester,
      size: const Size(390, 844),
      onPetition: (kase) => begun.add(kase.number),
    );
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('agenda-hearing-'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dilekçe başlat'));
    await tester.pumpAndSettle();
    expect(begun, ['2025/412']);
    expect(find.byKey(const ValueKey('agenda-prep')), findsNothing);
  });

  testWidgets('a notice’s deadline waits in the review until confirmed, '
      'then comes to the agenda', (tester) async {
    final opened = <String>[];
    final db = await pump(
      tester,
      onOpenNotice: opened.add,
      before: (db) {
        db.mergeNotices([
          UetsMessage(
            id: 'm1',
            subject: '$court [2025/412] [x]',
            sent: DateTime.utc(2026, 9, 30, 9),
          ),
          // A notice of 2023: its time ran out long ago.
          UetsMessage(
            id: 'old',
            subject: 'Manavgat 1. Aile Mahkemesi [2022/332] [x]',
            sent: DateTime.utc(2023, 11, 1, 9),
          ),
        ]);
        db.saveManifest('old', [
          (id: 'q1', name: '(1)GerekceliKarar.pdf', mime: ''),
        ]);
        db.saveManifest('m1', [
          (id: 'p1', name: '(1)GerekceliKarar.pdf', mime: ''),
        ]);
        refreshNoticeDeadlines(db, now: now);
      },
    );
    expect(find.byKey(const ValueKey('agenda-review')), findsOne);
    expect(find.textContaining('Onayınızı bekliyor'), findsOne);
    // Not counted: the only deadline due soon is the lawyer's own.
    expect(find.text('19.10.2026'), findsOne);
    // Which case it is, and the way to its notice.
    expect(find.textContaining('$court · 2025/412'), findsWidgets);
    expect(find.textContaining('2022/332'), findsNothing);
    final id = db.deadlines(noticeId: 'm1').single.record.id;
    await tester.ensureVisible(find.byKey(ValueKey('review-notice-$id')));
    await tester.tap(find.byKey(ValueKey('review-notice-$id')));
    expect(opened, ['m1']);
    await tester.ensureVisible(find.byKey(ValueKey('review-confirm-$id')));
    await tester.tap(find.byKey(ValueKey('review-confirm-$id')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agenda-review')), findsNothing);
    expect(db.agenda().map((i) => i.id), contains(id));
    // A notice served three years ago brings none: its time is long run.
    final old = db.deadlines(noticeId: 'old');
    expect(old, isNotEmpty);
    expect(old.every((d) => d.expired(now)), isTrue);
    expect(
      db.agenda().firstWhere((i) => i.id == id).body,
      contains('$court · 2025/412'),
    );
    expect(find.text('İstinaf süresi'), findsWidgets);
  });
}

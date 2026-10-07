import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/portal/uyap_notice.dart';
import 'package:evrak_convert/ui/agenda/uyap_notices_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// UYAP Bildirimleri (docs/design/uyap-bildirim-taslak.png): both channels'
// notifications in one list, tied to their case, read when opened.
void main() {
  late PortalDatabase db;
  late PortalSync sync;
  final now = DateTime(2026, 10, 7, 15);

  setUp(() {
    db = PortalDatabase.memory();
    sync = PortalSync(database: () async => db);
    db.mergeCases([
      PortalCase.create(
        number: '2024/318',
        court: 'Antalya 3. Asliye Hukuk Mahkemesi',
      ),
    ], portfolio: true);
    db.saveUyapNotices([
      const UyapNoticeRow(
        source: UyapNoticeSource.mobile,
        id: 'a',
        messageId: 'ma',
        title: 'Gerekçeli Karar',
        sentAt: null,
      ),
    ]);
    db.saveUyapNotices([
      UyapNoticeRow(
        source: UyapNoticeSource.mobile,
        id: 'm1',
        messageId: 'mm1',
        title: 'Gerekçeli Karar',
        sentAt: DateTime(2026, 10, 7, 14, 5),
      ),
      UyapNoticeRow(
        source: UyapNoticeSource.web,
        id: '1',
        title: 'Gerekçeli Karar',
        body:
            'Antalya 3. Asliye Hukuk Mahkemesi Biriminde Bulunan 2024/318 '
            'sayılı dosyaya gerekçeli karar eklenmiştir.',
        sentAt: DateTime(2026, 10, 7, 14, 5, 31),
        remoteRead: false,
      ),
      UyapNoticeRow(
        source: UyapNoticeSource.web,
        id: '2',
        title: 'Vekil Kaydı',
        body: 'Kurum adına vekil kaydı yapıldı.',
        sentAt: DateTime(2026, 10, 6, 10, 2),
        remoteRead: true,
      ),
    ]);
  });
  tearDown(() {
    sync.dispose();
    db.dispose();
  });

  Future<List<String>> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UyapNoticesPage(
            database: db,
            sync: sync,
            now: () => now,
            onOpenCase: (key) {
              opened.add(key);
              return true;
            },
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    return opened;
  }

  testWidgets('both channels’ notification is one row, tied to its case; '
      'opened, it is read and leads to the case', (tester) async {
    final opened = await pump(tester, const Size(1440, 900));
    expect(tester.takeException(), isNull);
    // The twin of two channels shown once; the one with no time at the end.
    expect(find.text('Gerekçeli Karar'), findsNWidgets(2));
    expect(find.text('BUGÜN'), findsOneWidget);
    expect(find.text('DÜN'), findsOneWidget);
    expect(
      find.textContaining('2024/318 · Antalya 3. Asliye Hukuk'),
      findsOneWidget,
    );
    expect(find.text('Dosyası bulunamadı'), findsWidgets);
    final pair = db.uyapNotices().firstWhere((n) => n.rows.length == 2);
    expect(pair.read, isFalse);
    await tester.tap(find.byKey(ValueKey('notice-${pair.key}')));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(db.uyapNotices().firstWhere((n) => n.rows.length == 2).read, isTrue);
    expect(
      find.text('İki kanaldan da geldi, bir kez gösteriliyor'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('notice-open-case')));
    expect(opened, [pair.caseKey]);
    // Unread only: the read ones gone.
    await tester.tap(find.byKey(const ValueKey('notices-filter-unread')));
    await tester.pump();
    expect(find.text('Vekil Kaydı'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the notifications fit a phone, a notification opening on '
      'its own page', (tester) async {
    await pump(tester, const Size(390, 844));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Vekil Kaydı'));
    await tester.pumpAndSettle();
    expect(find.text('Kurum adına vekil kaydı yapıldı.'), findsWidgets);
    expect(find.textContaining('hiçbir dosyaya bağlanmadı'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

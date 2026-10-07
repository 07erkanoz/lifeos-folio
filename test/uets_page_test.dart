import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/uets/notice_matcher.dart';
import 'package:evrak_convert/services/uets/uets_api.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/agenda/uets_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 6, 9);

  Future<PortalDatabase> pump(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    db.mergeCases([
      PortalCase.create(
        number: '2025/412',
        court: 'Antalya 3. Asliye Hukuk Mahkemesi',
      ),
      PortalCase.create(number: '2026/77', court: 'Antalya 1. İcra Dairesi'),
    ]);
    db.mergeNotices([
      UetsMessage(
        id: 'm1',
        subject:
            'Antalya 3. Asliye Hukuk Mahkemesi [2025/412] [Gerekçeli Karar]',
        sent: DateTime(2026, 10, 1, 10),
      ),
      UetsMessage(
        id: 'm2',
        subject: 'İzmir 2. Sulh Hukuk Mahkemesi [2026/5] [Duruşma Davetiyesi]',
        sent: DateTime(2026, 9, 20, 10),
        read: DateTime(2026, 9, 21),
      ),
    ]);
    matchNotices(db, now: now);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UetsPage(
            database: db,
            sync: PortalSync(
              web: UyapWebService.forTesting(),
              mobile: UyapMobileApi.forTesting(
                Uri.parse('http://127.0.0.1:9/'),
              ),
              uets: UetsApi.forTesting(Uri.parse('http://127.0.0.1:9/')),
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

  testWidgets('the notices, their cases and the deadlines they started', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Antalya 3. Asliye Hukuk Mahkemesi · 2025/412'), findsOne);
    expect(find.text('Eşleşmedi'), findsOne);
    // The newest is selected: tied, with its deadline.
    expect(find.textContaining('otomatik eşleşti'), findsOne);
    // Its deadline, a candidate waiting for the lawyer.
    expect(find.textContaining('Onayınızı bekliyor'), findsWidgets);
    expect(find.text('20.10.2026'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('uets-filter-unread')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uets-row-m2')), findsNothing);
    expect(find.byKey(const ValueKey('uets-row-m1')), findsOne);
  });

  testWidgets('the lawyer ties a notice by hand', (tester) async {
    final db = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('uets-row-m2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('uets-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026/77'));
    await tester.pumpAndSettle();
    final m2 = db.notices().firstWhere((n) => n.message.id == 'm2');
    expect(m2.link, 'manual');
    expect(m2.caseKey, caseKey('2026/77', 'Antalya 1. İcra Dairesi'));
    expect(find.textContaining('elle eşleştirildi'), findsOne);
  });

  testWidgets('on a phone a notice opens on a page of its own', (tester) async {
    for (final size in const [Size(360, 760), Size(390, 844)]) {
      await pump(tester, size: size);
      expect(find.byKey(const ValueKey('uets-row-m1')), findsOne);
      // No side panel on a phone.
      expect(find.textContaining('otomatik eşleşti'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('uets-row-m1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('otomatik eşleşti'), findsOne);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });
}

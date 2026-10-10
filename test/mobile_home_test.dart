import 'package:evrak_convert/ui/mobile/document_home.dart';
import 'package:evrak_convert/ui/mobile/mobile_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in const [Size(360, 760), Size(390, 844)]) {
    testWidgets('the first page and the menu fit a ${size.width} px phone', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            drawer: MobileDrawer(
              group: 'agenda',
              home: true,
              agendaToday: 2,
              uetsUnread: 3,
              uyapCases: 12,
              onHome: () {},
              onGroup: opened.add,
              onFolders: () {},
              onSettings: () {},
              onConnectMobile: () {},
              onConnectWeb: () {},
              onConnectUets: () {},
              onSyncComputer: () {},
            ),
            body: Builder(
              builder: (context) => MobileDocumentHome(
                recent: const [],
                onOpen: () {},
                onNew: () {},
                onArchive: () {},
                onGallery: () {},
                onScan: () {},
                onRecovery: () {},
                onRecent: (_) {},
                onShare: (_) {},
                recoveryCount: 0,
                name: 'Av. Erkan Öz',
                agendaToday: 2,
                deadlinesToday: 1,
                uetsUnread: 3,
                uyapCases: 12,
                uyapFresh: 4,
                next: const NextHearingLine(
                  '09:20 · Antalya 3. Asliye Hukuk · 2025/412',
                  'Ön inceleme duruşması · 2 sa sonra',
                ),
                onAgenda: () => opened.add('agenda'),
                onUets: () {},
                onUyap: () {},
                now: () => DateTime(2026, 10, 6, 9),
              ),
            ),
          ),
        ),
      );
      expect(find.text('6 Ekim Salı'), findsOne);
      expect(find.text('Günaydın, Av. Erkan Öz'), findsOne);
      expect(find.text('Bugün 2 duruşma · 1 süre dolacak'), findsOne);
      expect(find.text('3 okunmamış tebligat'), findsOne);
      expect(find.text('12 dosya · 4 yeni evrak'), findsOne);
      await tester.tap(find.byKey(const ValueKey('mobile-agenda')));
      expect(opened, ['agenda']);
      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();
      expect(find.text('Bugün 2'), findsOne);
      // Further down the menu, past the office's pages.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('drawer-sync')),
        120,
        scrollable: find
            .descendant(
              of: find.byType(Drawer),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.byKey(const ValueKey('drawer-sync')), findsOne);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('drawer-uets')),
        -120,
        scrollable: find
            .descendant(
              of: find.byType(Drawer),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const ValueKey('drawer-uets')));
      expect(opened.last, 'uets');
    });
  }
}

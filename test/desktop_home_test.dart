import 'dart:io';

import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_hearing.dart';
import 'package:evrak_convert/services/uyap/uyap_case_links.dart';
import 'package:evrak_convert/ui/desktop/desktop_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late List<EvrakFile> recent;
  final now = DateTime(2026, 10, 7, 8, 50);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('folio_home_');
    recent = [
      for (final name in [
        'Cevap dilekçesi.udf',
        'Bilirkişi raporuna itiraz.udf',
        'Tarama 2026-10-06.pdf',
        'Vekaletname.docx',
      ])
        EvrakFile.fromPath(
          (File(p.join(dir.path, name))..writeAsStringSync('x')).path,
        ),
    ];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<List<String>> pump(
    WidgetTester tester,
    Size size, {
    DesktopHomeOffice office = const DesktopHomeOffice(),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopHome(
            name: 'Av. Deniz Kaya',
            recent: recent,
            office: office,
            links: UyapCaseLinks(directory: dir),
            now: () => now,
            onSearch: (q) => calls.add('search:$q'),
            onOpen: (f) => calls.add('open:${p.basename(f.path)}'),
            onEdit: (f) => calls.add('edit:${p.basename(f.path)}'),
            onSendUyap: (f) => calls.add('send:${p.basename(f.path)}'),
            onArchive: () => calls.add('archive'),
            onDrafts: () => calls.add('drafts'),
            onAgenda: () => calls.add('agenda'),
            onUets: () => calls.add('uets'),
          ),
        ),
      ),
    );
    await tester.pump();
    return calls;
  }

  for (final size in const [Size(1440, 900), Size(1100, 760), Size(900, 700)]) {
    testWidgets('the first page fits ${size.width} px', (tester) async {
      await pump(
        tester,
        size,
        office: DesktopHomeOffice(
          today: [
            PortalHearing.create(
              number: '2024/318 Esas',
              court: 'Antalya 3. Asliye Hukuk Mahkemesi',
              at: DateTime(2026, 10, 7, 9, 35),
            ),
          ],
          deadlines: [
            AgendaItem(
              id: 'd1',
              kind: 'deadline',
              title: 'İstinaf süresi',
              at: DateTime(2026, 10, 7, 23, 59),
              updated: now,
            ),
            AgendaItem(
              id: 'd2',
              kind: 'deadline',
              title: 'Bilirkişi raporuna itiraz',
              at: DateTime(2026, 10, 9),
              updated: now,
            ),
          ],
          unread: 3,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Günaydın, Av. Deniz Kaya'), findsOne);
      expect(find.text('KALDIĞINIZ YERDEN DEVAM EDİN'), findsOne);
      expect(find.text('UYAP Web'), findsOne);
      expect(find.text('UYAP Mobil'), findsOne);
    });
  }

  testWidgets('today, the deadlines and UETS', (tester) async {
    await pump(
      tester,
      const Size(1440, 900),
      office: DesktopHomeOffice(
        today: [
          PortalHearing.create(
            number: '2024/318 Esas',
            court: 'Antalya 3. Asliye Hukuk Mahkemesi',
            at: DateTime(2026, 10, 7, 9, 35),
          ),
        ],
        deadlines: [
          AgendaItem(
            id: 'd1',
            kind: 'deadline',
            title: 'İstinaf süresi',
            at: DateTime(2026, 10, 7, 23, 59),
            updated: now,
          ),
        ],
        unread: 3,
      ),
    );
    expect(find.text('SON EVRAKLAR'), findsOne);
    expect(find.text('YAKLAŞAN SÜRELER'), findsOne);
    expect(find.text('BUGÜN'), findsOne);
    expect(find.textContaining('Duruşma · Antalya'), findsOne);
    expect(find.text('okunmamış tebligat'), findsOne);
    expect(find.text('SIRADAKİ'), findsNothing);
  });

  testWidgets('no hearing today shows the next one', (tester) async {
    await pump(
      tester,
      const Size(1440, 900),
      office: DesktopHomeOffice(
        next: PortalHearing.create(
          number: '2025/77 Esas',
          court: 'Antalya 5. İş Mahkemesi',
          at: DateTime(2026, 10, 9, 10, 15),
        ),
      ),
    );
    expect(find.text('SIRADAKİ'), findsOne);
    expect(find.textContaining('9 Ekim Cuma 10:15'), findsOne);
  });

  testWidgets('continues, searches and filters', (tester) async {
    final calls = await pump(tester, const Size(1440, 900));
    expect(find.byKey(const ValueKey('home-continue-send')), findsOne);
    await tester.tap(find.byKey(const ValueKey('home-continue-edit')));
    await tester.enterText(find.byKey(const ValueKey('home-search')), 'kira');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.tap(find.byKey(const ValueKey('home-archive')));
    expect(calls, ['edit:Cevap dilekçesi.udf', 'search:kira', 'archive']);
    await tester.tap(find.byKey(const ValueKey('home-filter-scans')));
    await tester.pump();
    expect(find.byKey(const ValueKey('home-recent-0')), findsOne);
    expect(find.byKey(const ValueKey('home-recent-1')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

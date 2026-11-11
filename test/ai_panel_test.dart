import 'package:evrak_convert/services/ai/ai_assistant.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_hearing.dart';
import 'package:evrak_convert/ui/ai/ai_markdown.dart';
import 'package:evrak_convert/ui/ai/ai_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The conversation's screen: what an empty one offers, what is done with
// an answer, and what the program says of itself on the way.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AiAssistant.statusesForTest = const [
      AiStatus(AiProvider.claude, path: '/bin/claude', signedIn: true),
    ];
  });
  tearDown(() => AiAssistant.statusesForTest = null);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
    }
  }

  Widget app(Widget panel) => MaterialApp(home: Scaffold(body: panel));

  test('the allowance the program tells, by its fullest window', () {
    final events = AiEvents.claude(
      '{"type":"rate_limit_event","rate_limit_info":{"status":"allowed",'
      '"unifiedWindows":{"five_hour":{"utilization":0.05},'
      '"seven_day":{"utilization":0.42}}}}',
    );
    final quota = events.single as AiQuota;
    expect(quota.label, 'Haftalık %42');
    expect(quota.most, closeTo(.42, 1e-9));
    expect(AiEvents.claude('{"type":"rate_limit_event"}'), isEmpty);
  });

  test('a step is counted by what it looked at', () {
    expect(const AiStep('1', 'mevzuat_madde').kind, 'mevzuat');
    expect(const AiStep('1', 'karar_getir').kind, 'karar');
    expect(const AiStep('1', 'evrak_oku').kind, 'evrak');
    expect(const AiStep('1', 'atif_dogrula').kind, '');
  });

  testWidgets('a citation named is a link where it stands', (tester) async {
    Offset? pressed;
    await tester.pumpWidget(
      app(
        AiMarkdown(
          'İşçi **TBK m.49** uyarınca tazminat ister; TBK m.49 açıktır.',
          links: {'TBK m.49': (at) => pressed = at},
        ),
      ),
    );
    final rich = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text)
        .whereType<TextSpan>();
    var links = 0;
    void walk(InlineSpan span) {
      if (span is TextSpan) {
        if (span.recognizer != null) {
          links++;
          expect(span.text, 'TBK m.49');
        }
        span.children?.forEach(walk);
      }
    }

    rich.forEach(walk);
    // In the bold and in the plain text both.
    expect(links, 2);
    await tester.tapOnText(find.textRange.ofSubstring('TBK m.49').last);
    expect(pressed, isNotNull);
  });

  testWidgets('a fenced block is drawn by who takes its language', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        AiMarkdown(
          'Öneri:\n\n```belge\nDavanın kabulüne.\n```\n\n```dart\nx\n```',
          block: (language, text) =>
              language == 'belge' ? Text('KART:$text') : null,
        ),
      ),
    );
    expect(find.text('KART:Davanın kabulüne.'), findsOneWidget);
    expect(find.text('x'), findsOneWidget);
  });

  testWidgets('the page of no case: today, and what may be asked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    final now = DateTime.now();
    db.mergeCases([
      PortalCase.create(number: '2026/470', court: 'Manavgat 3. İş Mahkemesi'),
    ], portfolio: true);
    db.mergeHearings(
      PortalChannel.uyapMobile,
      now.subtract(const Duration(days: 1)),
      now.add(const Duration(days: 30)),
      [
        PortalHearing.create(
          number: '2026/470',
          court: 'Manavgat 3. İş Mahkemesi',
          at: DateTime(now.year, now.month, now.day, 23, 59),
        ),
      ],
      complete: true,
    );
    await tester.pumpWidget(
      app(AiPanel(embedded: true, showCase: true, database: () async => db)),
    );
    await settle(tester);
    expect(find.text('Bugün ne yapalım?'), findsOneWidget);
    expect(find.text('Bugün 1 duruşmanız var'), findsOneWidget);
    // A card that needs the lawyer's own words writes its start.
    await tester.tap(find.text('Dilekçe yazdır'));
    await tester.pump();
    final box = tester.widget<TextField>(
      find.byKey(const ValueKey('ai-question')),
    );
    expect(box.controller!.text, 'Şu dosya için dilekçe yaz: ');
    // The tier asked at is chosen under the box.
    expect(find.byKey(const ValueKey('ai-tier-strong')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-tier-normal')), findsOneWidget);
  });

  testWidgets('beside the editor a text for the document is written into it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final written = <String>[];
    await tester.pumpWidget(
      app(
        AiPanel(
          embedded: true,
          document: () => 'Belge',
          documentName: 'dilekce.udf',
          selection: () => null,
          onInsert: written.add,
          onClose: () {},
          chat: const {
            'id': 's1',
            'turlar': [
              {
                'soru': 'Talep sonucu yaz',
                'yazan': 'Claude · Normal',
                'sure': 75,
                'adimlar': ['Evrak okundu · Dava dilekçesi'],
                'cevap': 'Şöyle:\n\n```belge\nDavanın kabulüne.\n```',
              },
            ],
          },
        ),
      ),
    );
    await settle(tester);
    // What the answer took, said beside who wrote it.
    expect(find.text('Claude · Normal · 1 adım · 1 dk 15 sn'), findsOneWidget);
    expect(find.text('Yapılan incelemeler (1) · 1 evrak'), findsOneWidget);
    expect(find.text('Belge için metin'), findsOneWidget);
    final insert = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('ai-belge-insert-'),
    );
    await tester.tap(insert);
    expect(written, ['Davanın kabulüne.']);
    // Asked at the lesser tier, it may be asked again at the stronger.
    expect(find.text('Güçlü modelle tekrarla'), findsOneWidget);
    expect(find.text('Belgede seçili metni soruya ekle'), findsOneWidget);
  });
}

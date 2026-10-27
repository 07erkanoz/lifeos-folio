import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/ofis_app.dart';
import 'package:evrak_convert/services/editor/editor_drafts.dart';
import 'package:evrak_convert/services/platform/app_edition.dart';
import 'package:evrak_convert/services/platform/document_launch.dart';
import 'package:evrak_convert/ui/widgets/editor_ribbon.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:evrak_convert/ui/widgets/folio_about_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => AppEdition.current = AppEdition.folio);

  testWidgets('Ofis\'s first page: open, a new UDF or Word document, and '
      'the recent ones, each opened with a click', (tester) async {
    tester.view.physicalSize = const Size(1280, 840);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final done = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ofisHomeForTesting(
          recent: [
            EvrakFile.fromPath('/belgeler/Bilirkişi raporu.udf'),
            EvrakFile.fromPath('/belgeler/Kira sözleşmesi.docx'),
          ],
          onOpen: () => done.add('open'),
          onNew: (format) => done.add('new:${format.defaultExtension}'),
          onOpenFile: (path) => done.add('file:$path'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Belgeleriniz'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ofis-home-open')));
    await tester.tap(find.byKey(const ValueKey('ofis-home-new-udf')));
    await tester.tap(find.byKey(const ValueKey('ofis-home-new-docx')));
    await tester.tap(find.text('Kira sözleşmesi'));
    expect(done, [
      'open',
      'new:udf',
      'new:docx',
      'file:/belgeler/Kira sözleşmesi.docx',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in Ofis the editor\'s research tab keeps case law, signing '
      'by card and the history; no petitions, UYAP, mobile signature, '
      'agenda or live sharing', (tester) async {
    AppEdition.current = AppEdition.ofis;
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => editorRibbonTab.value = RibbonTab.home);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: Column(
            children: [
              const EditorRibbonTabs(),
              Expanded(
                child: EditorWidget(
                  draft: EditorDrafts().draft('ofis', 'Yeni belge.udf'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(RibbonTab.legal.label, 'Araştırma');
    await tester.tap(find.byKey(const ValueKey('ribbon-tab-legal')));
    await tester.pump();
    expect(find.byKey(const ValueKey('legal-case-law')), findsOneWidget);
    expect(find.byKey(const ValueKey('legal-sign-card')), findsOneWidget);
    for (final key in [
      'legal-templates',
      'legal-send',
      'legal-sign-mobile',
      'legal-uyap-case',
      'legal-deadline',
      'legal-live',
    ]) {
      expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
    }
    for (final group in ['Dilekçe', 'Ajanda', 'Paylaşım']) {
      expect(find.text(group), findsNothing, reason: group);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Ofis\'s About names Ofis, not Folio\'s lawyers', (
    tester,
  ) async {
    AppEdition.current = AppEdition.ofis;
    tester.view.physicalSize = const Size(900, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FolioAboutDialog())),
    );
    expect(find.text('LifeOS Ofis'), findsOneWidget);
    expect(find.textContaining('Avukatlar için'), findsNothing);
    expect(find.byKey(const ValueKey('about-download')), findsNothing);
    expect(find.textContaining('Ofis tescilli'), findsOneWidget);
  });

  test('a document Ofis is started on is read; --edit writes in it', () {
    final launch = DocumentLaunch.parse(['--edit', '--', '/tmp/a.udf']);
    expect(launch.edit, isTrue);
    expect(ofisTitle('/tmp/a.udf'), 'a.udf — LifeOS Ofis');
    expect(ofisTitle(null), 'LifeOS Ofis');
  });
}

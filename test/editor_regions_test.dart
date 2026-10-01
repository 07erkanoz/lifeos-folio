import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/editor/editor_drafts.dart';
import 'package:evrak_convert/services/editor/letterheads.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/editor_region_band.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';

import 'editor_shortcuts_test.dart' show shortcut, waitFor;

DocModel _withHeader() => DocModel(
  blocks: [DocBlock(plainText: 'Dilekçe gövdesi')],
  pageRegions: {
    'header': [DocBlock(plainText: 'T.C. ANKARA 3. ASLİYE HUKUK MAHKEMESİ')],
    'footer': [DocBlock(plainText: 'Sayfa')],
  },
  metadata: const {
    'formatId': '1.8',
    'pageRegionAttrs': {
      'header': {'startPage': '2'},
      'footer': {'pageNumber-spec': 'BSP32_2120', 'pageNumber-seperator': '/'},
    },
  },
);

void main() {
  test('a header keeps the settings that are not text', () {
    // Page numbering and the page a header starts on live only in these
    // attributes; a save that dropped them would restart numbering at one.
    final reopened = UdfReader.readBytes(UdfWriter.writeBytes(_withHeader()))!;
    final attrs = reopened.metadata['pageRegionAttrs'] as Map;
    expect((attrs['header'] as Map)['startPage'], '2');
    expect((attrs['footer'] as Map)['pageNumber-spec'], 'BSP32_2120');
    expect((attrs['footer'] as Map)['pageNumber-seperator'], '/');
    expect(
      reopened.pageRegions['header']!.single.plainText,
      'T.C. ANKARA 3. ASLİYE HUKUK MAHKEMESİ',
    );
  });

  testWidgets('the header and footer are shown, edited and saved', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('editor-regions-'),
    ))!;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    final file = File('${dir.path}/belge.udf');
    await tester.runAsync(
      () => file.writeAsBytes(UdfWriter.writeBytes(_withHeader())),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: EditorWidget(
            initialFilePath: file.path,
            initialFormat: EvrakFormat.udf,
          ),
        ),
      ),
    );
    await waitFor(
      tester,
      () => find.byType(EditorRegionBand).evaluate().length == 2,
    );

    // The header is on screen rather than only in the file. It starts on
    // page 2, as UYAP prints it, so on this one-page document it is shown
    // faded, to be written in, and said so.
    expect(
      find.text('ÜST BİLGİ · 2. sayfadan itibaren basılır'),
      findsOneWidget,
    );
    expect(find.text('ALT BİLGİ'), findsOneWidget);
    final bands = tester.widgetList<EditorRegionBand>(
      find.byType(EditorRegionBand),
    );
    final header = bands.firstWhere((b) => b.isHeader);
    expect(
      header.controller.document.toPlainText().trim(),
      'T.C. ANKARA 3. ASLİYE HUKUK MAHKEMESİ',
    );

    // Editing the header marks the document unsaved and reaches the file.
    header.controller.replaceText(
      0,
      4,
      'T.C. İSTANBUL',
      const TextSelection.collapsed(offset: 13),
    );
    await tester.pump();
    tester
        .widget<QuillEditor>(
          find.descendant(
            of: find.byType(EditorRegionBand).first,
            matching: find.byType(QuillEditor),
          ),
        )
        .focusNode
        .requestFocus();
    await tester.pump();
    await shortcut(tester, LogicalKeyboardKey.keyS);
    await waitFor(
      tester,
      () => find.textContaining('Başarıyla kaydedildi:').evaluate().isNotEmpty,
    );

    final saved = (await tester.runAsync(
      () async => UdfReader.readFile(file.path),
    ))!;
    expect(
      saved.pageRegions['header']!.map((b) => b.plainText).join(),
      startsWith('T.C. İSTANBUL'),
    );
    expect(saved.pageRegions['footer']!.single.plainText, 'Sayfa');
    expect(saved.toPlainText(), 'Dilekçe gövdesi');
    // The body is untouched by an edit that only changed the header.
    expect(
      ((saved.metadata['pageRegionAttrs'] as Map)['header']
          as Map)['startPage'],
      '2',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('the header is on every page, and is edited on the page it is '
      'clicked on', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('editor-regions-'),
    ))!;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    final file = File('${dir.path}/belge.udf');
    // Eighty rows: two pages.
    final model = DocModel(
      blocks: [for (var i = 1; i <= 80; i++) DocBlock(plainText: 'Satır $i')],
      pageRegions: {
        'header': [
          DocBlock(plainText: 'T.C. ANKARA 3. ASLİYE HUKUK MAHKEMESİ'),
        ],
      },
    );
    await tester.runAsync(() => file.writeAsBytes(UdfWriter.writeBytes(model)));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: EditorWidget(
            initialFilePath: file.path,
            initialFormat: EvrakFormat.udf,
          ),
        ),
      ),
    );
    await waitFor(
      tester,
      () => find.byType(EditorRegionBand).evaluate().length == 2,
    );
    // Measured as the preview measures it, which lays the pages out again.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
    // The first page's is the one typed in, the second's a copy of it.
    final live = find.byKey(const ValueKey('region-header'));
    final copy = find.byKey(const ValueKey('region-header-1'));
    expect(live, findsOneWidget);
    expect(copy, findsOneWidget);
    expect(
      tester.getTopLeft(copy).dy,
      greaterThan(tester.getTopLeft(live).dy + 500),
    );

    await tester.ensureVisible(copy);
    // Scrolling keeps the page from taking taps until it has come to rest.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    final second = tester.getTopLeft(copy).dy;
    await tester.tap(copy);
    await tester.pump();
    await tester.pump();
    // Now the second page's is the one typed in, and it has the cursor.
    expect(find.byKey(const ValueKey('region-header-1')), findsNothing);
    expect(tester.getTopLeft(live).dy, closeTo(second, 1));
    final editor = tester.widget<QuillEditor>(
      find.descendant(of: live, matching: find.byType(QuillEditor)),
    );
    expect(editor.focusNode.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a header added in the editor is saved, leaves nothing '
      'unsaved, and is there when the file is opened again', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('editor-regions-'),
    ))!;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    final file = File('${dir.path}/belge.udf');
    await tester.runAsync(
      () => file.writeAsBytes(
        UdfWriter.writeBytes(
          DocModel(blocks: [DocBlock(plainText: 'Dilekçe gövdesi')]),
        ),
      ),
    );
    final drafts = EditorDrafts();
    final draft = drafts.draft(file.path, 'belge.udf');
    Widget app(Key key, EditorDraft draft) => MaterialApp(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      home: Scaffold(
        body: EditorWidget(
          key: key,
          initialFilePath: file.path,
          initialFormat: EvrakFormat.udf,
          draft: draft,
        ),
      ),
    );
    await tester.pumpWidget(app(const ValueKey(1), draft));
    await waitFor(
      tester,
      () => find.byTooltip('Üst bilgi ve alt bilgi').evaluate().isNotEmpty,
    );
    await tester.tap(find.byTooltip('Üst bilgi ve alt bilgi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Üst bilgi').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final band = tester.widget<EditorRegionBand>(
      find.byKey(const ValueKey('region-header')),
    );
    band.controller.replaceText(
      0,
      0,
      'Av. Deneme Hukuk Bürosu',
      const TextSelection.collapsed(offset: 23),
    );
    await tester.pump();
    expect(draft.changed!(), isTrue);

    await shortcut(tester, LogicalKeyboardKey.keyS);
    await waitFor(
      tester,
      () => find.textContaining('Başarıyla kaydedildi:').evaluate().isNotEmpty,
    );
    final saved = (await tester.runAsync(
      () async => UdfReader.readFile(file.path),
    ))!;
    expect(
      saved.pageRegions['header']?.map((b) => b.plainText).join(),
      'Av. Deneme Hukuk Bürosu',
    );
    // Saved is saved: nothing asks to be saved again on the way out.
    expect(draft.changed!(), isFalse);

    // Opened again, the header is on the page.
    final again = drafts.draft('${file.path}#2', 'belge.udf');
    await tester.pumpWidget(app(const ValueKey(2), again));
    await waitFor(
      tester,
      () => find.byKey(const ValueKey('region-header')).evaluate().isNotEmpty,
    );
    expect(
      tester
          .widget<EditorRegionBand>(find.byKey(const ValueKey('region-header')))
          .controller
          .document
          .toPlainText()
          .trim(),
      'Av. Deneme Hukuk Bürosu',
    );
    expect(again.changed!(), isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('page numbers are set from the menu, drawn on every page and '
      'saved as UYAP keeps them', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('editor-regions-'),
    ))!;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    final file = File('${dir.path}/belge.udf');
    await tester.runAsync(
      () => file.writeAsBytes(
        UdfWriter.writeBytes(
          DocModel(
            blocks: [
              for (var i = 1; i <= 80; i++) DocBlock(plainText: 'Satır $i'),
            ],
          ),
        ),
      ),
    );
    final draft = EditorDrafts().draft(file.path, 'belge.udf');
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: EditorWidget(
            initialFilePath: file.path,
            initialFormat: EvrakFormat.udf,
            draft: draft,
          ),
        ),
      ),
    );
    await waitFor(
      tester,
      () => find.byTooltip('Üst bilgi ve alt bilgi').evaluate().isNotEmpty,
    );
    await tester.tap(find.byTooltip('Üst bilgi ve alt bilgi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sayfa numarası…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alt bilgide'));
    await tester.pump();
    await tester.tap(find.text('Toplam sayfayla'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Ön metin'),
      'Sayfa ',
    );
    await tester.pump();
    expect(find.text('Örnek: Sayfa 1/5'), findsOneWidget);
    await tester.tap(find.text('Tamam'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // A footer on each of the two pages, each with its number.
    final numbers = tester
        .widgetList<EditorRegionBand>(find.byType(EditorRegionBand))
        .map((b) => b.numberLabel)
        .toList();
    expect(numbers, ['Sayfa 1/2', 'Sayfa 2/2']);
    expect(draft.changed!(), isTrue);

    await shortcut(tester, LogicalKeyboardKey.keyS);
    await waitFor(
      tester,
      () => find.textContaining('Başarıyla kaydedildi:').evaluate().isNotEmpty,
    );
    expect(draft.changed!(), isFalse);
    final saved = (await tester.runAsync(
      () async => UdfReader.readFile(file.path),
    ))!;
    // The very set UYAP's own dialog writes for a numbered footer.
    expect((saved.metadata['pageRegionAttrs'] as Map)['footer'], {
      'pageNumber-spec': 'BSP32_2088',
      'pageNumber-seperator': '/',
      'pageNumber-fontBold': 'false',
      'pageNumber-fontItalic': 'false',
      'pageNumber-fontFace': 'Arial',
      'pageNumber-fontSize': '11',
      'pageNumber-color': '-16777216',
      'pageNumber-foreStr': 'Sayfa ',
      'pageNumber-pageStartNumStr': '',
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a header is kept as a letterhead, put on another document on '
      'its first page, and heads new documents', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final letterheads = LetterheadStore.memory();
    LetterheadStore.useShared(letterheads);
    addTearDown(() => LetterheadStore.useShared(null));
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('editor-regions-'),
    ))!;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    final withHeader = File('${dir.path}/antetli.udf');
    final plain = File('${dir.path}/duz.udf');
    await tester.runAsync(() async {
      await withHeader.writeAsBytes(
        UdfWriter.writeBytes(
          DocModel(
            blocks: [DocBlock(plainText: 'Gövde')],
            pageRegions: {
              'header': [
                DocBlock(
                  plainText: 'AV. DENEME HUKUK BÜROSU',
                  alignment: DocAlignment.center,
                ),
              ],
            },
          ),
        ),
      );
      await plain.writeAsBytes(
        UdfWriter.writeBytes(
          DocModel(blocks: [DocBlock(plainText: 'Başka dilekçe')]),
        ),
      );
    });
    Widget app(Widget editor) => MaterialApp(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      home: Scaffold(body: editor),
    );
    Future<void> openMenu() async {
      await waitFor(
        tester,
        () => find.byTooltip('Üst bilgi ve alt bilgi').evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('Üst bilgi ve alt bilgi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Antet…'));
      await tester.pumpAndSettle();
    }

    // Kept from the first document's header.
    await tester.pumpWidget(
      app(
        EditorWidget(
          key: const ValueKey(1),
          initialFilePath: withHeader.path,
          initialFormat: EvrakFormat.udf,
        ),
      ),
    );
    await openMenu();
    expect(find.textContaining('Henüz antet yok'), findsOneWidget);
    await tester.tap(find.text('Üst bilgiyi antet olarak kaydet…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Büro');
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
    expect(letterheads.all.single.name, 'Büro');
    expect(letterheads.all.single.summary, 'AV. DENEME HUKUK BÜROSU');
    // The first one kept is the one new documents get.
    expect(letterheads.defaultOne?.name, 'Büro');
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();

    // Put on another, on its first page only, and saved as UYAP keeps it.
    final draft = EditorDrafts().draft(plain.path, 'duz.udf');
    await tester.pumpWidget(
      app(
        EditorWidget(
          key: const ValueKey(2),
          initialFilePath: plain.path,
          initialFormat: EvrakFormat.udf,
          draft: draft,
        ),
      ),
    );
    await openMenu();
    await tester.tap(find.text('Yalnız ilk sayfada'));
    await tester.pump();
    await tester.tap(find.text('Uygula'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditorRegionBand>(find.byKey(const ValueKey('region-header')))
          .controller
          .document
          .toPlainText()
          .trim(),
      'AV. DENEME HUKUK BÜROSU',
    );
    expect(draft.changed!(), isTrue);
    await shortcut(tester, LogicalKeyboardKey.keyS);
    await waitFor(
      tester,
      () => find.textContaining('Başarıyla kaydedildi:').evaluate().isNotEmpty,
    );
    final saved = (await tester.runAsync(
      () async => UdfReader.readFile(plain.path),
    ))!;
    expect(
      saved.pageRegions['header']!.single.plainText,
      'AV. DENEME HUKUK BÜROSU',
    );
    expect((saved.metadata['pageRegionAttrs'] as Map)['header'], {
      'stopPage': '1',
    });
    expect(saved.blocks.single.plainText, 'Başka dilekçe');

    // A new document starts under it, and is not an unsaved change.
    final fresh = EditorDrafts().draft('new', 'Yeni evrak');
    await tester.pumpWidget(
      app(EditorWidget(key: const ValueKey(3), draft: fresh)),
    );
    await waitFor(
      tester,
      () => find.byKey(const ValueKey('region-header')).evaluate().isNotEmpty,
    );
    expect(fresh.changed!(), isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a document with no header is not given empty bands', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('editor-noregion-'),
    ))!;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    final file = File('${dir.path}/belge.udf');
    await tester.runAsync(
      () => file.writeAsBytes(
        UdfWriter.writeBytes(
          DocModel(blocks: [DocBlock(plainText: 'Sade belge')]),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: EditorWidget(
            initialFilePath: file.path,
            initialFormat: EvrakFormat.udf,
          ),
        ),
      ),
    );
    await waitFor(tester, () => find.byType(QuillEditor).evaluate().isNotEmpty);
    expect(find.byType(EditorRegionBand), findsNothing);
    await tester.pumpAndSettle();
  });
}

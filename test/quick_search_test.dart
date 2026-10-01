import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/services/search/search_models.dart';
import 'package:evrak_convert/services/search/index_database.dart';
import 'package:evrak_convert/services/search/text_extractor.dart';
import 'package:evrak_convert/ui/desktop/quick_search_palette.dart';
import 'package:evrak_convert/ui/library/search_controls.dart';
import 'package:evrak_convert/ui/theme/app_theme.dart';

void main() {
  test('long queries retain the final term, exact phrase preserves repetitions', () {
    final words = List.generate(150, (i) => 'sözcük$i');
    final db = IndexDatabase(':memory:');
    addTearDown(db.close);
    final root = db.addSource('/synthetic', true, true);
    for (var i = 0; i < 2; i++) {
      final id = db.registerFile(
        sourceId: root,
        token: 1,
        path: '/synthetic/karar$i.txt',
        size: 1,
        modified: i,
        changed: i,
        changedContent: true,
      );
      db.setContent(
        id,
        '${words.join(' ')} ${i == 0 ? 'sonbelirteç' : 'başka'} karar karar kesinleşti',
        'ready',
        null,
      );
    }
    expect(
      db.search(
        SearchQuery(text: '${words.join(' ')} sonbelirteç').toMap(),
      )['total'],
      1,
    );
    expect(
      db.search(
        const SearchQuery(
          text: 'karar karar kesinleşti',
          match: SearchMatch.phrase,
        ).toMap(),
      )['total'],
      2,
    );
    expect(
      db.search(
        const SearchQuery(
          text: 'karar kesinleşti karar',
          match: SearchMatch.phrase,
        ).toMap(),
      )['total'],
      0,
    );
    expect(
      db.search(
        const SearchQuery(
          text: 'sonbelirteç başka',
          match: SearchMatch.any,
        ).toMap(),
      )['total'],
      2,
    );
    expect(
      () => SearchQuery.expression('a' * (SearchQuery.maxQueryCharacters + 1)),
      throwsFormatException,
    );
  });
  test('content beyond old two-million-character cutoff is indexed and excerpted', () async {
    final dir = await Directory.systemTemp.createTemp('folio-long-');
    final file = File('${dir.path}/uzun.txt');
    final text =
        '${'Genel açıklama ve duruşma notları. ' * 70000}\nSON BÖLÜM: Mücbir sebep nedeniyle tebligatın iadesi kararlaştırılmıştır.';
    try {
      await file.writeAsString(text);
      final extraction = await IndexTextExtractor.extract(file.path);
      expect(extraction['state'], 'ready');
      expect(extraction['text'], text);
      final db = IndexDatabase(':memory:');
      try {
        final root = db.addSource(dir.path, true, true);
        final id = db.registerFile(
          sourceId: root,
          token: 1,
          path: file.path,
          size: text.length,
          modified: 1,
          changed: 1,
          changedContent: true,
        );
        db.setContent(id, extraction['text'] as String, 'ready', null);
        final page = db.search(
          const SearchQuery(text: 'mucbir sebep tebligatin').toMap(),
        );
        expect(page['total'], 1);
        final hit = (page['hits'] as List).single;
        expect(hit['excerpt'], contains('Mücbir sebep'));
        expect(hit['excerpt'], contains('tebligatın'));
        expect((hit['excerpt'] as String).length, lessThan(500));
        expect(hit.containsKey('text'), isFalse);
      } finally {
        db.close();
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });
  testWidgets(
    'palette uses the same query, filters and keyboard-selected preview',
    (tester) async {
      tester.view.physicalSize = const Size(740, 580);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('folio-palette-'),
      ))!;
      final library = LibraryController(
        databasePath: ':memory:',
        watchFolders: false,
      );
      await tester.runAsync(() async {
        await File('${dir.path}/İtiraz dilekçesi.txt').writeAsString(
          'İhtiyati tedbir kararına itiraz ve hukuki değerlendirme.',
        );
        await File('${dir.path}/Duruşma tutanağı.txt')
            .writeAsString('İhtiyati tedbir kararı duruşmada değerlendirildi.');
        await library.addPaths([dir.path]);
        await library.waitForIdle();
      });
      library.query = 'ihtiyati tedbir';
      await tester.runAsync(library.searchNow);
      String? opened;
      var dismissed = false;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: RepaintBoundary(
            key: boundary,
            child: QuickSearchPalette(
              library: library,
              onOpen: (file) => opened = file.path,
              onDismiss: () => dismissed = true,
              onMain: () {},
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SearchControls), findsOneWidget);
      expect(find.text('2 SONUÇ'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opened, library.hits[1].file.path);
      await tester.tap(find.byTooltip('Arama seçenekleri'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tam ifade'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(library.match, SearchMatch.phrase);
      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Reviewable render from real widgets and a synthetic index.
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ImageByteFormat.png);
        if (bytes != null) {
          await File('/tmp/folio-quick-search.png')
              .writeAsBytes(bytes.buffer.asUint8List());
        }
        image.dispose();
      });
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(dismissed, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        library.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await dir.delete(recursive: true);
      });
    },
  );
}

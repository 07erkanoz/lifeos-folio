import 'dart:io';

import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/services/search/search_models.dart';
import 'package:evrak_convert/ui/mobile/mobile_gallery.dart';
import 'package:evrak_convert/ui/mobile/photo_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  late Directory dir;
  late List<SearchHit> hits;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('folio-gallery-');
    final png = img.encodePng(
      img.Image(width: 120, height: 80)..clear(img.ColorRgb8(90, 120, 160)),
    );
    hits = [
      for (var i = 0; i < 5; i++)
        SearchHit(
          file: EvrakFile.fromPath(
            (File('${dir.path}/foto$i.png')..writeAsBytesSync(png)).path,
          ),
          modified: DateTime(2026, 10, 7, 9, i).millisecondsSinceEpoch,
        ),
    ];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('a long press chooses; the order chosen is the PDF’s', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final library = LibraryController(watchFolders: false);
    addTearDown(library.dispose);
    List<EvrakFile>? pdf;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileGallery(
            hits: hits,
            library: library,
            hasMore: false,
            loadMore: () {},
            pickFolder: () async => null,
            onOpen: (_) {},
            onMakePdf: (files) => pdf = files,
            onShare: (_) {},
            onToCase: (_) {},
            onScan: () {},
            now: () => DateTime(2026, 10, 7, 12),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Bugün'), findsOne);
    expect(find.text('5 öğe'), findsOne);
    expect(find.text('Tara'), findsOne);
    await tester.longPress(find.byKey(const ValueKey('gallery-tile-3')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('gallery-tile-1')));
    await tester.pump();
    expect(find.text('2 seçili'), findsOne);
    expect(find.text('Tara'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('gallery-make-pdf')));
    expect(pdf!.map((f) => f.name), ['foto3.png', 'foto1.png']);
    await tester.tap(find.byKey(const ValueKey('gallery-choose-close')));
    await tester.pump();
    expect(find.text('2 seçili'), findsNothing);
  });

  testWidgets('the editor opens on the corners and keeps a copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => saved = await PhotoEditorPage.open(
              context,
              hits.first.file.path,
            ),
            child: const Text('aç'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aç'));
    for (
      var i = 0;
      i < 60 && find.byKey(const ValueKey('photo-corner-0')).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('photo-corner-0')), findsOne);
    expect(find.text('Belge düzelt'), findsOne);
    expect(find.text('Renkli belge'), findsOne);
    await tester.tap(find.byKey(const ValueKey('photo-filter-document')));
    await tester.tap(find.byKey(const ValueKey('photo-tool-redact')));
    await tester.pump();
    expect(find.textContaining('Kapatmak istediğiniz'), findsOne);
    await tester.tap(find.byKey(const ValueKey('photo-save')));
    for (var i = 0; i < 80 && saved == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(saved, endsWith('foto0 (düzenlenmiş).png'));
    expect(File(saved!).existsSync(), isTrue);
  });
}

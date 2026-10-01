import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_library.dart';

/// The folder UYAP documents are saved in is one Folio searches.
void main() {
  test(
    'it is added once, and not at all when documents are not saved',
    () async {
      final dir = await Directory.systemTemp.createTemp('folio-uyap-arama-');
      final library = LibraryController(
        databasePath: '${dir.path}/index.sqlite',
        watchFolders: false,
      );
      addTearDown(() async {
        library.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await dir.delete(recursive: true);
      });
      final settings = UyapSettings(
        directory: Directory('${dir.path}/destek'),
        home: '${dir.path}/ev',
      );

      // Nothing saved yet: no folder to search.
      expect(await searchUyapFolder(library, settings: settings), isFalse);

      await Directory(settings.folder).create(recursive: true);
      await settings.update(saveDocuments: false);
      expect(await searchUyapFolder(library, settings: settings), isFalse);

      await settings.update(saveDocuments: true);
      expect(await searchUyapFolder(library, settings: settings), isTrue);
      await library.waitForIdle();
      expect(library.sources.map((s) => s.path), [settings.folder]);
      // Asked again, at the next start or the next document: already there.
      expect(await searchUyapFolder(library, settings: settings), isFalse);
    },
  );

  test('the archive narrows to what is under one folder, a case’s, and '
      'widens again', () async {
    final dir = await Directory.systemTemp.createTemp('folio-uyap-icinde-');
    final library = LibraryController(
      databasePath: '${dir.path}/index.sqlite',
      watchFolders: false,
    );
    addTearDown(() async {
      library.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await dir.delete(recursive: true);
    });
    final root = await Directory('${dir.path}/UYAP').create();
    // Names a LIKE pattern would read as wildcards, and one that merely
    // starts the same way.
    final mine = await Directory('${root.path}/Aile_5 %1 2026-1204 Esas')
        .create();
    final other = await Directory('${root.path}/Aile_5 %1 2026-12045 Esas')
        .create();
    final also = await Directory('${root.path}/AileX5 x1 2026-1204 Esas')
        .create();
    await File('${mine.path}/rapor.txt').writeAsString('bilirkişi raporu');
    await File('${other.path}/dilekce.txt').writeAsString('dava dilekçesi');
    await File('${also.path}/karar.txt').writeAsString('ara karar');
    await library.addPaths([root.path]);
    await library.waitForIdle();
    library.filter(inside: mine.path);
    await library.searchNow();
    expect(library.hits.map((h) => h.file.name), ['rapor.txt']);
    library.filter(clearFolder: true);
    await library.searchNow();
    expect(library.matches, 3);
  });
}

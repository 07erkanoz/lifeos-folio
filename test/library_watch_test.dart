import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/services/search/index_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'watcher automatically indexes added, edited, moved and deleted files',
    () async {
      final dir = await Directory.systemTemp.createTemp('evrak-watch-');
      final source = await Directory('${dir.path}/documents').create();
      final library = LibraryController(
        databasePath: '${dir.path}/index.sqlite',
      );
      addTearDown(() async {
        library.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await dir.delete(recursive: true);
      });
      await library.addPaths([source.path]);
      await library.waitForIdle();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      Future<void> until(bool Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 12));
        while (DateTime.now().isBefore(deadline)) {
          await library.searchNow();
          if (condition()) return;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        fail('Automatic index update timed out: ${library.error}');
      }

      final file = await File('${source.path}/yeni.txt')
          .writeAsString('İhtiyati tedbir talebi');
      library.setQuery('tedbir');
      await until(() => library.matches == 1);
      await file.writeAsString('Kesinleşmiş karar bildirimi');
      await until(() => library.matches == 0);
      library.setQuery('kesinlesmis');
      await until(() => library.matches == 1);
      final moved = await file.rename('${source.path}/tasindi.txt');
      await until(() => library.hits.singleOrNull?.file.name == 'tasindi.txt');
      await moved.delete();
      await until(() => library.matches == 0);
      expect(library.error, isNull);
    },
  );

  test('quick look passages travel over the index isolate', () async {
    final dir = await Directory.systemTemp.createTemp('evrak-quicklook-');
    final source = await Directory('${dir.path}/documents').create();
    await File('${source.path}/karar.txt').writeAsString(
      'Baslangic bolumu. ${'Dolgu metni. ' * 60} İtiraz süresi on gündür.',
    );
    final library = LibraryController(
      databasePath: '${dir.path}/index.sqlite',
      watchFolders: false,
    );
    addTearDown(() async {
      library.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        /* Windows can still hold the index file open. */
      }
    });
    await library.addPaths([source.path]);
    await library.waitForIdle();
    library.setQuery('itiraz');
    await library.searchNow();
    final hit = library.hits.single;
    expect(hit.id, isNot(0), reason: 'the card needs a document to ask about');

    // A reply is matched to its caller by request id. An argument named 'id'
    // used to overwrite that, leaving the card waiting forever.
    final found = await library
        .passages(hit.id)
        .timeout(const Duration(seconds: 10));
    expect(found.matches, 1);
    expect(found.passages.single, contains('İtiraz süresi on gündür.'));
  });

  test('recent searches persist, deduplicate and clear; additions retain first index time', () async {
    final dir = await Directory.systemTemp.createTemp('evrak-history-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/index.sqlite';
    var db = IndexDatabase(path);
    final source = db.addSource('/archive', true, true);
    int register(String name, int modified) => db.registerFile(
      sourceId: source,
      token: 1,
      path: '/archive/$name.txt',
      size: 5,
      modified: modified,
      changed: 1,
      changedContent: true,
    );
    final old = register('once', 99999);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final added = register('yeni', 1);
    final timestamp = db.db.select('SELECT added FROM documents WHERE id=?', [
      old,
    ]).first['added'];
    register('once', 100000);
    expect(
      db.db.select('SELECT added FROM documents WHERE id=?', [
        old,
      ]).first['added'],
      timestamp,
    );
    expect((db.search({'sort': 'added'})['hits'] as List).first['id'], added);
    for (var i = 0; i < 15; i++) {
      db.rememberQuery('sorgu $i');
    }
    db.rememberQuery('İTİRAZ');
    db.rememberQuery('itiraz');
    expect(db.recentQueries().length, 12);
    expect(db.recentQueries().first, 'itiraz');
    db.close();
    db = IndexDatabase(path);
    expect(db.recentQueries().first, 'itiraz');
    db.clearHistory();
    expect(db.recentQueries(), isEmpty);
    db.close();
    // Upgrade a version-1 index without losing document contents.
    final legacy = sqlite3.open(path);
    legacy.execute('DROP INDEX documents_added');
    legacy.execute('ALTER TABLE documents DROP COLUMN added');
    // Everything later migrations added has to go too, or replaying them hits
    // a column that is already there.
    legacy.execute('DROP INDEX documents_ocr');
    legacy.execute('ALTER TABLE documents DROP COLUMN ocr');
    legacy.execute('DROP TABLE annotations');
    legacy.execute('PRAGMA user_version=1');
    legacy.dispose();
    db = IndexDatabase(path);
    expect(db.stats()['total'], 2);
    expect(db.db.select('PRAGMA user_version').first.values.first, 10);
    db.close();
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/search/index_database.dart';
import 'package:evrak_convert/services/search/index_service.dart';
import 'package:evrak_convert/services/search/search_models.dart';

void main() {
  test('1000 unchanged documents are reconciled without rewriting document rows', () async {
    final db = IndexDatabase(':memory:');
    addTearDown(db.close);
    final source = db.addSource('/benchmark', true, true);
    final files = List.generate(
      1000,
      (i) => (path: '/benchmark/$i.txt', size: 10, modified: 1, changed: 1),
    );
    db.beginScan(source);
    final pending = db.registerFiles(sourceId: source, token: 1, files: files);
    db.finishScan(source, 1);
    for (final file in pending) {
      db.setContent(file.id, 'örnek belge', 'ready', null);
    }
    // A trigger records persistent writes, excluding the temporary scan table.
    db.db.execute('CREATE TEMP TABLE audit(n INTEGER)');
    db.db.execute(
      'CREATE TEMP TRIGGER document_writes AFTER UPDATE ON documents BEGIN INSERT INTO audit VALUES(1); END',
    );
    db.db.execute(
      'CREATE TEMP TRIGGER membership_writes AFTER INSERT ON memberships BEGIN INSERT INTO audit VALUES(1); END',
    );
    final timer = Stopwatch()..start();
    db.beginScan(source);
    expect(db.registerFiles(sourceId: source, token: 2, files: files), isEmpty);
    db.finishScan(source, 2);
    expect(db.db.select('SELECT count(*) AS n FROM audit').single['n'], 0);
    expect(db.stats()['total'], 1000);
    // ignore: avoid_print
    print(
      '1000 unchanged records: ${timer.elapsedMilliseconds} ms; document/membership writes: 0',
    );
  });

  test('file updates and deletes do not walk the source again', () async {
    final dir = await Directory.systemTemp.createTemp('folio-incremental-');
    final source = await Directory('${dir.path}/documents').create();
    final file = await File('${source.path}/a.txt')
        .writeAsString('eski içerik');
    await File('${source.path}/b.txt').writeAsString('sabit belge');
    final service = await IndexService.open('${dir.path}/index.sqlite');
    try {
      await service.request('add', {
        'paths': [source.path],
      });
      await service.waitForIdle();
      final before = await service.request<Map>('diagnostics');
      await file.writeAsString('yeni değiştirilmiş içerik');
      await service.request('paths', {
        'paths': [file.path],
      });
      await service.waitForIdle();
      expect(
        (await service.search(const SearchQuery(text: 'değiştirilmiş'))).total,
        1,
      );
      final after = await service.request<Map>('diagnostics');
      expect(after['walks'], before['walks']);
      expect(after['extractedFiles'], before['extractedFiles'] + 1);
      await file.delete();
      await service.request('paths', {
        'paths': [file.path],
      });
      await service.waitForIdle();
      expect(
        (await service.search(const SearchQuery(text: 'değiştirilmiş'))).total,
        0,
      );
      expect((await service.search(const SearchQuery(text: 'sabit'))).total, 1);
      expect(
        (await service.request<Map>('diagnostics'))['walks'],
        before['walks'],
      );
    } finally {
      await service.close();
      await dir.delete(recursive: true);
    }
  });

  test('durable events survive restart; completing an old event preserves a newer event', () async {
    final dir = await Directory.systemTemp.createTemp('folio-durable-');
    final path = '${dir.path}/index.sqlite';
    final file = await File('${dir.path}/document.txt')
        .writeAsString('kalıcı kuyruk');
    var db = IndexDatabase(path);
    db.addSource(file.path, false, false);
    db.queuePaths([file.path]);
    final first = db.pendingPaths().single['id'] as int;
    db.queuePaths([file.path]);
    db.completePath(first);
    expect(db.pendingPaths(), hasLength(1));
    db.close();
    final service = await IndexService.open(path);
    try {
      await service.request('refresh');
      await service.waitForIdle();
      expect(
        (await service.search(const SearchQuery(text: 'kalıcı'))).total,
        1,
      );
    } finally {
      await service.close();
    }
    db = IndexDatabase(path);
    expect(db.pendingPaths(), isEmpty);
    db.close();
    await dir.delete(recursive: true);
  });

  test('overlapping roots share traversal and keep memberships; new subtree only scans itself', () async {
    final dir = await Directory.systemTemp.createTemp('folio-roots-');
    final nested = await Directory('${dir.path}/nested').create();
    await File('${dir.path}/root.txt').writeAsString('kök belge');
    await File('${nested.path}/a.txt').writeAsString('ortak belge');
    final service = await IndexService.open(':memory:');
    try {
      await service.request('add', {
        'paths': [dir.path, nested.path],
      });
      await service.waitForIdle();
      final before = await service.request<Map>('diagnostics');
      expect(before['walks'], 1);
      expect(before['extractedFiles'], 2);
      final newFolder = await Directory('${dir.path}/new').create();
      await File('${newFolder.path}/c.txt').writeAsString('yeni klasör');
      await service.request('paths', {
        'paths': [newFolder.path],
      });
      await service.waitForIdle();
      final after = await service.request<Map>('diagnostics');
      expect(after['metadataFiles'] - before['metadataFiles'], 1);
      expect((await service.request<Map>('catalog'))['total'], 3);
      await newFolder.delete(recursive: true);
      await service.request('paths', {
        'paths': [newFolder.path],
      });
      await service.waitForIdle();
      expect((await service.request<Map>('catalog'))['total'], 2);
      // A temporarily disconnected source must keep searchable records.
      final renamed = await dir.rename('${dir.path}-offline');
      await service.request('paths', {
        'paths': [dir.path],
      });
      await service.waitForIdle();
      expect((await service.request<Map>('catalog'))['total'], 2);
      await renamed.rename(dir.path);
    } finally {
      await service.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });
}

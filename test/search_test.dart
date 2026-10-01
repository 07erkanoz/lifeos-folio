import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:image/image.dart' as img;
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/docx/docx_bridge.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/services/search/index_database.dart';
import 'package:evrak_convert/services/search/index_service.dart';
import 'package:evrak_convert/services/search/search_models.dart';
import 'package:evrak_convert/services/search/text_extractor.dart';
import 'package:evrak_convert/ui/theme/theme_controller.dart';
import 'package:flutter/material.dart';

import 'support/pdfium.dart';

void main() {
  // PDFs are read with PDFium, which flutter_tester does not carry itself.
  configurePdfiumForTest();
  test('literal queries are safe and Turkish search is tolerant', () {
    expect(
      foldSearchText('İHTİYATİ HACİZ ÇAĞRI IŞIK ı'),
      'ihtiyati haciz cagri isik i',
    );
    expect(
      SearchQuery.expression('"itiraz süresi" 2026'),
      '"itiraz suresi" AND "2026"*',
    );
    expect(SearchQuery.expression('foo OR bar'), '"foo"* AND "or"* AND "bar"*');
    expect(SearchQuery.expression('*** : ( )'), '');
  });

  test('quick look returns the text around each match, not the first page', () {
    final db = IndexDatabase(':memory:');
    addTearDown(db.close);
    final source = db.addSource('/archive', true, true);
    final id = db.registerFile(
      sourceId: source,
      token: 1,
      path: '/archive/karar.udf',
      size: 10,
      modified: 1,
      changed: 1,
      changedContent: true,
    );
    final filler = 'Dolgu metni. ' * 40;
    db.setContent(
      id,
      'Baslangic bolumu. $filler '
          'İtiraz süresi on gündür. $filler '
          'Ayrıca İTİRAZ dilekçesi eklendi.',
      'ready',
      null,
    );

    final found = db.passages(id, 'itiraz');
    // Turkish İ folds to i, so both spellings count as the same word.
    expect(found['matches'], 2);
    final passages = (found['passages'] as List).cast<String>();
    expect(passages.length, 2);
    // Offsets map back to the original text, accents intact.
    expect(passages.first, contains('İtiraz süresi on gündür.'));
    expect(passages.first, startsWith('… '));
    expect(passages.last, contains('İTİRAZ dilekçesi eklendi.'));
    // The opening of the document is not what a search match shows.
    expect(passages.first, isNot(contains('Baslangic bolumu')));

    // Browsing without a query falls back to the opening lines.
    final opening = db.passages(id, '');
    expect(opening['matches'], 0);
    expect(
      (opening['passages'] as List).single,
      startsWith('Baslangic bolumu.'),
    );

    // A word that is not in the document also falls back rather than failing.
    expect(db.passages(id, 'bulunmayan')['matches'], 0);
  });

  test('a failed document is only parsed again when it changes', () {
    final db = IndexDatabase(':memory:');
    addTearDown(db.close);
    final source = db.addSource('/archive', true, true);
    const file = (
      path: '/archive/bulut.pdf',
      size: 10,
      modified: 5,
      changed: 5,
    );
    List<({int id, String path, int size, int modified, int changed})> scan(
      int token, {
      bool force = false,
      ({String path, int size, int modified, int changed}) entry = file,
    }) => db.registerFiles(
      sourceId: source,
      token: token,
      files: [entry],
      force: force,
    );

    expect(scan(1).length, 1, reason: 'a new file needs extraction');
    final id = db.document(file.path)!['id'] as int;
    db.setContent(id, '', 'error', 'Dosya cevrimdisi saklaniyor.');

    // An unreadable file used to be reopened on every launch, which kept the
    // indexer busy for as long as the file stayed unreadable.
    expect(scan(2), isEmpty);
    expect(db.document(file.path)!['state'], 'error');

    // An explicit rescan still retries it.
    expect(scan(3, force: true).length, 1);
    db.setContent(id, '', 'error', 'Dosya cevrimdisi saklaniyor.');

    // So does the file actually changing on disk.
    expect(
      scan(
        4,
        entry: (path: file.path, size: 11, modified: 6, changed: 6),
      ).length,
      1,
    );

    // Work interrupted by a shutdown is left pending and does resume.
    db.setContent(id, '', 'pending', null);
    expect(scan(5).length, 1);
  });

  test(
    'FTS ranks filename, filters sources/types and retains original excerpts',
    () {
      final db = IndexDatabase(':memory:');
      addTearDown(db.close);
      final source = db.addSource('/archive', true, true);
      for (var i = 0; i < 3; i++) {
        final id = db.registerFile(
          sourceId: source,
          token: 1,
          path: '/archive/${i == 0 ? 'İtiraz.udf' : 'karar$i.pdf'}',
          size: 100,
          modified: 100 + i,
          changed: 10,
          changedContent: true,
        );
        db.setContent(
          id,
          i == 0
              ? 'Süre hesaplandı.'
              : 'İhtiyati tedbir ve itiraz süresi değerlendirildi.',
          'ready',
          null,
        );
      }
      final result = db.search(const SearchQuery(text: 'itiraz').toMap());
      expect(result['total'], 3);
      expect((result['hits'] as List).first['name'], 'İtiraz.udf');
      final content = db.search(
        const SearchQuery(text: 'ihtiyati tedb').toMap(),
      );
      expect(content['total'], 2);
      expect(
        (content['hits'] as List).first['excerpt'],
        contains('İhtiyati tedbir'),
      );
      expect(
        db.search(
          const SearchQuery(text: 'ihtiyati', namesOnly: true).toMap(),
        )['total'],
        0,
      );
      expect(
        db.search(
          SearchQuery(
            text: 'itiraz',
            extensions: const ['udf'],
            sourceId: source,
          ).toMap(),
        )['total'],
        1,
      );
      expect(
        db.search(const SearchQuery(text: '"itiraz süresi"').toMap())['total'],
        2,
      );
      expect(
        db.search(const SearchQuery(text: '"süresi itiraz"').toMap())['total'],
        0,
      );
      expect(
        db.search(const SearchQuery(text: '" OR name:* --').toMap())['total'],
        0,
      );
      expect(
        db.search(const SearchQuery(limit: 2).toMap())['hits'],
        hasLength(2),
      );
      expect(
        db.search(const SearchQuery(limit: 2, offset: 2).toMap())['hits'],
        hasLength(1),
      );
    },
  );

  test('persistent index updates and removes changed files without touching sources', () async {
    final dir = await Directory.systemTemp.createTemp('evrak-index-');
    IndexService? service;
    try {
      final root = await Directory('${dir.path}/evrak').create();
      final nested = await Directory('${root.path}/alt').create();
      final text = File('${root.path}/dilekce.txt');
      await text.writeAsString('İhtiyati tedbir talebi');
      await File('${nested.path}/karar.udf').writeAsBytes(
        UdfWriter.writeBytes(
          DocModel(blocks: [DocBlock(plainText: 'Bozma kararı kesinleşti')]),
        ),
      );
      await File('${root.path}/belge.docx').writeAsBytes(
        await DocxBridge.writeBytes(
          DocModel(blocks: [DocBlock(plainText: 'Zamanaşımı itirazı')]),
        ),
      );
      final pdf = pw.Document()
        ..addPage(pw.Page(build: (_) => pw.Text('Appeal decision document')));
      await File('${root.path}/karar.pdf').writeAsBytes(await pdf.save());
      await File('${root.path}/tarama.png')
          .writeAsBytes(img.encodePng(img.Image(width: 20, height: 20)));
      await File('${root.path}/ignored.exe').writeAsString('secret keyword');
      final path = '${dir.path}/index.sqlite';
      service = await IndexService.open(path);
      await service.request('add', {
        'paths': [root.path],
        'recursive': true,
      });
      await service.waitForIdle();
      final stats = await service.request<Map>('catalog');
      expect(stats['total'], 5);
      expect(stats['ready'], 4);
      expect(stats['namesOnly'], 1);
      expect(
        (await service.search(const SearchQuery(text: 'ihtiyati'))).total,
        1,
      );
      expect(
        (await service.search(const SearchQuery(text: 'zamanaşımı'))).total,
        1,
      );
      expect((await service.search(const SearchQuery(text: 'bozma'))).total, 1);
      expect(
        (await service.search(const SearchQuery(text: 'appeal'))).total,
        1,
      );
      expect(
        (await service.search(const SearchQuery(text: 'secret'))).total,
        0,
      );
      expect(
        (await service.search(const SearchQuery(text: 'tarama')))
            .hits
            .single
            .state,
        'image',
      );
      await service.close();
      service = await IndexService.open(path);
      expect(
        (await service.search(const SearchQuery(text: 'ihtiyati'))).total,
        1,
      );
      await text.writeAsString('Kesin hüküm savunması');
      await File('${root.path}/karar.pdf').delete();
      await service.request('refresh');
      await service.waitForIdle();
      expect(
        (await service.search(const SearchQuery(text: 'ihtiyati'))).total,
        0,
      );
      expect(
        (await service.search(const SearchQuery(text: 'kesin hukum'))).total,
        1,
      );
      expect(
        (await service.search(const SearchQuery(text: 'appeal'))).total,
        0,
      );
      await service.request('refresh');
      await service.waitForIdle();
      expect((await service.request<Map>('catalog'))['pending'], 0);
      final ids = (await service.request<Map>('catalog'))['sources'] as List;
      await service.request('remove', {'sourceId': ids.single['id']});
      expect((await service.request<Map>('catalog'))['total'], 0);
      expect(await text.readAsString(), 'Kesin hüküm savunması');
    } finally {
      await service?.close();
      await dir.delete(recursive: true);
    }
  });

  test(
    'overlapping folders deduplicate and removal respects surviving membership',
    () async {
      final dir = await Directory.systemTemp.createTemp('evrak-overlap-');
      final service = await IndexService.open(':memory:');
      try {
        final nested = await Directory('${dir.path}/nested').create();
        await File('${nested.path}/a.txt').writeAsString('Ortak belge');
        await File('${dir.path}/root.txt').writeAsString('Kök belge');
        final ids = await service.request<List>('add', {
          'paths': [dir.path, nested.path],
        });
        await service.waitForIdle();
        expect((await service.request<Map>('catalog'))['total'], 2);
        await service.request('remove', {'sourceId': ids.first});
        expect((await service.request<Map>('catalog'))['total'], 1);
        await nested.rename('${dir.path}/unavailable');
        await service.request('refresh');
        await service.waitForIdle();
        final stats = await service.request<Map>('catalog');
        expect(
          stats['total'],
          1,
        ); // Temporarily unavailable roots retain their index.
        expect(
          (stats['sources'] as List).single['error'],
          contains('erişilebilir'),
        );
      } finally {
        await service.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'empty folder refresh prunes index, root-only scan excludes nested files',
    () async {
      final dir = await Directory.systemTemp.createTemp('evrak-prune-');
      final service = await IndexService.open(':memory:');
      try {
        await Directory('${dir.path}/nested').create();
        final file = File('${dir.path}/one.txt');
        await file.writeAsString('Birinci içerik');
        await File('${dir.path}/nested/two.txt').writeAsString('İkinci içerik');
        await service.request('add', {
          'paths': [dir.path],
          'recursive': false,
        });
        await service.waitForIdle();
        expect((await service.request<Map>('catalog'))['total'], 1);
        await file.delete();
        await service.request('refresh');
        await service.waitForIdle();
        expect((await service.request<Map>('catalog'))['total'], 0);
      } finally {
        await service.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test('search stays responsive while indexing and cancellation leaves resumable work', () async {
    final dir = await Directory.systemTemp.createTemp('evrak-cancel-');
    final service = await IndexService.open(':memory:');
    try {
      for (var i = 0; i < 80; i++) {
        await File('${dir.path}/evrak$i.txt')
            .writeAsString('Duruşma tutanağı $i');
      }
      await service.request('add', {
        'paths': [dir.path],
      });
      final page = await service
          .search(const SearchQuery(text: 'evrak'))
          .timeout(const Duration(seconds: 3));
      expect(page.total, greaterThanOrEqualTo(0));
      await service.request('cancel');
      await service.waitForIdle();
      await service.request('refresh');
      await service.waitForIdle();
      expect(
        (await service.search(const SearchQuery(text: 'durusma'))).total,
        80,
      );
    } finally {
      await service.close();
      await dir.delete(recursive: true);
    }
  });

  test('UTF16 and Windows1254 extraction preserves Turkish text', () {
    final units = 'İtiraz ışık'.codeUnits;
    final bytes = Uint8List.fromList([
      255,
      254,
      for (final c in units) ...[c & 255, c >> 8],
    ]);
    expect(IndexTextExtractor.decodeText(bytes), 'İtiraz ışık');
    expect(
      IndexTextExtractor.decodeText(
        Uint8List.fromList([0xdd, 0xfe, 0xfd, 0xf0]),
      ),
      'İşığ',
    );
  });

  test('theme choice persists across restarts', () async {
    final dir = await Directory.systemTemp.createTemp('evrak-theme-');
    final path = '${dir.path}/appearance.json';
    final controller = ThemeController(settingsPath: path);
    final restored = ThemeController(settingsPath: path);
    try {
      await controller.load();
      controller.setMode(ThemeMode.light);
      controller.setMode(ThemeMode.dark);
      await controller.saved;
      await restored.load();
      expect(restored.mode, ThemeMode.dark);
      expect(jsonDecode(await File(path).readAsString())['theme'], 'dark');
    } finally {
      controller.dispose();
      restored.dispose();
      await dir.delete(recursive: true);
    }
  });

  test('10,000 indexed documents can be searched without reading source files', () {
    final db = IndexDatabase(':memory:');
    addTearDown(db.close);
    final root = db.addSource('/not-on-disk', true, true);
    for (var i = 0; i < 10000; i++) {
      final id = db.registerFile(
        sourceId: root,
        token: 1,
        path: '/not-on-disk/evrak$i.txt',
        size: 50,
        modified: i,
        changed: i,
        changedContent: true,
      );
      db.setContent(
        id,
        i % 100 == 0
            ? 'İhtiyati tedbir değerlendirmesi $i'
            : 'Duruşma tutanağı ve karar $i',
        'ready',
        null,
      );
    }
    final result = db.search(const SearchQuery(text: 'ihtiyati tedb').toMap());
    expect(result['total'], 100);
    expect(result['hits'], hasLength(50));
    // Diagnostic only: absolute timing depends on CI hardware.
    // ignore: avoid_print
    print(
      'FTS5 / 10,000 documents: ${((result['elapsedMicros'] as int) / 1000).toStringAsFixed(2)} ms',
    );
  });
}

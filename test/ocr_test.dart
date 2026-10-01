import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/ocr/ocr_service.dart';
import 'package:evrak_convert/services/ocr/preview_ocr.dart';
import 'package:evrak_convert/services/search/index_database.dart';
import 'package:evrak_convert/services/search/index_service.dart';
import 'package:evrak_convert/services/search/search_models.dart';
import 'package:evrak_convert/services/search/text_extractor.dart';

import 'support/pdfium.dart';

/// A rendered page of Turkish legal text, drawn with the Liberation serif the
/// app already ships so the fixture needs no font from the host.
const fixture = 'test/fixtures/ocr_taranmis.png';

/// The same page inside a PDF with no text layer — what a scanner produces.
const scannedPdf = 'test/fixtures/ocr_taranmis.pdf';

/// The same page three times in one TIFF, which is how a court scan of a whole
/// filing arrives. Built with the bundled tiffcp so the pages are real image
/// directories rather than something only this test would accept.
const multiPageTiff = 'test/fixtures/ocr_cok_sayfali.tif';

void main() {
  setUp(OcrService.resetForTest);

  test('a rendered page goes to Tesseract as a TIFF read from memory', () {
    // Two pixels of PDFium BGRA: pure blue, then white. Leptonica reads a
    // PNM from memory through a temporary file on Windows; a TIFF it reads
    // through its own memory stream, so the page never touches the disk.
    final tiff = OcrService.toGrayTiff(
      Uint8List.fromList([255, 0, 0, 255, 255, 255, 255, 255]),
      2,
      1,
    );
    final data = ByteData.sublistView(tiff);
    expect(String.fromCharCodes(tiff.sublist(0, 2)), 'II');
    expect(data.getUint16(2, Endian.little), 42);
    final directory = data.getUint32(4, Endian.little);
    final tags = <int, int>{};
    for (var i = 0; i < data.getUint16(directory, Endian.little); i++) {
      final at = directory + 2 + i * 12;
      final type = data.getUint16(at + 2, Endian.little);
      tags[data.getUint16(at, Endian.little)] = type == 3
          ? data.getUint16(at + 8, Endian.little)
          : data.getUint32(at + 8, Endian.little);
    }
    expect(tags[256], 2); // width
    expect(tags[257], 1); // height
    expect(tags[258], 8); // one byte a pixel
    expect(tags[259], 1); // uncompressed
    expect(tags[262], 1); // black is zero
    expect(tags.containsKey(282), isFalse, reason: 'çözünürlük tahmin edilir');
    final pixels = tiff.sublist(tags[273]!, tags[273]! + tags[279]!);
    // Blue is dark in luma (29/256 of full), white stays white: the channels
    // are read as BGRA, not RGBA.
    expect(pixels, [(255 * 29) >> 8, 255]);
  });

  test('an image is left name-only while OCR is off', () async {
    final result = await IndexTextExtractor.extract(fixture);
    expect(result['state'], 'image');
    expect(result['text'], '');
    expect(result['note'], contains('OCR'));
  });

  test('turning OCR off is what keeps a scan unsearchable, not the file', () async {
    // The same file must be able to produce both outcomes; otherwise the switch
    // is not what decides and the setting is a lie.
    final off = await IndexTextExtractor.extract(fixture, ocr: false);
    expect(off['state'], 'image');
    if (!await OcrService.available) return;
    final on = await IndexTextExtractor.extract(fixture, ocr: true);
    expect(on['state'], 'ready');
  });

  test('the Tesseract Folio ships reads words with confidences from its models alone', () async {
    // The shipped tessdata holds the models and nothing else. Asking for
    // TSV through the `tsv` config file worked against a system Tesseract,
    // whose tessdata has the file, and read nothing in the installed app.
    final platform = Platform.isWindows ? 'windows-x64' : 'linux-x64';
    final binary = File(
      'native_tools/$platform/bin/tesseract${Platform.isWindows ? '.exe' : ''}',
    );
    if (!(Platform.isLinux || Platform.isWindows) || !binary.existsSync()) {
      markTestSkipped('paketlenmiş tesseract yok');
      return;
    }
    final result = await Process.run(
      binary.path,
      [
        fixture,
        '-',
        '-l',
        OcrService.language,
        '--psm',
        '3',
        ...OcrService.tsv,
      ],
      environment: {'TESSDATA_PREFIX': 'native_tools/$platform/tessdata'},
      stdoutEncoding: utf8,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stderr, isNot(contains("Can't open")));
    final page = OcrPageRead.fromTsv(result.stdout as String);
    expect(page.words, greaterThan(0));
    expect(page.text, contains('2026/123'));
  });

  test('OCR reads Turkish text out of an image', () async {
    if (!await OcrService.available) {
      markTestSkipped('tesseract kurulu değil');
      return;
    }
    final text = await OcrService.recognize(fixture, EvrakFormat.image);
    expect(text, isNotNull);
    expect(text, contains('2026/123'));
    // Tesseract writes UTF-8. Decoding its output byte-per-character puts
    // 'AÄ°LE' in the search index instead of 'AİLE', and every Turkish query
    // then misses the document. Assert the letters themselves, not the ASCII
    // around them, or the mistake passes unnoticed. The fixture carries every
    // letter Turkish adds to the alphabet.
    expect(text, contains('AİLE'));
    expect(text, contains('açılan'));
    expect(text, contains('saygıyla'));
    expect(text, contains('Çiğdem Şenoğlu'));
    expect(text, isNot(contains('Ä')));
  });

  test('a scanned PDF is read page by page', () async {
    // flutter_tester ships no PDFium beside it; the built bundle does.
    final bundled = pdfiumLibrary();
    if (!await OcrService.available || bundled == null) {
      markTestSkipped('tesseract veya paketlenmiş PDFium yok');
      return;
    }
    OcrService.pdfiumPathOverride = bundled;
    addTearDown(() => OcrService.pdfiumPathOverride = null);

    final dir = await Directory.systemTemp.createTemp('folio-ocr-pdf-');
    addTearDown(() => dir.delete(recursive: true));
    final pdf = File('${dir.path}/taranmis.pdf');
    await pdf.writeAsBytes(await File(scannedPdf).readAsBytes());

    final result = await IndexTextExtractor.extract(pdf.path, ocr: true);
    expect(result['state'], 'ready');
    expect(result['text'], contains('AİLE'));
    expect(result['text'], contains('Şenoğlu'));
    expect(result['text'], contains('2026/123'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a recognized image is indexed as ready and says so', () async {
    if (!await OcrService.available) {
      markTestSkipped('tesseract kurulu değil');
      return;
    }
    final result = await IndexTextExtractor.extract(fixture, ocr: true);
    expect(result['state'], 'ready');
    expect(result['text'], contains('DOSYA'));
    expect(result['note'], contains('OCR'));
  });

  test(
    'an unreadable image stays name-only rather than becoming an error',
    () async {
      final dir = await Directory.systemTemp.createTemp('folio-ocr-blank-');
      addTearDown(() => dir.delete(recursive: true));
      final blank = File('${dir.path}/bos.png');
      // A real PNG with nothing in it: OCR finds no words and the document must
      // fall back to name-only search, not be recorded as damaged.
      await blank.writeAsBytes(await File(fixture).readAsBytes());
      await blank.writeAsBytes(_blankPng());
      final result = await IndexTextExtractor.extract(blank.path, ocr: true);
      expect(result['state'], 'image');
      expect(result['state'], isNot('error'));
    },
  );

  test('OCR is unavailable without the tool, and recognize says so', () async {
    if (await OcrService.available) return;
    expect(await OcrService.recognize(fixture, EvrakFormat.image), isNull);
  });

  test('the index worker accepts the OCR switch', () async {
    final dir = await Directory.systemTemp.createTemp('folio-ocr-cmd-');
    addTearDown(() => dir.delete(recursive: true));
    final service = await IndexService.open('${dir.path}/index.sqlite');
    addTearDown(service.close);
    // The command must round-trip: an unknown command throws, so reaching the
    // reply proves the worker understands it.
    await service
        .request<void>('ocr', {'enabled': true})
        .timeout(const Duration(seconds: 10));
    await service
        .request<void>('ocr', {'enabled': false})
        .timeout(const Duration(seconds: 10));
  });

  test('turning OCR on queues the documents it can help, and only those', () async {
    if (!await OcrService.available) {
      markTestSkipped('tesseract kurulu değil');
      return;
    }
    final dir = await Directory.systemTemp.createTemp('folio-ocr-switch-');
    addTearDown(() => dir.delete(recursive: true));
    await File('${dir.path}/taranmis.png')
        .writeAsBytes(await File(fixture).readAsBytes());
    // A document that is already searchable must not be re-read: a full rescan
    // would cost the whole archive to reach the part that needs OCR.
    await File('${dir.path}/okunabilir.txt')
        .writeAsString('Bu belgenin metni zaten var.');

    final service = await IndexService.open('${dir.path}/index.sqlite');
    addTearDown(service.close);
    await service.request('add', {
      'paths': [dir.path],
      'recursive': true,
    });
    await service.waitForIdle();

    var page = await service.search(const SearchQuery(text: ''));
    expect(
      page.hits.firstWhere((h) => h.file.name.endsWith('.png')).state,
      'image',
    );

    // Exactly the image is queued; the text file is already ready.
    final queued = await service.request<int>('ocr', {'enabled': true});
    expect(queued, 1);
    await service.waitForIdle();

    page = await service.search(const SearchQuery(text: ''));
    expect(
      page.hits.firstWhere((h) => h.file.name.endsWith('.png')).state,
      'ready',
    );
    final found = await service.search(const SearchQuery(text: 'mahkeme'));
    expect(found.total, 1, reason: 'taranmış belge artık aranabilir olmalı');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('restoring the saved setting at startup queues nothing', () async {
    final dir = await Directory.systemTemp.createTemp('folio-ocr-restore-');
    addTearDown(() => dir.delete(recursive: true));
    final service = await IndexService.open('${dir.path}/index.sqlite');
    addTearDown(service.close);
    // Otherwise every launch would re-read every scan in the archive.
    final queued = await service.request<int>('ocr', {
      'enabled': true,
      'reprocess': false,
    });
    expect(queued, 0);
  });

  test(
    'OCR-read documents are marked, counted and can be listed on their own',
    () async {
      if (!await OcrService.available) {
        markTestSkipped('tesseract kurulu değil');
        return;
      }
      final dir = await Directory.systemTemp.createTemp('folio-ocr-filter-');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/taranmis.png')
          .writeAsBytes(await File(fixture).readAsBytes());
      await File('${dir.path}/okunabilir.txt')
          .writeAsString('MANAVGAT mahkeme kararı, metni zaten var.');

      final service = await IndexService.open('${dir.path}/index.sqlite');
      addTearDown(service.close);
      await service.request('add', {
        'paths': [dir.path],
        'recursive': true,
      });
      await service.waitForIdle();

      var stats = await service.request<Map>('catalog');
      expect(
        stats['ocr'],
        0,
        reason: 'OCR kapalıyken hiçbiri işaretli olmamalı',
      );

      await service.request<int>('ocr', {'enabled': true});
      await service.waitForIdle();

      stats = await service.request<Map>('catalog');
      expect(stats['ocr'], 1);

      // Both documents match the word; the filter must return only the scanned
      // one, so a reader can tell recognised text from text the file carried.
      final all = await service.search(const SearchQuery(text: 'mahkeme'));
      expect(all.total, 2);
      final onlyOcr = await service.search(
        const SearchQuery(text: 'mahkeme', ocrOnly: true),
      );
      expect(onlyOcr.total, 1);
      expect(onlyOcr.hits.single.file.name, endsWith('.png'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('an index from the previous version gains the OCR column', () async {
    final dir = await Directory.systemTemp.createTemp('folio-ocr-migrate-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/index.sqlite';
    var db = IndexDatabase(path);
    expect(db.db.select('PRAGMA user_version').first.values.first, 10);
    // The index is built on the column, so it goes first; this is only here to
    // fake an older database, the migration itself creates them in order.
    db.db.execute('DROP INDEX documents_ocr');
    db.db.execute('ALTER TABLE documents DROP COLUMN ocr');
    db.db.execute('PRAGMA user_version=5');
    db.close();

    db = IndexDatabase(path);
    addTearDown(db.close);
    expect(db.db.select('PRAGMA user_version').first.values.first, 10);
    expect(db.stats()['ocr'], 0);
  });

  test('interface assets are skipped instead of costing a process each', () async {
    if (!await OcrService.available) {
      markTestSkipped('tesseract kurulu değil');
      return;
    }
    final dir = await Directory.systemTemp.createTemp('folio-ocr-icons-');
    addTearDown(() => dir.delete(recursive: true));
    // A GTK icon theme dropped into an archive folder is thousands of files
    // this size. None can hold a readable word, and each would otherwise launch
    // Tesseract to read nothing.
    final icon = File('${dir.path}/icon.png');
    await icon.writeAsBytes(_blankPng()); // 8x8
    expect(await OcrService.recognize(icon.path, EvrakFormat.image), isNull);
    final result = await IndexTextExtractor.extract(icon.path, ocr: true);
    expect(result['state'], 'image');

    // The real fixture is well above the floor and still read.
    expect(await OcrService.recognize(fixture, EvrakFormat.image), isNotNull);
  });

  test('the floor sits between interface assets and real document photos', () {
    // Measured on a real archive: the largest icon in a GTK theme was 108 px on
    // its short side and the smallest genuine document image 270 px, with
    // WhatsApp photos from 720 px up. A floor that drifted into that gap would
    // silently stop indexing photographed documents, which is the case OCR
    // exists for.
    expect(
      OcrService.minSide,
      greaterThan(108),
      reason: 'arayüz ikonları elenmeli',
    );
    expect(
      OcrService.minSide,
      lessThan(270),
      reason: 'gerçek belge fotoğrafı elenmemeli',
    );
  });

  test('SVG never reaches OCR, because Leptonica cannot decode it', () async {
    if (!await OcrService.available) {
      markTestSkipped('tesseract kurulu değil');
      return;
    }
    final dir = await Directory.systemTemp.createTemp('folio-ocr-svg-');
    addTearDown(() => dir.delete(recursive: true));
    final svg = File('${dir.path}/cizim.svg');
    await svg.writeAsString(
      '<svg xmlns="http://www.w3.org/2000/svg" width="800" height="600">'
      '<text x="20" y="40">MAHKEMESİ</text></svg>',
    );
    // Large enough to pass the size floor, so this proves the format check and
    // not the dimension one.
    expect(await OcrService.recognize(svg.path, EvrakFormat.svg), isNull);
  });

  test(
    'OCR can be aimed at one folder, leaving the rest of the archive alone',
    () async {
      if (!await OcrService.available) {
        markTestSkipped('tesseract kurulu değil');
        return;
      }
      final dir = await Directory.systemTemp.createTemp('folio-ocr-scope-');
      addTearDown(() => dir.delete(recursive: true));
      final wanted = Directory('${dir.path}/taranmislar')..createSync();
      final other = Directory('${dir.path}/diger')..createSync();
      final deep = Directory('${wanted.path}/alt')..createSync();
      for (final d in [wanted, other, deep]) {
        await File('${d.path}/sayfa.png')
            .writeAsBytes(await File(fixture).readAsBytes());
      }

      final service = await IndexService.open('${dir.path}/index.sqlite');
      addTearDown(service.close);
      await service.request('add', {
        'paths': [dir.path],
        'recursive': true,
      });
      await service.waitForIdle();

      // No folder chosen yet: the whole archive is in scope.
      expect(await service.request<int>('ocrCandidates'), 3);

      // One folder, subfolders included: the sibling stays out.
      var candidates = await service.request<int>('addOcrPath', {
        'path': wanted.path,
        'recursive': true,
      });
      expect(candidates, 2);

      await service.request<int>('ocr', {'enabled': true});
      await service.waitForIdle();

      final page = await service.search(const SearchQuery(text: 'mahkeme'));
      final read = page.hits.map((h) => h.file.path).toList();
      // Compared as paths, not as text: this test builds its folders with '/'
      // while the index stores what the platform uses, so on Windows a plain
      // startsWith compares "…xxx/taranmislar" against "…xxx	aranmislar" and
      // fails on a scope that is actually correct.
      expect(read.any((hit) => p.isWithin(wanted.path, hit)), isTrue);
      expect(
        read.any((hit) => p.isWithin(other.path, hit)),
        isFalse,
        reason: 'kapsam dışı klasör okunmamalı',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('a folder without its subfolders covers only its own files', () async {
    final dir = await Directory.systemTemp.createTemp('folio-ocr-flat-');
    addTearDown(() => dir.delete(recursive: true));
    final top = Directory('${dir.path}/ust')..createSync();
    final deep = Directory('${top.path}/alt')..createSync();
    for (final d in [top, deep]) {
      await File('${d.path}/sayfa.png')
          .writeAsBytes(await File(fixture).readAsBytes());
    }
    // A sibling whose name starts with the chosen folder's name must not be
    // swept in by a prefix match.
    final lookalike = Directory('${dir.path}/ust eski')..createSync();
    await File('${lookalike.path}/sayfa.png')
        .writeAsBytes(await File(fixture).readAsBytes());

    final service = await IndexService.open('${dir.path}/index.sqlite');
    addTearDown(service.close);
    await service.request('add', {
      'paths': [dir.path],
      'recursive': true,
    });
    await service.waitForIdle();

    final candidates = await service.request<int>('addOcrPath', {
      'path': top.path,
      'recursive': false,
    });
    expect(candidates, 1, reason: 'yalnız o klasördeki tek dosya');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('OCR folder matching treats percent and underscore literally', () {
    final db = IndexDatabase(':memory:');
    addTearDown(db.close);
    final source = db.addSource('/arsiv', true, true);
    for (final (index, path) in <String>[
      '/arsiv/dava_2026/belge.png',
      '/arsiv/davaX2026/belge.png',
      '/arsiv/%10/belge.png',
      '/arsiv/110/belge.png',
      '/arsiv/📁_dava/belge.png',
    ].indexed) {
      final id = db.registerFile(
        sourceId: source,
        token: 1,
        path: path,
        size: 10,
        modified: index + 1,
        changed: index + 1,
        changedContent: true,
      );
      db.setContent(id, '', 'image', null);
    }

    db.addOcrPath('/arsiv/dava_2026', true);
    expect(db.ocrCandidates(), 1, reason: 'alt çizgi joker olmamalı');
    db.removeOcrPath(db.ocrPaths().single['id'] as int);
    db.addOcrPath('/arsiv/%10', true);
    expect(db.ocrCandidates(), 1, reason: 'yüzde işareti joker olmamalı');
    db.removeOcrPath(db.ocrPaths().single['id'] as int);
    db.addOcrPath('/arsiv/📁_dava', true);
    expect(
      db.ocrCandidates(),
      1,
      reason: 'Unicode klasör uzunluğu SQLite tarafında hesaplanmalı',
    );
  });

  test('OCR candidates exclude formats recognition cannot improve', () {
    final db = IndexDatabase(':memory:');
    addTearDown(db.close);
    final source = db.addSource('/arsiv', true, true);
    for (final (index, entry) in <(String, String)>[
      ('taranmis.pdf', 'no_text'),
      ('fotograf.png', 'image'),
      ('bos.txt', 'no_text'),
      ('cizim.svg', 'image'),
    ].indexed) {
      final id = db.registerFile(
        sourceId: source,
        token: 1,
        path: '/arsiv/${entry.$1}',
        size: 10,
        modified: index + 1,
        changed: index + 1,
        changedContent: true,
      );
      db.setContent(id, '', entry.$2, null);
    }

    expect(db.ocrCandidates(), 2);
    expect(db.markUnreadableForOcr(), 2);
    expect(
      db.db
          .select("SELECT extension FROM documents WHERE state='pending'")
          .map((row) => row['extension']),
      unorderedEquals(['pdf', 'png']),
    );
  });

  test(
    'documents read before the flag existed are backfilled from their note',
    () async {
      // 409 documents in a real archive had been read by OCR before the column
      // was added, so the filter would have stayed hidden until every scan was
      // read a second time.
      final dir = await Directory.systemTemp.createTemp('folio-ocr-backfill-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/index.sqlite';
      var db = IndexDatabase(path);
      final source = db.addSource('/arsiv', true, true);
      final id = db.registerFile(
        sourceId: source,
        token: 1,
        path: '/arsiv/taranmis.jpg',
        size: 10,
        modified: 1,
        changed: 1,
        changedContent: true,
      );
      db.setContent(
        id,
        'MAHKEMESİ',
        'ready',
        'Metin taranmış sayfalardan okundu (OCR); tanıma hataları olabilir.',
      );
      // Simulate the row as the older build left it: read by OCR, unflagged.
      db.db.execute('UPDATE documents SET ocr=0');
      db.db.execute('PRAGMA user_version=7');
      expect(db.stats()['ocr'], 0);
      db.close();

      db = IndexDatabase(path);
      addTearDown(db.close);
      expect(db.db.select('PRAGMA user_version').first.values.first, 10);
      expect(db.stats()['ocr'], 1, reason: 'not alanından geriye doldurulmalı');
      expect(db.documentText('/arsiv/taranmis.jpg'), contains('MAHKEMESİ'));
    },
  );

  test('text is only offered for documents OCR actually read', () {
    final db = IndexDatabase(':memory:');
    addTearDown(db.close);
    final source = db.addSource('/arsiv', true, true);
    final id = db.registerFile(
      sourceId: source,
      token: 1,
      path: '/arsiv/normal.pdf',
      size: 10,
      modified: 1,
      changed: 1,
      changedContent: true,
    );
    // A document that carried its own text must not be presented as recognised.
    db.setContent(id, 'Belgenin kendi metni', 'ready', null);
    expect(db.documentText('/arsiv/normal.pdf'), isNull);
    expect(db.documentText('/arsiv/yok.pdf'), isNull);
  });

  test('the editor only reuses current native PDF text', () {
    final db = IndexDatabase(':memory:');
    addTearDown(db.close);
    final source = db.addSource('/arsiv', true, true);
    final id = db.registerFile(
      sourceId: source,
      token: 1,
      path: '/arsiv/normal.pdf',
      size: 123,
      modified: 456,
      changed: 456,
      changedContent: true,
    );
    db.setContent(id, 'PDF kendi metni', 'ready', null);

    expect(
      db.nativeDocumentText('/arsiv/normal.pdf', 123, 456),
      'PDF kendi metni',
    );
    expect(
      db.nativeDocumentText('/arsiv/normal.pdf', 124, 456),
      isNull,
      reason: 'değişmiş dosyada eski indeks metni kullanılmamalı',
    );

    db.setContent(id, 'Yaklaşık OCR metni', 'ready', null, ocr: true);
    expect(
      db.nativeDocumentText('/arsiv/normal.pdf', 123, 456),
      isNull,
      reason: 'OCR çıktısı doğal metin katmanı gibi düzenlenmemeli',
    );
  });

  test('fullWidth is what scales the page into the buffer', () async {
    // width/height alone only size the output buffer. Without fullWidth and
    // fullHeight the page is drawn at its natural 72 dpi into the corner of a
    // large white canvas, so OCR reads tiny text padded with blank space. The
    // text it produced still looked plausible, which is why an end-to-end
    // assertion did not catch it; this compares the two renders directly.
    final bundled = pdfiumLibrary();
    if (bundled == null) {
      markTestSkipped('paketlenmiş PDFium yok');
      return;
    }
    Pdfrx.pdfiumModulePath ??= bundled;
    await pdfrxInitialize();
    final doc = await PdfDocument.openFile(scannedPdf);
    addTearDown(doc.dispose);
    final page = doc.pages.first;
    final w = (page.width * OcrService.renderDpi / 72).round();
    final h = (page.height * OcrService.renderDpi / 72).round();

    int rightmostInk(PdfImage img) {
      var found = 0;
      for (var y = 0; y < img.height; y += 4) {
        for (var x = img.width - 1; x > found; x--) {
          if (img.pixels[(y * img.width + x) * 4] < 200) {
            found = x;
            break;
          }
        }
      }
      return found;
    }

    final scaled = await page.render(
      width: w,
      height: h,
      fullWidth: w.toDouble(),
      fullHeight: h.toDouble(),
      backgroundColor: 0xFFFFFFFF,
    );
    final unscaled = await page.render(
      width: w,
      height: h,
      backgroundColor: 0xFFFFFFFF,
    );
    expect(scaled, isNotNull);
    expect(unscaled, isNotNull);
    // The page is rendered larger, so its ink reaches further across the buffer.
    expect(
      rightmostInk(scaled!),
      greaterThan((rightmostInk(unscaled!) * 1.5).round()),
      reason: 'ölçekleme olmadan sayfa tuvalin köşesinde kalır',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a document outside the archive can still be read on demand', () async {
    if (!await OcrService.available) {
      markTestSkipped('tesseract kurulu değil');
      return;
    }
    // Folio is a viewer as much as an archive: a file opened from the desktop
    // has no index entry, so nothing has ever read it.
    final dir = await Directory.systemTemp.createTemp('folio-ocr-demand-');
    addTearDown(() => dir.delete(recursive: true));
    final loose = File('${dir.path}/taranmis.png');
    await loose.writeAsBytes(await File(fixture).readAsBytes());

    final ocr = PreviewOcr();
    addTearDown(ocr.dispose);
    await ocr.attach(loose.path, EvrakFormat.image);
    expect(ocr.text, isNull, reason: 'indekste olmadığı için metin yok');
    expect(ocr.canRun, isTrue, reason: 'okuma teklif edilmeli');

    await ocr.run(EvrakFormat.image);
    expect(ocr.running, isFalse);
    expect(ocr.text, contains('AİLE'));
    expect(ocr.error, isNull);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('reading on demand adds nothing to the archive', () async {
    if (!await OcrService.available) {
      markTestSkipped('tesseract kurulu değil');
      return;
    }
    final dir = await Directory.systemTemp.createTemp('folio-ocr-noindex-');
    addTearDown(() => dir.delete(recursive: true));
    final loose = File('${dir.path}/taranmis.png');
    await loose.writeAsBytes(await File(fixture).readAsBytes());

    final service = await IndexService.open('${dir.path}/index.sqlite');
    addTearDown(service.close);
    final before = await service.request<Map>('catalog');

    final ocr = PreviewOcr();
    addTearDown(ocr.dispose);
    await ocr.attach(loose.path, EvrakFormat.image);
    await ocr.run(EvrakFormat.image);
    expect(ocr.text, isNotNull);

    // Looking at a document must not quietly add it to the archive.
    final after = await service.request<Map>('catalog');
    expect(after['total'], before['total']);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('formats OCR cannot help are not offered a button', () async {
    final dir = await Directory.systemTemp.createTemp('folio-ocr-offer-');
    addTearDown(() => dir.delete(recursive: true));
    final svg = File('${dir.path}/cizim.svg');
    await svg.writeAsString('<svg xmlns="http://www.w3.org/2000/svg"/>');
    final ocr = PreviewOcr();
    addTearDown(ocr.dispose);
    await ocr.attach(svg.path, EvrakFormat.svg);
    expect(ocr.canRun, isFalse, reason: 'SVG çözülemez, teklif edilmemeli');

    final txt = File('${dir.path}/not.txt');
    await txt.writeAsString('kendi metni var');
    await ocr.attach(txt.path, EvrakFormat.text);
    expect(ocr.canRun, isFalse, reason: 'metin belgesi zaten okunabilir');
  });

  test('both models ship, so the split between quick and careful is real', () {
    // The archive pass walks hundreds of documents and cannot spend 6 s a page;
    // one document the reader asked for can. That only means something if both
    // models are actually in the bundle.
    final dir = Directory('native_tools/linux-x64/tessdata');
    if (!dir.existsSync()) {
      markTestSkipped('paketlenmiş tessdata yok');
      return;
    }
    expect(
      File('${dir.path}/${OcrService.language}.traineddata').existsSync(),
      isTrue,
    );
    expect(
      File('${dir.path}/${OcrService.thoroughLanguage}.traineddata')
          .existsSync(),
      isTrue,
    );
    expect(OcrService.language, isNot(OcrService.thoroughLanguage));
  });

  test(
    'asking for the careful model falls back when it is not installed',
    () async {
      if (!await OcrService.available) {
        markTestSkipped('tesseract kurulu değil');
        return;
      }
      // A system Tesseract has only its own models. Asking for the careful one
      // must quietly use the quick one rather than failing to read at all.
      final careful = await OcrService.recognize(
        fixture,
        EvrakFormat.image,
        thorough: true,
      );
      expect(careful, isNotNull, reason: 'model yoksa da metin dönmeli');
      expect(careful, contains('AİLE'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('a scanned filing is counted by its pages, not taken for one', () async {
    // Court scans arrive as one TIFF holding the whole filing. Counting that as
    // a single page is what let a long document be killed part-read.
    expect(await OcrService.tiffPages(File(multiPageTiff)), 3);
  });

  test(
    'an unreadable header is read as one page rather than refused',
    () async {
      final dir = await Directory.systemTemp.createTemp('folio-tiff');
      addTearDown(() => dir.delete(recursive: true));
      final junk = File('${dir.path}/not-a-tiff.tif');
      await junk.writeAsBytes(_blankPng());
      // Guessing one page only restores the old budget; refusing would make a
      // file OCR used to read unreadable.
      expect(await OcrService.tiffPages(junk), 1);
    },
  );

  test('every page of a multi-page scan is read, not just the first', () async {
    if (!await OcrService.available) return;
    final text = await OcrService.recognize(multiPageTiff, EvrakFormat.tif);
    expect(text, isNotNull);
    // The fixture repeats one page three times, so a reader that stops early
    // still returns text and only the count betrays it.
    expect(
      'AİLE'.allMatches(text!).length,
      3,
      reason: 'üç sayfanın üçü de okunmalı',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('the time budget follows the page count and then stops', () {
    // A per-page budget spent on a whole document is what threw the work away:
    // Tesseract was killed mid-scan and the reader was told no text was found.
    final one = OcrService.budgetFor(1);
    expect(OcrService.budgetFor(12), one * 12);
    expect(
      OcrService.budgetFor(500),
      one * OcrService.maxPages,
      reason: 'bozuk bir başlık günlerce süren bir süreç bırakmamalı',
    );
    expect(
      OcrService.budgetFor(0),
      one,
      reason: 'sayfa sayısı hiç sıfır olmamalı',
    );
  });
}

/// Smallest valid all-white PNG (8x8, greyscale).
List<int> _blankPng() => [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x08,
  0x08, 0x00, 0x00, 0x00, 0x00, 0x3A, 0x2A, 0xF4,
  0xBF, 0x00, 0x00, 0x00, 0x16, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0xFC, 0xCF, 0x80, 0x1B,
  0xFC, 0xFF, 0xFF, 0xFF, 0x19, 0x18, 0x00, 0x00,
  0xFF, 0xFF, 0x03, 0x00, 0x3B, 0x61, 0x09, 0xF1,
  0x1F, 0x6D, 0x3E, 0xD9, 0x00, 0x00, 0x00, 0x00,
  0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

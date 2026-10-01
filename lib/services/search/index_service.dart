import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../library/file_library.dart';
import 'index_database.dart';
import 'search_models.dart';
import 'text_extractor.dart';
import '../pdf/pdf_pages.dart';

class IndexService {
  final _receive = ReceivePort();
  final _events = StreamController<Map<String, Object?>>.broadcast();
  final _pending = <int, Completer<Object?>>{};
  final _ready = Completer<void>();
  SendPort? _port;
  Isolate? _isolate;
  int _sequence = 0;
  bool _closed = false;
  Stream<Map<String, Object?>> get events => _events.stream;
  IndexService._();

  static Future<IndexService> open(String databasePath) async {
    final service = IndexService._();
    service._receive.listen(service._message);
    try {
      service._isolate = await Isolate.spawn(
        _workerEntry,
        // PDFium stays with this isolate; the index asks it (see PdfPages).
        [service._receive.sendPort, databasePath, PdfPagesHost.start()],
        onError: service._receive.sendPort,
        onExit: service._receive.sendPort,
      );
      await service._ready.future.timeout(const Duration(seconds: 20));
      return service;
    } catch (_) {
      await service.close();
      rethrow;
    }
  }

  void _message(dynamic message) {
    if (_closed) return;
    if (message is! Map) {
      final error = StateError('Arama motoru beklenmedik biçimde kapandı.');
      if (!_ready.isCompleted) _ready.completeError(error);
      for (final completer in _pending.values) {
        completer.completeError(error);
      }
      _pending.clear();
      _events.add({'event': 'error', 'message': error.toString()});
      return;
    }
    if (message['port'] is SendPort) {
      _port = message['port'];
      _ready.complete();
      return;
    }
    if (message['id'] case final int id) {
      final completer = _pending.remove(id);
      if (message['error'] != null) {
        completer?.completeError(StateError(message['error']));
      } else {
        completer?.complete(message['result']);
      }
    } else {
      if (message['event'] == 'error' && !_ready.isCompleted) {
        _ready.completeError(StateError(message['message']));
      }
      _events.add(Map<String, Object?>.from(message));
    }
  }

  Future<T> request<T>(
    String command, [
    Map<String, Object?> args = const {},
  ]) async {
    if (_closed || _port == null) throw StateError('Arama motoru kapalı.');
    final id = ++_sequence;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    // The request id is written last: an argument named 'id' would otherwise
    // replace it and the reply could never be matched to its caller.
    _port!.send({'command': command, ...args, 'id': id});
    return (await completer.future) as T;
  }

  Future<SearchPage> search(SearchQuery query) async =>
      SearchPage.fromMap(await request<Map>('search', query.toMap()));
  Future<void> waitForIdle() => request<void>('idle');
  Future<void> close() async {
    if (_closed) return;
    try {
      if (_port != null) {
        await request<void>('close').timeout(const Duration(seconds: 3));
      }
    } catch (_) {
      /* The isolate is terminated below even after worker failure. */
    }
    _closed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _receive.close();
    for (final pending in _pending.values) {
      pending.completeError(StateError('Arama motoru kapatıldı.'));
    }
    _pending.clear();
    await _events.close();
  }
}

void _workerEntry(List args) async {
  final output = args[0] as SendPort;
  final path = args[1] as String;
  PdfPages.host = args[2] as SendPort?;
  try {
    if (path != ':memory:') {
      await Directory(p.dirname(path)).create(recursive: true);
    }
    final worker = _IndexWorker(IndexDatabase(path), output);
    final input = ReceivePort();
    output.send({'port': input.sendPort});
    input.listen(
      (message) => worker.handle(Map<String, dynamic>.from(message), input),
    );
  } catch (error) {
    output.send({'event': 'error', 'message': 'İndeks açılamadı: $error'});
  }
}

class _IndexWorker {
  final IndexDatabase database;
  final SendPort output;
  final _queue = <int, bool>{};
  Future<void>? _running;
  bool _cancelled = false;
  bool _closing = false;
  _ExtractionJob? _extraction;
  final _scanCache = <String, FolderScanResult>{};

  /// Reading scans is opt-in: it costs seconds of CPU per page, so the user
  /// turns it on rather than having the archive warm up the fans by itself.
  bool _ocr = false;
  int _walks = 0, _metadataFiles = 0, _extractedFiles = 0;
  int _walkMicros = 0, _extractMicros = 0;
  final _progressClock = Stopwatch()..start();
  _IndexWorker(this.database, this.output);

  Future<void> handle(Map<String, dynamic> request, ReceivePort input) async {
    final id = request['id'];
    try {
      Object? result;
      switch (request['command']) {
        case 'diagnostics':
          result = {
            'walks': _walks,
            'metadataFiles': _metadataFiles,
            'extractedFiles': _extractedFiles,
            'walkMicros': _walkMicros,
            'extractMicros': _extractMicros,
          };
        case 'search':
          result = database.search(request);
        case 'passages':
          result = database.passages(
            request['documentId'] as int,
            request['query'] as String? ?? '',
          );
        case 'annotations':
          result = database.annotations(request['docKey'] as String);
        case 'saveAnnotation':
          // Nested under 'row' on purpose: an annotation carries its own 'id'
          // and spreading it here would overwrite the request id.
          result = database.saveAnnotation(
            Map<String, Object?>.from(request['row'] as Map),
          );
        case 'deleteAnnotation':
          database.deleteAnnotation(request['annotationId'] as int);
        case 'rememberQuery':
          database.rememberQuery(request['query'] as String);
          result = database.recentQueries();
        case 'clearHistory':
          database.clearHistory();
        case 'catalog':
          result = database.stats();
        case 'add':
          final sourceIds = <int>[];
          for (final raw in (request['paths'] as List).cast<String>()) {
            final path = p.normalize(p.absolute(raw));
            final type = await FileSystemEntity.type(path, followLinks: false);
            if (type != FileSystemEntityType.directory &&
                !(type == FileSystemEntityType.file &&
                    FileLibrary.supports(path))) {
              continue;
            }
            sourceIds.add(
              database.addSource(
                path,
                type == FileSystemEntityType.directory,
                request['recursive'] != false,
              ),
            );
          }
          _enqueue(sourceIds, false);
          result = sourceIds;
        case 'paths':
          database.queuePaths(
            (request['paths'] as List).cast<String>().map(
              (path) => p.normalize(p.absolute(path)),
            ),
          );
          _enqueue([], false);
        case 'refresh':
          final ids =
              (request['ids'] as List?)?.cast<int>() ??
              database.sources().map((s) => s['id'] as int).toList();
          _enqueue(ids, request['force'] == true);
        case 'remove':
          final sourceId = request['sourceId'] as int;
          _queue.remove(sourceId);
          database.removeSource(sourceId);
          output.send({'event': 'changed'});
        case 'documentText':
          result = database.documentText(request['docPath'] as String);
        case 'repeatedPassages':
          result = [
            for (final one in database.repeatedPassages(
              inAtLeast: (request['inAtLeast'] as int?) ?? 5,
            ))
              {'text': one.text, 'documents': one.documents},
          ];
        case 'nativeDocumentText':
          result = database.nativeDocumentText(
            request['docPath'] as String,
            request['size'] as int,
            request['modified'] as int,
          );
        case 'ocrPaths':
          result = database.ocrPaths();
        case 'addOcrPath':
          database.addOcrPath(
            p.normalize(p.absolute(request['path'] as String)),
            request['recursive'] != false,
          );
          result = _ocr ? _queueOcrCandidates() : database.ocrCandidates();
        case 'removeOcrPath':
          database.removeOcrPath(request['pathId'] as int);
          // Removing the final selection expands the scope back to the whole
          // archive. If OCR is already on, newly included documents must not
          // wait for the user to toggle the setting off and on again.
          result = _ocr ? _queueOcrCandidates() : database.ocrCandidates();
        case 'ocrCandidates':
          result = database.ocrCandidates();
        case 'ocr':
          final enabling = request['enabled'] == true && !_ocr;
          _ocr = request['enabled'] == true;
          // Turning the setting on is the moment the user expects their scans
          // to become searchable. Queue the documents it can help and start, so
          // it does not look like nothing happened; `reprocess: false` is for
          // restoring the saved setting at startup, which must not re-run.
          if (enabling && request['reprocess'] != false) {
            result = _queueOcrCandidates();
          } else {
            result = 0;
          }
        case 'cancel':
          _cancelled = true;
          _queue.clear();
          _extraction?.cancel();
        case 'idle':
          await _running;
        case 'close':
          _closing = true;
          _cancelled = true;
          _queue.clear();
          _extraction?.cancel();
          await _running;
          database.close();
          input.close();
        default:
          throw ArgumentError('Bilinmeyen indeks komutu.');
      }
      output.send({'id': id, 'result': result});
    } catch (error) {
      output.send({'id': id, 'error': '$error'});
    }
  }

  int _queueOcrCandidates() {
    final queued = database.markUnreadableForOcr();
    if (queued > 0) {
      _enqueue(database.sources().map((s) => s['id'] as int).toList(), false);
    }
    return queued;
  }

  void _enqueue(List<int> ids, bool force) {
    for (final id in ids) {
      _queue[id] = force || (_queue[id] ?? false);
    }
    if (_running == null && (_queue.isNotEmpty || database.hasPendingPaths)) {
      _cancelled = false;
      _running = _drain();
    }
  }

  Future<void> _drain() async {
    try {
      var lastAttempted = 0;
      while (!_cancelled && !_closing) {
        final event = database.nextPendingPath(lastAttempted);
        if (event != null) {
          final eventId = event['id'] as int;
          lastAttempted = eventId;
          try {
            await _updatePath(event['path'] as String);
            if (!_cancelled && !_closing) database.completePath(eventId);
          } catch (e) {
            output.send({
              'event': 'error',
              'message': 'Dosya güncellenemedi: $e',
            });
          }
          continue;
        }
        if (_queue.isEmpty) break;
        final candidates = _queue.keys.toList()
          ..sort(
            (a, b) => ((database.source(a)?['path'] as String?)?.length ?? 0)
                .compareTo(
                  (database.source(b)?['path'] as String?)?.length ?? 0,
                ),
          );
        final id = candidates.first;
        final force = _queue.remove(id)!;
        final source = database.source(id);
        if (source == null) continue;
        try {
          await _scan(source, force);
        } catch (error) {
          database.finishScan(
            id,
            DateTime.now().microsecondsSinceEpoch,
            error: 'Klasör taranamadı: $error',
            prune: false,
          );
          output.send({
            'event': 'error',
            'message': 'Klasör taranamadı: $error',
          });
        }
      }
    } finally {
      _scanCache.clear();
      database.abandonScans();
      _extraction?.dispose();
      _extraction = null;
      _running = null;
      output.send({
        'event': 'progress',
        'active': false,
        'cancelled': _cancelled,
      });
      output.send({'event': 'changed'});
      if (_queue.isNotEmpty && !_closing) {
        Future.microtask(() => _enqueue([], false));
      }
    }
  }

  void _progress(
    String phase,
    int processed,
    int total,
    String path, {
    bool force = false,
  }) {
    if (!force && _progressClock.elapsedMilliseconds < 150) return;
    _progressClock.reset();
    output.send({
      'event': 'progress',
      'active': true,
      'phase': phase,
      'processed': processed,
      'total': total,
      'path': path,
    });
  }

  Future<void> _scan(
    Map<String, Object?> source,
    bool force, {
    String? within,
  }) async {
    final sourceId = source['id'] as int;
    final path = within ?? source['path'] as String;
    final token = DateTime.now().microsecondsSinceEpoch;
    _progress('Değişiklikler kontrol ediliyor', 0, 0, path, force: true);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      database.finishScan(
        sourceId,
        token,
        error: 'Kaynak şu anda erişilebilir değil; mevcut indeks korundu.',
        prune: false,
      );
      return;
    }
    final cached = _scanCache.entries
        .where((e) => p.equals(e.key, path) || p.isWithin(e.key, path))
        .firstOrNull;
    final recursive = source['recursive'] == 1;
    final FolderScanResult scan;
    if (cached != null) {
      final files = cached.value.files
          .where(
            (file) =>
                p.equals(file.path, path) ||
                (p.isWithin(path, file.path) &&
                    (recursive || p.equals(p.dirname(file.path), path))),
          )
          .toList();
      scan = FolderScanResult(
        files.map((e) => e.path).toList(),
        0,
        cached.value.unreadable,
        files,
      );
    } else {
      final timer = Stopwatch()..start();
      _walks++;
      scan = await FileLibrary.collect(
        [path],
        recursive: recursive,
        metadata: true,
        sort: false,
        shouldCancel: () => _cancelled || _closing,
      );
      _walkMicros += timer.elapsedMicroseconds;
      _metadataFiles += scan.files.length;
      if (recursive && type == FileSystemEntityType.directory) {
        _scanCache[path] = scan;
      }
    }
    if (_cancelled || _closing) return;
    final scanned = scan.files;
    database.beginScan(sourceId);
    // Registered in chunks: one transaction per file cost a WAL commit each,
    // while one transaction for the whole scan would block this isolate — and
    // with it every search and quick look — until the last file was written.
    const chunk = 500;
    final pending =
        <({int id, String path, int size, int modified, int changed})>[];
    for (var start = 0; start < scanned.length; start += chunk) {
      if (_cancelled || _closing || database.source(sourceId) == null) return;
      final end = start + chunk < scanned.length
          ? start + chunk
          : scanned.length;
      pending.addAll(
        database.registerFiles(
          sourceId: sourceId,
          token: token,
          files: scanned.sublist(start, end),
          force: force,
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }
    database.finishScan(
      sourceId,
      token,
      prune: scan.unreadable.isEmpty,
      within: within,
      error: scan.unreadable.isEmpty
          ? null
          : '${scan.unreadable.length} konum okunamadı; önceki kayıtlar korundu.',
    );
    output.send({'event': 'changed'});
    await _extract(pending, sourceId);
  }

  bool _covers(Map<String, Object?> source, String path) {
    final root = source['path'] as String;
    if (source['kind'] == 'file') return p.equals(root, path);
    return p.isWithin(root, path) &&
        (source['recursive'] == 1 || p.equals(p.dirname(path), root));
  }

  Future<void> _updatePath(String path) async {
    _scanCache.clear();
    final sources = database.sources();
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      // Native watchers also report files in new subtrees. An explicit folder
      // event is a reconciliation fallback, never a reason to parse all text.
      for (final source in sources) {
        if (_covers(source, path) || p.equals(source['path'] as String, path)) {
          await _scan(source, false, within: path);
        }
      }
      return;
    }
    for (final source in sources) {
      final sourceId = source['id'] as int;
      if (type == FileSystemEntityType.notFound) {
        if (source['kind'] == 'folder' &&
            !await Directory(source['path'] as String).exists()) {
          continue;
        }
        database.removeMissingPath(sourceId, path);
        continue;
      }
      if (!_covers(source, path) || !FileLibrary.supports(path)) continue;
      if (type != FileSystemEntityType.file) continue;
      final stat = await File(path).stat();
      if (stat.type != FileSystemEntityType.file) continue;
      final pending = database.registerFiles(
        sourceId: sourceId,
        token: DateTime.now().microsecondsSinceEpoch,
        files: [
          (
            path: path,
            size: stat.size,
            modified: stat.modified.microsecondsSinceEpoch,
            changed: stat.changed.microsecondsSinceEpoch,
          ),
        ],
      );
      await _extract(pending, sourceId);
    }
    output.send({'event': 'changed'});
  }

  Future<void> _extract(
    List<({int id, String path, int size, int modified, int changed})> pending,
    int sourceId,
  ) async {
    var count = 0;
    for (final file in pending) {
      if (_cancelled || _closing || database.source(sourceId) == null) break;
      _progress(
        'Metin indeksleniyor',
        count,
        pending.length,
        file.path,
        force: count == 0,
      );
      _extraction ??= _ExtractionJob();
      final timer = Stopwatch()..start();
      // Checked per document, not once per run: narrowing the folders while a
      // scan is going stops the work that has not started yet.
      final extracted = await _extraction!.run(
        file.path,
        ocr: _ocr && database.ocrCovers(file.path),
      );
      _extractMicros += timer.elapsedMicroseconds;
      _extractedFiles++;
      if (_cancelled || _closing) break;
      final stat = await File(file.path).stat();
      if (stat.size != file.size ||
          stat.modified.microsecondsSinceEpoch != file.modified ||
          stat.changed.microsecondsSinceEpoch != file.changed) {
        database.setContent(
          file.id,
          '',
          'pending',
          'Dosya işlem sırasında değişti; yeniden taranmalı.',
        );
        database.queuePaths([file.path]);
      } else {
        database.setContent(
          file.id,
          extracted['text'] as String,
          extracted['state'] as String,
          extracted['note'] as String?,
          ocr: extracted['ocr'] == true,
        );
      }
      _progress(
        'Metin indeksleniyor',
        ++count,
        pending.length,
        file.path,
        force: count == pending.length,
      );
      if (count % 10 == 0) output.send({'event': 'changed'});
    }
  }
}

/// One reusable parser isolate per active indexing batch. A stuck parser is
/// killed on timeout/cancel and recreated for the next document.
class _ExtractionJob {
  Isolate? _isolate;
  ReceivePort? _port;
  SendPort? _commands;
  Completer<SendPort>? _ready;
  Completer<Map<String, Object?>>? _done;
  bool _cancelled = false;

  void _stop() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commands = null;
    _port?.close();
    _port = null;
  }

  void dispose() => _stop();

  void cancel() {
    _cancelled = true;
    _stop();
    if (_done?.isCompleted == false) {
      _done!.complete({
        'text': '',
        'state': 'pending',
        'note': 'İşlem durduruldu.',
      });
    }
    if (_ready?.isCompleted == false) {
      _ready!.completeError(StateError('İşlem durduruldu.'));
    }
  }

  Future<void> _start() async {
    if (_commands != null) return;
    final ready = _ready = Completer<SendPort>();
    final port = _port = ReceivePort();
    port.listen((dynamic message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
      } else if (message is Map) {
        if (_done?.isCompleted == false) {
          _done!.complete(Map<String, Object?>.from(message));
        }
      } else {
        if (!ready.isCompleted) {
          ready.completeError(StateError('Ayrıştırıcı başlatılamadı.'));
        }
        if (_done?.isCompleted == false) {
          _done!.complete({
            'text': '',
            'state': 'error',
            'note': 'Metin çıkarma işlemi tamamlanamadı.',
          });
        }
        _stop();
      }
    });
    // Attach error handling before isolate startup can report failure.
    final waiting = ready.future.timeout(const Duration(seconds: 10));
    unawaited(waiting.then<void>((_) {}, onError: (Object _) {}));
    _isolate = await Isolate.spawn(
      _extractEntry,
      (output: port.sendPort, pdfium: PdfPages.host),
      onError: port.sendPort,
      onExit: port.sendPort,
    );
    if (_cancelled) {
      _stop();
      throw StateError('İşlem durduruldu.');
    }
    _commands = await waiting;
  }

  Future<Map<String, Object?>> run(String path, {bool ocr = false}) async {
    _done = Completer<Map<String, Object?>>();
    try {
      await _start();
      if (_cancelled) {
        return {'text': '', 'state': 'pending', 'note': 'İşlem durduruldu.'};
      }
      _commands!.send({'path': path, 'ocr': ocr});
      return await _done!.future.timeout(
        // Reading a scan costs seconds per page, so the parse budget cannot be
        // the same as for a document whose text is already there.
        ocr ? const Duration(minutes: 3) : const Duration(seconds: 30),
        onTimeout: () {
          _stop();
          return {
            'text': '',
            'state': 'error',
            'note': 'Metin çıkarma zaman aşımına uğradı.',
          };
        },
      );
    } catch (_) {
      _stop();
      return {
        'text': '',
        'state': _cancelled ? 'pending' : 'error',
        'note': 'Metin çıkarma işlemi tamamlanamadı.',
      };
    } finally {
      _done = null;
    }
  }
}

void _extractEntry(({SendPort output, SendPort? pdfium}) args) {
  final output = args.output;
  PdfPages.host = args.pdfium;
  final input = ReceivePort();
  output.send(input.sendPort);
  input.listen((dynamic message) async {
    try {
      final request = message as Map;
      output.send(
        await IndexTextExtractor.extract(
          request['path'] as String,
          ocr: request['ocr'] == true,
        ),
      );
    } catch (_) {
      output.send({
        'text': '',
        'state': 'error',
        'note': 'Metin çıkarma işlemi tamamlanamadı.',
      });
    }
  });
}

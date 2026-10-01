import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';

import 'package:watcher/watcher.dart';

import '../annotations/pdf_annotation.dart';
import '../ocr/ocr_service.dart';
import '../library/file_library.dart';
import '../platform/document_intents.dart';
import 'index_service.dart';
import 'search_models.dart';

class LibraryController extends ChangeNotifier {
  final String? databasePath;
  final bool watchFolders;
  IndexService? _service;
  Future<void>? _initializing;
  final _watchers = <int, StreamSubscription<WatchEvent>>{};
  final _changedPaths = <String>{};
  Timer? _watchDebounce;
  Timer? _watchRecovery;
  StreamSubscription? _events;
  Timer? _debounce;
  Timer? _historyDebounce;
  Timer? _catalogDebounce;
  bool _disposed = false;
  bool _syncingAndroid = false;

  /// Told when only [phase], [processed], [toProcess] or [currentPath]
  /// moved. Indexing reports those every 150 ms; telling every listener of
  /// the controller rebuilt the whole home page that often while the
  /// archive was scanned. What shows the counters listens here too.
  Listenable get progress => _progress;
  final _progress = _Progress();
  int _generation = 0;
  String? _actualPath;
  bool ready = false;
  bool searching = false;
  bool active = false;
  bool cancelled = false;
  String? error;
  String phase = 'Hazır';
  String currentPath = '';
  int processed = 0;
  int toProcess = 0;
  int total = 0;
  int searchable = 0;
  int failures = 0;
  int namesOnlyCount = 0;
  int pending = 0;
  List<LibrarySource> sources = [];
  List<String> recentQueries = [];
  List<SearchHit> hits = [];
  int matches = 0;
  int elapsedMicros = 0;
  String query = '';
  bool namesOnly = false;
  SearchMatch match = SearchMatch.all;
  String? searchError;
  List<String> extensions = [];
  int? sourceId;

  /// Only the documents under this folder, as a UYAP case's are.
  String? within;
  String sort = 'relevance';

  /// Only documents whose text came from OCR.
  bool ocrOnly = false;

  /// How many documents in the archive were read by OCR; the filter is only
  /// worth showing when there are some.
  int ocrCount = 0;

  /// Folders OCR is aimed at. Empty means the whole archive, which is what the
  /// setting did before folders could be chosen.
  List<({int id, String path, bool recursive})> ocrFolders = const [];

  /// How many documents the current selection would take on. Shown before the
  /// user commits to work that costs seconds per page.
  int ocrPending = 0;

  /// Reading scans costs seconds of CPU per page, so it stays off until the
  /// user asks for it.
  bool ocrEnabled = false;
  bool ocrAvailable = false;

  LibraryController({this.databasePath, this.watchFolders = true});

  Future<File> _ocrSettingsFile() async =>
      File(p.join((await folioSupportDirectory()).path, 'ocr.json'));

  Future<void> _loadOcrSetting() async {
    ocrAvailable = await OcrService.available;
    try {
      final file = await _ocrSettingsFile();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        ocrEnabled = data is Map && data['enabled'] == true;
      }
    } catch (_) {
      ocrEnabled = false;
    }
    // Without the tool the setting cannot take effect, so never report it as on.
    if (!ocrAvailable) ocrEnabled = false;
    // Restoring the saved setting must not re-queue the archive on every start.
    if (ocrEnabled) {
      try {
        await _sendOcr(reprocess: false);
      } catch (_) {}
    }
  }

  /// Text OCR read out of this document, or null when it was not read that
  /// way. The preview offers it beside the picture: a reader needs to check
  /// recognised text against the page, and to copy from it.
  Future<String?> ocrText(String path) async {
    final service = _service;
    if (service == null) return null;
    try {
      return await service.request<String?>('documentText', {'docPath': path});
    } catch (_) {
      return null;
    }
  }

  /// Passages the archive repeats, most repeated first.
  ///
  /// What the snippet library offers on a first run: a reader with nothing
  /// kept yet does not want to be told to go and select a paragraph, they
  /// want to be shown the ones they have already written twenty times.
  Future<List<({String text, int documents})>> repeatedPassages({
    int inAtLeast = 5,
  }) async {
    final service = _service;
    if (service == null) return const [];
    try {
      final rows = await service.request<List>('repeatedPassages', {
        'inAtLeast': inAtLeast,
      });
      return [
        for (final row in rows)
          if (row is Map)
            (
              text: '${row['text']}',
              documents: (row['documents'] as num?)?.toInt() ?? 0,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// The current native text layer of an indexed PDF. This is separate from
  /// [ocrText]: editing a normal PDF should reuse text the index already read,
  /// while OCR output must remain explicitly identified as an approximation.
  Future<String?> nativePdfText(String path) async {
    final service = _service;
    if (service == null) return null;
    try {
      final stat = await File(path).stat();
      if (stat.type != FileSystemEntityType.file) return null;
      return await service.request<String?>('nativeDocumentText', {
        'docPath': path,
        'size': stat.size,
        'modified': stat.modified.microsecondsSinceEpoch,
      });
    } catch (_) {
      return null;
    }
  }

  Future<void> refreshOcrScope() async {
    final service = _service;
    if (service == null) return;
    try {
      final rows = await service.request<List>('ocrPaths');
      ocrFolders = [
        for (final row in rows)
          (
            id: row['id'] as int,
            path: row['path'] as String,
            recursive: row['recursive'] == 1,
          ),
      ];
      ocrPending = await service.request<int>('ocrCandidates');
    } catch (_) {
      return;
    }
    _notify();
  }

  /// Aim OCR at one folder. With none chosen it covers the whole archive, so
  /// the first folder added is also what narrows it.
  Future<int> addOcrFolder(String path, {bool recursive = true}) async {
    final service = _service;
    if (service == null) return 0;
    final affected = await service.request<int>('addOcrPath', {
      'path': path,
      'recursive': recursive,
    });
    await refreshOcrScope();
    return affected;
  }

  Future<int> removeOcrFolder(int id) async {
    final service = _service;
    if (service == null) return 0;
    final affected = await service.request<int>('removeOcrPath', {
      'pathId': id,
    });
    await refreshOcrScope();
    return affected;
  }

  /// Returns how many documents were queued for a second look. Zero when the
  /// setting is only being restored at startup, or when nothing in the archive
  /// needs OCR.
  Future<int> _sendOcr({bool reprocess = true}) async {
    final service = _service;
    if (service == null) return 0;
    return await service.request<int>('ocr', {
      'enabled': ocrEnabled,
      'reprocess': reprocess,
    });
  }

  /// Turning OCR on immediately queues the documents it can help — the ones
  /// with no searchable text — rather than waiting for a full rescan, which
  /// would re-read the whole archive to reach the fifth of it that needs it.
  /// Returns how many were queued so the caller can say so.
  Future<int> setOcr(bool enabled) async {
    if (!ocrAvailable && enabled) return 0;
    ocrEnabled = enabled;
    _notify();
    var queued = 0;
    try {
      queued = await _sendOcr();
    } catch (e) {
      // The switch would otherwise read as on while the indexer never heard.
      ocrEnabled = !enabled;
      error = 'OCR ayarı uygulanamadı: $e';
      _notify();
      return 0;
    }
    try {
      await (await _ocrSettingsFile()).writeAsString(
        jsonEncode({'enabled': enabled}),
        flush: true,
      );
    } catch (_) {}
    _notify();
    return queued;
  }

  /// Where the archive's index lives unless a test says otherwise; the
  /// suggestions read it too, to learn from.
  static Future<String> defaultDatabasePath() async => p.join(
    (await folioSupportDirectory()).path,
    'library',
    'evrak_index.sqlite',
  );

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    final startup = Stopwatch()..start();
    try {
      _actualPath = databasePath ?? await defaultDatabasePath();
      if (_disposed) return;
      _service = await IndexService.open(_actualPath!);
      if (_disposed) {
        await _service!.close();
        return;
      }
      _events = _service!.events.listen(_event);
      ready = true;
      await _loadOcrSetting();
      await refreshCatalog();
      await searchNow();
      if (Platform.environment['FOLIO_STARTUP_TRACE'] == '1') {
        stderr.writeln(
          'Folio index and first results: ${startup.elapsedMilliseconds} ms',
        );
      }
      if (sources.isNotEmpty) {
        // The index already answers searches; the rescan that catches what
        // changed while Folio was closed waits until the window has settled,
        // rather than share the first seconds with it. The folder watchers,
        // started by refreshCatalog above, already report changes meanwhile.
        if (!Platform.environment.containsKey('FLUTTER_TEST')) {
          await Future<void>.delayed(const Duration(seconds: 3));
          if (_disposed) return;
        }
        await refresh();
      }
    } catch (e) {
      error = 'Arama arşivi açılamadı: $e';
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _event(Map<String, Object?> event) {
    if (_disposed) return;
    if (event['event'] == 'error') {
      error = event['message'] as String?;
    }
    final wasActive = active;
    if (event['event'] == 'progress') {
      active = event['active'] == true;
      cancelled = event['cancelled'] == true;
      if (active) {
        phase = event['phase'] as String? ?? phase;
        processed = event['processed'] as int? ?? processed;
        toProcess = event['total'] as int? ?? toProcess;
        currentPath = event['path'] as String? ?? '';
      } else {
        phase = cancelled ? 'İndeksleme durduruldu' : 'İndeks güncel';
      }
    }
    if (event['event'] == 'changed' || !active) {
      _catalogDebounce?.cancel();
      _catalogDebounce = Timer(const Duration(milliseconds: 200), () async {
        await refreshCatalog();
        await searchNow();
      });
    }
    if (event['event'] == 'progress' && active && wasActive) {
      if (!_disposed) _progress.changed();
      return;
    }
    _notify();
    if (!_disposed) _progress.changed();
  }

  Future<void> refreshCatalog() async {
    if (!ready || _disposed) return;
    try {
      final data = await _service!.request<Map>('catalog');
      if (_disposed) return;
      recentQueries = List<String>.from(data['recentQueries'] as List? ?? []);
      total = data['total'];
      searchable = data['ready'];
      failures = data['errors'];
      pending = data['pending'];
      namesOnlyCount = data['namesOnly'];
      ocrCount = data['ocr'] as int? ?? 0;
      unawaited(refreshOcrScope());
      // A filter that can only ever be empty is noise.
      if (ocrCount == 0) ocrOnly = false;
      sources = (data['sources'] as List)
          .map((s) => LibrarySource.fromMap(s))
          .toList();
      if (sourceId != null && !sources.any((s) => s.id == sourceId)) {
        sourceId = null;
      }
      _syncWatchers();
    } catch (e) {
      error = '$e';
    }
    _notify();
  }

  Future<void> addPaths(List<String> paths, {bool recursive = true}) async {
    await initialize();
    if (!ready || _disposed) return;
    try {
      error = null;
      await _service!.request('add', {'paths': paths, 'recursive': recursive});
      await refreshCatalog();
      await searchNow();
    } catch (e) {
      error = '$e';
      _notify();
    }
  }

  Future<void> refresh({List<int>? ids, bool force = false}) async {
    if (!ready || _disposed || _syncingAndroid) return;
    try {
      error = null;
      _syncingAndroid = Platform.isAndroid;
      await DocumentIntents.syncFolders(
        sources
            .where((s) => s.folder && (ids == null || ids.contains(s.id)))
            .map((s) => s.path)
            .toList(),
      );
      if (_disposed) return;
      await _service!.request('refresh', {'ids': ids, 'force': force});
    } catch (e) {
      error = '$e';
      _notify();
    } finally {
      _syncingAndroid = false;
    }
  }

  /// Passages for the quick look. Only the hovered document is read, and only
  /// when the card opens.
  Future<DocumentPassages> passages(int documentId) async {
    if (!ready || _disposed || documentId == 0) {
      return const DocumentPassages();
    }
    try {
      return DocumentPassages.fromMap(
        await _service!.request<Map>('passages', {
          'documentId': documentId,
          'query': query,
        }),
      );
    } catch (_) {
      return const DocumentPassages();
    }
  }

  /// Highlights for one PDF. Works for documents outside the archive too: the
  /// key is derived from the path, not from an index row.
  Future<List<PdfHighlight>> highlights(String path) async {
    if (!ready || _disposed) return const [];
    try {
      final rows = await _service!.request<List>('annotations', {
        'docKey': PdfHighlight.keyFor(path),
      });
      return rows.map((row) => PdfHighlight.fromMap(row as Map)).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Returns the stored highlight, carrying the id the database assigned.
  /// Throws when the index is unavailable, so the viewer can tell the user the
  /// mark was not kept instead of silently dropping it.
  Future<PdfHighlight> saveHighlight(PdfHighlight highlight) async {
    if (!ready || _disposed) {
      throw StateError('Arşiv hazır değil; vurgu kaydedilemedi.');
    }
    final id = await _service!.request<int>('saveAnnotation', {
      'row': highlight.toMap(),
    });
    return highlight.copyWith(id: id);
  }

  Future<void> deleteHighlight(int id) async {
    if (!ready || _disposed || id == 0) return;
    try {
      await _service!.request<void>('deleteAnnotation', {'annotationId': id});
    } catch (_) {}
  }

  Future<void> removeSource(int id) async {
    if (!ready || _disposed) return;
    try {
      final source = sources.where((s) => s.id == id).firstOrNull;
      if (source != null) await DocumentIntents.forgetFolder(source.path);
      await _service!.request('remove', {'sourceId': id});
      await refreshCatalog();
      await searchNow();
    } catch (e) {
      error = '$e';
      _notify();
    }
  }

  Future<void> cancel() async {
    if (!ready || _disposed) return;
    await _service!.request('cancel');
  }

  void setQuery(String text) {
    query = text;
    _generation++; // Invalidate results from earlier requests immediately.
    _debounce?.cancel();
    searching = true;
    _notify();
    _debounce = Timer(const Duration(milliseconds: 180), searchNow);
    _historyDebounce?.cancel();
    _historyDebounce = Timer(const Duration(milliseconds: 1200), rememberQuery);
  }

  Future<void> rememberQuery() async {
    _historyDebounce?.cancel();
    if (!ready || _disposed || query.trim().isEmpty) return;
    try {
      recentQueries = List<String>.from(
        await _service!.request<List>('rememberQuery', {'query': query}),
      );
      _notify();
    } catch (_) {
      /* History must never interrupt a search. */
    }
  }

  Future<void> clearHistory() async {
    _historyDebounce?.cancel();
    if (!ready || _disposed) return;
    await _service!.request('clearHistory');
    recentQueries = [];
    _notify();
  }

  void filter({
    bool? byName,
    SearchMatch? matching,
    List<String>? types,
    bool? onlyOcr,
    int? folder,
    bool clearFolder = false,
    String? inside,
    String? ordering,
  }) {
    namesOnly = byName ?? namesOnly;
    match = matching ?? match;
    extensions = types ?? extensions;
    ocrOnly = onlyOcr ?? ocrOnly;
    sourceId = clearFolder ? null : folder ?? sourceId;
    // One way of narrowing to a place at a time.
    if (clearFolder || folder != null) within = null;
    if (inside != null) {
      within = inside;
      sourceId = null;
    }
    sort = ordering ?? sort;
    searchNow();
  }

  Future<void> searchNow({bool more = false}) async {
    _debounce?.cancel();
    if (!ready || _disposed) return;
    final generation = ++_generation;
    searchError = null;
    searching = true;
    _notify();
    try {
      final page = await _service!.search(
        SearchQuery(
          text: query,
          match: match,
          namesOnly: namesOnly,
          ocrOnly: ocrOnly,
          extensions: extensions,
          sourceId: sourceId,
          within: within,
          sort: sort,
          offset: more ? hits.length : 0,
        ),
      );
      if (_disposed || generation != _generation) return;
      hits = more ? [...hits, ...page.hits] : page.hits;
      matches = page.total;
      elapsedMicros = page.elapsedMicros;
    } catch (e) {
      if (generation == _generation) {
        searchError = 'Arama tamamlanamadı: $e';
        hits = [];
        matches = 0;
      }
    } finally {
      if (generation == _generation) {
        searching = false;
        _notify();
      }
    }
  }

  Future<void> waitForIdle() async {
    await initialize();
    await _service?.waitForIdle();
    await refreshCatalog();
    await searchNow();
  }

  Future<void> updatePaths(Iterable<String> paths) async {
    if (!ready || _disposed) return;
    try {
      await _service!.request('paths', {'paths': paths.toSet().toList()});
    } catch (e) {
      error = 'Dosya değişiklikleri kaydedilemedi: $e';
      _notify();
    }
  }

  void _syncWatchers() {
    if (!watchFolders) return;
    // A recursive watcher can serve child folders and individual files too.
    final ordered = sources.toList()
      ..sort((a, b) => a.path.length.compareTo(b.path.length));
    final roots = <int, String>{};
    for (final source in ordered) {
      final directory = source.folder ? source.path : p.dirname(source.path);
      if (roots.values.any(
        (root) => p.equals(root, directory) || p.isWithin(root, directory),
      )) {
        continue;
      }
      roots[source.id] = directory;
    }
    for (final id in _watchers.keys.toList()) {
      if (!roots.containsKey(id)) _watchers.remove(id)?.cancel();
    }
    for (final entry in roots.entries) {
      if (_watchers.containsKey(entry.key)) continue;
      final watcher = DirectoryWatcher(entry.value);
      _watchers[entry.key] = watcher.events.listen(
        (event) {
          final path = p.normalize(p.absolute(event.path));
          if (_actualPath != ':memory:' &&
              (p.equals(path, _actualPath!) ||
                  path == '${_actualPath!}-wal' ||
                  path == '${_actualPath!}-shm')) {
            return;
          }
          final relevant = sources.any(
            (source) => source.folder
                ? (p.equals(source.path, path) ||
                          p.isWithin(source.path, path)) &&
                      (source.recursive ||
                          p.equals(p.dirname(path), source.path) ||
                          p.equals(path, source.path))
                : p.equals(source.path, path) ||
                      (event.type == ChangeType.REMOVE &&
                          p.isWithin(path, source.path)),
          );
          if (!relevant) return;
          if (!FileLibrary.supports(path) && event.type != ChangeType.REMOVE) {
            return;
          }
          _changedPaths.add(path);
          // Persist batches without continually postponing them during a burst.
          _watchDebounce ??= Timer(const Duration(milliseconds: 180), () async {
            _watchDebounce = null;
            final paths = _changedPaths.toList();
            _changedPaths.clear();
            await updatePaths(paths);
          });
        },
        onError: (Object e) {
          _watchers.remove(entry.key)?.cancel();
          error = 'Klasör izlemesi kesildi; değişiklikler yeniden kontrol edilecek.';
          _notify();
          _watchRecovery ??= Timer(const Duration(seconds: 10), () {
            _watchRecovery = null;
            if (_disposed) return;
            _syncWatchers();
            refresh();
          });
        },
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _historyDebounce?.cancel();
    _generation++;
    _debounce?.cancel();
    _catalogDebounce?.cancel();
    _events?.cancel();
    _watchDebounce?.cancel();
    _watchRecovery?.cancel();
    for (final watcher in _watchers.values) {
      watcher.cancel();
    }
    _service?.close();
    _progress.dispose();
    super.dispose();
  }
}

class _Progress extends ChangeNotifier {
  void changed() => notifyListeners();
}

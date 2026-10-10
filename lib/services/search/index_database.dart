import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../platform/app_directories.dart';
import 'search_models.dart';

/// Owned exclusively by the background library isolate. Search can run between
/// extraction jobs; filesystem parsing never blocks Flutter's UI isolate.
class IndexDatabase {
  // Formats Tesseract can actually improve. Empty office/text documents and
  // SVG drawings may also have the states below, but re-parsing them with the
  // OCR switch on only wastes a worker slot and inflates the confirmation
  // count shown to the user.
  static const _ocrFormats =
      "('pdf','png','jpg','jpeg','webp','bmp','gif','tif','tiff')";
  final Database db;
  final _activeScans = <int>{};
  IndexDatabase(String path) : db = sqlite3.open(path) {
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA busy_timeout=5000');
    db.execute('PRAGMA foreign_keys=ON');
    db.execute('PRAGMA synchronous=NORMAL');
    db.execute('PRAGMA temp_store=MEMORY');
    db.execute(
      'CREATE TEMP TABLE scan_seen(source_id INTEGER NOT NULL, document_id INTEGER NOT NULL, PRIMARY KEY(source_id,document_id))',
    );
    final version = db.select('PRAGMA user_version').first.values.first as int;
    if (version > 10) {
      throw StateError('İndeks daha yeni bir uygulama sürümüne ait.');
    }
    db.execute('''
      CREATE TABLE IF NOT EXISTS sources (
        id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE, kind TEXT NOT NULL,
        recursive INTEGER NOT NULL DEFAULT 1, error TEXT, scanned INTEGER);
      CREATE TABLE IF NOT EXISTS documents (
        id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
        extension TEXT NOT NULL, size INTEGER NOT NULL, modified INTEGER NOT NULL,
        changed INTEGER NOT NULL, text TEXT NOT NULL DEFAULT '',
        state TEXT NOT NULL DEFAULT 'pending', note TEXT);
      CREATE TABLE IF NOT EXISTS memberships (
        source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
        document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
        seen INTEGER NOT NULL, PRIMARY KEY(source_id, document_id));
      CREATE INDEX IF NOT EXISTS documents_modified ON documents(modified DESC);
      CREATE INDEX IF NOT EXISTS documents_extension ON documents(extension);
      -- Extracted text lives in the row, so counting states without this index
      -- reads the whole table; the archive summary asks for those counts on
      -- every catalog refresh.
      CREATE INDEX IF NOT EXISTS documents_state ON documents(state);
      CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(
        name, body, tokenize='unicode61 remove_diacritics 0', prefix='2 3 4');
      CREATE TRIGGER IF NOT EXISTS remove_search AFTER DELETE ON documents BEGIN
        DELETE FROM search_fts WHERE rowid=old.id;
      END;
      CREATE TABLE IF NOT EXISTS recent_queries (normalized TEXT PRIMARY KEY, query TEXT NOT NULL, searched INTEGER NOT NULL);
    ''');
    if (version < 2) {
      transaction(() {
        db.execute(
          'ALTER TABLE documents ADD COLUMN added INTEGER NOT NULL DEFAULT 0',
        );
        db.execute('UPDATE documents SET added=modified');
        db.execute('PRAGMA user_version=2');
      });
    }
    if (version < 3) {
      // One-off cleanups. Running these on every open cost a full scan of the
      // documents table, including its inline text, before the first search.
      transaction(() {
        db.execute(
          "UPDATE documents SET state='pending' WHERE state='partial' AND note='İlk 2 milyon karakter indekslendi.'",
        );
        db.execute(
          'CREATE INDEX IF NOT EXISTS documents_added ON documents(added DESC)',
        );
        db.execute('PRAGMA user_version=3');
      });
    }
    if (version < 4) {
      transaction(() {
        db.execute(
          'CREATE TABLE IF NOT EXISTS pending_paths (id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL UNIQUE)',
        );
        db.execute('PRAGMA user_version=4');
      });
    }
    if (version < 5) {
      // Highlights are keyed by a hash of the absolute path, not by a
      // documents(id) foreign key: a PDF opened from the desktop or the command
      // line is never in the index, and it can be marked up all the same. The
      // path is kept alongside so a moved file can be reattached later.
      transaction(() {
        db.execute('''
          CREATE TABLE IF NOT EXISTS annotations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            doc_key TEXT NOT NULL, path TEXT NOT NULL,
            page INTEGER NOT NULL, rects TEXT NOT NULL,
            text TEXT NOT NULL DEFAULT '', color INTEGER NOT NULL,
            note TEXT, created INTEGER NOT NULL,
            rotation INTEGER NOT NULL DEFAULT 0);
          CREATE INDEX IF NOT EXISTS annotations_doc ON annotations(doc_key, page);
        ''');
        db.execute('PRAGMA user_version=5');
      });
    }
    if (version < 6) {
      // Text read by OCR is a different kind of result from text a document
      // carried: it can contain recognition mistakes, so the archive shows
      // which documents it came from and can list just those. The document
      // itself is still 'ready' — this is about where the text came from, not
      // whether it worked.
      transaction(() {
        db.execute(
          'ALTER TABLE documents ADD COLUMN ocr INTEGER NOT NULL DEFAULT 0',
        );
        db.execute(
          'CREATE INDEX IF NOT EXISTS documents_ocr ON documents(ocr)',
        );
        db.execute('PRAGMA user_version=6');
      });
    }
    if (version < 7) {
      // OCR can be aimed at part of the archive. An empty table means the whole
      // of it, which is what the setting did before this existed.
      transaction(() {
        db.execute(
          'CREATE TABLE IF NOT EXISTS ocr_paths (id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'path TEXT NOT NULL UNIQUE, recursive INTEGER NOT NULL DEFAULT 1)',
        );
        db.execute('PRAGMA user_version=7');
      });
    }
    if (version < 8) {
      // Documents read before the ocr column existed carry the note this code
      // writes and nothing else, so the note is what records where their text
      // came from. Without this backfill the filter stays hidden until every
      // scan in the archive is read a second time.
      transaction(() {
        db.execute(
          "UPDATE documents SET ocr=1 WHERE ocr=0 AND state='ready' "
          "AND note LIKE '%(OCR)%'",
        );
        db.execute('PRAGMA user_version=8');
      });
    }
    if (version < 9) {
      // Scanned PDFs read before this were rendered at their natural 72 dpi
      // into the corner of a much larger blank canvas, so OCR saw tiny text
      // surrounded by white and the result was materially wrong. Queue them to
      // be read again. Images are untouched: they go to the reader as files and
      // were never rendered.
      transaction(() {
        db.execute(
          "UPDATE documents SET state='pending' WHERE ocr=1 AND extension='pdf'",
        );
        db.execute('PRAGMA user_version=9');
      });
    }
    if (version < 10) {
      // PDF text now comes from PDFium. The reader before it wrote glyph
      // names in place of Turkish letters in 30% of PDFs with a text layer
      // ("oldugbreveu" for "olduğu"), which no search finds, and ran out of
      // memory or time on long files. Read those PDFs again. Scans read by
      // OCR, and PDFs that yielded nothing, are left alone: their text layer
      // is empty, so reading them again would only send them back to OCR.
      transaction(() {
        db.execute(
          "UPDATE documents SET state='pending' WHERE extension='pdf' "
          "AND ocr=0 AND state IN ('ready','partial','error')",
        );
        db.execute('PRAGMA user_version=10');
      });
    }
    _followMovedFolder();
  }

  /// On an iPhone the app's folder moves when Folio is updated: the paths
  /// kept here under the old one are taken to the new ([ownPath]), once,
  /// so that the archive finds its documents and folders again.
  void _followMovedFolder() {
    if (!Platform.isIOS) return;
    const tables = [
      'sources',
      'documents',
      'pending_paths',
      'annotations',
      'ocr_paths',
    ];
    transaction(() {
      for (final table in tables) {
        final exists = db.select(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
          [table],
        );
        if (exists.isEmpty) continue;
        for (final row in db.select(
          "SELECT rowid AS r, path FROM $table "
          "WHERE path LIKE '%/Containers/Data/Application/%'",
        )) {
          final kept = row['path'] as String;
          final now = ownPath(kept);
          if (now == kept) continue;
          db.execute('UPDATE OR IGNORE $table SET path=? WHERE rowid=?', [
            now,
            row['r'],
          ]);
        }
      }
    });
  }

  /// Passages the archive repeats, for the snippet library to offer.
  ///
  /// Counted here rather than in the interface because the text is already
  /// here: fetching seventeen hundred documents across the isolate to count
  /// them on the other side would cost seventeen hundred round trips to
  /// learn something a single pass answers.
  ///
  /// A passage counts once per document, not once per appearance, so a
  /// recital repeated three times in one filing does not look like three
  /// filings. Short lines are headings and long ones are particular to
  /// their case; what repeats usefully sits between.
  List<({String text, int documents})> repeatedPassages({
    int inAtLeast = 5,
    int shortest = 60,
    int longest = 400,
    int most = 200,
  }) {
    final counts = <String, int>{};
    for (final row in db.select(
      "SELECT text FROM documents WHERE state IN ('ready','partial') "
      "AND length(text) > 0",
    )) {
      final text = row['text'] as String;
      final seen = <String>{};
      for (final piece in text.split(RegExp(r'\n\s*\n'))) {
        final passage = piece.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (passage.length < shortest || passage.length > longest) continue;
        seen.add(passage);
      }
      for (final passage in seen) {
        counts[passage] = (counts[passage] ?? 0) + 1;
      }
    }
    final out = [
      for (final entry in counts.entries)
        if (entry.value >= inAtLeast) (text: entry.key, documents: entry.value),
    ]..sort((a, b) => b.documents.compareTo(a.documents));
    return out.length > most ? out.sublist(0, most) : out;
  }

  /// The indexed text of one document. Lets the preview show what OCR read
  /// without running it again.
  String? documentText(String path) {
    final rows = db.select(
      "SELECT text FROM documents WHERE path=? AND ocr=1 "
      "AND state IN ('ready','partial')",
      [path],
    );
    if (rows.isEmpty) return null;
    final text = (rows.first['text'] as String).trim();
    return text.isEmpty ? null : text;
  }

  /// Native text already extracted from a PDF, but only while the indexed row
  /// still describes the exact file on disk. OCR text and partial/truncated
  /// rows are deliberately excluded: an editor must never silently import an
  /// approximation or only the beginning of a document.
  String? nativeDocumentText(String path, int size, int modified) {
    final rows = db.select(
      "SELECT text FROM documents WHERE path=? AND size=? AND modified=? "
      "AND ocr=0 AND state='ready'",
      [path, size, modified],
    );
    if (rows.isEmpty) return null;
    final text = (rows.first['text'] as String).trim();
    return text.isEmpty ? null : text;
  }

  List<Map<String, Object?>> ocrPaths() => db
      .select('SELECT id,path,recursive FROM ocr_paths ORDER BY path')
      .map((row) => Map<String, Object?>.from(row))
      .toList();

  void addOcrPath(String path, bool recursive) => db.execute(
    'INSERT OR REPLACE INTO ocr_paths(path,recursive) VALUES(?,?)',
    [path, recursive ? 1 : 0],
  );

  void removeOcrPath(int id) =>
      db.execute('DELETE FROM ocr_paths WHERE id=?', [id]);

  /// SQL that limits a query to the chosen folders. Empty when none are set,
  /// which means the whole archive.
  (String, List<Object?>) _ocrScope() {
    final paths = ocrPaths();
    if (paths.isEmpty) return ('', const []);
    final parts = <String>[];
    final params = <Object?>[];
    for (final row in paths) {
      final path = row['path'] as String;
      final prefix = '$path${p.separator}';
      if (row['recursive'] == 1) {
        // Compare the literal prefix instead of using LIKE. A perfectly valid
        // folder called "Dava_2026" or "%10" must not turn '_'/'%' into SQL
        // wildcards and silently send neighbouring folders through OCR.
        // The separator also keeps "/Belgeler" from matching
        // "/Belgeler eski".
        // Let SQLite count characters. Dart counts UTF-16 code units, which
        // differs for an emoji in a perfectly legal folder name.
        parts.add('(path=? OR substr(path,1,length(?))=?)');
        params.addAll([path, prefix, prefix]);
      } else {
        // One level only: below the folder, with no further separator after it.
        parts.add(
          '(substr(path,1,length(?))=? AND '
          'instr(substr(path,length(?)+1), ?)=0)',
        );
        params.addAll([prefix, prefix, prefix, p.separator]);
      }
    }
    return (' AND (${parts.join(' OR ')})', params);
  }

  /// How many documents OCR would take on right now, without changing anything.
  /// The dialog shows this before the user commits to the work.
  int ocrCandidates() {
    final (scope, params) = _ocrScope();
    return db
            .select(
              "SELECT count(*) AS n FROM documents "
              "WHERE state IN ('no_text','image') "
              "AND extension IN $_ocrFormats$scope",
              params,
            )
            .first['n']
        as int;
  }

  List<Map<String, Object?>> annotations(String docKey) => db
      .select(
        'SELECT id,doc_key AS docKey,path,page,rects,text,color,note,created,rotation '
        'FROM annotations WHERE doc_key=? ORDER BY page, created',
        [docKey],
      )
      .map((row) => Map<String, Object?>.from(row))
      .toList();

  /// Insert when [id] is 0, otherwise update the colour and note in place.
  /// Geometry never changes after creation, so an edit cannot move a highlight.
  int saveAnnotation(Map<String, Object?> row) {
    final id = row['id'] as int? ?? 0;
    if (id > 0) {
      db.execute('UPDATE annotations SET color=?, note=? WHERE id=?', [
        row['color'],
        row['note'],
        id,
      ]);
      return id;
    }
    db.execute(
      'INSERT INTO annotations(doc_key,path,page,rects,text,color,note,created,rotation) '
      'VALUES(?,?,?,?,?,?,?,?,?)',
      [
        row['docKey'],
        row['path'],
        row['page'],
        row['rects'],
        row['text'],
        row['color'],
        row['note'],
        row['created'],
        row['rotation'] ?? 0,
      ],
    );
    return db.lastInsertRowId;
  }

  void deleteAnnotation(int id) =>
      db.execute('DELETE FROM annotations WHERE id=?', [id]);

  /// Documents OCR can do something about: they parsed fine, they just hold no
  /// searchable text. Marking exactly these pending is what makes switching OCR
  /// on take effect, without re-reading the documents that are already
  /// searchable — a full rescan would re-parse the whole archive to reach the
  /// fifth of it that needs it. Returns how many are queued.
  int markUnreadableForOcr() {
    final (scope, params) = _ocrScope();
    db.execute(
      "UPDATE documents SET state='pending' "
      "WHERE state IN ('no_text','image') "
      "AND extension IN $_ocrFormats$scope",
      params,
    );
    return db.updatedRows;
  }

  /// Whether OCR should be attempted for this document. Checked at extraction
  /// time, so narrowing the folders later stops work that has not run yet.
  bool ocrCovers(String path) {
    final (scope, params) = _ocrScope();
    if (scope.isEmpty) return true;
    return db.select('SELECT 1 FROM documents WHERE path=?$scope', [
      path,
      ...params,
    ]).isNotEmpty;
  }

  void queuePaths(Iterable<String> paths) => transaction(() {
    for (final path in paths) {
      db.execute('INSERT OR REPLACE INTO pending_paths(path) VALUES(?)', [
        path,
      ]);
    }
  });

  List<Map<String, Object?>> pendingPaths() => db
      .select('SELECT id,path FROM pending_paths ORDER BY id')
      .map((row) => Map<String, Object?>.from(row))
      .toList();

  bool get hasPendingPaths =>
      db.select('SELECT 1 FROM pending_paths LIMIT 1').isNotEmpty;

  Map<String, Object?>? nextPendingPath(int afterId) {
    final rows = db.select(
      'SELECT id,path FROM pending_paths WHERE id>? ORDER BY id LIMIT 1',
      [afterId],
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
  }

  void completePath(int id) =>
      db.execute('DELETE FROM pending_paths WHERE id=?', [id]);

  /// Path comparisons, rather than LIKE, keep %, _ and separators literal.
  void removeMissingPath(int sourceId, String path) => transaction(() {
    final rows = db.select(
      'SELECT d.id,d.path FROM documents d JOIN memberships m ON m.document_id=d.id WHERE m.source_id=?',
      [sourceId],
    );
    for (final row in rows) {
      final stored = row['path'] as String;
      if (p.equals(stored, path) || p.isWithin(path, stored)) {
        db.execute(
          'DELETE FROM memberships WHERE source_id=? AND document_id=?',
          [sourceId, row['id']],
        );
      }
    }
    _removeOrphans();
  });

  void beginScan(int sourceId) {
    db.execute('DELETE FROM scan_seen WHERE source_id=?', [sourceId]);
    _activeScans.add(sourceId);
  }

  void abandonScans() {
    _activeScans.clear();
    db.execute('DELETE FROM scan_seen');
  }

  void _markMembership(int sourceId, int documentId, int token) {
    if (_activeScans.contains(sourceId)) {
      db.execute(
        'INSERT OR IGNORE INTO memberships(source_id,document_id,seen) VALUES(?,?,?)',
        [sourceId, documentId, token],
      );
      db.execute(
        'INSERT OR IGNORE INTO scan_seen(source_id,document_id) VALUES(?,?)',
        [sourceId, documentId],
      );
    } else {
      db.execute(
        'INSERT OR REPLACE INTO memberships(source_id,document_id,seen) VALUES(?,?,?)',
        [sourceId, documentId, token],
      );
    }
  }

  void close() => db.dispose();
  void transaction(void Function() action) {
    db.execute('BEGIN IMMEDIATE');
    try {
      action();
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<Map<String, Object?>> sources() => db
      .select('''
    SELECT s.*, count(m.document_id) AS count FROM sources s
    LEFT JOIN memberships m ON m.source_id=s.id GROUP BY s.id ORDER BY s.path
  ''')
      .map((r) => Map<String, Object?>.from(r))
      .toList();
  Map<String, Object?>? source(int id) {
    final rows = db.select('SELECT * FROM sources WHERE id=?', [id]);
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  int addSource(String path, bool folder, bool recursive) {
    db.execute(
      '''INSERT INTO sources(path,kind,recursive) VALUES(?,?,?)
      ON CONFLICT(path) DO UPDATE SET recursive=excluded.recursive''',
      [
        p.normalize(p.absolute(path)),
        folder ? 'folder' : 'file',
        recursive ? 1 : 0,
      ],
    );
    return db.select('SELECT id FROM sources WHERE path=?', [
          p.normalize(p.absolute(path)),
        ]).first['id']
        as int;
  }

  void removeSource(int id) => transaction(() {
    db.execute('DELETE FROM sources WHERE id=?', [id]);
    _removeOrphans();
  });
  void _removeOrphans() => db.execute(
    'DELETE FROM documents WHERE NOT EXISTS (SELECT 1 FROM memberships WHERE document_id=documents.id)',
  );
  void finishScan(
    int sourceId,
    int token, {
    String? error,
    bool prune = true,
    String? within,
  }) => transaction(() {
    if (prune) {
      if (within == null) {
        if (_activeScans.contains(sourceId)) {
          db.execute(
            'DELETE FROM memberships WHERE source_id=? AND document_id NOT IN (SELECT document_id FROM scan_seen WHERE source_id=?)',
            [sourceId, sourceId],
          );
        } else {
          db.execute('DELETE FROM memberships WHERE source_id=? AND seen<>?', [
            sourceId,
            token,
          ]);
        }
      } else {
        final predicate = _activeScans.contains(sourceId)
            ? 'm.document_id NOT IN (SELECT document_id FROM scan_seen WHERE source_id=?)'
            : 'm.seen<>?';
        final rows = db.select(
          'SELECT d.id,d.path FROM documents d JOIN memberships m ON m.document_id=d.id WHERE m.source_id=? AND $predicate',
          [sourceId, _activeScans.contains(sourceId) ? sourceId : token],
        );
        for (final row in rows) {
          final path = row['path'] as String;
          if (p.equals(within, path) || p.isWithin(within, path)) {
            db.execute(
              'DELETE FROM memberships WHERE source_id=? AND document_id=?',
              [sourceId, row['id']],
            );
          }
        }
      }
      _removeOrphans();
    }
    _activeScans.remove(sourceId);
    db.execute('DELETE FROM scan_seen WHERE source_id=?', [sourceId]);
    db.execute('UPDATE sources SET error=?, scanned=? WHERE id=?', [
      error,
      token,
      sourceId,
    ]);
  });
  Map<String, Object?>? document(String path) {
    final rows = db.select(
      'SELECT id,size,modified,changed,state FROM documents WHERE path=?',
      [path],
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  /// Registers a whole scan in a single transaction and returns the files whose
  /// content must be extracted again. One transaction per file cost a WAL
  /// commit each, which dominated rescans of a large folder.
  ///
  /// A document that previously failed is only retried when the file itself
  /// changed or when [force] is set, so an unreadable file (an offline cloud
  /// placeholder, say) is not parsed again on every launch.
  List<({int id, String path, int size, int modified, int changed})>
  registerFiles({
    required int sourceId,
    required int token,
    required List<({String path, int size, int modified, int changed})> files,
    bool force = false,
  }) {
    final pending =
        <({int id, String path, int size, int modified, int changed})>[];
    final scanning = _activeScans.contains(sourceId);
    // Prepared once for the whole batch: a launch rescans every file of
    // the archive, and preparing three statements for each unchanged one
    // was most of what that cost.
    final lookup = db.prepare(
      'SELECT d.id,d.size,d.modified,d.changed,d.state, EXISTS(SELECT 1 FROM '
      'memberships m WHERE m.source_id=? AND m.document_id=d.id) AS member '
      'FROM documents d WHERE d.path=?',
    );
    final seen = scanning
        ? db.prepare(
            'INSERT OR IGNORE INTO scan_seen(source_id,document_id) VALUES(?,?)',
          )
        : null;
    try {
      transaction(() {
        for (final file in files) {
          final rows = lookup.select([sourceId, file.path]);
          final previous = rows.isEmpty ? null : rows.first;
          final changedContent =
              force ||
              previous == null ||
              previous['state'] == 'pending' ||
              previous['size'] != file.size ||
              previous['modified'] != file.modified ||
              previous['changed'] != file.changed;
          if (!changedContent) {
            final id = previous['id'] as int;
            if (!scanning) {
              _markMembership(sourceId, id, token);
            } else {
              // During a scan the membership is only inserted if missing,
              // so one that exists needs no write; the scan only notes it.
              if (previous['member'] != 1) {
                _markMembership(sourceId, id, token);
              } else {
                seen!.execute([sourceId, id]);
              }
            }
            continue;
          }
          final id = _register(
            sourceId: sourceId,
            token: token,
            path: file.path,
            size: file.size,
            modified: file.modified,
            changed: file.changed,
            changedContent: changedContent,
          );
          if (changedContent) {
            pending.add((
              id: id,
              path: file.path,
              size: file.size,
              modified: file.modified,
              changed: file.changed,
            ));
          }
        }
      });
    } finally {
      lookup.dispose();
      seen?.dispose();
    }
    return pending;
  }

  int registerFile({
    required int sourceId,
    required int token,
    required String path,
    required int size,
    required int modified,
    required int changed,
    required bool changedContent,
  }) {
    late int registeredId;
    transaction(
      () => registeredId = _register(
        sourceId: sourceId,
        token: token,
        path: path,
        size: size,
        modified: modified,
        changed: changed,
        changedContent: changedContent,
      ),
    );
    return registeredId;
  }

  int _register({
    required int sourceId,
    required int token,
    required String path,
    required int size,
    required int modified,
    required int changed,
    required bool changedContent,
  }) {
    final name = p.basename(path);
    db.execute(
      '''INSERT INTO documents(path,name,extension,size,modified,changed,added)
      VALUES(?,?,?,?,?,?,?) ON CONFLICT(path) DO UPDATE SET size=excluded.size,
      modified=excluded.modified, changed=excluded.changed''',
      [
        path,
        name,
        p.extension(path).substring(1).toLowerCase(),
        size,
        modified,
        changed,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    final id =
        db.select('SELECT id FROM documents WHERE path=?', [path]).first['id']
            as int;
    _markMembership(sourceId, id, token);
    if (changedContent) _writeContent(id, '', 'pending', null, false);
    return id;
  }

  void setContent(
    int id,
    String text,
    String state,
    String? note, {
    bool ocr = false,
  }) => transaction(() => _writeContent(id, text, state, note, ocr));

  void _writeContent(
    int id,
    String text,
    String state,
    String? note,
    bool ocr,
  ) {
    final row = db.select('SELECT name FROM documents WHERE id=?', [id]);
    if (row.isEmpty) return; // Source removed during extraction.
    db.execute('UPDATE documents SET text=?,state=?,note=?,ocr=? WHERE id=?', [
      text,
      state,
      note,
      ocr ? 1 : 0,
      id,
    ]);
    db.execute('DELETE FROM search_fts WHERE rowid=?', [id]);
    db.execute('INSERT INTO search_fts(rowid,name,body) VALUES(?,?,?)', [
      id,
      foldSearchText(row.first['name'] as String),
      foldSearchText(text),
    ]);
  }

  Map<String, Object?> stats() {
    final rows = db.select(
      'SELECT state,count(*) AS count FROM documents GROUP BY state',
    );
    final byState = {
      for (final row in rows) row['state'] as String: row['count'] as int,
    };
    return {
      'total': byState.values.fold<int>(0, (a, b) => a + b),
      'ready': (byState['ready'] ?? 0) + (byState['partial'] ?? 0),
      'pending': byState['pending'] ?? 0,
      'errors': byState['error'] ?? 0,
      'namesOnly':
          (byState['image'] ?? 0) +
          (byState['no_text'] ?? 0) +
          (byState['too_large'] ?? 0),
      'ocr':
          db
                  .select('SELECT count(*) AS n FROM documents WHERE ocr=1')
                  .first['n']
              as int,
      'sources': sources(),
      'recentQueries': recentQueries(),
    };
  }

  // Windows clocks can hand out the same timestamp to searches typed moments
  // apart, so insertion order breaks the tie. INSERT OR REPLACE gives the
  // rewritten row a new rowid, which keeps the newest query first.
  List<String> recentQueries() => db
      .select(
        'SELECT query FROM recent_queries ORDER BY searched DESC, rowid DESC LIMIT 12',
      )
      .map((r) => r['query'] as String)
      .toList();
  void rememberQuery(String text) {
    final query = text.trim();
    if (query.isEmpty ||
        query.length > SearchQuery.maxQueryCharacters ||
        SearchQuery.expression(query).isEmpty) {
      return;
    }
    transaction(() {
      db.execute(
        'INSERT OR REPLACE INTO recent_queries(normalized,query,searched) VALUES(?,?,?)',
        [foldSearchText(query), query, DateTime.now().microsecondsSinceEpoch],
      );
      db.execute(
        'DELETE FROM recent_queries WHERE normalized NOT IN (SELECT normalized FROM recent_queries ORDER BY searched DESC, rowid DESC LIMIT 12)',
      );
    });
  }

  void clearHistory() => db.execute('DELETE FROM recent_queries');

  Map<String, Object?> search(Map request) {
    final clock = Stopwatch()..start();
    final query = request['text'] as String? ?? '';
    final expression = SearchQuery.expression(
      query,
      namesOnly: request['namesOnly'] == true,
      match:
          SearchMatch.values
              .where((m) => m.name == request['match'])
              .firstOrNull ??
          SearchMatch.all,
    );
    final searching = query.trim().isNotEmpty;
    if (searching && expression.isEmpty) {
      return {
        'hits': [],
        'total': 0,
        'elapsedMicros': clock.elapsedMicroseconds,
      };
    }
    final from = searching
        ? 'documents d JOIN search_fts ON search_fts.rowid=d.id'
        : 'documents d';
    final conditions = <String>[];
    final params = <Object?>[];
    if (searching) {
      conditions.add('search_fts MATCH ?');
      params.add(expression);
    }
    final extensions = (request['extensions'] as List? ?? []).cast<String>();
    if (extensions.isNotEmpty) {
      conditions.add(
        'd.extension IN (${List.filled(extensions.length, '?').join(',')})',
      );
      params.addAll(extensions);
    }
    if (request['ocrOnly'] == true) {
      conditions.add('d.ocr=1');
    }
    if (request['sourceId'] != null) {
      conditions.add(
        'EXISTS (SELECT 1 FROM memberships m WHERE m.document_id=d.id AND m.source_id=?)',
      );
      params.add(request['sourceId']);
    }
    final within = request['within'];
    if (within is String && within.isNotEmpty) {
      // '!' escapes, as '\\' would clash with Windows paths.
      final folder = within.endsWith(p.separator)
          ? within
          : '$within${p.separator}';
      conditions.add("d.path LIKE ? ESCAPE '!'");
      params.add(
        '${folder.replaceAll('!', '!!').replaceAll('%', '!%').replaceAll('_', '!_')}%',
      );
    }
    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
    final order = switch (request['sort']) {
      'name' => 'd.name COLLATE NOCASE, d.id',
      'oldest' => 'd.modified, d.id',
      'added' => 'd.added DESC, d.id DESC',
      'newest' => 'd.modified DESC, d.id',
      _ =>
        searching
            ? 'bm25(search_fts,5.0,1.0), d.modified DESC, d.id'
            : 'd.modified DESC, d.id',
    };
    final total = db
        .select('SELECT count(*) AS total FROM $from $where', params)
        .first['total'];
    final rows = db.select(
      "SELECT d.*, ${searching ? "snippet(search_fts,1,'','',' … ',40)" : "''"} AS fragment FROM $from $where ORDER BY $order LIMIT ? OFFSET ?",
      [
        ...params,
        (request['limit'] as int? ?? 50).clamp(1, 100),
        (request['offset'] as int? ?? 0).clamp(0, 10000000),
      ],
    );
    final terms = SearchQuery.terms(query);
    final hits = rows.map((row) {
      final value = Map<String, Object?>.from(row);
      value['excerpt'] = _excerpt(
        value.remove('text') as String,
        terms,
        value.remove('fragment') as String,
      );
      return value;
    }).toList();
    return {
      'hits': hits,
      'total': total,
      'elapsedMicros': clock.elapsedMicroseconds,
    };
  }

  /// Context windows around the query matches in one document, for the hover
  /// card. Built on demand so search results never carry whole texts.
  ///
  /// [foldSearchText] replaces each character with exactly one character, so an
  /// offset found in the folded text addresses the original text unchanged.
  Map<String, Object?> passages(int id, String query, {int limit = 3}) {
    final rows = db.select('SELECT text FROM documents WHERE id=?', [id]);
    final text = rows.isEmpty ? '' : (rows.first['text'] as String? ?? '');
    if (text.isEmpty) return {'passages': <String>[], 'matches': 0};
    final terms = SearchQuery.terms(query);
    final opening = {
      'passages': [_window(text, 0, 700)],
      'matches': 0,
    };
    if (terms.isEmpty) return opening;
    final normalized = foldSearchText(text);
    final found = <int>[];
    for (final term in terms) {
      for (
        var at = normalized.indexOf(term);
        at >= 0;
        at = normalized.indexOf(term, at + term.length)
      ) {
        found.add(at);
        if (found.length >= 2000) break;
      }
    }
    if (found.isEmpty) return opening;
    found.sort();
    final windows = <String>[];
    var covered = -1;
    for (final at in found) {
      if (at <= covered) continue; // Already inside a window being shown.
      final start = (at - 120).clamp(0, text.length);
      final end = (at + 280).clamp(0, text.length);
      windows.add(_window(text, start, end - start));
      covered = end;
      if (windows.length >= limit) break;
    }
    return {'passages': windows, 'matches': found.length};
  }

  static String _window(String text, int start, int length) {
    final end = (start + length).clamp(0, text.length);
    final body = text
        .substring(start, end)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return '${start > 0 ? '… ' : ''}$body${end < text.length ? ' …' : ''}';
  }

  // FTS chooses the passage with the most relevant cluster of hits, even near
  // the end of a large document. Map it back to the original Turkish text.
  static String _excerpt(String text, List<String> terms, String fragment) {
    if (text.isEmpty) return '';
    final normalized = foldSearchText(text);
    final passages = fragment
        .split(' … ')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    var first = -1;
    var length = 300;
    if (passages.isNotEmpty) {
      final passage = passages.reduce((a, b) => a.length >= b.length ? a : b);
      first = normalized.indexOf(passage);
      length = passage.length.clamp(200, 480);
    }
    if (first < 0) {
      first = 0;
      for (final term in terms) {
        final found = normalized.indexOf(term);
        if (found >= 0) {
          first = (found - 60).clamp(0, text.length);
          break;
        }
      }
    }
    final end = (first + length).clamp(0, text.length);
    return '${first > 0 ? '… ' : ''}${text.substring(first, end).replaceAll(RegExp(r'\s+'), ' ')}${end < text.length ? ' …' : ''}';
  }
}

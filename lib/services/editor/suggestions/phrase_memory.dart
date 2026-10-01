import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../platform/app_directories.dart';
import 'phrases.dart';

/// A phrase Folio has learned, with what it knows about it.
class LearnedPhrase {
  const LearnedPhrase({
    required this.key,
    required this.text,
    required this.archive,
    required this.saved,
    required this.accepted,
    required this.seen,
  });

  /// [foldPhrase] of [text]; what it is matched and stored by.
  final String key;
  final String text;

  /// In how many documents of the archive it appears.
  final int archive;

  /// In how many documents saved from the editor it appears.
  final int saved;

  /// How many times it was taken from the suggestion list.
  final int accepted;

  /// When it was last seen in a document or taken.
  final DateTime seen;

  int get documents => archive + saved;

  /// Offered once it is in two different documents, or has been taken once.
  bool get offered => documents >= 2 || accepted >= 1;

  /// Documents and takings, fading as the phrase goes unused: one not seen
  /// for three months counts half.
  double score(DateTime now) {
    final days = now.difference(seen).inHours / 24;
    return (documents + 3 * accepted) / (1 + math.max(0, days) / 90);
  }
}

/// What Folio has learned from the documents saved in the editor and from
/// the archive's index, kept in its own SQLite file on this computer only.
///
/// A document counts once however many times it is saved; saving it again
/// replaces what it contributed. The archive is read in the background and
/// only phrases found in at least three of its documents are kept.
class PhraseMemory extends ChangeNotifier {
  PhraseMemory._(this._db, this.path) {
    _db.execute('''
      PRAGMA journal_mode=WAL;
      PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS phrases (
        key TEXT PRIMARY KEY, text TEXT NOT NULL,
        archive INTEGER NOT NULL DEFAULT 0,
        accepted INTEGER NOT NULL DEFAULT 0,
        seen INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS saved (
        doc TEXT NOT NULL, key TEXT NOT NULL, PRIMARY KEY(doc, key));
      CREATE INDEX IF NOT EXISTS saved_key ON saved(key);
      CREATE TABLE IF NOT EXISTS blocked (key TEXT PRIMARY KEY, text TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS meta (name TEXT PRIMARY KEY, value TEXT NOT NULL);
    ''');
    _reload();
  }

  final Database _db;

  /// Where the file is; the archive reader opens it again from its isolate.
  final String path;

  var _phrases = <LearnedPhrase>[];
  var _blocked = <String>{};

  /// Everything learned, blocked phrases left out, best first.
  List<LearnedPhrase> get phrases => _phrases;

  /// The phrases the reader asked never to be offered again.
  Set<String> get blocked => _blocked;

  bool _learningArchive = false;
  bool get learningArchive => _learningArchive;

  /// When the archive was last read, if ever.
  DateTime? get archiveLearned {
    final row = _db.select(
      "SELECT value FROM meta WHERE name='archive-learned'",
    );
    return row.isEmpty ? null : DateTime.tryParse(row.first['value'] as String);
  }

  static PhraseMemory? _shared;
  static Future<PhraseMemory>? _opening;

  /// The one kept in Folio's data folder.
  static Future<PhraseMemory> shared() async {
    if (_shared != null) return _shared!;
    return _opening ??= () async {
      final dir = await folioSupportDirectory();
      final file = p.join(dir.path, 'oneriler.sqlite');
      return _shared = PhraseMemory.open(file);
    }();
  }

  /// Already opened by [shared], for deciding within a keystroke.
  static PhraseMemory? get cached => _shared;

  static PhraseMemory open(String path) =>
      PhraseMemory._(sqlite3.open(path), path);

  @visibleForTesting
  static PhraseMemory memory() => PhraseMemory._(sqlite3.openInMemory(), '');

  @visibleForTesting
  static void useShared(PhraseMemory? memory) {
    _shared = memory;
    _opening = memory == null ? null : Future.value(memory);
  }

  void _reload() {
    final rows = _db.select('''
      SELECT p.key, p.text, p.archive, p.accepted, p.seen,
             (SELECT count(*) FROM saved s WHERE s.key = p.key) AS saved
      FROM phrases p WHERE p.key NOT IN (SELECT key FROM blocked)''');
    final now = DateTime.now();
    _phrases = [
      for (final r in rows)
        LearnedPhrase(
          key: r['key'] as String,
          text: r['text'] as String,
          archive: r['archive'] as int,
          saved: r['saved'] as int,
          accepted: r['accepted'] as int,
          seen: DateTime.fromMillisecondsSinceEpoch(r['seen'] as int),
        ),
    ]..sort((a, b) => b.score(now).compareTo(a.score(now)));
    _blocked = {
      for (final r in _db.select('SELECT key FROM blocked')) r['key'] as String,
    };
    notifyListeners();
  }

  /// Learns from a document just saved at [doc], replacing what an earlier
  /// save of the same document taught.
  void learnSaved(String doc, String text) {
    final found = phrasesIn(text);
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM saved WHERE doc = ?', [doc]);
      final phrase = _db.prepare(
        'INSERT INTO phrases(key, text, seen) VALUES(?, ?, ?) '
        'ON CONFLICT(key) DO UPDATE SET seen = excluded.seen',
      );
      final saved = _db.prepare('INSERT INTO saved(doc, key) VALUES(?, ?)');
      for (final e in found.entries) {
        phrase.execute([e.key, e.value, now]);
        saved.execute([doc, e.key]);
      }
      phrase.dispose();
      saved.dispose();
      _forgetOrphans();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    _reload();
  }

  /// Phrases nothing vouches for any more.
  void _forgetOrphans() => _db.execute('''
    DELETE FROM phrases WHERE archive = 0 AND accepted = 0
      AND key NOT IN (SELECT key FROM saved)''');

  /// The reader took [text] from the list. Only learned phrases are
  /// counted; the built-in ones and the profile need no remembering.
  void accepted(String key) {
    _db.execute(
      'UPDATE phrases SET accepted = accepted + 1, seen = ? WHERE key = ?',
      [DateTime.now().millisecondsSinceEpoch, key],
    );
    if (_db.updatedRows > 0) _reload();
  }

  void remove(String key) {
    _db.execute('DELETE FROM phrases WHERE key = ?', [key]);
    _db.execute('DELETE FROM saved WHERE key = ?', [key]);
    _reload();
  }

  /// Never offers [text] again, whatever the documents say.
  void block(String key, String text) {
    _db.execute('INSERT OR REPLACE INTO blocked(key, text) VALUES(?, ?)', [
      key,
      text,
    ]);
    _reload();
  }

  void unblock(String key) {
    _db.execute('DELETE FROM blocked WHERE key = ?', [key]);
    _reload();
  }

  /// Forgets everything learned; the blocked list stays.
  void clear() {
    _db.execute('DELETE FROM phrases; DELETE FROM saved;');
    _db.execute("DELETE FROM meta WHERE name='archive-learned'");
    _reload();
  }

  /// Reads the archive's index at [indexPath] in the background and keeps
  /// the phrases found in at least three of its documents, at most
  /// [limit]. Returns how many were kept.
  Future<int> learnArchive(String indexPath, {int limit = 5000}) async {
    if (_learningArchive) return 0;
    _learningArchive = true;
    notifyListeners();
    try {
      final counted = await Isolate.run(
        () => countArchive(indexPath, limit: limit),
      );
      _storeArchive(counted);
      return counted.length;
    } finally {
      _learningArchive = false;
      _reload();
    }
  }

  /// Reads the archive again if it has never been read, or not for a week,
  /// and the reader lets it be learned from.
  Future<void> learnArchiveIfDue(
    String indexPath, {
    required bool allowed,
  }) async {
    if (!allowed) return;
    final last = archiveLearned;
    if (last != null && DateTime.now().difference(last).inDays < 7) return;
    if (!File(indexPath).existsSync()) return;
    try {
      await learnArchive(indexPath);
    } on Object catch (e) {
      debugPrint('Arşivden öğrenilemedi: $e');
    }
  }

  void _storeArchive(List<(String, String, int)> counted) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute('BEGIN');
    try {
      _db.execute('UPDATE phrases SET archive = 0');
      final put = _db.prepare(
        'INSERT INTO phrases(key, text, archive, seen) VALUES(?, ?, ?, ?) '
        'ON CONFLICT(key) DO UPDATE SET archive = excluded.archive',
      );
      for (final (key, text, n) in counted) {
        put.execute([key, text, n, now]);
      }
      put.dispose();
      _forgetOrphans();
      _db.execute(
        "INSERT OR REPLACE INTO meta(name, value) VALUES('archive-learned', ?)",
        [DateTime.now().toIso8601String()],
      );
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  void dispose() {
    if (identical(_shared, this)) {
      _shared = null;
      _opening = null;
    }
    _db.dispose();
    super.dispose();
  }
}

/// The documents whose text is the lawyer's own kind of writing: text the
/// index read directly, not by OCR, whose guesses rarely repeat.
const _written = "('udf','docx','doc','rtf','odt','txt','pdf')";

/// Counts, in the index at [indexPath], in how many documents each phrase
/// appears, and returns those in at least [least] of them, most common
/// first: (key, text as most often written, documents). Runs in an isolate.
@visibleForTesting
List<(String, String, int)> countArchive(
  String indexPath, {
  int least = 3,
  int limit = 5000,
}) {
  final db = sqlite3.open(indexPath, mode: OpenMode.readOnly);
  final counts = <String, int>{};
  final texts = <String, String>{};
  try {
    final query = db.prepare('''
      SELECT text FROM documents
      WHERE state IN ('ready', 'partial') AND coalesce(ocr, 0) = 0
        AND extension IN $_written AND length(text) > 0
      ORDER BY modified DESC LIMIT 20000''');
    final rows = query.selectCursor();
    while (rows.moveNext()) {
      var text = rows.current['text'] as String;
      if (text.length > 400000) text = text.substring(0, 400000);
      phrasesIn(text).forEach((key, phrase) {
        counts[key] = (counts[key] ?? 0) + 1;
        texts.putIfAbsent(key, () => phrase);
      });
      // Keep memory bounded on a very large archive: phrases met once so
      // far are dropped when there are too many of them.
      if (counts.length > 600000) {
        counts.removeWhere((_, n) => n < 2);
        texts.removeWhere((k, _) => !counts.containsKey(k));
      }
    }
    query.dispose();
  } finally {
    db.dispose();
  }
  final kept = [
    for (final e in counts.entries)
      if (e.value >= least) (e.key, texts[e.key]!, e.value),
  ]..sort((a, b) => b.$3.compareTo(a.$3));
  return kept.take(limit).toList();
}

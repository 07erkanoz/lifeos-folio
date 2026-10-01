import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';

/// A passage a lawyer writes over and over.
///
/// Kept as the editor's own delta rather than as plain text: a recital that
/// loses its bold heading, or a list that arrives as one long line, has to be
/// restyled by hand every time, which is most of the saving gone. Measured
/// against a real archive, 309 passages appeared word for word in five or
/// more filings, 3020 times between them.
@immutable
class Snippet {
  const Snippet({
    required this.id,
    required this.name,
    required this.body,
    this.used = 0,
    this.keyword = '',
    this.hotkey,
  });

  final String id;

  /// What the reader looks for it by.
  final String name;

  /// The passage, formatting and all.
  final Delta body;

  /// How often it has been reached for. The list is ordered by this, because
  /// a library of two hundred passages is only usable if the handful that
  /// are used daily rise to the top on their own.
  final int used;

  /// A short word that turns into the passage when Tab follows it: "dil1",
  /// "vek". Empty when there is none.
  final String keyword;

  /// The function key that writes it with Alt held: 1 for Alt+F1. Never 4,
  /// which closes the window on Windows. Null when there is none.
  final int? hotkey;

  /// The keys that may carry a passage: F1 to F12 without F4.
  static const hotkeys = [1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12];

  /// Whether [word] can be a keyword: 2 to 20 letters or digits, no space,
  /// so that it is a word Tab can find in front of the cursor.
  static bool validKeyword(String word) =>
      RegExp(r'^[\p{L}\p{N}_]{2,20}$', unicode: true).hasMatch(word);

  /// The opening of the passage, for the line under the name.
  String get preview {
    final out = StringBuffer();
    for (final operation in body.toList()) {
      final data = operation.data;
      if (data is String) out.write(data);
      if (out.length > 160) break;
    }
    return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// How many characters it puts in, which is where the cursor lands.
  int get length => body.toList().fold(0, (n, operation) {
    final data = operation.data;
    return n + (data is String ? data.length : 1);
  });

  /// A blank the reader fills in when the passage goes in: [TARİH],
  /// [MÜVEKKİL], [ESAS]. Upper case and bracketed, because a filing does not
  /// otherwise write square brackets around a shouted word, and because a
  /// blank left behind has to be impossible to read past.
  static final marker = RegExp(r'\[([A-ZÇĞİÖŞÜ][A-ZÇĞİÖŞÜ0-9 ]{1,23})\]');

  /// The blanks in this passage, in the order they are met, each once.
  List<String> get blanks {
    final seen = <String>[];
    for (final operation in body.toList()) {
      final data = operation.data;
      if (data is! String) continue;
      for (final found in marker.allMatches(data)) {
        final name = found.group(1)!;
        if (!seen.contains(name)) seen.add(name);
      }
    }
    return seen;
  }

  /// The passage with its blanks filled in. A blank with nothing given for
  /// it is left as it is, so it is still visible and still caught on saving.
  Delta withBlanks(Map<String, String> given) {
    final out = Delta();
    for (final operation in body.toList()) {
      final data = operation.data;
      if (data is! String) {
        out.insert(data, operation.attributes);
        continue;
      }
      out.insert(
        data.replaceAllMapped(marker, (found) {
          final value = given[found.group(1)]?.trim() ?? '';
          return value.isEmpty ? found.group(0)! : value;
        }),
        operation.attributes,
      );
    }
    return out;
  }

  Snippet copyWith({
    String? name,
    Delta? body,
    int? used,
    String? keyword,
    int? Function()? hotkey,
  }) => Snippet(
    id: id,
    name: name ?? this.name,
    body: body ?? this.body,
    used: used ?? this.used,
    keyword: keyword ?? this.keyword,
    hotkey: hotkey == null ? this.hotkey : hotkey(),
  );

  Snippet reached() => copyWith(used: used + 1);

  Snippet renamed(String to) => copyWith(name: to);

  Map<String, Object?> toJson() => {
    'id': id,
    'ad': name,
    'govde': body.toJson(),
    'kullanim': used,
    if (keyword.isNotEmpty) 'anahtar': keyword,
    'kisayol': ?hotkey,
  };

  static Snippet? fromJson(Map<String, Object?> row) {
    final id = row['id'], name = row['ad'], body = row['govde'];
    if (id is! String || name is! String || body is! List) return null;
    try {
      final keyword = row['anahtar'];
      final hotkey = (row['kisayol'] as num?)?.toInt();
      return Snippet(
        id: id,
        name: name,
        body: Delta.fromJson(body),
        used: (row['kullanim'] as num?)?.toInt() ?? 0,
        keyword: keyword is String && validKeyword(keyword) ? keyword : '',
        hotkey: hotkeys.contains(hotkey) ? hotkey : null,
      );
    } on Object {
      // A row written by a later version, or damaged. The rest still load.
      return null;
    }
  }
}

/// The passages the reader has kept.
///
/// These are the reader's own writing, not something the app ships, so they
/// live in the application's data directory beside the index rather than in
/// assets. One file, so it can be copied to another machine or backed up
/// without knowing anything about the app.
class SnippetStore extends ChangeNotifier {
  SnippetStore({required this.file});

  /// A library that never reaches the disk. Used by tests, where a real
  /// file write never finishes under the fake clock.
  @visibleForTesting
  SnippetStore.memory() : file = File('') {
    _loaded = true;
  }

  final File file;
  var _all = <Snippet>[];
  var _loaded = false;

  bool get loaded => _loaded;

  /// Most reached for first, then alphabetically, so the order is steady.
  List<Snippet> get all => List.unmodifiable(_all);

  static SnippetStore? _shared;

  /// The one the editor uses. Built once; the file is read on first use.
  static Future<SnippetStore> shared() async {
    final already = _shared;
    if (already != null) {
      await already.load();
      return already;
    }
    final folder = await folioSupportDirectory();
    final store = SnippetStore(
      file: File(p.join(folder.path, 'kaliplar.json')),
    );
    await store.load();
    return _shared = store;
  }

  @visibleForTesting
  static void useShared(SnippetStore store) => _shared = store;

  Future<void> load() async {
    if (_loaded) return;
    try {
      if (await file.exists()) {
        final read = jsonDecode(await file.readAsString());
        if (read is List) {
          _all = [
            for (final row in read)
              if (row is Map) ?Snippet.fromJson(row.cast<String, Object?>()),
          ];
        }
      }
    } on Object {
      // A damaged file must not stop the editor opening. It is left on disk
      // rather than overwritten, so nothing is lost while it is looked at.
      _all = [];
    }
    _order();
    _loaded = true;
    notifyListeners();
  }

  void _order() => _all.sort((a, b) {
    final reached = b.used.compareTo(a.used);
    return reached != 0 ? reached : fold(a.name).compareTo(fold(b.name));
  });

  Future<void> _write() async {
    _order();
    if (file.path.isEmpty) {
      notifyListeners();
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode([for (final one in _all) one.toJson()]),
    );
    notifyListeners();
  }

  /// An id no passage here has. The clock alone is not enough: passages
  /// added in one go — a harvest from the archive — can read the same
  /// microsecond, and two passages under one id are renamed, counted and
  /// deleted together.
  String _newId() {
    final base = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    var id = base;
    for (var n = 1; _all.any((one) => one.id == id); n++) {
      id = '$base-$n';
    }
    return id;
  }

  Future<Snippet> add(String name, Delta body) async {
    final one = Snippet(
      id: _newId(),
      name: name.trim().isEmpty ? 'Adsız kalıp' : name.trim(),
      body: body,
    );
    _all = [..._all, one];
    await _write();
    return one;
  }

  Future<void> remove(String id) async {
    _all = [
      for (final one in _all)
        if (one.id != id) one,
    ];
    await _write();
  }

  Future<void> rename(String id, String to) async {
    _all = [for (final one in _all) one.id == id ? one.renamed(to) : one];
    await _write();
  }

  /// Puts [changed] in place of the passage with its id: name, keyword,
  /// key and body, as the reader edited them.
  Future<void> update(Snippet changed) async {
    _all = [for (final one in _all) one.id == changed.id ? changed : one];
    await _write();
  }

  /// The passage [word] is the keyword of, folded the way a search is, so
  /// "İHTAR" is found by "ihtar". Null when none is.
  Snippet? byKeyword(String word) {
    final want = fold(word);
    if (want.isEmpty) return null;
    for (final one in _all) {
      if (one.keyword.isNotEmpty && fold(one.keyword) == want) return one;
    }
    return null;
  }

  /// The passage on Alt+F[key], or null.
  Snippet? byHotkey(int key) {
    for (final one in _all) {
      if (one.hotkey == key) return one;
    }
    return null;
  }

  /// The passage other than [except] that already has [keyword], or null:
  /// two passages under one keyword would make Tab a guess.
  Snippet? keywordTaken(String keyword, {String? except}) {
    final want = fold(keyword);
    for (final one in _all) {
      if (one.id != except &&
          one.keyword.isNotEmpty &&
          fold(one.keyword) == want) {
        return one;
      }
    }
    return null;
  }

  /// The passage other than [except] already on Alt+F[key], or null.
  Snippet? hotkeyTaken(int key, {String? except}) {
    for (final one in _all) {
      if (one.id != except && one.hotkey == key) return one;
    }
    return null;
  }

  /// Every passage, for keeping elsewhere or carrying to another computer.
  String export() =>
      const JsonEncoder.withIndent('  ')
          .convert([for (final one in _all) one.toJson()]);

  /// Adds the passages in [json], as [export] wrote them. A passage already
  /// here word for word is not added twice; a keyword or key another
  /// passage has is dropped rather than taken from it. Answers how many were
  /// added.
  Future<int> import(String json) async {
    final read = jsonDecode(json);
    if (read is! List) {
      throw const FormatException('Bu dosya bir kalıp listesi değil.');
    }
    var added = 0;
    final seen = {
      for (final one in _all)
        '${fold(one.name)}|${jsonEncode(one.body.toJson())}',
    };
    for (final row in read) {
      if (row is! Map) continue;
      final one = Snippet.fromJson(row.cast<String, Object?>());
      if (one == null) continue;
      final key = '${fold(one.name)}|${jsonEncode(one.body.toJson())}';
      if (!seen.add(key)) continue;
      final keyword =
          one.keyword.isNotEmpty && keywordTaken(one.keyword) == null
          ? one.keyword
          : '';
      final hotkey = one.hotkey != null && hotkeyTaken(one.hotkey!) == null
          ? one.hotkey
          : null;
      _all = [
        ..._all,
        Snippet(
          id: _newId(),
          name: one.name,
          body: one.body,
          used: 0,
          keyword: keyword,
          hotkey: hotkey,
        ),
      ];
      added++;
    }
    if (added > 0) await _write();
    return added;
  }

  /// Counts a use, which is what decides the order next time.
  Future<void> reached(String id) async {
    _all = [for (final one in _all) one.id == id ? one.reached() : one];
    await _write();
  }

  /// Folding for searching, which is deliberately more forgiving than
  /// Turkish itself.
  ///
  /// Strictly, "Islah" begins with a dotless ı and typing "islah" should not
  /// find it. In a search box that is the wrong trade: a miss costs the
  /// reader the passage, a loose match costs them one extra line in a list
  /// of twenty. So the i family is folded together, and so are the letters
  /// people skip when typing quickly. Dart's own toLowerCase is no help
  /// either: it puts a combining dot on a capital İ and the two stop
  /// matching.
  static String fold(String text) {
    const same = {
      'ı': 'i',
      'İ': 'i',
      'I': 'i',
      'ş': 's',
      'Ş': 's',
      'ğ': 'g',
      'Ğ': 'g',
      'ü': 'u',
      'Ü': 'u',
      'ö': 'o',
      'Ö': 'o',
      'ç': 'c',
      'Ç': 'c',
    };
    final out = StringBuffer();
    for (final letter in text.split('')) {
      out.write(same[letter] ?? letter);
    }
    return out.toString().toLowerCase();
  }

  /// What matches [asked], best first.
  ///
  /// The name is searched first and the passage second, because a reader
  /// typing "arab" means the mediation passage, not every filing that
  /// mentions a mediator.
  List<Snippet> matching(String asked) {
    final want = fold(asked).trim();
    if (want.isEmpty) return all;
    final words = want.split(RegExp(r'\s+'));
    final scored = <(Snippet, int)>[];
    for (final one in _all) {
      final name = fold(one.name), body = fold(one.preview);
      var weight = 0;
      for (final word in words) {
        if (name.startsWith(word)) {
          weight += 6;
        } else if (name.contains(word)) {
          weight += 4;
        } else if (body.contains(word)) {
          weight += 1;
        } else {
          weight = -1;
          break;
        }
      }
      if (weight > 0) scored.add((one, weight));
    }
    scored.sort((a, b) {
      final weight = b.$2.compareTo(a.$2);
      return weight != 0 ? weight : b.$1.used.compareTo(a.$1.used);
    });
    return [for (final (one, _) in scored) one];
  }
}

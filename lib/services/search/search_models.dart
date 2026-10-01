import '../../models/evrak_file.dart';

/// ASCII-folded Turkish search key. Original text is kept for display.
String foldSearchText(String value) => value
    .replaceAll('İ', 'i')
    .replaceAll('I', 'i')
    .replaceAll('ı', 'i')
    .toLowerCase()
    .replaceAll('ç', 'c')
    .replaceAll('ğ', 'g')
    .replaceAll('ö', 'o')
    .replaceAll('ş', 's')
    .replaceAll('ü', 'u')
    .replaceAll('â', 'a')
    .replaceAll('î', 'i')
    .replaceAll('û', 'u');

enum SearchMatch { all, phrase, any }

class SearchQuery {
  static const maxQueryCharacters = 16384;
  final SearchMatch match;
  final String text;
  final bool namesOnly;

  /// Show only documents whose text came from OCR. A separate axis from the
  /// format filters: it is about where the text came from, not the file type.
  final bool ocrOnly;
  final List<String> extensions;
  final int? sourceId;

  /// Only what is under this folder: a UYAP case's own documents.
  final String? within;
  final String sort;
  final int offset;
  final int limit;
  const SearchQuery({
    this.text = '',
    this.match = SearchMatch.all,
    this.namesOnly = false,
    this.ocrOnly = false,
    this.extensions = const [],
    this.sourceId,
    this.within,
    this.sort = 'relevance',
    this.offset = 0,
    this.limit = 50,
  });

  Map<String, Object?> toMap() => {
    'text': text,
    'match': match.name,
    'namesOnly': namesOnly,
    'ocrOnly': ocrOnly,
    'extensions': extensions,
    'sourceId': sourceId,
    'within': within,
    'sort': sort,
    'offset': offset,
    'limit': limit,
  };

  /// User text never becomes raw FTS syntax. Quotes request a literal phrase.
  static String expression(
    String query, {
    bool namesOnly = false,
    SearchMatch match = SearchMatch.all,
  }) {
    if (query.length > maxQueryCharacters) {
      throw const FormatException(
        'Arama metni en fazla 16.384 karakter olabilir.',
      );
    }
    final normalized = foldSearchText(query);
    if (match == SearchMatch.phrase) {
      final words = RegExp(
        r'[\p{L}\p{N}_]+',
        unicode: true,
      ).allMatches(normalized).map((m) => m.group(0)!).toList();
      if (words.isEmpty) return '';
      final phrase = '"${words.join(' ')}"';
      return namesOnly ? 'name : ($phrase)' : phrase;
    }
    final units = RegExp(r'"([^"]+)"|([\p{L}\p{N}_]+)', unicode: true)
        .allMatches(normalized)
        .map((match) {
          final phrase = match.group(1);
          final value = (phrase ?? match.group(2)!).replaceAll('"', '""');
          return '"$value"${phrase == null ? '*' : ''}';
        })
        .toList();
    if (units.isEmpty) return '';
    final result = units.toSet().join(
      match == SearchMatch.any ? ' OR ' : ' AND ',
    );
    return namesOnly ? 'name : ($result)' : result;
  }

  static List<String> terms(String query) => RegExp(
    r'[\p{L}\p{N}_]+',
    unicode: true,
  ).allMatches(foldSearchText(query)).map((m) => m.group(0)!).toSet().toList();
}

class LibrarySource {
  final int id;
  final String path;
  final bool folder;
  final bool recursive;
  final int count;
  final String? error;
  const LibrarySource({
    required this.id,
    required this.path,
    required this.folder,
    required this.recursive,
    this.count = 0,
    this.error,
  });
  factory LibrarySource.fromMap(Map row) => LibrarySource(
    id: row['id'],
    path: row['path'],
    folder: row['kind'] == 'folder',
    recursive: row['recursive'] == 1,
    count: row['count'] ?? 0,
    error: row['error'],
  );
  String get name =>
      path
          .replaceAll('\\', '/')
          .split('/')
          .where((s) => s.isNotEmpty)
          .lastOrNull ??
      path;
}

class SearchHit {
  final int id;
  final EvrakFile file;
  final String excerpt;
  final String state;
  final String? note;
  final int modified;
  const SearchHit({
    this.id = 0,
    required this.file,
    this.excerpt = '',
    this.state = 'pending',
    this.note,
    this.modified = 0,
  });
  factory SearchHit.fromMap(Map row) => SearchHit(
    id: row['id'] as int? ?? 0,
    file: EvrakFile(
      path: row['path'],
      name: row['name'],
      format: EvrakFormat.fromExtension(row['extension']),
      sizeInBytes: row['size'],
    ),
    excerpt: row['excerpt'] ?? '',
    state: row['state'],
    note: row['note'],
    modified: row['modified'],
  );
  String get stateLabel => switch (state) {
    'ready' => 'İçerik hazır',
    'pending' => 'İndeksleniyor',
    'image' => 'Dosya adı aranabilir',
    'no_text' => 'Metin katmanı yok',
    'too_large' => 'Yalnız dosya adı aranabilir',
    'partial' => 'Kısmi içerik',
    'error' => 'Okunamadı',
    _ => state,
  };
}

/// What the quick look shows: the passages around the query matches, plus how
/// many matches the whole document holds.
class DocumentPassages {
  final List<String> passages;
  final int matches;
  const DocumentPassages({this.passages = const [], this.matches = 0});
  factory DocumentPassages.fromMap(Map map) => DocumentPassages(
    passages: List<String>.from(map['passages'] as List? ?? const []),
    matches: map['matches'] as int? ?? 0,
  );
  bool get isEmpty => passages.isEmpty;
}

class SearchPage {
  final List<SearchHit> hits;
  final int total;
  final int elapsedMicros;
  const SearchPage(this.hits, this.total, this.elapsedMicros);
  factory SearchPage.fromMap(Map map) => SearchPage(
    (map['hits'] as List).map((r) => SearchHit.fromMap(r)).toList(),
    map['total'],
    map['elapsedMicros'],
  );
}

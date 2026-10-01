import 'dart:math' as math;
import 'dart:typed_data';

enum DiffKind { same, added, removed }

class DiffPiece {
  final DiffKind kind;
  final String text;
  const DiffPiece(this.kind, this.text);
}

/// What changed between two versions of a document's text, word by word.
///
/// Paragraphs are matched first and only the paragraphs that differ are
/// compared word by word, so a long filing with a handful of edits costs a
/// handful of small comparisons rather than one across every word in it.
class TextDiff {
  final List<DiffPiece> pieces;
  final int addedWords, removedWords;
  const TextDiff(this.pieces, this.addedWords, this.removedWords);

  bool get identical => addedWords == 0 && removedWords == 0;

  /// Edits beyond this many are not searched for: two texts that far apart
  /// are shown as one replaced stretch, which is what they are to a reader.
  static const _limit = 2000;

  static TextDiff between(String before, String after) {
    final out = <DiffPiece>[];
    final a = _lines(before), b = _lines(after);
    final script = _script(a, b);
    if (script == null) {
      _emit(out, DiffKind.removed, a.join());
      _emit(out, DiffKind.added, b.join());
    } else {
      var i = 0, j = 0, s = 0;
      while (s < script.length) {
        if (script[s] == _keep) {
          _emit(out, DiffKind.same, a[i++]);
          j++;
          s++;
          continue;
        }
        // A run of removed and added lines is one changed stretch, compared
        // word by word.
        final removed = StringBuffer(), added = StringBuffer();
        while (s < script.length && script[s] != _keep) {
          if (script[s] == _remove) {
            removed.write(a[i++]);
          } else {
            added.write(b[j++]);
          }
          s++;
        }
        _words(out, removed.toString(), added.toString());
      }
    }
    var addedWords = 0, removedWords = 0;
    for (final piece in out) {
      if (piece.kind == DiffKind.same) continue;
      final words = _word.allMatches(piece.text).length;
      if (piece.kind == DiffKind.added) {
        addedWords += words;
      } else {
        removedWords += words;
      }
    }
    return TextDiff(out, addedWords, removedWords);
  }

  static final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);
  static final _token = RegExp(
    r'\s+|[\p{L}\p{N}]+|[^\s\p{L}\p{N}]',
    unicode: true,
  );

  /// Lines with their line break, so that joining a run gives back the text.
  static List<String> _lines(String text) {
    if (text.isEmpty) return const [];
    final normalized = text.endsWith('\n') ? text : '$text\n';
    return RegExp(
      r'[^\n]*\n',
    ).allMatches(normalized).map((m) => m.group(0)!).toList();
  }

  static void _words(List<DiffPiece> out, String before, String after) {
    final a = _token.allMatches(before).map((m) => m.group(0)!).toList();
    final b = _token.allMatches(after).map((m) => m.group(0)!).toList();
    final script = _script(a, b);
    if (script == null) {
      _emit(out, DiffKind.removed, before);
      _emit(out, DiffKind.added, after);
      return;
    }
    var i = 0, j = 0;
    for (final step in script) {
      if (step == _keep) {
        _emit(out, DiffKind.same, a[i++]);
        j++;
      } else if (step == _remove) {
        _emit(out, DiffKind.removed, a[i++]);
      } else {
        _emit(out, DiffKind.added, b[j++]);
      }
    }
  }

  static void _emit(List<DiffPiece> out, DiffKind kind, String text) {
    if (text.isEmpty) return;
    if (out.isNotEmpty && out.last.kind == kind) {
      out[out.length - 1] = DiffPiece(kind, out.last.text + text);
    } else {
      out.add(DiffPiece(kind, text));
    }
  }

  static const _keep = 0, _remove = 1, _add = 2;

  /// The shortest edit script from [a] to [b], one step per item: keep,
  /// remove or add. Myers' algorithm, with the shared start and end set
  /// aside first. Null when more than [_limit] edits would be needed.
  static List<int>? _script(List<String> a, List<String> b) {
    var start = 0;
    while (start < a.length && start < b.length && a[start] == b[start]) {
      start++;
    }
    var endA = a.length, endB = b.length;
    while (endA > start && endB > start && a[endA - 1] == b[endB - 1]) {
      endA--;
      endB--;
    }
    final middle = _myers(
      a.sublist(start, endA),
      b.sublist(start, endB),
    );
    if (middle == null) return null;
    return [
      for (var i = 0; i < start; i++) _keep,
      ...middle,
      for (var i = endA; i < a.length; i++) _keep,
    ];
  }

  static List<int>? _myers(List<String> a, List<String> b) {
    final n = a.length, m = b.length;
    if (n == 0) return List.filled(m, _add);
    if (m == 0) return List.filled(n, _remove);
    final max = math.min(n + m, _limit);
    final offset = max + 1;
    final v = Int32List(2 * max + 3);
    // What v held at the start of each round, for the walk back.
    final trace = <Int32List>[];
    for (var d = 0; d <= max; d++) {
      trace.add(Int32List.fromList(v.sublist(offset - d, offset + d + 1)));
      for (var k = -d; k <= d; k += 2) {
        var x = k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])
            ? v[offset + k + 1]
            : v[offset + k - 1] + 1;
        var y = x - k;
        while (x < n && y < m && a[x] == b[y]) {
          x++;
          y++;
        }
        v[offset + k] = x;
        if (x >= n && y >= m) return _walkBack(trace, n, m, d);
      }
    }
    return null;
  }

  static List<int> _walkBack(List<Int32List> trace, int n, int m, int depth) {
    final steps = <int>[];
    var x = n, y = m;
    for (var d = depth; d > 0; d--) {
      final v = trace[d];
      int at(int k) => v[k + d];
      final k = x - y;
      final previous = k == -d || (k != d && at(k - 1) < at(k + 1))
          ? k + 1
          : k - 1;
      final px = at(previous), py = px - previous;
      while (x > px && y > py) {
        steps.add(_keep);
        x--;
        y--;
      }
      steps.add(x == px ? _add : _remove);
      x = px;
      y = py;
    }
    while (x > 0 && y > 0) {
      steps.add(_keep);
      x--;
      y--;
    }
    return steps.reversed.toList();
  }
}

/// [TextDiff.between] for `compute`, which takes a single argument.
TextDiff diffTexts((String, String) texts) =>
    TextDiff.between(texts.$1, texts.$2);

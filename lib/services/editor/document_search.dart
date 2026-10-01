import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

/// Literal, UTF-16-offset preserving search. Turkish case folding keeps İ/i and I/ı pairs.
class DocumentSearch {
  static String _fold(String text) =>
      text.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
  static final _word = RegExp(r'[\p{L}\p{N}\p{M}_]', unicode: true);

  static List<TextRange> find(
    Document document,
    String query, {
    bool matchCase = false,
    bool wholeWord = false,
  }) {
    if (query.isEmpty) return [];
    final text = document.toPlainText();
    final haystack = matchCase ? text : _fold(text);
    final needle = matchCase ? query : _fold(query);
    final protected = <TextRange>[];
    var offset = 0, lineStart = 0;
    for (final op in document.toDelta().toList()) {
      if (op.data is String) {
        final value = op.data as String;
        for (var i = 0; i < value.length; i++) {
          if (value[i] != '\n') continue;
          if (op.attributes?['korunan-blok'] != null) {
            protected.add(TextRange(start: lineStart, end: offset + i + 1));
          }
          lineStart = offset + i + 1;
        }
      } else {
        protected.add(TextRange(start: offset, end: offset + op.length!));
      }
      offset += op.length!;
    }
    final matches = <TextRange>[];
    var start = 0;
    while (start < haystack.length) {
      final at = haystack.indexOf(needle, start);
      if (at < 0) break;
      final end = at + needle.length;
      // Never replace the document's mandatory final newline or protected objects.
      if (end < text.length &&
          !protected.any((range) => at < range.end && end > range.start) &&
          (!wholeWord ||
              ((at == 0 || !_word.hasMatch(text.substring(at - 1, at))) &&
                  (end == text.length ||
                      !_word.hasMatch(text.substring(end, end + 1)))))) {
        matches.add(TextRange(start: at, end: end));
      }
      start = end;
    }
    return matches;
  }

  /// Compose once so Replace All is a single undo operation. Each replacement
  /// inherits its first character's formatting, leaving surrounding runs intact.
  static void replace(
    QuillController controller,
    List<TextRange> ranges,
    String value,
  ) {
    if (ranges.isEmpty) return;
    final source = controller.document.toDelta();
    final change = Delta();
    var cursor = 0;
    for (final range in ranges) {
      change.retain(range.start - cursor);
      final style = source.slice(range.start, range.start + 1).first.attributes;
      if (value.isNotEmpty) change.insert(value, style);
      change.delete(range.end - range.start);
      cursor = range.end;
    }
    controller.compose(change, controller.selection, ChangeSource.local);
  }
}

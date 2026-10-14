import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A stretch of the document drawn differently from the text around it.
///
/// Two things mark the text now — a word the spelling checker did not know,
/// and a law the document cites — and they are drawn by the same splitter so
/// that a leaf carrying both is cut once rather than twice.
@immutable
class TextMark {
  const TextMark({
    required this.start,
    required this.length,
    required this.style,
    this.recognizer,
  });

  /// Counted in UTF-16 code units from the start of the document, the way a
  /// Dart string counts.
  final int start, length;

  /// Merged onto whatever style the text already had, so a marked stretch
  /// keeps its font and size.
  final TextStyle style;

  /// What to do when it is clicked, for the marks that can be.
  final GestureRecognizer? recognizer;

  int get end => start + length;
}

/// Splits [text] so each mark that reaches into it carries its own style.
///
/// [start] is where [text] begins in the document, since the marks are
/// counted from there. Returns null when nothing touches this stretch, so the
/// caller can go on using the single span it already had — which is the usual
/// case, and worth not allocating for.
///
/// Marks are taken in the order given: where two overlap, the one offered
/// first keeps the ground, and the other is drawn only where it sticks out.
List<InlineSpan>? markedSpans(
  String text,
  int start,
  TextStyle? style,
  List<TextMark> marks,
) {
  if (text.isEmpty || marks.isEmpty) return null;
  final end = start + text.length;
  final here = marks.length < 32
      ? [
          for (final mark in marks)
            if (mark.end > start && mark.start < end) mark,
        ]
      : (_indexes[marks] ??= _MarkIndex(marks)).touching(marks, start, end);
  if (here.isEmpty) return null;

  // Stable: marks offered earlier win a tie, which is how a citation keeps
  // its ground against a misspelling that begins in the same place.
  final ordered = [...here]..sort((a, b) => a.start.compareTo(b.start));

  final spans = <InlineSpan>[];
  var at = 0;
  for (final mark in ordered) {
    final from = (mark.start - start).clamp(0, text.length);
    final to = (mark.end - start).clamp(0, text.length);
    if (to <= at) continue;
    if (from > at) {
      spans.add(TextSpan(text: text.substring(at, from), style: style));
    }
    spans.add(
      TextSpan(
        text: text.substring(from < at ? at : from, to),
        style: (style ?? const TextStyle()).merge(mark.style),
        recognizer: mark.recognizer,
      ),
    );
    at = to;
  }
  if (spans.isEmpty) return null;
  if (at < text.length) {
    spans.add(TextSpan(text: text.substring(at), style: style));
  }
  return spans;
}

/// Each list of marks by where its marks start, made once for the list: a
/// run asks only the marks near it. Every run held against every mark of
/// the document made a long one's keystroke cost the runs times the marks
/// (an English text the spelling checker marks every word of: a quarter of
/// a second a key in 50 pages).
final _indexes = Expando<_MarkIndex>();

class _MarkIndex {
  _MarkIndex(List<TextMark> marks)
    : order = [for (var i = 0; i < marks.length; i++) i]
        ..sort((a, b) {
          final by = marks[a].start.compareTo(marks[b].start);
          return by != 0 ? by : a.compareTo(b);
        }),
      longest = marks.fold(0, (n, m) => m.length > n ? m.length : n);

  /// The marks' places in their list, by where they start.
  final List<int> order;

  /// The longest mark: none starting further back than this reaches here.
  final int longest;

  /// The marks reaching into [start]..[end], in the order they were given.
  List<TextMark> touching(List<TextMark> marks, int start, int end) {
    // The first that may reach here: starting no more than [longest] back.
    var lo = 0, hi = order.length;
    final from = start - longest;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (marks[order[mid]].start < from) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final found = <int>[];
    for (var k = lo; k < order.length; k++) {
      final mark = marks[order[k]];
      if (mark.start >= end) break;
      if (mark.end > start) found.add(order[k]);
    }
    return [for (final i in found..sort()) marks[i]];
  }
}

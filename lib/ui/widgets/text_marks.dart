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
  final here = [
    for (final mark in marks)
      if (mark.end > start && mark.start < end) mark,
  ];
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

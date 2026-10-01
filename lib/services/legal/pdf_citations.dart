import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../annotations/pdf_annotation.dart';
import 'citation.dart';
import 'decision.dart';

/// A law or a decision cited on a rendered page, and where it sits on it.
@immutable
class PdfCitation {
  const PdfCitation({this.citation, this.decision, required this.rects});

  /// One of the two is set and the other is not.
  final Citation? citation;
  final DecisionCitation? decision;

  bool get isDecision => decision != null;

  /// In the page's unrotated space, the way a highlight keeps them, so a
  /// page the reader turns is redrawn without being read again.
  final List<NormRect> rects;
}

/// Finds the laws a previewed document cites.
///
/// The editor works on text and can mark a citation as it draws the line. A
/// preview has no text to mark: UDF and DOCX are rendered to PDF and what is
/// on screen is a picture of a page. The way in is the same one the
/// highlighter uses — the page's own text layer, which gives both the words
/// and a rectangle for every character.
///
/// Pages are read one at a time, as they come into view, because a filing of
/// two hundred pages should not be read through before the first one shows.
class PdfCitations {
  PdfCitations(this._scanner, [this._decisions]);

  final CitationScanner _scanner;

  /// Left out when the reader turned decisions off, which is what stops
  /// them being marked at all.
  final DecisionScanner? _decisions;
  final _byPage = <int, List<PdfCitation>>{};
  final _reading = <int>{};

  /// Pages whose text could not be had yet, and how often that has happened.
  ///
  /// A page the viewer has not finished loading answers with nothing, and
  /// recording that as "this page cites nothing" was what made the marks
  /// come and go: whichever pages happened to be ready got them and the
  /// rest were written off for good. They are tried again as the reader
  /// passes them, a few times, and then let be.
  final _unread = <int, int>{};
  static const _tries = 4;

  /// What was found on this page, or null if it has not been read yet.
  List<PdfCitation>? found(int pageNumber) => _byPage[pageNumber];

  bool get isEmpty => _byPage.values.every((page) => page.isEmpty);

  /// Reads a page, unless it has been read or is being read.
  ///
  /// Answers whether anything changed, so the caller knows to redraw. A page
  /// with no citations is remembered as empty rather than read again.
  Future<bool> read(PdfPage page, {int quarterTurns = 0}) async {
    final number = page.pageNumber;
    if (_byPage.containsKey(number) ||
        _reading.contains(number) ||
        (_unread[number] ?? 0) >= _tries) {
      return false;
    }
    _reading.add(number);
    try {
      final text = await page.loadText();
      if (text == null || text.fullText.isEmpty) {
        _unread[number] = (_unread[number] ?? 0) + 1;
        return false;
      }
      // A turned page reports its width and height swapped while the text
      // layer stays in the original space, so the rectangles are normalised
      // against the unrotated box and turned again only when drawn.
      final swapped = quarterTurns.isOdd;
      _byPage[number] = citationsIn(
        _scanner,
        text.fullText,
        text.charRects,
        swapped ? page.height : page.width,
        swapped ? page.width : page.height,
        decisions: _decisions,
      );
      return true;
    } on Object {
      // A page the viewer has not finished with throws as readily as one
      // that truly has no text — a scan, a photograph — so this is counted
      // rather than settled, and tried again as the reader passes it.
      _unread[number] = (_unread[number] ?? 0) + 1;
      return false;
    } finally {
      _reading.remove(number);
    }
  }

  /// The citations in a page's text, placed where its characters are.
  ///
  /// Kept apart from the page itself so it can be measured without one.
  @visibleForTesting
  static List<PdfCitation> citationsIn(
    CitationScanner scanner,
    String body,
    List<PdfRect> charRects,
    double baseWidth,
    double baseHeight, {
    DecisionScanner? decisions,
  }) {
    if (body.isEmpty) return const [];

    List<NormRect> where(int start, int end) {
      final boxes = <NormRect>[];
      for (var i = start; i < end && i < charRects.length; i++) {
        final r = charRects[i];
        if (r.isEmpty) continue;
        boxes.add(
          NormRect.fromPdf(
            r.left,
            r.top,
            r.right,
            r.bottom,
            baseWidth,
            baseHeight,
          ),
        );
      }
      // A citation that wraps gives one rectangle per line it crosses.
      return PdfHighlight.mergeLines(boxes);
    }

    final out = <PdfCitation>[];
    for (final citation in scanner.scan(body)) {
      final rects = where(citation.start, citation.end);
      if (rects.isNotEmpty) {
        out.add(PdfCitation(citation: citation, rects: rects));
      }
    }
    for (final one in decisions?.scan(body) ?? const <DecisionCitation>[]) {
      // Only what can actually be fetched is marked; a first instance case
      // number is the writer's own file and no bank holds it.
      if (!one.fetchable) continue;
      final rects = where(one.start, one.end);
      if (rects.isNotEmpty) {
        out.add(PdfCitation(decision: one, rects: rects));
      }
    }
    return out;
  }

  /// Forgets everything, for a viewer handed another document.
  void clear() {
    _byPage.clear();
    _reading.clear();
    _unread.clear();
  }
}

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../services/legal/citation.dart';
import '../../services/legal/decision.dart';
import 'text_marks.dart';

/// The colour a citation is drawn in.
///
/// Fixed rather than taken from the theme. These marks sit on the document —
/// white paper, whichever way the application itself is lit — so following
/// the application's colours turned the line nearly black in the dark theme
/// and left it unreadable against the page.
const citationInk = Color(0xFF1155CC);

/// How a law the document cites is drawn: the colour a link is drawn in,
/// underlined, so it reads as something to press rather than as an error.
TextStyle citationStyle(ColorScheme colors) => const TextStyle(
  color: citationInk,
  decoration: TextDecoration.underline,
  decorationColor: Color(0x8C1155CC),
);

/// How a decision the document cites is drawn. The same colour as a law,
/// because they are the same kind of thing to press, but dotted: a decision
/// may or may not be in the bank, and the line should not promise more than
/// the app can keep.
TextStyle decisionStyle(ColorScheme colors) => const TextStyle(
  color: citationInk,
  decoration: TextDecoration.underline,
  decorationStyle: TextDecorationStyle.dotted,
  decorationColor: Color(0x8C1155CC),
);

/// The laws and decisions the document cites, and what to do when one is
/// pressed.
///
/// Scanning is quick and local — no network, no platform channel — but a long
/// document is scanned in full, so the question waits for the typing to stop,
/// the same way the spelling checker does. The marks already drawn stay drawn
/// while it waits.
class CitationMarks extends ChangeNotifier {
  CitationMarks({
    required this.onTap,
    this.onTapDecision,
    CitationScanner? scanner,
    DecisionScanner? decisions,
    this.after = const Duration(milliseconds: 500),
  }) : _scanner = scanner,
       _decisions = decisions {
    if (scanner == null || decisions == null) unawaited(_loadScanner());
  }

  /// Called with the citation and where on screen it was pressed.
  final void Function(Citation citation, Offset at) onTap;

  /// The same for a decision. Left out, decisions are not marked at all,
  /// which is what a reader who turned them off should see.
  final void Function(DecisionCitation citation, Offset at)? onTapDecision;

  /// How long the typing has to stop for.
  final Duration after;

  CitationScanner? _scanner;
  DecisionScanner? _decisions;
  List<Citation> _marks = const [];
  List<DecisionCitation> _cases = const [];
  final _recognizers = <Object, TapGestureRecognizer>{};
  Timer? _waiting;
  String? _scanned;
  bool _disposed = false;

  List<Citation> get marks => _marks;

  bool get isEmpty => _marks.isEmpty;

  /// The citation covering [offset], if one is marked there.
  Citation? at(int offset) {
    for (final mark in _marks) {
      if (offset >= mark.start && offset <= mark.end) return mark;
    }
    return null;
  }

  Future<void> _loadScanner() async {
    try {
      final loaded = _scanner ?? await CitationScanner.load();
      final cases = _decisions ?? await DecisionScanner.load();
      if (_disposed) return;
      _scanner = loaded;
      _decisions = cases;
      // Whatever was asked for before the table arrived is asked again now.
      final waiting = _scanned;
      _scanned = null;
      if (waiting != null) _scan(waiting);
    } on Object {
      // No table, no marks. The editor is not otherwise affected.
    }
  }

  /// Says the document now reads [text]. Scanned once the typing settles.
  void changed(String text) {
    if (_disposed || text == _scanned) return;
    _waiting?.cancel();
    _waiting = Timer(after, () => _scan(text));
  }

  /// Scans now rather than waiting, for a document that has just opened.
  void now(String text) => _scan(text);

  void _scan(String text) {
    if (_disposed) return;
    final scanner = _scanner;
    if (scanner == null) {
      // Remembered so the scan can be repeated once the table has loaded.
      _scanned = text;
      return;
    }
    _scanned = text;
    final found = scanner.scan(text);
    // Only what can actually be fetched is marked: a first instance case
    // number in a filing is the writer's own file, and drawing it as
    // something to press would promise what no bank can give.
    final cases = onTapDecision == null
        ? const <DecisionCitation>[]
        : [
            for (final one
                in _decisions?.scan(text) ?? const <DecisionCitation>[])
              if (one.fetchable) one,
          ];
    if (_same(found, _marks) && _same(cases, _cases)) return;
    _marks = found;
    _cases = cases;
    _dropUnusedRecognizers();
    notifyListeners();
  }

  /// The decisions marked, for a caller that wants to count them.
  List<DecisionCitation> get decisions => _cases;

  /// The marks as the text splitter wants them.
  List<TextMark> textMarks(ColorScheme colors) {
    if (_marks.isEmpty && _cases.isEmpty) return const [];
    final law = citationStyle(colors);
    final case_ = decisionStyle(colors);
    return [
      for (final mark in _marks)
        TextMark(
          start: mark.start,
          length: mark.length,
          style: law,
          recognizer: _recognizerFor(mark),
        ),
      for (final mark in _cases)
        TextMark(
          start: mark.start,
          length: mark.length,
          style: case_,
          recognizer: _recognizerFor(mark),
        ),
    ];
  }

  /// One recognizer per citation, kept rather than made afresh.
  ///
  /// A leaf is rebuilt on every paint, and a recognizer made during a build
  /// is never disposed of, so making one each time would leak a listener per
  /// frame for every citation on screen.
  TapGestureRecognizer _recognizerFor(Object cited) =>
      _recognizers.putIfAbsent(cited, () {
        final recognizer = TapGestureRecognizer();
        if (cited is Citation) {
          recognizer.onTapUp = (d) => onTap(cited, d.globalPosition);
        } else if (cited is DecisionCitation) {
          recognizer.onTapUp = (d) =>
              onTapDecision?.call(cited, d.globalPosition);
        }
        return recognizer;
      });

  void _dropUnusedRecognizers() {
    final live = _marks.toSet();
    _recognizers.removeWhere((citation, recognizer) {
      if (live.contains(citation)) return false;
      recognizer.dispose();
      return true;
    });
  }

  static bool _same<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void clear() {
    _waiting?.cancel();
    _scanned = null;
    if (_marks.isEmpty && _cases.isEmpty) return;
    _marks = const [];
    _cases = const [];
    _dropUnusedRecognizers();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _waiting?.cancel();
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }
}

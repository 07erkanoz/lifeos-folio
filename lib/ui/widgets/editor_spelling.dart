import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/editor/spell_check.dart';
import 'text_marks.dart';

/// What the checker last said about the document, and when to ask it again.
///
/// Asking on every keystroke would send the whole document across a channel
/// several times a second, so the question waits for the typing to stop. The
/// marks that are already drawn stay drawn while it waits: a word stops being
/// underlined a moment after it is finished, which is how every other editor
/// behaves, rather than flickering under the cursor as it is typed.
class SpellingMarks extends ChangeNotifier {
  SpellingMarks({
    SpellCheck? checker,
    this.after = const Duration(milliseconds: 700),
  }) : _checker = checker ?? SpellCheck.instance;

  final SpellCheck _checker;

  /// How long the typing has to stop for.
  final Duration after;

  List<Misspelling> _marks = const [];
  Timer? _waiting;
  String? _asked;
  String? _pending;
  bool _asking = false;
  bool _disposed = false;

  /// Everything the checker did not recognise, in document offsets.
  List<Misspelling> get marks => _marks;

  bool get isEmpty => _marks.isEmpty;

  /// The word covering [offset], if one is underlined there.
  Misspelling? at(int offset) {
    for (final mark in _marks) {
      if (offset >= mark.start && offset <= mark.end) return mark;
    }
    return null;
  }

  /// Says the document now reads [text]. Checked once the typing settles.
  void changed(String text) {
    if (_disposed || text == _asked) return;
    _waiting?.cancel();
    _waiting = Timer(after, () => _ask(text));
  }

  /// Checks now rather than waiting, for a document that has just opened.
  Future<void> now(String text) => _ask(text);

  Future<void> _ask(String text) async {
    if (_disposed) return;
    // An answer already on its way is for text the document has moved past.
    // The new text is held rather than dropped: forgetting it would leave
    // the marks sitting at offsets the document no longer has, and, if the
    // typing has stopped, leave them there for good.
    if (_asking) {
      _pending = text;
      return;
    }
    _asking = true;
    try {
      var next = text;
      for (;;) {
        final found = await _checker.check(next);
        if (_disposed) return;
        _asked = next;
        if (!_same(found, _marks)) {
          _marks = found;
          notifyListeners();
        }
        final waiting = _pending;
        _pending = null;
        if (waiting == null || waiting == _asked) break;
        next = waiting;
      }
    } finally {
      _asking = false;
    }
  }

  /// Nothing is repainted for an answer that says what the last one said.
  static bool _same(List<Misspelling> a, List<Misspelling> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void clear() {
    _waiting?.cancel();
    _asked = null;
    _pending = null;
    if (_marks.isEmpty) return;
    _marks = const [];
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _waiting?.cancel();
    _pending = null;
    super.dispose();
  }
}

/// How a word the checker did not know is drawn.
const spellingUnderline = TextStyle(
  decoration: TextDecoration.underline,
  decorationStyle: TextDecorationStyle.wavy,
  decorationColor: Color(0xFFD93A3A),
  decorationThickness: 1.1,
);

/// Splits [text] so the stretches the checker marked carry the underline.
///
/// [start] is where [text] begins in the document, since the marks are
/// counted from there. Returns null when nothing in this stretch is marked,
/// so the caller can go on using the single span it already had.
List<InlineSpan>? spellingSpans(
  String text,
  int start,
  TextStyle? style,
  List<Misspelling> marks,
) => markedSpans(text, start, style, [
  for (final mark in marks)
    TextMark(start: mark.start, length: mark.length, style: spellingUnderline),
]);

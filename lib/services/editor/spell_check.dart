import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A stretch of text the checker did not recognise.
@immutable
class Misspelling {
  const Misspelling({
    required this.start,
    required this.length,
    this.repeated = false,
  });

  /// Counted in UTF-16 code units, the way a Dart string counts, so these
  /// index the very string that was handed over.
  final int start, length;

  /// A word typed twice over rather than a word spelled wrongly.
  final bool repeated;

  int get end => start + length;

  @override
  bool operator ==(Object other) =>
      other is Misspelling &&
      other.start == start &&
      other.length == length &&
      other.repeated == repeated;

  @override
  int get hashCode => Object.hash(start, length, repeated);

  @override
  String toString() => 'Misspelling($start,$length)';
}

/// Turkish spelling, asked of whatever on this machine already knows Turkish.
///
/// A word list of our own would be no use: Turkish builds words by adding to
/// them, so mahkemesine, dilekçesiyle and davalılardan are all ordinary words
/// and no list holds every form. Windows has carried a real Turkish checker
/// since 8 and suggests corrections as well as finding faults, and the reader
/// has probably already taught it the names they use. Asking it is both
/// better and lighter than carrying a dictionary.
///
/// Anywhere that has no such checker, this simply finds nothing, and the
/// editor underlines nothing.
class SpellCheck {
  SpellCheck({@visibleForTesting MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('folio/spellcheck');

  final MethodChannel _channel;

  /// The one the app uses. Replaced in tests.
  static SpellCheck instance = SpellCheck();

  /// Written as Windows names it.
  static const language = 'tr-TR';
  static const _maxCheckChunk = 20000;

  bool? _available;

  /// Whether this machine can check Turkish at all.
  ///
  /// Asked once and remembered, including the no: where the bridge is not
  /// built the channel throws on the first call and is never called again.
  Future<bool> get available async {
    if (_available != null) return _available!;
    try {
      final answer = await _channel.invokeMethod<bool>('available', {
        'language': language,
      });
      return _available = answer ?? false;
    } on PlatformException {
      return _available = false;
    } on MissingPluginException {
      return _available = false;
    }
  }

  /// What is wrong with [text], as offsets into it.
  Future<List<Misspelling>> check(String text) async {
    if (text.trim().isEmpty || !await available) return const [];
    try {
      final out = <Misspelling>[];
      for (final chunk in _chunks(text)) {
        final found = await _channel.invokeMethod<List<Object?>>('check', {
          'language': language,
          'text': chunk.text,
        });
        for (final entry in found ?? const []) {
          if (entry is! Map) continue;
          out.add(
            Misspelling(
              start: chunk.start + (entry['start'] as num).toInt(),
              length: (entry['length'] as num).toInt(),
              repeated: entry['repeated'] == true,
            ),
          );
        }
        // Desktop spell-check bridges run on their platform thread. Yielding
        // between bounded chunks lets window messages and frames through
        // instead of making a long imported PDF look as if the app froze.
        if (chunk.start + chunk.text.length < text.length) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      return out;
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  static Iterable<({int start, String text})> _chunks(String text) sync* {
    var start = 0;
    while (start < text.length) {
      var end = (start + _maxCheckChunk).clamp(0, text.length);
      if (end < text.length) {
        // Keep a word (and a UTF-16 surrogate pair) in one request so native
        // offsets still point into precisely the string the editor displays.
        var boundary = end;
        final floor = end - 512 > start ? end - 512 : start;
        while (boundary > floor &&
            !_isWhitespace(text.codeUnitAt(boundary - 1))) {
          boundary--;
        }
        if (boundary > floor) end = boundary;
        final last = text.codeUnitAt(end - 1);
        if (last >= 0xD800 && last <= 0xDBFF) end--;
      }
      if (end <= start) end = (start + _maxCheckChunk).clamp(0, text.length);
      yield (start: start, text: text.substring(start, end));
      start = end;
    }
  }

  static bool _isWhitespace(int unit) =>
      unit == 0x20 || unit == 0xA0 || (unit >= 0x09 && unit <= 0x0D);

  /// What to write instead, best first.
  Future<List<String>> suggest(String word) async {
    if (word.isEmpty || !await available) return const [];
    try {
      final given = await _channel.invokeMethod<List<Object?>>('suggest', {
        'language': language,
        'word': word,
      });
      return [
        for (final value in given ?? const [])
          if (value is String && value.isNotEmpty) value,
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Teaches the machine a word, in the dictionary every program here reads.
  Future<void> learn(String word) async {
    if (word.isEmpty || !await available) return;
    try {
      await _channel.invokeMethod<void>('add', {
        'language': language,
        'word': word,
      });
    } on PlatformException {
      // Nothing to do: the word stays underlined.
    } on MissingPluginException {
      // As above.
    }
  }
}

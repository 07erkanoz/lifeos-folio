import '../lawyer_profile.dart';
import '../snippets.dart';
import 'phrase_memory.dart';
import 'phrases.dart';

/// Where a suggestion comes from, in the order they are offered.
enum SuggestionSource { snippet, profile, builtIn, learned }

/// One line of the list under the caret.
class Suggestion {
  const Suggestion({
    required this.text,
    required this.source,
    required this.typed,
    this.label,
    this.snippet,
    this.learned,
  });

  /// What replaces the typed words when it is taken.
  final String text;
  final SuggestionSource source;

  /// How many characters before the caret it replaces.
  final int typed;

  /// Shown beside it: "Kalıp", the profile field, "12 belgede".
  final String? label;

  /// A snippet is expanded, not typed in.
  final Snippet? snippet;
  final LearnedPhrase? learned;
}

/// Finds what could complete the words just typed.
///
/// The last one to six words of the clause are compared, folded, with the
/// beginning of every phrase; the longest match comes first, and within one
/// length the sources keep their order: snippets, the lawyer's profile, the
/// built-in phrases, then what was learned, most used first.
class SuggestionEngine {
  SuggestionEngine({this.snippets, this.profile, this.memory});

  final SnippetStore? snippets;
  final LawyerProfile? profile;
  final PhraseMemory? memory;

  static const limit = 6;

  List<Suggestion> suggest(String before) {
    final tail = typedTail(before);
    if (tail == null) return const [];
    final words = RegExp(r'\S+').allMatches(tail).toList();
    final out = <Suggestion>[];
    final seen = <String>{};

    void offer(Suggestion s) {
      if (out.length >= limit) return;
      if (seen.add(foldPhrase(s.text))) out.add(s);
    }

    // Longest typed run first: "gereğini say" before "say".
    for (var from = 0; from < words.length && out.length < limit; from++) {
      final typed = tail.substring(words[from].start);
      final key = foldPhrase(typed);
      final length = typed.length;
      // A single word needs two letters; the snippet keyword needs its own
      // whole word, so it is only looked at for the last word alone.
      if (from == words.length - 1) {
        final snippet = snippets?.byKeyword(typed);
        if (snippet != null) {
          offer(
            Suggestion(
              text: snippet.name,
              source: SuggestionSource.snippet,
              typed: length,
              label: 'Kalıp',
              snippet: snippet,
            ),
          );
        }
      }
      for (final (label, value)
          in profile?.entries() ?? const <(String, String)>[]) {
        if (_completes(value, key)) {
          offer(
            Suggestion(
              text: value,
              source: SuggestionSource.profile,
              typed: length,
              label: label,
            ),
          );
        }
      }
      for (final phrase in builtInPhrases) {
        if (_completes(phrase, key)) {
          offer(
            Suggestion(
              text: _cased(phrase, typed),
              source: SuggestionSource.builtIn,
              typed: length,
            ),
          );
        }
      }
      for (final phrase in memory?.phrases ?? const <LearnedPhrase>[]) {
        if (phrase.offered &&
            phrase.key.startsWith(key) &&
            phrase.key.length > key.length) {
          offer(
            Suggestion(
              text: _cased(phrase.text, typed),
              source: SuggestionSource.learned,
              typed: length,
              label: '${phrase.documents} belgede',
              learned: phrase,
            ),
          );
        }
      }
    }
    return out;
  }

  static bool _completes(String phrase, String key) {
    final folded = foldPhrase(phrase);
    return folded.startsWith(key) && folded.length > key.length;
  }

  /// A heading is kept in capitals; otherwise the phrase starts the way the
  /// reader started it, so "davanın" typed mid-sentence stays lower case
  /// and "Davanın" at the start of one stays capital.
  static String _cased(String phrase, String typed) {
    if (phrase == phrase.toUpperCase() || _isName(phrase)) return phrase;
    final first = typed.isEmpty ? '' : typed[0];
    if (first.isEmpty || phrase.isEmpty) return phrase;
    final upper = first != first.toLowerCase() || first == 'İ';
    final head = phrase[0];
    final cased = upper ? _upper(head) : _lower(head);
    return cased + phrase.substring(1);
  }

  /// A name — "İcra ve İflas Kanunu", "Asliye Hukuk Mahkemesine" — is
  /// written the one way whatever was typed: every word but the short
  /// joining ones starts with a capital.
  static bool _isName(String phrase) {
    final words = phrase.split(' ').where((w) => w.length > 3).toList();
    return words.length >= 2 &&
        words.every((w) => w[0] != w[0].toLowerCase() || w[0] == 'İ');
  }

  static String _upper(String c) => switch (c) {
    'i' => 'İ',
    'ı' => 'I',
    _ => c.toUpperCase(),
  };

  static String _lower(String c) => switch (c) {
    'I' => 'ı',
    'İ' => 'i',
    _ => c.toLowerCase(),
  };
}

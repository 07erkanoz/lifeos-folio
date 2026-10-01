import 'package:flutter/foundation.dart';

import 'legal_terms.dart' show lowerTr;
import 'turkish_stem.dart';

/// How well one decision answers what was asked, and the piece of it to show.
@immutable
class Relevance {
  const Relevance(this.score, this.snippet, this.matched);

  final double score;

  /// The stretch of the decision where the search words sit thickest, so a
  /// reader can tell from the list whether to open it.
  final String snippet;

  /// Which of the asked-for words were actually found.
  final List<String> matched;

  static const none = Relevance(0, '', []);
}

/// Ranking search results without asking a model anything.
///
/// The case bank returns what matched; it does not say which of a hundred
/// thousand decisions answers the question. That ordering is done here, from
/// the text itself, by counting: how often each word appears, how many of
/// them appear at all, whether they stand next to each other, and whether
/// the reader asked for something to be left out.
///
/// It is deliberately arithmetic rather than learned. A lawyer has to be
/// able to see why one decision came above another, and a score built from
/// counts can be explained; a score from a model cannot.
class Relevances {
  const Relevances._();

  /// Words too common to search for, and question words that are not part
  /// of the question.
  ///
  /// Leaving the question words in was a real failure: "yargıtay ne diyor"
  /// searched for "ne" and "diyor", which every decision contains, and
  /// drowned the two words that mattered.
  static const _stopWords = {
    've',
    'ile',
    'veya',
    'için',
    'bir',
    'bu',
    'şu',
    'olan',
    'olarak',
    'dair',
    'göre',
    'nedeniyle',
    'hakkında',
    'ne',
    'diyor',
    'nedir',
    'mı',
    'mi',
    'mu',
    'mü',
  };

  /// One spelling for the same words, whichever side they came from.
  ///
  /// The last of these is not tidiness: decisions write "el atma" apart and
  /// readers write "elatma" together, so without it the commonest search in
  /// an expropriation file matches nothing at all. Both the query and the
  /// text pass through here, so the two always agree.
  static String normalize(String value) =>
      lowerTr(value)
          .replaceAll(RegExp(r'[^a-z0-9çğıöşü\s]'), ' ')
          .replaceAll('elatma', 'el atma')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  /// The words worth searching for in what was typed.
  static List<String> termsIn(String query) =>
      normalize(query.replaceAll(RegExp(r'-\S+'), ''))
          .split(' ')
          .where((term) => term.length > 1 && !_stopWords.contains(term))
          .toSet()
          .toList();

  /// The words the reader asked to be left out, written with a leading minus.
  static List<String> excludedIn(String query) =>
      RegExp(r'-(\S+)')
          .allMatches(query)
          .map((m) => normalize(m.group(1)!))
          .where((term) => term.isNotEmpty)
          .toList();

  /// Where the matches lie thickest, for the snippet.
  ///
  /// The first match of the busiest six-hundred-character window, so what
  /// is shown has the words near its start rather than buried in it.
  static int _busiest(List<int> positions) {
    if (positions.isEmpty) return 0;
    final sorted = [...positions]..sort();
    var bestStart = sorted.first;
    var best = 0;
    for (var i = 0; i < sorted.length; i++) {
      final limit = sorted[i] + 600;
      var j = i;
      var count = 0;
      while (j < sorted.length && sorted[j] <= limit) {
        count++;
        j++;
      }
      if (count > best) {
        best = count;
        bestStart = sorted[i];
      }
    }
    return bestStart;
  }

  /// What [text] is worth against [query].
  static Relevance score(String query, String text) {
    // Lower case that keeps its length, so a position found here is a
    // position in the original and the snippet does not slide.
    final lower = lowerTr(text);
    final compact = normalize(text);
    final wanted = termsIn(query);
    final unwanted = excludedIn(query);
    if (wanted.isEmpty || compact.isEmpty) return Relevance.none;

    // A very long decision should not win on sheer bulk.
    final lengthNorm = 1.0 / (1.0 + (compact.length / 60000.0));

    var score = 0.0;
    final matched = <String>[];
    final firstOf = <int>[];
    final everyMatch = <int>[];

    // Every word of the text indexed by its stem, so a search term matches
    // the inflections of itself: "iş kazaları" finds "iş kazası".
    final byStem = <String, List<int>>{};
    for (final m in RegExp(r'[a-z0-9çğıöşü]+').allMatches(lower)) {
      (byStem[TurkishStem.of(m.group(0)!)] ??= <int>[]).add(m.start);
    }

    for (final term in wanted) {
      final at = byStem[TurkishStem.of(term)] ?? const <int>[];
      if (at.isEmpty) continue;
      matched.add(term);
      final count = at.length.toDouble();
      // Saturating: the twentieth occurrence of a word says little more
      // than the third did.
      final saturated = count / (count + 2.5);
      score += 24 * saturated * (0.6 + 0.4 * lengthNorm);
      firstOf.add(at.first);
      everyMatch.addAll(at.take(40));
    }
    if (matched.isEmpty) return Relevance.none;

    // How much of what was asked for is here at all. This counts for more
    // than how often any one word repeats.
    score += (matched.length / wanted.length) * 45;
    final all = matched.length == wanted.length;
    if (all) score += 16;

    // The words standing together, in that order, is a strong signal.
    if (wanted.length >= 2 && compact.contains(wanted.join(' '))) score += 40;

    // Failing that, standing near each other at least means one context
    // rather than two unrelated mentions in a long judgment.
    if (all && firstOf.length >= 2) {
      firstOf.sort();
      final span = firstOf.last - firstOf.first;
      if (span <= 300) {
        score += 24;
      } else if (span <= 1200) {
        score += 10;
      }
    }

    for (final term in unwanted) {
      if (compact.contains(term)) score -= 45;
    }

    final centre = _busiest(everyMatch);
    final from = (centre - 200).clamp(0, text.length);
    final to = (centre + 440).clamp(0, text.length);
    return Relevance(
      score.clamp(0, 150),
      text.substring(from, to).replaceAll(RegExp(r'\s+'), ' ').trim(),
      matched,
    );
  }

  /// How high the bench sits: full assembly 4, chamber 3, appeal 2, first
  /// instance 1.
  static int authorityOf(String chamber, String courtType) {
    final name = normalize(chamber);
    if (name.contains('genel kurul') ||
        name.contains('birleştir') ||
        name.contains('büyük')) {
      return 4;
    }
    return switch (courtType) {
      'ISTINAFHUKUK' => 2,
      'YERELHUKUK' => 1,
      _ => 3,
    };
  }

  /// What the bench is worth in the ranking.
  ///
  /// Modest on purpose: it separates decisions that are otherwise equally
  /// on the point, and never lifts a distant one over a close one.
  static double authorityBonus(int rank) => (rank - 1) * 4.0;

  /// What a word being rare in this set of results is worth.
  ///
  /// A term that nearly every result contains says nothing about which to
  /// read; one that only a few contain is the reason those few are here.
  /// Searching "kamulaştırma faiz" over a pool that is all about
  /// expropriation, it is "faiz" that should decide the order.
  ///
  /// Below three results there is no pool to speak of, so nothing is added.
  static List<double> rarityBonuses(List<List<String>> matchedPerResult) {
    final n = matchedPerResult.length;
    if (n < 3) return List.filled(n, 0);
    final inHowMany = <String, int>{};
    for (final terms in matchedPerResult) {
      for (final term in terms.toSet()) {
        inHowMany[term] = (inHowMany[term] ?? 0) + 1;
      }
    }
    return [
      for (final terms in matchedPerResult)
        terms
            .toSet()
            .fold<double>(
              0,
              (sum, term) => sum + 16.0 * ((n - (inHowMany[term] ?? n)) / n),
            )
            .clamp(0.0, 64.0),
    ];
  }

  /// A mark of what a decision says, for spotting the same reasoning twice.
  ///
  /// Taken from the body rather than the opening. A judgment begins with
  /// what is particular to it — the parties, the case numbers, the dates —
  /// and only then gives the reasoning. Marking the opening therefore told
  /// every decision apart, including the ones that were word for word the
  /// same from there on.
  ///
  /// That is not a rare case. A chamber deciding twenty claims against one
  /// employer on the same day writes one set of reasons twenty times, under
  /// twenty case numbers. Measured against the bank, a search for kıdem
  /// tazminatı returned six decisions of which five were that: one page of
  /// results carrying one holding.
  ///
  /// So they are marked alike and all but the best placed is put last. They
  /// are still separate decisions and are not hidden — but a reader looking
  /// for what the courts have held should not be shown it five times before
  /// seeing anything else.
  static String signatureOf(String text) {
    final flat = normalize(text);
    if (flat.length < 40) return '';
    // Taken from the end. What is particular to a case — its numbers, its
    // court, its dates — is written at the top; the reasoning runs to the
    // last line. Measured on two of these decisions: 1518 characters each,
    // of which the last 1376 were identical and only the opening differed.
    // Marking from the front told them apart; marking from the back does
    // not. Below a thousand characters there is not enough reasoning to
    // judge by, so a short decision is marked whole.
    const tail = 1200;
    final from = flat.length > tail + 200 ? flat.length - tail : 0;
    final body = flat.substring(from);
    // FNV-1a. Only ever compared with marks made in the same run, so it
    // needs to be steady rather than portable.
    var hash = 0x811c9dc5;
    for (var i = 0; i < body.length; i++) {
      hash ^= body.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16);
  }
}

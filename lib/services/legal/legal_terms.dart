import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A term of art, and what it means.
@immutable
class LegalTerm {
  const LegalTerm({
    required this.term,
    required this.meaning,
    this.clipped = false,
  });

  final String term;
  final String meaning;

  /// The source cuts a long entry off at a fixed length. Said plainly rather
  /// than shown as though the sentence had ended.
  final bool clipped;
}

/// What one law means by a term, inside that law.
///
/// A statute's "Tanımlar" article does not define a word, it scopes one:
/// "in this Act, Bakanlık means …". Eight laws say eight different things
/// by it, and every one of them is right where it stands. The law is
/// therefore never shown without its definition.
@immutable
class StatuteMeaning {
  const StatuteMeaning({required this.meaning, required this.law});

  final String meaning;

  /// "6698 s. Kişisel Verilerin Korunması Kanunu".
  final String law;
}

/// Everything the app can say about one word.
@immutable
class TermMatch {
  const TermMatch({
    required this.term,
    this.dictionary,
    this.statutes = const [],
  });

  /// As it is written in whichever source names it.
  final String term;

  /// What the dictionary says it means, where the dictionary has it.
  final LegalTerm? dictionary;

  /// What each law means by it. Often empty; occasionally longer than the
  /// dictionary entry and more to the point for the document in hand.
  final List<StatuteMeaning> statutes;

  bool get isEmpty => dictionary == null && statutes.isEmpty;
}

/// Turkish lower case, which is not the one Dart does by default.
///
/// Dart turns İ into i followed by a combining dot, as Unicode's default
/// casing says; Turkish wants a plain i, and I to become the undotted ı.
/// Getting this wrong loses every term with an İ in it, which here is a
/// hundred and eighty of them, İstinaf among them.
String lowerTr(String value) =>
    value.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

/// The legal terms the app ships, looked up by the word a reader points at.
///
/// Turkish builds words by adding to them, so the word in the document is
/// rarely the word in the dictionary: şüphelinin, müddeabihi, tefhiminden.
/// A term is therefore found by matching the beginning of the word and
/// keeping the longest term that fits, and the softening a final consonant
/// undergoes before a suffix — sanık becoming sanığın — is allowed for.
class LegalTerms {
  LegalTerms(
    List<LegalTerm> terms, {
    Map<String, List<StatuteMeaning>>? statutes,
  }) : _terms = terms {
    for (final term in terms) {
      for (final key in _keysFor(term.term)) {
        // The first term to claim a key keeps it; the file is in the source's
        // own order, which puts the plain form before the compounds.
        _byKey.putIfAbsent(key, () => term);
      }
    }
    if (statutes == null) return;
    for (final entry in statutes.entries) {
      for (final key in _keysFor(entry.key)) {
        _statutesByKey.putIfAbsent(key, () => entry.value);
      }
      _written.putIfAbsent(lowerTr(entry.key).trim(), () => entry.key);
    }
  }

  final List<LegalTerm> _terms;
  final _byKey = <String, LegalTerm>{};
  final _statutesByKey = <String, List<StatuteMeaning>>{};

  /// The spelling a statutory term is written with, for a word the
  /// dictionary does not carry and so cannot name.
  final _written = <String, String>{};

  int get length => _terms.length;

  int get statuteLength => _written.length;

  static Future<LegalTerms> load({
    String asset = 'assets/sozluk/terms.json',
    String? statutes = 'assets/mevzuat/terms.json',
  }) async => LegalTerms.parse(
    await rootBundle.loadString(asset),
    statutes: statutes == null ? null : await rootBundle.loadString(statutes),
  );

  @visibleForTesting
  static LegalTerms parse(String raw, {String? statutes}) {
    final json = jsonDecode(raw) as Map<String, Object?>;
    return LegalTerms([
      for (final entry in json['terimler'] as List)
        if (entry is Map)
          LegalTerm(
            term: entry['t'] as String,
            meaning: entry['a'] as String,
            clipped: entry['k'] == 1,
          ),
    ], statutes: statutes == null ? null : _statutesIn(statutes));
  }

  static Map<String, List<StatuteMeaning>> _statutesIn(String raw) {
    final json = jsonDecode(raw) as Map<String, Object?>;
    return {
      for (final entry in json['terimler'] as List)
        if (entry is Map)
          entry['t'] as String: [
            for (final one in entry['k'] as List)
              if (one is Map)
                StatuteMeaning(
                  meaning: one['a'] as String,
                  law: one['y'] as String,
                ),
          ],
    };
  }

  /// A final k, p, t or ç softens before a suffix that begins with a vowel:
  /// sanık becomes sanığın, kitap kitabı. Both forms are indexed so the
  /// written word can be matched against either.
  static const _softens = {'k': 'ğ', 'p': 'b', 't': 'd', 'ç': 'c'};

  static List<String> _keysFor(String term) {
    final key = lowerTr(term).trim();
    if (key.isEmpty) return const [];
    final soft = _softens[key[key.length - 1]];
    return soft == null
        ? [key]
        : [key, key.substring(0, key.length - 1) + soft];
  }

  /// How far back a word may be cut looking for the term inside it.
  ///
  /// Turkish chains its suffixes, but a chain long enough to matter is still
  /// short: tefhim+inden, mahkeme+sinden. Letting the cut go further turns
  /// every compound into a false match — bilgisayarcılık would be answered
  /// with what a statute means by bilgi.
  static const _longestSuffix = 6;

  static int _shortestStem(String key) =>
      math.max(4, key.length - _longestSuffix);

  /// The term [word] is a form of, or null when it is not one.
  ///
  /// The word is matched from its beginning so that a suffix does not hide
  /// the term, but a stem shorter than four letters is not matched that way:
  /// at that length almost any word would find something.
  LegalTerm? forWord(String word) {
    final key = lowerTr(word).trim();
    if (key.length < 2) return null;
    final exact = _byKey[key];
    if (exact != null) return exact;
    for (var end = key.length - 1; end >= _shortestStem(key); end--) {
      final found = _byKey[key.substring(0, end)];
      if (found != null) return found;
    }
    return null;
  }

  /// What each law means by [word], if any of them define it.
  List<StatuteMeaning> statutesFor(String word) {
    final key = lowerTr(word).trim();
    if (key.length < 2) return const [];
    final exact = _statutesByKey[key];
    if (exact != null) return exact;
    for (var end = key.length - 1; end >= _shortestStem(key); end--) {
      final found = _statutesByKey[key.substring(0, end)];
      if (found != null) return found;
    }
    return const [];
  }

  /// Everything known about [words], from either source or both.
  ///
  /// The two are looked up separately because they cover different ground:
  /// the dictionary has the old words of the profession, müstenif and vedia,
  /// and the statutes have the ones the legislature made up, açık rıza and
  /// veri sorumlusu. A word may be in either, or in both and disagreeing.
  TermMatch? matchPhrase(List<String> words) {
    for (var take = words.length; take >= 1; take--) {
      final phrase = words.take(take).join(' ');
      final entry = forWord(phrase);
      final statutes = statutesFor(phrase);
      if (entry == null && statutes.isEmpty) continue;
      return TermMatch(
        term: entry?.term ?? _writtenFormOf(phrase) ?? phrase,
        dictionary: entry,
        statutes: statutes,
      );
    }
    return null;
  }

  String? _writtenFormOf(String phrase) {
    final key = lowerTr(phrase).trim();
    final exact = _written[key];
    if (exact != null) return exact;
    for (var end = key.length - 1; end >= _shortestStem(key); end--) {
      final found = _written[key.substring(0, end)];
      if (found != null) return found;
    }
    return null;
  }

  /// The term a phrase names, preferring the longest that fits.
  ///
  /// Two thirds of these entries are more than one word — "aciz vesikası",
  /// "kanuni temsilci" — so the words after the one pointed at are offered
  /// too, and the longest match wins.
  LegalTerm? forPhrase(List<String> words) {
    for (var take = words.length; take >= 1; take--) {
      final found = forWord(words.take(take).join(' '));
      if (found != null) return found;
    }
    return null;
  }
}

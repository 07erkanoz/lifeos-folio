import 'package:flutter/foundation.dart';

import 'legal_terms.dart' show lowerTr;

/// A piece of a decision, word for word, and where it stands in it.
///
/// Everything the anatomy of a decision reports is one of these: never a
/// paraphrase, always the court's own words, and always with the place
/// they were taken from so the reader can be taken there and check.
@immutable
class Quote {
  const Quote(this.text, this.start);

  /// Exactly `decision.substring(start, end)`.
  final String text;

  /// Counted in UTF-16 code units, the way a Dart string counts.
  final int start;

  int get end => start + text.length;

  /// The quote taken out of [source] between [from] and [to], with the
  /// space at either end trimmed off and the place moved to match.
  static Quote? within(String source, int from, int to) {
    var a = from.clamp(0, source.length);
    var b = to.clamp(a, source.length);
    while (a < b && _isSpace(source.codeUnitAt(a))) {
      a++;
    }
    while (b > a && _isSpace(source.codeUnitAt(b - 1))) {
      b--;
    }
    if (a >= b) return null;
    return Quote(source.substring(a, b), a);
  }

  static bool _isSpace(int unit) =>
      unit == 0x20 || unit == 0x0a || unit == 0x0d || unit == 0x09;

  @override
  bool operator ==(Object other) =>
      other is Quote && other.text == text && other.start == start;

  @override
  int get hashCode => Object.hash(text, start);

  @override
  String toString() => 'Quote(@$start "$text")';
}

/// Cuts a decision into sentences without cutting where a decision does
/// not end one.
///
/// A decision is full of full stops that are not the end of anything. The
/// bank anonymises names with an ellipsis — "davacı ... vekili" — and a
/// splitter that took that for a stop left half sentences behind, which is
/// what made the earlier attempt's "principles" end mid-word. Then there
/// are the ordinals ("3. Hukuk Dairesi", "370. maddesi"), the dates
/// ("12.03.2024"), the sums ("1.250,00 TL"), and the marks of a citation
/// ("E.", "K.", "T.", "m.", "vd.").
///
/// A stop is taken as an end only where a sentence can begin after it: a
/// capital letter, or the end of the line. The bank's text has one
/// paragraph to a line, so a sentence never runs on past one.
class DecisionSentences {
  const DecisionSentences._();

  /// Short forms that are followed by a full stop and then, often enough,
  /// by a capital: "Yargıtay 3. HD, E. 2019/1 K. 2020/2", "Av. Ali".
  static const _abbreviations = {
    'm',
    'md',
    'mad',
    'f',
    'fık',
    'b',
    'bent',
    'vd',
    'vb',
    'vs',
    'bkz',
    'krş',
    'karş',
    'av',
    'dr',
    'prof',
    'doç',
    'yrd',
    'no',
    'nolu',
    's',
    'sh',
    'sy',
    'sk',
    'cad',
    'mah',
    'sok',
    'apt',
    'şti',
    'ltd',
    'a.ş',
    'aş',
    'tic',
    'san',
    'koll',
    'or',
    'gn',
    'yön',
    'müd',
    'hd',
    'cd',
    'hgk',
    'cgk',
    'ibk',
    'yibk',
    'dn',
    'st',
    'tl',
    'tc',
    't.c',
  };

  static bool _isUpper(String char) =>
      char != lowerTr(char) && RegExp(r'[A-ZÇĞİÖŞÜ]').hasMatch(char);

  static bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

  /// The sentences of [text] between [from] and [to].
  static List<Quote> of(String text, [int from = 0, int? to]) {
    final end = (to ?? text.length).clamp(0, text.length);
    final out = <Quote>[];
    var lineStart = from.clamp(0, end);
    while (lineStart < end) {
      var lineEnd = text.indexOf('\n', lineStart);
      if (lineEnd < 0 || lineEnd > end) lineEnd = end;
      _line(text, lineStart, lineEnd, out);
      lineStart = lineEnd + 1;
    }
    return out;
  }

  static void _line(String text, int from, int to, List<Quote> out) {
    var start = from;
    for (var i = from; i < to; i++) {
      final char = text[i];
      if (char != '.' && char != '!' && char != '?') continue;
      if (!_endsHere(text, i, from, to)) continue;
      // Take any closing quotation mark or bracket with the sentence.
      var close = i + 1;
      while (close < to && '"”’\')'.contains(text[close])) {
        close++;
      }
      final found = Quote.within(text, start, close);
      if (found != null) out.add(found);
      start = close;
      i = close - 1;
    }
    final rest = Quote.within(text, start, to);
    if (rest != null) out.add(rest);
  }

  /// Whether the stop at [i] ends a sentence.
  static bool _endsHere(String text, int i, int lineFrom, int lineTo) {
    final char = text[i];
    // An ellipsis is the bank's anonymisation, or a quotation cut short;
    // either way the sentence goes on.
    if (char == '.') {
      if (i + 1 < lineTo && (text[i + 1] == '.' || text[i + 1] == '…')) {
        return false;
      }
      if (i > lineFrom && (text[i - 1] == '.' || text[i - 1] == '…')) {
        return false;
      }
    }

    // What follows: a sentence begins with a capital, a quotation mark or
    // a bracket before one, or the line simply ends.
    var next = i + 1;
    if (next < lineTo &&
        !RegExp(r'\s').hasMatch(text[next]) &&
        !'"”’\')'.contains(text[next])) {
      // "12.03.2024", "1.250,00", "A.Ş." go on. But the bank's text often
      // runs two sentences together with no space between, "…istemine
      // ilişkindir.Mahkemece yapılan…": a word in small letters, the stop,
      // and a capitalised word is an end.
      // So is a numbered item run on the same way, "…istinaf
      // edilmiştir.1-Çözülmesi gereken…".
      final rest = text.substring(next, lineTo);
      final joined =
          char == '.' &&
          i > lineFrom &&
          next + 1 < lineTo &&
          RegExp(r'[a-zçğıöşüâîû]').hasMatch(text[i - 1]) &&
          ((_isUpper(text[next]) &&
                  RegExp(r'[a-zçğıöşüâîû]').hasMatch(text[next + 1])) ||
              RegExp(r'^\d{1,2}\s*[-.)]\s*[A-ZÇĞİÖŞÜ]').hasMatch(rest));
      if (!joined) return false;
      var w = i;
      while (w > lineFrom &&
          RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]').hasMatch(text[w - 1])) {
        w--;
      }
      return !_abbreviations.contains(lowerTr(text.substring(w, i)));
    }
    while (next < lineTo && '"”’\')'.contains(text[next])) {
      next++;
    }
    while (next < lineTo && RegExp(r'\s').hasMatch(text[next])) {
      next++;
    }
    if (next >= lineTo) return true;
    var lead = next;
    while (lead < lineTo && '"“‘\'('.contains(text[lead])) {
      lead++;
    }
    if (lead >= lineTo) return true;
    if (!_isUpper(text[lead]) && !_isDigit(text.codeUnitAt(lead))) {
      return false;
    }
    if (char != '.') return true;

    // A number before the stop is an ordinal, a date or a sum: "3. Hukuk
    // Dairesi", "370. maddesi".
    if (i > lineFrom && _isDigit(text.codeUnitAt(i - 1))) return false;

    // A Roman numeral alone is a heading's number, "IV. İSTİNAF".
    // A short form, or a lone letter: "E.", "K.", "m.", "Av.".
    var w = i;
    while (w > lineFrom &&
        RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü.]').hasMatch(text[w - 1])) {
      w--;
    }
    final word = lowerTr(text.substring(w, i));
    if (word.isEmpty) return true;
    if (word.length == 1) return false;
    if (_abbreviations.contains(word)) return false;
    if (RegExp(r'^[ivxlc]+$').hasMatch(word) && w == lineFrom) return false;
    return true;
  }
}

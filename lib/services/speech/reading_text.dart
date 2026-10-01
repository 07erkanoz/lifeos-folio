import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;

import '../legal/citation.dart';

/// What a document says, written the way it is said aloud.
///
/// A voice reads what it is given, and a filing is written for the eye:
/// "HMK m. 119", "2025/417 E.", "15.000 TL", "3. Asliye". Read as written
/// they come out as letters and digits, so each is put into words before it
/// reaches the voice. Which short form means what is not knowledge that
/// belongs in code: the laws come from the citation table, everything else
/// from assets/ses/okuma.json.
class ReadingText {
  ReadingText({
    required this.laws,
    required this.abbreviations,
    required this.caseKinds,
    required this.currencies,
    required this.afterNumber,
  });

  /// The tables, read once for the app.
  static Future<ReadingText> shared() =>
      _shared ??= load().catchError((Object e) {
        _shared = null;
        throw e;
      });
  static Future<ReadingText>? _shared;

  /// Forgets the tables read, so that each test reads its own: a future
  /// kept from one test's fake clock never completes in the next.
  @visibleForTesting
  static void forget() => _shared = null;

  static Future<ReadingText> load() async {
    final scanner = await CitationScanner.load();
    return parse(await rootBundle.loadString('assets/ses/okuma.json'), {
      for (final law in scanner.laws)
        for (final short in law.abbreviations)
          // "Anayasa" is a word as well as a law; only a short form is
          // replaced wherever it stands.
          if (!RegExp(r'^\p{Lu}\p{Ll}+$', unicode: true).hasMatch(short))
            short: law.name,
    });
  }

  /// [raw] is okuma.json; [laws] each law's short form with its name.
  static ReadingText parse(String raw, Map<String, String> laws) {
    final json = jsonDecode(raw) as Map<String, Object?>;
    Map<String, String> table(String key) => {
      for (final e in (json[key] as Map? ?? const {}).entries)
        e.key as String: e.value as String,
    };
    return ReadingText(
      laws: laws,
      abbreviations: table('kisaltmalar'),
      caseKinds: table('dosyaTurleri'),
      currencies: table('paraBirimleri'),
      afterNumber: table('sayidanSonra'),
    );
  }

  /// Each law's short form, with its name.
  final Map<String, String> laws;

  /// The tables of okuma.json.
  final Map<String, String> abbreviations;
  final Map<String, String> caseKinds;
  final Map<String, String> currencies;
  final Map<String, String> afterNumber;

  /// [text] cut where a reader draws breath: at each line and each full
  /// stop that ends a sentence rather than an abbreviation or an ordinal.
  /// Each piece keeps where it came from, so the page can follow the voice.
  List<ReadingSentence> sentences(String text) {
    final out = <ReadingSentence>[];
    void add(int start, int end) {
      while (start < end && _isSpace(text.codeUnitAt(start))) {
        start++;
      }
      while (end > start && _isSpace(text.codeUnitAt(end - 1))) {
        end--;
      }
      if (end <= start) return;
      final piece = text.substring(start, end);
      if (!_wordy.hasMatch(piece)) return;
      // A voice holds a long sentence badly; a lawyer's run to a hundred
      // words. It is parted at a comma or semicolon, as it would be read.
      if (piece.length > _longest) {
        final cut = _cutAt(piece);
        if (cut != null) {
          add(start, start + cut);
          add(start + cut, end);
          return;
        }
      }
      out.add(ReadingSentence(start, end, piece, spoken(piece)));
    }

    var start = 0;
    for (final m in _ends.allMatches(text)) {
      if (m[0] == '\n') {
        add(start, m.start);
        start = m.end;
        continue;
      }
      if (_notAnEnd(text, m.start)) continue;
      add(start, m.end);
      start = m.end;
    }
    add(start, text.length);
    return out;
  }

  static const _longest = 320;
  static final _ends = RegExp(r'\n|[.!?…]+["”’»)\]]*(?=\s|$)');
  static final _wordy = RegExp(r'[\p{L}\d]', unicode: true);
  static bool _isSpace(int c) =>
      c == 32 || c == 9 || c == 10 || c == 13 || c == 0xA0 || c == 0x2060;

  static int? _cutAt(String piece) {
    for (final mark in ['; ', ', ']) {
      final at = piece.lastIndexOf(mark, _longest);
      if (at > _longest ~/ 3) return at + mark.length;
    }
    return null;
  }

  /// Whether the full stop at [at] closes a word that is not the end of a
  /// sentence: "Av.", "m.", a single initial, a number.
  bool _notAnEnd(String text, int at) {
    if (at >= text.length || text[at] != '.') return false;
    var from = at;
    while (from > 0 && !_isSpace(text.codeUnitAt(from - 1))) {
      from--;
    }
    final word = text.substring(from, at + 1);
    if (RegExp(r'^\(?\d+\.$').hasMatch(word)) return true;
    if (RegExp(r'^\p{Lu}\.$', unicode: true).hasMatch(word)) return true;
    if (const {'m.', 'md.', 'f.', 'b.'}.contains(word)) return true;
    return abbreviations.containsKey(word) ||
        caseKinds.containsKey(word) ||
        afterNumber.containsKey(word) ||
        // "Ltd. Şti.", "D. İş" and the like are two words.
        abbreviations.keys.any((k) => k.contains(' ') && k.startsWith(word));
  }

  /// [sentence] in words.
  String spoken(String sentence) {
    var s = sentence.replaceAll(RegExp(r'[ ⁠​]'), ' ');

    // 2025/417 E. — a case, the year and its number.
    s = s.replaceAllMapped(_caseNumber, (m) {
      final kind = caseKinds[m[3]!]!;
      return '${sayiYazi(int.parse(m[1]!))}, ${_number(m[2]!)} $kind';
    });

    // 01.02.2025
    s = s.replaceAllMapped(_date, (m) {
      final month = int.parse(m[2]!);
      if (month < 1 || month > 12) return m[0]!;
      return '${sayiYazi(int.parse(m[1]!))} ${_months[month - 1]} '
          '${sayiYazi(int.parse(m[3]!))}';
    });

    // 6100 s. — a law by its number.
    s = s.replaceAllMapped(_afterNumberPattern, (m) {
      return '${_number(m[1]!)} ${afterNumber[m[2]!]!}';
    });

    // HMK m. 119/1 — an article of a law, and the paragraph in it.
    s = s.replaceAllMapped(_citation, (m) {
      final name = laws[m[1]!]!;
      final article = siraYazi(int.parse(m[2]!));
      final paragraph = m[3];
      return paragraph == null
          ? '${inflect(name, 'nın')} $article maddesi'
          : '${inflect(name, 'nın')} $article maddesinin '
                '${siraYazi(int.parse(paragraph))} fıkrası';
    });
    // m. 119 — an article of the law already named.
    s = s.replaceAllMapped(_bareArticle, (m) {
      final paragraph = m[2];
      return paragraph == null
          ? '${siraYazi(int.parse(m[1]!))} madde'
          : '${siraYazi(int.parse(m[1]!))} maddenin '
                '${siraYazi(int.parse(paragraph))} fıkrası';
    });

    // HMK, HMK'nın — the law, by name, with whatever the sentence adds.
    s = s.replaceAllMapped(_lawPattern, (m) {
      final name = laws[m[1]!]!;
      return m[2] == null ? name : inflect(name, m[2]!);
    });
    s = s.replaceAllMapped(_abbreviationPattern, (m) {
      final said = abbreviations[m[1]!]!;
      return m[2] == null ? said : inflect(said, m[2]!);
    });

    // 15.000 TL, ₺15.000, 1.250,50 TL
    s = s.replaceAllMapped(_moneyAfter, (m) {
      return _money(m[1]!, m[2], currencies[m[3]!]!, m[4]);
    });
    s = s.replaceAllMapped(_moneyBefore, (m) {
      return _money(m[2]!, m[3], currencies[m[1]!]!, null);
    });

    // %18
    s = s.replaceAllMapped(
      RegExp(r'%\s*(\d+(?:,\d+)?)'),
      (m) => 'yüzde ${_decimal(m[1]!)}',
    );

    // 3. Asliye, 119. maddesi — a number that counts.
    s = s.replaceAllMapped(
      RegExp(r'(?<![\d.,/])(\d{1,4})\.(?=\s*[\p{L}(])', unicode: true),
      (m) => siraYazi(int.parse(m[1]!)),
    );

    // 89/1
    s = s.replaceAllMapped(RegExp(r'(?<=\d)\s*/\s*(?=\d)'), (_) => ' bölü ');

    // 15.000, 12,5, 0532
    s = s.replaceAllMapped(
      RegExp(r'\d{1,3}(?:\.\d{3})+(?:,\d+)?|\d+(?:,\d+)?'),
      (m) => _decimal(m[0]!.replaceAll('.', '')),
    );

    // Capitals: an abbreviation no table carries is said letter by letter;
    // a heading in capitals is read as the words it is.
    s = s.replaceAllMapped(
      RegExp(r'(?<!\p{L})\p{Lu}{2,}(?!\p{L})', unicode: true),
      (m) {
        final word = m[0]!;
        return _vowels.hasMatch(word) ? trLower(word) : _spell(word);
      },
    );

    return s
        .replaceAll(RegExp(r'\s*[•▪►◦·–—]\s*'), ', ')
        .replaceAll(RegExp(r'_+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[,\s]+'), '')
        .trim();
  }

  static final _vowels = RegExp('[AEIİOÖUÜ]');

  late final RegExp _caseNumber = RegExp(
    r'(?<!\d)(\d{4})\s*/\s*(\d+)\s*'
    '(${_alternation(caseKinds.keys)})'
    r'(?![\p{L}\d])',
    unicode: true,
  );

  static final _date = RegExp(
    r'(?<![\d.])(\d{1,2})[./](\d{1,2})[./](\d{4})(?![\d])',
  );

  late final RegExp _afterNumberPattern = RegExp(
    '(?<![\\d.])(\\d+)\\s*(${_alternation(afterNumber.keys)})'
    r'(?!\p{L})',
    unicode: true,
  );

  late final RegExp _citation = RegExp(
    '(?<![\\p{L}\\d])(${_alternation(laws.keys)})'
    r"(?:['’]\p{L}+)?\s*(?:m\.|md\.|madde)\s*(\d+)(?:\s*/\s*(\d+))?",
    unicode: true,
  );

  static final _bareArticle = RegExp(
    r'(?<![\p{L}\d])(?:m\.|md\.)\s*(\d+)(?:\s*/\s*(\d+))?',
    unicode: true,
  );

  late final RegExp _lawPattern = RegExp(
    '(?<![\\p{L}\\d])(${_alternation(laws.keys)})'
    r"(?:['’](\p{L}+))?(?![\p{L}\d])",
    unicode: true,
  );

  late final RegExp _abbreviationPattern = RegExp(
    '(?<![\\p{L}\\d])(${_alternation(abbreviations.keys)})'
    r"(?:(?<=\p{L})['’](\p{L}+))?(?![\p{L}\d])",
    unicode: true,
  );

  static const _amount = r'(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2}))?';

  late final RegExp _moneyAfter = RegExp(
    '(?<![\\d.,])$_amount\\s*(${_alternation(currencies.keys)})'
    r"(?:['’](\p{L}+))?(?!\p{L})",
    unicode: true,
  );

  late final RegExp _moneyBefore = RegExp(
    '(${_alternation(currencies.keys.where((k) => !RegExp(r'\p{L}', unicode: true).hasMatch(k)))})'
    '\\s*$_amount',
    unicode: true,
  );

  String _money(String whole, String? cents, String currency, String? suffix) {
    final amount = sayiYazi(int.parse(whole.replaceAll('.', '')));
    final said = suffix == null
        ? currency
        : inflect(currency, suffix, proper: false);
    final kurus = cents == null ? 0 : int.parse(cents.padRight(2, '0'));
    return kurus == 0
        ? '$amount $said'
        : '$amount $said ${sayiYazi(kurus)} kuruş';
  }

  /// Longest first, so "Ltd. Şti." is taken before "Ltd.".
  static String _alternation(Iterable<String> words) {
    final list = words.toList()..sort((a, b) => b.length.compareTo(a.length));
    return list.isEmpty ? r'(?!)' : list.map(RegExp.escape).join('|');
  }

  static String _number(String digits) {
    final n = int.tryParse(digits);
    if (n == null || digits.length > 15) {
      return digits.split('').map((d) => sayiYazi(int.parse(d))).join(' ');
    }
    // 0532: the zero is said.
    final zeros = RegExp(r'^0+(?=\d)').stringMatch(digits)?.length ?? 0;
    return [for (var i = 0; i < zeros; i++) 'sıfır', sayiYazi(n)].join(' ');
  }

  static String _decimal(String written) {
    final parts = written.split(',');
    if (parts.length == 1) return _number(parts[0]);
    return '${_number(parts[0])} virgül ${_number(parts[1])}';
  }

  static String _spell(String word) =>
      word.split('').map((c) => _letters[c] ?? c).join(' ');

  static const _letters = {
    'A': 'a',
    'B': 'be',
    'C': 'ce',
    'Ç': 'çe',
    'D': 'de',
    'E': 'e',
    'F': 'fe',
    'G': 'ge',
    'Ğ': 'yumuşak ge',
    'H': 'ha',
    'I': 'ı',
    'İ': 'i',
    'J': 'je',
    'K': 'ke',
    'L': 'le',
    'M': 'me',
    'N': 'ne',
    'O': 'o',
    'Ö': 'ö',
    'P': 'pe',
    'R': 're',
    'S': 'se',
    'Ş': 'şe',
    'T': 'te',
    'U': 'u',
    'Ü': 'ü',
    'V': 've',
    'Y': 'ye',
    'Z': 'ze',
    'Q': 'ku',
    'W': 've',
    'X': 'iks',
  };

  static const _months = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];
}

/// One piece of a text as it is read: where it is, and what is said.
class ReadingSentence {
  const ReadingSentence(this.start, this.end, this.text, this.spoken);
  final int start, end;
  final String text, spoken;

  /// The same, [by] characters further on: a sentence of a part of a text
  /// placed in the whole of it.
  ReadingSentence shifted(int by) =>
      ReadingSentence(start + by, end + by, text, spoken);
}

String trLower(String value) =>
    value.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

const _ones = [
  '',
  'bir',
  'iki',
  'üç',
  'dört',
  'beş',
  'altı',
  'yedi',
  'sekiz',
  'dokuz',
];
const _tens = [
  '',
  'on',
  'yirmi',
  'otuz',
  'kırk',
  'elli',
  'altmış',
  'yetmiş',
  'seksen',
  'doksan',
];

/// 2025 → "iki bin yirmi beş".
String sayiYazi(int n) {
  if (n == 0) return 'sıfır';
  final words = <String>[];
  for (final (value, name) in const [
    (1000000000000, 'trilyon'),
    (1000000000, 'milyar'),
    (1000000, 'milyon'),
    (1000, 'bin'),
  ]) {
    final count = n ~/ value;
    if (count == 0) continue;
    // "bin", never "bir bin".
    if (!(value == 1000 && count == 1)) words.add(_belowThousand(count));
    words.add(name);
    n %= value;
  }
  if (n > 0) words.add(_belowThousand(n));
  return words.join(' ');
}

String _belowThousand(int n) {
  final words = <String>[];
  final hundreds = n ~/ 100;
  if (hundreds > 0) {
    if (hundreds > 1) words.add(_ones[hundreds]);
    words.add('yüz');
  }
  if ((n % 100) ~/ 10 > 0) words.add(_tens[(n % 100) ~/ 10]);
  if (n % 10 > 0) words.add(_ones[n % 10]);
  return words.join(' ');
}

/// 119 → "yüz on dokuzuncu".
String siraYazi(int n) {
  final words = sayiYazi(n);
  if (words.endsWith('dört')) {
    return '${words.substring(0, words.length - 4)}dördüncü';
  }
  final v = _fourWay(_lastVowel(words));
  return _endsInVowel(words) ? '${words}nc$v' : '$words${v}nc$v';
}

/// [name] with the case [written] asks for, in the sound [name] takes:
/// "HMK'ya" becomes "Hukuk Muhakemeleri Kanunu'na", "SGK'dan" becomes
/// "Sosyal Güvenlik Kurumu'ndan". A suffix that is not a case — "'daki" is
/// "'da" and "ki" — keeps whatever follows the case.
String inflect(String name, String written, {bool proper = true}) {
  final last = name.split(' ').last;
  final vowel = _lastVowel(last);
  final v4 = _fourWay(vowel);
  final v2 = 'aıou'.contains(vowel) ? 'a' : 'e';
  final open = _endsInVowel(last);
  // "Kanunu", "Kurumu": a compound already ending in its own possessive
  // takes n before a case; a word of its own takes y.
  final compound = open && name.contains(' ');
  final hard = RegExp('[çfhkpsşt]\$').hasMatch(last);
  final lower = trLower(written);
  String? suffix;
  var rest = '';
  RegExpMatch? m;
  if ((m = RegExp(r'^n?[dt][ae]n').firstMatch(lower)) != null) {
    suffix = '${open ? (compound ? 'nd' : 'd') : (hard ? 't' : 'd')}${v2}n';
  } else if ((m = RegExp(r'^n?[ıiuü]n').firstMatch(lower)) != null) {
    suffix = '${open ? 'n' : ''}${v4}n';
  } else if ((m = RegExp(r'^n?[dt][ae]').firstMatch(lower)) != null) {
    suffix = '${open ? (compound ? 'nd' : 'd') : (hard ? 't' : 'd')}$v2';
  } else if ((m = RegExp(r'^[yn]?[ae]$').firstMatch(lower)) != null) {
    suffix = '${open ? (compound ? 'n' : 'y') : ''}$v2';
  } else if ((m = RegExp(r'^[yn]?[ıiuü]$').firstMatch(lower)) != null) {
    suffix = '${open ? (compound ? 'n' : 'y') : ''}$v4';
  }
  if (m != null) rest = lower.substring(m.end);
  final said = suffix == null ? written : '$suffix$rest';
  return proper ? "$name'$said" : '$name$said';
}

String _lastVowel(String word) {
  for (var i = word.length - 1; i >= 0; i--) {
    final c = trLower(word[i]);
    if ('aeıioöuü'.contains(c)) return c;
  }
  return 'e';
}

String _fourWay(String vowel) => switch (vowel) {
  'a' || 'ı' => 'ı',
  'e' || 'i' => 'i',
  'o' || 'u' => 'u',
  _ => 'ü',
};

bool _endsInVowel(String word) =>
    word.isNotEmpty && 'aeıioöuü'.contains(trLower(word[word.length - 1]));

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A law the reader may cite, and the short forms they cite it by.
@immutable
class Law {
  const Law({
    required this.number,
    required this.tertip,
    required this.name,
    this.abbreviations = const [],
    this.aliases = const [],
    this.repealed = false,
    this.byName = true,
  });

  /// A law the table does not carry, known only by the number written
  /// before it: "5626 sayılı Kanun'un 8. maddesi". Its real name and its
  /// place in the Düstur are asked of the official source when it is opened.
  factory Law.numbered(int number) =>
      Law(number: number, tertip: 0, name: '$number sayılı Kanun');

  /// The number every Turkish law is known by: 4721, 6100, 5237.
  final int number;

  /// Which collection of the Düstur holds it. Mevzuat wants this to find the
  /// text, and it is not derivable from the number: 213 is in the fourth,
  /// 2004 in the third, most of the rest in the fifth. Zero for a law known
  /// only by its number.
  final int tertip;

  final String name;

  /// TMK, MK — the forms a lawyer actually writes.
  final List<String> abbreviations;

  /// Other names the same law goes by in a filing: a lawyer writing about
  /// the Code of Obligations is as likely to put "Borçlar Kanunu" as the
  /// whole of "Türk Borçlar Kanunu".
  final List<String> aliases;

  /// Repealed, and still cited: an old contract or an old case stays under
  /// the law of its day.
  final bool repealed;

  /// False for a repealed law that shares its name with the one in force.
  /// "Borçlar Kanunu" is 6098 now; the old one, 818, is recognised only by
  /// its number, "818 s. BK m. 41".
  final bool byName;

  /// Whether the table carries this law, rather than only its number.
  bool get isKnown => tertip != 0;

  /// Every name this law answers to, longest first so the fullest reading
  /// of a phrase is the one that is taken.
  List<String> get names => byName
      ? (<String>{
          name,
          ...aliases,
          // Almost every code carries the country's name, and almost no
          // lawyer writes it every time.
          if (name.startsWith('Türk ')) name.substring(5),
        }.toList()..sort((a, b) => b.length.compareTo(a.length)))
      : const [];

  /// "4721 s. Türk Medeni Kanunu", or only "5626 sayılı Kanun" for a law the
  /// table does not carry.
  String get shown =>
      isKnown ? '$number s. $name${repealed ? ' (mülga)' : ''}' : name;

  static Law fromJson(Map<String, Object?> json) => Law(
    number: (json['no'] as num).toInt(),
    tertip: (json['tertip'] as num).toInt(),
    name: json['ad'] as String,
    abbreviations: [
      for (final a in (json['kisa'] as List? ?? const [])) a as String,
    ],
    aliases: [
      for (final a in (json['adlar'] as List? ?? const [])) a as String,
    ],
    repealed: json['mulga'] == true,
    byName: json['adla'] != false,
  );
}

/// Which article of a law, when it is not an ordinary one.
enum ArticleKind {
  plain(''),

  /// Geçici madde: HMK geçici m. 3.
  provisional('geçici '),

  /// Ek madde: 4857 sayılı Kanun ek m. 2.
  additional('ek ');

  const ArticleKind(this.prefix);

  /// How it is written before "m.".
  final String prefix;
}

/// A reference to a law article, and where it sits in the text.
@immutable
class Citation {
  const Citation({
    required this.law,
    required this.article,
    required this.start,
    required this.length,
    this.paragraph,
    this.clause,
    this.letter,
    this.kind = ArticleKind.plain,
    this.romanParagraph = false,
    this.written = '',
  });

  final Law law;

  /// The article number: the 166 of TMK m. 166.
  final int article;

  /// The letter of a lettered article: the a of İİK 68/a, which is an article
  /// of its own and not a part of 68.
  final String? letter;

  /// A provisional or an added article, which is numbered on its own.
  final ArticleKind kind;

  /// The fıkra and the bent, when the reader wrote them: the 1 and the a of
  /// TCK m. 53/1-a. Kept so the reader can be shown where to look, though
  /// the article is fetched whole.
  final int? paragraph;
  final String? clause;

  /// Whether the fıkra was written in Roman numerals, "TBK m. 479/II", and
  /// is shown that way.
  final bool romanParagraph;

  /// The citation as the document wrote it.
  final String written;

  /// Counted in UTF-16 code units, the way a Dart string counts, so these
  /// index the very string that was scanned.
  final int start, length;

  int get end => start + length;

  /// Where in the law: "m. 166/1-a", "geçici m. 3", "m. 68/a", and the
  /// fıkra of a lettered article after a dash, "m. 18/A-7".
  String get place {
    final where = StringBuffer('${kind.prefix}m. $article');
    if (letter != null) where.write('/$letter');
    if (paragraph != null) {
      where.write(letter == null ? '/' : '-');
      where.write(romanParagraph ? romanOf(paragraph!) : paragraph);
    }
    if (clause != null) where.write('-$clause');
    return where.toString();
  }

  /// How it is named on screen: "4721 s. Türk Medeni Kanunu m. 166/1".
  String get label => '${law.shown} $place';

  Citation _with({Law? law, int? start, int? length, String? written}) =>
      Citation(
        law: law ?? this.law,
        article: article,
        start: start ?? this.start,
        length: length ?? this.length,
        paragraph: paragraph,
        clause: clause,
        letter: letter,
        kind: kind,
        romanParagraph: romanParagraph,
        written: written ?? this.written,
      );

  @override
  bool operator ==(Object other) =>
      other is Citation &&
      other.law.number == law.number &&
      other.article == article &&
      other.letter == letter &&
      other.kind == kind &&
      other.paragraph == paragraph &&
      other.clause == clause &&
      other.start == start &&
      other.length == length;

  @override
  int get hashCode => Object.hash(
    law.number,
    article,
    letter,
    kind,
    paragraph,
    clause,
    start,
    length,
  );

  @override
  String toString() => 'Citation($label @$start+$length)';
}

/// Turkish upper case, which is not the one Dart does by default.
///
/// Dart turns i into I, as English wants. Turkish wants İ, and keeps a
/// separate ı for the undotted one. Without this, iik and İİK are different
/// words and the reader's lower-case writing is never recognised.
String upperTr(String value) =>
    value.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// "HASAN DURMUŞ" as a name is written, "Hasan Durmuş"; "VE DİĞERLERİ"
/// stays small, "ve Diğerleri".
String titleCaseTr(String value) {
  final lower = value
      .replaceAll('İ', 'i')
      .replaceAll('I', 'ı')
      .toLowerCase()
      .trim();
  return lower
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map(
        (word) => word == 've'
            ? word
            : '${upperTr(word.substring(0, 1))}${word.substring(1)}',
      )
      .join(' ');
}

/// The key a name or a short form is looked up by: upper case, the Turkish
/// way, with the dot over the capital I let go and the spaces made single.
///
/// A document typed on a keyboard without Turkish letters writes MEDENI and
/// IIK; a court's own capitals write MEDENİ and İİK. They are the same law.
String lookupKey(String value) =>
    upperTr(value.replaceAll(RegExp(r'\s+'), ' ').trim()).replaceAll('İ', 'I');

/// A word as a pattern that finds it in capitals too.
///
/// Dart's case-insensitive matching folds i to I the English way and never
/// reaches İ or ı, so "sayılı" does not find "SAYILI" and "madde" finds
/// "MADDE" but "maddesi" stops short of "MADDESİ". Every i-like letter is
/// widened to all four; the rest of the word is left to the ignored case.
String trLoose(String literal) {
  final out = StringBuffer();
  for (final rune in literal.runes) {
    final char = String.fromCharCode(rune);
    out.write(switch (char) {
      'i' || 'İ' || 'ı' || 'I' => '[iİıI]',
      _ => RegExp.escape(char),
    });
  }
  return out.toString();
}

/// I, II, III… for the fıkra written that way.
String romanOf(int value) {
  const numerals = [(10, 'X'), (9, 'IX'), (5, 'V'), (4, 'IV'), (1, 'I')];
  var left = value;
  final out = StringBuffer();
  for (final (worth, numeral) in numerals) {
    while (left >= worth) {
      out.write(numeral);
      left -= worth;
    }
  }
  return out.toString();
}

int? _romanValue(String numeral) {
  const values = {'I': 1, 'V': 5, 'X': 10};
  var total = 0;
  var previous = 0;
  for (final char in numeral.toUpperCase().split('').reversed) {
    final value = values[char];
    if (value == null) return null;
    total += value < previous ? -value : value;
    if (value > previous) previous = value;
  }
  return total == 0 ? null : total;
}

// -- the pieces every pattern shares ----------------------------------------

const _letters = 'A-Za-zÇĞİÖŞÜçğıöşüÂâÎîÛû';

/// Not in the middle of a word or a number.
const _before = '(?<![${_letters}0-9])';
const _after = '(?![${_letters}0-9])';

/// The letters a suffix is written in, capitals included: with the case
/// ignored every letter here finds its capital except the dotted İ.
const _suffix = "a-zçğıöşüâîûİ";

/// "119 uncu", "18 inci", "297. maddesi" — the ordinal ending.
final _ordinal =
    '(?:${trLoose('inci')}|${trLoose('ıncı')}|[uüUÜ]nc[uüUÜ]|nc[iİıIuüUÜ])';

/// The words that say an article is meant.
final _marker =
    '(?:m\\.|md\\.|mad\\.|madde(?:${trLoose('si')}|${trLoose('sinde')}|'
    '${trLoose('since')}|ye|${trLoose('nin')})?)';

/// Geçici and ek articles are numbered on their own.
final _special = '(?:(?<ozel>${trLoose('geçici')}|ek)\\s+)?';

/// "madde", "maddesi", "maddesinin", "MADDESİ" — after the number.
final _articleWord = 'madde[$_suffix]*';

/// What may follow an article number: the letter of a lettered article
/// (68/a), the fıkra (/1, /II) and the bent (-a).
String _tail([String n = '']) =>
    '(?![0-9])'
    '(?:\\s*/\\s*(?<harf$n>[$_letters])$_after'
    '(?:\\s*-\\s*(?<hfikra$n>[0-9]{1,3})(?![0-9]))?)?'
    '(?:\\s*/\\s*(?:(?<fikra$n>[0-9]{1,3})|(?<roma$n>(?:IX|IV|V?I{1,3}|V|X))'
    '(?![$_letters]))(?![0-9]))?'
    '(?:\\s*-\\s*(?<bent$n>[a-zçğıöşü])$_after)?';

/// TMK m. 166/1-a, İİK 89/1, HMK'nın 297. maddesi, H.M.K. 193. maddesi.
///
/// A short form may follow a digit without a space — "2020/64HMK 200", as
/// text taken out of a PDF often runs — but a number may not.
final _short = RegExp(
  '(?<kisa>(?<![${_letters}0-9])[0-9]{3,5}'
  '|(?<![$_letters])(?:[A-ZÇĞİÖŞÜ]\\.){2,5}|(?<![$_letters])[$_letters]{2,8})'
  "(?:['’][$_letters]{1,5})?"
  '\\s*$_special'
  '(?<isaret>$_marker)?\\s*'
  '(?<no>[0-9]{1,4})${_tail()}'
  '(?<son>\\s*\\.?\\s*$_ordinal?\\s*$_articleWord)?',
  caseSensitive: false,
);

final _numbered =
    '(?<![0-9/.])(?<kno>[0-9]{3,5})\\s*(?:s\\.|${trLoose('sayılı')})';

/// What may stand between "NNNN sayılı" and the article: anything but the
/// end of a sentence and another "NNNN sayılı". "13100 sayılı Resmî Gazete'de
/// yayımlanan 7242 sayılı Kanunun 10. maddesi" is an article of 7242, and
/// the Gazette's number has to give way to it.
String _between(int most) =>
    '(?<ara>(?:(?![0-9]{3,5}\\s*(?:s\\.|${trLoose('sayılı')}))[^.;:]){0,$most}?)';

/// 6100 sayılı Hukuk Muhakemeleri Kanunu'nun 119. maddesi — the long way,
/// where the number and the article sit either side of the law's name.
final _long = RegExp(
  '$_numbered'
  '${_between(90)}'
  '(?<no>[0-9]{1,4})${_tail()}\\s*\\.?\\s*$_ordinal?\\s*$_articleWord',
  caseSensitive: false,
);

/// 2942 sayılı Kanun m. 11 — the long way with the article marked first.
///
/// Measured against a working archive of 2,600 documents: this is how
/// about nine hundred of its citations are written, and none of them was
/// read before.
final _longMarked = RegExp(
  '$_numbered'
  '${_between(60)}$_special'
  '(?:m\\.|md\\.|mad\\.|madde(?:${trLoose('si')}|${trLoose('sinde')})?)'
  '\\s*(?<no>[0-9]{1,4})${_tail()}',
  caseSensitive: false,
);

/// "NNNN sayılı" just before a short form: the number decides the law.
/// "818 s. BK m. 41" is the old Code of Obligations, not the new one BK
/// otherwise stands for.
///
/// A word or two may stand between, "7036 sayılı İş M.K. m. 3" — but not
/// another law: "6100 sayılı Kanun ve TMK m. 166" cites two.
final _numberBefore = RegExp(
  '(?<![0-9/.])([0-9]{3,5})\\s*(?:s\\.|${trLoose('sayılı')})'
  '((?:\\s+[$_letters]{1,12}){0,2})\\s*\$',
  caseSensitive: false,
);

final _anotherLaw = RegExp(
  '(?:^|\\s)(?:kanun|yasa|ve|ile|veya|${trLoose('ilgili')})',
  caseSensitive: false,
);

/// "sayılı … maddesi" can describe something that is not a law at all.
final _notALaw = RegExp(
  [
    trLoose('yönetmeli'),
    'genelge',
    '${trLoose('tebli')}[ğĞg]',
    'tüzü',
    'karar',
    trLoose('yönerge'),
    trLoose('sözleşme'),
    'protokol',
    'dosya',
    'gazete',
  ].join('|'),
  caseSensitive: false,
);

final _saysLaw = RegExp('kanun|yasa', caseSensitive: false);

/// ", 50 ve 51. maddeleri" — the next articles of the same law.
///
/// What follows the number has to close the list or the sentence: "166,
/// 2. fıkra" and "166, 2 çocuk" are not lists of articles. A dash lists
/// articles only after a bare article: after a fıkra or a bent it goes on
/// dividing that article, "HMK 353/1-b-2", "TCK 53/1-2-3".
///
/// The article before may still carry its ordinal — "Anayasa'nın 2. ve 38.
/// maddelerine", "2 nci ve 38 inci maddeleri" — which the citation before
/// left behind.
RegExp _continuation({required bool dash}) => RegExp(
  '(?<on>(?:\\.|\\s*$_ordinal)?\\s*(?:,|ve|ile|veya|ila${dash ? '|-|–' : ''})\\s*'
  '(?:(?:m\\.|md\\.)\\s*)?)'
  '(?<no>[0-9]{1,4})(?![0-9]|[.,/][0-9])'
  '(?:\\s*/\\s*(?<fikra>[0-9]{1,3}))?'
  '(?:\\s*-\\s*(?<bent>[a-zçğıöşü])$_after)?'
  '(?=(?:\\s*$_ordinal)?\\s*(?:[,;:)]|\\.(?!\\s*(?:f[ıi]kra|bent|c[üu]mle|sat[ıi]r|sayfa))'
  '|ve(?![$_letters])|ile(?![$_letters])|veya(?![$_letters])'
  '|ila(?![$_letters])|madde|h[üu]k[üu]m|uyar[ıi]nca|gere[ğg]ince|kapsam|\$))',
  caseSensitive: false,
);

final _continued = _continuation(dash: true);
final _continuedUndashed = _continuation(dash: false);

/// "aynı Kanun'un 7. maddesi" — the law cited just before.
final _same = RegExp(
  '$_before'
  '(?:${trLoose('aynı')}|${trLoose('anılan')}|mezk[uû]r|'
  '${trLoose('söz')}\\s+konusu|${trLoose('sözü')}\\s+edilen|'
  '${trLoose('bahsi')}\\s+${trLoose('geçen')}|${trLoose('ilgili')})'
  "\\s+(?:kanun|yasa)[$_suffix'’]{0,7}\\s*$_special"
  '(?:$_marker\\s*(?<no1>[0-9]{1,4})${_tail('1')}'
  '|(?<no2>[0-9]{1,4})${_tail('2')}\\s*\\.?\\s*$_ordinal?\\s*$_articleWord)',
  caseSensitive: false,
);

/// "The same law" reaches back only this far; further is another context.
const _sameReach = 600;

/// Finds the laws a document cites.
///
/// Turkish legal writing points at a law in a handful of settled ways — TMK
/// m. 166/1, İİK 89/1, HMK'nın 297. maddesi, 6100 sayılı Kanun'un 119.
/// maddesi — and a document is usually thick with them. Which law each short
/// form means is not knowledge that belongs in code: it is carried in a data
/// file that can be corrected and added to without touching this.
class CitationScanner {
  CitationScanner(List<Law> laws) : _laws = laws {
    for (final law in laws) {
      _byNumber['${law.number}'] = law;
      for (final short in law.abbreviations) {
        _byAbbreviation[lookupKey(short)] = law;
      }
    }
  }

  final List<Law> _laws;
  final _byAbbreviation = <String, Law>{};
  final _byNumber = <String, Law>{};

  List<Law> get laws => List.unmodifiable(_laws);

  /// Reads the table the app ships with.
  static Future<CitationScanner> load({
    String asset = 'assets/mevzuat/laws.json',
  }) async {
    final raw = await rootBundle.loadString(asset);
    return CitationScanner.parse(raw);
  }

  @visibleForTesting
  static CitationScanner parse(String raw) {
    final json = jsonDecode(raw) as Map<String, Object?>;
    return CitationScanner([
      for (final entry in json['kanunlar'] as List)
        Law.fromJson(entry as Map<String, Object?>),
    ]);
  }

  /// A name, written as a pattern that survives how Turkish writes it.
  ///
  /// The name takes a suffix — Kanunu'nun, Kanununun, Kanunda — and the
  /// final u of "Kanunu" is itself part of the word being inflected, so it
  /// is made optional and the suffix allowed to follow. Whitespace between
  /// the words is loosened too, because a name can wrap onto the next line.
  static String _namePattern(String name) {
    final loose = name.split(RegExp(r'\s+')).map(trLoose).join(r'\s+');
    // The pattern ends in the u being made optional.
    return name.endsWith('Kanunu')
        ? '${loose.substring(0, loose.length - 1)}u?'
        : loose;
  }

  /// Each name with the law it belongs to, the longest name first so that
  /// "Türk Ceza Kanunu" is preferred over the "Ceza Kanunu" inside it.
  late final List<(String, Law)> _namesLongestFirst = () {
    final pairs = <(String, Law)>[];
    for (final law in _laws) {
      for (final name in law.names) {
        pairs.add((name, law));
      }
    }
    pairs.sort((a, b) => b.$1.length.compareTo(a.$1.length));
    return pairs;
  }();

  late final Map<String, Law> _byName = () {
    final out = <String, Law>{};
    for (final pair in _namesLongestFirst) {
      final key = lookupKey(pair.$1);
      out.putIfAbsent(key, () => pair.$2);
      // "Medeni Kanun'un" is written as often as "Medeni Kanunu'nun": the
      // final u belongs to the word being inflected and a writer who adds a
      // suffix often drops it. The pattern already allows for that, so the
      // shortened form has to be answerable here too.
      if (key.endsWith('KANUNU')) {
        out.putIfAbsent(key.substring(0, key.length - 1), () => pair.$2);
      }
    }
    return out;
  }();

  /// Türk Borçlar Kanunu'nun 112. maddesi — the law named rather than
  /// numbered, which is how most of a filing is written.
  late final RegExp _named = RegExp(
    '$_before'
    '(?<ad>${[for (final pair in _namesLongestFirst) _namePattern(pair.$1)].join('|')})'
    "(?:['’]?[$_suffix]{0,5})?\\s*$_special"
    '(?:$_marker\\s*(?<no1>[0-9]{1,4})${_tail('1')}'
    '|(?<no2>[0-9]{1,4})${_tail('2')}\\s*\\.?\\s*$_ordinal?\\s*$_articleWord)',
    caseSensitive: false,
  );

  /// The law a written name belongs to, however its spaces happened to fall.
  Law? _lawNamed(String written) => _byName[lookupKey(written)];

  /// Any name the table carries, standing on its own.
  late final RegExp _anyName = RegExp(
    '$_before(?:${[for (final pair in _namesLongestFirst) _namePattern(pair.$1)].join('|')})',
    caseSensitive: false,
  );

  static final _joined = RegExp(
    '(?:,|;|(?<![$_letters])(?:ve|ile|veya)(?![$_letters]))',
    caseSensitive: false,
  );

  /// Whether what stands between "NNNN sayılı" and an article joins on a
  /// second law: "6100 sayılı Kanun ve TMK m. 166" cites the Civil Code, not
  /// article 166 of 6100. Without a joining word the number stays in charge
  /// — "3713 sayılı TMK'nın 7/2. maddesi" is the Anti-Terror Law, whatever
  /// TMK otherwise means.
  bool _joinsAnotherLaw(String between, int number) {
    final joins = _joined.allMatches(between).toList();
    if (joins.isEmpty) return false;
    final after = between.substring(joins.last.end);
    for (final word in RegExp('[$_letters.]{2,10}').allMatches(after)) {
      final law =
          _byAbbreviation[lookupKey(word.group(0)!.replaceAll('.', ''))];
      if (law != null && law.number != number) return true;
    }
    for (final name in _anyName.allMatches(after)) {
      final law = _lawNamed(name.group(0)!);
      if (law != null && law.number != number) return true;
    }
    return false;
  }

  Law _numberedLaw(String number) =>
      _byNumber[number] ?? Law.numbered(int.parse(number));

  static bool _valid(int article) => article >= 1 && article <= 2000;

  /// A citation built from what one of the patterns caught.
  static Citation _read(
    RegExpMatch m,
    Law law,
    int article, {
    String n = '',
    String? special,
  }) {
    String? group(String name) {
      try {
        return m.namedGroup(name);
      } on ArgumentError {
        return null;
      }
    }

    var letter = group('harf$n');
    var paragraph = int.tryParse(group('hfikra$n') ?? group('fikra$n') ?? '');
    var roman = false;
    final romanWritten = group('roma$n');
    if (romanWritten != null) {
      paragraph = _romanValue(romanWritten);
      roman = paragraph != null;
    }
    // A capital I, V or X after the slash is the fıkra in Roman numerals —
    // "25/I" — rather than a lettered article, which Turkish writes in the
    // small letters of the alphabet: 68/a, 35/A.
    if (letter != null &&
        paragraph == null &&
        RegExp(r'^[IVX]$').hasMatch(letter)) {
      paragraph = _romanValue(letter);
      roman = true;
      letter = null;
    }
    final kindWritten = special ?? group('ozel');
    return Citation(
      law: law,
      article: article,
      letter: letter,
      paragraph: paragraph,
      romanParagraph: roman,
      clause: group('bent$n'),
      kind: kindWritten == null
          ? ArticleKind.plain
          : lookupKey(kindWritten) == 'EK'
          ? ArticleKind.additional
          : ArticleKind.provisional,
      start: m.start,
      length: m.end - m.start,
      written: m.group(0)!,
    );
  }

  /// A "NNNN sayılı" written just before decides the law, and is taken into
  /// the citation.
  Citation _numberInFront(String text, Citation found) {
    final from = found.start - 50 < 0 ? 0 : found.start - 50;
    final before = text.substring(from, found.start);
    final m = _numberBefore.firstMatch(before);
    if (m == null) return found;
    final words = m.group(2) ?? '';
    if (words.trim().isNotEmpty && _anotherLaw.hasMatch(words)) return found;
    final start = from + m.start;
    return found._with(
      law: _numberedLaw(m.group(1)!),
      start: start,
      length: found.end - start,
      written: text.substring(start, found.end),
    );
  }

  /// Every citation in [text], in the order they appear, none overlapping.
  List<Citation> scan(String text) {
    if (text.isEmpty) return const [];
    final found = <Citation>[];

    for (final pattern in [_long, _longMarked]) {
      for (final m in pattern.allMatches(text)) {
        final between = m.namedGroup('ara') ?? '';
        if (_notALaw.hasMatch(between)) continue;
        final number = m.namedGroup('kno')!;
        if (_joinsAnotherLaw(between, int.parse(number))) continue;
        final known = _byNumber[number];
        // Laws are numbered in four figures still; five are a Gazette's or a
        // file's number.
        if (known == null && number.length > 4) continue;
        // A number the table does not carry has to be called a law: "1234
        // sayılı dosyanın 5. maddesi" is not one.
        if (known == null && !_saysLaw.hasMatch(between)) continue;
        final article = int.parse(m.namedGroup('no')!);
        if (!_valid(article)) continue;
        // "Kanun'un geçici 1. maddesi": the word is left at the end of what
        // stands between.
        final trailing = RegExp(
          '(?:${trLoose('geçici')}|ek)\\s*\$',
          caseSensitive: false,
        ).firstMatch(between)?.group(0)?.trim();
        found.add(
          _read(m, known ?? _numberedLaw(number), article, special: trailing),
        );
      }
    }

    for (final m in _named.allMatches(text)) {
      final law = _lawNamed(m.namedGroup('ad')!);
      if (law == null) continue;
      final n = m.namedGroup('no1') != null ? '1' : '2';
      final article = int.parse(m.namedGroup('no$n')!);
      if (!_valid(article)) continue;
      found.add(_numberInFront(text, _read(m, law, article, n: n)));
    }

    for (final m in _short.allMatches(text)) {
      final written = m.namedGroup('kisa')!;
      final numeric = RegExp(r'^[0-9]').hasMatch(written);
      final dotted = written.contains('.');
      final law = numeric
          ? _byNumber[written]
          : _byAbbreviation[lookupKey(written.replaceAll('.', ''))];
      if (law == null) continue;
      // A short form of two letters, a bare number, or a short form written
      // in small letters is taken only with the word that marks an article:
      // "3 AY 15 GÜN", "12.03.2004 15:30" and "her ay 12" are not citations.
      final marked =
          m.namedGroup('isaret') != null ||
          m.namedGroup('son') != null ||
          m.namedGroup('ozel') != null;
      // "BK'nun 355" — a suffix makes even two letters a name.
      final suffixed = RegExp("^[$_letters.]+['’]").hasMatch(m.group(0)!);
      final asTheTableWrites =
          dotted ||
          written == upperTr(written) ||
          law.abbreviations.contains(written);
      final letters = written.replaceAll('.', '').length;
      if ((numeric || !asTheTableWrites) && !marked) continue;
      if (letters <= 2 && !marked && !(suffixed && asTheTableWrites)) continue;
      final article = int.parse(m.namedGroup('no')!);
      if (!_valid(article)) continue;
      found.add(_numberInFront(text, _read(m, law, article)));
    }

    // The long form contains a short one inside it often enough — 6100 sayılı
    // HMK'nın 119. maddesi is both — so the wider reading wins and the
    // narrower one inside it is dropped.
    final first = _apart(found);

    // "TBK'nın 49, 50 ve 51. maddeleri" is three citations of one law.
    final listed = <Citation>[];
    for (final one in first) {
      var at = one.end;
      while (true) {
        // Always a RegExpMatch, though the signature promises only a Match.
        final divided =
            at == one.end &&
            (one.paragraph != null || one.clause != null || one.letter != null);
        final m = (divided ? _continuedUndashed : _continued).matchAsPrefix(
          text,
          at,
        ) as RegExpMatch?;
        if (m == null) break;
        final article = int.parse(m.namedGroup('no')!);
        if (!_valid(article)) break;
        final start = m.start + m.namedGroup('on')!.length;
        listed.add(
          Citation(
            law: one.law,
            article: article,
            paragraph: int.tryParse(m.namedGroup('fikra') ?? ''),
            clause: m.namedGroup('bent'),
            start: start,
            length: m.end - start,
            written: text.substring(start, m.end),
          ),
        );
        at = m.end;
      }
    }
    final all = _apart([...first, ...listed]);

    // Last, because which law "the same Law" means is known only once the
    // citations before it are.
    final same = <Citation>[];
    for (final m in _same.allMatches(text)) {
      Citation? before;
      for (final one in all.reversed) {
        if (one.end <= m.start) {
          if (m.start - one.end <= _sameReach) before = one;
          break;
        }
      }
      if (before == null) continue;
      final n = m.namedGroup('no1') != null ? '1' : '2';
      final article = int.parse(m.namedGroup('no$n')!);
      if (!_valid(article)) continue;
      same.add(_read(m, before.law, article, n: n));
    }
    return _apart([...all, ...same]);
  }

  /// In the order they appear, the wider of two overlapping readings kept.
  static List<Citation> _apart(List<Citation> found) {
    final sorted = [...found]
      ..sort((a, b) {
        final at = a.start.compareTo(b.start);
        return at != 0 ? at : b.length.compareTo(a.length);
      });
    final kept = <Citation>[];
    var reached = -1;
    for (final one in sorted) {
      if (one.start < reached) continue;
      kept.add(one);
      reached = one.end;
    }
    return kept;
  }
}

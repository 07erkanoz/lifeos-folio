import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'citation.dart' show lookupKey, trLoose;

/// Where a court's decisions are asked for.
enum CaseSource {
  /// Bedesten, the Ministry's case bank, and UYAP Emsal after it.
  bedesten,

  /// The Constitutional Court's own decision bank, which publishes nowhere
  /// else: neither Bedesten nor UYAP Emsal carries a single one.
  constitutional,
}

/// A court, and whether what it decides is published.
@immutable
class Court {
  const Court({
    required this.name,
    required this.published,
    required this.pattern,
    this.source,
    this.kind = '',
    this.chamberLabel,
  });

  final String name;

  /// Whether its decisions are in the official case bank.
  ///
  /// The higher courts publish; a court of first instance does not. This is
  /// not a detail: in a filing, a first instance case number is usually the
  /// writer's own file, and offering to fetch it would be both impossible
  /// and confusing.
  final bool published;

  final RegExp pattern;

  /// Where its decisions are asked for; null for a court that publishes none.
  final CaseSource? source;

  /// Which branch it belongs to — yargitay, danistay, bam, aym — so that a
  /// bank answering with several decisions under the same numbers can be
  /// asked for the one the document meant.
  final String kind;

  /// How one of its chambers is named, with {d} for the number: "Danıştay
  /// {d}. Daire". Null when the number simply goes in front of the name.
  final String? chamberLabel;

  /// The way a chamber's number is written: "15.", "15", "On Beşinci".
  ///
  /// Turkish ordinals, not law: the data file says where a chamber number
  /// stands and this says how Turkish writes one.
  static final String chamberNumber = () {
    final ones = [
      'Birinci',
      'İkinci',
      'Üçüncü',
      'Dördüncü',
      'Beşinci',
      'Altıncı',
      'Yedinci',
      'Sekizinci',
      'Dokuzuncu',
    ].map(trLoose).join('|');
    return '(?:\\d{1,2}\\s*\\.?|(?:(?:On|Yirmi)\\s*)?(?:$ones)|Onuncu|Yirminci)';
  }();

  static Court fromJson(Map<String, Object?> json) => Court(
    name: json['ad'] as String,
    published: json['yayin'] == true,
    pattern: RegExp(
      widenTurkishI(json['kalip'] as String).replaceAll('{no}', chamberNumber),
      caseSensitive: false,
    ),
    source: switch (json['kaynak']) {
      'aym' => CaseSource.constitutional,
      'bedesten' => CaseSource.bedesten,
      _ => json['yayin'] == true ? CaseSource.bedesten : null,
    },
    kind: json['tur'] as String? ?? '',
    chamberLabel: json['etiket'] as String?,
  );
}

/// A decision a document points at.
@immutable
class DecisionCitation {
  const DecisionCitation({
    required this.court,
    required this.esas,
    required this.karar,
    required this.start,
    required this.length,
    this.chamber,
    this.written = '',
    this.courtWritten = '',
    this.application = false,
  });

  /// The court as it was recognised, or null when the writing named none.
  final Court? court;

  /// Which chamber, where the writing said: the 15 of "15. Hukuk Dairesi".
  ///
  /// [Court] names the kind of court, not the one; the number is the only
  /// thing that tells two chambers apart, and it is needed when the bank
  /// answers with more than one decision bearing these case numbers.
  final int? chamber;

  /// "2016/1531" and "2017/3344", as they are written. A General Assembly
  /// writes its esas with the chamber it came from, "2011/7-695", and keeps
  /// that here; the bank files it as 2011/695.
  ///
  /// For an individual application to the Constitutional Court [esas] is
  /// the application number and [karar] is empty.
  final String esas, karar;

  /// An individual application to the Constitutional Court, cited by its
  /// application number: "B. No: 2019/19126".
  final bool application;

  /// The citation as the document wrote it, and the court as it named it.
  final String written, courtWritten;

  /// Counted in UTF-16 code units, the way a Dart string counts.
  final int start, length;

  int get end => start + length;

  /// Only a published court can be fetched. Anything else is left alone.
  bool get fetchable => court?.published ?? false;

  bool get constitutional => court?.source == CaseSource.constitutional;

  /// The chamber as the document declared it: "15. Hukuk Dairesi",
  /// "Danıştay 6. Daire". Empty when no court was written.
  String get courtLabel {
    final named = court;
    if (named == null) return '';
    if (chamber == null) return named.name;
    final label = named.chamberLabel;
    return label == null
        ? '$chamber. ${named.name}'
        : label.replaceAll('{d}', '$chamber');
  }

  /// "E.2016/1531 K.2017/3344", or "B. No: 2019/19126".
  String get numbers => application ? 'B. No: $esas' : 'E.$esas K.$karar';

  String get label {
    final where = numbers;
    final named = courtLabel;
    return named.isEmpty ? where : '$named $where';
  }

  static int _year(String number) => int.parse(number.split('/').first);

  /// The sequence number, without the chamber a General Assembly writes in
  /// front of it: 695 of "2011/7-695".
  static int _sequence(String number) =>
      int.parse(number.split('/').last.split('-').last.trim());

  int get esasYear => _year(esas);
  int get esasNumber => _sequence(esas);
  int get kararYear => _year(karar);
  int get kararNumber => _sequence(karar);

  /// The esas as the bank files it: "2011/695" for "2011/7-695".
  String get bankEsas => '$esasYear/$esasNumber';

  @override
  bool operator ==(Object other) =>
      other is DecisionCitation &&
      other.esas == esas &&
      other.karar == karar &&
      other.start == start &&
      other.length == length &&
      other.chamber == chamber &&
      other.application == application &&
      other.court?.name == court?.name;

  @override
  int get hashCode => Object.hash(
    esas,
    karar,
    start,
    length,
    chamber,
    application,
    court?.name,
  );

  @override
  String toString() => 'DecisionCitation($label @$start+$length)';
}

// -- how the two halves of a citation are written ---------------------------

const _letters = 'A-Za-zÇĞİÖŞÜçğıöşüÂâÎîÛû';

/// A year and a sequence number: 2016/1531, "2019 / 3421", and the General
/// Assembly's 2011/7-695 with the chamber it came from.
const _number = r'(\d{4})\s*/\s*((?:\d{1,2}\s*-\s*)?\d{1,6})';

/// What stands between the halves: punctuation and space only, and at most
/// a "ve". A run of letters there means the sentence moved on and these are
/// two numbers that happen to stand near each other.
const _between = '[^$_letters]{0,25}(?:[vV][eE][^$_letters]{1,5})?';

/// A word as a pattern that finds it in any case, the Turkish way: these
/// patterns keep their case, because a lone E or K has to be a capital.
String _word(String word) {
  final out = StringBuffer();
  for (final rune in word.runes) {
    final char = String.fromCharCode(rune);
    if ('iİıI'.contains(char)) {
      out.write('[iİıI]');
      continue;
    }
    final lower = char.toLowerCase();
    final upper = char.toUpperCase();
    out.write(lower == upper ? RegExp.escape(char) : '[$lower$upper]');
  }
  return out.toString();
}

/// A pattern from the data file with every i-like letter widened to all
/// four, so that a court written in capitals — MAHKEMESİ, DANIŞTAY — is
/// found. Escapes are passed over and a character class is widened inside
/// itself; nothing else about the pattern changes.
@visibleForTesting
String widenTurkishI(String pattern) {
  final out = StringBuffer();
  var inClass = false;
  for (var i = 0; i < pattern.length; i++) {
    final char = pattern[i];
    if (char == r'\' && i + 1 < pattern.length) {
      out
        ..write(char)
        ..write(pattern[++i]);
      continue;
    }
    if (inClass) {
      if (char == ']') inClass = false;
      out.write('iİıI'.contains(char) ? 'iİıI' : char);
      continue;
    }
    if (char == '[') {
      inClass = true;
      out.write(char);
      continue;
    }
    out.write('iİıI'.contains(char) ? '[iİıI]' : char);
  }
  return out.toString();
}

/// The marks that say which half is which, written after the number…
final _esasAfter =
    '(?:E(?![$_letters])[.,:]?|\\(E\\)|${_word('Esas')}(?![$_letters])'
    '(?:\\s*${_word('No')}(?![$_letters]))?[.:]?)';
final _kararAfter =
    '(?:K(?![$_letters])|\\(K\\)|\\.K(?![$_letters])|${_word('Karar')}'
    '|${_word('sayılı')}(?=\\s+${_word('karar')}))';

/// …and before it.
final _label =
    '(?:\\s*(?:${_word('No')}|${_word('Numarası')}|${_word('Sayısı')}))?'
    '\\s*[.:]?\\s*';
final _esasBefore =
    '(?:(?<![${_letters}0-9])E[.,:]?\\s*|(?<![$_letters])${_word('Esas')}$_label)';
final _kararBefore =
    '(?:(?<![${_letters}0-9])K[.,:]?\\s*|(?<![$_letters])${_word('Karar')}$_label)';

/// "2016/1531 E., 2017/3344 K.", "2014/140 Esas, 2015/85 Karar sayılı",
/// "2020/191 (E) ve 2021/961 (K)", "2020/31E. Ve 2021/154K."
final _numberFirst = RegExp(
  '$_number\\s*$_esasAfter$_between$_number\\s*$_kararAfter',
);

/// "E.2025/465 K.2025/7162", "E: 2016/1531 K: 2017/3344", "Esas No: 2019/5535
/// Karar No: 2021/3365", "Esas:2019/2797 Karar:2021/5606" — the mark first.
final _markFirst = RegExp(
  '$_esasBefore$_number'
  '(?:\\s*(?:${_word('Esas')}|E\\.?)(?![$_letters]))?'
  '$_between$_kararBefore$_number',
);

/// "2021/214-2022/398 E-K sayılı", "2022/2678 - 2022/2286 esas karar sayılı"
/// and the bare "2014/140-2015/85 sayılı" — the pair first, the marks after.
final _pairFirst = RegExp(
  '$_number\\s*[-–]\\s*$_number\\s*'
  '(?:E\\s*[-–/]\\s*K\\s*|${_word('esas')}\\s*(?:[vV][eE]\\s+|[-–/]\\s*)?'
  '${_word('karar')}\\s*)?${_word('sayılı')}',
);

/// "B. No: 2019/19126" — an individual application to the Constitutional
/// Court, which is cited by its application number alone. Taken only when
/// the court named nearest before it is that one: the same words head every
/// mediation form in a working archive.
final _application = RegExp(
  '(?<![$_letters])(?:B\\s*\\.\\s*No|${_word('Başvuru')}\\s+(?:No|${_word('Numarası')}))'
  '\\s*[.:]?\\s*(\\d{4})\\s*/\\s*(\\d{1,7})',
);

/// Finds the court decisions a document cites.
///
/// A filing points at a decision by its case numbers — 2016/1531 E.,
/// 2017/3344 K. — and names the court before them. The numbers are written
/// every way there is: with a comma, with a dash, with no space at all
/// before the E. The court is therefore found by looking back from the
/// numbers rather than by writing one pattern for the whole thing.
///
/// Which courts are which is carried in a data file, not here, so the list
/// can be corrected and added to without touching this.
class DecisionScanner {
  DecisionScanner(this.courts);

  final List<Court> courts;

  static Future<DecisionScanner> load({
    String asset = 'assets/mevzuat/courts.json',
  }) async => DecisionScanner.parse(await rootBundle.loadString(asset));

  @visibleForTesting
  static DecisionScanner parse(String raw) {
    final json = jsonDecode(raw) as Map<String, Object?>;
    return DecisionScanner([
      for (final entry in json['mahkemeler'] as List)
        Court.fromJson(entry as Map<String, Object?>),
    ]);
  }

  /// How far back to look for the court that owns these numbers.
  ///
  /// Near first, because the court standing next to the numbers is the one
  /// that decided them. Then as far as the start of the paragraph, because
  /// a filing names a chamber once and then lists what it held: "Yargıtay
  /// 11. Ceza Dairesi … belirtmiş; E.2022/1762 K.2025/14801 … Aynı yönde:
  /// E.2025/532 K.2025/10816". Those later ones are the same court, and
  /// stopping at a fixed distance lost them.
  static const _lookBack = 130;
  static const _lookBackFar = 700;

  /// Every decision cited in [text], in the order they appear.
  List<DecisionCitation> scan(String text) {
    if (text.isEmpty) return const [];
    final out = <DecisionCitation>[];
    bool taken(int from, int to) =>
        out.any((one) => from < one.end && one.start < to);

    for (final pattern in [_numberFirst, _markFirst, _pairFirst]) {
      for (final m in pattern.allMatches(text)) {
        // The readings overlap where a filing writes both halves the same
        // way; the first to claim the ground keeps it.
        if (taken(m.start, m.end)) continue;
        final esas = _tidy(m.group(1)!, m.group(2)!);
        final karar = _tidy(m.group(3)!, m.group(4)!);
        final near = _courtBefore(text, m.start);
        out.add(
          DecisionCitation(
            court: near?.court,
            chamber: near?.chamber,
            courtWritten: near?.written ?? '',
            esas: esas,
            karar: karar,
            start: m.start,
            length: m.end - m.start,
            written: m.group(0)!,
          ),
        );
      }
    }

    for (final m in _application.allMatches(text)) {
      if (taken(m.start, m.end)) continue;
      final near = _courtBefore(text, m.start);
      if (near == null || near.court.source != CaseSource.constitutional) {
        continue;
      }
      out.add(
        DecisionCitation(
          court: near.court,
          courtWritten: near.written,
          esas: '${m.group(1)}/${int.parse(m.group(2)!)}',
          karar: '',
          application: true,
          start: m.start,
          length: m.end - m.start,
          written: m.group(0)!,
        ),
      );
    }

    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  /// "2011 / 7 - 695" as "2011/7-695".
  static String _tidy(String year, String sequence) =>
      '$year/${sequence.replaceAll(RegExp(r'\s+'), '')}';

  /// The court named nearest before [at].
  ///
  /// Nearest, not first in the table: a paragraph can mention several courts
  /// and the one that owns these numbers is the one standing next to them.
  /// Reading in table order instead once put a first instance file under the
  /// Court of Cassation because the sentence had begun by citing a code.
  ({Court court, int? chamber, String written})? _courtBefore(
    String text,
    int at,
  ) {
    if (at <= 0) return null;
    return _courtIn(text, at, _lookBack) ??
        _courtIn(text, at, _lookBackFar, toParagraph: true);
  }

  /// The court named nearest before [at], within [window].
  ///
  /// With [toParagraph] the window is cut short at the last line break, so
  /// the search never reaches into what was said before this paragraph.
  ({Court court, int? chamber, String written})? _courtIn(
    String text,
    int at,
    int window, {
    bool toParagraph = false,
  }) {
    var from = at - window < 0 ? 0 : at - window;
    if (toParagraph) {
      final para = text.lastIndexOf('\n', at - 1);
      if (para > from) from = para;
    }
    if (from >= at) return null;
    final before = text.substring(from, at);
    Court? nearest;
    String? written;
    var end = -1;
    for (final court in courts) {
      for (final hit in court.pattern.allMatches(before)) {
        if (hit.end > end) {
          end = hit.end;
          nearest = court;
          written = hit.group(0);
        }
      }
    }
    if (nearest == null) return null;
    return (
      court: nearest,
      chamber: chamberIn(written ?? ''),
      written: (written ?? '').replaceAll(RegExp(r'\s+'), ' ').trim(),
    );
  }

  /// The chamber number standing in a court's name: "15. Hukuk Dairesi",
  /// "12.HD", "Y.15. CD", "Danıştay Dördüncü Dairesi".
  static int? chamberIn(String written) {
    final digits = RegExp(r'\d{1,2}').firstMatch(written);
    if (digits != null) return int.parse(digits.group(0)!);
    final key = lookupKey(written).replaceAll(' ', '');
    const ones = {
      'BIRINCI': 1,
      'IKINCI': 2,
      'ÜÇÜNCÜ': 3,
      'DÖRDÜNCÜ': 4,
      'BEŞINCI': 5,
      'ALTINCI': 6,
      'YEDINCI': 7,
      'SEKIZINCI': 8,
      'DOKUZUNCU': 9,
    };
    if (key.contains('ONUNCU')) return 10;
    if (key.contains('YIRMINCI')) return 20;
    for (final entry in ones.entries) {
      final at = key.indexOf(entry.key);
      if (at < 0) continue;
      final before = key.substring(0, at);
      if (before.endsWith('YIRMI')) return 20 + entry.value;
      if (before.endsWith('ON')) return 10 + entry.value;
      return entry.value;
    }
    return null;
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'citation.dart';
import 'decision.dart';
import 'decision_sentences.dart';
import 'legal_terms.dart' show lowerTr;
import 'relevance.dart';
import 'turkish_stem.dart';

export 'decision_sentences.dart' show Quote;

/// Which step below the deciding court a court in the heading was.
enum CourtRole {
  firstInstance('İlk derece mahkemesi'),
  appeal('Bölge adliye mahkemesi'),

  /// The chamber of the Court of Cassation whose ruling a court resisted,
  /// in a General Assembly's heading.
  chamber('Özel daire');

  const CourtRole(this.label);

  final String label;
}

/// One court a decision came up through, as its heading names it.
@immutable
class CourtStep {
  const CourtStep({
    required this.role,
    required this.court,
    this.numbers,
    this.date,
    this.result,
  });

  final CourtRole role;

  /// The court as the heading writes it: "Trabzon 2. İş Mahkemesi".
  final Quote court;

  /// "2022/269 E., 2024/87 K." — its line in the heading, as written.
  final Quote? numbers;
  final Quote? date;

  /// What that court decided, where the heading says: "Esastan ret".
  final Quote? result;

  /// The esas and karar this court's decision carries, read from
  /// [numbers]: ("2022/269", "2024/87").
  (String, String)? get filed {
    final written = numbers?.text;
    if (written == null) return null;
    final pairs = RegExp(r'(\d{4})\s*/\s*(\d+)').allMatches(written).toList();
    if (pairs.length < 2) return null;
    return (
      '${pairs[0].group(1)}/${pairs[0].group(2)}',
      '${pairs[1].group(1)}/${pairs[1].group(2)}',
    );
  }
}

/// A part of a decision under its own heading.
@immutable
class DecisionSection {
  const DecisionSection({
    required this.heading,
    required this.level,
    required this.end,
  });

  /// The heading as written: "I. DAVA", "3. Değerlendirme".
  final Quote heading;

  /// 1 for a numbered or capital heading, 2 for a lettered one, 3 below.
  final int level;

  /// Where the part ends: the next heading at its level or above.
  final int end;

  int get start => heading.start;

  /// The heading without its number or closing colon: "DAVA".
  String get title => DecisionAnatomy.bareTitle(heading.text);
}

/// What a decision decided, in the court's own words.
enum OutcomeKind {
  bozma('Bozma'),
  uyusmazlikGiderme('Uyuşmazlığın giderilmesi'),
  gorevsizlik('Görevsizlik'),
  yetkisizlik('Yetkisizlik'),
  geriCevirme('Geri çevirme'),
  duzeltilerekOnama('Düzeltilerek onama'),
  onama('Onama'),
  kaldirma('Kaldırma'),
  esastanRet('Esastan ret'),
  usuldenRet('Usulden ret'),
  kismenKabul('Kısmen kabul'),
  kabul('Kabul'),
  ret('Ret'),
  iptal('İptal'),
  gonderme('Gönderme'),
  temyizReddi('Temyiz isteminin reddi'),
  karariYerOlmadigi('Karar verilmesine yer olmadığı');

  const OutcomeKind(this.label);

  final String label;

  /// Its name in the measurement files: "esastan_ret".
  String get key => name.replaceAllMapped(
    RegExp('[A-Z]'),
    (m) => '_${m.group(0)!.toLowerCase()}',
  );
}

/// One of the verbs of the operative part, and the clause it stands in.
@immutable
class OutcomeVerb {
  const OutcomeVerb(this.kind, this.verb, this.clause);

  final OutcomeKind kind;

  /// The word itself: "BOZULMASINA".
  final Quote verb;

  /// The numbered item or line it closes: "2. İlk Derece Mahkemesi
  /// kararının BOZULMASINA,".
  final Quote clause;
}

/// The operative part and what it says.
@immutable
class DecisionOutcome {
  const DecisionOutcome({required this.region, required this.verbs});

  /// From the heading of the operative part — KARAR, HÜKÜM, SONUÇ, or
  /// "Açıklanan sebeplerle" — to its last line.
  final Quote region;
  final List<OutcomeVerb> verbs;

  /// Every kind said, in the order of [OutcomeKind]: the weightiest first.
  List<OutcomeKind> get kinds =>
      ({for (final verb in verbs) verb.kind}.toList()
        ..sort((a, b) => a.index.compareTo(b.index)));

  /// What the decision came to, by the weightiest thing it said. A
  /// decision that reverses one part and upholds the rest is a reversal;
  /// one that dismisses an appeal and sends the file back is a dismissal.
  OutcomeKind? get primary => kinds.isEmpty ? null : kinds.first;
}

/// A sentence of the reasoning worth a reader's eye, and why.
@immutable
class Highlight {
  const Highlight(this.quote, this.score, this.matched);

  final Quote quote;
  final double score;

  /// Which of the asked-for words it carries.
  final List<String> matched;
}

/// Sentences a great many decisions say word for word.
///
/// A sentence that stands in dozens of unrelated decisions — "Dosyadaki
/// yazılara, kararın dayandığı delillerle gerektirici sebeplere göre…" —
/// is the court's form, not its reasoning in this case, and is never the
/// part a reader should be pointed at. Such sentences are recognised by
/// counting: the same sentence in several decisions decided by different
/// chambers on different questions. The count is made beforehand over a
/// body of decisions apart from the ones measured (see
/// tool/olcum/karar_kaliplari_test.dart), and kept as a set of marks.
class DecisionBoilerplate {
  DecisionBoilerplate(this.keys);

  static final empty = DecisionBoilerplate(const {});

  final Set<String> keys;

  static Future<DecisionBoilerplate> load({
    String asset = 'assets/mevzuat/karar_kaliplari.json',
  }) async {
    try {
      return parse(await rootBundle.loadString(asset));
    } on Object {
      return empty;
    }
  }

  static DecisionBoilerplate parse(String raw) {
    final json = jsonDecode(raw) as Map<String, Object?>;
    return DecisionBoilerplate({
      for (final key in json['anahtarlar'] as List) key as String,
    });
  }

  /// The mark of a sentence: its words in lower case, with figures, the
  /// bank's anonymising ellipsis and punctuation taken out, so that the
  /// same form written for another file and another date marks alike.
  static String keyOf(String sentence) {
    final flat = lowerTr(sentence)
        .replaceAll(RegExp(r'\d+'), '#')
        .replaceAll(RegExp(r'[^a-zçğıöşüâîû#\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (flat.length < 30) return '';
    var hash = 0x811c9dc5;
    for (var i = 0; i < flat.length; i++) {
      hash ^= flat.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16);
  }

  /// The marks of the sentences that stand in at least [inAtLeast] of
  /// [texts], counted once per text.
  static Set<String> repeatedIn(Iterable<String> texts, {int inAtLeast = 3}) {
    final counts = <String, int>{};
    for (final text in texts) {
      final seen = <String>{};
      for (final sentence in DecisionSentences.of(text)) {
        final key = keyOf(sentence.text);
        if (key.isNotEmpty) seen.add(key);
      }
      for (final key in seen) {
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    return {
      for (final entry in counts.entries)
        if (entry.value >= inAtLeast) entry.key,
    };
  }

  bool isStock(String sentence) {
    final key = keyOf(sentence);
    return key.isNotEmpty && keys.contains(key);
  }

  DecisionBoilerplate plus(Set<String> more) =>
      more.isEmpty ? this : DecisionBoilerplate({...keys, ...more});
}

/// What a decision is made of, found by reading its structure.
///
/// Nothing here is written by the app. Every part is a quotation from the
/// decision with its place in it, so that a reader can be taken there and
/// read it in its context. Where a part cannot be found it is left out
/// rather than guessed at: a wrong court or a wrong outcome is worse than
/// none.
///
/// Measured against decisions fetched from Bedesten and read by hand; see
/// test/decision_anatomy_measure_test.dart for the figures.
@immutable
class DecisionAnatomy {
  const DecisionAnatomy({
    this.chain = const [],
    this.subjectHeading,
    this.subject,
    this.outcome,
    this.sections = const [],
    this.laws = const [],
    this.decisions = const [],
    this.highlights = const [],
    this.headerEnd = 0,
  });

  static const none = DecisionAnatomy();

  /// The courts below, as the heading lists them.
  final List<CourtStep> chain;

  /// What the heading calls the case: "DAVA TÜRÜ : Boşanma".
  final Quote? subjectHeading;

  /// The sentence that says what the case is about: "Dava, … ilişkindir."
  final Quote? subject;

  final DecisionOutcome? outcome;
  final List<DecisionSection> sections;

  /// The law the decision cites, and the decisions it cites — not counting
  /// its own heading and the decisions under review.
  final List<Citation> laws;
  final List<DecisionCitation> decisions;

  /// The sentences of the reasoning that stand out, best first.
  final List<Highlight> highlights;

  /// Where the heading ends and the decision proper begins.
  final int headerEnd;

  bool get isEmpty =>
      chain.isEmpty &&
      subjectHeading == null &&
      subject == null &&
      outcome == null &&
      sections.isEmpty &&
      highlights.isEmpty;

  // -- reading it --------------------------------------------------------

  /// Only what the decision decided: the part a list of results shows,
  /// read for every decision on the page each time another text arrives,
  /// so none of the rest is worked out for it.
  static DecisionOutcome? outcomeOf(String text) {
    if (text.trim().isEmpty) return null;
    final lines = _lines(text);
    final header = _header(text, lines);
    return _outcome(
      text,
      lines,
      _sections(text, lines, header.end),
      header.end,
    );
  }

  static DecisionAnatomy of(
    String text, {
    String query = '',
    CitationScanner? laws,
    DecisionScanner? decisions,
    DecisionBoilerplate? boilerplate,
  }) {
    if (text.trim().isEmpty) return none;
    final lines = _lines(text);
    final header = _header(text, lines);
    final sections = _sections(text, lines, header.end);
    final outcome = _outcome(text, lines, sections, header.end);
    final verdictAt = outcome?.region.start ?? text.length;
    final subject = _subject(text, header.end, verdictAt);

    // The decisions under review are this file's. The chamber a General
    // Assembly names is authority, and is cited as such below.
    final reviewed = {
      for (final step in header.chain)
        if (step.role != CourtRole.chamber && step.filed != null) step.filed!,
    };
    final cited = [
      for (final found in decisions?.scan(text) ?? const <DecisionCitation>[])
        if (found.start >= header.end &&
            !reviewed.contains((found.bankEsas, found.karar)) &&
            !reviewed.contains((found.esas, found.karar)) &&
            !_ownHistory(text, found.start, sections, outcome))
          found,
    ];
    final law = [
      for (final found in laws?.scan(text) ?? const <Citation>[])
        if (found.start >= header.end) found,
    ];

    return DecisionAnatomy(
      chain: header.chain,
      subjectHeading: header.subject ?? _claimLine(text, header.end, verdictAt),
      subject: subject,
      outcome: outcome,
      sections: sections,
      laws: law,
      decisions: cited,
      highlights: _highlights(
        text,
        sections,
        header.end,
        verdictAt,
        query,
        boilerplate ?? DecisionBoilerplate.empty,
      ),
      headerEnd: header.end,
    );
  }

  /// Parts that retell the case's own way up — the first instance's
  /// decision, the regional court's, a resistance — whose numbers are this
  /// file's and not authority it relies on. The chamber's own reversal is
  /// left out of this: a General Assembly cites it as authority as well.
  static final _historyTitle = RegExp(
    r'İLK\s+DERECE|BÖLGE\s+ADLİYE\s+MAHKEMESİ\s+KARARI|^İSTİNAF$|DİRENME|^MAHKEME\s+KARARI|BİRLEŞEN',
  );

  /// "İlk Derece Mahkemesinin 12.12.2016 tarihli ve 2013/861 E. …" — a
  /// court named by its rank alone, with no place or number, is this
  /// case's own; a precedent is cited by its name.
  static final _ownCourt = RegExp(
    r'^(?:\d+\s*[.\-]\s*)?(?:İlk\s+Derece\s+Mahkemesi|Bölge\s+Adliye\s+Mahkemesi|Mahkeme|Yerel\s+[Mm]ahkeme|Mahkememiz)(?:nin|sinin|since|ce|nce|’nce|\x27nce)?\s',
  );

  /// How a court below is said to have decided this case: "Erzin Asliye
  /// Hukuk Mahkemesince davanın kabulüne dair verilen, 23.10.2012 tarihli
  /// ve 2011/177 …", and the files merged into it.
  static final _givenBelow = RegExp(
    r'Mahkemesi[’\x27]?n?ce\s+(?:[^.]{0,90}?\s)?verilen|BİRLEŞEN|ASIL\s+DAVA',
  );

  /// "… 2012/105-2014/189 sayılı kararın Yargıtayca incelenmesi …": the
  /// decision under review, said after its numbers.
  static final _reviewedAfter = RegExp(
    r'^[^.\n]{0,40}?sayılı\s+(?:karar|hüküm|hükm)[a-zçğıöşü]*\s+(?:Yargıtayca|temyizen|istinaf)',
  );

  /// The numbers themselves, so that what is said after them can be read.
  static final _citedNumbers = RegExp(
    r'^[\d\s/().\-–]+(?:E\.?|Esas)?[\s,.\-–]*(?:ve\s+)?[\d\s/().\-–]+(?:K\.?|Karar)?',
  );

  static bool _ownHistory(
    String text,
    int at,
    List<DecisionSection> sections,
    DecisionOutcome? outcome,
  ) {
    // The operative part names the decision it upholds or reverses.
    final region = outcome?.region;
    if (region != null && at >= region.start && at < region.end) return true;

    final lineStart = text.lastIndexOf('\n', at - 1) + 1;
    var sentenceStart = lineStart;
    for (final s in DecisionSentences.of(text, lineStart, at)) {
      sentenceStart = s.start;
    }
    // Only what stands nearest before the numbers: "… kararın temyiz
    // edilmesi üzerine Dairenin 14.03.2024 tarihli ve 2024/527 E." cites
    // the chamber's own earlier decision, not the one the sentence began
    // with.
    var lead = text.substring(sentenceStart, at);
    final turn = RegExp(r'üzerine,?|;').allMatches(lead).lastOrNull;
    if (turn != null) lead = lead.substring(turn.end).trimLeft();
    if (lead.length > 150) lead = lead.substring(lead.length - 150);
    if (_ownCourt.hasMatch(lead) || _givenBelow.hasMatch(lead)) return true;
    final after = text.substring(at, (at + 120).clamp(at, text.length));
    if (_reviewedAfter.hasMatch(after.replaceFirst(_citedNumbers, ''))) {
      return true;
    }

    // In the opening of a part that retells the case's history.
    for (final section in sections.reversed) {
      if (section.start > at) continue;
      if (at - section.heading.end > 400) break;
      if (_historyTitle.hasMatch(upperTr(section.title))) return true;
      break;
    }
    return false;
  }

  /// The heading's words alone: "DAVA" of "I. DAVA", "Değerlendirme" of
  /// "3. Değerlendirme", "SONUÇ" of "S O N U Ç:".
  static String bareTitle(String heading) {
    var title = _unspaced(heading.trim());
    title = title.replaceFirst(
      RegExp(r'^(?:[IVX]{1,5}|[A-H]|\d{1,2})\s*[.)\-]\s*'),
      '',
    );
    title = title.replaceFirst(RegExp(r'\s*:.*$'), '');
    return title.trim();
  }

  /// "H Ü K Ü M" as "HÜKÜM". Courts space out a heading's letters for
  /// emphasis; read as written, it is a row of one-letter words.
  static String _unspaced(String line) {
    final spaced = RegExp(r'^[-\s]*((?:[A-ZÇĞİÖŞÜ] ){2,}[A-ZÇĞİÖŞÜ])\s*[-]?')
        .firstMatch(line);
    if (spaced == null) return line;
    return line.replaceRange(
      spaced.start,
      spaced.end,
      spaced.group(1)!.replaceAll(' ', ''),
    );
  }

  // -- lines ---------------------------------------------------------------

  static List<({int start, int end})> _lines(String text) {
    final out = <({int start, int end})>[];
    var at = 0;
    while (at <= text.length) {
      var end = text.indexOf('\n', at);
      if (end < 0) end = text.length;
      out.add((start: at, end: end));
      at = end + 1;
    }
    return out;
  }

  // -- the heading ---------------------------------------------------------

  /// The bank writes its own title before the decision, ending in
  /// "İçtihat Metni" in quotation marks; the decision's heading follows on
  /// the same line.
  static final _bankTitle = RegExp(r'"İçtihat Metni"\s*');

  /// "SAYISI : 2024/1375 E., 2025/1715 K." — a label in capitals and what
  /// follows its colon. The Council of State writes two of its labels in
  /// small letters, "Esas No :", "Karar No :".
  static final _label = RegExp(
    r"^\s*([A-ZÇĞİÖŞÜ][A-ZÇĞİÖŞÜ .()/'’]{1,45}?|Esas No|Karar No)\s*:\s*(.*)$",
  );

  static final _courtWithoutColon = RegExp(r'^\s*(MAHKEMES[İI])\s+([^:\s].*)$');

  static String _labelKey(String label) =>
      upperTr(_unspaced(label)).replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Who the parties and the bench are, and the file's own numbers and
  /// dates: lines of the heading that say nothing about the case, and are
  /// never a part of the decision when they recur below it.
  static final _metaLabel = RegExp(
    r"^(?:\(X+\)\s*)?(?:T\.C\.?|(?:TEMYİZ|İSTİNAF)\s+EDEN(?:LER)?(?:\s*\(|\s+TARAF|$)|KARŞI\s+TARAF(?:\s*\(|$)|(?:BAŞVURAN\s+)?DAVACI(?:LAR)?(?:\s*\(|\s+VEKİL|$)|(?:BAŞVURAN\s+)?DAVALI(?:LAR)?(?:\s*\(|\s+VEKİL|$)|BAŞVURAN|(?:ASIL|BİRLEŞEN|KARŞI)\s+DAVADA$|VEKİL|İHBAR|FER['’]?İ|MÜDAHİL|KATILAN|BAŞKAN|ÜYE|KATİP|ZABIT|HAKİM|HÂKİM|ESAS|KARAR\s+NO|DOSYA|MAHKEMESİ$|SAYISI$|NUMARASI$|DAVANIN\s+KONUSU|DAVA\s+TÜRÜ|İSTEMİN\s+KONUSU|(?:DANIŞTAY\s+)?TETKİK\s+H[AÂ]K[İI]M[İI]$|AV\.)|TARİH",
  );

  /// The court below named in a request to the Council of State: "…
  /// Bölge İdare Mahkemesi … İdari Dava Dairesinin … kararının bozulması".
  static final _administrativeAppeal = RegExp(
    r'(?:(?<![.…\w])[A-ZÇĞİÖŞÜ][a-zçğıöşü]+\s+)?Bölge\s+İdare\s+Mahkemesi[\s.…]*?(?:\d+\.\s*)?(?:İdar[iîe]|Vergi)\s+Dava\s+Daire(?:si)?',
  );

  /// "… Vergi Mahkemesinin … kararına yönelik istinaf başvurusunu…" — the
  /// court of first instance, never the "İdare Mahkemesi" inside a
  /// regional one's name.
  static final _administrativeFirst = RegExp(
    r'(?:(?<![.…\w])[A-ZÇĞİÖŞÜ][a-zçğıöşü]+\s+)?(?:\d+\.\s*)?(?<!Bölge\s)(?:İdare|Vergi)\s+Mahkemesi',
  );

  static ({List<CourtStep> chain, Quote? subject, int end}) _header(
    String text,
    List<({int start, int end})> lines,
  ) {
    final chain = <CourtStep>[];
    Quote? subject;
    var end = 0;

    // Mutable copies of the last step, filled in as its lines arrive.
    CourtRole? role;
    Quote? court, numbers, date, result;
    void close() {
      if (role != null && court != null) {
        chain.add(
          CourtStep(
            role: role!,
            court: court!,
            numbers: numbers,
            date: date,
            result: result,
          ),
        );
      }
      role = null;
      court = numbers = date = result = null;
    }

    final title = _bankTitle.firstMatch(text);
    final bodyFrom = title?.end ?? 0;
    if (title != null) end = title.end;

    var looked = 0;
    // Far enough for a regional court's list of a dozen parties and their
    // lawyers, which comes before anything else.
    for (var i = 0; i < lines.length && looked < 90; i++) {
      var from = lines[i].start;
      final to = lines[i].end;
      if (to <= bodyFrom) continue;
      if (from < bodyFrom) from = bodyFrom;
      looked++;
      final line = text.substring(from, to);
      if (line.trim().isEmpty) continue;
      // A paragraph: the decision itself has begun. The Council of State's
      // request runs long and is still the heading.
      if (line.length > 250 && !line.trimLeft().startsWith('İSTEMİN')) break;
      if (_roman.hasMatch(line.trim())) break;

      final bare = _courtWithoutColon.firstMatch(line);
      final m = bare ?? _label.firstMatch(line);
      if (m == null) {
        // "(İlk Derece sıfatıyla)" under a regional court that tried the
        // case itself.
        if (court != null &&
            RegExp(r'^\s*\(İlk Derece', caseSensitive: false).hasMatch(line)) {
          role = CourtRole.firstInstance;
          end = to;
          continue;
        }
        // The rest of a value broken over two lines: "2022/6558 Esas,
        // 2022/9433 Karar sayılı BOZMA kararı".
        if (court != null &&
            numbers == null &&
            RegExp(r'^\s*\d{4}\s*/').hasMatch(line) &&
            line.length < 160) {
          numbers = Quote.within(text, from, to);
          end = to;
        }
        continue;
      }
      final key = _labelKey(m.group(1)!);
      // The value runs to the end of the line, so it starts where the
      // line's length less its own leaves off.
      final value = Quote.within(text, to - m.group(2)!.length, to);

      switch (key) {
        case 'MAHKEMESİ' || 'İLK DERECE MAHKEMESİ':
          close();
          if (value == null) break;
          role = key.startsWith('İLK')
              ? CourtRole.firstInstance
              : (lowerTr(value.text).contains('bölge adliye')
                    ? CourtRole.appeal
                    : CourtRole.firstInstance);
          court = value;
          end = to;
        case 'ÖZEL DAİRE KARARI' || 'BOZMA KARARI' || 'DAİRE KARARI':
          close();
          if (value == null) break;
          role = CourtRole.chamber;
          court = value;
          end = to;
        case 'SAYISI' || 'NUMARASI' || 'ESAS - KARAR NO' || 'ESAS-KARAR NO':
          if (court != null && value != null) numbers ??= value;
          end = to;
        case 'TARİHİ' || 'TARİH':
          if (court != null && value != null) date ??= value;
          end = to;
        case 'KARAR' || 'HÜKÜM':
          // In the heading only with a value and under a court: "KARAR :
          // Esastan ret". Otherwise it is the decision's own operative part.
          if (value == null || court == null) {
            i = lines.length;
            break;
          }
          result ??= value;
          end = to;
        case 'DAVA' ||
            'DAVA TÜRÜ' ||
            'DAVANIN KONUSU' ||
            'DAVA KONUSU' ||
            'DAVANIN TÜRÜ' ||
            'KONU':
          if (value != null) subject ??= value;
          end = to;
        case 'İSTEMİN KONUSU':
          // The Council of State says here which court's decision it is
          // asked to review; what the case is about comes further down.
          // Both courts may be named, the first instance's decision and the
          // regional court's that upheld it, in the order they are written.
          if (value != null) {
            close();
            final named = <(int, String, CourtRole)>[
              for (final m in _administrativeAppeal.allMatches(value.text))
                (m.start, m.group(0)!, CourtRole.appeal),
            ];
            for (final m in _administrativeFirst.allMatches(value.text)) {
              if (named.any(
                (n) => m.start < n.$1 + n.$2.length && n.$1 < m.end,
              )) {
                continue;
              }
              named.add((m.start, m.group(0)!, CourtRole.firstInstance));
            }
            named.sort((a, b) => a.$1.compareTo(b.$1));
            for (final (at, written, found) in named) {
              role = found;
              court = Quote(written, value.start + at);
              close();
            }
          }
          end = to;
        default:
          if (_metaLabel.hasMatch(key) || key == 'KARAR TARİHİ') {
            if (key == 'KARAR TARİHİ' && court != null && value != null) {
              date ??= value;
            }
            end = to;
            break;
          }
          // A label the heading does not carry is the first part of the
          // decision: "GEREĞİ DÜŞÜNÜLDÜ:", "YARGILAMA SÜRECİ :".
          i = lines.length;
      }
    }
    close();
    return (chain: chain, subject: subject, end: end);
  }

  // -- the parts -----------------------------------------------------------

  /// Headings a decision stands alone on a line in capitals — or spaced
  /// out — that are the title of the document rather than a part of it.
  static const _documentTitles = {
    'T.C.',
    'TÜRKMİLLETİADINA',
    'YARGITAYKARARI',
    'BÖLGEADLİYEMAHKEMESİKARARI',
    'İSTİNAFKARARI',
    'GEREKÇELİKARAR',
    'İNCELENENKARARIN',
    'İÇTİHATMETNİ',
    'HUKUKGENELKURULUKARARI',
    'DANIŞTAY',
  };

  static final _roman = RegExp(r'^([IVX]{1,5})\s*[.)\-]\s*(\S.*)$');
  static final _lettered = RegExp(r'^([A-H])\s*[.)]\s*(\S.*)$');
  static final _numbered = RegExp(r'^(\d{1,2})\s*[.)\-]\s*(\S.*)$');

  /// A heading in capitals with its text after a colon on the same line:
  /// "HÜKÜM:Gerekçeleri yukarıda…", "V. SONUÇ: Davacının…", "TEMYİZ
  /// EDENİN İDDİALARI : …", "S O N U Ç: …". The operative part's heading
  /// may take a slash instead: "HÜKÜM / Ayrıntısı ve gerekçesi…".
  static final _inlineHeading = RegExp(
    r"^((?:[IVX]{1,5}\s*[.)\-]\s*)?)((?:[A-ZÇĞİÖŞÜÂÎÛ] ){2,}[A-ZÇĞİÖŞÜÂÎÛ]|[A-ZÇĞİÖŞÜÂÎÛ][A-ZÇĞİÖŞÜÂÎÛ0-9 '’.…()\-]{2,80}?)\s*(:|/(?=\s*[A-ZÇĞİÖŞÜ][a-zçğıöşü]))",
  );

  /// A dissent's mark before its heading: "(X)KARŞI OY", "(X)-KARŞI OY".
  static final _dissentMark = RegExp(r'^\s*\(X+\)\s*-?\s*');

  /// Words that may stand in lower case inside a title-case heading.
  static const _small = {
    've',
    'ile',
    'ilişkin',
    'ait',
    'dair',
    'yönünden',
    'hakkında',
    'olarak',
    'göre',
    'ilgili',
  };

  static bool _mostlyCapitals(String value) {
    final letters = value.replaceAll(
      RegExp(r'[^A-Za-zÇĞİÖŞÜçğıöşüÂâÎîÛû]'),
      '',
    );
    if (letters.length < 3) return false;
    final capitals = letters.replaceAll(RegExp(r'[a-zçğıöşüâîû]'), '');
    return capitals.length / letters.length >= 0.85;
  }

  static bool _titleCase(String value) {
    final words = value.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.length > 7) return false;
    var capitals = 0;
    for (final word in words) {
      final first = word.replaceAll(RegExp(r'^[("“]'), '');
      if (first.isEmpty) continue;
      if (RegExp(r'^[A-ZÇĞİÖŞÜ]').hasMatch(first)) {
        capitals++;
      } else if (!_small.contains(lowerTr(first))) {
        return false;
      }
    }
    return capitals >= 1 && RegExp(r'^[A-ZÇĞİÖŞÜ]').hasMatch(words.first);
  }

  /// The heading on [line], if it is one: where it starts within the line,
  /// its level and how far it runs.
  static ({int skip, int level, int length})? _headingOn(String line) {
    final mark = _dissentMark.firstMatch(line);
    final skip = mark?.end ?? 0;
    final rest = line.substring(skip);
    final trimmed = rest.trimRight();
    if (trimmed.isEmpty) return null;

    final inline = _inlineHeading.firstMatch(trimmed);
    if (inline != null) {
      final label = _labelKey(inline.group(2)!);
      final slash = inline.group(3) == '/';
      final value = trimmed.substring(inline.end).trim();
      if (_mostlyCapitals(label) &&
          !_metaLabel.hasMatch(label) &&
          (!slash || _outcomeHeadings.contains(label)) &&
          // "DAVALI : X Ltd. Şti." in a party list, written below the
          // heading, is still not a part of the decision.
          !(value.isNotEmpty && value.length < 60 && _mostlyCapitals(value))) {
        final length = slash
            ? inline.group(1)!.length + inline.group(2)!.length
            : inline.end;
        return (skip: skip, level: 1, length: length);
      }
    }
    if (trimmed.length > 110) return null;

    final roman = _roman.firstMatch(trimmed);
    if (roman != null) {
      final head = roman.group(2)!;
      if (_mostlyCapitals(head) && head.length <= 70) {
        return (skip: skip, level: 1, length: trimmed.length);
      }
      return null;
    }

    final lettered = _lettered.firstMatch(trimmed);
    if (lettered != null) {
      final head = lettered.group(2)!.replaceFirst(RegExp(r':\s*$'), '');
      if (!RegExp(r'[.,;]$').hasMatch(head) &&
          head.length <= 80 &&
          (_titleCase(head) || _mostlyCapitals(head))) {
        return (skip: skip, level: 2, length: trimmed.length);
      }
      return null;
    }

    final numbered = _numbered.firstMatch(trimmed);
    if (numbered != null) {
      final head = numbered.group(2)!.replaceFirst(RegExp(r':\s*$'), '');
      if (head.length <= 60 &&
          !RegExp(r'[.,;]$').hasMatch(head) &&
          _titleCase(head) &&
          !RegExp(r'[A-ZÇĞİÖŞÜ]{4,}(?:MASINA|MESİNE|NE|NA)\b').hasMatch(head)) {
        return (skip: skip, level: 3, length: trimmed.length);
      }
      return null;
    }

    // A title in dashes, "-K A R A R-", or in brackets is the document's
    // own, not one of its parts.
    if (RegExp(r'^\s*[-(]').hasMatch(trimmed)) return null;
    final head = _unspaced(trimmed).replaceFirst(RegExp(r'\s*:\s*$'), '');
    if (_documentTitles.contains(head.replaceAll(RegExp(r'[\s\-]'), ''))) {
      return null;
    }
    if (_mostlyCapitals(head) &&
        head.length <= 70 &&
        !_metaLabel.hasMatch(_labelKey(head.split(':').first)) &&
        !head.contains(RegExp(r'\d{4}'))) {
      // "YETKİLİ YARGI YERİNİN BELİRLENMESİ KARARI", "HUKUK GENEL KURULU
      // KARARI": what kind of decision this is, said once above it.
      if (RegExp(r'KARARI$').hasMatch(head.trim())) return null;
      // "KARŞI OY (X)": the mark after the heading is not part of it.
      final marked = RegExp(r'\s*\(X+\)\s*$').firstMatch(trimmed);
      return (skip: skip, level: 1, length: marked?.start ?? trimmed.length);
    }
    // "Davacı İstemi", "Ön Sorun" — a short title alone on its line.
    // The bench signing at the foot of the page is not one.
    if (_titleCase(head) &&
        head.split(' ').length <= 5 &&
        !RegExp(r'[.,;]$').hasMatch(head) &&
        !RegExp(
          r'^(?:Başkan|Üye|Katip|Kâtip|Zabıt|Hakim|Hâkim|Tetkik|Bilirkişi)\b',
        ).hasMatch(head)) {
      return (skip: skip, level: 2, length: trimmed.length);
    }
    return null;
  }

  static List<DecisionSection> _sections(
    String text,
    List<({int start, int end})> lines,
    int from,
  ) {
    final found = <(Quote, int)>[];
    for (final line in lines) {
      if (line.end <= from) continue;
      final start = line.start < from ? from : line.start;
      final heading = _headingOn(text.substring(start, line.end));
      if (heading == null) continue;
      final at = start + heading.skip;
      final quote = Quote.within(text, at, at + heading.length);
      if (quote == null) continue;
      found.add((quote, heading.level));
    }
    return [
      for (var i = 0; i < found.length; i++)
        DecisionSection(
          heading: found[i].$1,
          level: found[i].$2,
          end: () {
            for (var j = i + 1; j < found.length; j++) {
              if (found[j].$2 <= found[i].$2) return found[j].$1.start;
            }
            return text.length;
          }(),
        ),
    ];
  }

  // -- the operative part --------------------------------------------------

  static const _outcomeHeadings = {
    'KARAR',
    'HÜKÜM',
    'SONUÇ',
    'KARAR SONUCU',
    'HÜKÜM SONUCU',
    'SONUÇ VE KARAR',
  };

  /// "Açıklanan sebeplerle;" — how the operative part begins where it has
  /// no heading of its own.
  static final _operativeLead = RegExp(
    r'^\s*(?:\d+\s*[.\-]\s*)?(?:Yukarıda\s+)?(?:Açıklanan|açıklanan|Gerekçe(?:si|leri)?\s+yukarıda\s+açıklandığı)\s*(?:sebep|neden|gerekçe|üzere)',
  );

  /// A dissent, written after the decision and not part of it.
  static final _dissent = RegExp(
    r'^\s*(?:\(X+\)\s*-?\s*)?(?:KARŞI\s*OY|MUHALEFET\s*ŞERHİ|K\s*A\s*R\s*Ş\s*I\s*O\s*Y|AZLIK\s*OYU|Karşı\s*Oy\s*Yazısı)',
  );

  /// The line a short decision closes on, where it has neither a heading
  /// for its operative part nor a phrase that opens one.
  static final _decided = RegExp(r'karar\s+veril(?:di|miştir)');

  static DecisionOutcome? _outcome(
    String text,
    List<({int start, int end})> lines,
    List<DecisionSection> sections,
    int headerEnd,
  ) {
    var end = text.length;
    for (final line in lines) {
      if (line.start < headerEnd) continue;
      if (_dissent.hasMatch(text.substring(line.start, line.end))) {
        end = line.start;
        break;
      }
    }

    var start = -1;
    for (final section in sections.reversed) {
      if (section.start >= end) continue;
      if (_outcomeHeadings.contains(upperTr(section.title))) {
        start = section.start;
        break;
      }
    }
    if (start < 0) {
      for (final line in lines.reversed) {
        if (line.start < headerEnd) break;
        if (line.start >= end) continue;
        if (_operativeLead.hasMatch(text.substring(line.start, line.end))) {
          start = line.start;
          break;
        }
      }
    }
    if (start < 0) {
      for (final line in lines.reversed) {
        if (line.start < headerEnd) break;
        if (line.start >= end) continue;
        if (_decided.hasMatch(text.substring(line.start, line.end))) {
          start = line.start;
          break;
        }
      }
    }
    if (start < 0) return null;

    final region = Quote.within(text, start, end);
    if (region == null) return null;
    return DecisionOutcome(region: region, verbs: _verbs(text, start, end));
  }

  /// The verbs of an operative part, in the order they are tried: where
  /// two readings claim the same words, the earlier keeps them.
  ///
  /// Read only inside the operative part. Searching the whole decision for
  /// "reddine" called a General Assembly's order to return a file a
  /// dismissal, because the decision quoted a lower court that had
  /// dismissed something.
  static final List<(OutcomeKind, RegExp)> _verbPatterns = [
    (
      OutcomeKind.duzeltilerekOnama,
      RegExp(r'DÜZELTİLEREK\s+ONANMASINA|düzeltilerek\s+onanmasına'),
    ),
    (OutcomeKind.onama, RegExp(r'ONANMASINA|onanmasına')),
    (OutcomeKind.bozma, RegExp(r'BOZULMASINA|bozulmasına')),
    (
      OutcomeKind.kaldirma,
      RegExp(
        r'(?:ORTADAN\s+)?KALDIRILMASINA|(?:kararının|kararın|hükmünün|hükmün)\s+(?:[^,;\n]{0,90}?\s)?(?:ortadan\s+)?kaldırılmasına',
      ),
    ),
    (
      OutcomeKind.gorevsizlik,
      RegExp(
        r'GÖREVSİZLİ[ĞK]|görevsizli[ğk]|görev\s+yönünden\s+(?:usulden\s+)?(?:REDDİNE|reddine)|GÖREV\s+YÖNÜNDEN\s+(?:USULDEN\s+)?REDDİNE',
      ),
    ),
    (
      OutcomeKind.yetkisizlik,
      RegExp(
        r'YETKİSİZLİ[ĞK]|yetkisizli[ğk]|yetki\s+yönünden\s+(?:usulden\s+)?(?:REDDİNE|reddine)',
      ),
    ),
    (
      OutcomeKind.esastanRet,
      RegExp(r'esastan\s+(?:REDDİNE|reddine)|ESASTAN\s+REDDİNE'),
    ),
    (
      OutcomeKind.usuldenRet,
      RegExp(r'usulden\s+(?:REDDİNE|reddine)|USULDEN\s+REDDİNE'),
    ),
    (
      OutcomeKind.geriCevirme,
      RegExp(r'GERİ\s+ÇEVRİLMESİNE|geri\s+çevrilmesine'),
    ),
    (
      OutcomeKind.uyusmazlikGiderme,
      RegExp(r'uyuşmazlığın[^\n]{0,800}?giderilmesine'),
    ),
    (
      OutcomeKind.gonderme,
      RegExp(
        r'GÖNDERİLMESİNE|(?:[Mm]ahkemesine|MAHKEMESİNE|[Dd]airesine|DAİRESİNE)\s+İADESİNE',
      ),
    ),
    (
      OutcomeKind.kismenKabul,
      RegExp(
        r'[Kk]ısmen\s+(?:KABULÜNE|kabulüne|kabulü\s+ile)|KISMEN\s+KABULÜNE',
      ),
    ),
    (OutcomeKind.kabul, RegExp(r'KABULÜNE|kabulüne|kabulü\s+ile')),
    (OutcomeKind.ret, RegExp(r'REDDİNE|reddine')),
    (OutcomeKind.iptal, RegExp(r'İPTALİNE|iptaline')),
    (
      OutcomeKind.karariYerOlmadigi,
      RegExp(
        r'konusuz\s+kal[^,;\n]{0,160}?(?:karar\s+verilmesine\s+yer\s+olmadığına|KARAR\s+VERİLMESİNE\s+YER\s+OLMADIĞINA)',
      ),
    ),
  ];

  /// An appeal, as against the claim: "istinaf başvurusunun", "temyiz
  /// isteminin", "temyiz dilekçesinin".
  static final _appeal = RegExp(
    r'(istinaf|temyiz)\s+(başvuru|istem|isteğ|dilekçe|itiraz|tale[pb]|kanun\s+yolu)',
  );

  /// The claim itself: "davanın", "asıl davanın", "istemin", "talebin".
  static final _claimWord = RegExp(
    r'(dava|istem|tale[pb]|itiraz|şikayet|şikâyet|başvuru)[a-zçğıöşü]*\s*[^,;]{0,80}$',
  );

  /// What a "kabulüne" or a "reddine" is about decides what it means: the
  /// claim's is the outcome, an appeal's or a petition's is not.
  static OutcomeKind? _acceptOrRefuse(OutcomeKind kind, String before) {
    final near = lowerTr(before);
    if (_appeal.hasMatch(near)) {
      // The petition refused — "temyiz dilekçesinin miktardan reddine" —
      // is an outcome of its own. The Council of State's "temyiz isteminin
      // reddine" is the merits of the appeal refused, which its upholding
      // or reversing already says.
      if (kind == OutcomeKind.ret &&
          RegExp(r'temyiz\s+dilekçe').hasMatch(near)) {
        return OutcomeKind.temyizReddi;
      }
      return null;
    }
    return _claimWord.hasMatch(near) ? kind : null;
  }

  static List<OutcomeVerb> _verbs(String text, int from, int to) {
    final region = text.substring(from, to);
    final out = <OutcomeVerb>[];
    final taken = <(int, int)>[];
    bool overlaps(int a, int b) => taken.any((t) => a < t.$2 && t.$1 < b);

    for (final (kind, pattern) in _verbPatterns) {
      for (final m in pattern.allMatches(region)) {
        if (overlaps(m.start, m.end)) continue;
        final clause = _clauseAround(region, m.start, m.end);
        final before = region.substring(clause.$1, m.start);
        final after = region.substring(m.end);
        // "…esastan reddine ilişkin Bölge Adliye Mahkemesi kararının
        // ORTADAN KALDIRILMASINA" — a verb that names the decision under
        // review rather than deciding anything.
        if (RegExp(r'^\s*(?:ilişkin|dair|yönelik)\b').hasMatch(after)) {
          continue;
        }
        var found = kind;
        switch (kind) {
          case OutcomeKind.kabul || OutcomeKind.kismenKabul || OutcomeKind.ret:
            final read = _acceptOrRefuse(kind, before);
            if (read == null) continue;
            found = read;
          case OutcomeKind.esastanRet || OutcomeKind.usuldenRet:
            // Only an appeal is dismissed on the merits or on procedure;
            // a court of first instance dismissing a claim on procedure
            // has dismissed the claim.
            if (!_appeal.hasMatch(lowerTr(before)) &&
                !RegExp(r'başvuru', caseSensitive: false).hasMatch(before)) {
              if (!_claimWord.hasMatch(lowerTr(before))) continue;
              found = OutcomeKind.ret;
            }
          case OutcomeKind.iptal:
            if (!RegExp(r'işlem|karar|yönetmelik|tebliğ|ihale|tapu|kayd')
                .hasMatch(lowerTr(before))) {
              continue;
            }
          default:
            break;
        }
        taken.add((m.start, m.end));
        out.add(
          OutcomeVerb(
            found,
            Quote(m.group(0)!, from + m.start),
            Quote.within(text, from + clause.$1, from + clause.$2) ??
                Quote(m.group(0)!, from + m.start),
          ),
        );
      }
    }
    out.sort((a, b) => a.verb.start.compareTo(b.verb.start));
    return out;
  }

  /// The numbered item or line a verb closes: back to the line start or
  /// the last "2-" or "3." that opens an item, on to the comma after it.
  static (int, int) _clauseAround(String region, int start, int end) {
    final lineFrom = region.lastIndexOf('\n', start) + 1;
    var from = lineFrom;
    // The item nearest before the verb, not the first on the line.
    final item = RegExp(r'(?:^|[,;]\s*)(\d{1,2}\s*[-.)]\s*)(?=\D)');
    for (final m in item.allMatches(region.substring(lineFrom, start))) {
      from = lineFrom + m.end - m.group(1)!.length;
    }
    var to = region.indexOf('\n', end);
    if (to < 0) to = region.length;
    final comma = RegExp(r'[,;]').firstMatch(region.substring(end, to));
    if (comma != null) to = end + comma.end;
    return (from, to);
  }

  // -- what the case is about ----------------------------------------------

  /// "Dava, … ilişkindir." — the sentence a decision says what the case is
  /// about in. It may follow a paragraph number or the heading of its part
  /// on the same line, "GEREKÇE:Dava, …", which are left out of the quote.
  /// "Dava konusu istem: …" is the Council of State's label, not this.
  static final _subjectSentence = RegExp(
    r'^(?:\d+\s*[.\-]\s*|[A-ZÇĞİÖŞÜ][A-ZÇĞİÖŞÜ ]{2,40}:\s*)?(Dava|Eldeki dava|Uyuşmazlık|Somut uyuşmazlık|Temyize konu uyuşmazlık|İstem|Talep)(?!\s+[Kk]onusu)\s*[,;]?\s+.{5,900}?(?:ilişkindir|ilişkin olup|istemlidir|ibarettir|konusudur|talebidir|istemidir)\b',
    dotAll: true,
  );

  /// "Taraflar arasındaki kira bedelinin tespiti davasından dolayı" — what
  /// an older decision opens with instead. "Taraflar arasında görülen
  /// davada" names nothing, and is passed over.
  static final _betweenParties = RegExp(
    r'Taraflar\s+arasında(?:ki)?\s+(?!görülen\s+dava)(?:görülen\s+)?[“"]?\s*(.{4,160}?)\s*[”"]?\s*(?:davasından|davasının|davası\b|istemine\s+ilişkin|davada)',
  );

  /// "Dava konusu istem: …" — what the case is about, in the Council of
  /// State's words, written below its heading.
  static final _claim = RegExp(r'^\s*Dava\s+[Kk]onusu\s+[İi]stem\s*:\s*(.+)$');

  static Quote? _claimLine(String text, int from, int to) {
    for (final line in _lines(text)) {
      if (line.end <= from) continue;
      if (line.start >= to) break;
      final m = _claim.firstMatch(text.substring(line.start, line.end));
      if (m == null) continue;
      return Quote.within(text, line.end - m.group(1)!.length, line.end);
    }
    return null;
  }

  static Quote? _subject(String text, int from, int to) {
    Quote? uyusmazlik;
    for (final sentence in DecisionSentences.of(text, from, to)) {
      final m = _subjectSentence.firstMatch(sentence.text);
      if (m == null) continue;
      final at = sentence.start + m.group(0)!.indexOf(m.group(1)!);
      final quote = Quote.within(text, at, sentence.end) ?? sentence;
      if (m.group(1) == 'Dava' || m.group(1) == 'Eldeki dava') return quote;
      uyusmazlik ??= quote;
    }
    if (uyusmazlik != null) return uyusmazlik;
    final parties = _betweenParties.firstMatch(text.substring(from, to));
    if (parties != null) {
      final name = parties.group(1)!;
      final at = from + parties.start + parties.group(0)!.indexOf(name);
      return Quote.within(text, at, at + name.length);
    }
    return null;
  }

  // -- what stands out -------------------------------------------------------

  /// Where the court gives its own reasons, as opposed to what the parties
  /// said and what the court below did.
  static final _reasoningTitle = RegExp(
    r'değerlendirme|gerekçe|inceleme|hukuki\s+nitelendirme|uyuşmazlık',
    caseSensitive: false,
  );

  static final _notReasoning = RegExp(
    r'temyiz\s+sebep|istinaf\s+sebep|iddia|savunma|cevap|istem|talep|başvuru\s+sebep|özeti|ilgili\s+hukuk',
    caseSensitive: false,
  );

  static (int, int) _reasoningRegion(
    String text,
    List<DecisionSection> sections,
    int headerEnd,
    int verdictAt,
  ) {
    DecisionSection? best;
    for (final section in sections) {
      if (section.start >= verdictAt) break;
      final title = lowerTr(section.title);
      if (!_reasoningTitle.hasMatch(title) || _notReasoning.hasMatch(title)) {
        continue;
      }
      // The deepest, and of equals the last: "3. Değerlendirme" inside
      // "VI. GEREKÇE" is the court's own reasons; the rest of the part is
      // the law it set out first.
      if (best == null ||
          section.level >= best.level ||
          section.start > best.end) {
        best = section;
      }
    }
    if (best != null) {
      final end = best.end < verdictAt ? best.end : verdictAt;
      if (end - best.heading.end > 200) return (best.heading.end, end);
    }
    return (_reasonsBegin(text, headerEnd, verdictAt), verdictAt);
  }

  /// "-KARAR-", "Y A R G I T A Y K A R A R I", "… gereği düşünüldü:": the
  /// line after which an older decision, without parts, turns from what
  /// the parties and the court below said to its own reasons.
  static final _turnToReasons = RegExp(
    r'Y\s*A\s*R\s*G\s*I\s*T\s*A\s*Y\s+K\s*A\s*R\s*A\s*R\s*I|^\s*-?\s*K\s*A\s*R\s*A\s*R\s*-?\s*$|gereği\s+(?:görüşülüp\s+|konuşulup\s+)?düşünüldü\s*[:.]?|GEREĞİ\s+DÜŞÜNÜLDÜ\s*:?',
    multiLine: true,
  );

  /// Where an older decision's reasons begin: after the last turn to them
  /// before the operative part, or, with none, where the decision begins.
  ///
  /// Taking the latter part of the text instead, as this once did, lost
  /// the reasons of every short decision whose reasons came early: in two
  /// of the Court of Cassation's older decisions it found no sentence at
  /// all.
  static int _reasonsBegin(String text, int headerEnd, int verdictAt) {
    if (verdictAt <= headerEnd) return headerEnd;
    var begin = headerEnd;
    for (final m in _turnToReasons.allMatches(
      text.substring(headerEnd, verdictAt),
    )) {
      begin = headerEnd + m.end;
    }
    return begin;
  }

  /// What a court writes when it is giving the law, rather than retelling.
  static final _reasonCues = RegExp(
    // The last of these are how a court opens a statement of the law,
    // "Bilindiği üzere", "Öncelikle belirtelim ki", and how it says what
    // will hold, "… ayrı ayrı belirlenecektir".
    r'gerek(?:ir|mektedir|mekte|ecektir|li)|zorunlu|esastır|şarttır|mümkün\s+(?:değildir|olmaz|değil)|kabul\s+edilmelidir|hükme\s+bağlan|düzenlen(?:miştir|mektedir)|kural\s+olarak|ilke(?:si)?\s+olarak|ilkesi|kararlılık\s+kazanmış|yerleşik|uygulaması\s+bu\s+doğrultudadır|hukuk\s+genel\s+kurulu|içtihad|takdirde|h[aâ]linde|bu\s+itibarla|o\s+h[aâ]lde|nitekim|ancak|bilindiği\s+(?:üzere|gibi)|belirt(?:elim|mek\s+gerekir)|vurgulamak\s+gerekir|(?:ecek|acak)t[iı]r\b',
    caseSensitive: false,
  );

  /// The court telling what someone else said or did, which is never the
  /// part to point a reader at.
  static final _retelling = RegExp(
    r'(?:istemiştir|talep\s+etmiştir|savunmuştur|ileri\s+sürmüştür|beyan\s+etmiştir|karar\s+verilmiştir|temyiz\s+edilmiştir|istinaf\s+edilmiştir|bildirmiştir|açıklamıştır)\s*[.:]?\s*$',
  );

  /// A party speaking — "Davacı vekili beyan dilekçesinde; …" — or the
  /// operative part beginning, neither of which is the court's reasoning.
  static final _notReasons = RegExp(
    r'^(?:\d{1,2}\s*[.\-)]\s*)?(?:(?:Davacı|Davalı|Davacılar|Davalılar|Katılan|Başvurucu)(?:\s+\S+){0,4}?\s+(?:dilekçe(?:si|leri)?(?:nde|yle|siyle)|cevabında|cevap\s+dilekçesinde|beyanında|savunmasında)|(?:Yukarıda\s+)?Açıklanan\s+(?:sebep|neden))',
  );

  /// Where the court turns from the law to the case before it: what a
  /// lawyer most often quotes, since it says how the rule was applied.
  static final _applying = RegExp(
    r'^(?:\d{1,2}\s*[.\-)]\s*)?(?:Bu\s+durumda|Bu\s+itibarla|O\s+h[aâ]lde|H[aâ]l\s+böyle\s+olunca|Sonuç\s+itibar[ıi]yla|Buna\s+göre|Bu\s+nedenle|Somut\s+(?:olayda|uyuşmazlıkta)|Eldeki\s+davada|Bu\s+açıklamalar)',
  );

  static List<Highlight> _highlights(
    String text,
    List<DecisionSection> sections,
    int headerEnd,
    int verdictAt,
    String query,
    DecisionBoilerplate boilerplate,
  ) {
    final (from, to) = _reasoningRegion(text, sections, headerEnd, verdictAt);
    final found = _scored(text, sections, from, to, query, boilerplate);
    if (found.isNotEmpty) return found;
    // The part a heading named held nothing to show — a decision that gave
    // its reasons before setting out the parties' — so the whole of it is
    // read instead.
    final begin = _reasonsBegin(text, headerEnd, verdictAt);
    if (begin >= from && verdictAt <= to) return found;
    return _scored(text, sections, begin, verdictAt, query, boilerplate);
  }

  /// "Dava, … davasıdır", "Asıl ve birleşen davalar yönünden dava; …" —
  /// what the case is about, said again, which is shown as that already.
  static final _restatesSubject = RegExp(
    r'^(?:\d{1,2}\s*[.\-)]\s*)?(?:(?:(?:Asıl|Birleşen|Karşı)\s+)?(?:ve\s+birleşen\s+)?(?:davalar?\s+yönünden\s+)?[Dd]ava|(?:Somut\s+)?[Uu]yuşmazlık)\s*[,;]',
  );

  /// A statute set out in its own words — "… başlıklı 36. maddesinde ise;
  /// “…”" — which the reader can open from the citation; the court's own
  /// sentence about it is the one worth pointing at.
  static final _recitesStatute = RegExp(r'başlıklı\s+\d|[“"][^”"]{80,}[”"]');

  static List<Highlight> _scored(
    String text,
    List<DecisionSection> sections,
    int from,
    int to,
    String query,
    DecisionBoilerplate boilerplate,
  ) {
    if (to - from < 40) return const [];
    final wanted = {
      for (final term in Relevances.termsIn(query)) TurkishStem.of(term): term,
    };
    final headings = {for (final s in sections) s.heading.start};

    final scored = <Highlight>[];
    for (final sentence in DecisionSentences.of(text, from, to)) {
      final s = sentence.text;
      if (headings.contains(sentence.start)) continue;
      // A regional court or a court of first instance often gives its whole
      // reasoning as one sentence of a thousand characters and more; those
      // are kept, and made to compete harder below.
      if (s.length < 70 || s.length > 2400) continue;
      // Whole: closed by its stop, or the paragraph's own last words — a
      // court of first instance often ends its reasoning "… aşağıdaki
      // şekilde hüküm kuruldu" with nothing after.
      final endsLine =
          sentence.end >= text.length || text[sentence.end] == '\n';
      if (!RegExp(r'[.!?;:]["”’)]?$').hasMatch(s) && !endsLine) continue;
      if (boilerplate.isStock(s)) continue;
      if (_retelling.hasMatch(s)) continue;
      if (_notReasons.hasMatch(s)) continue;
      // "Dava, … ilişkindir." is shown as what the case is about already.
      if (_subjectSentence.hasMatch(s) || _restatesSubject.hasMatch(s)) {
        continue;
      }
      // A sentence that begins mid-way — after a cut, a quotation or a
      // list marker the splitter kept — is not shown as if it were whole.
      final opening = s.replaceFirst(
        RegExp(r'^(?:\d{1,2}\s*[.\-)]\s*|[(“"])'),
        '',
      );
      if (opening.isEmpty || !RegExp(r'^[A-ZÇĞİÖŞÜ0-9]').hasMatch(opening)) {
        continue;
      }

      var score = 0.0;
      final lower = lowerTr(s);
      final matched = <String>[];
      if (wanted.isNotEmpty) {
        final stems = <String, int>{};
        for (final w in RegExp(r'[a-zçğıöşü0-9]+').allMatches(lower)) {
          final stem = TurkishStem.of(w.group(0)!);
          stems[stem] = (stems[stem] ?? 0) + 1;
        }
        for (final entry in wanted.entries) {
          final n = stems[entry.key] ?? 0;
          if (n == 0) continue;
          matched.add(entry.value);
          score += 6 + (n > 1 ? 2 : 0);
        }
        if (matched.length == wanted.length && wanted.length > 1) score += 4;
      }
      final cues = _reasonCues.allMatches(s).length;
      score += (cues * 5).clamp(0, 15).toDouble();
      if (_applying.hasMatch(s)) score += 3;

      // Figures belong to the case; a statement of the law has few.
      final figures = RegExp(r'\d+[.,/]\d+').allMatches(s).length;
      if (figures > 2) score -= (figures - 2) * 2.0;
      // Dates and sums are the facts of this file.
      score -=
          2.0 *
          RegExp(r'\b\d{1,2}[./]\d{1,2}[./]\d{2,4}\b|\bTL\b|₺')
              .allMatches(s)
              .length;
      if (s.contains('...') || s.contains('…')) score -= 2;
      if (s.length > 550) score -= 3;
      if (s.length > 900) score -= 3;
      if (_recitesStatute.hasMatch(s)) score -= 5;
      if (score <= 4) continue;
      scored.add(Highlight(sentence, score, matched));
    }
    scored.sort((a, b) {
      final by = b.score.compareTo(a.score);
      return by != 0 ? by : a.quote.start.compareTo(b.quote.start);
    });
    return scored.take(3).toList();
  }
}

/// Reads a decision's anatomy with the tables the app ships — the laws,
/// the courts and the stock sentences — each loaded once and kept.
class DecisionAnatomist {
  const DecisionAnatomist._();

  static Future<
    ({
      CitationScanner? laws,
      DecisionScanner? courts,
      DecisionBoilerplate stock,
    })
  >?
  _tables;

  static Future<T?> _orNull<T>(Future<T> Function() load) async {
    try {
      return await load();
    } on Object {
      // A table that cannot be read leaves its part of the anatomy empty;
      // it does not keep the rest from being shown.
      return null;
    }
  }

  static Future<DecisionAnatomy> read(String text, {String query = ''}) async {
    final tables = await (_tables ??= () async {
      final laws = _orNull(CitationScanner.load);
      final courts = _orNull(DecisionScanner.load);
      final stock = DecisionBoilerplate.load();
      return (laws: await laws, courts: await courts, stock: await stock);
    }());
    return DecisionAnatomy.of(
      text,
      query: query,
      laws: tables.laws,
      decisions: tables.courts,
      boilerplate: tables.stock,
    );
  }
}

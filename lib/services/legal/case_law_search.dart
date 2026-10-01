import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'constitutional_court.dart';
import 'relevance.dart';
import 'rich_text.dart' show decisionReference;

/// Which bench a search looks through.
enum CourtKind {
  yargitay('YARGITAYKARARI', 'Yargıtay'),
  istinaf('ISTINAFHUKUK', 'Bölge Adliye'),
  danistay('DANISTAYKARAR', 'Danıştay'),
  yerel('YERELHUKUK', 'Yerel mahkeme'),
  kanunYarari('KYB', 'Kanun yararına bozma'),

  /// The Constitutional Court publishes in its own bank, which is searched
  /// on its own: it cannot be asked together with the others.
  aymNorm('NormDenetimi', 'AYM norm denetimi'),
  aymBireysel('BireyselBasvuru', 'AYM bireysel başvuru');

  const CourtKind(this.code, this.label);

  final String code;
  final String label;

  /// The Constitutional Court's bank this kind is, or null for Bedesten.
  ConstitutionalKind? get constitutional => ConstitutionalKind.of(code);
}

/// How the words a reader types are joined.
enum WordJoin {
  /// Every word must appear.
  all('Tümü geçsin'),

  /// Any of them.
  any('Herhangi biri geçsin');

  const WordJoin(this.label);

  final String label;
}

/// A search, as the reader set it up.
@immutable
class CaseLawQuery {
  const CaseLawQuery({
    this.words = '',
    this.join = WordJoin.all,
    this.kinds = const {CourtKind.yargitay},
    this.chamber,
    this.from,
    this.to,
    this.esasYear,
    this.esasNumber,
    this.kararYear,
    this.kararNumber,
    this.page = 1,
    this.pageSize = 10,
  });

  final String words;
  final WordJoin join;
  final Set<CourtKind> kinds;

  /// A chamber as the bank names it: "3. Hukuk Dairesi".
  final String? chamber;

  /// Both ends are needed together; see [CaseLawQueryBuilder.body].
  final DateTime? from, to;

  final int? esasYear, esasNumber, kararYear, kararNumber;
  final int page;

  /// How many the reader is shown at once. Ten, because every decision on
  /// the page costs a request to read and rank, and the bank allows about
  /// a dozen together.
  final int pageSize;

  /// How many the bank is asked for in one go, which is a different
  /// question and was for a while wrongly treated as the same one.
  ///
  /// The bank's ceiling is a hundred and it answers a hundred as fast as
  /// it answers ten: measured, 0.4 seconds either way, one request. Asking
  /// for ten was what made this search look worthless. The top of the pool
  /// is thick with decisions a chamber produced in one sitting, and a live
  /// search of 5,528 results for kıdem tazminatı came back a first page of
  /// eight decisions carrying one holding. A hundred costs nothing more
  /// and gives [CaseLawSpread] something to work with.
  static const fetchSize = 100;

  /// Which of the bank's pages holds the reader's page.
  int get bankPage => ((page - 1) * pageSize) ~/ fetchSize + 1;

  /// Where the reader's page begins inside that batch.
  int get offsetInBatch => ((page - 1) * pageSize) % fetchSize;

  bool get hasWords => words.trim().isNotEmpty;

  /// The Constitutional Court's bank, when that is what is searched.
  ConstitutionalKind? get constitutional {
    for (final kind in kinds) {
      final bank = kind.constitutional;
      if (bank != null) return bank;
    }
    return null;
  }

  bool get hasNumbers =>
      esasYear != null ||
      esasNumber != null ||
      kararYear != null ||
      kararNumber != null;
  bool get hasRange => from != null && to != null;
  bool get isEmpty => !hasWords && !hasNumbers;

  CaseLawQuery copyWith({
    String? words,
    WordJoin? join,
    Set<CourtKind>? kinds,
    String? chamber,
    DateTime? from,
    DateTime? to,
    int? esasYear,
    int? esasNumber,
    int? kararYear,
    int? kararNumber,
    int? page,
    bool clearChamber = false,
    bool clearRange = false,
    bool clearNumbers = false,
  }) => CaseLawQuery(
    words: words ?? this.words,
    join: join ?? this.join,
    kinds: kinds ?? this.kinds,
    chamber: clearChamber ? null : (chamber ?? this.chamber),
    from: clearRange ? null : (from ?? this.from),
    to: clearRange ? null : (to ?? this.to),
    esasYear: clearNumbers ? null : (esasYear ?? this.esasYear),
    esasNumber: clearNumbers ? null : (esasNumber ?? this.esasNumber),
    kararYear: clearNumbers ? null : (kararYear ?? this.kararYear),
    kararNumber: clearNumbers ? null : (kararNumber ?? this.kararNumber),
    page: page ?? this.page,
    pageSize: pageSize,
  );
}

/// Turns what the reader typed into what the bank will accept.
///
/// The bank reads a query the usual search-engine way — AND, OR, NOT, a
/// leading plus or minus, quotation marks for an exact phrase, brackets for
/// grouping — but three things about it have to be handled here rather than
/// explained to the reader.
///
/// Its own default is OR. Two words typed plainly answer with everything
/// containing either: measured live, "kira tahliye" returns two hundred
/// thousand decisions where the twenty-four thousand containing both were
/// wanted. Words are therefore joined explicitly.
///
/// It refuses characters it does not know, with a validation error rather
/// than by ignoring them, so a query carrying a colon or a question mark
/// fails outright. Those are cleared.
///
/// And a slash inside the words is refused too, which matters because a
/// lawyer writes an article as "4857/25". The paragraph is dropped and the
/// article kept; a case number is not touched, since that is searched
/// through its own fields.
class CaseLawQueryBuilder {
  const CaseLawQueryBuilder._();

  /// Everything the bank will not take. The operators it does take — plus,
  /// minus, quotation mark — are kept, and so are Turkish letters.
  static final _refused = RegExp(r'[^a-zA-Z0-9çğıöşüÇĞİÖŞÜ\s+"-]');

  /// "166/3" and "4857/25" are an article and its paragraph. The paragraph
  /// goes; a year and sequence like "2023/7868" is left alone, because its
  /// second half is four digits and case numbers are searched structurally.
  static final _articleParagraph = RegExp(
    r'\b(\d{1,4})\s*/\s*(\d{1,3}|son)\b',
    caseSensitive: false,
  );

  /// Written by the reader rather than assembled: quotation marks, brackets
  /// or an operator mean they are saying it themselves, and joining their
  /// words would break what they wrote.
  static final _authored = RegExp(r'["()+]|\bAND\b|\bOR\b|\bNOT\b');

  @visibleForTesting
  static String accepted(String phrase) => phrase
      .replaceAllMapped(_articleParagraph, (m) => m.group(1)!)
      .replaceAll(_refused, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @visibleForTesting
  static String phraseFor(String words, WordJoin join) {
    final typed = accepted(words);
    if (typed.isEmpty) return '';
    if (_authored.hasMatch(typed)) return typed;

    // The words worth searching for: the stop list takes out what every
    // decision contains, and the question words that are not the question.
    final terms = Relevances.termsIn(typed);
    if (terms.isEmpty) return typed;

    final excluded = Relevances.excludedIn(words);
    final joined = terms.join(join == WordJoin.all ? ' AND ' : ' OR ');
    if (excluded.isEmpty) return joined;
    return '$joined ${excluded.map((term) => '-$term').join(' ')}';
  }

  static String _day(DateTime at) =>
      '${at.toUtc().toIso8601String().split('T').first}T00:00:00.000Z';

  /// The body the bank is sent.
  static String body(CaseLawQuery query) {
    final data = <String, Object?>{
      'pageSize': CaseLawQuery.fetchSize,
      'pageNumber': query.bankPage,
      'itemTypeList': [
        for (final kind in query.kinds)
          if (kind.constitutional == null) kind.code,
      ],
    };
    final phrase = phraseFor(query.words, query.join);
    if (phrase.isNotEmpty) data['phrase'] = phrase;

    // birimAdi, not birimId: the latter answers with the same count for two
    // different chambers, so it filters by something that is not the name.
    final chamber = query.chamber?.trim();
    if (chamber != null && chamber.isNotEmpty) data['birimAdi'] = chamber;

    // Only a whole range. A lone start date is dropped by the bank without
    // a word of complaint, and a filter that quietly does nothing is worse
    // than one that is not offered.
    if (query.hasRange) {
      data['kararTarihiStart'] = _day(query.from!);
      data['kararTarihiEnd'] = _day(query.to!);
    }

    if (query.esasYear != null) data['esasNoYil'] = query.esasYear;
    if (query.esasNumber != null) data['esasNoSira'] = query.esasNumber;
    if (query.kararYear != null) data['kararNoYil'] = query.kararYear;
    if (query.kararNumber != null) data['kararNoSira'] = query.kararNumber;

    return jsonEncode({'data': data, 'applicationName': 'UyapMevzuat'});
  }
}

/// One decision in a list of results.
@immutable
class CaseLawHit {
  const CaseLawHit({
    required this.documentId,
    required this.court,
    required this.kind,
    required this.esas,
    required this.karar,
    required this.date,
    this.score = 0,
    this.snippet = '',
    this.alike = 0,
    this.reference = '',
  });

  final String documentId;
  final String court;

  /// Which collection it came from, which decides how high the bench sits.
  final String kind;
  final String esas, karar;
  final String date;

  /// What it is worth against the question, filled in once the text of the
  /// page of results has been read.
  final double score;
  final String snippet;

  /// How many other decisions on this page carry the same reasoning word
  /// for word. Shown beside this one rather than listed under it.
  final int alike;

  /// The reference the court asks for, where it has its own form; see
  /// [citationReference].
  final String reference;

  /// The reference a lawyer copies into a filing: "Yargıtay 15. Hukuk
  /// Dairesi, 2016/1531 E., 2017/3344 K., 21.09.2017 T.", or the
  /// Constitutional Court's own form.
  String get citationReference => reference.isNotEmpty
      ? reference
      : decisionReference(court: court, esas: esas, karar: karar, date: date);

  /// An individual application to the Constitutional Court, which has an
  /// application number rather than case numbers.
  bool get isApplication => kind == ConstitutionalKind.individual.code;

  String get title => isApplication
      ? [court, 'B. No: $esas', if (date.isNotEmpty) date].join(' ')
      : [court, 'E.$esas', 'K.$karar', if (date.isNotEmpty) date].join(' ');

  CaseLawHit ranked(double score, String snippet, {int alike = 0}) =>
      CaseLawHit(
        documentId: documentId,
        court: court,
        kind: kind,
        esas: esas,
        karar: karar,
        date: date,
        score: score,
        snippet: snippet,
        alike: alike,
        reference: reference,
      );

  /// A decision of the Constitutional Court in a list of results: its case
  /// numbers, or its application number, and what it was about.
  factory CaseLawHit.fromConstitutional(ConstitutionalRecord record) {
    final individual = record.kind == ConstitutionalKind.individual;
    return CaseLawHit(
      documentId: record.id,
      court: individual && record.body.isNotEmpty
          ? 'Anayasa Mahkemesi ${record.body}'
          : 'Anayasa Mahkemesi',
      kind: record.kind.code,
      esas: individual ? record.application : record.esas,
      karar: record.karar,
      date: record.date,
      snippet: [
        if (individual && record.applicant.isNotEmpty) record.applicant,
        if (record.outcome.isNotEmpty) record.outcome,
        if (record.subject.isNotEmpty) record.subject,
      ].join(' · '),
      reference: record.reference,
    );
  }

  static CaseLawHit? fromJson(Map<String, Object?> row) {
    final id = row['documentId'];
    if (id == null) return null;
    final type = row['itemType'];
    return CaseLawHit(
      documentId: '$id',
      court: '${row['birimAdi'] ?? ''}',
      kind: type is Map ? '${type['name'] ?? ''}' : '',
      esas: '${row['esasNo'] ?? ''}',
      karar: '${row['kararNo'] ?? ''}',
      date: '${row['kararTarihiStr'] ?? ''}',
    );
  }
}

/// What a search came back with.
@immutable
class CaseLawResults {
  const CaseLawResults({
    required this.hits,
    required this.total,
    required this.page,
  });

  const CaseLawResults.empty() : hits = const [], total = 0, page = 1;

  final List<CaseLawHit> hits;

  /// How many the bank says there are, which is usually far more than were
  /// asked for. Shown so the reader knows whether to narrow the search.
  final int total;
  final int page;

  bool get isEmpty => hits.isEmpty;
}

/// Spreads a batch so that one sitting of one chamber cannot fill the
/// first page.
///
/// A chamber deciding twenty like claims against one employer on one day
/// writes the same reasons twenty times and files them under consecutive
/// case numbers. The bank does rank by relevance — measured, the first
/// page of a search scores about 2.7 times what the twenty-fifth page
/// scores — and that is exactly why those twenty arrive together at the
/// top: they all match perfectly. Measured live, the first page of 5,528
/// results for kıdem tazminatı was eight decisions carrying one holding,
/// consecutive from E.2014/5760 to E.2014/5767, 1557 characters each.
///
/// Such a run is recognisable from the list alone, with no text fetched:
/// same chamber, same day, case numbers within a few of one another. What
/// is not safe is to hide one on that evidence. Checked against the bank,
/// a run of twelve held two different holdings — its first member was an
/// unrelated case that merely sat next to them — and a run of five held
/// two. Of nine distinct holdings across the runs checked, collapsing on
/// the metadata alone would have hidden three. For a lawyer, authority
/// that is never shown is the worst failure there is.
///
/// So a run is spread, not cut. At most [perRun] of it come forward; the
/// rest keep their order and go behind the others, still reached by
/// paging. Nothing is dropped, and the first page shows what the bank
/// found rather than what one chamber did one morning.
class CaseLawSpread {
  const CaseLawSpread._();

  /// How many of one run may come forward.
  ///
  /// Two rather than one, because a run is not reliably a single holding.
  /// Where the two are in truth the same, the text-verified gathering in
  /// [CaseLawRanking] merges them once their texts have been read; that
  /// check is exact, and this one is not.
  static const perRun = 2;

  /// How far two case numbers may sit apart and still be one filing. A run
  /// reaching the same page of results is rarely unbroken.
  static const _gap = 3;

  static final _esas = RegExp(r'^(\d{4})/(\d+)$');

  /// Which run each decision belongs to, by its place in [rows]. A
  /// decision standing on its own is absent.
  @visibleForTesting
  static Map<int, String> runsIn(List<CaseLawHit> rows) {
    final grouped = <String, List<(int, int)>>{};
    for (var at = 0; at < rows.length; at++) {
      final found = _esas.firstMatch(rows[at].esas.trim());
      if (found == null) continue;
      final key = '${rows[at].court}|${rows[at].date}|${found.group(1)}';
      (grouped[key] ??= <(int, int)>[]).add((int.parse(found.group(2)!), at));
    }

    final runs = <int, String>{};
    for (final group in grouped.entries) {
      final members = group.value..sort((a, b) => a.$1.compareTo(b.$1));
      var run = <(int, int)>[members.first];
      var n = 0;
      void close() {
        if (run.length < 2) return;
        final id = '${group.key}#${n++}';
        for (final member in run) {
          runs[member.$2] = id;
        }
      }

      for (final member in members.skip(1)) {
        if (member.$1 - run.last.$1 <= _gap) {
          run.add(member);
        } else {
          close();
          run = [member];
        }
      }
      close();
    }
    return runs;
  }

  /// The batch reordered. Relevance order is otherwise untouched.
  static List<CaseLawHit> of(List<CaseLawHit> rows) {
    final runs = runsIn(rows);
    if (runs.isEmpty) return rows;
    final forward = <CaseLawHit>[];
    final behind = <CaseLawHit>[];
    final taken = <String, int>{};
    for (var at = 0; at < rows.length; at++) {
      final run = runs[at];
      if (run == null) {
        forward.add(rows[at]);
        continue;
      }
      final already = taken[run] ?? 0;
      if (already < perRun) {
        taken[run] = already + 1;
        forward.add(rows[at]);
      } else {
        behind.add(rows[at]);
      }
    }
    return [...forward, ...behind];
  }
}

/// Puts a page of results in the order a reader would want them.
///
/// The bank hands back what matched, not what answers the question. The
/// ordering is done here, over the text of the decisions on this page: how
/// well each one meets the words asked for, how rare those words are among
/// these particular results, and how high the bench sits. The same decision
/// published twice under different numbers is put last rather than shown
/// twice.
class CaseLawRanking {
  const CaseLawRanking._();

  static List<CaseLawHit> of(
    String query,
    List<CaseLawHit> hits,
    Map<String, String> textById,
  ) {
    if (hits.isEmpty) return hits;
    final scored = <CaseLawHit>[];
    final matched = <List<String>>[];
    for (final hit in hits) {
      final text = textById[hit.documentId] ?? '';
      final found = Relevances.score(query, text);
      scored.add(hit.ranked(found.score, found.snippet));
      matched.add(found.matched);
    }

    final rarity = Relevances.rarityBonuses(matched);
    final weighted = <(CaseLawHit, double, String)>[];
    for (var i = 0; i < scored.length; i++) {
      final hit = scored[i];
      final weight =
          hit.score +
          rarity[i] +
          Relevances.authorityBonus(
            Relevances.authorityOf(hit.court, hit.kind),
          );
      weighted.add((
        hit,
        weight,
        Relevances.signatureOf(textById[hit.documentId] ?? ''),
      ));
    }

    // Ordered first, then gathered, so that of several decisions carrying
    // the same reasoning it is the best placed one that stands for them.
    weighted.sort((a, b) => b.$2.compareTo(a.$2));

    // Gathered rather than merely pushed down. A chamber deciding twenty
    // claims against one employer on the same day writes one set of reasons
    // twenty times, and pushing the copies to the foot of the page does
    // nothing when they are the whole page: a live search for kıdem
    // tazminatı came back six decisions of which five were one holding.
    // They are counted against the one that represents them instead, so
    // the page carries six answers rather than one answer six times.
    //
    // A decision whose text could not be fetched has no mark, and an
    // unknown is not a match: those are never gathered with anything.
    final firstOf = <String, int>{};
    final out = <CaseLawHit>[];
    final alike = <int>[];
    for (final (hit, _, mark) in weighted) {
      final already = mark.isEmpty ? null : firstOf[mark];
      if (already != null) {
        alike[already]++;
        continue;
      }
      if (mark.isNotEmpty) firstOf[mark] = out.length;
      out.add(hit);
      alike.add(0);
    }
    return [
      for (var i = 0; i < out.length; i++)
        alike[i] == 0
            ? out[i]
            : out[i].ranked(out[i].score, out[i].snippet, alike: alike[i]),
    ];
  }
}

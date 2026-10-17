// How well the anatomy of a decision is read, field by field, against
// sixty decisions fetched from Bedesten and read by hand.
//
// The texts are in test/fixtures/decisions, with index.json saying where
// each came from and expected.json what a careful reader finds in it. The
// figures are printed and written to build/karar_anatomisi_olcumu.md; the
// floors asserted at the end keep them from sliding back unnoticed.
import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/legal/citation.dart';
import 'package:evrak_convert/services/legal/decision.dart';
import 'package:evrak_convert/services/legal/decision_anatomy.dart';
import 'package:evrak_convert/services/legal/legal_terms.dart' show lowerTr;
import 'package:flutter_test/flutter_test.dart';

const _dir = 'test/fixtures/decisions';

String _flat(String value) =>
    lowerTr(value).replaceAll(RegExp(r'\s+'), ' ').trim();

/// A heading as compared: spaced letters closed up, capitals, no number
/// after the colon. "S O N U Ç:" and "SONUÇ" are the same heading.
String _heading(String value) {
  var title = value.trim();
  final spaced = RegExp(r'^[-\s]*((?:[A-ZÇĞİÖŞÜ] ){2,}[A-ZÇĞİÖŞÜ])')
      .firstMatch(title);
  if (spaced != null) {
    title = title.replaceRange(
      spaced.start,
      spaced.end,
      spaced.group(1)!.replaceAll(' ', ''),
    );
  }
  return upperTr(title.split(':').first)
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^([IVX]+)\s*[.)\-]\s*'), r'$1. ')
      .trim();
}

String _opening(String sentence) =>
    sentence.replaceFirst(RegExp(r'^\s*\d{1,2}\s*[.\-)]\s*'), '').trim();

const _roles = {
  'ilk_derece': CourtRole.firstInstance,
  'istinaf': CourtRole.appeal,
  'ozel_daire': CourtRole.chamber,
};

class _Tally {
  int right = 0, total = 0;
  final misses = <String>[];

  void count(String id, bool ok, [String why = '']) {
    total++;
    if (ok) {
      right++;
    } else {
      misses.add(why.isEmpty ? id : '$id: $why');
    }
  }

  double get rate => total == 0 ? 0 : right / total;
  String get shown => '$right/$total (%${(rate * 100).toStringAsFixed(0)})';
}

typedef _Measured = ({
  String report,
  double verbatim,
  double chain,
  double subject,
  double outcome,
  double sections,
  double laws,
  double decisions,
  double top3,
  int stockShown,
});

_Measured _measure(String indexName, String expectedName, String title) {
  {
    final index = [
      for (final row
          in jsonDecode(File('$_dir/$indexName').readAsStringSync()) as List)
        (row as Map).cast<String, Object?>(),
    ];
    final expected = (jsonDecode(
      File('$_dir/$expectedName').readAsStringSync(),
    ) as Map).cast<String, Object?>();
    final laws = CitationScanner.parse(
      File('assets/mevzuat/laws.json').readAsStringSync(),
    );
    final courts = DecisionScanner.parse(
      File('assets/mevzuat/courts.json').readAsStringSync(),
    );
    final stockFile = File('assets/mevzuat/karar_kaliplari.json');
    final stock = stockFile.existsSync()
        ? DecisionBoilerplate.parse(stockFile.readAsStringSync())
        : DecisionBoilerplate.empty;

    final chain = _Tally(),
        subject = _Tally(),
        subjectSentence = _Tally(),
        outcome = _Tally(),
        outcomeAll = _Tally(),
        sections = _Tally(),
        lawRecall = _Tally(),
        decisionRecall = _Tally(),
        decisionPrecision = _Tally(),
        top1 = _Tally(),
        top3 = _Tally(),
        verbatim = _Tally();
    var sectionHits = 0, sectionFound = 0, sectionWanted = 0;
    var stockShown = 0, shown = 0;
    final byGroup = <String, Map<String, _Tally>>{};

    for (final row in index) {
      final id = row['id']! as String;
      final group = id.replaceAll(RegExp(r'_\d+$'), '');
      final want = (expected[id]! as Map).cast<String, Object?>();
      final text = File('$_dir/$id.txt').readAsStringSync();
      final anatomy = DecisionAnatomy.of(
        text,
        query: row['query']! as String,
        laws: laws,
        decisions: courts,
        boilerplate: stock,
      );
      final mine = byGroup.putIfAbsent(
        group,
        () => {
          for (final name in ['zincir', 'konu', 'sonuc', 'one_cikan'])
            name: _Tally(),
        },
      );

      // Every quotation is the decision's own words, at the place given.
      final quotes = <Quote>[
        for (final step in anatomy.chain) ...[
          step.court,
          ?step.numbers,
          ?step.date,
          ?step.result,
        ],
        ?anatomy.subjectHeading,
        ?anatomy.subject,
        if (anatomy.outcome case final o?) ...[
          o.region,
          for (final verb in o.verbs) ...[verb.verb, verb.clause],
        ],
        for (final section in anatomy.sections) section.heading,
        for (final h in anatomy.highlights) h.quote,
      ];
      verbatim.count(
        id,
        quotes.every((q) => text.substring(q.start, q.end) == q.text),
      );

      // 1. The chain of courts.
      final wantChain = [
        for (final step in want['zincir']! as List)
          (step as Map).cast<String, Object?>(),
      ];
      var chainOk = wantChain.length == anatomy.chain.length;
      if (chainOk) {
        for (var i = 0; i < wantChain.length; i++) {
          final got = anatomy.chain[i];
          if (got.role != _roles[wantChain[i]['rol']] ||
              !_flat(got.court.text)
                  .contains(_flat(wantChain[i]['mahkeme']! as String))) {
            chainOk = false;
          }
        }
      }
      final chainWhy = anatomy.chain
          .map((s) => '${s.role.name}:${s.court.text}')
          .join(' / ');
      chain.count(id, chainOk, chainWhy);
      mine['zincir']!.count(id, chainOk);

      // 2. What the case is about.
      final phrases = [for (final p in want['konu']! as List) p as String];
      final said = _flat(
        '${anatomy.subjectHeading?.text ?? ''} ${anatomy.subject?.text ?? ''}',
      );
      final subjectOk = phrases.isEmpty
          ? anatomy.subjectHeading == null && anatomy.subject == null
          : phrases.every((p) => said.contains(_flat(p)));
      subject.count(
        id,
        subjectOk,
        said.length > 90 ? said.substring(0, 90) : said,
      );
      mine['konu']!.count(id, subjectOk);

      final sentence = want['konu_cumlesi'] as String?;
      final gotSentence = anatomy.subject?.text;
      final isSentence =
          gotSentence != null &&
          RegExp(
            r'^(?:\d+\s*[.\-]\s*)?(Dava|Eldeki dava|Uyuşmazlık|Somut uyuşmazlık|Temyize konu uyuşmazlık|İstem|Talep)\b',
          ).hasMatch(gotSentence);
      subjectSentence.count(
        id,
        sentence == null
            ? !isSentence
            : isSentence && _opening(gotSentence).startsWith(sentence.trim()),
        gotSentence ?? '-',
      );

      // 3. The outcome, read from the operative part alone.
      final wantPrimary = want['sonuc'] as String?;
      final gotPrimary = anatomy.outcome?.primary?.key;
      outcome.count(
        id,
        wantPrimary == gotPrimary,
        'beklenen $wantPrimary, bulunan $gotPrimary',
      );
      mine['sonuc']!.count(id, wantPrimary == gotPrimary);
      final wantAll = {
        for (final k in want['sonuc_tumu']! as List) k as String,
      };
      final gotAll = {
        for (final k in anatomy.outcome?.kinds ?? const <OutcomeKind>[]) k.key,
      };
      outcomeAll.count(
        id,
        wantAll.length == gotAll.length && wantAll.containsAll(gotAll),
        'beklenen $wantAll, bulunan $gotAll',
      );

      // 4. The parts.
      final wantSections = [
        for (final s in want['bolumler']! as List) _heading(s as String),
      ];
      final gotSections = [
        for (final s in anatomy.sections)
          if (s.level == 1) _heading(s.heading.text),
      ];
      final unmatched = [...gotSections];
      var hits = 0;
      for (final s in wantSections) {
        if (unmatched.remove(s)) hits++;
      }
      sectionHits += hits;
      sectionFound += gotSections.length;
      sectionWanted += wantSections.length;
      sections.count(
        id,
        hits == wantSections.length && hits == gotSections.length,
        'eksik ${wantSections.where((s) => !gotSections.contains(s)).toList()}'
        ' fazla $unmatched',
      );

      // 5. What it cites.
      for (final cited in want['mevzuat']! as List) {
        // "2004:89", or a lettered article "2004:68/a".
        final parts = (cited as String).split(':');
        final article = parts[1].split('/');
        final found = anatomy.laws.any(
          (c) =>
              c.law.number == int.parse(parts[0]) &&
              c.article == int.parse(article[0]) &&
              (article.length == 1 ||
                  lowerTr(c.letter ?? '') == lowerTr(article[1])),
        );
        lawRecall.count(id, found, cited);
      }
      String pair(String esas, String karar) =>
          '${esas.replaceAll(' ', '')}|${karar.replaceAll(' ', '')}';
      final wantDecisions = {
        for (final d in want['kararlar']! as List) d as String,
      };
      final gotDecisions = {
        for (final d in anatomy.decisions) pair(d.esas, d.karar),
      };
      for (final d in wantDecisions) {
        decisionRecall.count(id, gotDecisions.contains(d), d);
      }
      for (final d in gotDecisions) {
        decisionPrecision.count(id, wantDecisions.contains(d), d);
      }

      // 6. What stands out.
      final acceptable = [
        for (final s in want['one_cikan']! as List) _opening(s as String),
      ];
      for (final h in anatomy.highlights) {
        shown++;
        if (stock.isStock(h.quote.text)) stockShown++;
      }
      if (acceptable.isNotEmpty) {
        bool good(Highlight h) {
          final opening = _opening(h.quote.text);
          return acceptable.any(
            (a) => opening.startsWith(a) || a.startsWith(opening),
          );
        }

        final first = anatomy.highlights.isEmpty
            ? '-'
            : _opening(anatomy.highlights.first.quote.text);
        final ok1 =
            anatomy.highlights.isNotEmpty && good(anatomy.highlights.first);
        top1.count(id, ok1, first.length > 70 ? first.substring(0, 70) : first);
        mine['one_cikan']!.count(id, ok1);
        top3.count(id, anatomy.highlights.any(good));
      }
    }

    String pct(int a, int b) =>
        b == 0 ? '-' : '$a/$b (%${(a * 100 / b).toStringAsFixed(0)})';
    final report = StringBuffer()
      ..writeln('## $title')
      ..writeln()
      ..writeln(
        '${index.length} karar, elle işaretlenmiş beklenen değerlere '
        'karşı.',
      )
      ..writeln()
      ..writeln('| Alan | İsabet |')
      ..writeln('|---|---|')
      ..writeln(
        '| Birebir alıntı (her alan metindeki yeriyle) | ${verbatim.shown} |',
      )
      ..writeln('| Mahkeme zinciri (tam doğru) | ${chain.shown} |')
      ..writeln('| Dava konusu | ${subject.shown} |')
      ..writeln('| "Dava, … ilişkindir." cümlesi | ${subjectSentence.shown} |')
      ..writeln('| Sonuç (asıl) | ${outcome.shown} |')
      ..writeln('| Sonuç (bütün fiiller) | ${outcomeAll.shown} |')
      ..writeln('| Bölümler: karar başına tam doğru | ${sections.shown} |')
      ..writeln('| Bölümler: duyarlılık | ${pct(sectionHits, sectionWanted)} |')
      ..writeln('| Bölümler: kesinlik | ${pct(sectionHits, sectionFound)} |')
      ..writeln('| Mevzuat atfı: duyarlılık | ${lawRecall.shown} |')
      ..writeln('| Karar atfı: duyarlılık | ${decisionRecall.shown} |')
      ..writeln('| Karar atfı: kesinlik | ${decisionPrecision.shown} |')
      ..writeln('| Öne çıkan: ilk alıntı kabul edilebilir | ${top1.shown} |')
      ..writeln('| Öne çıkan: ilk üçte kabul edilebilir var | ${top3.shown} |')
      ..writeln(
        '| Öne çıkan: kalıp cümle gösterilen | '
        '${pct(stockShown, shown)} |',
      )
      ..writeln()
      ..writeln('| Grup | Zincir | Konu | Sonuç | Öne çıkan (ilk) |')
      ..writeln('|---|---|---|---|---|');
    for (final entry in byGroup.entries) {
      final t = entry.value;
      report.writeln(
        '| ${entry.key} | ${t['zincir']!.shown} | ${t['konu']!.shown} | '
        '${t['sonuc']!.shown} | ${t['one_cikan']!.shown} |',
      );
    }
    report.writeln();
    for (final (name, tally) in [
      ('Zincir', chain),
      ('Konu', subject),
      ('Konu cümlesi', subjectSentence),
      ('Sonuç', outcome),
      ('Sonuç (bütün)', outcomeAll),
      ('Bölümler', sections),
      ('Mevzuat', lawRecall),
      ('Karar atfı (kaçan)', decisionRecall),
      ('Karar atfı (fazla)', decisionPrecision),
      ('Öne çıkan (ilk)', top1),
    ]) {
      if (tally.misses.isEmpty) continue;
      report
        ..writeln('### Iskalar: $name')
        ..writeln();
      for (final miss in tally.misses) {
        report.writeln('- $miss');
      }
      report.writeln();
    }
    return (
      report: '$report',
      verbatim: verbatim.rate,
      chain: chain.rate,
      subject: subject.rate,
      outcome: outcome.rate,
      sections: sectionWanted == 0 ? 1.0 : sectionHits / sectionWanted,
      laws: lawRecall.rate,
      decisions: decisionRecall.rate,
      top3: top3.rate,
      stockShown: stockShown,
    );
  }
}

void main() {
  test('karar anatomisi alan alan isabet', () {
    // The decisions the rules were written against, and a second set
    // fetched afterwards and never tuned on: the second is the honest
    // figure for a decision the app has not seen.
    final tuned = _measure(
      'index.json',
      'expected.json',
      'Ayar kümesi (kurallar bu kararlara bakılarak yazıldı)',
    );
    final held = File('$_dir/index_dogrulama.json').existsSync()
        ? _measure(
            'index_dogrulama.json',
            'expected_dogrulama.json',
            'Doğrulama kümesi (kurallar yazıldıktan sonra indirildi, ayar '
                'yapılmadı)',
          )
        : null;
    final report =
        '# Karar anatomisi ölçümü\n\n${tuned.report}\n${held?.report ?? ''}';
    Directory('build').createSync(recursive: true);
    File('build/karar_anatomisi_olcumu.md').writeAsStringSync(report);
    // ignore: avoid_print
    print(report);

    // Floors, a little under what was measured, so that a change that
    // makes any field worse fails here rather than in a lawyer's hands.
    for (final m in [tuned, ?held]) {
      expect(m.verbatim, 1.0);
      expect(m.stockShown, 0);
    }
    expect(tuned.chain, greaterThanOrEqualTo(0.95));
    expect(tuned.subject, greaterThanOrEqualTo(0.8));
    expect(tuned.outcome, greaterThanOrEqualTo(0.95));
    expect(tuned.sections, greaterThanOrEqualTo(0.9));
    expect(tuned.laws, greaterThanOrEqualTo(0.9));
    expect(tuned.decisions, greaterThanOrEqualTo(0.85));
    expect(tuned.top3, greaterThanOrEqualTo(0.8));
  });
}

// Fetches, once, the law articles and the court decision the demo documents
// cite, into tool/screenshots/data/support/ where the screenshots read them
// back offline. The only part of the screenshot tooling that uses the network.
//
//   flutter test tool/screenshots/fetch_legal_test.dart
//
// The decision is a real one, as the Court of Cassation publishes it with the
// parties' names removed; the documents citing it are invented.
// The services' cache folders are test seams; this tool is a test in all but
// its folder, which the analyser does not count as one.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:evrak_convert/services/legal/case_law.dart';
import 'package:evrak_convert/services/legal/case_law_search.dart';
import 'package:evrak_convert/services/legal/citation.dart';
import 'package:evrak_convert/services/legal/decision.dart';
import 'package:evrak_convert/services/legal/legislation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'demo_documents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fetch the articles and the decision the demo petition cites', () async {
    // The test binding answers every request with an empty 400; this one
    // test needs the real network.
    HttpOverrides.global = null;
    final support = Directory('tool/screenshots/data/support');
    final caseLaw = CaseLaw(cache: Directory('${support.path}/ictihat'));
    final legislation = Legislation(
      cache: Directory('${support.path}/mevzuat'),
    );

    final results = await caseLaw.search(
      const CaseLawQuery(
        words: 'şiddetli geçimsizlik boşanma kusur tazminat',
        kinds: {CourtKind.yargitay},
        chamber: '2. Hukuk Dairesi',
        pageSize: 10,
      ),
    );
    final decisions = DecisionScanner((await DecisionScanner.load()).courts);
    Decision? decision;
    DecisionCitation? cited;
    for (final hit in results.hits) {
      final found = decisions.scan(hit.citationReference);
      if (found.isEmpty) continue;
      final full = await caseLaw.decision(found.first);
      if (full != null && full.text.length > 1500) {
        decision = full;
        cited = found.first;
        break;
      }
    }
    expect(decision, isNotNull, reason: 'no decision with text was found');
    File('tool/screenshots/data/decision.txt').writeAsStringSync(cited!.label);

    final petition = demoPetition(cited.label);
    final laws = await CitationScanner.load();
    var articles = 0;
    for (final citation in laws.scan(petition.map((p) => p.text).join('\n'))) {
      if (await legislation.article(citation) != null) articles++;
    }
    // ignore: avoid_print
    print('decision: ${cited.label}, articles kept: $articles');
    expect(articles, greaterThanOrEqualTo(3));
  }, timeout: const Timeout(Duration(minutes: 5)));
}

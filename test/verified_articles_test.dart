import 'dart:io';

import 'package:evrak_convert/services/legal/citation.dart';
import 'package:evrak_convert/services/legal/legislation.dart';
import 'package:evrak_convert/services/legal/verified_articles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Citation at(int law, int article, {String? letter, ArticleKind? kind}) =>
      Citation(
        law: Law.numbered(law),
        article: article,
        start: 0,
        length: 1,
        letter: letter,
        kind: kind ?? ArticleKind.plain,
      );

  test('labels as Folio files articles', () {
    expect(VerifiedArticles.keyOf('madde 68/A'), '68/a');
    expect(VerifiedArticles.keyOf('ek 17'), 'ek 17');
    expect(VerifiedArticles.keyOf('geçici 5'), 'geçici 5');
  });

  test('every target has its text, and only targets are in the file', () {
    final v = VerifiedArticles.parse(
      File(VerifiedArticles.asset).readAsStringSync(),
    );
    expect(v.cutOn, '2026-09-21');
    for (final MapEntry(key: law, value: keys)
        in VerifiedArticles.targets.entries) {
      for (final k in keys) {
        expect(v.of(law, k)?.text, isNotEmpty, reason: '$law $k');
      }
    }
  });

  group('looked up', () {
    // No bank and no page: whatever comes, comes from the cut text.
    final legislation = Legislation(
      download: (law) async => throw const SocketException('ağ yok'),
      cache: Directory.systemTemp.createTempSync('folio-dogrulanmis-'),
    );

    test('the law as amended by 7589, not Bedesten\'s older text', () async {
      final got = await legislation.lookup(at(1512, 55));
      expect(got.outcome, ArticleOutcome.found);
      expect(got.article!.text, contains('7589'));
      expect(got.article!.text, isNot(contains('sorgu hakimliği')));
      expect(got.article!.source, ArticleSource.verified);
    });

    test('"iki yıl" aday sürücülük', () async {
      final got = await legislation.lookup(
        at(2918, 17, kind: ArticleKind.additional),
      );
      expect(got.article!.text, contains('iki yıl'));
    });

    test('an article Bedesten does not know at all', () async {
      final got = await legislation.lookup(at(1211, 68, letter: 'A'));
      expect(got.outcome, ArticleOutcome.found);
      expect(got.article!.text, contains('68/A'));
    });

    test('a repealed law given from a copy says so', () async {
      final got = await legislation.lookup(
        at(2981, 5, kind: ArticleKind.provisional),
      );
      expect(got.article!.source, ArticleSource.verifiedCopy);
    });

    test('another article of the same law is not given from here', () async {
      final got = await legislation.lookup(at(1512, 56));
      expect(got.outcome, isNot(ArticleOutcome.found));
    });
  });
}

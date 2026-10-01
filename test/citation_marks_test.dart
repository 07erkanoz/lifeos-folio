import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/legal/citation.dart';
import 'package:evrak_convert/services/legal/legal_terms.dart';
import 'package:evrak_convert/services/legal/legislation.dart';
import 'package:evrak_convert/ui/widgets/article_panel.dart';
import 'package:evrak_convert/ui/widgets/overlay_card.dart';
import 'package:evrak_convert/ui/widgets/editor_citations.dart';
import 'package:evrak_convert/ui/widgets/editor_spelling.dart';
import 'package:evrak_convert/ui/widgets/text_marks.dart';

CitationScanner _scanner() =>
    CitationScanner.parse(File('assets/mevzuat/laws.json').readAsStringSync());

const _colors = ColorScheme.light();

void main() {
  group('the marks a document carries', () {
    test('a citation is found and drawn where it stands', () async {
      final marks = CitationMarks(
        scanner: _scanner(),
        onTap: (_, _) {},
        after: const Duration(milliseconds: 5),
      );
      addTearDown(marks.dispose);

      const text = 'Boşanma için TMK m. 166 ileri sürülmüştür.';
      marks.now(text);

      expect(marks.marks, hasLength(1));
      final one = marks.marks.single;
      expect(text.substring(one.start, one.end), 'TMK m. 166');
      expect(marks.at(one.start + 2)?.article, 166);
      expect(marks.at(0), isNull);
    });

    test('the same recognizer is handed out for the same citation', () {
      final marks = CitationMarks(scanner: _scanner(), onTap: (_, _) {});
      addTearDown(marks.dispose);
      marks.now('TMK m. 166');

      // A leaf is rebuilt on every paint; a fresh recognizer each time would
      // leak one per frame.
      final first = marks.textMarks(_colors).single.recognizer;
      final second = marks.textMarks(_colors).single.recognizer;
      expect(identical(first, second), isTrue);
    });

    test('pressing a citation says which one, and where', () {
      Citation? pressed;
      Offset? at;
      final marks = CitationMarks(
        scanner: _scanner(),
        onTap: (citation, where) {
          pressed = citation;
          at = where;
        },
      );
      addTearDown(marks.dispose);
      marks.now('İİK 89/1 uyarınca');

      final recognizer =
          marks.textMarks(_colors).single.recognizer! as TapGestureRecognizer;
      recognizer.onTapUp!(
        TapUpDetails(
          kind: PointerDeviceKind.mouse,
          globalPosition: const Offset(120, 240),
        ),
      );

      expect(pressed?.law.number, 2004);
      expect(pressed?.article, 89);
      expect(pressed?.paragraph, 1);
      expect(at, const Offset(120, 240));
    });

    test('a document with nothing to cite carries no marks', () {
      final marks = CitationMarks(scanner: _scanner(), onTap: (_, _) {});
      addTearDown(marks.dispose);
      marks.now('Dosya 2024/1234 esas sayılıdır.');
      expect(marks.isEmpty, isTrue);
      expect(marks.textMarks(_colors), isEmpty);
    });
  });

  group('two kinds of mark over one stretch', () {
    test('a marked stretch is cut out and the rest left alone', () {
      const style = TextStyle(fontSize: 12);
      final spans = markedSpans('Sayın hakm bey', 0, style, const [
        TextMark(start: 6, length: 4, style: spellingUnderline),
      ])!;
      expect(spans.map((s) => (s as TextSpan).text), [
        'Sayın ',
        'hakm',
        ' bey',
      ]);
    });

    test('nothing reaching this stretch means no splitting at all', () {
      expect(
        markedSpans('Sayın', 100, null, const [
          TextMark(start: 6, length: 4, style: spellingUnderline),
        ]),
        isNull,
      );
      expect(markedSpans('Sayın', 0, null, const []), isNull);
    });

    test('a mark reaching past the end of a leaf is cut to it', () {
      final spans = markedSpans('abcde', 0, null, const [
        TextMark(start: 2, length: 20, style: spellingUnderline),
      ])!;
      expect(spans.map((s) => (s as TextSpan).text), ['ab', 'cde']);
    });

    test('the first mark offered keeps the ground the two share', () {
      // TMK is not a word the checker knows, so the same letters are both a
      // citation and a misspelling. Offered first, the citation wins.
      const citation = TextStyle(color: Color(0xFF0066CC));
      final spans = markedSpans('TMK m. 166', 0, null, const [
        TextMark(start: 0, length: 10, style: citation),
        TextMark(start: 0, length: 3, style: spellingUnderline),
      ])!;
      expect(spans, hasLength(1));
      expect((spans.single as TextSpan).style?.color, const Color(0xFF0066CC));
    });
  });

  group('the card the article is shown in', () {
    Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

    const law = Law(number: 4721, tertip: 5, name: 'Türk Medeni Kanunu');
    const cite = Citation(law: law, article: 166, start: 0, length: 10);

    testWidgets('it names the article while the text is still coming', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          ArticleCard(
            citation: cite,
            lookup: () => Completer<ArticleLookup>().future,
            maxHeight: 420,
            onClose: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('4721 s. Türk Medeni Kanunu m. 166'), findsOneWidget);
      expect(find.text('Madde getiriliyor…'), findsOneWidget);
    });

    testWidgets('it shows the article once it arrives', (tester) async {
      await tester.pumpWidget(
        host(
          ArticleCard(
            citation: cite,
            lookup: () async => const ArticleLookup(
              ArticleOutcome.found,
              article: Article(
                law: law,
                number: 166,
                text: 'Madde 166- Evlilik birliği, ortak hayatı…',
              ),
            ),
            maxHeight: 420,
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Evlilik birliği, ortak hayatı…',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.textContaining('mevzuat.gov.tr'), findsWidgets);
      // Künye, bir düğmeyle kopyalanabilir durumda.
      expect(find.text('Künyeyi kopyala'), findsOneWidget);
      expect(find.text('Resmî kaynakta aç'), findsOneWidget);
    });

    testWidgets('it says so plainly when the article cannot be had', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          ArticleCard(
            citation: cite,
            lookup: () async => const ArticleLookup(ArticleOutcome.unreachable),
            maxHeight: 420,
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('ulaşılamadı'), findsOneWidget);
      expect(find.text('Yeniden dene'), findsOneWidget);
    });

    testWidgets('the close button closes it', (tester) async {
      var closed = false;
      await tester.pumpWidget(
        host(
          ArticleCard(
            citation: cite,
            lookup: () async => const ArticleLookup(ArticleOutcome.absent),
            maxHeight: 420,
            onClose: () => closed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      expect(closed, isTrue);
    });
  });

  group('the panel over the document', () {
    const law = Law(number: 6100, tertip: 5, name: 'Hukuk Muhakemeleri Kanunu');
    const cite = Citation(law: law, article: 119, start: 0, length: 9);

    testWidgets('it opens over the page and Esc takes it away', (tester) async {
      late BuildContext held;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                held = context;
                return const Text('belge');
              },
            ),
          ),
        ),
      );

      expect(OverlayCard.dismissActive(), isFalse);

      ArticlePanel.show(
        held,
        citation: cite,
        lookup: () async => const ArticleLookup(
          ArticleOutcome.found,
          article: Article(law: law, number: 119, text: 'MADDE 119- …'),
        ),
        at: const Offset(200, 200),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('article-panel')), findsOneWidget);

      // This is what main.dart's Esc handler calls.
      expect(OverlayCard.dismissActive(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('article-panel')), findsNothing);
      expect(OverlayCard.dismissActive(), isFalse);
    });

    testWidgets('a second citation replaces the first card', (tester) async {
      late BuildContext held;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                held = context;
                return const Text('belge');
              },
            ),
          ),
        ),
      );

      for (var i = 0; i < 2; i++) {
        ArticlePanel.show(
          held,
          citation: cite,
          lookup: () async => const ArticleLookup(
            ArticleOutcome.found,
            article: Article(law: law, number: 119, text: 'MADDE 119- …'),
          ),
          at: const Offset(200, 200),
        );
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('article-panel')), findsOneWidget);

      expect(OverlayCard.dismissActive(), isTrue);
      await tester.pumpAndSettle();
      expect(OverlayCard.dismissActive(), isFalse);
    });
  });

  group('the card a term is shown in', () {
    Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

    testWidgets('it names the term and gives its meaning', (tester) async {
      await tester.pumpWidget(
        host(
          TermCard(
            term: const TermMatch(
              term: 'Müddeabih',
              dictionary: LegalTerm(term: 'Müddeabih', meaning: 'Dava konusu'),
            ),
            maxHeight: 260,
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Müddeabih'), findsOneWidget);
      expect(find.text('Dava konusu'), findsOneWidget);
      expect(find.text('sozluk.adalet.gov.tr'), findsOneWidget);
    });

    testWidgets('a clipped meaning says so rather than passing for whole', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          TermCard(
            term: const TermMatch(
              term: 'Acenta',
              dictionary: LegalTerm(
                term: 'Acenta',
                meaning:
                    'Ticari mümessil, satış memuru gibi bir sıfatı olmaksızın',
                clipped: true,
              ),
            ),
            maxHeight: 260,
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('…'), findsOneWidget);
      expect(find.textContaining('kısaltılmış'), findsOneWidget);
    });

    testWidgets('a word only the statutes define is still answered', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          TermCard(
            term: const TermMatch(
              term: 'Açık rıza',
              statutes: [
                StatuteMeaning(
                  meaning:
                      'Belirli bir konuya ilişkin, özgür iradeyle '
                      'açıklanan rızayı',
                  law: '6698 s. Kişisel Verilerin Korunması Kanunu',
                ),
              ],
            ),
            maxHeight: 300,
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Açık rıza'), findsOneWidget);
      expect(find.text('Kanundaki tanımı'), findsOneWidget);
      expect(
        find.text('6698 s. Kişisel Verilerin Korunması Kanunu'),
        findsOneWidget,
      );
      expect(find.textContaining('mevzuat.gov.tr'), findsOneWidget);
    });

    testWidgets('several laws meaning different things are each named', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          TermCard(
            term: const TermMatch(
              term: 'Bakanlık',
              statutes: [
                StatuteMeaning(
                  meaning: 'Adalet Bakanlığını',
                  law: '6325 s. Arabuluculuk Kanunu',
                ),
                StatuteMeaning(
                  meaning: 'Maliye Bakanlığını',
                  law: '5549 s. Suç Gelirlerinin Aklanmasının Önlenmesi Kanunu',
                ),
              ],
            ),
            maxHeight: 340,
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Coguldur: sekiz kanun sekiz ayri kurumu kastediyor ve hicbiri
      // "Bakanlik" kelimesinin anlami degil.
      expect(find.text('Kanunlardaki tanımları'), findsOneWidget);
      expect(find.text('Adalet Bakanlığını'), findsOneWidget);
      expect(find.text('Maliye Bakanlığını'), findsOneWidget);
    });

    testWidgets('a word in both sources shows both, and says so', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          TermCard(
            term: const TermMatch(
              term: 'Tüketici',
              dictionary: LegalTerm(
                term: 'Tüketici',
                meaning: 'Mal veya hizmeti satın alan kişi',
              ),
              statutes: [
                StatuteMeaning(
                  meaning: 'Ticari veya mesleki olmayan amaçlarla hareket eden',
                  law: '6502 s. Tüketicinin Korunması Hakkında Kanun',
                ),
              ],
            ),
            maxHeight: 340,
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mal veya hizmeti satın alan kişi'), findsOneWidget);
      expect(find.text('Kanundaki tanımı'), findsOneWidget);
      expect(
        find.text('sozluk.adalet.gov.tr · mevzuat.gov.tr'),
        findsOneWidget,
      );
    });
  });

  group('the term panel over the document', () {
    testWidgets('it opens, and Esc takes it away', (tester) async {
      late BuildContext held;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                held = context;
                return const Text('belge');
              },
            ),
          ),
        ),
      );
      expect(OverlayCard.dismissActive(), isFalse);

      TermPanel.show(
        held,
        term: const TermMatch(
          term: 'Vedia',
          dictionary: LegalTerm(term: 'Vedia', meaning: 'Saklama'),
        ),
        at: const Offset(200, 200),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('term-panel')), findsOneWidget);

      expect(OverlayCard.dismissActive(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('term-panel')), findsNothing);
    });
  });
}

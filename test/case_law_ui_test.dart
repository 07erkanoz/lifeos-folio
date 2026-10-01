import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/legal/case_law_search.dart';
import 'package:evrak_convert/ui/legal/case_law_results.dart';

CaseLawHit _hit({
  String id = '1',
  String court = '9. Hukuk Dairesi',
  String snippet = 'para ile ölçülebilen menfaatler göz önünde tutulur',
  int alike = 0,
}) => CaseLawHit(
  documentId: id,
  court: court,
  kind: 'YARGITAYKARARI',
  esas: '2014/5767',
  karar: '2014/9001',
  date: '21.09.2014',
  score: 137,
  snippet: snippet,
  alike: alike,
);

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(height: 600, child: child)),
);

void main() {
  group('a page of results', () {
    testWidgets('before anything is asked it says what to do', (tester) async {
      await tester.pumpWidget(
        _host(
          CaseLawResultList(
            results: const CaseLawResults.empty(),
            onOpen: (_) {},
          ),
        ),
      );
      expect(find.textContaining('Aranacak kelimeleri yazın'), findsOneWidget);
    });

    testWidgets('after an empty answer it says so, and suggests a way on', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          CaseLawResultList(
            results: const CaseLawResults.empty(),
            asked: true,
            onOpen: (_) {},
          ),
        ),
      );
      expect(find.textContaining('bulunamadı'), findsOneWidget);
      expect(find.textContaining('herhangi biri'), findsOneWidget);
    });

    testWidgets('a decision shows whose it is and what it says', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          CaseLawResultList(
            results: CaseLawResults(hits: [_hit()], total: 1, page: 1),
            asked: true,
            onOpen: (_) {},
          ),
        ),
      );
      expect(find.textContaining('9. Hukuk Dairesi'), findsOneWidget);
      expect(find.textContaining('para ile ölçülebilen'), findsOneWidget);
    });

    testWidgets('gathered decisions are counted, not hidden', (tester) async {
      // Sayfanın tamamı tek gerekçe olduğunda okuyucu bunu bilmeli: banka
      // 5528 diyor ama ekranda bir satır var, sebebi yazılı olmalı.
      await tester.pumpWidget(
        _host(
          CaseLawResultList(
            results: CaseLawResults(
              hits: [_hit(alike: 7)],
              total: 5528,
              page: 1,
            ),
            asked: true,
            onOpen: (_) {},
          ),
        ),
      );
      expect(find.text('+7 aynı gerekçe'), findsOneWidget);
      expect(find.textContaining('5528 karar bulundu'), findsOneWidget);
      expect(
        find.textContaining('aynı gerekçeyle birleştirildi'),
        findsOneWidget,
      );
    });

    testWidgets('with nothing gathered the summary stays plain', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          CaseLawResultList(
            results: CaseLawResults(hits: [_hit()], total: 40, page: 1),
            asked: true,
            onOpen: (_) {},
          ),
        ),
      );
      expect(find.textContaining('bu sayfada 1 tanesi'), findsOneWidget);
      expect(find.textContaining('birleştirildi'), findsNothing);
    });

    testWidgets('pressing one opens it', (tester) async {
      CaseLawHit? opened;
      await tester.pumpWidget(
        _host(
          CaseLawResultList(
            results: CaseLawResults(hits: [_hit(id: 'x')], total: 1, page: 1),
            asked: true,
            onOpen: (hit) => opened = hit,
          ),
        ),
      );
      await tester.tap(find.textContaining('9. Hukuk Dairesi'));
      expect(opened?.documentId, 'x');
    });
  });

  group('paging', () {
    testWidgets('it is offered only when there is more than this page', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          CaseLawResultList(
            results: CaseLawResults(hits: [_hit()], total: 1, page: 1),
            asked: true,
            onOpen: (_) {},
            onPage: (_) {},
          ),
        ),
      );
      expect(find.text('Sonraki'), findsNothing);
    });

    testWidgets('on the first page there is no way back', (tester) async {
      var went = -1;
      await tester.pumpWidget(
        _host(
          CaseLawResultList(
            results: CaseLawResults(hits: [_hit()], total: 500, page: 1),
            asked: true,
            onOpen: (_) {},
            onPage: (page) => went = page,
          ),
        ),
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Önceki'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Sonraki'));
      expect(went, 2);
    });
  });
}

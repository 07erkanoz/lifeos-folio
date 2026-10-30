import 'package:evrak_convert/services/ai/ai_case_law.dart';
import 'package:evrak_convert/services/legal/case_law.dart';
import 'package:evrak_convert/services/legal/case_law_search.dart';
import 'package:flutter_test/flutter_test.dart';

// The case bank searched with the lawyer's AI program: it writes the
// searches, Folio runs them on the bank, it picks among what was found by
// number, saying why; a number it made up is not taken.
class _Bank extends CaseLaw {
  final asked = <CaseLawQuery>[];

  CaseLawHit _hit(String id) => CaseLawHit(
    documentId: id,
    court: 'Yargıtay 9. Hukuk Dairesi',
    kind: 'YARGITAYKARARI',
    esas: '2016/$id',
    karar: '2017/$id',
    date: '01.02.2017',
    snippet: 'yıllık izin ücreti $id',
  );

  @override
  Future<void> rank(
    CaseLawQuery query,
    CaseLawResults results,
    void Function(CaseLawResults ordered) onSettled, {
    bool Function()? wanted,
  }) async => onSettled(results);

  @override
  Future<CaseLawResults> search(CaseLawQuery query) async {
    asked.add(query);
    final hits = query.words.contains('izin')
        ? [_hit('1'), _hit('2'), _hit('3')]
        : [_hit('3'), _hit('4')];
    return CaseLawResults(hits: hits, total: hits.length, page: 1);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'searches written by the program, run by Folio, picked by number',
    () async {
      final bank = _Bank();
      final prompts = <String>[];
      final stages = <String>[];
      final picks = await AiCaseLawSearch.run(
        bank: bank,
        question: 'İşçi izinlerini kullanmadan ayrıldı',
        document: 'Davacı vekili olarak yıllık izin ücreti talep ederiz.',
        onStage: stages.add,
        ask: (prompt) async {
          prompts.add(prompt);
          return prompts.length == 1
              ? '```json\n{"sorgular": ["\\"yıllık izin ücreti\\"", '
                    '"izin defteri ispat"]}\n```'
              : '{"secilen": [{"no": 4, "neden": "İzin defteri yoksa ispat '
                    'yükü işverende."}, {"no": 1, "neden": "İzin ücreti son '
                    'ücretle hesaplanır."}, {"no": 99, "neden": "uydurma"}]}';
        },
      );
      expect(prompts.first, contains('<belge>'));
      expect(prompts.first, contains('İşçi izinlerini kullanmadan ayrıldı'));
      expect(bank.asked.map((q) => q.words), [
        '"yıllık izin ücreti"',
        'izin defteri ispat',
      ]);
      // Each decision once, numbered for the program.
      expect(prompts.last, contains('[3]'));
      expect(prompts.last, isNot(contains('[4]')));
      expect(picks.map((p) => p.hit.documentId), ['1']);
      expect(picks.single.reason, contains('son ücretle'));
      expect(stages, [
        'Arama ifadeleri hazırlanıyor',
        'Resmî karar bankasında aranıyor',
        'Kararlar değerlendiriliyor',
      ]);
    },
  );

  test('with nothing chosen, the bank\'s order; with no searches written, '
      'the question itself', () async {
    final bank = _Bank();
    var n = 0;
    final picks = await AiCaseLawSearch.run(
      bank: bank,
      question: 'kıdem tazminatı',
      ask: (_) async => n++ == 0 ? 'anlaşılmadı' : '{"secilen": []}',
    );
    expect(bank.asked.first.words, 'kıdem tazminatı');
    expect(picks.map((p) => p.hit.documentId), ['3', '4']);
    expect(picks.every((p) => p.reason.isEmpty), isTrue);
  });
}

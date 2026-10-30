import 'dart:convert';

import '../legal/case_law.dart';
import '../legal/case_law_search.dart';
import 'ai_assistant.dart';

/// A decision the AI program chose for the lawyer's question, and why.
class AiCaseLawPick {
  const AiCaseLawPick(this.hit, this.reason);
  final CaseLawHit hit;
  final String reason;
}

/// The case bank searched with the lawyer's AI program: from the question
/// as the lawyer puts it (and the document they are writing) it writes a
/// few searches as the bank takes them; Folio runs them on the official
/// bank itself; the program then picks the decisions that answer the
/// question, saying why. Every decision is the bank's: the program only
/// chooses among what Folio found, by number.
abstract final class AiCaseLawSearch {
  /// The most decisions put before the program to choose from, and chosen.
  static const candidates = 30, chosen = 8;

  /// The decisions of each search read for the program.
  static const perSearch = 10;

  /// Its answers, [ask] standing in for the program in a test.
  static Future<List<AiCaseLawPick>> run({
    required CaseLaw bank,
    required String question,
    String document = '',
    Set<CourtKind> kinds = const {CourtKind.yargitay},
    void Function(String stage)? onStage,
    Future<String> Function(String prompt)? ask,
  }) async {
    final asking = ask ?? await _program();
    onStage?.call('Arama ifadeleri hazırlanıyor');
    final searches = queriesIn(
      await asking(_queriesPrompt(question, document, kinds)),
    );
    if (searches.isEmpty) searches.add(question);
    onStage?.call('Resmî karar bankasında aranıyor');
    final found = <String, CaseLawHit>{};
    for (final words in searches.take(3)) {
      for (final join in [WordJoin.all, WordJoin.any]) {
        final query = CaseLawQuery(
          words: words,
          kinds: kinds,
          join: join,
          pageSize: perSearch,
        );
        CaseLawResults got;
        try {
          got = await bank.search(query);
        } catch (_) {
          continue;
        }
        // Each decision's text read for what it says of the question: the
        // program chooses by that, not by its number alone.
        var read = got;
        try {
          await bank.rank(query, got, (ordered) => read = ordered);
        } catch (_) {}
        for (final h in read.hits) {
          found.putIfAbsent(h.documentId, () => h);
        }
        // "Any word" only when every word found too little.
        if (got.hits.length >= 3) break;
      }
      if (found.length >= candidates) break;
    }
    final list = found.values.take(candidates).toList();
    if (list.isEmpty) return const [];
    onStage?.call('Kararlar değerlendiriliyor');
    final picks = picksIn(await asking(_rankPrompt(question, list)), list);
    return picks.isNotEmpty
        ? picks
        : [for (final h in list.take(chosen)) AiCaseLawPick(h, '')];
  }

  static Future<Future<String> Function(String)> _program() async {
    final settings = await AiSettings.load();
    final statuses = await AiAssistant.statuses();
    final provider =
        settings.provider != null &&
            statuses.any((s) => s.provider == settings.provider && s.usable)
        ? settings.provider!
        : statuses.where((s) => s.usable).map((s) => s.provider).firstOrNull;
    if (provider == null) {
      throw const AiFailure(
        'Bu bilgisayarda oturumu açık bir yapay zekâ programı yok.',
      );
    }
    // Quick work: the lighter tier, and no tools.
    final model = settings.modelFor(provider, AiTier.normal);
    return (prompt) => AiAssistant.ask(
      provider,
      prompt,
      model: model,
      tier: AiTier.normal,
      tools: false,
    );
  }

  static String _queriesPrompt(
    String question,
    String document,
    Set<CourtKind> kinds,
  ) => [
    'Avukat resmî karar bankasında emsal karar arıyor '
        '(${kinds.map((k) => k.label).join(', ')}).',
    'Avukatın sorusu: $question',
    if (document.trim().isNotEmpty) ...[
      'Avukatın yazdığı belgeden (bağlam için):',
      '<belge>',
      document.length > 6000 ? document.substring(0, 6000) : document,
      '</belge>',
    ],
    'Bu soruya cevap olacak kararları bulmak için bankada çalıştırılacak 2 '
        'ile 4 arama ifadesi yaz. Kurallar: kararlarda geçen hukuk '
        'terimlerini kullan; tam ifade için "çift tırnak"; dışarıda '
        'bırakılacak kelimenin başına -; her ifade en çok 6 kelime; kanun '
        'numarası ya da madde yazma, karar uydurma.',
    'Yalnız şu JSON ile cevap ver: {"sorgular": ["...", "..."]}',
  ].join('\n');

  static String _rankPrompt(String question, List<CaseLawHit> hits) => [
    'Avukatın sorusu: $question',
    'Resmî karar bankasının bulduğu adaylar:',
    for (final (i, h) in hits.indexed)
      '[${i + 1}] ${h.citationReference} — '
          '${h.snippet.length > 300 ? '${h.snippet.substring(0, 300)}…' : h.snippet}',
    'Soruya gerçekten cevap olan en çok $chosen kararı seç ve en ilgiliden '
        'başlayarak sırala. Her biri için kararın soruyla ilgisini tek kısa '
        'cümleyle yaz; yalnız adayların metninde görüleni söyle. Uyan '
        'yoksa boş liste ver.',
    'Yalnız şu JSON ile cevap ver: '
        '{"secilen": [{"no": 1, "neden": "..."}]}',
  ].join('\n');

  /// The searches the program wrote.
  static List<String> queriesIn(String answer) {
    final json = _json(answer);
    return [
      for (final q in (json?['sorgular'] as List? ?? const []))
        if ('$q'.trim().isNotEmpty) '$q'.trim(),
    ];
  }

  /// The decisions the program chose, by their number among [hits].
  static List<AiCaseLawPick> picksIn(String answer, List<CaseLawHit> hits) {
    final json = _json(answer);
    final out = <AiCaseLawPick>[];
    final seen = <int>{};
    for (final p in (json?['secilen'] as List? ?? const [])) {
      if (p is! Map) continue;
      final n = p['no'] is num
          ? (p['no'] as num).toInt()
          : int.tryParse('${p['no']}');
      if (n == null || n < 1 || n > hits.length || !seen.add(n)) continue;
      out.add(AiCaseLawPick(hits[n - 1], '${p['neden'] ?? ''}'.trim()));
      if (out.length >= chosen) break;
    }
    return out;
  }

  /// The JSON object in [text], fenced or not.
  static Map<String, Object?>? _json(String text) {
    final start = text.indexOf('{'), end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final json = jsonDecode(text.substring(start, end + 1));
      return json is Map ? json.cast<String, Object?>() : null;
    } on FormatException {
      return null;
    }
  }
}

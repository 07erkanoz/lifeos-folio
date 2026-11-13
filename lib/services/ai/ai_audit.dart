import 'ai_events.dart';
import 'ai_guide.dart';
import 'folio_mcp.dart';

/// Folio's own look at an answer before the lawyer sees it. Every article
/// and decision the answer cites is looked up: one that does not exist, or
/// is repealed, must go; a vote said wrong is put right; a sentence
/// reckoned without Folio's engine is reckoned with it. What it finds is
/// said to the program, which writes its answer again. An article cited
/// without being read is not sent back for that alone: the rule to read
/// first is the program's.
class AnswerAudit {
  AnswerAudit(this.mcp);

  final FolioMcp mcp;

  /// Whether the last [feedback] found something wrong in the answer
  /// itself (a citation that does not exist or is repealed, a vote said
  /// wrong, a sentence reckoned without Folio's engine), not only articles
  /// it rested on unread. Only such a finding is worth a second round.
  bool serious = false;

  /// The most articles Folio reads for one answer.
  static const mostRead = 4;

  /// What the program must put right in [answer], said to it; null when
  /// nothing is wrong. [steps] are what it did on the way, the articles it
  /// read among them. [said] tells what Folio did, for the lawyer.
  Future<String?> feedback(
    String answer,
    Iterable<AiStep> steps, {
    void Function(String note)? said,
    String? question,
  }) async {
    final problems = <String>[];
    serious = false;
    // A sentence reckoned without Folio's engine.
    if (question != null &&
        LegalGuide.asksCrime(question) &&
        !steps.any((s) => s.tool == FolioMcp.crimeTool)) {
      problems.add(
        '- Soru bir cezanın hesabını içeriyor ama ceza_hesapla aracını '
        'çağırmadın. Ceza aralığını, lehe kanunu, HAGB\'yi, ertelemeyi ve '
        'zamanaşımını şimdi ceza_hesapla ile hesapla (suç kodu ve olay '
        'tarihiyle) ve cevabını onun sonucuna göre düzelt.',
      );
    }
    // Not existing, repealed, unpublished.
    final checked = await mcp.call('atif_dogrula', {'metin': answer});
    for (final one in checked['atiflar'] as List? ?? const []) {
      if (one is! Map) continue;
      final written = '${one['yazilan'] ?? ''}';
      final state = one['durum'];
      if (state == 'yok' && !_saysAbsent(answer, written)) {
        problems.add(
          '- "$written" resmî kaynakta yok. Bu atfı çıkar; yerine bir '
          'dayanak göstereceksen önce araçla bul ve oku.',
        );
      } else if (state == 'mulga') {
        problems.add('- "$written" mülga. Buna dayanma.');
      } else if (state == 'mahkeme_belirsiz') {
        problems.add(
          '- "$written" kararının künyesinde mahkeme yok; Folio denetleyemedi. '
          'Mahkemeyi ve daireyi numarayla birlikte yaz '
          '(ör. "Yargıtay Hukuk Genel Kurulu, 2017/2348 E., 2019/82 K.").',
        );
      } else if (state == 'yayimlanmamis') {
        final court = '${one['mahkeme'] ?? ''}'.trim();
        problems.add(
          court.isEmpty
              ? '- "$written" yayımlanmamış bir karar; tam metni okunamaz. '
                    'Dayanacaksan bunu açıkça söyle.'
              : '- Folio "$written" künyesini "$court" kararı olarak okudu; '
                    'bu mahkemenin kararları yayımlanmaz. Kararı başka bir '
                    'mahkeme verdiyse mahkemeyi ve daireyi künyenin hemen '
                    'önüne yaz; vermediyse tam metni okunamadığını açıkça söyle.',
        );
      }
    }
    // How a decision was given, as the answer says it and as its text does.
    problems.addAll(await _votes(answer));
    // An article cited unread is not sent back: the program is told to
    // read before it rests on one, and a rewrite for it alone cost the
    // lawyer a second and third answer to a simple question
    // (13.11.2026). What does not exist or is repealed is still sent back.
    serious = problems.isNotEmpty;
    if (problems.isEmpty) return null;
    return [
      'Folio cevabını avukata göstermeden denetledi.',
      ...problems,
      'Cevabını baştan, tam olarak yeniden yaz. Dayandığın her madde '
          'söylediğin şeyi gerçekten söylüyor mu, metne bakarak denetle; '
          'söylemiyorsa o atfı çıkar ve doğru maddeyi araçla bul '
          '(hukuk_rehber, mevzuat_icindekiler, mevzuat_madde). Okumadığın '
          'bir maddeye dayanma. Bu notu cevabında anma.',
    ].join('\n\n');
  }

  /// The decisions the answer says were given unanimously or by majority,
  /// set against their own text; the most [mostRead].
  Future<List<String>> _votes(String answer) async {
    final out = <String>[];
    final (_, decisions) = await mcp.citationsIn(answer);
    var asked = 0;
    for (final d in decisions) {
      if (asked >= mostRead) break;
      final end = (d.start + d.length + 160).clamp(0, answer.length);
      final near = answer
          .substring((d.start - 160).clamp(0, answer.length), end)
          .toLowerCase();
      final saysMajority = RegExp(r'oy\s*[çc]oklu[ğg]u').hasMatch(near);
      final saysUnanimous = RegExp(r'oy\s*birli[ğg]i').hasMatch(near);
      if (saysMajority == saysUnanimous) continue;
      asked++;
      try {
        final got = await mcp.decision(d);
        final text = got.decision?.text ?? '';
        if (text.isEmpty) continue;
        final vote = FolioMcp.outcomeOf(text)['oy'];
        final written = answer.substring(d.start, d.start + d.length);
        if (saysUnanimous && vote == 'oy çokluğu') {
          out.add(
            '- "$written" oybirliğiyle değil, oy çokluğuyla verilmiş (kararın '
            'kendi metni). Düzelt.',
          );
        } else if (saysMajority && vote == 'oybirliği') {
          out.add(
            '- "$written" oy çokluğuyla değil, oybirliğiyle verilmiş (kararın '
            'kendi metni). Düzelt.',
          );
        }
      } catch (_) {}
    }
    return out;
  }

  /// Whether [answer] says itself that [written] does not exist: it is
  /// right, and not sent back for it.
  static bool _saysAbsent(String answer, String written) {
    final at = answer.indexOf(written);
    if (at < 0) return false;
    final near = answer
        .substring(
          (at - 40).clamp(0, answer.length),
          (at + written.length + 120).clamp(0, answer.length),
        )
        .toLowerCase();
    return const [
      'bulunmamakta',
      'yoktur',
      'mevcut değil',
      'yer almamakta',
      'yok.',
      'yok ',
      'olmayan',
      'bulunamadı',
    ].any(near.contains);
  }

  /// [feedback]'s findings as one short line for the lawyer.
  static String summary(int rounds, int read) => [
    'Folio cevabı denetledi',
    if (read > 0) '$read madde okuttu',
    if (rounds > 0) '$rounds kez düzelttirdi',
  ].join(' · ');
}

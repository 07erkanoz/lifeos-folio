import '../legal/citation.dart';
import 'ai_events.dart';
import 'folio_mcp.dart';

/// Folio's own look at an answer before the lawyer sees it. Every article
/// and decision the answer cites is looked up: one that does not exist, or
/// is repealed, must go; an article the answer rests on but the program
/// never read in this answer is read by Folio and handed back with its
/// official text. What it finds is said to the program, which writes its
/// answer again. A rule in its instructions is a request; this is a check.
class AnswerAudit {
  AnswerAudit(this.mcp);

  final FolioMcp mcp;

  /// The most articles Folio reads for one answer.
  static const mostRead = 4;

  /// What the program must put right in [answer], said to it; null when
  /// nothing is wrong. [steps] are what it did on the way, the articles it
  /// read among them. [said] tells what Folio did, for the lawyer.
  Future<String?> feedback(
    String answer,
    Iterable<AiStep> steps, {
    void Function(String note)? said,
  }) async {
    final problems = <String>[];
    final texts = <String>[];
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
    // Rested on, never read: read by Folio.
    final read = <String>{};
    for (final s in steps) {
      final asked = switch (s.tool) {
        'mevzuat_madde' => [s.args],
        // Several in one call: each counts as read.
        'mevzuat_toplu' => s.args['maddeler'] as List? ?? const [],
        _ => const [],
      };
      for (final a in asked) {
        final (articles, _) = await mcp.citationsIn(
          a is Map ? '${a['kanun'] ?? ''} m.${a['madde'] ?? ''}' : '$a',
        );
        read.addAll(articles.map(_key));
      }
    }
    final (cited, _) = await mcp.citationsIn(answer);
    final unread = <String, Citation>{};
    for (final c in cited) {
      final key = _key(c);
      if (!read.contains(key)) unread.putIfAbsent(key, () => c);
    }
    for (final c in unread.values.take(mostRead)) {
      final got = await mcp.call('mevzuat_madde', {
        'kanun': '${c.law.number}',
        'madde': '${c.article}${c.letter ?? ''}',
      });
      final text = '${got['metin'] ?? ''}'.trim();
      if (got['durum'] != 'bulundu' || text.isEmpty) continue;
      said?.call('Folio okudu: ${c.written}');
      texts.add(
        '"${c.written}" maddesine dayandın ama bu cevapta okumadın. Folio '
        'okudu, resmî metni:\n${text.length > 6000 ? '${text.substring(0, 6000)}…' : text}',
      );
    }
    if (problems.isEmpty && texts.isEmpty) return null;
    return [
      'Folio cevabını avukata göstermeden denetledi.',
      ...problems,
      ...texts,
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

  static String _key(Citation c) =>
      '${c.law.number}|${c.article}${c.letter ?? ''}';

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

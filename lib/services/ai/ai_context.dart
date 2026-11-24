import 'dart:convert';

import 'ai_assistant.dart';

/// A long conversation with the lawyer's AI program started again from
/// Folio's own record of it, between two questions and never in the middle
/// of an answer.
///
/// Why (banaozel, measured 21 Kasım 2026): the program remembers nothing of
/// itself; each of its calls sends the whole conversation again. One
/// conversation grew to 931 thousand tokens a call, and two lawyers'
/// five-hour quota ran out in two hours: most of it went on carrying the
/// documents read long before. Claude Code's own compaction comes only when
/// its window is full, in the middle of an answer, and turns what it was
/// reading into a summary.
///
/// banaozel asks the program for a summary (`/compact`). Folio does not
/// need one: it keeps the conversation itself (the questions, the answers
/// as they were shown, the documents the lawyer added, the steps taken).
/// When the conversation at the end of an answer is larger than the
/// ceiling, the next question starts a new session given all of that:
/// every question and answer word for word, the added documents again, the
/// case named, and an exact index of what was read — documents, decisions,
/// articles — taken from the steps by code, not written by a model. What
/// goes is only the texts the tools gave back; the index names them for
/// the program to read again. A case's memory is its conversations and
/// findings as they are ([AiMemory]); nothing of this changes it.
class AiContext {
  /// Tokens at the end of an answer above which the next question starts a
  /// new session. banaozel's: 300 thousand was too narrow for a legal
  /// analysis; 400 thousand holds two case reviews and their follow-ups.
  static const defaultCeiling = 400000;
  static const choices = [300000, 400000, 500000, 600000];

  /// Answers to go between two restarts, unless the conversation is past
  /// [hardFactor] times the ceiling: the documents just read stay at hand
  /// for the next question.
  static const betweenTurns = 3;
  static const hardFactor = 2.0;

  /// How large the conversation was at the end of an answer, from Claude
  /// Code's result: its last call (`usage.iterations`), not the turn's sum
  /// (twelve calls of 360 thousand add up to millions). Null when it is not
  /// told: no decision is taken on a size not known.
  static int? endOfTurn(Object? usage) {
    if (usage is! Map) return null;
    final iterations = usage['iterations'];
    if (iterations is! List || iterations.isEmpty) return null;
    final last = iterations.last;
    if (last is! Map) return null;
    int n(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
    final sum =
        n(last['input_tokens']) +
        n(last['cache_read_input_tokens']) +
        n(last['cache_creation_input_tokens']) +
        n(last['output_tokens']);
    return sum > 0 ? sum : null;
  }

  /// [endOfTurn] of Claude Code's output: one JSON object, or a line an
  /// event with the result last.
  static int? fromClaudeOutput(String stdout) {
    Map? result;
    try {
      final whole = jsonDecode(stdout.trim());
      if (whole is Map && whole['type'] == 'result') result = whole;
    } on FormatException {
      for (final line in stdout.trim().split('\n').reversed) {
        if (!line.startsWith('{')) continue;
        try {
          final e = jsonDecode(line);
          if (e is Map && e['type'] == 'result') {
            result = e;
            break;
          }
        } on FormatException {
          continue;
        }
      }
    }
    return endOfTurn(result?['usage']);
  }

  /// Whether the next question starts a new session. [ceiling] 0 is off;
  /// [since] the answers since the last restart, null for none yet.
  static bool needed(int? size, int ceiling, {int? since}) {
    if (ceiling <= 0 || size == null || size < ceiling) return false;
    if (since == null || since >= betweenTurns) return true;
    return size >= ceiling * hardFactor;
  }

  /// Before a question to [provider] in [thread]: whether it starts a new
  /// session now, its program's record of the old one let go of.
  static bool beforeQuestion(AiThread thread, AiProvider provider) {
    if (!thread.restart.remove(provider)) return false;
    thread.ids.remove(provider);
    return true;
  }

  /// After an answer: whether the next question starts a new session, by
  /// the size the program told and the answers since the last start.
  static void afterAnswer(
    AiThread thread,
    AiProvider provider,
    int ceiling, {
    required bool restarted,
  }) {
    final since = thread.sinceRestart;
    thread.sinceRestart = restarted
        ? 1
        : since == null
        ? null
        : since + 1;
    if (needed(thread.size[provider], ceiling, since: thread.sinceRestart)) {
      thread.restart.add(provider);
    }
  }

  static String shown(int tokens) => '${(tokens / 1000).round()} bin';

  /// What the program is told with the first question of the new session.
  static const note =
      '[SOHBET YENİDEN BAŞLATILDI — Folio’nun notu; avukat yazmadı]\n'
      'Bu sohbet çok uzadığı için Folio onu kendi kaydından yeniden başlattı. '
      'Önceki sorular ve cevaplar aynen, avukatın eklediği belgeler yeniden '
      'verildi. Önceki araç sonuçları (evrak, karar ve mevzuat metinleri) '
      'artık bağlamında yok:\n'
      '- Bir evraktan alıntı yapacak, bir tarihe, tutara ya da sayfaya '
      'dayanacak, bir kararın gerekçesini anlatacaksan önce ilgili aracı '
      'yeniden çağırıp metni oku. Önceki cevaplarındaki değeri kaynak '
      'gösterme.\n'
      '- Künye, madde ve süre için “bu sohbette daha önce doğrulandı” '
      'sayılmaz; yeni bir iddiada yeniden doğrula.\n'
      '- Dosyanın kalıcı tespitleri için dosya_hafizasi aracına bak.\n'
      '- Önceki cevap ile araç sonucu çelişirse araç sonucu geçerlidir.\n'
      'Avukata yeniden başlatmadan söz etmen gerekmez; işe kaldığın yerden '
      'devam et.';

  static const _most = 12000;
  static const _each = 60;

  /// The exact index of what the conversation's [steps] read and wrote,
  /// taken from their tools and inputs: none of it written by a model, and
  /// none of the texts themselves. [attached] the documents the lawyer
  /// added, by name; [cases] the cases it was about. Empty when there is
  /// nothing to list.
  static String index(
    Iterable<AiStep> steps, {
    Iterable<String> attached = const [],
    Iterable<String> cases = const [],
  }) {
    final parts = <String, List<String>>{
      for (final k in _titles.keys) k: <String>[],
    };
    void add(String part, String line) {
      line = line.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (line.isEmpty || parts[part]!.contains('- $line')) return;
      parts[part]!.add('- $line');
    }

    String s(Object? v, [int most = 120]) {
      final t = '${v ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
      return t.length > most ? '${t.substring(0, most)}…' : t;
    }

    for (final c in cases) {
      add('dosya', s(c));
    }
    for (final a in attached) {
      add('ek', s(a, 160));
    }
    for (final step in steps) {
      final tool = step.tool.split('__').last;
      final a = step.args;
      switch (tool) {
        case 'evrak_oku':
          final piece = a['parca'];
          add(
            'evrak',
            'anahtar: ${s(a['anahtar'])}'
                '${piece != null && '$piece' != '1' ? ' (parça $piece)' : ''}',
          );
        case 'dosya_sec':
          add('dosya', 'anahtar: ${s(a['anahtar'])}');
        case 'karar_getir':
          add(
            'karar',
            [
              if (s(a['kunye']).isNotEmpty) s(a['kunye']),
              if (s(a['kimlik']).isNotEmpty) 'kimlik: ${s(a['kimlik'])}',
            ].join(' · '),
          );
        case 'emsal_getir' || 'kurul_karar_getir' || 'doktrin_getir':
          add('karar', '$tool(${s(a['kimlik'])})');
        case 'kunye_dogrula':
          add(
            'karar',
            'denetlendi: ${s(a['daire'] ?? a['mahkeme'] ?? '')} '
                'E.${s(a['esas'])} K.${s(a['karar'])}',
          );
        case 'mevzuat_madde':
          add('mevzuat', '${s(a['kanun'], 40)} m.${s(a['madde'], 20)}');
        case 'mevzuat_toplu':
          for (final m in a['maddeler'] as List? ?? const []) {
            if (m is Map) {
              add('mevzuat', '${s(m['kanun'], 40)} m.${s(m['madde'], 20)}');
            }
          }
        case 'mevzuat_belge_getir':
          add('mevzuat', 'belge: ${s(a['kimlik'])}');
        case 'sure_hesapla':
          add(
            'mevzuat',
            'süre: ${s(a['madde'], 40)} · ${s(a['miktar'], 10)} '
                '${s(a['birim'], 10)} · ${s(a['baslangic'] ?? a['tarih'], 20)}',
          );
        case 'taslak_oner':
          add('belge', '«${s(a['baslik'], 120)}»');
        case 'bulgu_oner':
          for (final b in a['bulgular'] as List? ?? const []) {
            add('bulgu', s(b is Map ? b['metin'] ?? b['baslik'] ?? b : b, 160));
          }
      }
    }
    final out = <String>[];
    for (final e in _titles.entries) {
      final lines = parts[e.key]!;
      if (lines.isEmpty) continue;
      out.add('${e.value}:');
      out.addAll(lines.take(_each));
      if (lines.length > _each) {
        out.add('  … ${lines.length - _each} satır daha (gösterilmedi)');
      }
    }
    if (out.isEmpty) return '';
    var text =
        '[KESİN DİZİN — Folio sohbetin adımlarından kodla çıkardı; model '
        'yazmadı]\n'
        'Önceki bölümde okunanların ve yazılanların kimlikleri. Liste '
        'tamdır ama yalnız kimlik taşır: bir kayda dayanacaksan metnini '
        'yeniden oku.\n${out.join('\n')}';
    if (text.length > _most) {
      text =
          '${text.substring(0, text.lastIndexOf('\n', _most))}\n'
          '⚠ Dizin kesildi (boy sınırı); listeyi tam sayma.';
    }
    return text;
  }

  static const _titles = {
    'dosya': 'ÜZERİNDE ÇALIŞILAN DOSYALAR',
    'ek': 'AVUKATIN EKLEDİĞİ BELGELER (bu mesajda yeniden verildi)',
    'evrak':
        'OKUNAN EVRAKLAR (metinleri bağlamda yok; evrak_oku ile yeniden oku)',
    'karar': 'AÇILAN VE DENETLENEN KARARLAR',
    'mevzuat': 'OKUNAN MEVZUAT MADDELERİ VE HESAPLANAN SÜRELER',
    'belge': 'AVUKATA SUNULAN TASLAKLAR',
    'bulgu': 'AVUKATA SUNULAN BULGULAR',
  };
}

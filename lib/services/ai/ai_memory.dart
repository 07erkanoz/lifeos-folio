import 'dart:math';

/// What the lawyer's AI program leaves of a case, kept in Folio's own
/// database (PortalAi) and on the lawyer's own devices alone: its
/// conversations, the findings the lawyer agreed to keep, and the drafts it
/// wrote. The case's memory is made of these as they are, never of a
/// summary the program wrote of itself.
abstract final class AiMemory {
  static const chat = 'sohbet', finding = 'bulgu', draft = 'taslak';

  /// A finding's kinds, as the program names them and the lawyer reads.
  static const kinds = {
    'olgu': 'Olgu',
    'belge': 'Belgeden tespit',
    'mahkeme': 'Mahkemenin tespiti',
    'strateji': 'Strateji',
    'acik_soru': 'Açık soru',
    'yapilacak': 'Yapılacak',
    'cikarim': 'Yapay zekâ çıkarımı',
  };

  /// The most of a conversation kept: its last turns, each answer cut.
  static const keptTurns = 60, keptAnswer = 20000;

  /// Earlier conversations given in the memory, and how much of each.
  static const memoryChats = 5,
      memoryQuestions = 20,
      questionLength = 180,
      answerLength = 4000;

  static String id() {
    final r = Random.secure();
    return [
      DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      for (var i = 0; i < 3; i++) r.nextInt(1 << 30).toRadixString(36),
    ].join('-');
  }

  static String _cut(String text, int most) =>
      text.length <= most ? text : '${text.substring(0, most)}…';

  /// A conversation as kept: [turns] of `soru`, `cevap`, `yazan`, `zaman`.
  static Map<String, Object?> chatRecord({
    required String title,
    required String document,
    required DateTime started,
    required List<Map<String, Object?>> turns,
    String? court,
    String? number,
  }) {
    final kept = turns.length > keptTurns
        ? turns.sublist(turns.length - keptTurns)
        : turns;
    return {
      'baslik': _cut(title, 120),
      'belge': document,
      'mahkeme': ?court,
      'esas': ?number,
      'basladi': started.toIso8601String(),
      'guncellendi': DateTime.now().toIso8601String(),
      'turlar': [
        for (final t in kept)
          {...t, 'cevap': _cut('${t['cevap'] ?? ''}', keptAnswer)},
      ],
    };
  }

  static List<Map<String, Object?>> turnsOf(Map<String, Object?> chat) => [
    for (final t in chat['turlar'] as List? ?? const [])
      if (t is Map) t.cast<String, Object?>(),
  ];

  static DateTime? _at(Object? text) => DateTime.tryParse('${text ?? ''}');

  /// What the program reads of a case before it works on it again: the
  /// findings standing and those found wrong, the drafts it wrote, its
  /// earlier conversations (the questions, and each one's fullest answer),
  /// and the documents come since the last of them. [current] is the
  /// conversation going on, left out.
  static Map<String, Object?> build({
    required List<Map<String, Object?>> chats,
    required List<Map<String, Object?>> findings,
    required List<Map<String, Object?>> drafts,
    required List<({String title, DateTime? date})> documents,
    String? current,
  }) {
    final earlier = [
      for (final c in chats)
        if (c['id'] != current) c,
    ]..sort((a, b) => '${b['guncellendi']}'.compareTo('${a['guncellendi']}'));
    final last = earlier.isEmpty ? null : _at(earlier.first['guncellendi']);
    final standing = [
      for (final f in findings)
        if (f['yanlis'] == null) f,
    ];
    final wrong = [
      for (final f in findings)
        if (f['yanlis'] case final Map w) (f, w),
    ];
    return {
      'durum': 'bulundu',
      'not':
          'Bu hafıza kanıt değildir: avukatın kaydettiği bulgular ve önceki '
          'konuşmalardır. Bir şeye dayanacaksan kaynağını evrak_oku, '
          'mevzuat_madde ya da karar_getir ile yeniden oku.',
      'bulgular': [
        for (final f in standing)
          {
            'tur': kinds[f['tur']] ?? f['tur'],
            'metin': f['metin'],
            'kaynaklar': f['kaynaklar'],
            'zaman': f['zaman'],
          },
      ],
      if (wrong.isNotEmpty)
        'yanlis_bulunanlar': [
          for (final (f, w) in wrong)
            {'metin': f['metin'], 'neden': w['neden']},
        ],
      'taslaklar': [
        for (final d in drafts) {'baslik': d['baslik'], 'zaman': d['zaman']},
      ],
      'onceki_sohbetler': [
        for (final c in earlier.take(memoryChats))
          () {
            final turns = turnsOf(c);
            final fullest = turns.isEmpty
                ? ''
                : turns
                      .map((t) => '${t['cevap'] ?? ''}')
                      .reduce((a, b) => b.length > a.length ? b : a);
            return {
              'baslik': c['baslik'],
              'zaman': c['guncellendi'],
              'sorular': [
                for (final t in turns.take(memoryQuestions))
                  _cut('${t['soru'] ?? ''}', questionLength),
              ],
              'en_kapsamli_cevap': _cut(fullest, answerLength),
            };
          }(),
      ],
      if (last != null)
        'son_sohbetten_beri_gelen_evrak': [
          for (final d in documents)
            if (d.date != null && d.date!.isAfter(last)) d.title,
        ],
    };
  }

  /// The line the question opens with when the case has a memory: for the
  /// program to read it first. Null for a case with none.
  static String? hint(Map<String, int> counts) {
    final findings = counts[finding] ?? 0,
        chats = counts[chat] ?? 0,
        drafts = counts[draft] ?? 0;
    if (findings + chats + drafts == 0) return null;
    return 'Bu dosyada önceki çalışma var: $findings bulgu, $chats sohbet, '
        '$drafts taslak. Soruya geçmeden önce dosya_hafizasi aracıyla '
        'dosyanın hafızasını oku.';
  }

  /// The quoted parts of [text]: what stands between quotation marks.
  static List<String> quotes(String text) => [
    for (final m in RegExp(r'["“”«»]([^"“”«»]{8,})["“”«»]').allMatches(text))
      m[1]!.trim(),
  ];

  /// [text] as quotes are looked for in it: one space, no case.
  static String plain(String text) => text
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('İ', 'i')
      .replaceAll('I', 'ı')
      .toLowerCase()
      .trim();
}

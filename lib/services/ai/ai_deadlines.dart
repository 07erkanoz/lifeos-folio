import 'dart:convert';

import '../legal/deadlines/deadline_service.dart';
import '../legal/deadlines/kural_bilgisi.dart';
import '../legal/deadlines/mahkeme_kategori.dart';
import '../legal/deadlines/sure_katalogu.dart';
import '../uets/deadline_choice.dart';
import 'ai_assistant.dart';

/// One time or task an AI program drew out of a notice, for the lawyer to
/// approve: what it is, the time and its article, the event it runs from,
/// and the sentence of the notice it rests on. Its last day is never the
/// program's: Folio's engine reckons it ([lastDay]).
class AiDeadlineSuggestion {
  const AiDeadlineSuggestion({
    required this.what,
    this.amount = 0,
    this.unit,
    this.article = '',
    this.nature = 'kanuni',
    this.startEvent = 'teblig',
    this.startDay,
    this.quote = '',
    this.whose = 'belirsiz',
    this.until,
    this.warning = '',
  });

  final String what;

  /// The time; 0 with no [unit] for a task the notice gives no time for.
  final int amount;
  final SureBirimi? unit;
  final String article;

  /// 'kanuni', 'hakim' or 'maddi' (see [SureNiteligi]).
  final String nature;

  /// 'teblig', 'tefhim', 'karar', 'ilan' or 'ogrenme', and that event's day
  /// when it is not the notice's service.
  final String startEvent;
  final DateTime? startDay;
  final String quote;

  /// Whose the work is: 'muvekkil' (the lawyer's client, the lawyer's to
  /// do), 'karsi' (the other side's), 'mahkeme' or 'belirsiz'.
  final String whose;

  /// A time given up to a day ("ilk duruşma gününe kadar"), not a length:
  /// kept as a task on that day, never turned into a count of days.
  final DateTime? until;

  /// What Folio found wrong with it ("ceza dosyasında HMK maddesi").
  final String warning;

  /// Not the lawyer's to do: shown, not ticked.
  bool get others => whose == 'karsi' || whose == 'mahkeme';

  /// What the time rests on, as the lawyer reads it.
  String get _basis => article.isNotEmpty
      ? article
      : nature == 'hakim'
      ? 'Hâkimin verdiği süre'
      : 'Dayanak yazılmadı';

  bool get isTask => unit == null || amount < 1 || until != null;

  YasalSure get rule => YasalSure(
    ad: what,
    miktar: amount,
    birim: unit ?? SureBirimi.gun,
    kanunMaddesi: _basis,
    nitelik: SureNiteligi.values.asNameMap()[nature] ?? SureNiteligi.kanuni,
  );

  /// The last day by Folio's engine, from [served] (the notice's service)
  /// or [startDay]; null for a task.
  DeadlineItem? lastDay(
    DateTime served,
    MahkemeKategorisi court, {
    DateTime? now,
  }) {
    if (isTask) return null;
    return DeadlineService.computeFromOzelSure(
      baslangic: startDay ?? served,
      sure: rule,
      kategori: court,
      now: now,
    ).items.firstOrNull;
  }

  /// The catalogue's rule this is, when one has its article, time and
  /// start: then the catalogue's own rule is kept, not one made of this.
  String? get catalogueRule {
    String key(String v) => v
        .toLowerCase()
        .replaceAll(RegExp(r'[\s.]'), '')
        .replaceAll('madde', 'm');
    for (final r in choosableRules.expand((g) => g.rules)) {
      if (key(r.kanunMaddesi) == key(article) &&
          r.miktar == amount &&
          r.birim == unit) {
        return kuralBilgisi(r)?.id;
      }
    }
    return null;
  }

  /// As kept for the notice once the lawyer approved it.
  DeadlineChoice choice({
    required String id,
    required String noticeId,
    required String model,
    DateTime? now,
  }) {
    final known = catalogueRule;
    return DeadlineChoice(
      id: id,
      noticeId: noticeId,
      ruleId: known ?? 'ozel',
      amount: amount,
      unit: unit ?? SureBirimi.gun,
      purpose: what,
      startEvent: startEvent,
      startDay: startDay == null
          ? null
          : '${startDay!.year}-${startDay!.month.toString().padLeft(2, '0')}-'
                '${startDay!.day.toString().padLeft(2, '0')}',
      created: now ?? DateTime.now(),
      article: _basis,
      nature: nature,
      source: 'yapay_zeka',
      quote: quote,
      model: model,
    );
  }
}

abstract final class AiDeadlines {
  /// What the program is asked for a notice: [text] is the envelope's and
  /// the documents' text, [served] the day of service as Folio reckoned it.
  static String prompt({
    required String text,
    required DateTime served,
    String unit = '',
    String subject = '',
    String side = '',
    List<String> known = const [],
  }) {
    String day(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    return [
      'Görev: Aşağıdaki UETS tebligatından avukatın yapması gereken işleri '
          've süreleri çıkar.',
      'Tebliğ tarihi (Folio hesapladı): ${day(served)}.',
      if (unit.isNotEmpty) 'Gönderen birim: $unit.',
      if (subject.isNotEmpty) 'Konu: $subject.',
      if (side.isNotEmpty)
        'Avukatın bu dosyadaki müvekkili: $side.'
      else
        'Avukatın bu dosyada hangi tarafı temsil ettiği bilinmiyor; taraf '
            'varsayma.',
      if (known.isNotEmpty) ...[
        '',
        'Folio\'nun kural motoru bu tebligatta şu süreleri buldu:',
        for (final k in known) '- $k',
        'Bunları tekrar yazma; yalnız bunların dışında kalan süreleri ve '
            'işleri yaz. Hiçbiri yoksa boş liste ver.',
      ] else ...[
        '',
        'Folio\'nun kural motoru bu tebligatta süre bulamadı.',
      ],
      '',
      '<tebligat>',
      text,
      '</tebligat>',
      '',
      'Kurallar:',
      '- Yalnız tebligatta gerçekten yazan ya da tebliğ edilen belgenin '
          'türünden kanunen doğan süreleri ve işleri yaz. Tahmin etme.',
      '- Kanundan doğan bir süre için dayandığı maddeyi mevzuat_madde ile '
          'oku ve dosyanın yargı koluna (hukuk HMK, ceza CMK, icra İİK, idari '
          'İYUK) uygun maddeyi yaz. Hâkimin ya da mahkemenin verdiği süre için '
          'madde yazma, nitelik "hakim" olsun.',
      '- Karşı tarafın dilekçesi, bilirkişi raporu ya da kararın tebliği gibi '
          'belgelerin türünden doğan süreyi ancak tebliğ edilen belge gerçekten '
          'o türse yaz; zarfta adı geçmesi yetmez, ekin ne olduğuna bak.',
      '- Süre bir tarihe kadar verildiyse (ör. "ilk duruşma gününe kadar", '
          '"15.01.2027 tarihine kadar") gün sayısına çevirme: miktarı 0 bırak, '
          'tarihi biliyorsan "son_tarih" alanına YYYY-AA-GG yaz.',
      '- Son günü hesaplama; Folio hesaplar. Yalnız süreyi ve neyin '
          'tarihinden işlediğini yaz.',
      '- Her öneri için tebligattaki cümleyi kelimesi kelimesine alıntıla.',
      '- Süre yazmayan bir iş (ör. "tanık listesi verilecek") de yaz; '
          'miktarı 0 ve birimi boş bırak.',
      '- Her öneride işin kimde olduğunu yaz: muvekkil (avukatın '
          'müvekkili), karsi (karşı taraf), mahkeme ya da belirsiz. Süre '
          'yalnız karşı tarafa verildiyse karsi yaz.',
      '',
      'Cevabın yalnız şu biçimde tek bir ```json bloğu olsun:',
      '```json',
      '{"oneriler": [{"ne": "Cevap dilekçesi verilecek", "miktar": 2, '
          '"birim": "hafta", "madde": "HMK m.127", "nitelik": "kanuni", '
          '"baslangic": "teblig", "baslangic_tarihi": null, '
          '"alinti": "...tebliğden itibaren iki hafta içinde...", '
          '"kimde": "muvekkil", "son_tarih": null}]}',
      '```',
      'birim: gun, is_gunu, hafta, ay, yil ya da boş. nitelik: kanuni, '
          'hakim ya da maddi. baslangic: teblig, tefhim, karar, ilan ya da '
          'ogrenme; tebliğden başka bir olaysa baslangic_tarihi YYYY-AA-GG.',
    ].join('\n');
  }

  /// The suggestions in [answer]; empty when it gives none. A suggestion
  /// whose sentence is not in [text] is left out: the program may have made
  /// it up.
  static List<AiDeadlineSuggestion> parse(
    String answer, {
    String text = '',
    MahkemeKategorisi? court,
    Set<String> knownRules = const {},
  }) {
    final block =
        RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(answer)?[1] ??
        answer.substring(
          answer.indexOf('{').clamp(0, answer.length),
          (answer.lastIndexOf('}') + 1).clamp(0, answer.length),
        );
    Object? json;
    try {
      json = jsonDecode(block.trim());
    } on FormatException {
      return const [];
    }
    final list = json is Map ? json['oneriler'] : json;
    if (list is! List) return const [];
    String fold(String v) => v
        .toLowerCase()
        .replaceAll(RegExp(r'[“”"…\.]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final source = fold(text);
    return [
      for (final o in list)
        if (o is Map && '${o['ne'] ?? ''}'.trim().isNotEmpty)
          if (_suggestion(o, court) case final s?
              when (text.isEmpty ||
                      s.quote.isEmpty ||
                      source.contains(fold(s.quote))) &&
                  // What the rules found already is not said twice.
                  !knownRules.contains(s.catalogueRule))
            _timeSaid(s),
    ];
  }

  /// A time whose sentence says no time ("BU ZARFTA İstinaf Cevap Dilekçesi
  /// VARDIR"): measured on real notices, a time the program made up from a
  /// document's name. Kept as a task, with the time taken off and said so.
  static final _timeWords = RegExp(
    r'\b(gün|gun|hafta|ay|yıl|yil|süre|sure|saat)',
    caseSensitive: false,
  );

  static AiDeadlineSuggestion _timeSaid(AiDeadlineSuggestion s) {
    if (s.isTask || _timeWords.hasMatch(s.quote)) return s;
    return AiDeadlineSuggestion(
      what: s.what,
      article: s.article,
      nature: s.nature,
      startEvent: s.startEvent,
      quote: s.quote,
      whose: s.whose,
      warning: [
        if (s.warning.isNotEmpty) s.warning,
        'Yapay zekâ ${s.rule.sureMetni} süre önerdi, ama dayandığı cümlede '
            'süre yazmıyor; süre eklenmedi.',
      ].join(' '),
    );
  }

  /// The codes whose articles belong to a jurisdiction: an article of
  /// another's is said to the lawyer ("HMK m.127" for a criminal case).
  static const _codes = {
    MahkemeKategorisi.hukuk: {'HMK', 'TBK', 'TMK', 'TTK', 'İİK'},
    MahkemeKategorisi.ceza: {'CMK', 'TCK'},
    MahkemeKategorisi.icra: {'İİK', 'HMK'},
    MahkemeKategorisi.idare: {'İYUK', 'VUK', '2577'},
    MahkemeKategorisi.vergi: {'İYUK', 'VUK', '2577', '213'},
  };

  static String _misplaced(String article, MahkemeKategorisi? court) {
    final own = _codes[court];
    if (own == null || article.isEmpty) return '';
    final code = RegExp(r'^(HMK|TBK|TMK|TTK|İİK|CMK|TCK|İYUK|VUK)\b')
        .firstMatch(
          article
              .replaceAll('IIK', 'İİK')
              .toUpperCase()
              .replaceAll('İIK', 'İİK'),
        )?[1];
    if (code == null || own.contains(code)) return '';
    return '$code maddesi bu yargı koluna uymuyor; dayanağı denetleyin.';
  }

  /// Whether [text] writes [day]: 15/01/2027, 15.01.2027, 15-01-2027 or
  /// 2027-01-15.
  static bool _says(String text, DateTime day) {
    final d = day.day.toString().padLeft(2, '0');
    final m = day.month.toString().padLeft(2, '0');
    return RegExp('0?${day.day}[./-]0?${day.month}[./-]${day.year}')
            .hasMatch(text) ||
        text.contains('${day.year}-$m-$d');
  }

  static AiDeadlineSuggestion? _suggestion(Map o, MahkemeKategorisi? court) {
    final amount = o['miktar'] is num
        ? (o['miktar'] as num).toInt()
        : int.tryParse('${o['miktar'] ?? ''}') ?? 0;
    final unit = switch ('${o['birim'] ?? ''}'.trim()) {
      'gun' || 'gün' => SureBirimi.gun,
      'is_gunu' || 'iş günü' => SureBirimi.isGunu,
      'hafta' => SureBirimi.hafta,
      'ay' => SureBirimi.ay,
      'yil' || 'yıl' => SureBirimi.yil,
      _ => null,
    };
    final start = '${o['baslangic'] ?? 'teblig'}'.trim();
    final day = DateTime.tryParse('${o['baslangic_tarihi'] ?? ''}');
    final nature = '${o['nitelik'] ?? 'kanuni'}'.trim();
    // A day of the notice's own only ("15/01/2027 tarihine kadar"): one
    // the program reckoned itself (measured: it wrote its own last day
    // there) would pass the engine by.
    final quoted = '${o['alinti'] ?? ''}';
    final named = DateTime.tryParse('${o['son_tarih'] ?? ''}');
    final until = named != null && _says(quoted, named) ? named : null;
    final article = '${o['madde'] ?? ''}'
        .trim()
        .replaceAll('[doğrulanmalı]', '')
        .trim();
    return AiDeadlineSuggestion(
      what: '${o['ne']}'.trim(),
      amount: unit == null ? 0 : amount,
      unit: amount < 1 ? null : unit,
      article: nature == 'hakim' ? '' : article,
      until: until,
      warning: nature == 'hakim' ? '' : _misplaced(article, court),
      nature: const {'kanuni', 'hakim', 'maddi'}.contains(nature)
          ? nature
          : 'kanuni',
      startEvent:
          const {'teblig', 'tefhim', 'karar', 'ilan', 'ogrenme'}.contains(start)
          ? start
          : 'teblig',
      // A day other than the service only for another event.
      startDay: start == 'teblig' ? null : day,
      whose:
          const {
            'muvekkil',
            'karsi',
            'mahkeme',
          }.contains('${o['kimde'] ?? ''}'.trim())
          ? '${o['kimde']}'.trim()
          : 'belirsiz',
      quote: '${o['alinti'] ?? ''}'
          .trim()
          .replaceAll(RegExp(r'^[.…]+|[.…]+$'), '')
          .trim(),
    );
  }

  /// [text] asked of [provider] at the light tier; the suggestions found.
  static Future<List<AiDeadlineSuggestion>> ask(
    AiProvider provider, {
    required String text,
    required DateTime served,
    String unit = '',
    String subject = '',
    String side = '',
    List<String> known = const [],
    Set<String> knownRules = const {},
    MahkemeKategorisi? court,
    void Function(AiEvent event)? onEvent,
    Future<void>? cancel,
  }) async {
    final settings = await AiSettings.load();
    final shown = settings.mask ? AiAssistant.maskIdentityNumbers(text) : text;
    final cut = shown.length > 60000 ? shown.substring(0, 60000) : shown;
    final answer = await AiAssistant.ask(
      provider,
      prompt(
        text: cut,
        served: served,
        unit: unit,
        subject: subject,
        side: side,
        known: known,
      ),
      model: settings.modelFor(provider, AiTier.light),
      tier: AiTier.light,
      onEvent: onEvent,
      cancel: cancel,
    );
    return parse(answer, text: cut, court: court, knownRules: knownRules);
  }
}

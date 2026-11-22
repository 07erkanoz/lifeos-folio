import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../ai/ai_case.dart';
import '../ai/ai_groq.dart';
import '../ai/ai_usage.dart';

/// What Live may call, and what answers it.
abstract class LiveToolBox {
  /// The declarations for a new session: what this conversation needs now.
  Future<List<Map<String, Object?>>> declarations();

  /// [name] run with [args]; [question] is what the lawyer last said.
  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> args, {
    String question = '',
  });

  /// Written into a new session after the conversation's lines: the last
  /// summaries, so that "that decision" still means something.
  String get remembered => '';

  /// What the summaries cost, dollars.
  double get spent => 0;
}

/// Folio's own tools for Live, the way AvukatOS Asistan (`canli_araclar.dart`)
/// keeps the cost down, since Live re-bills every declaration every turn:
///
/// - Only the core tools are declared; the rest are found with
///   [findTool] (on this computer, free) and run with [runTool]. A tool
///   found and run in a conversation is declared in its next sessions.
/// - A long answer is summarized by Gemini Flash for the question asked;
///   Live sees the summary and a `metin_id`, the whole is kept here and
///   asked with [askText], word for word.
/// - Heavier work (a draft, a long reading) goes to the lawyer's AI program
///   ([brainTool]).
///
/// The tools are Folio's MCP tools run in Folio itself ([FolioToolHost]),
/// the same the AI panel's API services use: Folio's data, within the
/// lawyer's rights, secret notes hidden.
class FolioLiveTools implements LiveToolBox {
  FolioLiveTools({
    required this.brain,
    Future<FolioToolHost> Function()? host,
    Future<String> Function(String prompt, int most)? flash,
  }) : _host = host ?? _here,
       _flashOverride = flash;

  static Future<FolioToolHost> _here() async =>
      FolioToolsHere(await AiCaseSession.open(null));

  final Future<String> Function(String question) brain;
  final Future<FolioToolHost> Function() _host;
  final Future<String> Function(String prompt, int most)? _flashOverride;

  static const findTool = 'arac_bul',
      runTool = 'arac_calistir',
      askText = 'metinde_sor',
      brainTool = 'folio_ajan_sor';

  /// Declared in every session.
  static const core = {
    'ajanda',
    'tebligatlar',
    'uyap_bildirimleri',
    'dosyalar',
    'dosya_ara',
    'dosya_sec',
    'dosya_bilgisi',
    'dosya_evraklari',
    'evrak_oku',
    'mevzuat_madde',
    'karar_ara',
    'sure_hesapla',
  };

  /// Put before the lawyer in the AI panel: there is no panel here.
  static const _panelOnly = {'bulgu_oner', 'taslak_oner'};

  static const _summaryOver = 2500, _keptAsIs = 600, _mostPromoted = 8;
  static const flashModel = 'gemini-3.8-flash';

  FolioToolHost? _ready;
  Map<String, Map<String, Object?>>? _all;
  final _promoted = <String>{};
  final _texts = <String, (String, String)>{};
  final _summaries = <String>[];
  int _textCount = 0;
  double _spent = 0;

  @override
  double get spent => _spent;

  Future<Map<String, Map<String, Object?>>> _tools() async {
    if (_all case final all?) return all;
    final host = _ready ??= await _host();
    return _all = {
      for (final t in await host.tools())
        if (!_panelOnly.contains(t['name'])) '${t['name']}': t,
    };
  }

  static Map<String, Object?> _declare(Map<String, Object?> t) => {
    'name': t['name'],
    'description': '${t['description'] ?? ''}',
    'parametersJsonSchema':
        t['inputSchema'] ??
        {'type': 'object', 'properties': <String, Object?>{}},
  };

  @override
  Future<List<Map<String, Object?>>> declarations() async {
    final all = await _tools();
    return [
      for (final t in all.values)
        if (core.contains(t['name']) || _promoted.contains(t['name']))
          _declare(t),
      _find(all),
      _run,
      _ask,
      _brain,
    ];
  }

  @override
  String get remembered => _summaries.isEmpty
      ? ''
      : '\n\nSon araç özetleri (metin_id ile asılları sorulabilir):\n'
            '${_summaries.join('\n')}';

  /// What may be found, by kind, for the description of [findTool].
  static String _map(Map<String, Map<String, Object?>> all) {
    final rest = [
      for (final n in all.keys)
        if (!core.contains(n)) n,
    ];
    return rest.join(', ');
  }

  Map<String, Object?> _find(Map<String, Map<String, Object?>> all) => {
    'name': findTool,
    'description':
        'Elindeki araçlarla yapamadığın bir istekte "yapamam" demeden ÖNCE '
        'bunu çağır: ihtiyacı kendi sözlerinle yaz; uygun araçları (ad, '
        'açıklama, parametreler) döndürür, sonra $runTool ile çalıştır. '
        'Bulunabilecek araçlar: ${_map(all)}.',
    'parametersJsonSchema': {
      'type': 'object',
      'properties': {
        'ihtiyac': {
          'type': 'string',
          'description': 'ne gerekiyor, ör. "icra dosyasında kasa durumu"',
        },
      },
      'required': ['ihtiyac'],
    },
  };

  static const _run = {
    'name': runTool,
    'description': '$findTool ile bulunan bir aracı çalıştırır.',
    'parametersJsonSchema': {
      'type': 'object',
      'properties': {
        'ad': {'type': 'string', 'description': '$findTool’un verdiği ad'},
        'argumanlar': {
          'type': 'string',
          'description': 'JSON nesnesi, ör. {"ifade": "2024/512"}',
        },
      },
      'required': ['ad'],
    },
  };

  static const _ask = {
    'name': askText,
    'description':
        'Özetlenmiş bir araç sonucunun ASLINA soru sorar (tarih, tutar, '
        'ifade, gerekçe…): cevap asıldan, ilgili cümleler aynen alıntılanarak '
        'gelir. Özette olmayan bir ayrıntıyı ASLA tahmin etme, bunu çağır.',
    'parametersJsonSchema': {
      'type': 'object',
      'properties': {
        'metin_id': {'type': 'string'},
        'soru': {'type': 'string'},
      },
      'required': ['metin_id', 'soru'],
    },
  };

  static const _brain = {
    'name': brainTool,
    'description':
        'Ağır işler için avukatın yapay zekâ programına (Claude Code, Codex, '
        'Antigravity ya da API) sorar: dilekçe ya da belge taslağı, birçok '
        'evrakı okuyup değerlendirme, uzun hukuki inceleme. Kısa sorular için '
        'önce araçları kullan; bu birkaç dakika sürebilir.',
    'parametersJsonSchema': {
      'type': 'object',
      'properties': {
        'soru': {
          'type': 'string',
          'description': 'Avukatın isteği, gerekli bütün ayrıntıyla.',
        },
      },
      'required': ['soru'],
    },
  };

  @override
  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> args, {
    String question = '',
  }) async {
    switch (name) {
      case findTool:
        return found('${args['ihtiyac'] ?? ''}', await _tools());
      case runTool:
        return _runFound(args, question);
      case askText:
        return _askKept(args);
      case brainTool:
        final answer = await brain('${args['soru'] ?? ''}');
        return _shorten('Yapay zekâ programının cevabı', answer, question);
    }
    final all = await _tools();
    if (!all.containsKey(name)) {
      return {'hata': 'böyle bir araç yok; önce $findTool ile ara'};
    }
    return _shorten(name, await _ready!.call(name, args), question);
  }

  static String _fold(String s) => s
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ş', 's')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .replaceAll('i̇', 'i');

  static String _cut(String s, int n) =>
      s.length > n ? '${s.substring(0, n)}…' : s;

  static Map<String, String> _parameters(Map<String, Object?> t) {
    final schema = (t['inputSchema'] as Map?) ?? const {};
    final props = ((schema['properties'] as Map?) ?? const {})
        .cast<String, Object?>();
    final needed = {
      for (final r in schema['required'] as List? ?? const []) '$r',
    };
    return {
      for (final e in props.entries)
        '${e.key}${needed.contains(e.key) ? ' (zorunlu)' : ''}':
            '${(e.value as Map?)?['type'] ?? 'string'}'
            '${(e.value as Map?)?['description'] == null ? '' : ' — ${_cut('${(e.value as Map)['description']}', 90)}'}',
    };
  }

  /// The tools that fit [need], best first: words of the need in a tool's
  /// name count three, in its description one (stems, so that Turkish
  /// endings do not matter).
  static Map<String, Object?> found(
    String need,
    Map<String, Map<String, Object?>> all,
  ) {
    const stop = {'icin', 'ile', 've', 'bir', 'bu', 'olan', 'var', 'nedir'};
    final words = _fold(need)
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length >= 3 && !stop.contains(w))
        .map((w) => w.length > 5 ? w.substring(0, 5) : w)
        .toList();
    final scored = <(Map<String, Object?>, int)>[];
    for (final t in all.values) {
      final name = _fold('${t['name']}'.replaceAll('_', ' '));
      final text = _fold('${t['description'] ?? ''}');
      var score = 0;
      for (final w in words) {
        if (name.contains(w)) score += 3;
        if (text.contains(w)) score += 1;
      }
      if (score > 0) scored.add((t, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    if (scored.isEmpty) {
      return {'sonuc': 'uygun araç bulunamadı', 'araclar': all.keys.join(', ')};
    }
    return {
      'araclar': [
        for (final (t, _) in scored.take(5))
          {
            'ad': t['name'],
            'aciklama': _cut('${t['description'] ?? ''}', 300),
            'parametreler': _parameters(t),
          },
      ],
      'not': 'Uygun olanı $runTool ile çalıştır (argumanlar JSON).',
    };
  }

  Future<Map<String, Object?>> _runFound(
    Map<String, Object?> args,
    String question,
  ) async {
    final all = await _tools();
    final name = '${args['ad'] ?? ''}'.trim();
    final t = all[name];
    if (t == null) {
      return {'hata': 'böyle bir araç yok; önce $findTool ile ara'};
    }
    final Map<String, Object?> given;
    final raw = args['argumanlar'];
    try {
      given = raw is Map
          ? raw.cast<String, Object?>()
          : raw == null || '$raw'.trim().isEmpty
          ? <String, Object?>{}
          : (jsonDecode('$raw') as Map).cast<String, Object?>();
    } catch (_) {
      return {
        'hata': 'argumanlar geçerli bir JSON nesnesi değil',
        'parametreler': _parameters(t),
      };
    }
    final schema = (t['inputSchema'] as Map?) ?? const {};
    final missing = [
      for (final r in schema['required'] as List? ?? const [])
        if ('${given['$r'] ?? ''}'.trim().isEmpty) '$r',
    ];
    if (missing.isNotEmpty) {
      return {
        'hata': 'eksik parametre: ${missing.join(', ')}',
        'parametreler': _parameters(t),
      };
    }
    _promoted
      ..remove(name)
      ..add(name);
    while (_promoted.length > _mostPromoted) {
      _promoted.remove(_promoted.first);
    }
    return _shorten(name, await _ready!.call(name, given), question);
  }

  String _keep(String title, String text) {
    final id = 'm${++_textCount}';
    _texts[id] = (title, text);
    while (_texts.length > 12) {
      _texts.remove(_texts.keys.first);
    }
    return id;
  }

  /// A long answer kept whole here and summarized for Live.
  Future<Map<String, Object?>> _shorten(
    String title,
    String text,
    String question,
  ) async {
    if (text.length <= _keptAsIs) return {'sonuc': text};
    final id = _keep(title, text);
    if (text.length <= _summaryOver) return {'sonuc': text, 'metin_id': id};
    try {
      final summary = await _flash(
        'Avukatın sorusu: "${question.isEmpty ? '(belirtilmedi)' : question}"\n'
        'Kaynak: $title\n\nÇıktı:\n$text\n\n'
        'Bu çıktıyı, avukatın sorusunu cevaplamaya yetecek şekilde Türkçe '
        'özetle: en çok 150 kelime; tarih, esas/karar no, tutar, ad ve '
        'süreleri AYNEN koru; çıktıda olmayan hiçbir bilgi ekleme; soruyla '
        'ilgisiz kısımları at. Soruyla ilgili bilgi yoksa bunu açıkça yaz.',
        600,
      );
      _summaries.add('$title [$id]: ${_cut(summary, 500)}');
      while (_summaries.length > 3) {
        _summaries.removeAt(0);
      }
      return {
        'ozet': summary,
        'metin_id': id,
        'not':
            'Bu bir ÖZET; aslı saklı. Ayrıntı için $askText (metin_id ile). '
            'Özette olmayanı tahmin etme.',
      };
    } catch (_) {
      return {
        'sonuc': '${text.substring(0, 4000)}\n…[kısaltıldı]',
        'metin_id': id,
      };
    }
  }

  Future<Map<String, Object?>> _askKept(Map<String, Object?> args) async {
    final kept = _texts['${args['metin_id'] ?? ''}'.trim()];
    if (kept == null) {
      return {'hata': 'metin bulunamadı; metin_id araç sonucunda yazar'};
    }
    try {
      return {
        'cevap': await _flash(
          'Kaynak: ${kept.$1}\n\n${kept.$2}\n\nSoru: ${args['soru'] ?? ''}\n\n'
          'Yalnız bu metne dayanarak Türkçe cevapla. İlgili cümleleri tırnak '
          'içinde AYNEN alıntıla; tarih, tutar, esas/karar no ve adları '
          'değiştirme. Metinde yoksa "metinde yok" de, tahmin etme.',
          1200,
        ),
      };
    } catch (e) {
      return {'hata': 'okunamadı: $e'};
    }
  }

  // Gemini 3.8 Flash, dollars a million tokens; twice that from 2027.
  static bool get _dearer => !DateTime.now().isBefore(DateTime(2027));
  static double get _flashIn => _dearer ? 1.50 : 0.75;
  static double get _flashOut => _dearer ? 7.50 : 3.75;

  Future<String> _flash(String prompt, int most) async {
    if (_flashOverride case final f?) return f(prompt, most);
    final key = await GroqChat.key(ApiService.gemini);
    if (key == null) throw StateError('Gemini anahtarı yok');
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/'
          '$flashModel:generateContent',
        ),
      );
      request.headers
        ..set('x-goog-api-key', key)
        ..contentType = ContentType.json;
      request.write(
        jsonEncode({
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          // A summary needs no thought; thinking is billed as output.
          'generationConfig': {
            'temperature': 0.1,
            'maxOutputTokens': most,
            'thinkingConfig': {'thinkingLevel': 'low'},
          },
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw HttpException('Gemini ${response.statusCode}');
      }
      final json = jsonDecode(body) as Map;
      final usage = json['usageMetadata'];
      if (usage is Map) {
        int n(Object? v) => (v as num?)?.toInt() ?? 0;
        final input = n(usage['promptTokenCount']);
        final output =
            n(usage['candidatesTokenCount']) + n(usage['thoughtsTokenCount']);
        _spent += (input * _flashIn + output * _flashOut) / 1e6;
        unawaited(AiUsage.add(ApiService.gemini, input: input, output: output));
      }
      final parts =
          ((((json['candidates'] as List?)?.firstOrNull as Map?)?['content']
                  as Map?)?['parts']
              as List?) ??
          const [];
      final text = parts
          .whereType<Map>()
          .where((p) => p['thought'] != true)
          .map((p) => '${p['text'] ?? ''}')
          .join()
          .trim();
      if (text.isEmpty) throw StateError('boş cevap');
      return text;
    } finally {
      client.close();
    }
  }
}

/// Only the AI program, through one tool: when Folio's own tools are not
/// to be given (tests, the trial window).
class BrainOnlyTools implements LiveToolBox {
  BrainOnlyTools(this.brain);
  final Future<String> Function(String question) brain;

  @override
  Future<List<Map<String, Object?>>> declarations() async => const [
    FolioLiveTools._brain,
  ];

  @override
  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> args, {
    String question = '',
  }) async => name == FolioLiveTools.brainTool
      ? {'sonuc': await brain('${args['soru'] ?? ''}')}
      : {'hata': 'Bu araç yok: $name'};

  @override
  String get remembered => '';

  @override
  double get spent => 0;
}

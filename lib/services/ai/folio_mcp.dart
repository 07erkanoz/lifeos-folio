import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../legal/bedesten_legislation.dart';
import '../legal/case_law.dart';
import '../legal/case_law_search.dart';
import '../legal/citation.dart';
import '../legal/decision.dart';
import '../legal/legislation.dart';
import 'ai_assistant.dart';
import 'ai_case.dart';
import 'ai_guide.dart';
import 'ai_office.dart';

/// `lifeos_folio --mcp`: Folio's own tools for the lawyer's AI program, over
/// the Model Context Protocol on standard input and output. They only read:
/// an article of a law as the official text has it, a law's table of
/// contents, Yargıtay, Danıştay, regional and Constitutional Court decisions
/// from the official banks, and a check of the citations a draft makes. The
/// program is told to cite only what these return, so an article or a
/// decision it would otherwise make up is either found or said not to be.
/// Run for a question asked of a case, it also has that case's tools
/// ([FolioCaseTools]).
class FolioMcp {
  FolioMcp({
    Legislation? legislation,
    CaseLaw? caseLaw,
    BedestenLegislation? bank,
    Future<CitationScanner> Function()? laws,
    Future<DecisionScanner> Function()? courts,
    this.caseTools,
    this.officeTools,
  }) : _legislation = legislation ?? Legislation(),
       _caseLaw = caseLaw ?? CaseLaw(),
       _bank = bank ?? BedestenLegislation(),
       _laws = laws ?? CitationScanner.load,
       _courts = courts ?? DecisionScanner.load {
    // A finding's citations are looked up as an answer's are.
    caseTools?.citations = _check;
  }

  final Legislation _legislation;
  final CaseLaw _caseLaw;
  final BedestenLegislation _bank;
  final Future<CitationScanner> Function() _laws;
  final Future<DecisionScanner> Function() _courts;

  /// The tools of the case the question is asked of; null when it is of
  /// none, or the program was not run by Folio for a question.
  final FolioCaseTools? caseTools;

  /// The tools of the lawyer's whole practice, with the case's.
  final FolioOfficeTools? officeTools;
  CitationScanner? _scanner;
  DecisionScanner? _decisions;

  /// Decisions [karar_ara] returned, by the id it gave: [karar_getir] needs
  /// their court and numbers, which the bank's page alone does not carry.
  final _hits = <String, CaseLawHit>{};

  static const protocol = '2025-06-18';

  /// A decision's text is given in parts of about this many characters.
  static const partSize = 7000;

  /// The command line flag.
  static const flag = '--mcp';

  /// The name its tools go by in the AI program: `mcp__folio__…`.
  static const name = 'folio';

  /// What the program reads before it uses the tools.
  static const instructions =
      'Folio\'nun hukuk araçları. Hukuki bir değerlendirmeye başlarken '
      'ilgili konuyu hukuk_rehber ile oku: hangi maddelerin ve sürelerin '
      'geçerli olduğu oradadır. Kanun maddesi, karar künyesi ya da karar '
      'metni yazacaksan önce bu araçlardan oku ve yalnız onların döndürdüğü '
      'metni ve "atif" alanını kullan. Araç "yok" ya da "ulasilamadi" '
      'dönerse bunu söyle; madde ya da karar uydurma, numara tahmin etme. '
      'Madde numarasından emin değilsen önce mevzuat_icindekiler, karardan '
      'emin değilsen önce karar_ara çağır. Taslak yazdıysan bitirmeden '
      'atif_dogrula ile denetle. Duruşma, süre, görev, tebligat, UYAP '
      'bildirimi ve dosya listesi gibi büronun bütünüyle ilgili sorularda '
      'ajanda, tebligatlar, uyap_bildirimleri ve dosyalar araçlarını kullan; '
      'bilgi eski görünüyorsa ya da avukat güncelini isterse önce '
      'uyap_baglantilari, sonra uyap_guncelle. Konuşma bir dosyaya bağlı '
      'değilse ve soru '
      'avukatın bir dosyasıyla ilgiliyse dosya_ara ile bul, tek dosya açıkça '
      'uyuyorsa dosya_sec ile seç, birden fazlası uyuyorsa avukata sor. '
      'Soru bir dosyaya bağlıysa dosya_bilgisi ve '
      'dosya_evraklari ile dosyayı tanı; evrakı evrak_oku ile oku, inmemiş '
      'olanı yalnız gerekiyorsa evrak_indir ile avukattan iste.';

  /// Every tool's name: the case's too, for the program to be let use them.
  static List<String> get names => [
    for (final t in [
      ...tools,
      ...FolioCaseTools.tools,
      ...FolioOfficeTools.tools,
    ])
      '${t['name']}',
    guideTool,
  ];

  /// The legal guide's tool (LegalGuide), its description made from the
  /// guide's own list of topics.
  static const guideTool = 'hukuk_rehber';

  static const _readOnly = {
    'readOnlyHint': true,
    'idempotentHint': true,
    'openWorldHint': true,
  };

  /// The tools, as `tools/list` gives them.
  static const tools = <Map<String, Object?>>[
    {
      'name': 'mevzuat_madde',
      'title': 'Kanun maddesini getir',
      'description':
          'Bir kanunun tek maddesini resmî güncel metniyle getirir (Bedesten, '
          'gerekirse mevzuat.gov.tr). Kanun numarası, kısaltması ya da adı '
          'verilebilir: "6098", "TBK", "Türk Borçlar Kanunu". Madde: "49", '
          '"68/a", "geçici 3", "ek 1". Mülga madde mulga=true ve yürürlükten '
          'kalkma notuyla döner. Bulunamazsa durum "yok" döner; metni '
          'uydurma.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'kanun': {
            'type': 'string',
            'description': 'Kanun numarası, kısaltması ya da adı',
          },
          'madde': {
            'type': 'string',
            'description': 'Madde: "49", "68/a", "geçici 3", "ek 1"',
          },
        },
        'required': ['kanun', 'madde'],
      },
      'annotations': _readOnly,
    },
    {
      'name': 'mevzuat_icindekiler',
      'title': 'Kanunun içindekileri',
      'description':
          'Bir kanunun madde numaralarını ve başlıklarını listeler. Hangi '
          'maddenin konuya ait olduğundan emin değilsen numara tahmin etmek '
          'yerine önce buna bak, sonra mevzuat_madde ile oku.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'kanun': {
            'type': 'string',
            'description': 'Kanun numarası, kısaltması ya da adı',
          },
        },
        'required': ['kanun'],
      },
      'annotations': _readOnly,
    },
    {
      'name': 'mevzuat_ara',
      'title': 'Kanun ara',
      'description':
          'Folio\'nun tanıdığı kanunları adına, kısaltmasına ya da numarasına '
          'göre arar; numara, kısaltma ve resmî adı döner. Kanunun numarasını '
          'bilmiyorsan önce bunu kullan.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'ifade': {
            'type': 'string',
            'description': 'Kanunun adından sözcükler, kısaltma ya da numara',
          },
        },
        'required': ['ifade'],
      },
      'annotations': _readOnly,
    },
    {
      'name': 'karar_ara',
      'title': 'Karar ara',
      'description':
          'Yargıtay, Danıştay, bölge adliye, kanun yararına bozma ve Anayasa '
          'Mahkemesi kararlarını resmî bankada arar. Sonuçlar künyesi '
          '("atif") ve kimliğiyle döner; metni okumak için karar_getir. '
          'Aramadan bulduğun karar künyesini yazma.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'sorgu': {
            'type': 'string',
            'description':
                'Aranacak sözcükler; tırnak içinde öbek, başına - dışarıda '
                'bırakır',
          },
          'mahkeme': {
            'type': 'string',
            'enum': [
              'yargitay',
              'danistay',
              'istinaf',
              'kyb',
              'aym_norm',
              'aym_bireysel',
            ],
            'description': 'Varsayılan yargitay',
          },
          'daire': {
            'type': 'string',
            'description': 'Dairenin tam adı, ör. "9. Hukuk Dairesi", "Hukuk Genel Kurulu"',
          },
          'tarih_bas': {
            'type': 'string',
            'description': 'YYYY-AA-GG; tarih_bit ile birlikte verilir',
          },
          'tarih_bit': {'type': 'string', 'description': 'YYYY-AA-GG'},
          'sayfa': {'type': 'integer', 'minimum': 1},
        },
        'required': ['sorgu'],
      },
      'annotations': _readOnly,
    },
    {
      'name': 'karar_getir',
      'title': 'Kararın tam metni',
      'description':
          'Bir kararın tam metnini aynen getirir: karar_ara\'nın verdiği '
          '"kimlik" ya da künye ("Yargıtay 9. HD, 2016/1531 E., 2017/3344 K."). '
          'Uzun metin parçalar halinde gelir; "parca" ile sonrakini iste. '
          'Künye bankada yoksa durum "yok" döner.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'kimlik': {'type': 'string', 'description': 'karar_ara kimliği'},
          'kunye': {'type': 'string', 'description': 'Kararın künyesi'},
          'parca': {'type': 'integer', 'minimum': 1},
        },
      },
      'annotations': _readOnly,
    },
    {
      'name': 'atif_dogrula',
      'title': 'Atıfları denetle',
      'description':
          'Bir metindeki kanun maddesi ve karar atıflarını bulur ve her birini '
          'resmî kaynakta denetler: bulundu, yok, mülga, ulaşılamadı. '
          'Dilekçe ya da görüş yazdıysan bitirmeden bununla denetle.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'metin': {'type': 'string', 'description': 'Denetlenecek metin'},
        },
        'required': ['metin'],
      },
      'annotations': _readOnly,
    },
  ];

  Future<CitationScanner> get _lawTable async => _scanner ??= await _laws();
  Future<DecisionScanner> get _courtTable async =>
      _decisions ??= await _courts();

  /// The article and decision citations in [text], as Folio reads them:
  /// what an answer rests on, shown under it.
  Future<(List<Citation>, List<DecisionCitation>)> citationsIn(
    String text,
  ) async => ((await _lawTable).scan(text), (await _courtTable).scan(text));

  /// The text of what a citation names, from the official source.
  Future<ArticleLookup> article(Citation c) => _legislation.lookup(c);
  Future<DecisionLookup> decision(DecisionCitation c) => _caseLaw.lookup(c);

  /// One JSON-RPC message; the answer, or null for a notification.
  Future<Map<String, Object?>?> handle(Map<String, Object?> message) async {
    final id = message['id'];
    final method = message['method'];
    if (id == null) return null;
    Map<String, Object?> result(Object? value) => {
      'jsonrpc': '2.0',
      'id': id,
      'result': value,
    };
    Map<String, Object?> error(int code, String text) => {
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': code, 'message': text},
    };
    switch (method) {
      case 'initialize':
        return result({
          'protocolVersion': protocol,
          'capabilities': {
            'tools': {'listChanged': false},
          },
          'serverInfo': {'name': name, 'title': 'LifeOS Folio', 'version': '1'},
          'instructions': instructions,
        });
      case 'ping':
        return result(const <String, Object?>{});
      case 'tools/list':
        return result({
          'tools': [
            ...tools,
            (await LegalGuide.load()).tool,
            if (caseTools != null) ...FolioCaseTools.tools,
            if (officeTools != null) ...FolioOfficeTools.tools,
          ],
        });
      case 'tools/call':
        final params = message['params'];
        if (params is! Map) return error(-32602, 'params yok');
        final name = '${params['name']}';
        final args = params['arguments'];
        final arguments = args is Map
            ? args.cast<String, Object?>()
            : const <String, Object?>{};
        if (name != guideTool &&
            !tools.any((t) => t['name'] == name) &&
            !(caseTools != null && FolioCaseTools.owns(name)) &&
            !(officeTools != null && FolioOfficeTools.owns(name))) {
          return error(-32602, 'Bilinmeyen araç: $name');
        }
        Map<String, Object?> answer;
        var failed = false;
        try {
          answer = await call(name, arguments);
        } catch (e) {
          failed = true;
          answer = {'durum': 'ulasilamadi', 'aciklama': '$e'};
        }
        return result({
          'content': [
            {
              'type': 'text',
              'text': const JsonEncoder.withIndent('  ').convert(answer),
            },
          ],
          'structuredContent': answer,
          'isError': failed,
        });
      default:
        return error(-32601, 'Bilinmeyen yöntem: $method');
    }
  }

  /// The tool [name] run with [args]; Folio uses it itself too, to check
  /// an answer's citations.
  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> args,
  ) async {
    String text(String key) => '${args[key] ?? ''}'.trim();
    if (caseTools case final c? when FolioCaseTools.owns(name)) {
      return c.call(name, args);
    }
    if (officeTools case final o? when FolioOfficeTools.owns(name)) {
      return o.call(name, args);
    }
    switch (name) {
      case 'mevzuat_madde':
        return _article(text('kanun'), text('madde'));
      case 'mevzuat_icindekiler':
        return _contents(text('kanun'));
      case 'mevzuat_ara':
        return _findLaw(text('ifade'));
      case 'karar_ara':
        return _search(args);
      case 'karar_getir':
        final part = args['parca'];
        return _decision(
          text('kimlik'),
          text('kunye'),
          part is num ? part.toInt() : 1,
        );
      case 'atif_dogrula':
        return _check(text('metin'));
      case guideTool:
        return (await LegalGuide.load()).read(text('konu'));
    }
    throw StateError('Bilinmeyen araç: $name');
  }

  /// The law [kanun] names: by its number, an abbreviation or its name.
  Future<Law?> _law(String kanun) async {
    final table = await _lawTable;
    final n = int.tryParse(kanun.replaceAll(RegExp(r'[^0-9]'), ''));
    if (n != null && RegExp(r'^\s*\d+').hasMatch(kanun)) {
      for (final law in table.laws) {
        if (law.number == n) return law;
      }
      return Law.numbered(n);
    }
    final key = lookupKey(kanun);
    for (final law in table.laws) {
      if (law.abbreviations.any((a) => lookupKey(a) == key) ||
          law.names.any((name) => lookupKey(name) == key)) {
        return law;
      }
    }
    // A name written in part: the one law whose name holds every word.
    final words = key.split(' ').where((w) => w.length > 2).toList();
    final matches = [
      for (final law in table.laws)
        if (words.isNotEmpty &&
            law.names.any((name) {
              final n = lookupKey(name);
              return words.every(n.contains);
            }))
          law,
    ];
    return matches.length == 1 ? matches.single : null;
  }

  /// [madde] of [law] as Folio reads a citation of it.
  Future<Citation?> _citation(Law law, String madde) async {
    final written = madde.trim();
    final table = CitationScanner([law]);
    final name = law.abbreviations.isNotEmpty
        ? law.abbreviations.first
        : law.name;
    for (final text in [
      '$name m. $written',
      '$name ${written.contains(RegExp('[a-zA-ZçğışöüÇĞİŞÖÜ]')) ? written : 'm. $written'}',
      '${law.number} sayılı Kanun\'un $written. maddesi',
    ]) {
      final found = table.scan(text);
      if (found.isNotEmpty) return found.first;
    }
    return null;
  }

  Map<String, Object?> _lawJson(Law law) => {
    'kanun_no': law.number,
    'ad': law.name,
    if (law.abbreviations.isNotEmpty) 'kisaltma': law.abbreviations,
    if (law.repealed) 'mulga': true,
  };

  Future<Map<String, Object?>> _article(String kanun, String madde) async {
    if (kanun.isEmpty || madde.isEmpty) {
      return {'durum': 'yok', 'aciklama': 'kanun ve madde gerekli'};
    }
    final law = await _law(kanun);
    if (law == null) {
      return {
        'durum': 'yok',
        'aciklama':
            '"$kanun" diye bir kanun bulunamadı. mevzuat_ara ile numarasını '
            'bul.',
      };
    }
    final citation = await _citation(law, madde);
    if (citation == null) {
      return {
        'durum': 'yok',
        'aciklama': '"$madde" bir madde numarası olarak okunamadı.',
      };
    }
    final got = await _legislation.lookup(citation);
    final article = got.article;
    if (got.outcome == ArticleOutcome.unreachable || article == null) {
      return {
        'durum': got.outcome == ArticleOutcome.absent ? 'yok' : 'ulasilamadi',
        ..._lawJson(law),
        'madde': madde,
        if (got.url.isNotEmpty) 'kaynak_adres': got.url,
        'aciklama': got.outcome == ArticleOutcome.absent
            ? 'Bu madde kanunun resmî metninde yok.'
            : 'Resmî kaynağa şu an ulaşılamadı; madde metnini yazma.',
      };
    }
    return {
      'durum': 'bulundu',
      'kimlik':
          'mevzuat:${law.number}/${citation.letter == null ? citation.article : '${citation.article}/${citation.letter}'}',
      'kanun_no': law.number,
      'resmi_ad': article.lawName,
      'madde': article.place.isEmpty ? '${article.number}' : article.place,
      'atif': article.title,
      if (article.headings.isNotEmpty) 'basliklar': article.headings,
      'metin': article.text,
      if (article.repealed) 'mulga': true,
      'mulga_notu': ?article.repealNotice,
      'kaynak': article.source.label,
      if (article.url.isNotEmpty) 'kaynak_adres': article.url,
    };
  }

  Future<Map<String, Object?>> _contents(String kanun) async {
    final law = await _law(kanun);
    if (law == null) {
      return {'durum': 'yok', 'aciklama': '"$kanun" bulunamadı.'};
    }
    final bank = await _bank.law(law.number);
    if (bank == null) {
      return {'durum': 'yok', ..._lawJson(law)};
    }
    final nodes = await _bank.tree(bank.id);
    // Many laws' articles come with no side heading of their own (the
    // Code of Obligations': "344" alone): each article is given the part
    // above it, said once where it begins, for the program to find the
    // article by its subject rather than guess its number.
    final articles = <Map<String, Object?>>[];
    String? part;
    var said = false;
    for (final n in nodes) {
      if (!n.isArticle) {
        if (n.heading.trim().isNotEmpty) {
          part = n.heading.trim();
          said = false;
        }
        continue;
      }
      articles.add({
        'madde': n.number,
        if (n.sideHeading.isNotEmpty) 'baslik': n.sideHeading,
        if (part != null && !said) 'bolum': part,
      });
      said = true;
    }
    return {
      'durum': 'bulundu',
      ..._lawJson(law),
      'resmi_ad': bank.name,
      'kaynak_adres': bank.url,
      'not':
          'Başlığı olmayan maddelerin konusu, üstlerindeki "bolum" ile '
          'başlar; konunun maddesini bulamazsan hukuk_rehber\'e bak.',
      'maddeler': articles,
    };
  }

  Future<Map<String, Object?>> _findLaw(String ifade) async {
    final table = await _lawTable;
    final key = lookupKey(ifade);
    final number = int.tryParse(ifade.trim());
    final words = key.split(' ').where((w) => w.isNotEmpty).toList();
    final found = [
      for (final law in table.laws)
        if (law.number == number ||
            law.abbreviations.any((a) => lookupKey(a) == key) ||
            (words.isNotEmpty &&
                law.names.any((n) => words.every(lookupKey(n).contains))))
          _lawJson(law),
    ];
    return {
      'durum': found.isEmpty ? 'yok' : 'bulundu',
      'kanunlar': found.take(20).toList(),
      if (found.isEmpty)
        'aciklama':
            'Folio\'nun tablosunda yok. Numarasını biliyorsan '
            'mevzuat_madde\'ye numarayla sor.',
    };
  }

  static DateTime? _day(Object? value) =>
      DateTime.tryParse('${value ?? ''}'.trim());

  Future<Map<String, Object?>> _search(Map<String, Object?> args) async {
    final kind = switch ('${args['mahkeme'] ?? 'yargitay'}') {
      'danistay' => CourtKind.danistay,
      'istinaf' => CourtKind.istinaf,
      'kyb' => CourtKind.kanunYarari,
      'aym_norm' => CourtKind.aymNorm,
      'aym_bireysel' => CourtKind.aymBireysel,
      _ => CourtKind.yargitay,
    };
    final from = _day(args['tarih_bas']);
    final to = _day(args['tarih_bit']);
    final page = args['sayfa'];
    final chamber = '${args['daire'] ?? ''}'.trim();
    final query = CaseLawQuery(
      words: '${args['sorgu'] ?? ''}',
      kinds: {kind},
      chamber: chamber.isEmpty ? null : chamber,
      // The bank leaves one end of a range alone unheeded: both or neither.
      from: from != null && to != null ? from : null,
      to: from != null && to != null ? to : null,
      page: page is num && page > 0 ? page.toInt() : 1,
    );
    final results = await _caseLaw.search(query);
    return {
      'durum': results.hits.isEmpty ? 'yok' : 'bulundu',
      'toplam': results.total,
      'sayfa': query.page,
      'sonuclar': [
        for (final hit in results.hits)
          {
            'kimlik': _keep(hit),
            'mahkeme': hit.court,
            'esas': hit.esas,
            'karar': hit.karar,
            'tarih': hit.date,
            'atif': _referenceOf(hit),
            if (hit.snippet.isNotEmpty) 'ozet_cumle': hit.snippet,
            if (hit.alike > 0) 'benzer_sayisi': hit.alike,
          },
      ],
    };
  }

  /// The hit's citation with its court named whole: the bank gives the
  /// chamber alone ("9. Hukuk Dairesi") for Yargıtay and Danıştay.
  static String _referenceOf(CaseLawHit hit) {
    if (hit.reference.isNotEmpty) return hit.reference;
    final bench = switch (hit.kind) {
      'YARGITAYKARARI' => 'Yargıtay',
      'DANISTAYKARAR' => 'Danıştay',
      _ => '',
    };
    final court = bench.isEmpty || hit.court.startsWith(bench)
        ? hit.court
        : '$bench ${hit.court}';
    return '$court E.${hit.esas} K.${hit.karar} ${hit.date}'.trim();
  }

  String _keep(CaseLawHit hit) {
    final id = 'karar:${hit.kind}:${hit.documentId}';
    _hits[id] = hit;
    return id;
  }

  Future<Map<String, Object?>> _decision(
    String kimlik,
    String kunye,
    int part,
  ) async {
    Decision? decision;
    var differs = false;
    if (kimlik.isNotEmpty) {
      final hit = _hits[kimlik];
      if (hit == null) {
        return {
          'durum': 'yok',
          'aciklama':
              'Bu kimlik bu oturumda karar_ara\'dan gelmedi; künyeyle iste.',
        };
      }
      decision = await _caseLaw.byId(hit);
      if (decision == null) {
        return {'durum': 'ulasilamadi', 'kimlik': kimlik};
      }
    } else if (kunye.isNotEmpty) {
      final cited = (await _courtTable).scan(kunye);
      if (cited.isEmpty) {
        return {
          'durum': 'yok',
          'aciklama': 'Künye okunamadı: mahkeme, esas ve karar no gerekli.',
        };
      }
      final got = await _caseLaw.lookup(cited.first);
      switch (got.outcome) {
        case LookupOutcome.found:
          decision = got.decision;
          differs = got.chamberDiffers;
        case LookupOutcome.absent:
          return {
            'durum': 'yok',
            'kunye': kunye,
            'aciklama': 'Bu künyede bir karar resmî bankalarda yok.',
          };
        case LookupOutcome.unpublished:
          return {
            'durum': 'yok',
            'kunye': kunye,
            'aciklama': 'Karar var ama yayımlanmamış; metni okunamaz.',
          };
        case LookupOutcome.unreachable:
          return {'durum': 'ulasilamadi', 'kunye': kunye};
      }
    } else {
      return {'durum': 'yok', 'aciklama': 'kimlik ya da kunye gerekli'};
    }
    final found = decision!;
    final text = found.text;
    final parts = (text.length / partSize).ceil().clamp(1, 1 << 20);
    final at = part.clamp(1, parts);
    final start = (at - 1) * partSize;
    return {
      'durum': 'bulundu',
      'atif': found.reference,
      'mahkeme': found.court,
      'esas': found.esas,
      'karar': found.karar,
      'tarih': found.date,
      if (differs) 'daire_farkli': true,
      'parca': at,
      'toplam_parca': parts,
      'metin': text.substring(start, (start + partSize).clamp(0, text.length)),
      'kaynak': found.source.name,
      if (found.url.isNotEmpty) 'kaynak_adres': found.url,
    };
  }

  /// The most citations checked at once: each may ask a bank.
  static const checkAtMost = 25;

  Future<Map<String, Object?>> _check(String metin) async {
    final articles = (await _lawTable).scan(metin);
    final decisions = (await _courtTable).scan(metin);
    final out = <Map<String, Object?>>[];
    for (final c in articles.take(checkAtMost)) {
      final written = metin.substring(c.start, c.start + c.length);
      try {
        final got = await _legislation.lookup(c);
        final a = got.article;
        out.add({
          'tur': 'madde',
          'yazilan': written,
          'durum': switch (got.outcome) {
            ArticleOutcome.found when a?.repealed ?? false => 'mulga',
            ArticleOutcome.found => 'bulundu',
            ArticleOutcome.absent => 'yok',
            ArticleOutcome.unreachable => 'ulasilamadi',
          },
          if (a != null) 'dogru_atif': a.title,
          'mulga_notu': ?a?.repealNotice,
        });
      } catch (_) {
        out.add({'tur': 'madde', 'yazilan': written, 'durum': 'ulasilamadi'});
      }
    }
    for (final c in decisions.take(checkAtMost)) {
      final written = metin.substring(c.start, c.start + c.length);
      try {
        final got = await _caseLaw.lookup(c);
        out.add({
          'tur': 'karar',
          'yazilan': written,
          'durum': switch (got.outcome) {
            LookupOutcome.found => 'bulundu',
            LookupOutcome.absent => 'yok',
            LookupOutcome.unpublished => 'yayimlanmamis',
            LookupOutcome.unreachable => 'ulasilamadi',
          },
          if (got.decision case final d?) 'dogru_atif': d.reference,
          if (got.chamberDiffers) 'daire_farkli': true,
        });
      } catch (_) {
        out.add({'tur': 'karar', 'yazilan': written, 'durum': 'ulasilamadi'});
      }
    }
    return {
      'atiflar': out,
      if (articles.length + decisions.length > out.length)
        'aciklama': 'İlk $checkAtMost atıf denetlendi.',
    };
  }

  /// Serves the protocol on standard input and output until input ends;
  /// one JSON message a line, as the stdio transport has it.
  static Future<int> serve() async {
    // AI turned off in Folio: no program is answered.
    if (!(await AiSettings.load()).enabled) {
      stderr.writeln('Folio’da yapay zekâ özellikleri kapalı.');
      return 1;
    }
    final server = FolioMcp(
      caseTools: FolioCaseTools.fromEnvironment(),
      officeTools: FolioOfficeTools.fromEnvironment(),
    );
    final pending = <Future<void>>[];
    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      Object? message;
      try {
        message = jsonDecode(line);
      } on FormatException {
        stdout.writeln(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': null,
            'error': {'code': -32700, 'message': 'JSON okunamadı'},
          }),
        );
        continue;
      }
      if (message is! Map) continue;
      // Answered as each is done: a slow bank does not hold a ping back.
      pending.add(
        server.handle(message.cast<String, Object?>()).then((answer) {
          if (answer != null) stdout.writeln(jsonEncode(answer));
        }),
      );
    }
    await Future.wait(pending);
    await stdout.flush();
    return 0;
  }
}

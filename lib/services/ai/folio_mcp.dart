import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../legal/bedesten_legislation.dart';
import '../legal/case_law.dart';
import '../legal/case_law_search.dart';
import '../legal/citation.dart';
import '../legal/decision.dart';
import '../legal/deadlines/deadline_service.dart';
import '../legal/deadlines/mahkeme_kategori.dart';
import '../legal/deadlines/sure_katalogu.dart';
import '../legal/doctrine.dart';
import '../legal/legislation.dart';
import '../legal/uyap_emsal.dart';
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
      'Birkaç maddeye dayanacaksan mevzuat_toplu ile tek çağrıda oku. '
      'Yönetmelik, tebliğ, tüzük, Cumhurbaşkanlığı kararnamesi ve kararı '
      'kanun değildir: mevzuat_belge_ara ile bul, mevzuat_belge_getir ile '
      'oku. Parasal sınır, harç, tarife, oran gibi her yıl değişen değerleri '
      'kanun metninden ya da ezberden verme; güncel tebliğden oku. Sürenin '
      'son gününü kendin hesaplama: dayandığı maddeyi okuduktan sonra '
      'sure_hesapla ile Folio\'nun süre motoruna hesaplat. Doktrine '
      'ancak mevzuat ve içtihat yetmezse ya da avukat isterse bak '
      '(doktrin_ara, doktrin_getir); dayandığın yazarı okuyup künyesiyle an. '
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
      'name': 'mevzuat_toplu',
      'title': 'Birden çok maddeyi getir',
      'description':
          'Birden çok kanun maddesini tek çağrıda, mevzuat_madde ile aynı '
          'resmî kaynaktan getirir (en çok 10). Aynı soruda birkaç maddeye '
          'dayanacaksan tek tek çağırmak yerine bunu kullan.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'maddeler': {
            'type': 'array',
            'maxItems': 10,
            'items': {
              'type': 'object',
              'properties': {
                'kanun': {'type': 'string'},
                'madde': {'type': 'string'},
              },
              'required': ['kanun', 'madde'],
            },
          },
        },
        'required': ['maddeler'],
      },
      'annotations': _readOnly,
    },
    {
      'name': 'mevzuat_belge_ara',
      'title': 'Yönetmelik, tebliğ, kararname ara',
      'description':
          'Kanun dışındaki mevzuatı arar: yönetmelik, tebliğ, tüzük, KHK, '
          'Cumhurbaşkanlığı kararnamesi, yönetmeliği, kararı ve genelgesi, '
          'mülga mevzuat (Bedesten). Parasal sınır, tarife, oran ve ücret gibi '
          'her yıl değişen değerler kanunda değil tebliğde ya da tarifede '
          'yayımlanır; kanun metnindeki rakam eskidir. Belgenin adını '
          'biliyorsan basliktaAra=true ile ada göre ara; numarası biliniyorsa '
          '"no" ver (metin araması numarayı kaçırır). Sorguyu Türkçe '
          'harflerle yaz. Arama yalnız belgenin ana metnini tarar, ayrı '
          'dosyadaki ekleri taramaz. Sonuç en yeniden eskiye gelir; dayanmadan '
          'önce mevzuat_belge_getir ile oku.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'sorgu': {'type': 'string', 'description': 'Aranacak sözcükler'},
          'basliktaAra': {
            'type': 'boolean',
            'description': 'true: yalnız belge adında ara',
          },
          'no': {'type': 'string', 'description': 'Belgenin numarası'},
          'tur': {
            'type': 'string',
            'description':
                'Bilmiyorsan boş bırak. Türler: KANUN, KHK, TUZUK, '
                'YONETMELIK, KKY (kurum yönetmeliği), UY (üniversite), '
                'CB_KARARNAME, CB_YONETMELIK, CB_KARAR, CB_GENELGE, '
                'TEBLIGLER, MULGA',
          },
        },
      },
      'annotations': _readOnly,
    },
    {
      'name': 'mevzuat_belge_getir',
      'title': 'Yönetmelik ya da tebliği oku',
      'description':
          'mevzuat_belge_ara\'nın verdiği kimlikle belgenin tam metnini '
          'getirir; uzunsa parça parça ("parca"). Bir yönetmeliğe ya da '
          'tebliğe dayanmadan önce oku; dayandığın hükmü metinden alıntıla.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'kimlik': {
            'type': 'string',
            'description': 'mevzuat_belge_ara kimliği',
          },
          'parca': {'type': 'integer', 'minimum': 1},
        },
        'required': ['kimlik'],
      },
      'annotations': _readOnly,
    },
    {
      'name': 'sure_hesapla',
      'title': 'Sürenin son gününü hesapla',
      'description':
          'Bir sürenin son gününü Folio\'nun süre motoruyla hesaplar: '
          'adli tatil (HMK m.103-104, CMK m.331, İYUK m.61), hafta sonu, '
          'resmî ve dinî bayramlar. Süreyi ve dayandığı maddeyi sen verirsin '
          '(maddeyi önce oku); takvim hesabını kendin yapma, bunu kullan. '
          'baslangic, sürenin başladığı olayın tarihidir (tebliğ, tefhim, '
          'öğrenme); süre ertesi günden işler.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'baslangic': {'type': 'string', 'description': 'YYYY-AA-GG'},
          'miktar': {'type': 'integer', 'minimum': 1},
          'birim': {
            'type': 'string',
            'enum': ['gun', 'is_gunu', 'hafta', 'ay', 'yil'],
          },
          'yargi': {
            'type': 'string',
            'enum': ['hukuk', 'icra', 'ceza', 'idare', 'vergi'],
          },
          'madde': {
            'type': 'string',
            'description': 'Sürenin dayanağı: "İİK m.62"',
          },
          'nitelik': {
            'type': 'string',
            'enum': ['kanuni', 'hakim', 'maddi'],
            'description':
                'kanuni: kanunun usul süresi; hakim: hâkimin verdiği süre; '
                'maddi: hak düşürücü ya da zamanaşımı gibi, adli tatilden '
                'etkilenmeyen süre',
          },
          'adli_tatile_tabi': {
            'type': 'boolean',
            'description':
                'Dava ya da iş adli tatile tabi mi; bilmiyorsan verme',
          },
        },
        'required': ['baslangic', 'miktar', 'birim', 'yargi', 'madde'],
      },
      'annotations': _readOnly,
    },
    {
      'name': 'emsal_ara',
      'title': 'Bölge adliye ve ilk derece kararı ara',
      'description':
          'UYAP Emsal\'de bölge adliye mahkemesi (istinaf) ve ilk derece '
          'kararlarını arar: kelimeyle ya da esas ve karar numarasıyla '
          '("2024/1642"). Sonuçta dairesi, künyesi ve kesinleşip '
          'kesinleşmediği gelir. Yargıtay ve Danıştay kararları burada '
          'yoktur, onlar için karar_ara.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'sorgu': {'type': 'string'},
          'esas': {'type': 'string', 'description': 'YYYY/NNNN'},
          'karar': {'type': 'string', 'description': 'YYYY/NNNN'},
          'sayfa': {'type': 'integer', 'minimum': 1},
        },
      },
      'annotations': _readOnly,
    },
    {
      'name': 'emsal_getir',
      'title': 'UYAP Emsal kararını oku',
      'description':
          'emsal_ara\'nın verdiği kimlikle kararın tam metnini parça parça '
          'getirir; sonucu ve oy durumu "sonuc" alanındadır.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'kimlik': {'type': 'string'},
          'parca': {'type': 'integer', 'minimum': 1},
        },
        'required': ['kimlik'],
      },
      'annotations': _readOnly,
    },
    {
      'name': 'kunye_dogrula',
      'title': 'Künyeyi iki kaynakta doğrula',
      'description':
          'Bir kararın esas ve karar numarasını iki resmî kaynakta birden '
          'arar: Bedesten (Yargıtay, Danıştay, bölge adliye) ve UYAP Emsal '
          '(bölge adliye ve ilk derece). Bulunan her kaydın dairesini, '
          'tarihini ve yazdığın daireyle uyup uymadığını söyler. Bir künyeye '
          'dayanmadan önce ya da avukat "bu karar gerçek mi" dediğinde kullan. '
          'İki kaynakta da bulunmaması kararın olmadığını kanıtlamaz; açık '
          'kaynakta doğrulanamadığını söyle.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'esas': {'type': 'string', 'description': 'YYYY/NNNN'},
          'karar': {'type': 'string', 'description': 'YYYY/NNNN'},
          'daire': {
            'type': 'string',
            'description': 'Yazılan mahkeme ve daire, varsa',
          },
        },
        'required': ['esas', 'karar'],
      },
      'annotations': _readOnly,
    },
    {
      'name': 'doktrin_ara',
      'title': 'Doktrin ara',
      'description':
          'Hukuk alanındaki akademik yayınları (makale, inceleme) TR Dizin\'de '
          'arar: başlık, yazar, dergi, yıl, özet. Doktrin ikna edicidir, '
          'bağlayıcı değildir; yalnız mevzuat ve içtihat yetmediğinde ya da '
          'avukat görüş istediğinde ara. en_yeni=true en yeniden sıralar.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'sorgu': {'type': 'string'},
          'adet': {'type': 'integer', 'minimum': 1, 'maximum': 12},
          'en_yeni': {'type': 'boolean'},
        },
        'required': ['sorgu'],
      },
      'annotations': _readOnly,
    },
    {
      'name': 'doktrin_getir',
      'title': 'Doktrini oku',
      'description':
          'doktrin_ara\'nın verdiği kimlikle yayının künyesini ve dergi PDF '
          'verdiyse tam metnini parça parça getirir. Bir yazara dayanacaksan '
          'önce oku; yazar, yıl, dergi, cilt, sayı ve sayfayla an. Metni '
          'okunamadıysa yalnız özete dayan ve bunu söyle.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'kimlik': {'type': 'string'},
          'parca': {'type': 'integer', 'minimum': 1},
        },
        'required': ['kimlik'],
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
          'resmî kaynakta denetler: bulundu, yok, mülga, ulaşılamadı; '
          'künyesinde mahkeme yazılmamış karar mahkeme_belirsiz döner. '
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
        final said = const JsonEncoder.withIndent('  ').convert(answer);
        return result({
          'content': [
            {'type': 'text', 'text': said},
          ],
          // Not twice for a long answer: a program counts both against the
          // most it hands its model.
          if (said.length < 20000) 'structuredContent': answer,
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
      case 'mevzuat_toplu':
        return _articles(args['maddeler']);
      case 'mevzuat_belge_ara':
        return _findDocuments(args);
      case 'mevzuat_belge_getir':
        final part = args['parca'];
        return _document(text('kimlik'), part is num ? part.toInt() : 1);
      case 'sure_hesapla':
        return deadline(args);
      case 'emsal_ara':
        final page = args['sayfa'];
        if (text('sorgu').isEmpty &&
            (UyapEmsal.numbers(text('esas')) == null ||
                UyapEmsal.numbers(text('karar')) == null)) {
          return {
            'durum': 'yok',
            'aciklama': 'sorgu ya da esas ve karar (YYYY/NNNN) gerekli.',
          };
        }
        final got = await _emsal.search(
          words: text('sorgu'),
          esas: text('esas'),
          karar: text('karar'),
          page: page is num ? page.toInt() : 1,
        );
        for (final r in got.rows) {
          _emsalNames['${r['kimlik']}'] = r;
        }
        return {
          'durum': got.rows.isEmpty ? 'yok' : 'bulundu',
          'toplam': got.total,
          'sonuclar': got.rows,
        };
      case 'emsal_getir':
        final part = args['parca'];
        return _emsalDecision(text('kimlik'), part is num ? part.toInt() : 1);
      case 'kunye_dogrula':
        return _verify(text('esas'), text('karar'), text('daire'));
      case 'doktrin_ara':
        final count = args['adet'];
        return _doctrine.search(
          text('sorgu'),
          count: count is num ? count.toInt() : 8,
          newest: args['en_yeni'] == true,
        );
      case 'doktrin_getir':
        final part = args['parca'];
        return _doctrine.read(
          text('kimlik'),
          part: part is num ? part.toInt() : 1,
        );
      case guideTool:
        return (await LegalGuide.load()).read(
          text('konu'),
          parts: text('bolum'),
        );
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

  /// Up to ten articles, each as mevzuat_madde gives it.
  Future<Map<String, Object?>> _articles(Object? asked) async {
    if (asked is! List || asked.isEmpty) {
      return {'durum': 'yok', 'aciklama': 'maddeler listesi gerekli'};
    }
    final out = <Map<String, Object?>>[];
    for (final one in asked.take(10)) {
      // "TBK m.344" as well as {kanun, madde}.
      if (one is String) {
        final m = RegExp(r'^(.+?)\s+m(?:adde)?\.?\s*(.+)$')
            .firstMatch(one.trim());
        out.add(
          m == null
              ? {'durum': 'yok', 'aciklama': '"$one" okunamadı'}
              : await _article(m[1]!.trim(), m[2]!.trim()),
        );
      } else if (one is Map) {
        out.add(
          await _article(
            '${one['kanun'] ?? ''}'.trim(),
            '${one['madde'] ?? ''}'.trim(),
          ),
        );
      }
    }
    return {
      'maddeler': out,
      if (asked.length > 10) 'aciklama': 'İlk 10 madde getirildi.',
    };
  }

  /// Documents other than laws, as the bank finds them.
  Future<Map<String, Object?>> _findDocuments(Map<String, Object?> args) async {
    final query = '${args['sorgu'] ?? ''}'.trim();
    final number = '${args['no'] ?? ''}'.trim();
    if (query.isEmpty && number.isEmpty) {
      return {'durum': 'yok', 'aciklama': 'sorgu ya da no gerekli'};
    }
    final kind = '${args['tur'] ?? ''}'.trim().toUpperCase();
    final found = await _bank.documents(
      query: query,
      kind: kind.isEmpty ? null : kind,
      inTitle: args['basliktaAra'] == true,
      number: number,
    );
    if (found.isEmpty) {
      return {
        'durum': 'yok',
        'aciklama':
            'Eşleşen belge bulunamadı. basliktaAra\'yı değiştir, türü boş '
            'bırak ya da Türkçe harflerle yeniden ara. Bulunamaması belgenin '
            'olmadığını göstermez.',
      };
    }
    for (final d in found) {
      _documentNames[d.id] = d.name;
    }
    return {
      'durum': 'bulundu',
      'belgeler': [
        for (final d in found)
          {
            'kimlik': 'mevzuat-belge:${d.id}',
            'ad': d.name,
            'tur': BedestenLegislation.documentKinds[d.kind] ?? d.kind,
            if (d.number.isNotEmpty) 'no': d.number,
            if (d.gazette.isNotEmpty) 'resmi_gazete': d.gazette,
          },
      ],
      'not':
          'Sonuçlar en yeniden eskiye. Dayanmadan önce mevzuat_belge_getir ile '
          'oku. Arama ayrı dosyadaki ekleri taramaz.',
    };
  }

  /// A document's text, in parts of [partSize] characters.
  Future<Map<String, Object?>> _document(String id, int part) async {
    final bare = id.replaceFirst('mevzuat-belge:', '').trim();
    if (bare.isEmpty || !RegExp(r'^[\w.-]+$').hasMatch(bare)) {
      return {'durum': 'yok', 'aciklama': 'mevzuat_belge_ara kimliği gerekli'};
    }
    final got = await (_documents[bare] ??= _bank.document(bare));
    if (got.text.isEmpty) {
      _documents.remove(bare);
      return {'durum': 'yok', 'aciklama': 'Bu belgenin metni alınamadı.'};
    }
    final parts = (got.text.length / partSize).ceil();
    final at = part.clamp(1, parts);
    return {
      'durum': 'bulundu',
      'ad': got.name.isNotEmpty ? got.name : _documentNames[bare] ?? '',
      'tur': BedestenLegislation.documentKinds[got.kind] ?? got.kind,
      'parca': at,
      'toplam_parca': parts,
      'metin': got.text.substring(
        (at - 1) * partSize,
        (at * partSize).clamp(0, got.text.length),
      ),
      if (at < parts)
        'not':
            'Devamı için parca=${at + 1}. Dayandığın hüküm başka parçada olabilir.',
      'kaynak': 'UYAP/Bedesten · resmî metin',
    };
  }

  /// The names the search gave, by the bank's id: the document's own page
  /// does not carry it.
  final _documentNames = <String, String>{};

  final _emsal = UyapEmsal();
  final _emsalNames = <String, Map<String, Object?>>{};
  final _emsalTexts = <String, String>{};

  Future<Map<String, Object?>> _emsalDecision(String id, int part) async {
    final key = id.startsWith('emsal:') ? id : 'emsal:$id';
    final text = _emsalTexts[key] ??= await _emsal.text(key);
    if (text.isEmpty) {
      _emsalTexts.remove(key);
      return {'durum': 'yok', 'aciklama': 'Bu kararın metni alınamadı.'};
    }
    final parts = (text.length / partSize).ceil();
    final at = part.clamp(1, parts);
    return {
      'durum': 'bulundu',
      ...?_emsalNames[key],
      'sonuc': outcomeOf(text),
      'parca': at,
      'toplam_parca': parts,
      'metin': text.substring(
        (at - 1) * partSize,
        (at * partSize).clamp(0, text.length),
      ),
      'kaynak': 'UYAP Emsal',
    };
  }

  /// A decision's numbers asked of both banks: what each holds under them,
  /// and whether the court written is one of those.
  Future<Map<String, Object?>> _verify(
    String esas,
    String karar,
    String written,
  ) async {
    final e = UyapEmsal.numbers(esas), k = UyapEmsal.numbers(karar);
    if (e == null || k == null) {
      return {
        'durum': 'kunye_bozuk',
        'aciklama': 'esas ve karar YYYY/NNNN biçiminde olmalı ("2024/1642").',
      };
    }
    final found = <Map<String, Object?>>[];
    final unreached = <String>[];
    try {
      final got = await _emsal.search(esas: esas, karar: karar);
      for (final r in got.rows) {
        if (UyapEmsal.numbers('${r['esas']}') == e &&
            UyapEmsal.numbers('${r['karar']}') == k) {
          found.add({...r, 'kaynak': 'UYAP Emsal'});
        }
      }
    } catch (_) {
      unreached.add('UYAP Emsal');
    }
    try {
      for (final kind in const [
        CourtKind.yargitay,
        CourtKind.danistay,
        CourtKind.istinaf,
      ]) {
        final got = await _caseLaw.search(
          CaseLawQuery(
            kinds: {kind},
            esasYear: e.$1,
            esasNumber: e.$2,
            kararYear: k.$1,
            kararNumber: k.$2,
          ),
        );
        for (final hit in got.hits) {
          if (UyapEmsal.numbers(hit.esas) == e &&
              UyapEmsal.numbers(hit.karar) == k) {
            found.add({
              'kimlik': _keep(hit),
              'mahkeme': _referenceOf(hit)
                  .split(RegExp(r',| E\.| \d{4}/'))
                  .first
                  .trim(),
              'esas': hit.esas,
              'karar': hit.karar,
              'tarih': hit.date,
              'kaynak': 'Bedesten',
            });
          }
        }
      }
    } catch (_) {
      unreached.add('Bedesten');
    }
    bool matches(Map r) => courtMatches(written, '${r['mahkeme']}');

    return {
      'durum': found.isNotEmpty
          ? 'bulundu'
          : unreached.length == 2
          ? 'ulasilamadi'
          : 'bulunamadi',
      'kunye': 'E.$esas K.$karar',
      'kayitlar': [
        for (final r in found)
          {...r, if (written.isNotEmpty) 'daire_uyuyor': matches(r)},
      ],
      if (unreached.isNotEmpty) 'ulasilamayan': unreached,
      'aciklama': found.isNotEmpty
          ? (written.isNotEmpty && !found.any(matches)
                ? 'Bu numaralarla kayıt var ama yazılan daireyle uyuşmuyor; '
                      'doğru daireyi yaz.'
                : 'Künye resmî kaynakta bulundu.')
          : unreached.isNotEmpty
          ? '${unreached.join(' ve ')} yanıt vermedi; doğrulama tam yapılamadı. '
                'Bu, kararın olmadığı anlamına gelmez.'
          : 'İki kaynakta da bu numaralarla kayıt yok. Bu yokluk kanıtı '
                'değildir: açık yayın her kararı taşımaz; "açık kaynakta '
                'doğrulanamadı" de.',
    };
  }

  /// Whether the court [written] ("Yargıtay 3. HD", "İstanbul BAM 54. HD")
  /// is [court] as the bank names it: its kind of chamber and its number
  /// the same.
  static bool courtMatches(String written, String court) {
    String norm(String v) {
      var t = ' ${v.toLowerCase().replaceAll('i̇', 'i')} '.replaceAll(
        RegExp(r'[.,]'),
        ' ',
      );
      for (final (a, b) in const [
        ('hgk', 'hukuk genel kurulu'),
        ('cgk', 'ceza genel kurulu'),
        ('hd', 'hukuk daire'),
        ('cd', 'ceza daire'),
        ('bam', 'bölge adliye mahkemesi'),
        ('bim', 'bölge idare mahkemesi'),
        ('iddk', 'idari dava daireleri kurulu'),
        ('vddk', 'vergi dava daireleri kurulu'),
        ('d', 'daire'),
        ('dairesi', 'daire'),
      ]) {
        t = t.replaceAll(' $a ', ' $b ');
      }
      return t.replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    final w = norm(written), c = norm(court);
    if (w.isEmpty) return false;
    final number = RegExp(r'(?:^| )(\d{1,3})(?= |$)');
    if (number.firstMatch(w)?[1] != number.firstMatch(c)?[1]) return false;
    for (final kind in const [
      'hukuk',
      'ceza',
      'genel kurul',
      'idari',
      'vergi',
      'bölge',
    ]) {
      if (w.contains(kind) && !c.contains(kind)) return false;
    }
    for (final top in const ['yargıtay', 'danıştay']) {
      if (w.contains(top) && !c.contains(top)) return false;
    }
    return true;
  }

  final _doctrine = Doctrine(
    pdfText: (path) => AiAssistant.documentText(path, ocr: false),
  );

  /// Documents read in this session, by the bank's id.
  final _documents =
      <String, Future<({String name, String kind, String text})>>{};

  /// A time's last day, by Folio's own engine: the time and its article
  /// given by the program, the calendar reckoned here.
  static Map<String, Object?> deadline(
    Map<String, Object?> args, {
    DateTime? now,
  }) {
    final start = DateTime.tryParse('${args['baslangic'] ?? ''}'.trim());
    final amount = args['miktar'] is num
        ? (args['miktar'] as num).toInt()
        : int.tryParse('${args['miktar'] ?? ''}');
    final unit = switch ('${args['birim'] ?? ''}') {
      'gun' => SureBirimi.gun,
      'is_gunu' => SureBirimi.isGunu,
      'hafta' => SureBirimi.hafta,
      'ay' => SureBirimi.ay,
      'yil' => SureBirimi.yil,
      _ => null,
    };
    final court = switch ('${args['yargi'] ?? ''}') {
      'hukuk' => MahkemeKategorisi.hukuk,
      'icra' => MahkemeKategorisi.icra,
      'ceza' => MahkemeKategorisi.ceza,
      'idare' => MahkemeKategorisi.idare,
      'vergi' => MahkemeKategorisi.vergi,
      _ => null,
    };
    final article = '${args['madde'] ?? ''}'.trim();
    if (start == null ||
        amount == null ||
        amount < 1 ||
        unit == null ||
        court == null ||
        article.isEmpty) {
      return {
        'durum': 'yok',
        'aciklama':
            'baslangic (YYYY-AA-GG), miktar, birim, yargi ve madde gerekli.',
      };
    }
    final kind = switch ('${args['nitelik'] ?? 'kanuni'}') {
      'hakim' => SureNiteligi.hakim,
      'maddi' => SureNiteligi.maddi,
      _ => SureNiteligi.kanuni,
    };
    final recess = args['adli_tatile_tabi'];
    final got = DeadlineService.computeFromOzelSure(
      baslangic: start,
      sure: YasalSure(
        ad: article,
        miktar: amount,
        birim: unit,
        kanunMaddesi: article,
        nitelik: kind,
      ),
      kategori: court,
      now: now,
      adliTatileTabi: recess is bool ? recess : null,
    );
    final item = got.items.firstOrNull;
    if (item == null) {
      return {'durum': 'yok', 'aciklama': 'Süre hesaplanamadı.'};
    }
    String day(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return {
      'durum': 'hesaplandi',
      'sure': '${item.sureMetni} (${item.kanun})',
      'baslangic': day(item.baslangicTarihi),
      'son_gun': day(item.etkiliSonGun),
      if (item.uzadi) 'takvimdeki_son_gun': day(item.hamSonGun),
      'kalan_gun': item.kalanGun,
      if (item.dayanakNotlari.isNotEmpty) 'notlar': item.dayanakNotlari,
      if (item.tatilBelirsiz)
        'uyari':
            'Son gün adli tatile denk geliyor; işin adli tatile tabi olup '
            'olmadığı bilinmediği için uzayıp uzamadığı kesin değil.',
      'guven': item.guven.name,
      'not':
          'Son günü Folio hesapladı; süreyi ve başlangıcını sen verdin. '
          'Avukata sürenin dayanağını ve başlangıç olayını da söyle.',
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
      // How it ended, on every part: measured, a program that read only the
      // first of three parts wrote "oybirliği" for a decision by majority.
      'sonuc': outcomeOf(text),
      'parca': at,
      'toplam_parca': parts,
      if (parts > 1)
        'not':
            'Kararın sonucu ve oy durumu "sonuc" alanında. Gerekçeye '
            'dayanacaksan ilgili parçayı oku; okumadığın kısım için '
            'tahminde bulunma.',
      'metin': text.substring(start, (start + partSize).clamp(0, text.length)),
      'kaynak': found.source.name,
      if (found.url.isNotEmpty) 'kaynak_adres': found.url,
    };
  }

  /// How a decision ended, from its own text: whether it was given
  /// unanimously or by majority, whether a dissent is printed, and the
  /// sentence it was given in ("… oy çokluğuyla kesin olarak karar
  /// verildi.").
  static Map<String, Object?> outcomeOf(String text) {
    final tail = text.length > 8000 ? text.substring(text.length - 8000) : text;
    final majority = RegExp(r'[Oo][Yy]\s*([çc]oklu[ğg]u|ÇOKLU[ĞG]U)');
    final unanimous = RegExp(r'[Oo][Yy]\s*([bB]irli[ğg]i|BİRLİ[ĞG]İ)');
    // Written out: Dart's case folding does not know "Ş" and "I".
    final dissent = RegExp(
      r'KARŞI\s*OY|[Kk]arşı\s*[Oo]y|MUHALEFET\s*ŞERH|[Mm]uhalefet\s*şerh',
    ).hasMatch(tail);
    // The sentences that give it; the one that says how wins, the last of
    // them (a dissent printed after it says neither).
    final given = [
      for (final m in RegExp(
        r'[^.]{0,500}(karar\s+veril(di|miştir)|hükmolundu)[^.]*\.',
        caseSensitive: false,
      ).allMatches(tail))
        m[0]!.replaceAll(RegExp(r'\s+'), ' ').trim(),
    ];
    String? vote;
    String sentence = given.isEmpty ? '' : given.last;
    for (final g in given.reversed) {
      if (majority.hasMatch(g)) {
        vote = 'oy çokluğu';
      } else if (unanimous.hasMatch(g)) {
        vote = 'oybirliği';
      }
      if (vote != null) {
        sentence = g;
        break;
      }
    }
    return {
      'oy': vote ?? 'metinde yazmıyor',
      'karsi_oy': dissent,
      if (sentence.isNotEmpty) 'hukum_cumlesi': sentence,
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
      // Numbers with no court beside them: not a court no bank publishes,
      // only one not named. "Yargıtay HGK, … onadı (E.2017/2348 K.2019/82)".
      if (c.court == null) {
        out.add({
          'tur': 'karar',
          'yazilan': written,
          'durum': 'mahkeme_belirsiz',
          'aciklama':
              'Künyenin yanında mahkeme yazılmadığı için denetlenemedi; '
              'mahkemeyi ve daireyi numarayla birlikte yaz.',
        });
        continue;
      }
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
          // Which court Folio took the numbers to be of: the nearest one
          // named, which may be a court the case went to, not the one that
          // decided it ("davayı asliye ticarete gönderen … (E.…)").
          if (got.outcome == LookupOutcome.unpublished)
            'mahkeme': c.courtWritten,
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

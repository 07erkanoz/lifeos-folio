import 'dart:convert';

import 'package:path/path.dart' as p;

import '../ai/ai_case.dart';
import '../ai/ai_draft.dart';
import '../ai/ai_groq.dart';
import '../ai/ai_refresh.dart';
import '../ai/ai_tools_apart.dart';
import '../portal/portal_database.dart';
import '../uyap/uyap_case_store.dart';
import 'general_tools.dart';

/// Folio Ajan's tools in a spoken conversation: Folio's own (the case's,
/// the office's, and those of the programs on this computer: the clients,
/// the cash, the e-notices, adding to the agenda and notes), what they ask
/// of UYAP done here ([AiSessionServer]), and a petition put in the case's
/// "Dilekçelerim" as a UDF, and what is not Folio ([AjanGeneralTools]:
/// the rates, the weather, the news, music). A voice that could only read was of little use
/// to the lawyer (22 Kasım 2026).
class AjanToolHost implements FolioToolHost {
  AjanToolHost(
    this.session, {
    UyapCaseStore? store,
    AjanGeneralTools? general,
    FolioToolHost? folio,
  }) : _store = store ?? UyapCaseStore.instance,
       _general = general ?? AjanGeneralTools(),
       _server = AiSessionServer(session, store: store),
       _folio = folio ?? FolioToolsHere(session, external: true) {
    _server.start();
  }

  /// Folio's tools in an isolate of their own ([FolioToolsApart]): run
  /// here they held the window for up to seconds and stopped Folio Ajan's
  /// animation (22 Kasım 2026).
  static Future<AjanToolHost> open() async {
    final session = await AiCaseSession.open(null);
    return AjanToolHost(
      session,
      folio: await FolioToolsApart.start(session, external: true),
    );
  }

  final AiCaseSession session;
  final UyapCaseStore _store;
  final AiSessionServer _server;
  final FolioToolHost _folio;
  final AjanGeneralTools _general;

  static const petitionTool = 'dilekce_kaydet';

  static const _petition = <String, Object?>{
    'name': petitionTool,
    'title': 'Dilekçeyi dosyaya kaydet',
    'description':
        'Yazdığın dilekçeyi ya da belgeyi UDF olarak seçili dosyanın '
        '(dosya_sec) klasörüne kaydeder; Folio\'da dosyanın detayındaki '
        'Dilekçelerim bölümünde görünür, avukat UDF düzenleyicide açıp '
        'düzeltir. Dosya seçilmemişse Folio\'nun "Yapay zekâ" klasörüne '
        'gider. Metni avukatın söylediklerine ve dosyanın bilgisine dayanarak '
        'tam yaz: mahkeme başlığı, taraflar, konu, açıklamalar, hukuki '
        'sebepler, deliller, sonuç ve istem; bilmediğin bilgiyi uydurma, '
        '[…] diye boş bırak. Yalnız avukat istediyse ve kaydetmeyi '
        'onayladıysa kullan.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'baslik': {
          'type': 'string',
          'description': 'Dosya adı olur, ör. "Cevap dilekçesi"',
        },
        'metin': {
          'type': 'string',
          'description':
              'Dilekçenin tam metni; her satır bir paragraf, boş satır '
              'aralık, # ile başlayan satır kalın başlık',
        },
      },
      'required': ['baslik', 'metin'],
    },
    'annotations': {
      'readOnlyHint': false,
      'destructiveHint': false,
      'idempotentHint': false,
      'openWorldHint': false,
    },
  };

  @override
  Future<List<Map<String, Object?>>> tools() async => [
    ...await _folio.tools(),
    _petition,
    ...AjanGeneralTools.declarations,
  ];

  @override
  Future<String> call(String name, Map<String, Object?> args) async {
    if (AjanGeneralTools.names.contains(name)) {
      return jsonEncode(await _general.call(name, args));
    }
    if (name != petitionTool) return _folio.call(name, args);
    return jsonEncode(
      await savePetition(
        '${args['baslik'] ?? ''}'.trim(),
        '${args['metin'] ?? ''}'.trim(),
      ),
    );
  }

  /// [text] as a UDF in the chosen case's folder.
  Future<Map<String, Object?>> savePetition(String title, String text) async {
    if (text.isEmpty) return {'durum': 'yok', 'aciklama': 'Metin boş.'};
    final record = await _server.record();
    final path = await writeAiDraft(
      _store,
      record,
      title.isEmpty ? 'Dilekçe' : title,
      text,
    );
    PortalDatabase.changed?.call();
    return {
      'durum': 'kaydedildi',
      'ad': p.basename(path),
      if (record != null) 'dosya': '${record.court} ${record.number}',
      'aciklama': record != null
          ? 'Dosyanın Dilekçelerim bölümüne UDF olarak eklendi.'
          : 'Dosya seçili değildi; Folio\'nun "Yapay zekâ" klasörüne '
                'kaydedildi.',
    };
  }

  @override
  Future<void> close() async {
    _server.stop();
    await _folio.close();
  }
}

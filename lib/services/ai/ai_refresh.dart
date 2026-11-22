import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../portal/portal_database.dart';
import '../portal/portal_sync.dart';
import '../uets/uets_api.dart';
import '../uyap/uyap_mobile_api.dart';
import '../uyap/uyap_web_service.dart';
import '../uyap/uyap_case_panel_controller.dart';
import '../uyap/uyap_case_store.dart';
import 'ai_case.dart';

/// The running Folio doing what the AI program asked of UYAP and UETS
/// (FolioOfficeTools' uyap_guncelle and uyap_baglantilari): through the
/// same sync the lawyer's own buttons use, one after another. The same
/// thing asked again within [again] is not asked of UYAP twice.
abstract final class AiRefresh {
  static const again = Duration(minutes: 5);

  static final _done = <String, DateTime>{};

  /// What [scope] (and [key] for one case) came to, as the tool says it.
  /// Asks the lawyer to connect where [UyapNeed] says, the PIN of the
  /// e-signature card on Folio Ajan's screen or the connection dialog
  /// elsewhere; true once connected. Set by the window: a program that
  /// needed UYAP or UETS only said it was not connected (22 Kasım 2026).
  static Future<bool> Function(UyapNeed need, String why)? askConnect;
  static DateTime? _declined;
  static Future<bool>? _asking;

  /// [askConnect], once at a time, and not again for two minutes after
  /// the lawyer closed it.
  static Future<bool> connect(UyapNeed need, String why) async {
    final ask = askConnect;
    if (ask == null) return false;
    final declined = _declined;
    if (declined != null &&
        DateTime.now().difference(declined) < const Duration(minutes: 2)) {
      return false;
    }
    final ok = await (_asking ??= ask(
      need,
      why,
    ).whenComplete(() => _asking = null));
    if (!ok) _declined = DateTime.now();
    return ok;
  }

  static Future<Map<String, Object?>> run(String scope, String key) async {
    var web = UyapWebService.instance.connected;
    var mobile = UyapMobileApi.instance.connected;
    var uets = UetsApi.instance.connected;
    if (scope == 'baglantilar') {
      return {
        'durum': 'bulundu',
        'uyap_web': web,
        'uyap_mobil': mobile,
        'uets': uets,
        'not':
            'UYAP Web dosyaların tamamını, icra hesabını, dosya borcunu, '
            'tahsilatı, Yargıtay ve savcılık dosyalarını verir; UYAP Mobil '
            'dosya listesini, evrakı ve duruşmaları. İkisi bağlıysa Folio '
            'ikisini birlikte kullanır.',
      };
    }
    final sync = PortalSync.started;
    if (sync == null) {
      return {'durum': 'yapilamadi', 'aciklama': 'Folio henüz hazır değil.'};
    }
    var needs = scope == 'tebligatlar' ? uets : web || mobile;
    if (!needs &&
        await connect(
          scope == 'tebligatlar' ? UyapNeed.uets : UyapNeed.web,
          scope == 'tebligatlar'
              ? 'Tebligatlara bakmak için UETS’e e-imzanızla bağlanın.'
              : 'Bilgiyi UYAP’tan güncellemek için Avukat Portalı’na '
                    'e-imzanızla bağlanın.',
        )) {
      web = UyapWebService.instance.connected;
      mobile = UyapMobileApi.instance.connected;
      uets = UetsApi.instance.connected;
      needs = scope == 'tebligatlar' ? uets : web || mobile;
    }
    if (!needs) {
      return {
        'durum': 'bagli_degil',
        'aciklama': scope == 'tebligatlar'
            ? 'Folio UETS\'e bağlı değil; avukat bağlanınca güncellenir.'
            : 'Folio UYAP\'a bağlı değil; avukat UYAP Web ya da UYAP '
                  'Mobil\'e bağlanınca güncellenir.',
      };
    }
    final id = '$scope|$key';
    final last = _done[id];
    if (last != null && DateTime.now().difference(last) < again) {
      return {
        'durum': 'guncel',
        'aciklama':
            'Az önce güncellendi (${last.toIso8601String().substring(11, 16)}); '
            'Folio\'daki bilgi günceldir.',
      };
    }
    try {
      String? problem;
      switch (scope) {
        case 'durusmalar':
          await sync.refreshHearings();
        case 'tebligatlar':
          await sync.syncUets();
        case 'bildirimler':
          await sync.syncNotices(force: true);
        case 'portfoy':
          await sync.syncPortfolio();
        case 'dosya':
          problem = await sync.syncCase(key);
        default:
          return {'durum': 'yok', 'aciklama': 'Bilinmeyen kapsam.'};
      }
      if (problem != null) {
        return {'durum': 'yapilamadi', 'aciklama': problem};
      }
      _done[id] = DateTime.now();
      return {
        'durum': 'guncellendi',
        'kanal': [if (web) 'UYAP Web', if (mobile) 'UYAP Mobil'].join(', '),
        'aciklama': 'Güncellendi; bilgiyi araçlarla yeniden oku.',
      };
    } catch (e) {
      return {'durum': 'yapilamadi', 'aciklama': '$e'};
    }
  }

  /// What the program asked of [session], done one by one; [told] hears
  /// each as it starts, for the lawyer to see.
  static Future<void> serve(
    AiCaseSession session, {
    void Function(String said)? told,
  }) async {
    for (final r in await session.refreshes()) {
      told?.call(_said(r.scope));
      await session.answerRefresh(r.id, await run(r.scope, r.key));
    }
  }

  /// The documents the program asked for in [session], downloaded from
  /// UYAP one after another while Folio is connected: [told] hears each
  /// (its title, and then what came of it).
  static Future<void> serveDownloads(
    AiCaseSession session, {
    void Function(String id, String title, String? outcome)? told,
  }) async {
    for (final r in await session.pending()) {
      if (!session.handled.add(r.id)) continue;
      final record = session.record;
      final title =
          [
            for (final d
                in record?.documents ?? const <UyapCaseDocument>[]) ...[
              d,
              ...d.attachments,
            ],
          ].where((d) => d.key == r.key).firstOrNull?.title ??
          'Evrak';
      told?.call(r.id, title, null);
      final String state, note;
      if (record == null) {
        (state, note) = ('yapilamadi', 'Konuşma bir dosyaya bağlı değil.');
      } else {
        (state, note) = await _download(record, r.key);
      }
      await session.answer(r, state, note);
      told?.call(r.id, title, switch (state) {
        'indirildi' => 'İndirildi',
        'uyap_bagli_degil' => 'UYAP’a bağlı değil; indirilemedi',
        _ => 'İndirilemedi',
      });
    }
  }

  /// The case a download was last for, kept a while: a new panel for
  /// every document found the case in UYAP and fetched its whole list
  /// again before each one, and three documents took minutes
  /// (22 Kasım 2026).
  static UyapCasePanelController? _panel;
  static String? _panelFor;
  static Timer? _panelEnds;

  static UyapCasePanelController _panelOf(UyapCaseRecord record) {
    _panelEnds?.cancel();
    _panelEnds = Timer(const Duration(minutes: 10), () {
      _panel?.dispose();
      _panel = null;
      _panelFor = null;
    });
    if (_panel case final panel? when _panelFor == record.key) return panel;
    _panel?.dispose();
    _panelFor = record.key;
    return _panel = UyapCasePanelController(store: UyapCaseStore.instance);
  }

  static Future<(String, String)> _download(
    UyapCaseRecord record,
    String key,
  ) async {
    final store = UyapCaseStore.instance;
    try {
      // Already here: read, not asked of UYAP again.
      if (await store.load(record.court, record.number) case final now?
          when store.fileOf(now, key) != null) {
        return ('indirildi', 'Zaten inmiş; evrak_oku ile oku.');
      }
      final fresh = _panelFor != record.key;
      final panel = _panelOf(record);
      if (!panel.connected &&
          !await connect(
            UyapNeed.web,
            'Evrakı UYAP’tan indirmek için Avukat Portalı’na e-imzanızla '
            'bağlanın.',
          )) {
        return (
          'uyap_bagli_degil',
          'Folio UYAP\'a bağlı değil; avukat bağlanınca indirilebilir.',
        );
      }
      // Shown once: showing again forgets the list UYAP gave.
      if (fresh || panel.record == null) await panel.show(record);
      await panel.download([key]);
      final now = await store.load(record.court, record.number);
      if (now != null && store.fileOf(now, key) != null) {
        return ('indirildi', 'İndirildi; evrak_oku ile oku.');
      }
      final why = panel.error;
      // A panel that went wrong is not kept for the next one.
      _panel?.dispose();
      _panel = null;
      _panelFor = null;
      return ('indirilemedi', why ?? 'UYAP evrakı vermedi.');
    } catch (e) {
      _panel?.dispose();
      _panel = null;
      _panelFor = null;
      return ('indirilemedi', '$e');
    }
  }

  static String _said(String scope) => switch (scope) {
    'durusmalar' => 'UYAP’tan duruşmalar güncelleniyor',
    'tebligatlar' => 'UETS’ten tebligatlar güncelleniyor',
    'bildirimler' => 'UYAP bildirimleri güncelleniyor',
    'portfoy' => 'UYAP’tan dosya listesi güncelleniyor',
    'dosya' => 'Dosya UYAP’tan güncelleniyor',
    _ => 'UYAP bağlantıları okunuyor',
  };
}

/// A conversation with no panel of its own (Folio Ajan's voice) served:
/// what its program asks of UYAP (uyap_guncelle) and the documents it asks
/// for (evrak_indir) are done while it runs. Without it the voice saw only
/// what had come down already, and could not refresh (22 Kasım 2026).
class AiSessionServer {
  AiSessionServer(this.session, {UyapCaseStore? store})
    : _store = store ?? UyapCaseStore.instance;

  final AiCaseSession session;
  final UyapCaseStore _store;
  Timer? _timer;
  bool _busy = false;

  void start() => _timer ??= Timer.periodic(
    const Duration(seconds: 1),
    (_) => unawaited(tick()),
  );

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// The case the program chose (dosya_sec), as it is now.
  Future<UyapCaseRecord?> record() async {
    final bound = await session.bound();
    final record = session.record;
    if (bound == null) {
      session.record = null;
    } else if (record == null ||
        record.court != bound.court ||
        record.number != bound.number) {
      session.record = await _store.load(bound.court, bound.number);
    }
    return session.record;
  }

  /// One look: the case the program chose, then its asks.
  Future<void> tick() async {
    if (_busy) return;
    _busy = true;
    try {
      await record();
      await AiRefresh.serve(session);
      await AiRefresh.serveDownloads(session);
      // An agenda entry or a note added: Folio's screens read again.
      var added = false;
      await for (final entry in session.folder.list()) {
        if (entry is File && p.basename(entry.path).startsWith('degisti-')) {
          added = true;
          try {
            await entry.delete();
          } catch (_) {}
        }
      }
      if (added) PortalDatabase.changed?.call();
    } catch (_) {
      // Looked at again in a second.
    } finally {
      _busy = false;
    }
  }
}

/// Where a program's request needs a session: the UYAP lawyer portal or
/// UETS, each with the e-signature card.
enum UyapNeed { web, uets }

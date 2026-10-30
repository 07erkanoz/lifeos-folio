import 'dart:async';

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
  static Future<Map<String, Object?>> run(String scope, String key) async {
    final web = UyapWebService.instance.connected;
    final mobile = UyapMobileApi.instance.connected;
    final uets = UetsApi.instance.connected;
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
    final needs = scope == 'tebligatlar' ? uets : web || mobile;
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

  /// The most documents downloaded for one question.
  static const downloadsPerQuestion = 10;

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
      } else if (session.handled.length > downloadsPerQuestion) {
        (state, note) = (
          'sinir',
          'Bir soruda en çok $downloadsPerQuestion evrak indirilir; elindekiyle '
              'sürdür.',
        );
      } else {
        (state, note) = await _download(record, r.key);
      }
      await session.answer(r, state, note);
      told?.call(r.id, title, switch (state) {
        'indirildi' => 'İndirildi',
        'uyap_bagli_degil' => 'UYAP’a bağlı değil; indirilemedi',
        'sinir' => 'Sınır doldu; indirilmedi',
        _ => 'İndirilemedi',
      });
    }
  }

  static Future<(String, String)> _download(
    UyapCaseRecord record,
    String key,
  ) async {
    final store = UyapCaseStore.instance;
    final panel = UyapCasePanelController(store: store);
    try {
      if (!panel.connected) {
        return (
          'uyap_bagli_degil',
          'Folio UYAP\'a bağlı değil; avukat bağlanınca indirilebilir.',
        );
      }
      await panel.show(record);
      await panel.download([key]);
      final now = await store.load(record.court, record.number);
      return now != null && store.fileOf(now, key) != null
          ? ('indirildi', 'İndirildi; evrak_oku ile oku.')
          : ('indirilemedi', 'UYAP evrakı vermedi.');
    } catch (e) {
      return ('indirilemedi', '$e');
    } finally {
      panel.dispose();
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

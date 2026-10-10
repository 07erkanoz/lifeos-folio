import '../uyap/uyap_case_links.dart';
import '../uyap/uyap_case_panel_controller.dart';
import '../uyap/uyap_case_store.dart';
import '../uyap/uyap_web_service.dart';
import 'portal_case.dart';
import 'portal_sync.dart';

/// Brings a case of the portfolio (the agenda's, UETS's) into UYAP
/// Dosyalarım: its place in UYAP, then its particulars, parties and
/// documents from whichever portal is connected, the web first.
class PortalCaseImport {
  PortalCaseImport({this._sync, this._store});

  final PortalSync? _sync;
  final UyapCaseStore? _store;
  PortalSync get sync => _sync ?? PortalSync.instance;
  UyapCaseStore get store => _store ?? UyapCaseStore.instance;

  /// Hukuk 1, Ceza 0, İcra 2, İdari 6, read from the court's name when the
  /// mobile API did not say.
  static String guessJurisdiction(String court) => court.contains('Ceza')
      ? '0'
      : court.contains('İcra')
      ? '2'
      : court.contains('İdare') || court.contains('Vergi')
      ? '6'
      : '1';

  /// Where [kase] is in UYAP. What the mobile API gave (yargı türü and
  /// birimi) and the web's unit id are used; with the web connected, what
  /// is missing is looked up among its courts by the court's name.
  Future<UyapCaseLink> linkFor(PortalCase kase) async {
    final kept = (await store.load(kase.court, kase.number))?.link;
    if (kept != null && kept.courtType.isNotEmpty && kept.courtId.isNotEmpty) {
      return kept;
    }
    final details = kase.details?.value ?? const <String, Object?>{};
    String text(String key) => '${details[key] ?? ''}'.trim();
    final jurisdiction = text('yargiTuru').isNotEmpty
        ? text('yargiTuru')
        : guessJurisdiction(kase.court);
    var courtType = text('yargiBirimi');
    var courtId = text('birimId');
    final web = sync.web;
    if (web.connected && (courtType.isEmpty || courtId.isEmpty)) {
      final name = UyapWebService.fold(kase.court);
      final types = courtType.isNotEmpty
          ? [courtType]
          : [for (final t in await web.courtTypes(jurisdiction)) t.id];
      search:
      for (final type in types) {
        for (final closed in [false, true]) {
          for (final c in await web.courts(
            jurisdiction,
            type,
            closed: closed,
          )) {
            if (c.id == courtId || UyapWebService.fold(c.label) == name) {
              courtType = type;
              courtId = c.id;
              break search;
            }
          }
        }
      }
    }
    return UyapCaseLink(
      jurisdiction: jurisdiction,
      courtType: courtType,
      courtId: courtId,
      court: kase.court,
      number: kase.number,
      closed: (kase.status?.value ?? '').contains('Kapal'),
    );
  }

  /// Fetches [kase] and keeps it in Dava Dosyalarım; the record kept.
  Future<UyapCaseRecord> add(PortalCase kase) async {
    if (!sync.web.connected && !sync.mobile.connected) {
      throw StateError(
        'Dosyayı eklemek için UYAP Web’e ya da UYAP Mobil’e bağlanın.',
      );
    }
    final link = await linkFor(kase);
    final controller = UyapCasePanelController(
      web: sync.web,
      mobile: sync.mobile,
      sync: sync,
      store: store,
    );
    try {
      await controller.attach(link);
      await controller.refresh();
      final record = controller.record;
      if (controller.error != null || record == null) {
        throw StateError(controller.error ?? 'Dosya UYAP’tan alınamadı.');
      }
      return record;
    } finally {
      controller.dispose();
    }
  }
}

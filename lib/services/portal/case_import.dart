import '../uyap/uyap_case_links.dart';
import '../uyap/uyap_case_panel_controller.dart';
import '../uyap/uyap_case_store.dart';
import '../uyap/uyap_web_service.dart';
import 'portal_case.dart';
import 'portal_channel.dart';
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

  /// The prosecutor's office or the high court chamber [court] names, on
  /// the web: (yargı türü, birim id); null when it names neither or is not
  /// found. A prosecutor's office is looked for among the cases [kept]
  /// first, then province by province.
  static Future<(String, String)?> ownListPlace(
    UyapWebService web,
    String court,
    Future<Iterable<PortalCase>> Function() kept,
  ) async {
    final name = UyapWebService.fold(court);
    if (name.contains('savcilig')) {
      for (final c in await kept()) {
        final id = '${c.details?.value['birimId'] ?? ''}';
        if (c.family == CaseFamily.prosecutor &&
            id.isNotEmpty &&
            UyapWebService.fold(c.court) == name) {
          return (UyapWebService.prosecution, id);
        }
      }
      for (final province in await web.provinces()) {
        for (final office in await web.prosecutorOffices(province.id)) {
          if (UyapWebService.fold(office.label) == name) {
            return (UyapWebService.prosecution, office.id);
          }
        }
      }
      return null;
    }
    for (final MapEntry(key: jurisdiction, value: label)
        in UyapWebService.highCourts.entries) {
      if (!name.contains(UyapWebService.fold(label))) continue;
      for (final chamber in await web.chambers(jurisdiction)) {
        final bare = UyapWebService.fold(
          chamber.label.replaceFirst(RegExp(r'\s*\(\d+\)\s*$'), ''),
        );
        // Whole words: "11. Hukuk Dairesi" is not "1. Hukuk Dairesi".
        if (name == bare || name.endsWith(' $bare')) {
          return (jurisdiction, chamber.id);
        }
      }
      return null;
    }
    return null;
  }

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
    final known = text('yargiTuru');
    var jurisdiction = known.isNotEmpty ? known : guessJurisdiction(kase.court);
    var courtType = text('yargiBirimi');
    var courtId = text('birimId');
    final web = sync.web;
    // A prosecutor's office and a high court are found by lists of their
    // own (findCase), not among the courts.
    var ownList =
        jurisdiction == UyapWebService.prosecution ||
        UyapWebService.isHighCourt(jurisdiction);
    // Known by name alone: a prosecutor's office or a chamber is found by
    // its own list.
    if (web.connected && known.isEmpty && courtId.isEmpty) {
      final place = await ownListPlace(web, kase.court, sync.portfolio);
      if (place != null) {
        (jurisdiction, courtId) = place;
        ownList = true;
      }
    }
    if (web.connected && !ownList && (courtType.isEmpty || courtId.isEmpty)) {
      final name = UyapWebService.fold(kase.court);
      // A guess is tried first, then the other kinds: a guess is no fact.
      final candidates = known.isNotEmpty
          ? [known]
          : {jurisdiction, ...webJurisdictions}.toList();
      var found = false;
      search:
      for (final candidate in candidates) {
        final types = courtType.isNotEmpty
            ? [courtType]
            : [for (final t in await web.courtTypes(candidate)) t.id];
        for (final type in types) {
          for (final closed in [false, true]) {
            for (final c in await web.courts(candidate, type, closed: closed)) {
              if (c.id == courtId || UyapWebService.fold(c.label) == name) {
                jurisdiction = candidate;
                courtType = type;
                courtId = c.id;
                found = true;
                break search;
              }
            }
          }
        }
      }
      // Not found: the guess is not kept as if it were known.
      if (!found && known.isEmpty) jurisdiction = '';
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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../security/secret_store.dart';
import '../uets/notice_matcher.dart';
import '../uets/uets_api.dart';
import '../uyap/mobile_case_finder.dart';
import '../uyap/uyap_case_links.dart';
import '../uyap/uyap_case_panel_controller.dart';
import '../uyap/uyap_case_store.dart';
import '../uyap/uyap_mobile_api.dart';
import '../uyap/uyap_web_service.dart';
import 'hearing_sync.dart';
import 'observed.dart';
import 'portal_case.dart';
import 'portal_channel.dart';
import 'portal_database.dart';
import 'portal_hearing.dart';

/// One channel's sync, as the screens show it.
class ChannelSync {
  final bool running;
  final DateTime? finished;

  /// What could not be fetched, or null.
  final String? problem;

  /// How far a long run has come: "Portföy 34/145".
  final String? progress;
  const ChannelSync({
    this.running = false,
    this.finished,
    this.problem,
    this.progress,
  });
}

/// Runs each connected channel's sync when it connects, whether or not the
/// agenda is open, and never one channel's for another (UYGULAMAPLANI §3,
/// §9). A channel's sync touches only its own share: the web's hearings,
/// or the mobile API's hearings and cases; the database merges them.
class PortalSync extends ChangeNotifier {
  PortalSync({
    UyapWebService? web,
    UyapMobileApi? mobile,
    UetsApi? uets,
    Future<PortalDatabase> Function()? database,
    SecretStore? secrets,
  }) : _secrets = secrets ?? SecretStore(),
       _web = web ?? UyapWebService.instance,
       _mobile = mobile ?? UyapMobileApi.instance,
       _uets = uets ?? UetsApi.instance,
       _database = database ?? PortalDatabase.shared;

  static PortalSync? _instance;
  static PortalSync get instance => _instance ??= PortalSync()..start();

  /// The one started, if Folio started it: what only looks (a list, a
  /// listener) uses this, so that a test never wakes the lawyer's sessions.
  static PortalSync? get started => _instance;

  /// Starts the one instance: the kept mobile session comes back with it.
  /// Folio's window and an editor window of its own call this at start.
  static void begin() => _instance ??= PortalSync()..start();

  final UyapWebService _web;
  final UyapMobileApi _mobile;
  final UetsApi _uets;
  final Future<PortalDatabase> Function() _database;
  final SecretStore _secrets;

  static const _mobileSecret = 'uyap-mobile';
  final _state = <PortalChannel, ChannelSync>{};
  bool _started = false;

  ChannelSync state(PortalChannel channel) =>
      _state[channel] ?? const ChannelSync();

  UyapWebService get web => _web;
  UyapMobileApi get mobile => _mobile;
  UetsApi get uets => _uets;
  SecretStore get secrets => _secrets;

  void start() {
    if (_started) return;
    _started = true;
    _web.session.addListener(_webChanged);
    _mobile.session.addListener(_mobileChanged);
    _uets.session.addListener(_uetsChanged);
    // The mobile session lasts a week: kept sealed between runs, and taken
    // up again here. The web portal's three hours are not kept.
    _mobile.onTokens = (tokens) => unawaited(
      tokens == null
          ? _secrets.remove(_mobileSecret)
          : _secrets.write(_mobileSecret, tokens.toJson()),
    );
    unawaited(_restoreMobile());
  }

  /// Takes the kept session up again. Without a network at start (a laptop
  /// waking, Wi-Fi coming late) the session is not lost: it is tried again,
  /// each wait longer, until UYAP answers yes or no.
  Future<void> _restoreMobile({int attempt = 0}) async {
    if (_mobile.connected || _disposed) return;
    final kept = MobileTokens.fromJson(await _secrets.read(_mobileSecret));
    if (kept == null) return;
    try {
      await _mobile.restore(kept);
    } on UyapMobileUnreachable {
      if (attempt >= 8 || _disposed) return;
      final wait = Duration(seconds: 15 * (1 << attempt).clamp(1, 16));
      _restoreRetry?.cancel();
      _restoreRetry = Timer(
        wait,
        () => unawaited(_restoreMobile(attempt: attempt + 1)),
      );
    }
  }

  Timer? _restoreRetry;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _restoreRetry?.cancel();
    _web.session.removeListener(_webChanged);
    _mobile.session.removeListener(_mobileChanged);
    _uets.session.removeListener(_uetsChanged);
    super.dispose();
  }

  void _webChanged() {
    notifyListeners();
    if (_web.connected) unawaited(syncWeb());
  }

  void _uetsChanged() {
    notifyListeners();
    if (_uets.connected) unawaited(syncUets());
  }

  /// The UETS inbox, from a day before the newest notice kept (or the last
  /// ninety days the first time), merged into the database; then each
  /// untied notice is matched to a case (§9.8).
  Future<void> syncUets() => _run(PortalChannel.uets, (db) async {
    if (!_uets.connected) return null;
    final kept = db.notices();
    final newest = kept.isEmpty ? null : kept.first.message.sent;
    // The first time the whole box: a notice older than ninety days may
    // still run a year's deadline. After that the last weeks again, every
    // time, for what was read or deemed read since.
    final recent = DateTime.now().subtract(const Duration(days: 45));
    final since = newest == null
        ? null
        : newest.subtract(const Duration(days: 1)).isBefore(recent)
        ? newest.subtract(const Duration(days: 1))
        : recent;
    final inbox = await _uets.listing(since: since);
    db.mergeNotices(inbox.messages);
    var whole = inbox.complete;
    // What the lawyer moved to the archive is still a notice; a box
    // without an archive folder is no failure.
    try {
      final archive = await _uets.listing(folder: uetsArchiveFolder, since: since);
      db.mergeNotices(archive.messages);
      whole = whole && archive.complete;
    } on UetsAccessDenied {
      // No archive here.
    }
    matchNotices(db);
    return whole
        ? null
        : 'UETS listesinin tamamı alınamadı; eşitlemeyi yeniden deneyin.';
  });

  void _mobileChanged() {
    notifyListeners();
    if (_mobile.connected) unawaited(syncMobile());
  }

  /// Says how far [channel]'s running sync has come.
  void _progress(PortalChannel channel, String text) {
    final now = state(channel);
    if (!now.running) return;
    _state[channel] = ChannelSync(
      running: true,
      finished: now.finished,
      progress: text,
    );
    notifyListeners();
  }

  Future<void> _run(
    PortalChannel channel,
    Future<String?> Function(PortalDatabase db) work,
  ) async {
    if (state(channel).running) return;
    _state[channel] = ChannelSync(
      running: true,
      finished: state(channel).finished,
    );
    notifyListeners();
    String? problem;
    try {
      final db = await _database();
      problem = await work(db);
      // The portfolio may have grown: untied notices are tried again (§9.8).
      if (channel != PortalChannel.uets) matchNotices(db);
    } catch (e) {
      problem = '$e';
    }
    _state[channel] = ChannelSync(finished: DateTime.now(), problem: problem);
    notifyListeners();
  }

  /// One case's details and documents, asked of the channels the table
  /// gives for them (§9.2): the web's kind of suit, status and complete
  /// document list first, else the mobile API's shorter list. What is kept
  /// of the case stays; the answer is merged in. Null when it worked, else
  /// what went wrong.
  /// Asks UYAP to excuse [hearing] with [reason], through the mobile API:
  /// the web portal has no such request. The hearing is looked up afresh in
  /// that day's list, by its mobile id or else by its case and minute, and
  /// only a single match is used, lest the request reach another case. A
  /// hearing UYAP closed to excuses is not asked for at all.
  Future<({bool ok, String message})> requestExcuse(
    PortalHearing hearing,
    String reason,
  ) async {
    final text = reason.trim();
    if (text.isEmpty) {
      return (ok: false, message: 'Mazeret gerekçesi boş olamaz.');
    }
    if (text.length > UyapMobileApi.excuseLimit) {
      return (
        ok: false,
        message:
            'Mazeret gerekçesi en fazla ${UyapMobileApi.excuseLimit} karakter '
            'olabilir (${text.length} yazdınız).',
      );
    }
    if (!_mobile.connected) {
      return (ok: false, message: 'Mazeret için UYAP Mobil’e bağlanın.');
    }
    final day = DateTime(hearing.at.year, hearing.at.month, hearing.at.day);
    final List<Map<String, Object?>> rows;
    try {
      rows = await _mobile.hearingRows(day, day);
    } catch (e) {
      return (ok: false, message: 'UYAP duruşma listesi alınamadı: $e');
    }
    final id = hearing.ids[PortalChannel.uyapMobile] ?? '';
    final now = DateTime.now();
    var fresh = [
      for (final r in rows)
        if (id.isNotEmpty && '${r['kayitId'] ?? ''}'.trim() == id) r,
    ];
    if (fresh.isEmpty) {
      fresh = [
        for (final r in rows)
          if (parseHearing(r, PortalChannel.uyapMobile, now)?.key ==
              hearing.key)
            r,
      ];
    }
    if (fresh.length != 1) {
      return (
        ok: false,
        message: fresh.isEmpty
            ? 'Duruşma UYAP’ın o günkü listesinde bulunamadı; kaldırılmış ya '
                  'da ertelenmiş olabilir.'
            : 'O gün aynı dosyada birden fazla duruşma var; yanlış duruşmaya '
                  'gitmesin diye talep gönderilmedi.',
      );
    }
    final row = fresh.single;
    if (row['mazaretButonAktifmi'] != true) {
      final why = '${row['mazaretDurumuAciklama'] ?? ''}'
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return (
        ok: false,
        message: why.isEmpty
            ? 'UYAP bu duruşmada mazeret talebine kapalı.'
            : 'UYAP bu duruşmada mazeret kabul etmiyor: $why',
      );
    }
    try {
      final answer = await _mobile.requestExcuse(row, text);
      return (
        ok: answer.ok,
        message: answer.message.isNotEmpty
            ? answer.message
            : answer.ok
            ? 'Mazeret talebi UYAP’a iletildi.'
            : 'UYAP talebi kabul etmedi.',
      );
    } catch (e) {
      // The request may have arrived and only its answer been lost: a
      // second excuse for one hearing is not to be sent blindly.
      return (
        ok: false,
        message:
            'Talep gönderilemedi ($e). Duruşmayı yenileyip talebin geçip '
            'geçmediğini denetleyin; körlemesine yeniden göndermeyin.',
      );
    }
  }

  Future<String?> syncCase(String key) async {
    final db = await _database();
    final kase = db.cases()[key];
    if (kase == null) return 'Dosya henüz kayıtlı değil.';
    final connected = {
      if (_web.connected) PortalChannel.uyapWeb,
      if (_mobile.connected) PortalChannel.uyapMobile,
    };
    final asked = DateTime.now().toUtc();
    final old = kase.details?.value ?? const <String, Object?>{};
    String? problem = 'Dosyayı güncellemek için UYAP bağlantısı gerekir.';
    for (final channel in ChannelTable.channels(
      UyapOp.details,
      connected,
      kase.family,
    )) {
      final id = kase.ids[channel];
      if (id == null || id.isEmpty) continue;
      try {
        if (channel == PortalChannel.uyapWeb) {
          final target = UyapCase(
            id,
            kase.number,
            '${old['birimId'] ?? ''}',
            kase.court,
          );
          final details = await _web.caseDetails(target);
          final documents = await _web.caseDocuments(target);
          db.mergeCases([
            PortalCase(
              key: kase.key,
              number: kase.number,
              court: kase.court,
              status: details.status.isEmpty
                  ? null
                  : Observed(details.status, channel, asked),
              details: Observed(
                {
                  ...old,
                  if (details.kind.isNotEmpty) 'davaTuru': details.kind,
                  if (details.opening.isNotEmpty) 'acilisTuru': details.opening,
                },
                channel,
                asked,
              ),
              documents: Observed(
                _newestFirst([
                  for (final d in documents.documents)
                    if (d.parentKey == null)
                      {
                        'ad': d.type.isNotEmpty ? d.type : d.description,
                        'tarih': d.approved,
                        'no': d.number,
                      },
                ]),
                channel,
                asked,
              ),
            ),
          ]);
        } else {
          final raw = await _mobile.caseDocuments(id);
          db.mergeCases([
            PortalCase(
              key: kase.key,
              number: kase.number,
              court: kase.court,
              documents: Observed(
                _newestFirst(_mobileDocuments(raw)),
                channel,
                asked,
                complete: false,
              ),
            ),
          ]);
        }
        notifyListeners();
        return null;
      } catch (e) {
        problem = '$e';
      }
    }
    return problem;
  }

  /// The web portal's hearings.
  Future<void> syncWeb() => _run(PortalChannel.uyapWeb, (db) async {
    if (!_web.connected) return null;
    final result = await syncHearings(
      PortalChannel.uyapWeb,
      db,
      _web.hearingRows,
    );
    return result.complete ? null : 'Bazı tarihler alınamadı';
  });

  /// The mobile API's hearings, then its cases. The whole portfolio is read
  /// court by court, hundreds of requests: once a day, kept across runs,
  /// or when [full] is asked (Portföyü yenile); otherwise only the
  /// hearings. After it the open cases are asked what is new in them
  /// ([refreshCases]). A second call while one runs waits for that one.
  Future<void> syncMobile({bool full = false}) =>
      _mobileSync ??= _run(PortalChannel.uyapMobile, (db) async {
        if (!_mobile.connected) return null;
        _progress(PortalChannel.uyapMobile, 'Duruşmalar');
        final hearings = await syncHearings(
          PortalChannel.uyapMobile,
          db,
          _mobile.hearingRows,
        );
        final read = DateTime.tryParse(db.meta(_portfolioKey) ?? '');
        var cases = const PortfolioResult(0, true);
        if (full ||
            read == null ||
            DateTime.now().difference(read) > portfolioInterval) {
          final session = _mobile.session.value;
          final ids = <String, String>{};
          cases = await syncMobilePortfolio(
            _mobile,
            db,
            includeClosed: db.meta(_closedKey) == '1',
            onCaseId: (key, id) => ids[key] = id,
            onProgress: (done, total) => _progress(
              PortalChannel.uyapMobile,
              total == 0 ? 'Portföy' : 'Portföy $done/$total',
            ),
          );
          _sessionIds = ids;
          _idsSession = session;
          db.setMeta(_portfolioKey, DateTime.now().toIso8601String());
          await refreshCases(db);
        }
        return hearings.complete && cases.complete
            ? null
            : 'Bazı kayıtlar alınamadı';
      }).whenComplete(() => _mobileSync = null);
  Future<void>? _mobileSync;

  /// How often the whole portfolio is read on its own.
  static const portfolioInterval = Duration(hours: 20);
  static const _portfolioKey = 'portfolio_at';
  static const _closedKey = 'portfolio_closed';
  static const _checkedKey = 'cases_checked_at';

  /// The mobile ids the last reading of the portfolio gave, valid while
  /// [_idsSession] lasts: a case then needs no search of its own.
  Map<String, String> _sessionIds = const {};
  MobileSession? _idsSession;

  /// When the whole portfolio was last read, and its open cases checked.
  Future<DateTime?> portfolioAt() async =>
      DateTime.tryParse((await _database()).meta(_portfolioKey) ?? '');
  Future<DateTime?> casesCheckedAt() async =>
      DateTime.tryParse((await _database()).meta(_checkedKey) ?? '');

  /// Whether the closed cases are read too (Kapalı dosyaları da indir).
  Future<bool> includeClosed() async =>
      (await _database()).meta(_closedKey) == '1';
  Future<void> setIncludeClosed(bool value) async {
    (await _database()).setMeta(_closedKey, value ? '1' : '0');
    notifyListeners();
  }

  /// Each open case asked once what is new in it: documents, parties,
  /// its state, its money. Kept only where something changed, and the
  /// change remembered for the portfolio's list. One case at a time, as
  /// UYAP answers a burst with errors.
  Future<void> refreshCases(PortalDatabase db) async {
    final open = [
      for (final c in db.cases().values)
        if (c.family == CaseFamily.court && !isClosedStatus(c.status?.value)) c,
    ];
    for (final (i, kase) in open.indexed) {
      if (!_mobile.connected && !_web.connected) break;
      _progress(PortalChannel.uyapMobile, 'Evraklar ${i + 1}/${open.length}');
      final panel = UyapCasePanelController(pause: Duration.zero);
      try {
        await panel.attach(linkOf(kase));
        final before = panel.record;
        await panel.refresh();
        final after = panel.record;
        if (after == null || identical(after, before)) continue;
        db.noteChange(
          kase.key,
          fresh: after.fresh.length,
          change: before == null ? null : describeChange(before, after),
        );
      } catch (_) {
        // One case that does not answer does not stop the others.
      } finally {
        panel.dispose();
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    db.setMeta(_checkedKey, DateTime.now().toIso8601String());
    notifyListeners();
  }

  late final _finder = MobileCaseFinder(_mobile);

  /// The mobile API's id of the case [number] at [court] in this session,
  /// looked up anew (§9: the id is the session's and never kept): the
  /// codes the portfolio kept for it narrow the search to a few requests.
  /// Null when the mobile API is not connected or does not list the case.
  Future<String?> mobileCaseId({
    required String court,
    required String number,
    String? jurisdiction,
    String? unitKind,
  }) async {
    final key = caseKey(number, court);
    if (identical(_mobile.session.value, _idsSession)) {
      final known = _sessionIds[key];
      if (known != null && known.isNotEmpty) return known;
    }
    final kept = (await _database()).cases()[key];
    final details = kept?.details?.value ?? const <String, Object?>{};
    String? code(Object? v) => '${v ?? ''}'.trim().isEmpty ? null : '$v';
    return _finder.find(
      court: court,
      number: number,
      jurisdiction: code(details['yargiTuru']) ?? code(jurisdiction),
      unitKind: code(details['yargiBirimi']) ?? code(unitKind),
      closedFirst: (kept?.status?.value ?? '').contains('Kapal'),
    );
  }

  /// The case kept as [key], if any.
  Future<PortalCase?> portalCase(String key) async =>
      (await _database()).cases()[key];

  /// Every case kept, from both portals.
  Future<List<PortalCase>> portfolio() async =>
      (await _database()).cases().values.toList();
}

/// The mobile API's documents of a case, from `tumEvraklar` (grouped by
/// case, or a list) or else `son20Evrak`.
List<Map<String, Object?>> _mobileDocuments(Map<String, Object?> raw) {
  Iterable<Object?> rows(Object? v) => v is List
      ? v
      : v is Map
      ? v.values.expand((g) => g is List ? g : const [])
      : const [];
  var all = rows(raw['tumEvraklar']).toList();
  if (all.isEmpty) all = rows(raw['son20Evrak']).toList();
  String text(Map row, List<String> keys) => keys
      .map((k) => '${row[k] ?? ''}'.trim())
      .firstWhere((v) => v.isNotEmpty, orElse: () => '');
  return [
    for (final row in all)
      if (row is Map)
        {
          'ad': text(row, [
            'evrakTuruAciklama',
            'dagitimPlanTuruAciklama',
            'evrakTuru',
            'aciklama',
          ]),
          'tarih': text(row, ['onayTarihi', 'onaylandigiTarih']),
          'no': text(row, ['birimEvrakNo', 'evrakId']),
        },
  ];
}

/// Documents with the latest approval first ("06.10.2026 09:20" or ISO).
List<Map<String, Object?>> _newestFirst(List<Map<String, Object?>> docs) {
  DateTime when(Map<String, Object?> d) {
    final raw = '${d['tarih'] ?? ''}';
    final tr = RegExp(r'(\d{1,2})\.(\d{1,2})\.(\d{4})').firstMatch(raw);
    if (tr != null) {
      return DateTime(
        int.parse(tr.group(3)!),
        int.parse(tr.group(2)!),
        int.parse(tr.group(1)!),
      );
    }
    return DateTime.tryParse(raw) ?? DateTime(1900);
  }

  return [...docs]..sort((a, b) => when(b).compareTo(when(a)));
}

class PortfolioResult {
  final int cases;
  final bool complete;
  const PortfolioResult(this.cases, this.complete);
}

/// The kinds of jurisdiction the mobile API lists cases for: ceza, hukuk,
/// icra and idari. The Court of Cassation's and the prosecutors' are the
/// web's alone (§9.2).
const mobileJurisdictions = [1, 0, 2, 6];

/// Every case the mobile API knows of the lawyer's, open and closed, merged
/// into [db]: the number, the court, the status and the kind, as partial
/// answers that fill what the web has not given and replace nothing it
/// has (§9.4). A court that fails makes the answer incomplete; the others
/// are still asked.
Future<PortfolioResult> syncMobilePortfolio(
  UyapMobileApi api,
  PortalDatabase db, {
  void Function(int done, int total)? onProgress,
  bool includeClosed = false,
  void Function(String key, String mobileId)? onCaseId,
}) async {
  // The first reading brings the portfolio as it is: nothing in it is news.
  final baseline = db.meta('portfolio_at') == null;
  final asked = DateTime.now().toUtc();
  const mobile = PortalChannel.uyapMobile;
  var complete = true;
  final found = <String, PortalCase>{};

  void add(
    Map<String, Object?> row,
    CaseFamily family, {
    int? jurisdiction,
    String? unit,
  }) {
    final number = '${row['dosyaNo'] ?? ''}'.trim();
    final court = '${row['birimAdi'] ?? ''}'.trim();
    if (number.isEmpty || court.isEmpty) return;
    final closed = row['dosyaKapaliMi'] == true;
    final status = '${row['dosyaDurumAciklama'] ?? ''}'.trim();
    final details = {
      if ('${row['dosyaTurAciklama'] ?? ''}'.isNotEmpty)
        'tur': row['dosyaTurAciklama'],
      if ('${row['dosyaAcilisTarihi'] ?? ''}'.isNotEmpty)
        'acilis': row['dosyaAcilisTarihi'],
      if ('${row['dosyaKapanisTarihi'] ?? ''}'.isNotEmpty)
        'kapanis': row['dosyaKapanisTarihi'],
      // The web portal's yargı türü and yargı birimi are the same codes:
      // with them the case is found on the web too.
      if (jurisdiction != null) 'yargiTuru': '$jurisdiction',
      'yargiBirimi': ?unit,
    };
    final one = PortalCase(
      key: caseKey(number, court),
      number: number,
      court: court,
      family: family,
      ids: {
        if ('${row['dosyaId'] ?? ''}'.isNotEmpty) mobile: '${row['dosyaId']}',
      },
      status: Observed(
        status.isNotEmpty ? status : (closed ? 'Kapalı' : 'Açık'),
        mobile,
        asked,
      ),
      details: details.isEmpty
          ? null
          : Observed(details, mobile, asked, complete: false),
    );
    found[one.key] = found[one.key]?.merge(one) ?? one;
    final id = one.ids[mobile];
    if (id != null) onCaseId?.call(one.key, id);
  }

  // The courts first, so that how far the reading has come can be said;
  // then each court's cases, kept as soon as they come, so that a case can
  // be added while the rest is still being read.
  final courts = <(int, String, String, bool)>[];
  onProgress?.call(0, 0);
  for (final type in mobileJurisdictions) {
    List<Map<String, Object?>> units;
    try {
      units = await api.unitTypes(type);
    } catch (_) {
      complete = false;
      continue;
    }
    for (final unit in units) {
      final kind = '${unit['tablo'] ?? ''}'.trim();
      if (kind.isEmpty) continue;
      for (final closed in [false, if (includeClosed) true]) {
        try {
          for (final court in await api.courts(type, kind, closed: closed)) {
            final id = '${court['birimId'] ?? ''}'.trim();
            if (id.isNotEmpty) courts.add((type, kind, id, closed));
          }
        } catch (_) {
          complete = false;
        }
      }
    }
  }
  for (final (i, (type, kind, id, closed)) in courts.indexed) {
    onProgress?.call(i, courts.length);
    try {
      for (final row in await api.cases(type, kind, id, closed: closed)) {
        add(row, CaseFamily.court, jurisdiction: type, unit: kind);
      }
      if (found.isNotEmpty) {
        db.mergeCases(found.values, portfolio: true, baseline: baseline);
        found.clear();
      }
    } catch (_) {
      complete = false;
    }
  }
  onProgress?.call(courts.length, courts.length);
  try {
    for (final chamber in await api.danistayChambers()) {
      final id = '${chamber['birimId'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      for (final row in await api.danistayCases(id)) {
        add(row, CaseFamily.danistay);
      }
    }
  } catch (_) {
    complete = false;
  }
  db.mergeCases(found.values, portfolio: true, baseline: baseline);
  return PortfolioResult(courts.length, complete);
}

/// "Kapalı", "Kapalı (12.03.2025)", "Arşiv": a case closed for good.
bool isClosedStatus(String? status) {
  final s = (status ?? '').trim().toLowerCase();
  return s.startsWith('kapal') ||
      s.startsWith('arşiv') ||
      s.startsWith('arsiv');
}

/// Where [kase] is in UYAP, as a document is tied to it.
UyapCaseLink linkOf(PortalCase kase) {
  final d = kase.details?.value ?? const <String, Object?>{};
  String text(String key) => '${d[key] ?? ''}'.trim();
  return UyapCaseLink(
    jurisdiction: text('yargiTuru'),
    courtType: text('yargiBirimi'),
    courtId: text('birimId'),
    court: kase.court,
    number: kase.number,
  );
}

/// What changed in a case between two fetches, said shortly: "3 yeni
/// evrak", "Taraflar değişti", "Durum: Karara çıkmış". Null for nothing.
String? describeChange(UyapCaseRecord before, UyapCaseRecord after) {
  final parts = <String>[];
  final fresh = after.fresh.difference(before.fresh).length;
  if (fresh > 0) parts.add('$fresh yeni evrak');
  Set<String> ids(UyapCaseRecord r) => {for (final t in r.parties) t.identity};
  final had = ids(before), has = ids(after);
  if (had.isNotEmpty &&
      has.isNotEmpty &&
      (had.length != has.length || !had.containsAll(has))) {
    parts.add('Taraflar değişti');
  }
  final was = before.details.state.trim();
  final now = after.details.state.trim();
  if (now.isNotEmpty && was.isNotEmpty && now != was) parts.add('Durum: $now');
  if (before.money != null &&
      after.money != null &&
      jsonEncode(before.money!.toJson()) != jsonEncode(after.money!.toJson())) {
    parts.add('Para hareketi');
  }
  return parts.isEmpty ? null : parts.join(' · ');
}

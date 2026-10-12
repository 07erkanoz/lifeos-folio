import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as kdf;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../editor/lawyer_profile.dart';
import '../editor/profile_autofill.dart';
import '../platform/app_directories.dart';
import '../legal/deadlines/aidiyet.dart';
import '../security/secret_store.dart';
import '../uets/notice_deadlines.dart';
import '../uets/notice_events.dart';
import '../uets/notice_documents.dart';
import '../uets/notice_packages.dart';
import '../uets/notice_matcher.dart';
import '../uets/uets_api.dart';
import '../uyap/mobile_case_finder.dart';
import '../uyap/uyap_case_links.dart';
import '../uyap/uyap_case_panel_controller.dart';
import '../uyap/uyap_case_store.dart';
import '../uyap/uyap_mobile_api.dart';
import '../uyap/uyap_pace.dart';
import '../uyap/uyap_web_service.dart';
import 'hearing_sync.dart';
import 'observed.dart';
import 'case_import.dart';
import 'portal_case.dart';
import 'portal_channel.dart';
import 'portal_database.dart';
import 'portal_hearing.dart';
import 'background_notices.dart';
import 'uyap_notice.dart';

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
    Future<String?> Function()? packageRoot,
    this._packageGap = const Duration(seconds: 3),
    this.quiet = false,
  }) : _packageRoot = packageRoot ?? _defaultPackageRoot,
       _secrets = secrets ?? SecretStore(),
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
  /// Folio's window and an editor window of its own call this at start;
  /// the editor's is [quiet].
  static void begin({bool quiet = false}) =>
      _instance ??= PortalSync(quiet: quiet)..start();

  /// An editor window's: it holds the sessions, to tie a petition to its
  /// case, but syncs nothing of itself and asks for no notifications.
  /// Folio's own window does that, once for the computer: UYAP is asked
  /// no more because more windows are open.
  final bool quiet;

  final UyapWebService _web;
  final UyapMobileApi _mobile;
  final UetsApi _uets;
  final Future<PortalDatabase> Function() _database;
  final SecretStore _secrets;

  /// Where the notices' packages are written: the UYAP folder's `UETS`,
  /// which the archive searches. Null writes none, as under the tests,
  /// which must not write into the lawyer's folder.
  final Future<String?> Function() _packageRoot;
  final Duration _packageGap;

  /// The UYAP folder's `UETS` when the lawyer keeps UYAP's documents
  /// there (the archive searches it); else Folio's own data folder, which
  /// nothing syncs or shares.
  static Future<String?> _defaultPackageRoot() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
    await UyapSettings.instance.load();
    if (!UyapSettings.instance.saveDocuments) {
      return p.join((await folioSupportDirectory()).path, 'uets');
    }
    return p.join(UyapSettings.instance.folder, 'UETS');
  }

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
    // up again here; the web portal's and UETS's sessions likewise, until
    // they end (see _restoreKept).
    _mobile.keptTokens = () async =>
        MobileTokens.fromJson(await _secrets.read(_mobileSecret));
    _mobile.onTokens = (tokens) {
      unawaited(
        tokens == null
            ? _secrets.remove(_mobileSecret)
            : _secrets.write(_mobileSecret, tokens.toJson()),
      );
      mobileTokensChanged?.call();
    };
    // Whether UYAP is read of itself here, before the sessions come back:
    // a session taken up again asks UYAP nothing unless it is.
    unawaited(
      _loadAuto().whenComplete(() {
        unawaited(_restoreMobile());
        unawaited(_restoreKept());
      }),
    );
    // UYAP's notifications are asked for now and then while a portal is
    // there to ask; not in tests, where nothing is.
    if (!quiet && !Platform.environment.containsKey('FLUTTER_TEST')) {
      _noticeTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        // In sight: the phone's background check leaves it to this run.
        if (!paused) unawaited(_database().then(BackgroundNotices.seen));
        if (night(DateTime.now()) || !autoFetch) return;
        unawaited(syncNotices(within: noticeEvery, auto: true));
        // The day's hearings and Monday's portfolio, when due: each asks
        // nothing until it is.
        _readDue();
      });
    }
  }

  /// The sessions one of the lawyer's own devices can take over (docs/
  /// buro.md, Senkron): UYAP Mobil, UETS and the UYAP web portal.
  static const sessionKinds = ['mobil', 'uets', 'web'];

  bool holds(String kind) => switch (kind) {
    'mobil' => _mobile.connected,
    'uets' => _uets.connected,
    'web' => _web.connected,
    _ => false,
  };

  /// The session of [kind] as it goes to another own device; null when
  /// this one has none.
  Map<String, Object?>? sessionOf(String kind) => switch (kind) {
    'mobil' => _mobile.tokens?.toJson(),
    'uets' => _uets.exportSession(),
    'web' => _web.exportSession(),
    _ => null,
  };

  /// Takes up a session another own device gave; false when the portal
  /// does not hold it.
  Future<bool> takeSession(String kind, Object? kept) async {
    if (kept is! Map) return false;
    final data = kept.cast<String, Object?>();
    switch (kind) {
      case 'mobil':
        final tokens = MobileTokens.fromJson(data);
        if (tokens == null) return false;
        // Kept first: renewed later here, it is these that renew.
        if (!await _secrets.write(_mobileSecret, tokens.toJson())) {
          return false;
        }
        try {
          if (await _quietly(() => _mobile.restore(tokens)) == null) {
            return false;
          }
        } on UyapMobileUnreachable {
          // UYAP out of reach: kept, and taken up when it answers.
          unawaited(_restoreMobile());
        }
        return true;
      case 'uets':
        if (!await _quietly(() => _uets.restoreSession(data))) return false;
        // Kept before it is said taken: the giver ends its own on that.
        final kept = _uets.exportSession();
        return kept != null && await _secrets.write(_uetsSecret, kept);
      case 'web':
        if (!await _quietly(() => _web.restoreSession(data))) return false;
        final kept = _web.exportSession();
        return kept != null && await _secrets.write(_webSecret, kept);
    }
    return false;
  }

  /// Told when UYAP Mobil's tokens change here, renewed or taken up: the
  /// person's other devices that share the session hear of it.
  static VoidCallback? mobileTokensChanged;

  /// The session's tokens, renewed when about to end, for another own
  /// device that renews through this one.
  Future<Map<String, Object?>?> freshMobile() async =>
      (await _mobile.freshTokens())?.toJson();

  /// Who renews UYAP Mobil's session for this device (see
  /// [UyapMobileApi.renewElsewhere]).
  void renewMobileThrough(Future<Map<String, Object?>?> Function()? ask) =>
      _mobile.renewElsewhere = ask == null
      ? null
      : () async => MobileTokens.fromJson(await ask());

  /// The session's tokens as another own device has them, when they are
  /// newer than these: taken up, so that both go on with the latest and
  /// neither renews with one UYAP may have made void.
  bool keepMobileAlike(Object? theirs) {
    final tokens = MobileTokens.fromJson(theirs);
    final mine = _mobile.tokens;
    if (tokens == null || mine == null || !_mobile.connected) return false;
    if (tokens.refresh == mine.refresh && tokens.access == mine.access) {
      return false;
    }
    if (!tokens.accessExpires.isAfter(mine.accessExpires)) return false;
    _mobile.adopt(tokens);
    return true;
  }

  static const _webSecret = 'uyap-web';
  static const _uetsSecret = 'uets';

  /// The web portal's and UETS's sessions, kept like the mobile one: in
  /// this computer's keystore, until they end. Taken up again here; one its
  /// portal no longer holds is dropped.
  Future<void> _restoreKept() async {
    final web = await _secrets.read(_webSecret);
    if (web != null && !_web.connected) {
      if (!await _quietly(() => _web.restoreSession(web))) {
        await _secrets.remove(_webSecret);
      }
    }
    final uets = await _secrets.read(_uetsSecret);
    if (uets != null && !_uets.connected) {
      if (!await _quietly(() => _uets.restoreSession(uets))) {
        await _secrets.remove(_uetsSecret);
      }
    }
    _restored = true;
    _keepWeb();
    _keepUets();
  }

  // Reading UYAP of itself (Ayarlar › Bağlantılar).

  /// Whether Folio reads UYAP of itself here: the notifications each hour,
  /// the hearings each day, the portfolio each week, and whatever a
  /// session taken up again would read. Off until the lawyer turns it on,
  /// having read what it means; then Folio asks UYAP only when the lawyer
  /// does something (signs in, refreshes, opens a case or a page), as a
  /// browser would.
  bool autoFetch = false;
  static const autoKey = 'uyap_auto';

  Future<void> _loadAuto() async {
    try {
      autoFetch = (await _database()).meta(autoKey) == '1';
    } catch (_) {}
  }

  Future<void> setAutoFetch(bool on) async {
    autoFetch = on;
    (await _database()).setMeta(autoKey, on ? '1' : '0');
    notifyListeners();
    uyapChanged?.call();
    if (on && !night(DateTime.now())) {
      unawaited(syncNotices(auto: true));
      _readDue();
    }
  }

  /// What is due of itself: the day's hearings, the week's portfolio;
  /// nothing is started, nor told the other devices, when nothing is.
  void _readDue() {
    if (quiet) return;
    unawaited(
      () async {
        final db = await _database();
        final now = DateTime.now();
        final read = DateTime.tryParse(db.meta(_portfolioKey) ?? '');
        final tried = DateTime.tryParse(db.meta('portfolio_try_at') ?? '');
        final portfolioDue =
            (read == null || read.isBefore(weekStart(now))) &&
            (tried == null || now.difference(tried) > const Duration(hours: 2));
        final unfilled = _unfilled(db).isNotEmpty;
        if (_mobile.connected &&
            (portfolioDue ||
                _hearingsDue(db, PortalChannel.uyapMobile) ||
                (unfilled && !_web.connected))) {
          unawaited(syncMobile());
        }
        // The web reads the portfolio alone, or beside UYAP Mobil what only
        // it has (syncWeb).
        final webPortfolioDue = _portfolioDue(
          db,
          full: false,
          key: _mobile.connected ? _webOnlyKey : _portfolioKey,
        ).$1;
        if (_web.connected &&
            (_hearingsDue(db, PortalChannel.uyapWeb) ||
                webPortfolioDue ||
                unfilled)) {
          unawaited(syncWeb());
        }
        if (_web.connected) unawaited(enrichOnWeb());
      }().catchError((Object _) {}),
    );
  }

  /// Sessions taken up again (at start, from another own device) under way:
  /// nothing is read of UYAP for them unless [autoFetch] is on.
  int _restoring = 0;
  Future<T> _quietly<T>(Future<T> Function() take) async {
    _restoring++;
    try {
      return await take();
    } finally {
      _restoring--;
    }
  }

  /// Whether a session that came now is to be read: one the lawyer opened,
  /// or any while Folio reads UYAP of itself.
  bool get _readsNow => autoFetch || _restoring == 0;

  /// Not written over before the kept ones were taken up.
  bool _restored = false;

  void _keepWeb() {
    if (!_restored) return;
    final kept = _web.exportSession();
    unawaited(
      kept == null
          ? _secrets.remove(_webSecret)
          : _secrets.write(_webSecret, kept),
    );
  }

  void _keepUets() {
    if (!_restored) return;
    final kept = _uets.exportSession();
    unawaited(
      kept == null
          ? _secrets.remove(_uetsSecret)
          : _secrets.write(_uetsSecret, kept),
    );
  }

  /// Takes the kept session up again. Without a network at start (a laptop
  /// waking, Wi-Fi coming late) the session is not lost: it is tried again,
  /// each wait longer, until UYAP answers yes or no.
  Future<void> _restoreMobile({int attempt = 0}) async {
    if (_mobile.connected || _disposed) return;
    final kept = MobileTokens.fromJson(await _secrets.read(_mobileSecret));
    if (kept == null) return;
    try {
      await _quietly(() => _mobile.restore(kept));
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

  /// A sync still running when this is let go of ends without telling.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _restoreRetry?.cancel();
    _progressTimer?.cancel();
    _noticeTimer?.cancel();
    noticesVersion.dispose();
    _web.session.removeListener(_webChanged);
    _mobile.session.removeListener(_mobileChanged);
    _uets.session.removeListener(_uetsChanged);
    super.dispose();
  }

  void _webChanged() {
    _keepWeb();
    notifyListeners();
    _rememberTc(_web.tckn);
    // The lawyer's name as the web portal gives it, where the profile has
    // none: whose clients the parties are is told by it.
    final user = _web.session.value?.user.trim() ?? '';
    if (user.isNotEmpty && !_placeholder(user)) {
      _remember(() => rememberLawyer(name: user));
    }
    if (_web.connected && !quiet && _readsNow) {
      unawaited(syncWeb());
      unawaited(syncNotices());
    } else if (_web.connected && !quiet) {
      // Taken up again with nothing read of itself: what the first
      // reading left unread is still read, once.
      unawaited(_fillOnly());
    }
  }

  /// A name a portal gives when it has none: no lawyer's.
  static bool _placeholder(String name) {
    final n = UyapWebService.fold(name);
    return n.isEmpty || n.startsWith('uyap ');
  }

  void _uetsChanged() {
    _keepUets();
    notifyListeners();
    _rememberTc(_uets.session.value?.tckn ?? '');
    if (_uets.connected && !quiet && _readsNow) unawaited(syncUets());
  }

  /// The UETS inbox, from a day before the newest notice kept (or the last
  /// ninety days the first time), merged into the database; then each
  /// untied notice is matched to a case (§9.8).
  Future<void> syncUets() => _run(PortalChannel.uets, (db) async {
    if (!_uets.connected) return null;
    final refused = await _checkUetsAccount(db);
    if (refused != null) {
      _uets.logout();
      return refused;
    }
    final kept = db.notices();
    final newest = kept.isEmpty ? null : kept.first.message.sent;
    // The whole box until one whole reading of it is done (a box kept by an
    // older Folio was read only for ninety days); after that the last
    // weeks again, every time, for what was read or deemed read since.
    final full = db.meta('uets_full_listing') != '1';
    final recent = DateTime.now().subtract(const Duration(days: 45));
    final since = full || newest == null
        ? null
        : newest.subtract(const Duration(days: 1)).isBefore(recent)
        ? newest.subtract(const Duration(days: 1))
        : recent;
    var whole = true;
    // Every folder of the box but the bin: what the lawyer moved to the
    // archive or a folder of their own is still a notice.
    final folders = await _uets.noticeFolders();
    for (var i = 0; i < folders.length; i++) {
      _progress(
        PortalChannel.uets,
        folders.length == 1
            ? 'Tebligatlar'
            : 'Tebligatlar · klasör ${i + 1}/${folders.length}',
      );
      try {
        final listing = await _uets.listing(folder: folders[i], since: since);
        db.mergeNotices(listing.messages);
        whole = whole && listing.complete;
      } on UetsAccessDenied {
        // A folder this box has not.
      }
    }
    if (full && whole) db.setMeta('uets_full_listing', '1');
    await _fetchManifests(db);
    // The deadlines from the documents' names at once; each package then
    // makes its own notice's again as it comes, not after the whole box.
    await _loadDeadlineContext();
    await matchNoticesGently(db);
    notifyListeners();
    await _fetchMissingParties(db);
    final root = await _packageRoot();
    if (root != null) {
      await fetchNoticePackages(
        _uets,
        db,
        root: root,
        gap: _packageGap,
        progress: (done, total) => _progress(
          PortalChannel.uets,
          'Tebligat paketleri ${done + (done < total ? 1 : 0)}/$total',
        ),
        onKept: (id) => refreshNoticeDeadlines(
          db,
          parties: NoticeDeadlineContext.parties,
          lawyer: NoticeDeadlineContext.lawyer,
          only: {id},
        ),
      );
      // Every package's documents read, the ones kept before too, each
      // notice's deadlines made again as its documents are read.
      await readNoticeDocuments(
        db,
        onRead: (id) {
          tieByCaseFile(db, id);
          _keepPackageParties(db, id);
          refreshNoticeDeadlines(
            db,
            parties: NoticeDeadlineContext.parties,
            lawyer: NoticeDeadlineContext.lawyer,
            only: {id},
          );
        },
      );
      // The hearings and inspections the papers set, where UYAP has none.
      refreshNoticeEvents(db);
    }
    return whole
        ? null
        : 'UETS listesinin tamamı alınamadı; eşitlemeyi yeniden deneyin.';
  });

  /// The package of notice [id], asked for by the lawyer (one older than
  /// the forty days whose packages come by themselves); its deadlines made
  /// again. Null when it came, else what went wrong.
  Future<String?> fetchPackageOf(String id) async {
    if (!_uets.connected) return 'UETS’ye bağlı değil.';
    final root = await _packageRoot();
    if (root == null) return null;
    final db = await _database();
    await _loadDeadlineContext();
    await fetchNoticePackages(
      _uets,
      db,
      root: root,
      gap: Duration.zero,
      only: {id},
      recent: null,
    );
    await readNoticeDocuments(db, only: {id});
    tieByCaseFile(db, id);
    refreshNoticeDeadlines(
      db,
      parties: NoticeDeadlineContext.parties,
      lawyer: NoticeDeadlineContext.lawyer,
      only: {id},
    );
    refreshNoticeEvents(db);
    notifyListeners();
    final e = db.envelope(id);
    return e?.state == 'hata' ? e?.error ?? 'Paket alınamadı.' : null;
  }

  /// The lists of documents of the notices that have none yet, newest
  /// first, all of them, the progress saying how far. What UETS would not
  /// give is kept as such and asked again a day later.
  Future<void> _fetchManifests(PortalDatabase db) async {
    final now = DateTime.now();
    final kept = db.manifests();
    final due = [
      for (final n in db.notices())
        if (switch (kept[n.message.id]) {
          null => true,
          (state: 'hata', fetchedAt: final at?, parts: _) =>
            now.difference(DateTime.parse(at)) > const Duration(days: 1),
          _ => false,
        })
          n.message.id,
    ];
    for (var i = 0; i < due.length; i++) {
      if (!_uets.connected) return;
      _progress(PortalChannel.uets, 'Ekler ${i + 1}/${due.length}');
      try {
        final parts = await _uets.parts(due[i]);
        db.saveManifest(due[i], [
          for (final p in parts) (id: p.id, name: p.name, mime: p.mime),
        ]);
      } catch (e) {
        db.saveManifest(due[i], null, error: '$e');
      }
    }
  }

  /// The parties of the cases Folio keeps, by case key, and the lawyer's
  /// own name as UYAP writes it (else the profile's), for the sign of
  /// whose a notice's deadline is.
  Future<void> _loadDeadlineContext() async {
    final parties = <String, List<TarafKaydi>>{};
    final fetched = <String, List<UyapParty>>{};
    try {
      for (final (record, _) in await UyapCaseStore.instance.cases()) {
        if (record.parties.isEmpty) continue;
        final key = caseKey(record.number, record.court);
        fetched[key] = record.parties;
        parties[key] = [
          for (final t in record.parties) (rol: t.role, vekil: t.lawyer),
        ];
      }
    } catch (_) {
      // No parties: every deadline's owner stays "not known".
    }
    var lawyer = _mobile.session.value?.user ?? '';
    if (_placeholder(lawyer)) lawyer = '';
    if (lawyer.isEmpty) lawyer = _web.session.value?.user ?? '';
    if (_placeholder(lawyer)) lawyer = '';
    if (lawyer.isEmpty) {
      try {
        lawyer = (await LawyerProfile.load()).lawyer?.name ?? '';
      } catch (_) {}
    }
    // Every fetched case's parties kept in the database too, for the
    // clients' accounts to come; and the parties read on their own for a
    // notice's case (see [_fetchMissingParties]), where the case itself was
    // not fetched.
    try {
      final db = await _database();
      for (final e in fetched.entries) {
        db.saveCaseParties(e.key, e.value, source: 'uyap');
      }
      for (final e in db.caseParties().entries) {
        parties.putIfAbsent(
          e.key,
          () => [for (final t in e.value) (rol: t.role, vekil: t.lawyer)],
        );
      }
    } catch (_) {}
    NoticeDeadlineContext.parties = parties;
    NoticeDeadlineContext.lawyer = lawyer.isEmpty ? null : lawyer;
  }

  /// The parties of every case a notice is tied to that Folio knows none
  /// of, read from UYAP on their own (not the whole case, nor its
  /// documents), a few seconds apart: for whose its deadlines are. A case
  /// UYAP would not tell is asked again a day later. The notices of the
  /// cases read have their deadlines made again.
  Future<void> _fetchMissingParties(PortalDatabase db) async {
    if (!_mobile.connected && !_web.connected) return;
    final known = NoticeDeadlineContext.parties.keys.toSet();
    final now = DateTime.now();
    final keys = <String>{
      for (final n in db.notices())
        if (n.caseKey case final key? when !known.contains(key))
          if (DateTime.tryParse(db.meta('taraflar_denendi:$key') ?? '')
              case final tried
              when tried == null ||
                  now.difference(tried) > const Duration(days: 1))
            key,
    };
    final read = <String>{};
    for (final key in keys.take(30)) {
      final kase = db.caseOf(key);
      if (kase == null) continue;
      db.setMeta('taraflar_denendi:$key', now.toIso8601String());
      final parties = await _partiesFromUyap(kase);
      if (parties != null && parties.isNotEmpty) {
        db.saveCaseParties(key, parties, source: 'taraflar');
        read.add(key);
      }
      if (_packageGap > Duration.zero) await Future<void>.delayed(_packageGap);
    }
    if (read.isEmpty) return;
    await _loadDeadlineContext();
    refreshNoticeDeadlines(
      db,
      parties: NoticeDeadlineContext.parties,
      lawyer: NoticeDeadlineContext.lawyer,
      only: {
        for (final n in db.notices())
          if (read.contains(n.caseKey)) n.message.id,
      },
    );
    notifyListeners();
  }

  /// The parties a notice's package lists (dosyaBilgileri), kept for its
  /// case where UYAP gave none: names and roles, without lawyers.
  void _keepPackageParties(PortalDatabase db, String id) {
    final key = db.notice(id)?.caseKey;
    if (key == null) return;
    final file = db
        .noticeDocuments(id)
        .map((d) => d.caseFile)
        .whereType<NoticeCaseFile>()
        .firstOrNull;
    if (file == null || file.parties.isEmpty) return;
    db.saveCaseParties(key, [
      for (final t in file.parties)
        UyapParty(t.name, t.role, '', t.institution ? 'Kurum' : 'Kişi'),
    ], source: 'paket');
  }

  /// A case's parties from UYAP Mobil, else from the web portal; null when
  /// neither would tell.
  /// A case's parties from UYAP: the web portal's first, which writes
  /// their names whole; UYAP Mobil's, which may shorten them, after.
  Future<List<UyapParty>?> _partiesFromUyap(PortalCase kase) async {
    final details = kase.details?.value ?? const <String, Object?>{};
    // The web's ids are its session's: found in this one by its court
    // and number, even a case known only from a hearing.
    if (_web.connected) {
      try {
        return await _web.parties(
          await _web.findCase(await PortalCaseImport(sync: this).linkFor(kase)),
        );
      } catch (_) {}
    }
    if (_mobile.connected) {
      try {
        // The mobile API's ids are its session's too.
        final mobileId = await mobileCaseId(
          court: kase.court,
          number: kase.number,
        );
        if (mobileId == null) return null;
        return [
          for (final p in await _mobile.parties(
            mobileId,
            caseType: '${details['dosyaTurKod'] ?? ''}',
          ))
            UyapParty.fromMap(p),
        ];
      } catch (_) {}
    }
    return null;
  }

  static const _uetsAccountKey = 'uets-account-key';

  /// Folio keeps one UETS box. The box a login opens is told from the one
  /// kept before by a keyed digest of its TC number (the key in this
  /// computer's keystore; where there is none, a slow salted one), never
  /// the number itself; a login to another box is refused, so that two
  /// boxes' notices and deadlines are never mixed.
  Future<String?> _checkUetsAccount(PortalDatabase db) async {
    final tckn = _uets.session.value?.tckn ?? '';
    if (tckn.isEmpty) return null;
    final (:id, :keyLost) = await _uetsAccountId(db, tckn);
    final kept = db.meta('uets_account');
    if (kept == null || kept == id) {
      if (kept == null) db.setMeta('uets_account', id);
      return null;
    }
    // Another digest with the key still here is another TC number: refused.
    // Only when the key was lost (a new keystore, a reinstall) is the
    // digest no proof, and then the box is told by its own notices: all
    // of the newest it lists that Folio kept before must be Folio's, and
    // there must be some. An office's box two lawyers share is not enough,
    // since then the key would not have been lost.
    if (keyLost) {
      final known = {for (final n in db.notices()) n.message.id};
      final page = await _uets.messages(count: 50);
      final shared = page.where((m) => known.contains(m.id)).length;
      if (shared > 0 && shared == page.length) {
        db.setMeta('uets_account', id);
        db.setMeta('uets_account_rekey', '');
        return null;
      }
    }
    return 'Bu Folio başka bir UETS hesabının tebligatlarını tutuyor. İki '
        'hesabın tebligatları ve süreleri karışmasın diye bu hesapla '
        'bağlanılmadı.';
  }

  /// The box's digest, and whether the keystore's key had to be made anew
  /// though a box was kept before with one: the old digest cannot be had.
  Future<({String id, bool keyLost})> _uetsAccountId(
    PortalDatabase db,
    String tckn,
  ) async {
    var key = (await _secrets.read(_uetsAccountKey))?['k'] as String?;
    var keyLost = false;
    if (key == null && db.meta('uets_account_salt') == null) {
      final fresh = base64Encode(
        List<int>.generate(32, (_) => Random.secure().nextInt(256)),
      );
      if (await _secrets.write(_uetsAccountKey, {'k': fresh})) {
        key = fresh;
        // Kept until the box is told again by its notices: a first login
        // with another box after the loss must not shut the right one out.
        if (db.meta('uets_account')?.startsWith('h:') ?? false) {
          db.setMeta('uets_account_rekey', '1');
        }
      }
    }
    keyLost = db.meta('uets_account_rekey') == '1';
    if (key != null) {
      return (
        id: 'h:${Hmac(sha256, base64Decode(key)).convert(utf8.encode(tckn))}',
        keyLost: keyLost,
      );
    }
    // No keystore: a salt beside the database and a slow derivation, so
    // that the eleven digits are not had back by trying them all quickly.
    var salt = db.meta('uets_account_salt');
    if (salt == null) {
      salt = base64Encode(
        List<int>.generate(16, (_) => Random.secure().nextInt(256)),
      );
      db.setMeta('uets_account_salt', salt);
    }
    final derived = await kdf.Pbkdf2(
      macAlgorithm: kdf.Hmac.sha256(),
      iterations: 200000,
      bits: 256,
    ).deriveKeyFromPassword(password: tckn, nonce: base64Decode(salt));
    return (
      id: 'p:${base64Encode(await derived.extractBytes())}',
      keyLost: false,
    );
  }

  void _mobileChanged() {
    notifyListeners();
    final s = _mobile.session.value;
    if (s != null && s.user.isNotEmpty && s.user != 'UYAP Mobil') {
      _remember(
        () => rememberLawyer(
          name: s.user,
          bar: s.bar,
          barNumber: s.barNumber,
          tbbNumber: s.tbbNumber,
          tckn: s.tckn,
          phone: s.phones.firstOrNull ?? '',
          email: s.emails.firstOrNull ?? '',
        ),
      );
    }
    if (_mobile.connected && !quiet && _readsNow) {
      unawaited(syncMobile());
      unawaited(syncNotices());
    } else if (_mobile.connected && !quiet) {
      unawaited(_fillOnly());
    }
  }

  /// The lawyer's own particulars, as a portal told them, written into the
  /// profile where it is blank: the TC number most of all, which UETS's
  /// mobile signature asks for. Never in tests, which have no lawyer.
  void _remember(Future<void> Function() write) {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    unawaited(write().catchError((Object _) {}));
  }

  void _rememberTc(String tc) {
    if (RegExp(r'^\d{11}$').hasMatch(tc.trim())) {
      _remember(() => rememberLawyer(tckn: tc));
    }
  }

  // UYAP's notifications.

  /// How often they are asked for while a portal is connected: once an
  /// hour, UYAP having said that programs asking it often tire it. The
  /// lawyer asks at once with Yenile.
  static const noticeEvery = Duration(hours: 1);

  /// Within this of the last reading, a page opened or Folio come back to
  /// sight does not ask again.
  static const noticeFresh = Duration(minutes: 30);

  /// Night, when nothing is asked of UYAP of itself: from nine in the
  /// evening to seven in the morning.
  static bool night(DateTime at) => at.hour >= 21 || at.hour < 7;

  /// Told each time the notifications kept change.
  final noticesVersion = ValueNotifier<int>(0);

  /// Told the notifications that came new and unread, each once, for the
  /// desktop's word of them; set by the window.
  void Function(List<UyapNotice> notices)? onNewNotices;

  /// What went wrong in the last reading; null when it worked.
  String? noticeProblem;
  DateTime? noticesCheckedAt;

  Timer? _noticeTimer;

  /// Whether Folio is out of sight on a phone, set by the window.
  bool paused = false;
  Future<void>? _noticeSync;
  DateTime _noticesAt = DateTime.fromMillisecondsSinceEpoch(0);
  final _emptyBodies = <String>{};

  /// UYAP Mobil's and the portal's notifications kept, each channel in
  /// its own rows. Not again within [noticeFresh] unless [force]d (the
  /// lawyer's Yenile); a second call while one runs waits for it.
  Future<void> syncNotices({
    bool force = false,
    Duration? within,
    bool auto = false,
  }) {
    if (_noticeSync != null) return _noticeSync!;
    // Of itself (the hour's, Folio back in sight): only when the lawyer
    // has Folio read UYAP of itself, not at night, and once an hour.
    if (auto) {
      if (!autoFetch || night(DateTime.now())) return Future.value();
      within ??= noticeEvery;
    }
    // A phone with Folio out of sight leaves it to the background check.
    if (paused && !force) return Future.value();
    if (!_mobile.connected && !_web.connected) return Future.value();
    if (force) {
      return _noticeSync = UyapPace.background(_syncNotices)
          .whenComplete(() => _noticeSync = null);
    }
    return _noticeSync = () async {
      // Asked lately, here or on another of the person's own devices
      // (Senkron brings the time with what it read): not again yet.
      if (await _askedLately(within ?? noticeFresh)) return;
      if (_disposed) return;
      // A phone leaves it to a computer of the person's on the network.
      if (deferToComputer?.call() ?? false) return;
      await UyapPace.background(_syncNotices);
    }().whenComplete(() => _noticeSync = null);
  }

  /// The last whole reading of the notifications, on any of the person's
  /// own devices: kept, not only in memory.
  static const noticesAtKey = 'notices_at';

  Future<bool> _askedLately(Duration within) async {
    final kept = DateTime.tryParse(
      (await _database()).meta(noticesAtKey) ?? '',
    );
    final last = kept != null && kept.isAfter(_noticesAt) ? kept : _noticesAt;
    return DateTime.now().difference(last) < within;
  }

  /// Whether this device leaves what UYAP is asked of itself to another of
  /// the person's own: a phone, while a computer of theirs that holds the
  /// session is on the network (set by Senkron). What the lawyer asks for
  /// by hand is asked here all the same.
  static bool Function()? deferToComputer;

  /// Told when a reading of UYAP or UETS here is done: Senkron gives it to
  /// the person's other devices.
  static VoidCallback? uyapChanged;

  static const _mobileNoticesKey = 'uyap_notice_mobile';
  static const _webNoticesKey = 'uyap_notice_web';
  static const _toldNoticesKey = 'uyap_notice_told';

  /// Whether a reading of them runs now.
  bool get noticesRunning => _noticeSync != null;

  Future<void> _syncNotices() async {
    _noticesAt = DateTime.now();
    await Future<void>.delayed(Duration.zero);
    // Let go of meanwhile: nothing is asked or told.
    if (_disposed) return;
    noticesVersion.value++;
    final db = await _database();
    final added = <UyapNoticeRow>[];
    final problems = <String>[];
    if (_mobile.connected) {
      // The first reading goes back further; it tells of nothing: what was
      // there before Folio looked is not news.
      final first = db.meta(_mobileNoticesKey) == null;
      try {
        final rows = <UyapNoticeRow>[];
        String? after;
        for (var page = 0; page < (first ? 10 : 2); page++) {
          final got = await _mobile.noticeRows(after: after);
          if (got.isEmpty) break;
          rows.addAll(got.map(UyapNoticeRow.fromMobile).nonNulls);
          final last = '${got.last['mesajId'] ?? ''}'.trim();
          if (last.isEmpty || last == after) break;
          after = last;
        }
        final fresh = db.saveUyapNotices(rows);
        if (!first) added.addAll(fresh);
        db.setMeta(_mobileNoticesKey, DateTime.now().toIso8601String());
        if (!_disposed) noticesVersion.value++;
        // Their bodies, which name the case: a few at a time, not to ask
        // UYAP for hundreds at once. One UYAP gave empty is not asked for
        // again while Folio runs.
        // Those UYAP gave empty set aside: the older ones are asked for.
        for (final r in db.uyapNoticesWithoutBody(skip: _emptyBodies)) {
          if (!_mobile.connected || _disposed) break;
          if (_emptyBodies.contains(r.id)) continue;
          try {
            final body = await _mobile.noticeBody(r.messageId);
            if (body.isNotEmpty) {
              db.setUyapNoticeBody(r.id, body);
            } else {
              _emptyBodies.add(r.id);
            }
          } catch (_) {
            // Asked again next time.
          }
        }
      } catch (e) {
        problems.add('UYAP Mobil: ${_said(e)}');
      }
    }
    if (_web.connected) {
      final first = db.meta(_webNoticesKey) == null;
      try {
        final now = DateTime.now();
        final got = await _web.noticeRows(
          now.subtract(const Duration(days: 30)),
          now,
        );
        final fresh = db.saveUyapNotices(
          got.map(UyapNoticeRow.fromWeb).nonNulls,
        );
        if (!first) added.addAll(fresh);
        db.setMeta(_webNoticesKey, now.toIso8601String());
      } catch (e) {
        problems.add('UYAP Web: ${_said(e)}');
      }
    }
    if (_disposed) return;
    // Made counsel in a case not yet in the portfolio: the portfolio is
    // read again and the case comes in new.
    if (added.isNotEmpty && portfolioChannel != null && !quiet) {
      final keys = db.cases().keys.toSet();
      final rows = db.uyapNoticesOf([
        for (final r in added) '${r.source.name}|${r.id}',
      ]);
      // At once, whenever the last reading was: a new case is not kept
      // waiting. A notification is new only once, so none reads twice.
      if (rows.any((r) => uyapNoticeNamesNewCase(r, keys))) {
        // One running now may not read the portfolio: this one follows it.
        // Both the readings under way are waited for: a call while one
        // runs would only be given that one.
        unawaited(
          _whenIdle().whenComplete(
            () => syncPortfolio(full: true, newCase: true),
          ),
        );
      }
    }
    noticeProblem = problems.isEmpty ? null : problems.join(' · ');
    noticesCheckedAt = DateTime.now();
    if (problems.isEmpty) {
      db.setMeta(noticesAtKey, noticesCheckedAt!.toIso8601String());
    }
    uyapChanged?.call();
    noticesVersion.value++;
    if (added.isNotEmpty) _tellNew(db, added);
  }

  static String _said(Object e) =>
      '$e'.replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');

  /// The notifications of the last day among [added], unread, each told
  /// once though both channels bring it.
  void _tellNew(PortalDatabase db, List<UyapNoticeRow> added) {
    final now = DateTime.now();
    final ids = {for (final r in added) '${r.source.name}:${r.id}'};
    final told = <String, String>{};
    try {
      final kept = jsonDecode(db.meta(_toldNoticesKey) ?? '{}');
      if (kept is Map) {
        for (final MapEntry(:key, :value) in kept.entries) {
          final at = DateTime.tryParse('$value');
          if (at != null && now.difference(at) < const Duration(days: 3)) {
            told['$key'] = '$value';
          }
        }
      }
    } catch (_) {}
    final out = <UyapNotice>[];
    for (final n in db.uyapNotices(
      since: now.subtract(const Duration(days: 1)),
    )) {
      if (n.read) continue;
      if (!n.rows.any((r) => ids.contains('${r.source.name}:${r.id}'))) {
        continue;
      }
      if (told.containsKey(n.signature)) continue;
      told[n.signature] = now.toIso8601String();
      out.add(n);
    }
    db.setMeta(_toldNoticesKey, jsonEncode(told));
    if (out.isNotEmpty) onNewNotices?.call(out);
  }

  /// [notices] read, or unread again, in Folio. Only Folio's count: UYAP
  /// is not told, a notification being no more than news of the case.
  Future<void> markNotices(
    List<UyapNotice> notices, {
    required bool read,
  }) async {
    if (notices.isEmpty) return;
    final db = await _database();
    db.setUyapNoticeRead([for (final n in notices) ...n.rows], read);
    noticesVersion.value++;
  }

  /// Says how far [channel]'s running sync has come.
  ///
  /// Told at most twice a second: a sync of five hundred cases says how far
  /// it has come five hundred times, and every page listening reads its
  /// data again each time it is told; told each time, the window froze.
  void _progress(PortalChannel channel, String text) {
    final now = state(channel);
    if (!now.running) return;
    _state[channel] = ChannelSync(
      running: true,
      finished: now.finished,
      progress: text,
    );
    final since = DateTime.now().difference(_lastProgress);
    if (since >= _progressEvery) {
      _lastProgress = DateTime.now();
      notifyListeners();
    } else {
      _progressTimer ??= Timer(_progressEvery - since, () {
        _progressTimer = null;
        _lastProgress = DateTime.now();
        notifyListeners();
      });
    }
  }

  static const _progressEvery = Duration(milliseconds: 500);
  DateTime _lastProgress = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _progressTimer;

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
      // A sync's requests keep UYAP's slow pace (UyapPace).
      problem = await UyapPace.background(() async {
        final db = await _database();
        final problem = await work(db);
        // The portfolio may have grown: untied notices are tried again
        // (§9.8).
        if (channel != PortalChannel.uets) {
          await _loadDeadlineContext();
          await matchNoticesGently(db);
        }
        return problem;
      });
    } catch (e) {
      problem = '$e';
    }
    _state[channel] = ChannelSync(finished: DateTime.now(), problem: problem);
    notifyListeners();
    uyapChanged?.call();
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
    final kase = db.caseOf(key);
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
      // The web's ids are its session's: the case is found in this one by
      // its court and number, even one known only from a hearing.
      if (channel != PortalChannel.uyapWeb && (id == null || id.isEmpty)) {
        continue;
      }
      try {
        if (channel == PortalChannel.uyapWeb) {
          final target = await _web.findCase(
            await PortalCaseImport(sync: this).linkFor(kase),
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
          final raw = await _mobile.caseDocuments(id!);
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

  /// Every open case asked again from the web portal, one after another:
  /// its particulars, documents, parties, money, and an enforcement file's
  /// account and debtors. Long (some seconds a case), so asked for by hand.
  Future<void> refreshAllOnWeb() => _run(PortalChannel.uyapWeb, (db) async {
    if (!_web.connected) return 'UYAP Web bağlı değil.';
    await refreshCases(db, channel: PortalChannel.uyapWeb);
    return null;
  });

  /// The open cases enriched from the web of themselves while [autoFetch]
  /// is on, once a day (the lawyer's choice, 11 Ekim 2026): the cases with
  /// a hearing within a month, those never fetched, and a seventh of the
  /// rest, so that each is fetched within the week. The money, the
  /// enforcement account and the debtors are the web's alone; the
  /// documents' list comes, the documents do not. Apart from [syncWeb], so
  /// that the lawyer's Senkronize et is not held while it runs; in UYAP's
  /// one queue, a lawyer opening a case going first (refreshCases), and it
  /// stops when the web goes, at night or when [autoFetch] is turned off.
  Future<void> enrichOnWeb() => _enrichment ??= () async {
    bool keepGoing() =>
        !_disposed && _web.connected && autoFetch && !night(DateTime.now());
    // Not left to a computer of the person's: it may have UYAP Mobil only,
    // and the money is the web's.
    if (!keepGoing()) return;
    final db = await _database();
    final now = DateTime.now();
    final at = DateTime.tryParse(db.meta(enrichedKey) ?? '');
    if (at != null &&
        at.year == now.year &&
        at.month == now.month &&
        at.day == now.day) {
      return;
    }
    // Tried, it is tried again in two hours, not every five minutes.
    final tried = DateTime.tryParse(db.meta('${enrichedKey}_try') ?? '');
    if (tried != null && now.difference(tried) < const Duration(hours: 2)) {
      return;
    }
    db.setMeta('${enrichedKey}_try', now.toIso8601String());
    // After the portfolio's reading and its first reading of the cases,
    // which would be asked twice otherwise.
    await _whenIdle();
    if (!keepGoing()) return;
    // Nothing to enrich yet (the first portfolio still coming): not done.
    if (db.cases().isEmpty) return;
    final done = await UyapPace.background(
      () => refreshCases(
        db,
        changed: const {},
        channel: PortalChannel.uyapWeb,
        keepGoing: keepGoing,
      ),
    );
    if (done) {
      db.setMeta(enrichedKey, DateTime.now().toIso8601String());
      uyapChanged?.call();
    }
  }().catchError((Object _) {}).whenComplete(() => _enrichment = null);

  Future<void>? _enrichment;

  /// When the open cases were last enriched from the web of themselves.
  static const enrichedKey = 'web_enriched_at';

  /// The web portal's hearings, once a day of itself, and, when UYAP Mobil
  /// is not connected, the portfolio on the same terms as [syncMobile]'s;
  /// or both when [force]d (the lawyer's Senkronize et). A second call
  /// while one runs waits for that one.
  Future<void> syncWeb({bool force = false, bool newCase = false}) =>
      _webSync ??= _run(PortalChannel.uyapWeb, (db) async {
        if (!_web.connected) return null;
        // With UYAP Mobil connected it reads the courts' cases; the web
        // reads only what it alone has, on its own clock.
        final webOnly = _mobile.connected;
        final (portfolioDue, rested) = _portfolioDue(
          db,
          full: force,
          newCase: newCase,
          key: webOnly ? _webOnlyKey : _portfolioKey,
        );
        final hearingsDue = force || _hearingsDue(db, PortalChannel.uyapWeb);
        if (!hearingsDue && !portfolioDue && _unfilled(db).isEmpty) {
          return null;
        }
        // Not left to a computer of the person's: it may have UYAP Mobil
        // only, and the prosecutors' and the Court of Cassation's are the
        // web's.
        var hearings = const HearingSyncResult(0, true, []);
        if (hearingsDue) {
          _progress(PortalChannel.uyapWeb, 'Duruşmalar');
          hearings = await syncHearings(
            PortalChannel.uyapWeb,
            db,
            _web.hearingRows,
          );
          if (hearings.complete) _hearingsRead(db, PortalChannel.uyapWeb);
        }
        var cases = const PortfolioResult(0, true);
        if (portfolioDue) {
          cases = await syncWebPortfolio(
            _web,
            db,
            webOnly: webOnly,
            // A new case may be in a prosecutor's office not yet known.
            everyProvince: newCase,
            includeClosed: db.meta(_closedKey) == '1',
            onChanged: () => portfolioVersion.value++,
            onProgress: (done, total) => _progress(
              PortalChannel.uyapWeb,
              total == 0 ? 'Portföy' : 'Portföy $done/$total',
            ),
          );
          final now = DateTime.now().toIso8601String();
          if (!cases.complete) {
            db.setMeta(_tryKey(webOnly ? _webOnlyKey : _portfolioKey), now);
          } else {
            // Read whole alone, it read what only the web has as well.
            db.setMeta(_webOnlyKey, now);
            if (!webOnly) db.setMeta(_portfolioKey, now);
          }
        }
        // Every case the web has not read of itself yet, read now: its
        // parties (whose clients they are), its money and an icra file's
        // account, which only the web gives. Beside UYAP Mobil, after it
        // has listed the courts' cases.
        if (webOnly) await _mobileSync;
        final filled = await _fill(db, PortalChannel.uyapWeb);
        if (!hearings.complete || !cases.complete || !filled) {
          return 'Bazı kayıtlar alınamadı';
        }
        return rested;
      }).whenComplete(() => _webSync = null);

  /// The open cases the channel reading them now has not read of
  /// themselves: with the web connected, those it has not read (UYAP
  /// Mobil's reading gives no money); else those UYAP Mobil has not. One
  /// that would not be read waits a day.
  List<PortalCase> _unfilled(PortalDatabase db) {
    final web = _web.connected;
    if (!web && !_mobile.connected) return const [];
    final now = DateTime.now();
    // The closed ones too where the lawyer asked for them listed.
    final closedToo = db.meta(_closedKey) == '1';
    return [
      for (final c in db.cases().values)
        if ((closedToo || !isClosedStatus(c.status?.value)) &&
            // The prosecutors' and the Court of Cassation's are the web's
            // alone; UYAP Mobil lists the Council of State's itself.
            (web ||
                c.family == CaseFamily.court ||
                c.family == CaseFamily.danistay) &&
            db.meta(web ? webCheckedKey(c.key) : 'case_checked:${c.key}') ==
                null &&
            switch (DateTime.tryParse(
              db.meta(
                    _fillTryKey(
                      c.key,
                      web ? PortalChannel.uyapWeb : PortalChannel.uyapMobile,
                    ),
                  ) ??
                  '',
            )) {
              null => true,
              final tried => now.difference(tried) > const Duration(days: 1),
            })
          c,
    ];
  }

  /// Where it is kept that the web read a case of itself.
  static String webCheckedKey(String key) => 'case_web_checked:$key';

  /// Where [channel]'s try at reading a case is kept: UYAP Mobil's
  /// does not keep the web from reading it.
  static String _fillTryKey(String key, PortalChannel channel) =>
      'case_fill_try:${channel.name}:$key';

  /// [_unfilled]'s cases read one by one by [channel], those with a hearing
  /// within a month first. True when every one was read.
  Future<bool> _fill(PortalDatabase db, PortalChannel channel) async {
    final todo = _unfilled(db);
    if (todo.isEmpty) return true;
    final now = DateTime.now();
    final soon = {
      for (final h in db.hearings(
        from: now,
        to: now.add(const Duration(days: 31)),
      ))
        h.caseKey,
    };
    todo.sort(
      (a, b) => (soon.contains(a.key) ? 0 : 1).compareTo(
        soon.contains(b.key) ? 0 : 1,
      ),
    );
    bool connected() =>
        !_disposed &&
        (channel == PortalChannel.uyapWeb ? _web.connected : _mobile.connected);
    return _refreshEach(db, todo, channel, keepGoing: connected);
  }

  /// What a case's reading brought kept beside the portfolio: its parties,
  /// for the clients and whose a deadline is, and when it was read, and
  /// whether by the web.
  Future<void> caseRead(UyapCasePanelController panel) async {
    final record = panel.record;
    if (record == null || panel.error != null) return;
    final db = await _database();
    final key = caseKey(record.number, record.court);
    _keepRead(db, key, record, web: panel.usedWeb, whole: panel.whole);
    portfolioVersion.value++;
    // For the person's other devices too.
    uyapChanged?.call();
  }

  /// What the first reading left unread, read on its own: when a session
  /// is taken up again with nothing read of itself, and after UYAP Mobil
  /// has listed the cases the web is to read. After what runs.
  Future<void> _fillOnly() async {
    final channel = _web.connected
        ? PortalChannel.uyapWeb
        : _mobile.connected
        ? PortalChannel.uyapMobile
        : null;
    if (channel == null || _disposed) return;
    await _webSync;
    await _mobileSync;
    final db = await _database();
    if (_unfilled(db).isEmpty) return;
    await _run(
      channel,
      (db) async => await _fill(db, channel) ? null : 'Bazı kayıtlar alınamadı',
    );
  }

  void _keepRead(
    PortalDatabase db,
    String key,
    UyapCaseRecord record, {
    required bool web,
    bool whole = true,
  }) {
    final at = DateTime.now().toIso8601String();
    if (record.parties.isNotEmpty) {
      db.saveCaseParties(key, record.parties, source: 'uyap');
    }
    // Its parties, money or account did not come: asked again.
    if (!whole) return;
    db.setMeta('case_checked:$key', at);
    if (web) db.setMeta(webCheckedKey(key), at);
  }

  /// When the web last read the prosecutors' and the Court of Cassation's
  /// cases whole, while UYAP Mobil read the rest.
  static const _webOnlyKey = 'portfolio_web_only_at';

  /// Where a reading of [key]'s that came back in part is stamped: tried
  /// again in two hours, not at once.
  static String _tryKey(String key) =>
      key == _portfolioKey ? 'portfolio_try_at' : '${key}_try';

  Future<void>? _webSync;

  /// When no UYAP reading runs: a call made while one runs would be given
  /// that one, or dropped by [_run].
  Future<void> _whenIdle() async {
    await Future.wait([?_mobileSync, ?_webSync]);
    while (!_disposed) {
      if (!state(PortalChannel.uyapMobile).running &&
          !state(PortalChannel.uyapWeb).running) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  /// The portfolio read again from whichever portal is connected, UYAP
  /// Mobil first; [full] as the lawyer's Senkronize et, [newCase] at once.
  Future<void> syncPortfolio({bool full = false, bool newCase = false}) =>
      Future.wait([
        if (_mobile.connected) syncMobile(full: full, newCase: newCase),
        // Alone, the web reads it all; beside UYAP Mobil, what only it has.
        if (_web.connected) syncWeb(force: full, newCase: newCase),
      ]);

  /// Whether the portfolio is being read, by either portal.
  bool get portfolioRunning =>
      state(PortalChannel.uyapMobile).running ||
      state(PortalChannel.uyapWeb).running;

  /// The state of the portal reading the portfolio now, UYAP Mobil's when
  /// neither is.
  ChannelSync get portfolioState => state(PortalChannel.uyapMobile).running
      ? state(PortalChannel.uyapMobile)
      : state(PortalChannel.uyapWeb).running
      ? state(PortalChannel.uyapWeb)
      : state(PortalChannel.uyapMobile);

  /// The channel [syncPortfolio] reads with now; null with neither.
  PortalChannel? get portfolioChannel => _mobile.connected
      ? PortalChannel.uyapMobile
      : _web.connected
      ? PortalChannel.uyapWeb
      : null;

  /// Whether the portfolio is to be read now, and what is said when it is
  /// not for having been read a little before ([full], by hand).
  (bool, String?) _portfolioDue(
    PortalDatabase db, {
    required bool full,
    bool newCase = false,
    String key = _portfolioKey,
  }) {
    final now = DateTime.now();
    final read = DateTime.tryParse(db.meta(key) ?? '');
    final tried = DateTime.tryParse(db.meta(_tryKey(key)) ?? '');
    if (!full) {
      return (
        (read == null || read.isBefore(weekStart(now))) &&
            (tried == null || now.difference(tried) > const Duration(hours: 2)),
        null,
      );
    }
    final last = [read, tried].nonNulls.fold<DateTime?>(
      null,
      (a, b) => a == null || b.isAfter(a) ? b : a,
    );
    // A Vekil Kaydı naming a new case reads at once, rest or not.
    if (newCase || last == null || now.difference(last) >= portfolioRest) {
      return (true, null);
    }
    final again = last.add(portfolioRest);
    return (
      false,
      'Portföy ${_clock(last)}’de okundu; UYAP’ı yormamak için '
          '${_clock(again)}’den önce yeniden okunmaz.',
    );
  }

  /// The mobile API's hearings, once a day, then its cases: the whole
  /// portfolio, read court by court in a hundred requests and more, on
  /// Mondays (the first time Folio runs in a week), or when [full] is
  /// asked (Portföyü yenile), though not again within [portfolioRest].
  /// The cases' documents are not asked for of themselves: a case's page
  /// asks when it is opened. A second call while one runs waits for that
  /// one.
  Future<void> syncMobile({
    bool full = false,
    bool newCase = false,
  }) => _mobileSync ??=
      _run(PortalChannel.uyapMobile, (db) async {
        if (!_mobile.connected) return null;
        if (!full && (deferToComputer?.call() ?? false)) return null;
        var hearings = const HearingSyncResult(0, true, []);
        if (full || _hearingsDue(db, PortalChannel.uyapMobile)) {
          _progress(PortalChannel.uyapMobile, 'Duruşmalar');
          hearings = await syncHearings(
            PortalChannel.uyapMobile,
            db,
            _mobile.hearingRows,
          );
          if (hearings.complete) _hearingsRead(db, PortalChannel.uyapMobile);
        }
        final (due, rested) = _portfolioDue(db, full: full, newCase: newCase);
        var cases = const PortfolioResult(0, true);
        if (due) {
          final session = _mobile.session.value;
          final ids = <String, String>{};
          cases = await syncMobilePortfolio(
            _mobile,
            db,
            includeClosed: db.meta(_closedKey) == '1',
            onChanged: () => portfolioVersion.value++,
            onCaseId: (key, id) => ids[key] = id,
            onProgress: (done, total) => _progress(
              PortalChannel.uyapMobile,
              total == 0 ? 'Portföy' : 'Portföy $done/$total',
            ),
          );
          _sessionIds = ids;
          _idsSession = session;
          // Read whole, it is not read again until next week; read in
          // part, it is tried again in two hours, the courts that failed
          // with it.
          db.setMeta(
            cases.complete ? _portfolioKey : 'portfolio_try_at',
            DateTime.now().toIso8601String(),
          );
        }
        // Alone, UYAP Mobil reads each case it has not of itself: its
        // parties and documents' list. Beside the web, the web does.
        final filled =
            _web.connected || await _fill(db, PortalChannel.uyapMobile);
        if (!hearings.complete || !cases.complete || !filled) {
          return 'Bazı kayıtlar alınamadı';
        }
        return rested;
      }).whenComplete(() {
        _mobileSync = null;
        if (_web.connected) unawaited(_fillOnly());
      });

  /// Monday's start of the week [at] falls in.
  static DateTime weekStart(DateTime at) =>
      DateTime(at.year, at.month, at.day - (at.weekday - DateTime.monday));

  /// Not read again by hand within this of the last reading.
  static const portfolioRest = Duration(hours: 3);

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  /// Whether [channel]'s hearings have not been read whole today.
  bool _hearingsDue(PortalDatabase db, PortalChannel channel) {
    final at = DateTime.tryParse(db.meta('hearings_at:${channel.name}') ?? '');
    final now = DateTime.now();
    return at == null ||
        at.year != now.year ||
        at.month != now.month ||
        at.day != now.day;
  }

  void _hearingsRead(PortalDatabase db, PortalChannel channel) => db.setMeta(
    'hearings_at:${channel.name}',
    DateTime.now().toIso8601String(),
  );

  Future<void>? _mobileSync;

  /// Counted up whenever a sync writes a case anew or changes one, as it
  /// runs: what lists the portfolio shows it then, and only then.
  final portfolioVersion = ValueNotifier<int>(0);

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

  /// The open cases asked what is new in them: documents, parties, state,
  /// money. Not all of them each time, which wrote over hundreds of cases
  /// to change a few: the ones the portfolio's reading brought anew or
  /// changed ([changed]), those with a hearing within a month, and of the
  /// rest the [stale] longest unasked (a seventh of them, so that each is
  /// asked within a week of daily syncs). Kept only where something changed, and the change remembered
  /// for the portfolio's list. One case at a time, as UYAP answers a
  /// burst with errors. With [changed] null, every open case is asked.
  Future<bool> refreshCases(
    PortalDatabase db, {
    Set<String>? changed,
    int? stale,
    PortalChannel channel = PortalChannel.uyapMobile,
    bool Function()? keepGoing,
  }) async {
    final all = [
      for (final c in db.cases().values)
        if ((c.family == CaseFamily.court ||
                channel == PortalChannel.uyapWeb) &&
            !isClosedStatus(c.status?.value))
          c,
    ];
    final now = DateTime.now();
    DateTime? checked(PortalCase c) =>
        DateTime.tryParse(db.meta('case_checked:${c.key}') ?? '');
    final List<PortalCase> open;
    if (changed == null) {
      open = all;
    } else {
      final soon = {
        for (final h in db.hearings(
          from: now,
          to: now.add(const Duration(days: 31)),
        ))
          h.caseKey,
      };
      final chosen = {
        for (final c in all)
          if (changed.contains(c.key) || soon.contains(c.key)) c.key,
      };
      final rest =
          [
            for (final c in all)
              if (!chosen.contains(c.key) &&
                  (checked(c) == null ||
                      now.difference(checked(c)!) > const Duration(days: 7)))
                c,
          ]..sort((a, b) {
            final x = checked(a), y = checked(b);
            if (x == null || y == null) {
              return x == null ? (y == null ? 0 : -1) : 1;
            }
            return x.compareTo(y);
          });
      // A seventh of the open cases a day: each asked within the week.
      chosen.addAll(
        rest.take(stale ?? max(30, (all.length / 7).ceil())).map((c) => c.key),
      );
      open = [
        for (final c in all)
          if (chosen.contains(c.key)) c,
      ];
    }
    final through = await _refreshEach(db, open, channel, keepGoing: keepGoing);
    db.setMeta(_checkedKey, DateTime.now().toIso8601String());
    notifyListeners();
    return through;
  }

  /// [open] read one case at a time, as UYAP answers a burst with errors;
  /// what each brought kept ([_keepRead]), and the change remembered for
  /// the portfolio's list. False when one was not read or [keepGoing]
  /// stopped it.
  Future<bool> _refreshEach(
    PortalDatabase db,
    List<PortalCase> open,
    PortalChannel channel, {
    bool Function()? keepGoing,
  }) async {
    var through = true;
    for (final (i, kase) in open.indexed) {
      if ((!_mobile.connected && !_web.connected) ||
          (keepGoing != null && !keepGoing())) {
        through = false;
        break;
      }
      _progress(channel, 'Dosyalar ${i + 1}/${open.length}');
      // A lawyer waiting for a case of theirs goes first.
      while (UyapCasePanelController.lawyerWaiting) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      final panel = UyapCasePanelController(
        web: _web,
        mobile: _mobile,
        sync: this,
        pause: Duration.zero,
        background: true,
      );
      try {
        db.setMeta(
          _fillTryKey(kase.key, channel),
          DateTime.now().toIso8601String(),
        );
        await panel.attach(linkOf(kase));
        final before = panel.record;
        await panel.refresh();
        // Not answered: its turn comes again soon, not in a week, and the
        // day is not done.
        if (panel.error != null || panel.record == null) {
          through = false;
          continue;
        }
        final after = panel.record!;
        // Asked, changed or not: it waits its turn again.
        _keepRead(db, kase.key, after, web: panel.usedWeb, whole: panel.whole);
        if (!panel.whole) through = false;
        portfolioVersion.value++;
        if (identical(after, before)) continue;
        db.noteChange(
          kase.key,
          fresh: after.fresh.length,
          change: before == null ? null : describeChange(before, after),
        );
      } catch (_) {
        // One case that does not answer does not stop the others.
        through = false;
      } finally {
        panel.dispose();
      }
      await Future<void>.delayed(_caseGap);
    }
    return through;
  }

  /// Between two cases read one after another.
  @visibleForTesting
  static Duration caseGap = const Duration(milliseconds: 250);
  Duration get _caseGap => caseGap;

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
    final kept = (await _database()).caseOf(key);
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
      (await _database()).caseOf(key);

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

  /// The cases the reading brought anew or changed; the others it left as
  /// they were.
  final Set<String> changed;
  const PortfolioResult(this.cases, this.complete, [this.changed = const {}]);
}

/// The kinds of jurisdiction the mobile API lists cases for: ceza, hukuk,
/// icra and idari. The Court of Cassation's and the prosecutors' are the
/// web's alone (§9.2).
const mobileJurisdictions = [1, 0, 2, 6];

/// The kinds of jurisdiction the web portal lists cases for, court by
/// court: the mobile API's four and satış and arabuluculuk, which it has
/// not. The prosecutors' offices and the high courts have lists of their
/// own (§9.2).
const webJurisdictions = ['1', '0', '2', '6', '11', '13'];

/// What the web reads beside UYAP Mobil: what the mobile API does not give.
const _webOnlyJurisdictions = ['11', '13'];

/// Pages of [UyapWebService.pageSize] asked at most of one list: past it
/// the reading is said to be incomplete, never cut short in silence.
const _webPages = 40;

/// The prosecutors' offices where the lawyer has had a case, kept so that
/// a reading asks them alone and not all 81 provinces.
const _prosecutorOfficesKey = 'web_prosecutor_offices';
const _prosecutorFullKey = 'web_prosecutor_full_at';

/// Every case the web portal knows of the lawyer's, merged into [db] as
/// [syncMobilePortfolio] merges the mobile API's: court by court, by yargı
/// türü and birimi (the same codes as the mobile API's), page by page; the
/// prosecutors' offices province by province (open and closed, for most
/// investigations are closed); the high courts chamber by chamber. With
/// each case its place on the web is kept (its birim and the codes).
///
/// [webOnly], while UYAP Mobil reads the courts' cases: only what it does
/// not give, satış and arabuluculuk, the prosecutors' offices and the
/// Court of Cassation. The prosecutors' offices are found in all 81
/// provinces the first time, when [everyProvince] or a month on; between,
/// only those where a case was found are asked. A list that fails, or is
/// longer than [_webPages] pages, makes the answer incomplete; the others
/// are still asked.
Future<PortfolioResult> syncWebPortfolio(
  UyapWebService web,
  PortalDatabase db, {
  void Function()? onChanged,
  void Function(int done, int total)? onProgress,
  bool includeClosed = false,
  bool webOnly = false,
  bool everyProvince = false,
}) async {
  final baseline = db.meta('portfolio_at') == null;
  final asked = DateTime.now().toUtc();
  const channel = PortalChannel.uyapWeb;
  var complete = true;
  final found = <String, PortalCase>{};
  final changed = <String>{};

  void add(
    UyapCase c,
    CaseFamily family, {
    required String jurisdiction,
    String? unit,
    bool closed = false,
  }) {
    final number = c.number.trim();
    final court = c.courtName.trim();
    if (number.isEmpty || court.isEmpty) return;
    final listing = c.listing;
    final state = (listing?.state ?? '').trim();
    final details = {
      if ((listing?.type ?? '').isNotEmpty) 'tur': listing!.type,
      'acilis': ?listing?.openedOn,
      'kapanis': ?listing?.closedOn,
      'yargiTuru': jurisdiction,
      'yargiBirimi': ?unit,
      if (c.courtId.isNotEmpty) 'birimId': c.courtId,
    };
    final one = PortalCase(
      key: caseKey(number, court),
      number: number,
      court: court,
      family: family,
      ids: {if (c.id.isNotEmpty) channel: c.id},
      status: Observed(
        state.isNotEmpty ? state : (closed ? 'Kapalı' : 'Açık'),
        channel,
        asked,
      ),
      details: Observed(details, channel, asked, complete: false),
    );
    found[one.key] = found[one.key]?.merge(one) ?? one;
  }

  void keep() {
    if (found.isEmpty) return;
    final before = changed.length;
    db.mergeCases(
      found.values,
      portfolio: true,
      baseline: baseline,
      changed: changed,
    );
    if (changed.length != before) onChanged?.call();
    found.clear();
  }

  /// Every page of one list, until a page is not full or the total is
  /// reached; false when it ran past [_webPages].
  Future<bool> pages(
    Future<UyapCasePage> Function(int page) ask,
    void Function(UyapCase c) each,
  ) async {
    final ids = <String>{};
    for (var page = 1; page <= _webPages; page++) {
      final got = await ask(page);
      var fresh = 0;
      for (final c in got.cases) {
        if (ids.add(c.id.isEmpty ? '${c.courtId}|${c.number}' : c.id)) fresh++;
        each(c);
      }
      keep();
      final total = got.total;
      // A page answered again as the last one: no more is coming.
      if (got.cases.isNotEmpty && fresh == 0) return false;
      if (got.rows < UyapWebService.pageSize) {
        // Short of what the portal said it has: not whole.
        return total == null || ids.length >= total;
      }
      if (total != null && ids.length >= total) return true;
    }
    return false;
  }

  // Each kind of court read as soon as its courts are known, hukuk first:
  // the cases come in from the first minute, not after every list of
  // courts and every province's prosecutors' offices has been asked. How
  // far the reading has come counts what is known so far.
  var steps = 0;
  var step = 0;
  onProgress?.call(0, 0);
  for (final jurisdiction
      in webOnly ? _webOnlyJurisdictions : webJurisdictions) {
    List<UyapOption> units;
    try {
      units = await web.courtTypes(jurisdiction);
    } catch (_) {
      complete = false;
      continue;
    }
    final courts = <(String, UyapOption, bool)>[];
    for (final unit in units) {
      for (final closed in [false, if (includeClosed) true]) {
        try {
          for (final court in await web.courts(
            jurisdiction,
            unit.id,
            closed: closed,
          )) {
            courts.add((unit.id, court, closed));
          }
        } catch (_) {
          complete = false;
        }
      }
    }
    steps += courts.length;
    for (final (unit, court, closed) in courts) {
      onProgress?.call(step++, steps);
      try {
        final whole = await pages(
          (page) => web.casePage(
            jurisdiction: jurisdiction,
            courtType: unit,
            court: court,
            closed: closed,
            pageNumber: page,
          ),
          (c) => add(
            c,
            CaseFamily.court,
            jurisdiction: jurisdiction,
            unit: unit,
            closed: closed,
          ),
        );
        if (!whole) complete = false;
      } catch (_) {
        complete = false;
      }
    }
  }

  // The high courts, chamber by chamber: a few lists.
  for (final (jurisdiction, family) in [
    ('yargitay', CaseFamily.yargitay),
    // The mobile API lists the Council of State's itself.
    if (!webOnly) ('danistay', CaseFamily.danistay),
  ]) {
    List<UyapOption> chambers;
    try {
      chambers = await web.chambers(jurisdiction);
    } catch (_) {
      complete = false;
      continue;
    }
    // One chamber that fails does not keep the others from being read.
    for (final chamber in chambers) {
      try {
        for (final c in await web.chamberCases(jurisdiction, chamber)) {
          add(c, family, jurisdiction: jurisdiction);
        }
        keep();
      } catch (_) {
        complete = false;
      }
    }
  }

  // The prosecutors' offices last: the known ones, or every province's,
  // which is hundreds of questions. Known by the cases kept of them, which
  // another own device brings too, and by those found before with no case
  // kept now.
  final known = <String, String>{
    for (final o
        in (jsonDecode(db.meta(_prosecutorOfficesKey) ?? '[]') as List))
      if (o is Map) '${o['id']}': '${o['ad'] ?? ''}',
    for (final c in db.cases().values)
      if (c.family == CaseFamily.prosecutor)
        if ('${c.details?.value['birimId'] ?? ''}'.trim() case final id
            when id.isNotEmpty)
          id: c.court,
  };
  final full = DateTime.tryParse(db.meta(_prosecutorFullKey) ?? '');
  final everywhere =
      everyProvince ||
      full == null ||
      DateTime.now().difference(full) > const Duration(days: 30);
  var offices = [for (final e in known.entries) UyapOption(e.key, e.value)];
  var provincesRead = false;
  if (everywhere) {
    try {
      final all = <UyapOption>[];
      var whole = true;
      for (final province in await web.provinces()) {
        try {
          all.addAll(await web.prosecutorOffices(province.id));
        } catch (_) {
          whole = false;
        }
      }
      if (!whole) complete = false;
      // The known ones too: a province that did not answer keeps its own.
      final ids = {for (final o in all) o.id};
      offices = [...all, ...offices.where((o) => !ids.contains(o.id))];
      provincesRead = whole;
    } catch (_) {
      complete = false;
    }
  }

  steps += offices.length;
  final withCases = <String, String>{...known};
  var officesWhole = provincesRead || !everywhere;
  for (final office in offices) {
    onProgress?.call(step++, steps);
    for (final closed in [false, true]) {
      try {
        var any = false;
        final whole = await pages(
          (page) =>
              web.prosecutorCases(office, closed: closed, pageNumber: page),
          (c) {
            any = true;
            add(
              c,
              CaseFamily.prosecutor,
              jurisdiction: UyapWebService.prosecution,
              unit: office.id,
              closed: closed,
            );
          },
        );
        if (any) withCases[office.id] = office.label;
        if (!whole) {
          complete = false;
          officesWhole = false;
          withCases[office.id] = office.label;
        }
      } catch (_) {
        complete = false;
        officesWhole = false;
        // Asked again next time, whether it has cases or not.
        withCases[office.id] = office.label;
      }
    }
  }
  db.setMeta(
    _prosecutorOfficesKey,
    jsonEncode([
      for (final e in withCases.entries) {'id': e.key, 'ad': e.value},
    ]),
  );
  if (everywhere && officesWhole) {
    db.setMeta(_prosecutorFullKey, DateTime.now().toIso8601String());
  }
  onProgress?.call(steps, steps);
  keep();
  return PortfolioResult(steps, complete, changed);
}

/// Every case the mobile API knows of the lawyer's, open and closed, merged
/// into [db]: the number, the court, the status and the kind, as partial
/// answers that fill what the web has not given and replace nothing it
/// has (§9.4). A court that fails makes the answer incomplete; the others
/// are still asked.
Future<PortfolioResult> syncMobilePortfolio(
  UyapMobileApi api,
  PortalDatabase db, {
  void Function()? onChanged,
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
  final changed = <String>{};

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
        final before = changed.length;
        db.mergeCases(
          found.values,
          portfolio: true,
          baseline: baseline,
          changed: changed,
        );
        if (changed.length != before) onChanged?.call();
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
  db.mergeCases(
    found.values,
    portfolio: true,
    baseline: baseline,
    changed: changed,
  );
  return PortfolioResult(courts.length, complete, changed);
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

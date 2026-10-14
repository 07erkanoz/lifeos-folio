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
import 'case_sections.dart';
import 'portal_channel.dart';
import 'uyap_job.dart';
import 'portal_database.dart';
import 'portal_hearing.dart';
import 'sync_log.dart';
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
  static PortalSync get instance =>
      _instance ??= PortalSync(quiet: quietHere)..start();

  /// Set by an editor window of its own: whatever first asks for the one
  /// instance here (a page, a picker), it is [quiet].
  static bool quietHere = false;

  /// The one started, if Folio started it: what only looks (a list, a
  /// listener) uses this, so that a test never wakes the lawyer's sessions.
  static PortalSync? get started => _instance;

  /// Starts the one instance: the kept mobile session comes back with it.
  /// Folio's window and an editor window of its own call this at start;
  /// the editor's is [quiet].
  static void begin({bool quiet = false}) =>
      _instance ??= PortalSync(quiet: quiet || quietHere)..start();

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
      _autoLoaded.whenComplete(() {
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
    await _loadJob();
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
        // Turned off meanwhile, or let go of: nothing is started.
        if (!autoFetch || _disposed) return;
        final now = DateTime.now();
        final read = DateTime.tryParse(db.meta(_portfolioKey) ?? '');
        final tried = DateTime.tryParse(db.meta('portfolio_try_at') ?? '');
        final portfolioDue =
            (read == null || read.isBefore(weekStart(now))) &&
            (tried == null || now.difference(tried) > const Duration(hours: 2));
        if (_mobile.connected &&
            (portfolioDue || _hearingsDue(db, PortalChannel.uyapMobile))) {
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
            (_hearingsDue(db, PortalChannel.uyapWeb) || webPortfolioDue)) {
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
    unawaited(
      SyncLog.note(
        _web.connected ? 'UYAP Web bağlandı' : 'UYAP Web bağlantısı kapandı',
      ),
    );
    _rememberTc(_web.tckn);
    // The lawyer's name as the web portal gives it, where the profile has
    // none: whose clients the parties are is told by it.
    final user = _web.session.value?.user.trim() ?? '';
    if (user.isNotEmpty && !_placeholder(user)) {
      _remember(() => rememberLawyer(name: user));
    }
    if (_web.connected && !quiet) unawaited(_connected(PortalChannel.uyapWeb));
  }

  /// A portal connected (by the lawyer, or a session taken up again)
  /// (docs/uyap-hedef-harita.md §5). A job the lawyer started on it and did
  /// not pause goes on where it was. With UYAP read of itself ([autoFetch])
  /// what is due is read. Else nothing: never read, the setup is offered
  /// ([setupOffer]) for the lawyer to start. A case is read when its page
  /// is opened, everything else by the lawyer's own buttons.
  Future<void> _connected(PortalChannel channel) async {
    await _autoLoaded;
    if (_disposed || quiet) return;
    final j = job.value;
    if (j != null &&
        !j.done &&
        j.channel == channel &&
        (j.stopped == null || j.stopped == UyapJobStop.session)) {
      unawaited(SyncLog.note('Bağlandı: başlatılan iş kaldığı yerden sürüyor'));
      unawaited(_runJob());
      return;
    }
    final sync = channel == PortalChannel.uyapWeb ? syncWeb : syncMobile;
    if (autoFetch) {
      unawaited(sync());
      unawaited(syncNotices());
      return;
    }
    final db = await _database();
    final neverRead =
        db.meta(_portfolioKey) == null && db.meta(_webOnlyKey) == null;
    if (neverRead && j == null) setupOffer.value = true;
  }

  // The lawyer's own long readings (§6, §11.3).

  /// The setup or the web's completion the lawyer started; null when none.
  final job = ValueNotifier<UyapJob?>(null);

  /// How far the running job has come.
  final jobProgress = ValueNotifier<UyapJobProgress?>(null);

  /// Set when a portal connects and the portfolio was never read: the
  /// screens offer the setup, which the lawyer starts.
  static final setupOffer = ValueNotifier<bool>(false);

  static const _jobKey = 'uyap_job';
  Future<void>? _jobRun;

  /// Counted up when a job starts, is paused or let go of: a run of an
  /// earlier count stops at its next step and writes nothing more.
  int _jobGen = 0;

  Future<void> _loadJob() async {
    try {
      job.value = UyapJob.decode((await _database()).meta(_jobKey));
    } catch (_) {}
  }

  Future<UyapJob> _keepJob(UyapJob next) async {
    (await _database()).setMeta(_jobKey, next.encode());
    job.value = next;
    return next;
  }

  /// The first setup, on [channel]: its portfolio's list and hearings,
  /// then each open case's parties, then each one's documents' list. The
  /// lawyer starts it, so it runs with [autoFetch] off.
  Future<void> startSetup(PortalChannel channel) => _startJob(
    UyapJob(
      kind: UyapJobKind.setup,
      channel: channel,
      stage: UyapJobStage.list,
      started: DateTime.now(),
    ),
  );

  /// The web's completion: the Court of Cassation's cases, then each open
  /// case's particulars, parties with counsel, money, an icra file's
  /// account and debtors, and its documents' list where none came whole.
  Future<void> startWebCompletion() => _startJob(
    UyapJob(
      kind: UyapJobKind.webCompletion,
      channel: PortalChannel.uyapWeb,
      stage: UyapJobStage.list,
      started: DateTime.now(),
    ),
  );

  Future<void> _startJob(UyapJob next) async {
    setupOffer.value = false;
    final gen = ++_jobGen;
    // A run of the job before stops first: one job at a time.
    await _jobRun;
    // Another start, a pause or a drop came meanwhile: that one stands.
    if (gen != _jobGen || _disposed) return;
    await _keepJob(next);
    unawaited(
      SyncLog.note(
        '${next.kind == UyapJobKind.setup ? 'Kurulum' : 'Web tamamlaması'} '
        'başladı (${_channelName(next.channel)})',
      ),
    );
    await _runJob();
  }

  /// The running job paused by the lawyer: it waits for them
  /// ([resumeJob]), the cases read kept. The case being read when it is
  /// paused is the last one.
  Future<void> pauseJob() async {
    final j = job.value;
    if (j == null || j.done) return;
    _jobGen++;
    await _keepJob(j.copyWith(stage: j.stage, stopped: UyapJobStop.user));
  }

  /// A stopped job goes on, where its channel is connected; not connected,
  /// it stays stopped, waiting for the channel.
  Future<void> resumeJob() async {
    if (job.value == null || job.value!.done) return;
    final gen = ++_jobGen;
    await _jobRun;
    // Let go of, paused or started anew meanwhile: that stands.
    final j = job.value;
    if (gen != _jobGen || _disposed || j == null || j.done) return;
    if (!_jobConnected(j)) {
      await _keepJob(j.copyWith(stage: j.stage, stopped: UyapJobStop.session));
      return;
    }
    await _keepJob(j.copyWith(stage: j.stage));
    if (gen != _jobGen) return;
    await _runJob();
  }

  /// The job let go of: what it read stays.
  Future<void> dropJob() async {
    _jobGen++;
    (await _database()).setMeta(_jobKey, '');
    job.value = null;
    jobProgress.value = null;
  }

  static String _channelName(PortalChannel c) =>
      c == PortalChannel.uyapWeb ? 'UYAP Web' : 'UYAP Mobil';

  bool _jobConnected(UyapJob j) =>
      j.channel == PortalChannel.uyapWeb ? _web.connected : _mobile.connected;

  /// The list the job's first stage reads: the whole portfolio for the
  /// setup on either channel; what only the web has for the completion.
  String _jobListKey(UyapJob j) =>
      j.kind == UyapJobKind.setup ? _portfolioKey : _webOnlyKey;

  Future<void> _runJob() => _jobRun ??= _jobSteps()
      .catchError((Object e) {
        unawaited(SyncLog.note('İş durdu: $e'));
      })
      .whenComplete(() => _jobRun = null);

  Future<void> _jobSteps() async {
    final gen = _jobGen;
    var j = job.value;
    if (j == null || j.done || !_jobConnected(j)) return;
    // Whether this run is still the job's: a pause, a drop or a start
    // after it makes it another's, and it writes nothing more.
    bool current() => !_disposed && gen == _jobGen;
    bool going() => current() && _jobConnected(j!);
    Future<bool> keep(UyapJob next) async {
      final db = await _database();
      if (!current()) return false;
      db.setMeta(_jobKey, next.encode());
      job.value = next;
      j = next;
      return true;
    }

    Future<void> stopped([UyapJobStop why = UyapJobStop.session]) async {
      if (await keep(j!.copyWith(stage: j!.stage, stopped: why))) {
        unawaited(SyncLog.note('İş durdu (${why.name}): ${j!.stage.name}'));
      }
    }

    // A reading of the lawyer's own on the channel finishes first: one
    // started while it runs would be given that one.
    Future<void> idle() async {
      while (state(j!.channel).running && going()) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }

    if (j!.stage == UyapJobStage.list) {
      jobProgress.value = const UyapJobProgress(UyapJobStage.list, 0, 0);
      await idle();
      if (!going()) return stopped();
      final db = await _database();
      if (!going()) return stopped();
      final key = _jobListKey(j!);
      final before = db.meta(key);
      final webSetup =
          j!.channel == PortalChannel.uyapWeb && j!.kind == UyapJobKind.setup;
      if (j!.channel == PortalChannel.uyapMobile) {
        await syncMobile(full: true);
      } else {
        // The setup on the web reads every list, UYAP Mobil connected or
        // not, and is not held back by UYAP Mobil's reading before.
        await syncWeb(force: true, whole: webSetup);
      }
      if (!going()) return stopped();
      // Read whole now; on UYAP Mobil also within the rest before: the
      // list is there. Else it is said, and the cases listed are read.
      final at = DateTime.tryParse(db.meta(key) ?? '');
      final fresh =
          at != null &&
          (db.meta(key) != before ||
              (!webSetup && DateTime.now().difference(at) < portfolioRest));
      if (!await keep(
        j!.copyWith(
          stage: j!.kind == UyapJobKind.setup
              ? UyapJobStage.parties
              : UyapJobStage.web,
          listGaps: !fresh,
        ),
      )) {
        return;
      }
    }
    for (final (stage, next) in [
      (UyapJobStage.parties, UyapJobStage.documents),
      (UyapJobStage.documents, UyapJobStage.done),
      (UyapJobStage.web, UyapJobStage.done),
    ]) {
      if (j!.stage != stage) continue;
      await idle();
      if (!going()) return stopped();
      // Not run (another reading took the channel first): not done.
      int? left;
      await _run(j!.channel, (db) async {
        left = await _jobCases(db, j!, going, current);
        return left! > 0 ? 'Bazı dosyalar okunamadı' : null;
      });
      if (!going()) return stopped();
      // Cases left that would not be read, or the stage not run: the job
      // waits, to be tried again when the lawyer says.
      if (left == null || left! > 0) return stopped(UyapJobStop.incomplete);
      if (!await keep(j!.copyWith(stage: next))) return;
    }
    if (j!.done) {
      jobProgress.value = null;
      unawaited(SyncLog.note('İş bitti: ${j!.kind.name}'));
      uyapChanged?.call();
    }
  }

  /// Tries at a section before a job gives it up: it stays failed, shown,
  /// and is read when the case is opened.
  static const _jobTries = 3;

  /// The sections [j]'s stage reads of a case, of those its channel has
  /// not read done as they last were; empty when none is left.
  Set<CaseSection> _jobWants(UyapJob j, List<SectionState> states) {
    SectionState? on(CaseSection s, PortalChannel c) =>
        states.where((x) => x.section == s && x.channel == c).firstOrNull;
    bool wanted(CaseSection s, PortalChannel c) {
      final x = on(s, c);
      if (x == null) return true;
      if (x.result.done && x.succeeded != null) return false;
      return x.tries < _jobTries;
    }

    return switch (j.stage) {
      UyapJobStage.parties => {
        if (wanted(CaseSection.parties, j.channel)) CaseSection.parties,
      },
      UyapJobStage.documents => {
        if (wanted(CaseSection.documents, j.channel)) CaseSection.documents,
      },
      UyapJobStage.web => {
        for (final s in CaseSection.values)
          if (wanted(s, PortalChannel.uyapWeb) &&
              // The documents' list UYAP Mobil gave whole is not asked again.
              !(s == CaseSection.documents &&
                  (on(s, PortalChannel.uyapMobile)?.complete ?? false)))
            s,
      },
      _ => const {},
    };
  }

  /// The open cases [j]'s stage has left, read one at a time on its
  /// channel alone: those with a hearing within a month first, then the
  /// icra files, then the rest. Each case's sections are counted again
  /// just before it is read: what the lawyer read meanwhile is not asked
  /// again. How many are left unread at the end, counted anew; on stopping
  /// ([going]) at least one. A run no longer [current] writes nothing.
  Future<int> _jobCases(
    PortalDatabase db,
    UyapJob j,
    bool Function() going,
    bool Function() current,
  ) async {
    final archived = db.revokedShares();
    final now = DateTime.now();
    final soon = {
      for (final h in db.hearings(
        from: now,
        to: now.add(const Duration(days: 31)),
      ))
        h.caseKey,
    };
    int rank(PortalCase c) => soon.contains(c.key)
        ? 0
        : '${c.details?.value['yargiTuru'] ?? ''}' == '2'
        ? 1
        : 2;
    final mobile = j.channel == PortalChannel.uyapMobile;
    final open = [
      for (final c in db.cases().values)
        if (!archived.contains(c.key) &&
            !isClosedStatus(c.status?.value) &&
            // UYAP Mobil does not open the prosecutors' and the Court of
            // Cassation's: the web's completion does (§11.6).
            (!mobile || mobileReads(c)))
          c,
    ]..sort((a, b) => rank(a).compareTo(rank(b)));
    final total = open.length;
    var done = 0;
    final label = switch (j.stage) {
      UyapJobStage.parties => 'Taraflar',
      UyapJobStage.documents => 'Evrak listeleri',
      _ => 'Web bilgileri',
    };
    unawaited(SyncLog.note('$label: $total açık dosya'));
    final changed = <String>{};
    try {
      for (final kase in open) {
        if (!going()) return 1;
        if (_jobWants(j, db.sections(kase.key)).isEmpty) {
          done++;
          continue;
        }
        jobProgress.value = UyapJobProgress(j.stage, done, total);
        while (UyapCasePanelController.lawyerWaiting && going()) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
        if (!going()) return 1;
        _progress(j.channel, '$label $done/$total');
        final panel = UyapCasePanelController(
          web: _web,
          mobile: _mobile,
          sync: this,
          pause: Duration.zero,
          background: true,
        );
        try {
          await panel.attach(linkOf(kase));
          // Counted again now: the lawyer may have read it meanwhile.
          final wants = _jobWants(j, db.sections(kase.key));
          if (wants.isNotEmpty && going()) {
            await panel.readSections(j.channel, wants);
            // A run let go of keeps nothing more.
            if (!current()) return 1;
            if (panel.outcomes.isNotEmpty && panel.record != null) {
              // What came is kept, the session gone after it or not.
              _keepRead(
                db,
                kase.key,
                panel.record!,
                web: j.channel == PortalChannel.uyapWeb,
                whole: panel.whole && panel.error == null,
                outcomes: panel.outcomes,
              );
              if (panel.outcomes.any(
                (o) =>
                    o.section == CaseSection.parties &&
                    o.result == SectionResult.read,
              )) {
                changed.add(kase.key);
              }
            } else {
              // The session gone: stopped, to go on when it is back.
              if (!going()) return 1;
              // Counted a try, so that it is not asked for without end.
              db.saveSections(kase.key, j.channel, [
                for (final s in wants) SectionOutcome(s, SectionResult.failed),
              ]);
              unawaited(SyncLog.note('$label: ${kase.number} okunamadı'));
            }
            portfolioVersion.value++;
          }
        } catch (e) {
          unawaited(SyncLog.note('$label: ${kase.number} hata: $e'));
        } finally {
          panel.dispose();
        }
        if (!going()) return 1;
        done++;
        jobProgress.value = UyapJobProgress(j.stage, done, total);
        await Future<void>.delayed(_caseGap);
      }
    } finally {
      // Whose a deadline is, told again by the parties come.
      if (changed.isNotEmpty) await _partiesChanged(db, changed);
    }
    // Counted at the end: one the lawyer read meanwhile is not left.
    return [
      for (final c in open)
        if (_jobWants(j, db.sections(c.key)).isNotEmpty) c,
    ].length;
  }

  /// Whether UYAP Mobil reads [kase]'s sections: a court's or the Council
  /// of State's. The prosecutors' and the Court of Cassation's are the
  /// web's until their mobile ways are measured (§11.6).
  static bool mobileReads(PortalCase kase) =>
      kase.family == CaseFamily.court || kase.family == CaseFamily.danistay;

  /// The deadlines of the notices of [keys]' cases made again, by the
  /// parties now kept: nothing is asked of UYAP.
  Future<void> _partiesChanged(PortalDatabase db, Set<String> keys) async {
    try {
      await _loadDeadlineContext();
      refreshNoticeDeadlines(
        db,
        parties: NoticeDeadlineContext.parties,
        lawyer: NoticeDeadlineContext.lawyer,
        only: {
          for (final n in db.notices())
            if (keys.contains(n.caseKey)) n.message.id,
        },
      );
      notifyListeners();
    } catch (_) {}
  }

  /// Done when whether UYAP is read of itself is known.
  late final Future<void> _autoLoaded = _loadAuto();

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
    // UETS asks UYAP nothing (docs/uyap-hedef-harita.md §4 T): the parties
    // of a notice's case come from its package, or from the case's reading.
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
      // notice's deadlines made again as its documents are read. The
      // portfolio is read once for them all, and again only if it changed:
      // by the database's own count of case writes, which every writer
      // moves (a hearing's sync adds cases without telling the portfolio).
      (int, Map<String, PortalCase>)? portfolio;
      Map<String, PortalCase> cases() {
        final version = db.casesRevision;
        final kept = portfolio;
        if (kept != null && kept.$1 == version) return kept.$2;
        return (portfolio = (version, db.cases())).$2;
      }

      await readNoticeDocuments(
        db,
        onRead: (id) {
          tieByCaseFile(db, id, cases: cases());
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
      for (final (record, _) in await UyapCaseStore.instance.cases(
        counted: false,
      )) {
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
    // clients' accounts; and those a notice's package gave, where the case
    // itself was not fetched.
    try {
      final db = await _database();
      // Only where none are kept: a record's parties are not written again
      // over those its readings kept, under another name.
      final kept = db.caseParties();
      for (final e in fetched.entries) {
        if (kept.containsKey(e.key)) continue;
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
    if (_mobile.connected && !quiet) {
      unawaited(_connected(PortalChannel.uyapMobile));
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

  /// Changes when a channel connects, starts, finishes or fails; a line of
  /// progress alone leaves it as it was. A page that reads its data again
  /// when told should compare this first: told twice a second while a sync
  /// runs, a page reading everything each time held the window.
  String get channelStamp => [
    for (final c in PortalChannel.values)
      '${state(c).running}/${state(c).finished?.microsecondsSinceEpoch}/'
          '${state(c).problem}',
    _web.connected,
    _mobile.connected,
    _uets.connected,
  ].join('|');

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

  /// When a notification last named a case the portfolio has not, with
  /// Folio not reading UYAP of itself: the lawyer is told, to read the
  /// portfolio again ("Portföyü yenile").
  static final newCaseNotice = ValueNotifier<DateTime?>(null);

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
        // Read of itself only while the lawyer has Folio read UYAP of
        // itself; else they are told, and read the portfolio when they
        // will (docs/uyap-hedef-harita.md §5).
        // A phone's background check never reads the portfolio (§5).
        if (autoFetch && !paused) {
          // One running now may not read the portfolio: this one follows
          // it. Both the readings under way are waited for: a call while
          // one runs would only be given that one.
          unawaited(
            _whenIdle().whenComplete(() {
              // Turned off meanwhile, or let go of: told instead.
              if (!autoFetch || _disposed) {
                if (!_disposed) newCaseNotice.value = DateTime.now();
                return;
              }
              unawaited(syncPortfolio(full: true, newCase: true));
            }),
          );
        } else {
          newCaseNotice.value = DateTime.now();
          unawaited(
            SyncLog.note(
              'Vekil Kaydı bildirimi: portföyde olmayan dosya; '
              'okuma kullanıcıya bırakıldı',
            ),
          );
        }
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

  /// Why a case kept as an archive is not asked about.
  static const _archiveWord =
      'Paylaşımı kaldırılan dosya arşivde duruyor; UYAP’a sorulmaz.';

  Future<String?> syncCase(String key) async {
    final db = await _database();
    final kase = db.caseOf(key);
    if (kase == null) return 'Dosya henüz kayıtlı değil.';
    if (db.revokedShare(key) != null) return _archiveWord;
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
      // Ids are their session's: the case is found in this one by its
      // court and number, even one known only from a hearing; on UYAP
      // Mobil only a court's or the Council of State's (§11.6).
      String? id;
      if (channel != PortalChannel.uyapWeb) {
        if (!mobileReads(kase)) continue;
        try {
          id = await mobileCaseId(court: kase.court, number: kase.number);
        } catch (_) {}
        // Not found anew: the id the list gave, which may still hold.
        if (id == null || id.isEmpty) id = kase.ids[channel];
        if (id == null || id.isEmpty) continue;
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

  /// The open cases' web sections freshened of themselves while
  /// [autoFetch] is on, once a day (docs/uyap-hedef-harita.md §7): only
  /// sections the web read before and older than a week, or failed, those
  /// with a hearing within a month first; at most [enrichPerDay] cases a
  /// day, not at night. The first filling is the lawyer's (the web's
  /// completion), never this. On the web alone; it stops when the web
  /// goes, at night or when [autoFetch] is turned off, a lawyer opening a
  /// case going first.
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
    final done = await UyapPace.background(() => _enrichStale(db, keepGoing));
    if (done) {
      db.setMeta(enrichedKey, DateTime.now().toIso8601String());
      uyapChanged?.call();
    }
  }().catchError((Object _) {}).whenComplete(() => _enrichment = null);

  Future<void>? _enrichment;

  /// Cases freshened of themselves a day at most.
  static const enrichPerDay = 500;

  Future<bool> _enrichStale(PortalDatabase db, bool Function() going) async {
    final now = DateTime.now();
    final dayKey = 'web_enriched_count:${now.year}-${now.month}-${now.day}';
    var count = int.tryParse(db.meta(dayKey) ?? '') ?? 0;
    final archived = db.revokedShares();
    final soon = {
      for (final h in db.hearings(
        from: now,
        to: now.add(const Duration(days: 31)),
      ))
        h.caseKey,
    };
    // A case's web sections the web read before and older than a week,
    // or failed; never filled from the web, the lawyer's completion does
    // it. Counted when the case's turn comes.
    Set<CaseSection> stale(String key) {
      final at = DateTime.now();
      return {
        for (final s in db.sections(key))
          if (s.channel == PortalChannel.uyapWeb &&
              ((!s.result.done && s.tries < _jobTries) ||
                  (s.succeeded != null &&
                      at.difference(s.succeeded!) > const Duration(days: 7))))
            s.section,
      };
    }

    final todo =
        [
          for (final c in db.cases().values)
            if (!archived.contains(c.key) &&
                !isClosedStatus(c.status?.value) &&
                stale(c.key).isNotEmpty)
              c,
        ]..sort(
          (a, b) => (soon.contains(a.key) ? 0 : 1).compareTo(
            soon.contains(b.key) ? 0 : 1,
          ),
        );
    var through = true;
    final changed = <String>{};
    try {
      for (final kase in todo) {
        if (count >= enrichPerDay) break;
        if (!going()) return false;
        while (UyapCasePanelController.lawyerWaiting && going()) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
        if (!going()) return false;
        // Read meanwhile by the lawyer: not again.
        final wants = stale(kase.key);
        if (wants.isEmpty) continue;
        final panel = UyapCasePanelController(
          web: _web,
          mobile: _mobile,
          sync: this,
          pause: Duration.zero,
          background: true,
        );
        try {
          await panel.attach(linkOf(kase));
          await panel.readSections(PortalChannel.uyapWeb, wants);
          if (panel.outcomes.isNotEmpty && panel.record != null) {
            _keepRead(
              db,
              kase.key,
              panel.record!,
              web: true,
              whole: panel.whole && panel.error == null,
              outcomes: panel.outcomes,
            );
            if (panel.outcomes.any(
              (o) =>
                  o.section == CaseSection.parties &&
                  o.result == SectionResult.read,
            )) {
              changed.add(kase.key);
            }
            if (panel.outcomes.any((o) => !o.result.done)) through = false;
          } else {
            through = false;
            if (!going()) return false;
            db.saveSections(kase.key, PortalChannel.uyapWeb, [
              for (final s in wants) SectionOutcome(s, SectionResult.failed),
            ]);
          }
          portfolioVersion.value++;
        } catch (_) {
          through = false;
        } finally {
          panel.dispose();
        }
        count++;
        db.setMeta(dayKey, '$count');
        await Future<void>.delayed(_caseGap);
      }
    } finally {
      if (changed.isNotEmpty) await _partiesChanged(db, changed);
    }
    // Not done for the day while one failed: tried again in two hours.
    return through;
  }

  /// When the open cases were last enriched from the web of themselves.
  static const enrichedKey = 'web_enriched_at';

  /// The web portal's hearings, once a day of itself, and, when UYAP Mobil
  /// is not connected, the portfolio on the same terms as [syncMobile]'s;
  /// or both when [force]d (the lawyer's Senkronize et). A second call
  /// while one runs waits for that one.
  Future<void> syncWeb({
    bool force = false,
    bool newCase = false,
    bool closed = false,
    bool whole = false,
  }) => _webSync ??= _run(PortalChannel.uyapWeb, (db) async {
    if (!_web.connected) return null;
    // With UYAP Mobil connected it reads the courts' cases; the web
    // reads only what it alone has, on its own clock.
    // [whole]: the setup on the web, which reads every list.
    final webOnly = !whole && _mobile.connected;
    // The setup on the web ([whole]) is not held back by the rest: UYAP
    // Mobil's reading before is not the web's lists.
    final (portfolioDue, rested) = _portfolioDue(
      db,
      full: force,
      newCase: newCase || closed || whole,
      key: webOnly ? _webOnlyKey : _portfolioKey,
    );
    final hearingsDue = force || _hearingsDue(db, PortalChannel.uyapWeb);
    if (!hearingsDue && !portfolioDue) return null;
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
    unawaited(
      SyncLog.note(
        'Web senkronu: duruşmalar ${hearingsDue ? 'okunacak' : 'okunmayacak'}, '
        'portföy ${portfolioDue ? 'okunacak' : 'okunmayacak'}'
        '${webOnly ? ' (UYAP Mobil yanında, yalnız webe özgü olanlar)' : ''}',
      ),
    );
    if (portfolioDue) {
      // The list alone: no case's parties, documents or money (§2.3).
      cases = await syncWebPortfolio(
        _web,
        db,
        webOnly: webOnly,
        // A new case may be in a prosecutor's office not yet known.
        everyProvince: newCase || closed,
        includeClosed: closed,
        onChanged: () => portfolioVersion.value++,
        onProgress: (done, total) => _progress(
          PortalChannel.uyapWeb,
          total == 0 ? 'Portföy' : 'Portföy $done/$total',
        ),
      );
      final now = DateTime.now().toIso8601String();
      unawaited(
        SyncLog.note(
          'Web portföyü okundu: ${db.cases().length} dosya kayıtlı, '
          '${cases.complete ? 'eksiksiz' : 'bazı listeler alınamadı'}',
        ),
      );
      _listWhole[PortalChannel.uyapWeb] = cases.complete;
      if (!cases.complete) {
        db.setMeta(_tryKey(webOnly ? _webOnlyKey : _portfolioKey), now);
      } else {
        // Read whole alone, it read what only the web has as well.
        db.setMeta(_webOnlyKey, now);
        if (!webOnly) db.setMeta(_portfolioKey, now);
      }
    }
    // No case is read of itself after the list: the lawyer starts that
    // (docs/uyap-hedef-harita.md §2.3, §6).
    if (!hearings.complete || !cases.complete) {
      return 'Bazı kayıtlar alınamadı';
    }
    return rested;
  }).whenComplete(() => _webSync = null);

  /// Where it is kept that the web read a case of itself.
  static String webCheckedKey(String key) => 'case_web_checked:$key';

  /// Where [channel]'s try at reading a case is kept: UYAP Mobil's
  /// does not keep the web from reading it.
  static String _fillTryKey(String key, PortalChannel channel) =>
      'case_fill_try:${channel.name}:$key';

  /// The sections UYAP Mobil gives.
  static const _mobileSections = [
    CaseSection.particulars,
    CaseSection.parties,
    CaseSection.documents,
  ];

  /// When each case's page last read UYAP on opening.
  final _openedAt = <String, DateTime>{};

  /// What opening a case's page reads (docs/uyap-hedef-harita.md §5): that
  /// case alone, its sections never read, read in part, failed, or older
  /// than a day; on the web when it is connected, its money, account and
  /// debtors with it; else on UYAP Mobil, what it gives. Not again within
  /// three minutes. The web not finding the case, UYAP Mobil reads its own
  /// sections; the web's wait for the web.
  Future<void> readOpened(UyapCasePanelController panel, String key) async {
    final now = DateTime.now();
    if (_openedAt[key] case final last?
        when now.difference(last) < const Duration(minutes: 3)) {
      return;
    }
    // A second opening meanwhile does not read it too.
    if (!_opening.add(key)) return;
    try {
      await _readOpened(panel, key, now);
    } finally {
      _opening.remove(key);
    }
  }

  final _opening = <String>{};

  Future<void> _readOpened(
    UyapCasePanelController panel,
    String key,
    DateTime now,
  ) async {
    final db = await _database();
    final states = db.sections(key);
    bool fresh(SectionState? s, CaseSection section) =>
        s != null &&
        s.result.done &&
        (s.complete || section == CaseSection.particulars) &&
        now.difference(s.succeeded!) <= const Duration(days: 1);
    SectionState? on(CaseSection section, PortalChannel channel) => states
        .where((s) => s.section == section && s.channel == channel)
        .firstOrNull;
    Set<CaseSection> stale(PortalChannel channel) => {
      for (final section
          in channel == PortalChannel.uyapWeb
              ? CaseSection.values
              : _mobileSections)
        if (!fresh(on(section, channel), section) &&
            // The documents' list UYAP Mobil gave whole today is not asked
            // of the web again (§7).
            !(channel == PortalChannel.uyapWeb &&
                section == CaseSection.documents &&
                fresh(on(section, PortalChannel.uyapMobile), section)))
          section,
    };

    if (_web.connected) {
      final wanted = stale(PortalChannel.uyapWeb);
      if (wanted.isEmpty) return;
      _openedAt[key] = now;
      await panel.readSections(PortalChannel.uyapWeb, wanted);
      if (panel.error == null || !_mobile.connected) return;
    }
    // The prosecutors' and the Court of Cassation's are the web's (§11.6).
    final kase = db.caseOf(key);
    if (!_mobile.connected || (kase != null && !mobileReads(kase))) return;
    final wanted = stale(PortalChannel.uyapMobile);
    if (wanted.isEmpty) return;
    _openedAt[key] = now;
    await panel.readSections(PortalChannel.uyapMobile, wanted);
  }

  /// What a case's reading brought kept beside the portfolio: its parties,
  /// for the clients and whose a deadline is, and when it was read, and
  /// whether by the web.
  Future<void> caseRead(UyapCasePanelController panel) async {
    final record = panel.record;
    if (record == null || panel.error != null) return;
    final db = await _database();
    final key = caseKey(record.number, record.court);
    _keepRead(
      db,
      key,
      record,
      web: panel.usedWeb,
      whole: panel.whole,
      outcomes: panel.outcomes,
    );
    if (panel.outcomes.isEmpty ||
        panel.outcomes.any((o) => o.section == CaseSection.parties)) {
      unawaited(_partiesChanged(db, {key}));
    }
    portfolioVersion.value++;
    // For the person's other devices too.
    uyapChanged?.call();
  }

  void _keepRead(
    PortalDatabase db,
    String key,
    UyapCaseRecord record, {
    required bool web,
    bool whole = true,
    List<SectionOutcome> outcomes = const [],
  }) {
    final at = DateTime.now().toIso8601String();
    db.saveSections(
      key,
      web ? PortalChannel.uyapWeb : PortalChannel.uyapMobile,
      outcomes,
    );
    // The parties written under this channel's name only when this reading
    // read them: those kept from before are not another channel's anew.
    final partiesRead =
        outcomes.isEmpty ||
        outcomes.any(
          (o) =>
              o.section == CaseSection.parties &&
              o.result == SectionResult.read,
        );
    if (record.parties.isNotEmpty && partiesRead) {
      db.saveCaseParties(
        key,
        record.parties,
        source: web ? 'uyap_web' : 'uyap_mobil',
      );
    }
    // Its parties, money or account did not come, or only some sections
    // were asked for: not counted read whole.
    if (!whole) return;
    if (outcomes.isNotEmpty) {
      // Whole by now, this reading and those before: on the web every
      // section, the documents' list UYAP Mobil gave whole counting.
      final states = db.sections(key);
      bool done(CaseSection s, PortalChannel c, {bool whole = false}) =>
          states.any(
            (x) =>
                x.section == s &&
                x.channel == c &&
                x.result.done &&
                (whole ? x.complete : x.succeeded != null),
          );
      final channel = web ? PortalChannel.uyapWeb : PortalChannel.uyapMobile;
      final read = (web ? CaseSection.values : _mobileSections).every(
        (s) =>
            done(s, channel) ||
            (web &&
                s == CaseSection.documents &&
                done(s, PortalChannel.uyapMobile, whole: true)),
      );
      if (!read) return;
    }
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
    bool closed = false,
  }) => _mobileSync ??= _run(PortalChannel.uyapMobile, (db) async {
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
    final (due, rested) = _portfolioDue(
      db,
      full: full,
      newCase: newCase || closed,
    );
    var cases = const PortfolioResult(0, true);
    if (due) {
      final session = _mobile.session.value;
      final ids = <String, String>{};
      cases = await syncMobilePortfolio(
        _mobile,
        db,
        // A new case may be in a prosecutor's office not yet known.
        everyProvince: newCase || closed,
        includeClosed: closed,
        onChanged: () => portfolioVersion.value++,
        onCaseId: (key, id) => ids[key] = id,
        onProgress: (done, total) => _progress(
          PortalChannel.uyapMobile,
          total == 0 ? 'Portföy' : 'Portföy $done/$total',
        ),
      );
      _sessionIds = ids;
      _idsSession = session;
      _listWhole[PortalChannel.uyapMobile] = cases.complete;
      // Read whole, it is not read again until next week; read in
      // part, it is tried again in two hours, the courts that failed
      // with it.
      db.setMeta(
        cases.complete ? _portfolioKey : 'portfolio_try_at',
        DateTime.now().toIso8601String(),
      );
    }
    // No case is read of itself after the list (§2.3, §6).
    if (!hearings.complete || !cases.complete) {
      return 'Bazı kayıtlar alınamadı';
    }
    return rested;
  }).whenComplete(() => _mobileSync = null);

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

  /// The hearings alone, now, from each portal connected: the agenda's
  /// "Duruşmaları yenile" (§5 D). No portfolio, no case is read.
  Future<void> refreshHearings() => Future.wait([
    for (final (channel, connected, rows) in [
      (PortalChannel.uyapWeb, _web.connected, _web.hearingRows),
      (PortalChannel.uyapMobile, _mobile.connected, _mobile.hearingRows),
    ])
      if (connected)
        _run(channel, (db) async {
          _progress(channel, 'Duruşmalar');
          final read = await syncHearings(channel, db, rows);
          if (!read.complete) return 'Bazı duruşmalar alınamadı';
          _hearingsRead(db, channel);
          return null;
        }),
  ]);

  Future<void>? _mobileSync;

  /// Counted up whenever a sync writes a case anew or changes one, as it
  /// runs: what lists the portfolio shows it then, and only then.
  final portfolioVersion = ValueNotifier<int>(0);

  static const _portfolioKey = 'portfolio_at';
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

  /// Whether the reading running now lists the closed cases too: only the
  /// one the lawyer asks for in Dava Dosyalarım ([scanClosed]); no setting
  /// keeps it on (docs/uyap-hedef-harita.md §8, §10.4). The setting kept
  /// by an earlier Folio is let go of.
  bool closedScan = false;

  /// When the closed cases were last listed, at the lawyer's asking.
  static const closedScanKey = 'closed_scan_at';

  /// Whether each channel's last portfolio reading listed every unit.
  final _listWhole = <PortalChannel, bool>{};

  /// The closed cases listed once, from each portal connected: their list
  /// alone, no case read. Not held back by [portfolioRest]: the lawyer
  /// asked for it.
  Future<void> scanClosed() async {
    if (closedScan) return;
    closedScan = true;
    notifyListeners();
    try {
      await _whenIdle();
      final channels = [
        if (_mobile.connected) PortalChannel.uyapMobile,
        if (_web.connected) PortalChannel.uyapWeb,
      ];
      // This scan's own results, not an earlier reading's.
      for (final c in channels) {
        _listWhole.remove(c);
      }
      await Future.wait([
        for (final c in channels)
          c == PortalChannel.uyapMobile
              ? syncMobile(full: true, closed: true)
              : syncWeb(force: true, closed: true),
      ]);
      // Said scanned only when every channel read its lists whole.
      if (channels.isNotEmpty &&
          channels.every((c) => _listWhole[c] ?? false)) {
        (await _database()).setMeta(
          closedScanKey,
          DateTime.now().toIso8601String(),
        );
      }
    } finally {
      closedScan = false;
      notifyListeners();
    }
  }

  /// When the closed cases were last listed.
  Future<DateTime?> closedScannedAt() async =>
      DateTime.tryParse((await _database()).meta(closedScanKey) ?? '');

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
    // An archive (a case shared and then no longer) is not asked about.
    final archived = db.revokedShares();
    final all = [
      for (final c in db.cases().values)
        if (!archived.contains(c.key) &&
            (c.family == CaseFamily.court ||
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
        unawaited(
          SyncLog.note('Dosya okuma ${i + 1}/${open.length}. dosyada durdu'),
        );
        through = false;
        break;
      }
      _progress(channel, 'Dosyalar ${i + 1}/${open.length}');
      if (i % 10 == 0) {
        final cool = UyapPace.instance.cooling;
        unawaited(
          SyncLog.note(
            'Dosya ${i + 1}/${open.length}'
            '${cool > Duration.zero ? ', UYAP yavaşlattı: ${cool.inSeconds} sn bekleme' : ''}',
          ),
        );
      }
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
        // On [channel] alone, every section it gives (§2.4).
        await panel.readSections(
          channel,
          channel == PortalChannel.uyapWeb
              ? CaseSection.values.toSet()
              : _mobileSections.toSet(),
        );
        // Not answered: its turn comes again soon, not in a week, and the
        // day is not done.
        if (panel.error != null || panel.record == null) {
          unawaited(
            SyncLog.note(
              'Dosya ${i + 1}/${open.length} okunamadı: '
              '${panel.error ?? 'kayıt yok'}',
            ),
          );
          through = false;
          continue;
        }
        final after = panel.record!;
        // Asked, changed or not: it waits its turn again.
        _keepRead(
          db,
          kase.key,
          after,
          web: panel.usedWeb,
          whole: panel.whole,
          outcomes: panel.outcomes,
        );
        if (!panel.whole) {
          through = false;
          unawaited(
            SyncLog.note(
              'Dosya ${i + 1}/${open.length} yarım okundu '
              '(${panel.usedWeb ? 'web' : 'mobil'}; taraf, para ya da hesap '
              'gelmedi)',
            ),
          );
        }
        portfolioVersion.value++;
        if (identical(after, before)) continue;
        db.noteChange(
          kase.key,
          fresh: after.fresh.length,
          change: before == null ? null : describeChange(before, after),
        );
      } catch (e) {
        // One case that does not answer does not stop the others.
        through = false;
        unawaited(SyncLog.note('Dosya ${i + 1}/${open.length} hata: $e'));
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

  /// The mobile id the portfolio's reading gave for [key] forgotten: it
  /// did not answer, and is looked up again.
  void forgetMobileId(String key) {
    if (_sessionIds.containsKey(key)) {
      _sessionIds = {..._sessionIds}..remove(key);
    }
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

/// The kinds of jurisdiction the mobile API lists court cases for
/// (measured live, 14 Ekim 2026; docs/uyap-hedef-harita.md §1): hukuk
/// (with the regional courts' civil chambers), ceza (with their criminal
/// ones), icra, idari, the Tazminat Komisyonu (26), satış memurluğu (11)
/// and arabuluculuk (25). 12 and 13 are not asked: they give again cases
/// 0 and 1 give. The Court of Cassation's are the web's alone; the
/// prosecutors' come by their own lists ([_mobileProsecutors]).
const mobileJurisdictions = [1, 0, 2, 6, 26, 11, 25];

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
  Future<void> Function(List<UyapCase> open)? onPage,
}) async {
  final baseline = db.meta('portfolio_at') == null;
  final asked = DateTime.now().toUtc();
  const channel = PortalChannel.uyapWeb;
  var complete = true;
  final found = <String, PortalCase>{};
  final changed = <String>{};
  final pageOpen = <UyapCase>[];

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
    if (c.id.isNotEmpty && !closed && !isClosedStatus(state)) pageOpen.add(c);
  }

  void keep() {
    if (found.isEmpty) return;
    // (pageOpen is handed on by [pages], after the page is kept.)
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
    // By court and number: UYAP gives a case a new id in every answer.
    final ids = <String>{};
    for (var page = 1; page <= _webPages; page++) {
      final got = await ask(page);
      var fresh = 0;
      for (final c in got.cases) {
        if (ids.add('${c.courtId}|${c.number}')) fresh++;
        each(c);
      }
      keep();
      if (onPage != null && pageOpen.isNotEmpty) {
        final open = [...pageOpen];
        pageOpen.clear();
        await onPage(open);
      }
      pageOpen.clear();
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

  // A list a kind of unit, every court of it at once, hukuk first (as
  // banaozel reads it): some sixty lists, not one a court. How far the
  // reading has come counts what is known so far.
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
    final lists = [
      for (final unit in units)
        for (final closed in [false, if (includeClosed) true]) (unit, closed),
    ];
    steps += lists.length;
    for (final (unit, closed) in lists) {
      onProgress?.call(step++, steps);
      try {
        final whole = await pages(
          (page) => web.casePage(
            jurisdiction: jurisdiction,
            courtType: unit.id,
            court: const UyapOption('', ''),
            closed: closed,
            pageNumber: page,
          ),
          (c) => add(
            c,
            CaseFamily.court,
            jurisdiction: jurisdiction,
            unit: unit.id,
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
        if (onPage != null && pageOpen.isNotEmpty) {
          final open = [...pageOpen];
          pageOpen.clear();
          await onPage(open);
        }
        pageOpen.clear();
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
    // The closed investigations only where the lawyer asked for the
    // closed cases.
    for (final closed in [false, if (includeClosed) true]) {
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
  bool everyProvince = false,
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
    // A prosecutor's case's id is not given out: its sections are the
    // web's until UYAP Mobil's ways are measured (§11.6).
    if (id != null && family != CaseFamily.prosecutor) {
      onCaseId?.call(one.key, id);
    }
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
      List<Map<String, Object?>> rows;
      try {
        rows = await api.cases(type, kind, id, closed: closed);
      } on UyapListIncomplete catch (e) {
        // What came is kept; the list is said to be incomplete.
        rows = e.rows;
        complete = false;
      }
      for (final row in rows) {
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
  if (!await _mobileProsecutors(
    api,
    db,
    includeClosed: includeClosed,
    everyProvince: everyProvince,
    add: (row) => add(row, CaseFamily.prosecutor),
  )) {
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

/// The prosecutors' offices where UYAP Mobil found the lawyer a case, kept
/// so that a reading asks them alone and not every province's; and when
/// every province was last asked.
const _mobileOfficesKey = 'mobile_prosecutor_offices';
const _mobileOfficesFullKey = 'mobile_prosecutor_full_at';

/// The lawyer's investigations as UYAP Mobil lists them (measured live,
/// 14 Ekim 2026; docs/uyap-hedef-harita.md §1): every province's offices
/// the first time, when [everyProvince] or a month on; between, only the
/// offices where a case was found. Their particulars stay the web's to
/// read (§11.6): no unit code is kept with them, the web finds the office
/// by its own list. False when a list did not come.
Future<bool> _mobileProsecutors(
  UyapMobileApi api,
  PortalDatabase db, {
  required bool includeClosed,
  required bool everyProvince,
  required void Function(Map<String, Object?> row) add,
}) async {
  var complete = true;
  Map<String, String> kept;
  try {
    kept = (jsonDecode(db.meta(_mobileOfficesKey) ?? '{}') as Map).map(
      (k, v) => MapEntry('$k', '$v'),
    );
  } catch (_) {
    kept = {};
  }
  final last = DateTime.tryParse(db.meta(_mobileOfficesFullKey) ?? '');
  final full =
      everyProvince ||
      last == null ||
      DateTime.now().difference(last) > const Duration(days: 30);
  final offices = <String, String>{if (!full) ...kept};
  if (full) {
    try {
      for (final p in await api.provinces()) {
        final code = '${p['il'] ?? ''}'.trim();
        if (code.isEmpty) continue;
        try {
          for (final o in await api.prosecutorOffices(code)) {
            final id = '${o['birimId'] ?? ''}'.trim();
            if (id.isNotEmpty) offices[id] = '${o['birimAdi'] ?? ''}'.trim();
          }
        } catch (_) {
          complete = false;
        }
      }
    } catch (_) {
      return false;
    }
  }
  final withCases = <String, String>{};
  for (final MapEntry(key: id, value: name) in offices.entries) {
    for (final closed in [false, if (includeClosed) true]) {
      try {
        List<Map<String, Object?>> rows;
        try {
          rows = await api.prosecutorCases(id, closed: closed);
        } on UyapListIncomplete catch (e) {
          rows = e.rows;
          complete = false;
        }
        for (final row in rows) {
          add(row);
        }
        if (rows.isNotEmpty) withCases[id] = name;
      } catch (_) {
        complete = false;
      }
    }
  }
  // An office once found stays known: a reading that failed does not
  // forget it.
  db.setMeta(
    _mobileOfficesKey,
    jsonEncode({if (!full || !complete) ...kept, ...withCases}),
  );
  if (full && complete) {
    db.setMeta(_mobileOfficesFullKey, DateTime.now().toIso8601String());
  }
  return complete;
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

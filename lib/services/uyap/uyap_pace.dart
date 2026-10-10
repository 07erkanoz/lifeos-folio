import 'dart:async';
import 'dart:io';
import 'dart:math';

/// The pace Folio keeps with UYAP, its web portal and its mobile service
/// alike: one request at a time, a breath between them, and longer ones
/// after UYAP has failed to answer. UYAP has said that programs asking it
/// too much tire it; Folio asks as a lawyer at a screen would.
///
/// What runs in [background] (the syncs) waits one to two seconds after
/// the last request, and while UYAP is failing, longer each time (from
/// thirty seconds to a quarter of an hour). What a lawyer asked for waits
/// only a moment and never for the failing: they are looking at the screen.
/// There is no daily limit: one would stop a lawyer's work.
class UyapPace {
  UyapPace({
    this.gap = const Duration(milliseconds: 1000),
    this.spread = const Duration(milliseconds: 1000),
    this.quickGap = const Duration(milliseconds: 250),
    this.firstCool = const Duration(seconds: 30),
    this.maxCool = const Duration(minutes: 15),
    Random? random,
    DateTime Function()? now,
  }) : _random = random ?? Random(),
       _now = now ?? DateTime.now,
       _queued = true;

  /// No waiting and no turns, for the tests, whose UYAP is a stand-in:
  /// a request a widget test leaves unanswered in its fake time would
  /// otherwise hold every later test's.
  UyapPace.none()
    : gap = Duration.zero,
      spread = Duration.zero,
      quickGap = Duration.zero,
      firstCool = Duration.zero,
      maxCool = Duration.zero,
      _random = Random(),
      _now = DateTime.now,
      _queued = false;

  static UyapPace instance = Platform.environment.containsKey('FLUTTER_TEST')
      ? UyapPace.none()
      : UyapPace();

  /// Whether [error] is UYAP not answering as it should: no connection, no
  /// answer in time, a server error or too many requests ([status]).
  static bool fault(Object error, {int? status}) =>
      error is SocketException ||
      error is TimeoutException ||
      error is HttpException ||
      error is HandshakeException ||
      (status != null && (status == 429 || status >= 500));

  final Duration gap, spread, quickGap, firstCool, maxCool;
  final Random _random;
  final DateTime Function() _now;
  final bool _queued;

  static final _backgroundKey = Object();

  /// Runs [work] as a sync: its requests keep the slow pace.
  static Future<T> background<T>(Future<T> Function() work) =>
      runZoned(work, zoneValues: {_backgroundKey: true});

  /// Whether the request being made now is a sync's.
  static bool get inBackground => Zone.current[_backgroundKey] == true;

  Future<void> _queue = Future.value();
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _cool = Duration.zero;
  DateTime _coolUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// How long the syncs wait now, UYAP having failed; zero when it answers.
  Duration get cooling => _cool;

  /// Makes [request] in its turn. A failure that is UYAP's (no answer, a
  /// server error, too many requests: [isUyapFault]) slows the syncs; an
  /// answer of any kind, a refusal included, sets them back to their pace.
  Future<T> run<T>(
    Future<T> Function() request, {
    bool Function(Object error)? isUyapFault,
  }) async {
    if (!_queued) return request();
    final slow = inBackground;
    // A sync waits out UYAP's failing before it takes its place in line:
    // a lawyer's request behind it is not held for a quarter of an hour.
    if (slow) {
      final left = _coolUntil.difference(_now());
      if (_cool > Duration.zero && left > Duration.zero) {
        await Future<void>.delayed(left);
      }
    }
    final previous = _queue;
    final done = Completer<void>();
    _queue = done.future;
    try {
      await previous;
      final wait = _waitFor(slow);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      try {
        final result = await request();
        _cool = Duration.zero;
        return result;
      } catch (e) {
        if (isUyapFault?.call(e) ?? false) {
          _cool = _cool == Duration.zero
              ? firstCool
              : Duration(
                  milliseconds: min(
                    _cool.inMilliseconds * 2,
                    maxCool.inMilliseconds,
                  ),
                );
          _coolUntil = _now().add(_cool);
        } else {
          _cool = Duration.zero;
        }
        rethrow;
      } finally {
        _last = _now();
      }
    } finally {
      done.complete();
    }
  }

  Duration _waitFor(bool slow) {
    final now = _now();
    final breath = slow
        ? gap +
              Duration(
                milliseconds: spread.inMilliseconds <= 0
                    ? 0
                    : _random.nextInt(spread.inMilliseconds + 1),
              )
        : quickGap;
    var until = _last.add(breath);
    if (slow && _cool > Duration.zero && _coolUntil.isAfter(until)) {
      until = _coolUntil;
    }
    final wait = until.difference(now);
    return wait.isNegative ? Duration.zero : wait;
  }
}

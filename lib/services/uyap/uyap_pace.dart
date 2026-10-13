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
/// A sync's request not made because UYAP is failing and the sync was
/// holding a line others wait in (see [UyapPace.holding]). Not UYAP's own
/// fault: it slows nothing further.
class UyapCooling implements Exception {
  const UyapCooling();

  @override
  String toString() => 'UYAP şu an yanıt vermiyor; daha sonra yeniden denenecek.';
}

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

  static final _holdingKey = Object();

  /// Runs [work] holding a line of the caller's own (a service's serial
  /// queue). A sync's request in it that finds UYAP failing is not slept on
  /// there, with the lawyer's requests queued behind it: it fails with
  /// [UyapCooling] instead, and the sync's next request waits outside.
  static Future<T> holding<T>(Future<T> Function() work) =>
      runZoned(work, zoneValues: {_holdingKey: true});

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
    final holding = Zone.current[_holdingKey] == true;
    while (true) {
      // A sync waits out UYAP's failing before it takes its place in line:
      // a lawyer's request behind it is not held for a quarter of an hour.
      // Holding a line of its own, it does not wait there at all.
      if (slow && holding && _coolingNow) throw const UyapCooling();
      await cooled();
      final previous = _queue;
      final done = Completer<void>();
      _queue = done.future;
      try {
        await previous;
        // UYAP began failing while this sync stood in line: it steps out
        // again rather than sleep at the front with the lawyer behind it.
        // Held in a line of its own as well (a service's, see [holding]),
        // it gives that up too: waiting here, it would hold it.
        if (slow && _coolingNow) {
          if (holding) throw const UyapCooling();
          continue;
        }
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
  }

  bool get _coolingNow =>
      _cool > Duration.zero && _coolUntil.isAfter(_now());

  /// For a sync, the wait until UYAP's failing is over; none for what a
  /// lawyer asked. Awaited before taking a turn in any line (this one, or a
  /// service's own), so a sync never sleeps holding a place others wait on.
  Future<void> cooled() async {
    if (!_queued || !inBackground) return;
    while (_coolingNow) {
      await Future<void>.delayed(_coolUntil.difference(_now()));
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
    final wait = _last.add(breath).difference(now);
    return wait.isNegative ? Duration.zero : wait;
  }
}

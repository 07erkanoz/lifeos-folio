import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:evrak_convert/services/uyap/uyap_pace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  UyapPace pace() => UyapPace(
    gap: const Duration(milliseconds: 120),
    spread: Duration.zero,
    quickGap: const Duration(milliseconds: 10),
    firstCool: const Duration(milliseconds: 300),
    maxCool: const Duration(milliseconds: 500),
    random: Random(1),
  );

  Future<Duration> timed(Future<void> Function() f) async {
    final watch = Stopwatch()..start();
    await f();
    return watch.elapsed;
  }

  test('one request at a time, in the order asked', () async {
    final p = pace();
    final order = <int>[];
    var running = 0;
    Future<void> one(int i) => p.run(() async {
      running++;
      expect(running, 1);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      order.add(i);
      running--;
    });
    await Future.wait([for (var i = 0; i < 5; i++) one(i)]);
    expect(order, [0, 1, 2, 3, 4]);
  });

  test('a sync waits between requests; the lawyer only a moment', () async {
    final p = pace();
    await p.run(() async {});
    final quick = await timed(() => p.run(() async {}));
    expect(quick, lessThan(const Duration(milliseconds: 100)));
    final slow = await timed(
      () => UyapPace.background(() => p.run(() async {})),
    );
    expect(slow, greaterThanOrEqualTo(const Duration(milliseconds: 110)));
  });

  test('UYAP failing slows the syncs, longer each time; an answer ends it; '
      'the lawyer is not held back', () async {
    final p = pace();
    Future<void> fail() => p
        .run<void>(
          () => throw const SocketException('yok'),
          isUyapFault: UyapPace.fault,
        )
        .catchError((_) {});
    await fail();
    expect(p.cooling, const Duration(milliseconds: 300));
    await UyapPace.background(fail);
    expect(p.cooling, const Duration(milliseconds: 500), reason: 'capped');
    final sync = await timed(
      () => UyapPace.background(() => p.run(() async {})),
    );
    expect(sync, greaterThanOrEqualTo(const Duration(milliseconds: 400)));
    expect(p.cooling, Duration.zero);
    await fail();
    final lawyer = await timed(() => p.run(() async {}));
    expect(lawyer, lessThan(const Duration(milliseconds: 200)));
    // Answered: the syncs go on at their pace.
    expect(p.cooling, Duration.zero);
    // A refusal is an answer: it slows nothing.
    await p
        .run<void>(
          () => throw StateError('oturum'),
          isUyapFault: UyapPace.fault,
        )
        .catchError((_) {});
    expect(p.cooling, Duration.zero);
  });

  test('a sync already in line when UYAP starts failing steps out, rather '
      'than hold the lawyer behind it', () async {
    final p = pace();
    final failing = p
        .run<void>(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          throw const SocketException('yok');
        }, isUyapFault: UyapPace.fault)
        .catchError((_) {});
    // Queued behind the failing request, before the cool-off began.
    final sync = UyapPace.background(() => p.run(() async {}));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final lawyer = timed(() => p.run(() async {}));
    await failing;
    expect(await lawyer, lessThan(const Duration(milliseconds: 200)));
    await sync;
  });

  test('a sync holding a service’s line gives it up when UYAP is failing, '
      'rather than sleep in it', () async {
    final p = pace();
    // A service's own serial line, as UyapWebService keeps.
    var line = Future<void>.value();
    Future<T> serial<T>(Future<T> Function() op) async {
      await p.cooled();
      final previous = line;
      final done = Completer<void>();
      line = done.future;
      await previous;
      try {
        return await UyapPace.holding(op);
      } finally {
        done.complete();
      }
    }

    final failing = serial(
      () => p.run<void>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        throw const SocketException('yok');
      }, isUyapFault: UyapPace.fault),
    ).catchError((_) {});
    // A sync's request queued in the service's line behind the failing one.
    final sync = UyapPace.background(
      () => serial(() => p.run(() async => 'cevap')),
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final lawyer = timed(() => serial(() => p.run(() async {})));
    await failing;
    await expectLater(sync, throwsA(isA<UyapCooling>()));
    expect(await lawyer, lessThan(const Duration(milliseconds: 200)));
  });

  test('cooled() holds only a sync, and only while UYAP is failing', () async {
    final p = pace();
    expect(await timed(p.cooled), lessThan(const Duration(milliseconds: 50)));
    await p
        .run<void>(
          () => throw const SocketException('yok'),
          isUyapFault: UyapPace.fault,
        )
        .catchError((_) {});
    expect(await timed(p.cooled), lessThan(const Duration(milliseconds: 50)));
    final sync = await timed(() => UyapPace.background(p.cooled));
    expect(sync, greaterThanOrEqualTo(const Duration(milliseconds: 250)));
  });

  test('UYAP’s faults: no answer, a server error, too many requests', () {
    expect(UyapPace.fault(const SocketException('x')), isTrue);
    expect(UyapPace.fault(TimeoutException('x')), isTrue);
    expect(UyapPace.fault(Exception(), status: 503), isTrue);
    expect(UyapPace.fault(Exception(), status: 429), isTrue);
    expect(UyapPace.fault(Exception(), status: 404), isFalse);
    expect(UyapPace.fault(StateError('x')), isFalse);
  });

  test('documents come one at a time, each the gap after the one before '
      'ended, whoever asks; one that fails does not stop the line', () async {
    final pace = UyapPace(documentGap: const Duration(milliseconds: 300));
    final watch = Stopwatch()..start();
    final spans = <(int, int)>[];
    Future<int> fetch(int i, {bool fail = false}) => pace.document(() async {
      final start = watch.elapsedMilliseconds;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      spans.add((start, watch.elapsedMilliseconds));
      if (fail) throw StateError('UYAP');
      return i;
    });
    // Three asked at once, as a bulk download, a shared case and a task
    // would.
    final results = await Future.wait([
      fetch(1),
      fetch(2, fail: true).catchError((Object _) => -1),
      fetch(3),
    ]);
    expect(results, [1, -1, 3]);
    for (var i = 1; i < spans.length; i++) {
      expect(
        spans[i].$1 - spans[i - 1].$2,
        greaterThanOrEqualTo(290),
        reason: 'document ${i + 1} began too soon',
      );
    }
    // The real gap: three seconds.
    expect(UyapPace().documentGap, const Duration(seconds: 3));
  });
}

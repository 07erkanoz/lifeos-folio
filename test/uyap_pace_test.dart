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

  test('UYAP’s faults: no answer, a server error, too many requests', () {
    expect(UyapPace.fault(const SocketException('x')), isTrue);
    expect(UyapPace.fault(TimeoutException('x')), isTrue);
    expect(UyapPace.fault(Exception(), status: 503), isTrue);
    expect(UyapPace.fault(Exception(), status: 429), isTrue);
    expect(UyapPace.fault(Exception(), status: 404), isFalse);
    expect(UyapPace.fault(StateError('x')), isFalse);
  });
}

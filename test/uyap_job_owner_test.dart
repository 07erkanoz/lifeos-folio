import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/uyap_job.dart';
import 'package:evrak_convert/services/portal/uyap_job_owner.dart';
import 'package:evrak_convert/services/sync/hlc.dart';

/// The job's ownership between the person's own devices
/// (docs/uyap-is-sahipligi.md): who runs it, and which of two records
/// stands when they meet.
void main() {
  final t0 = DateTime.utc(2026, 10, 16, 9);
  Hlc at(DateTime when, String device) =>
      Hlc(when.millisecondsSinceEpoch, 0, device);

  UyapJob job({DateTime? started, UyapJobStop? stopped}) => UyapJob(
    kind: UyapJobKind.setup,
    channel: PortalChannel.uyapMobile,
    stage: UyapJobStage.documents,
    started: started ?? t0,
    stopped: stopped,
  );

  UyapJobClaim started(
    String device, {
    DateTime? when,
    UyapJobClaim? known,
    UyapJobStop? stopped,
  }) => UyapJobClaim.start(
    job(started: when ?? t0, stopped: stopped),
    owner: device,
    ownerName: device == 'ofis' ? 'Ofis bilgisayarı' : 'Ev bilgisayarı',
    version: at(when ?? t0, device),
    known: known,
  );

  group('who runs it', () {
    test('only its owner, while it is neither done nor let go of', () {
      final c = started('ofis');
      expect(c.runsOn('ofis'), isTrue);
      expect(c.runsOn('ev'), isFalse);
      final done = c.said(
        version: at(t0.add(const Duration(minutes: 1)), 'ofis'),
        job: c.job!.copyWith(stage: UyapJobStage.done),
      );
      expect(done.runsOn('ofis'), isFalse);
      final dropped = c.said(
        version: at(t0.add(const Duration(minutes: 1)), 'ofis'),
        drop: true,
      );
      expect(dropped.dropped, isTrue);
      expect(dropped.runsOn('ofis'), isFalse);
    });

    test('running while its owner was heard of within three minutes, by its '
        'word or by when it came here; stopped is not running', () {
      final c = started('ofis');
      expect(c.running(t0.add(const Duration(minutes: 2))), isTrue);
      expect(c.running(t0.add(const Duration(minutes: 3))), isFalse);
      // Heard of here later than it said: its clock may be behind.
      expect(
        c.running(
          t0.add(const Duration(minutes: 10)),
          heard: t0.add(const Duration(minutes: 9)),
        ),
        isTrue,
      );
      final beat = c.said(
        version: at(t0.add(const Duration(minutes: 5)), 'ofis'),
        beating: true,
      );
      expect(beat.running(t0.add(const Duration(minutes: 7))), isTrue);
      final paused = started('ofis', stopped: UyapJobStop.session);
      expect(paused.running(t0.add(const Duration(seconds: 10))), isFalse);
    });

    test('taken over: the other device runs it, a generation on, the job '
        'going on from where it was', () {
      final c = started('ofis', stopped: UyapJobStop.incomplete).said(
        version: at(t0.add(const Duration(minutes: 1)), 'ofis'),
        progress: const UyapJobProgress(UyapJobStage.documents, 212, 333),
      );
      final taken = c.takenOver(
        device: 'ev',
        name: 'Ev bilgisayarı',
        version: at(t0.add(const Duration(hours: 3)), 'ev'),
      );
      expect(taken.runsOn('ev'), isTrue);
      expect(taken.runsOn('ofis'), isFalse);
      expect(taken.generation, c.generation + 1);
      expect(taken.id, c.id);
      expect(taken.job!.stage, UyapJobStage.documents);
      expect(taken.job!.stopped, isNull);
      expect(taken.progress!.done, 212);
      expect(UyapJobClaim.pick(c, taken), same(taken));
      expect(UyapJobClaim.pick(taken, c), same(taken));
    });
  });

  group('two records met', () {
    test('a job started knowing another comes after it', () {
      final first = started('ofis');
      final next = started(
        'ev',
        when: t0.subtract(const Duration(hours: 1)),
        known: first,
      );
      expect(next.generation, 2);
      expect(UyapJobClaim.pick(first, next), same(next));
      expect(UyapJobClaim.pick(next, first), same(next));
    });

    test('two started apart, each knowing nothing of the other: the one '
        'started later stands, whichever device holds which', () {
      final office = started('ofis');
      final home = started('ev', when: t0.add(const Duration(hours: 2)));
      expect(UyapJobClaim.pick(office, home), same(home));
      expect(UyapJobClaim.pick(home, office), same(home));
    });

    test('the same job taken over on two devices apart: the same one '
        'stands on both, whatever either says after', () {
      final c = started('ofis');
      final home = c.takenOver(
        device: 'ev',
        name: 'Ev',
        version: at(t0.add(const Duration(hours: 1)), 'ev'),
      );
      final laptop = c.takenOver(
        device: 'laptop',
        name: 'Dizüstü',
        version: at(t0.add(const Duration(hours: 2)), 'laptop'),
      );
      final winner = UyapJobClaim.pick(home, laptop);
      expect(UyapJobClaim.pick(laptop, home), same(winner));
      // The loser's later beat does not take it back.
      final loser = identical(winner, home) ? laptop : home;
      final later = loser.said(
        version: at(t0.add(const Duration(hours: 5)), loser.owner),
        beating: true,
      );
      expect(UyapJobClaim.pick(winner, later).owner, winner.owner);
      expect(UyapJobClaim.pick(later, winner).owner, winner.owner);
    });

    test('of the same owner the later word stands; a job let go of is not '
        'brought back by an older word', () {
      final c = started('ofis');
      final beat = c.said(
        version: at(t0.add(const Duration(minutes: 1)), 'ofis'),
        beating: true,
      );
      final dropped = beat.said(
        version: at(t0.add(const Duration(minutes: 2)), 'ofis'),
        drop: true,
      );
      expect(UyapJobClaim.pick(c, beat), same(beat));
      expect(UyapJobClaim.pick(beat, dropped), same(dropped));
      expect(UyapJobClaim.pick(dropped, beat), same(dropped));
      expect(UyapJobClaim.pick(dropped, c), same(dropped));
    });
  });

  group('kept and sent', () {
    test('read back as written, its stop and progress with it', () {
      final c = started('ofis', stopped: UyapJobStop.session).said(
        version: at(t0.add(const Duration(minutes: 4)), 'ofis'),
        beating: true,
        progress: const UyapJobProgress(UyapJobStage.documents, 5, 9),
      );
      final back = UyapJobClaim.decode(c.encode())!;
      expect(back.id, c.id);
      expect(back.owner, 'ofis');
      expect(back.ownerName, 'Ofis bilgisayarı');
      expect(back.generation, 1);
      expect(back.version, c.version);
      expect(back.beat, c.beat);
      expect(back.job!.stopped, UyapJobStop.session);
      expect(back.job!.stage, UyapJobStage.documents);
      expect(back.progress!.done, 5);
      expect(back.progress!.total, 9);
      final dropped = UyapJobClaim.decode(
        c
            .said(
              version: at(t0.add(const Duration(minutes: 5)), 'ofis'),
              drop: true,
            )
            .encode(),
      )!;
      expect(dropped.dropped, isTrue);
    });

    test('what is not one is not read: no version, or a job this Folio '
        'cannot read taken for one let go of', () {
      expect(UyapJobClaim.decode(''), isNull);
      expect(UyapJobClaim.decode('{"kimlik":"x"}'), isNull);
      final j = started('ofis').toJson();
      expect(
        UyapJobClaim.fromJson({
          ...j,
          'is': {'tur': 'yeniTur'},
        }),
        isNull,
      );
    });
  });
}

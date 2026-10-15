import 'dart:convert';

import '../sync/hlc.dart';
import 'uyap_job.dart';

/// The lawyer's long UYAP job as their own devices keep it alike
/// (docs/uyap-is-sahipligi.md): the job, the one device that runs it, and
/// how lately it said so. Every other own device only shows it; it runs it
/// when the lawyer takes it over there. The person's, never an office
/// member's: it goes between their own devices alone.
class UyapJobClaim {
  const UyapJobClaim({
    required this.id,
    required this.started,
    required this.owner,
    required this.ownerName,
    required this.generation,
    required this.version,
    this.job,
    this.beat,
    this.progress,
  });

  /// A job started here now, by [owner]: of a generation after every one
  /// [known] of, so that it comes after them wherever it meets them. Said
  /// running, unless [beating] is false: one kept from before the job had
  /// an owner was not said running.
  factory UyapJobClaim.start(
    UyapJob job, {
    required String owner,
    required String ownerName,
    required Hlc version,
    UyapJobClaim? known,
    bool beating = true,
  }) => UyapJobClaim(
    id: '$owner:${job.started.toUtc().microsecondsSinceEpoch}',
    started: job.started,
    owner: owner,
    ownerName: ownerName,
    generation: (known?.generation ?? 0) + 1,
    version: version,
    job: job,
    beat: beating ? version.wall : null,
  );

  /// The job's own: the device that started it and when.
  final String id;
  final DateTime started;

  /// The device that runs it ([SyncClock.localDeviceId]) and its name as
  /// shown on the others.
  final String owner, ownerName;

  /// Counted up at each start and each taking over: the higher stands.
  final int generation;

  /// The owner's latest word of it; within one job and generation the
  /// later stands.
  final Hlc version;

  /// The job; null when the lawyer let go of it.
  final UyapJob? job;

  /// When its owner last said it runs; moved on only while it runs.
  final DateTime? beat;

  /// How far it has come, as its owner last said.
  final UyapJobProgress? progress;

  /// How long an owner unheard of is still taken to be running it.
  static const fresh = Duration(minutes: 3);

  /// How often a running owner says so.
  static const beatEvery = Duration(seconds: 60);

  bool get dropped => job == null;

  bool ownedBy(String device) => owner == device;

  /// Whether [device] may run it: its owner's, while not done or let go.
  bool runsOn(String device) => ownedBy(device) && job != null && !job!.done;

  /// Whether its owner is taken to be running it now: running when it last
  /// said, and heard of within [fresh], by its word or by when it was
  /// [heard] here (this device's clock, its owner's may be off).
  bool running(DateTime now, {DateTime? heard}) {
    final j = job;
    if (j == null || j.done || j.stopped != null) return false;
    final last = [
      ?beat,
      ?heard,
    ].fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    return last != null && now.difference(last) < fresh;
  }

  /// The latest word of its owner: when it last said it runs, or of any
  /// other change of it.
  DateTime get lastWord {
    final at = version.wall;
    return beat != null && beat!.isAfter(at) ? beat! : at;
  }

  /// Taken over by [device] now: its generation after every one known, the
  /// job the same, gone on from where it was, its stop left behind.
  UyapJobClaim takenOver({
    required String device,
    required String name,
    required Hlc version,
  }) {
    final j = job;
    return UyapJobClaim(
      id: id,
      started: started,
      owner: device,
      ownerName: name,
      generation: generation + 1,
      version: version,
      job: j?.copyWith(stage: j.stage),
      beat: version.wall,
      progress: progress,
    );
  }

  /// Its owner's next word: the job as it is now, said running or not.
  UyapJobClaim said({
    required Hlc version,
    UyapJob? job,
    bool drop = false,
    bool beating = false,
    UyapJobProgress? progress,
  }) => UyapJobClaim(
    id: id,
    started: started,
    owner: owner,
    ownerName: ownerName,
    generation: generation,
    version: version,
    job: drop ? null : job ?? this.job,
    beat: beating ? version.wall : beat,
    progress: drop ? null : progress ?? this.progress,
  );

  /// Which of two stands, the same on every device whichever it holds: the
  /// higher generation; of one generation the job started later, the
  /// lawyer's latest wish, then the higher id; of the same job taken over
  /// on two devices apart, the higher device, whatever either said since
  /// (a later word of the other's does not make the one that stopped for
  /// it the owner again); of the same owner the later word.
  static UyapJobClaim pick(UyapJobClaim a, UyapJobClaim b) {
    if (a.generation != b.generation) {
      return a.generation > b.generation ? a : b;
    }
    if (a.id != b.id) {
      final at = a.started.toUtc().compareTo(b.started.toUtc());
      if (at != 0) return at > 0 ? a : b;
      return a.id.compareTo(b.id) > 0 ? a : b;
    }
    if (a.owner != b.owner) return a.owner.compareTo(b.owner) > 0 ? a : b;
    return a.version >= b.version ? a : b;
  }

  Map<String, Object?> toJson() => {
    'kimlik': id,
    'basladi': started.toUtc().toIso8601String(),
    'sahip': owner,
    'sahipAdi': ownerName,
    'nesil': generation,
    'surum': version.toString(),
    'is': ?(job == null ? null : jsonDecode(job!.encode())),
    'nabiz': ?beat?.toUtc().toIso8601String(),
    if (progress case final p?)
      'ilerleme': {'asama': p.stage.name, 'bitti': p.done, 'toplam': p.total},
  };

  String encode() => jsonEncode(toJson());

  /// Null when [j] is not one.
  static UyapJobClaim? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      final version = Hlc.tryParse(j['surum']);
      final generation = j['nesil'];
      if (version == null ||
          generation is! int ||
          j['kimlik'] is! String ||
          j['sahip'] is! String) {
        return null;
      }
      final job = j['is'] == null ? null : UyapJob.decode(jsonEncode(j['is']));
      // A job there that this Folio cannot read is not one let go of.
      if (j['is'] != null && job == null) return null;
      final p = j['ilerleme'];
      return UyapJobClaim(
        id: j['kimlik'] as String,
        started: DateTime.parse('${j['basladi']}'),
        owner: j['sahip'] as String,
        ownerName: '${j['sahipAdi'] ?? ''}',
        generation: generation,
        version: version,
        job: job,
        beat: DateTime.tryParse('${j['nabiz'] ?? ''}'),
        progress: p is Map && p['bitti'] is int && p['toplam'] is int
            ? UyapJobProgress(
                UyapJobStage.values.byName('${p['asama']}'),
                p['bitti'] as int,
                p['toplam'] as int,
              )
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  static UyapJobClaim? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }
}

extension on Hlc {
  /// The moment this version was made, by its maker's clock.
  DateTime get wall => DateTime.fromMillisecondsSinceEpoch(l, isUtc: true);
}

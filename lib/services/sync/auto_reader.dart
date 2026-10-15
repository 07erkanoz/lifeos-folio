import '../portal/portal_channel.dart';

/// One of the person's other own devices on the network now, as Senkron
/// last heard of it: what it says of reading UYAP of itself.
class AutoReadPeer {
  const AutoReadPeer({
    required this.id,
    required this.name,
    this.phone = false,
    this.reads = false,
    this.held = const {},
    this.job,
  });

  /// Its office device id, and its name as shown.
  final String id, name;

  final bool phone;

  /// It reads UYAP of itself and gives what it reads (`oto`).
  final bool reads;

  /// The sessions it holds: `mobil`, `web`, `uets`.
  final Set<String> held;

  /// The channel of the long job it runs now, if any.
  final PortalChannel? job;
}

/// The other own device that reads [channel] of itself in this one's
/// stead (docs/uyap-otomatik-okuma-tek-cihaz.md): its name; null when this
/// one does. Of the computers on the network that read UYAP of themselves
/// and hold [channel]'s session, the one running the long job on it comes
/// first, then the lowest id: the same one on every device. None is left
/// to when this one does not take what the others read
/// ([takesTheirs]).
String? autoReaderElsewhere(
  PortalChannel channel, {
  required String me,
  required PortalChannel? myJob,
  required Iterable<AutoReadPeer> peers,
  required bool takesTheirs,
}) {
  final kind = switch (channel) {
    PortalChannel.uyapMobile => 'mobil',
    PortalChannel.uyapWeb => 'web',
    PortalChannel.uets => null,
  };
  if (!takesTheirs || kind == null) return null;
  // Whether a comes before b: the job on the channel, then the lower id.
  bool before(PortalChannel? aJob, String a, PortalChannel? bJob, String b) {
    final aRuns = aJob == channel, bRuns = bJob == channel;
    if (aRuns != bRuns) return aRuns;
    return a.compareTo(b) < 0;
  }

  AutoReadPeer? first;
  for (final p in peers) {
    if (p.phone || !p.reads || !p.held.contains(kind) || p.id == me) continue;
    if (first == null || before(p.job, p.id, first.job, first.id)) first = p;
  }
  if (first == null || !before(first.job, first.id, myJob, me)) return null;
  return first.name.isEmpty ? 'öbür bilgisayarınız' : first.name;
}

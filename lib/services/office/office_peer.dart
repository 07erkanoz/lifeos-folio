import '../uyap/uyap_web_service.dart';

/// The kind of computer a Folio runs on, as the office's list shows it.
enum OfficePlatform {
  linux('Linux'),
  windows('Windows'),
  macos('macOS'),
  android('Android'),
  ios('iOS'),
  other('Folio');

  const OfficePlatform(this.label);
  final String label;

  bool get phone => this == android || this == ios;

  static OfficePlatform of(String? name) => OfficePlatform.values.firstWhere(
    (p) => p.name == name,
    orElse: () => OfficePlatform.other,
  );
}

/// A Folio on the office's network, as its announcement tells of it: no
/// file, no name of a document or of a client, only who and what it is.
class OfficePeer {
  const OfficePeer({
    required this.deviceId,
    required this.userId,
    required this.name,
    required this.device,
    required this.platform,
    this.host,
    this.port = 0,
    this.version = protocol,
    this.online = true,
    this.lastSeen,
  });

  /// The version of what Folios say to each other; the announcement's.
  static const protocol = 1;
  static const type = '_folio._tcp';

  final String deviceId, userId;

  /// "Av. Deniz Kaya": the lawyer's profile on that device.
  final String name;

  /// "erkan-dizustu": the computer's own name.
  final String device;
  final OfficePlatform platform;
  final String? host;
  final int port, version;
  final bool online;
  final DateTime? lastSeen;

  /// The announcement's TXT record.
  Map<String, String> get attributes => {
    'v': '$version',
    'id': deviceId,
    'u': userId,
    'n': name,
    'c': device,
    'p': platform.name,
  };

  /// Read back from an announcement; null when it is not a Folio's or is
  /// of a protocol this one does not speak.
  static OfficePeer? fromAnnouncement(
    Map<String, String> txt, {
    String? host,
    int port = 0,
    DateTime? now,
  }) {
    final id = txt['id'] ?? '';
    final user = txt['u'] ?? '';
    final version = int.tryParse(txt['v'] ?? '') ?? 0;
    if (id.isEmpty || user.isEmpty || version < 1) return null;
    return OfficePeer(
      deviceId: id,
      userId: user,
      name: (txt['n'] ?? '').trim(),
      device: (txt['c'] ?? '').trim(),
      platform: OfficePlatform.of(txt['p']),
      host: host,
      port: port,
      version: version,
      lastSeen: now ?? DateTime.now(),
    );
  }

  /// The same, reachable where [other] said it was: an announcement's
  /// words can come before the address they are at, and must not lose it.
  ///
  /// An IPv4 address is kept over an IPv6 one heard after it: an office's
  /// routers pass the first more surely.
  OfficePeer keepingPlaceOf(OfficePeer? other) =>
      other == null ||
          (host != null &&
              port != 0 &&
              !(_v6(host!) && other.host != null && !_v6(other.host!)))
      ? this
      : OfficePeer(
          deviceId: deviceId,
          userId: userId,
          name: name,
          device: device,
          platform: platform,
          host: host == null || (_v6(host!) && other.host != null)
              ? other.host
              : host,
          port: port != 0 ? port : other.port,
          version: version,
          online: online,
          lastSeen: lastSeen,
        );

  static bool _v6(String host) => host.contains(':');

  OfficePeer gone(DateTime at) => OfficePeer(
    deviceId: deviceId,
    userId: userId,
    name: name,
    device: device,
    platform: platform,
    host: host,
    port: port,
    version: version,
    online: false,
    lastSeen: at,
  );
}

/// A person and their devices on the list.
class OfficePerson {
  const OfficePerson({
    required this.name,
    required this.devices,
    this.self = false,
  });

  final String name;
  final List<OfficePeer> devices;

  /// This Folio's own person.
  final bool self;

  bool get online => devices.any((d) => d.online);
}

/// The devices put under their people: by the person's key, and until a
/// person's devices know each other (each has a key of its own then) by
/// the profile's name, folded, so that one lawyer's desktop and phone are
/// one person; the user's own first, then by name.
List<OfficePerson> groupPeople(
  Iterable<OfficePeer> peers, {
  required OfficePeer self,
}) {
  String key(OfficePeer p) =>
      p.name.isEmpty ? 'u:${p.userId}' : 'n:${UyapWebService.fold(p.name)}';
  final selfKey = key(self);
  final groups = <String, List<OfficePeer>>{
    selfKey: [self],
  };
  for (final p in peers) {
    if (p.deviceId == self.deviceId) continue;
    (groups[key(p)] ??= []).add(p);
  }
  int byState(OfficePeer a, OfficePeer b) {
    if (a.deviceId == self.deviceId) return -1;
    if (b.deviceId == self.deviceId) return 1;
    if (a.online != b.online) return a.online ? -1 : 1;
    return a.device.compareTo(b.device);
  }

  final people = [
    for (final e in groups.entries)
      OfficePerson(
        name: e.value.first.name,
        devices: e.value..sort(byState),
        self: e.key == selfKey,
      ),
  ];
  people.sort((a, b) {
    if (a.self != b.self) return a.self ? -1 : 1;
    if (a.online != b.online) return a.online ? -1 : 1;
    return UyapWebService.fold(a.name).compareTo(UyapWebService.fold(b.name));
  });
  return people;
}

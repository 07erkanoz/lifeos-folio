import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../editor/lawyer_profile.dart';
import '../platform/app_directories.dart';
import 'office_identity.dart';
import 'office_peer.dart';

/// The office's network (docs/buro.md): this Folio announced on the local
/// network, and the other Folios found there, under their people.
///
/// Nothing is announced until the user joins: an announcement carries the
/// lawyer's name, and a café's network is not an office's. Once joined,
/// Folio joins again at each start until the user leaves.
class OfficeNetwork extends ChangeNotifier {
  OfficeNetwork({Future<File> Function()? settings, this.platformName})
    : _settingsFile = settings ?? _defaultSettings;

  static OfficeNetwork? _instance;
  static OfficeNetwork get instance => _instance ??= OfficeNetwork();

  /// For tests: the platform the device says it is.
  final String? platformName;
  final Future<File> Function() _settingsFile;

  static Future<File> _defaultSettings() async =>
      File(p.join((await folioSupportDirectory()).path, 'buro.json'));

  OfficeIdentity? _identity;
  OfficePeer? _self;
  ServerSocket? _server;
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _events;
  final _peers = <String, OfficePeer>{};

  bool _joined = false, _starting = false;
  String? _error;

  /// Whether this Folio is announced and looking.
  bool get joined => _joined;
  bool get starting => _starting;

  /// What went wrong the last time it tried to join; null when nothing.
  String? get error => _error;

  /// This device, as the others see it; null before it has joined.
  OfficePeer? get self => _self;

  /// Whether the keys outlive this run (see [OfficeIdentity.kept]).
  bool get kept => _identity?.kept ?? true;

  /// The people on the network with their devices, this user's first.
  List<OfficePerson> get people {
    final self = _self;
    if (self == null) return const [];
    return groupPeople(_peers.values, self: self);
  }

  /// Joins again if the user had joined before; at Folio's start.
  Future<void> resume() async {
    if (await _wanted()) await join();
  }

  Future<bool> _wanted() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) return false;
      final json = jsonDecode(await file.readAsString());
      return json is Map && json['gorun'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _remember(bool joined) async {
    try {
      final file = await _settingsFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'gorun': joined}));
    } catch (_) {}
  }

  /// Announces this Folio and starts looking for the others.
  Future<void> join() async {
    if (_joined || _starting) return;
    _starting = true;
    _error = null;
    if (kDebugMode) debugPrint('Büro ağı: katılıyor');
    notifyListeners();
    try {
      _identity ??= await OfficeIdentity.load();
      // Where the others will reach this Folio; what is said there comes in
      // the next step (docs/buro.md, Aktarım), till then it hangs up.
      // Both families: the others may find this one by either address.
      _server = await ServerSocket.bind(
        InternetAddress.anyIPv6,
        0,
        v6Only: false,
      );
      _server!.listen((socket) => socket.destroy());
      _self = await _describe(_identity!, _server!.port);
      await _announce(_self!);
      await _look();
      _joined = true;
      await _remember(true);
      if (kDebugMode) {
        debugPrint('Büro ağı: katıldı, ${_self!.device}:${_self!.port}');
      }
    } catch (e) {
      _error = '$e';
      if (kDebugMode) debugPrint('Büro ağı: katılınamadı: $e');
      await _close();
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  /// Stops announcing and looking; Folio will not join at its next start.
  Future<void> leave() async {
    await _close();
    _joined = false;
    _peers.clear();
    await _remember(false);
    notifyListeners();
  }

  /// Announces again with the profile's name, after it was changed.
  Future<void> rename() async {
    final identity = _identity, server = _server;
    if (!_joined || identity == null || server == null) return;
    final next = await _describe(identity, server.port);
    if (next.name == _self?.name) return;
    await _broadcast?.stop();
    _self = next;
    await _announce(next);
    notifyListeners();
  }

  Future<OfficePeer> _describe(OfficeIdentity identity, int port) async {
    var name = '';
    try {
      name = (await LawyerProfile.load()).lawyer?.titled ?? '';
    } catch (_) {}
    final platform = OfficePlatform.of(
      platformName ?? Platform.operatingSystem,
    );
    var device = '';
    try {
      device = Platform.localHostname;
    } catch (_) {}
    if (device.isEmpty || device == 'localhost') {
      device = platform.phone ? '${platform.label} telefon' : platform.label;
    }
    return OfficePeer(
      deviceId: identity.deviceId,
      userId: identity.userId,
      name: name,
      device: device,
      platform: platform,
      port: port,
    );
  }

  Future<void> _announce(OfficePeer self) async {
    final broadcast = BonsoirBroadcast(
      printLogs: false,
      service: BonsoirService(
        // The device's id: unique on the network, and nothing of the person.
        name: 'folio-${self.deviceId}',
        type: OfficePeer.type,
        port: self.port,
        attributes: self.attributes,
      ),
    );
    await broadcast.initialize();
    await broadcast.start();
    _broadcast = broadcast;
  }

  Future<void> _look() async {
    final discovery = BonsoirDiscovery(printLogs: false, type: OfficePeer.type);
    await discovery.initialize();
    _events = discovery.eventStream?.listen((event) => _seen(discovery, event));
    await discovery.start();
    _discovery = discovery;
  }

  void _seen(BonsoirDiscovery discovery, BonsoirDiscoveryEvent event) {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent(:final service):
        // Found is only its name; what it says comes when it is resolved.
        try {
          discovery.serviceResolver.resolveService(service);
        } catch (_) {}
      case BonsoirDiscoveryServiceResolvedEvent(:final service) ||
          BonsoirDiscoveryServiceUpdatedEvent(:final service):
        final heard = OfficePeer.fromAnnouncement(
          service.attributes,
          host: service.hostAddresses.firstOrNull ?? service.hostname,
          port: service.port,
        );
        if (heard == null || heard.deviceId == _self?.deviceId) return;
        final before = _peers[heard.deviceId];
        final peer = heard.keepingPlaceOf(before);
        if (kDebugMode && peer.host != null && before?.host == null) {
          debugPrint(
            'Büro ağı: ${peer.name} · ${peer.device} '
            '(${peer.host}:${peer.port}) bulundu',
          );
        }
        _peers[peer.deviceId] = peer;
        notifyListeners();
      case BonsoirDiscoveryServiceLostEvent(:final service):
        final id =
            service.attributes['id'] ?? service.name.replaceFirst('folio-', '');
        final peer = _peers[id];
        if (peer == null) return;
        _peers[id] = peer.gone(DateTime.now());
        notifyListeners();
      default:
    }
  }

  Future<void> _close() async {
    await _events?.cancel();
    _events = null;
    try {
      await _discovery?.stop();
    } catch (_) {}
    try {
      await _broadcast?.stop();
    } catch (_) {}
    _discovery = null;
    _broadcast = null;
    await _server?.close();
    _server = null;
  }

  /// For tests: a peer as if it had been found.
  @visibleForTesting
  void seenForTesting(OfficePeer peer, {OfficePeer? self}) {
    if (self != null) _self = self;
    _joined = true;
    _peers[peer.deviceId] = peer;
    notifyListeners();
  }
}

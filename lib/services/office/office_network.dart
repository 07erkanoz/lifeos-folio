import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../editor/lawyer_profile.dart';
import '../platform/app_directories.dart';
import 'office_channel.dart';
import 'office_identity.dart';
import 'office_known.dart';
import 'office_link.dart';
import 'office_pairing.dart';
import 'office_peer.dart';
import 'office_transfer.dart';

/// The office's network (docs/buro.md): this Folio announced on the local
/// network, and the other Folios found there, under their people.
///
/// Nothing is announced until the user joins: an announcement carries the
/// lawyer's name, and a café's network is not an office's. Once joined,
/// Folio joins again at each start until the user leaves.
class OfficeNetwork extends ChangeNotifier {
  OfficeNetwork({
    Future<File> Function()? settings,
    KnownDevices? known,
    this.platformName,
  }) : _settingsFile = settings ?? _defaultSettings,
       _known = known ?? KnownDevices();

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
  final KnownDevices _known;
  Map<String, KnownDevice> _knownDevices = const {};

  /// Files a known device offers: the user is asked wherever they are.
  final incomingOffer = ValueNotifier<OfficeTransfer?>(null);

  /// This run's transfers, the newest first.
  final transfers = <OfficeTransfer>[];

  /// Offers taken before, going on from where they stopped when made again.
  final _accepted = <String>{};

  /// Where what comes is put; for tests, a folder of their own.
  Future<Directory> Function() inbox = _defaultInbox;

  static Future<Directory> _defaultInbox() async {
    final base = Platform.isAndroid || Platform.isIOS
        ? await getApplicationDocumentsDirectory()
        : await getDownloadsDirectory() ??
              await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'Folio Gelenler'));
    await dir.create(recursive: true);
    return dir;
  }

  /// Sends [paths] to a known device on the network; null when it is not
  /// both known and on the network now.
  Future<OfficeTransfer?> send(
    OfficePeer to,
    List<String> paths, {
    String note = '',
    String? id,
  }) async {
    final identity = _identity;
    final known = _knownDevices[to.deviceId];
    final seen = _peers[to.deviceId] ?? to;
    final host = seen.host;
    if (identity == null || known == null || host == null || seen.port == 0) {
      return null;
    }
    final t = await OfficeTransfer.send(
      identity: identity,
      peer: known,
      host: host,
      port: seen.port,
      paths: paths,
      note: note,
      id: id,
      onEnd: _ended,
    );
    _added(t);
    return t;
  }

  /// Sends a cut-off transfer again: what came of it is not sent twice.
  Future<OfficeTransfer?> retry(OfficeTransfer t) async {
    final to = _peers[t.peer.deviceId];
    if (!t.outgoing || to == null) return null;
    transfers.remove(t);
    return send(to, t.paths, note: t.note, id: t.id);
  }

  void _added(OfficeTransfer t) {
    transfers.insert(0, t);
    t.addListener(notifyListeners);
    notifyListeners();
  }

  void _ended(OfficeTransfer t) {
    unawaited(_log(t));
    notifyListeners();
  }

  Future<File> _logFile() async =>
      File(p.join((await _settingsFile()).parent.path, 'buro_aktarimlar.json'));

  /// The transfers' record: who sent what to whom, when, and how it ended.
  Future<void> _log(OfficeTransfer t) async {
    try {
      final file = await _logFile();
      var list = <Object?>[];
      if (await file.exists()) {
        final old = jsonDecode(await file.readAsString());
        if (old is List) list = old;
      }
      list.insert(0, t.toJson());
      if (list.length > 500) list = list.sublist(0, 500);
      await file.writeAsString(jsonEncode(list));
    } catch (_) {}
  }

  /// A device that asked to know this one: shown wherever the user is.
  final incoming = ValueNotifier<OfficePairing?>(null);
  OfficePairing? _pairing;

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

  /// The people on the network with their devices, this user's first; a
  /// known device that is not on it now is there too, as closed.
  List<OfficePerson> get people {
    final self = _self;
    if (self == null) return const [];
    return groupPeople([
      ..._peers.values,
      for (final d in _knownDevices.values)
        if (!_peers.containsKey(d.deviceId)) d.asAbsent(null),
    ], self: self);
  }

  /// The devices this one knows, the newest first.
  List<KnownDevice> get known =>
      _knownDevices.values.toList()
        ..sort((a, b) => b.knownAt.compareTo(a.knownAt));

  bool isKnown(String deviceId) => _knownDevices.containsKey(deviceId);

  /// Starts knowing [peer] by a code; null while another is being known.
  OfficePairing? pair(OfficePeer peer) {
    final identity = _identity, self = _self;
    if (identity == null || self == null) return null;
    if (_pairing != null && !_pairing!.finished) return null;
    return _pairing = OfficePairing.start(
      identity: identity,
      self: self,
      peer: peer,
      onKnown: _knownNow,
    );
  }

  /// Forgets a known device: it must be known by its code again before
  /// anything goes to it or comes from it.
  Future<void> forget(String deviceId) async {
    await _known.forget(deviceId);
    await _loadKnown();
    notifyListeners();
  }

  /// A known device's encrypted talk: an offer of files, for now.
  Future<void> _talk(
    OfficeLink link,
    Map<String, Object?> hello,
    OfficeIdentity identity,
  ) async {
    final ch = await OfficeChannel.accept(
      link: link,
      hello: hello,
      identity: identity,
      known: _known.of,
    );
    if (ch == null) return;
    late final StreamSubscription<Map<String, Object?>> first;
    first = ch.messages.listen((m) async {
      await first.cancel();
      final t = m['t'] == 'offer'
          ? OfficeTransfer.receive(
              channel: ch,
              offer: m,
              folder: await inbox(),
              onEnd: _ended,
            )
          : null;
      if (t == null) {
        await ch.close();
        return;
      }
      transfers.removeWhere((old) => old.id == t.id && old.finished);
      _added(t);
      if (_accepted.contains(t.id)) {
        await t.accept();
      } else {
        incomingOffer.value = t;
      }
    });
  }

  /// The user took an offer: if it is cut off, it goes on unasked.
  Future<void> acceptOffer(OfficeTransfer t) async {
    _accepted.add(t.id);
    await t.accept();
  }

  Future<void> _knownNow(KnownDevice device) async {
    await _known.remember(device);
    await _loadKnown();
    notifyListeners();
  }

  Future<void> _loadKnown() async {
    _knownDevices = {for (final d in await _known.all()) d.deviceId: d};
  }

  /// A talk another Folio opened: knowing by a code, for now; what is
  /// sent to a known device comes in the next step (docs/buro.md, Aktarım).
  void _opened(Socket socket) {
    final link = OfficeLink(socket);
    late final StreamSubscription<Map<String, Object?>> first;
    first = link.messages.listen((m) {
      unawaited(first.cancel());
      final identity = _identity, self = _self;
      if (m['t'] == 'hello' && identity != null) {
        unawaited(_talk(link, m, identity));
        return;
      }
      if (m['t'] != 'pair' || identity == null || self == null) {
        unawaited(link.close());
        return;
      }
      if (_pairing != null && !_pairing!.finished) {
        link.send({'t': 'busy'});
        unawaited(link.close());
        return;
      }
      final pairing = OfficePairing.answer(
        link: link,
        first: m,
        identity: identity,
        self: self,
        onKnown: _knownNow,
      );
      _pairing = pairing;
      if (!pairing.finished) incoming.value = pairing;
    });
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
      await _loadKnown();
      // Where the others will reach this Folio; what is said there comes in
      // the next step (docs/buro.md, Aktarım), till then it hangs up.
      // Both families: the others may find this one by either address.
      _server = await ServerSocket.bind(
        InternetAddress.anyIPv6,
        0,
        v6Only: false,
      );
      _server!.listen(_opened);
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
    // Nothing was announced (a test's listening): nothing to say again.
    if (_broadcast == null) return;
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

  /// For tests: listening as [join] does, without the announcement.
  @visibleForTesting
  Future<void> listenForTesting(
    OfficeIdentity identity,
    OfficePeer self,
  ) async {
    _identity = identity;
    await _loadKnown();
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_opened);
    _self = OfficePeer(
      deviceId: identity.deviceId,
      userId: identity.userId,
      name: self.name,
      device: self.device,
      platform: self.platform,
      host: '127.0.0.1',
      port: _server!.port,
    );
    _joined = true;
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

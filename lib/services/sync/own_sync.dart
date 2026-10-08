import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../office/office_network.dart';
import '../platform/app_directories.dart';
import '../portal/portal_database.dart';
import '../portal/portal_sync.dart';
import '../uets/notice_deadlines.dart';

/// Senkron (docs/buro.md): what one person's own devices keep alike when
/// they are on the same network, each part on or off on this device.
class OwnSync extends ChangeNotifier {
  OwnSync({
    OfficeNetwork? network,
    Future<PortalDatabase> Function()? database,
    Future<File> Function()? file,
    SessionHolder? sessions,
    this.phone,
  }) : _net = network ?? OfficeNetwork.instance,
       _database = database ?? PortalDatabase.shared,
       _file = file ?? _default,
       _sessionsGiven = sessions;

  static Future<File> _default() async =>
      File(p.join((await folioSupportDirectory()).path, 'senkron.json'));

  static final instance = OwnSync();

  final OfficeNetwork _net;
  final Future<PortalDatabase> Function() _database;
  final Future<File> Function() _file;

  static const agenda = 'ajanda';
  static const sessionsPart = 'oturumlar';

  final SessionHolder? _sessionsGiven;
  late final SessionHolder _sessions = _sessionsGiven ?? _PortalSessions();

  /// The sessions each own device said it holds, by device.
  final held = <String, Set<String>>{};
  Set<String> _mine = const {};

  Set<String> get heldHere => {
    for (final k in PortalSync.sessionKinds)
      if (_sessions.holds(k)) k,
  };

  /// The parts on: all of them until the user turns one off.
  final _off = <String>{};
  bool _started = false;

  bool isOn(String part) => !_off.contains(part);

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final file = await _file();
      if (await file.exists()) {
        final j = jsonDecode(await file.readAsString());
        if (j is Map) {
          _off.addAll([
            for (final s in (j['kapali'] as List? ?? const [])) '$s',
          ]);
        }
      }
    } catch (_) {}
    await _apply();
    _startSessions();
    // An own device found before these were set is made alike now.
    unawaited(_net.syncOwn());
  }

  void _startSessions() {
    _net.ownParts[sessionsPart] = OwnPart(
      export: () async => {
        'cihaz': _net.self?.deviceId,
        'telefon': _isPhone,
        'acik': heldHere.toList(),
        // UYAP Mobil's latest tokens: the other goes on with them, not
        // with a refresh token this one may have spent.
        'mobil': ?_sessions.sessionOf('mobil'),
      },
      merge: (theirs) async {
        if (theirs is! Map || theirs['cihaz'] is! String) return false;
        final id = theirs['cihaz'] as String;
        held[id] = {
          for (final k in (theirs['acik'] as List? ?? const [])) '$k',
        };
        if (theirs['telefon'] == true) _phones.add(id);
        _sessions.keepMobileAlike(theirs['mobil']);
        notifyListeners();
        return false;
      },
    );
    // Another own device asks for a session: shared, kept here too.
    _net.ownAnswers['oturum-ver'] = (asked) async {
      final data = _sessions.sessionOf('${asked['kanal']}');
      return (
        data == null
            ? <String, Object?>{'bos': true}
            : <String, Object?>{'oturum': data},
        null,
      );
    };
    // A phone renews UYAP Mobil through a computer of the person's.
    _net.ownAnswers['jeton-tazele'] = (asked) async =>
        (<String, Object?>{'jeton': await _sessions.freshMobile()}, null);
    if (_isPhone) _sessions.renewMobileThrough(_renewThroughComputer);
    _sessions.listenMobileTokens(_net.ownChanged);
    // Another own device gives one.
    _net.ownAnswers['oturum-al'] = (asked) async {
      final ok = await _sessions.takeSession(
        '${asked['kanal']}',
        asked['oturum'],
      );
      if (ok) _changedHere();
      return (<String, Object?>{'aldim': ok}, null);
    };
    _sessions.listen(() {
      final now = heldHere;
      if (now.length == _mine.length && now.containsAll(_mine)) return;
      _mine = now;
      _changedHere();
    });
    _mine = heldHere;
  }

  /// The person's own devices that said they are phones.
  final _phones = <String>{};

  /// Whether this device is a phone; by the platform when not said.
  final bool? phone;
  bool get _isPhone =>
      phone ??
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// A computer of the person's on the network that holds UYAP Mobil's
  /// session renews it for this phone: one refresh token, one spender.
  Future<Map<String, Object?>?> _renewThroughComputer() async {
    for (final peer in _net.ownOnline) {
      if (_phones.contains(peer.deviceId)) continue;
      if (!(held[peer.deviceId]?.contains('mobil') ?? false)) continue;
      final answer = await _net.askOwn(peer.deviceId, 'jeton-tazele');
      final tokens = answer?['jeton'];
      if (tokens is Map) return tokens.cast<String, Object?>();
    }
    return null;
  }

  void _changedHere() {
    notifyListeners();
    _net.ownChanged();
  }

  /// "Bu cihazda da aç": the session of [kind] [deviceId] has, opened
  /// here too; it stays open there. Why not, in the user's words.
  Future<String?> take(String deviceId, String kind) async {
    final answer = await _net.askOwn(
      deviceId,
      'oturum-ver',
      body: {'kanal': kind},
    );
    if (answer == null) return 'Cihaza ulaşılamadı. Aynı ağda ve açık mı?';
    if (answer['bos'] == true) return 'O cihazda bu oturum açık değil.';
    if (!await _sessions.takeSession(kind, answer['oturum'])) {
      return 'Oturum açılamadı; süresi dolmuş olabilir.';
    }
    _changedHere();
    return null;
  }

  /// "Öbür cihazla paylaş": the session of [kind] opened on [deviceId] too;
  /// it stays open here.
  Future<String?> give(String deviceId, String kind) async {
    final data = _sessions.sessionOf(kind);
    if (data == null) return 'Bu cihazda bu oturum açık değil.';
    final answer = await _net.askOwn(
      deviceId,
      'oturum-al',
      body: {'kanal': kind, 'oturum': data},
    );
    if (answer == null) return 'Cihaza ulaşılamadı. Aynı ağda ve açık mı?';
    if (answer['aldim'] != true) {
      return 'Oturum paylaşılamadı; süresi dolmuş olabilir.';
    }
    (held[deviceId] ??= {}).add(kind);
    _changedHere();
    return null;
  }

  Future<void> turn(String part, bool on) async {
    on ? _off.remove(part) : _off.add(part);
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'kapali': _off.toList()}));
    } catch (_) {}
    await _apply();
    notifyListeners();
    if (on) unawaited(_net.syncOwn());
  }

  Future<void> _apply() async {
    if (isOn(agenda)) {
      final db = await _database();
      _net.ownParts[agenda] = OwnPart(
        export: () async => db.agendaExport(),
        merge: (theirs) async {
          final changed = db.agendaMerge(theirs);
          // A deadline chosen, or whom the lawyer acts for, on another
          // device: those notices' deadlines made again here.
          if (db.mergedNotices.isNotEmpty) {
            refreshNoticeDeadlines(
              db,
              parties: NoticeDeadlineContext.parties,
              lawyer: NoticeDeadlineContext.lawyer,
              only: db.mergedNotices,
            );
          }
          // The agenda's pages read it again.
          if (changed) PortalSync.started?.notifyListeners();
          return changed;
        },
      );
      PortalDatabase.changed = _net.ownChanged;
    } else {
      _net.ownParts.remove(agenda);
      PortalDatabase.changed = null;
    }
  }
}

/// The portals' sessions as Senkron moves them (see [PortalSync]).
abstract interface class SessionHolder {
  bool holds(String kind);
  Map<String, Object?>? sessionOf(String kind);
  Future<bool> takeSession(String kind, Object? kept);

  /// Told when a session opens or ends here.
  void listen(VoidCallback changed);

  /// UYAP Mobil's tokens, renewed when about to end, for one that asks.
  Future<Map<String, Object?>?> freshMobile();

  /// Another own device's tokens for the shared session, when newer.
  bool keepMobileAlike(Object? theirs);

  /// Who renews UYAP Mobil for this device; null for itself.
  void renewMobileThrough(Future<Map<String, Object?>?> Function()? ask);

  /// Told when UYAP Mobil's tokens change here.
  void listenMobileTokens(VoidCallback changed);
}

/// Folio's own sessions, once Folio started them: a test never wakes the
/// lawyer's sessions.
class _PortalSessions implements SessionHolder {
  PortalSync? get _sync => PortalSync.started;

  @override
  bool holds(String kind) => _sync?.holds(kind) ?? false;
  @override
  Map<String, Object?>? sessionOf(String kind) => _sync?.sessionOf(kind);
  @override
  Future<bool> takeSession(String kind, Object? kept) async =>
      await _sync?.takeSession(kind, kept) ?? false;
  @override
  void listen(VoidCallback changed) => _sync?.addListener(changed);
  @override
  Future<Map<String, Object?>?> freshMobile() async =>
      await _sync?.freshMobile();
  @override
  bool keepMobileAlike(Object? theirs) =>
      _sync?.keepMobileAlike(theirs) ?? false;
  @override
  void renewMobileThrough(Future<Map<String, Object?>?> Function()? ask) =>
      _sync?.renewMobileThrough(ask);
  @override
  void listenMobileTokens(VoidCallback changed) =>
      PortalSync.mobileTokensChanged = changed;
}

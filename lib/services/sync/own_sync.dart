import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../office/office_network.dart';
import '../platform/app_directories.dart';
import '../portal/portal_database.dart';
import '../portal/portal_sync.dart';

/// Senkron (docs/buro.md): what one person's own devices keep alike when
/// they are on the same network, each part on or off on this device.
class OwnSync extends ChangeNotifier {
  OwnSync({
    OfficeNetwork? network,
    Future<PortalDatabase> Function()? database,
    Future<File> Function()? file,
    SessionHolder? sessions,
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
  }

  void _startSessions() {
    _net.ownParts[sessionsPart] = OwnPart(
      export: () async => {
        'cihaz': _net.self?.deviceId,
        'acik': heldHere.toList(),
      },
      merge: (theirs) async {
        if (theirs is! Map || theirs['cihaz'] is! String) return false;
        held[theirs['cihaz'] as String] = {
          for (final k in (theirs['acik'] as List? ?? const [])) '$k',
        };
        notifyListeners();
        return false;
      },
    );
    // Another own device asks for a session: given, and ended here once
    // it says it took it.
    _net.ownAnswers['oturum-ver'] = (asked) async {
      final kind = '${asked['kanal']}';
      final data = _sessions.sessionOf(kind);
      if (data == null) return (<String, Object?>{'bos': true}, null);
      return (
        <String, Object?>{'oturum': data},
        (Map<String, Object?>? word) async {
          if (word?['aldim'] == true) {
            _sessions.dropSession(kind);
            _changedHere();
          }
        },
      );
    };
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

  void _changedHere() {
    notifyListeners();
    _net.ownChanged();
  }

  /// "Bu cihaza al": the session of [kind] comes here from [deviceId] and
  /// ends there. Why not, in the user's words, when it cannot.
  Future<String?> take(String deviceId, String kind) async {
    var took = false;
    final answer = await _net.askOwn(
      deviceId,
      'oturum-ver',
      body: {'kanal': kind},
      then: (answer) async {
        if (answer['oturum'] == null) return null;
        took = await _sessions.takeSession(kind, answer['oturum']);
        return {'aldim': took};
      },
    );
    if (answer == null) return 'Cihaza ulaşılamadı. Aynı ağda ve açık mı?';
    if (answer['bos'] == true) return 'O cihazda bu oturum açık değil.';
    if (!took) return 'Oturum alınamadı; süresi dolmuş olabilir.';
    held[deviceId]?.remove(kind);
    _changedHere();
    return null;
  }

  /// "Telefona ver": the session of [kind] goes to [deviceId] and ends here.
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
      return 'Oturum verilemedi; süresi dolmuş olabilir.';
    }
    _sessions.dropSession(kind);
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
  void dropSession(String kind);

  /// Told when a session opens or ends here.
  void listen(VoidCallback changed);
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
  void dropSession(String kind) => _sync?.dropSession(kind);
  @override
  void listen(VoidCallback changed) => _sync?.addListener(changed);
}

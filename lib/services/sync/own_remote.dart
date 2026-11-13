import 'dart:async';

import 'package:flutter/foundation.dart';

import '../live/live_remote.dart';
import '../office/office_network.dart';

/// Senkron between the person's own devices when they are not on one
/// network (the phone on mobile data, the computer at the office): they
/// meet in a room of the relay (canli.lifeos.com.tr) and talk over the
/// same channel as on the network, each proving itself with its device
/// key; the relay carries sealed words it cannot open, keeps nothing, and
/// counts what it carries against the person's quota. The room's name and
/// the quota's are made with the person's private key, which only their
/// own devices hold: no one else can find the room to block it, nor spend
/// the person's quota. On one network the relay is never used.
///
/// Each device waits, for each of its own devices elsewhere, in a room of
/// its own for that one: any of them may come to it there, to keep alike,
/// to ask, to send a document. Of two, the one whose id sorts last comes
/// now and then to keep alike; the other only answers. A device seen on
/// the network is not met on the relay.
class OwnRemote extends ChangeNotifier {
  OwnRemote({OfficeNetwork? network, this.every = const Duration(minutes: 2)})
    : _net = network ?? OfficeNetwork.instance;

  static final instance = OwnRemote();

  final OfficeNetwork _net;

  /// How often a device that comes tries its rooms.
  final Duration every;

  /// Kept alike this long ago, on the network or here: not met again yet.
  static const rest = Duration(minutes: 5);

  Timer? _timer;

  /// Each start a new one: what an earlier run left going stops itself.
  int _run = 0;
  final _waiting = <String, RelayWire>{};

  /// Devices a room is being opened for, before it is: one at a time.
  final _opening = <String>{};

  /// How long to wait before a room is opened again after one that did
  /// not last, by device: longer each time, back to none once one did.
  final _backoff = <String, Duration>{};
  final _open = <RelayWire>{};
  final _coming = <String>{};

  /// Until when the relay said the person's quota was used.
  DateTime? stoppedUntil;

  /// The last time each own device was kept alike over the relay.
  final metAt = <String, DateTime>{};

  bool get running => _timer != null;

  void start() {
    if (_timer != null) return;
    final run = ++_run;
    // The network reaches an own device elsewhere through its room here.
    _net.ownRelay = (id) => reach(id);
    _timer = Timer.periodic(every, (_) => unawaited(tick(run)));
    unawaited(tick(run));
  }

  /// Stops, every room left and every talk going on cut.
  Future<void> stop() async {
    _run++;
    _net.ownRelay = null;
    _timer?.cancel();
    _timer = null;
    _waiting.clear();
    for (final w in _open.toList()) {
      await w.close();
    }
    _open.clear();
  }

  Future<RelayWire?> _connect(
    int run,
    String room,
    String role,
    String person,
  ) async {
    final wire = await RelayWire.connect(room, role, person: person);
    if (run != _run) {
      await wire.close();
      return null;
    }
    _open.add(wire);
    unawaited(wire.done.whenComplete(() => _open.remove(wire)));
    return wire;
  }

  /// One look at every own device not on the network.
  @visibleForTesting
  Future<void> tick([int? run]) async {
    final current = run ?? _run;
    if (current != _run) return;
    final me = _net.self?.deviceId;
    if (me == null || _net.ownParts.isEmpty) return;
    final until = stoppedUntil;
    if (until != null && DateTime.now().isBefore(until)) return;
    final person = await _net.ownTag('kota');
    if (person == null) return;
    final online = {for (final p in _net.ownOnline) p.deviceId};
    for (final d in _net.ownKnown) {
      if (current != _run) return;
      final id = d.deviceId;
      if (online.contains(id)) {
        // On the network now: the relay's room let go of.
        unawaited(_waiting.remove(id)?.close());
        continue;
      }
      // Its room here, waited in whatever else is done.
      final mine = await _net.ownTag('oda|$me|$id');
      if (mine == null) continue;
      await _wait(current, id, mine, person);
      // Kept alike now and then, by the one whose id sorts last.
      final last = [_net.synced[id], metAt[id]]
          .whereType<DateTime>()
          .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
      if (last != null && DateTime.now().difference(last) < rest) continue;
      if (me.compareTo(id) > 0) {
        final theirs = await _net.ownTag('oda|$id|$me');
        if (theirs != null) await _come(current, id, theirs, person);
      }
    }
  }

  /// [id]'s room for this device, reached: null when [id] is not waiting
  /// there now (not open, or the quota used).
  Future<RelayWire?> reach(String id) async {
    final run = _run;
    bool live() =>
        run == _run &&
        _timer != null &&
        (stoppedUntil == null || DateTime.now().isAfter(stoppedUntil!));
    if (!live()) return null;
    final me = _net.self?.deviceId;
    final person = await _net.ownTag('kota');
    final room = await _net.ownTag('oda|$id|$me');
    if (me == null || person == null || room == null) return null;
    // Twice: a talk that just ended leaves its room a moment (4410), and
    // the room is waited in again a second after (OwnRemote._wait).
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!live()) return null;
      try {
        final wire = await _connect(run, room, 'katilan', person);
        if (wire == null) return null;
        // No room (4404) or one in use (4410): the relay says so at once.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!live()) {
          await wire.close();
          return null;
        }
        if (!wire.closed) return wire;
        _quota(wire.closeCode);
        if (wire.closeCode == 4429) return null;
      } catch (e) {
        _refused(e);
        return null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
    return null;
  }

  /// Waits in the room for [id]; answered as on the network when it comes,
  /// then waited in again at a later look.
  Future<void> _wait(int run, String id, String room, String person) async {
    final open = _waiting[id];
    if (open != null && !open.closed) return;
    // Reserved before the relay is reached: two at once would open two.
    if (!_opening.add(id)) return;
    final RelayWire wire;
    final opened = DateTime.now();
    try {
      final got = await _connect(run, room, 'paylasan', person);
      if (got == null) return;
      wire = got;
      _waiting[id] = wire;
    } catch (e) {
      _refused(e);
      return;
    } finally {
      _opening.remove(id);
    }
    // Someone came: a talk, however short, not a room the relay refused.
    var met = false;
    unawaited(() async {
      try {
        // The relay keeps a room 15 minutes: a new one at a later look.
        final came = await wire.next(const Duration(minutes: 15));
        met = came != null && came['t'] == 'katilan';
        if (came == null || came['t'] != 'katilan' || run != _run) {
          _quota(wire.closeCode);
          await wire.close();
          return;
        }
        if (await _net.answerOwnOver(wire, id) && run == _run) {
          metAt[id] = DateTime.now();
          notifyListeners();
        }
        _quota(wire.closeCode);
      } finally {
        if (identical(_waiting[id], wire)) _waiting.remove(id);
        await wire.close();
        // Waited in again: at once after a room that lasted (the next to
        // come finds it), later and later after one the relay shut at
        // once (4409, its quota, its door).
        final lasted =
            met ||
            DateTime.now().difference(opened) > const Duration(seconds: 5);
        final Duration pause;
        if (lasted) {
          _backoff.remove(id);
          pause = const Duration(seconds: 1);
        } else {
          pause = _backoff[id] = Duration(
            seconds: ((_backoff[id]?.inSeconds ?? 2) * 2).clamp(4, 600),
          );
        }
        unawaited(
          Future<void>.delayed(pause).then((_) async {
            if (run == _run &&
                _timer != null &&
                _net.ownKnown.any((d) => d.deviceId == id) &&
                !_net.ownOnline.any((p) => p.deviceId == id) &&
                (stoppedUntil == null ||
                    DateTime.now().isAfter(stoppedUntil!))) {
              await _wait(run, id, room, person);
            }
          }),
        );
      }
    }());
  }

  /// Comes to [id]'s room; kept alike over it when [id] is waiting there.
  Future<void> _come(int run, String id, String room, String person) async {
    if (!_coming.add(id)) return;
    RelayWire? wire;
    try {
      wire = await _connect(run, room, 'katilan', person);
      if (wire == null) return;
      // No room (4404): not there now. The relay says so at once.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (wire.closed || run != _run) {
        _quota(wire.closeCode);
        return;
      }
      if (await _net.syncOwnOver(wire, id) && run == _run) {
        metAt[id] = DateTime.now();
        notifyListeners();
      }
      _quota(wire.closeCode);
    } catch (e) {
      _refused(e);
    } finally {
      await wire?.close();
      _coming.remove(id);
    }
  }

  void _refused(Object e) {
    // 429 at the door: the person's quota used. (503 is the relay being
    // full for a while: tried again at the next look.)
    if ('$e'.contains('429')) _stopForToday();
  }

  void _quota(int? code) {
    if (code == 4429) _stopForToday();
  }

  /// Until the relay's day turns: its days are UTC (Istanbul's 03.00).
  void _stopForToday() {
    final now = DateTime.now().toUtc();
    stoppedUntil = DateTime.utc(now.year, now.month, now.day + 1).toLocal();
    notifyListeners();
  }
}

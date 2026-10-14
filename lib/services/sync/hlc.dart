import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A change's version (docs/senkron-plan.md R2): the time it was made, a
/// counter for changes within the same millisecond, and who made it, the
/// device and its write generation ("cihaz:nesil"). A device that has seen
/// a change writes after it, whatever its clock says.
class Hlc implements Comparable<Hlc> {
  const Hlc(this.l, this.c, this.source);

  /// Milliseconds since the epoch, UTC.
  final int l;
  final int c;

  /// The device that made the change and its write generation; `goc` for
  /// a version made of an old timestamp (R2.1).
  final String source;

  static const zero = Hlc(0, 0, '');

  /// The largest counter: past it the clock's millisecond goes on by one,
  /// so that a version is always written in [toString]'s width.
  static const maxCounter = 99999;

  /// The source of versions made of old timestamps.
  static const migrated = 'goc';

  @override
  int compareTo(Hlc other) {
    if (l != other.l) return l.compareTo(other.l);
    if (c != other.c) return c.compareTo(other.c);
    return source.compareTo(other.source);
  }

  bool operator <(Hlc other) => compareTo(other) < 0;
  bool operator >(Hlc other) => compareTo(other) > 0;
  bool operator <=(Hlc other) => compareTo(other) <= 0;
  bool operator >=(Hlc other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is Hlc && other.l == l && other.c == c && other.source == source;

  @override
  int get hashCode => Object.hash(l, c, source);

  /// "001760430000000.00000.<source>": ordered as text as it is as a
  /// version, for a column or a JSON field.
  @override
  String toString() =>
      '${l.toString().padLeft(15, '0')}.'
      '${c.toString().padLeft(5, '0')}.$source';

  /// [text] as [toString] writes it; null when it is not one.
  static Hlc? tryParse(Object? text) {
    if (text is! String) return null;
    final m = RegExp(r'^(\d{1,15})\.(\d{1,5})\.(.*)$').firstMatch(text);
    if (m == null) return null;
    return Hlc(int.parse(m[1]!), int.parse(m[2]!), m[3]!);
  }

  /// An old timestamp of Folio's as a version, the same on every device
  /// (R2.1). Folio wrote `DateTime.now().toIso8601String()`: local time,
  /// with no zone. That is read as Türkiye's time, +03:00 all year since
  /// 2016, whatever the zone of the device reading it. A timestamp with
  /// its zone ("…Z", "…+02:00") keeps its instant. One missing or
  /// unreadable is older than every real version.
  static Hlc fromLegacy(Object? stamp) {
    final text = stamp is String ? stamp.trim() : '';
    if (text.isEmpty) return const Hlc(0, 0, migrated);
    final zoned = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(text);
    final at = DateTime.tryParse(zoned ? text : '$text+03:00');
    if (at == null) return const Hlc(0, 0, migrated);
    return Hlc(at.millisecondsSinceEpoch, 0, migrated);
  }

  /// Which of two versions of the same field or group wins, [a] with its
  /// value [aValue] or [b] with [bValue]: the later version; for the same
  /// version (two old timestamps alike, R2.1) the value whose canonical
  /// digest is greater, so that every device chooses alike. Positive when
  /// [a] wins, negative when [b] does, zero for the same value.
  static int decide(Hlc a, Object? aValue, Hlc b, Object? bValue) {
    final byVersion = a.compareTo(b);
    if (byVersion != 0) return byVersion;
    return digest(aValue).compareTo(digest(bValue));
  }

  /// [value]'s JSON with its maps' keys in order: the same content gives
  /// the same text on every device.
  static String canonical(Object? value) => jsonEncode(_sorted(value));

  /// A short digest of [canonical].
  static String digest(Object? value) =>
      sha256.convert(utf8.encode(canonical(value))).toString().substring(0, 16);

  static Object? _sorted(Object? v) => switch (v) {
    final Map m => {
      for (final k in (m.keys.map((k) => '$k').toList()..sort()))
        k: _sorted(m[k]),
    },
    final List l => [for (final e in l) _sorted(e)],
    _ => v,
  };
}

/// The device's hybrid logical clock (R2). Its state is kept by [persist]
/// after every change and given back at start, so that it never goes back:
/// a restart begins at the later of what was kept and now.
class HlcClock {
  HlcClock({
    required this._source,
    this._l = 0,
    this._c = 0,
    DateTime Function()? now,
    this._persist,
  }) : _now = now ?? DateTime.now;

  final String _source;
  final DateTime Function() _now;
  final void Function(int l, int c)? _persist;
  int _l, _c;

  String get source => _source;

  /// The latest version this clock has made or seen.
  Hlc get last => Hlc(_l, _c, _source);

  int _wall() => _now().toUtc().millisecondsSinceEpoch;

  /// A version for a change made here now.
  Hlc tick() {
    final wall = _wall();
    if (wall > _l) {
      _l = wall;
      _c = 0;
    } else {
      _c++;
    }
    _bound();
    _persist?.call(_l, _c);
    return Hlc(_l, _c, _source);
  }

  /// A counter past [Hlc.maxCounter] carried into the millisecond.
  void _bound() {
    if (_c > Hlc.maxCounter) {
      _l++;
      _c = 0;
    }
  }

  /// [remote], a version another device made, seen here: what is written
  /// after it here comes after it.
  void receive(Hlc remote) {
    final wall = _wall();
    final l = [_l, remote.l, wall].reduce((a, b) => a > b ? a : b);
    final int c;
    if (l == _l && l == remote.l) {
      c = (_c > remote.c ? _c : remote.c) + 1;
    } else if (l == _l) {
      c = _c + 1;
    } else if (l == remote.l) {
      c = remote.c + 1;
    } else {
      c = 0;
    }
    _l = l;
    _c = c;
    _bound();
    _persist?.call(_l, _c);
  }
}

import 'dart:convert';

import 'hlc.dart';

/// A row's fields by the groups each is changed with, every group with a
/// version of its own (docs/senkron-plan.md R1): another device's copy
/// changes only the groups it changed later. A row kept before versions
/// has each group's version made of its last change, the same on every
/// device (R2.1).
class FieldGroups {
  const FieldGroups(this.groups);

  final Map<String, List<String>> groups;

  /// The versions kept in [kept] (a JSON text or map), each group missing
  /// made of [legacy], the row's old timestamp.
  Map<String, Hlc> versionsOf(Object? kept, {required Object? legacy}) {
    final map = kept is String ? _decode(kept) : kept;
    final old = Hlc.fromLegacy(legacy);
    return {
      for (final g in groups.keys)
        g: (map is Map ? Hlc.tryParse(map[g]) : null) ?? old,
    };
  }

  /// [versions] as kept in a row.
  static String encode(Map<String, Hlc> versions) => jsonEncode({
    for (final k in versions.keys.toList()..sort()) k: '${versions[k]}',
  });

  static Object? _decode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  /// [group]'s value in [row].
  Object? valueOf(Map row, String group) => {
    for (final f in groups[group]!) f: row[f],
  };

  /// The versions of [after], a row as it is now written: a group that
  /// says what it said in [before] keeps its version, one changed (or all,
  /// for a new row) is given [tick]'s.
  Map<String, Hlc> stamp(
    Map? before,
    Map<String, Hlc> kept,
    Map after,
    Hlc Function() tick,
  ) => {
    for (final g in groups.keys)
      g:
          before != null &&
              Hlc.canonical(valueOf(before, g)) ==
                  Hlc.canonical(valueOf(after, g))
          ? kept[g]!
          : tick(),
  };

  /// [mine] and [theirs], two copies of one row with their versions, made
  /// one: each group as the later of the two changed it; for the same
  /// version, the same value chosen on every device.
  ({Map<String, Object?> row, Map<String, Hlc> versions}) merge(
    Map mine,
    Map<String, Hlc> mineVersions,
    Map theirs,
    Map<String, Hlc> theirVersions,
  ) {
    final row = <String, Object?>{...mine.cast<String, Object?>()};
    final versions = <String, Hlc>{};
    for (final g in groups.keys) {
      final a = mineVersions[g]!, b = theirVersions[g]!;
      final theirsWin =
          Hlc.decide(b, valueOf(theirs, g), a, valueOf(mine, g)) > 0;
      versions[g] = theirsWin ? b : a;
      if (theirsWin) {
        for (final f in groups[g]!) {
          row[f] = theirs[f];
        }
      }
    }
    return (row: row, versions: versions);
  }
}

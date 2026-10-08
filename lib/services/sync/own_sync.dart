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
  }) : _net = network ?? OfficeNetwork.instance,
       _database = database ?? PortalDatabase.shared,
       _file = file ?? _default;

  static Future<File> _default() async =>
      File(p.join((await folioSupportDirectory()).path, 'senkron.json'));

  static final instance = OwnSync();

  final OfficeNetwork _net;
  final Future<PortalDatabase> Function() _database;
  final Future<File> Function() _file;

  static const agenda = 'ajanda';

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

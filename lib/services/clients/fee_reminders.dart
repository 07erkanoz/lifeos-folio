import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';
import '../portal/portal_database.dart';
import 'client.dart';
import 'client_accounts.dart';

/// An instalment of a client's fee to be told of: its client, case, day
/// and amount, and the days left (less than none when late).
typedef DueInstalment = ({
  Client client,
  String caseKey,
  DateTime due,
  int amount,
  int daysLeft,
});

/// The instalments of the fees agreed coming or late: told three days
/// before, on the day, then a day, a week, two and a month late; each
/// once, kept on this device. Only to one who sees the money.
class FeeReminders {
  FeeReminders({Future<File> Function()? file}) : _file = file ?? _default;

  static final instance = FeeReminders();

  static Future<File> _default() async => File(
    p.join((await folioSupportDirectory()).path, 'muvekkil_hatirlatma.json'),
  );

  final Future<File> Function() _file;
  final _sent = <String>{};
  bool _loaded = false;
  Timer? _timer;

  static const _before = {3, 0};
  static const _late = {1, 7, 14, 30};

  /// Every instalment not paid and coming within a week or late.
  static List<DueInstalment> open(PortalDatabase db, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final cards = {for (final c in db.clientCards()) c.id: c};
    // A card merged into another is that one's: its records with it.
    final canon = <String, String>{
      for (final c in cards.values)
        if (!c.removed) ...{for (final a in c.absorbed) a: c.id, c.id: c.id},
    };
    final byClient = <String, List<ClientRecord>>{};
    for (final r in db.allClientRecords()) {
      final id = canon[r.clientId];
      if (id != null && !r.removed && r.kind.money) {
        (byClient[id] ??= []).add(r);
      }
    }
    final out = <DueInstalment>[];
    for (final e in byClient.entries) {
      final client = cards[e.key];
      if (client == null || client.removed) continue;
      for (final a in caseAccounts(e.value).values) {
        for (final t in a.instalments(now)) {
          if (t.paid) continue;
          final left = DateTime(
            t.due.year,
            t.due.month,
            t.due.day,
          ).difference(today).inDays;
          if (left > 7) continue;
          out.add((
            client: client,
            caseKey: a.caseKey,
            due: t.due,
            amount: t.amount,
            daysLeft: left,
          ));
        }
      }
    }
    return out..sort((a, b) => a.due.compareTo(b.due));
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is Map) {
        _sent.addAll([for (final s in j['gonderilen'] as List? ?? []) '$s']);
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({'gonderilen': _sent.toList()}));
    } catch (_) {}
  }

  /// What is to be told now, each once.
  @visibleForTesting
  List<DueInstalment> due(PortalDatabase db, DateTime now) => [
    for (final t in open(db, now))
      if ((t.daysLeft >= 0
              ? _before.contains(t.daysLeft)
              : _late.contains(-t.daysLeft)) &&
          _sent.add(
            '${t.client.id}|${t.caseKey}|${t.due.toIso8601String()}|'
            '${t.daysLeft}',
          ))
        t,
  ];

  /// Checks now and every hour while Folio runs, when [sees] says this
  /// person sees the money.
  void start(
    bool Function() sees,
    void Function(DueInstalment t) tell, {
    Future<PortalDatabase> Function()? database,
  }) {
    _timer?.cancel();
    Future<void> check() async {
      if (!sees()) return;
      await _load();
      try {
        final db = await (database ?? PortalDatabase.shared)();
        final todo = due(db, DateTime.now());
        if (todo.isEmpty) return;
        await _save();
        todo.forEach(tell);
      } catch (_) {}
    }

    unawaited(check());
    _timer = Timer.periodic(const Duration(hours: 1), (_) => check());
  }
}

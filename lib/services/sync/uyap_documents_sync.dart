import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../office/office_network.dart';
import '../office/office_transfer.dart';
import '../uyap/uyap_case_store.dart';

/// UYAP's documents an own device has downloaded, given to another of the
/// person's devices when asked (Senkron): a phone being set up takes what
/// its computer has, so that it need not fetch each from UYAP again.
/// Asked for, never sent of itself; each document put in its case's place
/// as though fetched here.
class UyapDocumentsSync {
  UyapDocumentsSync({required this.network, this._store});

  static const kind = 'uyap-evrak';

  final OfficeNetwork network;
  final UyapCaseStore? _store;
  UyapCaseStore get store => _store ?? UyapCaseStore.instance;

  /// Every downloaded document here: its case, its key, where and how big.
  Future<List<({String court, String number, String key, File file})>>
  here() async {
    final out = <({String court, String number, String key, File file})>[];
    for (final (record, _) in await store.cases(counted: false)) {
      for (final d in record.documents) {
        for (final one in [d, ...d.attachments]) {
          final f = store.fileOf(record, one.key);
          if (f != null) {
            out.add((
              court: record.court,
              number: record.number,
              key: one.key,
              file: f,
            ));
          }
        }
      }
    }
    return out;
  }

  /// What another own device asked: how many and how big (`gonder` not
  /// set), or that they be sent to it (`cihaz` names it).
  Future<Map<String, Object?>> answer(Map<String, Object?> asked) async {
    final all = await here();
    var bytes = 0;
    for (final one in all) {
      try {
        bytes += await one.file.length();
      } catch (_) {}
    }
    if (asked['gonder'] == true && asked['cihaz'] is String) {
      final to = network.ownOnline
          .where((p) => p.deviceId == asked['cihaz'])
          .firstOrNull;
      if (to != null && all.isNotEmpty) {
        // A few at a time: one transfer is not a whole archive.
        for (var i = 0; i < all.length; i += 20) {
          final batch = all.skip(i).take(20).toList();
          unawaited(
            network.send(
              to,
              [for (final one in batch) one.file.path],
              meta: {
                'senkron': kind,
                'evrak': jsonEncode([
                  for (final one in batch)
                    {'m': one.court, 'e': one.number, 'k': one.key},
                ]),
              },
            ),
          );
        }
      }
    }
    return {'evrak': all.length, 'bayt': bytes};
  }

  /// How many documents [deviceId] has, and their size; null when it could
  /// not be asked.
  Future<({int count, int bytes})?> count(String deviceId) async {
    final a = await network.askOwn(deviceId, kind);
    if (a == null) return null;
    return (
      count: (a['evrak'] as num?)?.toInt() ?? 0,
      bytes: (a['bayt'] as num?)?.toInt() ?? 0,
    );
  }

  /// [deviceId] asked to send its documents here.
  Future<bool> ask(String deviceId) async =>
      await network.askOwn(
        deviceId,
        kind,
        body: {'gonder': true, 'cihaz': network.self?.deviceId},
      ) !=
      null;

  /// Documents that came: each put in its case's place, as though fetched
  /// here, where this device has none of its own for it. The copies that
  /// came are not left behind.
  Future<int> came(OfficeTransfer t) => place(t.saved, t.meta);

  /// [saved], as a transfer with [meta] brought them: see [came].
  Future<int> place(List<String> saved, Map<String, Object?> meta) async {
    List<Object?> which;
    try {
      which = jsonDecode('${meta['evrak'] ?? '[]'}') as List<Object?>;
    } catch (_) {
      which = const [];
    }
    var placed = 0;
    for (var i = 0; i < saved.length; i++) {
      final path = saved[i];
      final one = i < which.length && which[i] is Map ? which[i] as Map : null;
      try {
        if (one != null) {
          final record = await store.load('${one['m']}', '${one['e']}');
          final key = '${one['k']}';
          final doc = record == null
              ? null
              : [
                  for (final d in record.documents) ...[d, ...d.attachments],
                ].where((d) => d.key == key).firstOrNull;
          if (record != null &&
              doc != null &&
              store.fileOf(record, key) == null) {
            await store.save(
              record,
              doc,
              Uint8List.fromList(await File(path).readAsBytes()),
            );
            placed++;
          }
        }
      } catch (_) {}
      try {
        await File(path).delete();
      } catch (_) {}
    }
    return placed;
  }
}

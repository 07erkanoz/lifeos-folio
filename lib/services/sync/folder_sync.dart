import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../library/file_library.dart';
import '../office/office_network.dart';
import '../office/office_transfer.dart';
import '../platform/app_directories.dart';
import '../uyap/uyap_case_store.dart' show UyapSettings;

/// A folder kept alike on the person's own devices.
class SyncedFolder {
  const SyncedFolder({
    required this.id,
    required this.name,
    required this.path,
    this.since,
  });
  final String id, name, path;

  /// Joined for what comes from now on only (a phone's choice): files
  /// changed before this are not fetched.
  final DateTime? since;

  Map<String, Object?> toJson() => {
    'id': id,
    'ad': name,
    'yol': path,
    if (since != null) 'since': since!.millisecondsSinceEpoch,
  };

  static SyncedFolder? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || j['yol'] is! String) return null;
    return SyncedFolder(
      id: j['id'] as String,
      name: '${j['ad'] ?? ''}',
      path: j['yol'] as String,
      since: j['since'] is int
          ? DateTime.fromMillisecondsSinceEpoch(j['since'] as int)
          : null,
    );
  }
}

/// A folder another of the person's devices keeps alike and this one not
/// yet.
class OfferedFolder {
  const OfferedFolder(this.id, this.name, this.from, this.fromName);
  final String id, name, from, fromName;
}

/// Senkron's folders (docs/buro.md): each device sends the other what it
/// has newer, by the file's contents; what both changed is kept twice,
/// the other's copy under the name of the device it came from; a file
/// taken off on one goes to Senkron's bin on the other, for thirty days.
class FolderSync extends ChangeNotifier {
  FolderSync({
    OfficeNetwork? network,
    Future<File> Function()? file,
    Future<Directory> Function()? bin,
    String Function()? root,
  }) : _net = network ?? OfficeNetwork.instance,
       _file = file ?? _defaultFile,
       _bin = bin ?? _defaultBin,
       _root = root ?? _defaultRoot;

  static final instance = FolderSync();

  static Future<File> _defaultFile() async => File(
    p.join((await folioSupportDirectory()).path, 'senkron_klasorler.json'),
  );
  static Future<Directory> _defaultBin() async =>
      Directory(p.join((await folioSupportDirectory()).path, 'senkron-cop'));

  /// Where a folder joined from another device is put: beside UYAP's.
  static String _defaultRoot() =>
      p.join(p.dirname(UyapSettings.instance.folder), 'Senkron');

  final OfficeNetwork _net;
  final Future<File> Function() _file;
  final Future<Directory> Function() _bin;
  final String Function() _root;

  /// A folder made here, for the library to search.
  void Function(String path)? onAdded;

  final folders = <String, SyncedFolder>{};
  final offered = <String, OfferedFolder>{};

  /// Folder → file (relative, '/') → its contents' hash as last alike.
  final _base = <String, Map<String, String>>{};

  /// Folder → file → when it was taken off.
  final _removed = <String, Map<String, int>>{};

  /// File → (size, modified, hash): hashed again only when changed.
  final _hashes = <String, (int, int, String)>{};

  /// Folder → how many files it has, as last counted.
  final counts = <String, int>{};

  static const part = 'klasorler';
  static const binLife = Duration(days: 30);
  bool _loaded = false;
  Timer? _look;

  Future<void> start() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (await file.exists()) {
        final j = jsonDecode(await file.readAsString());
        if (j is Map) {
          for (final f in (j['klasorler'] as List? ?? const [])) {
            final folder = SyncedFolder.fromJson(f);
            if (folder != null) folders[folder.id] = folder;
          }
          (j['taban'] as Map? ?? const {}).forEach(
            (id, m) => _base['$id'] = (m as Map).cast<String, String>(),
          );
          (j['silinen'] as Map? ?? const {}).forEach(
            (id, m) => _removed['$id'] = (m as Map).cast<String, int>(),
          );
        }
      }
    } catch (_) {}
    _net.ownParts[part] = OwnPart(export: _export, merge: _merge);
    _net.onOwnFiles = (t) => unawaited(_came(t));
    // The other put what this one sent in place: alike now, so that a
    // change made there next is not taken here for one made on both.
    _net.ownAnswers['klasor-yerlesti'] = (asked) async {
      final f = folders['${asked['klasor']}'];
      final placed = asked['dosyalar'];
      if (f != null && placed is Map) {
        final base = _base[f.id] ??= {};
        final index = await _index(f);
        placed.forEach((rel, sum) {
          if (index['$rel']?.$3 == sum) base['$rel'] = '$sum';
        });
        await _save();
      }
      return (<String, Object?>{'tamam': true}, null);
    };
    unawaited(_clearStaging());
    unawaited(_emptyBin());
    // Files changed on disk are looked for now and then.
    _look = Timer.periodic(const Duration(minutes: 2), (_) {
      if (folders.isNotEmpty) unawaited(_net.syncOwn());
    });
  }

  @override
  void dispose() {
    _look?.cancel();
    super.dispose();
  }

  Future<void> _saving = Future.value();
  Future<void> _save() => _saving = _saving
      .then((_) async {
        final file = await _file();
        await file.parent.create(recursive: true);
        final part = File('${file.path}.part');
        await part.writeAsString(
          jsonEncode({
            'klasorler': [for (final f in folders.values) f.toJson()],
            'taban': _base,
            'silinen': _removed,
          }),
          flush: true,
        );
        await part.rename(file.path);
      })
      .catchError((Object _) {});

  static String _newId() {
    final r = Random.secure();
    return [
      for (var i = 0; i < 8; i++)
        r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  /// Why [path] cannot be kept alike, or null: one folder kept alike is
  /// never inside another, or its files would be counted twice.
  String? whyNot(String path) {
    for (final f in folders.values) {
      if (p.equals(f.path, path)) return null;
      if (p.isWithin(f.path, path) || p.isWithin(path, f.path)) {
        return '“${f.name}” ile iç içe; iç içe klasörler eşitlenmez.';
      }
    }
    return null;
  }

  /// Starts keeping [path] alike on the person's other devices; null when
  /// it is inside or around one already (see [whyNot]).
  Future<SyncedFolder?> share(String path) async {
    final kept = folders.values.where((f) => p.equals(f.path, path));
    if (kept.isNotEmpty) return kept.first;
    if (whyNot(path) != null) return null;
    final f = SyncedFolder(id: _newId(), name: p.basename(path), path: path);
    folders[f.id] = f;
    await _save();
    notifyListeners();
    unawaited(_net.syncOwn());
    return f;
  }

  /// Keeps an offered folder here too, under Senkron's folder; with
  /// [existing] false only what changes from now on comes.
  Future<void> join(String id, {bool existing = true}) async {
    final o = offered.remove(id);
    if (o == null || folders.containsKey(id)) return;
    var dir = Directory(p.join(_root(), _safeName(o.name)));
    for (var n = 2; await dir.exists(); n++) {
      dir = Directory(p.join(_root(), '${_safeName(o.name)} ($n)'));
    }
    await dir.create(recursive: true);
    folders[id] = SyncedFolder(
      id: id,
      name: o.name,
      path: dir.path,
      since: existing ? null : DateTime.now(),
    );
    await _save();
    onAdded?.call(dir.path);
    notifyListeners();
    unawaited(_net.syncOwn());
  }

  /// Keeps it no more; its files stay where they are.
  Future<void> stop(String id) async {
    folders.remove(id);
    _base.remove(id);
    _removed.remove(id);
    await _save();
    notifyListeners();
  }

  static String _safeName(String name) {
    final s = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
    return s.isEmpty || s == '.' || s == '..' ? 'Klasör' : s;
  }

  /// [rel] as a path inside [folder], or null when it would lead out.
  static String? _inside(String folder, String rel) {
    final parts = rel.split('/');
    if (parts.any((s) => s.isEmpty || s == '.' || s == '..')) return null;
    if (parts.any((s) => s.contains('\\') || s.contains(':'))) return null;
    final full = p.joinAll([folder, ...parts]);
    return p.isWithin(folder, full) ? full : null;
  }

  /// A folder's files the library reads, by their path inside it.
  Future<Map<String, (int, int, String)>> _index(SyncedFolder f) async {
    final dir = Directory(f.path);
    if (!await dir.exists()) return const {};
    final stats = <String, FileStat>{};
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: f.path).replaceAll('\\', '/');
      if (rel.split('/').any((s) => s.startsWith('.'))) continue;
      if (!FileLibrary.supports(e.path)) continue;
      stats[rel] = await e.stat();
    }
    bool same(String rel) {
      final h = _hashes[p.join(f.path, rel)], st = stats[rel]!;
      return h != null &&
          h.$1 == st.size &&
          h.$2 == st.modified.millisecondsSinceEpoch;
    }

    final stale = <String>[
      for (final rel in stats.keys)
        if (!same(rel)) p.join(f.path, rel),
    ];
    if (stale.isNotEmpty) {
      final sums = await _hashApart(stale);
      for (final path in stale) {
        final st = stats[p.relative(path, from: f.path).replaceAll('\\', '/')]!;
        final sum = sums[path];
        if (sum != null) {
          _hashes[path] = (st.size, st.modified.millisecondsSinceEpoch, sum);
        }
      }
    }
    final out = <String, (int, int, String)>{
      for (final rel in stats.keys) rel: ?_hashes[p.join(f.path, rel)],
    };
    // What was alike and is gone is taken off on the others too.
    final base = _base[f.id] ??= {};
    final gone = [
      for (final rel in base.keys)
        if (!out.containsKey(rel)) rel,
    ];
    if (gone.isNotEmpty) {
      final removed = _removed[f.id] ??= {};
      for (final rel in gone) {
        base.remove(rel);
        removed[rel] = DateTime.now().millisecondsSinceEpoch;
      }
      unawaited(_save());
    }
    counts[f.id] = out.length;
    return out;
  }

  // Not inside an async body: there the closure would hold its futures,
  // which cannot go to another isolate.
  static Future<Map<String, String>> _hashApart(List<String> paths) =>
      Isolate.run(() => _hashAll(paths));

  static Map<String, String> _hashAll(List<String> paths) {
    final out = <String, String>{};
    for (final path in paths) {
      try {
        out[path] = hash.sha256
            .convert(File(path).readAsBytesSync())
            .toString();
      } catch (_) {}
    }
    return out;
  }

  Future<Object?> _export() async => {
    'cihaz': _net.self?.deviceId,
    'ad': _net.self?.device,
    'klasorler': [
      for (final f in folders.values)
        {
          'id': f.id,
          'ad': f.name,
          if (f.since != null) 'since': f.since!.millisecondsSinceEpoch,
          'dizin': {
            for (final e in (await _index(f)).entries)
              e.key: [e.value.$1, e.value.$2, e.value.$3],
          },
          'silinen': _removed[f.id] ?? const <String, int>{},
        },
    ],
  };

  Future<bool> _merge(Object? theirs) async {
    if (theirs is! Map || theirs['cihaz'] is! String) return false;
    final from = theirs['cihaz'] as String;
    final fromName = '${theirs['ad'] ?? ''}';
    var changed = false;
    for (final t in (theirs['klasorler'] as List? ?? const [])) {
      if (t is! Map || t['id'] is! String) continue;
      final id = t['id'] as String;
      final mine = folders[id];
      if (mine == null) {
        if (!offered.containsKey(id)) {
          offered[id] = OfferedFolder(id, '${t['ad'] ?? ''}', from, fromName);
          changed = true;
        }
        continue;
      }
      await _alike(mine, t, from, fromName);
    }
    if (changed) notifyListeners();
    return changed;
  }

  /// What one folder needs between this device and [from].
  Future<void> _alike(
    SyncedFolder f,
    Map theirs,
    String from,
    String fromName,
  ) async {
    final index = await _index(f);
    final base = _base[f.id] ??= {};
    final removedHere = _removed[f.id] ??= {};
    final theirIndex = <String, (int, int, String)>{
      for (final e in (theirs['dizin'] as Map? ?? const {}).entries)
        if (e.value is List && (e.value as List).length == 3)
          '${e.key}': (
            (e.value as List)[0] as int,
            (e.value as List)[1] as int,
            '${(e.value as List)[2]}',
          ),
    };
    final theirRemoved = (theirs['silinen'] as Map? ?? const {})
        .cast<String, Object?>();
    final theirSince = theirs['since'] is int ? theirs['since'] as int : null;
    // Taken off there after it was last alike, and not changed here since:
    // to the bin here.
    for (final MapEntry(key: rel, value: at) in theirRemoved.entries) {
      final mineNow = index[rel];
      // Unchanged here since alike: by contents, not by the two clocks.
      if (at is! int || mineNow == null || base[rel] != mineNow.$3) continue;
      await _toBin(f, rel);
      index.remove(rel);
      base.remove(rel);
      removedHere[rel] = at;
    }
    // What this device has that they have not, or older.
    final push = <String>[];
    for (final MapEntry(key: rel, value: mine) in index.entries) {
      final there = theirIndex[rel];
      if (there == null) {
        // Taken off there and not changed here since: going to the bin.
        if (theirRemoved.containsKey(rel) && base[rel] == mine.$3) continue;
        if (theirSince != null && mine.$2 < theirSince) continue;
        push.add(rel);
      } else if (there.$3 == mine.$3) {
        base[rel] = mine.$3;
      } else if (there.$3 == base[rel]) {
        // Changed here only.
        push.add(rel);
      } else if (mine.$3 == base[rel]) {
        // Changed there only: theirs comes.
      } else if ((_net.self?.deviceId ?? '').compareTo(from) < 0) {
        // Changed on both: this device's goes under the name, and theirs,
        // kept as it comes, under the name of the device it was on.
        push.add(rel);
      }
    }
    unawaited(_save());
    if (push.isEmpty) return;
    final peer = _net.ownOnline.where((p) => p.deviceId == from).firstOrNull;
    if (peer == null) return;
    // In batches: one offer of hundreds of files would be one long wait.
    for (var i = 0; i < push.length; i += 50) {
      final batch = push.sublist(i, min(i + 50, push.length));
      // Taken as alike only when the other says it put them in place
      // (see 'klasor-yerlesti').
      await _net.send(
        peer,
        [for (final rel in batch) _inside(f.path, rel)!],
        meta: {'senkron': f.id, 'yollar': jsonEncode(batch)},
      );
    }
  }

  /// Files another own device sent: each to its place, a change made here
  /// and not yet alike kept under this device's name first.
  Future<void> _came(OfficeTransfer t) async {
    final f = folders[t.meta['senkron']];
    List<Object?> rels;
    try {
      rels = jsonDecode('${t.meta['yollar'] ?? '[]'}') as List<Object?>;
    } catch (_) {
      rels = const [];
    }
    if (f == null || rels.length != t.files.length) {
      // No place for them: not left lying in the staging folder.
      for (final path in t.saved) {
        await File(path).delete().catchError((Object _) => File(path));
      }
      return;
    }
    final placed = <String, String>{};
    final base = _base[f.id] ??= {};
    for (var i = 0; i < t.files.length && i < t.saved.length; i++) {
      final rel = '${rels[i]}';
      final target = _inside(f.path, rel);
      final came = File(t.saved[i]);
      if (target == null || await _throughLink(f.path, target)) {
        await came.delete().catchError((Object _) => came);
        continue;
      }
      final here = File(target);
      if (await here.exists()) {
        final sum = await OfficeTransfer.sha256Of(here);
        if (sum == t.files[i].sha256) {
          await came.delete().catchError((Object _) => came);
          base[rel] = sum;
          placed[rel] = sum;
          continue;
        }
        if (sum != base[rel]) {
          // Changed here too: kept, under this device's name.
          await here.rename(_copyName(target, _net.self?.device ?? 'bu cihaz'));
        }
      }
      try {
        await here.parent.create(recursive: true);
        await _place(came, target);
      } catch (_) {
        // Not put in place: not said so, and sent again next time.
        continue;
      }
      base[rel] = t.files[i].sha256;
      placed[rel] = t.files[i].sha256;
      _removed[f.id]?.remove(rel);
    }
    await _save();
    notifyListeners();
    if (placed.isNotEmpty) {
      await _net.askOwn(
        t.peer.deviceId,
        'klasor-yerlesti',
        body: {'klasor': f.id, 'dosyalar': placed},
      );
    }
  }

  /// Moved in at once; from another disk, copied beside it first and then
  /// moved, so that a cut copy never stands for the file.
  static Future<void> _place(File came, String target) async {
    try {
      await came.rename(target);
      return;
    } on FileSystemException {
      // Another disk.
    }
    final part = File('$target.folio-parca');
    await came.copy(part.path);
    await part.rename(target);
    await came.delete();
  }

  /// Whether a folder between [folder] and [target] is a link: one that
  /// leads out of it would take a file elsewhere.
  static Future<bool> _throughLink(String folder, String target) async {
    var dir = p.dirname(target);
    while (p.isWithin(folder, dir)) {
      if (await FileSystemEntity.isLink(dir)) return true;
      dir = p.dirname(dir);
    }
    return FileSystemEntity.isLink(target);
  }

  /// What came and was never put in place, a day on.
  Future<void> _clearStaging() async {
    try {
      final staging = Directory(
        p.join((await _net.inbox()).path, '.folio-senkron'),
      );
      if (!await staging.exists()) return;
      final old = DateTime.now().subtract(const Duration(days: 1));
      await for (final e in staging.list()) {
        if (e is File && (await e.lastModified()).isBefore(old)) {
          await e.delete();
        }
      }
    } catch (_) {}
  }

  static String _copyName(String path, String device) {
    final ext = p.extension(path);
    final stem = p.withoutExtension(path);
    final who = _safeName(device);
    var name = '$stem ($who)$ext';
    for (var n = 2; File(name).existsSync(); n++) {
      name = '$stem ($who $n)$ext';
    }
    return name;
  }

  Future<void> _toBin(SyncedFolder f, String rel) async {
    final from = _inside(f.path, rel);
    if (from == null) return;
    try {
      final now = DateTime.now();
      final day =
          '${now.year}-${'${now.month}'.padLeft(2, '0')}-${'${now.day}'.padLeft(2, '0')}';
      final dir = Directory(
        p.join((await _bin()).path, day, _safeName(f.name)),
      );
      await dir.create(recursive: true);
      var to = p.join(dir.path, p.basename(from));
      for (var n = 2; await File(to).exists(); n++) {
        to = p.join(
          dir.path,
          '${p.basenameWithoutExtension(from)} ($n)${p.extension(from)}',
        );
      }
      try {
        await File(from).rename(to);
      } on FileSystemException {
        await File(from).copy(to);
        await File(from).delete();
      }
    } catch (_) {}
  }

  /// What went to the bin more than thirty days ago is gone.
  Future<void> _emptyBin() async {
    try {
      final bin = await _bin();
      if (!await bin.exists()) return;
      final old = DateTime.now().subtract(binLife);
      await for (final day in bin.list()) {
        final when = DateTime.tryParse(p.basename(day.path));
        if (day is Directory && when != null && when.isBefore(old)) {
          await day.delete(recursive: true);
        }
      }
    } catch (_) {}
  }

  /// Where the bin is, to open it.
  Future<String> binPath() async => (await _bin()).path;
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';
import 'office_network.dart';

/// One delivery that came: who sent it, when, with what word, and where
/// its files are.
class InboxItem {
  const InboxItem({
    required this.id,
    required this.from,
    required this.device,
    required this.names,
    required this.paths,
    required this.size,
    required this.note,
    required this.at,
    this.withMessage = false,
    this.task,
  });

  final String id, from, device, note;
  final List<String> names, paths;
  final int size;
  final DateTime at;

  /// Came with a message: also in Mesajlar.
  final bool withMessage;

  /// The title of the task whose case it came with.
  final String? task;

  static InboxItem? fromLog(Map<String, Object?> e) {
    if (e['yon'] != 'gelen' || e['durum'] != 'done') return null;
    // Every delivery, but a folder's files kept alike: those have their
    // place and are no delivery; nor a voice message, which is heard in
    // its talk.
    if (e['tur'] == 'senkron') return null;
    final names = [for (final n in (e['dosyalar'] as List? ?? const [])) '$n'];
    if (e['tur'] == 'sohbet' &&
        names.isNotEmpty &&
        names.every((n) => n.toLowerCase().endsWith('.wav'))) {
      return null;
    }
    final at = DateTime.tryParse('${e['at']}');
    final id = e['id'];
    if (at == null || id is! String) return null;
    return InboxItem(
      id: id,
      from: '${e['kisi'] ?? ''}',
      device: '${e['cihaz'] ?? ''}',
      names: names,
      paths: [for (final n in (e['yollar'] as List? ?? const [])) '$n'],
      size: e['boyut'] is int ? e['boyut'] as int : 0,
      note: '${e['not'] ?? ''}',
      at: at.toLocal(),
      withMessage: e['tur'] == 'sohbet',
      task: e['tur'] == 'gorev' ? '${e['gorevAdi'] ?? 'görev'}' : null,
    );
  }
}

/// Gelenler: the files that came to this device, the newest first, and
/// which of them were opened; kept beside Folio's settings.
class OfficeInbox extends ChangeNotifier {
  OfficeInbox({OfficeNetwork? network, Future<File> Function()? file})
    : _net = network ?? OfficeNetwork.instance,
      _file = file ?? _default;

  static final instance = OfficeInbox();

  static Future<File> _default() async =>
      File(p.join((await folioSupportDirectory()).path, 'buro_gelenler.json'));

  final OfficeNetwork _net;
  final Future<File> Function() _file;
  final _seen = <String>{};

  /// Taken off Gelenler, their files deleted.
  final _gone = <String>{};

  /// Whether what comes is found in the archive's search too: off until
  /// the user says so, what comes may be confidential.
  bool searchable = false;
  List<InboxItem> _items = const [];
  bool _started = false;

  List<InboxItem> get items => _items;
  bool isNew(InboxItem i) => !_seen.contains(i.id);
  int get unread => _items.where(isNew).length;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final file = await _file();
      if (await file.exists()) {
        final j = jsonDecode(await file.readAsString());
        if (j is Map) {
          _seen.addAll([for (final s in (j['acilan'] as List? ?? [])) '$s']);
          _gone.addAll([for (final s in (j['silinen'] as List? ?? [])) '$s']);
          searchable = j['aramada'] == true;
        }
      }
    } catch (_) {}
    await reload();
    _net.arrived.addListener(_came);
  }

  Future<void> reload() async {
    _items = [
      for (final e in await _net.transferLog())
        if (InboxItem.fromLog(e) case final i? when !_gone.contains(i.id)) i,
    ];
    notifyListeners();
  }

  /// One that came now: shown at once, not when the record is written.
  void _came() {
    final t = _net.arrived.value;
    if (t == null) return;
    final item = InboxItem.fromLog({..._net.recordOf(t), 'durum': 'done'});
    if (item == null || _items.any((i) => i.id == item.id)) return;
    _items = [item, ..._items];
    notifyListeners();
  }

  Future<void> markRead(InboxItem i) async {
    if (!_seen.add(i.id)) return;
    notifyListeners();
    await _save();
  }

  /// "Okunmadı yap".
  Future<void> markUnread(InboxItem i) async {
    if (!_seen.remove(i.id)) return;
    notifyListeners();
    await _save();
  }

  /// "Sil": off Gelenler, and its files off the disk.
  Future<void> remove(InboxItem i) async {
    for (final path in i.paths) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    _gone.add(i.id);
    _items = [
      for (final x in _items)
        if (x.id != i.id) x,
    ];
    notifyListeners();
    await _save();
  }

  Future<void> setSearchable(bool on) async {
    searchable = on;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'acilan': _seen.toList(),
          'silinen': _gone.toList(),
          'aramada': searchable,
        }),
      );
    } catch (_) {}
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../models/document_model.dart';
import 'doc_model_json.dart';
import '../platform/app_directories.dart';

/// A letterhead the lawyer designed once, to head their documents with: a
/// header's paragraphs and pictures, kept at the quality they were put in.
class Letterhead {
  const Letterhead({
    required this.id,
    required this.name,
    required this.blocks,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final List<DocBlock> blocks;

  /// Put on every new document.
  final bool isDefault;

  bool get hasPicture => blocks.any((b) => b.type == DocBlockType.image);

  /// The first line of its text, to tell one from another in a list.
  String get summary => blocks
      .map((b) => b.plainText.trim())
      .firstWhere((t) => t.isNotEmpty, orElse: () => '');

  Letterhead copyWith({
    String? name,
    List<DocBlock>? blocks,
    bool? isDefault,
  }) => Letterhead(
    id: id,
    name: name ?? this.name,
    blocks: blocks ?? this.blocks,
    isDefault: isDefault ?? this.isDefault,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (isDefault) 'default': true,
    'header': DocModelJson.encode(DocModel(blocks: blocks)),
  };

  static Letterhead? fromJson(Map<String, Object?> json) {
    final id = json['id'], name = json['name'];
    final model = DocModelJson.decode(json['header']);
    if (id is! String || name is! String || model == null) return null;
    return Letterhead(
      id: id,
      name: name,
      blocks: model.blocks,
      isDefault: json['default'] == true,
    );
  }
}

/// The letterheads, in one file beside the kept passages, so they can be
/// backed up or taken to another machine without knowing the app.
class LetterheadStore extends ChangeNotifier {
  LetterheadStore({required this.file});

  /// One that never reaches the disk. Used by tests, where a real file write
  /// never finishes under the fake clock.
  @visibleForTesting
  LetterheadStore.memory() : file = File('') {
    _loaded = true;
  }

  final File file;
  var _all = <Letterhead>[];
  var _loaded = false;

  List<Letterhead> get all => List.unmodifiable(_all);

  Letterhead? get defaultOne => _all.where((one) => one.isDefault).firstOrNull;

  static LetterheadStore? _shared;

  static Future<LetterheadStore> shared() async {
    final already = _shared;
    if (already != null) {
      await already.load();
      return already;
    }
    final folder = await folioSupportDirectory();
    final store = LetterheadStore(
      file: File(p.join(folder.path, 'antetler.json')),
    );
    await store.load();
    return _shared = store;
  }

  @visibleForTesting
  static void useShared(LetterheadStore? store) => _shared = store;

  Future<void> load() async {
    if (_loaded) return;
    try {
      if (await file.exists()) {
        final read = jsonDecode(await file.readAsString());
        if (read is List) {
          _all = [
            for (final row in read)
              if (row is Map) ?Letterhead.fromJson(row.cast<String, Object?>()),
          ];
        }
      }
    } on Object {
      // A damaged file must not stop the editor opening; it is left on disk
      // rather than overwritten.
      _all = [];
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _write() async {
    if (file.path.isNotEmpty) {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode([for (final one in _all) one.toJson()]),
      );
    }
    notifyListeners();
  }

  Letterhead? byName(String name) {
    final want = name.trim().toLowerCase();
    return _all.where((one) => one.name.toLowerCase() == want).firstOrNull;
  }

  /// Keeps [blocks] as the letterhead called [name], in place of one already
  /// called so.
  Future<Letterhead> save(String name, List<DocBlock> blocks) async {
    final trimmed = name.trim().isEmpty ? 'Antet' : name.trim();
    final existing = byName(trimmed);
    final one =
        existing?.copyWith(name: trimmed, blocks: blocks) ??
        Letterhead(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
          name: trimmed,
          blocks: blocks,
          isDefault: _all.isEmpty,
        );
    _all = existing == null
        ? [..._all, one]
        : [for (final x in _all) x.id == one.id ? one : x];
    await _write();
    return one;
  }

  Future<void> rename(String id, String to) async {
    if (to.trim().isEmpty) return;
    _all = [for (final x in _all) x.id == id ? x.copyWith(name: to.trim()) : x];
    await _write();
  }

  Future<void> remove(String id) async {
    _all = [
      for (final x in _all)
        if (x.id != id) x,
    ];
    await _write();
  }

  /// Makes [id] the one new documents get, or none when null.
  Future<void> makeDefault(String? id) async {
    _all = [for (final x in _all) x.copyWith(isDefault: x.id == id)];
    await _write();
  }
}

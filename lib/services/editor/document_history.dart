import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';
import 'document_lock.dart';
import '../platform/atomic_file.dart';

class DocumentRevision {
  final String id, document, name, format, kind;
  final String? sourcePath;
  final DateTime created;
  final int size;
  final String digest;

  /// Whether the stored bytes are a UDF carrying an e-signature. Kept with the
  /// entry so the list can say so without opening every version.
  final bool signed;
  const DocumentRevision({
    required this.id,
    required this.document,
    required this.name,
    required this.format,
    required this.kind,
    required this.sourcePath,
    required this.created,
    required this.size,
    required this.digest,
    this.signed = false,
  });
  bool get recovery => kind == 'recovery';

  /// What the entry is, in the words the history list uses.
  String get kindLabel => switch (kind) {
    'original' => 'Üzerine yazılmadan önceki hali',
    'before-sign' => 'E-imzadan önceki hali',
    'signed' => 'E-imzalandı',
    'before-restore' => 'Geri yüklemeden önceki hali',
    'restored' => 'Eski sürüme döndürüldü',
    'recovery' => 'Kaydedilmemiş taslak',
    _ => 'Folio’da kaydedildi',
  };
  Map<String, Object?> toJson() => {
    'id': id,
    'document': document,
    'name': name,
    'format': format,
    'kind': kind,
    'sourcePath': sourcePath,
    'created': created.toIso8601String(),
    'size': size,
    'digest': digest,
    if (signed) 'signed': true,
  };
  factory DocumentRevision.fromJson(Map<String, dynamic> json) =>
      DocumentRevision(
        id: json['id'],
        document: json['document'],
        name: json['name'],
        format: json['format'],
        kind: json['kind'],
        sourcePath: json['sourcePath'],
        created: DateTime.parse(json['created']),
        size: json['size'],
        digest: json['digest'],
        signed: json['signed'] as bool? ?? false,
      );
}

/// Private, local snapshots. Publish metadata only after the immutable payload
/// has been flushed. A crash leaves either the previous or the new full draft.
class DocumentHistory {
  static DocumentHistory instance = DocumentHistory();
  final Directory? directory;
  final int maxVersions, maxBytes;
  Future<void> _tail = Future.value();
  Future<Directory>? _resolvedRoot;
  bool _protectedRoot = false;
  DocumentHistory({
    this.directory,
    this.maxVersions = 20,
    this.maxBytes = 100 * 1024 * 1024,
  });

  static String documentKey(String path) => sha256
      .convert(
        utf8.encode(
          Platform.isWindows
              ? p.normalize(p.absolute(path)).toLowerCase()
              : p.normalize(p.absolute(path)),
        ),
      )
      .toString();
  static String newKey() => 'new-${DateTime.now().microsecondsSinceEpoch}';

  /// A recovery slot of its own for one editor, for as long as it is open.
  ///
  /// Keyed by the document, as it used to be, a second session on the same
  /// file shared the first one's slot: opening the file again after a crash,
  /// or merely minimising the window with it open, replaced or deleted the
  /// draft the crash had left behind before anyone had looked at it.
  static String draftKey() =>
      'draft-${DateTime.now().microsecondsSinceEpoch}-${_draftCount++}';
  static int _draftCount = 0;

  /// Slots whose editor is open right now. Their drafts are work in progress,
  /// not something to recover: offering one sent the reader to a draft the
  /// open editor was about to replace or delete.
  static final _live = <String>{};

  /// The same, across windows: each editor window is a process of its own,
  /// and a draft one of them is writing is not another's to recover.
  static final _liveLocks = <String, Future<DocumentLock?>>{};

  static void holdDraft(String key) {
    _live.add(key);
    _liveLocks[key] = DocumentLock.acquire('taslak-$key')
        .catchError((Object _) => null);
  }

  static void releaseDraft(String key) {
    _live.remove(key);
    _liveLocks.remove(key)?.then((lock) => lock?.release());
    recoveryChanges.value++;
  }

  /// Whether the draft [key] is being written by an editor in another
  /// window. A lock that cannot be looked at says no: a draft offered twice
  /// is better than one never offered.
  static Future<bool> _openElsewhere(String key) async {
    try {
      return await DocumentLock.heldElsewhere('taslak-$key');
    } catch (_) {
      return false;
    }
  }

  /// Ticks when the drafts waiting to be recovered may have changed, so the
  /// count on the homepage's restore button follows without being polled.
  static final recoveryChanges = ValueNotifier<int>(0);

  Future<Directory> _root() => _resolvedRoot ??= _resolveRoot();
  Future<Directory> _resolveRoot() async =>
      directory ??
      Directory(
        p.join((await folioSupportDirectory()).path, 'document-history'),
      );
  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<List<DocumentRevision>> _list({
    String? document,
    bool recovery = false,
  }) async {
    final root = await _root();
    final folder = Directory(
      recovery
          ? p.join(root.path, 'recovery')
          : p.join(root.path, 'versions', document!),
    );
    if (!await folder.exists()) return [];
    final entries = <DocumentRevision>[];
    await for (final file in folder.list()) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      try {
        final item = DocumentRevision.fromJson(
          jsonDecode(await file.readAsString()),
        );
        if (!RegExp(r'^[a-z0-9-]+$').hasMatch(item.id) ||
            !RegExp(r'^[a-z0-9-]+$').hasMatch(item.document)) {
          continue;
        }
        if (document == null || item.document == document) entries.add(item);
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    entries.sort((a, b) => b.created.compareTo(a.created));
    return entries;
  }

  Future<List<DocumentRevision>> versions(String document) =>
      _serial(() => _list(document: document));

  /// Drafts waiting to be recovered, newest first. [includeOpen] lists the
  /// ones open editors are still writing as well.
  Future<List<DocumentRevision>> recoveries({bool includeOpen = false}) =>
      _serial(() async {
        final seen = <String>{};
        final out = <DocumentRevision>[];
        for (final e in await _list(recovery: true)) {
          if (!seen.add(e.document)) continue;
          if (!includeOpen &&
              (_live.contains(e.document) ||
                  await _openElsewhere(e.document))) {
            continue;
          }
          out.add(e);
        }
        return out;
      });

  /// Drafts left behind for the file at [path], newest first.
  Future<List<DocumentRevision>> recoveriesFor(String path) async {
    final key = documentKey(path);
    return [
      for (final entry in await recoveries())
        if (entry.sourcePath != null && documentKey(entry.sourcePath!) == key)
          entry,
    ];
  }

  Future<void> _remove(DocumentRevision entry) async {
    final root = await _root();
    final folder = entry.recovery
        ? 'recovery'
        : p.join('versions', entry.document);
    // Remove visibility first; an interrupted cleanup cannot expose no payload.
    for (final ext in ['json', 'bin']) {
      final file = File(p.join(root.path, folder, '${entry.id}.$ext'));
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> clearRecovery(String document) => _serial(() async {
    var removed = false;
    for (final entry in await _list(document: document, recovery: true)) {
      await _remove(entry);
      removed = true;
    }
    if (removed) recoveryChanges.value++;
  });
  Future<List<int>> read(DocumentRevision entry) => _serial(() async {
    final root = await _root();
    final bytes = await File(
      p.join(
        root.path,
        entry.recovery ? 'recovery' : p.join('versions', entry.document),
        '${entry.id}.bin',
      ),
    ).readAsBytes();
    if (bytes.length != entry.size ||
        await compute(_digest, bytes) != entry.digest) {
      throw const FormatException('Saklanan kopya eksik veya bozuk.');
    }
    return bytes;
  });
  Future<void> capture({
    required String document,
    required String name,
    required String? sourcePath,
    required String format,
    required List<int> bytes,
    String kind = 'saved',
  }) => _serial(() async {
    final recovery = kind == 'recovery';
    if (!recovery && bytes.length > maxBytes) {
      throw const FileSystemException(
        'Belge, geçmiş için ayrılan 100 MB sınırını aşıyor.',
      );
    }
    final previous = await _list(document: document, recovery: recovery);
    final (digest, signed) = await compute(_inspect, (
      bytes: bytes,
      udf: format.toLowerCase() == 'udf',
    ));
    if (previous.isNotEmpty &&
        previous.first.digest == digest &&
        previous.first.format == format &&
        previous.first.sourcePath == sourcePath) {
      return;
    }
    final now = DateTime.now();
    final entry = DocumentRevision(
      id: '${now.microsecondsSinceEpoch}-$document',
      document: document,
      name: name,
      format: format,
      kind: kind,
      sourcePath: sourcePath,
      created: now,
      size: bytes.length,
      digest: digest,
      signed: signed,
    );
    final root = await _root();
    await root.create(recursive: true);
    if (!_protectedRoot && (Platform.isLinux || Platform.isMacOS)) {
      await compute(_protectDirectory, root.path);
    }
    _protectedRoot = true;
    final folder = recovery
        ? p.join(root.path, 'recovery')
        : p.join(root.path, 'versions', document);
    await replaceFileIfChanged(File(p.join(folder, '${entry.id}.bin')), bytes);
    await replaceFileIfChanged(
      File(p.join(folder, '${entry.id}.json')),
      utf8.encode(jsonEncode(entry.toJson())),
    );
    var retainedBytes = entry.size;
    for (var i = 0; i < previous.length; i++) {
      retainedBytes += previous[i].size;
      if (recovery || i + 1 >= maxVersions || retainedBytes > maxBytes) {
        await _remove(previous[i]);
      }
    }
  });

  /// Puts a stored version back in place of the file at [path].
  ///
  /// What the file held until now is stored first, so going back is itself
  /// something the history can undo — a signed file included, byte for byte.
  Future<void> restoreToFile(DocumentRevision entry, String path) async {
    final bytes = await read(entry);
    final file = File(path);
    final format = p.extension(path).replaceFirst('.', '').toLowerCase();
    Future<void> keep(List<int> content, String kind) => capture(
      document: documentKey(path),
      name: p.basename(path),
      sourcePath: path,
      format: format,
      bytes: content,
      kind: kind,
    );
    if (await file.exists())
      await keep(await file.readAsBytes(), 'before-restore');
    await file.writeAsBytes(bytes, flush: true);
    await keep(bytes, 'restored');
  }

  static Future<void> _protectDirectory(String path) async {
    final result = await Process.run('chmod', ['700', path]);
    if (result.exitCode != 0) {
      throw FileSystemException('Geçmiş dizini korunamadı', path);
    }
  }

  static String _digest(List<int> bytes) => sha256.convert(bytes).toString();

  static (String, bool) _inspect(({List<int> bytes, bool udf}) input) {
    var signed = false;
    if (input.udf) {
      try {
        signed = ZipDecoder()
            .decodeBytes(input.bytes)
            .files
            .any(
              (file) => file.isFile && file.name.toLowerCase() == 'sign.sgn',
            );
      } catch (_) {
        // Not a readable archive: nothing to say about a signature.
      }
    }
    return (_digest(input.bytes), signed);
  }
}

/// Throttled rather than debounced: continuous typing still reaches disk.
/// Generation checks and one queue prevent a pending write from resurrecting a
/// draft after an explicit save/discard. No document serialization on selection.
class DraftRecovery {
  final Future<void> Function() write;
  final Future<void> Function() remove;
  final void Function(Object) onError;
  final Duration delay;
  Timer? _timer;
  Future<void> _tail = Future.value();
  int _generation = 0;
  bool _disposed = false;
  DraftRecovery({
    required this.write,
    required this.remove,
    required this.onError,
    this.delay = const Duration(seconds: 10),
  });
  void changed() {
    if (_disposed) return;
    _timer ??= Timer(delay, () {
      _timer = null;
      flush();
    });
  }

  /// Writes the draft now. False when writing failed, which [onError] has
  /// already been told about.
  Future<bool> flush() {
    _timer?.cancel();
    _timer = null;
    final generation = _generation;
    final written = _tail
        .then((_) async {
          if (!_disposed && generation == _generation) await write();
          return true;
        })
        .catchError((Object e) {
          onError(e);
          return false;
        });
    _tail = written;
    return written;
  }

  Future<void> clear() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _tail = _tail.then((_) => remove()).catchError((Object e) {
      onError(e);
    });
    return _tail;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}

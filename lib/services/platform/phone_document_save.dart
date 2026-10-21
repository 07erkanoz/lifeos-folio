import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_directories.dart';
import 'viewer_file_types.dart';

/// A phone saves through the system's own save screen, which never writes
/// over the file a document came from: Android returns content URIs, not
/// filesystem paths, and an iPhone's Files screen copies a file Folio has
/// already written (its export takes a file, not a place to write one).
/// Either way a readable local copy is kept for preview and history, and
/// published through the system's picker.
class PhoneDocumentSave {
  static const channel = MethodChannel('lifeos_evrak/documents');

  /// Whether documents are saved this way here: on a phone.
  static bool get here => Platform.isAndroid || Platform.isIOS;

  static String _mimeOf(String fileName) {
    final extension = p.extension(fileName).replaceFirst('.', '').toLowerCase();
    final type = ViewerFileType.supported
        .where((type) => type.extensions.contains(extension))
        .firstOrNull;
    return type?.mimeTypes.first ?? 'application/octet-stream';
  }

  /// The readable local copy a save keeps, in a folder of its own.
  static Future<(Directory, File)> _copy(
    String fileName,
    List<int> bytes,
    Directory? supportDirectory,
  ) async {
    final root = Directory(
      p.join(
        (supportDirectory ?? await folioSupportDirectory()).path,
        'saved-documents',
      ),
    );
    await root.create(recursive: true);
    final directory = await root.createTemp('document-');
    final file = File(p.join(directory.path, p.basename(fileName)));
    await file.writeAsBytes(bytes, flush: true);
    return (directory, file);
  }

  /// Saved into the folder chosen for it ([PhoneSaveFolder]), under its own
  /// name, over one of that name: no save screen. The local copy, and where
  /// it went as the lawyer would look for it ("Dilekçeler/İtiraz.udf").
  static Future<({String path, String shown})> saveToFolder({
    required String fileName,
    required List<int> bytes,
    required PhoneSaveFolder folder,
    Directory? supportDirectory,
  }) async {
    final (directory, file) = await _copy(fileName, bytes, supportDirectory);
    try {
      final shown = await folder.write(
        file.path,
        name: p.basename(fileName),
        mimeType: _mimeOf(fileName),
      );
      return (path: file.path, shown: shown);
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  /// An iPhone: a signed document copied into Folio's own folder, which the
  /// Files app shows ("On My iPhone > LifeOS Folio"; UIFileSharingEnabled):
  /// the signature is put on Folio's private copy, where nothing else
  /// looks (21 Ekim 2026). Where it went, as the lawyer would look for it.
  static Future<String> keepSignedInFiles(
    String path, {
    Directory? documents,
  }) async {
    final base = documents ?? await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(base.path, signedFolder));
    await folder.create(recursive: true);
    await File(path).copy(p.join(folder.path, p.basename(path)));
    return 'LifeOS Folio/$signedFolder/${p.basename(path)}';
  }

  static const signedFolder = 'İmzalı Belgeler';

  static Future<String?> save({
    required String fileName,
    required List<int> bytes,
    Directory? supportDirectory,
  }) async {
    final (directory, file) = await _copy(fileName, bytes, supportDirectory);
    var published = false;
    try {
      final String? uri;
      if (Platform.isIOS) {
        // The Files screen, given the copy written here: the lawyer chooses
        // where it goes (ios/Runner/AppDelegate.swift, exportDocument).
        // Not file_picker's, which writes over a document of the same name
        // in Folio's own folder first.
        uri = await channel.invokeMethod<String>('exportDocument', file.path);
      } else {
        uri = await channel.invokeMethod<String>('saveDocument', {
          'path': file.path,
          'mimeType': _mimeOf(fileName),
        });
      }
      if (uri == null) return null;
      published = true;
      return file.path;
    } finally {
      if (!published) await directory.delete(recursive: true);
    }
  }
}

/// The folder a phone saves documents into, chosen once with a lasting grant
/// to write it (Android's ACTION_OPEN_DOCUMENT_TREE; android SaveFolder.kt).
/// The save screen asked again at every save, and a document signed in
/// Folio stayed in Folio's own folder, where the file manager does not look
/// (21 Ekim 2026). Kept beside Folio's data: the folder's address and name.
class PhoneSaveFolder {
  PhoneSaveFolder({Future<File> Function()? file, MethodChannel? channel})
    : _file = file ?? _defaultFile,
      _channel = channel ?? PhoneDocumentSave.channel;

  static PhoneSaveFolder instance = PhoneSaveFolder();

  /// Only Android grants a folder for good; an iPhone's Files screen does
  /// not keep one.
  static bool get available => Platform.isAndroid;

  static Future<File> _defaultFile() async =>
      File(p.join((await folioSupportDirectory()).path, 'kayit-klasoru.json'));

  final Future<File> Function() _file;
  final MethodChannel _channel;

  /// The folder chosen, while it may still be written to; null when none
  /// is, or its grant was taken back.
  Future<({String uri, String name})?> current() async {
    try {
      final json = jsonDecode(await (await _file()).readAsString());
      if (json is! Map || json['uri'] is! String) return null;
      final uri = json['uri'] as String;
      final usable = await _channel.invokeMethod<bool>('saveFolderUsable', {
        'uri': uri,
      });
      if (usable != true) return null;
      return (uri: uri, name: '${json['ad'] ?? 'Klasör'}');
    } catch (_) {
      return null;
    }
  }

  /// The system's folder screen; null when nothing was chosen.
  Future<({String uri, String name})?> choose() async {
    final chosen = await _channel.invokeMapMethod<String, Object?>(
      'pickSaveFolder',
    );
    final uri = chosen?['uri'];
    if (uri is! String) return null;
    final name = '${chosen?['name'] ?? 'Klasör'}';
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({'uri': uri, 'ad': name}));
    return (uri: uri, name: name);
  }

  /// [path], one of Folio's saved copies, written into the folder as
  /// [name]; where it went, "Dilekçeler/İtiraz.udf".
  Future<String> write(
    String path, {
    required String name,
    required String mimeType,
  }) async {
    final folder = await current();
    if (folder == null) {
      throw StateError('Kayıt klasörüne yazılamıyor; klasörü yeniden seçin.');
    }
    final shown = await _channel.invokeMethod<String>('writeToSaveFolder', {
      'uri': folder.uri,
      'path': path,
      'name': name,
      'mimeType': mimeType,
    });
    return shown ?? '${folder.name}/$name';
  }
}

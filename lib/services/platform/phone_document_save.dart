import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

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

  static Future<String?> save({
    required String fileName,
    required List<int> bytes,
    Directory? supportDirectory,
  }) async {
    final root = Directory(
      p.join(
        (supportDirectory ?? await folioSupportDirectory()).path,
        'saved-documents',
      ),
    );
    await root.create(recursive: true);
    final directory = await root.createTemp('document-');
    final file = File(p.join(directory.path, p.basename(fileName)));
    var published = false;
    try {
      await file.writeAsBytes(bytes, flush: true);
      final extension = p
          .extension(fileName)
          .replaceFirst('.', '')
          .toLowerCase();
      final type = ViewerFileType.supported
          .where((type) => type.extensions.contains(extension))
          .firstOrNull;
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
          'mimeType': type?.mimeTypes.first ?? 'application/octet-stream',
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

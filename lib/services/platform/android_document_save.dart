import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'app_directories.dart';
import 'viewer_file_types.dart';

/// Android returns content URIs, not filesystem paths. Keep a readable local
/// copy for preview/history and publish it through the system document picker.
class AndroidDocumentSave {
  static const channel = MethodChannel('lifeos_evrak/documents');

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
      final uri = await channel.invokeMethod<String>('saveDocument', {
        'path': file.path,
        'mimeType': type?.mimeTypes.first ?? 'application/octet-stream',
      });
      if (uri == null) return null;
      published = true;
      return file.path;
    } finally {
      if (!published) await directory.delete(recursive: true);
    }
  }
}

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Transfers the saved original file. No conversion, upload or editor serialization.
class FileActions {
  static const channel = MethodChannel('lifeos_evrak/file_actions');

  static String mimeType(String path) => switch (p
      .extension(path)
      .toLowerCase()) {
    '.xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    '.udf' => 'application/x-uyap-udf',
    '.pdf' => 'application/pdf',
    '.docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.odt' => 'application/vnd.oasis.opendocument.text',
    '.html' || '.htm' => 'text/html',
    '.md' || '.markdown' => 'text/markdown',
    '.csv' => 'text/csv',
    '.tsv' => 'text/tab-separated-values',
    '.json' => 'application/json',
    '.xml' => 'application/xml',
    '.svg' => 'image/svg+xml',
    '.png' => 'image/png',
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.gif' => 'image/gif',
    '.webp' => 'image/webp',
    '.bmp' => 'image/bmp',
    '.tif' || '.tiff' => 'image/tiff',
    '.txt' || '.log' => 'text/plain',
    '.ics' => 'text/calendar',
    _ => 'application/octet-stream',
  };

  static Future<void> invoke(String action, String path) async {
    final file = File(path).absolute;
    if (!await file.exists()) {
      throw const FileSystemException('Belge bulunamadı.');
    }
    await channel.invokeMethod<void>(action, {
      'path': file.path,
      'mimeType': mimeType(file.path),
    });
  }

  /// Several files at once: the gallery's chosen photographs.
  static Future<void> shareMany(List<String> paths) async {
    if (paths.length == 1) return invoke('share', paths.single);
    for (final path in paths) {
      if (!await File(path).exists()) {
        throw const FileSystemException('Belge bulunamadı.');
      }
    }
    await channel.invokeMethod<void>('shareMany', {
      'paths': [for (final path in paths) File(path).absolute.path],
    });
  }

  static Future<void> composeEmail(String path) async {
    if (!Platform.isLinux) return invoke('email', path);
    final file = File(path).absolute;
    if (!await file.exists()) {
      throw const FileSystemException('Belge bulunamadı.');
    }
    try {
      final result = await Process.run('xdg-email', [
        '--utf8',
        '--attach',
        file.path,
      ]);
      if (result.exitCode != 0) {
        throw const FileSystemException(
          'E-posta uygulaması açılamadı. Dosyayı kopyalayıp e-postanıza ekleyebilirsiniz.',
        );
      }
    } on ProcessException {
      throw const FileSystemException(
        'E-posta uygulaması bulunamadı. Dosyayı kopyalayıp e-postanıza ekleyebilirsiniz.',
      );
    }
  }

  static Future<String> copyToDirectory(String path, String directory) async {
    final source = File(path);
    if (!await source.exists()) {
      throw const FileSystemException('Belge bulunamadı.');
    }
    final destination = Directory(directory);
    if (!await destination.exists()) {
      throw const FileSystemException('Hedef klasör bulunamadı.');
    }
    final name = p.basenameWithoutExtension(path);
    final extension = p.extension(path);
    var target = p.join(directory, p.basename(path));
    for (
      var suffix = 2;
      await FileSystemEntity.type(target) != FileSystemEntityType.notFound;
      suffix++
    ) {
      target = p.join(directory, '$name ($suffix)$extension');
    }
    await source.copy(target);
    return target;
  }
}

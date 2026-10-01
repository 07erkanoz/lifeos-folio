import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

String fontKey(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');

class SystemFontCatalog {
  static Future<Map<String, Map<String, String>>>? _pending;
  static Future<Map<String, Map<String, String>>> load() =>
      _pending ??= compute(_scan, null);
}

/// Read only SFNT headers/name tables, not the full font files. Runs off the UI thread.
Map<String, Map<String, String>> _scan(void _) {
  final home = Platform.environment['HOME'];
  final roots = Platform.isWindows
      ? [
          p.join(Platform.environment['WINDIR'] ?? r'C:\Windows', 'Fonts'),
          if (Platform.environment['LOCALAPPDATA'] != null)
            p.join(
              Platform.environment['LOCALAPPDATA']!,
              'Microsoft',
              'Windows',
              'Fonts',
            ),
        ]
      : Platform.isAndroid
      ? ['/system/fonts']
      : Platform.isMacOS
      ? [
          '/System/Library/Fonts',
          '/Library/Fonts',
          if (home != null) '$home/Library/Fonts',
        ]
      : [
          '/usr/share/fonts',
          '/usr/local/share/fonts',
          if (home != null) '$home/.fonts',
          if (home != null) '$home/.local/share/fonts',
        ];
  final result = <String, Map<String, String>>{};
  for (final root in roots) {
    try {
      final directory = Directory(root);
      if (!directory.existsSync()) continue;
      for (final file in directory.listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (file is! File || p.extension(file.path).toLowerCase() != '.ttf') {
          continue;
        }
        try {
          final info = readFontName(file);
          if (info == null) continue;
          final styles = result.putIfAbsent(info.$1, () => {});
          styles.putIfAbsent(info.$2, () => file.path);
        } catch (_) {
          /* Unsupported or inaccessible fonts use the bundled fallback. */
        }
      }
    } on FileSystemException {
      /* Keep other system/user font locations. */
    }
  }
  return result;
}

/// Supports TrueType outlines consumed by both Flutter and the PDF writer.
(String, String)? readFontName(File file) {
  final handle = file.openSync();
  try {
    final header = handle.readSync(12);
    if (header.length < 12) return null;
    final head = ByteData.sublistView(header);
    if (head.getUint32(0) != 0x00010000 && head.getUint32(0) != 0x74727565) {
      return null;
    }
    final count = head.getUint16(4);
    if (count > 256) return null;
    final records = handle.readSync(count * 16);
    if (records.length != count * 16) return null;
    final tables = ByteData.sublistView(records);
    for (var i = 0; i < count; i++) {
      final offset = i * 16;
      if (tables.getUint32(offset) != 0x6e616d65) continue;
      final size = tables.getUint32(offset + 12);
      if (size < 6 || size > 1024 * 1024) return null;
      handle.setPositionSync(tables.getUint32(offset + 8));
      final bytes = handle.readSync(size);
      if (bytes.length != size) return null;
      final data = ByteData.sublistView(bytes);
      final names = <int, String>{};
      final start = data.getUint16(4);
      for (var n = 0; n < data.getUint16(2); n++) {
        final at = 6 + n * 12;
        if (at + 12 > size) break;
        final platform = data.getUint16(at);
        final id = data.getUint16(at + 6);
        if (![1, 2, 16, 17].contains(id)) continue;
        final length = data.getUint16(at + 8);
        final from = start + data.getUint16(at + 10);
        if (from + length > size) continue;
        final value = platform == 0 || platform == 3
            ? String.fromCharCodes([
                for (var j = from; j + 1 < from + length; j += 2)
                  data.getUint16(j),
              ])
            : String.fromCharCodes(bytes.sublist(from, from + length));
        if (value.trim().isEmpty) continue;
        if (!names.containsKey(id) ||
            (platform == 3 && data.getUint16(at + 4) == 0x0409)) {
          names[id] = value.trim();
        }
      }
      final family = names[16] ?? names[1];
      if (family == null) return null;
      final style = (names[17] ?? names[2] ?? '').toLowerCase();
      final bold = style.contains('bold');
      final italic = style.contains('italic') || style.contains('oblique');
      // Other weights stay available via their legacy family rather than silently
      // replacing the regular face in a four-style document family.
      final variant =
          style.contains('light') ||
          style.contains('black') ||
          style.contains('medium') ||
          style.contains('thin') ||
          style.contains('condensed');
      return (
        variant ? names[1] ?? family : family,
        bold
            ? (italic ? 'BoldItalic' : 'Bold')
            : (italic ? 'Italic' : 'Regular'),
      );
    }
    return null;
  } finally {
    handle.closeSync();
  }
}

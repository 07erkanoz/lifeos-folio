import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A UETS notice's package (EYP, the e-correspondence package): a zip
/// whose envelope is `UstYazi/*.pdf`, its documents under `Ekler/`, its
/// metadata `Ustveri/Ustveri.xml`, and its signatures beside. Read with
/// limits, so that a damaged or hostile package is an error, never a
/// hang, and never a file written outside its folder.
class EypPackage {
  EypPackage._(this.envelope, this.attachments, this.metadata);

  /// The envelope's PDF: the court's or the office's letter that says what
  /// the notice is and what is to be done. Null when the package has none.
  final EypEntry? envelope;

  /// The documents, in the package's order (`EK-1`, `EK-2`…).
  final List<EypEntry> attachments;

  /// `Ustveri.xml`, the package's own description; null when absent.
  final EypEntry? metadata;

  /// The package as UETS sends it, before it is opened.
  static const maxPackageBytes = 200 * 1024 * 1024;
  static const maxEntries = 400;
  static const maxTotalBytes = 300 * 1024 * 1024;
  static const maxEntryBytes = 120 * 1024 * 1024;

  /// [bytes] read. Throws [FormatException] for what is not a package, is
  /// too large, or names a path that would leave its folder.
  static EypPackage read(Uint8List bytes) {
    if (bytes.length > maxPackageBytes) {
      throw const FormatException('Tebligat paketi çok büyük.');
    }
    // A zip begins "PK"; the decoder takes anything else for an empty one.
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw const FormatException('Tebligat paketi bir zip değil.');
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('Tebligat paketi açılamadı.');
    }
    final files = archive.files.where((f) => f.isFile).toList();
    if (files.isEmpty) {
      throw const FormatException('Tebligat paketi boş.');
    }
    if (files.length > maxEntries) {
      throw const FormatException('Tebligat paketinde çok fazla dosya var.');
    }
    var total = 0;
    EypEntry? envelope, metadata;
    final attachments = <EypEntry>[];
    for (final f in files) {
      final path = f.name.replaceAll('\\', '/');
      if (!_safe(path)) {
        throw FormatException('Tebligat paketinde geçersiz bir yol var: $path');
      }
      if (f.size > maxEntryBytes) {
        throw const FormatException(
          'Tebligat paketinde çok büyük bir dosya var.',
        );
      }
      total += f.size;
      if (total > maxTotalBytes) {
        throw const FormatException('Tebligat paketi çok büyük.');
      }
      final parts = path.split('/');
      final folder = parts.length > 1
          ? parts[parts.length - 2].toLowerCase()
          : '';
      final name = parts.last;
      final lower = name.toLowerCase();
      EypEntry entry() => EypEntry(path, name, Uint8List.fromList(f.content));
      if (folder == 'ustyazi' && lower.endsWith('.pdf')) {
        envelope ??= entry();
      } else if (folder == 'ekler') {
        attachments.add(entry());
      } else if (folder == 'ustveri' && lower.endsWith('.xml')) {
        metadata ??= entry();
      }
    }
    attachments.sort((a, b) => _order(a.name).compareTo(_order(b.name)));
    return EypPackage._(envelope, attachments, metadata);
  }

  /// No absolute path, no drive, no step up out of the package.
  static bool _safe(String path) =>
      path.isNotEmpty &&
      !path.startsWith('/') &&
      !RegExp(r'^[A-Za-z]:').hasMatch(path) &&
      !path.split('/').any((s) => s == '..');

  /// `EK-12` after `EK-2`.
  static int _order(String name) {
    final m = RegExp(r'(\d+)').firstMatch(name);
    return m == null ? 1 << 30 : int.parse(m.group(1)!);
  }
}

class EypEntry {
  final String path;
  final String name;
  final Uint8List bytes;
  const EypEntry(this.path, this.name, this.bytes);
}

import 'dart:typed_data';

/// Reads the container that Word 97-2003 files are packed in.
///
/// A `.doc` is not one file but a little filesystem — Microsoft's Compound
/// File Binary, the same one `.xls` and `.msg` use. It has a sector table, a
/// directory, and a second smaller allocation for the streams under 4 KB.
/// None of that is on pub.dev, and the Word reader needs two of its streams.
class CfbFile {
  final Map<String, Uint8List> streams;
  const CfbFile(this.streams);

  static const _signature = [
    0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1, //
  ];

  static bool looksLikeCfb(List<int> bytes) {
    if (bytes.length < 512) return false;
    for (var i = 0; i < _signature.length; i++) {
      if (bytes[i] != _signature[i]) return false;
    }
    return true;
  }

  static CfbFile? parse(List<int> input) {
    if (!looksLikeCfb(input)) return null;
    try {
      return _Cfb(Uint8List.fromList(input)).read();
    } catch (_) {
      return null;
    }
  }
}

class _Cfb {
  final Uint8List bytes;
  late final ByteData data = ByteData.sublistView(bytes);

  /// End of a sector chain, and an unallocated sector.
  static const endOfChain = 0xfffffffe;
  static const free = 0xffffffff;

  late int sectorSize;
  late int miniSectorSize;
  late int miniCutoff;
  final fat = <int>[];
  final miniFat = <int>[];

  _Cfb(this.bytes);

  int _offset(int sector) => (sector + 1) * sectorSize;

  CfbFile read() {
    sectorSize = 1 << data.getUint16(0x1e, Endian.little);
    miniSectorSize = 1 << data.getUint16(0x20, Endian.little);
    if (sectorSize < 128 || sectorSize > 1 << 20 || miniSectorSize < 8) {
      throw const FormatException('Sektör boyutu geçersiz.');
    }
    final fatCount = data.getUint32(0x2c, Endian.little);
    final directoryStart = data.getUint32(0x30, Endian.little);
    miniCutoff = data.getUint32(0x38, Endian.little);
    final miniFatStart = data.getUint32(0x3c, Endian.little);
    final difatStart = data.getUint32(0x44, Endian.little);
    final difatCount = data.getUint32(0x48, Endian.little);
    final perSector = sectorSize ~/ 4;

    // Which sectors hold the allocation table: 109 of them are named in the
    // header, and the rest are chained through sectors of their own.
    final fatSectors = <int>[];
    for (var i = 0; i < 109 && fatSectors.length < fatCount; i++) {
      final sector = data.getUint32(0x4c + i * 4, Endian.little);
      if (sector == endOfChain || sector == free) break;
      fatSectors.add(sector);
    }
    var difat = difatStart;
    for (
      var i = 0;
      i < difatCount && difat != endOfChain && difat != free;
      i++
    ) {
      final base = _offset(difat);
      if (base + sectorSize > bytes.length) break;
      for (var j = 0; j < perSector - 1; j++) {
        final sector = data.getUint32(base + j * 4, Endian.little);
        if (sector == endOfChain || sector == free) break;
        fatSectors.add(sector);
      }
      difat = data.getUint32(base + (perSector - 1) * 4, Endian.little);
    }
    for (final sector in fatSectors) {
      final base = _offset(sector);
      if (base + sectorSize > bytes.length) break;
      for (var i = 0; i < perSector; i++) {
        fat.add(data.getUint32(base + i * 4, Endian.little));
      }
    }
    if (fat.isEmpty) throw const FormatException('Yerleşim tablosu boş.');

    var sector = miniFatStart;
    var guard = 0;
    while (sector != endOfChain && sector != free && sector < fat.length) {
      if (guard++ > 1 << 20) break;
      final base = _offset(sector);
      if (base + sectorSize > bytes.length) break;
      for (var i = 0; i < perSector; i++) {
        miniFat.add(data.getUint32(base + i * 4, Endian.little));
      }
      sector = fat[sector];
    }

    final directory = _chain(directoryStart, 1 << 28);
    final entries = <({String name, int type, int start, int size})>[];
    for (var at = 0; at + 128 <= directory.length; at += 128) {
      final view = ByteData.sublistView(directory, at, at + 128);
      final nameLength = view.getUint16(0x40, Endian.little);
      final type = view.getUint8(0x42);
      if (nameLength < 2 || nameLength > 64 || type == 0) continue;
      final units = <int>[];
      for (var i = 0; i + 1 < nameLength - 1; i += 2) {
        units.add(view.getUint16(i, Endian.little));
      }
      entries.add((
        name: String.fromCharCodes(units),
        type: type,
        start: view.getUint32(0x74, Endian.little),
        size: view.getUint32(0x78, Endian.little),
      ));
    }

    // The root entry doubles as the place the small streams are kept.
    final root = entries.where((e) => e.type == 5).firstOrNull;
    final host = root == null ? Uint8List(0) : _chain(root.start, root.size);

    final streams = <String, Uint8List>{};
    for (final entry in entries) {
      if (entry.type != 2 || entry.size == 0) continue;
      streams[entry.name] = entry.size < miniCutoff
          ? _miniChain(entry.start, entry.size, host)
          : _chain(entry.start, entry.size);
    }
    return CfbFile(streams);
  }

  Uint8List _chain(int start, int size) {
    final out = BytesBuilder();
    var sector = start;
    var guard = 0;
    while (sector != endOfChain && sector != free && sector < fat.length) {
      if (guard++ > 1 << 22 || out.length >= size) break;
      final base = _offset(sector);
      if (base >= bytes.length) break;
      final end = base + sectorSize > bytes.length
          ? bytes.length
          : base + sectorSize;
      out.add(bytes.sublist(base, end));
      sector = fat[sector];
    }
    final all = out.takeBytes();
    return all.length > size ? all.sublist(0, size) : all;
  }

  Uint8List _miniChain(int start, int size, Uint8List host) {
    final out = BytesBuilder();
    var sector = start;
    var guard = 0;
    while (sector != endOfChain && sector != free && sector < miniFat.length) {
      if (guard++ > 1 << 22 || out.length >= size) break;
      final base = sector * miniSectorSize;
      if (base >= host.length) break;
      final end = base + miniSectorSize > host.length
          ? host.length
          : base + miniSectorSize;
      out.add(host.sublist(base, end));
      sector = miniFat[sector];
    }
    final all = out.takeBytes();
    return all.length > size ? all.sublist(0, size) : all;
  }
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/doc/cfb_reader.dart';
import 'package:evrak_convert/services/doc/doc_reader.dart';

/// Builds a Word 97 file the way Word does: a compound-file container holding
/// a WordDocument stream and the table stream its piece table lives in.
///
/// Writing one by hand is the only way to test the reader without shipping a
/// binary fixture, and it pins down the parts that are easy to get wrong —
/// which stream the flags point at, and how a piece's offset is stored.
Uint8List buildDoc({
  required List<int> textBytes,
  required bool wide,
  bool useOneTable = true,
}) {
  const sectorSize = 512;

  // The WordDocument stream: a FIB, then the text at a known offset.
  final word = Uint8List(4096);
  final fib = ByteData.sublistView(word);
  fib.setUint16(0x00, 0xa5ec, Endian.little); // wIdent
  fib.setUint16(0x02, 193, Endian.little); // nFib, Word 97
  fib.setUint16(0x0a, useOneTable ? 0x0200 : 0x0000, Endian.little);
  const textAt = 1024;
  fib.setUint32(0x18, textAt, Endian.little); // fcMin
  fib.setUint32(0x1c, textAt + textBytes.length, Endian.little); // fcMac
  word.setRange(textAt, textAt + textBytes.length, textBytes);

  // The counted arrays that follow the fixed head, then the file positions.
  var at = 32;
  fib.setUint16(at, 0, Endian.little); // csw
  at += 2;
  fib.setUint16(at, 0, Endian.little); // cslw
  at += 2;
  fib.setUint16(at, 40, Endian.little); // cbRgFcLcb
  at += 2;
  const clxIndex = 33;
  final characters = wide ? textBytes.length ~/ 2 : textBytes.length;

  // The piece table: one piece covering the whole text.
  final clx = BytesBuilder()
    ..add([0x02])
    ..add(_uint32(4 + 8 + 4)) // one CP pair plus one descriptor
    ..add(_uint32(0))
    ..add(_uint32(characters))
    ..add([0, 0])
    ..add(_uint32(wide ? textAt : (textAt * 2) | 0x40000000))
    ..add([0, 0]);
  final table = clx.takeBytes();
  fib.setUint32(at + clxIndex * 8, 0, Endian.little); // fcClx
  fib.setUint32(at + clxIndex * 8 + 4, table.length, Endian.little); // lcbClx

  return _container({
    'WordDocument': word,
    useOneTable ? '1Table' : '0Table': table,
  }, sectorSize);
}

List<int> _uint32(int value) => [
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
  (value >> 24) & 0xff,
];

/// A compound file holding the given streams.
///
/// Streams smaller than 4 KB go in the mini stream, which is where a real
/// Word file keeps its table stream — and the reader has to look there.
Uint8List _container(Map<String, Uint8List> streams, int sectorSize) {
  const miniUnit = 64;
  const cutoff = 4096;
  final big = [
    for (final e in streams.entries)
      if (e.value.length >= cutoff) e.key,
  ];
  final small = [
    for (final e in streams.entries)
      if (e.value.length < cutoff) e.key,
  ];

  // Pack the small streams into one byte array, each starting on a boundary.
  final miniAt = <String, int>{};
  final mini = BytesBuilder();
  for (final name in small) {
    miniAt[name] = mini.length ~/ miniUnit;
    mini.add(streams[name]!);
    while (mini.length % miniUnit != 0) {
      mini.addByte(0);
    }
  }
  final miniHost = mini.takeBytes();

  final sectorsFor = <String, int>{};
  var next = 0;
  int take(int bytes) {
    final start = next;
    next += (bytes + sectorSize - 1) ~/ sectorSize;
    return start;
  }

  for (final name in big) {
    sectorsFor[name] = take(streams[name]!.length);
  }
  final miniStart = miniHost.isEmpty ? 0xfffffffe : take(miniHost.length);
  final miniFatStart = small.isEmpty ? 0xfffffffe : take(4);
  final directoryStart = take((streams.length + 1) * 128);
  final fatStart = take(4);
  final out = Uint8List((next + 1) * sectorSize);
  final data = ByteData.sublistView(out);

  out.setRange(0, 8, [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]);
  data.setUint16(0x1e, 9, Endian.little);
  data.setUint16(0x20, 6, Endian.little);
  data.setUint32(0x2c, 1, Endian.little);
  data.setUint32(0x30, directoryStart, Endian.little);
  data.setUint32(0x38, cutoff, Endian.little);
  data.setUint32(0x3c, miniFatStart, Endian.little);
  data.setUint32(0x40, small.isEmpty ? 0 : 1, Endian.little);
  data.setUint32(0x44, 0xfffffffe, Endian.little);
  data.setUint32(0x48, 0, Endian.little);
  for (var i = 0; i < 109; i++) {
    data.setUint32(0x4c + i * 4, i == 0 ? fatStart : 0xffffffff, Endian.little);
  }

  final fat = List<int>.filled(sectorSize ~/ 4, 0xffffffff);
  void chain(int start, int bytes) {
    final count = (bytes + sectorSize - 1) ~/ sectorSize;
    for (var i = 0; i < count; i++) {
      fat[start + i] = i == count - 1 ? 0xfffffffe : start + i + 1;
    }
  }

  void put(int sector, List<int> value) => out.setRange(
    (sector + 1) * sectorSize,
    (sector + 1) * sectorSize + value.length,
    value,
  );

  for (final name in big) {
    chain(sectorsFor[name]!, streams[name]!.length);
    put(sectorsFor[name]!, streams[name]!);
  }
  if (miniHost.isNotEmpty) {
    chain(miniStart, miniHost.length);
    put(miniStart, miniHost);
    // Each small stream is one chain of 64-byte units inside that array.
    final miniFat = List<int>.filled(sectorSize ~/ 4, 0xffffffff);
    for (final name in small) {
      final units = (streams[name]!.length + miniUnit - 1) ~/ miniUnit;
      for (var i = 0; i < units; i++) {
        miniFat[miniAt[name]! + i] = i == units - 1
            ? 0xfffffffe
            : miniAt[name]! + i + 1;
      }
    }
    chain(miniFatStart, 4);
    for (var i = 0; i < miniFat.length; i++) {
      data.setUint32(
        (miniFatStart + 1) * sectorSize + i * 4,
        miniFat[i],
        Endian.little,
      );
    }
  }
  chain(directoryStart, (streams.length + 1) * 128);
  chain(fatStart, 4);
  for (var i = 0; i < fat.length; i++) {
    data.setUint32((fatStart + 1) * sectorSize + i * 4, fat[i], Endian.little);
  }

  void entry(int index, String name, int type, int start, int size) {
    final base = (directoryStart + 1) * sectorSize + index * 128;
    for (var i = 0; i < name.length; i++) {
      data.setUint16(base + i * 2, name.codeUnitAt(i), Endian.little);
    }
    data.setUint16(base + 0x40, (name.length + 1) * 2, Endian.little);
    data.setUint8(base + 0x42, type);
    data.setUint32(base + 0x74, start, Endian.little);
    data.setUint32(base + 0x78, size, Endian.little);
  }

  entry(0, 'Root Entry', 5, miniStart, miniHost.length);
  var index = 1;
  for (final name in streams.keys) {
    entry(
      index++,
      name,
      2,
      streams[name]!.length >= cutoff ? sectorsFor[name]! : miniAt[name]!,
      streams[name]!.length,
    );
  }
  return out;
}

void main() {
  test('a Word 97 document reads back its text', () {
    // 0xFE is ş on a Turkish machine; Latin-1 would make it þ.
    final bytes = buildDoc(
      textBytes: [
        ...'Taþınmaz satýþ sözleþmesi'.codeUnits.map(
          (c) => c < 0x100 ? c : 0x3f,
        ),
        0x0d,
        ...'İkinci paragraf'.codeUnits.map((c) => c < 0x100 ? c : 0xdd),
        0x0d,
      ],
      wide: false,
    );
    final model = DocReader.readBytes(bytes)!;
    expect(model.blocks.length, 2);
    expect(model.blocks.first.plainText, startsWith('Taş'));
    expect(model.blocks.first.plainText, isNot(contains('þ')));
    expect(model.blocks[1].plainText, startsWith('İkinci'));
  });

  test('a document written in UTF-16 reads back the same way', () {
    final text = 'Çiğdem Şenoğlu';
    final units = <int>[];
    for (final unit in text.codeUnits) {
      units.addAll([unit & 0xff, (unit >> 8) & 0xff]);
    }
    units.addAll([0x0d, 0x00]);
    final model = DocReader.readBytes(buildDoc(textBytes: units, wide: true))!;
    expect(model.blocks.first.plainText, text);
  });

  test('the other table stream is found when the flags point at it', () {
    final model = DocReader.readBytes(
      buildDoc(
        textBytes: [...'Eski belge'.codeUnits, 0x0d],
        wide: false,
        useOneTable: false,
      ),
    )!;
    expect(model.blocks.first.plainText, 'Eski belge');
  });

  test('table cells end their own paragraph rather than running together', () {
    final model = DocReader.readBytes(
      buildDoc(
        textBytes: [
          ...'ALACAKLI'.codeUnits,
          0x07,
          ...'Ayla'.codeUnits,
          0x07,
          0x0d,
        ],
        wide: false,
      ),
    )!;
    expect(model.blocks.map((b) => b.plainText).where((t) => t.isNotEmpty), [
      'ALACAKLI',
      'Ayla',
    ]);
  });

  test('field codes are left out and their results kept', () {
    final model = DocReader.readBytes(
      buildDoc(
        textBytes: [
          ...'Sayı: '.codeUnits,
          0x13,
          ...'MERGEFIELD no'.codeUnits,
          0x14,
          ...'2026/120'.codeUnits,
          0x15,
          0x0d,
        ],
        wide: false,
      ),
    )!;
    expect(model.blocks.first.plainText, contains('2026/120'));
  });

  test('something that is not a Word document is refused', () {
    expect(DocReader.readBytes(const [0x50, 0x4b, 0x03, 0x04]), isNull);
    expect(CfbFile.parse(const [0x50, 0x4b, 0x03, 0x04]), isNull);
    // A compound file that is a spreadsheet, not a document.
    final workbook = _container({'Workbook': Uint8List(64)}, 512);
    expect(DocReader.readBytes(workbook), isNull);
    expect(CfbFile.parse(workbook)!.streams.keys, contains('Workbook'));
  });

  test('a .doc is offered the formats that can actually be written', () {
    expect(EvrakFormat.fromExtension('doc'), EvrakFormat.doc);
    expect(EvrakFormat.doc.canEdit, isTrue);
    // There is no writer for the old binary format, so saving goes elsewhere.
    expect(EvrakFormat.doc.defaultExtension, isNot('doc'));
    expect(EvrakFormat.doc.availableConversions, contains(EvrakFormat.udf));
  });
}

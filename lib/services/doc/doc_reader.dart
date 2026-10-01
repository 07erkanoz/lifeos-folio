import 'dart:typed_data';

import '../../models/document_model.dart';
import '../text/windows_codepages.dart';
import 'cfb_reader.dart';

/// Reads Word 97-2003 documents.
///
/// There are a hundred and forty-five of them in this office's folder —
/// contracts, undertakings, notices — and nothing on pub.dev opens one. The
/// format keeps its text in a stream that is not laid out in reading order:
/// a piece table in a second stream says which parts of it to read, in what
/// order, and whether each part is one byte per character or two.
///
/// What is recovered is the text, its paragraphs and where the table cells
/// end. Character formatting lives in a separate run of binary property
/// blocks and is not read; a document opened here shows what it says, not
/// which words were bold.
class DocReader {
  /// Word's marker for a document, at the start of the WordDocument stream.
  static const _magic = 0xa5ec;

  static DocModel? readBytes(List<int> bytes) {
    try {
      final container = CfbFile.parse(bytes);
      if (container == null) return null;
      final word = container.streams['WordDocument'];
      if (word == null || word.length < 96) return null;
      final text = _text(word, container);
      if (text == null) return null;
      return _model(text);
    } catch (_) {
      return null;
    }
  }

  static bool looksLikeDoc(List<int> bytes) {
    if (!CfbFile.looksLikeCfb(bytes)) return false;
    final container = CfbFile.parse(bytes);
    return container?.streams.containsKey('WordDocument') ?? false;
  }

  /// The document's text, in reading order.
  static String? _text(Uint8List word, CfbFile container) {
    final fib = ByteData.sublistView(word);
    if (fib.getUint16(0, Endian.little) != _magic) return null;
    final flags = fib.getUint16(0x0a, Endian.little);
    final complex = flags & 0x0004 != 0;
    // Bit 9 says which of the two table streams this document uses.
    final table = container.streams[flags & 0x0200 != 0 ? '1Table' : '0Table'];

    final fcMin = fib.getUint32(0x18, Endian.little);
    final fcMac = fib.getUint32(0x1c, Endian.little);

    // Word 6 and 95 keep the text in one run and no piece table.
    if (table == null) {
      if (complex || fcMac <= fcMin || fcMac > word.length) return null;
      return _decode(word.sublist(fcMin, fcMac), wide: false);
    }

    final clx = _clx(word, fib, table);
    if (clx == null) {
      if (fcMac <= fcMin || fcMac > word.length) return null;
      return _decode(word.sublist(fcMin, fcMac), wide: false);
    }
    return _pieces(word, clx);
  }

  /// Finds the piece table inside the table stream.
  static Uint8List? _clx(Uint8List word, ByteData fib, Uint8List table) {
    // The FIB grew by accretion: fixed head, then four counted arrays. The
    // file positions live in the third one.
    var at = 32;
    if (at + 2 > word.length) return null;
    final csw = fib.getUint16(at, Endian.little);
    at += 2 + csw * 2;
    if (at + 2 > word.length) return null;
    final cslw = fib.getUint16(at, Endian.little);
    at += 2 + cslw * 4;
    if (at + 2 > word.length) return null;
    final cbRgFcLcb = fib.getUint16(at, Endian.little);
    at += 2;
    // fcClx is the 34th pair in that array.
    const clxIndex = 33;
    if (cbRgFcLcb <= clxIndex || at + (clxIndex + 1) * 8 > word.length) {
      return null;
    }
    final fcClx = fib.getUint32(at + clxIndex * 8, Endian.little);
    final lcbClx = fib.getUint32(at + clxIndex * 8 + 4, Endian.little);
    if (lcbClx == 0 || fcClx + lcbClx > table.length) return null;
    return table.sublist(fcClx, fcClx + lcbClx);
  }

  /// Walks the piece table, reading each piece out of the text stream.
  static String? _pieces(Uint8List word, Uint8List clx) {
    var at = 0;
    // Property blocks come first and are of no interest here.
    while (at < clx.length && clx[at] == 0x01) {
      if (at + 3 > clx.length) return null;
      final size = ByteData.sublistView(clx).getUint16(at + 1, Endian.little);
      at += 3 + size;
    }
    if (at >= clx.length || clx[at] != 0x02) return null;
    if (at + 5 > clx.length) return null;
    final view = ByteData.sublistView(clx);
    final size = view.getUint32(at + 1, Endian.little);
    at += 5;
    if (size < 4 || at + size > clx.length) return null;

    // n+1 character positions, then n descriptors of 8 bytes each.
    final count = (size - 4) ~/ 12;
    if (count <= 0) return null;
    final positions = <int>[
      for (var i = 0; i <= count; i++)
        view.getUint32(at + i * 4, Endian.little),
    ];
    final descriptors = at + (count + 1) * 4;

    final out = StringBuffer();
    for (var i = 0; i < count; i++) {
      final base = descriptors + i * 8;
      if (base + 8 > clx.length) break;
      final fc = view.getUint32(base + 2, Endian.little);
      // Bit 30 means the piece is one byte per character, and the offset is
      // stored halved.
      final wide = fc & 0x40000000 == 0;
      final start = wide ? (fc & 0x3fffffff) : (fc & 0x3fffffff) ~/ 2;
      final characters = positions[i + 1] - positions[i];
      if (characters <= 0) continue;
      final length = wide ? characters * 2 : characters;
      if (start < 0 || start + length > word.length) continue;
      out.write(_decode(word.sublist(start, start + length), wide: wide));
    }
    final text = out.toString();
    return text.isEmpty ? null : text;
  }

  /// Word stores text either as UTF-16 or as bytes in the writer's codepage.
  /// Turkish files are almost always the latter, and Latin-1 would turn ş
  /// into þ.
  static String _decode(Uint8List bytes, {required bool wide}) {
    if (wide) {
      final units = <int>[];
      for (var i = 0; i + 1 < bytes.length; i += 2) {
        units.add(bytes[i] | (bytes[i + 1] << 8));
      }
      return String.fromCharCodes(units);
    }
    final out = StringBuffer();
    for (final byte in bytes) {
      out.writeCharCode(
        byte < 0x80 ? byte : (cp1254[byte] ?? cp1252[byte] ?? byte),
      );
    }
    return out.toString();
  }

  /// Turns the recovered text into paragraphs.
  static DocModel _model(String text) {
    final blocks = <DocBlock>[];
    final line = StringBuffer();

    void close() {
      final value = line.toString().trimRight();
      line.clear();
      blocks.add(DocBlock(plainText: value));
    }

    for (final rune in text.runes) {
      switch (rune) {
        case 0x0d: // paragraph
        case 0x07: // end of a table cell or row
          close();
        case 0x0b: // line break inside a paragraph
          line.write('\n');
        case 0x09:
          line.write('\t');
        case 0x0c: // page break
        case 0x01: // an anchor for a picture
        case 0x08:
        case 0x13: // the three marks around a field's code
        case 0x14:
        case 0x15:
        case 0x00:
          break;
        default:
          if (rune >= 0x20 || rune == 0x0a) line.writeCharCode(rune);
      }
    }
    if (line.isNotEmpty) close();
    while (blocks.isNotEmpty && blocks.last.plainText.trim().isEmpty) {
      blocks.removeLast();
    }
    if (blocks.isEmpty) blocks.add(DocBlock(plainText: ''));
    return DocModel(blocks: blocks);
  }
}

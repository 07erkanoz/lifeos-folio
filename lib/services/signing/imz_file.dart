import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:asn1lib/asn1lib.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../udf/signature_parser.dart';
import 'udf_signing_service.dart';

/// A file signed with an e-signature card, as `.imz` (5070 sayılı Kanun):
/// the document itself inside a CAdES-BES signature (CMS SignedData with
/// its content attached), the way Turkey's e-signature programs write it.
/// `sozlesme.pdf` signed is `sozlesme.pdf.imz`.
class ImzContent {
  const ImzContent({
    required this.content,
    required this.name,
    required this.signers,
    required this.valid,
  });

  /// The document that was signed, byte for byte.
  final Uint8List content;

  /// Its name: the `.imz`'s without the `.imz`, its kind found from its
  /// bytes when that name does not say.
  final String name;
  final List<UdfSignatureInfo> signers;

  /// Whether every signature holds over [content] with its own
  /// certificate. Whether the certificate is trusted and not revoked is
  /// not checked here.
  final bool valid;
}

abstract final class ImzFile {
  static const extension = 'imz';

  static bool isImz(String path) =>
      p.extension(path).toLowerCase() == '.$extension';

  /// [path] signed with the card into `<path>.imz` beside it (a number
  /// added if one is there already); the signature's path.
  static Future<String> sign(
    String path,
    UdfSigningService service,
    SigningCard card,
    SigningCertificate certificate,
    String pin,
  ) async {
    final data = await File(path).readAsBytes();
    final signature = await service.signBytes(
      data,
      card,
      certificate,
      pin,
      attached: true,
    );
    // What was signed is what is inside.
    final read = await compute(_read, (signature, p.basename(path)));
    if (read == null || !read.valid || !listEquals(read.content, data)) {
      throw StateError('İmza oluşturuldu ama doğrulanamadı; kaydedilmedi.');
    }
    var target = '$path.$extension';
    for (var n = 2; await File(target).exists(); n++) {
      target = '$path ($n).$extension';
    }
    await File(target).writeAsBytes(signature, flush: true);
    return target;
  }

  /// [path]'s document and its signatures; null when it is no signature
  /// with a document inside.
  static Future<ImzContent?> open(String path) async {
    final bytes = await File(path).readAsBytes();
    return compute(_read, (bytes, p.basename(path)));
  }

  static ImzContent? _read((Uint8List, String) request) =>
      read(request.$1, request.$2);

  /// [bytes] read, [fileName] being the `.imz`'s name.
  @visibleForTesting
  static ImzContent? read(Uint8List bytes, String fileName) {
    try {
      final info = ASN1Parser(bytes).nextObject() as ASN1Sequence;
      final contentType = info.elements[0] as ASN1ObjectIdentifier;
      if (contentType.identifier != '1.2.840.113549.1.7.2') return null;
      final signedData =
          ASN1Parser(info.elements[1].valueBytes()).nextObject()
              as ASN1Sequence;
      final fields = signedData.elements;
      final encap = fields[2] as ASN1Sequence;
      if (encap.elements.length < 2) return null;
      final content = _octets(
        ASN1Parser(encap.elements[1].valueBytes()).nextObject(),
      );
      // The signature without the document, as one beside it would be:
      // what the signature reader and checker take.
      final signature = _tlv(0x30, [
        ...contentType.encodedBytes,
        ..._tlv(
          0xa0,
          _tlv(0x30, [
            ...fields[0].encodedBytes,
            ...fields[1].encodedBytes,
            ..._tlv(0x30, encap.elements[0].encodedBytes),
            for (final field in fields.skip(3)) ...field.encodedBytes,
          ]),
        ),
      ]);
      return ImzContent(
        content: content,
        name: _nameOf(fileName, content),
        signers: UdfSignatureParser.parse(signature),
        valid: UdfSignatureParser.verifyDocument(signature, content),
      );
    } catch (_) {
      return null;
    }
  }

  /// A DER tag, its length and [content].
  static Uint8List _tlv(int tag, List<int> content) {
    final length = content.length;
    final head = <int>[tag];
    if (length < 0x80) {
      head.add(length);
    } else {
      final digits = <int>[];
      for (var n = length; n > 0; n >>= 8) {
        digits.insert(0, n & 0xff);
      }
      head
        ..add(0x80 | digits.length)
        ..addAll(digits);
    }
    return Uint8List.fromList([...head, ...content]);
  }

  /// An OCTET STRING's bytes, whole or in a constructed string's pieces.
  static Uint8List _octets(ASN1Object object) {
    if (object.tag == 0x04) return object.valueBytes();
    if (object.tag == 0x24) {
      final parser = ASN1Parser(object.valueBytes());
      final out = BytesBuilder(copy: false);
      while (parser.hasNext()) {
        out.add(_octets(parser.nextObject()));
      }
      return out.toBytes();
    }
    throw const FormatException('belge içeriği yok');
  }

  /// `sozlesme.pdf.imz` → `sozlesme.pdf`; a name with no kind of its own
  /// is given the one its bytes show.
  static String _nameOf(String fileName, Uint8List content) {
    var name = fileName;
    if (p.extension(name).toLowerCase() == '.$extension') {
      name = p.basenameWithoutExtension(name);
    }
    if (p.extension(name).isNotEmpty) return name;
    return '${name.isEmpty ? 'belge' : name}.${_kindOf(content)}';
  }

  static String _kindOf(Uint8List b) {
    bool starts(List<int> magic) =>
        b.length >= magic.length &&
        List.generate(magic.length, (i) => b[i] == magic[i]).every((x) => x);
    if (starts('%PDF'.codeUnits)) return 'pdf';
    if (starts('{\\rtf'.codeUnits)) return 'rtf';
    if (starts([0xd0, 0xcf, 0x11, 0xe0])) return 'doc';
    if (starts([0x50, 0x4b])) {
      try {
        final names = ZipDecoder()
            .decodeBytes(b, verify: false)
            .files
            .map((f) => f.name)
            .toSet();
        if (names.contains('content.xml') && names.contains('sign.sgn') ||
            names.contains('content.xml') && !names.contains('mimetype')) {
          return 'udf';
        }
        if (names.contains('word/document.xml')) return 'docx';
        if (names.contains('xl/workbook.xml')) return 'xlsx';
        if (names.contains('mimetype')) return 'odt';
      } catch (_) {}
      return 'zip';
    }
    if (starts([0xff, 0xd8])) return 'jpg';
    if (starts([0x89, 0x50, 0x4e, 0x47])) return 'png';
    return 'bin';
  }
}

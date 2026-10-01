import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// The PKCS#7 inside a signed UDF, handled at the level of its DER bytes.
///
/// A signed UDF is a ZIP holding `content.xml` untouched and `sign.sgn`, a
/// *detached* SignedData over the raw bytes of `content.xml` — not over the
/// ZIP. Across 649 signed UDFs out of UYAP (Turkcell mobile and TÜRKTRUST
/// cards alike) there was no exception. Several signers share one `sign.sgn`:
/// one SignedData with a SignerInfo each.
///
/// Walked by hand rather than decoded and re-encoded, so that certificates and
/// signer infos keep the exact bytes they were signed with.
class SignedData {
  SignedData._();

  static const _sequence = 0x30, _set = 0x31, _octetString = 0x04;
  static const _context0 = 0xA0, _context1 = 0xA1;

  /// DER of the messageDigest attribute's OID, 1.2.840.113549.1.9.4.
  static final _messageDigestOid = Uint8List.fromList([
    0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x04, //
  ]);

  /// [signature] without the content it may carry: UYAP's mobile signature
  /// service returns it embedded, a UDF keeps it detached, and writing the
  /// embedded form doubles the file and sets it apart from UYAP's own.
  static Uint8List detach(Uint8List signature) {
    final (oid, start, end) = _signedData(signature);
    final body = BytesBuilder();
    var found = false;
    for (final e in _elements(signature, start, end)) {
      // The first SEQUENCE of a SignedData is encapContentInfo: version and
      // the digestAlgorithms SET come before it.
      if (e.tag == _sequence && !found) {
        found = true;
        final inner = BytesBuilder();
        for (final c in _elements(signature, e.bodyStart, e.bodyEnd)) {
          if (c.tag == _context0) continue; // eContent
          inner.add(signature.sublist(c.start, c.end));
        }
        body.add(_der(_sequence, inner.takeBytes()));
      } else {
        body.add(signature.sublist(e.start, e.end));
      }
    }
    if (!found) throw const FormatException('encapContentInfo bulunamadı.');
    return _der(_sequence, [
      ...oid,
      ..._der(_context0, _der(_sequence, body.takeBytes())),
    ]);
  }

  /// The messageDigest of the first signer, or null.
  static Uint8List? messageDigest(Uint8List signature) {
    final at = _indexOf(signature, _messageDigestOid);
    if (at < 0) return null;
    final from = at + _messageDigestOid.length;
    for (final set in _elements(signature, from, signature.length)) {
      if (set.tag != _set) return null;
      for (final value in _elements(signature, set.bodyStart, set.bodyEnd)) {
        if (value.tag == _octetString) {
          return signature.sublist(value.bodyStart, value.bodyEnd);
        }
      }
      return null;
    }
    return null;
  }

  /// Whether [signature] really covers [content].
  ///
  /// The one place a signature that is not bound to the document can be
  /// caught: UYAP's service, asked the wrong way, zeroes the first 100 bytes
  /// of what it signs and reports no error at all. The digest algorithm is
  /// told by the digest's length — 647 of 649 real UDFs used SHA-256, two
  /// SHA-1, and assuming one would refuse the other.
  static bool covers(Uint8List signature, List<int> content) {
    final Uint8List? digest;
    try {
      digest = messageDigest(signature);
    } on FormatException {
      return false;
    }
    if (digest == null) return false;
    final hash = switch (digest.length) {
      20 => sha1,
      32 => sha256,
      48 => sha384,
      64 => sha512,
      _ => null,
    };
    return hash != null && listEquals(hash.convert(content).bytes, digest);
  }

  /// [existing] and [added] as one detached SignedData with the signers of
  /// both — how UYAP keeps a document signed by several people.
  ///
  /// Both must cover the same content; two signatures over different text in
  /// one container would make both invalid, and nobody would notice.
  static Uint8List merge(Uint8List existing, Uint8List added) {
    final da = messageDigest(existing), db = messageDigest(added);
    if (da == null || db == null || !listEquals(da, db)) {
      throw const FormatException(
        'İki imza aynı içeriği kapsamıyor; birleştirilmedi.',
      );
    }
    return _join(existing, added);
  }

  /// [merge] for two signatures already known to cover the same content —
  /// possibly with different digests: a SHA-1 signer and a SHA-256 one sign
  /// the same text, and their digests never compare equal.
  static Uint8List _join(Uint8List existing, Uint8List added) {
    final a = _parts(detach(existing)), b = _parts(detach(added));
    final body = BytesBuilder()
      ..add(_der(0x02, [a.version > b.version ? a.version : b.version]))
      ..add(_der(_set, _unique([...a.digestAlgorithms, ...b.digestAlgorithms])))
      ..add(a.encapsulated);
    final certificates = _unique([...a.certificates, ...b.certificates]);
    if (certificates.isNotEmpty) body.add(_der(_context0, certificates));
    final crls = _unique([...a.crls, ...b.crls]);
    if (crls.isNotEmpty) body.add(_der(_context1, crls));
    body.add(_der(_set, _unique([...a.signers, ...b.signers])));
    return _der(_sequence, [
      ...a.oid,
      ..._der(_context0, _der(_sequence, body.takeBytes())),
    ]);
  }

  /// [udf] signed with [signature]: `content.xml` byte for byte as it was,
  /// and `sign.sgn` holding the detached signature — joined to the signers
  /// already there, if the document was signed before.
  ///
  /// Refuses a signature that does not cover the document's `content.xml`.
  static Uint8List sign(Uint8List udf, Uint8List signature) {
    final archive = ZipDecoder().decodeBytes(udf);
    final content = archive.findFile('content.xml');
    if (content == null) {
      throw const FormatException('UDF içinde content.xml bulunamadı.');
    }
    final bytes = content.content;
    if (!covers(signature, bytes)) {
      throw const FormatException(
        'İmza bu belgenin metnini kapsamıyor; belge kaydedilmedi.',
      );
    }
    final entry = archive.findFile('sign.sgn');
    final previous = entry == null ? null : Uint8List.fromList(entry.content);
    if (previous != null && !covers(previous, bytes)) {
      throw const FormatException(
        'Belgedeki mevcut imza bu metni kapsamıyor; imza eklenmedi.',
      );
    }
    final signed = previous == null
        ? detach(signature)
        : _join(previous, signature);
    final out = Archive();
    for (final file in archive.files) {
      if (!file.isFile || file.name == 'sign.sgn') continue;
      out.addFile(ArchiveFile(file.name, file.content.length, file.content));
    }
    out.addFile(ArchiveFile('sign.sgn', signed.length, signed));
    return Uint8List.fromList(ZipEncoder().encode(out));
  }

  /// How many signers [signature] carries.
  static int signerCount(Uint8List signature) {
    try {
      final parts = _parts(signature);
      final signers = Uint8List.fromList(parts.signers);
      return _elements(
        signers,
        0,
        signers.length,
      ).where((e) => e.tag == _sequence).length;
    } on FormatException {
      return 0;
    }
  }

  /// The `sign.sgn` of [udf], or null when it has none.
  static Uint8List? signatureOf(Uint8List udf) {
    final file = ZipDecoder().decodeBytes(udf).findFile('sign.sgn');
    return file == null ? null : Uint8List.fromList(file.content);
  }

  /// The raw bytes of the `content.xml` entry of [udf].
  static Uint8List content(Uint8List udf) {
    final file = ZipDecoder().decodeBytes(udf).findFile('content.xml');
    if (file == null) {
      throw const FormatException('UDF içinde content.xml bulunamadı.');
    }
    return Uint8List.fromList(file.content);
  }

  static _Parts _parts(Uint8List signature) {
    final (oid, start, end) = _signedData(signature);
    final parts = _Parts(oid);
    var digests = false, encapsulated = false;
    for (final e in _elements(signature, start, end)) {
      final body = signature.sublist(e.bodyStart, e.bodyEnd);
      if (e.tag == 0x02 && !digests) {
        parts.version = body.isEmpty ? 1 : body.last;
      } else if (e.tag == _set && !digests) {
        parts.digestAlgorithms = body;
        digests = true;
      } else if (e.tag == _sequence && !encapsulated) {
        parts.encapsulated = signature.sublist(e.start, e.end);
        encapsulated = true;
      } else if (e.tag == _context0) {
        parts.certificates = body;
      } else if (e.tag == _context1) {
        parts.crls = body;
      } else if (e.tag == _set) {
        parts.signers = body;
      }
    }
    if (parts.encapsulated.isEmpty || parts.signers.isEmpty) {
      throw const FormatException(
        'PKCS#7 beklenen SignedData yapısında değil.',
      );
    }
    return parts;
  }

  /// The elements of a SET OF body, each once, in their order: the same
  /// person signing twice would otherwise carry their certificate twice,
  /// which some validators stumble on.
  static Uint8List _unique(List<int> body) {
    final bytes = Uint8List.fromList(body);
    final seen = <String>{};
    final out = BytesBuilder();
    for (final e in _elements(bytes, 0, bytes.length)) {
      final element = bytes.sublist(e.start, e.end);
      if (seen.add(String.fromCharCodes(element))) out.add(element);
    }
    return out.takeBytes();
  }

  /// (contentType OID element, SignedData body start, body end).
  static (Uint8List, int, int) _signedData(Uint8List p7) {
    final info = _single(p7, 0, p7.length);
    final parts = _elements(p7, info.bodyStart, info.bodyEnd).toList();
    if (parts.length < 2) throw const FormatException('ContentInfo eksik.');
    final oid = p7.sublist(parts[0].start, parts[0].end);
    final wrapped = parts[1];
    final data = _single(p7, wrapped.bodyStart, wrapped.bodyEnd);
    return (oid, data.bodyStart, data.bodyEnd);
  }

  static _Element _single(Uint8List b, int start, int end) {
    for (final e in _elements(b, start, end)) {
      return e;
    }
    throw const FormatException('Beklenen DER öğesi yok.');
  }

  static Iterable<_Element> _elements(Uint8List b, int start, int end) sync* {
    var i = start;
    while (i < end) {
      final at = i;
      final tag = b[i++];
      if (i >= end) throw const FormatException('Geçersiz DER.');
      var length = b[i++];
      if (length >= 0x80) {
        final count = length & 0x7F;
        if (count == 0 || count > 4 || i + count > end) {
          throw const FormatException('Geçersiz DER uzunluğu.');
        }
        length = 0;
        for (var k = 0; k < count; k++) {
          length = (length << 8) | b[i++];
        }
      }
      if (i + length > end) {
        throw const FormatException('DER öğesi kabına sığmıyor.');
      }
      yield _Element(tag, at, i, i + length);
      i += length;
    }
  }

  static Uint8List _der(int tag, List<int> body) {
    final length = body.length;
    final header = <int>[tag];
    if (length < 0x80) {
      header.add(length);
    } else {
      final bytes = <int>[];
      for (var n = length; n > 0; n >>= 8) {
        bytes.insert(0, n & 0xFF);
      }
      header
        ..add(0x80 | bytes.length)
        ..addAll(bytes);
    }
    return Uint8List.fromList([...header, ...body]);
  }

  static int _indexOf(Uint8List haystack, Uint8List needle) {
    outer:
    for (var i = 0; i <= haystack.length - needle.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}

class _Element {
  final int tag, start, bodyStart, bodyEnd;
  const _Element(this.tag, this.start, this.bodyStart, this.bodyEnd);
  int get end => bodyEnd;
}

class _Parts {
  _Parts(this.oid);
  final Uint8List oid;
  int version = 1;
  List<int> digestAlgorithms = const [];
  Uint8List encapsulated = Uint8List(0);
  List<int> certificates = const [];
  List<int> crls = const [];
  List<int> signers = const [];
}

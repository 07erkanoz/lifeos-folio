import 'dart:convert';

import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

/// Signer display metadata. Trust and revocation are not established here.
class UdfSignatureInfo {
  final String? signerName;
  final String? issuerName;
  final String? organization;
  final String? subjectIdentifier;
  final String? certificateSerial;
  final DateTime? signedAt;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final bool counterSignature;
  final String? issue;

  const UdfSignatureInfo({
    this.signerName,
    this.issuerName,
    this.organization,
    this.subjectIdentifier,
    this.certificateSerial,
    this.signedAt,
    this.validFrom,
    this.validUntil,
    this.counterSignature = false,
    this.issue,
  });
}

/// CMS SignedData / SignerInfo matching follows RFC 5652 §5.3.
/// Each signer is matched by issuer + serial, or subject key identifier.
/// Unrelated certificates (including CAs) are never presented as signers.
class UdfSignatureParser {
  /// Verifies every document signer against the exact content and its embedded
  /// certificate. Certificate trust and revocation are separate checks.
  static bool verifyDocument(List<int> signature, List<int> content) {
    try {
      final root = _sequence(_object(signature));
      if (_oid(root[0]) != '1.2.840.113549.1.7.2') return false;
      final signedData = _sequence(_object(root[1].valueBytes()));
      final certificates = <_Certificate>[];
      for (final field in signedData.skip(3)) {
        if (field.tag == 0xa0) {
          for (final entry in _children(field)) {
            if (entry.tag == 0x30) certificates.add(_Certificate(entry));
          }
        }
      }
      final signers = _children(signedData.last).toList();
      if (signers.isEmpty) return false;
      for (final signer in signers) {
        final fields = _sequence(signer);
        if (fields.length < 6 || fields[3].tag != 0xa0) return false;
        final matches = certificates.where((c) => c.matches(fields[1]));
        if (matches.length != 1) return false;
        final digestOid = _oid(_sequence(fields[2])[0]);
        final hash = switch (digestOid) {
          '1.3.14.3.2.26' => sha1,
          '2.16.840.1.101.3.4.2.1' => sha256,
          '2.16.840.1.101.3.4.2.2' => sha384,
          '2.16.840.1.101.3.4.2.3' => sha512,
          _ => null,
        };
        if (hash == null) return false;
        final digest = hash.convert(content).bytes;
        var matchingDigest = 0;
        var matchingType = 0;
        for (final attribute in _children(fields[3])) {
          final pair = _sequence(attribute);
          final oid = _oid(pair[0]);
          final values = _children(pair[1]).toList();
          if (values.length != 1) return false;
          if (oid == '1.2.840.113549.1.9.4') {
            if (values.single.tag != 0x04 ||
                !listEquals(values.single.valueBytes(), digest)) {
              return false;
            }
            matchingDigest++;
          }
          if (oid == '1.2.840.113549.1.9.3') {
            if (_oid(values.single) != '1.2.840.113549.1.7.1') return false;
            matchingType++;
          }
        }
        if (matchingDigest != 1 || matchingType != 1) return false;
        final signatureAlgorithm = _oid(_sequence(fields[4])[0]);
        final rsaOid = switch (digestOid) {
          '1.3.14.3.2.26' => '1.2.840.113549.1.1.5',
          '2.16.840.1.101.3.4.2.1' => '1.2.840.113549.1.1.11',
          '2.16.840.1.101.3.4.2.2' => '1.2.840.113549.1.1.12',
          '2.16.840.1.101.3.4.2.3' => '1.2.840.113549.1.1.13',
          _ => null,
        };
        if (fields[5].tag != 0x04) return false;
        final attrs = Uint8List.fromList(fields[3].encodedBytes)..[0] = 0x31;
        if (signatureAlgorithm == '1.2.840.113549.1.1.1' ||
            signatureAlgorithm == rsaOid) {
          final publicKey = matches.single.rsaPublicKey;
          if (publicKey == null) return false;
          final verifier = switch (digestOid) {
            '1.3.14.3.2.26' => RSASigner(SHA1Digest(), '06052b0e03021a'),
            '2.16.840.1.101.3.4.2.1' => RSASigner(
              SHA256Digest(),
              '0609608648016503040201',
            ),
            '2.16.840.1.101.3.4.2.2' => RSASigner(
              SHA384Digest(),
              '0609608648016503040202',
            ),
            '2.16.840.1.101.3.4.2.3' => RSASigner(
              SHA512Digest(),
              '0609608648016503040203',
            ),
            _ => null,
          };
          if (verifier == null) return false;
          verifier.init(false, PublicKeyParameter<RSAPublicKey>(publicKey));
          if (!verifier.verifySignature(
            attrs,
            RSASignature(fields[5].valueBytes()),
          )) {
            return false;
          }
        } else {
          final ecOid = switch (digestOid) {
            '1.3.14.3.2.26' => '1.2.840.10045.4.1',
            '2.16.840.1.101.3.4.2.1' => '1.2.840.10045.4.3.2',
            '2.16.840.1.101.3.4.2.2' => '1.2.840.10045.4.3.3',
            '2.16.840.1.101.3.4.2.3' => '1.2.840.10045.4.3.4',
            _ => null,
          };
          if (signatureAlgorithm != ecOid) return false;
          final publicKey = matches.single.ecPublicKey;
          if (publicKey == null) return false;
          final values = _sequence(_object(fields[5].valueBytes()));
          if (values.length != 2) return false;
          final verifier = ECDSASigner(switch (digestOid) {
            '1.3.14.3.2.26' => SHA1Digest(),
            '2.16.840.1.101.3.4.2.1' => SHA256Digest(),
            '2.16.840.1.101.3.4.2.2' => SHA384Digest(),
            '2.16.840.1.101.3.4.2.3' => SHA512Digest(),
            _ => throw const FormatException('Unsupported digest'),
          });
          verifier.init(false, PublicKeyParameter<ECPublicKey>(publicKey));
          if (!verifier.verifySignature(
            attrs,
            ECSignature(_integer(values[0]), _integer(values[1])),
          )) {
            return false;
          }
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static List<UdfSignatureInfo> parse(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) return const [];
    try {
      final content = _sequence(_object(bytes));
      if (_oid(content[0]) != '1.2.840.113549.1.7.2' ||
          content[1].tag != 0xa0) {
        return const [];
      }
      final signedData = _sequence(_object(content[1].valueBytes()));
      if (signedData.length < 4 || signedData.last.tag != 0x31) return const [];
      final certificates = <_Certificate>[];
      for (final field in signedData.skip(3)) {
        if (field.tag != 0xa0) continue;
        for (final item in _children(field)) {
          try {
            if (item.tag == 0x30) certificates.add(_Certificate(item));
          } catch (_) {
            // Unsupported certificate choices must not hide other signers.
          }
        }
      }
      final result = <UdfSignatureInfo>[];
      for (final signer in _children(signedData.last)) {
        _readSigner(signer, certificates, result, 0);
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  static void _readSigner(
    ASN1Object signer,
    List<_Certificate> certificates,
    List<UdfSignatureInfo> output,
    int depth,
  ) {
    if (depth > 4 || output.length >= 64) return;
    try {
      final fields = _sequence(signer);
      if (fields.length < 5) throw const FormatException('SignerInfo');
      final sid = fields[1];
      final matches = certificates.where((cert) => cert.matches(sid)).toList();
      final cert = matches.length == 1 ? matches.single : null;
      DateTime? signedAt;
      for (final field in fields.skip(3)) {
        if (field.tag != 0xa0) continue;
        for (final attr in _children(field)) {
          final pair = _sequence(attr);
          if (_oid(pair[0]) == '1.2.840.113549.1.9.5') {
            signedAt = _time(_children(pair[1]).single);
          }
        }
      }
      output.add(
        UdfSignatureInfo(
          signerName: cert?.subject['2.5.4.3'],
          issuerName: cert?.issuer['2.5.4.3'] ?? cert?.issuer['2.5.4.10'],
          organization: cert?.subject['2.5.4.10'],
          subjectIdentifier: cert?.subject['2.5.4.5'],
          certificateSerial: cert?.serial.toRadixString(16).toUpperCase(),
          signedAt: signedAt,
          validFrom: cert?.validFrom,
          validUntil: cert?.validUntil,
          counterSignature: depth > 0,
          issue: cert == null
              ? 'İmzacı sertifikası bulunamadı veya tekil olarak eşleştirilemedi.'
              : null,
        ),
      );
      // Only countersignature attributes contain additional document signers;
      // timestamp authorities in other unsigned attributes are not signers.
      for (final field in fields.skip(3)) {
        if (field.tag != 0xa1) continue;
        for (final attr in _children(field)) {
          final pair = _sequence(attr);
          if (_oid(pair[0]) != '1.2.840.113549.1.9.6') continue;
          for (final counter in _children(pair[1])) {
            _readSigner(counter, certificates, output, depth + 1);
          }
        }
      }
    } catch (_) {
      output.add(
        UdfSignatureInfo(
          counterSignature: depth > 0,
          issue: 'Bu imza kaydının ayrıntıları okunamadı.',
        ),
      );
    }
  }
}

ASN1Object _object(List<int> source) {
  final bytes = source is Uint8List ? source : Uint8List.fromList(source);
  final header = ASN1Object.fromBytes(bytes);
  final length = header.totalEncodedByteLength;
  if (length <= 0 || length > bytes.length) {
    throw const FormatException('ASN.1 length');
  }
  return ASN1Object.fromBytes(Uint8List.sublistView(bytes, 0, length));
}

List<ASN1Object> _sequence(ASN1Object obj) {
  if (obj.tag != 0x30) throw const FormatException('ASN.1 sequence');
  return _children(obj).toList();
}

String? _oid(ASN1Object obj) => obj.tag == 6
    ? ASN1ObjectIdentifier.fromBytes(obj.encodedBytes).identifier
    : null;
BigInt _integer(ASN1Object obj) {
  if (obj.tag != 2) throw const FormatException('ASN.1 integer');
  return ASN1Integer.fromBytes(obj.encodedBytes).valueAsBigInteger;
}

// Parse containers lazily. Apart from bounding nesting, this avoids the
// dependency's BMPString UTF-8 decoding and its incorrect UTC year pivot.
Iterable<ASN1Object> _children(ASN1Object obj) sync* {
  final bytes = obj.valueBytes();
  var offset = 0;
  while (offset < bytes.length) {
    final child = _object(Uint8List.sublistView(bytes, offset));
    final length = child.totalEncodedByteLength;
    if (length <= 0 || offset + length > bytes.length) {
      throw const FormatException('ASN.1 length');
    }
    yield child;
    offset += length;
  }
}

DateTime? _time(ASN1Object obj) {
  if (obj.tag != 0x17 && obj.tag != 0x18) return null;
  try {
    var s = ascii.decode(obj.valueBytes());
    if (obj.tag == 0x17) {
      final year = int.parse(s.substring(0, 2));
      s = '${year >= 50 ? '19' : '20'}$s';
    }
    if (!RegExp(r'^\d{14}(Z|[+-]\d{4})$').hasMatch(s)) return null;
    return DateTime.parse('${s.substring(0, 8)}T${s.substring(8)}').toUtc();
  } catch (_) {
    return null;
  }
}

String _string(ASN1Object obj) {
  if (obj.tag == 0x0c) return utf8.decode(obj.valueBytes());
  final bytes = obj.valueBytes();
  if (obj.tag == 0x1e) {
    if (bytes.length.isOdd) throw const FormatException('BMPString');
    return String.fromCharCodes([
      for (var i = 0; i < bytes.length; i += 2) (bytes[i] << 8) | bytes[i + 1],
    ]);
  }
  return latin1.decode(bytes);
}

Map<String, String> _name(ASN1Object obj) => {
  for (final rdn in _sequence(obj))
    for (final attr in _children(rdn))
      if (_oid(_sequence(attr)[0]) case final String oid)
        oid: _string(_sequence(attr)[1]),
};

String _nameKey(ASN1Object obj) => _sequence(obj)
    .map((rdn) {
      final pairs = _children(rdn).map((attr) {
        final pair = _sequence(attr);
        return '${_oid(pair[0])}=${_string(pair[1]).trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase()}';
      }).toList()..sort();
      return jsonEncode(pairs);
    })
    .join('/');

class _Certificate {
  late final BigInt serial;
  late final ASN1Object issuerObject;
  late final Map<String, String> issuer;
  late final Map<String, String> subject;
  DateTime? validFrom;
  DateTime? validUntil;
  List<int>? subjectKeyId;
  RSAPublicKey? rsaPublicKey;
  ECPublicKey? ecPublicKey;

  _Certificate(ASN1Object certificate) {
    final tbs = _sequence(_sequence(certificate)[0]);
    final offset = tbs[0].tag == 0xa0 ? 1 : 0;
    serial = _integer(tbs[offset]);
    issuerObject = tbs[offset + 2];
    issuer = _name(issuerObject);
    final validity = _sequence(tbs[offset + 3]);
    validFrom = _time(validity[0]);
    validUntil = _time(validity[1]);
    subject = _name(tbs[offset + 4]);
    try {
      final spki = _sequence(tbs[offset + 5]);
      final algorithm = _sequence(spki[0]);
      if (_oid(algorithm[0]) == '1.2.840.113549.1.1.1') {
        final bits = spki[1].valueBytes();
        if (bits.isNotEmpty && bits[0] == 0) {
          final pair = _sequence(_object(bits.sublist(1)));
          rsaPublicKey = RSAPublicKey(_integer(pair[0]), _integer(pair[1]));
        }
      } else if (_oid(algorithm[0]) == '1.2.840.10045.2.1') {
        final curve = switch (_oid(algorithm[1])) {
          '1.2.840.10045.3.1.7' => 'secp256r1',
          '1.3.132.0.34' => 'secp384r1',
          '1.3.132.0.35' => 'secp521r1',
          _ => null,
        };
        final bits = spki[1].valueBytes();
        if (curve != null && bits.isNotEmpty && bits[0] == 0) {
          final parameters = ECDomainParameters(curve);
          ecPublicKey = ECPublicKey(
            parameters.curve.decodePoint(bits.sublist(1)),
            parameters,
          );
        }
      }
    } catch (_) {
      // Unsupported keys remain unavailable to the verifier.
    }
    for (final field in tbs.skip(offset + 6)) {
      if (field.tag != 0xa3) continue;
      for (final ext in _sequence(_object(field.valueBytes()))) {
        final parts = _sequence(ext);
        if (_oid(parts[0]) == '2.5.29.14') {
          subjectKeyId = _object(parts.last.valueBytes()).valueBytes();
        }
      }
    }
  }

  bool matches(ASN1Object sid) {
    if (sid.tag == 0x80) {
      return subjectKeyId != null && listEquals(subjectKeyId, sid.valueBytes());
    }
    if (sid.tag != 0x30) return false;
    final fields = _sequence(sid);
    return fields.length == 2 &&
        fields[1].tag == 2 &&
        _integer(fields[1]) == serial &&
        (listEquals(fields[0].encodedBytes, issuerObject.encodedBytes) ||
            _nameKey(fields[0]) == _nameKey(issuerObject));
  }
}

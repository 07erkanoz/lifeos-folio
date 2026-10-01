/// X.509 sertifika DER ayrıştırıcısı.
///
/// Akıllı karttan okunan DER-encoded X.509 sertifikadan
/// temel bilgileri (isim, sağlayıcı, seri no, geçerlilik) çıkarır.
library;

import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';

/// X.509 sertifika bilgileri (insan okunabilir).
class X509CertInfo {
  final String subjectCN; // İmza sahibi adı
  final String issuerCN; // Sertifika sağlayıcısı
  final String serialNumber; // Seri numarası (hex)
  final DateTime notBefore; // Geçerlilik başlangıcı
  final DateTime notAfter; // Geçerlilik bitişi
  final String? subjectSerialNumber; // TC Kimlik No (varsa)
  final String? organizationName; // Kurum adı (varsa)
  final Uint8List issuerDer; // Issuer DER bytes (CAdES için)
  final Uint8List serialNumberDer; // Serial Number DER bytes (CAdES için)

  const X509CertInfo({
    required this.subjectCN,
    required this.issuerCN,
    required this.serialNumber,
    required this.notBefore,
    required this.notAfter,
    this.subjectSerialNumber,
    this.organizationName,
    required this.issuerDer,
    required this.serialNumberDer,
  });

  bool get isExpired => DateTime.now().isAfter(notAfter);
  bool get isNotYetValid => DateTime.now().isBefore(notBefore);
  bool get isValid => !isExpired && !isNotYetValid;

  /// Görüntüleme için formatlı metin
  String get displayName {
    if (subjectSerialNumber != null) {
      return '$subjectCN ($subjectSerialNumber)';
    }
    return subjectCN;
  }

  @override
  String toString() =>
      'X509[$subjectCN, issuer=$issuerCN, '
      'valid=${notBefore.toIso8601String()}-${notAfter.toIso8601String()}]';
}

/// DER-encoded X.509 sertifikayı ayrıştır.
///
/// RFC 5280 Certificate yapısı:
/// ```
/// Certificate ::= SEQUENCE {
///   tbsCertificate     TBSCertificate,
///   signatureAlgorithm AlgorithmIdentifier,
///   signatureValue     BIT STRING
/// }
/// TBSCertificate ::= SEQUENCE {
///   version         [0] EXPLICIT INTEGER DEFAULT v1,
///   serialNumber         INTEGER,
///   signature            AlgorithmIdentifier,
///   issuer               Name,
///   validity             Validity,
///   subject              Name,
///   ...
/// }
/// ```
X509CertInfo? parseX509Certificate(Uint8List derBytes) {
  try {
    final parser = ASN1Parser(derBytes);
    final certSeq = parser.nextObject() as ASN1Sequence;

    // tbsCertificate
    final tbsCert = certSeq.elements[0] as ASN1Sequence;

    int fieldIndex = 0;

    // version [0] EXPLICIT (opsiyonel)
    if (tbsCert.elements[0].tag == 0xA0) {
      fieldIndex++; // version alanını atla
    }

    // serialNumber INTEGER
    final serialNumberObj = tbsCert.elements[fieldIndex] as ASN1Integer;
    final serialNumberHex = serialNumberObj.valueAsBigInteger
        .toRadixString(16)
        .toUpperCase();
    final serialNumberDer = Uint8List.fromList(serialNumberObj.encodedBytes);
    fieldIndex++;

    // signature AlgorithmIdentifier (atla)
    fieldIndex++;

    // issuer Name
    final issuerSeq = tbsCert.elements[fieldIndex] as ASN1Sequence;
    final issuerDer = Uint8List.fromList(issuerSeq.encodedBytes);
    final issuerCN = _extractCN(issuerSeq);
    fieldIndex++;

    // validity Validity
    final validitySeq = tbsCert.elements[fieldIndex] as ASN1Sequence;
    final notBefore = _parseTime(validitySeq.elements[0]);
    final notAfter = _parseTime(validitySeq.elements[1]);
    fieldIndex++;

    // subject Name
    final subjectSeq = tbsCert.elements[fieldIndex] as ASN1Sequence;
    final subjectCN = _extractCN(subjectSeq);
    final subjectSerialNumber = _extractAttribute(
      subjectSeq,
      '2.5.4.5',
    ); // serialNumber OID
    final orgName = _extractAttribute(
      subjectSeq,
      '2.5.4.10',
    ); // organizationName OID

    return X509CertInfo(
      subjectCN: subjectCN.isNotEmpty ? subjectCN : 'Bilinmeyen',
      issuerCN: issuerCN.isNotEmpty ? issuerCN : 'Bilinmeyen',
      serialNumber: serialNumberHex,
      notBefore: notBefore,
      notAfter: notAfter,
      subjectSerialNumber: subjectSerialNumber,
      organizationName: orgName,
      issuerDer: issuerDer,
      serialNumberDer: serialNumberDer,
    );
  } catch (e) {
    return null;
  }
}

// ─── Yardımcılar ──────────────────────────────────────────────────────

/// X.500 Name yapısından CommonName (OID 2.5.4.3) çıkar.
String _extractCN(ASN1Sequence nameSeq) {
  return _extractAttribute(nameSeq, '2.5.4.3') ?? '';
}

/// X.500 Name yapısından belirli OID'li attribute değerini çıkar.
///
/// Name ::= SEQUENCE OF RelativeDistinguishedName
/// RDN ::= SET OF AttributeTypeAndValue
/// AttributeTypeAndValue ::= SEQUENCE { type OID, value ANY }
String? _extractAttribute(ASN1Sequence nameSeq, String oidStr) {
  for (final rdn in nameSeq.elements) {
    if (rdn is! ASN1Set) continue;
    for (final atv in rdn.elements) {
      if (atv is! ASN1Sequence) continue;
      final oid = atv.elements[0];
      if (oid is ASN1ObjectIdentifier) {
        if (oid.identifier == oidStr) {
          final value = atv.elements[1];
          if (value is ASN1UTF8String) return value.utf8StringValue;
          if (value is ASN1PrintableString) return value.stringValue;
          // IA5String, BMPString vb. için ham bytes
          if (value.encodedBytes.length > 2) {
            return String.fromCharCodes(value.valueBytes());
          }
        }
      }
    }
  }
  return null;
}

/// UTCTime veya GeneralizedTime'ı DateTime'a çevir.
DateTime _parseTime(ASN1Object timeObj) {
  if (timeObj is ASN1UtcTime) {
    return timeObj.dateTimeValue;
  }
  if (timeObj is ASN1GeneralizedTime) {
    return timeObj.dateTimeValue;
  }
  // Fallback: tag'e göre parse et
  final bytes = timeObj.valueBytes();
  if (bytes.isEmpty) return DateTime.now();
  final str = String.fromCharCodes(bytes);
  return _parseTimeString(str, timeObj.tag == 0x17); // 0x17 = UTCTime
}

DateTime _parseTimeString(String s, bool isUtcTime) {
  try {
    if (isUtcTime) {
      // YYMMDDHHmmSSZ format
      final year = int.parse(s.substring(0, 2));
      final fullYear = year >= 50 ? 1900 + year : 2000 + year;
      return DateTime.utc(
        fullYear,
        int.parse(s.substring(2, 4)),
        int.parse(s.substring(4, 6)),
        int.parse(s.substring(6, 8)),
        int.parse(s.substring(8, 10)),
        s.length > 10 ? int.parse(s.substring(10, 12)) : 0,
      );
    } else {
      // YYYYMMDDHHmmSSZ format
      return DateTime.utc(
        int.parse(s.substring(0, 4)),
        int.parse(s.substring(4, 6)),
        int.parse(s.substring(6, 8)),
        int.parse(s.substring(8, 10)),
        int.parse(s.substring(10, 12)),
        s.length > 12 ? int.parse(s.substring(12, 14)) : 0,
      );
    }
  } catch (_) {
    return DateTime.now();
  }
}
